# 🔭 infra-monitoring

Production monitoring stack for heterogeneous infrastructure: VMs, PostgreSQL, MySQL, MSSQL, Kafka, Debezium, Docker, Kubernetes.

**Key feature:** Debezium / PostgreSQL WAL accumulation detection — catches stuck connectors before they fill your disk.

---

## Stack

| Component | Role |
|-----------|------|
| **VictoriaMetrics** | Metrics storage (Prometheus-compatible, ~5x more efficient) |
| **Grafana** | Visualization |
| **Alertmanager** | Alert routing → Telegram |
| **kafka-connect-exporter** | Custom Rust exporter: Kafka Connect connector/task status |
| **node_exporter** | Linux VM metrics (deployed via Ansible) |
| **postgres_exporter** | PostgreSQL metrics + replication slot lag |
| **mysqld_exporter** | MySQL metrics |
| **sql_exporter** | MSSQL metrics |
| **kafka_exporter** | Kafka broker + consumer group metrics |
| **jmx_exporter** | JVM / Debezium metrics |
| **kube-state-metrics** | Kubernetes object metrics |

---

## Quick Start

```bash
git clone https://github.com/KoshelevDV/infra-monitoring
cd infra-monitoring
cp .env.example .env
# Edit .env — set GRAFANA_PASSWORD, KAFKA_CONNECT_URLS
docker compose up -d
```

- Grafana: **http://localhost:3000** (admin / changeme)
- VictoriaMetrics: **http://localhost:8428**
- Alertmanager: **http://localhost:9093**

---

## Docker Compose

```bash
# Start
docker compose up -d

# Logs
docker compose logs -f victoria-metrics
docker compose logs -f kafka-connect-exporter

# Stop
docker compose down
```

### Environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `GRAFANA_USER` | `admin` | Grafana admin username |
| `GRAFANA_PASSWORD` | `changeme` | Grafana admin password |
| `KAFKA_CONNECT_URLS` | `http://kafka-connect:8083` | Comma-separated Kafka Connect URLs |

---

## Helm (Kubernetes)

Chart lives in `helm/infra-monitoring/` — not published to any registry.

```bash
# Install
helm install monitoring ./helm/infra-monitoring \
  --namespace monitoring --create-namespace \
  --set alertmanager.telegram.botToken=YOUR_BOT_TOKEN \
  --set alertmanager.telegram.chatId=YOUR_CHAT_ID

# Upgrade
helm upgrade monitoring ./helm/infra-monitoring

# With custom values file
helm install monitoring ./helm/infra-monitoring -f my-values.yaml
```

### Enable Grafana ingress

```bash
helm install monitoring ./helm/infra-monitoring \
  --set grafana.ingress.enabled=true \
  --set grafana.ingress.host=grafana.example.com \
  --set grafana.ingress.className=nginx
```

---

## Alert Rules

| File | Coverage |
|------|----------|
| `alerts/infrastructure.yml` | Host down, disk, memory, CPU, systemd |
| `alerts/databases.yml` | PostgreSQL, MySQL, MSSQL — connections, replication, deadlocks |
| `alerts/kafka-debezium.yml` | Kafka brokers, Connect connector/task status, **WAL accumulation** |
| `alerts/kubernetes.yml` | Nodes, pods (crashloop/OOM), deployments, PVC |

### Alert severity levels

| Icon | Severity | Behaviour |
|------|----------|-----------|
| 🔴 | `critical` | Notify immediately, repeat every 1h |
| ⚠️ | `warning` | Notify after 5–10m, repeat every 4h |
| — | `none` | Watchdog only |

### Anti-noise measures

- All alerts have `for: Xm` — no spike-triggered noise
- **Inhibition rules**: if host is down → suppress all service alerts on that host
- Debezium WAL alerts grouped separately with 5s `group_wait` — they're urgent

---

## Debezium / WAL Monitoring

The core problem: PostgreSQL **logical replication slots** hold WAL until the consumer (Debezium) advances. If a connector fails/stalls, WAL accumulates and can fill the disk.

### What we monitor

```
postgres_exporter (custom query on pg_replication_slots):
  pg_replication_slots_pg_wal_lsn_diff   — lag in bytes per slot
  pg_replication_slots_active            — 0/1 whether slot is active

kafka-connect-exporter:
  kafka_connect_connector_state{state="failed"}     — connector FAILED
  kafka_connect_connector_task_state{state="failed"} — task FAILED
  kafka_connect_connectors_failed                    — total failed count
```

### Alert thresholds

| Alert | Threshold | Severity |
|-------|-----------|----------|
| `DebeziumSlotInactiveWithLag` | > 100MB + inactive | 🔴 critical |
| `DebeziumWALLagWarning` | > 1 GB | ⚠️ warning |
| `DebeziumWALLagCritical` | > 5 GB | 🔴 critical |
| `DebeziumWALLagGrowing` | +512MB in 15m + inactive | 🔴 critical |
| `KafkaConnectorFailed` | state=failed for 1m | 🔴 critical |
| `KafkaConnectorTaskFailed` | task state=failed for 2m | 🔴 critical |

