# Production migration reconciliation — 2026-10-29

## Purpose and safety

This document records a read-only comparison between the migration history returned by Supabase for Production project `iigzzwyfxxtqbgjawyom` and SQL files in `main:supabase/migrations`.

**This is an evidence manifest, not a migration, and must not be applied to a database.** No Production changes were made while collecting this information.

## Counts

- Production history entries: 75
- SQL migration files on `main`: 49
- Exact name matches after stripping each repository filename's 14-digit timestamp prefix: 38
- History names without an exact filename-stem match: 37

A name mismatch does not prove SQL is missing: files may have been renamed, squashed, or combined. Each relationship below remains a hypothesis until contents are compared to trusted originals and catalog effects.

## Confirmed blocker

`supabase/migrations/20261007200000_foundation_schema_rbac_rls.sql` is a 285-byte placeholder. It says the full SQL is maintained in the migration applied to Production. It does not recreate the foundation schema and cannot be used for clean replay. A later workflow migration failed in isolated startup with `type "document_status" does not exist`, consistent with this gap.

The tracked fixture `supabase/tests/fixtures/recovered-production-catalog.sql` is explicitly a generated catalog snapshot for isolated tests, includes test-only patches, and sets `check_function_bodies = off`. It is not a substitute for canonical migration history.

## History entries with no exact filename-stem match

| Production version | Recorded migration name | Possible repository candidate | Status |
|---|---|---|---|
| 20261007134222 | harden_rls_and_indexes | — | No exact name; source not reconciled |
| 20261007134728 | document_registration_rpc | — | No exact name; source not reconciled |
| 20261007135044 | seed_school_registers_2026 | — | No exact name; source not reconciled |
| 20261007140118 | audit_trail_v1 | — | No exact name; source not reconciled |
| 20261007140759 | reporting_views_v1 | — | No exact name; source not reconciled |
| 20261008042634 | admin_department_management_v1 | — | No exact name; source not reconciled |
| 20261008053554 | harden_admin_department_rpc_execute_v2 | — | No exact name; source not reconciled |
| 20261010085023 | 20261010130000_secure_public_workflow_rpc_wrappers_v1 | 20261010130000_secure_public_workflow_rpc_wrappers_v1.sql | Candidate by recorded name; version/name anomaly, verify contents |
| 20261010085025 | 20261010150000_grant_director_document_update | 20261010150000_grant_director_document_update.sql | Candidate by recorded name; version/name anomaly, verify contents |
| 20261010085028 | 20261010170000_department_scoped_document_access_v1 | 20261010170000_department_scoped_document_access_v1.sql | Candidate by recorded name; version/name anomaly, verify contents |
| 20261010085031 | 20261010180000_scope_workflow_assignment_and_status | 20261010180000_scope_workflow_assignment_and_status.sql | Candidate by recorded name; version/name anomaly, verify contents |
| 20261010085034 | 20261010190000_department_aware_document_registration_v1 | 20261010190000_department_aware_document_registration_v1.sql | Candidate by recorded name; version/name anomaly, verify contents |
| 20261011143751 | prevent_global_role_escalation | — | No exact name; source not reconciled |
| 20261011144307 | grant_director_global_document_create | — | No exact name; source not reconciled |
| 20261012011549 | production_multi_department_membership_v1 | — | No exact name; source not reconciled |
| 20261012011559 | production_department_scoped_roles_permissions_v1 | — | No exact name; source not reconciled |
| 20261012011633 | production_department_role_matrix_seed_fix | — | No exact name; source not reconciled |
| 20261012011639 | production_department_scoped_read_rpc_fix | — | No exact name; source not reconciled |
| 20261012011646 | production_department_scoped_write_rpc_guards | — | No exact name; source not reconciled |
| 20261012011653 | production_department_scoped_access_final_correction | — | No exact name; source not reconciled |
| 20261012011659 | production_department_scoped_approval_guards | — | No exact name; source not reconciled |
| 20261012011708 | production_department_scoped_rls_and_file_guards | — | No exact name; source not reconciled |
| 20261012011719 | production_close_remaining_department_rls_bypasses | — | No exact name; source not reconciled |
| 20261012011729 | production_separate_document_edit_from_approve_assign | — | No exact name; source not reconciled |
| 20261012011736 | production_guard_document_file_attachment | — | No exact name; source not reconciled |
| 20261012011746 | production_require_department_membership_for_scoped_permissions | — | No exact name; source not reconciled |
| 20261012011831 | production_require_explicit_active_department_membership | — | No exact name; source not reconciled |
| 20261012024902 | secure_department_membership_management_rpc | — | No exact name; source not reconciled |
| 20261012024916 | active_department_membership_approval_guard | — | No exact name; source not reconciled |
| 20261013001230 | include_department_scoped_permissions_in_identity | — | No exact name; source not reconciled |
| 20261015005425 | permanent_delete_incoming_drive_v1 | permanent_delete_incoming_drive.sql | Candidate by semantic similarity; verify exact SQL |
| 20261015005428 | list_deleted_incoming_documents_v1 | list_deleted_incoming_documents.sql | Candidate by semantic similarity; verify exact SQL |
| 20261015023421 | fix_list_deleted_incoming_status_enum_cast | — | No exact name; source not reconciled |
| 20261016161349 | notify_director_and_deputy_on_incoming_registration | 20261016233000_notify_leadership_on_incoming_registration.sql | Candidate by semantic similarity; verify exact SQL |
| 20261016162544 | restrict_sender_directory_management_to_admin_and_registry | 20261016234500_restrict_sender_directory_management.sql | Candidate by semantic similarity; verify exact SQL |
| 20261017070421 | allow_assignees_to_complete_active_assignments | — | No exact name; source not reconciled |
| 20261017070749 | fix_assignment_status_enum_check_for_completion | — | No exact name; source not reconciled |

