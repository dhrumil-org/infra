################################################################################
# Observability Alarms — Bedrock + Comprehend + app-log signals
#
# 21 CloudWatch alarms, all routed through aws_sns_topic.alerts (the same SNS
# topic ECS CPU / Memory / canary alarms already use).
#
# Threshold convention:
#   - "warn" alarms trip at 50 % of the relevant cap
#   - "crit" alarms trip at 80 % of the relevant cap
#   - Reliability alarms (throttles, 5xx) are single-tier
#
# See ALARMS.md for a runbook entry per alarm.
################################################################################

locals {
  ai_alarm_actions = [aws_sns_topic.alerts.arn]
  ai_ok_actions    = [aws_sns_topic.alerts.arn]

  # Bedrock ModelId dimensions (exact strings emitted by AWS/Bedrock metrics).
  bedrock_haiku    = "us.anthropic.claude-haiku-4-5-20251001-v1:0"
  bedrock_sonnet   = "us.anthropic.claude-sonnet-4-6"
  bedrock_nova_pro = "arn:aws:bedrock:us-east-1::foundation-model/amazon.nova-pro-v1:0"

  # App log group emitted by Spring Boot (used for ai.call metric filters).
  app_log_group = "/ecs/${var.project}-${var.env}-app"
}

################################################################################
# Bedrock — Requests-per-minute (50 cap on both Haiku and Sonnet)
################################################################################

resource "aws_cloudwatch_metric_alarm" "bedrock_haiku_rpm_warn" {
  alarm_name          = "${var.project}-${var.env}-bedrock-haiku-rpm-warn"
  alarm_description   = "Haiku 4.5 — RPM at 50 % of cap (25/min). Heads-up."
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  threshold           = 25
  metric_name         = "Invocations"
  namespace           = "AWS/Bedrock"
  period              = 60
  statistic           = "Sum"
  dimensions          = { ModelId = local.bedrock_haiku }
  alarm_actions       = local.ai_alarm_actions
  ok_actions          = local.ai_ok_actions
  treat_missing_data  = "notBreaching"
  tags                = { Name = "${var.project}-${var.env}-bedrock-haiku-rpm-warn" }
}

resource "aws_cloudwatch_metric_alarm" "bedrock_haiku_rpm_crit" {
  alarm_name          = "${var.project}-${var.env}-bedrock-haiku-rpm-crit"
  alarm_description   = "Haiku 4.5 — RPM at 80 % of cap (40/min). Throttling imminent."
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  threshold           = 40
  metric_name         = "Invocations"
  namespace           = "AWS/Bedrock"
  period              = 60
  statistic           = "Sum"
  dimensions          = { ModelId = local.bedrock_haiku }
  alarm_actions       = local.ai_alarm_actions
  ok_actions          = local.ai_ok_actions
  treat_missing_data  = "notBreaching"
  tags                = { Name = "${var.project}-${var.env}-bedrock-haiku-rpm-crit" }
}

resource "aws_cloudwatch_metric_alarm" "bedrock_sonnet_rpm_warn" {
  alarm_name          = "${var.project}-${var.env}-bedrock-sonnet-rpm-warn"
  alarm_description   = "Sonnet 4.6 — RPM at 50 % of cap (25/min). Heads-up."
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  threshold           = 25
  metric_name         = "Invocations"
  namespace           = "AWS/Bedrock"
  period              = 60
  statistic           = "Sum"
  dimensions          = { ModelId = local.bedrock_sonnet }
  alarm_actions       = local.ai_alarm_actions
  ok_actions          = local.ai_ok_actions
  treat_missing_data  = "notBreaching"
  tags                = { Name = "${var.project}-${var.env}-bedrock-sonnet-rpm-warn" }
}

