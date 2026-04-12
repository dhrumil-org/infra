variable "aws_region" {
  type    = string
  default = "us-east-1"
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
