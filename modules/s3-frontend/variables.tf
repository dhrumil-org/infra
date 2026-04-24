variable "env"         { type = string }
variable "bucket_name" { type = string }

variable "cloudfront_distribution_arn" {
  type    = string
  default = ""
}

variable "kms_key_arn" {
  description = "KMS key ARN for S3 server-side encryption"
  type        = string
}
