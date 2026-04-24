variable "project" {
  description = "Project name"
  type        = string
}

variable "env" {
  description = "Environment name"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "aws_account_id" {
  description = "AWS account ID"
  type        = string
}

variable "associated_resource_arn" {
  description = "ARN of the resource to associate with the WAF web ACL (API Gateway stage or ALB)"
  type        = string
}

variable "rate_limit_per_ip" {
  description = "Max requests per IP per 5 minutes before rate limiting kicks in"
  type        = number
  default     = 2000
}

