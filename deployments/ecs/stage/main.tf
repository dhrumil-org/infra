data "aws_caller_identity" "current" {}

# Pull Bedrock IDs dynamically from bedrock/stage remote state
data "terraform_remote_state" "bedrock_stage" {
  backend = "s3"
  config = {
    bucket = "vocuone-terraform-state-499290259511"
    key    = "bedrock/stage/terraform.tfstate"
    region = "us-east-1"
  }
}

################################################################################
# Shared env vars passed to both the initial ECS task def and CodePipeline
# redeployments via taskdef.json template
################################################################################


locals {
  # Build full ECR image URI dynamically from account ID + region
  container_image = "${var.aws_account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/${var.container_image}"

  app_environment_variables = [
    {
      name  = "SPRING_PROFILES_ACTIVE"
      value = var.spring_profile
    },
    {
      name  = "AWS_REGION"
      value = var.aws_region
    },
    {
      name  = "aws.region"
      value = var.aws_region
    },
    {
      name  = "aws.secrets.db-secret-name"
      value = var.app_db_secret_name
    },
    {
      name  = "APP_EMAIL_REDIRECT_URL"
      value = var.app_email_redirect_url
    },
    {
      name  = "APP_CORS_ALLOWEDORIGINPATTERNS"
      value = var.app_cors_allowed_origins
    },
    {
      name  = "APP_COOKIE_DOMAIN"
      value = ""
    },
    {
      name  = "APP_COOKIE_SECURE"
      value = "true"
    },
    {
      name  = "APP_COOKIE_SAMESITE"
      value = "Lax"
    },
    {
      name  = "APP_COOKIE_ACCESSTTL"
      value = "PT1H"
    },
    {
      name  = "APP_COOKIE_REFRESHTTL"
      value = "P7D"
    },
    {
      name  = "GOOGLE_CALENDAR_ENABLED"
      value = "false"
    },
    {
      name  = "AWS_S3_BUCKET_NAME"
      value = data.terraform_remote_state.bedrock_stage.outputs.primary_bucket_name
    },
    {
      name  = "BEDROCK_KB_ID"
      value = data.terraform_remote_state.bedrock_stage.outputs.knowledge_base_id
    },
    {
      name  = "BEDROCK_DATASOURCE_ID"
      value = data.terraform_remote_state.bedrock_stage.outputs.primary_data_source_id
    },
    {
      name  = "BEDROCK_AGENT_ID"
      value = data.terraform_remote_state.bedrock_stage.outputs.agent_id
    },
    {
      name  = "BEDROCK_AGENT_ALIAS_ID"
      value = data.terraform_remote_state.bedrock_stage.outputs.agent_alias_id
    },
  ]
}

################################################################################
# CloudTrail — API audit trail (HIPAA requirement)
################################################################################

module "cloudtrail" {
  source = "../../../modules/cloudtrail"

  env            = var.env
  project        = var.project
  aws_region     = var.aws_region
  aws_account_id = var.aws_account_id
  kms_key_arn    = module.kms.key_arns["logs"]
}
module "synthetics" {
  source = "../../../modules/synthetics"

  env     = var.env
  project = var.project

  base_url              = "https://${var.api_domain}"
  login_email           = var.canary_login_email
  login_password        = var.canary_login_password
  schedule_rate_minutes = var.canary_schedule_rate_minutes
}
################################################################################
# KMS Keys — Encryption at rest (HIPAA)
################################################################################

module "kms" {
  source = "../../../modules/kms"

  env     = var.env
  project = var.project

