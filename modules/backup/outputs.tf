output "vault_arn" {
  description = "Backup vault ARN"
  value       = aws_backup_vault.this.arn
}

output "vault_name" {
  description = "Backup vault name"
  value       = aws_backup_vault.this.name
}

output "daily_plan_arn" {
  description = "Daily backup plan ARN"
  value       = aws_backup_plan.daily.arn
}

output "monthly_plan_arn" {
  description = "Monthly backup plan ARN"
  value       = aws_backup_plan.monthly.arn
}

output "backup_role_arn" {
  description = "IAM role ARN used by AWS Backup"
  value       = aws_iam_role.backup.arn
}

output "sns_topic_arn" {
  description = "SNS topic ARN for backup failure alerts"
  value       = aws_sns_topic.backup_alerts.arn
}
