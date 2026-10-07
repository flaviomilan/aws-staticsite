mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
}
variables {
  aws_region          = "sa-east-1"
  repository          = "owner/site"
  environment         = "production"
  name_prefix         = "mysite-production"
  domain              = "example.com"
  aliases             = ["www.example.com"]
  hosted_zone_id      = "ZEXAMPLE"
  bucket_name         = "mysite-live"
  release_bucket_name = "mysite-release"
  distribution_id     = "EEXAMPLE"
  state_bucket_name   = "shared-state"
  site_state_key      = "sites/mysite/production.tfstate"
}
run "economic_permissions" {
  command = plan
  assert {
    condition     = alltrue([for s in jsondecode(output.infrastructure_policy_json).Statement : !anytrue([for a in s.Action : startswith(a, "iam:") || startswith(a, "wafv2:") || startswith(a, "logs:")])])
    error_message = "An economical site needs no IAM administration or optional-feature permissions."
  }
  assert {
    condition     = one([for s in jsondecode(output.infrastructure_policy_json).Statement : s.Resource if contains(s.Action, "s3:DeleteObject")]) == "arn:aws:s3:::shared-state/sites/mysite/production.tfstate.tflock"
    error_message = "Object deletion must be limited to the selected site's lock, not state or live content."
  }
  assert {
    condition     = one([for s in jsondecode(output.infrastructure_policy_json).Statement : s.Condition["ForAllValues:StringEquals"]["acm:DomainNames"] if s.Sid == "RequestSiteCertificate"]) == ["example.com", "www.example.com"]
    error_message = "Certificate requests must be limited to configured hostnames."
  }
}
run "production_permissions" {
  command = plan
  variables {
    enable_waf                = true
    enable_monitoring         = true
    enable_access_logs        = true
    enable_additional_metrics = true
  }
  assert {
    condition     = length(output.infrastructure_policy_json) < 10240
    error_message = "The complete policy must fit IAM's inline-role policy limit."
  }
  assert {
    condition     = one([for s in jsondecode(output.infrastructure_policy_json).Statement : s.Resource if s.Sid == "SiteWAF"]) == "arn:aws:wafv2:us-east-1:123456789012:global/webacl/waf-example-com/*"
    error_message = "WAF permissions must match the real domain-derived ACL name in us-east-1."
  }
  assert {
    condition     = contains(one([for s in jsondecode(output.infrastructure_policy_json).Statement : s.Action if s.Sid == "CloudFrontLogDelivery"]), "logs:CreateDelivery") && one([for s in jsondecode(output.infrastructure_policy_json).Statement : s.Resource if s.Sid == "EnableDistributionLogDelivery"]) == "arn:aws:cloudfront::123456789012:distribution/EEXAMPLE"
    error_message = "Access-log setup needs delivery APIs and permission for this exact distribution."
  }
}
