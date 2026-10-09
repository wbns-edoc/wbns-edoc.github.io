# Migration Source Parity Review — 2026-10-09
Status: **RECONCILIATION REQUIRED — DO NOT DEPLOY**
Scope: read-only comparison of repository migration filenames on `main` with Supabase production migration history.
Reviewed: 2026-10-09

## Observed counts
- Repository `supabase/migrations/` contains 21 SQL files.
- Supabase production migration history contains 26 entries.
- Therefore, there is not a one-to-one filename/history match yet. This is not proof that the schema is wrong: timestamps and migration names can differ, and migrations may have been applied outside the current repository history. It is a release blocker until reconciled.

## Production history entries without an obvious same-name repository file
The following production history names did not have an obvious exact-name counterpart in the current repository filename list:
- `harden_rls_and_indexes`
- `document_registration_rpc`
- `seed_school_registers_2026`
- `audit_trail_v1`
- `reporting_views_v1`
- `admin_department_management_v1`
- `harden_admin_department_rpc_execute_v2`

Some may be represented by later consolidated or renamed migrations. Verify by comparing SQL definitions and checksums, not by filename alone.

## Repository files with no obvious same-name production history entry
- `harden_workflow_rpc`
- `bootstrap_initial_system_admin_v1`

These may have been applied under different names, intentionally omitted, or remain unapplied. Confirm from SQL contents, deployment records, and live schema before taking action.

## Safe next steps
1. Retrieve authoritative migration SQL from the production deployment records or a trusted backup. Do not extract secrets or sensitive records.
2. Compare each repository SQL file against production migration history and relevant live schema objects. Produce a mapping of repo filename -> production version/name -> checksum -> status.
3. For unmatched production history, recover the original SQL into a clearly marked archive or reconstructed migration only after provenance review; never silently fabricate historical migration files or mark them applied.
4. For repository-only files, verify whether their effects exist in the live schema. Do not replay on Production.
5. Apply any corrective migration only as a new forward-only migration, after testing on an isolated non-production database and review/approval.
6. Keep the existing Production administrator role assignment unchanged throughout this work.

## Related known security triage
The Supabase Security Advisor still reports 10 exposed `SECURITY DEFINER` RPC warnings and a leaked-password-protection warning. These are triage findings requiring per-function authorization review; do not blanket-revoke function access because application workflows may rely on intended RPCs.

## Release gate
**Not approved for Production deployment** until migration parity, backup/restore, role-lockout protection, negative authorization tests, and owner acceptance are evidenced.
