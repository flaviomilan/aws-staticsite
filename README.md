# Publish a static site on AWS

Put your HTML, Astro build or single-page application online with your own domain and HTTPS. Your files stay in a private S3 bucket; CloudFront delivers them worldwide. Route53 manages DNS and AWS Certificate Manager issues and renews the certificate.

You can publish locally first, then automate updates through GitHub Actions with temporary AWS credentials. Each completed release has a private archive for rollback within 30 days.

## Start here

**New site:** follow [Publish your first site](docs/getting-started.md). It covers tools, AWS login, Terraform state, domain setup, HTTPS and the first upload, including how to verify every stage.

**Already using this project:** follow [Migrate an existing site](docs/migration.md) before changing infrastructure. Your existing resources and state must be preserved.

After your first successful publication:

| I want to… | Guide |
|---|---|
| Publish automatically when I push to GitHub | [Set up GitHub Actions and OIDC](docs/github-actions.md) |
| Use Astro, a SPA, aliases or external fonts/scripts | [Configure my site](docs/architecture.md) |
| Add WAF, access logs, alerts or object versioning | [Configure optional features](docs/architecture.md#add-protection-and-observability) |
| Update content, restore a release or investigate a failure | [Operate my site](docs/operations.md) |
| Choose features according to my budget | [Understand costs](docs/costs.md) |
| Check everything before production | [Run the acceptance checklist](docs/operations.md#before-production) |

## What you need

An AWS account, a domain you control, and a terminal. The guide uses Bash on Linux, macOS or Windows with WSL2, Terraform 1.10+, AWS CLI v2, Python 3.10+, Git and `dig`. HTML needs no JavaScript build tools; the Astro example needs Node.js 22.12+.

The economical setup includes HTTPS, private storage, static or SPA routing, security headers, `www` redirects, cache invalidation and release archives. WAF, logs, dashboards, alerts, S3 versioning and additional CloudFront metrics are optional and incur charges. See [costs](docs/costs.md) before enabling them.

## Which sites can I publish?

Publish any build that produces static files with `index.html` at its root. This includes plain HTML, Astro static output and client-side SPAs. Server rendering, APIs and databases need separate hosting.

Updates upload assets before HTML and wait for CloudFront invalidation. Publication is not atomic across files; rollback restores archived files and retains other keys. The [operations guide](docs/operations.md) explains these limits and recovery steps.

For upgrading the kit, use [the changelog](CHANGELOG.md) and review the Terraform plan. For contributing, see [local verification](docs/verification.md). Technical references are available in [the AWS research notes](docs/aws-research.md).
