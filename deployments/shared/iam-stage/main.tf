################################################################################
# IAM — Stage Developer User
#
# Unified naming-pattern access: all stage resources follow the pattern
# {project}-stage-* so the policy uses wildcards instead of specific ARNs.
# No hardcoded IDs, no remote state dependencies.
################################################################################

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  account_id   = data.aws_caller_identity.current.account_id
  region       = data.aws_region.current.name
  stage_prefix = "${var.project}-stage"
}

################################################################################
# IAM User + Access Key
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

################################################################################
# IAM Policy — unified naming-pattern access
################################################################################

resource "aws_iam_policy" "stage_dev" {
  name        = "${local.stage_prefix}-developer-policy"
  description = "Full access to all ${local.stage_prefix}-* resources via naming pattern"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [

      ############################################################################
      # ECR — push/pull {project}-stage-* repositories
      ############################################################################
      {
        Sid      = "ECRAuth"
        Effect   = "Allow"
        Action   = "ecr:GetAuthorizationToken"
        Resource = "*"
      },
      {
        Sid    = "ECRStageRepos"
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
      # ECS — full access to stage cluster, services, tasks
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
          "ecs:UpdateService",
          "ecs:TagResource",
        ]
        Resource = "*"
      },

      ############################################################################
      # Secrets Manager — all vocuone/stage/* and {project}/stage/* secrets
      ############################################################################
      {
        Sid    = "SecretsManagerRead"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
          "secretsmanager:ListSecretVersionIds",
          "secretsmanager:GetResourcePolicy",
          "secretsmanager:PutSecretValue",
          "secretsmanager:CreateSecret",
        ]
        Resource = [
          "arn:aws:secretsmanager:${local.region}:${local.account_id}:secret:vocuone/stage/*",
          "arn:aws:secretsmanager:${local.region}:${local.account_id}:secret:vocuone/prod/*",
          "arn:aws:secretsmanager:${local.region}:${local.account_id}:secret:${var.project}/stage/*",
          "arn:aws:secretsmanager:${local.region}:${local.account_id}:secret:${local.stage_prefix}-*",
        ]
      },
      {
        Sid      = "SecretsManagerList"
        Effect   = "Allow"
        Action   = "secretsmanager:ListSecrets"
        Resource = "*"
      },

      ############################################################################
      # Bedrock — all stage agents, KBs, and foundation models
      ############################################################################
      {
        Sid    = "Bedrock"
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream",
          "bedrock:Retrieve",
          "bedrock:RetrieveAndGenerate",
          "bedrock-agent-runtime:InvokeAgent",
          "bedrock-agent-runtime:Retrieve",
          "bedrock-agent-runtime:RetrieveAndGenerate",
        ]
        Resource = [
          "arn:aws:bedrock:${local.region}:${local.account_id}:agent/*",
          "arn:aws:bedrock:${local.region}:${local.account_id}:agent-alias/*",
          "arn:aws:bedrock:${local.region}:${local.account_id}:knowledge-base/*",
          "arn:aws:bedrock:${local.region}:${local.account_id}:inference-profile/*",
          "arn:aws:bedrock:*::foundation-model/*",
          "arn:aws:bedrock:*::inference-profile/*",
        ]
      },

      ############################################################################
      # S3 — all {project}-stage-* buckets
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
      # CloudWatch Logs — all stage log groups
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
          "arn:aws:logs:${local.region}:${local.account_id}:log-group:*${local.stage_prefix}*:*",
          "arn:aws:logs:${local.region}:${local.account_id}:log-group:/ecs/${local.stage_prefix}-*",
          "arn:aws:logs:${local.region}:${local.account_id}:log-group:/ecs/${local.stage_prefix}-*:*",
        ]
      },

      ############################################################################
      # CodePipeline + CodeDeploy — all {project}-stage-* pipelines
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
          "codedeploy:StopDeployment",
          "codedeploy:GetDeploymentConfig",
          "codedeploy:RegisterApplicationRevision",
        ]
        Resource = "*"
      },

      ############################################################################
      # RDS — all {project}-stage-* instances + IAM auth
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
      # KMS — all {project}-stage-* key aliases
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
      # SSM — bastion access via Session Manager
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
      # Marketplace — subscribe to Bedrock models
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