resource "aws_cloudwatch_metric_alarm" "bedrock_sonnet_rpm_crit" {
  alarm_name          = "${var.project}-${var.env}-bedrock-sonnet-rpm-crit"
  alarm_description   = "Sonnet 4.6 — RPM at 80 % of cap (40/min). Throttling imminent."
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  threshold           = 40
  metric_name         = "Invocations"
  namespace           = "AWS/Bedrock"
  period              = 60
  statistic           = "Sum"
  dimensions          = { ModelId = local.bedrock_sonnet }
  alarm_actions       = local.ai_alarm_actions
  ok_actions          = local.ai_ok_actions
  treat_missing_data  = "notBreaching"
  tags                = { Name = "${var.project}-${var.env}-bedrock-sonnet-rpm-crit" }
}

################################################################################
# Bedrock — Tokens-per-minute (input + output combined via metric math)
################################################################################

resource "aws_cloudwatch_metric_alarm" "bedrock_haiku_tpm_warn" {
  alarm_name          = "${var.project}-${var.env}-bedrock-haiku-tpm-warn"
  alarm_description   = "Haiku 4.5 — TPM at 50 % of 5M cap (2.5M/min). Heads-up."
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  threshold           = 2500000
  alarm_actions       = local.ai_alarm_actions
  ok_actions          = local.ai_ok_actions
  treat_missing_data  = "notBreaching"

  metric_query {
    id          = "tpm"
    expression  = "m_in + m_out"
    label       = "Haiku TPM"
    return_data = true
  }
  metric_query {
    id = "m_in"
    metric {
      metric_name = "InputTokenCount"
      namespace   = "AWS/Bedrock"
      period      = 60
      stat        = "Sum"
      dimensions  = { ModelId = local.bedrock_haiku }
    }
  }
  metric_query {
    id = "m_out"
    metric {
      metric_name = "OutputTokenCount"
      namespace   = "AWS/Bedrock"
      period      = 60
      stat        = "Sum"
      dimensions  = { ModelId = local.bedrock_haiku }
    }
  }
  tags = { Name = "${var.project}-${var.env}-bedrock-haiku-tpm-warn" }
}

resource "aws_cloudwatch_metric_alarm" "bedrock_haiku_tpm_crit" {
  alarm_name          = "${var.project}-${var.env}-bedrock-haiku-tpm-crit"
  alarm_description   = "Haiku 4.5 — TPM at 80 % of 5M cap (4M/min). Throttling imminent."
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  threshold           = 4000000
  alarm_actions       = local.ai_alarm_actions
  ok_actions          = local.ai_ok_actions
  treat_missing_data  = "notBreaching"

  metric_query {
    id          = "tpm"
    expression  = "m_in + m_out"
    label       = "Haiku TPM"
    return_data = true
  }
  metric_query {
    id = "m_in"
    metric {
      metric_name = "InputTokenCount"
      namespace   = "AWS/Bedrock"
      period      = 60
      stat        = "Sum"
      dimensions  = { ModelId = local.bedrock_haiku }
    }
  }
  metric_query {
    id = "m_out"
    metric {
      metric_name = "OutputTokenCount"
      namespace   = "AWS/Bedrock"
      period      = 60
      stat        = "Sum"
      dimensions  = { ModelId = local.bedrock_haiku }
    }
  }
  tags = { Name = "${var.project}-${var.env}-bedrock-haiku-tpm-crit" }
}

resource "aws_cloudwatch_metric_alarm" "bedrock_sonnet_tpm_warn" {
  alarm_name          = "${var.project}-${var.env}-bedrock-sonnet-tpm-warn"
  alarm_description   = "Sonnet 4.6 — TPM at 50 % of 6M cap (3M/min). Heads-up."
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  threshold           = 3000000
  alarm_actions       = local.ai_alarm_actions
  ok_actions          = local.ai_ok_actions
  treat_missing_data  = "notBreaching"

  metric_query {
    id          = "tpm"
    expression  = "m_in + m_out"
    label       = "Sonnet TPM"
    return_data = true
  }
  metric_query {
    id = "m_in"
    metric {
      metric_name = "InputTokenCount"
      namespace   = "AWS/Bedrock"
      period      = 60
      stat        = "Sum"
      dimensions  = { ModelId = local.bedrock_sonnet }
    }
  }
  metric_query {
    id = "m_out"
    metric {
      metric_name = "OutputTokenCount"
      namespace   = "AWS/Bedrock"
      period      = 60
      stat        = "Sum"
      dimensions  = { ModelId = local.bedrock_sonnet }
    }
  }
  tags = { Name = "${var.project}-${var.env}-bedrock-sonnet-tpm-warn" }
}

