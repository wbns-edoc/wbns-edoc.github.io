# Authorization semantic review — 2026-10-15

Branch reviewed: `feature/department-scoped-permissions-2026-10-11`. Comparison target: read-only Production catalog snapshot.

## Status

Do not merge or deploy candidate migrations yet. This review is read-only; the PostgreSQL replay uses a disposable database and does not modify Production.

## Finding A — inactive department checks differ between helpers

The recovered `private.user_has_department(uuid, uuid)` checks that both the profile and department are active. The recovered `private.has_department_permission(text, uuid)` checks an active profile and explicit department membership/role/permission rows, but does not itself check `departments.is_active`.

Consequently, a caller relying only on `has_department_permission` may still receive a positive result for an inactive department if related rows remain. The current presence of such data has not been established, and this finding is not evidence of a data breach. Review every RLS policy and RPC using this helper to determine whether another guard covers the inactive-department case.

**Required before deployment:** add regression cases for inactive profiles, inactive departments, removed membership, and disabled permissions. Prepare a minimal correction on the recovery branch that requires active membership and department while preserving the explicit System Admin/director exception. Test all affected create, update, approval, assignment, and file paths.

## Finding B — director global permission test

The disposable test previously asserted director read-all and approve, but omitted explicit create and update assertions. The test has been updated to assert create, update, and approve for both System Admin and director.

## Validation limits

Disposable PostgreSQL replay does not prove a complete Supabase clean install with Auth, Storage, Edge Functions, OAuth, or deployment configuration. Catalog equality, RPC grants, file/storage access, and workflow tests remain required.

## Decision

No Production writes were performed. No migration is approved for deployment. Keep PR #27 Draft until the findings and remaining reconstruction blockers are resolved.
