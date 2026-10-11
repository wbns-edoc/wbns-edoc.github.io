# Production Migration Reconciliation — WBNS e-Document

Status: release-blocking runbook. This document does not authorize production schema changes.

## Current verified state

- Supabase project: `iigzzwyfxxtqbgjawyom` (`wbns-edoc`).
- Production records foundation as version `20261007133831` / name `foundation_schema_rbac_rls`.
- Repository file `supabase/migrations/20261007200000_foundation_schema_rbac_rls.sql` is a placeholder, not a reproducible schema baseline.
- The Production catalog recovery fixture at `supabase/tests/fixtures/recovered-production-catalog.sql` is a test fixture, not a historical migration. It represents a later schema state and must not be copied into the foundation migration or applied to Production.
- Production does not currently contain `public.user_departments`, `public.user_department_roles`, or `public.department_role_permissions`. It does contain `public.documents.department_id` and `public.profiles.department_id`.
- Production has verified hotfix versions `20261011143751` and `20261011144307`.

## Known local/remote version divergence

| Local migration filename version | Production version | Production migration name |
| --- | --- | --- |
| `20261007200000_foundation_schema_rbac_rls.sql` | `20261007133831` | `foundation_schema_rbac_rls` |
| `20261010130000_secure_public_workflow_rpc_wrappers_v1.sql` | `20261010085023` | `20261010130000_secure_public_workflow_rpc_wrappers_v1` |
| `20261010150000_grant_director_document_update.sql` | `20261010085025` | `20261010150000_grant_director_document_update` |
| `20261010170000_department_scoped_document_access_v1.sql` | `20261010085028` | `20261010170000_department_scoped_document_access_v1` |
| `20261010180000_scope_workflow_assignment_and_status.sql` | `20261010085031` | `20261010180000_scope_workflow_assignment_and_status` |
| `20261010190000_department_aware_document_registration_v1.sql` | `20261010085034` | `20261010190000_department_aware_document_registration_v1` |

The local multi-department implementation also has ordering dependencies that differ from this historic Production sequence. Do not rename these files mechanically to remote versions: migration order affects whether referenced tables/functions exist when a migration executes.

## Mandatory recovery procedure

1. Freeze production feature deployment; keep the current live application and its verified hotfixes in place.
2. Capture a fresh, owner-authorized schema-only backup/export from the WBNS Supabase project. Keep it in a restricted location; never commit secrets, user rows, documents, tokens, or private file metadata.
3. Compare the fresh catalog with the recovered fixture and each migration's expected preconditions/postconditions. Mark every object as historical baseline, historical forward migration, or current production hotfix.
4. Reconstruct a reproducible clean-install baseline in a separate disposable Supabase/Postgres project. Do not overwrite the placeholder until the baseline can initialize an empty database and all remaining forward migrations run in order without duplicate-object or missing-dependency errors.
5. Design an explicit history reconciliation plan for the existing Production project. Rehearse it against a disposable copy of the current catalog. Do not run `db push`, `migration repair`, or a baseline/squash migration against Production until the exact commands, before/after versions, rollback limits, and catalog diff have been reviewed.
6. Run all database tests, RLS/authorization tests, file/workflow tests, and Excel user-import tests on the disposable environment. Include multi-department users, initial passwords, inactive users, and partial import failure.
7. Confirm no unintended schema/data changes, verify security advisors and global System Admin/director permissions, then schedule a controlled release. Back up first and verify the live site and sign-in after every production change.

## Release gate checklist

- [ ] Reproducible baseline builds from an empty database.
- [ ] Every local migration version reconciled with the intended migration history.
- [ ] Forward migrations replay cleanly from the baseline.
- [ ] Production history reconciliation rehearsed against a disposable catalog.
- [ ] Multi-department schema and per-department role/permission tests pass.
- [ ] Excel import end-to-end passes, including rollback/partial-failure handling.
- [ ] SECURITY DEFINER functions reviewed for caller identity, permission checks, search_path, and grants.
- [ ] Supabase Auth leaked-password protection reviewed/enabled if available on the project plan.
- [ ] All required CI workflows pass on the final PR head.
- [ ] Zero-baht operating-cost constraint rechecked.
- [ ] Production backup and post-deployment verification plan ready.

Until these gates pass, PR #12 must remain a draft and must not be merged to `main`. GitHub Pages production deployment is tied to `main`.
