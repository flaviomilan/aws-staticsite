terraform {
  required_version = ">= 1.10, < 2.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.38" }
  }
  backend "s3" {}
}
provider "aws" { region = var.aws_region }
provider "aws" {
  alias  = "edge"
  region = "us-east-1"
}
module "site" {
  source                    = "../modules/static-site"
  providers                 = { aws = aws, aws.edge = aws.edge }
  hosted_zone_id            = aws_route53_zone.public_zone.zone_id
  aliases                   = ["www.${var.domain}"]
  aws_region                = var.aws_region
  domain                    = var.domain
  bucket_name               = var.bucket_name
  project_name              = var.project_name
  environment               = var.environment
  enable_waf                = var.enable_waf
  enable_monitoring         = var.enable_monitoring
  enable_s3_versioning      = var.enable_s3_versioning
  notification_email        = var.notification_email
  csp_policy                = var.csp_policy
  waf_rate_limit            = var.waf_rate_limit
  minimum_tls_version       = var.minimum_tls_version
  routing_mode              = var.routing_mode
  hsts_include_subdomains   = var.hsts_include_subdomains
  hsts_preload              = var.hsts_preload
  redirect_aliases          = var.redirect_aliases
  enable_access_logs        = var.enable_access_logs
  enable_additional_metrics = coalesce(var.enable_additional_metrics, var.enable_monitoring)
  waf_mode                  = "block"
  block_anonymous_ips       = true
}
