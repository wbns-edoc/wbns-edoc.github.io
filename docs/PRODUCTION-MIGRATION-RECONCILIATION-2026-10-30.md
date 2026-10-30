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


## October 15 Production catalog snapshot — isolated replay result

The previously captured October 15 catalog evidence from the read-only recovery branch has now been restored into this integration branch together with its dependency-order parser, PostgreSQL compatibility bootstrap, and RLS behavior regression suite.

- [Schema Recovery PostgreSQL Replay — PASS](https://github.com/wbns-edoc/wbns-edoc.github.io/actions/runs/41018845542)
- Replay target: disposable PostgreSQL 17 service only; no Supabase Production connection.
- Verified inventory: 25 public tables, 5 public enums, 45 public RLS policies, 12 non-internal public triggers, 54 public/private functions, and 2 public views.
- Verified security properties: all captured public tables have RLS enabled; both views retain `security_invoker=true`; no captured public policy targets `anon` or `PUBLIC`.
- Behavioral tests cover System Admin/Director global document permissions, parent/subgroup visibility, multi-department membership, inactive departments/profiles, removed memberships, disabled permissions, and denial of unauthorized admin RPC calls.

This is stronger evidence than the October 10 fixture replay, but it is still a compatibility-harness replay of a catalog snapshot, not a complete Supabase clean-install parity proof. The captured artifacts do not fully establish object ownership, grants, default ACLs, all extension/platform configuration, Auth/Storage internals, or the exact historical SQL that produced the current Production state.

## Integration branch CI checkpoint

On integration head `f9e5803d689f8c27ebdd4d168f85f8ae515a0c18`, all seven CI workflows passed, including the separate October 15 catalog snapshot replay and the local Supabase leave/workflow regression suite. The latter continues to use the October 10 recovered compatibility fixture for its local Supabase stack; the October 15 PostgreSQL replay is a distinct test. Neither test authorizes Production deployment.

The Foundation migration remains a 285-byte placeholder and the Production migration ledger still contains unreconciled historical source entries. Production remains unchanged and release remains blocked.


## October 17 assignment migration candidates

A fresh read-only inventory also identified two Production entries whose names do not exactly match the checked-in migration stems, but have plausible source candidates in the Integration branch:

| Production version/name | Candidate repository file | Evidence / status |
|---|---|---|
| `20261017070421` — `allow_assignees_to_complete_active_assignments` | `20261017020000_sync_assignment_when_assignee_completes_document.sql` | Semantic candidate: updates the status RPC so an active assignee can complete assigned work and marks that assignee's assignment completed. Exact SQL equivalence and timestamp provenance are not proven. |
| `20261017070749` — `fix_assignment_status_enum_check_for_completion` | No verified source file identified. `20261017021000_reconcile_assignments_for_completed_documents.sql` is a related data backfill, not evidence of the Production enum/check-constraint change. |

Do not mark either history row reconciled until the SQL is compared with a trusted deployment artifact or the resulting Production catalog/data effects can be independently demonstrated. In particular, the current read-only migration ledger proves only that the Production migration names and versions were applied; it does not expose their historical SQL bodies.


## October 28 Production schema dump — newer static audit

A user-provided schema-only dump is available in the private Library as `wbns-production-schema.sql` (200,854 bytes; 4,777 lines; captured 2026-10-28). The raw dump is deliberately **not** copied into this public repository. A direct static scan of that file gives:

- **27 public table definitions** (correcting the earlier audit note that reported 28)
- 5 public enum types
- 2 public views, both declared with `security_invoker='true'`
- 69 function definitions: 34 in `public`, 27 in `private`, 6 in `extensions`, and 2 in `graphql_public` (63 unique schema-qualified function names)
- 14 public triggers
- 48 indexes
- 50 public RLS policies
- 213 GRANT statements, 63 REVOKE statements, 104 owner statements, and 18 default-privilege statements
- No `CREATE EXTENSION` statements in the dump

All 27 captured public tables have RLS enabled. Four tables have no RLS policies: `department_role_permissions`, `system_settings`, `user_department_roles`, and `user_departments`. The 50 captured policies target `authenticated`; none targets `anon` or `PUBLIC`. The dump nevertheless includes table grants to `anon` on 24 public relations, so the security boundary depends on RLS and invoker-safe views. The two views are configured with `security_invoker=true`.

The no-policy tables are intended to be accessed through reviewed RPC paths or denied direct access; do not add broad policies merely to silence advisors. The system settings table is accessed through restricted settings RPCs; the department membership/permission tables have RPC-only administration paths. These paths still need role-negative tests in a current Supabase stack.

### Snapshot drift

The October 15 recovery snapshot replayed in CI is not the October 28 dump. Compared with that October 15 snapshot, the October 28 dump contains:
- 2 additional public tables (27 vs 25)
- 5 additional public policies (50 vs 45)
- 2 additional public triggers (14 vs 12)
- 15 additional function definitions (69 vs 54)

Therefore the October 15 replay is historical evidence only. It does **not** prove parity with the October 28 Production schema. The current dump also includes Supabase-managed extension/GraphQL functions and no extension installation statements; a clean replay must provision the correct platform extensions and Auth/Storage dependencies first.

### Additional disposable regression

The Integration branch's October 15 snapshot behavior test now grants SELECT on public tables/views to the disposable `anon` role and asserts that RLS still returns no rows from `documents`, `document_monthly_summary`, and `document_report_summary`. This models the broad anonymous grants found in the October 28 dump while preserving the no-anonymous-policy security boundary. The test does not modify Production and must pass in CI before being treated as evidence.

### Baseline decision

The October 28 dump is a stronger current-state recovery artifact than the October 15 catalog snapshot, but it is not the original Foundation migration and not a complete disaster-recovery backup. Do not replace the placeholder Foundation migration with this dump directly. First separate Supabase-managed objects from school-owned schema, resolve extension/platform dependencies, preserve ownership/grants/default ACL semantics, and replay a candidate baseline in a disposable Supabase stack with catalog parity checks.


## 2026-10-30 read-only Production ACL and extension checkpoint

A read-only catalog query was run against Production project `iigzzwyfxxtqbgjawyom`; no DDL, DML, migration repair, or deployment was executed.

| Check | Production result |
|---|---|
| `authenticated` USAGE on `public`, `auth`, `private` | true |
| `authenticated` SELECT on `public.profiles` | true |
| `authenticated` EXECUTE on `auth.uid()` | true |
| `anon` SELECT privilege on `public.profiles` | true (RLS remains the row-access boundary; the captured policy targets authenticated only) |
| Information-schema public table-grant rows for `authenticated` | 177 |
| Information-schema public table-grant rows for `anon` | 168 |

This confirms that the disposable PostgreSQL replay needed explicit test-only grants for the authenticated API role because the October 15 schema snapshot captures RLS policies but not the corresponding Supabase ACLs. The workflow now models the verified Production schema/function/profile grants only inside the disposable database.

Production currently has these seven installed extensions:

- `pg_cron` 1.6.4 in `pg_catalog`
- `pg_stat_statements` 1.11 in `extensions`
- `pg_trgm` 1.6 in `extensions`
- `pgcrypto` 1.3 in `extensions`
- `plpgsql` 1.0 in `pg_catalog`
- `supabase_vault` 0.3.1 in `vault`
- `uuid-ossp` 1.1 in `extensions`

The plain PostgreSQL 17 snapshot replay currently installs `pg_trgm` as a compatibility prerequisite only. It does not reproduce all Supabase-managed extensions, Auth/Storage platform objects, owners, default privileges, or project settings. Therefore the successful snapshot replay is strong SQL/object/RLS evidence, **not complete Supabase clean-install parity**.

## 2026-10-30 deeper staff-leave replay

The Schema Recovery PostgreSQL Replay workflow now applies the complete current staff-leave draft migration set to the reconstructed October 15 Production catalog in a disposable PostgreSQL 17 database, then runs all 12 staff-leave regression SQL tests. This caught missing test-harness API-role grants that the October 10 compatibility fixture did not expose. After adding test-only grants that were independently confirmed by the read-only Production ACL query, the deeper replay passed:

- [Schema Recovery PostgreSQL Replay — PASS, commit `39f5603d`](https://github.com/wbns-edoc/wbns-edoc.github.io/actions/runs/41023644975)
- Staff-leave migrations applied in the disposable replay: 16 (including the retired no-op foundation draft and school responsibility settings).
- Staff-leave regression SQL files executed: 12.
- The real leave-policy activation gate remains fail-closed; synthetic fixture policy approval is confined to rollback-protected tests and does not approve the school's handbook policy.

A frontend role-visibility regression was also found: `loadIdentity()` returns role display names before role codes, while the leave dashboard originally checked only role codes. The UI now normalizes names/codes and recognizes the Thai Director/Vice Director display names, and System Admin display name. A dedicated regression test is included in Frontend Build CI.

These passing tests do not close the remaining Foundation, 29 Production migration-name mapping, handbook-policy, full Supabase parity, live notification-delivery, rollback, or zero-cost release blockers.


## Historical source search across repository branches

A read-only scan of all **49 repository branches** inspected their recursive trees for migration SQL candidates related to the unmatched Production history. No alternate original Foundation migration path was found; the same placeholder path appears across the branch history sampled, and the file is 285 bytes with a comment that the full SQL is maintained in Supabase. Exact commit searches for the Foundation filename and several unmatched early migration names returned no source commits.

This means the current repository history cannot supply the original Foundation SQL. The October 15 current-state catalog is the best recovered object-definition evidence, but it is not the original migration and does not reconstruct every historical grant, owner, extension, Auth/Storage object, or platform setting. Do not fabricate a historical Foundation file from the migration name or replace it with a current-state dump and then replay later migrations on top.


## 2026-10-30 notifications realtime readiness

A read-only Production query confirmed that the `supabase_realtime` publication exists and emits INSERT/UPDATE/DELETE/TRUNCATE changes, but `public.notifications` was not a member of that publication. The existing notifications RLS policies are recipient-scoped:

- SELECT: `recipient_id = auth.uid()`, role `authenticated` only.
- UPDATE: `recipient_id = auth.uid()`, role `authenticated` only.

The Integration branch now contains draft migration `20261030110000_notifications_realtime_publication_draft.sql`, which adds only `public.notifications` to the existing publication if it is not already present. The NotificationBell subscribes to INSERT events with a `recipient_id=eq.<current-user-id>` filter and removes its channel on unmount. Regression tests assert the subscription contract and publication membership in local Supabase. This is not yet deployed to Production.
