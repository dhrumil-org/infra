################################################################################
# DB Subnet Group (private subnets only)
################################################################################

resource "aws_db_subnet_group" "this" {
  name       = "${var.project}-${var.env}-db-subnet-group"
  subnet_ids = var.private_subnet_ids

  tags = {
    Name = "${var.project}-${var.env}-db-subnet-group"
  }
}

################################################################################
# DB Security Group — Only allow from ECS tasks
################################################################################

resource "aws_security_group" "rds" {
  name_prefix = "${var.project}-${var.env}-rds-"
  description = "Security group for RDS PostgreSQL"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.project}-${var.env}-rds-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "rds_from_ecs" {
  security_group_id            = aws_security_group.rds.id
  description                  = "PostgreSQL from ECS tasks"
  from_port                    = var.db_port
  to_port                      = var.db_port
  ip_protocol                  = "tcp"
  referenced_security_group_id = var.ecs_security_group_id
}

################################################################################
# DB Parameter Group — HIPAA-compliant defaults
################################################################################

resource "aws_db_parameter_group" "this" {
  name_prefix = "${var.project}-${var.env}-pg16-"
  family      = "postgres16"
  description = "Parameter group for ${var.project}-${var.env}"

  # HIPAA: Log all connections and disconnections for audit
  parameter {
    name  = "log_connections"
    value = "1"
  }

  parameter {
    name  = "log_disconnections"
    value = "1"
  }

  # HIPAA: Force SSL/TLS for all connections
  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }

  tags = {
    Name = "${var.project}-${var.env}-pg16-params"
  }

  lifecycle {
    create_before_destroy = true
  }
}

################################################################################
# Auto-generate strong DB master password
################################################################################

resource "random_password" "master" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

################################################################################
# Secrets Manager — Store DB credentials
################################################################################

resource "aws_secretsmanager_secret" "db" {
  name                    = "${var.project}/${var.env}/rds/credentials"
  description             = "RDS master credentials for ${var.project}-${var.env}"
  kms_key_id              = var.secrets_kms_key_arn
  recovery_window_in_days = var.recovery_window_in_days

  tags = {
    Name = "${var.project}-${var.env}-rds-credentials"
  }
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id
  secret_string = jsonencode({
    username = var.master_username
    password = random_password.master.result
    engine   = "postgres"
    host     = aws_db_instance.this.address
    port     = aws_db_instance.this.port
    dbname   = var.db_name
  })
}

################################################################################
# Secrets Manager — App-facing secret (schema expected by Spring Boot app)
# Keys: DB_USERNAME, DATASOURCE_URL — read by RdsIamDataSourceConfig
################################################################################

resource "aws_secretsmanager_secret" "app_db" {
  count = var.create_app_secret ? 1 : 0

  name                    = var.app_secret_name
  description             = "DB credentials for ${var.project}-${var.env} application (IAM auth schema)"
  kms_key_id              = var.secrets_kms_key_arn
  recovery_window_in_days = var.recovery_window_in_days

  tags = {
    Name = "${var.project}-${var.env}-app-db-secret"
  }
}

resource "aws_secretsmanager_secret_version" "app_db" {
  count = var.create_app_secret ? 1 : 0

  secret_id = aws_secretsmanager_secret.app_db[0].id
  secret_string = jsonencode({
    DB_USERNAME   = var.app_db_username
    DATASOURCE_URL = "jdbc:postgresql://${aws_db_instance.this.address}:${aws_db_instance.this.port}/${var.db_name}"
  })

  lifecycle {
    ignore_changes = [secret_string]
  }
}

################################################################################
# CloudWatch Log Groups — Pre-created for HIPAA encryption + retention
#
# Background: RDS auto-creates these log groups on first export with the
# AWS-owned default key and no retention. That fails two HIPAA controls:
#   - §164.312(a)(2)(iv): want a key in our key policy domain
#   - §164.530(j)(2): 6+ year retention on PHI-bearing audit records
#     (postgresql logs contain query text → can leak PHI via WHERE clauses,
#      error messages, etc.)
#
# Pre-creating them with our `logs` CMK + 7-year retention closes both gaps.
# The aws_db_instance below declares depends_on so RDS finds these groups
# already present and reuses them rather than auto-creating unencrypted ones.
#
# RDS log group naming convention: /aws/rds/instance/<db-identifier>/<log-type>
#
# Migration note: if these groups already exist in AWS (RDS auto-created them
# before this module change), the parent stack must use `import` blocks to
# claim ownership before `terraform apply` — otherwise apply fails with
# ResourceAlreadyExistsException.
################################################################################

resource "aws_cloudwatch_log_group" "postgresql" {
  name              = "/aws/rds/instance/${var.project}-${var.env}-db/postgresql"
  retention_in_days = var.log_retention_in_days
  kms_key_id        = var.logs_kms_key_arn

  tags = {
    Name = "${var.project}-${var.env}-rds-postgresql-logs"
  }
}

