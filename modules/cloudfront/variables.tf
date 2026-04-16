variable "env"    { type = string }
variable "project" { type = string }
variable "s3_bucket_id" { type = string }
variable "s3_bucket_regional_domain" { type = string }

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
