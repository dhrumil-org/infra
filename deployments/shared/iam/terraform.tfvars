aws_region        = "us-east-1"
aws_account_id    = "499290259511"
project           = "vocuone"
tf_state_bucket   = "vocuone-terraform-state-499290259511"
tf_dynamodb_table = "vocuone-terraform-locks"

s3_buckets = [
  "dev-vocuone-ai-landingpage",
  "stage-admin-vocuone-ai",
  "prod-admin-vocuone-ai",
  "stage-vocuone-ai-frontend",
  "prod-vocuone-ai-frontend"
]

secret_names = [
  "vocuone/stage/admin",
  "vocuone/prod/admin",
  "vocuone/stage/frontend",
  "vocuone/prod/frontend"
]
