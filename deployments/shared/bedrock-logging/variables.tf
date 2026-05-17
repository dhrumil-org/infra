variable "project" {
  description = "Project name (used as prefix on every resource)"
  type        = string
}

variable "aws_region" {
  description = "AWS region for the invocation logging configuration"
  type        = string
  default     = "us-east-1"
}

variable "aws_account_id" {
  description = "AWS account ID — used in the IAM role trust policy's confused-deputy guards"
  type        = string
}
