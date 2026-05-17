################################################################################
# Bedrock Model Invocation Logging — Account-wide (singleton)
#
# Bedrock Model Invocation Logging is account-level: only ONE configuration can
# exist per account/region, regardless of how many environments share it.
# This file lives under deployments/bedrock/stage/ for historical reasons but
# the resources here apply to ALL Bedrock calls in account 499290259511,
# including prod. Distinguish stage vs prod via requestMetadata.env field set
# by the application (com.vocanote.observability.EnvTag).
#
# Captures every Converse / InvokeModel / InvokeAgent / Retrieve call to
# CloudWatch Logs, including:
#   - input + output token counts
#   - cached_read / cached_write token splits (when prompt caching is used)
#   - model ID, region, latency
#   - the requestMetadata object the app attaches
#       { feature, company_uid, user_id, request_id, case_uid? }
#
# This is the single source of truth for per-customer cost attribution.
# Until this is enabled, no log entries exist — even though the app already
# attaches requestMetadata on every call.
#
# HIPAA controls applied here:
#   - kms_key_id : customer-managed CMK (aws_kms_key.bedrock_invocations)
#   - retention  : 2557 days (~7 years) per §164.530(j)(2)
#   - delivery   : text only; image/embedding/video disabled to limit PHI
#
# Cost (Apr 2026 us-east-1 list prices):
#   - CWL ingestion : $0.50/GB     (~$0.0025/mo at current volume)
#   - CWL storage   : $0.03/GB-mo  (7-year retention bumps this slightly)
#   - Insights query: $0.005/GB scanned
#
# At 1000x growth this stays under ~$5/mo.
################################################################################

# Dedicated CMK for the Bedrock invocation log group.
# Bedrock invocation logging is account-wide (one config per region) and this
# log group serves BOTH stage and prod traffic. We don't reuse either ECS
# stack's "logs" CMK to avoid coupling a shared resource to one env's stack.
data "aws_caller_identity" "bedrock_logging" {}

resource "aws_kms_key" "bedrock_invocations" {
  description             = "KMS key for Bedrock invocation log group (account-wide)"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EnableRootAccountAdmin"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.bedrock_logging.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        # CloudWatch Logs uses this key to encrypt log events on ingestion.
        # The EncryptionContext condition pins it to /aws/bedrock/* groups so
        # the key can't be (mis)used to encrypt arbitrary other log groups.
        Sid       = "AllowCloudWatchLogs"
        Effect    = "Allow"
        Principal = { Service = "logs.${var.aws_region}.amazonaws.com" }
        Action = [
          "kms:Encrypt*",
          "kms:Decrypt*",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:Describe*",
        ]
        Resource = "*"
        Condition = {
          ArnLike = {
            "kms:EncryptionContext:aws:logs:arn" = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.bedrock_logging.account_id}:log-group:/aws/bedrock/*"
          }
        }
      },
    ]
  })

  tags = {
    Name    = "${var.project}-bedrock-invocations"
    Purpose = "bedrock-invocation-log-group-encryption"
  }
}

resource "aws_kms_alias" "bedrock_invocations" {
  name          = "alias/${var.project}-bedrock-invocations"
  target_key_id = aws_kms_key.bedrock_invocations.key_id
}

resource "aws_cloudwatch_log_group" "bedrock_invocations" {
  name              = "/aws/bedrock/${var.project}-invocations"
  retention_in_days = 2557 # 7 years (HIPAA §164.530(j)(2))
  kms_key_id        = aws_kms_key.bedrock_invocations.arn

  tags = {
    Project = var.project
    Purpose = "bedrock-invocation-logging"
    Scope   = "account-wide"
  }
}

# IAM role Bedrock assumes to write to the log group.
data "aws_iam_policy_document" "bedrock_logging_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["bedrock.amazonaws.com"]
    }

    # Confused-deputy guards.
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.aws_account_id]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:bedrock:${var.aws_region}:${var.aws_account_id}:*"]
    }
  }
}

resource "aws_iam_role" "bedrock_logging" {
  name               = "${var.project}-bedrock-logging"
  assume_role_policy = data.aws_iam_policy_document.bedrock_logging_assume.json
}

data "aws_iam_policy_document" "bedrock_logging" {
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = [
      "${aws_cloudwatch_log_group.bedrock_invocations.arn}:*",
    ]
  }
}

resource "aws_iam_role_policy" "bedrock_logging" {
  name   = "write-invocation-logs"
  role   = aws_iam_role.bedrock_logging.id
  policy = data.aws_iam_policy_document.bedrock_logging.json
}

# Account-level setting. Only ONE Model Invocation Logging config per region.
# Importing the existing config first (if any) is recommended:
#   terraform import aws_bedrock_model_invocation_logging_configuration.this <account_id>
resource "aws_bedrock_model_invocation_logging_configuration" "this" {
  logging_config {
    embedding_data_delivery_enabled = false
    image_data_delivery_enabled     = false
    text_data_delivery_enabled      = true
    video_data_delivery_enabled     = false

    cloudwatch_config {
      log_group_name = aws_cloudwatch_log_group.bedrock_invocations.name
      role_arn       = aws_iam_role.bedrock_logging.arn
    }
  }

  depends_on = [aws_iam_role_policy.bedrock_logging]
}

output "bedrock_invocation_log_group" {
  description = "CloudWatch Logs group receiving Bedrock invocation events"
  value       = aws_cloudwatch_log_group.bedrock_invocations.name
}
