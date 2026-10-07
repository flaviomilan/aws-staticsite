# Automate your site with GitHub Actions

Follow this guide after [your first local publication](getting-started.md). You will put the site configuration in its own repository, authorize GitHub with OIDC and publish each push to `main`. OIDC supplies temporary AWS credentials; you do not need AWS access-key secrets.

Use the same AWS account, hosted zone, buckets and **exact site state key** as your local deployment. Creating another state for the same site can cause conflicts.

## 1. Copy the hosting configuration into your site repository

Keep `KIT_DIR`, `SITE_ROOT` and the values from the first-site guide available. Select a reviewed, published kit commit that contains the reusable workflows, then create the consumer configuration:

```bash
export KIT_SHA="$(git -C "$KIT_DIR" rev-parse HEAD)"
export SITE_REPO_DIR=/absolute/path/to/your/site-repository
export GITHUB_REPOSITORY=YOUR_OWNER/YOUR_SITE_REPOSITORY
mkdir -p "$SITE_REPO_DIR/infra" "$SITE_REPO_DIR/.github/workflows"
cp "$SITE_ROOT/main.tf" "$SITE_ROOT/variables.tf" \
  "$SITE_ROOT/.terraform.lock.hcl" "$SITE_ROOT/site.hcl" \
  "$SITE_ROOT/backend.hcl" "$SITE_REPO_DIR/infra/"
export CONSUMER_ROOT="$SITE_REPO_DIR/infra"
python3 - <<'PYCODE'
import os
from pathlib import Path
p = Path(os.environ['CONSUMER_ROOT']) / 'main.tf'
s = 'git::https://github.com/flaviomilan/aws-staticsite.git//modules/static-site?ref=' + os.environ['KIT_SHA']
p.write_text(p.read_text().replace('../../modules/static-site', s))
PYCODE
terraform -chdir="$CONSUMER_ROOT" init -backend-config=backend.hcl -lockfile=readonly
terraform -chdir="$CONSUMER_ROOT" plan -var-file=site.hcl
```

Expect no changes when copying the same settings. These instructions apply to the new-site example. For an existing legacy installation, retain its migration root and follow [migration](migration.md).

The `KIT_SHA` must exist in the remote kit repository. A local, unpublished commit cannot be used by Actions or Terraform's Git source. Reusable workflows and module sources must all use this same full 40-character SHA. If using a fork, replace the repository in module URLs, workflow `uses` references and supply `kit-repository` to each reusable workflow.

Commit a consumer `.gitignore` that excludes at least:

```gitignore
**/.terraform/
*.tfstate
*.tfstate.*
*.tfplan
*.tfvars
*_override.tf
node_modules/
dist/
```

Commit `infra/main.tf`, `variables.tf`, `.terraform.lock.hcl`, `site.hcl` and `backend.hcl`. The two `.hcl` configuration files contain identifiers, not credentials. Backend region identifies the state bucket; `site.hcl` region identifies the origin bucket. They can differ if you reuse a backend in another region.

## 2. Register or reuse GitHub's identity provider

Sign in locally to an identity authorized to manage IAM. In AWS IAM, open **Identity providers** and look for `token.actions.githubusercontent.com`. If present, reuse it and verify that its audiences include `sts.amazonaws.com`.

If absent, choose **Add provider → OpenID Connect**, enter:

| Field | Value |
|---|---|
| Provider URL | `https://token.actions.githubusercontent.com` |
| Audience | `sts.amazonaws.com` |

