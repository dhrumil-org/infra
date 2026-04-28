variable "env" {
  description = "Environment name"
  type        = string
}

variable "project" {
  description = "Project name"
  type        = string
}

variable "service_name" {
  description = "ECS service name suffix"
  type        = string
  default     = "app"
}

variable "ecs_cluster_name" {
  description = "ECS cluster name"
  type        = string
}

variable "ecs_service_name" {
  description = "ECS service name"
  type        = string
}

variable "https_listener_arn" {
  description = "ALB HTTPS listener ARN (production traffic, port 443). CodeDeploy ECS only allows one listener in prod_traffic_route, so this is the single one CodeDeploy swaps on blue/green promotion."
  type        = string
}

variable "test_listener_arn" {
  description = "ALB test listener ARN (canary validation, port 8443)"
  type        = string
}

variable "blue_target_group_name" {
  description = "Blue target group name"
  type        = string
}

variable "green_target_group_name" {
  description = "Green target group name"
  type        = string
}
