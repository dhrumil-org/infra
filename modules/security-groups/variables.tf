variable "env" {
  description = "Environment name"
  type        = string
}

variable "project" {
  description = "Project name"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "container_port" {
  description = "Container port for the application"
  type        = number
  default     = 8080
}

variable "vpc_cidr" {
  description = "VPC CIDR block (for internal egress rules like RDS)"
  type        = string
}
