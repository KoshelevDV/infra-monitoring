# Vault Terraform Configuration

Terraform IaC replacement for the `vault_configure` Ansible role.
Manages Vault policies, auth methods (AppRole, Userpass), and KV v2 secret engines.

---

## Why Terraform instead of Ansible?

The original Ansible role used the `uri` module to call the Vault HTTP API directly — a fragile anti-pattern:
- No state tracking (idempotency by convention, not enforcement)
- No plan/preview step
- Error handling is manual (`status_code: [200, 204, 400]`)

Terraform with the `hashicorp/vault` provider gives you:
- Declarative state with `terraform plan`
- Proper idempotency via state file
- Structured modules reusable across environments

---

## Structure

```
terraform/vault/
├── main.tf                  # Provider + module calls
├── variables.tf             # All input variables
├── outputs.tf               # Role IDs and KV paths
├── versions.tf              # Provider version constraints
├── terraform.tfvars.example # Example configuration
└── modules/
    ├── vault_policy/        # ACL policy management
    ├── auth_approle/        # AppRole auth method + roles
    ├── auth_userpass/       # Userpass auth method + users
    └── secret_engine_kv/   # KV v2 secret engines
```

---

## Usage

### 1. Copy example vars

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
```

### 2. Init

```bash
terraform init
```

### 3. Plan

```bash
terraform plan -var-file=terraform.tfvars
```

### 4. Apply

```bash
terraform apply -var-file=terraform.tfvars
```

---

## Variables

| Variable            | Type         | Default                      | Description                                 |
|---------------------|--------------|------------------------------|---------------------------------------------|
| `vault_address`     | `string`     | `https://127.0.0.1:8200`    | Vault server URL                            |
| `vault_token`       | `string`     | —                            | Root/admin token (sensitive)                |
| `vault_ca_cert_file`| `string`     | `""`                         | Path to CA cert; empty = skip TLS verify    |
| `policies`          | `list(object)`| `[]`                        | ACL policies to create                      |
| `approle_roles`     | `list(object)`| `[]`                        | AppRole roles to create                     |
| `userpass_users`    | `list(object)`| `[]`                        | Userpass users (sensitive)                  |
| `kv_engines`        | `list(object)`| `[]`                        | KV v2 engines to mount                      |

### policies object

```hcl
{
  name  = "mypolicy"
  rules = [
    { path = "secret/*", capabilities = ["read", "list"] }
  ]
}
```

### approle_roles object

```hcl
{
  role_name      = "my-role"
  token_policies = ["mypolicy"]
  token_ttl      = 3600      # seconds
  token_max_ttl  = 86400     # seconds
  secret_id_ttl  = 86400     # seconds; 0 = no expiry
}
```

### userpass_users object

```hcl
{
  username = "devops"
  password = "secret"
  policies = ["admin"]
}
```

### kv_engines object

```hcl
{
  path         = "secret"
  description  = "Main KV store"
  max_versions = 10
}
```

---

## Outputs

| Output              | Description                           |
|---------------------|---------------------------------------|
| `approle_role_ids`  | Map of `role_name => role_id`         |
| `kv_engine_paths`   | List of mounted KV engine paths       |

---

## Notes

- `vault_token` is used only for bootstrapping. After initial setup, switch to a scoped token or use Vault Agent.
- `skip_tls_verify` is automatically `true` when `vault_ca_cert_file` is empty. Always provide the CA cert in production.
- AppRole and Userpass modules mount the auth backends at fixed paths (`approle`, `userpass`). If you need multiple mounts, extend the module with a `path` variable.

---

## Ansible → Terraform mapping

| Ansible task                        | Terraform resource                          |
|-------------------------------------|---------------------------------------------|
| Enable KV engine (URI POST)         | `vault_mount` + `vault_kv_secret_backend_v2`|
| Create policy (URI POST)            | `vault_policy`                              |
| Enable AppRole auth (URI POST)      | `vault_auth_backend` (type=approle)         |
| Create AppRole (URI POST)           | `vault_approle_auth_backend_role`           |
| Enable Userpass auth (URI POST)     | `vault_auth_backend` (type=userpass)        |
| Create userpass user (URI POST)     | `vault_generic_endpoint`                    |

---

## Использование (RU)

Эта конфигурация заменяет Ansible-роль `vault_configure`, которая использовала модуль `uri` для прямых вызовов Vault HTTP API.

**Порядок работы:**

```bash
cp terraform.tfvars.example terraform.tfvars
# Заполни terraform.tfvars своими значениями

terraform init
terraform plan -var-file=terraform.tfvars   # проверить что будет создано
terraform apply -var-file=terraform.tfvars  # применить
```

**Что создаётся:**
- Политики доступа (ACL policies)
- Auth-метод AppRole + роли
- Auth-метод Userpass + пользователи
- KV v2 секретные хранилища

**Важно:** `vault_token` — это root/bootstrap токен только для первоначальной настройки.
В проде используй scoped токен с минимальными правами или Vault Agent.
