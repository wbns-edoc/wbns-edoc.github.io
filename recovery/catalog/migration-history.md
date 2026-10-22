# Production migration history vs GitHub main

Captured 2026-10-15 from connected Supabase Production project and GitHub main.

- Production migration history entries: 55
- SQL files under `supabase/migrations` on main: 31
- The version strings/names do not align 1:1; do not treat this as a safe missing-migration list.

## Production migration history

- 20261007133831 — foundation_schema_rbac_rls
- 20261007134222 — harden_rls_and_indexes
- 20261007134728 — document_registration_rpc
- 20261007135044 — seed_school_registers_2026
- 20261007135356 — workflow_engine_v1
- 20261007135756 — notification_deadline_engine_v1
- 20261007135857 — move_pg_trgm_to_extensions
- 20261007140118 — audit_trail_v1
- 20261007140240 — audit_trail_hardening_v2
- 20261007140759 — reporting_views_v1
- 20261007163008 — workflow_safety_hardening_v2
- 20261007163111 — workflow_status_transition_guard_v1
- 20261007163119 — workflow_assignment_transition_guard_v1
- 20261007163251 — reporting_views_security_invoker_v1
- 20261007165305 — get_my_permissions_v1
- 20261008015934 — outgoing_sent_archive_transition_v1
- 20261008031530 — admin_role_management_v1
- 20261008034236 — document_file_versioning_v1
- 20261008034444 — revoke_anon_security_definer_rpcs_v1
- 20261008042634 — admin_department_management_v1
- 20261008053522 — admin_profile_department_management_v1
- 20261008053554 — harden_admin_department_rpc_execute_v2
- 20261008053608 — revoke_anon_admin_department_rpc_v1
- 20261009005230 — enforce_status_transition_permissions_v1
- 20261009005407 — protect_dedicated_workflow_rpc_transitions_v1
- 20261009005459 — validate_approval_recipient_permission_v1
- 20261010085023 — 20261010130000_secure_public_workflow_rpc_wrappers_v1
- 20261010085025 — 20261010150000_grant_director_document_update
- 20261010085028 — 20261010170000_department_scoped_document_access_v1
- 20261010085031 — 20261010180000_scope_workflow_assignment_and_status
- 20261010085034 — 20261010190000_department_aware_document_registration_v1
- 20261010090253 — guard_last_active_system_admin_role_removal_v1
- 20261011143751 — prevent_global_role_escalation
- 20261011144307 — grant_director_global_document_create
- 20261012011549 — production_multi_department_membership_v1
- 20261012011559 — production_department_scoped_roles_permissions_v1
- 20261012011633 — production_department_role_matrix_seed_fix
- 20261012011639 — production_department_scoped_read_rpc_fix
- 20261012011646 — production_department_scoped_write_rpc_guards
- 20261012011653 — production_department_scoped_access_final_correction
- 20261012011659 — production_department_scoped_approval_guards
- 20261012011708 — production_department_scoped_rls_and_file_guards
- 20261012011719 — production_close_remaining_department_rls_bypasses
- 20261012011729 — production_separate_document_edit_from_approve_assign
- 20261012011736 — production_guard_document_file_attachment
- 20261012011746 — production_require_department_membership_for_scoped_permissions
- 20261012011831 — production_require_explicit_active_department_membership
- 20261012024902 — secure_department_membership_management_rpc
- 20261012024916 — active_department_membership_approval_guard
- 20261013001230 — include_department_scoped_permissions_in_identity
- 20261014162126 — admin_global_role_management_v1
- 20261014202558 — registry_officer_delete_incoming_documents_v1
- 20261015005425 — permanent_delete_incoming_drive_v1
- 20261015005428 — list_deleted_incoming_documents_v1
- 20261015023421 — fix_list_deleted_incoming_status_enum_cast

## Repository migration files on main

- `20261007200000_foundation_schema_rbac_rls.sql`
- `20261007205000_workflow_engine_v1.sql`
- `20261007205500_harden_workflow_rpc.sql`
- `20261007210000_notification_deadline_engine_v1.sql`
- `20261007210500_move_pg_trgm_to_extensions.sql`
- `20261007211000_audit_trail_hardening_v2.sql`
- `20261007212000_workflow_safety_hardening_v2.sql`
- `20261007213000_workflow_status_transition_guard_v1.sql`
- `20261007213500_workflow_assignment_transition_guard_v1.sql`
- `20261007214000_reporting_views_security_invoker_v1.sql`
- `20261007214500_get_my_permissions_v1.sql`
- `20261007215000_outgoing_sent_archive_transition_v1.sql`
- `20261007215500_admin_role_management_v1.sql`
- `20261008090000_document_file_versioning_v1.sql`
- `20261008091000_revoke_anon_security_definer_rpcs_v1.sql`
- `20261008120000_admin_profile_department_management_v1.sql`
- `20261008120500_revoke_anon_admin_department_rpc_v1.sql`
- `20261009005230_enforce_status_transition_permissions_v1.sql`
- `20261009005407_protect_dedicated_workflow_rpc_transitions_v1.sql`
- `20261009005459_validate_approval_recipient_permission_v1.sql`
- `20261009013200_bootstrap_initial_system_admin_v1.sql`
- `20261010130000_secure_public_workflow_rpc_wrappers_v1.sql`
- `20261010150000_grant_director_document_update.sql`
- `20261010170000_department_scoped_document_access_v1.sql`
- `20261010180000_scope_workflow_assignment_and_status.sql`
- `20261010190000_department_aware_document_registration_v1.sql`
- `20261010200000_guard_last_active_system_admin_role_removal_v1.sql`
- `20261014162126_admin_global_role_management_v1.sql`
- `20261015120000_registry_officer_delete_incoming_documents_v1.sql`
- `20261015130000_permanent_delete_incoming_drive.sql`
- `20261015131000_list_deleted_incoming_documents.sql`

## Important finding

`20261007200000_foundation_schema_rbac_rls.sql` on main is a 285-byte placeholder, not the full SQL that originally created the foundation schema. A catalog-derived snapshot has been captured separately under `recovery/catalog/`; it is not a substitute for a validated `pg_dump` and must not be applied directly to Production.