resource "aws_cloudwatch_metric_alarm" "bedrock_sonnet_tpm_crit" {
  alarm_name          = "${var.project}-${var.env}-bedrock-sonnet-tpm-crit"
  alarm_description   = "Sonnet 4.6 — TPM at 80 % of 6M cap (4.8M/min). Throttling imminent."
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  threshold           = 4800000
  alarm_actions       = local.ai_alarm_actions
  ok_actions          = local.ai_ok_actions
  treat_missing_data  = "notBreaching"

  metric_query {
    id          = "tpm"
    expression  = "m_in + m_out"
    label       = "Sonnet TPM"
    return_data = true
  }
  metric_query {
    id = "m_in"
    metric {
      metric_name = "InputTokenCount"
      namespace   = "AWS/Bedrock"
      period      = 60
      stat        = "Sum"
      dimensions  = { ModelId = local.bedrock_sonnet }
    }
  }
  metric_query {
    id = "m_out"
    metric {
      metric_name = "OutputTokenCount"
      namespace   = "AWS/Bedrock"
      period      = 60
      stat        = "Sum"
      dimensions  = { ModelId = local.bedrock_sonnet }
    }
  }
  tags = { Name = "${var.project}-${var.env}-bedrock-sonnet-tpm-crit" }
}

resource "aws_cloudwatch_metric_alarm" "bedrock_nova_pro_tpm_warn" {
  alarm_name          = "${var.project}-${var.env}-bedrock-nova-pro-tpm-warn"
  alarm_description   = "Nova Pro — TPM at 50 % of 2M cap (1M/min). KB ingestion approaching cap."
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  threshold           = 1000000
  alarm_actions       = local.ai_alarm_actions
  ok_actions          = local.ai_ok_actions
  treat_missing_data  = "notBreaching"

  metric_query {
    id          = "tpm"
    expression  = "m_in + m_out"
    label       = "Nova Pro TPM"
    return_data = true
  }
  metric_query {
    id = "m_in"
    metric {
      metric_name = "InputTokenCount"
      namespace   = "AWS/Bedrock"
      period      = 60
      stat        = "Sum"
      dimensions  = { ModelId = local.bedrock_nova_pro }
    }
  }
  metric_query {
    id = "m_out"
    metric {
      metric_name = "OutputTokenCount"
      namespace   = "AWS/Bedrock"
      period      = 60
      stat        = "Sum"
      dimensions  = { ModelId = local.bedrock_nova_pro }
    }
  }
  tags = { Name = "${var.project}-${var.env}-bedrock-nova-pro-tpm-warn" }
}

resource "aws_cloudwatch_metric_alarm" "bedrock_nova_pro_tpm_crit" {
  alarm_name          = "${var.project}-${var.env}-bedrock-nova-pro-tpm-crit"
  alarm_description   = "Nova Pro — TPM at 80 % of 2M cap (1.6M/min). KB ingestion will throttle."
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  threshold           = 1600000
  alarm_actions       = local.ai_alarm_actions
  ok_actions          = local.ai_ok_actions
  treat_missing_data  = "notBreaching"

  metric_query {
    id          = "tpm"
    expression  = "m_in + m_out"
    label       = "Nova Pro TPM"
    return_data = true
  }
  metric_query {
    id = "m_in"
    metric {
      metric_name = "InputTokenCount"
      namespace   = "AWS/Bedrock"
      period      = 60
      stat        = "Sum"
      dimensions  = { ModelId = local.bedrock_nova_pro }
    }
  }
  metric_query {
    id = "m_out"
    metric {
      metric_name = "OutputTokenCount"
      namespace   = "AWS/Bedrock"
      period      = 60
      stat        = "Sum"
      dimensions  = { ModelId = local.bedrock_nova_pro }
    }
  }
  tags = { Name = "${var.project}-${var.env}-bedrock-nova-pro-tpm-crit" }
}

