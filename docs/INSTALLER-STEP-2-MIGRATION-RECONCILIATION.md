# Installer Step 2 — Migration Reconciliation

Date: 2026-10-17  
Scope: documentation and read-only repository inspection only. No Production changes.

## Counts confirmed

- Live Supabase migration-history rows supplied by the user: **75**.
- SQL files in `supabase/migrations/` on repository `main`: **49**.
- Live migration names that match a repository filename after stripping the repository timestamp prefix: **38**.
- Live names without an exact filename match: **37**.
- These name-match counts are only a first-pass comparison, not proof of missing SQL: some live names may be represented by renamed/combined repository migrations, and the production history uses different timestamps from many repository filenames.

## Repository findings

1. `20261007200000_foundation_schema_rbac_rls.sql` is only a 285-byte placeholder. It says the full SQL is maintained in the migration applied to the WBNS Supabase project. It cannot create the original schema from an empty database.
2. `supabase/tests/fixtures/recovered-production-catalog.sql` is explicitly marked as a generated, read-only catalog snapshot for isolated tests, not a historical migration and not intended for Production deployment. It contains test-only changes and an incomplete subset of the live catalog. It must not be copied wholesale as an installer baseline.
3. A previous read-only inventory of the live catalog found 27 public base tables and 2 public views. The test fixture omits several live tables, so a fixture pass alone does not establish that a new school can install the complete application.
4. Production history contains migration names that are absent from the repository under the same filename, including initial hardening, registration RPC and register seeding, department-scoped access/permissions, multi-department membership, and additional assignment/deletion fixes.
5. Some production names plausibly correspond to repository files with a different name, e.g. the live names with embedded original timestamps and the repository files with standard timestamp prefixes. This needs source/diff inspection; do not assume equivalence from similar names alone.
6. Repository migration files use timestamps that do not match the live migration-history versions for many entries. The installer must not rely on the current repo chain being a faithful replay of the live project.

## First-pass name reconciliation

### Live names with an exact repository filename match (38)

```text
foundation_schema_rbac_rls
workflow_engine_v1
notification_deadline_engine_v1
move_pg_trgm_to_extensions
audit_trail_hardening_v2
workflow_safety_hardening_v2
workflow_status_transition_guard_v1
workflow_assignment_transition_guard_v1
reporting_views_security_invoker_v1
get_my_permissions_v1
outgoing_sent_archive_transition_v1
admin_role_management_v1
document_file_versioning_v1
revoke_anon_security_definer_rpcs_v1
admin_profile_department_management_v1
revoke_anon_admin_department_rpc_v1
enforce_status_transition_permissions_v1
protect_dedicated_workflow_rpc_transitions_v1
validate_approval_recipient_permission_v1
guard_last_active_system_admin_role_removal_v1
admin_global_role_management_v1
registry_officer_delete_incoming_documents_v1
grant_director_document_assignment
deputy_director_assignment_instructions
list_document_assignees_scoped_rpc
expand_document_assignee_lookup_for_approvals
expand_assignees_to_child_departments
assign_document_to_multiple_staff
allow_document_readers_to_view_assignees
document_assignment_reports_v1
allow_assignees_to_read_assigned_documents
allow_assignees_to_start_assigned_documents
sync_assignment_when_assignee_completes_document
reconcile_assignments_for_completed_documents
add_admin_system_settings
add_public_school_name_reader
support_be_incoming_register_numbers
include_registration_date_in_deleted_incoming_list
```

### Live names without an exact repository filename match (37)

```text
harden_rls_and_indexes
document_registration_rpc
seed_school_registers_2026
audit_trail_v1
reporting_views_v1
admin_department_management_v1
harden_admin_department_rpc_execute_v2
20261010130000_secure_public_workflow_rpc_wrappers_v1
20261010150000_grant_director_document_update
20261010170000_department_scoped_document_access_v1
20261010180000_scope_workflow_assignment_and_status
20261010190000_department_aware_document_registration_v1
prevent_global_role_escalation
grant_director_global_document_create
production_multi_department_membership_v1
production_department_scoped_roles_permissions_v1
production_department_role_matrix_seed_fix
production_department_scoped_read_rpc_fix
production_department_scoped_write_rpc_guards
production_department_scoped_access_final_correction
production_department_scoped_approval_guards
production_department_scoped_rls_and_file_guards
production_close_remaining_department_rls_bypasses
production_separate_document_edit_from_approve_assign
production_guard_document_file_attachment
production_require_department_membership_for_scoped_permissions
production_require_explicit_active_department_membership
secure_department_membership_management_rpc
active_department_membership_approval_guard
include_department_scoped_permissions_in_identity
permanent_delete_incoming_documents_v1
list_deleted_incoming_documents_v1
fix_list_deleted_incoming_status_enum_cast
notify_director_and_deputy_on_incoming_registration
restrict_sender_directory_management_to_admin_and_registry
allow_assignees_to_complete_active_assignments
fix_assignment_status_enum_check_for_completion
```

## Safe conclusion

Do not run `supabase db reset`, do not replay these migrations against the WBNS Production project, and do not manufacture a replacement foundation migration from the test fixture. A full installable baseline requires authoritative live catalog definitions and careful review of the full migration history.

## Next required evidence

The migration history is now available. The next safe step is to recover authoritative definitions from the live catalog, read-only, in exportable batches: enum types, tables/columns/constraints, indexes, functions and their security settings, triggers, views, RLS policies, grants, and extensions. Never export row data or secrets. If using the Supabase SQL Editor, run only metadata/catalog queries and export results as CSV. If the query errors, share the exact error instead of changing permissions.

## Acceptance criteria before authoring installer SQL

- Inspect the full source of the 37 unmatched migration names and determine whether equivalent changes exist under different repository filenames.
- Recover all required schemas, enums/types, tables, constraints, indexes, functions, triggers, views, RLS policies, grants, and extensions from authoritative live catalog definitions.
- Review privileged functions and RLS behavior before including them.
- Validate on a disposable, newly created Supabase project/database—not on WBNS Production.
- Verify a clean installation path and test authentication, department-scoped access, executive permissions, document workflows, and Drive integration with test credentials.
- Keep project IDs, OAuth details, service-role keys, and bridge secrets out of the distributable template.

## Status

**Step 2: migration-history inventory received; detailed reconciliation still in progress.** No Production changes have been made.
