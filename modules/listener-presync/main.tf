################################################################################
# Listener Pre-Sync Lambda
#
# Invoked by CodeDeploy as a BeforeAllowTraffic lifecycle hook. Aligns the
# secondary ALB listener (HTTP:80) with the replacement target group at the
# exact moment CodeDeploy is about to swap the production listener (HTTPS:443).
# Result: zero misalignment window, zero downtime on every deploy.
################################################################################

locals {
  function_name = "${var.project}-${var.env}-listener-presync"
}

data "archive_file" "lambda" {
  type        = "zip"
  source_file = "${path.module}/lambda.py"
  output_path = "${path.module}/lambda.zip"
}

################################################################################
# IAM role
################################################################################

resource "aws_iam_role" "lambda" {
  name = "${local.function_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Name = "${local.function_name}-role" }
}

resource "aws_iam_role_policy" "lambda" {
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ELB"
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:DescribeListeners",
          "elasticloadbalancing:DescribeTargetGroups",
          "elasticloadbalancing:ModifyListener",
        ]
        Resource = "*"
      },
      {
        Sid    = "CodeDeployHook"
        Effect = "Allow"
        Action = [
          "codedeploy:GetDeployment",
          "codedeploy:PutLifecycleEventHookExecutionStatus",
        ]
        Resource = "*"
      },
      {
        Sid    = "Logs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
    ]
  })
}

################################################################################
# Lambda function
################################################################################

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${local.function_name}"
  retention_in_days = 30
}

resource "aws_lambda_function" "this" {
  function_name = local.function_name
  role          = aws_iam_role.lambda.arn

  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256

  runtime = "python3.12"
  handler = "lambda.lambda_handler"
  timeout = 30

  environment {
    variables = {
      PROD_LISTENER_ARN      = var.prod_listener_arn
      SECONDARY_LISTENER_ARN = var.secondary_listener_arn
    }
  }

  depends_on = [aws_cloudwatch_log_group.lambda]

  tags = { Name = local.function_name }
}

################################################################################
# Permission for CodeDeploy to invoke the Lambda
################################################################################

resource "aws_lambda_permission" "codedeploy" {
  statement_id  = "AllowExecutionFromCodeDeploy"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.this.function_name
  principal     = "codedeploy.amazonaws.com"
}

################################################################################
# Outputs
################################################################################

output "function_name" {
  description = "Lambda function name — wire this into the CodeDeploy AppSpec Hooks section"
  value       = aws_lambda_function.this.function_name
}

output "function_arn" {
  value = aws_lambda_function.this.arn
}

output "log_group" {
  description = "CloudWatch log group with hook run logs"
  value       = aws_cloudwatch_log_group.lambda.name
}
