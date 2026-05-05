locals {
  name_prefix  = "${var.project}-${var.env}"
  kb_full_name = "${local.name_prefix}-${var.kb_name}-kb"

  # All resource names derive from name_prefix → stage: vocuone-stage-*, prod: vocuone-prod-*
  vector_bucket_name = var.vector_bucket_name != "" ? var.vector_bucket_name : "${local.name_prefix}-s3-vector-store"
  vector_index_name  = var.vector_index_name != "" ? var.vector_index_name : "${local.name_prefix}-kb-index"

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

# Explicit bucket policy — required so Bedrock can validate write access
# IAM role policy alone is not sufficient for this validation
resource "aws_s3_bucket_policy" "multimodal" {
  count  = var.create_multimodal_bucket ? 1 : 0
  bucket = aws_s3_bucket.multimodal[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowBedrockKBRoleAccess"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.bedrock_kb.arn
        }
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetBucketLocation",
        ]
        Resource = [
          aws_s3_bucket.multimodal[0].arn,
          "${aws_s3_bucket.multimodal[0].arn}/*",
        ]
      },
      {
        Sid    = "AllowBedrockServiceAccess"
        Effect = "Allow"
        Principal = {
          Service = "bedrock.amazonaws.com"
        }
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
        ]
        Resource = [
          aws_s3_bucket.multimodal[0].arn,
          "${aws_s3_bucket.multimodal[0].arn}/*",
        ]
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = var.aws_account_id
          }
        }
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.multimodal]
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
  statement {
    sid       = "AllowEmbeddingModelInvoke"
    effect    = "Allow"
    actions   = ["bedrock:InvokeModel"]
    resources = [var.embedding_model_arn]
  }

  dynamic "statement" {
    for_each = var.enable_secondary_data_source ? [1] : []
    content {
      sid       = "AllowParsingModelInvoke"
      effect    = "Allow"
      actions   = ["bedrock:InvokeModel"]
      resources = [var.parsing_model_arn]
    }
  }

  # Multimodal embedding/parsing models (Nova) often route through cross-region
  # inference profiles internally; without this Bedrock returns 429/AccessDenied
  # during the pre-flight model check.
  statement {
    sid       = "AllowInferenceProfileInvoke"
    effect    = "Allow"
    actions   = ["bedrock:InvokeModel"]
    resources = ["arn:aws:bedrock:${var.aws_region}:${var.aws_account_id}:inference-profile/*"]
  }

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

  statement {
    sid    = "AllowMultimodalStorageWrite"
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:DeleteObject",
      "s3:ListBucket",
      "s3:GetBucketLocation",
    ]
    resources = [
      local.multimodal_bucket_arn,
      "${local.multimodal_bucket_arn}/*",
    ]
  }

  # S3 Vectors — read/write the vector index
  statement {
    sid    = "AllowS3VectorsAccess"
    effect = "Allow"
    actions = [
      "s3vectors:GetIndex",
      "s3vectors:ListIndexes",
      "s3vectors:PutVectors",
      "s3vectors:GetVectors",
      "s3vectors:DeleteVectors",
      "s3vectors:QueryVectors",
    ]
    resources = [
      "arn:aws:s3vectors:${var.aws_region}:${var.aws_account_id}:bucket/${local.vector_bucket_name}",
      "arn:aws:s3vectors:${var.aws_region}:${var.aws_account_id}:bucket/${local.vector_bucket_name}/index/${local.vector_index_name}",
    ]
  }

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
# S3 Vectors — Vector bucket + index
################################################################################

resource "aws_s3vectors_vector_bucket" "kb" {
  vector_bucket_name = local.vector_bucket_name
}

