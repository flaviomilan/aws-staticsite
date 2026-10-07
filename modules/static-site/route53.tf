data "aws_route53_zone" "existing" {
  zone_id      = var.hosted_zone_id
  private_zone = false
}

resource "aws_route53_record" "acm_validation" {
  for_each = {
    for host in concat([var.domain], var.aliases) : host => one([
      for dvo in aws_acm_certificate.cert[0].domain_validation_options : {
        name   = dvo.resource_record_name
        record = dvo.resource_record_value
        type   = dvo.resource_record_type
      } if dvo.domain_name == host
    ])
  }
  name    = each.value.name
  records = [each.value.record]
  ttl     = 60
  type    = each.value.type
  zone_id = var.hosted_zone_id
}

resource "aws_route53_record" "site" {
  for_each = { for record in setproduct(toset([for host in var.aliases : host if host != "www.${var.domain}"]), toset(["A", "AAAA"])) : "${record[0]}:${record[1]}" => { name = record[0], type = record[1] } }
  zone_id  = var.hosted_zone_id
  name     = each.value.name
  type     = each.value.type
  alias {
    name                   = aws_cloudfront_distribution.s3_distribution[0].domain_name
    zone_id                = aws_cloudfront_distribution.s3_distribution[0].hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "record_a" {
  count = 1

  zone_id = var.hosted_zone_id
  name    = var.domain
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.s3_distribution[0].domain_name
    zone_id                = aws_cloudfront_distribution.s3_distribution[0].hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "record_aaaa" {
  count = 1

  zone_id = var.hosted_zone_id
  name    = var.domain
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.s3_distribution[0].domain_name
    zone_id                = aws_cloudfront_distribution.s3_distribution[0].hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "www_a" {
  count = contains(var.aliases, "www.${var.domain}") ? 1 : 0

  zone_id = var.hosted_zone_id
  name    = "www.${var.domain}"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.s3_distribution[0].domain_name
    zone_id                = aws_cloudfront_distribution.s3_distribution[0].hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "www_aaaa" {
  count = contains(var.aliases, "www.${var.domain}") ? 1 : 0

  zone_id = var.hosted_zone_id
  name    = "www.${var.domain}"
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.s3_distribution[0].domain_name
    zone_id                = aws_cloudfront_distribution.s3_distribution[0].hosted_zone_id
    evaluate_target_health = false
  }
}
