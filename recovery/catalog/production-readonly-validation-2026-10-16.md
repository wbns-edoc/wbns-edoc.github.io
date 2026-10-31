# Production read-only authorization validation — 2026-10-16

Project: `iigzzwyfxxtqbgjawyom`  
Purpose: verify the current live function definition and check for rows that would be affected by the inactive-department authorization gap.  
Method: read-only catalog and aggregate SELECT queries only.

## Live function confirmation

The live Production definition of `private.has_department_permission(text, uuid)` matches the October 15 catalog snapshot: it checks the caller's active profile, the explicit department membership, scoped role, and enabled permission, but does not join `public.departments` or test `departments.is_active`.

Live catalog properties:
- Owner: `postgres`
- `SECURITY DEFINER`: true
- Pinned `search_path`: `pg_catalog, public, private`
- `anon` can execute: false
- `authenticated` can execute: true

The live `private.user_has_department(uuid, uuid)` does check `departments.is_active = true` and `profiles.is_active = true`. `private.can_access_document(uuid)` is also `SECURITY DEFINER` with the same pinned search path and is executable by authenticated but not anon.

## Live aggregate check for current stale assignments

The read-only aggregate query returned:

| Check | Count |
|---|---:|
| Inactive departments | 0 |
| Membership rows attached to inactive departments | 0 |
| Department role assignments attached to inactive departments | 0 |
| Enabled scoped permissions attached to inactive departments | 0 |
| Scoped role assignments for inactive profiles | 0 |
| Memberships for inactive profiles | 0 |

**Interpretation:** the query found no current rows in these specific stale-assignment categories at the time of the check. The function-level authorization gap still merits correction because the helper itself does not enforce department active state; zero current rows do not prove future safety or rule out unrelated authorization issues.

## Corrective candidate handling

`recovery/catalog/candidate-has-department-permission-active-department.sql` is a recovery-only candidate applied by the disposable PostgreSQL workflow, not a Production migration. It adds the active-department join to the scoped-permission branch while retaining the explicit active-profile global-role exception for `system_admin` and `director` on `document.view`, `document.create`, `document.approve`, and `document.update`.

The candidate uses `CREATE OR REPLACE FUNCTION` with the same signature and does not intentionally change ownership or function grants. This still requires an explicit pre/post ACL and owner comparison before any eventual production rollout.

## Validation and decision

- Disposable PostgreSQL replay with inactive department, inactive profile, removed membership, disabled permission, and director global-role regression tests passed on [run 38845302526](https://github.com/wbns-edoc/wbns-edoc.github.io/actions/runs/38845302526).
- Static evidence checks passed on [run 38845388640](https://github.com/wbns-edoc/wbns-edoc.github.io/actions/runs/38845388640).
- No Production writes were performed.
- Full local Supabase stack replay, downstream RPC/file/storage validation, complete clean-install catalog comparison, and a rollback plan remain required. Production deployment is **NOT APPROVED**.
