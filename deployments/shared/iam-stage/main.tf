################################################################################
# IAM — Stage Developer User
#
# Full access to all vocanote-stage-* resources:
#   - ECR (push/pull images)
#   - ECS (describe services, tasks, trigger deployments)
#   - Secrets Manager (read all stage secrets)
#   - Bedrock (invoke agent + KB)
#   - S3 (stage buckets: KB data, pipeline artifacts)
#   - CloudWatch Logs (read stage logs)
#   - CodePipeline / CodeDeploy (trigger deployments)
#   - RDS (describe, connect via IAM auth)
#   - KMS (decrypt stage keys)
#   - SSM (bastion access)
#   - Marketplace (subscribe to Bedrock models)
################################################################################

################################################################################
# Dynamic lookups — no hardcoded IDs
################################################################################

# Resolve AWS account ID from the current caller
data "aws_caller_identity" "current" {}

# Resolve region from the provider (avoids duplicating it in variables)
data "aws_region" "current" {}

# Pull Bedrock agent + KB IDs from the bedrock/stage remote state
data "terraform_remote_state" "bedrock_stage" {
  backend = "s3"
  config = {
    bucket = "vocanote-terraform-state-499290259511"
    key    = "bedrock/stage/terraform.tfstate"
    region = "us-east-1"
  }
}

locals {
  stage_prefix = "${var.project}-stage"
  account_id   = data.aws_caller_identity.current.account_id
  region       = data.aws_region.current.name
  agent_id     = data.terraform_remote_state.bedrock_stage.outputs.agent_id
  kb_id        = data.terraform_remote_state.bedrock_stage.outputs.knowledge_base_id
}

################################################################################
# IAM User
################################################################################

resource "aws_iam_user" "stage_dev" {
  name = "${local.stage_prefix}-developer"

  tags = {
    Project     = var.project
    Environment = "stage"
    ManagedBy   = "terraform"
  }
}

resource "aws_iam_access_key" "stage_dev" {
  user = aws_iam_user.stage_dev.name
}

