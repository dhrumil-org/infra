variable "env" {
  description = "Environment name"
  type        = string
}

variable "project" {
  description = "Project name"
  type        = string
}

variable "aws_account_id" {
  description = "AWS account ID"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "ecr_repository_name" {
  description = "ECR repository name (triggers pipeline on image push)"
  type        = string
}

variable "ecr_repository_arn" {
  description = "ECR repository ARN"
  type        = string
}

variable "ecr_image_tag" {
  description = "ECR image tag to watch for (triggers pipeline)"
  type        = string
  default     = "latest"
}

variable "codedeploy_app_name" {
  description = "CodeDeploy application name"
  type        = string
}

variable "codedeploy_deployment_group_name" {
  description = "CodeDeploy deployment group name"
  type        = string
}

variable "ecs_task_role_arns" {
  description = "ARNs of ECS task and execution roles (for iam:PassRole)"
  type        = list(string)
}

# Task definition template variables
variable "task_family" {
  description = "ECS task definition family name"
  type        = string
}

variable "task_cpu" {
  description = "Task CPU units"
  type        = string
}

variable "task_memory" {
  description = "Task memory in MiB"
  type        = string
}

variable "execution_role_arn" {
  description = "ECS task execution role ARN"
  type        = string
}

variable "task_role_arn" {
  description = "ECS task role ARN"
  type        = string
}

variable "container_name" {
  description = "Container name in task definition"
  type        = string
  default     = "app"
}

variable "container_port" {
  description = "Container port"
  type        = number
  default     = 8080
}

variable "log_group" {
  description = "CloudWatch log group name"
  type        = string
}

variable "environment_variables" {
  description = "Environment variables to pass to the container in the task definition"
  type = list(object({
    name  = string
    value = string
  }))
  default = []
}

variable "secrets" {
  description = "Secrets from Secrets Manager/Parameter Store injected into the container"
  type = list(object({
    name      = string
    valueFrom = string
  }))
  default = []
}

variable "alb_name" {
  description = "Name of the ALB whose port-80 listener should be re-aligned to port 443's target group after each successful CodeDeploy promotion. Empty disables the post-deploy sync stage."
  type        = string
  default     = ""
}
