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
container_port       = 80
task_cpu             = 512
task_memory          = 1024

# ALB
acm_certificate_arn = "arn:aws:acm:us-east-1:499290259511:certificate/76546c9c-daec-44d0-9544-a2ff36dac831"
health_check_path   = "/"
