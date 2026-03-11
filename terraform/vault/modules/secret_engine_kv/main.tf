resource "vault_mount" "kv" {
  type        = "kv"
  path        = var.path
  description = var.description
  options     = { version = "2" }
}

resource "vault_kv_secret_backend_v2" "config" {
  mount        = vault_mount.kv.path
  max_versions = var.max_versions
}
