# Follow-up catalog audit — 2026-10-15

## Scope
Read-only catalog/privilege checks against Production project `iigzzwyfxxtqbgjawyom`. No database writes were performed.

## Recovery snapshot completeness checks
- 25 tables in `public` (no tables without RLS were found in the selected `public`/`private` schemas).
- 45 RLS policies; all observed policy roles are `authenticated` (zero policies explicitly target `anon` or `PUBLIC`).
- 26 `private` functions and 28 `public` functions were captured.
- The identity/generated-column query returned no identity or generated columns in the selected schemas.
- The sequence inventory query returned no sequences owned by objects in the selected schemas.
- 7 installed extensions were observed, including `pg_trgm`, `pgcrypto`, and `uuid-ossp` in `extensions`, plus platform extensions in managed schemas. Extension installation/configuration is not represented by the relation snapshot.
- The recovery relation script includes table constraints, non-constraint indexes, RLS flags, policies, triggers, and view definitions. It remains a catalog-derived reconstruction, not a validated `pg_dump`.

## Security observations requiring a separate reviewed fix
1. `information_schema.role_table_grants` reports grants to role `anon` on 24 public relations (168 privilege entries). This alone does **not** prove data exposure because RLS is enabled and the 45 policies target `authenticated`, but it is broader than the principle of least privilege and should be reviewed.
2. Both `public.document_monthly_summary` and `public.document_report_summary` have SELECT privilege for `anon` and `authenticated`. They aggregate document counts by month/type/status/urgency. Confirm whether these summaries are intended to be public; otherwise, revoke anonymous access and consider `security_invoker=true` after testing.
3. Four functions appear executable by `anon`/PUBLIC in the privilege check: `private.allocate_document_number(uuid, integer)`, `private.has_permission(text)`, `private.is_admin()`, and `public.set_updated_at()`. The `private` schema has no USAGE for `anon` or PUBLIC, so its functions should not be directly addressable by anonymous API clients despite inherited EXECUTE. `set_updated_at()` is a trigger helper. Explicit least-privilege grants/revokes should be validated against the app and all triggers before a migration is drafted.
4. All 25 public tables have RLS enabled, but the two views are not themselves RLS-enabled (ordinary views are not tables). Their view-owner/security-invoker behavior needs explicit inspection.

## Recommended next step
Before changing grants, inspect the exact view relation options and schema/API exposure; verify whether anonymous REST requests can query these views in a controlled test. Then prepare a narrowly scoped security migration and regression tests. Do not apply any grant/revoke change to Production based only on this report.

## Important
This report is evidence, not a change request and not a production migration. No secrets or row-level school data were exported.
