# Production Schema Recovery — 2026-10-10

## Purpose

Recover the missing version-controlled database source from the live WBNS Supabase catalog without changing Production. This document records observations from read-only catalog queries. It is not a claim that a complete reproducible migration has been recovered.

## Target

- Supabase project ref: `iigzzwyfxxtqbgjawyom`
- Region: Singapore (`ap-southeast-1`)
- Status observed previously: ACTIVE_HEALTHY
- Repository: `wbns-edoc/wbns-edoc.github.io`
- Production migration history: 26 entries
- Repository migration SQL files: 21, with version/name drift
- Foundation migration in `main` and current feature branch is a placeholder comment, not executable schema SQL.

## Read-only catalog observations (2026-10-10)

- 22 public base tables (catalog count includes current public table inventory).
- 28 routines in public/private schemas.
- 45 RLS policies across public/private schemas.
- Public enum types:
  - `approval_decision`: pending, approved, rejected, returned
  - `assignment_status`: assigned, accepted, in_progress, completed, cancelled
  - `document_status`: draft, pending_approval, approved, received, registered, assigned, in_progress, completed, archived, sent, cancelled
  - `document_type`: incoming, outgoing
  - `urgency_level`: normal, urgent, very_urgent, critical
- `documents` currently has no `department_id` column. `profiles.department_id` exists.
- Production `documents`, `document_files`, `google_drive_files`, and `departments` were previously observed empty; current user/profile count was 1.
- Production security advisor snapshot observed on 2026-10-09: 10 warnings for authenticated-executable public SECURITY DEFINER functions and one warning for disabled leaked-password protection.
- No Production changes were made during this recovery inspection.

## Migration history vs repository

Production has the following 26 applied migrations (the authoritative names/versions reported by Supabase):

```text
20261007133831 foundation_schema_rbac_rls
20261007134222 harden_rls_and_indexes
20261007134728 document_registration_rpc
20261007135044 seed_school_registers_2026
20261007135356 workflow_engine_v1
20261007135756 notification_deadline_engine_v1
20261007135857 move_pg_trgm_to_extensions
20261007140118 audit_trail_v1
20261007140240 audit_trail_hardening_v2
20261007140759 reporting_views_v1
20261007163008 workflow_safety_hardening_v2
20261007163111 workflow_status_transition_guard_v1
20261007163119 workflow_assignment_transition_guard_v1
20261007163251 reporting_views_security_invoker_v1
20261007165305 get_my_permissions_v1
20261008015934 outgoing_sent_archive_transition_v1
20261008031530 admin_role_management_v1
20261008034236 document_file_versioning_v1
20261008034444 revoke_anon_security_definer_rpcs_v1
20261008042634 admin_department_management_v1
20261008053522 admin_profile_department_management_v1
20261008053554 harden_admin_department_rpc_execute_v2
20261008053608 revoke_anon_admin_department_rpc_v1
20261009005230 enforce_status_transition_permissions_v1
20261009005407 protect_dedicated_workflow_rpc_transitions_v1
20261009005459 validate_approval_recipient_permission_v1
```

## Recovery method

1. Use read-only queries against PostgreSQL catalogs to extract enum labels, column types/defaults/nullability, constraints, indexes, RLS policies, views, triggers, function definitions, grants, and relevant extension/schema configuration.
2. Compare the recovered snapshot with every repository migration and frontend/Edge Function call site.
3. Build a fresh baseline only on a disposable local PostgreSQL/Supabase test environment (CI runner); never create a paid Supabase branch.
4. Add catalog assertions and behavior tests, especially authorization isolation and workflow side effects.
5. Keep a separate forward-only migration for any approved Production changes. A catalog snapshot is not by itself an ordered historical migration set.
6. Before Production changes: capture/verify backup, pass tests, review advisor findings, and obtain explicit owner approval.

## Critical reconstruction cautions

- Do not seed Production data from this schema recovery.
- Do not copy auth user records, user-specific identifiers, secrets, or production data into source control.
- Do not infer the four department names or central-role permission matrix from existing rows; these require the owner's approved authorization rules.
- Do not fix advisor warnings with blanket EXECUTE revocations. Review each RPC and its delegated private implementation.
- Do not add broad file-table INSERT policies. The upload path uses server-side metadata writes and a version-attachment RPC.
- Do not add `documents.department_id` in Production until the forward-only data/authorization design is tested against the real schema.
- This work is read-only until a verified recovery baseline and safe forward-only patch are available.


## Reconstructed catalog fixture added

A test-only SQL snapshot was assembled from read-only catalog output and committed at:
`supabase/tests/fixtures/recovered-production-catalog.sql`.

It contains current public enum/table/constraint/index/function/view/trigger/RLS-policy definitions, current API ACLs, and only the system reference rows for roles, permissions, role-permission mappings, and document registers. It deliberately omits profiles, role assignments, senders, documents, files, audit logs, and other operational records.

A separate CI workflow, `.github/workflows/recovered-catalog-fixture-ci.yml`, applies this snapshot to a disposable local Supabase stack and runs schema lint plus smoke tests. The fixture is a **reconstructed current-state test snapshot**, not the missing ordered 26-migration history and not a Production deployment artifact. The original migration chain remains unreconciled until the snapshot passes CI and its definitions are reviewed against repository code.
