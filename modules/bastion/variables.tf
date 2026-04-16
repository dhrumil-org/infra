variable "env" {
  description = "Environment name"
  type        = string
}

variable "project" {
  description = "Project name"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID where bastion will run (private subnet works with SSM)"
  type        = string
}

variable "rds_security_group_id" {
  description = "RDS security group ID (bastion SG will be allowed to connect)"
  type        = string
}

variable "master_secret_arn" {
  description = "ARN of Secrets Manager secret with RDS master credentials"
  type        = string
}

variable "secrets_kms_key_arn" {
  description = "KMS key ARN for secrets decryption"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.nano"
}
