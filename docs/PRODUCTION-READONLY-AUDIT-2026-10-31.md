# Production read-only audit — 2026-10-31

**Scope:** read-only Supabase inspection of `wbns-edoc` (`iigzzwyfxxtqbgjawyom`) and GitHub migration inventory at Integration head `274400abba0e42ee40967152a2dffac9f0b8754f`.

**No Production DDL, DML, migration repair, function deployment, or project-setting change was performed.**

## Migration history reconciliation

- Production migration ledger: **76 applied entries** (read from Supabase migration history).
- Integration branch: **85 SQL migration files**.
- Exact normalized migration-name matches (timestamp prefix removed): **47**.
- Production history entries without an exact repository filename-stem match: **29**.
- Repository migration files not represented by an exact Production migration name: **38**.

The 29 unmatched Production rows are not all proof of missing SQL. Some have restored historical branch candidates whose names differ from the Production ledger; they remain candidates until exact SQL or resulting catalog behavior is verified.

Latest Production migration row observed:
- `20261030094941` — `require_active_department_for_scoped_permissions`

The original Foundation migration remains a placeholder in the repository. The October 15 recovered-catalog fixture and the current Production schema export are not interchangeable with the missing historical Foundation SQL. Do not substitute an end-state snapshot at the beginning of the migration chain.

## Security Advisor — current read-only findings

### RLS-enabled public tables without policies: 4

| Table | authenticated SELECT grant | authenticated writes | anon SELECT |
|---|---:|---:|---:|
| `department_role_permissions` | yes | no | no |
| `system_settings` | no | no | no |
| `user_department_roles` | yes | no | no |
| `user_departments` | no | no | no |

RLS is enabled and no policy exists on each table, so direct authenticated row access remains denied even where a SELECT grant exists. The application currently uses narrowly scoped SECURITY DEFINER RPCs for permission evaluation and settings access. Do not add broad policies to silence the Advisor.

### SECURITY DEFINER function exposure: 18

- All 18 inspected functions have an explicit fixed `search_path`.
- The Advisor reports 18 callable by `authenticated`; source inspection found authentication, permission, or document-scope checks on all 17 non-public-reader functions.
- `get_public_school_name()` is callable by `anon` intentionally and only returns the configured school name. Keep this public reader only if the school still wants the public login/about screen to display the school name.
- This is a code-level spot audit, not a substitute for role-impersonation tests against every function signature. Keep the SQL security regression suite as a release gate.

### Auth warning

- Leaked-password protection is disabled. Enabling it is a separate Auth configuration change requiring account-recovery communication and review. It was not changed during this audit.

## Performance Advisor — current read-only findings

- 10 foreign keys without covering indexes.
- 25 indexes reported unused by current statistics.
- 7 tables with multiple permissive SELECT policies.

Do not automatically add/drop indexes or consolidate policies. Usage statistics may be reset or reflect low traffic, and policy consolidation can change access semantics. Review each against actual query plans and role tests before proposing a migration.

## CI evidence

At Integration commit `c66029e965c8acea63d407e6ea22c38e5fd89efa` on 2026-10-30, all eight required CI workflows passed. The Workflow RPC Security job ran 12 SQL test files / 104 assertions successfully. The leave schema/RLS job ran the 12 leave SQL regression files against disposable PostgreSQL 17; the Supabase snapshot/replay job ran on an isolated local Supabase database.

A follow-up hardening change on Integration:
- restricts the GitHub Pages deployment job to `refs/heads/main`, preventing a manual `workflow_dispatch` on a feature branch from publishing that branch;
- adds `.github/workflows/deploy.yml` to Frontend Build CI path filters so changes to the deployment workflow trigger a pull-request build.

These follow-up commits are under CI at the time of this report. The guard is on the Draft PR branch only and is not active on `main` until reviewed and merged.

## Release blockers that remain

1. Recover or formally reconstruct the historical Foundation migration; validate against the current Production catalog including ownership, grants, default ACLs, extensions, Auth/Storage objects, views, triggers, and publication settings.
2. Reconcile the 29 unmatched Production history rows using exact historical SQL or reviewed catalog-effect mappings.
3. Complete the leave policy implementation for school holidays, service history, carry-over balances, childcare subtype, prior-use checks, and evidence/eligibility rules. The school-wide leave policy must remain draft and calculation-disabled until approved.
4. Complete browser E2E using school accounts and verify deployed notification/Realtime delivery and real role authorization.
5. Review the 18 callable SECURITY DEFINER functions and the 4 no-policy RLS tables in the live role context; keep direct table access denied where intended.
6. Plan Auth leaked-password protection and recovery UX; rehearse backup/rollback; verify the actual hosting/billing configuration remains 0 baht.
7. Obtain a final school acceptance decision and an approved maintenance window before any Production rollout.

**Release decision: NOT APPROVED. Keep PR #55 Draft. Keep Production unchanged.**
