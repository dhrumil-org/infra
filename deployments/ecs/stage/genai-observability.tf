################################################################################
# GenAI Observability — AWS Distro for OpenTelemetry (ADOT) Java agent
#
# Auto-instruments AWS SDK calls (Bedrock, Comprehend) and emits OTel GenAI
# semantic spans into CloudWatch Application Signals → CloudWatch console
# (Application Signals → GenAI view).
#
# Requires:
#   1. ADOT Java agent included in the container image (see Dockerfile change
#      in vocanote-be: COPY the agent jar into the runtime image at /app/aws-opentelemetry-agent.jar).
#   2. Env vars below appended to the ECS task definition (main.tf concats
#      local.genai_observability_env into local.app_environment_variables).
#   3. IAM permissions on the ECS task role (this file).
#
# Cost: at current volume ~$1–5/month for Application Signals span ingestion.
################################################################################

# Look up the existing ECS task role (created by the ecs-service module).
data "aws_iam_role" "ecs_task_observability" {
  name = "${var.project}-${var.env}-app-task-role"
}

data "aws_iam_policy_document" "genai_observability" {
  statement {
    sid    = "ApplicationSignals"
    effect = "Allow"
    actions = [
      "cloudwatch:PutMetricData",
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "cloudwatch:namespace"
      values   = ["ApplicationSignals", "AWS/ApplicationSignals"]
    }
  }

  statement {
    sid    = "XRayForADOT"
    effect = "Allow"
    actions = [
      "xray:PutTraceSegments",
      "xray:PutTelemetryRecords",
      "xray:GetSamplingRules",
      "xray:GetSamplingTargets",
      "xray:GetSamplingStatisticSummaries",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "OTelLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
    ]
    resources = [
      "arn:aws:logs:${var.aws_region}:${var.aws_account_id}:log-group:/aws/application-signals/data:*",
      "arn:aws:logs:${var.aws_region}:${var.aws_account_id}:log-group:/aws/application-signals/data",
    ]
  }
}

resource "aws_iam_role_policy" "genai_observability" {
  name   = "${var.project}-${var.env}-genai-observability"
  role   = data.aws_iam_role.ecs_task_observability.id
  policy = data.aws_iam_policy_document.genai_observability.json
}

################################################################################
# Env vars merged into the ECS task definition via main.tf:
#
#   locals {
#     app_environment_variables = concat(
#       local.app_environment_variables_base,
#       local.genai_observability_env,
#     )
#   }
################################################################################

locals {
  genai_observability_env = [
    {
      name  = "JAVA_TOOL_OPTIONS"
      value = "-javaagent:/app/aws-opentelemetry-agent.jar"
    },
    {
      name  = "OTEL_RESOURCE_ATTRIBUTES"
      value = "service.name=vocanote-be,deployment.environment=${var.env}"
    },
    {
      name  = "OTEL_AWS_APPLICATION_SIGNALS_ENABLED"
      value = "true"
    },
    {
      name  = "OTEL_AWS_APPLICATION_SIGNALS_RUNTIME_ENABLED"
      value = "true"
    },
    {
      name  = "OTEL_METRICS_EXPORTER"
      value = "none"
    },
    {
      name  = "OTEL_LOGS_EXPORTER"
      value = "none"
    },
    {
      name  = "OTEL_AWS_APPLICATION_SIGNALS_EXPORTER_ENDPOINT"
      value = "http://localhost:4316/v1/metrics"
    },
    {
      name  = "OTEL_EXPORTER_OTLP_PROTOCOL"
      value = "http/protobuf"
    },
    {
      name  = "OTEL_EXPORTER_OTLP_TRACES_ENDPOINT"
      value = "http://localhost:4316/v1/traces"
    },
    {
      name  = "OTEL_TRACES_SAMPLER"
      value = "xray"
    },
    {
      name  = "OTEL_TRACES_SAMPLER_ARG"
      value = "endpoint=http://localhost:2000"
    },
    {
      name  = "OTEL_PROPAGATORS"
      value = "tracecontext,baggage,b3,xray"
    },
  ]
}

output "genai_observability_env_count" {
  description = "Number of env vars added by GenAI Observability"
  value       = length(local.genai_observability_env)
}
