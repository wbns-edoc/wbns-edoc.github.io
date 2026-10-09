# SECURITY DEFINER SEARCH_PATH POSTURE — 2026-10-09

## Scope
Read-only catalog checks on production project `wbns-edoc` (`iigzzwyfxxtqbgjawyom`). No privileges, data, schema, functions, or configuration were changed. No runtime test was performed.

## Positive control observed
The catalog query for all functions in `public` and `private` with `prosecdef = true` returned a function-level `search_path` configuration for every listed function. Observed paths were either:
- `pg_catalog, public`
- `pg_catalog, public, private`

No selected SECURITY DEFINER function had a missing function-level configuration in this snapshot. A separate schema privilege query showed that `anon`, `authenticated`, and the `PUBLIC` pseudo-role do not have CREATE privilege on either `public` or `private`. This reduces the specific risk of untrusted API roles creating objects to shadow names in these schemas.

## Remaining cautions
- A pinned search_path is a positive control, but does not prove each routine is safe. Function bodies still need review for authorization checks, row/department scope, dynamic SQL, unsafe object resolution, and intended caller identity.
- The configured path includes `public` and, for some routines, `private`. Prefer explicit schema qualification for sensitive object references where practical and verify ownership/privileges on referenced objects.
- The default ACL findings documented in `LIVE-DEFAULT-PRIVILEGE-AND-FUNCTION-EXECUTE-AUDIT-2026-10-09.md` remain unresolved. Do not assume search_path settings compensate for overly broad EXECUTE defaults.
- The live API exposed-schema configuration remains unverified; a `pg_settings` lookup did not reveal it. Catalog EXECUTE privileges alone do not establish API reachability.
- No anon/authenticated request tests, no workflow integration tests, and no production changes were made.

## Release decision
**BLOCKED.** Keep the zero-incremental-cost constraint (0 THB), do not create a Supabase branch/project, and do not change grants until an approved least-privilege plan can be validated without jeopardizing the existing System Admin.
