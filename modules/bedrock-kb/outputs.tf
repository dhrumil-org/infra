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

output "primary_data_source_id" {
  description = "Primary S3 data source ID"
  value       = aws_bedrockagent_data_source.primary.data_source_id
}

output "secondary_data_source_id" {
  description = "Secondary S3 data source ID (Bedrock model parsing)"
  value       = var.enable_secondary_data_source ? aws_bedrockagent_data_source.secondary[0].data_source_id : null
}

output "opensearch_collection_arn" {
  description = "OpenSearch Serverless collection ARN (vector store)"
  value       = aws_opensearchserverless_collection.kb.arn
}

output "opensearch_collection_endpoint" {
  description = "OpenSearch Serverless collection endpoint"
  value       = aws_opensearchserverless_collection.kb.collection_endpoint
}

output "vector_index_name" {
  description = "OpenSearch index name where vectors are stored"
  value       = local.vector_index_name
}

output "bedrock_kb_role_arn" {
  description = "IAM role ARN used by the Bedrock Knowledge Base"
  value       = aws_iam_role.bedrock_kb.arn
}

output "primary_bucket_name" {
  description = "Primary S3 bucket for KB documents"
  value       = local.primary_bucket_name
}

output "secondary_bucket_name" {
  description = "Secondary S3 bucket (Bedrock model parsing data source)"
  value       = var.enable_secondary_data_source ? local.secondary_bucket_name : null
}

output "multimodal_bucket_name" {
  description = "S3 bucket for extracted multimodal content (images, audio)"
  value       = local.multimodal_bucket_name
}

output "kb_access_policy_arn" {
  description = "IAM policy ARN — attach to your ECS task role so the app can call Retrieve / RetrieveAndGenerate"
  value       = aws_iam_policy.kb_access.arn
}

output "kb_access_policy_name" {
  description = "IAM policy name"
  value       = aws_iam_policy.kb_access.name
}
