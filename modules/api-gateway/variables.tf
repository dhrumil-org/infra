variable "project" {
  description = "Project name"
  type        = string
}

variable "env" {
  description = "Environment name"
  type        = string
}

variable "api_domain" {
  description = "Public domain for the API (e.g. api.stage.vocuone.ai)"
  type        = string
}

variable "alb_dns_name" {
  description = "ALB DNS name the API Gateway forwards requests to"
  type        = string
}

variable "acm_certificate_arn" {
  description = "ACM certificate ARN for the API Gateway custom domain (regional cert, not CloudFront)"
  type        = string
}

variable "throttling_burst_limit" {
  description = "Burst limit for throttling across all routes"
  type        = number
  default     = 500
}

variable "throttling_rate_limit" {
  description = "Steady-state rate limit (requests per second)"
  type        = number
  default     = 100
}

variable "log_retention_days" {
  description = "CloudWatch log retention for access logs"
  type        = number
  default     = 90
}

variable "kms_key_arn" {
  description = "KMS key ARN for encrypting access log group"
  type        = string
}

variable "gateway_secret" {
  description = "Secret value injected as X-Gateway-Secret header to identify traffic from API Gateway"
  type        = string
  sensitive   = true
}

variable "route53_zone_id" {
  description = "Route53 hosted zone ID (required if create_route53_record = true)"
  type        = string
  default     = ""
}

variable "create_route53_record" {
  description = "Create Route53 alias pointing api_domain to API Gateway. Set false if DNS is managed elsewhere."
  type        = bool
  default     = false
}