Choose **Add provider**. Do this once per AWS account; multiple sites can share it. Follow [AWS's OIDC provider instructions](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_create_oidc.html) rather than copying a stale certificate thumbprint.

Verify:

```bash
export AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
aws iam get-open-id-connect-provider \
  --open-id-connect-provider-arn "arn:aws:iam::$AWS_ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
```

Expect the GitHub URL and `sts.amazonaws.com` in `ClientIDList`. An existing provider missing this audience can be updated in IAM without replacing it.

## 3. Create separate infrastructure and publication roles

The runnable identity example supplies a maintenance policy for your already-created site and separate permissions for publishing. The GitHub infrastructure role cannot create its own IAM roles, manage the backend bucket or create a hosted zone. Keep those setup tasks with your authorized local identity.

```bash
mkdir -p "$SITE_REPO_DIR/identity"
cp "$KIT_DIR/examples/github-oidc/main.tf" \
  "$KIT_DIR/examples/github-oidc/permissions.tf" \
  "$KIT_DIR/examples/github-oidc/.terraform.lock.hcl" "$SITE_REPO_DIR/identity/"
export IDENTITY_ROOT="$SITE_REPO_DIR/identity"
python3 - <<'PYCODE'
import os
from pathlib import Path
p = Path(os.environ['IDENTITY_ROOT']) / 'main.tf'
s = 'git::https://github.com/flaviomilan/aws-staticsite.git//modules/github-oidc?ref=' + os.environ['KIT_SHA']
p.write_text(p.read_text().replace('../../modules/github-oidc', s))
PYCODE
cat > "$IDENTITY_ROOT/identity.hcl" <<EOF
aws_region = "$AWS_REGION"
repository = "$GITHUB_REPOSITORY"
environment = "$ENVIRONMENT"
name_prefix = "$SITE_ID-$ENVIRONMENT"
domain = "$DOMAIN"
aliases = ["www.$DOMAIN"]
hosted_zone_id = "$HOSTED_ZONE_ID"
bucket_name = "$SITE_BUCKET"
release_bucket_name = "$RELEASE_BUCKET"
distribution_id = "$DISTRIBUTION_ID"
state_bucket_name = "$STATE_BUCKET"
site_state_key = "$SITE_STATE_KEY"
enable_waf = false
enable_monitoring = false
enable_access_logs = false
enable_additional_metrics = false
EOF
cat > "$IDENTITY_ROOT/backend.hcl" <<EOF
bucket = "$STATE_BUCKET"
key = "identity/$SITE_ID/$ENVIRONMENT.tfstate"
region = "$AWS_REGION"
encrypt = true
use_lockfile = true
EOF
```

If the state bucket is in a different region, update the backend region. Keep `domain` and `aliases` aligned with `site.hcl`; certificate requests are limited to those names. If you enabled optional resources, change the four feature flags in `identity.hcl` to match `site.hcl` before proceeding. Versioning uses the core S3 configuration permissions and needs no separate identity flag.

```bash
terraform -chdir="$IDENTITY_ROOT" init -backend-config=backend.hcl -lockfile=readonly
terraform -chdir="$IDENTITY_ROOT" plan -var-file=identity.hcl -out=identity.tfplan
terraform -chdir="$IDENTITY_ROOT" show identity.tfplan
terraform -chdir="$IDENTITY_ROOT" apply identity.tfplan
export AWS_INFRA_ROLE_ARN="$(terraform -chdir="$IDENTITY_ROOT" output -raw infrastructure_role_arn)"
export AWS_PUBLISH_ROLE_ARN="$(terraform -chdir="$IDENTITY_ROOT" output -raw publication_role_arn)"
```

Review `permissions.tf` and the plan with your account administrator. The policy scopes state access to the site's state/lock, bucket configuration to named buckets, DNS to the selected zone and distribution updates to the existing distribution. It intentionally permits broader supporting CloudFront policy operations, certificate lifecycle in the account's `us-east-1` region and selected logging/subscription APIs. Some creation/list APIs require `Resource = "*"`; this template is a starting maintenance policy, not a claim of minimum permissions for every organization.

To inspect its rendered JSON after apply:

```bash
terraform -chdir="$IDENTITY_ROOT" output -raw infrastructure_policy_json > /tmp/site-infrastructure-policy.json
python3 -m json.tool /tmp/site-infrastructure-policy.json
```

The publication role can read/write only the live and release buckets, invalidate this distribution and read it for smoke checks. It cannot delete content, access state or change DNS. Its trust requires the exact repository and environment. Infrastructure also trusts `main` for its plan job, which runs without an environment approval. Anyone who can execute arbitrary code on that trusted branch can use the infrastructure permissions; protect `main` with reviewed pull requests.

The identity example uses native S3 locks in the default workspace. Legacy DynamoDB locking or nondefault Terraform workspaces require adjusted backend permissions before adoption. IAM policies also remain subject to account SCPs and permission boundaries; see [troubleshooting](troubleshooting.md#github-cannot-assume-the-role).

## 4. Configure the GitHub repository

In **Settings → Environments**, create the exact environment from `ENVIRONMENT`, normally `production`. Restrict deployment branches to `main` and enable required reviewers when your repository/plan supports them. Public and private repositories have different protection availability; check [GitHub's environment documentation](https://docs.github.com/en/actions/how-tos/deploy/configure-and-manage-deployments/manage-environments).

If reviewers are unavailable, use the available branch protection and recognize that apply/publication will proceed without that manual gate. Do not describe an unconfigured or unsupported approval as protection you have enabled.

In **Settings → Secrets and variables → Actions → Variables**, create these **repository variables**, not environment-only variables. Repository variables are available when the caller evaluates reusable-workflow inputs.

| Variable | Value from this walkthrough |
|---|---|
| `AWS_INFRA_ROLE_ARN` | `AWS_INFRA_ROLE_ARN` |
| `AWS_PUBLISH_ROLE_ARN` | `AWS_PUBLISH_ROLE_ARN` |
| `HOSTED_ZONE_ID` | `HOSTED_ZONE_ID` |
| `SITE_BUCKET` | `SITE_BUCKET` |
| `RELEASE_BUCKET` | `RELEASE_BUCKET` |
| `CLOUDFRONT_DISTRIBUTION_ID` | `DISTRIBUTION_ID` |
| `SITE_URL` | `SITE_URL` |

The last four destination variables support manual rollback; publication receives these values from Terraform outputs. If [GitHub CLI](https://cli.github.com/) is installed and authenticated, set them directly:

```bash
gh variable set AWS_INFRA_ROLE_ARN --repo "$GITHUB_REPOSITORY" --body "$AWS_INFRA_ROLE_ARN"
gh variable set AWS_PUBLISH_ROLE_ARN --repo "$GITHUB_REPOSITORY" --body "$AWS_PUBLISH_ROLE_ARN"
gh variable set HOSTED_ZONE_ID --repo "$GITHUB_REPOSITORY" --body "$HOSTED_ZONE_ID"
gh variable set SITE_BUCKET --repo "$GITHUB_REPOSITORY" --body "$SITE_BUCKET"
gh variable set RELEASE_BUCKET --repo "$GITHUB_REPOSITORY" --body "$RELEASE_BUCKET"
gh variable set CLOUDFRONT_DISTRIBUTION_ID --repo "$GITHUB_REPOSITORY" --body "$DISTRIBUTION_ID"
gh variable set SITE_URL --repo "$GITHUB_REPOSITORY" --body "$SITE_URL"
```

No AWS secrets are needed with OIDC. The workflow declares `contents: read` and `id-token: write`. Your existing role secrets should not override these explicit role inputs; remove long-lived AWS keys after confirming the replacement.

## 5. Add publication and rollback workflows

```bash
# Use this for Astro or another npm-based static build:
export SITE_WORKFLOW=consumer-workflow.yml.example
# For plain HTML, set SITE_WORKFLOW=html-workflow.yml.example instead.
cp "$KIT_DIR/examples/$SITE_WORKFLOW" "$SITE_REPO_DIR/.github/workflows/site.yml"
cp "$KIT_DIR/examples/rollback-workflow.yml.example" "$SITE_REPO_DIR/.github/workflows/rollback.yml"
python3 - <<'PYCODE'
import os
from pathlib import Path
for name in ('site.yml', 'rollback.yml'):
    p = Path(os.environ['SITE_REPO_DIR']) / '.github/workflows' / name
    text = p.read_text().replace('KIT_COMMIT_SHA', os.environ['KIT_SHA'])
    text = text.replace('site-id: example', 'site-id: ' + os.environ['SITE_ID'])
    text = text.replace('environment: production', 'environment: ' + os.environ['ENVIRONMENT'])
    text = text.replace('aws-region: sa-east-1', 'aws-region: ' + os.environ['AWS_REGION'])
    p.write_text(text)
PYCODE
```

The replacement command sets the same site ID, environment, region and kit SHA in both workflows. Review those values before committing. Rollback must use the same region as publication. Keep `working-directory: infra`, `backend-config-file: backend.hcl` and `var-file: site.hcl` for the configuration you copied above.

The supplied build job runs Node.js 22, `npm ci` and `npm run build`, then uploads the contents of `dist`. It assumes your package files are at the repository root. For the Astro example, copy its `package.json`, `package-lock.json`, `astro.config.mjs` and `src` into your new site's root. For another framework, adjust its build commands and output directory.

For an **empty** site repository, you can copy one of the ready-to-publish samples:

```bash
# Plain HTML (pair with html-workflow.yml.example):
mkdir -p "$SITE_REPO_DIR/site"
cp -R "$KIT_DIR/examples/html/site/." "$SITE_REPO_DIR/site/"
```

Or, for the Astro workflow:

```bash
cp "$KIT_DIR/examples/astro/package.json" "$KIT_DIR/examples/astro/package-lock.json" \
  "$KIT_DIR/examples/astro/astro.config.mjs" "$SITE_REPO_DIR/"
cp -R "$KIT_DIR/examples/astro/src" "$SITE_REPO_DIR/"
```

Choose one sample; keep your existing source if you already have a site.

The plain HTML workflow already omits Node.js and build steps and uploads `site`. Copy your HTML into that location or change the upload path to your existing static files directory. Its artifact must contain `index.html` at the root. If using hidden verification files, explicitly include only the needed `.well-known` content; see [artifact requirements](operations.md#prepare-the-files).

Commit the configuration, workflow files and source through your normal review process, then push to `main`. Use **Actions → Site** to follow the run:

1. Build produces the `site` artifact.
2. Infrastructure plans against remote state; review the saved-plan artifact and approve the environment gate if configured. Saved plans may contain sensitive resource values; keep repository access appropriate.
3. Apply uses the reviewed plan for that exact caller commit and checks DNS delegation before changing the site.
4. Publication assumes the publication role, archives the build, uploads it, waits for invalidation and runs the HTTPS/private-origin checks. Publication has its own environment gate if configured.

Expect all jobs to pass and the new content to load. A stale plan is rejected; rerun planning after concurrent infrastructure changes. The infrastructure workflow uses a read-only provider lockfile, so commit `.terraform.lock.hcl` before the first run.

## 6. Prove rollback and maintain permissions

Publish two different commits. Copy the first completed publication's full SHA from the Actions run. Open **Actions → Restore site → Run workflow**, use branch `main` and enter that SHA as `release-id`. Approve the environment gate if configured, then verify the first content is restored. The release must still exist in the 30-day archive.

For a new optional feature, update and apply `identity.hcl` locally first, then update `infra/site.hcl`. To disable a feature, keep permissions until removal has completed. For a kit upgrade, change every pinned module/workflow SHA together, initialize intentionally, review any provider lockfile update and test on staging.

Do not repurpose the site role to maintain the backend or DNS zone itself. Backend maintenance requires the original bootstrap state and a separately reviewed local identity/role. The kit's bootstrap workflow is for maintaining an already-created remote backend, not for first-time setup.
