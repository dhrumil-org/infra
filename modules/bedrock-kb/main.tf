locals {
  name_prefix  = "${var.project}-${var.env}"
  kb_full_name = "${local.name_prefix}-${var.kb_name}-kb"

  # All resource names derive from name_prefix → stage: vocanote-stage-*, prod: vocanote-prod-*
  # OpenSearch Serverless collection name max 32 chars — keep suffix short
  collection_name   = "${local.name_prefix}-kb"
  vector_index_name = var.vector_index_name != "" ? var.vector_index_name : "${local.name_prefix}-kb-index"

  # Resolve primary bucket
  primary_bucket_name = var.create_primary_bucket ? aws_s3_bucket.primary[0].bucket : var.existing_primary_bucket_name
  primary_bucket_arn  = var.create_primary_bucket ? aws_s3_bucket.primary[0].arn : var.existing_primary_bucket_arn

  # Resolve secondary bucket
  secondary_bucket_name = var.create_secondary_bucket ? aws_s3_bucket.secondary[0].bucket : var.existing_secondary_bucket_name
  secondary_bucket_arn  = var.create_secondary_bucket ? aws_s3_bucket.secondary[0].arn : var.existing_secondary_bucket_arn

  # Resolve multimodal bucket
  multimodal_bucket_name = var.create_multimodal_bucket ? aws_s3_bucket.multimodal[0].bucket : var.existing_multimodal_bucket_name
  multimodal_bucket_arn  = var.create_multimodal_bucket ? aws_s3_bucket.multimodal[0].arn : var.existing_multimodal_bucket_arn

  # All source bucket ARNs Bedrock needs to read
  all_source_bucket_arns = var.enable_secondary_data_source ? [
    local.primary_bucket_arn,
    local.secondary_bucket_arn,
  ] : [local.primary_bucket_arn]
}

################################################################################
# S3 Buckets
################################################################################

# --- Primary: standard docs (PDFs, text files) ---

resource "aws_s3_bucket" "primary" {
  count         = var.create_primary_bucket ? 1 : 0
  bucket        = "${local.name_prefix}-kb-data"
  force_destroy = false
  tags          = { Name = "${local.name_prefix}-kb-data" }
}

resource "aws_s3_bucket_versioning" "primary" {
  count  = var.create_primary_bucket ? 1 : 0
  bucket = aws_s3_bucket.primary[0].id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "primary" {
  count  = var.create_primary_bucket ? 1 : 0
  bucket = aws_s3_bucket.primary[0].id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.kms_key_arn != "" ? "aws:kms" : "AES256"
      kms_master_key_id = var.kms_key_arn != "" ? var.kms_key_arn : null
    }
    bucket_key_enabled = var.kms_key_arn != "" ? true : false
  }
}

