output "canary_name" {
  description = "CloudWatch Synthetics canary name"
  value       = aws_synthetics_canary.this.name
}

output "canary_arn" {
  description = "CloudWatch Synthetics canary ARN"
  value       = aws_synthetics_canary.this.arn
}

output "artifact_bucket" {
  description = "S3 bucket where canary results are stored"
  value       = aws_s3_bucket.artifacts.bucket
}

output "alarm_arn" {
  description = "CloudWatch alarm ARN for canary failures"
  value       = aws_cloudwatch_metric_alarm.canary_failed.arn
}
