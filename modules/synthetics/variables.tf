variable "project" {
  description = "Project name"
  type        = string
}

variable "env" {
  description = "Environment name"
  type        = string
}

variable "base_url" {
  description = "Base URL of the API to monitor (e.g. https://api.stage.vocuone.ai)"
  type        = string
}

variable "login_email" {
  description = "Canary test account email for authenticated checks (leave empty to skip auth step)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "login_password" {
  description = "Canary test account password for authenticated checks (leave empty to skip auth step)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "schedule_rate_minutes" {
  description = "How often to run the canary in minutes (minimum 1)"
  type        = number
  default     = 5
}

variable "runtime_version" {
  description = "CloudWatch Synthetics runtime version"
  type        = string
  default     = "syn-nodejs-puppeteer-9.1"
}

variable "extra_env_vars" {
  description = "Additional environment variables to pass to the canary (e.g. SKIP_CONVERSATION_ON_FORBIDDEN)"
  type        = map(string)
  default     = {}
}
