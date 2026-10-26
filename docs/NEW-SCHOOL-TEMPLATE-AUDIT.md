# New-school Template Audit — 2026-10-17

Status: **BLOCKED — do not use as a production installer**.

## Scope and safety
- Read-only inspection of repository files and GitHub workflow metadata.
- No Supabase query, migration, project creation, production deployment, or production data modification was performed in this audit.
- Installer documents are on `docs/school-installer-blueprint`; pull request #29 remains a draft and has not been merged.

## Findings

### Blocker A — Foundation migration is not reproducible
`supabase/migrations/20261007200000_foundation_schema_rbac_rls.sql` contains a placeholder comment stating that the full SQL is maintained in the migration applied to the WBNS Supabase project. It does not create the foundation schema.

### Blocker B — Migration history does not reconcile
`docs/PRODUCTION-SCHEMA-RECOVERY-2026-10-10.md` records 26 applied Production migrations versus 21 repository migration files at the time of inspection, with version/name drift. `docs/MIGRATION-RECONCILIATION-INITIAL-INVENTORY-2026-10-09.md` explicitly says semantic parity is unverified and identifies multiple missing or ambiguous source migrations.

### Blocker C — Supabase config points to the original school
`supabase/config.toml` contains `project_id = "iigzzwyfxxtqbgjawyom"`. This project-specific value must not be copied into an installer that creates another school's environment. Do not edit the live configuration on main as part of this audit; produce a reviewed template-specific configuration once the source migration issue is resolved.

### Blocker D — Seed source is absent
No `supabase/seed.sql` was found at the checked path. Before enabling repeatable installation, define an approved seed file containing only synthetic/reference data and never real school users or documents.

### Blocker E — Production acceptance is not complete
`docs/PHASE-STATUS.md` describes production acceptance as in progress and notes unresolved security/backup checks. A successful frontend deploy workflow alone does not prove the application is healthy or secure.

## Safe remediation sequence

1. **Recover authoritative SQL**: locate a trusted backup or original SQL source for the foundation migration and all missing migrations. Preserve provenance and hashes. Do not generate SQL by guessing from the live catalog.
2. **Reconcile migrations**: map each of the 26 production history entries to its exact source and determine which repository files are equivalent only after comparing SQL and object behavior. Record unresolved entries as blockers.
3. **Create a disposable local database**: use a local Supabase/PostgreSQL test environment only. Never point `supabase db reset`, migration replay, or tests at the WBNS Production project.
4. **Replay from zero**: verify every migration runs in order and creates the complete schema, extensions, types, policies, grants, triggers, functions, views, and storage setup needed by the app.
5. **Run security tests**: test unauthenticated denial, department isolation, multiple department memberships, admin/principal exceptions, approval and assignment transitions, and service/Edge Function authorization.
6. **Make an installation template**: remove project-specific identifiers from template configuration, document all required environment variables using placeholders only, add synthetic seed data, and scan repository history/workflows for secrets and production data.
7. **Test a second-school sandbox**: only after gates 1–6 pass, use a new school-owned GitHub repository, new Supabase project, and new Drive folder/credentials. Do not reuse WBNS data or credentials.
8. **Pilot and review**: have an independent installer follow the guide, test backup/restore, document costs/quotas, and require school-owner approval before any production launch.

## Do not do
- Do not merge the draft installer PR as if it were production-ready.
- Do not run live Production migrations to recover schema.
- Do not reset or recreate the existing Supabase project.
- Do not copy the WBNS project ID, users, records, Drive folder, or secrets into another school.
- Do not claim a clean install or successful pilot until logs and acceptance tests prove it.