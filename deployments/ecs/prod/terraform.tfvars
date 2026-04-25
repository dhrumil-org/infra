env            = "prod"
project        = "vocuone"
aws_region     = "us-east-1"
aws_account_id = "499290259511"

# VPC — non-overlapping with stage (10.1.0.0/16)
vpc_cidr             = "10.2.0.0/16"
public_subnet_cidrs  = ["10.2.1.0/24", "10.2.2.0/24"]
private_subnet_cidrs = ["10.2.10.0/24", "10.2.11.0/24"]
availability_zones   = ["us-east-1a", "us-east-1b"]

# ECS — sized up for prod
instance_type        = "t3.large"
asg_min_size         = 2
asg_max_size         = 6
asg_desired_capacity = 2

# Prod ECS pulls from vocuone-prod-app ECR repo (created by the ecr module).
# Bootstrap: until your app CI runs on main and pushes here, copy the stage
# image one-time:
#   STAGE=499290259511.dkr.ecr.us-east-1.amazonaws.com/vocuone-stage-app:latest
#   PROD=499290259511.dkr.ecr.us-east-1.amazonaws.com/vocuone-prod-app:latest
#   aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin 499290259511.dkr.ecr.us-east-1.amazonaws.com
#   docker pull $STAGE && docker tag $STAGE $PROD && docker push $PROD
container_image = "vocuone-prod-app:latest"
container_port  = 8080
task_cpu        = 1024
task_memory     = 4096

# ALB — same wildcard *.vocuone.ai cert covers api.vocuone.ai
acm_certificate_arn = "arn:aws:acm:us-east-1:499290259511:certificate/76546c9c-daec-44d0-9544-a2ff36dac831"
health_check_path   = "/health"

# RDS — kept aligned with stage (Multi-AZ off, 7-day backups, apply immediately)
# Flip db_multi_az + db_backup_retention_period when ready to harden prod.
db_engine_version          = "16.6"
db_instance_class          = "db.t3.medium"
db_allocated_storage       = 50
db_name                    = "appdb"
db_master_username         = "dbadmin"
db_multi_az                = false
db_backup_retention_period = 7
db_deletion_protection     = true
db_skip_final_snapshot     = false
db_apply_immediately       = true

# App-facing DB secret (matches what Spring Boot reads)
app_db_secret_name = "vocuone/prod/db"
app_db_username    = "vocuone_service_user"

# Spring profile — "prod" for IAM token auth + prod-specific config
spring_profile = "prod"

# App environment variables
app_email_redirect_url   = "https://app.vocuone.ai"
app_cors_allowed_origins = "https://app.vocuone.ai,https://vocuone.ai"

# Secrets the app reads at runtime via AWS SDK
task_secret_arns = [
  "arn:aws:secretsmanager:us-east-1:499290259511:secret:vocuone/prod/*",
]

# Secrets Manager — kept aligned with stage (0-day window allows clean recreate)
secrets_recovery_window_in_days = 0

# Public API
api_domain                   = "api.vocuone.ai"
app_cookie_domain            = "vocuone.ai"
canary_schedule_rate_minutes = 60
waf_rate_limit_per_ip        = 2000
alerts_email                 = "developer@vocuone.ai"
