# Production Migration Reconciliation — 2026-10-30

สถานะ: **BLOCKED — ห้ามใช้ Supabase CLI push/reset กับ Production จนกว่าจะยืนยัน mapping และ Foundation baseline**

## Read-only inventory

- Production Supabase project: `wbns-edoc` (`iigzzwyfxxtqbgjawyom`), Singapore
- Production migration history: **75 applied entries**
- Integration branch migration files: **83 SQL files**
- Exact normalized filename-stem matches: **46**
- Production history names without exact filename-stem match: **29**
- Repository migration names not represented by exact Production name: **37**

A name mismatch does not prove SQL is missing. Some migrations were applied directly to Production under a timestamp/name different from the tracked source file. Every candidate still needs content and catalog-effect verification.

## Recovered historical authorization source

Recovered **18 migration source files** and **7 regression tests** from the historical branch `feature/department-scoped-permissions-2026-10-11`, commit `ec09650a581a611cecef7d4c2d84569fd410f62f`, associated with Draft PR #12. PR #12's description states that the department-scoped changes were applied directly to Production on 2026-10-12.

The files are now restored to the Integration branch. Three have exact normalized name matches; fifteen are semantic candidates for Production history names with a `production_` prefix or different wording. This restores source evidence but does **not** prove byte-for-byte identity with SQL applied through the Supabase SQL editor.

Recovered regression tests cover department membership management, explicit active membership, approval authorization denials, role escalation, identity permissions, RLS/file guards, and final department access corrections.

## Production applied migrations without exact filename-stem matches

- `20261007134222` — harden_rls_and_indexes
- `20261007134728` — document_registration_rpc
- `20261007135044` — seed_school_registers_2026
- `20261007140118` — audit_trail_v1
- `20261007140759` — reporting_views_v1
- `20261008042634` — admin_department_management_v1
- `20261008053554` — harden_admin_department_rpc_execute_v2
- `20261012011549` — production_multi_department_membership_v1
- `20261012011559` — production_department_scoped_roles_permissions_v1
- `20261012011633` — production_department_role_matrix_seed_fix
- `20261012011639` — production_department_scoped_read_rpc_fix
- `20261012011646` — production_department_scoped_write_rpc_guards
- `20261012011653` — production_department_scoped_access_final_correction
- `20261012011659` — production_department_scoped_approval_guards
- `20261012011708` — production_department_scoped_rls_and_file_guards
- `20261012011719` — production_close_remaining_department_rls_bypasses
- `20261012011729` — production_separate_document_edit_from_approve_assign
- `20261012011736` — production_guard_document_file_attachment
- `20261012011746` — production_require_department_membership_for_scoped_permissions
- `20261012011831` — production_require_explicit_active_department_membership
- `20261012024902` — secure_department_membership_management_rpc
- `20261012024916` — active_department_membership_approval_guard
- `20261015005425` — permanent_delete_incoming_drive_v1
- `20261015005428` — list_deleted_incoming_documents_v1
- `20261015023421` — fix_list_deleted_incoming_status_enum_cast
- `20261016161349` — notify_director_and_deputy_on_incoming_registration
- `20261016162544` — restrict_sender_directory_management_to_admin_and_registry
- `20261017070421` — allow_assignees_to_complete_active_assignments
- `20261017070749` — fix_assignment_status_enum_check_for_completion

## Repository migration files not represented by an exact Production history name

- `20261007205500_harden_workflow_rpc.sql`
- `20261009013200_bootstrap_initial_system_admin_v1.sql`
- `20261010160000_multi_department_membership_v1.sql`
- `20261011100000_department_scoped_roles_permissions_v1.sql`
- `20261011120000_department_role_matrix_seed_fix.sql`
- `20261011121000_department_scoped_read_rpc_fix.sql`
- `20261011140000_department_scoped_write_rpc_guards.sql`
- `20261011150000_department_scoped_access_final_correction.sql`
- `20261011160000_department_scoped_approval_guards.sql`
- `20261011170000_department_scoped_rls_and_file_guards.sql`
- `20261011180000_close_remaining_department_rls_bypasses.sql`
- `20261011190000_separate_document_edit_from_approve_assign.sql`
- `20261011200000_guard_document_file_attachment.sql`
- `20261011210000_require_department_membership_for_scoped_permissions.sql`
- `20261011230000_manage_department_membership_rpc.sql`
- `20261011231000_require_active_membership_for_approvers.sql`
- `20261011232000_require_explicit_active_department_membership.sql`
- `20261015130000_permanent_delete_incoming_drive.sql`
- `20261015131000_list_deleted_incoming_documents.sql`
- `20261016233000_notify_leadership_on_incoming_registration.sql`
- `20261016234500_restrict_sender_directory_management.sql`
- `20261020230000_staff_leave_workflow_foundation_draft.sql`
- `20261021100000_staff_leave_secure_schema_draft.sql`
- `20261021120000_staff_leave_create_draft_rpc_draft.sql`
- `20261021140000_staff_leave_cancel_rpc_draft.sql`
- `20261021160000_staff_leave_submit_rpc_draft.sql`
- `20261021180000_staff_leave_decide_rpc_draft.sql`
- `20261022100000_staff_leave_two_stage_approval_draft.sql`
- `20261022130000_school_responsibility_assignments_draft.sql`
- `20261022210000_staff_leave_submit_two_stage_route_draft.sql`
- `20261023100000_staff_leave_immutable_route_snapshot_draft.sql`
- `20261023120000_staff_leave_responsibility_route_bridge_draft.sql`
- `20261023130000_staff_leave_in_app_notification_delivery_draft.sql`
- `20261023140000_staff_leave_shared_policy_calculation_gate_draft.sql`
- `20261023150000_staff_leave_over_limit_notifications_draft.sql`
- `20261023160000_staff_leave_approver_dashboard_summary_draft.sql`
- `20261023170000_staff_leave_direct_vice_absence_evidence_draft.sql`

