# Workflow RPC live catalog check

Date: 2026-10-10
Environment: read-only inspection of Supabase Production project `iigzzwyfxxtqbgjawyom`

## Results

Catalog query checked the security mode and effective EXECUTE privileges of the public workflow RPCs and corresponding private implementations.

| Function | Public SECURITY DEFINER? | Authenticated EXECUTE | Anon EXECUTE |
|---|---:|---:|---:|
| `public.assign_document(uuid,uuid,text,timestamptz)` | Yes | Yes | No |
| `public.update_document_status(uuid,document_status,text)` | Yes | Yes | No |
| `public.set_document_deadline(uuid,uuid,timestamptz,timestamptz)` | Yes | Yes | No |
| `public.create_approval(uuid,uuid,integer)` | No | Yes | No |
| `public.decide_approval(uuid,approval_decision,text)` | No | Yes | No |

Corresponding `private` implementations for all five functions are SECURITY DEFINER, executable by authenticated, and not executable by anon. The `private` schema currently grants USAGE to authenticated.

## Interpretation

- Anonymous EXECUTE was denied for the five public entry points in this catalog snapshot.
- The public `assign_document`, `update_document_status`, and `set_document_deadline` entry points still run as SECURITY DEFINER in Production. That contradicts the intended public-invoker-wrapper pattern in the repository hardening migration.
- This is a confirmed release blocker because these privileged public entry points do not independently enforce the school's department-level access boundary.
- This query only inspected catalog metadata. It did not invoke workflow functions, modify grants, alter schema, or test cross-department behavior.

## Next safe action

Recover and reconcile the full migration source before preparing a forward-only corrective migration. Then test the proposed change on a fully replayable disposable local database, including authenticated invocation behavior, explicit EXECUTE grants, department isolation, and System Admin lockout prevention. Do not apply a guessed migration to Production.

## Safety

No Production changes were made. No additional Supabase project or branch was created.


## Follow-up read-only confirmation (2026-10-10)

A second read-only catalog query reconfirmed that the live Production definitions of `public.assign_document`, `public.update_document_status`, and `public.set_document_deadline` are still SECURITY DEFINER. Their corresponding `private` implementations are also SECURITY DEFINER. No function was invoked and no database object, grant, or data was changed during this follow-up check. The remote migration history still reports 26 entries; the repository source reconciliation blocker remains unresolved.
