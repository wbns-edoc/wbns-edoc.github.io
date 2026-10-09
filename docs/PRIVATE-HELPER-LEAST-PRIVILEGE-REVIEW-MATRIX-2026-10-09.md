# Least-privilege review matrix: private helper and registration RPCs — 2026-10-09

## Purpose

This is a review matrix based on read-only live catalog queries. It is not executable SQL and does not change permissions. The project requirement remains zero incremental cost (0 THB).

## Exact live observations

The live database reports `USAGE` on schema `private` for `authenticated`, and no `USAGE` for `anon`.

Effective function privilege checks for the following exact signatures reported both `authenticated EXECUTE = true` and `anon EXECUTE = true`:

| Function signature | SECURITY DEFINER | Additional observed detail | Review action |
|---|---:|---|---|
| `private.allocate_document_number(uuid, integer)` | yes | Explicit ACL included PUBLIC EXECUTE and authenticated EXECUTE | Confirm it is only callable through trusted registration flows; review PUBLIC/default grants and whether direct calls are intended |
| `private.has_permission(text)` | yes | Explicit ACL included PUBLIC EXECUTE and authenticated EXECUTE | Decide whether callers should query this helper directly; avoid exposing internal authorization details unnecessarily |
| `private.is_admin()` | yes | Explicit ACL included PUBLIC EXECUTE and authenticated EXECUTE | Confirm whether this helper should be directly executable by API roles |
| `private.register_incoming_document(text, uuid, text, date, timestamptz, urgency_level, text)` | yes | Definition checks `auth.uid()` and `registry.incoming.manage` before writes | Keep the business permission check; verify all intended calls go through a documented API path |
| `private.register_outgoing_document(text, text, text, text, date, urgency_level)` | yes | Definition checks `auth.uid()` and `registry.outgoing.manage` before writes | Keep the business permission check; verify all intended calls go through a documented API path |

The register routines call `private.allocate_document_number`, so a future privilege change must preserve this internal call path. A function ACL reported as NULL means default ACL behavior applies; it does not mean the function is inaccessible. Effective privilege checks were used rather than inferring solely from the ACL string.

Other selected private workflow functions reported `authenticated EXECUTE = true` but `anon EXECUTE = false`. This includes `assign_document`, `create_approval`, `decide_approval`, `set_document_deadline`, and `update_document_status`.

## Important qualification

These are database ACL observations, not end-to-end API tests. The anonymous role currently lacks schema USAGE on `private`, which is a relevant barrier to direct schema-qualified access. The live API's exposed-schema settings were not verified by this query. Therefore this matrix does **not** claim that an anonymous HTTP request can invoke these routines or that an exploit has been reproduced.

## Proposed review sequence — do not execute yet

1. Confirm live PostgREST exposed schemas and role grants through supported project configuration evidence.
2. Trace all SQL and frontend/Edge Function callers of registration routines and helper functions.
3. Decide intended exposure per function: public API entrypoint, authenticated-only entrypoint, or internal helper.
4. Produce a narrow privilege proposal for each exact signature, accounting for ownership, default privileges, dependencies, and the registration routines' internal calls.
5. Test direct anonymous invocation, authenticated unauthorized invocation, authorized invocation, and registration-number concurrency in an isolated environment that costs 0 THB.
6. Review rollback and backup evidence before any Production change; do not test mutating calls against Production.

## Explicit prohibitions

- Do not apply blanket `REVOKE EXECUTE` statements.
- Do not grant schema USAGE to `anon` as a troubleshooting shortcut.
- Do not change the only System Admin assignment.
- Do not create a paid Supabase branch, project, runner, or other billable resource.
- Do not claim runtime security behavior is verified until tests have actually run.

## Status

Review matrix prepared for follow-up. No privileges or data changed; no runtime tests executed. Production release remains **BLOCKED**.