## Candidate mapping for restored department-scoped migrations

| Production history name | Restored repository file | Status |
|---|---|---|
| `production_multi_department_membership_v1` | `20261010160000_multi_department_membership_v1.sql` | Semantic candidate |
| `production_department_scoped_roles_permissions_v1` | `20261011100000_department_scoped_roles_permissions_v1.sql` | Semantic candidate |
| `production_department_role_matrix_seed_fix` | `20261011120000_department_role_matrix_seed_fix.sql` | Semantic candidate |
| `production_department_scoped_read_rpc_fix` | `20261011121000_department_scoped_read_rpc_fix.sql` | Semantic candidate |
| `production_department_scoped_write_rpc_guards` | `20261011140000_department_scoped_write_rpc_guards.sql` | Semantic candidate |
| `prevent_global_role_escalation` | `20261011143751_prevent_global_role_escalation.sql` | Exact name; applied timestamp still differs |
| `grant_director_global_document_create` | `20261011144307_grant_director_global_document_create.sql` | Exact name; applied timestamp still differs |
| `production_department_scoped_access_final_correction` | `20261011150000_department_scoped_access_final_correction.sql` | Semantic candidate |
| `production_department_scoped_approval_guards` | `20261011160000_department_scoped_approval_guards.sql` | Semantic candidate |
| `production_department_scoped_rls_and_file_guards` | `20261011170000_department_scoped_rls_and_file_guards.sql` | Semantic candidate |
| `production_close_remaining_department_rls_bypasses` | `20261011180000_close_remaining_department_rls_bypasses.sql` | Semantic candidate |
| `production_separate_document_edit_from_approve_assign` | `20261011190000_separate_document_edit_from_approve_assign.sql` | Semantic candidate |
| `production_guard_document_file_attachment` | `20261011200000_guard_document_file_attachment.sql` | Semantic candidate |
| `production_require_department_membership_for_scoped_permissions` | `20261011210000_require_department_membership_for_scoped_permissions.sql` | Semantic candidate |
| `secure_department_membership_management_rpc` | `20261011230000_manage_department_membership_rpc.sql` | Semantic candidate |
| `active_department_membership_approval_guard` | `20261011231000_require_active_membership_for_approvers.sql` | Semantic candidate |
| `production_require_explicit_active_department_membership` | `20261011232000_require_explicit_active_department_membership.sql` | Semantic candidate |
| `include_department_scoped_permissions_in_identity` | `20261013001230_include_department_scoped_permissions_in_identity.sql` | Exact name and version |

Other semantic candidates from current source include:
- `permanent_delete_incoming_drive_v1` → `20261015130000_permanent_delete_incoming_drive.sql`
- `list_deleted_incoming_documents_v1` → `20261015131000_list_deleted_incoming_documents.sql`
- `notify_director_and_deputy_on_incoming_registration` → `20261016233000_notify_leadership_on_incoming_registration.sql`
- `restrict_sender_directory_management_to_admin_and_registry` → `20261016234500_restrict_sender_directory_management.sql`

These remain candidates until exact SQL comparison or trusted deployment artifacts establish equivalence.

## Known Foundation blocker

The repository file `supabase/migrations/20261007200000_foundation_schema_rbac_rls.sql` is a placeholder, not a replayable foundation migration. A previous local clean replay failed when `20261007205000_workflow_engine_v1.sql` referenced missing type `public.document_status`.

Production has a schema-only export and a static catalog audit. A current-state schema dump is not the historical Foundation SQL and must not be substituted into the beginning of the migration chain without a separately designed baseline strategy.

Historical read-only reports:
- [2026-10-29 migration reconciliation](./production-recovery/migration-reconciliation-20261029.md)
- [2026-10-29 Production catalog checkpoint](./production-recovery/production-catalog-checkpoint-20261029.md)

## Release safety rules

1. Do not run `supabase db push`, `supabase db push --include-all`, `supabase db reset --linked`, or `supabase migration repair` against Production.
2. Do not rename migration files to force the CLI to consider them applied.
3. Continue isolated CI replay using the recovered catalog fixture, and do not treat that fixture as a production migration baseline.
4. Recover the remaining unmatched source SQL or document a proven combined/squashed mapping with exact catalog effects.
5. Reconstruct and verify the Foundation baseline in a disposable local Supabase environment.
6. Only then prepare a controlled forward-only Production migration plan, backup/rollback plan, and final release review.

## Next engineering action

The restored authorization migrations and CI coverage must pass on the current Integration head. Then reconcile the remaining unmatched Production migrations and recover the original Foundation source. The migration inventory above is read-only and must be refreshed immediately before any future migration operation.
