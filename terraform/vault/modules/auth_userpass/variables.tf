variable "username" {
  description = "Userpass username"
  type        = string
}

variable "password" {
  description = "Userpass password"
  type        = string
  sensitive   = true
}

variable "policies" {
  description = "List of policies to attach to the user"
  type        = list(string)
  default     = []
}
