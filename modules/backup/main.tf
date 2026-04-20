################################################################################
# AWS Backup — HIPAA-compliant S3 + RDS backup
#
# Vault:   KMS-encrypted, locked (WORM) after 3-day grace
# Daily:   2 AM UTC, 30-day retention  → covers accidental deletes/overwrites
# Monthly: 1st of month 3 AM UTC, 365-day retention → long-term compliance
################################################################################

################################################################################
# IAM Role — AWS Backup service role
################################################################################

data "aws_iam_policy_document" "backup_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["backup.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "backup" {
  name               = "${var.project}-${var.env}-backup-role"
  assume_role_policy = data.aws_iam_policy_document.backup_assume.json

  tags = {
    Name = "${var.project}-${var.env}-backup-role"
  }
}

# AWS managed policies required by AWS Backup
resource "aws_iam_role_policy_attachment" "backup_service" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

resource "aws_iam_role_policy_attachment" "backup_restore" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores"
}

# S3 backup requires explicit S3 data policy
resource "aws_iam_role_policy_attachment" "backup_s3_backup" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/AWSBackupServiceRolePolicyForS3Backup"
}

resource "aws_iam_role_policy_attachment" "backup_s3_restore" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/AWSBackupServiceRolePolicyForS3Restore"
}

################################################################################
# Backup Vault — encrypted with dedicated KMS key
################################################################################

resource "aws_backup_vault" "this" {
  name        = "${var.project}-${var.env}-vault"
  kms_key_arn = var.kms_key_arn

  tags = {
    Name = "${var.project}-${var.env}-vault"
  }
}

# Vault Lock — WORM protection (prevents deletion during retention period)
# 3-day changeable grace period, then locked permanently
resource "aws_backup_vault_lock_configuration" "this" {
  backup_vault_name   = aws_backup_vault.this.name
  changeable_for_days = 3
  min_retention_days  = 7
  max_retention_days  = 366
}

################################################################################
# Backup Plans
################################################################################

resource "aws_backup_plan" "daily" {
  name = "${var.project}-${var.env}-daily"

  rule {
    rule_name         = "daily-30-days"
    target_vault_name = aws_backup_vault.this.name
    schedule          = "cron(0 2 * * ? *)" # 2 AM UTC every day

    start_window_minutes      = 60  # start within 60 min of scheduled time
    completion_window_minutes = 180 # must complete within 3 hours

    lifecycle {
      delete_after = 30 # retain for 30 days
    }

    recovery_point_tags = {
      BackupType = "daily"
      Project    = var.project
      Env        = var.env
    }
  }

  tags = {
    Name = "${var.project}-${var.env}-daily-plan"
  }
}

resource "aws_backup_plan" "monthly" {
  name = "${var.project}-${var.env}-monthly"

  rule {
    rule_name         = "monthly-1-year"
    target_vault_name = aws_backup_vault.this.name
    schedule          = "cron(0 3 1 * ? *)" # 3 AM UTC on 1st of every month

    start_window_minutes      = 60
    completion_window_minutes = 480 # 8 hours (large S3 buckets may take time)

    lifecycle {
      cold_storage_after = 90  # move to cold storage after 90 days (cheaper)
      delete_after       = 365 # retain for 1 year
    }

    recovery_point_tags = {
      BackupType = "monthly"
      Project    = var.project
      Env        = var.env
    }
  }

  tags = {
    Name = "${var.project}-${var.env}-monthly-plan"
  }
}

################################################################################
# Backup Selections — which resources to back up
################################################################################

# Daily backup: all tagged S3 buckets + RDS
resource "aws_backup_selection" "daily_s3" {
  name         = "${var.project}-${var.env}-daily-s3"
  iam_role_arn = aws_iam_role.backup.arn
  plan_id      = aws_backup_plan.daily.id

  resources = var.s3_bucket_arns
}

resource "aws_backup_selection" "daily_rds" {
  count = length(var.rds_arn) > 0 ? 1 : 0

  name         = "${var.project}-${var.env}-daily-rds"
  iam_role_arn = aws_iam_role.backup.arn
  plan_id      = aws_backup_plan.daily.id

  resources = [var.rds_arn]
}

# Monthly backup: same resources, separate plan for long-term retention
resource "aws_backup_selection" "monthly_s3" {
  name         = "${var.project}-${var.env}-monthly-s3"
  iam_role_arn = aws_iam_role.backup.arn
  plan_id      = aws_backup_plan.monthly.id

  resources = var.s3_bucket_arns
}

resource "aws_backup_selection" "monthly_rds" {
  count = length(var.rds_arn) > 0 ? 1 : 0

  name         = "${var.project}-${var.env}-monthly-rds"
  iam_role_arn = aws_iam_role.backup.arn
  plan_id      = aws_backup_plan.monthly.id

  resources = [var.rds_arn]
}

################################################################################
# SNS — Backup job failure notifications
################################################################################

resource "aws_sns_topic" "backup_alerts" {
  name              = "${var.project}-${var.env}-backup-alerts"
  kms_master_key_id = var.kms_key_arn

  tags = {
    Name = "${var.project}-${var.env}-backup-alerts"
  }
}

resource "aws_backup_vault_notifications" "this" {
  backup_vault_name   = aws_backup_vault.this.name
  sns_topic_arn       = aws_sns_topic.backup_alerts.arn
  backup_vault_events = ["BACKUP_JOB_FAILED", "RESTORE_JOB_FAILED"]
}

# Allow AWS Backup to publish to SNS
data "aws_iam_policy_document" "sns_backup" {
  statement {
    effect  = "Allow"
    actions = ["SNS:Publish"]
    principals {
      type        = "Service"
      identifiers = ["backup.amazonaws.com"]
    }
    resources = [aws_sns_topic.backup_alerts.arn]
  }
}

resource "aws_sns_topic_policy" "backup_alerts" {
  arn    = aws_sns_topic.backup_alerts.arn
  policy = data.aws_iam_policy_document.sns_backup.json
}
