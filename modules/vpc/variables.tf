variable "env" {
  description = "Environment name"
  type        = string
}

variable "project" {
  description = "Project name"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
}

variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
}

variable "nat_gateway_count" {
  description = "Number of NAT gateways (1 for stage, match AZ count for prod)"
  type        = number
  default     = 1
}

variable "flow_logs_kms_key_arn" {
  description = "KMS key ARN for encrypting VPC flow logs"
  type        = string
}

variable "aws_region" {
  description = "AWS region (used for VPC endpoint service names)"
  type        = string
  default     = "us-east-1"
}

variable "enable_bedrock_endpoints" {
  description = "Create VPC endpoints for PHI services: S3, Secrets Manager, Transcribe, Bedrock"
  type        = bool
  default     = false
}
