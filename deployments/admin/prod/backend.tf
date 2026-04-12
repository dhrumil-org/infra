terraform {
  backend "s3" {
    bucket         = "vocanote-terraform-state-499290259511"
    key            = "admin/prod/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "vocanote-terraform-locks"
    encrypt        = true
  }
}
