# Production Migration Reconciliation — 2026-10-30

สถานะ: **BLOCKED — ห้ามใช้ Supabase CLI push/reset กับ Production จนกว่าจะ reconcile ประวัติ migration**

## Read-only inventory

- Production Supabase project: `wbns-edoc` (`iigzzwyfxxtqbgjawyom`), region Singapore
- Production migration history: **75 applied entries**
- Integration branch migration files: **65 SQL files**
- Matched by normalized migration name (strip timestamp prefix): **43 common**
- Production applied names without a corresponding repository file: **32**
- Repository migration names not present in Production history: **22**

The timestamp versions in Production and the timestamp prefixes in the repository are not aligned. Exact-version comparison therefore reports no direct timestamp matches; name comparison shows the following gaps. Do not infer that similarly named files are byte-for-byte equivalent.

## Production applied migrations missing from the repository

- `20261007134222` — harden_rls_and_indexes
- `20261007134728` — document_registration_rpc
- `20261007135044` — seed_school_registers_2026
- `20261007140118` — audit_trail_v1
- `20261007140759` — reporting_views_v1
- `20261008042634` — admin_department_management_v1
- `20261008053554` — harden_admin_department_rpc_execute_v2
- `20261011143751` — prevent_global_role_escalation
- `20261011144307` — grant_director_global_document_create
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
- `20261013001230` — include_department_scoped_permissions_in_identity
- `20261015005425` — permanent_delete_incoming_drive_v1
- `20261015005428` — list_deleted_incoming_documents_v1
- `20261015023421` — fix_list_deleted_incoming_status_enum_cast
- `20261016161349` — notify_director_and_deputy_on_incoming_registration
- `20261016162544` — restrict_sender_directory_management_to_admin_and_registry
- `20261017070421` — allow_assignees_to_complete_active_assignments
- `20261017070749` — fix_assignment_status_enum_check_for_completion

## Repository migration files not represented in Production history

- `20261007205500_harden_workflow_rpc.sql`
- `20261009013200_bootstrap_initial_system_admin_v1.sql`
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

## Known foundation blocker

The repository file `supabase/migrations/20261007200000_foundation_schema_rbac_rls.sql` is a placeholder rather than a replayable foundation migration. A local clean replay previously failed when `20261007205000_workflow_engine_v1.sql` referenced missing type `public.document_status`.

Production already has a schema-only export and a static audit, but that export is a current-state snapshot, not a substitute for the missing historical migration SQL. Replacing the placeholder with the current full schema dump would cause later historical migrations to replay over objects that already exist and is not a safe migration repair.

## Release safety rules

Until this reconciliation is complete:

1. Do not run `supabase db push`, `supabase db push --include-all`, `supabase db reset --linked`, or `supabase migration repair` against Production.
2. Do not rename or delete existing migration files merely to make the CLI appear aligned.
3. Continue testing new leave migrations in isolated CI fixtures; keep Production unchanged.
4. Recover the missing applied migration SQL or produce an explicitly versioned, independently verified baseline strategy before enabling automated deploy.
5. Deploy new migrations only through a controlled forward-only path after test replay, RLS/authorization checks, rollback plan, and school policy approval.

## Next engineering action

Build a verified mapping from each Production version/name to its repository file or recovery source, then reconcile the missing applied migrations. The current list above is a read-only snapshot as of 2026-10-30 and must be refreshed before any migration operation.


## Historical evidence and candidate mappings

A previous read-only checkpoint is preserved in:

- [2026-10-29 migration reconciliation](./production-recovery/migration-reconciliation-20261029.md)
- [2026-10-29 Production catalog checkpoint](./production-recovery/production-catalog-checkpoint-20261029.md)

The older checkpoint compared `main` (49 migration files at that time). The current integration branch contains 65 files because leave-module migrations have since been added. The current counts above are calculated against the integration branch, not the older main snapshot.

The following are candidates only and must be checked by comparing full SQL and catalog effects before mapping:

| Production version/name | Candidate repository file | Evidence status |
|---|---|---|
| `20261010085023` — secure public workflow RPC wrappers | `20261010130000_secure_public_workflow_rpc_wrappers_v1.sql` | Filename stem aligns with recorded name, but applied version differs |
| `20261010085025` — grant Director document update | `20261010150000_grant_director_document_update.sql` | Filename stem aligns with recorded name, but applied version differs |
| `20261010085028` — department-scoped document access | `20261010170000_department_scoped_document_access_v1.sql` | Filename stem aligns with recorded name, but applied version differs |
| `20261010085031` — scope workflow assignment and status | `20261010180000_scope_workflow_assignment_and_status.sql` | Filename stem aligns with recorded name, but applied version differs |
| `20261010085034` — department-aware document registration | `20261010190000_department_aware_document_registration_v1.sql` | Filename stem aligns with recorded name, but applied version differs |
| `20261015005425` — permanent delete incoming Drive | `permanent_delete_incoming_drive.sql` | Semantic similarity only; exact SQL not proven |
| `20261015005428` — list deleted incoming documents | `list_deleted_incoming_documents.sql` | Semantic similarity only; exact SQL not proven |
| `20261016161349` — notify Director and Deputy on incoming registration | `20261016233000_notify_leadership_on_incoming_registration.sql` | Semantic similarity only; exact SQL not proven |
| `20261016162544` — restrict sender directory management | `20261016234500_restrict_sender_directory_management.sql` | Semantic similarity only; exact SQL not proven |

A filename or semantic match is not enough to mark a migration reconciled. The SQL must be compared against a trusted original or an archived commit and its resulting schema/security effects must match Production.
