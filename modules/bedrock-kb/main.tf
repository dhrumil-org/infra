locals {
  name_prefix = "${var.project}-${var.env}"
  kb_full_name = "${local.name_prefix}-${var.kb_name}-kb"

  vector_bucket_name = var.vector_bucket_name != "" ? var.vector_bucket_name : "${local.name_prefix}-s3-vector-store"

  # Resolve primary bucket
  primary_bucket_name = var.create_primary_bucket ? aws_s3_bucket.primary[0].bucket : var.existing_primary_bucket_name
  primary_bucket_arn  = var.create_primary_bucket ? aws_s3_bucket.primary[0].arn : var.existing_primary_bucket_arn

  # Resolve secondary bucket
  secondary_bucket_name = var.create_secondary_bucket ? aws_s3_bucket.secondary[0].bucket : var.existing_secondary_bucket_name
  secondary_bucket_arn  = var.create_secondary_bucket ? aws_s3_bucket.secondary[0].arn : var.existing_secondary_bucket_arn

  # Resolve multimodal bucket
  multimodal_bucket_name = var.create_multimodal_bucket ? aws_s3_bucket.multimodal[0].bucket : var.existing_multimodal_bucket_name
  multimodal_bucket_arn  = var.create_multimodal_bucket ? aws_s3_bucket.multimodal[0].arn : var.existing_multimodal_bucket_arn

  # S3 buckets that Bedrock needs to read (for IAM)
  all_source_bucket_arns = var.enable_secondary_data_source ? [
    local.primary_bucket_arn,
    local.secondary_bucket_arn,
  ] : [local.primary_bucket_arn]
}

################################################################################
# Helper — common S3 bucket settings
################################################################################

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
# Primary S3 bucket — main document data source (default parsing)
################################################################################

resource "aws_s3_bucket" "primary" {
  count = var.create_primary_bucket ? 1 : 0

  bucket        = "${local.name_prefix}-kb-data"
  force_destroy = false

  tags = { Name = "${local.name_prefix}-kb-data" }
}

################################################################################
# Secondary S3 bucket — data source with Bedrock model parsing
################################################################################

resource "aws_s3_bucket" "secondary" {
  count = var.create_secondary_bucket && var.enable_secondary_data_source ? 1 : 0

  bucket        = "${local.name_prefix}-kb-source"
  force_destroy = false

  tags = { Name = "${local.name_prefix}-kb-source" }
}

################################################################################
# Multimodal storage bucket — Bedrock writes extracted images / audio here
################################################################################

resource "aws_s3_bucket" "multimodal" {
  count = var.create_multimodal_bucket ? 1 : 0

  bucket        = "${local.name_prefix}-kb-assets"
  force_destroy = false

  tags = { Name = "${local.name_prefix}-kb-assets" }
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

  tags = { Name = "${local.name_prefix}-bedrock-kb-role" }
}

data "aws_iam_policy_document" "bedrock_kb_policy" {
  # Invoke embedding model
  statement {
    sid    = "AllowEmbeddingModelInvoke"
    effect = "Allow"
    actions = [
      "bedrock:InvokeModel",
    ]
    resources = [var.embedding_model_arn]
  }

  # Invoke parsing model (used by secondary data source)
  dynamic "statement" {
    for_each = var.enable_secondary_data_source ? [1] : []
    content {
      sid    = "AllowParsingModelInvoke"
      effect = "Allow"
      actions = [
        "bedrock:InvokeModel",
      ]
      resources = [var.parsing_model_arn]
    }
  }

  # Read all source buckets
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

  # Write multimodal storage (images, audio extracted by Bedrock)
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

  # S3 Vectors — read/write vector index
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
      "arn:aws:s3vectors:${var.aws_region}:${var.aws_account_id}:bucket/${local.vector_bucket_name}/index/${var.vector_index_name}",
    ]
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
# S3 Vectors — Vector bucket + index
# (Amazon S3 Vectors replaces OpenSearch Serverless for this KB)
################################################################################

resource "aws_s3vectors_vector_bucket" "kb" {
  vector_bucket_name = local.vector_bucket_name
}

resource "aws_s3vectors_index" "kb" {
  vector_bucket_name = aws_s3vectors_vector_bucket.kb.vector_bucket_name
  index_name         = var.vector_index_name

  data_type  = "float32"
  dimension  = var.vector_dimensions
  metric     = "cosine"
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
    type = "S3_VECTORS"

    s3_vectors_configuration {
      index_arn = aws_s3vectors_index.kb.arn

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

  depends_on = [aws_iam_role_policy.bedrock_kb]
}

################################################################################
# Data Source 1 — Primary (default parsing, fixed-size chunking)
# Matches "vocanote-dev-data" in the screenshots
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
# Data Source 2 — Secondary (Bedrock model parsing + semantic chunking)
# Matches "dev-kb-source" in the screenshots
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
    # Semantic chunking — Bedrock decides chunk boundaries based on meaning
    chunking_configuration {
      chunking_strategy = "SEMANTIC"
    }

    # Bedrock model parsing — uses Claude to extract text from PDFs, images, etc.
    parsing_configuration {
      parsing_strategy = "BEDROCK_FOUNDATION_MODEL"

      bedrock_foundation_model_configuration {
        model_arn = var.parsing_model_arn

        parsing_modality = "MULTIMODAL_WITH_TEXT_AND_IMAGES"
      }
    }

    # Multimodal storage — where Bedrock writes extracted images/figures
    custom_transformation_configuration {
      intermediate_storage {
        s3_location {
          uri = "s3://${local.multimodal_bucket_name}/"
        }
      }
    }
  }
}
