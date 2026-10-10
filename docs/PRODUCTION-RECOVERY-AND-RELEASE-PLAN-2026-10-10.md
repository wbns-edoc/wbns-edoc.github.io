# Production Recovery and Release Plan — 2026-10-10

## Decision

Do not merge or deploy the current release branch yet. The release blocker is recoverable without creating a paid Supabase branch/project and without changing Production during diagnosis.

Current connected Production project: `iigzzwyfxxtqbgjawyom`. All checks below were read-only.

## Confirmed current state

- Production catalog: 1 profile, 0 departments, 0 documents, 0 document_files, 0 google_drive_files.
- Public workflow RPC catalog:
  - `public.assign_document(uuid,uuid,text,timestamptz)`: SECURITY DEFINER; EXECUTE granted to authenticated; denied to anon.
  - `public.update_document_status(uuid,document_status,text)`: SECURITY DEFINER; EXECUTE granted to authenticated; denied to anon.
  - `public.set_document_deadline(uuid,uuid,timestamptz,timestamptz)`: SECURITY DEFINER; EXECUTE granted to authenticated; denied to anon.
  - `public.create_approval(uuid,uuid,integer)` and `public.decide_approval(uuid,approval_decision,text)`: SECURITY INVOKER; authenticated can execute; anon cannot.
- `public.documents` has no `department_id`. Its SELECT policy permits creator/current owner OR anyone with the global `document.view` permission. UPDATE policy similarly uses creator/current owner or global permissions.
- `document_files` and `google_drive_files` policies are not sufficient evidence of department isolation because the parent document currently has no department scope.
- Production migration history contains 26 entries. Repository foundation migration `supabase/migrations/20261007200000_foundation_schema_rbac_rls.sql` is only a placeholder.
- Static CI correctly fails closed on the three public SECURITY DEFINER RPC definitions. The database replay test cannot yet run because the foundation SQL is not reproducible.

## Release recovery sequence

### Phase 0 — Freeze risky actions

1. Keep PR #6 open and draft; do not merge.
2. Do not run `apply_migration`, alter RLS/grants, deploy Edge Functions, reset Production, or remove/modify roles as part of diagnosis.
3. Do not create a Supabase development branch/project. Use local PostgreSQL in GitHub Actions or an owner-controlled local environment to keep infrastructure cost at 0 THB.
4. Preserve the only System Admin assignment. Any role-management migration must contain and test a last-System-Admin invariant before it is considered.

### Phase 1 — Recover an authoritative schema source

The existing placeholder must not be replaced with guessed DDL.

Preferred path, run by a project owner on a trusted machine with the Supabase CLI and database credentials kept local:

1. Make a schema-only dump of the connected project (do not send connection strings or keys):
   `pg_dump --schema-only --no-owner --no-privileges --schema=public --schema=private --schema=extensions "$DATABASE_URL" > wbns-production-schema.sql`
2. Preserve migration history separately from the schema dump. The dump is a recovery/reference artifact, not automatically a replacement for the original ordered migrations.
3. Compare the schema dump against all 26 remote migration-history entries and all repository migration files. Recover exact historical SQL from a trusted source if available. Mark any irrecoverable migration explicitly rather than fabricating its past contents.
4. Add the recovered, reviewed source to version control with a clear provenance note. Never commit credentials, data dumps, JWTs, service-role keys, or personal document data.

If the owner cannot run a schema-only dump, provide the original full migration SQL files or a schema-only SQL export through the repository's approved private workflow. Do not provide passwords or API secrets in chat.

### Phase 2 — Establish reproducible CI before changing behavior

1. Rebuild local DB from the recovered ordered migrations.
2. Verify the local schema against the production catalog: enums, tables/columns, foreign keys, indexes, triggers, RLS enablement, policies, functions, views, grants, and default privileges.
3. Run `supabase db reset` and `supabase test db` in CI using local disposable PostgreSQL services.
4. Keep the migration-order guard enabled. It should continue to fail while the three protected public RPCs are redefined as SECURITY DEFINER by later migrations.

### Phase 3 — Implement authorization, not just wrapper syntax

A public SECURITY INVOKER wrapper that delegates to a SECURITY DEFINER private routine does not itself fix authorization. Review and harden the private implementations too.

Required model:
- Four departments: กลุ่มบริหารงานวิชาการ, กลุ่มบริการงบประมาณ, กลุ่มบริหารงานบุคคล, กลุ่มบริหารงานทั่วไป.
- System Admin, เจ้าหน้าที่ธุรการ, ผู้อำนวยการสถานศึกษา, รองผู้อำนวยการสถานศึกษา are central roles, not department members.
- Central roles must have explicit role/action permissions. Do not automatically give them identical permissions.
- Add a document department scope (for example `documents.department_id`) with a foreign key and appropriate indexes; define how incoming/outgoing registry entries acquire their department.
- Enforce the same department/delegation checks in RLS, workflow RPCs, file attachment/upload authorization, reporting views, and download/link access.
- Prevent creator/current-owner predicates from accidentally retaining access after a document is transferred to another department unless policy explicitly allows it.
- Keep `document_files` and `google_drive_files` metadata and the underlying Drive object protected by the same parent-document authorization.
- Preserve least privilege: deny anon, grant only the needed authenticated RPCs, and keep SECURITY DEFINER routines in a non-exposed schema with fixed search_path, auth.uid() checks, and explicit permission/scope checks.

### Phase 4 — Tests required before any Production rollout

Automate at minimum:
1. User in department A can read permitted department A document.
2. User in department A cannot list, read by UUID, update, assign, approve, attach, or download department B document.
3. Creator/previous owner loses access after transfer where the policy requires it.
4. Central clerical role can perform only its approved registry actions across departments.
5. Director and deputy actions follow the approved delegation matrix.
6. System Admin account management works without implicitly granting document-content access unless approved.
7. Anonymous calls cannot execute privileged RPCs.
8. Authenticated RPCs reject missing identity, missing permission, invalid status transition, invalid assignee, and unauthorized department scope.
9. File upload compensation never deletes a resource after ambiguous lookup/attachment failure.
10. Last System Admin cannot be removed/deactivated or lose its required role.
11. Database migration replay works from an empty local database.
12. Backup restoration is demonstrated before release.

Use synthetic users/documents in the local test DB. Production currently has no documents or departments, but do not rely on emptiness as a substitute for backup/rollback preparation.

### Phase 5 — Production change window

Only after phases 1–4 pass and the school owner approves:
1. Take and verify a recoverable backup/export and record current migration/catalog state.
2. Review the exact forward-only migration SQL, grants, RLS diffs, and rollback/forward-repair strategy.
3. Apply one reviewed migration at a time, verify catalogs and smoke tests after each step, and stop on any mismatch.
4. Seed the four departments and explicitly verify the central-role assignments without assigning those central roles to departments.
5. Run a controlled upload/workflow test using an approved test account and test document.
6. Deploy the matching frontend/Edge Function version only after its environment configuration and origin are confirmed.
7. Release only when authorization tests, CI, backup/restore, monitoring, and owner approval are recorded.

## Current go/no-go

**NO-GO for Production release today.** The next actionable prerequisite is the authoritative schema/migration recovery in Phase 1. It is the blocker that prevents a reliable local database replay and makes a safe, tested forward-only fix impossible to certify. No Production changes were made while preparing this plan.
