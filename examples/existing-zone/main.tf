terraform {
  required_version = ">= 1.10, < 2.0"
  required_providers { aws = { source = "hashicorp/aws", version = "~> 6.38" } }
  backend "s3" {}
}
provider "aws" { region = var.aws_region }
provider "aws" {
  alias  = "edge"
  region = "us-east-1"
}
module "site" {
  source                    = "../../modules/static-site"
  providers                 = { aws = aws, aws.edge = aws.edge }
  aws_region                = var.aws_region
  bucket_name               = var.bucket_name
  domain                    = var.domain
  enable_waf                = var.enable_waf
  project_name              = var.project_name
  environment               = var.environment
  csp_policy                = var.csp_policy
  waf_rate_limit            = var.waf_rate_limit
  enable_monitoring         = var.enable_monitoring
  notification_email        = var.notification_email
  minimum_tls_version       = var.minimum_tls_version
  enable_s3_versioning      = var.enable_s3_versioning
  hosted_zone_id            = var.hosted_zone_id
  aliases                   = var.aliases
  routing_mode              = var.routing_mode
  canonical_domain          = var.canonical_domain
  redirect_aliases          = var.redirect_aliases
  hsts_include_subdomains   = var.hsts_include_subdomains
  hsts_preload              = var.hsts_preload
  enable_additional_metrics = var.enable_additional_metrics
  enable_access_logs        = var.enable_access_logs
  log_retention_days        = var.log_retention_days
  waf_mode                  = var.waf_mode
  block_anonymous_ips       = var.block_anonymous_ips
}
output "bucket_id" { value = module.site.bucket_id }
output "bucket_arn" { value = module.site.bucket_arn }
output "release_bucket_id" { value = module.site.release_bucket_id }
output "cloudfront_distribution_id" { value = module.site.cloudfront_distribution_id }
output "cloudfront_domain_name" { value = module.site.cloudfront_domain_name }
output "acm_certificate_arn" { value = module.site.acm_certificate_arn }
output "site_url" { value = module.site.site_url }
output "enabled_features" { value = module.site.enabled_features }
