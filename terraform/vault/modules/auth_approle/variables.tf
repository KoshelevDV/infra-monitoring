variable "role_name" {
  description = "AppRole role name"
  type        = string
}

variable "token_policies" {
  description = "List of policies attached to the token"
  type        = list(string)
  default     = []
}

variable "token_ttl" {
  description = "Token TTL in seconds"
  type        = number
  default     = 3600
}

variable "token_max_ttl" {
  description = "Token max TTL in seconds"
  type        = number
  default     = 86400
}

variable "secret_id_ttl" {
  description = "Secret ID TTL in seconds (0 = no expiry)"
  type        = number
  default     = 0
}