  keys = {
    logs = {
      description = "KMS key for CloudWatch Logs + CloudTrail encryption"
      policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
          {
            Sid    = "AllowKeyManagement"
            Effect = "Allow"
            Principal = {
              AWS = "arn:aws:iam::${var.aws_account_id}:root"
            }
            Action   = "kms:*"
            Resource = "*"
          },
          {
            Sid    = "AllowCloudWatchLogs"
            Effect = "Allow"
            Principal = {
              Service = "logs.${var.aws_region}.amazonaws.com"
            }
            Action = [
              "kms:Encrypt*",
              "kms:Decrypt*",
              "kms:ReEncrypt*",
              "kms:GenerateDataKey*",
              "kms:Describe*"
            ]
            Resource = "*"
            Condition = {
              ArnLike = {
                "kms:EncryptionContext:aws:logs:arn" = "arn:aws:logs:${var.aws_region}:${var.aws_account_id}:log-group:*"
              }
            }
          },
          {
            Sid    = "AllowCloudTrail"
            Effect = "Allow"
            Principal = {
              Service = "cloudtrail.amazonaws.com"
            }
            Action = [
              "kms:GenerateDataKey*",
              "kms:DescribeKey"
            ]
            Resource = "*"
            Condition = {
              StringEquals = {
                "aws:SourceArn" = "arn:aws:cloudtrail:${var.aws_region}:${var.aws_account_id}:trail/${var.project}-${var.env}-trail"
              }
            }
          },
          {
            Sid    = "AllowCloudTrailDecrypt"
            Effect = "Allow"
            Principal = {
              AWS = "arn:aws:iam::${var.aws_account_id}:root"
            }
            Action   = "kms:Decrypt"
            Resource = "*"
            Condition = {
              "Null" = {
                "kms:EncryptionContext:aws:cloudtrail:arn" = "false"
              }
            }
          }
        ]
      })
    }
    ecr = {
      description = "KMS key for ECR image encryption"
    }
    rds = {
      description = "KMS key for RDS storage encryption"
      policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
          {
            Sid       = "AllowKeyManagement"
            Effect    = "Allow"
            Principal = { AWS = "arn:aws:iam::${var.aws_account_id}:root" }
            Action    = "kms:*"
            Resource  = "*"
          },
          {
            Sid       = "AllowRDS"
            Effect    = "Allow"
            Principal = { Service = "rds.amazonaws.com" }
            Action    = ["kms:Decrypt", "kms:GenerateDataKey", "kms:CreateGrant", "kms:DescribeKey"]
            Resource  = "*"
          }
        ]
      })
    }
    secrets = {
      description = "KMS key for Secrets Manager encryption"
      policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
          {
            Sid       = "AllowKeyManagement"
            Effect    = "Allow"
            Principal = { AWS = "arn:aws:iam::${var.aws_account_id}:root" }
            Action    = "kms:*"
            Resource  = "*"
          },
          {
            Sid       = "AllowSecretsManager"
            Effect    = "Allow"
            Principal = { Service = "secretsmanager.amazonaws.com" }
            Action    = ["kms:Decrypt", "kms:GenerateDataKey", "kms:CreateGrant", "kms:DescribeKey"]
            Resource  = "*"
          }
        ]
      })
    }
    backup = {
      description = "KMS key for AWS Backup vault + SNS encryption"
      policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
          {
            Sid       = "AllowKeyManagement"
            Effect    = "Allow"
            Principal = { AWS = "arn:aws:iam::${var.aws_account_id}:root" }
            Action    = "kms:*"
            Resource  = "*"
          },
          {
            Sid       = "AllowBackupService"
            Effect    = "Allow"
            Principal = { Service = "backup.amazonaws.com" }
            Action    = ["kms:Decrypt", "kms:GenerateDataKey", "kms:CreateGrant", "kms:DescribeKey"]
            Resource  = "*"
          },
        ]
      })
    }
  }
}

################################################################################
# VPC — Network foundation
################################################################################

module "vpc" {
  source = "../../../modules/vpc"

  env     = var.env
  project = var.project

  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  availability_zones   = var.availability_zones
  nat_gateway_count    = 1

  flow_logs_kms_key_arn = module.kms.key_arns["logs"]
}

################################################################################
# Security Groups
################################################################################

module "security_groups" {
  source = "../../../modules/security-groups"

  env     = var.env
  project = var.project

  vpc_id         = module.vpc.vpc_id
  vpc_cidr       = var.vpc_cidr
  container_port = var.container_port
}

################################################################################
# ECR — Container Registry
################################################################################

module "ecr" {
  source = "../../../modules/ecr"

