output "role_id" {
  description = "AppRole role ID"
  value       = vault_approle_auth_backend_role.this.role_id
}
