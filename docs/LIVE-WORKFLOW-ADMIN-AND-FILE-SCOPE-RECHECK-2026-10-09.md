# Live Workflow, Admin Lockout, and File Scope Recheck — 2026-10-09

## Scope

Read-only catalog and metadata queries against Supabase project `iigzzwyfxxtqbgjawyom`, plus inspection of migration source in the existing repository. No DDL/DML, privilege changes, test writes, branch creation, or Production deployment occurred. Incremental spend remains 0 THB.

## Confirmed live facts

### Workflow function drift

The live catalog currently has the following public RPCs as SECURITY DEFINER implementations, not the SQL SECURITY INVOKER wrappers intended by `supabase/migrations/20261007205500_harden_workflow_rpc.sql`:

- `public.assign_document(uuid,uuid,text,timestamptz)`
- `public.update_document_status(uuid,document_status,text)`
- `public.set_document_deadline(uuid,uuid,timestamptz,timestamptz)`

The private implementations also exist and are SECURITY DEFINER. Their behavior differs from the public functions:

- `private.assign_document` checks `document.assign`, document/active assignee existence, but does not include the public implementation's registered-status-only guard, future-deadline validation, row lock, or its complete transition handling.
- `private.update_document_status` checks `document.update OR document.complete`, then directly updates status and history. It lacks the public implementation's dedicated-RPC transition guards, transition-specific permission checks, and call to `private.is_valid_document_transition`.
- `private.set_document_deadline` checks `document.assign` and future due date, but does not validate document existence, active assignee, or reminder ordering as the public implementation does.
- `public.create_approval` and `public.decide_approval` are currently SECURITY INVOKER, matching the intended wrapper posture at a high level.

**Risk:** blindly applying the repo migration could replace stricter live public implementations with wrappers delegating to weaker private implementations. Do not apply it unchanged. First reconcile behavior into one canonical implementation and test the exact live behavior.

### Admin lockout and department hierarchy

- `public.admin_remove_user_role` is SECURITY DEFINER and checks `user.manage` or `role.manage`, then deletes the requested role assignment. No visible guard was found in the function body for last-System-Admin protection or self-removal.
- `public.admin_create_department` and `public.admin_update_department` check management permissions and code/name validity, but no visible self-parent or recursive cycle prevention was found.
- Current snapshot counts: one System Admin role assignment, one active profile, zero documents, zero departments. The role assignment count is not proof that the account is healthy or that there are no alternate admin pathways; it does indicate last-admin safeguards are high priority.

### File attachment scope

- `public.attach_document_file_version` is SECURITY DEFINER; it requires authentication and `document.update`, checks that the document and Drive-file rows exist, and serializes version allocation with an advisory transaction lock.
- It does not visibly verify that the caller may access the target document's department/scope or that the selected Drive-file metadata belongs to that document/upload attempt. These are candidate authorization gaps requiring a concrete scope model and negative tests, not proof of an exploitable path by themselves.
- RLS policy inventory still shows SELECT-only policies on `google_drive_files` and `document_files`. The browser upload flow's metadata INSERT therefore remains an integration risk; no upload was attempted.

### Effective EXECUTE privileges

Read-only `has_function_privilege` checks show:
- `anon` has effective EXECUTE on `private.allocate_document_number`, `private.has_permission`, `private.is_admin`, `private.register_incoming_document`, and `private.register_outgoing_document`, but `anon` lacks USAGE on schema `private`. This is not evidence that anonymous API calls succeed; do not infer reachability from ACL alone.
- `authenticated` has effective EXECUTE on the selected private helpers and workflow implementations.
- `public.register_incoming_document` and `public.register_outgoing_document` retain PUBLIC/anon EXECUTE ACLs. They are SECURITY INVOKER wrappers and their private-schema dependency is inaccessible to anon by schema USAGE; function bodies also contain authentication/permission checks in the private implementations. Runtime anonymous behavior has not been tested.

## Migration source comparison

- `20261007205500_harden_workflow_rpc.sql` moves existing workflow implementations into `private` and creates public invoker wrappers, but it predates later public hardening migrations that add stricter behavior. Live state is not equivalent to simply replaying this file.
- `20261008091000_revoke_anon_security_definer_rpcs_v1.sql` revokes anon from selected RPCs but does not include the public registration wrappers.
- `20261008120500_revoke_anon_admin_department_rpc_v1.sql` revokes anon from the department admin RPCs. Current catalog confirms anon cannot execute those selected department RPCs.
- Migration filenames and presence are not sufficient proof of content parity; use exact SQL/definition comparisons and migration-history reconciliation.

## Safe next steps

1. Design a single canonical implementation for each workflow RPC, preserving all stricter live validations and side effects.
2. Write negative/positive authorization tests for role removal, department cycles, cross-document/department file attachment, invalid status transitions, unauthorized deadline assignment, and registration RPCs.
3. Use a rollback-safe test environment with no incremental spend. If that environment cannot be provided within the 0 THB limit, keep tests marked pending rather than mutating Production.
4. Implement metadata insertion through a trusted server-side transaction or a narrowly scoped authenticated RPC; do not add broad table INSERT policies.
5. Verify backup/restore and System Admin survivability before any Production DDL.

## Status

- Read-only live inspection: complete for this snapshot.
- Runtime authorization/integration tests: not run.
- Corrective migration: not created/applied.
- Production release: **blocked**.