  env     = var.env
  project = var.project

  repository_name = "app"
  kms_key_arn     = module.kms.key_arns["ecr"]
}

################################################################################
# ALB — Application Load Balancer
################################################################################

module "alb" {
  source = "../../../modules/alb"

  env     = var.env
  project = var.project

  vpc_id              = module.vpc.vpc_id
  public_subnet_ids   = module.vpc.public_subnet_ids
  security_group_id   = module.security_groups.alb_security_group_id
  acm_certificate_arn = var.acm_certificate_arn
  container_port      = var.container_port
  health_check_path   = var.health_check_path
}

################################################################################
# ECS Cluster — EC2 with ASG + Capacity Provider
################################################################################

module "ecs_cluster" {
  source = "../../../modules/ecs-cluster"

  env     = var.env
  project = var.project

  private_subnet_ids    = module.vpc.private_subnet_ids
  ecs_security_group_id = module.security_groups.ecs_security_group_id
  instance_type         = var.instance_type
  asg_min_size          = var.asg_min_size
  asg_max_size          = var.asg_max_size
  asg_desired_capacity  = var.asg_desired_capacity
}

################################################################################
# ECS Service — Task Definition + Auto Scaling
################################################################################

module "ecs_service" {
  source = "../../../modules/ecs-service"

  depends_on = [module.alb]

  env     = var.env
  project = var.project

  aws_region             = var.aws_region
  service_name           = "app"
  ecs_cluster_id         = module.ecs_cluster.cluster_id
  ecs_cluster_name       = module.ecs_cluster.cluster_name
  capacity_provider_name = module.ecs_cluster.capacity_provider_name
  private_subnet_ids     = module.vpc.private_subnet_ids
  ecs_security_group_id  = module.security_groups.ecs_security_group_id
  target_group_arn       = module.alb.blue_target_group_arn
  container_image        = local.container_image
  container_port         = var.container_port
  task_cpu               = var.task_cpu
  task_memory            = var.task_memory
  desired_count          = 1
  log_kms_key_arn        = module.kms.key_arns["logs"]

  # Env vars the Spring Boot app reads at startup (shared with CodePipeline)
  environment_variables = local.app_environment_variables

  # Auto Scaling
  autoscaling_min_capacity = 1
  autoscaling_max_capacity = 4
  cpu_target_value         = 70
  memory_target_value      = 80
  scale_in_cooldown        = 300
  scale_out_cooldown       = 120

  kms_key_arns  = [module.kms.key_arns["logs"], module.kms.key_arns["ecr"], module.kms.key_arns["secrets"]]
  secrets_arns  = var.task_secret_arns

  # Secrets the app reads at runtime via AWS SDK (not injected as env vars)
  task_secret_arns = var.task_secret_arns

  # Container health check (liveness probe) — restarts container if app hangs
  container_health_check = {
    command     = ["CMD-SHELL", "cat < /dev/tcp/localhost/8080 || exit 1"]
    interval    = 30
    timeout     = 5
    retries     = 3
    startPeriod = 120
  }
}

################################################################################
# RDS — PostgreSQL database in private subnet
################################################################################

module "rds" {
  source = "../../../modules/rds"

  env            = var.env
  project        = var.project
  aws_region     = var.aws_region
  aws_account_id = var.aws_account_id

  # Network
  vpc_id                = module.vpc.vpc_id
  private_subnet_ids    = module.vpc.private_subnet_ids
  ecs_security_group_id = module.security_groups.ecs_security_group_id

  # Database config
  engine_version    = var.db_engine_version
  instance_class    = var.db_instance_class
  allocated_storage = var.db_allocated_storage
  db_name           = var.db_name
  master_username   = var.db_master_username

  # HA and backups
  multi_az                = var.db_multi_az
  backup_retention_period = var.db_backup_retention_period

  # Encryption
  rds_kms_key_arn     = module.kms.key_arns["rds"]
  secrets_kms_key_arn = module.kms.key_arns["secrets"]

