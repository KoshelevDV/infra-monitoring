provider "vault" {
  address         = var.vault_address
  token           = var.vault_token
  ca_cert_file    = var.vault_ca_cert_file != "" ? var.vault_ca_cert_file : null
  skip_tls_verify = var.vault_ca_cert_file == ""
}

module "policies" {
  source   = "./modules/vault_policy"
  for_each = { for p in var.policies : p.name => p }

  name  = each.value.name
  rules = each.value.rules
}

module "default_policy" {
  source      = "./modules/vault_default_policy"
  for_each    = var.default_policy != null ? { "default" = var.default_policy } : {}
  extra_rules = each.value.extra_rules
}

module "approle" {
  source   = "./modules/auth_approle"
  for_each = { for r in var.approle_roles : r.role_name => r }

  role_name      = each.value.role_name
  token_policies = each.value.token_policies
  token_ttl      = each.value.token_ttl
  token_max_ttl  = each.value.token_max_ttl
  secret_id_ttl  = each.value.secret_id_ttl

  depends_on = [module.policies]
}

module "userpass" {
  source   = "./modules/auth_userpass"
  for_each = { for u in var.userpass_users : u.username => u }

  username = each.value.username
  password = each.value.password
  policies = each.value.policies

  depends_on = [module.policies]
}

module "jwt" {
  source   = "./modules/auth_jwt"
  for_each = { for r in var.jwt_roles : r.role_name => r }

  jwks_url       = each.value.jwks_url
  role_name      = each.value.role_name
  token_policies = each.value.token_policies
  token_ttl      = each.value.token_ttl
  token_max_ttl  = each.value.token_max_ttl
  bound_issuer   = each.value.bound_issuer
  bound_claims   = each.value.bound_claims

  depends_on = [module.policies]
}

module "kv_engines" {
  source   = "./modules/secret_engine_kv"
  for_each = { for e in var.kv_engines : e.path => e }

  path         = each.value.path
  description  = each.value.description
  max_versions = each.value.max_versions
}

module "transit" {
  source   = "./modules/secret_engine_transit"
  for_each = { for t in var.transit_engines : t.name => t }

  name        = each.value.name
  path        = lookup(each.value, "path", "transit")
  policy_name = each.value.policy_name

  depends_on = [module.policies]
}

module "audit" {
  source = "./modules/system_audit"
  count  = var.audit_config != null ? 1 : 0

  enable_file   = lookup(var.audit_config, "enable_file", true)
  file_path     = lookup(var.audit_config, "file_path", "/var/log/vault/audit.log")
  enable_syslog = lookup(var.audit_config, "enable_syslog", false)
}

module "password_policies" {
  source   = "./modules/system_password_policy"
  for_each = { for p in var.password_policies : p.name => p }

  name  = each.value.name
  rules = each.value.rules
}
