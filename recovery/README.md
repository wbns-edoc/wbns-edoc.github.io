# Production schema recovery — 2026-10-15

This branch is a **recovery evidence branch**, not a deploy branch.

## Source
Read-only catalog queries were executed against the connected Wat Bueng Nam Sai School Supabase project `iigzzwyfxxtqbgjawyom` on 2026-10-15. No SQL writes or migrations were applied to Production.

## Captured artifacts
- `catalog/private-functions.sql`: function definitions from the `private` schema.
- `catalog/public-functions.sql`: function definitions from the `public` schema.
- `catalog/relations-and-security.sql`: catalog-derived reconstruction of enum types, table columns, constraints, indexes, RLS flags, policies, triggers, and views.
- `catalog/migration-history.md`: comparison of Production migration history with SQL files in GitHub main.

## Critical limitations
These files are **not a verified, standalone schema dump** and are **not ready to execute**. A catalog-generated script can miss or fail to fully preserve:
- identity/generated column attributes and sequence ownership/defaults;
- grants, ownership, default privileges, extension configuration, publication settings, and some view options;
- dependency ordering and behavior that existed only in historical migrations;
- auth/storage schema objects and Supabase-managed objects outside the selected schemas.

The relation script is an evidence artifact for review. It may require fixes (for example, generated-column syntax or view security options) before it can run in a clean test database. Never apply these files to Production.

## Next validation steps
1. Compare this catalog snapshot with every versioned migration on all relevant branches.
2. Build a disposable/non-production database and validate reconstructed DDL there.
3. Compare table/column/constraint/index/function/policy/trigger/view inventories against Production.
4. Rebuild the Foundation migration and later migration sequence only after equivalence tests pass.
5. Keep Production untouched until a tested recovery plan is approved.

## Current finding
GitHub main contains a placeholder for `20261007200000_foundation_schema_rbac_rls.sql`; Production records 55 migrations, while main has 31 SQL migration files. Migration versions and names differ, so a naïve timestamp comparison would produce false positives.