  # Deletion protection (false for stage, true for prod)
  deletion_protection = var.db_deletion_protection
  skip_final_snapshot = var.db_skip_final_snapshot
  apply_immediately   = var.db_apply_immediately

  # App-facing secret (matches Spring Boot RdsIamDataSourceConfig expectations)
  create_app_secret = true
  app_secret_name   = var.app_db_secret_name
  app_db_username   = var.app_db_username

  # Secrets Manager — 0 for stage (clean destroy/recreate), 7+ for prod
  recovery_window_in_days = var.secrets_recovery_window_in_days
}

################################################################################
# Attach DB access policy to ECS task role so the app can read DB credentials
################################################################################

resource "aws_iam_role_policy_attachment" "ecs_task_db_access" {
  role       = module.ecs_service.task_role_name
  policy_arn = module.rds.db_access_policy_arn
}

################################################################################
# CodeDeploy — Canary Deployments
################################################################################

module "codedeploy" {
  source = "../../../modules/codedeploy"

  env     = var.env
  project = var.project

  service_name           = "app"
  ecs_cluster_name       = module.ecs_cluster.cluster_name
  ecs_service_name       = module.ecs_service.service_name
  https_listener_arn     = module.alb.https_listener_arn
  test_listener_arn      = module.alb.test_listener_arn
  blue_target_group_name = module.alb.blue_target_group_name
  green_target_group_name = module.alb.green_target_group_name
}

################################################################################
# CI/CD Pipeline — Triggered by ECR image push
################################################################################

module "cicd" {
  source = "../../../modules/cicd"

  env            = var.env
  project        = var.project
  aws_account_id = var.aws_account_id
  aws_region     = var.aws_region

  ecr_repository_name = module.ecr.repository_name
  ecr_repository_arn  = module.ecr.repository_arn
  ecr_image_tag       = "latest"

  codedeploy_app_name              = module.codedeploy.app_name
  codedeploy_deployment_group_name = module.codedeploy.deployment_group_name

  ecs_task_role_arns = [
    module.ecs_service.task_execution_role_arn,
    module.ecs_service.task_role_arn,
  ]

  # Task definition template values (same env vars as initial ECS task def)
  task_family           = "${var.project}-${var.env}-app"
  task_cpu              = tostring(var.task_cpu)
  task_memory           = tostring(var.task_memory)
  execution_role_arn    = module.ecs_service.task_execution_role_arn
  task_role_arn         = module.ecs_service.task_role_arn
  container_name        = "app"
  container_port        = var.container_port
  log_group             = module.ecs_service.log_group_name
  environment_variables = local.app_environment_variables
  secrets               = []
}
################################################################################
# API Gateway — HTTP API in front of ALB
#
# Client → api.stage.vocuone.ai → API Gateway → ALB → ECS
# Keeps existing blue/green via CodeDeploy on the ALB intact.
#
# DNS: set create_route53_record = true if you want Terraform to manage
# the Route53 alias. Otherwise, manually point api_domain at:
#   module.api_gateway.custom_domain_target
################################################################################

resource "random_password" "gateway_secret" {
  length  = 32
  special = false
}

module "api_gateway" {
  source = "../../../modules/api-gateway"

  env     = var.env
  project = var.project

  api_domain          = var.api_domain
  alb_dns_name        = module.alb.alb_dns_name
  acm_certificate_arn = var.acm_certificate_arn
  kms_key_arn         = module.kms.key_arns["logs"]

  gateway_secret       = random_password.gateway_secret.result
  cors_allowed_origins = split(",", var.app_cors_allowed_origins)

  # Throttling — adjust based on expected traffic
  throttling_burst_limit = 500
  throttling_rate_limit  = 100

  # Route53 management (manual DNS cutover recommended for first rollout)
  create_route53_record = false
  route53_zone_id       = ""
}
################################################################################
# AWS Backup — S3 + RDS daily/monthly snapshots (HIPAA)
################################################################################

module "backup" {
  source = "../../../modules/backup"

  env     = var.env
  project = var.project

  kms_key_arn = module.kms.key_arns["backup"]

