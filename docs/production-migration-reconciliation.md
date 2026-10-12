# Production Migration Reconciliation — WBNS e-Document

Status: release-blocking runbook. This document does not authorize production schema changes.

## Current verified state

- Supabase project: `iigzzwyfxxtqbgjawyom` (`wbns-edoc`).
- Production records foundation as version `20261007133831` / name `foundation_schema_rbac_rls`.
- Repository file `supabase/migrations/20261007200000_foundation_schema_rbac_rls.sql` is a placeholder, not a reproducible schema baseline.
- The Production catalog recovery fixture at `supabase/tests/fixtures/recovered-production-catalog.sql` is a test fixture, not a historical migration. It represents a later schema state and must not be copied into the foundation migration or applied to Production.
- Production now contains `public.user_departments`, `public.user_department_roles`, and `public.department_role_permissions`; the permission matrix has 168 rows. The existing profile has no primary department, and no memberships or scoped roles have been fabricated.
- Production has verified hotfix versions `20261011143751` and `20261011144307`, plus direct rollout migrations from `20261012011549` through `20261012024916` (see the rollout section below).

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


## Production rollout — 2026-10-12 (verified)

The following changes were applied directly to the WBNS Supabase project. These production history entries do not yet make the original migration history reproducible from a clean install:

| Production version | Recorded migration name |
| --- | --- |
| `20261012011549` | `production_multi_department_membership_v1` |
| `20261012011559` | `production_department_scoped_roles_permissions_v1` |
| `20261012011633` | `production_department_role_matrix_seed_fix` |
| `20261012011639` | `production_department_scoped_read_rpc_fix` |
| `20261012011646` | `production_department_scoped_write_rpc_guards` |
| `20261012011653` | `production_department_scoped_access_final_correction` |
| `20261012011659` | `production_department_scoped_approval_guards` |
| `20261012011708` | `production_department_scoped_rls_and_file_guards` |
| `20261012011719` | `production_close_remaining_department_rls_bypasses` |
| `20261012011729` | `production_separate_document_edit_from_approve_assign` |
| `20261012011736` | `production_guard_document_file_attachment` |
| `20261012011746` | `production_require_department_membership_for_scoped_permissions` |
| `20261012011831` | `production_require_explicit_active_department_membership` |
| `20261012024902` | `secure_department_membership_management_rpc` |
| `20261012024916` | `active_department_membership_approval_guard` |

Read-only verification after these changes:
- Membership, scoped-role, and permission tables exist; permission matrix count is 168.
- Counts are currently 0 membership rows, 0 scoped-role rows, 1 profile, and 0 profiles with a primary department. This is intentionally left unmapped pending confirmation of the real user's department membership.
- Public membership RPCs exist as `SECURITY INVOKER` wrappers, authenticated execution is granted, and anonymous execution is revoked. Their privileged implementations are in the `private` schema and perform permission checks.
- `private.create_approval` checks the target approver's current active membership in the document's department and the department-scoped approval permission.
- Security advisor still reports the three RLS-enabled membership/permission tables without direct table policies, and pre-existing exposed `SECURITY DEFINER` functions elsewhere. These require continued review before a full release.

The repository migration `20261011230000_manage_department_membership_rpc.sql` and its static regression test were updated to reflect the hardened wrapper/implementation split. The new production entries above still need deliberate reconciliation with the repository's migration ordering; do not use `db push` to force-align them.

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
