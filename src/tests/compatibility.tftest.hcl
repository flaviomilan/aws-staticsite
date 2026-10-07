mock_provider "aws" {
  mock_data "aws_route53_zone" {
    defaults = { name = "example.com.", private_zone = false }
  }
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
}
mock_provider "aws" {
  alias = "edge"
}
variables {
  domain      = "example.com"
  bucket_name = "legacy-example-site"
}
run "retain_legacy_security_and_monitoring" {
  command = plan
  variables { enable_monitoring = true }
  assert {
    condition     = module.site.enabled_features.additional_metrics
    error_message = "Legacy enable_monitoring must preserve its paid metrics subscription."
  }
  assert {
    condition     = var.hsts_preload && var.hsts_include_subdomains
    error_message = "Migration must retain legacy HSTS."
  }
}
run "reject_destructive_dns_phase" {
  command = plan
  variables { domain_enabled = false }
  expect_failures = [var.domain_enabled]
}
