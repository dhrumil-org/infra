output "key_arns" {
  description = "Map of KMS key ARNs"
  value       = { for k, v in aws_kms_key.this : k => v.arn }
}

output "key_ids" {
  description = "Map of KMS key IDs"
  value       = { for k, v in aws_kms_key.this : k => v.key_id }
}
