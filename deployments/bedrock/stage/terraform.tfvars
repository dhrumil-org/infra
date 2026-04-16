env            = "stage"
project        = "vocanote"
aws_region     = "us-east-1"
aws_account_id = "499290259511"

# Knowledge Base
kb_name        = "main"
kb_description = "VocaNote stage knowledge base — voice notes and medical terminology"

# Amazon Nova Multimodal Embeddings v1 — matches dev-vocanote-kb-v2
# Supports text + image inputs, 1024-dim float vectors
embedding_model_arn = "arn:aws:bedrock:us-east-1::foundation-model/amazon.nova-2-multimodal-embeddings-v1:0"
vector_dimensions   = 3072

# S3 Vectors — auto-named: vocanote-stage-s3-vector-store / vocanote-stage-kb-index
# Leave empty to use the env-prefixed defaults
vector_bucket_name = ""
vector_index_name  = ""

# Primary data source — standard docs (text, PDFs)
# Fixed-size chunking with 20% overlap
primary_chunking_strategy  = "FIXED_SIZE"
primary_max_tokens         = 512
primary_overlap_percentage = 20
primary_bucket_prefix      = ""

# Secondary data source — Bedrock model parsing (scanned PDFs, audio transcripts)
# Semantic chunking + Claude Haiku as parser
secondary_bucket_prefix = ""
parsing_model_arn       = "arn:aws:bedrock:us-east-1::foundation-model/anthropic.claude-3-haiku-20240307-v1:0"

# KMS — leave empty to use SSE-S3 (AES256)
# Set to a KMS key ARN for HIPAA CMK encryption
kms_key_arn = ""
