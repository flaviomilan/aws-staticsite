terraform {
  required_version = ">= 1.10, < 2.0"
  required_providers { aws = { source = "hashicorp/aws", version = "~> 6.38" } }
  backend "s3" {}
}
provider "aws" { region = var.aws_region }
data "aws_caller_identity" "current" {}
variable "aws_region" { type = string }
variable "repository" { type = string }
variable "environment" { type = string }
variable "name_prefix" { type = string }
variable "hosted_zone_id" { type = string }
variable "bucket_name" { type = string }
variable "release_bucket_name" { type = string }
variable "distribution_id" { type = string }
variable "domain" { type = string }
variable "aliases" {
  type    = list(string)
  default = []
}
variable "state_bucket_name" { type = string }
variable "site_state_key" { type = string }
variable "enable_waf" {
  type    = bool
  default = false
}
variable "enable_monitoring" {
  type    = bool
  default = false
}
variable "enable_access_logs" {
  type    = bool
  default = false
}
variable "enable_additional_metrics" {
  type    = bool
  default = false
}
module "identity" {
  source                     = "../../modules/github-oidc"
  repository                 = var.repository
  environment                = var.environment
  branch                     = "main"
  name_prefix                = var.name_prefix
  oidc_provider_arn          = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/token.actions.githubusercontent.com"
  bucket_arn                 = "arn:aws:s3:::${var.bucket_name}"
  release_bucket_arn         = "arn:aws:s3:::${var.release_bucket_name}"
  distribution_arn           = "arn:aws:cloudfront::${data.aws_caller_identity.current.account_id}:distribution/${var.distribution_id}"
  infrastructure_policy_json = jsonencode({ Version = "2012-10-17", Statement = local.infrastructure_statements })
}
output "infrastructure_role_arn" { value = module.identity.infrastructure_role_arn }
output "publication_role_arn" { value = module.identity.publication_role_arn }
output "infrastructure_policy_json" { value = jsonencode({ Version = "2012-10-17", Statement = local.infrastructure_statements }) }
