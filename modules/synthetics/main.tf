################################################################################
# CloudWatch Synthetics Canary
#
# Runs canary.js on a schedule against your API:
#   Step 1: GET /health           — unauthenticated liveness
#   Step 2: POST /auth/login      — authenticate (if credentials provided)
#   Step 3: GET /api/health       — authenticated endpoint check
#
# Results (screenshots, logs, HAR) stored in S3 for 91 days.
# CloudWatch alarm fires if canary fails.
################################################################################

################################################################################
# S3 — Artifact storage (canary results: logs, screenshots, HAR files)
################################################################################

resource "aws_s3_bucket" "artifacts" {
  bucket = "${var.project}-${var.env}-canary-artifacts"

  tags = {
    Name = "${var.project}-${var.env}-canary-artifacts"
  }
}

resource "aws_s3_bucket_versioning" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket                  = aws_s3_bucket.artifacts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  rule {
    id     = "expire-canary-results"
    status = "Enabled"

    filter {}

    expiration {
      days = 91 # keep 91 days of results
    }
  }
}

################################################################################
# IAM Role — CloudWatch Synthetics execution role
################################################################################

data "aws_iam_policy_document" "synthetics_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "canary" {
  name               = "${var.project}-${var.env}-canary-role"
  assume_role_policy = data.aws_iam_policy_document.synthetics_assume.json

  tags = {
    Name = "${var.project}-${var.env}-canary-role"
  }
}

data "aws_iam_policy_document" "canary" {
  # Write results to S3
  statement {
    sid    = "S3ArtifactWrite"
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:GetBucketLocation",
      "s3:ListAllMyBuckets",
    ]
    resources = [
      aws_s3_bucket.artifacts.arn,
      "${aws_s3_bucket.artifacts.arn}/*",
    ]
  }

  # CloudWatch Logs — canary execution logs
  statement {
    sid    = "CloudWatchLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["arn:aws:logs:*:*:*"]
  }

  # Publish canary metrics
  statement {
    sid     = "CloudWatchMetrics"
    effect  = "Allow"
    actions = ["cloudwatch:PutMetricData"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "cloudwatch:namespace"
      values   = ["CloudWatchSynthetics"]
    }
  }

  # X-Ray tracing
  statement {
    sid    = "XRay"
    effect = "Allow"
    actions = [
      "xray:PutTraceSegments",
      "xray:GetSamplingRules",
      "xray:GetSamplingTargets",
      "xray:GetSamplingStatisticSummaries",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "canary" {
  name   = "${var.project}-${var.env}-canary-policy"
  role   = aws_iam_role.canary.id
  policy = data.aws_iam_policy_document.canary.json
}

################################################################################
# Canary Script — zip the full canary/ directory
#
# CloudWatch Synthetics requires this structure inside the zip:
#   nodejs/
#   └── node_modules/
#       ├── canary.js              ← entry point (handler = "canary.handler")
#       ├── config/env.js
#       ├── config/syntheticsConfig.js
#       ├── lib/http.js
#       ├── data/formData.js
#       └── flows/*.js
#
# Drop your actual flow files into:
#   modules/synthetics/canary/nodejs/node_modules/flows/
################################################################################

data "archive_file" "canary" {
  type        = "zip"
  source_dir  = "${path.module}/canary"
  output_path = "${path.module}/canary.zip"
}

################################################################################
# CloudWatch Synthetics Canary
################################################################################

resource "aws_synthetics_canary" "this" {
  name                 = "${var.project}-${var.env}-api-canary"
  artifact_s3_location = "s3://${aws_s3_bucket.artifacts.bucket}/canary-results/"
  execution_role_arn   = aws_iam_role.canary.arn
  handler              = "canary.handler"
  zip_file             = filebase64(data.archive_file.canary.output_path)
  runtime_version      = var.runtime_version
  start_canary         = true

  environment_variables = merge(
    {
      BASE_URL       = var.base_url
      LOGIN_EMAIL    = var.login_email
      LOGIN_PASSWORD = var.login_password
    },
    var.extra_env_vars
  )

  schedule {
    expression          = "rate(${var.schedule_rate_minutes} minutes)"
    duration_in_seconds = 0 # run indefinitely
  }

  # Keep results for 91 days (matches S3 lifecycle)
  success_retention_period = 91
  failure_retention_period = 91

  tags = {
    Name = "${var.project}-${var.env}-api-canary"
  }

  depends_on = [
    aws_s3_bucket_public_access_block.artifacts,
    aws_iam_role_policy.canary,
  ]
}

################################################################################
# CloudWatch Alarm — alert on canary failures
################################################################################

resource "aws_cloudwatch_metric_alarm" "canary_failed" {
  alarm_name          = "${var.project}-${var.env}-canary-failed"
  alarm_description   = "API canary is failing — endpoint may be down or returning errors"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2     # fail 2 consecutive runs before alerting
  metric_name         = "SuccessPercent"
  namespace           = "CloudWatchSynthetics"
  period              = var.schedule_rate_minutes * 60
  statistic           = "Average"
  threshold           = 100 # any failure triggers alarm
  treat_missing_data  = "breaching"

  dimensions = {
    CanaryName = aws_synthetics_canary.this.name
  }

  tags = {
    Name = "${var.project}-${var.env}-canary-failed"
  }
}
