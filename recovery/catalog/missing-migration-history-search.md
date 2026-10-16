# Repository history search for missing migration sources

Updated: 2026-10-15  
Repository: `wbns-edoc/wbns-edoc.github.io`  
Method: read-only GitHub commit-history queries for exact, guessed `supabase/migrations/<Production-version>_<Production-name>.sql` paths, followed by read-only recursive tree inspection of existing feature branches. The path-specific history query was against the default branch and does not enumerate every branch.

## Initial default-branch path search

No commits were returned for the exact guessed paths in the default-branch path-history endpoint for these entries. That result was incomplete as a repository-wide source search:

- `harden_rls_and_indexes`
- `seed_school_registers_2026`
- `audit_trail_v1`
- `reporting_views_v1`
- `admin_department_management_v1`
- `harden_admin_department_rpc_execute_v2`
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
- `fix_list_deleted_incoming_status_enum_cast`

## Follow-up branch discovery

Inspection of `feature/department-scoped-permissions-2026-10-11` found branch-only candidate SQL files for most department-scoped authorization changes, including multi-department membership, department-role permissions, read/write/approval guards, membership-management RPCs, and global-role/director permission corrections. The current coverage matrix now maps those candidate paths explicitly. These files remain candidates, not confirmed reproductions of Production migrations; versions and names differ and semantic validation is still required.

## Interpretation and limits

- The default-branch path-history endpoint returned no history for the exact guessed paths, but a later branch-tree inspection found relevant SQL candidates on a feature branch.
- This does **not** prove the SQL never existed or that the branch candidates are the exact SQL applied to Production. A migration may have used another filename/path, lived on another repository/private branch, or been applied directly to Supabase without being committed.
- Do not reconstruct historical SQL by simply copying the Production name into a filename or inventing SQL from the name.
- Next source-recovery avenues: inspect all repository branches/tags and broader commit history for relevant function names, ask whether a local working copy/backups exist, and use the captured October 15 catalog to validate a separate clean-install candidate.

## Safety status

No SQL was executed and no Supabase data/schema was modified by this search. Production migration reproducibility remains **BLOCKED** and Production deployment remains **NOT APPROVED**.
