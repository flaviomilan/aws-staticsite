# Changelog

## Unreleased — 1.0.0 reusable-kit release candidate

### Added

- Backend-independent static-site module and separate GitHub OIDC infrastructure/publication roles.
- Reusable reviewed-plan infrastructure workflow, artifact publication and verified rollback.
- Correct site-specific WAF metric dimensions for global distributions.
- Standard access logs v2, configurable routing/canonical host and separately enabled paid metrics.
- DNS, existing-zone, production, HTML, Astro and SPA examples; documented operating/cost profiles.
- Mocked Terraform tests, routing/publication failure tests, actionlint and Trivy quality gates.

### Migration required

- `src/` now consumes the module with moved blocks and an S3 backend.
- `domain_enabled=false` is rejected; initial DNS creation uses a separate configuration.
- Terraform no longer manages site files. Removed blocks retain existing objects; publish artifacts through the content workflow.
- Blanket 403/404-to-200 fallback is removed. Choose static or SPA explicitly.
- New module HSTS preload/subdomains and WAF are opt-in; the wrapper retains legacy security/monitoring defaults.
- New backends use native S3 locking; existing DynamoDB tables remain until every client migrates.
- The unsafe four-job deployment is replaced. Initial bootstrap runs locally with state migration before CI maintenance.

No production resources or releases are changed by this repository update. Follow docs/migration.md before applying.

### User setup documentation

- End-to-end first-site setup, GitHub OIDC automation, optional-feature recipes, symptom-based troubleshooting and publication/rollback acceptance checks.
- Runnable hosting examples expose every supported site option; identity setup includes a reviewable maintenance policy with optional-feature permissions.
- User guides now focus on publishing and operating a site, without Mermaid diagrams or directory inventories.