### Required postgres_exporter custom queries

Add to your `postgres_exporter` configuration (`queries.yaml`):

```yaml
pg_replication_slots:
  query: |
    SELECT slot_name,
           active::int AS active,
           pg_wal_lsn_diff(pg_current_wal_lsn(), confirmed_flush_lsn) AS pg_wal_lsn_diff
    FROM pg_replication_slots
    WHERE slot_type = 'logical'
  metrics:
    - slot_name:
        usage: LABEL
    - active:
        usage: GAUGE
        description: "1 if replication slot is active"
    - pg_wal_lsn_diff:
        usage: GAUGE
        description: "Bytes of WAL behind current position"
```

---

## Ansible — Exporter Deployment

Exporters are deployed to target infrastructure via Ansible.
See [`ansible/README.md`](ansible/README.md) for details.

```bash
# Deploy all exporters
ansible-playbook -i ansible/inventories/production \
  ansible/playbooks/deploy-exporters.yml
```

**Terraform** integration is planned — see `terraform/` directory when added.

---

## Adding a new scrape target

Edit `victoria-metrics/scrape.yml`, add the target to the relevant `job_name`, then restart:

```bash
docker compose restart victoria-metrics
```

VictoriaMetrics hot-reloads scrape config every 30s (`--promscrape.configCheckInterval=30s`), so restart is often not needed.

---

## Project Structure

```
infra-monitoring/
├── docker-compose.yml
├── .env.example
├── victoria-metrics/
│   └── scrape.yml                    — scrape config for all jobs
├── alerts/
│   ├── infrastructure.yml            — hosts, disk, memory, CPU
│   ├── databases.yml                 — PG, MySQL, MSSQL
│   ├── kafka-debezium.yml            — Kafka, Debezium, WAL lag ← key file
│   └── kubernetes.yml                — K8s nodes, pods, deployments
├── alertmanager/
│   └── alertmanager.yml              — Telegram routing + inhibition rules
├── grafana/
│   ├── provisioning/                 — auto-provisioned datasources + dashboards
│   └── dashboards/                   — dashboard JSON files
├── exporters/
│   └── kafka-connect/                — custom Rust Prometheus exporter
│       ├── src/main.rs
│       ├── Cargo.toml
│       └── Dockerfile
├── ansible/
│   ├── inventories/production/       — hosts inventory
│   ├── playbooks/                    — deploy-exporters.yml and per-role playbooks
│   └── roles/                        — node-exporter, postgres-exporter, etc.
├── helm/
│   └── infra-monitoring/             — Helm chart (not published to registry)
└── README.md
```

---

## License

MIT

---
---

# 🔭 infra-monitoring (Русский)

Стек мониторинга для гетерогенной инфраструктуры: ВМ на Ubuntu, PostgreSQL, MySQL, MSSQL, Kafka, Debezium, Docker, Kubernetes.

**Ключевая фича:** детектирование накопления WAL в PostgreSQL из-за зависших Debezium-коннекторов — ловит проблему до того как диск заполнится.

---

## Быстрый старт

```bash
git clone https://github.com/KoshelevDV/infra-monitoring
cd infra-monitoring
cp .env.example .env
# Отредактировать .env — задать GRAFANA_PASSWORD, KAFKA_CONNECT_URLS
docker compose up -d
```

- Grafana: **http://localhost:3000**
- VictoriaMetrics: **http://localhost:8428**
- Alertmanager: **http://localhost:9093**

---

## Docker Compose

```bash
docker compose up -d          # запустить
docker compose logs -f        # логи
docker compose down           # остановить
```

---

## Helm

Чарт в `helm/infra-monitoring/` — в реестры не публикуется.

```bash
helm install monitoring ./helm/infra-monitoring \
  --namespace monitoring --create-namespace \
  --set alertmanager.telegram.botToken=TOKEN \
  --set alertmanager.telegram.chatId=CHAT_ID
```

---

## Debezium / WAL

Проблема: PostgreSQL не может очищать WAL пока logical replication slot не продвинулся. Коннектор завис — WAL растёт — диск заканчивается.

Решение: `postgres_exporter` с кастомным запросом к `pg_replication_slots` + `kafka-connect-exporter` поллит статусы коннекторов.

Алерты (см. `alerts/kafka-debezium.yml`):
- `DebeziumSlotInactiveWithLag` — слот неактивен + >100MB lag → 🔴 critical
- `DebeziumWALLagCritical` — >5GB lag → 🔴 critical
- `KafkaConnectorFailed` — коннектор FAILED → 🔴 critical

---

## Ansible

Экспортеры деплоятся на целевую инфраструктуру через Ansible.

```bash
ansible-playbook -i ansible/inventories/production \
  ansible/playbooks/deploy-exporters.yml
```

**Terraform** — запланирован, будет добавлен позже.

---

## Лицензия

MIT
