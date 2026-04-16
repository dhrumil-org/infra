locals {
  name_prefix = "${var.project}-${var.env}"
  agent_name  = "${local.name_prefix}-${var.agent_name}-agent"
}

################################################################################
# IAM Role — Bedrock Agent execution role
################################################################################

data "aws_iam_policy_document" "agent_assume" {
  statement {
    sid     = "AllowBedrockAgentAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["bedrock.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.aws_account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:bedrock:${var.aws_region}:${var.aws_account_id}:agent/*"]
    }
  }
}

resource "aws_iam_role" "agent" {
  name               = "${local.name_prefix}-bedrock-agent-role"
  assume_role_policy = data.aws_iam_policy_document.agent_assume.json
  tags               = { Name = "${local.name_prefix}-bedrock-agent-role" }
}

data "aws_iam_policy_document" "agent_policy" {
  # Invoke the foundation model
  statement {
    sid    = "AllowFoundationModelInvoke"
    effect = "Allow"
    actions = [
      "bedrock:InvokeModel",
      "bedrock:InvokeModelWithResponseStream",
    ]
    resources = [
      "arn:aws:bedrock:${var.aws_region}::foundation-model/${var.foundation_model}",
      # Allow cross-region inference profiles
      "arn:aws:bedrock:*::foundation-model/*",
      "arn:aws:bedrock:${var.aws_region}:${var.aws_account_id}:inference-profile/*",
    ]
  }

  # Query the associated Knowledge Base
  statement {
    sid    = "AllowKBRetrieve"
    effect = "Allow"
    actions = [
      "bedrock:Retrieve",
      "bedrock:RetrieveAndGenerate",
    ]
    resources = [
      "arn:aws:bedrock:${var.aws_region}:${var.aws_account_id}:knowledge-base/${var.knowledge_base_id}",
    ]
  }

  # Allow agent to manage itself (needed for alias creation)
  statement {
    sid    = "AllowAgentManagement"
    effect = "Allow"
    actions = [
      "bedrock:CreateAgent",
      "bedrock:UpdateAgent",
      "bedrock:PrepareAgent",
      "bedrock:GetAgent",
      "bedrock:ListAgents",
    ]
    resources = ["arn:aws:bedrock:${var.aws_region}:${var.aws_account_id}:agent/*"]
  }
}

resource "aws_iam_role_policy" "agent" {
  name   = "${local.name_prefix}-bedrock-agent-policy"
  role   = aws_iam_role.agent.id
  policy = data.aws_iam_policy_document.agent_policy.json
}

################################################################################
# Bedrock Agent
################################################################################

resource "aws_bedrockagent_agent" "this" {
  agent_name              = local.agent_name
  description             = var.agent_description != "" ? var.agent_description : "VocaNote ${var.env} AI assistant"
  agent_resource_role_arn = aws_iam_role.agent.arn
  foundation_model        = var.foundation_model
  instruction             = var.instruction
  idle_session_ttl_in_seconds = var.idle_session_ttl_seconds

  # Matches dev agent: no action groups, default orchestration
  prepare_agent = true

  tags = { Name = local.agent_name }

  depends_on = [aws_iam_role_policy.agent]
}

################################################################################
# Knowledge Base Association
################################################################################

resource "aws_bedrockagent_agent_knowledge_base_association" "this" {
  agent_id             = aws_bedrockagent_agent.this.id
  knowledge_base_id    = var.knowledge_base_id
  description          = var.knowledge_base_description
  knowledge_base_state = "ENABLED"
}

################################################################################
# Agent Alias — stable endpoint for your app to call
################################################################################

resource "aws_bedrockagent_agent_alias" "this" {
  agent_id         = aws_bedrockagent_agent.this.id
  agent_alias_name = var.alias_name
  description      = var.alias_description != "" ? var.alias_description : "${var.env} alias"

  tags = { Name = "${local.agent_name}-${var.alias_name}" }
}
