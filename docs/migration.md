# Preserve an existing installation

Use this guide when your site already exists. The goal is to keep its live bucket, CloudFront distribution and public hosted zone while gaining repeatable publication and rollback. Start with a reviewed plan; a new-site example must not take ownership through an empty state.

1. Pause the old deployment workflow. Record AWS account, bucket name/region, CloudFront ID, hosted zone ID, ACM ARN, nameservers, Terraform version, provider version and every tfvars setting. Obtain the authoritative Terraform state. The old CI used local state in ephemeral runners: if that state is missing, restore a valid backup or import the existing resources at their original addresses before migrating. Never apply an empty state against existing resources.
2. Export `terraform state pull` to a protected backup and record `terraform state list`. Save `.terraform.lock.hcl` from the installation. Compare resource identifiers with AWS using read-only inventory commands. Do not commit state or backups.
3. Upgrade the Terraform CLI separately to a version supporting native S3 locks and removed blocks (the kit pins 1.10.5). Keep the production provider version during address migration; if it is older than this module's 6.38 minimum, review that provider upgrade in a separate plan first. The checked-in 6.67.0 lockfile is a reproducible new-install/test default, not proof that an old installation can upgrade without changes.
4. If migrating a local backend, initialize the original configuration with its local state before changing the backend block. Then use the new S3 backend with `terraform init -migrate-state -backend-config=backend.hcl`. Reuse the exact existing state key when already remote. Keep `dynamodb_table` alongside `use_lockfile=true` until all clients have moved; ensure their IAM roles can use both locks. Verify the remote state backup and lock permissions.
5. Copy the old tfvars into the migration root `src/`. Set `domain_enabled=true`; false is rejected. Preserve existing WAF, monitoring, versioning, region, project name, CSP, TLS and zone settings. `files_path` is accepted but unused. Existing custom minimum-TLS settings must remain supported by the module.
6. Run a saved plan and inspect every change. `moved` blocks map old resource addresses into the module; the zone remains at its original address. `removed` with destroy=false relinquishes S3 object management without deleting the objects. Expect new cache policies and a private archive bucket, updates to routing/cache/header behavior and output values. No deletion or replacement of the live bucket, zone or distribution is acceptable. Run `terraform show -json migration.tfplan | python3 scripts/check_plan.py` using the correct relative script path.
7. Review routing separately: the old function resolved directory indexes while its error fallback imitated a SPA. Explicitly choose static or spa before applying. The new function never converts missing JS/CSS/image files into HTML success responses. Verify that old S3 object metadata is suitable before switching cache policy; re-publish the existing build through the publisher immediately after the migration to install the intended metadata.
8. Apply only the reviewed plan. Verify unchanged resource IDs, HTTPS, aliases, CSP, routing and direct-S3 denial. Publish the existing build as the first archived release and exercise rollback in staging. Confirm a second plan has no changes. Only then enable the replacement workflow and remove long-lived credentials.

Existing ACM/global WAF resources should already be in us-east-1. If the old configuration points their provider at another region, reconcile provider bindings and imported resource identities before applying. A new regional provider alias is not sufficient evidence that migration is safe.

Bootstrap also has a moved block for its original unindexed DynamoDB table. Keep enable_legacy_lock_table=true until dual-lock migration is finished. Setting false on an existing backend destroys that table; perform that cleanup only after checking every client. `prevent_destroy` remains on the state bucket. The initial bootstrap state must be migrated to remote storage before using the backend maintenance workflow.

This procedure preserves infrastructure identities but is not a guarantee of zero behavior changes. Test the new caching, headers and routing on staging before production. Recovery uses the state backup and a reviewed reverse configuration/state migration; do not blindly restore old code after new module addresses have been saved.

## Commands for the reviewed migration

Set the paths to your existing installation and this kit. Authenticate to the correct AWS account first. Store the state backup somewhere private outside Git.

```bash
export ORIGINAL_ROOT=/absolute/path/to/existing-terraform-root
export KIT_DIR=/absolute/path/to/aws-staticsite
export MIGRATION_ROOT="$KIT_DIR/src"
terraform -chdir="$ORIGINAL_ROOT" state pull > /tmp/site-before-migration.tfstate
terraform -chdir="$ORIGINAL_ROOT" state list
aws sts get-caller-identity
```

The backup must contain the known production resources. A temporary path is convenient for this example, but move the backup to your team's protected storage before proceeding. Copy your **reviewed existing variable values** into `MIGRATION_ROOT/site.hcl` and configure `MIGRATION_ROOT/backend.hcl` with the authoritative backend and exact state key. If state is local, complete step 4 above before planning against the new root; copying a backend file alone does not migrate local state.

After any separately reviewed provider/backend upgrades:

```bash
terraform -chdir="$MIGRATION_ROOT" init -backend-config=backend.hcl
terraform -chdir="$MIGRATION_ROOT" plan -var-file=site.hcl -out=migration.tfplan
terraform -chdir="$MIGRATION_ROOT" show migration.tfplan
terraform -chdir="$MIGRATION_ROOT" show -json migration.tfplan | python3 "$KIT_DIR/scripts/check_plan.py"
```

Stop if the plan deletes or replaces the live bucket, distribution or zone, creates duplicates of existing resources, or changes identifiers/settings you have not deliberately approved. A passing guard is not a substitute for reading the whole plan. Once the checks in steps 1–7 are complete, apply that saved plan:

```bash
terraform -chdir="$MIGRATION_ROOT" apply migration.tfplan
terraform -chdir="$MIGRATION_ROOT" output
terraform -chdir="$MIGRATION_ROOT" plan -var-file=site.hcl
```

Record unchanged identifiers, then run [the production acceptance checks](operations.md#before-production). Use [publication instructions](operations.md#publish-an-update) to archive and republish your current build with the intended cache metadata. Practice rollback on staging before adopting [GitHub automation](github-actions.md), retaining this migration configuration rather than substituting the new-site root.
