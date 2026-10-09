# Forward-Only Remediation Plan: Workflow RPC Exposure
**Project:** ระบบสารบรรณอิเล็กทรอนิกส์ โรงเรียนวัดบึงน้ำใส  
**Date:** 2026-10-10  
**Status:** Remediation specification; NOT an executable migration and NOT applied to Production

## Why this is now a confirmed blocker

A read-only Production catalog query confirmed that these public functions are currently SECURITY DEFINER and executable by `authenticated`:
- `public.assign_document(uuid,uuid,text,timestamptz)`
- `public.set_document_deadline(uuid,uuid,timestamptz,timestamptz)`
- `public.update_document_status(uuid,document_status,text)`

The query also confirmed `anon` cannot execute those functions. This is good for anonymous exposure, but it does not fix the SECURITY DEFINER exposure to authenticated callers. The corresponding implementations exist in `private` and are SECURITY DEFINER as expected for internal privileged implementations.

## Safe remediation shape

Do not run SQL in this document. Generate a proper timestamped migration with the Supabase CLI in a local checkout, test it against a disposable local database, and then submit it for review. The migration should restore these public API wrappers as SECURITY INVOKER and call only the matching private implementation.

Representative shape (signature and grants must be verified against the actual catalog before use):

```sql
create or replace function public.assign_document(
  p_document_id uuid,
  p_assignee_id uuid,
  p_instructions text default null,
  p_due_at timestamptz default null
) returns uuid
language sql
security invoker
set search_path = pg_catalog, public, private
as $$ select private.assign_document($1, $2, $3, $4) $$;

create or replace function public.set_document_deadline(
  p_document_id uuid,
  p_assigned_to uuid,
  p_due_at timestamptz,
  p_reminder_at timestamptz default null
) returns uuid
language sql
security invoker
set search_path = pg_catalog, public, private
as $$ select private.set_document_deadline($1, $2, $3, $4) $$;

create or replace function public.update_document_status(
  p_document_id uuid,
  p_to_status public.document_status,
  p_reason text default null
) returns boolean
language sql
security invoker
set search_path = pg_catalog, public, private
as $$ select private.update_document_status($1, $2, $3) $$;
```

Do not apply this representative SQL until confirming:
1. `authenticated` has `USAGE` on `private` if the invoker wrapper requires it.
2. Each wrapper has EXECUTE for `authenticated`, and not `anon`/PUBLIC.
3. Each private implementation is executable by the intended wrapper caller and independently validates `auth.uid()` and permission.
4. The public and private signatures exactly match the live catalog and migration history.
5. `public.create_approval` and `public.decide_approval` remain SECURITY INVOKER (they were already observed that way) and the same invariant is checked in CI.
6. The fix does not accidentally change return types, defaults, grants, or application RPC signatures.

## Separate mandatory fix: last System Admin protection

The live `public.admin_remove_user_role(uuid,uuid)` implementation is SECURITY DEFINER, requires a generic role/user management permission, and deletes the requested role assignment without a last-active-System-Admin guard. It is callable by `authenticated`, not `anon`.

A separate forward-only migration must:
- Identify the canonical System Admin role by a verified stable role identifier or approved exact role mapping; do not infer based on fuzzy label matching.
- Serialize concurrent removals/changes with a transaction-scoped advisory lock or an equivalent safe lock.
- Reject removing/deactivating the final assignment that leaves zero active System Admin users.
- Reject accidental self-lockout unless an independently verified active System Admin remains.
- Preserve the ability to maintain other roles normally.
- Test add/remove/deactivate concurrency in a disposable database. Never test destructive cases against the only Production System Admin.

## Required tests before release

- Catalog regression test: the three public workflow entry points above have `prosecdef = false`.
- Catalog regression test: `create_approval` and `decide_approval` remain `prosecdef = false`.
- ACL test: `anon` cannot execute public workflow RPCs; `authenticated` can execute only the approved public wrappers.
- Behavior test: each wrapper delegates correctly and rejects unauthenticated callers.
- Authorization test: cross-department operations are denied after document-scope enforcement is implemented.
- Last-admin test: final admin removal is rejected under sequential and concurrent attempts.
- Fresh local migration replay and upgrade-from-snapshot both pass.

## Why no Production change was made

Production migration history and repository migration files are not reconciled, and there is no isolated Supabase branch/project (nor should one be created if it adds cost). This task cannot safely validate a new migration by running it against Production. Keep the SQL as a remediation specification until it can be generated with the CLI, tested locally, reviewed, backed up, and explicitly approved.
