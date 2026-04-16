output "agent_id" {
  description = "Bedrock Agent ID"
  value       = aws_bedrockagent_agent.this.agent_id
}

output "agent_arn" {
  description = "Bedrock Agent ARN"
  value       = aws_bedrockagent_agent.this.agent_arn
}

output "agent_name" {
  description = "Bedrock Agent name"
  value       = aws_bedrockagent_agent.this.agent_name
}

output "agent_alias_id" {
  description = "Agent alias ID — use this in your app (InvokeAgent calls)"
  value       = aws_bedrockagent_agent_alias.this.agent_alias_id
}

output "agent_alias_arn" {
  description = "Agent alias ARN"
  value       = aws_bedrockagent_agent_alias.this.agent_alias_arn
}

output "agent_role_arn" {
  description = "IAM role ARN used by the agent"
  value       = aws_iam_role.agent.arn
}
