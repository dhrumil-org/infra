variable "project" {
  description = "Project name"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "aws_account_id" {
  description = "AWS account ID"
  type        = string
}

variable "bedrock_agent_id" {
  description = "Bedrock Agent ID for stage (from bedrock/stage terraform output)"
  type        = string
}

variable "bedrock_kb_id" {
  description = "Bedrock Knowledge Base ID for stage (from bedrock/stage terraform output)"
  type        = string
}
