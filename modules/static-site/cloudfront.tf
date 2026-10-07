# --------------------------------------------------------------
# CloudFront Distribution
# --------------------------------------------------------------

resource "aws_cloudfront_distribution" "s3_distribution" {
  count = 1

  origin {
    domain_name              = aws_s3_bucket.s3_bucket[0].bucket_regional_domain_name
    origin_id                = local.s3_origin_id
    origin_access_control_id = aws_cloudfront_origin_access_control.cloudfront_s3_oac[0].id
    s3_origin_config { origin_access_identity = "" }
  }

  enabled             = true
  is_ipv6_enabled     = true
  http_version        = "http2and3"
  comment             = "CloudFront distribution for ${var.domain}"
  default_root_object = "index.html"
  web_acl_id          = var.enable_waf ? aws_wafv2_web_acl.waf[0].arn : null

  aliases = concat([var.domain], var.aliases)

  default_cache_behavior {
    allowed_methods            = ["GET", "HEAD", "OPTIONS"]
    cached_methods             = ["GET", "HEAD", "OPTIONS"]
    target_origin_id           = local.s3_origin_id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.security_headers[0].id
    compress                   = true

    cache_policy_id = aws_cloudfront_cache_policy.site.id

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.rewrite_index.arn
    }

    viewer_protocol_policy = "redirect-to-https"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
      locations        = []
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate.cert[0].arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = var.minimum_tls_version
  }

  tags = local.project_tags

  depends_on = [aws_acm_certificate_validation.cert]
}

# --------------------------------------------------------------
# Origin Access Control (OAC)
# --------------------------------------------------------------

resource "aws_cloudfront_origin_access_control" "cloudfront_s3_oac" {
  count = 1

  name                              = "oac-${var.domain}"
  description                       = "Origin Access Control for ${var.domain} S3 bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# --------------------------------------------------------------
# CloudFront Function (SPA Rewrite)
# --------------------------------------------------------------

resource "aws_cloudfront_function" "rewrite_index" {
  name    = replace("rewrite-index-${var.domain}", ".", "-")
  runtime = "cloudfront-js-2.0"
  comment = "Rewrite extensionless URIs to index.html for SPA routing"
  publish = true
  code = templatefile("${path.module}/function/function.js.tftpl", {
    routing_mode     = jsonencode(var.routing_mode)
    canonical_domain = jsonencode(var.canonical_domain == null ? var.domain : var.canonical_domain)
    redirect_aliases = jsonencode(var.redirect_aliases)
  })
}

# --------------------------------------------------------------
# Security Headers Policy
# --------------------------------------------------------------

resource "aws_cloudfront_response_headers_policy" "security_headers" {
  count = 1
  name  = replace("security-headers-${var.domain}", ".", "-")

  security_headers_config {
    strict_transport_security {
      access_control_max_age_sec = 31536000
      include_subdomains         = var.hsts_include_subdomains
      preload                    = var.hsts_preload
      override                   = true
    }

    frame_options {
      frame_option = "SAMEORIGIN"
      override     = true
    }

    content_type_options {
      override = true
    }

    referrer_policy {
      referrer_policy = "strict-origin-when-cross-origin"
      override        = true
    }

    content_security_policy {
      content_security_policy = var.csp_policy
      override                = true
    }
  }

  custom_headers_config {
    items {
      header   = "Permissions-Policy"
      value    = "geolocation=(), microphone=(), camera=(), payment=(), usb=()"
      override = true
    }

    items {
      header   = "X-Permitted-Cross-Domain-Policies"
      value    = "none"
      override = true
    }
  }
}

# --------------------------------------------------------------
# CloudFront Real-Time Monitoring
# --------------------------------------------------------------

resource "aws_cloudfront_monitoring_subscription" "monitoring" {
  provider = aws.edge
  count    = var.enable_additional_metrics ? 1 : 0

  distribution_id = aws_cloudfront_distribution.s3_distribution[0].id

  monitoring_subscription {
    realtime_metrics_subscription_config {
      realtime_metrics_subscription_status = "Enabled"
    }
  }
}

resource "aws_cloudfront_cache_policy" "site" {
  name        = "${var.bucket_name}-cache"
  min_ttl     = 0
  default_ttl = 0
  max_ttl     = 31536000
  parameters_in_cache_key_and_forwarded_to_origin {
    enable_accept_encoding_brotli = true
    enable_accept_encoding_gzip   = true
    cookies_config { cookie_behavior = "none" }
    headers_config { header_behavior = "none" }
    query_strings_config { query_string_behavior = "none" }
  }
}