resource "aws_s3_bucket_public_access_block" "primary" {
  count                   = var.create_primary_bucket ? 1 : 0
  bucket                  = aws_s3_bucket.primary[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# --- Secondary: docs needing Bedrock model parsing ---

resource "aws_s3_bucket" "secondary" {
  count         = var.create_secondary_bucket && var.enable_secondary_data_source ? 1 : 0
  bucket        = "${local.name_prefix}-kb-source"
  force_destroy = false
  tags          = { Name = "${local.name_prefix}-kb-source" }
}

resource "aws_s3_bucket_versioning" "secondary" {
  count  = var.create_secondary_bucket && var.enable_secondary_data_source ? 1 : 0
  bucket = aws_s3_bucket.secondary[0].id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "secondary" {
  count  = var.create_secondary_bucket && var.enable_secondary_data_source ? 1 : 0
  bucket = aws_s3_bucket.secondary[0].id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.kms_key_arn != "" ? "aws:kms" : "AES256"
      kms_master_key_id = var.kms_key_arn != "" ? var.kms_key_arn : null
    }
    bucket_key_enabled = var.kms_key_arn != "" ? true : false
  }
}

resource "aws_s3_bucket_public_access_block" "secondary" {
  count                   = var.create_secondary_bucket && var.enable_secondary_data_source ? 1 : 0
  bucket                  = aws_s3_bucket.secondary[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# --- Multimodal: Bedrock writes extracted images/figures here ---

resource "aws_s3_bucket" "multimodal" {
  count         = var.create_multimodal_bucket ? 1 : 0
  bucket        = "${local.name_prefix}-kb-assets"
  force_destroy = false
  tags          = { Name = "${local.name_prefix}-kb-assets" }
}

resource "aws_s3_bucket_versioning" "multimodal" {
  count  = var.create_multimodal_bucket ? 1 : 0
  bucket = aws_s3_bucket.multimodal[0].id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "multimodal" {
  count  = var.create_multimodal_bucket ? 1 : 0
  bucket = aws_s3_bucket.multimodal[0].id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.kms_key_arn != "" ? "aws:kms" : "AES256"
      kms_master_key_id = var.kms_key_arn != "" ? var.kms_key_arn : null
    }
    bucket_key_enabled = var.kms_key_arn != "" ? true : false
  }
}

resource "aws_s3_bucket_public_access_block" "multimodal" {
  count                   = var.create_multimodal_bucket ? 1 : 0
  bucket                  = aws_s3_bucket.multimodal[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

################################################################################
# IAM Role — Bedrock Knowledge Base service role (internal, not for your app)
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
  tags               = { Name = "${local.name_prefix}-bedrock-kb-role" }
}

data "aws_iam_policy_document" "bedrock_kb_policy" {
  # Invoke embedding model
  statement {
    sid       = "AllowEmbeddingModelInvoke"
    effect    = "Allow"
    actions   = ["bedrock:InvokeModel"]
    resources = [var.embedding_model_arn]
  }

  # Invoke parsing model (secondary data source only)
  dynamic "statement" {
    for_each = var.enable_secondary_data_source ? [1] : []
    content {
      sid       = "AllowParsingModelInvoke"
      effect    = "Allow"
      actions   = ["bedrock:InvokeModel"]
      resources = [var.parsing_model_arn]
    }
  }

  # Read all S3 data source buckets
  statement {
    sid    = "AllowS3DataSourceRead"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:ListBucket",
    ]
    resources = flatten([
      for arn in local.all_source_bucket_arns : [arn, "${arn}/*"]
    ])
  }

  # Write multimodal storage (extracted images/figures)
  statement {
    sid    = "AllowMultimodalStorageWrite"
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:ListBucket",
    ]
    resources = [
      local.multimodal_bucket_arn,
      "${local.multimodal_bucket_arn}/*",
    ]
  }

  # OpenSearch Serverless — write and query the vector index
  statement {
    sid       = "AllowOpenSearchAccess"
    effect    = "Allow"
    actions   = ["aoss:APIAccessAll"]
    resources = ["arn:aws:aoss:${var.aws_region}:${var.aws_account_id}:collection/*"]
  }

  # KMS decryption (only if a KMS key is provided)
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
# (The Terraform AWS provider does not yet support aws_s3vectors_* resources)
################################################################################

resource "aws_opensearchserverless_security_policy" "encryption" {
  name        = "${local.collection_name}-enc"
  type        = "encryption"
  description = "Encryption policy for ${local.collection_name}"

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

resource "aws_opensearchserverless_security_policy" "network" {
  name        = "${local.collection_name}-net"
  type        = "network"
  description = "Network policy for ${local.collection_name}"

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
        "arn:aws:iam::${var.aws_account_id}:root",
      ]
    }
  ])
}

resource "aws_opensearchserverless_collection" "kb" {
  name        = local.collection_name
  type        = "VECTORSEARCH"
  description = "Vector store for ${local.kb_full_name}"

  depends_on = [
    aws_opensearchserverless_security_policy.encryption,
    aws_opensearchserverless_security_policy.network,
    aws_opensearchserverless_access_policy.kb,
  ]

  tags = { Name = local.collection_name }
}

