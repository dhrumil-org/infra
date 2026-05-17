variable "env" {
  description = "Environment name"
  type        = string
}

variable "recovery_window_in_days" {
  description = "Days before a deleted secret is permanently removed (0 for instant delete)"
  type        = number
  default     = 7
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

# Network
variable "vpc_id" {
  description = "VPC ID where RDS will be deployed"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for RDS (must be in at least 2 AZs)"
  type        = list(string)
}

variable "ecs_security_group_id" {
  description = "Security group ID of ECS tasks (allowed to connect to RDS)"
  type        = string
}

# Database
variable "engine_version" {
  description = "PostgreSQL engine version"
  type        = string
  default     = "16.4"
}

variable "instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}

variable "allocated_storage" {
  description = "Initial allocated storage in GB"
  type        = number
  default     = 20
}

variable "max_allocated_storage" {
  description = "Maximum allocated storage for autoscaling (GB)"
  type        = number
  default     = 100
}

variable "db_name" {
  description = "Initial database name"
  type        = string
  default     = "appdb"
}

variable "master_username" {
  description = "Master username for the database"
  type        = string
  default     = "dbadmin"
}

variable "db_port" {
  description = "Database port"
  type        = number
  default     = 5432
}

# High Availability
variable "multi_az" {
  description = "Enable Multi-AZ deployment (recommend true for prod, false for stage)"
  type        = bool
  default     = false
}

# Backups (HIPAA requires at least 7 days)
variable "backup_retention_period" {
  description = "Days to retain automated backups"
  type        = number
  default     = 7
}

# Encryption
variable "rds_kms_key_arn" {
  description = "KMS key ARN for RDS storage encryption"
  type        = string
}

variable "secrets_kms_key_arn" {
  description = "KMS key ARN for Secrets Manager encryption"
  type        = string
}

variable "logs_kms_key_arn" {
  description = "KMS key ARN for the pre-created RDS CloudWatch log groups (postgresql + upgrade)"
  type        = string
}

variable "log_retention_in_days" {
  description = "Retention for RDS CloudWatch log groups. Default 2557 = 7 years (HIPAA §164.530(j)(2))"
  type        = number
  default     = 2557
}

# Deletion protection
variable "deletion_protection" {
  description = "Prevent accidental deletion"
  type        = bool
  default     = false
}

variable "skip_final_snapshot" {
  description = "Skip final snapshot on deletion (set false for prod)"
  type        = bool
  default     = true
}

variable "apply_immediately" {
  description = "Apply changes immediately instead of next maintenance window"
  type        = bool
  default     = false
}

################################################################################
# App-facing secret (custom schema for Spring Boot RDS IAM auth)
################################################################################

variable "create_app_secret" {
  description = "Whether to create a separate secret with app-specific schema (DB_USERNAME, DATASOURCE_URL)"
  type        = bool
  default     = false
}

variable "app_secret_name" {
  description = "Name of the app-facing Secrets Manager secret (e.g. vocuone/stage/db)"
  type        = string
  default     = ""
}

variable "app_db_username" {
  description = "Application database username (IAM-authenticated, created manually via SQL)"
  type        = string
  default     = "vocuone_service_user"
}
