env            = "stage"
project        = "vocanote"
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
container_image      = "nginx:latest"
container_port       = 8080
task_cpu             = 512
task_memory          = 1024

# ALB
acm_certificate_arn = "arn:aws:acm:us-east-1:499290259511:certificate/76546c9c-daec-44d0-9544-a2ff36dac831"
health_check_path   = "/"

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
app_db_username    = "vocanote_service_user"