## Exact filename-stem matches

The following 38 Production migration names have a matching repository filename stem after removing the file's 14-digit timestamp prefix:

- foundation_schema_rbac_rls
- workflow_engine_v1
- notification_deadline_engine_v1
- move_pg_trgm_to_extensions
- audit_trail_hardening_v2
- workflow_safety_hardening_v2
- workflow_status_transition_guard_v1
- workflow_assignment_transition_guard_v1
- reporting_views_security_invoker_v1
- get_my_permissions_v1
- outgoing_sent_archive_transition_v1
- admin_role_management_v1
- document_file_versioning_v1
- revoke_anon_security_definer_rpcs_v1
- admin_profile_department_management_v1
- revoke_anon_admin_department_rpc_v1
- enforce_status_transition_permissions_v1
- protect_dedicated_workflow_rpc_transitions_v1
- validate_approval_recipient_permission_v1
- guard_last_active_system_admin_role_removal_v1
- admin_global_role_management_v1
- registry_officer_delete_incoming_documents_v1
- grant_director_document_assignment
- deputy_director_assignment_instructions
- list_document_assignees_scoped_rpc
- expand_document_assignee_lookup_for_approvals
- expand_assignees_to_child_departments
- assign_document_to_multiple_staff
- allow_document_readers_to_view_assignees
- document_assignment_reports_v1
- allow_assignees_to_read_assigned_documents
- allow_assignees_to_start_assigned_documents
- sync_assignment_when_assignee_completes_document
- reconcile_assignments_for_completed_documents
- add_admin_system_settings
- add_public_school_name_reader
- support_be_incoming_register_numbers
- include_registration_date_in_deleted_incoming_list

An exact name match alone does not prove that the file's content is identical to the SQL that was applied in Production.

## Required next steps before release

1. Recover canonical Foundation SQL and the original SQL for each unmatched history entry from a trusted source (known-good backup, exported migration artifact, or source commit).
2. Record each mapping as **exact**, **renamed-equivalent with content proof**, **combined/squashed with explicit explanation**, or **unresolved**. Do not treat semantic similarity alone as proof.
3. Provision a disposable isolated Supabase local environment, then replay the reconstructed migration chain with `ON_ERROR_STOP=1`. Do not run this in the linked Production directory.
4. Verify schema objects, enum types, functions, grants, RLS policies, triggers, and extensions against a fresh read-only Production catalog export.
5. Run permission/RPC and UI-to-database tests, including incoming registration, assignments, attachments, notifications, and staff leave.
6. Create and verify a backup and rollback plan; obtain explicit approval before any Production deployment.

## Release gate

**NOT READY FOR CLEAN REPLAY / PRODUCTION RELEASE.** The source alignment and Foundation baseline remain unresolved. No Production changes were made.
