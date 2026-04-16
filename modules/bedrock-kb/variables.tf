variable "env" {
  description = "Environment name"
  type        = string
}

variable "project" {
  description = "Project name"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "aws_account_id" {
  description = "AWS account ID"
  type        = string
}

################################################################################
# Knowledge Base
################################################################################

variable "kb_name" {
  description = "Name suffix for the Knowledge Base (e.g. 'main'). Full name: {project}-{env}-{kb_name}-kb"
  type        = string
  default     = "main"
}

variable "kb_description" {
  description = "Description for the Knowledge Base"
  type        = string
  default     = "Knowledge base for VocaNote application"
}

variable "embedding_model_arn" {
  description = "ARN of the Bedrock foundation model used for embeddings"
  type        = string
  # Titan Embed Text v2 — best for RAG, supports 1536 dimensions
  default = "arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-text-v2:0"
}

variable "vector_dimensions" {
  description = "Vector dimensions for the embedding model (must match model output)"
  type        = number
  # Titan Embed Text v2 default; change to 1024 or 256 for lower cost
  default = 1536
}

################################################################################
# S3 Data Source
################################################################################

variable "create_kb_bucket" {
  description = "Create a new S3 bucket for KB documents. Set false to use an existing bucket."
  type        = bool
  default     = true
}

variable "existing_kb_bucket_name" {
  description = "Existing S3 bucket name to use as data source (only when create_kb_bucket = false)"
  type        = string
  default     = ""
}

variable "existing_kb_bucket_arn" {
  description = "Existing S3 bucket ARN (only when create_kb_bucket = false)"
  type        = string
  default     = ""
}

variable "kb_bucket_prefix" {
  description = "S3 key prefix (folder) to include as data source. Empty string = entire bucket."
  type        = string
  default     = ""
}

variable "kms_key_arn" {
  description = "KMS key ARN for encrypting the S3 KB bucket (only used when create_kb_bucket = true)"
  type        = string
  default     = ""
}

################################################################################
# Chunking Strategy
################################################################################

variable "chunking_strategy" {
  description = "Chunking strategy: FIXED_SIZE, NONE, HIERARCHICAL, or SEMANTIC"
  type        = string
  default     = "FIXED_SIZE"

  validation {
    condition     = contains(["FIXED_SIZE", "NONE", "HIERARCHICAL", "SEMANTIC"], var.chunking_strategy)
    error_message = "chunking_strategy must be one of: FIXED_SIZE, NONE, HIERARCHICAL, SEMANTIC"
  }
}

variable "max_tokens" {
  description = "Max tokens per chunk (used when chunking_strategy = FIXED_SIZE)"
  type        = number
  default     = 512
}

variable "overlap_percentage" {
  description = "Overlap percentage between chunks (used when chunking_strategy = FIXED_SIZE, 0-99)"
  type        = number
  default     = 20
}

################################################################################
# OpenSearch Serverless
################################################################################

variable "collection_name" {
  description = "OpenSearch Serverless collection name suffix. Full: {project}-{env}-{name}"
  type        = string
  default     = "kb"
}

variable "vector_index_name" {
  description = "OpenSearch index name for vector storage"
  type        = string
  default     = "bedrock-kb-index"
}

variable "vector_field" {
  description = "Field name in OpenSearch that stores the vector embedding"
  type        = string
  default     = "bedrock-knowledge-base-default-vector"
}

variable "text_field" {
  description = "Field name in OpenSearch that stores the text content"
  type        = string
  default     = "AMAZON_BEDROCK_TEXT_CHUNK"
}

variable "metadata_field" {
  description = "Field name in OpenSearch that stores document metadata"
  type        = string
  default     = "AMAZON_BEDROCK_METADATA"
}
