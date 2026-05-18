################################################################################
# Backend health alarms — fires on any ALB-layer 5xx
#
# Catches "backend is down or broken" faster than the synthetics canary,
# which only runs once an hour. These alarms fire within 2 minutes of the
# first server-side error showing up at the ALB.
#
# Two signals, both routed to the existing aws_sns_topic.alerts:
#
#   1. HTTPCode_Target_5XX_Count
#      The ECS task returned a 5xx response (500/502/503/504 from the
#      Spring Boot app itself — Tomcat error pages, unhandled exceptions,
#      OOM, deadline-exceeded handlers, etc.).
#
#   2. HTTPCode_ELB_5XX_Count
#      The ALB returned a 5xx WITHOUT being able to forward to a target —
#      no healthy targets, connection refused, target timeout. Indicates
#      capacity / network / health-check problems rather than app errors.
#
# 4xx is intentionally not alarmed — normal traffic produces 401/404 from
# auth and routing, and would generate constant false positives.
#
# Threshold convention:
#   period             = 60s
#   evaluation_periods = 2
#   datapoints_to_alarm = 2
#   threshold          = >= 1
#   → fires only when at least one 5xx occurs in each of two consecutive
#     minutes (prevents single-flake alarms; minimal latency to detection).
################################################################################

resource "aws_cloudwatch_metric_alarm" "backend_target_5xx" {
  alarm_name          = "${var.project}-${var.env}-backend-target-5xx"
  alarm_description   = "ECS task returned 5xx (server-side error from the Spring Boot app). 2 consecutive minutes with >=1 error."
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  threshold           = 1
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Sum"
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = module.alb.alb_arn_suffix
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = { Name = "${var.project}-${var.env}-backend-target-5xx" }
}

resource "aws_cloudwatch_metric_alarm" "backend_elb_5xx" {
  alarm_name          = "${var.project}-${var.env}-backend-elb-5xx"
  alarm_description   = "ALB returned 5xx (couldn't forward to a target — no healthy hosts, connection refused, target timeout). 2 consecutive minutes with >=1 error."
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  threshold           = 1
  metric_name         = "HTTPCode_ELB_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Sum"
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = module.alb.alb_arn_suffix
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = { Name = "${var.project}-${var.env}-backend-elb-5xx" }
}
