output "canary_name" {
  description = "CloudWatch Synthetics canary name"
  value       = aws_synthetics_canary.this.name
}

output "canary_arn" {
  description = "CloudWatch Synthetics canary ARN"
  value       = aws_synthetics_canary.this.arn
}

output "artifact_bucket" {
  description = "S3 bucket for canary results AND script uploads (GHA uploads to canary-script/ prefix)"
  value       = aws_s3_bucket.artifacts.bucket
}

output "script_s3_key" {
  description = "S3 key where GitHub Actions should upload the canary zip"
  value       = "canary-script/canary.zip"
}

output "alarm_arn" {
  description = "CloudWatch alarm ARN for canary failures"
  value       = aws_cloudwatch_metric_alarm.canary_failed.arn
}
