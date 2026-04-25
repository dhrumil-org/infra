output "api_id" {
  description = "REST API ID"
  value       = aws_api_gateway_rest_api.this.id
}

output "api_endpoint" {
  description = "Default invoke URL — https://{api-id}.execute-api.{region}.amazonaws.com/{stage}"
  value       = "https://${aws_api_gateway_rest_api.this.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${aws_api_gateway_stage.this.stage_name}"
}

output "custom_domain_target" {
  description = "Target hostname for Route53/GoDaddy CNAME — point api_domain here"
  value       = aws_api_gateway_domain_name.this.regional_domain_name
}

output "custom_domain_hosted_zone_id" {
  description = "Hosted zone ID for Route53 alias"
  value       = aws_api_gateway_domain_name.this.regional_zone_id
}

output "access_log_group" {
  description = "CloudWatch log group for API Gateway access logs"
  value       = aws_cloudwatch_log_group.access.name
}

output "stage_arn" {
  description = "REST API stage ARN — used for WAF web ACL association"
  value       = aws_api_gateway_stage.this.arn
}
