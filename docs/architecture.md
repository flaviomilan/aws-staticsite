# Configure your site

Use these recipes after [publishing your first site](getting-started.md). The economical and production examples accept every option below; update your `site.hcl`, review a saved plan and apply it. Keep one assignment per option—replace an existing value rather than appending a duplicate.

```bash
cd "$SITE_ROOT"
terraform plan -var-file=site.hcl -out=site.tfplan
terraform show -json site.tfplan | python3 "$KIT_DIR/scripts/check_plan.py"
terraform apply site.tfplan
terraform output enabled_features
```

For GitHub-managed infrastructure, first update the identity example's feature flags and apply it locally when adding permissions, then change the site configuration and run your workflow. When disabling a feature, retain its IAM permissions until Terraform has removed its resources.

## Choose your hostnames

The economical sample configuration enables `www`. The underlying hosting module defaults to no aliases. All aliases must belong to the supplied public zone; names from unrelated domains need a separate setup.

```hcl
domain = "example.com"
aliases = ["www.example.com", "docs.example.com"]
canonical_domain = "example.com"
redirect_aliases = true
```

Every alias receives certificate coverage and A/AAAA records. With redirects enabled, aliases serve a 308 redirect to the canonical hostname, preserving path and query. To make `www` primary, set `canonical_domain = "www.example.com"`. With `redirect_aliases = false`, every configured hostname serves the same content.

For `domain = "blog.example.com"`, choose its parent public zone or a properly delegated `blog.example.com` zone. Choose aliases explicitly; you probably do not need `www.blog.example.com`. The `site_url` output uses `domain`; when another canonical hostname is selected it will redirect there.

## Select static or SPA routing

| Your build | Setting | Required output | Check |
|---|---|---|---|
| HTML or Astro static | `routing_mode = "static"` | `/about/index.html` for `/about/` | `/about/` returns the actual about page |
| Client-side SPA | `routing_mode = "spa"` | Root `index.html` plus client router | Refreshing a nested route loads the app |

Static routing resolves extensionless directory URLs to their `index.html`. SPA routing sends extensionless navigation URLs to the root index. Paths with file extensions and `.well-known` are not rewritten into the app. Missing assets keep an error response; private S3 may return 403 rather than 404. An uploaded `404.html` is not automatically used as a custom error page.

### Publish your own HTML

