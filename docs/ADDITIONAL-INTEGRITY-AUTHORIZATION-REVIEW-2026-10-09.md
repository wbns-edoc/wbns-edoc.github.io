# Additional Authorization and Integrity Review — 2026-10-09

## Scope and evidence

Read-only inspection of the live Supabase catalog for project `wbns-edoc` (`iigzzwyfxxtqbgjawyom`) on 2026-10-09. Inspected definitions of selected public SECURITY DEFINER functions and constraints on `public.user_roles` and `public.departments`.

This is a code/catalog review only. No production data, schema, grants, settings, migrations, or role assignments were changed. No exploit or authorization tests were executed. Findings below are review items, not proof of a reachable exploit.

## Findings to resolve before release

### 1. Department hierarchy validation is incomplete in the inspected RPCs

- `public.admin_create_department(text,text,uuid)` checks permission, required code/name, and duplicate code, then inserts `p_parent_id`.
- `public.admin_update_department(uuid,text,text,uuid,boolean)` checks permission, department existence, required code/name, and duplicate code, then writes `parent_id`.
- The function bodies inspected do not explicitly reject a parent equal to the department itself or a parent that would create an indirect cycle.
- The database has a self-referencing FK on `departments.parent_id`, but that only ensures the parent row exists; it does not prevent hierarchy cycles.

**Required follow-up:** add validation for self-parent and recursive cycle creation in a reviewed migration; test create/update with self-parent, ancestor-as-child, valid nesting, and nonexistent parent. Do not apply the fix to production until tested and approved.

### 2. Role removal RPC does not visibly protect the last System Admin

- `public.admin_remove_user_role(uuid,uuid)` was previously inspected and checks `user.manage` or `role.manage`, then deletes the requested row from `user_roles`.
- Its function body does not visibly enforce a last-System-Admin invariant or block self-removal.
- The inspected `user_roles` constraints are primary key `(user_id, role_id)` and foreign keys; no check constraint protects a minimum number of administrators. The selected trigger inventory did not show a non-internal trigger directly on `user_roles`.
- This does not rule out protection in other functions, policies, or application paths. The invariant must be verified across every role mutation path.

**Required follow-up:** design a transaction-safe invariant that prevents removal/demotion of the last active System Admin, including concurrent requests; test through all role assignment/removal paths using a non-production environment. Preserve the current production System Admin and do not perform lockout tests against production.

### 3. File-version attachment authorization needs resource-scope verification

- `public.attach_document_file_version(uuid,uuid,text)` is SECURITY DEFINER, checks an authenticated actor and `private.has_permission('document.update')`, validates that the document and file rows exist, then creates a document-file version.
- The inspected function body does not itself check document-level ownership, department scope, or workflow state. Whether that is a defect depends on the intended semantics of `document.update` and whether other layers enforce resource scope.
- The function uses an advisory transaction lock keyed by document ID and file role to serialize version numbering for that pair.

**Required follow-up:** confirm whether `document.update` is intentionally global. Add tests proving a user cannot attach a file to a document outside their permitted scope, if scope restrictions are part of the policy. Also test concurrent uploads and allowed file-role values. Do not blanket-revoke EXECUTE or alter grants before the wrapper/grant model is reconciled.

### 4. Department code uniqueness should be tested consistently

- The RPC checks duplicates using `lower(code)`, while the database constraint is a case-sensitive `UNIQUE (code)`.
- The RPC's check may provide case-insensitive behavior for these RPC calls, but direct writes or other mutation paths may not follow the same rule.

**Required follow-up:** decide whether department codes are intended to be case-insensitive. If yes, enforce that invariant at the database level (for example, a unique index on `lower(code)`) only after checking existing values and reconciling all migration sources. If no, align RPC validation and documentation with case-sensitive uniqueness.

## Release gate

- [ ] Reconcile production migration history with repository migration sources and provenance.
- [ ] Review every role grant/removal/demotion path and establish a transaction-safe last-admin invariant.
- [ ] Validate department hierarchy and uniqueness invariants at the database boundary.
- [ ] Confirm document-level authorization semantics for file attachment.
- [ ] Run the authorization matrix and regression tests in an isolated non-production environment.
- [ ] Verify backup and restore, obtain owner approval, and only then plan a controlled production rollout.

**Status:** review findings documented; tests not executed; no production changes made.