resource "aws_iam_policy" "stage_dev" {
  name        = "${local.stage_prefix}-developer-policy"
  description = "Full access to all ${var.project} stage resources"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [

      ############################################################################
      # ECR — push/pull stage images
      ############################################################################
      {
        Sid    = "ECR"
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
        ]
        Resource = "*"
      },
      {
        Sid    = "ECRStageRepo"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:DescribeRepositories",
          "ecr:DescribeImages",
          "ecr:ListImages",
          "ecr:GetRepositoryPolicy",
        ]
        Resource = "arn:aws:ecr:${local.region}:${local.account_id}:repository/${local.stage_prefix}-*"
      },

      ############################################################################
      # ECS — describe cluster, services, tasks
      ############################################################################
      {
        Sid    = "ECS"
        Effect = "Allow"
        Action = [
          "ecs:DescribeClusters",
          "ecs:DescribeServices",
          "ecs:DescribeTasks",
          "ecs:DescribeTaskDefinition",
          "ecs:ListClusters",
          "ecs:ListServices",
          "ecs:ListTasks",
          "ecs:ListTaskDefinitions",
          "ecs:RegisterTaskDefinition",
          "ecs:RunTask",
          "ecs:StopTask",
        ]
        Resource = "*"
      },

      ############################################################################
      # Secrets Manager — read all stage secrets
      ############################################################################
      {
        Sid    = "SecretsManagerRead"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
          "secretsmanager:ListSecretVersionIds",
          "secretsmanager:GetResourcePolicy",
        ]
        Resource = [
          "arn:aws:secretsmanager:${local.region}:${local.account_id}:secret:${var.project}/stage/*",
          "arn:aws:secretsmanager:${local.region}:${local.account_id}:secret:${local.stage_prefix}-*",
          "arn:aws:secretsmanager:${local.region}:${local.account_id}:secret:vocanote/stage/*",
        ]
      },
      {
        Sid    = "SecretsManagerList"
        Effect = "Allow"
        Action = [
          "secretsmanager:ListSecrets",
        ]
        Resource = "*"
      },

      ############################################################################
      # Bedrock — invoke stage agent + KB (IDs from remote state)
      ############################################################################
      {
        Sid    = "BedrockAgent"
        Effect = "Allow"
        Action = [
          "bedrock-agent-runtime:InvokeAgent",
          "bedrock-agent-runtime:Retrieve",
          "bedrock-agent-runtime:RetrieveAndGenerate",
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream",
          "bedrock:Retrieve",
          "bedrock:RetrieveAndGenerate",
        ]
        Resource = [
          "arn:aws:bedrock:${local.region}:${local.account_id}:agent/${local.agent_id}",
          "arn:aws:bedrock:${local.region}:${local.account_id}:agent-alias/${local.agent_id}/*",
          "arn:aws:bedrock:${local.region}:${local.account_id}:knowledge-base/${local.kb_id}",
          "arn:aws:bedrock:${local.region}::foundation-model/*",
          "arn:aws:bedrock:*::foundation-model/*",
          "arn:aws:bedrock:*::inference-profile/*",
          "arn:aws:bedrock:${local.region}:${local.account_id}:inference-profile/*",
        ]
      },

      ############################################################################
      # S3 — stage buckets (KB data sources, pipeline artifacts)
      ############################################################################
      {
        Sid    = "S3StageBuckets"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetBucketLocation",
          "s3:GetBucketVersioning",
        ]
        Resource = [
          "arn:aws:s3:::${local.stage_prefix}-*",
          "arn:aws:s3:::${local.stage_prefix}-*/*",
        ]
      },

      ############################################################################
      # CloudWatch Logs — read stage logs
      ############################################################################
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams",
          "logs:GetLogEvents",
          "logs:FilterLogEvents",
          "logs:StartQuery",
          "logs:StopQuery",
          "logs:GetQueryResults",
          "logs:GetLogRecord",
          "logs:TailLogEvents",
        ]
        Resource = [
          "arn:aws:logs:${local.region}:${local.account_id}:log-group:*${local.stage_prefix}*",
          "arn:aws:logs:${local.region}:${local.account_id}:log-group:*stage*:*",
          "arn:aws:logs:${local.region}:${local.account_id}:log-group:/ecs/${local.stage_prefix}-*:*",
          "arn:aws:logs:${local.region}:${local.account_id}:log-group:/ecs/${local.stage_prefix}-*",
        ]
      },

      ############################################################################
      # CodePipeline + CodeDeploy — trigger stage deployments
      ############################################################################
      {
        Sid    = "CodePipeline"
        Effect = "Allow"
        Action = [
          "codepipeline:GetPipeline",
          "codepipeline:GetPipelineState",
          "codepipeline:GetPipelineExecution",
          "codepipeline:ListPipelines",
          "codepipeline:ListPipelineExecutions",
          "codepipeline:StartPipelineExecution",
          "codepipeline:RetryStageExecution",
        ]
        Resource = "arn:aws:codepipeline:${local.region}:${local.account_id}:${local.stage_prefix}-*"
      },
      {
        Sid    = "CodeDeploy"
        Effect = "Allow"
        Action = [
          "codedeploy:GetDeployment",
          "codedeploy:GetDeploymentGroup",
          "codedeploy:GetApplication",
          "codedeploy:ListDeployments",
          "codedeploy:ListDeploymentGroups",
          "codedeploy:CreateDeployment",
          "codedeploy:GetDeploymentConfig",
          "codedeploy:RegisterApplicationRevision",
        ]
        Resource = "*"
      },

      ############################################################################
      # RDS — describe stage DB + IAM auth connect
      ############################################################################
      {
        Sid    = "RDS"
        Effect = "Allow"
        Action = [
          "rds:DescribeDBInstances",
          "rds:DescribeDBClusters",
          "rds:ListTagsForResource",
          "rds-db:connect",
        ]
        Resource = [
          "arn:aws:rds:${local.region}:${local.account_id}:db:${local.stage_prefix}-*",
          "arn:aws:rds-db:${local.region}:${local.account_id}:dbuser:*/*",
        ]
      },

      ############################################################################
      # KMS — decrypt stage secrets and data
      ############################################################################
      {
        Sid    = "KMS"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey",
        ]
        Resource = "*"
        Condition = {
          StringLike = {
            "kms:RequestAlias" = "alias/${local.stage_prefix}-*"
          }
        }
      },

      ############################################################################
      # SSM — connect to stage bastion via Session Manager
      ############################################################################
      {
        Sid    = "SSMBastion"
        Effect = "Allow"
        Action = [
          "ssm:StartSession",
          "ssm:TerminateSession",
          "ssm:DescribeSessions",
          "ssm:GetConnectionStatus",
          "ssm:DescribeInstanceInformation",
        ]
        Resource = [
          "arn:aws:ec2:${local.region}:${local.account_id}:instance/*",
          "arn:aws:ssm:${local.region}::document/AWS-StartPortForwardingSessionToRemoteHost",
          "arn:aws:ssm:${local.region}::document/AWS-StartSSHSession",
          "arn:aws:ssm:*:*:document/AWS-StartPortForwardingSessionToRemoteHost",
        ]
      },

      ############################################################################
      # AWS Marketplace — enable Bedrock models (Anthropic Claude, etc.)
      ############################################################################
      {
        Sid    = "Marketplace"
        Effect = "Allow"
        Action = [
          "aws-marketplace:ViewSubscriptions",
          "aws-marketplace:Subscribe",
          "aws-marketplace:Unsubscribe",
        ]
        Resource = "*"
      },
    ]
  })
}

resource "aws_iam_user_policy_attachment" "stage_dev" {
  user       = aws_iam_user.stage_dev.name
  policy_arn = aws_iam_policy.stage_dev.arn
}

################################################################################
# Outputs
################################################################################

output "iam_user_name" {
  description = "IAM username"
  value       = aws_iam_user.stage_dev.name
}

output "access_key_id" {
  description = "AWS Access Key ID"
  value       = aws_iam_access_key.stage_dev.id
  sensitive   = true
}

output "secret_access_key" {
  description = "AWS Secret Access Key"
  value       = aws_iam_access_key.stage_dev.secret
  sensitive   = true
}

output "aws_account_id" {
  description = "AWS account ID (resolved dynamically)"
  value       = local.account_id
}

output "bedrock_agent_id" {
  description = "Bedrock Agent ID (from bedrock/stage remote state)"
  value       = local.agent_id
}

output "bedrock_kb_id" {
  description = "Bedrock KB ID (from bedrock/stage remote state)"
  value       = local.kb_id
}