################################################################################
# Bedrock — Daily token cap (rolling 24h sum)
# Haiku: 27M  → warn 13.5M, crit 21.6M
# Sonnet: 10.8M (NOT ADJUSTABLE) → warn 5.4M, crit 8.6M
################################################################################

resource "aws_cloudwatch_metric_alarm" "bedrock_haiku_daily_warn" {
  alarm_name          = "${var.project}-${var.env}-bedrock-haiku-daily-warn"
  alarm_description   = "Haiku 4.5 — rolling 24h tokens at 50 % of 27M daily cap."
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  threshold           = 13500000
  alarm_actions       = local.ai_alarm_actions
  ok_actions          = local.ai_ok_actions
  treat_missing_data  = "notBreaching"

  metric_query {
    id          = "daily"
    expression  = "m_in + m_out"
    label       = "Haiku 24h tokens"
    return_data = true
  }
  metric_query {
    id = "m_in"
    metric {
      metric_name = "InputTokenCount"
      namespace   = "AWS/Bedrock"
      period      = 86400
      stat        = "Sum"
      dimensions  = { ModelId = local.bedrock_haiku }
    }
  }
  metric_query {
    id = "m_out"
    metric {
      metric_name = "OutputTokenCount"
      namespace   = "AWS/Bedrock"
      period      = 86400
      stat        = "Sum"
      dimensions  = { ModelId = local.bedrock_haiku }
    }
  }
  tags = { Name = "${var.project}-${var.env}-bedrock-haiku-daily-warn" }
}

resource "aws_cloudwatch_metric_alarm" "bedrock_haiku_daily_crit" {
  alarm_name          = "${var.project}-${var.env}-bedrock-haiku-daily-crit"
  alarm_description   = "Haiku 4.5 — rolling 24h tokens at 80 % of 27M daily cap."
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  threshold           = 21600000
  alarm_actions       = local.ai_alarm_actions
  ok_actions          = local.ai_ok_actions
  treat_missing_data  = "notBreaching"

  metric_query {
    id          = "daily"
    expression  = "m_in + m_out"
    label       = "Haiku 24h tokens"
    return_data = true
  }
  metric_query {
    id = "m_in"
    metric {
      metric_name = "InputTokenCount"
      namespace   = "AWS/Bedrock"
      period      = 86400
      stat        = "Sum"
      dimensions  = { ModelId = local.bedrock_haiku }
    }
  }
  metric_query {
    id = "m_out"
    metric {
      metric_name = "OutputTokenCount"
      namespace   = "AWS/Bedrock"
      period      = 86400
      stat        = "Sum"
      dimensions  = { ModelId = local.bedrock_haiku }
    }
  }
  tags = { Name = "${var.project}-${var.env}-bedrock-haiku-daily-crit" }
}

resource "aws_cloudwatch_metric_alarm" "bedrock_sonnet_daily_warn" {
  alarm_name          = "${var.project}-${var.env}-bedrock-sonnet-daily-warn"
  alarm_description   = "Sonnet 4.6 — rolling 24h tokens at 50 % of 10.8M daily cap (NOT adjustable)."
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  threshold           = 5400000
  alarm_actions       = local.ai_alarm_actions
  ok_actions          = local.ai_ok_actions
  treat_missing_data  = "notBreaching"

  metric_query {
    id          = "daily"
    expression  = "m_in + m_out"
    label       = "Sonnet 24h tokens"
    return_data = true
  }
  metric_query {
    id = "m_in"
    metric {
      metric_name = "InputTokenCount"
      namespace   = "AWS/Bedrock"
      period      = 86400
      stat        = "Sum"
      dimensions  = { ModelId = local.bedrock_sonnet }
    }
  }
  metric_query {
    id = "m_out"
    metric {
      metric_name = "OutputTokenCount"
      namespace   = "AWS/Bedrock"
      period      = 86400
      stat        = "Sum"
      dimensions  = { ModelId = local.bedrock_sonnet }
    }
  }
  tags = { Name = "${var.project}-${var.env}-bedrock-sonnet-daily-warn" }
}

