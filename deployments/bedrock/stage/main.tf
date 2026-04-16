################################################################################
# Bedrock Knowledge Base — Stage
#
# Creates:
#   - S3 bucket for KB documents (upload PDFs / text files here)
#   - OpenSearch Serverless collection (vector store)
#   - Bedrock Knowledge Base linked to the collection
#   - IAM service role for Bedrock
#
# After apply:
#   1. Upload documents to: s3://{kb_bucket_name}/
#   2. Trigger a sync in the AWS Console (Knowledge Bases → Sync) or run:
#      aws bedrock-agent start-ingestion-job \
#        --knowledge-base-id <kb_id> \
#        --data-source-id   <ds_id>
################################################################################

module "bedrock_kb" {
  source = "../../../modules/bedrock-kb"

  env            = var.env
  project        = var.project
  aws_region     = var.aws_region
  aws_account_id = var.aws_account_id

  kb_name        = var.kb_name
  kb_description = var.kb_description

  embedding_model_arn = var.embedding_model_arn
  vector_dimensions   = var.vector_dimensions

  # S3 document bucket (created by this module)
  create_kb_bucket = true
  kms_key_arn      = var.kms_key_arn
  kb_bucket_prefix = var.kb_bucket_prefix

  # Chunking
  chunking_strategy  = var.chunking_strategy
  max_tokens         = var.max_tokens
  overlap_percentage = var.overlap_percentage

  # OpenSearch Serverless
  collection_name   = "kb"
  vector_index_name = "bedrock-kb-index"
  vector_field      = "bedrock-knowledge-base-default-vector"
  text_field        = "AMAZON_BEDROCK_TEXT_CHUNK"
  metadata_field    = "AMAZON_BEDROCK_METADATA"
}

################################################################################
# Outputs
################################################################################

output "knowledge_base_id" {
  description = "Bedrock Knowledge Base ID — use in API calls"
  value       = module.bedrock_kb.knowledge_base_id
}

output "knowledge_base_arn" {
  description = "Bedrock Knowledge Base ARN"
  value       = module.bedrock_kb.knowledge_base_arn
}

output "knowledge_base_name" {
  description = "Bedrock Knowledge Base name"
  value       = module.bedrock_kb.knowledge_base_name
}

output "data_source_id" {
  description = "S3 data source ID — needed for ingestion job triggers"
  value       = module.bedrock_kb.data_source_id
}

output "kb_bucket_name" {
  description = "Upload your documents here to populate the KB"
  value       = module.bedrock_kb.kb_bucket_name
}

output "opensearch_collection_endpoint" {
  description = "OpenSearch Serverless collection endpoint"
  value       = module.bedrock_kb.opensearch_collection_endpoint
}

output "bedrock_kb_role_arn" {
  description = "IAM role ARN used by the Knowledge Base"
  value       = module.bedrock_kb.bedrock_kb_role_arn
}
