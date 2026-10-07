# --------------------------------------------------------------
# Route53 Hosted Zone
# --------------------------------------------------------------

resource "aws_route53_zone" "public_zone" {
  name          = var.domain
  comment       = "Public hosted zone for ${var.domain}"
  force_destroy = var.force_destroy_zone

  tags = local.project_tags
}
