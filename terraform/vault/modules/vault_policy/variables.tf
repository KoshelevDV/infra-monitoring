variable "name" {
  description = "Policy name"
  type        = string
}

variable "rules" {
  description = "List of policy rules"
  type = list(object({
    path         = string
    capabilities = list(string)
  }))
}
