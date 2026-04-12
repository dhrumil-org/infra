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
