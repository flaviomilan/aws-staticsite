mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
}
variables {
  repository                 = "owner/site"
  environment                = "production"
  name_prefix                = "example"
  oidc_provider_arn          = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
  bucket_arn                 = "arn:aws:s3:::live-site"
  release_bucket_arn         = "arn:aws:s3:::site-releases"
  distribution_arn           = "arn:aws:cloudfront::123456789012:distribution/EEXAMPLE"
  infrastructure_policy_json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
}
run "restricted_identity" {
  command = plan
  assert {
    condition     = length(aws_iam_role.github) == 2
    error_message = "Infrastructure and publication need separate roles."
  }
  assert {
    condition     = toset(one([for c in data.aws_iam_policy_document.trust["publish"].statement[0].condition : c.values if c.variable == "token.actions.githubusercontent.com:sub"])) == toset(["repo:owner/site:environment:production"])
    error_message = "Publication trust must be limited to the protected environment."
  }
  assert {
    condition     = alltrue([for s in data.aws_iam_policy_document.publish.statement : !contains(s.actions, "s3:DeleteObject") && !contains(s.actions, "*") && !contains(s.resources, "*")])
    error_message = "Content role must not receive delete or unrestricted privileges."
  }
}
run "reject_wildcard_repository" {
  command = plan
  variables { repository = "owner/*" }
  expect_failures = [var.repository]
}
