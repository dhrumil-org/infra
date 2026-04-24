output "api_id" {
  description = "API Gateway HTTP API ID"
  value       = aws_apigatewayv2_api.this.id
}

output "api_endpoint" {
  description = "Default invoke URL (API Gateway's auto-generated URL — for testing before DNS cutover)"
  value       = aws_apigatewayv2_api.this.api_endpoint
}

output "custom_domain_target" {
  description = "Target hostname for Route53 alias record (use this if managing DNS manually)"
  value       = aws_apigatewayv2_domain_name.this.domain_name_configuration[0].target_domain_name
}

output "custom_domain_hosted_zone_id" {
  description = "Hosted zone ID for Route53 alias (pair with custom_domain_target)"
  value       = aws_apigatewayv2_domain_name.this.domain_name_configuration[0].hosted_zone_id
}

output "access_log_group" {
  description = "CloudWatch log group where API Gateway access logs are written"
  value       = aws_cloudwatch_log_group.access.name
}

output "stage_arn" {
  description = "API Gateway default stage ARN — used for WAF web ACL association"
  value       = aws_apigatewayv2_stage.default.arn
}
