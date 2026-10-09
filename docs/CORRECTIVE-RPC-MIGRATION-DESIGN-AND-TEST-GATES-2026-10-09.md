# Corrective RPC Migration Design and Test Gates — 2026-10-09

## Objective and constraints

Prepare a safe correction path for the live workflow/admin/file-scope drift. This is a design document, not an executable migration. No Production SQL, grants, policies, data, or Auth settings were changed. No Supabase branch/project was created. Additional cost target: 0 THB.

## Non-negotiable safeguards

- Do not replay `20261007205500_harden_workflow_rpc.sql` unchanged: live public functions have stricter checks than the private implementations that the wrappers would call.
- Do not change or delete the current System Admin assignment during tests.
- Do not grant broad INSERT on `google_drive_files` or `document_files`.
- Do not globally revoke EXECUTE from `authenticated` or blanket-revoke function privileges without a per-function dependency and UI call-site inventory.
- No Production DDL until there is a verified backup/restore path, an approved rollback plan, CI coverage, a testable non-production target that does not add cost, and explicit owner approval.
- If a test cannot run safely at 0 THB, mark it pending. Never represent static review as a runtime test.

## Canonical behavior required before migration authoring

### 1. `assign_document`

The canonical function must retain all of these properties:
- require a non-null `auth.uid()` and `document.assign`;
- lock the target document row before deciding whether a transition is valid;
- require the document to exist and be in the expected assignable state (current public implementation allows only `registered`);
- require an active assignee;
- reject non-future due dates;
- atomically update owner/status, write status history, create the assignment and notification, and create the optional deadline;
- fail as one transaction if any required side effect fails.

Do not simply wrap the current `private.assign_document`; its live body does not enforce all of the above.

### 2. `update_document_status`

The canonical function must:
- require authentication;
- lock the document row and validate existence;
- enforce transition-specific permissions (`document.complete`, `document.archive`, otherwise `document.update`, subject to explicit policy);
- reject transitions with mandatory side effects that must go through dedicated workflow RPCs (at minimum `pending_approval`, `approved`, `assigned`, and `pending_approval` to `draft`);
- call `private.is_valid_document_transition`;
- update status and history atomically;
- close open deadlines when completing or archiving.

Resolve the policy conflict explicitly: the historical `20261009005230` migration allowed an `assigned` transition after checking `document.assign`; `20261009005407` later rejects direct assignment transitions to preserve dedicated RPC side effects. The latter guard must not be lost.

### 3. `set_document_deadline`

The canonical function must require authentication and `document.assign`, validate document existence, active assignee, future due date and reminder ordering, and ensure the caller has permission for the target document's scope. Insert deadline metadata atomically. Verify whether multiple open deadlines are allowed before adding uniqueness constraints.

### 4. Admin role removal

Before deleting an assignment, lock the relevant role/user assignment set consistently and reject:
- removal of the final active System Admin;
- self-removal when it would remove the caller's final administrative recovery path;
- removal of a role assignment that is required by a protected bootstrap/recovery process.

The live role row confirms the canonical System Admin code is `system_admin` (name `System Admin`). Resolve this role by the stable code and verify it remains unique before counting active assignments; do not rely on display-name substring matching. Add concurrency tests so two simultaneous removals cannot both pass a last-admin count check. No live role changes are part of this work.

### 5. Department hierarchy

For create/update:
- require management permission;
- reject parent ID equal to the department's own ID;
- reject indirect cycles by traversing descendants/ancestors in a recursive query;
- validate that the parent exists and is active (confirm business rule);
- serialize concurrent hierarchy edits or use a constraint/locking strategy so two concurrent changes cannot create a cycle.

Do not introduce hierarchy assumptions without confirming whether inactive parents are permitted.

### 6. File attachment and Drive metadata

The attachment RPC must verify:
- the caller can update the specific document under the actual department/scope model;
- the Drive metadata row is authorized for the caller and the upload attempt, rather than accepting any existing Drive-file UUID;
- the file role is on an allowlist;
- version numbering and current-version replacement are atomic;
- metadata and version attachment do not leave an orphaned or cross-document reference.

Prefer a trusted server-side upload/metadata flow or a narrow authenticated RPC with explicit scope checks. Do not solve the browser INSERT failure with a broad table policy.

## Required test matrix

| Area | Positive test | Negative tests | Concurrency / recovery |
|---|---|---|---|
| Assignment | Authorized actor assigns a registered document to an active user | Missing auth, missing permission, unknown document, inactive assignee, wrong status, past deadline | Two actors assign same document; confirm only one valid transition |
| Status | Each explicitly allowed transition succeeds and writes one history row | Missing permission; invalid transition; direct assignment/approval transition; unknown document | Repeated/concurrent transition must not duplicate history or bypass guard |
| Deadline | Authorized assignment creates valid future deadline | Inactive/unknown assignee, unknown document, past due, reminder after due, out-of-scope document | Concurrent inserts and duplicate open deadlines follow documented business rule |
| Admin removal | Remove a non-final permitted role assignment | Last System Admin, caller's only recovery role, unauthorized actor | Two concurrent admin removals; verify at least one recovery admin remains |
| Department tree | Create/update valid parent-child tree | Self-parent, descendant as parent, nonexistent parent, unauthorized actor | Concurrent opposing parent changes cannot form a cycle |
| File attach | Authorized document/file pair creates next version | Unauthorized department, unrelated Drive file, invalid role, missing document/file, unauthenticated caller | Concurrent version uploads produce unique sequential versions and exactly one current version |
| Registration RPC | Authorized registry manager creates valid record | Anonymous caller, missing auth, missing permission, invalid fields | Duplicate/sequence handling does not create duplicate register numbers |

Test each RPC through the same PostgREST/API role and JWT context the browser uses. SQL executed as postgres alone does not prove API authorization. Use disposable fixture records in a non-production target and roll them back or clean them up; never use live school records as fixtures.

## Migration and rollout gates

1. Freeze a snapshot of the exact live function definitions, ACLs, triggers, RLS policies, constraints, enum values, and migration history.
2. Reconcile the 26 live migration-history entries against the repository's 21 migration files by SQL content/checksum/provenance, not filenames alone.
3. Agree on the scope/department authorization model and the canonical System Admin role identifier.
4. Author a new forward-only corrective migration only after the canonical function bodies are reviewed. Keep changes narrow and preserve existing API signatures where possible.
5. Run migration lint/static checks and the complete test matrix in a no-cost non-production environment. If no such environment exists, do not use Production as a substitute.
6. Verify rollback/recovery procedure and backup restoration, then get explicit school owner approval.
7. Apply during an approved maintenance window, immediately re-query function definitions/ACLs and RLS policies, run advisors, and perform API smoke tests.
8. Stop and roll back if any authorization test fails, an unexpected admin privilege change occurs, migration parity remains unresolved, or backup recovery is unverified.

## Current gate status

- Static inspection: confirmed current drift and design requirements.
- Executable corrective migration: **not authored**; this file intentionally contains no SQL intended to be applied.
- Runtime authorization tests: **pending**.
- Backup/restore proof: **pending**.
- Owner approval: **pending**.
- Production release: **BLOCKED**.
