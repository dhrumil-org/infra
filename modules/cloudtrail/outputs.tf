output "trail_arn" {
  description = "CloudTrail trail ARN"
  value       = aws_cloudtrail.this.arn
}

output "log_bucket_name" {
  description = "S3 bucket name for CloudTrail logs"
  value       = aws_s3_bucket.logs.id
}

output "log_group_name" {
  description = "CloudWatch log group for real-time CloudTrail events"
  value       = aws_cloudwatch_log_group.cloudtrail.name
}
