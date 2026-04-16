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
  default     = "us-east-1"
}

variable "aws_account_id" {
  description = "AWS account ID"
  type        = string
}

variable "kb_name" {
  description = "Knowledge Base name suffix"
  type        = string
  default     = "main"
}

variable "kb_description" {
  description = "Knowledge Base description"
  type        = string
  default     = ""
}

# Embedding model
variable "embedding_model_arn" {
  description = "ARN of the Bedrock embedding model"
  type        = string
  # Amazon Nova Multimodal Embeddings v1 — matches dev-vocanote-kb-v2
  default = "arn:aws:bedrock:us-east-1::foundation-model/amazon.nova-embed-v1:0"
}

variable "vector_dimensions" {
  description = "Embedding vector dimensions (must match model)"
  type        = number
  default     = 1024
}

# S3 Vectors
variable "vector_bucket_name" {
  description = "S3 Vectors bucket name. Defaults to {project}-{env}-s3-vector-store."
  type        = string
  default     = ""
}

variable "vector_index_name" {
  description = "S3 Vectors index name"
  type        = string
  default     = "vocanote-kb-index"
}

# Primary data source
variable "primary_chunking_strategy" {
  description = "Chunking strategy for primary data source"
  type        = string
  default     = "FIXED_SIZE"
}

variable "primary_max_tokens" {
  description = "Max tokens per chunk (FIXED_SIZE)"
  type        = number
  default     = 512
}

variable "primary_overlap_percentage" {
  description = "Overlap % between chunks (FIXED_SIZE)"
  type        = number
  default     = 20
}

variable "primary_bucket_prefix" {
  description = "S3 prefix for primary data source scope"
  type        = string
  default     = ""
}

# Secondary data source
variable "secondary_bucket_prefix" {
  description = "S3 prefix for secondary data source scope"
  type        = string
  default     = ""
}

variable "parsing_model_arn" {
  description = "Bedrock model ARN for document parsing (secondary data source)"
  type        = string
  # Claude 3 Haiku — fast and cost-effective for parsing
  default = "arn:aws:bedrock:us-east-1::foundation-model/anthropic.claude-3-haiku-20240307-v1:0"
}

# KMS
variable "kms_key_arn" {
  description = "KMS key ARN for S3 encryption. Empty = SSE-S3."
  type        = string
  default     = ""
}
