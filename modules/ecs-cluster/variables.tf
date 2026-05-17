variable "env" {
  description = "Environment name"
  type        = string
}

variable "project" {
  description = "Project name"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for ECS instances"
  type        = list(string)
}

variable "ecs_security_group_id" {
  description = "Security group ID for ECS instances"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type for ECS"
  type        = string
  default     = "t3.medium"
}

variable "asg_min_size" {
  description = "Minimum ASG size"
  type        = number
  default     = 1
}

variable "asg_max_size" {
  description = "Maximum ASG size"
  type        = number
  default     = 3
}

variable "asg_desired_capacity" {
  description = "Desired ASG capacity"
  type        = number
  default     = 1
}

variable "ebs_kms_key_arn" {
  description = "KMS key ARN to encrypt ECS instance root EBS volumes. Empty string falls back to account-default EBS encryption (still encrypted, but with the AWS-owned alias/aws/ebs key). HIPAA-compliant either way; CMK preferred for audit trail."
  type        = string
  default     = ""
}

variable "ebs_volume_size_gb" {
  description = "Root EBS volume size (GB) for ECS instances. AL2023 ECS-optimized AMI default is 30 GB; bump if you need more room for container images."
  type        = number
  default     = 30
}
