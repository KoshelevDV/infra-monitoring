resource "vault_auth_backend" "approle" {
  type = "approle"
  path = "approle"
}

resource "vault_approle_auth_backend_role" "this" {
  backend        = vault_auth_backend.approle.path
  role_name      = var.role_name
  token_policies = var.token_policies
  token_ttl      = var.token_ttl
  token_max_ttl  = var.token_max_ttl
  secret_id_ttl  = var.secret_id_ttl != 0 ? var.secret_id_ttl : null
}
