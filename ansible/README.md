# Ansible — Exporter Deployment

This directory contains Ansible playbooks for deploying Prometheus exporters
to the monitored infrastructure.

## Structure

```
ansible/
├── inventories/
│   └── production/
│       ├── hosts.yml          — inventory: VMs, DB hosts, Kafka brokers
│       └── group_vars/
│           ├── all.yml        — shared vars
│           ├── postgresql.yml — postgres_exporter config
│           ├── mysql.yml
│           ├── mssql.yml
│           └── kafka.yml
├── roles/
│   ├── node-exporter/         — node_exporter on all VMs
│   ├── postgres-exporter/     — postgres_exporter on PG hosts
│   ├── mysql-exporter/        — mysqld_exporter
│   ├── mssql-exporter/        — sql_exporter
│   ├── kafka-exporter/        — kafka_exporter on Kafka brokers
│   └── jmx-exporter/         — jmx_exporter java agent on JVM apps
└── playbooks/
    ├── deploy-exporters.yml   — deploy all exporters
    ├── node-exporter.yml
    ├── db-exporters.yml
    └── kafka-exporters.yml
```

## Usage

```bash
# Deploy all exporters
ansible-playbook -i inventories/production playbooks/deploy-exporters.yml

# Deploy only node exporters
ansible-playbook -i inventories/production playbooks/node-exporter.yml

# Dry run
ansible-playbook -i inventories/production playbooks/deploy-exporters.yml --check
```

## Adding a new host

Edit `inventories/production/hosts.yml` and re-run the relevant playbook.
