# Production Migration Reconciliation — Initial Inventory
Date: 2026-10-09
Status: **partial inventory only; semantic parity is not yet established**

## Safety
This is a repository/metadata comparison only. No Production schema, migration history, data, or role assignment was changed. In particular, no administrator role was removed or modified.

## Counts observed
- Supabase Production migration metadata currently returns 26 entries.
- The GitHub repository `supabase/migrations/` directory currently returns 21 SQL files, including `20261009013200_bootstrap_initial_system_admin_v1.sql`.
- The bootstrap migration is not present in the returned 26-entry Production migration list. It may have been run manually in SQL Editor; do not rerun it and do not infer it is unapplied from metadata alone.
- Repository timestamps and Production version prefixes differ. Filename similarity can suggest a candidate only; it is not proof that the SQL was the SQL actually applied.

## Candidate semantic mapping (unverified)
| Production entry | Candidate repository file / current conclusion |
|---|---|
| `foundation_schema_rbac_rls` | `20261007200000_foundation_schema_rbac_rls.sql` — candidate only |
| `harden_rls_and_indexes` | `20261007200000_foundation_schema_rbac_rls.sql` or `20261007205500_harden_workflow_rpc.sql` — unresolved; inspect exact SQL and live objects |
| `document_registration_rpc` | No obvious same-purpose filename in current repository listing — source recovery needed |
| `seed_school_registers_2026` | No obvious same-purpose filename in current repository listing — source recovery needed |
| `workflow_engine_v1` | `20261007205000_workflow_engine_v1.sql` — candidate only |
| `notification_deadline_engine_v1` | `20261007210000_notification_deadline_engine_v1.sql` — candidate only |
| `move_pg_trgm_to_extensions` | `20261007210500_move_pg_trgm_to_extensions.sql` — candidate only |
| `audit_trail_v1` | No obvious original audit migration in current listing; `20261007211000_audit_trail_hardening_v2.sql` is not proof of the missing v1 — source recovery needed |
| `audit_trail_hardening_v2` | `20261007211000_audit_trail_hardening_v2.sql` — candidate only |
| `reporting_views_v1` | No obvious same-purpose base migration in current repository listing — source recovery needed |
| `workflow_safety_hardening_v2` | `20261007212000_workflow_safety_hardening_v2.sql` — candidate only |
| `workflow_status_transition_guard_v1` | `20261007213000_workflow_status_transition_guard_v1.sql` — candidate only |
| `workflow_assignment_transition_guard_v1` | `20261007213500_workflow_assignment_transition_guard_v1.sql` — candidate only |
| `reporting_views_security_invoker_v1` | `20261007214000_reporting_views_security_invoker_v1.sql` — candidate only |
| `get_my_permissions_v1` | `20261007214500_get_my_permissions_v1.sql` — candidate only |
| `outgoing_sent_archive_transition_v1` | `20261007215000_outgoing_sent_archive_transition_v1.sql` — candidate only |
| `admin_role_management_v1` | `20261007215500_admin_role_management_v1.sql` — candidate only |
| `document_file_versioning_v1` | `20261008090000_document_file_versioning_v1.sql` — candidate only |
| `revoke_anon_security_definer_rpcs_v1` | `20261008091000_revoke_anon_security_definer_rpcs_v1.sql` — candidate only |
| `admin_department_management_v1` | `20261008120000_admin_profile_department_management_v1.sql` — possible partial overlap; unresolved |
| `admin_profile_department_management_v1` | `20261008120000_admin_profile_department_management_v1.sql` — candidate only |
| `harden_admin_department_rpc_execute_v2` | `20261008120500_revoke_anon_admin_department_rpc_v1.sql` — possible partial overlap; unresolved |
| `revoke_anon_admin_department_rpc_v1` | `20261008120500_revoke_anon_admin_department_rpc_v1.sql` — candidate only |
| `enforce_status_transition_permissions_v1` | `20261009005230_enforce_status_transition_permissions_v1.sql` — candidate only |
| `protect_dedicated_workflow_rpc_transitions_v1` | `20261009005407_protect_dedicated_workflow_rpc_transitions_v1.sql` — candidate only |
| `validate_approval_recipient_permission_v1` | `20261009005459_validate_approval_recipient_permission_v1.sql` — candidate only |

## Git history recovery result (2026-10-10)
- The only Git history entry for `supabase/migrations/20261007200000_foundation_schema_rbac_rls.sql` is commit `88ffb0154e13d6b540cf92f0987ff0fd6a59c9d3` (`db: add foundation migration marker`). That commit adds a four-line placeholder stating that the full SQL is maintained in the Supabase project; it does not contain the Foundation DDL.
- Git history queries for the exact expected paths of `20261007133831_foundation_schema_rbac_rls.sql`, `20261007134728_document_registration_rpc.sql`, `20261007135356_seed_school_registers_2026.sql`, `20261007140240_audit_trail_v1.sql`, and `20261007140759_reporting_views_v1.sql` returned no commits.
- This is evidence that the missing source is not recoverable from those exact repository paths in the available Git history. It does **not** prove that no equivalent SQL exists elsewhere or in operator/deployment artifacts. Continue recovery from authoritative deployment artifacts and inspect the live catalog only as a parity target, not as a substitute for source provenance.

## What is needed to complete reconciliation
1. Retrieve authoritative SQL artifacts from the deployment history or the operator who applied each Production migration. Do not use current live function definitions as a substitute for the original migration SQL.
2. Compare each artifact with the repository candidate and record exact equality or semantic differences; inspect live catalog state for objects and grants.
3. Recover the missing base migrations (`document_registration_rpc`, `seed_school_registers_2026`, `audit_trail_v1`, `reporting_views_v1`) and clarify the department-management entries.
4. Determine whether the bootstrap migration was manually applied and record the evidence separately without re-executing it.
5. Only after reconciliation, backup and isolated restore evidence, prepare any forward-only Production remediation.

## Current decision
No migration is approved for replay or reapplication. Do not rename files to force version matches, insert unknown history rows, reset Production, or replay historical migrations. Release status remains **NOT YET PRODUCTION READY**.
