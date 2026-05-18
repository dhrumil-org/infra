################################################################################
# CI/CD permissions policy for the GitHub Actions OIDC roles defined in
# oidc.tf (vocuone-github-actions-stage-oidc / -prod-oidc). GitHub Actions
# assumes those roles via sts:AssumeRoleWithWebIdentity; this policy is what
# they get attached to them.
#
# The legacy long-lived IAM user that previously held this policy was deleted
# during the HIPAA pre-prod IAM review (§164.308(a)(4) — minimum necessary +
# rotation). Do not reintroduce an aws_iam_user here; add another OIDC role
# in oidc.tf and attach this same policy instead.
#
# Scope is intentionally near-admin: Terraform manages every service this
# project uses, so the role needs `<service>:*` on most actions. Resource =
# "*" everywhere is the known trade-off for one shared CI principal. If we
# split CI into per-stack roles (e.g. one for ecs, one for bedrock), each
# could be tightened — tracked in the IAM audit punch list.
################################################################################

resource "aws_iam_policy" "cicd" {
  name        = "${var.project}-github-actions-policy"
  description = "Scoped CI/CD policy for Terraform infrastructure management (attached to OIDC roles in oidc.tf)"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      ##########################################################################
      # Compute, networking, scaling
      ##########################################################################
      { Sid = "EC2", Effect = "Allow", Action = ["ec2:*"], Resource = "*" },
      { Sid = "ECS", Effect = "Allow", Action = ["ecs:*"], Resource = "*" },
      { Sid = "ECR", Effect = "Allow", Action = ["ecr:*"], Resource = "*" },
      { Sid = "ELB", Effect = "Allow", Action = ["elasticloadbalancing:*"], Resource = "*" },
      { Sid = "Lambda", Effect = "Allow", Action = ["lambda:*"], Resource = "*" },
      { Sid = "AutoScaling", Effect = "Allow", Action = ["autoscaling:*"], Resource = "*" },
      { Sid = "ApplicationAutoScaling", Effect = "Allow", Action = ["application-autoscaling:*"], Resource = "*" },

      ##########################################################################
      # Storage & data
      ##########################################################################
      { Sid = "S3", Effect = "Allow", Action = ["s3:*"], Resource = "*" },
      { Sid = "S3Vectors", Effect = "Allow", Action = ["s3vectors:*"], Resource = "*" },
      { Sid = "RDS", Effect = "Allow", Action = ["rds:*"], Resource = "*" },
      { Sid = "DynamoDB", Effect = "Allow", Action = ["dynamodb:*"], Resource = "*" },
      { Sid = "Backup", Effect = "Allow", Action = ["backup:*", "backup-storage:*"], Resource = "*" },

      ##########################################################################
      # Encryption & secrets
      ##########################################################################
      { Sid = "KMS", Effect = "Allow", Action = ["kms:*"], Resource = "*" },
      { Sid = "SecretsManager", Effect = "Allow", Action = ["secretsmanager:*"], Resource = "*" },
      { Sid = "ACM", Effect = "Allow", Action = ["acm:*"], Resource = "*" },

      ##########################################################################
      # Public edge & DNS
      ##########################################################################
      { Sid = "Route53", Effect = "Allow", Action = ["route53:*"], Resource = "*" },
      { Sid = "CloudFront", Effect = "Allow", Action = ["cloudfront:*"], Resource = "*" },
      { Sid = "APIGateway", Effect = "Allow", Action = ["apigateway:*"], Resource = "*" },
      { Sid = "WAFv2", Effect = "Allow", Action = ["wafv2:*"], Resource = "*" },

      ##########################################################################
      # Observability, alerting, audit
      ##########################################################################
      { Sid = "CloudWatch", Effect = "Allow", Action = ["cloudwatch:*", "logs:*"], Resource = "*" },
      { Sid = "CloudTrail", Effect = "Allow", Action = ["cloudtrail:*"], Resource = "*" },
      { Sid = "EventBridge", Effect = "Allow", Action = ["events:*"], Resource = "*" },
      { Sid = "SNS", Effect = "Allow", Action = ["sns:*"], Resource = "*" },
      { Sid = "Synthetics", Effect = "Allow", Action = ["synthetics:*"], Resource = "*" },
      { Sid = "Inspector", Effect = "Allow", Action = ["inspector2:*"], Resource = "*" },

      ##########################################################################
      # Deployment (CodePipeline + CodeDeploy stack)
      ##########################################################################
      { Sid = "CodeDeploy", Effect = "Allow", Action = ["codedeploy:*"], Resource = "*" },
      { Sid = "CodePipeline", Effect = "Allow", Action = ["codepipeline:*", "codestar-connections:*"], Resource = "*" },

      ##########################################################################
      # AI / Bedrock
      ##########################################################################
      { Sid = "Bedrock", Effect = "Allow", Action = ["bedrock:*", "bedrock-agent:*"], Resource = "*" },

      ##########################################################################
      # SSM Parameter Store (Terraform reads/writes parameters during apply)
      ##########################################################################
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
      # STS — just session/identity calls; Terraform self-checks via these
      ##########################################################################
      {
        Sid      = "STS"
        Effect   = "Allow"
        Action   = ["sts:GetCallerIdentity", "sts:TagSession"]
        Resource = "*"
      },

      ##########################################################################
      # IAM — Terraform manages every role/policy/instance-profile in the repo,
      # and the OIDC provider that this very role authenticates through.
      # Action list is enumerated (no iam:*) to keep the blast radius bounded
      # to what Terraform actually needs.
      ##########################################################################
      {
        Sid    = "IAMRoles"
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
          "iam:TagRole",
          "iam:UntagRole",
          "iam:ListRoleTags",
          "iam:ListRoles",
        ]
        Resource = "*"
      },
      {
        Sid    = "IAMPolicies"
        Effect = "Allow"
        Action = [
          "iam:CreatePolicy",
          "iam:DeletePolicy",
          "iam:GetPolicy",
          "iam:GetPolicyVersion",
          "iam:CreatePolicyVersion",
          "iam:DeletePolicyVersion",
          "iam:ListPolicyVersions",
          "iam:TagPolicy",
          "iam:UntagPolicy",
          "iam:ListPolicies",
          "iam:ListEntitiesForPolicy",
        ]
        Resource = "*"
      },
      {
        Sid    = "IAMInstanceProfiles"
        Effect = "Allow"
        Action = [
          "iam:CreateInstanceProfile",
          "iam:DeleteInstanceProfile",
          "iam:GetInstanceProfile",
          "iam:AddRoleToInstanceProfile",
          "iam:RemoveRoleFromInstanceProfile",
          "iam:ListInstanceProfiles",
          "iam:ListInstanceProfilesForRole",
        ]
        Resource = "*"
      },
      {
        # Needed for the Grafana user managed in this same stack and the
        # developer users in iam-prod / iam-stage. Future direction: replace
        # those with OIDC roles too, then this block can be trimmed.
        Sid    = "IAMUsers"
        Effect = "Allow"
        Action = [
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
          "iam:ListUsers",
        ]
        Resource = "*"
      },
      {
        # OIDC provider — terraform-via-OIDC must be able to refresh
        # aws_iam_openid_connect_provider.github (the resource that underpins
        # the very role being assumed for this run).
        Sid    = "IAMOIDCProvider"
        Effect = "Allow"
        Action = [
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
    ]
  })
}

################################################################################
# IAM User — Grafana Cloud (read-only CloudWatch access)
#
# Grafana Cloud is external SaaS and can't use AWS OIDC, so this is one of
# the very few legitimate long-lived-key users. Scope is read-only via the
# AWS-managed CloudWatchReadOnlyAccess policy — no access to log group
# contents that are encrypted with our CMKs, just metric data and metadata.
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
# Outputs — Grafana access keys (paste into Grafana Cloud's CloudWatch data
# source config). The CI/CD OIDC roles in oidc.tf have their own outputs.
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
