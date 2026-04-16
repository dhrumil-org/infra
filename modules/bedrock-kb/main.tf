locals {
  name_prefix     = "${var.project}-${var.env}"
  kb_full_name    = "${local.name_prefix}-${var.kb_name}-kb"
  collection_name = "${local.name_prefix}-${var.collection_name}"

  # Resolve bucket values whether we created one or use an existing one
  kb_bucket_name = var.create_kb_bucket ? aws_s3_bucket.kb[0].bucket : var.existing_kb_bucket_name
  kb_bucket_arn  = var.create_kb_bucket ? aws_s3_bucket.kb[0].arn : var.existing_kb_bucket_arn
}

################################################################################
# S3 Bucket — Document storage for the Knowledge Base
# (only created when create_kb_bucket = true)
################################################################################

resource "aws_s3_bucket" "kb" {
  count = var.create_kb_bucket ? 1 : 0

  bucket        = "${local.name_prefix}-bedrock-kb-docs"
  force_destroy = false

  tags = {
    Name = "${local.name_prefix}-bedrock-kb-docs"
  }
}

resource "aws_s3_bucket_versioning" "kb" {
  count = var.create_kb_bucket ? 1 : 0

  bucket = aws_s3_bucket.kb[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "kb" {
  count = var.create_kb_bucket ? 1 : 0

  bucket = aws_s3_bucket.kb[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.kms_key_arn != "" ? "aws:kms" : "AES256"
      kms_master_key_id = var.kms_key_arn != "" ? var.kms_key_arn : null
    }
    bucket_key_enabled = var.kms_key_arn != "" ? true : false
  }
}

resource "aws_s3_bucket_public_access_block" "kb" {
  count = var.create_kb_bucket ? 1 : 0

  bucket = aws_s3_bucket.kb[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "kb" {
  count = var.create_kb_bucket ? 1 : 0

  bucket = aws_s3_bucket.kb[0].id

  rule {
    id     = "expire-old-versions"
    status = "Enabled"

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

################################################################################
# IAM Role — Bedrock Knowledge Base service role
################################################################################

data "aws_iam_policy_document" "bedrock_kb_assume" {
  statement {
    sid     = "AllowBedrockKBAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["bedrock.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.aws_account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:bedrock:${var.aws_region}:${var.aws_account_id}:knowledge-base/*"]
    }
  }
}

resource "aws_iam_role" "bedrock_kb" {
  name               = "${local.name_prefix}-bedrock-kb-role"
  assume_role_policy = data.aws_iam_policy_document.bedrock_kb_assume.json

  tags = {
    Name = "${local.name_prefix}-bedrock-kb-role"
  }
}

data "aws_iam_policy_document" "bedrock_kb_policy" {
  # Allow invoking the embedding foundation model
  statement {
    sid    = "AllowEmbeddingModelInvoke"
    effect = "Allow"
    actions = [
      "bedrock:InvokeModel",
    ]
    resources = [var.embedding_model_arn]
  }

  # Allow reading from the S3 data source bucket
  statement {
    sid    = "AllowS3DataSourceRead"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:ListBucket",
    ]
    resources = [
      local.kb_bucket_arn,
      "${local.kb_bucket_arn}/*",
    ]
  }

  # Allow writing to OpenSearch Serverless collection
  statement {
    sid    = "AllowOpenSearchAccess"
    effect = "Allow"
    actions = [
      "aoss:APIAccessAll",
    ]
    resources = [
      "arn:aws:aoss:${var.aws_region}:${var.aws_account_id}:collection/*",
    ]
  }

  # KMS decryption for S3 bucket (only if a KMS key is provided)
  dynamic "statement" {
    for_each = var.kms_key_arn != "" ? [1] : []

    content {
      sid    = "AllowKMSDecrypt"
      effect = "Allow"
      actions = [
        "kms:Decrypt",
        "kms:GenerateDataKey",
        "kms:DescribeKey",
      ]
      resources = [var.kms_key_arn]
    }
  }
}

resource "aws_iam_role_policy" "bedrock_kb" {
  name   = "${local.name_prefix}-bedrock-kb-policy"
  role   = aws_iam_role.bedrock_kb.id
  policy = data.aws_iam_policy_document.bedrock_kb_policy.json
}

################################################################################
# OpenSearch Serverless — Vector store
################################################################################

# Encryption policy — required before collection creation
resource "aws_opensearchserverless_security_policy" "encryption" {
  name        = "${local.collection_name}-enc"
  type        = "encryption"
  description = "Encryption policy for ${local.collection_name} KB collection"

  policy = jsonencode({
    Rules = [
      {
        ResourceType = "collection"
        Resource     = ["collection/${local.collection_name}"]
      }
    ]
    AWSOwnedKey = true
  })
}

# Network policy — allow Bedrock and console access
resource "aws_opensearchserverless_security_policy" "network" {
  name        = "${local.collection_name}-net"
  type        = "network"
  description = "Network policy for ${local.collection_name} KB collection"

  policy = jsonencode([
    {
      Rules = [
        {
          ResourceType = "collection"
          Resource     = ["collection/${local.collection_name}"]
        },
        {
          ResourceType = "dashboard"
          Resource     = ["collection/${local.collection_name}"]
        }
      ]
      AllowFromPublic = true
    }
  ])
}

# Data access policy — allow Bedrock KB role to manage the index
resource "aws_opensearchserverless_access_policy" "kb" {
  name        = "${local.collection_name}-access"
  type        = "data"
  description = "Data access for Bedrock KB role on ${local.collection_name}"

  policy = jsonencode([
    {
      Rules = [
        {
          ResourceType = "index"
          Resource     = ["index/${local.collection_name}/*"]
          Permission = [
            "aoss:CreateIndex",
            "aoss:DeleteIndex",
            "aoss:UpdateIndex",
            "aoss:DescribeIndex",
            "aoss:ReadDocument",
            "aoss:WriteDocument",
          ]
        },
        {
          ResourceType = "collection"
          Resource     = ["collection/${local.collection_name}"]
          Permission = [
            "aoss:CreateCollectionItems",
            "aoss:DeleteCollectionItems",
            "aoss:UpdateCollectionItems",
            "aoss:DescribeCollectionItems",
          ]
        }
      ]
      Principal = [
        aws_iam_role.bedrock_kb.arn,
        # Allow the account root so admins can inspect via console
        "arn:aws:iam::${var.aws_account_id}:root",
      ]
    }
  ])
}

# OpenSearch Serverless collection
resource "aws_opensearchserverless_collection" "kb" {
  name        = local.collection_name
  type        = "VECTORSEARCH"
  description = "Vector store for ${local.kb_full_name} Bedrock Knowledge Base"

  depends_on = [
    aws_opensearchserverless_security_policy.encryption,
    aws_opensearchserverless_security_policy.network,
    aws_opensearchserverless_access_policy.kb,
  ]

  tags = {
    Name = local.collection_name
  }
}

################################################################################
# Bedrock Knowledge Base
################################################################################

resource "aws_bedrockagent_knowledge_base" "this" {
  name        = local.kb_full_name
  description = var.kb_description
  role_arn    = aws_iam_role.bedrock_kb.arn

  knowledge_base_configuration {
    type = "VECTOR"

    vector_knowledge_base_configuration {
      embedding_model_arn = var.embedding_model_arn
    }
  }

  storage_configuration {
    type = "OPENSEARCH_SERVERLESS"

    opensearch_serverless_configuration {
      collection_arn    = aws_opensearchserverless_collection.kb.arn
      vector_index_name = var.vector_index_name

      field_mapping {
        vector_field   = var.vector_field
        text_field     = var.text_field
        metadata_field = var.metadata_field
      }
    }
  }

  tags = {
    Name = local.kb_full_name
  }
}

################################################################################
# S3 Data Source
################################################################################

resource "aws_bedrockagent_data_source" "s3" {
  name                 = "${local.kb_full_name}-s3"
  knowledge_base_id    = aws_bedrockagent_knowledge_base.this.id
  data_deletion_policy = "RETAIN"

  data_source_configuration {
    type = "S3"

    s3_configuration {
      bucket_arn         = local.kb_bucket_arn
      inclusion_prefixes = var.kb_bucket_prefix != "" ? [var.kb_bucket_prefix] : null
    }
  }

  vector_ingestion_configuration {
    chunking_configuration {
      chunking_strategy = var.chunking_strategy

      dynamic "fixed_size_chunking_configuration" {
        for_each = var.chunking_strategy == "FIXED_SIZE" ? [1] : []

        content {
          max_tokens         = var.max_tokens
          overlap_percentage = var.overlap_percentage
        }
      }
    }
  }
}
