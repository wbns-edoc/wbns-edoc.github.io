# Follow-up: Private-schema permission review — 2026-10-09

## Scope and safety

A read-only catalog query was run against the existing Supabase project. No grants, policies, functions, rows, or Production settings were changed. No paid infrastructure was created.

## Observation

The live database reports effective EXECUTE privileges for the anonymous and authenticated database roles on a small set of SECURITY DEFINER helper and document-registration routines located in the schema named `private`. The schema itself does not grant USAGE to the anonymous role, while the authenticated role has USAGE. Some helper functions also have default/PUBLIC execute privileges in their function ACL.

This is an access-control review finding, not proof that an anonymous request can successfully invoke these routines or mutate data. The registration routines contain authentication and permission checks in their current definitions; no invocation was attempted.

## Required handling

- Review schema exposure, default privileges, exact function signatures, wrappers, and all callers together.
- Establish the intended caller role for each function, then prepare a narrow function-by-function privilege proposal.
- Do not apply blanket REVOKE statements or alter Production privileges before dependency review and regression tests.
- Run positive and negative runtime tests only in a genuinely isolated environment that satisfies the 0-THB requirement.
- Do not create a paid branch or any other billable resource.
- Preserve the only live System Admin assignment throughout remediation and testing.

## Status

Finding recorded for follow-up. No changes applied; no runtime tests performed. Release remains **BLOCKED**.
