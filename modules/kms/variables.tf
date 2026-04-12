variable "env" {
  description = "Environment name"
  type        = string
}

variable "project" {
  description = "Project name"
  type        = string
}

variable "keys" {
  description = "Map of KMS keys to create"
  type = map(object({
    description = string
    policy      = optional(string, null)
  }))
}