Build or copy the output into a directory containing `index.html` at its root. Use the publication command in [operations](operations.md#publish-an-update), changing `BUILD_DIR` to that directory. The HTML example needs no build command.

### Publish Astro

```bash
cd "$KIT_DIR/examples/astro"
npm ci --ignore-scripts --no-fund --no-audit
npm run build
export BUILD_DIR="$PWD/dist"
```

Use Node.js 22.12+. The example generates static output with trailing slashes, which matches `routing_mode = "static"`. Inspect the build output, then publish `BUILD_DIR` with a new release SHA. In your own repository, commit the dependency lockfile and configure your build to produce static output; server-rendered Astro needs another hosting solution.

### Publish a SPA

Set `routing_mode = "spa"`, apply the reviewed plan, then publish `examples/spa/site` using the normal publication command. With your own React/Vue/etc. app, publish the build directory rather than its source. Configure the client router for the domain root. Verify both navigation and a direct browser refresh on `/account/settings`; a missing `/missing.js` must still fail.

## Allow the resources your browser needs

The default Content Security Policy allows local scripts and fonts, local/data images and inline styles. Inline scripts, remote analytics, API connections and external fonts require deliberate additions.

For self-hosted scripts plus an external API, Google Fonts and an image host:

```hcl
csp_policy = "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; font-src 'self' https://fonts.gstatic.com; img-src 'self' data: https://images.example.com; connect-src 'self' https://api.example.com;"
```

Replace the example origins with the exact services you use. Check the browser console for CSP violations and verify fonts, forms and analytics after each change. For Astro inline scripts, prefer external script files or explicit CSP hashes; do not broadly allow inline JavaScript just to silence an error. The Permissions-Policy disables geolocation, camera, microphone, payment and USB; those permissions are not configurable through this kit's current inputs.

```hcl
minimum_tls_version = "TLSv1.2_2021"
hsts_include_subdomains = false
hsts_preload = false
```

TLS choices are `TLSv1.2_2018`, `TLSv1.2_2019` and `TLSv1.2_2021`. Keep the newest default unless your audience requires another supported policy. Enable HSTS subdomains only when every subdomain works over HTTPS. `hsts_preload = true` requires `hsts_include_subdomains = true`; it adds the header token but does not submit your domain to a preload list. Browser HSTS persists, so evaluate these changes before applying.

## Add protection and observability

Each feature below adds charges. Read [costs](costs.md), enable the features you need and verify their actual behavior.

### WAF: observe first, then block

```hcl
enable_waf = true
waf_mode = "count"
waf_rate_limit = 2000
block_anonymous_ips = false
```

The kit includes managed common, known-bad-input and IP-reputation rules, plus a per-IP rate rule using a five-minute window. `waf_rate_limit` accepts 100–20,000,000. In count mode matching requests are observed rather than blocked.

In the WAF console select CloudFront/global scope and the ACL `waf-` followed by your domain with dots replaced by hyphens. Review sampled requests and the CloudWatch log group `aws-waf-logs-` with the same domain suffix in `us-east-1`. Test normal browsing and your expected clients. Then set `waf_mode = "block"`, apply and retest.

`block_anonymous_ips = true` adds the anonymous-IP managed group; in count mode it counts, and in block mode it can reject VPN/proxy users. It is disabled by default. If legitimate users are blocked, revert to count mode while investigating; individual managed-rule exclusions are not exposed by this version.

### Store access logs

```hcl
enable_access_logs = true
log_retention_days = 30
```

For access logs, choose a hyphenated origin bucket name of at most 48 characters during initial setup. The log-delivery names derive from it and have tighter naming limits than S3. CloudFront standard logs v2 are delivered as JSON to a private S3 bucket. Locate the bucket from Terraform after enabling logs:

```bash
cd "$SITE_ROOT"
terraform state show 'module.site.aws_s3_bucket.logs[0]'
```

Copy its `id`, then run `aws s3 ls s3://YOUR_LOG_BUCKET/AWSLogs/ --recursive`. Generate traffic and allow time for delivery; logs are delayed. Download a sample using `aws s3 cp s3://YOUR_LOG_BUCKET/FULL_OBJECT_KEY /tmp/site-access-log.json` to inspect it.

`log_retention_days` controls S3 access-log expiry and WAF CloudWatch retention. Supported values: 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180 and 365. Lowering retention affects existing logs; expiry is asynchronous.

### Add dashboards and email alerts

```hcl
enable_monitoring = true
notification_email = "you@example.com"
enable_additional_metrics = false
```

Open CloudWatch in `us-east-1`. The dashboard is your domain with dots replaced by hyphens, followed by `-dashboard`. Alarms cover CloudFront 4xx/5xx error rates and, when WAF is enabled, blocked-request spikes. They measure traffic and errors; they are not a synthetic uptime check.

Confirm the SNS subscription email sent to `notification_email`. Without confirmation, email alerts are not delivered. To verify the channel, open SNS in `us-east-1`, select the matching `-alarms` topic, check that the subscription is confirmed and publish a test message. Leaving the email empty keeps the dashboard/alarms without email notifications.

`enable_additional_metrics = true` subscribes separately to paid CloudFront metrics. When monitoring is also enabled, the dashboard includes CacheHitRate. Basic monitoring does not require this subscription.

### Keep previous S3 object versions

```hcl
enable_s3_versioning = true
```

This preserves overwritten live-file versions; noncurrent versions expire after 30 days. Verify `aws s3api get-bucket-versioning --bucket "$SITE_BUCKET"` returns `Enabled`. Use release rollback for normal site recovery: it restores a checked set of files, while S3 versions are individual objects. Turning the feature off does not immediately erase old versions or end their storage charges; review S3 versioning/lifecycle status after applying.

## Economic and production profiles

The first-site guide starts with every optional feature off. The production example enables WAF in count mode, access logs, basic monitoring and live-object versioning; additional paid metrics remain off. Its sample requires you to replace the notification email.

For an existing site, change its current `site.hcl` rather than switching to a different root/state:

```hcl
enable_waf = true
waf_mode = "count"
enable_access_logs = true
log_retention_days = 30
enable_monitoring = true
notification_email = "you@example.com"
enable_s3_versioning = true
enable_additional_metrics = false
```

Confirm the outputs, log delivery and email subscription before depending on them. Keep `bucket_name`, region, domain, zone and state key stable when changing a profile. `project_name` controls project tagging and `environment` accepts development, staging or production; changing tags does not create an isolated environment.
