################################################################################
# GitHub Actions OIDC — replaces the long-lived IAM access keys
#
# How it works:
#   1. GitHub Actions presents a short-lived OIDC token to AWS STS.
#   2. STS validates the token against this OIDC provider.
#   3. The trust policy on each role checks the token's `sub` claim against
#      allowed (repo, branch) pairs.
#   4. If matched, STS hands back temporary credentials scoped to the role.
#
# Two roles — one per environment — mirroring the existing STAGE_*/PROD_*
# split. The trust policy on each role only accepts tokens from the
# appropriate branches, so a stage workflow physically cannot assume the
# prod role even if its OIDC token were copied somewhere.
################################################################################

locals {
  github_oidc_repos = {
    infra    = "vocanote-ai/vocanote-infra"
    backend  = "vocanote-ai/vocanote-be"
    frontend = "vocanote-ai/vocanote-fe"
    canary = "vocanote-ai/vocanote-canary"
  }
}

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  # Thumbprint kept for backward compatibility. AWS now validates the JWT
  # signature directly so this is effectively ignored.
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]

  tags = {
    Name = "${var.project}-github-actions"
  }
}

################################################################################
# STAGE role — only assumable from `stage` branches (and PRs targeting stage)
################################################################################

resource "aws_iam_role" "github_actions_stage" {
  name        = "${var.project}-github-actions-stage-oidc"
  description = "Assumed by GitHub Actions on stage branches. Replaces STAGE_AWS_ACCESS_KEY_ID."

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          "token.actions.githubusercontent.com:sub" = [
            # ref: patterns — plan job and other jobs without `environment:` set
            "repo:${local.github_oidc_repos.infra}:ref:refs/heads/stage",
            "repo:${local.github_oidc_repos.infra}:pull_request",
            "repo:${local.github_oidc_repos.backend}:ref:refs/heads/stage",
            "repo:${local.github_oidc_repos.frontend}:ref:refs/heads/stage",
            "repo:${local.github_oidc_repos.canary}:ref:refs/heads/stage",
            # environment: patterns — apply job uses `environment: stage` which
            # changes the OIDC sub format. Without these the assume role fails
            # at the gated step even though plan worked.
            "repo:${local.github_oidc_repos.infra}:environment:stage",
            "repo:${local.github_oidc_repos.backend}:environment:stage",
            "repo:${local.github_oidc_repos.frontend}:environment:stage",
            "repo:${local.github_oidc_repos.canary}:environment:stage",
          ]
        }
      }
    }]
  })

  tags = {
    Name      = "${var.project}-github-actions-stage-oidc"
    ManagedBy = "terraform"
  }
}

resource "aws_iam_role_policy_attachment" "github_actions_stage" {
  role       = aws_iam_role.github_actions_stage.name
  policy_arn = aws_iam_policy.cicd.arn
}

################################################################################
# PROD role — only assumable from `main` branches
################################################################################

resource "aws_iam_role" "github_actions_prod" {
  name        = "${var.project}-github-actions-prod-oidc"
  description = "Assumed by GitHub Actions on main branches. Replaces PROD_AWS_ACCESS_KEY_ID."

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          "token.actions.githubusercontent.com:sub" = [
            # ref: patterns — plan job and other jobs without `environment:` set
            "repo:${local.github_oidc_repos.infra}:ref:refs/heads/prod",
            "repo:${local.github_oidc_repos.backend}:ref:refs/heads/prod",
            "repo:${local.github_oidc_repos.frontend}:ref:refs/heads/prod",
            "repo:${local.github_oidc_repos.canary}:ref:refs/heads/prod",
            # environment: patterns — apply job uses `environment: prod`
            "repo:${local.github_oidc_repos.infra}:environment:prod",
            "repo:${local.github_oidc_repos.backend}:environment:prod",
            "repo:${local.github_oidc_repos.frontend}:environment:prod",
            "repo:${local.github_oidc_repos.canary}:environment:prod",
          ]
        }
      }
    }]
  })

  tags = {
    Name      = "${var.project}-github-actions-prod-oidc"
    ManagedBy = "terraform"
  }
}

resource "aws_iam_role_policy_attachment" "github_actions_prod" {
  role       = aws_iam_role.github_actions_prod.name
  policy_arn = aws_iam_policy.cicd.arn
}

################################################################################
# Outputs — set these as STAGE_TF_AWS_ROLE_ARN and PROD_TF_AWS_ROLE_ARN
# in each repo's GitHub Secrets after apply.
################################################################################

output "github_actions_stage_role_arn" {
  description = "ARN of the OIDC role for stage workflows. Set as STAGE_TF_AWS_ROLE_ARN secret in each repo."
  value       = aws_iam_role.github_actions_stage.arn
}

output "github_actions_prod_role_arn" {
  description = "ARN of the OIDC role for prod workflows. Set as PROD_TF_AWS_ROLE_ARN secret in each repo."
  value       = aws_iam_role.github_actions_prod.arn
}
