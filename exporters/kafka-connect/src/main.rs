/*!
 * kafka-connect-exporter
 *
 * Polls Kafka Connect REST API and exposes connector/task status
 * as Prometheus metrics.
 *
 * Metrics exposed:
 *   kafka_connect_connector_state{connector,state,instance}       1 if in that state
 *   kafka_connect_connector_task_state{connector,task,state,instance} 1 if in that state
 *   kafka_connect_up{instance}                                     1 if reachable
 *   kafka_connect_connectors_total{instance}                       total connectors
 *   kafka_connect_connectors_running{instance}                     running connectors
 *   kafka_connect_connectors_failed{instance}                      failed connectors
 */

use axum::{routing::get, Router};
use serde::Deserialize;
use std::{
    collections::HashMap,
    sync::{Arc, RwLock},
    time::Duration,
};
use tracing::{info, warn};

// ── Config ────────────────────────────────────────────────────────────────────

struct Config {
    connect_urls: Vec<String>,
    bind_addr: String,
    scrape_interval: Duration,
}

impl Config {
    fn from_env() -> Self {
        let urls = std::env::var("KAFKA_CONNECT_URLS")
            .unwrap_or_else(|_| "http://localhost:8083".into());
        let connect_urls = urls
            .split(',')
            .map(|u| u.trim().trim_end_matches('/').to_owned())
            .filter(|u| !u.is_empty())
            .collect();

        Self {
            connect_urls,
            bind_addr: std::env::var("BIND_ADDR")
                .unwrap_or_else(|_| "0.0.0.0:9407".into()),
            scrape_interval: Duration::from_secs(
                std::env::var("SCRAPE_INTERVAL_SECS")
                    .ok()
                    .and_then(|s| s.parse().ok())
                    .unwrap_or(30),
            ),
        }
    }
}

// ── Kafka Connect API types ───────────────────────────────────────────────────

#[derive(Deserialize, Debug)]
struct ConnectorStatus {
    connector: ConnectorInfo,
    tasks: Vec<TaskInfo>,
}

#[derive(Deserialize, Debug)]
struct ConnectorInfo {
    state: String,
}

#[derive(Deserialize, Debug)]
struct TaskInfo {
    id: u32,
    state: String,
}

// ── Metrics cache ─────────────────────────────────────────────────────────────

type MetricsCache = Arc<RwLock<String>>;

// ── Scraper ───────────────────────────────────────────────────────────────────

async fn scrape_connect(client: &reqwest::Client, base_url: &str) -> String {
    let instance = base_url
        .trim_start_matches("http://")
        .trim_start_matches("https://");

    // Fetch connector list
    let connector_names: Vec<String> = match client
        .get(format!("{}/connectors?expand=status", base_url))
        .send()
        .await
    {
        Ok(r) => {
            match r.json::<HashMap<String, serde_json::Value>>().await {
                Ok(map) => map.into_keys().collect(),
                Err(e) => {
                    warn!("Failed to parse connectors from {}: {}", base_url, e);
                    return format!(
                        "kafka_connect_up{{instance=\"{instance}\"}} 0\n"
                    );
                }
            }
        }
        Err(e) => {
            warn!("Cannot reach Kafka Connect at {}: {}", base_url, e);
            return format!("kafka_connect_up{{instance=\"{instance}\"}} 0\n");
        }
    };

    let total = connector_names.len();
    let mut running = 0usize;
    let mut failed = 0usize;
    let mut lines = Vec::new();

    // Fetch status for each connector
    for name in &connector_names {
        let url = format!("{}/connectors/{}/status", base_url, name);
        let status: ConnectorStatus = match client.get(&url).send().await {
            Ok(r) => match r.json().await {
                Ok(s) => s,
                Err(e) => {
                    warn!("Failed to parse status for {}: {}", name, e);
                    continue;
                }
            },
            Err(e) => {
                warn!("Failed to fetch status for {}: {}", name, e);
                continue;
            }
        };

        let c_state = status.connector.state.to_lowercase();
        if c_state == "running" { running += 1; }
        if c_state == "failed"  { failed  += 1; }

        // Emit state metrics as separate time series (one per state)
        for state in &["running", "failed", "paused", "unassigned"] {
            lines.push(format!(
                "kafka_connect_connector_state{{connector=\"{name}\",state=\"{state}\",instance=\"{instance}\"}} {}",
                if c_state == *state { 1 } else { 0 }
            ));
        }

        // Task-level metrics
        for task in &status.tasks {
            let t_state = task.state.to_lowercase();
            for state in &["running", "failed", "paused", "unassigned"] {
                lines.push(format!(
                    "kafka_connect_connector_task_state{{connector=\"{name}\",task=\"{}\",state=\"{state}\",instance=\"{instance}\"}} {}",
                    task.id,
                    if t_state == *state { 1 } else { 0 }
                ));
            }
        }
    }

    // Summary metrics
    lines.push(format!("kafka_connect_up{{instance=\"{instance}\"}} 1"));
    lines.push(format!("kafka_connect_connectors_total{{instance=\"{instance}\"}} {total}"));
    lines.push(format!("kafka_connect_connectors_running{{instance=\"{instance}\"}} {running}"));
    lines.push(format!("kafka_connect_connectors_failed{{instance=\"{instance}\"}} {failed}"));

    lines.join("\n")
}

async fn scrape_all(client: reqwest::Client, urls: Vec<String>) -> String {
    let mut all = Vec::new();
    for url in &urls {
        all.push(scrape_connect(&client, url).await);
    }
    all.join("\n")
}

// ── Background scrape loop ────────────────────────────────────────────────────

async fn scrape_loop(
    client: reqwest::Client,
    urls: Vec<String>,
    interval: Duration,
    cache: MetricsCache,
) {
    loop {
        let metrics = scrape_all(client.clone(), urls.clone()).await;
        *cache.write().unwrap() = metrics;
        tokio::time::sleep(interval).await;
    }
}

// ── HTTP handlers ─────────────────────────────────────────────────────────────

async fn metrics_handler(
    axum::extract::State(cache): axum::extract::State<MetricsCache>,
) -> String {
    cache.read().unwrap().clone()
}

async fn health_handler() -> &'static str { "ok" }

// ── Main ──────────────────────────────────────────────────────────────────────

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::from_default_env()
                .add_directive("kafka_connect_exporter=info".parse().unwrap()),
        )
        .init();

    let config = Config::from_env();
    let client = reqwest::Client::builder()
        .timeout(Duration::from_secs(10))
        .build()
        .expect("Failed to build HTTP client");

    let cache: MetricsCache = Arc::new(RwLock::new(String::new()));

    // Initial scrape before starting server
    {
        let metrics = scrape_all(client.clone(), config.connect_urls.clone()).await;
        *cache.write().unwrap() = metrics;
    }

    // Background scrape loop
    tokio::spawn(scrape_loop(
        client,
        config.connect_urls.clone(),
        config.scrape_interval,
        cache.clone(),
    ));

    let app = Router::new()
        .route("/metrics", get(metrics_handler))
        .route("/health", get(health_handler))
        .with_state(cache);

    info!(
        "kafka-connect-exporter listening on http://{} scraping: {:?}",
        config.bind_addr, config.connect_urls
    );

    let listener = tokio::net::TcpListener::bind(&config.bind_addr)
        .await
        .unwrap_or_else(|e| panic!("Failed to bind {}: {}", config.bind_addr, e));

    axum::serve(listener, app).await.unwrap();
}
