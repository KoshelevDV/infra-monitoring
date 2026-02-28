# Ansible — Exporter Deployment

Deploys Prometheus exporters to monitored infrastructure (Ubuntu 22.04).

## Roles

| Role | Exporter | Port | Notes |
|------|----------|------|-------|
| `node-exporter` | node_exporter v1.8.2 | 9100 | All VMs |
| `postgres-exporter` | postgres_exporter v0.15.0 | 9187 | Includes **custom queries** for replication slots (Debezium WAL) |
| `mysql-exporter` | mysqld_exporter v0.15.1 | 9104 | Creates `.my.cnf` credentials |
| `mssql-exporter` | sql_exporter v0.14.3 | 9399 | YAML query config |
| `kafka-exporter` | kafka_exporter v1.7.0 | 9308 | SASL/TLS optional |
| `jmx-exporter` | jmx_prometheus_javaagent v1.0.1 | 5556 | Java agent JAR, JVM + Debezium metrics |

## Prerequisites

```bash
# Install required Ansible collections
ansible-galaxy collection install community.general community.mysql
```

## Configuration

### 1. Fill in your hosts

Edit `inventories/production/hosts.yml` — uncomment and fill in your IPs:

```yaml
postgresql:
  hosts:
    pg-primary:
      ansible_host: 10.0.1.10
      postgres_exporter_dsn: "postgresql://exporter:secret@localhost/postgres?sslmode=disable"
```

### 2. Set per-group variables

`inventories/production/group_vars/postgresql.yml` — PostgreSQL settings
`inventories/production/group_vars/mysql.yml` — MySQL settings

## Usage

```bash
# Deploy everything
ansible-playbook -i inventories/production playbooks/deploy-exporters.yml

# Only node exporters (all hosts)
ansible-playbook -i inventories/production playbooks/node-exporter.yml

# Database exporters only
ansible-playbook -i inventories/production playbooks/db-exporters.yml

# Kafka + JVM exporters
ansible-playbook -i inventories/production playbooks/kafka-exporters.yml

# Dry run (check mode)
ansible-playbook -i inventories/production playbooks/deploy-exporters.yml --check --diff

# Only specific hosts
ansible-playbook -i inventories/production playbooks/db-exporters.yml \
  --limit pg-primary

# Check connectivity first
ansible -i inventories/production all -m ping
```

## PostgreSQL — create exporter user manually

```sql
CREATE USER exporter WITH PASSWORD 'your-password';
GRANT pg_monitor TO exporter;
GRANT CONNECT ON DATABASE postgres TO exporter;
```

## MySQL — create exporter user manually

```sql
CREATE USER 'exporter'@'localhost' IDENTIFIED BY 'your-password';
GRANT PROCESS, REPLICATION CLIENT, SELECT ON *.* TO 'exporter'@'localhost';
FLUSH PRIVILEGES;
```

## JVM — add agent to application startup

After deploying jmx-exporter, add this to your application's JVM args:

```
-javaagent:/opt/jmx-exporter/jmx_prometheus_javaagent.jar=5556:/opt/jmx-exporter/config.yml
```

For systemd services, add to `Environment=` or `EnvironmentFile=`:
```
JAVA_OPTS=-javaagent:/opt/jmx-exporter/jmx_prometheus_javaagent.jar=5556:/opt/jmx-exporter/config.yml
```

## After deploying exporters

Add the new hosts to `victoria-metrics/scrape.yml` and reload:

```bash
docker compose restart victoria-metrics
# or if using hot-reload (30s interval):
# just wait, it picks up changes automatically
```

---

## HashiCorp Vault

Роли для деплоя, инициализации и конфигурации HashiCorp Vault.

### Роли

| Роль | Назначение |
|------|-----------|
| `vault` | Single-node Vault (file storage, systemd, TLS опционально) |
| `vault_ha` | HA Vault кластер на Raft (3+ нод) |
| `vault_unseal` | Init + unseal (сохраняет ключи на control node) |
| `vault_configure` | Policies, auth methods (K8s, AppRole, JWT, Userpass), secret engines (KV, DB, PKI) |

### Быстрый старт — single node

```bash
# 1. Добавить хост в hosts.yml → vault_single

# 2. Установить Vault
ansible-playbook playbooks/vault-single.yml -i inventories/production/hosts.yml -l vault_single

# 3. Инициализировать и unseal
ansible-playbook playbooks/vault-init.yml -i inventories/production/hosts.yml -l vault_single
# Ключи сохраняются в playbooks/vault-keys/ — держи в секрете!

# 4. Базовая конфигурация (KV, userpass admin)
ansible-playbook playbooks/vault-configure.yml -i inventories/production/hosts.yml \
  -l vault_single --extra-vars "vault_root_token=s.XXXX"
```

### Быстрый старт — HA (Raft, 3 ноды)

```bash
# 1. Добавить 3 хоста в hosts.yml → vault_ha
# 2. Задать vault_raft_peers в group_vars/vault_ha.yml

# 3. Установить на все ноды
ansible-playbook playbooks/vault-ha.yml -i inventories/production/hosts.yml -l vault_ha

# 4. Init + unseal первой ноды, потом остальных
ansible-playbook playbooks/vault-init.yml -i inventories/production/hosts.yml -l vault_ha[0]
ansible-playbook playbooks/vault-init.yml -i inventories/production/hosts.yml -l vault_ha
```

### Unseal опции

По умолчанию ключи читаются из `playbooks/vault-keys/<hostname>-vault-keys.json`.
В продакшене замени на AWS KMS/GCP KMS через `vault_ha` конфиг (`seal "awskms" {}`).

### ⚠️ Безопасность

- `playbooks/vault-keys/` добавлен в `.gitignore` — **никогда не коммить unseal keys**
- Root token использовать только при начальной конфигурации
- Для пользователей — `no_log: true` везде где пароли
