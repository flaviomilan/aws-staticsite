terraform {
  required_version = ">= 1.10, < 2.0"
  required_providers { aws = { source = "hashicorp/aws", version = "~> 6.38" } }
  backend "s3" {}
}
provider "aws" { region = "us-east-1" }
variable "domain" { type = string }
resource "aws_route53_zone" "site" {
  name          = var.domain
  force_destroy = false
  tags          = { ManagedBy = "terraform" }
}
output "hosted_zone_id" { value = aws_route53_zone.site.zone_id }
output "name_servers" { value = aws_route53_zone.site.name_servers }
