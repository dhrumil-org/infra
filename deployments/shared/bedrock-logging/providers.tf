terraform {
  # 1.7+ required for `removed` blocks used during the migration from
  # deployments/bedrock/stage/invocation-logging.tf into this stack.
  required_version = ">= 1.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.100"
    }
  }

  backend "s3" {
    bucket       = "vocuone-terraform-state-499290259511"
    key          = "shared/bedrock-logging/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = var.project
      Scope     = "account-wide" # captures stage AND prod Bedrock traffic
      ManagedBy = "terraform"
    }
  }
}
