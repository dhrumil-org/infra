aws_region        = "us-east-1"
aws_account_id    = "499290259511"
project           = "vocanote"
tf_state_bucket   = "vocanote-terraform-state-499290259511"
tf_dynamodb_table = "vocanote-terraform-locks"

s3_buckets = [
  "dev-vocanote-ai-landingpage",
  "stage-admin-vocanote-ai",
  "prod-admin-vocanote-ai",
  "stage-vocanote-ai-frontend",
  "prod-vocanote-ai-frontend"
]

secret_names = [
  "vocuone/stage/admin",
  "vocuone/prod/admin",
  "vocuone/stage/frontend",
  "vocuone/prod/frontend"
]
