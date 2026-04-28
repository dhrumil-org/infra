################################################################################
# REST API Gateway (v1) — sits in front of ALB
#
# Flow:  Client → Route53 (api.stage.vocuone.ai) → REST API Gateway → ALB → ECS
#
# Using REST API (v1) instead of HTTP API (v2) to support timeout > 29s.
# Timeout up to 60s requires Service Quotas increase (already approved).
################################################################################

data "aws_region" "current" {}

################################################################################
# CloudWatch Logging Role — required for REST API access logs
#
# aws_api_gateway_account is account-level (not per-API).
# Safe to apply multiple times — Terraform manages it idempotently.
################################################################################

resource "aws_iam_role" "apigw_logging" {
  name = "${var.project}-${var.env}-apigw-logging-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "apigateway.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Name = "${var.project}-${var.env}-apigw-logging-role" }
}

resource "aws_iam_role_policy_attachment" "apigw_logging" {
  role       = aws_iam_role.apigw_logging.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}

resource "aws_api_gateway_account" "this" {
  cloudwatch_role_arn = aws_iam_role.apigw_logging.arn
}

################################################################################
# REST API
################################################################################

resource "aws_api_gateway_rest_api" "this" {
  name        = "${var.project}-${var.env}-api"
  description = "REST API for ${var.project}-${var.env}"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = { Name = "${var.project}-${var.env}-api" }
}

################################################################################
# Root resource — ANY /
################################################################################

resource "aws_api_gateway_method" "root" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  resource_id   = aws_api_gateway_rest_api.this.root_resource_id
  http_method   = "ANY"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "root" {
  rest_api_id             = aws_api_gateway_rest_api.this.id
  resource_id             = aws_api_gateway_rest_api.this.root_resource_id
  http_method             = aws_api_gateway_method.root.http_method
  integration_http_method = "ANY"
  type                    = "HTTP_PROXY"
  uri                     = "http://${var.alb_dns_name}/"

  timeout_milliseconds = var.integration_timeout_ms

  # Forward the original public Host header so the app generates redirects
  # using api.vocuone.ai instead of the raw ALB hostname. Also set
  # X-Forwarded-* so Spring can reconstruct absolute URLs correctly when
  # forward-headers-strategy is enabled.
  request_parameters = {
    "integration.request.header.Host"              = "'${var.api_domain}'"
    "integration.request.header.X-Forwarded-Host"  = "'${var.api_domain}'"
    "integration.request.header.X-Forwarded-Proto" = "'https'"
    "integration.request.header.X-Forwarded-Port"  = "'443'"
    "integration.request.header.X-Gateway-Secret"  = "'${var.gateway_secret}'"
  }
}

################################################################################
# Proxy resource — ANY /{proxy+}
################################################################################

resource "aws_api_gateway_resource" "proxy" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_rest_api.this.root_resource_id
  path_part   = "{proxy+}"
}

resource "aws_api_gateway_method" "proxy" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  resource_id   = aws_api_gateway_resource.proxy.id
  http_method   = "ANY"
  authorization = "NONE"

  request_parameters = {
    "method.request.path.proxy" = true
  }
}

resource "aws_api_gateway_integration" "proxy" {
  rest_api_id             = aws_api_gateway_rest_api.this.id
  resource_id             = aws_api_gateway_resource.proxy.id
  http_method             = aws_api_gateway_method.proxy.http_method
  integration_http_method = "ANY"
  type                    = "HTTP_PROXY"
  uri                     = "http://${var.alb_dns_name}/{proxy}"

  timeout_milliseconds = var.integration_timeout_ms

  request_parameters = {
    "integration.request.path.proxy"               = "method.request.path.proxy"
    "integration.request.header.Host"              = "'${var.api_domain}'"
    "integration.request.header.X-Forwarded-Host"  = "'${var.api_domain}'"
    "integration.request.header.X-Forwarded-Proto" = "'https'"
    "integration.request.header.X-Forwarded-Port"  = "'443'"
    "integration.request.header.X-Gateway-Secret"  = "'${var.gateway_secret}'"
  }
}

