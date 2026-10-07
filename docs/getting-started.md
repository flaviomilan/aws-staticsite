# Publish your first site

By the end of this guide, your site will load over HTTPS at your domain, redirect `www` to that domain and reject direct public access to its S3 files. Start with the economical configuration. Add features after this works.

This guide is for **new infrastructure**. If you already have a site managed by this project, use [the migration guide](migration.md).

## 1. Install tools and sign in

Use Bash on Linux, macOS or Windows with [WSL2](https://learn.microsoft.com/en-us/windows/wsl/install). Install [Terraform](https://developer.hashicorp.com/terraform/install), [AWS CLI v2](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html), [Python](https://www.python.org/downloads/) and [Git](https://git-scm.com/downloads). Use the vendor instructions for your operating system; workflow jobs use Terraform 1.10.5.

On Ubuntu/WSL, install `dig` with `sudo apt-get install dnsutils`; on Arch, `sudo pacman -S bind`. macOS includes `dig`.

```bash
terraform version
aws --version
python3 --version
git --version
dig -v
```

Expect Terraform 1.10 or later (below 2.0), AWS CLI 2 and Python 3.10 or later. For Astro, install [Node.js](https://nodejs.org/en/download) 22.12+ and check `node --version` and `npm --version`.

Use your organization's IAM Identity Center session if available:

```bash
aws configure sso --profile static-site
aws sso login --profile static-site
export AWS_PROFILE=static-site
export AWS_PAGER=""
aws sts get-caller-identity
```

During `configure sso`, obtain the start URL and SSO region from your administrator, select the intended AWS account and an authorized provisioning role, then choose your default region. Your SSO region can differ from your site's region. If your account uses another temporary credential mechanism, activate that session instead and run the same identity check. See [AWS CLI authentication](https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-authentication.html).

The returned `Account` must be the account where you intend to host the site. Your initial local identity needs permission to create the state bucket, DNS zone if needed, site resources and later IAM roles. An existing restrictive role may require your AWS administrator to authorize provisioning. Never put credentials in Terraform files.

## 2. Choose your values once

Keep this Bash session open. Replace the example values below with your own:

```bash
export AWS_REGION=sa-east-1
export DOMAIN=example.com
export SITE_ID=mysite
export ENVIRONMENT=production
export STATE_BUCKET=my-company-mysite-state-unique
export SITE_BUCKET=my-company-mysite-site-unique
export SITE_STATE_KEY="sites/$SITE_ID/$ENVIRONMENT.tfstate"
```

| Value | How to choose it |
|---|---|
| `AWS_REGION` | Region for your S3 files and state, such as `sa-east-1`. ACM and other global-facing resources use `us-east-1` automatically. |
| `DOMAIN` | Lowercase hostname you own, without `https://` or a trailing slash. This walkthrough assumes the domain apex and its `www` alias. |
| `SITE_ID` | Short identifier, reused in state keys and workflow configuration. |
| `ENVIRONMENT` | `production`, `staging` or `development`. Use a different hostname, bucket and state key for a separate environment. |
| `STATE_BUCKET`, `SITE_BUCKET` | Different globally unique S3 names, lowercase, 3–63 characters. Use letters, digits and hyphens and keep the site bucket name at most 48 characters so it also works with optional access logs. |

Your domain can remain registered with its current registrar. Domain registration is separate from creating a Route53 hosted zone.

Clone the kit and remember its location:

```bash
git clone https://github.com/flaviomilan/aws-staticsite.git
cd aws-staticsite
export KIT_DIR="$PWD"
git rev-parse HEAD
```

Use a reviewed kit revision containing these examples. Record the full commit SHA for later automation; don't update the kit in the middle of this walkthrough.

## 3. Create the Terraform state bucket

Terraform state records the AWS resources you manage. Give bootstrap, DNS, site and identity their own state keys. If you already have an encrypted, versioned S3 backend with native locking, reuse it and skip creation; your identity needs access to the chosen state and `.tflock` objects.

For a **new** state bucket:

```bash
cd "$KIT_DIR/bootstrap"
cat > bootstrap.hcl <<EOF
aws_region = "$AWS_REGION"
state_bucket_name = "$STATE_BUCKET"
environment = "$ENVIRONMENT"
enable_legacy_lock_table = false
EOF
cat > backend_override.tf <<'EOF'
terraform {
  backend "local" { path = "terraform.tfstate" }
}
EOF
terraform init
terraform plan -var-file=bootstrap.hcl -out=bootstrap.tfplan
terraform apply bootstrap.tfplan
terraform output -raw state_bucket_name
```

Review the plan before applying. The output must equal `STATE_BUCKET`. New backends use S3 locking and do not need DynamoDB. An existing legacy backend must keep its lock table until every client has migrated.

Now migrate bootstrap's own state to that bucket:

```bash
cp terraform.tfstate terraform.tfstate.before-migration
cat > backend.hcl <<EOF
bucket = "$STATE_BUCKET"
key = "bootstrap/$SITE_ID.tfstate"
region = "$AWS_REGION"
encrypt = true
use_lockfile = true
EOF
cat > backend_override.tf <<'EOF'
terraform {
  backend "s3" {}
}
EOF
terraform init -migrate-state -backend-config=backend.hcl
```

Answer `yes` when Terraform asks to copy the existing state. Verify the remote copy:

```bash
terraform state list
aws s3api head-object --bucket "$STATE_BUCKET" --key "bootstrap/$SITE_ID.tfstate"
aws s3api get-bucket-versioning --bucket "$STATE_BUCKET"
```

Expect the existing bootstrap resources, a remote state object and `Status: Enabled`. After verification, delete **only** `backend_override.tf`, using your editor or file manager. Keep the protected state backup until the site is verified; do not commit it. The permanent backend already uses S3. Never run first-time bootstrap on an ephemeral GitHub runner.

## 4. Connect your domain

### Reuse a public Route53 zone

```bash
aws route53 list-hosted-zones-by-name --dns-name "$DOMAIN" \
  --query 'HostedZones[].{Name:Name,Id:Id,Private:Config.PrivateZone}' --output table
export HOSTED_ZONE_ID=Z_REPLACE_WITH_PUBLIC_ZONE_ID
```

Choose the public zone for your domain; exclude private zones and duplicate zones that are not delegated. Copy its ID without `/hostedzone/`. If publishing a subdomain, use the parent public zone and see [hostname configuration](architecture.md#choose-your-hostnames).

### Create a public zone if you do not have one

```bash
cd "$KIT_DIR/examples/dns"
cat > dns.hcl <<EOF
domain = "$DOMAIN"
EOF
cat > backend.hcl <<EOF
bucket = "$STATE_BUCKET"
key = "dns/$SITE_ID.tfstate"
region = "$AWS_REGION"
encrypt = true
use_lockfile = true
EOF
terraform init -backend-config=backend.hcl
terraform plan -var-file=dns.hcl -out=dns.tfplan
terraform apply dns.tfplan
export HOSTED_ZONE_ID="$(terraform output -raw hosted_zone_id)"
terraform output name_servers
```

Review the plan; it should create a public hosted zone. In your domain registrar's DNS/nameserver settings, replace its current nameservers with **all four** Route53 nameservers. If the domain already serves email or other services, copy the required existing DNS records into Route53 before changing delegation. For a delegated subdomain, create the corresponding NS record in its parent zone instead.

### Verify delegation before requesting HTTPS

The following commands work for either a reused or newly created zone:

```bash
export ZONE_DOMAIN="$(aws route53 get-hosted-zone --id "$HOSTED_ZONE_ID" \
  --query HostedZone.Name --output text)"
aws route53 get-hosted-zone --id "$HOSTED_ZONE_ID" \
  --query DelegationSet.NameServers --output text > /tmp/static-site-nameservers.txt
read -r -a SITE_NAMESERVERS < /tmp/static-site-nameservers.txt
python3 "$KIT_DIR/scripts/check_dns.py" --domain "${ZONE_DOMAIN%.}" \
  --nameservers "${SITE_NAMESERVERS[@]}"
```

Expect `Route53 delegation verified`. DNS changes can take time. If this fails, fix the registrar or parent NS record and retry; do not create another hosted zone. Certificate validation depends on public DNS reaching this exact zone.

## 5. Create hosting and HTTPS

```bash
cd "$KIT_DIR/examples/existing-zone"
cat > site.hcl <<EOF
aws_region = "$AWS_REGION"
domain = "$DOMAIN"
aliases = ["www.$DOMAIN"]
bucket_name = "$SITE_BUCKET"
hosted_zone_id = "$HOSTED_ZONE_ID"
project_name = "$SITE_ID"
environment = "$ENVIRONMENT"
routing_mode = "static"
EOF
cat > backend.hcl <<EOF
bucket = "$STATE_BUCKET"
key = "$SITE_STATE_KEY"
region = "$AWS_REGION"
encrypt = true
use_lockfile = true
EOF
terraform init -backend-config=backend.hcl
terraform plan -var-file=site.hcl -out=site.tfplan
terraform show -json site.tfplan | python3 "$KIT_DIR/scripts/check_plan.py"
terraform apply site.tfplan
```

Read the plan, not just the guard result. Expect a private live bucket, release bucket, CloudFront distribution, certificate, routing/security policies and DNS records. Optional WAF, logs and monitoring remain disabled. The hosted zone is reused rather than replaced.

ACM automatically adds real DNS validation CNAME records in your zone; keep them for renewal. The certificate is issued in `us-east-1` even if the S3 bucket is elsewhere. Issuance and CloudFront deployment can take several minutes. If certificate validation times out, use [troubleshooting](troubleshooting.md#certificate-validation-is-pending).

Capture the outputs after apply:

```bash
export SITE_ROOT="$PWD"
export SITE_BUCKET="$(terraform output -raw bucket_id)"
export RELEASE_BUCKET="$(terraform output -raw release_bucket_id)"
export DISTRIBUTION_ID="$(terraform output -raw cloudfront_distribution_id)"
export SITE_URL="$(terraform output -raw site_url)"
terraform output enabled_features
```

Expect all optional features to be false. A 403 at the site before the first upload is expected: no homepage has been published yet.

## 6. Publish HTML and verify it

Use the included HTML site for your first upload:

```bash
cd "$KIT_DIR"
export RELEASE_ID="$(git rev-parse HEAD)"
python3 scripts/publish.py publish --directory examples/html/site \
  --release-id "$RELEASE_ID" --bucket "$SITE_BUCKET" \
  --release-bucket "$RELEASE_BUCKET" --distribution-id "$DISTRIBUTION_ID"
python3 scripts/smoke.py "$SITE_URL" "$DISTRIBUTION_ID"
curl -I "$SITE_URL"
curl -I "https://www.$DOMAIN/about/?source=setup"
curl -I "$SITE_URL/about/"
```

Expect `publish completed`, followed by `HTTPS, security headers and private origin verified`. The homepage and `/about/` should return 200; `www` should return a 308 redirect to your main hostname while preserving the path and query string.

Open `SITE_URL` in your browser. Direct S3 access must fail with 403; the smoke check verifies that for you. Save your output values and non-secret configuration. Do not commit Terraform state, plans or credentials.

When replacing the sample with your own content, give that build a **new commit SHA**. A completed SHA cannot be reused for different bytes. For independent projects, follow [GitHub setup](github-actions.md) to copy the configuration into your site repository and pin the kit revision.

## What to do next

- [Configure Astro or SPA routing, aliases and optional features](architecture.md).
- [Automate publication with GitHub Actions](github-actions.md).
- [Publish an update and practice rollback](operations.md).
- [Review charges and operating profiles](costs.md).

If an export is lost after closing the terminal, recover the resource values from `terraform -chdir="$SITE_ROOT" output` after setting `SITE_ROOT` to your site configuration and signing in again.
