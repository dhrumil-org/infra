terraform {
  backend "s3" {
    bucket         = "vocuone-terraform-state-499290259511"
    key            = "shared/iam/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "vocuone-terraform-locks"
    encrypt        = true
  }
}
