# Update, restore and operate your site

For initial setup use [Publish your first site](getting-started.md); for automation use [GitHub Actions](github-actions.md). This guide assumes the site already exists.

## Recover your values

Set `KIT_DIR` to your checkout of the pinned kit and `SITE_ROOT` to your Terraform configuration (`infra` in a consumer repository). Authenticate to the right AWS account before continuing:

```bash
export KIT_DIR=/absolute/path/to/aws-staticsite
export SITE_ROOT=/absolute/path/to/site-repository/infra
aws sts get-caller-identity
terraform -chdir="$SITE_ROOT" init -backend-config=backend.hcl -lockfile=readonly
export SITE_BUCKET="$(terraform -chdir="$SITE_ROOT" output -raw bucket_id)"
export RELEASE_BUCKET="$(terraform -chdir="$SITE_ROOT" output -raw release_bucket_id)"
export DISTRIBUTION_ID="$(terraform -chdir="$SITE_ROOT" output -raw cloudfront_distribution_id)"
export SITE_URL="$(terraform -chdir="$SITE_ROOT" output -raw site_url)"
```

Your local identity must have state access to read these outputs and publication permissions to upload content. A publication-only identity can use the non-secret destination values recorded during setup instead.

## Prepare the files

The publication directory must contain `index.html` at its root. Publish your built files, not source files, dependency folders or a ZIP containing another directory. The publisher rejects symlinks, unsafe paths and hidden files/directories except `.well-known`.

For local publication, include `.well-known` directly in the build directory. GitHub's artifact upload excludes hidden files by default. If needed, first check all output files are intended to be public, then use these upload settings, replacing `dist` with your build directory. Enabling hidden files affects artifact collection as well as `.well-known`:

```yaml
with:
  name: site
  path: |
    dist/**
    dist/.well-known/**
  include-hidden-files: true
  if-no-files-found: error
```

Inspect the build for credentials or other private material before publication. Only include files intended to be publicly downloadable; the publisher's path validation does not identify secret content.

## Publish an update

For GitHub, push a reviewed source change to `main` and monitor the Site workflow. Infrastructure need not change for a content update; the plan may be empty.

For local publication, build your source and use its new full commit SHA:

```bash
export CONTENT_REPO=/absolute/path/to/site-repository
export BUILD_DIR="$CONTENT_REPO/dist"
export RELEASE_ID="$(git -C "$CONTENT_REPO" rev-parse HEAD)"
python3 "$KIT_DIR/scripts/publish.py" publish --directory "$BUILD_DIR" \
  --release-id "$RELEASE_ID" --bucket "$SITE_BUCKET" \
  --release-bucket "$RELEASE_BUCKET" --distribution-id "$DISTRIBUTION_ID"
python3 "$KIT_DIR/scripts/smoke.py" "$SITE_URL" "$DISTRIBUTION_ID"
aws s3 cp "s3://$RELEASE_BUCKET/current.json" -
```

Replace `BUILD_DIR` with your actual output, such as `site` for HTML or `dist` for Astro. Commit the content before assigning its release ID. Use a fresh commit for changed build bytes; a completed SHA cannot be overwritten with a different build.

Expect `publish completed`, passing smoke checks and the selected SHA in `current.json`. The archive manifest is written only after all archive files upload. Live assets upload first, other HTML next and the root index last. CloudFront invalidation must complete before the completion marker is updated.

Local commands do not share GitHub's concurrency locks. Avoid overlapping local/CI publications or infrastructure applies for the same site.

## Understand caching

| File | Publisher's Cache-Control |
|---|---|
| HTML | `public,max-age=0,must-revalidate` |
| Assets with recognized hexadecimal content hashes in their names | `public,max-age=31536000,immutable` |
| Other files | `public,max-age=300,must-revalidate` |

Use content-hashed filenames for long-lived assets. Nonhex build hashes, including some generated Astro filenames, use the five-minute fallback. Every publication invalidates `/*` and waits for completion; browser caches of immutable URLs cannot be cleared by a CloudFront invalidation. Never change the bytes of an immutable asset while retaining its name.

Cookies, query strings and request headers are not included in this kit's cache key or forwarded to the origin; varying a query string does not select a different file. Redirects preserve query strings, which is separate from origin caching.

Inspect metadata when content appears stale:

```bash
aws s3api head-object --bucket "$SITE_BUCKET" --key index.html \
  --query '{CacheControl:CacheControl,ContentType:ContentType}'
curl -I "$SITE_URL"
aws cloudfront list-invalidations --distribution-id "$DISTRIBUTION_ID"
```

