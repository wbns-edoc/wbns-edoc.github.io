# Production schema recovery — 2026-10-15

This branch is a **recovery evidence branch**, not a deploy branch.

## Source
Read-only catalog queries were executed against the connected Wat Bueng Nam Sai School Supabase project `iigzzwyfxxtqbgjawyom` on 2026-10-15. No SQL writes or migrations were applied to Production.

## Captured artifacts
- `catalog/private-functions.sql`: function definitions from the `private` schema.
- `catalog/public-functions.sql`: function definitions from the `public` schema.
- `catalog/relations-and-security.sql`: catalog-derived reconstruction of enum types, table columns, constraints, indexes, RLS flags, policies, triggers, and views. The captured `security_invoker=true` view options are explicitly restored at the end.
- `catalog/migration-history.md`: comparison of Production migration history with SQL files in GitHub main.
- `catalog/security-follow-up.md`: read-only privilege findings and review items.
- `catalog/replay-dependency-audit.md`: verified trigger-function ordering requirements and the disposable PostgreSQL replay evidence.
- `catalog/migration-reconstruction-plan.md`: current gate status, historical migration gaps, stop conditions, and the safe path toward a reproducible clean-install candidate.
- `catalog/migration-coverage-matrix.md`: row-by-row mapping of all 55 Production migration history entries to repository SQL filename candidates or missing-source blockers.
- `tests/schema-recovery-snapshot.test.cjs`: static consistency checks for the recovery artifacts.
- `.github/workflows/schema-recovery-snapshot-ci.yml`: CI workflow for the static checks.

## Validation status
The latest GitHub Actions static snapshot check passed: [run 38754023251](https://github.com/wbns-edoc/wbns-edoc.github.io/actions/runs/38754023251). The latest isolated PostgreSQL 17 replay also passed: [run 38754023297](https://github.com/wbns-edoc/wbns-edoc.github.io/actions/runs/38754023297). This verifies replay in the compatibility harness and the included RBAC/RLS behavior checks; it **does not** prove full Supabase clean-install parity or Production readiness.

## Critical limitations
These files are **not a verified, standalone schema dump** and are **not ready to execute**. A catalog-generated script can miss or fail to fully preserve:
- grants, ownership, default privileges, extension configuration, publication settings, and some view options;
- dependency ordering and behavior that existed only in historical migrations;
- auth/storage schema objects and Supabase-managed objects outside the selected schemas.

The relation script is an evidence artifact for review. It may require fixes before it can run in a clean test database. Never apply these files to Production.

## Next validation steps
Follow [`catalog/migration-reconstruction-plan.md`](catalog/migration-reconstruction-plan.md) for the explicit go/no-go gates. In short: reconcile all 55 Production history entries with the 31 main-branch SQL files; build a separate clean-install candidate; validate grants, ownership, default ACLs, extensions and Supabase-managed dependencies; replay in a fresh local Supabase stack; then compare final catalogs and run security regressions. Keep Production untouched until every gate passes.

## Current finding
GitHub main contains a placeholder for `20261007200000_foundation_schema_rbac_rls.sql`; Production records 55 migrations, while main has 31 SQL migration files. Migration versions and names differ, so a naïve timestamp comparison would produce false positives.
