variable "project" {
  description = "Project name"
  type        = string
}

variable "env" {
  description = "Environment name"
  type        = string
}

variable "kms_key_arn" {
  description = "KMS key ARN for backup vault and SNS topic encryption"
  type        = string
}

variable "s3_bucket_arns" {
  description = "List of S3 bucket ARNs to back up (primary, secondary, multimodal)"
  type        = list(string)
}

variable "rds_arn" {
  description = "RDS instance ARN to back up (leave empty string to skip)"
  type        = string
  default     = ""
}
