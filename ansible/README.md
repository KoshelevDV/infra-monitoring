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

---

## Apache Kafka (KRaft)

Роли для деплоя Kafka без ZooKeeper (KRaft mode, Kafka 3.x+).

### Роли

| Роль | Назначение |
|------|-----------|
| `kafka` | Single-node Kafka (KRaft combined: broker+controller) |
| `kafka_ha` | HA кластер (3+ нод, KRaft, RF=3, min_isr=2) |

### Режимы безопасности

| `kafka_security_protocol` | `kafka_sasl_mechanism` | Что получаем |
|--------------------------|----------------------|--------------|
| `PLAINTEXT` | — | Без аутентификации, без TLS |
| `SASL_PLAINTEXT` | `PLAIN` | Логин+пароль в JAAS (статически) |
| `SASL_PLAINTEXT` | `SCRAM-SHA-512` | Логин+пароль через SCRAM (динамически) |
| `SASL_SSL` | `SCRAM-SHA-512` | Логин+пароль + TLS сертификат |

### Быстрый старт — single node

```bash
# Без auth
ansible-playbook playbooks/kafka-single.yml -i inventories/production/hosts.yml -l kafka_single

# SASL/SCRAM (рекомендуется для prod)
ansible-playbook playbooks/kafka-single.yml -i inventories/production/hosts.yml -l kafka_single \
  -e kafka_security_protocol=SASL_PLAINTEXT \
  -e kafka_sasl_mechanism=SCRAM-SHA-512 \
  -e kafka_broker_password=BrokerPass123 \
  -e 'kafka_users=[{"username":"producer","password":"Prod123"},{"username":"consumer","password":"Cons123"}]'

# SASL + TLS
ansible-playbook playbooks/kafka-single.yml -i inventories/production/hosts.yml -l kafka_single \
  -e kafka_security_protocol=SASL_SSL \
  -e kafka_ssl_keystore_src=files/kafka.keystore.jks \
  -e kafka_ssl_keystore_password=keystorepass \
  -e kafka_ssl_truststore_src=files/kafka.truststore.jks \
  -e kafka_ssl_truststore_password=truststorepass
```

### Быстрый старт — HA кластер

```bash
# 1. Сгенерировать cluster_id (один раз):
#    bin/kafka-storage.sh random-uuid  → вставить в group_vars/kafka_ha.yml

# 2. Заполнить group_vars/kafka_ha.yml (cluster_id + quorum_voters)
#    и host_vars/<node>.yml (kafka_node_id: 1/2/3)

# 3. Деплой
ansible-playbook playbooks/kafka-ha.yml -i inventories/production/hosts.yml -l kafka_ha
```

### Пользователи (SCRAM)

При SCRAM-SHA-512 пользователи создаются через `kafka-configs.sh` после старта брокера.
`kafka_users` — список `{username, password}` в group_vars или extra-vars.
Брокерский пользователь (`kafka_broker_username`) создаётся отдельно для inter-broker auth.

### TLS — генерация сертификатов

```bash
# Корневой CA
openssl genrsa -out ca.key 4096
openssl req -new -x509 -days 3650 -key ca.key -out ca.crt -subj "/CN=KafkaCA"

# Keystore для каждой ноды
keytool -genkey -keyalg RSA -alias kafka -keystore kafka.keystore.jks \
  -storepass changeit -keypass changeit -validity 365 \
  -dname "CN=kafka-01, OU=Kafka, O=MyOrg" \
  -ext "SAN=ip:10.0.0.51,dns:kafka-01"

# Подписать сертификат CA и импортировать
# (полная инструкция: kafka.apache.org/documentation/#security_ssl)
```

---

## Server Hardening

Роли для первичной настройки и хардинга VPS/серверов (Ubuntu 22.04+, Ubuntu 24.04).

### Роли

| Роль | Назначение |
|------|-----------|
| `snapd_remove` | Удаляет snapd, очищает директории, блокирует переустановку через `apt-mark hold` |
| `ssh_hardening` | Кастомный порт SSH, key-only auth, запрет root; поддерживает systemd socket activation (Ubuntu 24.04+) |
| `ufw` | Настройка UFW: default deny, SSH открыт всем, полный доступ для доверенных IP |
| `fail2ban` | Защита SSH от брутфорса; backend=systemd для Ubuntu 24.04+; whitelist для доверенных IP |
| `docker` | Установка Docker CE через официальный репозиторий, добавление пользователей в группу docker |
| `uptime_kuma` | Деплой Uptime Kuma в Docker (named volume, unless-stopped) |

### Быстрый старт — хардинг нового сервера

```bash
# 1. Добавить хост в inventories/production/hosts.yml → группа vps
#    Указать ansible_port: 22 (дефолт) перед первым запуском

# 2. Хардинг (snapd + SSH + UFW + fail2ban)
ansible-playbook -i inventories/production playbooks/server-hardening.yml --limit vps-01

# ВАЖНО: после этого SSH переезжает на порт 22022.
# Обновить ansible_port: 22022 в hosts.yml для следующих запусков.

# 3. Docker + Uptime Kuma
ansible-playbook -i inventories/production playbooks/uptime-kuma.yml --limit vps-01

# Dry run перед применением
ansible-playbook -i inventories/production playbooks/server-hardening.yml --check --diff --limit vps-01
```

### Переменные ssh_hardening

| Переменная | По умолчанию | Описание |
|-----------|-------------|----------|
| `ssh_port` | 22022 | SSH порт |
| `ssh_permit_root_login` | no | Запрет root входа |
| `ssh_password_authentication` | no | Только ключи |
| `ssh_max_auth_tries` | 3 | Попыток на соединение |
| `ssh_login_grace_time` | 30 | Секунд на аутентификацию |

### Переменные ufw

| Переменная | По умолчанию | Описание |
|-----------|-------------|----------|
| `ufw_ssh_port` | `{{ ssh_port \| default(22) }}` | SSH порт (берётся из ssh_hardening) |
| `ufw_trusted_ips` | `[]` | Список IP с полным доступом |
| `ufw_extra_rules` | `[]` | Дополнительные правила |

### Переменные fail2ban

| Переменная | По умолчанию | Описание |
|-----------|-------------|----------|
| `fail2ban_ssh_port` | `{{ ssh_port \| default(22) }}` | Порт SSH для jail |
| `fail2ban_maxretry` | 4 | Попыток до бана |
| `fail2ban_findtime` | 300 | Временное окно (сек) |
| `fail2ban_bantime` | 3600 | Время бана (сек) |
| `fail2ban_whitelist_ips` | `[]` | IP которые никогда не банятся |

### ⚠️ Нюансы Ubuntu 24.04 — systemd socket activation

В Ubuntu 24.04 SSH работает через `ssh.socket`. Директива `Port` в `sshd_config` **игнорируется** — порт контролирует сокет.

Роль `ssh_hardening` автоматически определяет наличие `ssh.socket` и создаёт override:
`/etc/systemd/system/ssh.socket.d/override.conf`

Это прозрачно для Ubuntu 22.04 (где socket activation нет).

### ⚠️ Порядок применения

1. Перед первым запуском `server-hardening.yml` — убедиться что в inventory `ansible_port: 22`
2. После прогона — обновить `ansible_port: 22022`
3. Плейбук сам ждёт появления нового порта (`wait_for`) перед завершением

### ⚠️ Docker и UFW

Docker напрямую манипулирует iptables и обходит UFW.  
Опубликованные порты контейнеров (`-p host:container`) доступны снаружи даже если UFW их блокирует.  
Для изоляции биндить контейнер на localhost: `ports: ["127.0.0.1:3001:3001"]`
