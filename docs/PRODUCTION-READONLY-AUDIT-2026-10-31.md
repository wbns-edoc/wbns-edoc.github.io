# Production read-only audit — 2026-10-31

**Scope:** read-only Supabase inspection of `wbns-edoc` (`iigzzwyfxxtqbgjawyom`) and GitHub migration inventory at Integration code commit `4e5481206d638d5ac42eae96692c38c8857e0907`.

**No Production DDL, DML, migration repair, function deployment, or project-setting change was performed.**

## Migration history reconciliation

- Production migration ledger: **76 applied entries** (read from Supabase migration history).
- Integration branch: **85 SQL migration files**.
- Exact normalized migration-name matches (timestamp prefix removed): **47**.
- Exact Production version + migration-name matches: **9**.
- Production history entries without an exact repository filename-stem match: **29**.
- Repository migration files not represented by an exact Production migration name: **38**.

The 29 unmatched Production rows are not all proof of missing SQL. Some have restored historical branch candidates whose names differ from the Production ledger; they remain candidates until exact SQL or resulting catalog behavior is verified.

Latest Production migration row observed:
- `20261030094941` — `require_active_department_for_scoped_permissions`

The Integration file is now named `20261030094941_require_active_department_for_scoped_permissions.sql`, matching the already-applied Production version. The previous Integration timestamp was removed only after comparing the migration's sole `private.has_department_permission(text,uuid)` function body with Production's `pg_get_functiondef`; the bodies match exactly after whitespace normalization (1,177 characters). The migration contains no additional DDL/DML. The snapshot CI assertion and workflow references were updated to this exact applied version. This reconciles one applied migration without running `migration repair` or changing Production.

The original Foundation SQL has now been recovered read-only from Production's own `supabase_migrations.schema_migrations.statements` row: version `20261007133831`, name `foundation_schema_rbac_rls`, one stored statement, 26,133 SQL characters. The exact source is archived outside `supabase/migrations` at `recovery/production-migrations/20261007133831_foundation_schema_rbac_rls.sql` on Integration commit `5a655ff9`; it is explicitly marked as a source archive and must not be replayed against Production. A separate disposable PostgreSQL 17 replay and catalog assertion were added to CI and passed on PR head `47237a17ee34c64bbb443ae111d457fcc91931d2` (Schema Recovery PostgreSQL Replay run `41436502874`). The workflow created a fresh `foundation_recovery` database, applied the archived source, and passed assertions for all 22 expected tables with RLS enabled, 5 enums, key functions, RLS policies, and triggers. This validates that the recovered SQL executes on a clean PostgreSQL 17 fixture; it does not prove that the historical Foundation alone equals today's evolved Production catalog. Migration parity still requires reconciliation against current Production objects, ownership, grants, extensions, Auth/Storage objects, defaults, and publication settings. Do not substitute an end-state snapshot at the beginning of the migration chain.

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

## Production Edge Function parity

Read-only inspection found **5 ACTIVE Edge Functions**, all with `verify_jwt=true`:

| Function | Production version |
|---|---:|
| `drive-health` | 8 |
| `drive-upload` | 15 |
| `user-import` | 11 |
| `permanent-delete-incoming` | 8 |
| `delete-document-attachment` | 1 |

Before the correction, GitHub Integration had drifted from the deployed code: `drive-upload` and `permanent-delete-incoming` had switched back to direct Google Drive OAuth, while Production uses the school's Apps Script Bridge. The repository also allowed 25 MiB even though the deployed bridge and Production validator enforce 20 MiB.

The Integration branch was corrected using the exact source returned by the deployed Production Edge Functions. At commit `c053322a96c1188d3ba8b918ec6c125b6b1744c6`, all **10 deployed source files across the 5 functions compare byte-for-byte identical** with the Integration branch. The 20 MiB cap and Thai UI error text/tests were aligned. No Edge Function was deployed or replaced in Production.

## CI evidence

At Integration commit `4e5481206d638d5ac42eae96692c38c8857e0907` on 2026-10-31, all eight required CI workflows passed. The Workflow RPC Security job ran 12 SQL test files / 104 assertions successfully. The leave schema/RLS job ran the 12 leave SQL regression files against disposable PostgreSQL 17; the Supabase snapshot/replay job ran on an isolated local Supabase database. Drive Upload CI passed 32 Deno unit tests across Apps Script Bridge error mapping, cleanup policy, the 20 MiB file limit, and user-import authorization/normalization. Schema Recovery PostgreSQL Replay and Recovered Catalog Fixture CI both passed after aligning the applied Production migration filename and its regression assertion. Frontend Build CI passed the main-only deployment guard assertion.

A follow-up hardening change on Integration:
- restricts the GitHub Pages deployment job to `refs/heads/main`, preventing a manual `workflow_dispatch` on a feature branch from publishing that branch;
- adds `.github/workflows/deploy.yml` to Frontend Build CI path filters so changes to the deployment workflow trigger a pull-request build.

The deployment guard is on the Draft PR branch only and is not active on `main` until reviewed and merged.

## Release blockers that remain

