# Production migration-to-repository coverage matrix

Updated: 2026-10-15. This is a manual reconciliation aid based on the read-only Production migration history and the SQL filenames on `main`. It is **not** proof that a filename contains equivalent SQL. Review each candidate file's contents and checksum before classifying any change as recovered.

## Classification rules

- **Filename candidate** — a similarly named SQL file exists in the repository; semantics and full contents still need comparison.
- **Missing source candidate** — no clearly corresponding SQL file appears in `main`; reconstruct only from verified evidence, never from the migration name alone.
- **Foundation placeholder** — matching filename exists but does not contain the original migration SQL.
- Production migration versions and repository filename timestamps differ, so timestamp-only matching is invalid.

## Row-by-row coverage

| Production version | Production migration name | Repository candidate / status |
|---|---|---|
| 20261007133831 | foundation_schema_rbac_rls | **Foundation placeholder** — `20261007200000_foundation_schema_rbac_rls.sql` is only 285 bytes |
| 20261007134222 | harden_rls_and_indexes | **Missing source candidate** — no matching candidate found in reviewed feature branch; exact path search also returned none |
| 20261007134728 | document_registration_rpc | Related candidate: `20261010190000_department_aware_document_registration_v1.sql`; not assumed equivalent |
| 20261007135044 | seed_school_registers_2026 | **Missing source candidate** — no matching candidate found in reviewed feature branch |
| 20261007135356 | workflow_engine_v1 | Filename candidate: `20261007205000_workflow_engine_v1.sql` |
| 20261007135756 | notification_deadline_engine_v1 | Filename candidate: `20261007210000_notification_deadline_engine_v1.sql` |
| 20261007135857 | move_pg_trgm_to_extensions | Filename candidate: `20261007210500_move_pg_trgm_to_extensions.sql` |
| 20261007140118 | audit_trail_v1 | **Missing source candidate**; later hardening file is not assumed to recreate the initial migration |
| 20261007140240 | audit_trail_hardening_v2 | Filename candidate: `20261007211000_audit_trail_hardening_v2.sql` |
| 20261007140759 | reporting_views_v1 | **Missing source candidate**; later security-invoker migration is not the original view definition |
| 20261007163008 | workflow_safety_hardening_v2 | Filename candidate: `20261007212000_workflow_safety_hardening_v2.sql` |
| 20261007163111 | workflow_status_transition_guard_v1 | Filename candidate: `20261007213000_workflow_status_transition_guard_v1.sql` |
| 20261007163119 | workflow_assignment_transition_guard_v1 | Filename candidate: `20261007213500_workflow_assignment_transition_guard_v1.sql` |
| 20261007163251 | reporting_views_security_invoker_v1 | Filename candidate: `20261007214000_reporting_views_security_invoker_v1.sql` |
| 20261007165305 | get_my_permissions_v1 | Filename candidate: `20261007214500_get_my_permissions_v1.sql` |
| 20261008015934 | outgoing_sent_archive_transition_v1 | Filename candidate: `20261007215000_outgoing_sent_archive_transition_v1.sql` |
| 20261008031530 | admin_role_management_v1 | Filename candidate: `20261007215500_admin_role_management_v1.sql` |
| 20261008034236 | document_file_versioning_v1 | Filename candidate: `20261008090000_document_file_versioning_v1.sql` |
| 20261008034444 | revoke_anon_security_definer_rpcs_v1 | Filename candidate: `20261008091000_revoke_anon_security_definer_rpcs_v1.sql` |
| 20261008042634 | admin_department_management_v1 | **Missing source candidate**; later profile-management migration is not assumed equivalent |
| 20261008053522 | admin_profile_department_management_v1 | Filename candidate: `20261008120000_admin_profile_department_management_v1.sql` |
| 20261008053554 | harden_admin_department_rpc_execute_v2 | **Missing source candidate** |
| 20261008053608 | revoke_anon_admin_department_rpc_v1 | Filename candidate: `20261008120500_revoke_anon_admin_department_rpc_v1.sql` |
| 20261009005230 | enforce_status_transition_permissions_v1 | Filename candidate: `20261009005230_enforce_status_transition_permissions_v1.sql` |
| 20261009005407 | protect_dedicated_workflow_rpc_transitions_v1 | Filename candidate: `20261009005407_protect_dedicated_workflow_rpc_transitions_v1.sql` |
| 20261009005459 | validate_approval_recipient_permission_v1 | Filename candidate: `20261009005459_validate_approval_recipient_permission_v1.sql` |
| 20261010085023 | 20261010130000_secure_public_workflow_rpc_wrappers_v1 | Filename candidate: `20261010130000_secure_public_workflow_rpc_wrappers_v1.sql` |
| 20261010085025 | 20261010150000_grant_director_document_update | Filename candidate: `20261010150000_grant_director_document_update.sql` |
| 20261010085028 | 20261010170000_department_scoped_document_access_v1 | Filename candidate: `20261010170000_department_scoped_document_access_v1.sql` |
| 20261010085031 | 20261010180000_scope_workflow_assignment_and_status | Filename candidate: `20261010180000_scope_workflow_assignment_and_status.sql` |
| 20261010085034 | 20261010190000_department_aware_document_registration_v1 | Filename candidate: `20261010190000_department_aware_document_registration_v1.sql` |
| 20261010090253 | guard_last_active_system_admin_role_removal_v1 | Filename candidate: `20261010200000_guard_last_active_system_admin_role_removal_v1.sql` |
| 20261011143751 | prevent_global_role_escalation | Branch candidate: `feature/department-scoped-permissions-2026-10-11:supabase/migrations/20261011143751_prevent_global_role_escalation.sql`; review exact contents before treating as equivalent |
| 20261011144307 | grant_director_global_document_create | Branch candidate: `feature/department-scoped-permissions-2026-10-11:supabase/migrations/20261011144307_grant_director_global_document_create.sql`; review exact contents before treating as equivalent |
| 20261012011549 | production_multi_department_membership_v1 | Branch candidate: `feature/department-scoped-permissions-2026-10-11:supabase/migrations/20261010160000_multi_department_membership_v1.sql`; name/version differ, not assumed equivalent |
| 20261012011559 | production_department_scoped_roles_permissions_v1 | Branch candidate: `feature/department-scoped-permissions-2026-10-11:supabase/migrations/20261011100000_department_scoped_roles_permissions_v1.sql`; not assumed equivalent |
| 20261012011633 | production_department_role_matrix_seed_fix | Branch candidate: `feature/department-scoped-permissions-2026-10-11:supabase/migrations/20261011120000_department_role_matrix_seed_fix.sql`; not assumed equivalent |
| 20261012011639 | production_department_scoped_read_rpc_fix | Branch candidate: `feature/department-scoped-permissions-2026-10-11:supabase/migrations/20261011121000_department_scoped_read_rpc_fix.sql`; not assumed equivalent |
| 20261012011646 | production_department_scoped_write_rpc_guards | Branch candidate: `feature/department-scoped-permissions-2026-10-11:supabase/migrations/20261011140000_department_scoped_write_rpc_guards.sql`; not assumed equivalent |
| 20261012011653 | production_department_scoped_access_final_correction | Branch candidate: `feature/department-scoped-permissions-2026-10-11:supabase/migrations/20261011150000_department_scoped_access_final_correction.sql`; not assumed equivalent |
| 20261012011659 | production_department_scoped_approval_guards | Branch candidate: `feature/department-scoped-permissions-2026-10-11:supabase/migrations/20261011160000_department_scoped_approval_guards.sql`; not assumed equivalent |
| 20261012011708 | production_department_scoped_rls_and_file_guards | Branch candidate: `feature/department-scoped-permissions-2026-10-11:supabase/migrations/20261011170000_department_scoped_rls_and_file_guards.sql`; not assumed equivalent |
| 20261012011719 | production_close_remaining_department_rls_bypasses | Branch candidate: `feature/department-scoped-permissions-2026-10-11:supabase/migrations/20261011180000_close_remaining_department_rls_bypasses.sql`; not assumed equivalent |
| 20261012011729 | production_separate_document_edit_from_approve_assign | Branch candidate: `feature/department-scoped-permissions-2026-10-11:supabase/migrations/20261011190000_separate_document_edit_from_approve_assign.sql`; not assumed equivalent |
| 20261012011736 | production_guard_document_file_attachment | Branch candidate: `feature/department-scoped-permissions-2026-10-11:supabase/migrations/20261011200000_guard_document_file_attachment.sql`; not assumed equivalent |
| 20261012011746 | production_require_department_membership_for_scoped_permissions | Branch candidate: `feature/department-scoped-permissions-2026-10-11:supabase/migrations/20261011210000_require_department_membership_for_scoped_permissions.sql`; not assumed equivalent |
| 20261012011831 | production_require_explicit_active_department_membership | Branch candidate: `feature/department-scoped-permissions-2026-10-11:supabase/migrations/20261011232000_require_explicit_active_department_membership.sql`; not assumed equivalent |
| 20261012024902 | secure_department_membership_management_rpc | Branch candidate: `feature/department-scoped-permissions-2026-10-11:supabase/migrations/20261011230000_manage_department_membership_rpc.sql`; not assumed equivalent |
| 20261012024916 | active_department_membership_approval_guard | Branch candidate: `feature/department-scoped-permissions-2026-10-11:supabase/migrations/20261011231000_require_active_membership_for_approvers.sql`; not assumed equivalent |
| 20261013001230 | include_department_scoped_permissions_in_identity | Branch candidate: `feature/department-scoped-permissions-2026-10-11:supabase/migrations/20261013001230_include_department_scoped_permissions_in_identity.sql`; not assumed equivalent |
| 20261014162126 | admin_global_role_management_v1 | Filename candidate: `20261014162126_admin_global_role_management_v1.sql` |
| 20261014202558 | registry_officer_delete_incoming_documents_v1 | Filename candidate: `20261015120000_registry_officer_delete_incoming_documents_v1.sql` |
| 20261015005425 | permanent_delete_incoming_drive_v1 | Filename candidate: `20261015130000_permanent_delete_incoming_drive.sql` |
| 20261015005428 | list_deleted_incoming_documents_v1 | Filename candidate: `20261015131000_list_deleted_incoming_documents.sql` |
| 20261015023421 | fix_list_deleted_incoming_status_enum_cast | **Missing source candidate** — no matching file found in reviewed branch trees |

## Additional branch review

The branch `feature/department-scoped-permissions-2026-10-11` contains several SQL files absent from `main`, including candidates for most department-membership and department-scoped permission corrections. These are now listed above as **branch candidates**, not confirmed matches. Their SQL contents and behavior must be compared with the October 15 catalog and Production behavior before reuse. This branch is not merged to `main` and is not itself a reproducible Production migration chain.

## Interpretation

- A **filename candidate** is only a starting point for semantic diff and dependency review. It does not mean the migration is historically identical.
- The table shows substantial gaps around department-scoped authorization and multi-department membership, as well as several early foundation/seed/hardening changes.
- Do not fill missing rows by inventing SQL from names. Use the captured current catalog, verified function definitions, repository history, and isolated behavior tests as evidence.
- The current end-state snapshot may support a clean-install baseline, but only after grants, owners, default ACLs, extensions, Auth/Storage dependencies, and full Supabase replay are validated.
- **No Production migration or schema change was applied to create this matrix.**
