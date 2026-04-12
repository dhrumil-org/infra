module "s3" {
  source                      = "../../../modules/s3-frontend"
  env                         = var.env
  bucket_name                 = var.bucket_name
  cloudfront_distribution_arn = module.cloudfront.distribution_arn
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
