################################################################################
# KMS — encrypts the frontend S3 bucket (no PHI, but stays consistent with the
# rest of the env's "encrypt everything" posture for HIPAA-clean audit answers)
################################################################################

resource "aws_kms_key" "frontend" {
  description             = "KMS key for ${var.project}-${var.env} frontend S3 bucket"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  tags = {
    Name = "${var.project}-${var.env}-frontend"
  }
}

resource "aws_kms_alias" "frontend" {
  name          = "alias/${var.project}-${var.env}-frontend"
  target_key_id = aws_kms_key.frontend.key_id
}

################################################################################
# Frontend S3 bucket + CloudFront distribution
################################################################################

module "s3" {
  source                      = "../../../modules/s3-frontend"
  env                         = var.env
  bucket_name                 = var.bucket_name
  cloudfront_distribution_arn = module.cloudfront.distribution_arn
  kms_key_arn                 = aws_kms_key.frontend.arn
}

module "cloudfront" {
  source                    = "../../../modules/cloudfront"
  env                       = var.env
  project                   = var.project
  s3_bucket_id              = module.s3.bucket_id
  s3_bucket_regional_domain = module.s3.bucket_regional_domain
  aliases                   = var.aliases
  acm_certificate_arn       = var.acm_certificate_arn
  price_class               = var.price_class
}

################################################################################
# Outputs — handy for CI / DNS setup
################################################################################

output "cloudfront_domain_name" {
  description = "Point app.vocuone.ai CNAME at this CloudFront domain"
  value       = module.cloudfront.domain_name
}

output "cloudfront_distribution_id" {
  description = "Distribution ID — used by frontend CI to invalidate cache after deploy"
  value       = module.cloudfront.distribution_id
}

output "frontend_bucket_name" {
  description = "Bucket the frontend CI uploads built assets to"
  value       = module.s3.bucket_id
}
