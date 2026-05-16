################################################################################
# IAM User — GitHub Actions CI/CD (Terraform infrastructure management)
#
# This user runs `terraform plan` and `terraform apply` in GitHub Actions.
# Needs broad permissions to CREATE/MANAGE all infrastructure resources.
# Separate from the stage-developer user (which only ACCESSES resources).
################################################################################

resource "aws_iam_user" "cicd" {
  name = "${var.project}-github-actions"

  tags = {
    Project   = var.project
    ManagedBy = "terraform"
  }
}

resource "aws_iam_access_key" "cicd" {
  user = aws_iam_user.cicd.name
}

################################################################################
# Scoped custom policy — only the services Terraform actually manages
################################################################################

resource "aws_iam_policy" "cicd" {
  name        = "${var.project}-github-actions-policy"
  description = "Scoped CI/CD policy for Terraform infrastructure management"

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
        Sid    = "ECS"
        Effect = "Allow"
        Action = ["ecs:*"]
        Resource = "*"
      },
      {
        Sid    = "ECR"
        Effect = "Allow"
        Action = ["ecr:*"]
        Resource = "*"
      },
      {
        Sid    = "ELB"
        Effect = "Allow"
        Action = ["elasticloadbalancing:*"]
        Resource = "*"
      },
      {
        Sid    = "RDS"
        Effect = "Allow"
        Action = ["rds:*"]
        Resource = "*"
      },
      {
        Sid    = "S3"
        Effect = "Allow"
        Action = ["s3:*"]
        Resource = "*"
      },
      {
        Sid    = "SecretsManager"
        Effect = "Allow"
        Action = ["secretsmanager:*"]
        Resource = "*"
      },
      {
        Sid    = "KMS"
        Effect = "Allow"
        Action = ["kms:*"]
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
        Sid    = "CloudTrail"
        Effect = "Allow"
        Action = ["cloudtrail:*"]
        Resource = "*"
      },
      {
        Sid    = "CodeDeploy"
        Effect = "Allow"
        Action = ["codedeploy:*"]
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
        Sid    = "APIGateway"
        Effect = "Allow"
        Action = ["apigateway:*"]
        Resource = "*"
      },
      {
        Sid    = "Route53"
        Effect = "Allow"
        Action = ["route53:*"]
        Resource = "*"
      },
      {
        Sid    = "ACM"
        Effect = "Allow"
        Action = ["acm:*"]
        Resource = "*"
      },
      {
        Sid    = "CloudFront"
        Effect = "Allow"
        Action = ["cloudfront:*"]
        Resource = "*"
      },
      {
        Sid    = "Synthetics"
        Effect = "Allow"
        Action = ["synthetics:*"]
        Resource = "*"
      },
      {
        Sid    = "Lambda"
        Effect = "Allow"
        Action = ["lambda:*"]
        Resource = "*"
      },
      {
        Sid    = "SNS"
        Effect = "Allow"
        Action = ["sns:*"]
        Resource = "*"
      },
      {
        Sid    = "DynamoDB"
        Effect = "Allow"
        Action = ["dynamodb:*"]
        Resource = "*"
      },
      {
        Sid    = "AutoScaling"
        Effect = "Allow"
        Action = ["autoscaling:*"]
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
    ]
  })
}

resource "aws_iam_user_policy_attachment" "cicd" {
  user       = aws_iam_user.cicd.name
  policy_arn = aws_iam_policy.cicd.arn
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


output "iam_user_name" {
  description = "GitHub Actions IAM user name"
  value       = aws_iam_user.cicd.name
}

output "access_key_id" {
  description = "AWS Access Key ID for GitHub Actions"
  value       = aws_iam_access_key.cicd.id
  sensitive   = true
}

output "secret_access_key" {
  description = "AWS Secret Access Key for GitHub Actions"
  value       = aws_iam_access_key.cicd.secret
  sensitive   = true
}
