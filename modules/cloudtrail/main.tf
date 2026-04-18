################################################################################
# S3 Bucket — CloudTrail log storage (7-year retention via Glacier)
################################################################################

resource "aws_s3_bucket" "logs" {
  bucket = "${var.project}-${var.env}-cloudtrail-${var.aws_account_id}"

  tags = {
    Name = "${var.project}-${var.env}-cloudtrail-logs"
  }
}

resource "aws_s3_bucket_versioning" "logs" {
  bucket = aws_s3_bucket.logs.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "logs" {
  bucket                  = aws_s3_bucket.logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    id     = "archive-to-glacier"
    status = "Enabled"

    filter {}

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    transition {
      days          = 365
      storage_class = "DEEP_ARCHIVE"
    }

    expiration {
      days = 2557 # 7 years
    }
  }
}

################################################################################
# S3 Bucket Policy — allow CloudTrail to write logs
################################################################################

resource "aws_s3_bucket_policy" "cloudtrail" {
  bucket = aws_s3_bucket.logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSCloudTrailAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.logs.arn
        Condition = {
          StringEquals = {
            "aws:SourceArn" = "arn:aws:cloudtrail:${var.aws_region}:${var.aws_account_id}:trail/${var.project}-${var.env}-trail"
          }
        }
      },
      {
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.logs.arn}/AWSLogs/${var.aws_account_id}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl"  = "bucket-owner-full-control"
            "aws:SourceArn" = "arn:aws:cloudtrail:${var.aws_region}:${var.aws_account_id}:trail/${var.project}-${var.env}-trail"
          }
        }
      }
    ]
  })
}

################################################################################
# CloudWatch Log Group — real-time log delivery for alerts
################################################################################

resource "aws_cloudwatch_log_group" "cloudtrail" {
  name              = "/cloudtrail/${var.project}-${var.env}"
  retention_in_days = 365
  kms_key_id        = var.kms_key_arn

  tags = {
    Name = "${var.project}-${var.env}-cloudtrail-logs"
  }
}

################################################################################
# IAM Role — CloudTrail → CloudWatch Logs delivery
################################################################################

resource "aws_iam_role" "cloudtrail_cw" {
  name = "${var.project}-${var.env}-cloudtrail-cw-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "cloudtrail.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = {
    Name = "${var.project}-${var.env}-cloudtrail-cw-role"
  }
}

resource "aws_iam_role_policy" "cloudtrail_cw" {
  name = "${var.project}-${var.env}-cloudtrail-cw-policy"
  role = aws_iam_role.cloudtrail_cw.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogStream",
        "logs:PutLogEvents",
      ]
      Resource = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
    }]
  })
}

################################################################################
# CloudTrail — multi-region, all management + S3 data events
################################################################################

resource "aws_cloudtrail" "this" {
  name                          = "${var.project}-${var.env}-trail"
  s3_bucket_name                = aws_s3_bucket.logs.id
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true
  kms_key_id                    = var.kms_key_arn

  cloud_watch_logs_group_arn = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
  cloud_watch_logs_role_arn  = aws_iam_role.cloudtrail_cw.arn

  # Log all management events (IAM, EC2, RDS, etc.)
  event_selector {
    read_write_type           = "All"
    include_management_events = true
  }

  tags = {
    Name = "${var.project}-${var.env}-trail"
  }

  depends_on = [aws_s3_bucket_policy.cloudtrail]
}
