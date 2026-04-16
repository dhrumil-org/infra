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
# Attach KB access policy to ECS task role
#
# Looks up the role by name — no remote state dependency.
# Role name follows the ecs-service module convention:
#   {project}-{env}-{service_name}-task-role → vocanote-stage-app-task-role
################################################################################

data "aws_iam_role" "ecs_task" {
  name = "${var.project}-${var.env}-app-task-role"
}

resource "aws_iam_role_policy_attachment" "ecs_task_kb_access" {
  role       = data.aws_iam_role.ecs_task.name
  policy_arn = module.bedrock_kb.kb_access_policy_arn
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
  description = "S3 Vectors bucket name"
  value       = module.bedrock_kb.vector_bucket_name
}

output "bedrock_kb_role_arn" {
  description = "IAM role ARN used by the Knowledge Base (internal — Bedrock uses this)"
  value       = module.bedrock_kb.bedrock_kb_role_arn
}

output "kb_access_policy_arn" {
  description = "IAM policy ARN attached to ECS task role — grants app access to Retrieve/RetrieveAndGenerate"
  value       = module.bedrock_kb.kb_access_policy_arn
}

################################################################################
# Bedrock Agent — sits on top of the KB, orchestrates LLM responses
################################################################################

module "bedrock_agent" {
  source = "../../../modules/bedrock-agent"

  env            = var.env
  project        = var.project
  aws_region     = var.aws_region
  aws_account_id = var.aws_account_id

  agent_name        = var.agent_name
  agent_description = var.agent_description
  foundation_model  = var.agent_foundation_model
  instruction       = var.agent_instruction

  # Link to the KB created above
  knowledge_base_id          = module.bedrock_kb.knowledge_base_id
  knowledge_base_description = "Use this knowledge base to answer questions about VocaNote"

  alias_name = var.env
}

output "agent_id" {
  description = "Bedrock Agent ID"
  value       = module.bedrock_agent.agent_id
}

output "agent_alias_id" {
  description = "Agent alias ID — pass this to InvokeAgent in your Spring Boot app"
  value       = module.bedrock_agent.agent_alias_id
}

output "agent_alias_arn" {
  description = "Agent alias ARN"
  value       = module.bedrock_agent.agent_alias_arn
}
