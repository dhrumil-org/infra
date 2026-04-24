variable "env" {
  description = "Environment name"
  type        = string
}

variable "project" {
  description = "Project name"
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

variable "kms_key_arn" {
  description = "KMS key ARN for encrypting CloudTrail logs (S3 + CloudWatch)"
  type        = string
}

variable "s3_data_event_bucket_arns" {
  description = "S3 bucket ARNs to enable object-level data event logging (PHI buckets)"
  type        = list(string)
  default     = []
}
