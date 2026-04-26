variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "aws_account_id" {
  type = string
}

variable "env" {
  type = string
}

variable "project" {
  type = string
}

variable "bucket_name" {
  type = string
}

variable "aliases" {
  type    = list(string)
  default = []
}

variable "acm_certificate_arn" {
  type    = string
  default = ""
}

variable "price_class" {
  type    = string
  default = "PriceClass_100"
}

variable "secret_name" {
  description = "Name of the Secrets Manager secret holding NEXT_PUBLIC_* values for the frontend build"
  type        = string
}

variable "secret_values" {
  description = "Key/value pairs written into the frontend build-time secret (NEXT_PUBLIC_*)"
  type        = map(string)
  default     = {}
}

variable "tf_state_bucket" {
  type    = string
  default = ""
}

variable "tf_dynamodb_table" {
  type    = string
  default = ""
}
