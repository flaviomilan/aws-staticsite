# Solve setup and publication problems

Use the symptom below, run the read-only checks and fix the cause before retrying. Commands use the values from [first setup](getting-started.md) or [operations](operations.md#recover-your-values). Start every investigation with `aws sts get-caller-identity` to confirm the account.

## AWS login expired or the wrong account is selected

Run `aws sso login --profile static-site`, set `AWS_PROFILE=static-site` and retry `aws sts get-caller-identity`. Check `aws configure list` for the selected profile/region. If environment credentials override your profile, activate the intended session and remove the stale credential exports in your shell. Do not paste credential values into an issue.

## Bucket name is already taken

S3 names are globally unique. For a new deployment that has not created the bucket, choose another lowercase name and re-plan. For an existing managed bucket, do not change its name as a retry: verify the account, configuration and authoritative state first. See [migration](migration.md) when state is missing.

## DNS delegation does not match Route53

```bash
aws route53 get-hosted-zone --id "$HOSTED_ZONE_ID"
dig NS "$DOMAIN"
```

Compare the four nameservers with the registrar/parent delegation. Check that the chosen zone is public and that you did not select an unused duplicate. Correct delegation, wait for DNS caches, then rerun the delegation command from setup. `dig NS` alone is not sufficient proof of the parent delegation; the provided check verifies it. For a subdomain, inspect its parent's NS record.

## Certificate validation is pending

From your hosting root:

```bash
export CERTIFICATE_ARN="$(terraform -chdir="$SITE_ROOT" output -raw acm_certificate_arn)"
aws acm describe-certificate --region us-east-1 --certificate-arn "$CERTIFICATE_ARN" \
  --query 'Certificate.{Status:Status,Validation:DomainValidationOptions}'
```

If apply failed before outputs were saved, locate the request with `aws acm list-certificates --region us-east-1` or in the ACM console and use its ARN. Check the actual `ResourceRecord.Name`, `Type` and `Value` from the response; ACM does not use a universal `_acm-challenge` name. Run `dig CNAME ACTUAL_RECORD_NAME` and compare its answer.

Confirm the public zone's delegation, all aliases belonging to it and any CAA restrictions (`dig CAA "$DOMAIN"`). Correct DNS, retain validation CNAMEs and re-plan. Do not recreate the zone or repeatedly request certificates to fix a delegation problem. ACM is managed in `us-east-1` for CloudFront, independently of the origin region.

## The homepage returns 403

Before publication, this usually means `index.html` does not exist. After publication:

```bash
aws s3api head-object --bucket "$SITE_BUCKET" --key index.html
aws cloudfront get-distribution --id "$DISTRIBUTION_ID" \
  --query 'Distribution.{Status:Status,Origins:DistributionConfig.Origins}'
aws s3api get-bucket-policy --bucket "$SITE_BUCKET" --query Policy --output text
```

Check that the distribution is deployed, its origin uses OAC and the bucket policy permits the CloudFront service with this distribution ARN. Leave S3 public access blocked. A direct-S3 403 is expected; a CloudFront homepage 403 after a valid upload is not. With WAF blocking enabled, inspect WAF logs for matching rules too.

If only a nested page fails, confirm its actual object key (`about/index.html` for static directory routing) and `routing_mode`. Missing assets may return 403 from private S3; they must not be converted to successful HTML responses.

## The site shows old content

Check the completed release marker and S3 object metadata using [operations](operations.md#understand-caching). Look at the most recent invalidation status. If upload finished but invalidation failed, retry the same build/SHA after resolving permissions. For immutable browser-cached assets, change the content hash in the filename and republish; invalidation only clears CloudFront caches.

## GitHub cannot assume the role

Check the workflow has `id-token: write`, the configured role ARN belongs to this AWS account and the IAM provider audience contains `sts.amazonaws.com`.

```bash
aws iam get-role --role-name YOUR_SITE_ROLE_NAME \
  --query Role.AssumeRolePolicyDocument
```

Compare the exact `owner/repo`, branch `main` and environment spelling with the trust subjects. Publication uses `repo:OWNER/REPO:environment:ENVIRONMENT`; infrastructure also accepts `repo:OWNER/REPO:ref:refs/heads/main` for planning. A renamed repository or environment requires updating the role. Custom OIDC subject templates require adapting trust conditions; the example assumes GitHub's default subjects.

Use repository variables for reusable-workflow role inputs. Confirm the workflow runs on `main` and its environment branch rules permit that branch. If the action cannot be found, verify the kit repository and full SHA are published and readable.

## Terraform or publication receives AccessDenied

Record the failing AWS API, assumed role and resource ARN from the error. Compare them with the rendered policy from [identity setup](github-actions.md#3-create-separate-infrastructure-and-publication-roles). A new optional feature needs its identity flag and locally applied permissions before CI can create it. Keep removal permissions until disabling the feature finishes.

State access needs reads/writes to the exact state object and reads/writes/deletion for its `.tflock` object. The sample identity policy assumes native S3 locks and the default Terraform workspace. SCPs, session policies and permission boundaries can deny actions even when an inline policy allows them. Have your account administrator review the specific denial rather than adding blanket administrator permissions.

## Terraform reports a lock or stale plan

Check whether another workflow/local operator is using the same state. Wait for an active operation to finish, then re-plan. A saved plan is invalid after intervening state changes. If a lock remains after an abandoned operation, verify no writer is active and use your team's reviewed lock-recovery procedure; do not blindly delete lock objects or bypass locking.

If CI reports a missing/changed lockfile, initialize the intended provider version locally and commit the reviewed `.terraform.lock.hcl` update. A new root copying an existing backend must keep the exact site key; never fix conflicts by applying an empty state against existing resources.

## Astro build or artifact validation fails

Check Node.js is 22.12+ and `npm ci` uses the committed lockfile. Run `npm run build` locally and verify the output contains a root `index.html`. Set the artifact upload path to that output (`dist` by default), not the repository or a nested archive.

For publisher path errors, remove symlinks and hidden build files; include only intentional `.well-known` files. For `Release SHA already exists with different content`, either reproduce the original bytes or commit a new content/build change and use its new SHA.

## Logs, metrics or email are missing

Inspect `terraform output enabled_features` first. Access logs and WAF logs are separate features. Generate traffic and wait for delivery; access logs arrive in S3 while WAF uses its CloudWatch log group in `us-east-1`. Confirm your role permitted log-delivery setup and that the last apply succeeded.

Open CloudWatch/SNS in `us-east-1`, confirm the email subscription and send a test notification. CacheHitRate requires the separately enabled paid metrics subscription; basic monitoring does not subscribe to it. Low-traffic alarms can have missing data and are not synthetic health checks.

## Rollback cannot find or validate a release

Confirm the full SHA and correct release bucket. Check that `releases/SHA/manifest.json` exists and all its archive objects remain. Releases expire after 30 days. A missing/corrupt archive fails before rollback writes live files; use another complete known-good archive or rebuild from the corresponding source with a new SHA. See [rollback](operations.md#restore-a-previous-release).
