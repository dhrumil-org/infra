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
  default     = "Knowledge base for VocaNote application"
}

variable "embedding_model_arn" {
  description = "ARN of the Bedrock embedding model"
  type        = string
  default     = "arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-text-v2:0"
}

variable "vector_dimensions" {
  description = "Embedding vector dimensions"
  type        = number
  default     = 1536
}

variable "chunking_strategy" {
  description = "Chunking strategy: FIXED_SIZE, NONE, HIERARCHICAL, or SEMANTIC"
  type        = string
  default     = "FIXED_SIZE"
}

variable "max_tokens" {
  description = "Max tokens per chunk"
  type        = number
  default     = 512
}

variable "overlap_percentage" {
  description = "Overlap percentage between chunks"
  type        = number
  default     = 20
}

variable "kb_bucket_prefix" {
  description = "S3 prefix to scope the data source (empty = entire bucket)"
  type        = string
  default     = ""
}

variable "kms_key_arn" {
  description = "KMS key ARN for S3 bucket encryption (leave empty for SSE-S3)"
  type        = string
  default     = ""
}
