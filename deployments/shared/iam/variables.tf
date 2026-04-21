variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "aws_account_id" {
  type = string
}

variable "project" {
  type = string
}

variable "tf_state_bucket" {
  type = string
}

variable "tf_dynamodb_table" {
  type = string
}

variable "s3_buckets" {
  type        = list(string)
  description = "All deployment bucket names this user needs access to"
}

variable "secret_names" {
  type        = list(string)
  description = "All secret name prefixes this user needs access to"
}
