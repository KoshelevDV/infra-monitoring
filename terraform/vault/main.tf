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

module "kv_engines" {
  source   = "./modules/secret_engine_kv"
  for_each = { for e in var.kv_engines : e.path => e }

  path         = each.value.path
  description  = each.value.description
  max_versions = each.value.max_versions
}
