output "alb_arn" {
  description = "ALB ARN"
  value       = aws_lb.this.arn
}

output "alb_arn_suffix" {
  description = "ALB ARN suffix (app/<name>/<id>) — used as the LoadBalancer dimension in CloudWatch alarms"
  value       = aws_lb.this.arn_suffix
}

output "alb_dns_name" {
  description = "ALB DNS name"
  value       = aws_lb.this.dns_name
}

output "alb_zone_id" {
  description = "ALB hosted zone ID"
  value       = aws_lb.this.zone_id
}

output "blue_target_group_arn" {
  description = "Blue target group ARN"
  value       = aws_lb_target_group.blue.arn
}

output "green_target_group_arn" {
  description = "Green target group ARN"
  value       = aws_lb_target_group.green.arn
}

output "blue_target_group_name" {
  description = "Blue target group name"
  value       = aws_lb_target_group.blue.name
}

output "green_target_group_name" {
  description = "Green target group name"
  value       = aws_lb_target_group.green.name
}

output "https_listener_arn" {
  description = "HTTPS listener ARN"
  value       = aws_lb_listener.https.arn
}

output "http_listener_arn" {
  description = "HTTP listener ARN (port 80 — managed by CodeDeploy alongside HTTPS)"
  value       = aws_lb_listener.http.arn
}

output "test_listener_arn" {
  description = "Test listener ARN for CodeDeploy"
  value       = aws_lb_listener.test.arn
}
