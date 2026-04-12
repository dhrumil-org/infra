output "pipeline_name" {
  description = "CodePipeline name"
  value       = aws_codepipeline.this.name
}

output "pipeline_arn" {
  description = "CodePipeline ARN"
  value       = aws_codepipeline.this.arn
}

output "artifacts_bucket" {
  description = "S3 bucket for pipeline artifacts"
  value       = aws_s3_bucket.artifacts.bucket
}
