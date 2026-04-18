aws_region        = "us-east-1"
aws_account_id    = "499290259511"
env               = "prod"
project           = "vocanote-frontend"
bucket_name       = "prod-vocanote-ai-frontend"
secret_name       = "vocuone/prod/frontend"
price_class       = "PriceClass_100"
tf_state_bucket   = "vocuone-terraform-state-499290259511"
tf_dynamodb_table = "vocuone-terraform-locks"

aliases             = []
acm_certificate_arn = ""

# injected via GitHub Actions secrets
secret_values = {
  NEXT_PUBLIC_API_BASE_URL = ""
  NEXT_PUBLIC_APP_URL      = ""
  NEXT_PUBLIC_SITE_URL     = ""
}
