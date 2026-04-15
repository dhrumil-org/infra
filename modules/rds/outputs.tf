################################################################################
# RDS Instance
################################################################################

output "db_instance_id" {
  description = "RDS instance identifier"
  value       = aws_db_instance.this.id
}

output "db_instance_arn" {
  description = "RDS instance ARN"
  value       = aws_db_instance.this.arn
}

output "db_instance_address" {
  description = "RDS instance hostname"
  value       = aws_db_instance.this.address
}

output "db_instance_endpoint" {
  description = "RDS instance endpoint (host:port)"
  value       = aws_db_instance.this.endpoint
}

output "db_instance_port" {
  description = "RDS instance port"
  value       = aws_db_instance.this.port
}

output "db_name" {
  description = "Initial database name"
  value       = aws_db_instance.this.db_name
}

output "db_resource_id" {
  description = "RDS resource ID (for IAM DB auth)"
  value       = aws_db_instance.this.resource_id
}

################################################################################
# Secrets Manager
################################################################################

output "db_secret_arn" {
  description = "ARN of Secrets Manager secret containing DB credentials"
  value       = aws_secretsmanager_secret.db.arn
}

output "db_secret_name" {
  description = "Name of Secrets Manager secret"
  value       = aws_secretsmanager_secret.db.name
}

output "app_db_secret_arn" {
  description = "ARN of app-facing DB secret (Spring Boot IAM auth schema)"
  value       = var.create_app_secret ? aws_secretsmanager_secret.app_db[0].arn : ""
}

output "app_db_secret_name" {
  description = "Name of app-facing DB secret"
  value       = var.create_app_secret ? aws_secretsmanager_secret.app_db[0].name : ""
}

################################################################################
# Security Group
################################################################################

output "db_security_group_id" {
  description = "Security group ID of the RDS instance"
  value       = aws_security_group.rds.id
}

################################################################################
# IAM — For attaching to ECS task role or IAM users
################################################################################

output "db_access_policy_arn" {
  description = "ARN of the IAM policy for DB access (attach to ECS task role or IAM users)"
  value       = aws_iam_policy.db_access.arn
}

output "db_access_role_arn" {
  description = "ARN of the IAM role that can be assumed for DB access"
  value       = aws_iam_role.db_access.arn
}

output "db_access_role_name" {
  description = "Name of the IAM role for DB access"
  value       = aws_iam_role.db_access.name
}
