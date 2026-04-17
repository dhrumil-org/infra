terraform {
  backend "s3" {
    bucket       = "vocanote-terraform-state-499290259511"
    key          = "shared/iam-stage/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}
