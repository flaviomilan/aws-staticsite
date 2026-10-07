# --------------------------------------------------------------
# ACM Certificate
# --------------------------------------------------------------

resource "aws_acm_certificate" "cert" {
  provider = aws.edge
  region   = "us-east-1"
  count    = 1

  domain_name               = var.domain
  subject_alternative_names = var.aliases
  validation_method         = "DNS"

  tags = local.project_tags

  lifecycle {
    create_before_destroy = true
    precondition {
      condition = !data.aws_route53_zone.existing.private_zone && alltrue([
        for host in concat([var.domain], var.aliases) :
        host == trimsuffix(data.aws_route53_zone.existing.name, ".") || endswith(host, ".${trimsuffix(data.aws_route53_zone.existing.name, ".")}")
      ])
      error_message = "All certificate names must belong to the supplied public hosted zone."
    }
  }
}

resource "aws_acm_certificate_validation" "cert" {
  provider = aws.edge
  region   = "us-east-1"
  count    = 1

  certificate_arn         = aws_acm_certificate.cert[0].arn
  validation_record_fqdns = [for record in aws_route53_record.acm_validation : record.fqdn]

  timeouts {
    create = "45m"
  }
}
