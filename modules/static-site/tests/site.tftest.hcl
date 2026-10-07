mock_provider "aws" {
  mock_resource "aws_s3_bucket" {
    defaults = { arn = "arn:aws:s3:::example-test-bucket" }
  }
  mock_resource "aws_cloudfront_function" {
    defaults = { arn = "arn:aws:cloudfront::123456789012:function/example" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }
  mock_data "aws_route53_zone" {
    defaults = { name = "example.com.", private_zone = false }
  }
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
}
mock_provider "aws" {
  alias = "edge"
  mock_resource "aws_acm_certificate" {
    defaults = {
      arn = "arn:aws:acm:us-east-1:123456789012:certificate/12345678-1234-1234-1234-123456789012"
      domain_validation_options = [{
        domain_name           = "example.com"
        resource_record_name  = "_validation.example.com"
        resource_record_type  = "CNAME"
        resource_record_value = "_validation.acm-validations.aws."
        }, {
        domain_name           = "www.example.com"
        resource_record_name  = "_www.example.com"
        resource_record_type  = "CNAME"
        resource_record_value = "_www.acm-validations.aws."
        }, {
        domain_name           = "app.example.com"
        resource_record_name  = "_app.example.com"
        resource_record_type  = "CNAME"
        resource_record_value = "_app.acm-validations.aws."
      }]
    }
  }
  mock_resource "aws_cloudwatch_log_delivery_destination" {
    defaults = { arn = "arn:aws:logs:us-east-1:123456789012:delivery-destination:example" }
  }
  mock_resource "aws_wafv2_web_acl" {
    defaults = { arn = "arn:aws:wafv2:us-east-1:123456789012:global/webacl/test/12345678-1234-1234-1234-123456789012" }
  }
  mock_resource "aws_cloudwatch_log_group" {
    defaults = { arn = "arn:aws:logs:us-east-1:123456789012:log-group:aws-waf-logs-example" }
  }
}
override_resource {
  target = aws_cloudfront_distribution.s3_distribution[0]
  values = { id = "EEXAMPLE", arn = "arn:aws:cloudfront::123456789012:distribution/EEXAMPLE", domain_name = "example.cloudfront.net", hosted_zone_id = "Z2FDTNDATAQYW2" }
}
variables {
  domain         = "example.com"
  bucket_name    = "example-test-site"
  hosted_zone_id = "Z0123456789"
}

run "economic_static_site" {
  command = plan
  assert {
    condition     = aws_s3_bucket_public_access_block.block_public_access[0].block_public_policy && aws_s3_bucket_public_access_block.block_public_access[0].restrict_public_buckets
    error_message = "The origin must remain private."
  }
  assert {
    condition     = aws_cloudfront_origin_access_control.cloudfront_s3_oac[0].signing_behavior == "always"
    error_message = "OAC must sign every origin request."
  }
  assert {
    condition     = length(aws_cloudfront_distribution.s3_distribution[0].custom_error_response) == 0
    error_message = "Missing assets must never become successful HTML responses."
  }
  assert {
    condition     = length(aws_wafv2_web_acl.waf) == 0 && length(aws_cloudwatch_dashboard.main) == 0 && length(aws_cloudfront_monitoring_subscription.monitoring) == 0 && length(aws_s3_bucket.logs) == 0
    error_message = "Paid features are opt-in."
  }
  assert {
    condition     = !aws_cloudfront_response_headers_policy.security_headers[0].security_headers_config[0].strict_transport_security[0].preload
    error_message = "HSTS preload must be explicit."
  }
}

run "production_spa_regional_origin" {
  command = apply
  variables {
    aws_region           = "sa-east-1"
    aliases              = ["www.example.com", "app.example.com"]
    canonical_domain     = "www.example.com"
    routing_mode         = "spa"
    enable_waf           = true
    enable_monitoring    = true
    enable_access_logs   = true
    enable_s3_versioning = true
  }
  assert {
    condition     = aws_acm_certificate.cert[0].region == "us-east-1" && aws_wafv2_web_acl.waf[0].region == "us-east-1"
    error_message = "ACM and global WAF must remain in the edge region."
  }
  assert {
    condition     = length(aws_route53_record.site) == 2 && length(aws_route53_record.www_a) == 1 && length(aws_route53_record.www_aaaa) == 1
    error_message = "Every extra alias needs IPv4 and IPv6 records."
  }
  assert {
    condition     = strcontains(aws_cloudfront_function.rewrite_index.code, "var routingMode = \"spa\"")
    error_message = "SPA routing must be generated independently of static directory routing."
  }
  assert {
    condition     = !strcontains(aws_cloudwatch_dashboard.main[0].dashboard_body, "CacheHitRate") && length(aws_cloudfront_monitoring_subscription.monitoring) == 0
    error_message = "Basic monitoring must not subscribe to additional metrics."
  }
}

run "additional_metrics" {
  command = apply
  variables {
    enable_monitoring         = true
    enable_additional_metrics = true
  }
  assert {
    condition     = length(aws_cloudfront_monitoring_subscription.monitoring) == 1 && strcontains(aws_cloudwatch_dashboard.main[0].dashboard_body, "CacheHitRate")
    error_message = "Cache hit rate requires its paid subscription."
  }
}
run "reject_invalid_routing" {
  command = plan
  variables { routing_mode = "ssr" }
  expect_failures = [var.routing_mode]
}
run "reject_invalid_canonical_domain" {
  command = plan
  variables { canonical_domain = "unrelated.example.org" }
  expect_failures = [var.canonical_domain]
}
run "reject_unsafe_preload" {
  command = plan
  variables { hsts_preload = true }
  expect_failures = [var.hsts_preload]
}

run "reject_alias_outside_hosted_zone" {
  command = plan
  variables { aliases = ["www.other.com"] }
  expect_failures = [aws_acm_certificate.cert]
}
