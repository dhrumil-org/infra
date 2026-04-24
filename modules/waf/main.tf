resource "aws_wafv2_web_acl" "this" {
  name        = "${var.project}-${var.env}-waf"
  description = "WAF for ${var.project}-${var.env} — rate limiting only"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  rule {
    name     = "RateLimitPerIP"
    priority = 1

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = var.rate_limit_per_ip
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project}-${var.env}-waf-rate-limit"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.project}-${var.env}-waf"
    sampled_requests_enabled   = true
  }

  tags = {
    Name = "${var.project}-${var.env}-waf"
  }
}

resource "aws_wafv2_web_acl_association" "this" {
  resource_arn = var.associated_resource_arn
  web_acl_arn  = aws_wafv2_web_acl.this.arn
}
