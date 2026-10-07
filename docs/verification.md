# Implementation verification

Verified locally on 2026-10-06. No account resources were provisioned, modified or destroyed, and no GitHub release was published.

| Check | Result |
|---|---|
| Terraform formatting | Passed recursively |
| Terraform schema validation | Passed for src, bootstrap, DNS/existing-zone/production/identity examples and the github-oidc module |
| Static-site mocked tests | 7 passed: economic defaults, production SPA/edge region, paid metrics, invalid routing/canonical/preload and aliases outside the zone |
| Migration-wrapper mocked tests | 2 passed: legacy security/metrics defaults and rejection of domain_enabled=false |
| Bootstrap mocked tests | 2 passed: native-lock new backend and legacy table retention |
| OIDC mocked tests | 2 passed: scoped publication identity/permissions and wildcard repository rejection |
| Identity setup policy tests | 2 passed: economic permissions/state-lock isolation and production resource names/delivery permissions/inline-policy size |
| Python tests | 12 passed: publication ordering/cache, interruption, archive checksum, rollback, release conflict, artifact paths and state/DNS guards |
| JavaScript routing tests | 3 passed: static/SPA behavior and canonical redirect with encoded/repeated query values |
| Workflow validation | actionlint passed for executable workflows and consumer templates |
| Security analysis | Trivy passed HIGH/CRITICAL gate with the documented, path-scoped SSE-S3 exception in .trivyignore.yaml |
| Astro example | npm ci and static build passed; generated homepage and about directory index |
| Git whitespace checks | Passed |

Toolchain: Terraform 1.10.5, AWS provider 6.67.0, actionlint 1.7.12, Trivy 0.75.0, Astro 7.3.6, local Node 26.8.1 and Python 3.14.7. CI explicitly selects Node 22, which satisfies Astro's >=22.12.0 requirement. Provider checksums and Actions commits are recorded; verification-tool archives use pinned SHA-256 checksums.

Tests exercise providers with mocks, including simulated apply/teardown. They do not prove actual AWS permissions, certificate issuance, log delivery, DNS delegation or resource-preserving migration. GitHub environment protections must also be configured on the consuming repository. Complete the AWS staging acceptance procedure in [operations](operations.md) and review the production state/plan using [migration](migration.md).

Publication and rollback retain old keys and are not atomic. The implementation deliberately favors cached-asset compatibility; removed pages may remain reachable until a separately reviewed cleanup. Smoke-test failure does not automatically restore the previous release.

## Documentation and example verification

The user setup guides were checked locally for existing file links and heading anchors, Bash syntax and forwarding of every hosting option in both runnable profiles. The HTML, npm-build and rollback workflow templates pass actionlint. The identity example validates and its policy tests use provider mocks; no live IAM role assumption was attempted. Trivy passes the HIGH/CRITICAL gate with the existing scoped exception.

For contributing changes, run the relevant checks locally:

```bash
terraform fmt -check -recursive
terraform -chdir=examples/github-oidc init -backend=false -lockfile=readonly
terraform -chdir=examples/github-oidc validate
terraform -chdir=examples/github-oidc test
terraform -chdir=modules/static-site init -backend=false -lockfile=readonly
terraform -chdir=modules/static-site test
python3 -m unittest discover -s tests -v
node --test tests/routing.test.cjs
python3 scripts/install_check_tools.py /tmp/static-site-checks actionlint trivy
/tmp/static-site-checks/actionlint
/tmp/static-site-checks/actionlint examples/consumer-workflow.yml.example examples/html-workflow.yml.example examples/rollback-workflow.yml.example
/tmp/static-site-checks/trivy config --ignorefile .trivyignore.yaml --exit-code 1 --severity HIGH,CRITICAL --skip-dirs .git --skip-dirs examples/astro/node_modules .
git diff --check
```

The Terraform CI matrix also validates the runnable identity root. Follow [AWS staging acceptance](operations.md#before-production) to verify actual permissions, DNS, certificates and log delivery; local checks cannot certify a deployment in your account.