Expect HTML content type, revalidation metadata and a completed invalidation. See [troubleshooting](troubleshooting.md#the-site-shows-old-content).

## Restore a previous release

List archived completed manifests:

```bash
aws s3 ls "s3://$RELEASE_BUCKET/releases/" --recursive
aws s3 cp "s3://$RELEASE_BUCKET/current.json" -
```

Select a known-good 40-character SHA whose `releases/SHA/manifest.json` exists. S3 lifecycle expires releases after 30 days; the older `current.json` marker can remain even after its archive expires. Keep independent backups if you need a longer recovery window.

```bash
export PREVIOUS_RELEASE=REPLACE_WITH_PREVIOUS_FULL_COMMIT_SHA
python3 "$KIT_DIR/scripts/publish.py" rollback --release-id "$PREVIOUS_RELEASE" \
  --bucket "$SITE_BUCKET" --release-bucket "$RELEASE_BUCKET" \
  --distribution-id "$DISTRIBUTION_ID"
python3 "$KIT_DIR/scripts/smoke.py" "$SITE_URL" "$DISTRIBUTION_ID"
```

Rollback downloads the full archive and verifies its checksums before touching live files. Expect `rollback completed`, passing smoke checks and the restored SHA in `current.json`. In GitHub, use the Restore site workflow with the same SHA. S3 versioning is optional and is not required for release rollback.

## Recover an interrupted or failed deployment

If archival/upload or invalidation fails, check the run's error and verify the served site. Retry with the **same bytes and SHA**, or explicitly restore a completed known-good archive. If you changed the build, create a new commit instead. A smoke failure fails the job but does not trigger automatic rollback.

Publication is not atomic across files. A failure may leave a mix of old and new files; `current.json` records the last completed publication, not a proof that no partial writes occurred later. Old keys are retained so cached pages can still load old assets. A page removed from the latest build may remain reachable, and rollback does not delete files introduced afterward.

Do not use `aws s3 sync --delete` as an incident shortcut. Remove obsolete files through a separate reviewed cleanup after considering cached pages and your rollback window. If you need atomic releases or guaranteed removal of old pages during promotion, this release of the kit does not provide that behavior.

## Check optional features

Use [configuration recipes](architecture.md#add-protection-and-observability) to enable and verify WAF, logs, alerts and versioning. CloudFront/WAF/monitoring management uses `us-east-1`; your S3 bucket remains in its configured region.

- WAF: review sampled requests and its CloudWatch log group before switching from count to block. Revert to count if legitimate clients are rejected.
- Logs: generate traffic and look for delivered S3 objects. Delivery is delayed; an empty log bucket immediately after setup does not prove failure.
- Email: confirm the SNS subscription and send a test message. Unconfirmed subscriptions cannot notify you.
- Paid metrics: check `enabled_features` before assuming CacheHitRate is subscribed. Basic alarms do not enable it automatically.

## Before production

Run this exercise on a separate staging hostname, bucket and state key, then record the results:

| Exercise | Expected result |
|---|---|
| Resolve main domain and aliases | A/AAAA answers reach the selected distribution; public delegation matches the intended zone |
| Open HTTPS and inspect headers | Valid certificate for all configured names; CSP/HSTS/content-type protections present |
| Request `www` with path/query | 308 to the canonical host with path/query preserved, when redirects are enabled |
| Access `/about/` or refresh a SPA route | Correct static page or SPA entry point according to the selected routing mode |
| Request a missing JS/CSS file | Error response, not HTML with HTTP 200 |
| Request S3 `index.html` directly | 403 without CloudFront authorization |
| Publish two different commits | Both complete; latest content and cache metadata are correct |
| Interrupt a staging publication and recover | Error is visible; retry or rollback restores a verified release |
| Roll back the first completed release | Checksums pass, original content returns and completion marker updates |
| Test selected optional features | Logs arrive, WAF records traffic, versioning is enabled and SNS test email arrives |
| Run another Terraform plan | No unexplained changes |
| Execute GitHub publication and rollback | Correct roles assumed; available environment gates and branch rules work |

These are live AWS acceptance checks. Local Terraform mocks and schema validation do not prove IAM permissions, certificate issuance or log delivery. No production account changes are made by repository quality checks.

## Retire a site

Stop its workflows first and decide whether you need to retain releases or a copy of live files. Review any DNS changes, especially if the zone also serves email or other sites. Export the files you need before emptying buckets; versioned buckets also contain noncurrent versions. Review the Terraform destruction plan deliberately—the normal plan guard rejects deletion/replacement of protected resources. The state bucket has `prevent_destroy` and may be shared by other sites; keep it and unrelated zones.

For an upgrade rather than retirement, retain resource identifiers and state keys and use [migration guidance](migration.md).
