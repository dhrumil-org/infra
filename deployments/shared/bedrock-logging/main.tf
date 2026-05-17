################################################################################
# Bedrock Model Invocation Logging — Account-wide singleton
#
# Bedrock Model Invocation Logging is account-level: only ONE configuration
# can exist per account/region. Because it captures BOTH stage and prod
# Bedrock traffic, owning it from either deployments/bedrock/stage or
# deployments/bedrock/prod is misleading — destroying that env's stack
# would tear down the other env's logging.
#
# This shared stack is the single owner. Cross-env distinction is by the
# requestMetadata.env field every Bedrock call attaches (set by
# com.vocanote.observability.EnvTag in the Spring Boot app).
#
# Captures every Converse / InvokeModel / InvokeAgent / Retrieve call to
# CloudWatch Logs, including:
#   - input + output token counts
#   - cached_read / cached_write token splits (when prompt caching is used)
#   - model ID, region, latency
#   - the requestMetadata object the app attaches:
#       { feature, company_uid, user_id, request_id, case_uid?, env }
#
# HIPAA controls applied here:
#   - kms_key_id : customer-managed CMK (aws_kms_key.this)
#   - retention  : 2557 days (~7 years) per §164.530(j)(2)
#   - role trust : confused-deputy guards via aws:SourceAccount/SourceArn
#   - delivery   : text only; image/embedding/video disabled to limit PHI
#
# Cost (Apr 2026 us-east-1 list prices):
#   - CWL ingestion : $0.50/GB
#   - CWL storage   : $0.03/GB-mo  (7-year retention scales linearly)
#   - Insights query: $0.005/GB scanned
################################################################################

data "aws_caller_identity" "current" {}

# Dedicated CMK for the invocation log group, scoped to /aws/bedrock/* groups
# via the kms:EncryptionContext condition so the key can't be (mis)used for
# arbitrary other log groups.
resource "aws_kms_key" "this" {
  description             = "KMS key for Bedrock invocation log group (account-wide)"
  deletion_window_in_days = 30
  enable_key_rotation     = true

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
            "kms:EncryptionContext:aws:logs:arn" = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/bedrock/*"
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

resource "aws_kms_alias" "this" {
  name          = "alias/${var.project}-bedrock-invocations"
  target_key_id = aws_kms_key.this.key_id
}

resource "aws_cloudwatch_log_group" "bedrock_invocations" {
  name              = "/aws/bedrock/${var.project}-invocations"
  retention_in_days = 2557 # 7 years (HIPAA §164.530(j)(2))
  kms_key_id        = aws_kms_key.this.arn

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

output "kms_key_arn" {
  description = "CMK encrypting the Bedrock invocation log group"
  value       = aws_kms_key.this.arn
}
