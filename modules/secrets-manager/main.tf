resource "aws_secretsmanager_secret" "frontend" {
  name                    = var.secret_name
  description             = "${var.project} ${var.env} frontend env vars"
  recovery_window_in_days = 7

  lifecycle {
    ignore_changes = [
      name,
      description
    ]
  }
}

resource "aws_secretsmanager_secret_version" "frontend" {
  secret_id     = aws_secretsmanager_secret.frontend.id
  secret_string = jsonencode(var.secret_values)

  lifecycle {
    ignore_changes = [secret_string]
  }
}
