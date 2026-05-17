################################################################################
# KMS key — Bedrock KB S3 buckets (PHI documents)
#
# The Bedrock Knowledge Base writes embedded documents, multimodal extracts,
# and parsing artifacts into S3 buckets created by modules/bedrock-kb.
# Customer healthcare data (PHI) flows through these buckets, so SSE-S3
# (AES256 with AWS-managed keys) doesn't meet HIPAA / SOC 2 expectations
# of customer-managed encryption keys.
#
# This CMK is bound to:
#   - vocuone-prod-kb-data       (primary, standard documents)
#   - vocuone-prod-kb-source     (secondary, Bedrock-parsed)
#   - vocuone-prod-kb-assets     (multimodal extracts)
#   - vocuone-prod-s3-vector-store (S3 Vectors backing store)
#
# Bedrock requires read/write access via its service principal; the bedrock-kb
# module's bucket policies grant Get/Put/Delete to bedrock.amazonaws.com
# scoped by aws:SourceAccount.
################################################################################

data "aws_caller_identity" "current" {}

resource "aws_kms_key" "bedrock_kb" {
  description             = "KMS key for ${var.project}-${var.env} Bedrock KB S3 buckets"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  # Default key policies only authorize the account root. Bedrock writes via
  # bedrock.amazonaws.com and inherits permissions from the KB's service role,
  # both of which need explicit grants here.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EnableRootAccountAdmin"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid       = "AllowBedrockServicePrincipal"
        Effect    = "Allow"
        Principal = { Service = "bedrock.amazonaws.com" }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey",
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      },
      {
        Sid       = "AllowS3ServicePrincipal"
        Effect    = "Allow"
        Principal = { Service = "s3.amazonaws.com" }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey",
        ]
        Resource = "*"
      },
    ]
  })

  tags = {
    Name = "${var.project}-${var.env}-bedrock-kb"
  }
}

resource "aws_kms_alias" "bedrock_kb" {
  name          = "alias/${var.project}-${var.env}-bedrock-kb"
  target_key_id = aws_kms_key.bedrock_kb.key_id
}
