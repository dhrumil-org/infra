################################################################################
# Legacy GitHub Actions IAM user (REMOVED)
#
# All CI/CD workflows now authenticate via the OIDC roles defined in oidc.tf
# (vocuone-cicd-stage / vocuone-cicd-prod, scoped to specific branches +
# environments + repos under vocanote-ai/*). The long-lived access key user
# that previously held all these permissions has been deleted as of the
# HIPAA pre-prod IAM review — long-lived keys for write-capable principals
# violate §164.308(a)(4) (information access management — minimum necessary +
# rotation) and remove the per-run auditability OIDC provides.
#
# If you need to reintroduce a CI principal for any reason, do it as another
# OIDC role in oidc.tf, not as a user with an access key.
################################################################################

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