  # S3 buckets that hold patient/user data (from Bedrock stage deployment)
  s3_bucket_arns = [
    "arn:aws:s3:::${data.terraform_remote_state.bedrock_stage.outputs.primary_bucket_name}",
    "arn:aws:s3:::${data.terraform_remote_state.bedrock_stage.outputs.secondary_bucket_name}",
    "arn:aws:s3:::${data.terraform_remote_state.bedrock_stage.outputs.multimodal_bucket_name}",
  ]

  # RDS PostgreSQL instance
  rds_arn = module.rds.db_instance_arn
}

################################################################################
# Outputs
################################################################################

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "ecs_task_role_name" {
  description = "ECS task role name — used by other deployments to attach policies"
  value       = module.ecs_service.task_role_name
}

output "ecs_task_role_arn" {
  description = "ECS task role ARN"
  value       = module.ecs_service.task_role_arn
}

output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = module.ecs_cluster.cluster_name
}

output "ecs_service_name" {
  description = "ECS service name"
  value       = module.ecs_service.service_name
}

output "alb_dns_name" {
  description = "ALB DNS name — access your app here"
  value       = module.alb.alb_dns_name
}

output "ecr_repository_url" {
  description = "ECR repository URL — push images here"
  value       = module.ecr.repository_url
}

output "codedeploy_app_name" {
  description = "CodeDeploy application name"
  value       = module.codedeploy.app_name
}

output "codedeploy_deployment_group" {
  description = "CodeDeploy deployment group name"
  value       = module.codedeploy.deployment_group_name
}

output "pipeline_name" {
  description = "CodePipeline name"
  value       = module.cicd.pipeline_name
}
################################################################################
# API Gateway Outputs
################################################################################

output "api_gateway_endpoint" {
  description = "Default API Gateway URL — test here before DNS cutover"
  value       = module.api_gateway.api_endpoint
}

output "api_gateway_custom_domain_target" {
  description = "Point your Route53 alias (api.stage.vocuone.ai) at this target"
  value       = module.api_gateway.custom_domain_target
}

output "api_gateway_custom_domain_zone_id" {
  description = "Hosted zone ID for the Route53 alias (pair with the target above)"
  value       = module.api_gateway.custom_domain_hosted_zone_id





}
################################################################################
# RDS Outputs
################################################################################

output "rds_endpoint" {
  description = "RDS instance endpoint (host:port)"
  value       = module.rds.db_instance_endpoint
}

output "rds_address" {
  description = "RDS instance hostname"
  value       = module.rds.db_instance_address
}

output "rds_port" {
  description = "RDS instance port"
  value       = module.rds.db_instance_port
}

output "rds_db_name" {
  description = "Initial database name"
  value       = module.rds.db_name
}

output "rds_secret_arn" {
  description = "ARN of Secrets Manager secret with DB credentials"
  value       = module.rds.db_secret_arn
}

output "rds_secret_name" {
  description = "Name of Secrets Manager secret (for AWS CLI lookup)"
  value       = module.rds.db_secret_name
}

output "app_db_secret_name" {
  description = "App-facing DB secret (Spring Boot reads from here)"
  value       = module.rds.app_db_secret_name
}

output "db_access_policy_arn" {
  description = "IAM policy ARN for DB access — attach to IAM users"
  value       = module.rds.db_access_policy_arn
}

output "db_access_role_arn" {
  description = "IAM role ARN for DB access — can be assumed by users"
  value       = module.rds.db_access_role_arn
}

################################################################################
# CloudTrail Outputs
################################################################################

output "cloudtrail_arn" {
  description = "CloudTrail trail ARN"
  value       = module.cloudtrail.trail_arn
}

output "cloudtrail_bucket" {
  description = "S3 bucket for CloudTrail logs (7-year retention)"
  value       = module.cloudtrail.log_bucket_name
}

################################################################################
# AWS Backup Outputs
################################################################################

output "backup_vault_name" {
  description = "AWS Backup vault name"
  value       = module.backup.vault_name
}

output "backup_vault_arn" {
  description = "AWS Backup vault ARN"
  value       = module.backup.vault_arn
}

