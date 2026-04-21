env            = "stage"
project        = "vocuone"
aws_region     = "us-east-1"
aws_account_id = "499290259511"

# VPC
vpc_cidr             = "10.1.0.0/16"
public_subnet_cidrs  = ["10.1.1.0/24", "10.1.2.0/24"]
private_subnet_cidrs = ["10.1.10.0/24", "10.1.11.0/24"]
availability_zones   = ["us-east-1a", "us-east-1b"]

# ECS
instance_type        = "t3.medium"
asg_min_size         = 1
asg_max_size         = 3
asg_desired_capacity = 1
container_image      = "vocuone-stage-app:latest"
container_port       = 8080
task_cpu             = 512
task_memory          = 2048

# ALB
acm_certificate_arn = "arn:aws:acm:us-east-1:499290259511:certificate/76546c9c-daec-44d0-9544-a2ff36dac831"
health_check_path   = "/health"

# RDS
db_engine_version          = "16.4"
db_instance_class          = "db.t3.micro"
db_allocated_storage       = 20
db_name                    = "appdb"
db_master_username         = "dbadmin"
db_multi_az                = false
db_backup_retention_period = 7
db_deletion_protection     = false
db_skip_final_snapshot     = true
db_apply_immediately       = true

# App-facing DB secret (matches what Spring Boot reads)
app_db_secret_name = "vocuone/stage/db"
app_db_username    = "vocuone_service_user"

# Spring profile — "stage" for IAM token auth, "dev" for password auth
spring_profile = "stage"

# App environment variables
app_email_redirect_url   = "https://app.vocuone.ai"
app_cors_allowed_origins = "https://app.vocanote.ai,https://vocanote.ai,https://stage-app.vocuone.ai"

# Secrets the app reads at runtime via AWS SDK
task_secret_arns = [
  "arn:aws:secretsmanager:us-east-1:499290259511:secret:vocuone/stage/*",
  "arn:aws:secretsmanager:us-east-1:499290259511:secret:vocuone/prod/*",
]

# Secrets Manager — 0 allows clean destroy/recreate without 7-day wait
secrets_recovery_window_in_days = 0

# Synthetics canary — script is deployed by GitHub Actions separately
api_domain                   = "api.stage.vocuone.ai"
canary_schedule_rate_minutes = 60
canary_login_email           = ""
canary_login_password        = ""
