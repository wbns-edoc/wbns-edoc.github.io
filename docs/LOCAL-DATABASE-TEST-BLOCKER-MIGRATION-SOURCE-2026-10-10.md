# Blocker: reproducible local database tests

Date: 2026-10-10
Project: WBNS e-Document
Supabase project ref: `iigzzwyfxxtqbgjawyom`

## Verified findings

- GitHub Actions run [Workflow RPC Security CI #2](https://github.com/wbns-edoc/wbns-edoc.github.io/actions/runs/37966549603) failed during `supabase db reset`, before database tests ran.
- The first foundation migration file, `supabase/migrations/20261007200000_foundation_schema_rbac_rls.sql`, is a placeholder. It explicitly says the full SQL is maintained in the migration applied to the Supabase project.
- The next migration, `20261007205000_workflow_engine_v1.sql`, defines functions using `document_status`. Since the placeholder foundation file did not create that type, local replay fails with `type "document_status" does not exist`.
- Production migration history contains 26 entries. The repository's migration directory does not reproduce that history as a complete, replayable set of SQL migrations. Some names/versions in the live history do not align with the checked-in files.
- Read-only Production catalog inspection confirms `document_status` and `approval_decision` are types in the `public` schema. No Production changes were made while investigating.

## Impact

The local database CI cannot validate migration replay, RPC security tests, or RLS behavior until the repository has a complete, reviewed schema history. Changing type references alone would conceal the missing foundation schema and is not a safe fix.

## Required remediation

1. Recover the actual migration SQL and complete schema from an authoritative, reviewed source or backup; do not reconstruct missing foundation DDL by guesswork.
2. Reconcile all 26 live migration-history entries with checked-in migrations, recording exact provenance and any migrations that are intentionally absent.
3. Build a clean disposable local database and replay the complete migration set from zero.
4. Run the RPC catalog tests and add behavioral tests for permission checks, department isolation, approvals, and the last-System-Admin guard.
5. Review backup/restore and obtain owner approval before any Production migration or privilege changes.

## Safety guard

The workflow now checks for this known placeholder and fails before pulling/starting local service containers. This is an explicit blocker, not a passing test. It does not connect to or modify Production and does not create a paid Supabase project or branch.

## Release status

**Not release-ready.** Production remains unchanged. The Draft PR must not be merged based on the current CI results alone.
