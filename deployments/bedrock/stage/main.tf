################################################################################
# Bedrock Knowledge Base — Stage
#
# Mirrors dev-vocanote-kb-v2 configuration:
#   - Embedding model : Amazon Nova Multimodal Embeddings v1 (1024 dims)
#   - Vector store    : Amazon S3 Vectors
#   - Data source 1   : Fixed-size chunking, default parsing
#   - Data source 2   : Semantic chunking, Bedrock model parsing (Claude Haiku)
#   - Multimodal store: Separate S3 bucket for extracted images/figures
#
# After apply:
#   1. Upload documents to the S3 bucket shown in output "primary_bucket_name"
#      (PDFs, plain text, DOCX)
#   2. For Bedrock-parsed docs (audio transcripts, scanned PDFs) upload to
#      output "secondary_bucket_name"
#   3. Trigger a sync:
#      aws bedrock-agent start-ingestion-job \
#        --knowledge-base-id $(terraform output -raw knowledge_base_id) \
#        --data-source-id   $(terraform output -raw primary_data_source_id) \
#        --region us-east-1
################################################################################

module "bedrock_kb" {
  source = "../../../modules/bedrock-kb"

  env            = var.env
  project        = var.project
  aws_region     = var.aws_region
  aws_account_id = var.aws_account_id

  # Knowledge Base identity
  kb_name        = var.kb_name
  kb_description = var.kb_description

  # Embedding model — Amazon Nova Multimodal Embeddings v1
  embedding_model_arn = var.embedding_model_arn
  vector_dimensions   = var.vector_dimensions

  # S3 Vectors vector store
  vector_bucket_name = var.vector_bucket_name
  vector_index_name  = var.vector_index_name

  # Primary data source — default parsing, fixed-size chunking
  create_primary_bucket      = true
  primary_chunking_strategy  = var.primary_chunking_strategy
  primary_max_tokens         = var.primary_max_tokens
  primary_overlap_percentage = var.primary_overlap_percentage
  primary_bucket_prefix      = var.primary_bucket_prefix

  # Secondary data source — Bedrock model parsing + semantic chunking
  enable_secondary_data_source = true
  create_secondary_bucket      = true
  secondary_bucket_prefix      = var.secondary_bucket_prefix
  parsing_model_arn            = var.parsing_model_arn

  # Multimodal storage for extracted images/figures
  create_multimodal_bucket = true

  # KMS (leave empty for SSE-S3)
  kms_key_arn = var.kms_key_arn
}

################################################################################
# Outputs
################################################################################

output "knowledge_base_id" {
  description = "Bedrock Knowledge Base ID — use in API calls"
  value       = module.bedrock_kb.knowledge_base_id
}

output "knowledge_base_name" {
  description = "Bedrock Knowledge Base name"
  value       = module.bedrock_kb.knowledge_base_name
}

output "primary_data_source_id" {
  description = "Primary data source ID (for ingestion jobs)"
  value       = module.bedrock_kb.primary_data_source_id
}

output "secondary_data_source_id" {
  description = "Secondary data source ID — Bedrock model parsing"
  value       = module.bedrock_kb.secondary_data_source_id
}

output "primary_bucket_name" {
  description = "Upload standard documents here (PDFs, text files)"
  value       = module.bedrock_kb.primary_bucket_name
}

output "secondary_bucket_name" {
  description = "Upload docs needing Bedrock parsing here (scanned PDFs, complex layouts)"
  value       = module.bedrock_kb.secondary_bucket_name
}

output "multimodal_bucket_name" {
  description = "Bedrock writes extracted images/figures here automatically"
  value       = module.bedrock_kb.multimodal_bucket_name
}

output "vector_bucket_name" {
  description = "S3 Vectors bucket (vector embeddings stored here)"
  value       = module.bedrock_kb.vector_bucket_name
}

output "bedrock_kb_role_arn" {
  description = "IAM role ARN used by the Knowledge Base"
  value       = module.bedrock_kb.bedrock_kb_role_arn
}
