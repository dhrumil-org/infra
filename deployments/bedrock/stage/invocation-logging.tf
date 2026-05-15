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
# Cost (Apr 2026 us-east-1 list prices):
#   - CWL ingestion : $0.50/GB     (~$0.0025/mo at current volume)
#   - CWL storage   : $0.03/GB-mo  (kept 30 days, set below)
#   - Insights query: $0.005/GB scanned
#
# At 1000x growth this stays under ~$5/mo.
################################################################################

resource "aws_cloudwatch_log_group" "bedrock_invocations" {
  name              = "/aws/bedrock/${var.project}-invocations"
  retention_in_days = 30
  # KMS optional; SSE handled by CloudWatch Logs by default.

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
