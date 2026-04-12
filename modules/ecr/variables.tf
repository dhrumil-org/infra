variable "env" {
  description = "Environment name"
  type        = string
}

variable "project" {
  description = "Project name"
  type        = string
}

variable "repository_name" {
  description = "ECR repository name suffix"
  type        = string
  default     = "app"
}

variable "kms_key_arn" {
  description = "KMS key ARN for ECR encryption"
  type        = string
}
