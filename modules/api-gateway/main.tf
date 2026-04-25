################################################################################
# HTTP API Gateway — sits in front of ALB
#
# Flow:  Client → Route53 (api.stage.vocuone.ai) → API Gateway → ALB → ECS
#
# Gives you: throttling, access logs, CORS management, future authorizers.
# Keeps your existing: ALB, CodeDeploy blue/green, CodePipeline, ECS service.
################################################################################

################################################################################
# HTTP API
################################################################################

resource "aws_apigatewayv2_api" "this" {
  name          = "${var.project}-${var.env}-http-api"
  protocol_type = "HTTP"
  description   = "HTTP API in front of ALB for ${var.project}-${var.env}"

  tags = {
    Name = "${var.project}-${var.env}-http-api"
  }
}

################################################################################
# Integration — HTTP_PROXY to ALB
#
# Forwards all requests to the ALB's HTTPS listener.
# ALB stays public (for blue/green + direct health checks) but traffic comes
# through API Gateway at the domain level.
################################################################################

resource "aws_apigatewayv2_integration" "alb" {
  api_id             = aws_apigatewayv2_api.this.id
  integration_type   = "HTTP_PROXY"
  integration_method = "ANY"

  # HTTPS with explicit SNI — connects to the ALB's elb.amazonaws.com DNS
  # but sends SNI "api.stage.vocuone.ai" so the ALB's ACM cert validates.
  # CodeDeploy manages the HTTPS listener, so this always hits the live TG.
  integration_uri = "https://${var.alb_dns_name}"

  tls_config {
    server_name_to_verify = var.api_domain
  }

  # Overwrite the path the backend sees — use the captured proxy variable
  # so /health → /health (not /{proxy})
  request_parameters = {
    "overwrite:path"                    = "/$request.path.proxy"
    "overwrite:header.X-Gateway-Secret" = "'${var.gateway_secret}'"
  }

  timeout_milliseconds = var.integration_timeout_ms
}

################################################################################
# Catch-all route — ANY /{proxy+} → integration
################################################################################

resource "aws_apigatewayv2_route" "proxy" {
  api_id    = aws_apigatewayv2_api.this.id
  route_key = "ANY /{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.alb.id}"
}

################################################################################
# CloudWatch Log Group — access logs
################################################################################

resource "aws_cloudwatch_log_group" "access" {
  name              = "/aws/apigateway/${var.project}-${var.env}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn

  tags = {
    Name = "${var.project}-${var.env}-apigw-access-logs"
  }
}

################################################################################
# Stage — $default with auto-deploy + throttling + access logs
################################################################################

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.this.id
  name        = "$default"
  auto_deploy = true

  default_route_settings {
    throttling_burst_limit = var.throttling_burst_limit
    throttling_rate_limit  = var.throttling_rate_limit
    detailed_metrics_enabled = true
  }

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.access.arn
    format = jsonencode({
      requestId                 = "$context.requestId"
      sourceIp                  = "$context.identity.sourceIp"
      requestTime               = "$context.requestTime"
      httpMethod                = "$context.httpMethod"
      routeKey                  = "$context.routeKey"
      path                      = "$context.path"
      status                    = "$context.status"
      protocol                  = "$context.protocol"
      responseLength            = "$context.responseLength"
      integrationStatus         = "$context.integrationStatus"
      integrationLatency        = "$context.integrationLatency"
      integrationRequestId      = "$context.integration.requestId"
      integrationError          = "$context.integration.error"
      integrationErrorMessage   = "$context.integrationErrorMessage"
      authorizerError           = "$context.authorizer.error"
      errorMessage              = "$context.error.message"
      errorResponseType         = "$context.error.responseType"
      userAgent                 = "$context.identity.userAgent"
    })
  }

  tags = {
    Name = "${var.project}-${var.env}-apigw-stage"
  }
}

################################################################################
# Custom Domain — api.stage.vocuone.ai points here instead of ALB
################################################################################

resource "aws_apigatewayv2_domain_name" "this" {
  domain_name = var.api_domain

  domain_name_configuration {
    certificate_arn = var.acm_certificate_arn
    endpoint_type   = "REGIONAL"
    security_policy = "TLS_1_2"
  }

  tags = {
    Name = "${var.project}-${var.env}-apigw-domain"
  }
}

resource "aws_apigatewayv2_api_mapping" "this" {
  api_id      = aws_apigatewayv2_api.this.id
  domain_name = aws_apigatewayv2_domain_name.this.id
  stage       = aws_apigatewayv2_stage.default.id
}

################################################################################
# Route53 — point api_domain at API Gateway (instead of ALB)
#
# Set create_route53_record = false if you want to manage DNS manually
# or if another resource already owns this record.
################################################################################

resource "aws_route53_record" "this" {
  count = var.create_route53_record ? 1 : 0

  zone_id = var.route53_zone_id
  name    = var.api_domain
  type    = "A"

  alias {
    name                   = aws_apigatewayv2_domain_name.this.domain_name_configuration[0].target_domain_name
    zone_id                = aws_apigatewayv2_domain_name.this.domain_name_configuration[0].hosted_zone_id
    evaluate_target_health = false
  }
}
