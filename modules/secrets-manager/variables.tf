variable "env"         { type = string }
variable "project"     { type = string }
variable "secret_name" { type = string }

variable "secret_values" {
  type      = map(string)
  sensitive = true
  default   = {}
}
