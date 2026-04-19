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
# Attach AWS managed policies for full infrastructure management
#
# PowerUserAccess = everything except IAM user/group management
# IAMFullAccess   = create/manage IAM roles, policies, instance profiles
#
# This is appropriate for a CI/CD user that manages all infrastructure.
# For tighter control, replace with a custom policy listing specific actions.
################################################################################

resource "aws_iam_user_policy_attachment" "power_user" {
  user       = aws_iam_user.cicd.name
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}

resource "aws_iam_user_policy_attachment" "iam_full" {
  user       = aws_iam_user.cicd.name
  policy_arn = "arn:aws:iam::aws:policy/IAMFullAccess"
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