1. **Foundation source recovered.** Exact SQL for Production migration `20261007133831` is archived at `recovery/production-migrations/20261007133831_foundation_schema_rbac_rls.sql` and its isolated PostgreSQL 17 replay passed. Full evolved Production catalog parity remains to be proven, including ownership, grants, default ACLs, extensions, Auth/Storage objects, views, triggers, and publication settings.
2. **All 76 Production migration ledger SQL statements recovered and archived read-only** on the Integration branch: individual archives plus `production-ledger-batch-01.md` and `production-ledger-batch-02.md`. A fresh normalized-name comparison found 42 exact filename-stem matches and 34 Production names without an exact current filename match; candidate historical files need SQL/effect comparison before the rows can be reconciled. The archives are evidence only and must not be copied into `supabase/migrations`, executed, or migration-repaired.
3. Complete the leave policy implementation for school holidays, service history, carry-over balances, childcare subtype, prior-use checks, and evidence/eligibility rules. The school-wide leave policy must remain draft and calculation-disabled until approved.
4. Complete browser E2E using school accounts and verify deployed notification/Realtime delivery and real role authorization.
5. Review the 18 callable SECURITY DEFINER functions and the 4 no-policy RLS tables in the live role context; keep direct table access denied where intended.
6. Plan Auth leaked-password protection and recovery UX; rehearse backup/rollback; verify the actual hosting/billing configuration remains 0 baht.
7. Obtain a final school acceptance decision and an approved maintenance window before any Production rollout.

**Release decision: NOT APPROVED. Keep PR #55 Draft. Keep Production unchanged.**


## 2026-11-02 Production migration ledger recovery update

- Read-only query returned all 76 applied Production history rows; each row contains exactly one recorded SQL statement. All statement text has been archived outside `supabase/migrations` under `recovery/production-migrations/`.
- Archive set includes the exact Foundation source, individual SQL archives for the recovered early entries, and two consolidated archives covering the remaining ledger rows. Each archive is labeled as already-applied Production source and not executable rollout input.
- Current normalized comparison against the Integration `supabase/migrations` directory: 76 Production ledger entries, 87 repository migration SQL files, 42 exact normalized name matches, 34 Production ledger names without an exact filename match, and 45 repository filename stems not exactly represented in Production history. Similar names are candidates only; no mapping is accepted without SQL/effect review.
- This closes the **missing historical SQL evidence** gap, not the migration reconciliation or current catalog parity gate. No Production DDL/DML, migration repair, function deployment, merge, or Pages deployment was performed.


## 2026-11-02 latest CI and live Production leave readiness spot-check

- On Integration head `863df5645026be7d65749173d9223ad865aa0a37`, all 8 required workflows completed successfully: Frontend Build, Staff Leave Schema RLS, School Responsibility Settings, Schema Recovery PostgreSQL Replay, Supabase Snapshot and Staff Leave Replay, Drive Upload, Workflow RPC Security, and Recovered Catalog Fixture CI.
- Read-only live Production SQL spot-check (project `iigzzwyfxxtqbgjawyom`) returned: 76 applied migration ledger rows; `staff-leave-private` Storage bucket absent (0); `public.notifications` absent from `supabase_realtime` publication (0); `public.staff_leave_director_absences` table absent (0); and `public.staff_leave_attachments` table absent (0).
- These findings confirm that staff-leave private file storage, Realtime notification publication, and Director-absence evidence workflow are not deployed in Production. Do not claim these capabilities are live or expose a go-live path for staff leave until secure implementations and browser/role tests are complete.
- Production project status remains `ACTIVE_HEALTHY`. No Production write, schema change, Storage bucket creation, publication change, merge, or deployment was performed.


## 2026-11-03 live read-only refresh

A fresh read-only inspection was performed against Production project `iigzzwyfxxtqbgjawyom` on 2026-11-03. No SQL write, migration, repair, Storage write, project-setting change, or deployment was performed.

- Project status: `ACTIVE_HEALTHY`; Postgres `17.11.0.003`; region `ap-southeast-1`.
- Migration ledger: 76 entries.
- Public catalog inventory: 29 relations (27 tables/partitioned tables plus 2 other relation kinds), 27 RLS-enabled public tables, 50 public RLS policies, 34 public functions, 14 non-internal public triggers, 5 public enums, and 7 installed extensions.
- No public `staff_leave%` tables exist; private bucket `staff-leave-private` does not exist.
- `pg_publication_tables` currently returns zero published tables, including no `public.notifications` publication for Supabase Realtime. Therefore, any Production feature that depends on Realtime push delivery is not yet verified/live; in-app notification row creation and Realtime delivery must be treated as separate gates.
- Security Advisor refresh at 2026-11-03 01:42 UTC: 4 RLS-enabled public tables without policies (`department_role_permissions`, `system_settings`, `user_department_roles`, `user_departments`); 18 authenticated-callable SECURITY DEFINER functions; 1 anon-callable SECURITY DEFINER function (`get_public_school_name`, which is intentionally public but still needs explicit documented review); leaked-password protection disabled.
- Performance Advisor refresh: 10 unindexed foreign-key candidates, 25 unused-index candidates, and 7 multiple-permissive-policy warnings. These are review candidates, not authorization to automatically change indexes or policies.
- Direct table privilege inspection confirms the four no-policy tables remain row-blocked by RLS; two grant authenticated SELECT and two do not. Several other public tables have anon SELECT table grants while RLS policies are present; the effective row exposure must be tested with the anon role, not inferred from grants alone.

The current Integration branch contains draft-only Realtime publication and notification least-privilege migrations with CI fixture coverage. They have not been applied to Production. Before any Production activation, test the exact deployed notification UX and authorization with real school accounts, then confirm the intended publication membership and least-privilege grants. Keep the Production database unchanged until full parity, E2E, rollback, policy, and zero-cost gates pass.