resource "aws_cloudwatch_log_group" "upgrade" {
  name              = "/aws/rds/instance/${var.project}-${var.env}-db/upgrade"
  retention_in_days = var.log_retention_in_days
  kms_key_id        = var.logs_kms_key_arn

  tags = {
    Name = "${var.project}-${var.env}-rds-upgrade-logs"
  }
}

################################################################################
# RDS Instance — PostgreSQL 16, HIPAA compliant
################################################################################

resource "aws_db_instance" "this" {
  identifier = "${var.project}-${var.env}-db"

  # Engine
  engine                = "postgres"
  engine_version        = var.engine_version
  instance_class        = var.instance_class
  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = "gp3"

  # Database
  db_name  = var.db_name
  username = var.master_username
  password = random_password.master.result
  port     = var.db_port

  # Network
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false
  multi_az               = var.multi_az

  # Parameters
  parameter_group_name = aws_db_parameter_group.this.name

  # HIPAA: Encryption at rest
  storage_encrypted = true
  kms_key_id        = var.rds_kms_key_arn

  # HIPAA: Backups and point-in-time recovery
  backup_retention_period = var.backup_retention_period
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:04:00-sun:05:00"
  copy_tags_to_snapshot   = true
  delete_automated_backups = false

  # HIPAA: IAM authentication (dual auth support)
  iam_database_authentication_enabled = true

  # HIPAA: Enhanced monitoring
  monitoring_interval = 60
  monitoring_role_arn = aws_iam_role.rds_monitoring.arn

  # HIPAA: Performance Insights
  performance_insights_enabled          = true
  performance_insights_kms_key_id       = var.rds_kms_key_arn
  performance_insights_retention_period = 7

  # HIPAA: Audit logging
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  # Protect against accidental deletion
  deletion_protection      = var.deletion_protection
  skip_final_snapshot      = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${var.project}-${var.env}-db-final-${formatdate("YYYYMMDD-hhmmss", timestamp())}"

  apply_immediately = var.apply_immediately

  tags = {
    Name = "${var.project}-${var.env}-rds"
  }

  # Pre-created encrypted log groups must exist before RDS starts exporting,
  # otherwise RDS auto-creates unencrypted ones with no retention.
  depends_on = [
    aws_cloudwatch_log_group.postgresql,
    aws_cloudwatch_log_group.upgrade,
  ]

  lifecycle {
    ignore_changes = [
      password,
      final_snapshot_identifier,
    ]
  }
}

################################################################################
# IAM Role for RDS Enhanced Monitoring
################################################################################

resource "aws_iam_role" "rds_monitoring" {
  name = "${var.project}-${var.env}-rds-monitoring-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "monitoring.rds.amazonaws.com"
      }
    }]
  })

  tags = {
    Name = "${var.project}-${var.env}-rds-monitoring-role"
  }
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

################################################################################
# IAM Policy — App DB Access (read/write via Secrets Manager + IAM auth)
################################################################################

resource "aws_iam_policy" "db_access" {
  name        = "${var.project}-${var.env}-rds-access-policy"
  description = "Allows read/write access to the RDS database (via Secrets Manager + IAM DB auth)"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadDBCredentials"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = compact([
          aws_secretsmanager_secret.db.arn,
          var.create_app_secret ? aws_secretsmanager_secret.app_db[0].arn : "",
        ])
      },
      {
        Sid    = "DecryptSecret"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey"
        ]
        Resource = var.secrets_kms_key_arn
      },
      {
        Sid    = "ConnectToDB"
        Effect = "Allow"
        Action = [
          "rds-db:connect"
        ]
        Resource = "arn:aws:rds-db:${var.aws_region}:${var.aws_account_id}:dbuser:${aws_db_instance.this.resource_id}/*"
      },
      {
        Sid    = "DescribeDB"
        Effect = "Allow"
        Action = [
          "rds:DescribeDBInstances",
          "rds:DescribeDBClusters",
          "rds:ListTagsForResource"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Name = "${var.project}-${var.env}-rds-access-policy"
  }
}

################################################################################
# IAM Role — Assumable role for DB access (can be attached to ECS tasks or users)
################################################################################

resource "aws_iam_role" "db_access" {
  name = "${var.project}-${var.env}-rds-access-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ECSTasksAssume"
        Effect = "Allow"
        Action = "sts:AssumeRole"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      },
      {
        Sid    = "IAMUsersAssume"
        Effect = "Allow"
        Action = "sts:AssumeRole"
        Principal = {
          AWS = "arn:aws:iam::${var.aws_account_id}:root"
        }
      }
    ]
  })

  tags = {
    Name = "${var.project}-${var.env}-rds-access-role"
  }
}

resource "aws_iam_role_policy_attachment" "db_access" {
  role       = aws_iam_role.db_access.name
  policy_arn = aws_iam_policy.db_access.arn
}
