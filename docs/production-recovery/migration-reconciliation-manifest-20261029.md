# Production migration reconciliation manifest

Generated from read-only metadata on 2026-10-29. This is an evidence manifest, not SQL and not authorization to deploy.

## Counts

- Production Supabase migration history: 75 entries.
- SQL files in `main:supabase/migrations`: 49.
- Exact name matches after stripping the 14-digit timestamp prefix from filenames: 38.
- Production history entries without an exact filename-stem match: 37.
- The exact-match count is based on migration **names**, not matching version timestamps or proving that SQL content is equivalent.

## Confirmed blocker

`20261007200000_foundation_schema_rbac_rls.sql` is a placeholder that says the full SQL is maintained in the already-applied Production migration. It is not a clean-install baseline. A later migration references enum `document_status`, so a clean replay currently cannot be considered verified.

## Production history entries without exact filename-stem matches

The following names need a source-level reconciliation. They may correspond to renamed/aliased files, historical SQL absent from the repository, or changes folded into later files; do not infer which without inspecting trusted SQL and content.

- `harden_rls_and_indexes`
- `document_registration_rpc`
- `seed_school_registers_2026`
- `audit_trail_v1`
- `reporting_views_v1`
- `admin_department_management_v1`
- `harden_admin_department_rpc_execute_v2`
- `20261010130000_secure_public_workflow_rpc_wrappers_v1`
- `20261010150000_grant_director_document_update`
- `20261010170000_department_scoped_document_access_v1`
- `20261010180000_scope_workflow_assignment_and_status`
- `20261010190000_department_aware_document_registration_v1`
- `prevent_global_role_escalation`
- `grant_director_global_document_create`
- `production_multi_department_membership_v1`
- `production_department_scoped_roles_permissions_v1`
- `production_department_role_matrix_seed_fix`
- `production_department_scoped_read_rpc_fix`
- `production_department_scoped_write_rpc_guards`
- `production_department_scoped_access_final_correction`
- `production_department_scoped_approval_guards`
- `production_department_scoped_rls_and_file_guards`
- `production_close_remaining_department_rls_bypasses`
- `production_separate_document_edit_from_approve_assign`
- `production_guard_document_file_attachment`
- `production_require_department_membership_for_scoped_permissions`
- `production_require_explicit_active_department_membership`
- `secure_department_membership_management_rpc`
- `active_department_membership_approval_guard`
- `include_department_scoped_permissions_in_identity`
- `permanent_delete_incoming_drive_v1`
- `list_deleted_incoming_documents_v1`
- `fix_list_deleted_incoming_status_enum_cast`
- `notify_director_and_deputy_on_incoming_registration`
- `restrict_sender_directory_management_to_admin_and_registry`
- `allow_assignees_to_complete_active_assignments`
- `fix_assignment_status_enum_check_for_completion`

## Safe next steps

1. Obtain/verify trusted SQL for the Foundation and unmatched historical migrations.
2. Build a reviewed one-to-one manifest containing Production version, Production name, canonical repository file, content provenance, and validation result.
3. Replay in a fresh isolated Supabase-compatible local environment with stop-on-error.
4. Compare resulting catalog with Production and run RLS/RPC, UI, document/file, notification, and leave-workflow tests.
5. Only then prepare a separately reviewed release plan. Do not apply this manifest or a reconstructed baseline to Production.

## Safety

Read-only Production metadata was used. No Production schema, data, roles, secrets, settings, or deployed functions were changed. No paid resources were created.
