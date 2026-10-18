# Production Schema Recovery Plan

Status: inventory-only; not a replayable schema snapshot.

## Safety rules
- Production catalog inspection is read-only.
- Never copy production user rows, Auth users, document rows, file metadata, secrets, or Drive contents into the test project.
- Do not apply this inventory as SQL.
- Do not deploy application Edge Functions into the empty test project until a complete, reviewed schema snapshot and required test-only secrets exist.
- Keep PR #30 in Draft until replay and upload tests pass.

## Catalog inventory (read-only inspection, 2026-10-18)
The current production catalog reports:
- 27 public base tables
- 2 public views
- 212 public columns
- 232 public table constraints
- 86 public indexes
- 50 public RLS policies
- 24 public triggers
- 61 application functions in the public/private schemas
- 5 public enum types: approval_decision, assignment_status, document_status, document_type, urgency_level

These are counts, not a complete schema definition. They do not capture all DDL, function bodies, grants, extensions, storage configuration, Auth configuration, or Edge Function secrets.

## Source recovery finding
The repository file `supabase/migrations/20261007200000_foundation_schema_rbac_rls.sql` is a placeholder comment that points to the migration applied to the production project. It is not a reproducible migration. The isolated project `wbns-edoc-test` has no application tables or recorded migrations.

## Required recovery procedure
1. Obtain a complete schema-only export from the authoritative database using a trusted PostgreSQL/Supabase export path with appropriate owner access. If no export capability is available, assemble DDL from catalog metadata and review it against the migration history; do not infer missing constraints or function bodies.
2. Review the export for secrets, real row data, production-only URLs, and environment-specific IDs; remove them before committing.
3. Include required extensions, enum types, tables, constraints, indexes, sequences, views, functions, triggers, grants, and RLS policies in dependency order. Review storage policies separately.
4. Apply the reviewed schema to `wbns-edoc-test` only, then compare its catalog to the source inventory and run schema/security tests.
5. Configure test-only Supabase secrets and an isolated test Drive folder. Do not reuse production Drive files or change production secrets.
6. Test small files, exactly 20,971,520 bytes, and 20,971,521 bytes through the complete browser → Edge Function → Apps Script → Drive path. Verify the Drive object and database metadata/attachment records for successful uploads, and verify rejection details for the oversized file.
7. Run signature, timestamp, replay, filename, deletion-boundary, shared-file, and failure-reconciliation tests. Record evidence before requesting review; keep PR #30 Draft until all blockers are cleared.

## Current decision
No production migration, function deployment, secret change, or user-data copy is authorized by this plan. The upload-size fix is not yet proven end-to-end.
