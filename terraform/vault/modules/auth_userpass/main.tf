resource "vault_auth_backend" "userpass" {
  type = "userpass"
  path = "userpass"
}

resource "vault_generic_endpoint" "user" {
  path                 = "auth/userpass/users/${var.username}"
  ignore_absent_fields = true
  data_json = jsonencode({
    password = var.password
    policies = join(",", var.policies)
  })
}