resource "aws_s3vectors_index" "kb" {
  vector_bucket_name = aws_s3vectors_vector_bucket.kb.vector_bucket_name
  index_name         = local.vector_index_name

  data_type       = "float32"
  dimension       = var.vector_dimensions  # 3072 for amazon.nova-2-multimodal-embeddings-v1:0
  distance_metric = "cosine"

  # Mark Bedrock's auto-attached chunk text + source metadata as non-filterable
  # so they don't count toward the 2048-byte filterable-metadata cap.
  metadata_configuration {
    non_filterable_metadata_keys = [
      "AMAZON_BEDROCK_METADATA",
      "AMAZON_BEDROCK_TEXT",
    ]
  }
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

      # Required when using multimodal embedding models (Nova Multimodal)
      # Bedrock stores extracted images/figures here during ingestion
      supplemental_data_storage_configuration {
        storage_location {
          type = "S3"

          s3_location {
            uri = "s3://${local.multimodal_bucket_name}/"
          }
        }
      }
    }
  }

  storage_configuration {
    type = "S3_VECTORS"

    s3_vectors_configuration {
      index_arn = aws_s3vectors_index.kb.index_arn
    }
  }

  tags = { Name = local.kb_full_name }

  depends_on = [
    aws_iam_role_policy.bedrock_kb,
    aws_s3_bucket_policy.multimodal,
  ]
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

  # Points at the primary kb-data bucket (matches old-account design):
  # one bucket, two data sources — primary does fast text extraction,
  # secondary re-parses image/scanned PDFs with the multimodal model.
  data_source_configuration {
    type = "S3"
    s3_configuration {
      bucket_arn         = local.primary_bucket_arn
      inclusion_prefixes = var.secondary_bucket_prefix != "" ? [var.secondary_bucket_prefix] : null
    }
  }

  vector_ingestion_configuration {
    chunking_configuration {
      chunking_strategy = "SEMANTIC"

      semantic_chunking_configuration {
        breakpoint_percentile_threshold = 95
        buffer_size                     = 0
        max_token                       = 3072
      }
    }

    parsing_configuration {
      parsing_strategy = "BEDROCK_FOUNDATION_MODEL"

      bedrock_foundation_model_configuration {
        model_arn         = var.parsing_model_arn
        parsing_modality  = "MULTIMODAL"

        parsing_prompt {
          parsing_prompt_string = "Extract all readable text from the document. Preserve section headings, tables, and key-value fields. Return plain text only."
        }
      }
    }
  }
}

################################################################################
# IAM Policy — for your app (ECS task role) to call the KB
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
    resources = [
      # Foundation models — wildcard region because cross-region inference
      # profiles route internally to us-east-1, us-east-2, us-west-2, etc.
      "arn:aws:bedrock:*::foundation-model/*",
      # Cross-region inference profiles (e.g. us.anthropic.claude-*)
      "arn:aws:bedrock:${var.aws_region}:${var.aws_account_id}:inference-profile/*",
      "arn:aws:bedrock:*::inference-profile/*",
    ]
  }

  statement {
    sid    = "AllowInferenceProfileRead"
    effect = "Allow"
    actions = [
      "bedrock:GetInferenceProfile",
      "bedrock:ListInferenceProfiles",
    ]
    resources = ["*"]
  }

  dynamic "statement" {
    for_each = var.create_primary_bucket ? [1] : []
    content {
      sid    = "AllowS3PrimaryBucketAccess"
      effect = "Allow"
      actions = [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket",
        "s3:GetBucketLocation",
        "s3:GetBucketCORS",
        "s3:PutBucketCORS",
      ]
      resources = [
        aws_s3_bucket.primary[0].arn,
        "${aws_s3_bucket.primary[0].arn}/*",
      ]
    }
  }

  dynamic "statement" {
    for_each = var.enable_secondary_data_source ? [1] : []
    content {
      sid    = "AllowS3SecondaryBucketAccess"
      effect = "Allow"
      actions = [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket",
        "s3:GetBucketLocation",
        "s3:GetBucketCORS",
        "s3:PutBucketCORS",
      ]
      resources = [
        aws_s3_bucket.secondary[0].arn,
        "${aws_s3_bucket.secondary[0].arn}/*",
      ]
    }
  }

  dynamic "statement" {
    for_each = var.create_multimodal_bucket ? [1] : []
    content {
      sid    = "AllowS3MultimodalBucketAccess"
      effect = "Allow"
      actions = [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket",
        "s3:GetBucketLocation",
        "s3:GetBucketCORS",
        "s3:PutBucketCORS",
      ]
      resources = [
        aws_s3_bucket.multimodal[0].arn,
        "${aws_s3_bucket.multimodal[0].arn}/*",
      ]
    }
  }

  statement {
    sid    = "AllowBedrockAgentInvoke"
    effect = "Allow"
    actions = [
      # AWS checks both prefixes depending on SDK/API path used
      "bedrock:InvokeAgent",
      "bedrock-agent-runtime:InvokeAgent",
      "bedrock-agent-runtime:Retrieve",
      "bedrock-agent-runtime:RetrieveAndGenerate",
    ]
    resources = [
      "arn:aws:bedrock:${var.aws_region}:${var.aws_account_id}:agent/*",
      "arn:aws:bedrock:${var.aws_region}:${var.aws_account_id}:agent-alias/*",
      "arn:aws:bedrock:${var.aws_region}:${var.aws_account_id}:knowledge-base/*",
    ]
  }
}

resource "aws_iam_policy" "kb_access" {
  name        = "${local.name_prefix}-bedrock-kb-access"
  description = "Allows the ${local.name_prefix} app to query the Bedrock Knowledge Base"
  policy      = data.aws_iam_policy_document.kb_access.json
  tags        = { Name = "${local.name_prefix}-bedrock-kb-access" }
}
