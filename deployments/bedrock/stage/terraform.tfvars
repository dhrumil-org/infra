env            = "stage"
project        = "vocanote"
aws_region     = "us-east-1"
aws_account_id = "499290259511"

# Knowledge Base
kb_name        = "main"
kb_description = "VocaNote stage knowledge base — voice notes and medical terminology"

# Titan Embed Text v2 — best accuracy, 1536 dimensions
embedding_model_arn = "arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-text-v2:0"
vector_dimensions   = 1536

# Chunking: 512 tokens with 20% overlap works well for Q&A use cases
chunking_strategy  = "FIXED_SIZE"
max_tokens         = 512
overlap_percentage = 20

# Leave empty to index the entire bucket, or set e.g. "docs/" to limit scope
kb_bucket_prefix = ""

# Leave empty to use SSE-S3 (AES256), or set a KMS key ARN for CMK encryption
kms_key_arn = ""
