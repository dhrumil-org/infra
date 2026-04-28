variable "project" {
  type = string
}

variable "env" {
  type = string
}

variable "prod_listener_arn" {
  description = "ALB listener CodeDeploy swaps during blue/green (HTTPS:443). The Lambda reads its current target group to determine the green one."
  type        = string
}

variable "secondary_listener_arn" {
  description = "ALB listener that should follow the prod one (HTTP:80). The Lambda updates its default action just before CodeDeploy swaps 443."
  type        = string
}
