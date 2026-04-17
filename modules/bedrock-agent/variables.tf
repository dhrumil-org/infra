variable "env" {
  description = "Environment name"
  type        = string
}

variable "project" {
  description = "Project name"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "aws_account_id" {
  description = "AWS account ID"
  type        = string
}

################################################################################
# Agent
################################################################################

variable "agent_name" {
  description = "Agent name suffix. Full name: {project}-{env}-{agent_name}-agent"
  type        = string
  default     = "assistant"
}

variable "agent_description" {
  description = "Agent description"
  type        = string
  default     = ""
}

variable "foundation_model" {
  description = "Bedrock foundation model ID for the agent"
  type        = string
  # Claude Sonnet — cross-region inference (matches dev screenshot)
  default = "us.anthropic.claude-sonnet-4-5-20250929-v1:0"
}

variable "instruction" {
  description = "Instructions that define the agent's behaviour"
  type        = string
}

variable "idle_session_ttl_seconds" {
  description = "Session idle timeout in seconds"
  type        = number
  default     = 600
}

################################################################################
# Knowledge Base association
################################################################################

variable "knowledge_base_id" {
  description = "Bedrock Knowledge Base ID to associate with this agent"
  type        = string
}

variable "knowledge_base_description" {
  description = "Description shown in the agent for this KB association"
  type        = string
  default     = "Use this knowledge base to answer questions"
}

################################################################################
# Alias
################################################################################

variable "alias_name" {
  description = "Agent alias name (e.g. 'stage', 'v1')"
  type        = string
  default     = "live"
}

variable "alias_description" {
  description = "Agent alias description"
  type        = string
  default     = ""
}
