# Costs and operating profiles

Choose the economical profile for a first site, then add protection and visibility according to your traffic and budget. Every site has one CloudFront distribution. The default is pay-as-you-go; costs depend on usage, region and your account's pricing eligibility.

| Profile | Enabled features | Cost drivers |
|---|---|---|
| Economic | Private origin, OAC, TLS, cache policies, Functions, DNS aliases, 30-day private release archive | CloudFront traffic/requests, S3 live and archive storage/requests, Route53 hosted zone; invalidations above the applicable allowance |
| Production example | Economic plus object versioning, WAF count mode, standard logs v2, dashboard and basic alarms | WAF ACL/rules/requests, noncurrent S3 versions, log delivery/storage, CloudWatch dashboard/alarms |
| Additional metrics | Explicit enable_additional_metrics=true | CloudFront additional metrics; independent of basic monitoring |

WAF count mode still incurs WAF charges. For a static site, enable rule groups based on actual traffic and threat exposure; blocking VPNs is not the default for new sites. Archive storage and object versions are different cost categories; releases expire after 30 days and noncurrent live-object versions after 30 days when versioning is enabled. Old live keys are deliberately retained for cached HTML and require a separately reviewed cleanup policy.

Current official pricing: [CloudFront](https://aws.amazon.com/cloudfront/pricing/), [S3](https://aws.amazon.com/s3/pricing/), [Route53](https://aws.amazon.com/route53/pricing/), [WAF](https://aws.amazon.com/waf/pricing/), [CloudWatch](https://aws.amazon.com/cloudwatch/pricing/), [ACM](https://aws.amazon.com/certificate-manager/pricing/). Create an estimate for the chosen region and traffic in the [AWS Pricing Calculator](https://calculator.aws/). ACM certificates used by this kit are non-exported public certificates.

CloudFront also offers [flat-rate plans](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/flat-rate-pricing-plan.html), including eligible WAF/DNS/logging/TLS services. Features and quotas vary: Free/Pro restrict custom policies, while multi-tenant distributions, continuous deployment and real-time logs have compatibility limits. This kit does not enroll a distribution in a fixed-price plan. Verify compatibility and billing eligibility before converting an existing distribution.

## Start with an economical configuration

The [first-site walkthrough](getting-started.md) keeps WAF, logs, monitoring, additional metrics and object versioning off. HTTPS and private-origin access are still included. You pay for the hosted zone, requests, delivery and storage according to current service pricing.

To add the production features to an existing site, follow [the configuration recipe](architecture.md#economic-and-production-profiles) using its current state. WAF count mode is a useful first step for evaluating rules, but it still incurs charges. Do not enable every feature simply because it is available.

## Watch storage and optional subscriptions

Release archives expire after 30 days. Live keys removed from a newer build are retained; they can continue to occupy storage. With S3 versioning enabled, overwritten versions add storage until lifecycle cleanup. Lowering log retention changes what you can investigate later. Disabling a Terraform feature does not necessarily erase existing stored data immediately.

For a first cost check, open AWS Billing and Cost Management, filter the account's costs by CloudFront, S3, Route53, WAF and CloudWatch, and inspect which optional features are actually enabled with `terraform output enabled_features`. Cost data can be delayed; it is not a real-time spending counter.

Create a monthly cost budget and email notification in [AWS Budgets](https://docs.aws.amazon.com/cost-management/latest/userguide/budgets-create.html), using an amount suitable for your site. A budget alert helps you notice spending; it does not automatically stop traffic or enforce a hard cap. Revisit the estimate after you have actual usage.

Public ACM certificates issued by this kit are used with CloudFront and are not exportable certificates. Storage uses SSE-S3; customer-managed KMS keys are not a setup option in this version.
