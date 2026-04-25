terraform {
  backend "s3" {
    bucket       = "vocuone-terraform-state-499290259511"
    key          = "ecs/prod/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}
