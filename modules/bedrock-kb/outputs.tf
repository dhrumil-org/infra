output "knowledge_base_id" {
  description = "Bedrock Knowledge Base ID"
  value       = aws_bedrockagent_knowledge_base.this.id
}

output "knowledge_base_arn" {
  description = "Bedrock Knowledge Base ARN"
  value       = aws_bedrockagent_knowledge_base.this.arn
}

output "knowledge_base_name" {
  description = "Bedrock Knowledge Base name"
  value       = aws_bedrockagent_knowledge_base.this.name
}

output "data_source_id" {
  description = "S3 data source ID"
  value       = aws_bedrockagent_data_source.s3.data_source_id
}

output "opensearch_collection_arn" {
  description = "OpenSearch Serverless collection ARN"
  value       = aws_opensearchserverless_collection.kb.arn
}

output "opensearch_collection_endpoint" {
  description = "OpenSearch Serverless collection endpoint URL"
  value       = aws_opensearchserverless_collection.kb.collection_endpoint
}

output "bedrock_kb_role_arn" {
  description = "IAM role ARN used by the Bedrock Knowledge Base"
  value       = aws_iam_role.bedrock_kb.arn
}

output "kb_bucket_name" {
  description = "S3 bucket name holding KB documents (empty if using existing bucket)"
  value       = var.create_kb_bucket ? aws_s3_bucket.kb[0].bucket : var.existing_kb_bucket_name
}

output "kb_bucket_arn" {
  description = "S3 bucket ARN for KB documents"
  value       = local.kb_bucket_arn
}
