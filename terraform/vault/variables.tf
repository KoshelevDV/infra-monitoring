variable "vault_address" {
  description = "Vault server address"
  type        = string
  default     = "https://127.0.0.1:8200"
}

variable "vault_token" {
  description = "Vault root/admin token"
  type        = string
  sensitive   = true
}

variable "vault_ca_cert_file" {
  description = "Path to Vault CA cert (for TLS verification). Leave empty to skip TLS verify."
  type        = string
  default     = ""
}

variable "policies" {
  description = "List of Vault policies to create"
  type = list(object({
    name = string
    rules = list(object({
      path         = string
      capabilities = list(string)
    }))
  }))
  default = []
}

variable "default_policy" {
  description = "Override for Vault default policy (extra rules appended to base). Set to null to skip."
  type = object({
    extra_rules = list(object({
      path         = string
      capabilities = list(string)
    }))
  })
  default = null
}

variable "approle_roles" {
  description = "AppRole auth roles"
  type = list(object({
    role_name      = string
    token_policies = list(string)
    token_ttl      = number
    token_max_ttl  = number
    secret_id_ttl  = number
  }))
  default = []
}

variable "userpass_users" {
  description = "Userpass auth users"
  type = list(object({
    username = string
    password = string
    policies = list(string)
  }))
  default   = []
  sensitive = true
}

variable "jwt_roles" {
  description = "JWT/OIDC auth roles"
  type = list(object({
    role_name      = string
    jwks_url       = string
    token_policies = list(string)
    token_ttl      = number
    token_max_ttl  = number
    bound_issuer   = optional(string, "")
    bound_claims   = optional(map(string), {})
  }))
  default = []
}

variable "kv_engines" {
  description = "KV v2 secret engines to mount"
  type = list(object({
    path         = string
    description  = string
    max_versions = number
  }))
  default = []
}

variable "transit_engines" {
  description = "Transit secret engines (e.g. for auto-unseal)"
  type = list(object({
    name        = string
    path        = optional(string, "transit")
    policy_name = string
  }))
  default = []
}

variable "audit_config" {
  description = "Audit device configuration. Set to null to skip audit setup."
  type = object({
    enable_file   = optional(bool, true)
    file_path     = optional(string, "/var/log/vault/audit.log")
    enable_syslog = optional(bool, false)
  })
  default = null
}

variable "password_policies" {
  description = "Vault password policies for random password generation"
  type = list(object({
    name  = string
    rules = list(object({
      charset   = string
      min_chars = number
    }))
  }))
  default = []
}
