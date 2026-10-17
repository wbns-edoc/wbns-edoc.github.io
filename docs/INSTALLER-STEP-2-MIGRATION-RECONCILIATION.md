# Installer Step 2 — Migration Reconciliation

Date: 2026-10-17  
Scope: documentation and read-only repository inspection only. No Production changes.

## Findings verified in the repository

1. The repository currently contains **49 SQL files** under `supabase/migrations/`.
2. `20261007200000_foundation_schema_rbac_rls.sql` is only a 285-byte placeholder. It says the full SQL is maintained in the migration applied to the WBNS Supabase project. It cannot create the original schema from an empty database.
3. The repository therefore cannot currently be treated as a complete, reproducible fresh-install migration chain.
4. `supabase/tests/fixtures/recovered-production-catalog.sql` is explicitly marked as a generated, read-only catalog snapshot for isolated tests, not a historical migration and not intended for Production deployment. It also contains test-only changes and an incomplete subset of the live catalog; it must not be copied wholesale as an installer baseline.
5. A previous read-only inventory of the live catalog found 27 public base tables and 2 public views. The test fixture omits several live tables, so a fixture pass alone does not establish that a new school can install the complete application.
6. Repository migration filenames/count cannot be assumed to match the migrations recorded by the Supabase project. The exact reconciliation remains open until the live migration-history list is exported and compared by version.

## Safe conclusion

Do not run `supabase db reset`, do not replay these migrations against the WBNS Production project, and do not manufacture a replacement foundation migration from the test fixture. The correct next input is the live project's migration-history metadata, followed by a reviewed schema-only recovery/export from the live catalog. These are read-only inspection steps.

## Required next evidence from Supabase SQL Editor

Run this query in the WBNS Supabase Dashboard SQL Editor. It reads migration metadata only:

```sql
SELECT version, name
FROM supabase_migrations.schema_migrations
ORDER BY version;
```

Export the result as CSV and provide that CSV here. If the query returns a permission/schema error, provide the exact error text instead; do not grant permissions or change project settings to make it work.

## Acceptance criteria before authoring installer SQL

- Reconcile every live migration version against the repository.
- Identify missing source migrations and separate later forward-only fixes from the original baseline.
- Recover all required schemas, enums/types, tables, constraints, indexes, functions, triggers, views, RLS policies, grants, and extensions from authoritative live catalog definitions.
- Review privileged functions and RLS behavior before including them.
- Validate on a disposable, newly created Supabase project/database—not on WBNS Production.
- Run installation twice or verify a clean replay path, then test authentication, department-scoped access, executive permissions, document workflows, and Drive integration with test credentials.
- Keep project IDs, OAuth details, service-role keys, and bridge secrets out of the distributable template.

## Status

**Step 2 is in progress.** Repository-side blockers are confirmed. The next required input is the live migration-history CSV or the exact SQL Editor error. No Production changes have been made.