################################################################################
# Bedrock Knowledge Base
################################################################################

resource "aws_bedrockagent_knowledge_base" "this" {
  name        = local.kb_full_name
  description = var.kb_description != "" ? var.kb_description : "Knowledge base for ${local.name_prefix}"
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
      vector_index_name = local.vector_index_name

      field_mapping {
        vector_field   = var.vector_field
        text_field     = var.text_field
        metadata_field = var.metadata_field
      }
    }
  }

  tags = { Name = local.kb_full_name }

  depends_on = [aws_iam_role_policy.bedrock_kb]
}

################################################################################
# Data Source 1 — Primary (fixed-size chunking, default parsing)
################################################################################

resource "aws_bedrockagent_data_source" "primary" {
  name                 = "${local.name_prefix}-kb-data"
  knowledge_base_id    = aws_bedrockagent_knowledge_base.this.id
  data_deletion_policy = "RETAIN"

  data_source_configuration {
    type = "S3"

    s3_configuration {
      bucket_arn         = local.primary_bucket_arn
      inclusion_prefixes = var.primary_bucket_prefix != "" ? [var.primary_bucket_prefix] : null
    }
  }

  vector_ingestion_configuration {
    chunking_configuration {
      chunking_strategy = var.primary_chunking_strategy

      dynamic "fixed_size_chunking_configuration" {
        for_each = var.primary_chunking_strategy == "FIXED_SIZE" ? [1] : []
        content {
          max_tokens         = var.primary_max_tokens
          overlap_percentage = var.primary_overlap_percentage
        }
      }
    }
  }
}

################################################################################
# Data Source 2 — Secondary (semantic chunking + Bedrock model parsing)
################################################################################

resource "aws_bedrockagent_data_source" "secondary" {
  count = var.enable_secondary_data_source ? 1 : 0

  name                 = "${local.name_prefix}-kb-source"
  knowledge_base_id    = aws_bedrockagent_knowledge_base.this.id
  data_deletion_policy = "RETAIN"

  data_source_configuration {
    type = "S3"

    s3_configuration {
      bucket_arn         = local.secondary_bucket_arn
      inclusion_prefixes = var.secondary_bucket_prefix != "" ? [var.secondary_bucket_prefix] : null
    }
  }

  vector_ingestion_configuration {
    chunking_configuration {
      chunking_strategy = "SEMANTIC"

      semantic_chunking_configuration {
        breakpoint_percentile_threshold = 95
        buffer_size                     = 0
        max_tokens                      = 300
      }
    }

    parsing_configuration {
      parsing_strategy = "BEDROCK_FOUNDATION_MODEL"

      bedrock_foundation_model_configuration {
        model_arn = var.parsing_model_arn
      }
    }
  }
}

################################################################################
# IAM Policy — for your app (ECS task role) to query the KB
#
# This is attached to the ECS task role in deployments/bedrock/stage/main.tf
# so your Spring Boot app can call bedrock:Retrieve / bedrock:RetrieveAndGenerate
################################################################################

data "aws_iam_policy_document" "kb_access" {
  statement {
    sid    = "AllowKBRetrieve"
    effect = "Allow"
    actions = [
      "bedrock:Retrieve",
      "bedrock:RetrieveAndGenerate",
    ]
    resources = [aws_bedrockagent_knowledge_base.this.arn]
  }

  statement {
    sid    = "AllowResponseModelInvoke"
    effect = "Allow"
    actions = [
      "bedrock:InvokeModel",
      "bedrock:InvokeModelWithResponseStream",
    ]
    resources = ["arn:aws:bedrock:${var.aws_region}::foundation-model/*"]
  }
}

resource "aws_iam_policy" "kb_access" {
  name        = "${local.name_prefix}-bedrock-kb-access"
  description = "Allows the ${local.name_prefix} app to query the Bedrock Knowledge Base"
  policy      = data.aws_iam_policy_document.kb_access.json

  tags = { Name = "${local.name_prefix}-bedrock-kb-access" }
}
