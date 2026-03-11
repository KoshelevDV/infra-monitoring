output "approle_role_ids" {
  description = "AppRole role IDs (map: role_name => role_id)"
  value = {
    for k, v in module.approle : k => v.role_id
  }
}

output "kv_engine_paths" {
  description = "Mounted KV engine paths"
  value       = [for k, v in module.kv_engines : v.path]
}
