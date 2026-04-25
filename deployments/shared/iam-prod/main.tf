################################################################################
# IAM — Prod Developer User
#
# Unified naming-pattern access: all prod resources follow the pattern
# {project}-prod-* so the policy uses wildcards instead of specific ARNs.
# No hardcoded IDs, no remote state dependencies.
################################################################################

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  account_id   = data.aws_caller_identity.current.account_id
  region       = data.aws_region.current.name
  prod_prefix = "${var.project}-prod"
}

################################################################################
# IAM User + Access Key
################################################################################

resource "aws_iam_user" "prod_dev" {
  name = "${local.prod_prefix}-developer"

  tags = {
    Project     = var.project
    Environment = "prod"
    ManagedBy   = "terraform"
  }
}

resource "aws_iam_access_key" "prod_dev" {
  user = aws_iam_user.prod_dev.name
}

################################################################################
# IAM Policy — unified naming-pattern access
################################################################################

resource "aws_iam_policy" "prod_dev" {
  name        = "${local.prod_prefix}-developer-policy"
  description = "Full access to all ${local.prod_prefix}-* resources via naming pattern"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [

      ############################################################################
      # ECR — push/pull {project}-prod-* repositories
      ############################################################################
      {
        Sid      = "ECRAuth"
        Effect   = "Allow"
        Action   = "ecr:GetAuthorizationToken"
        Resource = "*"
      },
      {
        Sid    = "ECRProdRepos"
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
        Resource = "arn:aws:ecr:${local.region}:${local.account_id}:repository/${local.prod_prefix}-*"
      },

      ############################################################################
      # ECS — full access to prod cluster, services, tasks
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
      # Secrets Manager — all vocuone/prod/* and {project}/prod/* secrets
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
          "arn:aws:secretsmanager:${local.region}:${local.account_id}:secret:vocuone/prod/*",
          "arn:aws:secretsmanager:${local.region}:${local.account_id}:secret:${var.project}/prod/*",
          "arn:aws:secretsmanager:${local.region}:${local.account_id}:secret:${local.prod_prefix}-*",
        ]
      },
      {
        Sid      = "SecretsManagerList"
        Effect   = "Allow"
        Action   = "secretsmanager:ListSecrets"
        Resource = "*"
      },

      ############################################################################
      # Bedrock — all prod agents, KBs, and foundation models
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
      # S3 — all {project}-prod-* buckets
      ############################################################################
      {
        Sid    = "S3ProdBuckets"
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
          "arn:aws:s3:::${local.prod_prefix}-*",
          "arn:aws:s3:::${local.prod_prefix}-*/*",
        ]
      },

      ############################################################################
      # CloudWatch Logs — all prod log groups
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
          "arn:aws:logs:${local.region}:${local.account_id}:log-group:*${local.prod_prefix}*",
          "arn:aws:logs:${local.region}:${local.account_id}:log-group:*${local.prod_prefix}*:*",
          "arn:aws:logs:${local.region}:${local.account_id}:log-group:/ecs/${local.prod_prefix}-*",
          "arn:aws:logs:${local.region}:${local.account_id}:log-group:/ecs/${local.prod_prefix}-*:*",
        ]
      },

      ############################################################################
      # CodePipeline + CodeDeploy — all {project}-prod-* pipelines
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
          "codepipeline:RetryProdExecution",
        ]
        Resource = "arn:aws:codepipeline:${local.region}:${local.account_id}:${local.prod_prefix}-*"
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
      # RDS — all {project}-prod-* instances + IAM auth
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
          "arn:aws:rds:${local.region}:${local.account_id}:db:${local.prod_prefix}-*",
          "arn:aws:rds-db:${local.region}:${local.account_id}:dbuser:*/*",
        ]
      },

      ############################################################################
      # KMS — all {project}-prod-* key aliases
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
            "kms:RequestAlias" = "alias/${local.prod_prefix}-*"
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

resource "aws_iam_user_policy_attachment" "prod_dev" {
  user       = aws_iam_user.prod_dev.name
  policy_arn = aws_iam_policy.prod_dev.arn
}

################################################################################
# Outputs
################################################################################

output "iam_user_name" {
  description = "IAM username"
  value       = aws_iam_user.prod_dev.name
}

output "access_key_id" {
  description = "AWS Access Key ID"
  value       = aws_iam_access_key.prod_dev.id
  sensitive   = true
}

output "secret_access_key" {
  description = "AWS Secret Access Key"
  value       = aws_iam_access_key.prod_dev.secret
  sensitive   = true
}