################################################################################
# Deployment — recreated on any config change
################################################################################

resource "aws_api_gateway_deployment" "this" {
  rest_api_id = aws_api_gateway_rest_api.this.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.proxy.id,
      aws_api_gateway_method.root.id,
      aws_api_gateway_method.proxy.id,
      aws_api_gateway_integration.root.uri,
      aws_api_gateway_integration.proxy.uri,
      aws_api_gateway_integration.root.timeout_milliseconds,
      aws_api_gateway_integration.proxy.timeout_milliseconds,
      # Header overrides (Host, X-Forwarded-*) — included so changes to
      # request_parameters trigger a stage redeploy.
      keys(aws_api_gateway_integration.root.request_parameters),
      keys(aws_api_gateway_integration.proxy.request_parameters),
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_api_gateway_method.root,
    aws_api_gateway_integration.root,
    aws_api_gateway_method.proxy,
    aws_api_gateway_integration.proxy,
  ]
}

################################################################################
# CloudWatch Log Group — access logs
################################################################################

resource "aws_cloudwatch_log_group" "access" {
  name              = "/aws/apigateway/${var.project}-${var.env}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn

  tags = { Name = "${var.project}-${var.env}-apigw-access-logs" }
}

################################################################################
# Stage — throttling + access logs
################################################################################

resource "aws_api_gateway_stage" "this" {
  deployment_id = aws_api_gateway_deployment.this.id
  rest_api_id   = aws_api_gateway_rest_api.this.id
  stage_name    = var.env

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.access.arn
    format = jsonencode({
      requestId          = "$context.requestId"
      sourceIp           = "$context.identity.sourceIp"
      requestTime        = "$context.requestTime"
      httpMethod         = "$context.httpMethod"
      resourcePath       = "$context.resourcePath"
      status             = "$context.status"
      protocol           = "$context.protocol"
      responseLength     = "$context.responseLength"
      integrationLatency = "$context.integrationLatency"
      integrationStatus  = "$context.integrationStatus"
      errorMessage       = "$context.error.message"
      userAgent          = "$context.identity.userAgent"
    })
  }

  tags = { Name = "${var.project}-${var.env}-apigw-stage" }

  depends_on = [aws_api_gateway_account.this]
}

resource "aws_api_gateway_method_settings" "this" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  stage_name  = aws_api_gateway_stage.this.stage_name
  method_path = "*/*"

  settings {
    throttling_burst_limit = var.throttling_burst_limit
    throttling_rate_limit  = var.throttling_rate_limit
    metrics_enabled        = true
    logging_level          = "INFO"
    data_trace_enabled     = false
  }
}

################################################################################
# Custom Domain
################################################################################

resource "aws_api_gateway_domain_name" "this" {
  domain_name              = var.api_domain
  regional_certificate_arn = var.acm_certificate_arn
  security_policy          = "TLS_1_2"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = { Name = "${var.project}-${var.env}-apigw-domain" }
}

resource "aws_api_gateway_base_path_mapping" "this" {
  api_id      = aws_api_gateway_rest_api.this.id
  stage_name  = aws_api_gateway_stage.this.stage_name
  domain_name = aws_api_gateway_domain_name.this.domain_name
}

################################################################################
# Route53 — optional, set create_route53_record = true to manage DNS
################################################################################

resource "aws_route53_record" "this" {
  count = var.create_route53_record ? 1 : 0

  zone_id = var.route53_zone_id
  name    = var.api_domain
  type    = "A"

  alias {
    name                   = aws_api_gateway_domain_name.this.regional_domain_name
    zone_id                = aws_api_gateway_domain_name.this.regional_zone_id
    evaluate_target_health = false
  }
}
