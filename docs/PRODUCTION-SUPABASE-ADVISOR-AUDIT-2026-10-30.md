# Supabase Production advisor audit — 2026-10-30

Status: **read-only audit; no settings, schema, or data were changed.**

Project: `wbns-edoc` (`iigzzwyfxxtqbgjawyom`), Singapore.

## Security advisor findings

- **4 tables** have RLS enabled and no direct policies:
  - `public.department_role_permissions`
  - `public.system_settings`
  - `public.user_department_roles`
  - `public.user_departments`

  This can be intentional when tables are only accessed through narrowly authorized SECURITY DEFINER RPCs. Verify the intended RPC access paths and confirm that direct Data API access remains denied.

- **1 public SECURITY DEFINER reader** is callable by `anon`: `public.get_public_school_name()`. It appears intended to return the school's public display name, but its body, output scope, fixed search_path, and grants still require review.

- **18 SECURITY DEFINER functions** are callable by `authenticated`. This is not automatically a vulnerability, but every function must enforce `auth.uid()`, role / ownership / department scope, a fixed safe `search_path`, and least-privilege grants. Existing workflow/department regression CI covers a subset; the full set still needs a function-by-function authorization review.

- **Leaked password protection is disabled** in Supabase Auth. Enable only after checking the school's account recovery process and communicating that previously compromised passwords may be rejected at next sign-in.

## Performance advisor findings

- **10 unindexed foreign keys** were reported across department-role, document-assignment, document-delete, settings, and user-department tables. Review query plans and add indexes only where they benefit actual join/delete/update paths.
- **25 unused indexes** were reported. This is a usage snapshot, not proof that an index is unnecessary; do not drop indexes solely from this advisory.
- **7 multiple-permissive-policy warnings** were reported for SELECT on deadlines, departments, document registers, permissions, role permissions, roles, and user roles. These are query-planning/performance warnings; merge policies only after preserving the exact access semantics and regression tests.

## Release implications

1. No advisor remediation was applied to Production during this review.
2. Keep the four RLS-without-policy tables inaccessible directly; do not add broad policies to silence the linter.
3. Review all 18 authenticated SECURITY DEFINER RPCs before the next Production change.
4. Review the public school-name reader separately; retain public execution only if its output is intentionally public.
5. Plan leaked-password protection as a controlled Auth configuration change.
6. Treat performance findings as review items, not automatic schema edits.

The current CI passing result does not close these Production advisor findings. Re-run security and performance advisors after any approved remediation.


## Follow-up read-only verification — 2026-10-30 16:25 ICT

The live advisor result was followed by read-only catalog/ACL queries; no SQL write was issued.

### RLS-without-policy tables

| Table | RLS | anon SELECT | authenticated SELECT | Direct policy |
|---|---:|---:|---:|---:|
| `department_role_permissions` | on | no | yes | none |
| `system_settings` | on | no | no | none |
| `user_department_roles` | on | no | yes | none |
| `user_departments` | on | no | no | none |

For the two tables with authenticated SELECT grants, RLS still has no permissive policy, so direct row access is denied by default. The other two do not grant SELECT to authenticated. Keep this design closed; do not add policies merely to silence the INFO-level advisor finding. Access should continue through narrowly authorized RPCs.

### SECURITY DEFINER inventory and grants

A live catalog query found **19** public SECURITY DEFINER functions:

- All 19 have an explicit fixed `search_path` in `proconfig`.
- 18 are executable by `authenticated`; their definitions use either `auth.uid()` checks or the private permission helper (which derives authority from the authenticated context).
- One is executable by `anon`: `public.get_public_school_name()`, which returns only the school's configured public display name.
- The older overload `admin_save_system_settings(text,bigint)` is not executable by `authenticated`; the three-argument overload is the active authenticated RPC and checks the System Admin role.

This is a structural/definition review, not a substitute for negative tests of every argument combination and data scope. Keep the 18 authenticated RPCs in the manual review list; do not revoke them wholesale because the application uses the authorized RPC paths.

### Performance advisor

The live advisor returned:

- 10 unindexed foreign keys
- 25 unused-index candidates
- 7 multiple-permissive SELECT-policy warnings

These are INFO/WARN findings, not automatic defects. Do not add/drop indexes or merge policies without query-plan evidence and authorization-regression tests.

### Auth

Leaked-password protection remains disabled. This is a separate Auth configuration decision; enabling it may reject compromised passwords during future sign-ins. Do not toggle it without a staff account-recovery plan and communication.

**Release implication:** this read-only verification confirms the current no-policy tables are not directly open to anon and that the observed SECURITY DEFINER functions have fixed search paths. It does not remove the need for the remaining migration, end-to-end, backup/rollback, and school-policy gates.
