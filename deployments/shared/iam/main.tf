################################################################################
# CI/CD permissions policy — now attached only to the OIDC roles in oidc.tf
#
# This policy used to be attached to a long-lived IAM user
# (`vocuone-github-actions` + permanent access key). That user has been
# removed as part of the HIPAA pre-prod IAM review — long-lived keys for
# write-capable principals violate §164.308(a)(4) (minimum necessary +
# rotation) and remove the per-run auditability OIDC provides through
# unique role-session names.
#
# The POLICY itself is still needed because aws_iam_role_policy_attachment
# .github_actions_stage and .github_actions_prod in oidc.tf attach it to
# the two OIDC roles (vocuone-github-actions-stage-oidc /
# vocuone-github-actions-prod-oidc). Those roles are what GitHub Actions
# now assumes via sts:AssumeRoleWithWebIdentity.
#
# If you need to add another CI principal, do it as another OIDC role in
# oidc.tf and attach this same policy — do NOT create another aws_iam_user.
################################################################################

resource "aws_iam_policy" "cicd" {
  name        = "${var.project}-github-actions-policy"
  description = "Scoped CI/CD policy for Terraform infrastructure management (attached to OIDC roles in oidc.tf)"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EC2VPC"
        Effect = "Allow"
        Action = [
          "ec2:*",
        ]
        Resource = "*"
      },
      {
        Sid      = "ECS"
        Effect   = "Allow"
        Action   = ["ecs:*"]
        Resource = "*"
      },
      {
        Sid      = "ECR"
        Effect   = "Allow"
        Action   = ["ecr:*"]
        Resource = "*"
      },
      {
        Sid      = "ELB"
        Effect   = "Allow"
        Action   = ["elasticloadbalancing:*"]
        Resource = "*"
      },
      {
        Sid      = "RDS"
        Effect   = "Allow"
        Action   = ["rds:*"]
        Resource = "*"
      },
      {
        Sid      = "S3"
        Effect   = "Allow"
        Action   = ["s3:*"]
        Resource = "*"
      },
      {
        Sid      = "SecretsManager"
        Effect   = "Allow"
        Action   = ["secretsmanager:*"]
        Resource = "*"
      },
      {
        Sid      = "KMS"
        Effect   = "Allow"
        Action   = ["kms:*"]
        Resource = "*"
      },
      {
        Sid    = "CloudWatch"
        Effect = "Allow"
        Action = [
          "cloudwatch:*",
          "logs:*",
        ]
        Resource = "*"
      },
      {
        Sid      = "CloudTrail"
        Effect   = "Allow"
        Action   = ["cloudtrail:*"]
        Resource = "*"
      },
      {
        Sid      = "CodeDeploy"
        Effect   = "Allow"
        Action   = ["codedeploy:*"]
        Resource = "*"
      },
      {
        Sid    = "CodePipeline"
        Effect = "Allow"
        Action = [
          "codepipeline:*",
          "codestar-connections:*",
        ]
        Resource = "*"
      },
      {
        Sid      = "APIGateway"
        Effect   = "Allow"
        Action   = ["apigateway:*"]
        Resource = "*"
      },
      {
        Sid      = "Route53"
        Effect   = "Allow"
        Action   = ["route53:*"]
        Resource = "*"
      },
      {
        Sid      = "ACM"
        Effect   = "Allow"
        Action   = ["acm:*"]
        Resource = "*"
      },
      {
        Sid      = "CloudFront"
        Effect   = "Allow"
        Action   = ["cloudfront:*"]
        Resource = "*"
      },
      {
        Sid      = "Synthetics"
        Effect   = "Allow"
        Action   = ["synthetics:*"]
        Resource = "*"
      },
      {
        Sid      = "Lambda"
        Effect   = "Allow"
        Action   = ["lambda:*"]
        Resource = "*"
      },
      {
        Sid      = "SNS"
        Effect   = "Allow"
        Action   = ["sns:*"]
        Resource = "*"
      },
      {
        Sid      = "DynamoDB"
        Effect   = "Allow"
        Action   = ["dynamodb:*"]
        Resource = "*"
      },
      {
        Sid      = "AutoScaling"
        Effect   = "Allow"
        Action   = ["autoscaling:*"]
        Resource = "*"
      },
      {
        Sid    = "IAM"
        Effect = "Allow"
        Action = [
          "iam:CreateRole",
          "iam:DeleteRole",
          "iam:GetRole",
          "iam:UpdateRole",
          "iam:PassRole",
          "iam:AttachRolePolicy",
          "iam:DetachRolePolicy",
          "iam:PutRolePolicy",
          "iam:DeleteRolePolicy",
          "iam:GetRolePolicy",
          "iam:ListRolePolicies",
          "iam:ListAttachedRolePolicies",
          "iam:CreatePolicy",
          "iam:DeletePolicy",
          "iam:GetPolicy",
          "iam:GetPolicyVersion",
          "iam:CreatePolicyVersion",
          "iam:DeletePolicyVersion",
          "iam:ListPolicyVersions",
          "iam:CreateInstanceProfile",
          "iam:DeleteInstanceProfile",
          "iam:GetInstanceProfile",
          "iam:AddRoleToInstanceProfile",
          "iam:RemoveRoleFromInstanceProfile",
          "iam:TagRole",
          "iam:UntagRole",
          "iam:ListRoleTags",
          "iam:TagPolicy",
          "iam:UntagPolicy",
          "iam:CreateUser",
          "iam:DeleteUser",
          "iam:GetUser",
          "iam:TagUser",
          "iam:UntagUser",
          "iam:ListUserTags",
          "iam:CreateAccessKey",
          "iam:DeleteAccessKey",
          "iam:ListAccessKeys",
          "iam:AttachUserPolicy",
          "iam:DetachUserPolicy",
          "iam:ListAttachedUserPolicies",
          "iam:PutUserPolicy",
          "iam:DeleteUserPolicy",
          "iam:GetUserPolicy",
          "iam:ListUserPolicies",
          "iam:ListEntitiesForPolicy",
          "iam:ListRoles",
          "iam:ListUsers",
          "iam:ListPolicies",
          "iam:ListInstanceProfiles",
          "iam:ListInstanceProfilesForRole",
          # OIDC provider — needed so terraform-via-OIDC can refresh
          # aws_iam_openid_connect_provider.github (the resource that
          # underpins the very role being assumed for this run).
          "iam:CreateOpenIDConnectProvider",
          "iam:DeleteOpenIDConnectProvider",
          "iam:GetOpenIDConnectProvider",
          "iam:ListOpenIDConnectProviders",
          "iam:UpdateOpenIDConnectProviderThumbprint",
          "iam:AddClientIDToOpenIDConnectProvider",
          "iam:RemoveClientIDFromOpenIDConnectProvider",
          "iam:TagOpenIDConnectProvider",
          "iam:UntagOpenIDConnectProvider",
          "iam:ListOpenIDConnectProviderTags",
        ]
        Resource = "*"
      },
      {
        Sid    = "SSM"
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:PutParameter",
          "ssm:DeleteParameter",
          "ssm:DescribeParameters",
        ]
        Resource = "*"
      },
      ##########################################################################
      # Below: gaps found while running CI/CD as the OIDC role. Each block
      # corresponds to a terraform refresh that previously hit AccessDenied.
      ##########################################################################
      {
        Sid      = "WAFv2"
        Effect   = "Allow"
        Action   = ["wafv2:*"]
        Resource = "*"
      },
      {
        Sid      = "ApplicationAutoScaling"
        Effect   = "Allow"
        Action   = ["application-autoscaling:*"]
        Resource = "*"
      },
      {
        Sid    = "Backup"
        Effect = "Allow"
        Action = [
          "backup:*",
          "backup-storage:*",
        ]
        Resource = "*"
      },
      {
        Sid      = "EventBridge"
        Effect   = "Allow"
        Action   = ["events:*"]
        Resource = "*"
      },
      {
        Sid    = "Bedrock"
        Effect = "Allow"
        Action = [
          "bedrock:*",
          "bedrock-agent:*",
        ]
        Resource = "*"
      },
      {
        Sid      = "Inspector"
        Effect   = "Allow"
        Action   = ["inspector2:*"]
        Resource = "*"
      },
      {
        Sid    = "STS"
        Effect = "Allow"
        Action = [
          "sts:GetCallerIdentity",
          "sts:TagSession",
        ]
        Resource = "*"
      },
      {
        Sid      = "S3Vectors"
        Effect   = "Allow"
        Action   = ["s3vectors:*"]
        Resource = "*"
      },
    ]
  })
}

################################################################################
# IAM User — Grafana Cloud (read-only CloudWatch access)
################################################################################

resource "aws_iam_user" "grafana" {
  name = "${var.project}-grafana"

  tags = {
    Project   = var.project
    ManagedBy = "terraform"
  }
}

resource "aws_iam_access_key" "grafana" {
  user = aws_iam_user.grafana.name
}

resource "aws_iam_user_policy_attachment" "grafana_cloudwatch" {
  user       = aws_iam_user.grafana.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchReadOnlyAccess"
}

################################################################################
# Outputs
################################################################################

output "grafana_access_key_id" {
  description = "AWS Access Key ID for Grafana Cloud"
  value       = aws_iam_access_key.grafana.id
  sensitive   = true
}

output "grafana_secret_access_key" {
  description = "AWS Secret Access Key for Grafana Cloud"
  value       = aws_iam_access_key.grafana.secret
  sensitive   = true
}
