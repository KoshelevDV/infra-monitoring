variable "path" {
  description = "Mount path for the KV engine"
  type        = string
}

variable "description" {
  description = "Human-readable description of the KV engine"
  type        = string
  default     = "KV v2 secrets engine"
}

variable "max_versions" {
  description = "Maximum number of versions to retain per secret"
  type        = number
  default     = 10
}