resource "aws_cloudwatch_metric_alarm" "bedrock_sonnet_daily_crit" {
  alarm_name          = "${var.project}-${var.env}-bedrock-sonnet-daily-crit"
  alarm_description   = "Sonnet 4.6 — rolling 24h tokens at 80 % of 10.8M cap. NON-adjustable: requires workload shift."
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  threshold           = 8640000
  alarm_actions       = local.ai_alarm_actions
  ok_actions          = local.ai_ok_actions
  treat_missing_data  = "notBreaching"

  metric_query {
    id          = "daily"
    expression  = "m_in + m_out"
    label       = "Sonnet 24h tokens"
    return_data = true
  }
  metric_query {
    id = "m_in"
    metric {
      metric_name = "InputTokenCount"
      namespace   = "AWS/Bedrock"
      period      = 86400
      stat        = "Sum"
      dimensions  = { ModelId = local.bedrock_sonnet }
    }
  }
  metric_query {
    id = "m_out"
    metric {
      metric_name = "OutputTokenCount"
      namespace   = "AWS/Bedrock"
      period      = 86400
      stat        = "Sum"
      dimensions  = { ModelId = local.bedrock_sonnet }
    }
  }
  tags = { Name = "${var.project}-${var.env}-bedrock-sonnet-daily-crit" }
}

################################################################################
# Bedrock — Reliability (throttles + 5xx)
################################################################################

resource "aws_cloudwatch_metric_alarm" "bedrock_throttles" {
  alarm_name          = "${var.project}-${var.env}-bedrock-throttles"
  alarm_description   = "Bedrock InvocationThrottles > 0 sustained 3 min. Quota hit — file increase + back off."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  threshold           = 0
  metric_name         = "InvocationThrottles"
  namespace           = "AWS/Bedrock"
  period              = 60
  statistic           = "Sum"
  alarm_actions       = local.ai_alarm_actions
  ok_actions          = local.ai_ok_actions
  treat_missing_data  = "notBreaching"
  tags                = { Name = "${var.project}-${var.env}-bedrock-throttles" }
}

resource "aws_cloudwatch_metric_alarm" "bedrock_5xx" {
  alarm_name          = "${var.project}-${var.env}-bedrock-5xx"
  alarm_description   = "Bedrock InvocationServerErrors > 5 in 5 min. AWS-side fault."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  threshold           = 5
  metric_name         = "InvocationServerErrors"
  namespace           = "AWS/Bedrock"
  period              = 300
  statistic           = "Sum"
  alarm_actions       = local.ai_alarm_actions
  ok_actions          = local.ai_ok_actions
  treat_missing_data  = "notBreaching"
  tags                = { Name = "${var.project}-${var.env}-bedrock-5xx" }
}

################################################################################
# Comprehend Medical — TPS (10 cap) + reliability
################################################################################

resource "aws_cloudwatch_metric_alarm" "comprehend_tps_warn" {
  alarm_name          = "${var.project}-${var.env}-comprehend-tps-warn"
  alarm_description   = "Comprehend Medical — 50 % of 10 TPS cap (5/sec sustained over 1 min)."
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  threshold           = 300 # 5 TPS * 60 s
  metric_name         = "SuccessfulRequestCount"
  namespace           = "AWS/ComprehendMedical"
  period              = 60
  statistic           = "Sum"
  alarm_actions       = local.ai_alarm_actions
  ok_actions          = local.ai_ok_actions
  treat_missing_data  = "notBreaching"
  tags                = { Name = "${var.project}-${var.env}-comprehend-tps-warn" }
}

