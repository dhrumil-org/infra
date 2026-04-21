################################################################################
# S3 — Canary artifact storage (results, logs, screenshots)
################################################################################

resource "aws_s3_bucket" "artifacts" {
  bucket = "${var.project}-${var.env}-canary-artifacts"
  tags   = { Name = "${var.project}-${var.env}-canary-artifacts" }
}

resource "aws_s3_bucket_versioning" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
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
    id     = "expire-results"
    status = "Enabled"
    filter {}
    expiration { days = 91 }
  }
}

################################################################################
# IAM Role — Synthetics Lambda execution role
################################################################################

resource "aws_iam_role" "canary" {
  name = "${var.project}-${var.env}-canary-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  tags = { Name = "${var.project}-${var.env}-canary-role" }
}

resource "aws_iam_role_policy" "canary" {
  name = "${var.project}-${var.env}-canary-policy"
  role = aws_iam_role.canary.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "S3Artifacts"
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:GetObject", "s3:GetBucketLocation", "s3:ListAllMyBuckets"]
        Resource = [aws_s3_bucket.artifacts.arn, "${aws_s3_bucket.artifacts.arn}/*"]
      },
      {
        Sid      = "Logs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Sid      = "Metrics"
        Effect   = "Allow"
        Action   = ["cloudwatch:PutMetricData"]
        Resource = "*"
        Condition = { StringEquals = { "cloudwatch:namespace" = "CloudWatchSynthetics" } }
      },
      {
        Sid      = "XRay"
        Effect   = "Allow"
        Action   = ["xray:PutTraceSegments", "xray:GetSamplingRules", "xray:GetSamplingTargets"]
        Resource = "*"
      }
    ]
  })
}

################################################################################
# Bootstrap zip — placeholder on first apply only
# Your GitHub Actions replaces this with the real script via update-canary
################################################################################

data "archive_file" "bootstrap" {
  type        = "zip"
  output_path = "${path.module}/bootstrap.zip"
  source {
    filename = "nodejs/node_modules/index.js"
    content  = "exports.handler = async () => { console.log('bootstrap'); };"
  }
}

################################################################################
# Canary
################################################################################

resource "aws_synthetics_canary" "this" {
  name                 = "${var.project}-${var.env}-api-canary"
  artifact_s3_location = "s3://${aws_s3_bucket.artifacts.bucket}/"
  execution_role_arn   = aws_iam_role.canary.arn
  handler              = "index.handler"
  runtime_version      = var.runtime_version
  start_canary         = true

  zip_file = filebase64(data.archive_file.bootstrap.output_path)

  environment_variables = {
    BASE_URL       = var.base_url
    LOGIN_EMAIL    = var.login_email
    LOGIN_PASSWORD = var.login_password
  }

  schedule {
    expression          = "rate(${var.schedule_rate_minutes} minutes)"
    duration_in_seconds = 0
  }

  success_retention_period = 31
  failure_retention_period = 31

  run_config {
    timeout_in_seconds    = 840
    memory_in_mb          = 960
    active_tracing        = false
    ephemeral_storage     = 1024
  }

  tags = { Name = "${var.project}-${var.env}-api-canary" }

  # GitHub Actions owns script updates — Terraform never touches the zip again
  lifecycle {
    ignore_changes = [zip_file, s3_bucket, s3_key, s3_version]
  }

  depends_on = [aws_s3_bucket_public_access_block.artifacts, aws_iam_role_policy.canary]
}

################################################################################
# CloudWatch Alarm — fires if canary fails
################################################################################

resource "aws_cloudwatch_metric_alarm" "canary_failed" {
  alarm_name          = "${var.project}-${var.env}-canary-failed"
  alarm_description   = "API canary failing"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "SuccessPercent"
  namespace           = "CloudWatchSynthetics"
  period              = var.schedule_rate_minutes * 60
  statistic           = "Average"
  threshold           = 100
  treat_missing_data  = "breaching"
  dimensions          = { CanaryName = aws_synthetics_canary.this.name }
  tags                = { Name = "${var.project}-${var.env}-canary-failed" }
}
