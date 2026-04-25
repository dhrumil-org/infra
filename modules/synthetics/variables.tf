variable "project" {
  description = "Project name"
  type        = string
}

variable "env" {
  description = "Environment name"
  type        = string
}

variable "base_url" {
  description = "Base URL of the API to monitor (e.g. https://api.vocanote.ai)"
  type        = string
}

variable "login_email" {
  description = "Canary test account email"
  type        = string
  default     = ""
  sensitive   = true
}

variable "login_password" {
  description = "Canary test account password"
  type        = string
  default     = ""
  sensitive   = true
}

variable "schedule_rate_minutes" {
  description = "How often to run the canary in minutes"
  type        = number
  default     = 60
}

variable "runtime_version" {
  description = "CloudWatch Synthetics runtime version"
  type        = string
  default     = "syn-nodejs-puppeteer-15.0"
}

variable "extra_env_vars" {
  description = "Additional environment variables for the canary"
  type        = map(string)
  default     = {}
}

variable "alarm_sns_topic_arn" {
  description = "SNS topic ARN to notify on canary alarm state changes"
  type        = string
  default     = ""
}