resource "aws_cloudwatch_metric_alarm" "comprehend_tps_crit" {
  alarm_name          = "${var.project}-${var.env}-comprehend-tps-crit"
  alarm_description   = "Comprehend Medical — 80 % of 10 TPS cap (8/sec sustained over 1 min)."
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  threshold           = 480 # 8 TPS * 60 s
  metric_name         = "SuccessfulRequestCount"
  namespace           = "AWS/ComprehendMedical"
  period              = 60
  statistic           = "Sum"
  alarm_actions       = local.ai_alarm_actions
  ok_actions          = local.ai_ok_actions
  treat_missing_data  = "notBreaching"
  tags                = { Name = "${var.project}-${var.env}-comprehend-tps-crit" }
}

resource "aws_cloudwatch_metric_alarm" "comprehend_throttles" {
  alarm_name          = "${var.project}-${var.env}-comprehend-throttles"
  alarm_description   = "Comprehend Medical ThrottledCount > 0 sustained 3 min. Quota hit."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  threshold           = 0
  metric_name         = "ThrottledCount"
  namespace           = "AWS/ComprehendMedical"
  period              = 60
  statistic           = "Sum"
  alarm_actions       = local.ai_alarm_actions
  ok_actions          = local.ai_ok_actions
  treat_missing_data  = "notBreaching"
  tags                = { Name = "${var.project}-${var.env}-comprehend-throttles" }
}

resource "aws_cloudwatch_metric_alarm" "comprehend_5xx" {
  alarm_name          = "${var.project}-${var.env}-comprehend-5xx"
  alarm_description   = "Comprehend Medical ServerErrorCount > 5 in 5 min."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  threshold           = 5
  metric_name         = "ServerErrorCount"
  namespace           = "AWS/ComprehendMedical"
  period              = 300
  statistic           = "Sum"
  alarm_actions       = local.ai_alarm_actions
  ok_actions          = local.ai_ok_actions
  treat_missing_data  = "notBreaching"
  tags                = { Name = "${var.project}-${var.env}-comprehend-5xx" }
}

################################################################################
# Latency — p95 per model (Bedrock-native metric)
################################################################################

resource "aws_cloudwatch_metric_alarm" "bedrock_haiku_p95_latency" {
  alarm_name          = "${var.project}-${var.env}-bedrock-haiku-p95-latency"
  alarm_description   = "Haiku 4.5 p95 InvocationLatency > 3s sustained 5 min."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 5
  threshold           = 3000
  metric_name         = "InvocationLatency"
  namespace           = "AWS/Bedrock"
  period              = 60
  extended_statistic  = "p95"
  dimensions          = { ModelId = local.bedrock_haiku }
  alarm_actions       = local.ai_alarm_actions
  ok_actions          = local.ai_ok_actions
  treat_missing_data  = "notBreaching"
  tags                = { Name = "${var.project}-${var.env}-bedrock-haiku-p95-latency" }
}

resource "aws_cloudwatch_metric_alarm" "bedrock_sonnet_p95_latency" {
  alarm_name          = "${var.project}-${var.env}-bedrock-sonnet-p95-latency"
  alarm_description   = "Sonnet 4.6 p95 InvocationLatency > 12s sustained 5 min."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 5
  threshold           = 12000
  metric_name         = "InvocationLatency"
  namespace           = "AWS/Bedrock"
  period              = 60
  extended_statistic  = "p95"
  dimensions          = { ModelId = local.bedrock_sonnet }
  alarm_actions       = local.ai_alarm_actions
  ok_actions          = local.ai_ok_actions
  treat_missing_data  = "notBreaching"
  tags                = { Name = "${var.project}-${var.env}-bedrock-sonnet-p95-latency" }
}

################################################################################
# App-level — ai.call status="error" rate (via CloudWatch log metric filter)
#
# The Spring-formatted log line contains the JSON payload; the filter pattern
# matches lines that include both marker=ai.call and status=error.
################################################################################

