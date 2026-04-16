output "instance_id" {
  description = "Bastion EC2 instance ID (use with aws ssm start-session)"
  value       = aws_instance.bastion.id
}

output "security_group_id" {
  description = "Bastion security group ID"
  value       = aws_security_group.bastion.id
}

output "role_arn" {
  description = "Bastion IAM role ARN"
  value       = aws_iam_role.bastion.arn
}
