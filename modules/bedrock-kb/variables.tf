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
  description = "Name suffix for the Knowledge Base. Full name: {project}-{env}-{kb_name}-kb"
  type        = string
  default     = "main"
}

variable "kb_description" {
  description = "Description for the Knowledge Base"
  type        = string
  default     = ""
}

variable "embedding_model_arn" {
  description = "ARN of the Bedrock foundation model used for embeddings"
  type        = string
  # Amazon Nova Multimodal Embeddings v1 — supports text + image, 1024 dims
  default = "arn:aws:bedrock:us-east-1::foundation-model/amazon.nova-embed-v1:0"
}

variable "vector_dimensions" {
  description = "Vector dimensions — must match the embedding model output"
  type        = number
  # Nova Multimodal Embeddings v1 = 1024
  default = 1024
}

################################################################################
# S3 Vectors — Vector store (replaces OpenSearch Serverless)
################################################################################

variable "vector_bucket_name" {
  description = "Name for the S3 Vectors bucket. Defaults to {project}-{env}-s3-vector-store"
  type        = string
  default     = ""
}

variable "vector_index_name" {
  description = "Name of the vector index inside the S3 Vectors bucket. Defaults to {project}-{env}-kb-index."
  type        = string
  default     = ""
}

variable "vector_field" {
  description = "Field name for the embedding vector"
  type        = string
  default     = "bedrock-knowledge-base-default-vector"
}

variable "text_field" {
  description = "Field name for the raw text chunk"
  type        = string
  default     = "AMAZON_BEDROCK_TEXT_CHUNK"
}

variable "metadata_field" {
  description = "Field name for document metadata"
  type        = string
  default     = "AMAZON_BEDROCK_METADATA"
}

################################################################################
# Primary S3 Data Source — default chunking + default parsing
################################################################################

variable "create_primary_bucket" {
  description = "Create a new S3 bucket for the primary data source"
  type        = bool
  default     = true
}

variable "existing_primary_bucket_name" {
  description = "Existing S3 bucket name for primary data source (create_primary_bucket = false)"
  type        = string
  default     = ""
}

variable "existing_primary_bucket_arn" {
  description = "Existing S3 bucket ARN for primary data source (create_primary_bucket = false)"
  type        = string
  default     = ""
}

variable "primary_bucket_prefix" {
  description = "S3 prefix to scope primary data source. Empty = entire bucket."
  type        = string
  default     = ""
}

variable "primary_chunking_strategy" {
  description = "Chunking strategy for primary data source"
  type        = string
  default     = "FIXED_SIZE"

  validation {
    condition     = contains(["FIXED_SIZE", "NONE", "HIERARCHICAL", "SEMANTIC"], var.primary_chunking_strategy)
    error_message = "Must be FIXED_SIZE, NONE, HIERARCHICAL, or SEMANTIC."
  }
}

variable "primary_max_tokens" {
  description = "Max tokens per chunk (FIXED_SIZE strategy)"
  type        = number
  default     = 512
}

variable "primary_overlap_percentage" {
  description = "Overlap % between chunks (FIXED_SIZE strategy, 0-99)"
  type        = number
  default     = 20
}

################################################################################
# Secondary S3 Data Source — semantic chunking + Bedrock model parsing
################################################################################

variable "enable_secondary_data_source" {
  description = "Add a second data source with Bedrock model parsing and semantic chunking"
  type        = bool
  default     = true
}

variable "create_secondary_bucket" {
  description = "Create a new S3 bucket for the secondary data source"
  type        = bool
  default     = true
}

variable "existing_secondary_bucket_name" {
  description = "Existing S3 bucket name for secondary data source (create_secondary_bucket = false)"
  type        = string
  default     = ""
}

variable "existing_secondary_bucket_arn" {
  description = "Existing S3 bucket ARN for secondary data source (create_secondary_bucket = false)"
  type        = string
  default     = ""
}

variable "secondary_bucket_prefix" {
  description = "S3 prefix to scope secondary data source. Empty = entire bucket."
  type        = string
  default     = ""
}

variable "parsing_model_arn" {
  description = "Bedrock foundation model ARN used for document parsing (secondary data source)"
  type        = string
  # Claude 3 Haiku — fast and cheap for parsing; swap for Sonnet for richer extraction
  default = "arn:aws:bedrock:us-east-1::foundation-model/anthropic.claude-3-haiku-20240307-v1:0"
}

################################################################################
# Multimodal Storage — S3 bucket for images/audio extracted during parsing
################################################################################

variable "create_multimodal_bucket" {
  description = "Create a dedicated S3 bucket for multimodal content (images, audio) extracted by Bedrock"
  type        = bool
  default     = true
}

variable "existing_multimodal_bucket_name" {
  description = "Existing S3 bucket name for multimodal storage (create_multimodal_bucket = false)"
  type        = string
  default     = ""
}

variable "existing_multimodal_bucket_arn" {
  description = "Existing S3 bucket ARN for multimodal storage (create_multimodal_bucket = false)"
  type        = string
  default     = ""
}

################################################################################
# KMS
################################################################################

variable "kms_key_arn" {
  description = "KMS key ARN for S3 bucket encryption. Empty = SSE-S3 (AES256)."
  type        = string
  default     = ""
}