resource "aws_cloudwatch_log_metric_filter" "ai_call_errors" {
  name           = "${var.project}-${var.env}-ai-call-errors"
  log_group_name = local.app_log_group
  pattern        = "\"\\\"marker\\\":\\\"ai.call\\\"\" \"\\\"status\\\":\\\"error\\\"\""

  metric_transformation {
    name          = "AiCallErrors"
    namespace     = "Vocuone/AI/${var.env}"
    value         = "1"
    default_value = "0"
    unit          = "Count"
  }
}

resource "aws_cloudwatch_metric_alarm" "ai_call_error_rate" {
  alarm_name          = "${var.project}-${var.env}-ai-call-error-rate"
  alarm_description   = "ai.call status=error events > 5 in 5 min. App-side AI failures."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  threshold           = 5
  metric_name         = aws_cloudwatch_log_metric_filter.ai_call_errors.metric_transformation[0].name
  namespace           = aws_cloudwatch_log_metric_filter.ai_call_errors.metric_transformation[0].namespace
  period              = 300
  statistic           = "Sum"
  alarm_actions       = local.ai_alarm_actions
  ok_actions          = local.ai_ok_actions
  treat_missing_data  = "notBreaching"
  tags                = { Name = "${var.project}-${var.env}-ai-call-error-rate" }

  depends_on = [aws_cloudwatch_log_metric_filter.ai_call_errors]
}

################################################################################
# Cost proxy — total daily Bedrock tokens (cost-runaway tripwire)
# Threshold computed off-the-cuff: ~$5 per million tokens average blended price.
# Adjust after 1 week of observed real spend.
#   stage: 10M tokens/day  ≈ $50/day
#   prod:  40M tokens/day  ≈ $200/day
################################################################################

resource "aws_cloudwatch_metric_alarm" "bedrock_daily_token_cost_proxy" {
  alarm_name          = "${var.project}-${var.env}-bedrock-daily-cost-proxy"
  alarm_description   = "Total Bedrock tokens in last 24h exceeded budget proxy. Review per-customer breakdown in Grafana."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  threshold           = var.env == "prod" ? 40000000 : 10000000
  alarm_actions       = local.ai_alarm_actions
  ok_actions          = local.ai_ok_actions
  treat_missing_data  = "notBreaching"

  metric_query {
    id          = "total"
    expression  = "haiku_in + haiku_out + sonnet_in + sonnet_out + nova_in + nova_out"
    label       = "Bedrock total tokens / 24h"
    return_data = true
  }
  metric_query {
    id = "haiku_in"
    metric {
      metric_name = "InputTokenCount"
      namespace   = "AWS/Bedrock"
      period      = 86400
      stat        = "Sum"
      dimensions  = { ModelId = local.bedrock_haiku }
    }
  }
  metric_query {
    id = "haiku_out"
    metric {
      metric_name = "OutputTokenCount"
      namespace   = "AWS/Bedrock"
      period      = 86400
      stat        = "Sum"
      dimensions  = { ModelId = local.bedrock_haiku }
    }
  }
  metric_query {
    id = "sonnet_in"
    metric {
      metric_name = "InputTokenCount"
      namespace   = "AWS/Bedrock"
      period      = 86400
      stat        = "Sum"
      dimensions  = { ModelId = local.bedrock_sonnet }
    }
  }
  metric_query {
    id = "sonnet_out"
    metric {
      metric_name = "OutputTokenCount"
      namespace   = "AWS/Bedrock"
      period      = 86400
      stat        = "Sum"
      dimensions  = { ModelId = local.bedrock_sonnet }
    }
  }
  metric_query {
    id = "nova_in"
    metric {
      metric_name = "InputTokenCount"
      namespace   = "AWS/Bedrock"
      period      = 86400
      stat        = "Sum"
      dimensions  = { ModelId = local.bedrock_nova_pro }
    }
  }
  metric_query {
    id = "nova_out"
    metric {
      metric_name = "OutputTokenCount"
      namespace   = "AWS/Bedrock"
      period      = 86400
      stat        = "Sum"
      dimensions  = { ModelId = local.bedrock_nova_pro }
    }
  }
  tags = { Name = "${var.project}-${var.env}-bedrock-daily-cost-proxy" }
}
