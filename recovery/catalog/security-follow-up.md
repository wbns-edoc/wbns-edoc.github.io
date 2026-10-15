# Follow-up catalog audit — 2026-10-15

## Scope
Read-only catalog/privilege checks against Production project `iigzzwyfxxtqbgjawyom`. No database writes were performed.

## Recovery snapshot completeness checks
- 25 tables in `public`; no tables without RLS were found in the selected `public`/`private` schemas.
- 45 RLS policies; observed policy roles are `authenticated` (zero policies explicitly target `anon` or `PUBLIC`).
- 26 `private` functions and 28 `public` functions were captured.
- No identity/generated columns were found in the selected schemas; no sequences owned by objects in the selected schemas were found.
- 7 installed extensions were observed, including `pg_trgm`, `pgcrypto`, and `uuid-ossp` in `extensions`, plus platform extensions in managed schemas. Extension installation/configuration is not represented by the relation snapshot.
- Both public views explicitly have `security_invoker=true`; this option must be retained when rebuilding them because it ensures underlying privileges/RLS are checked as the invoking role.
- The relation script includes table constraints, non-constraint indexes, RLS flags, policies, triggers, and view definitions. It remains a catalog-derived reconstruction, not a validated `pg_dump`.

## Security observations requiring a separate reviewed fix
1. `information_schema.role_table_grants` reports grants to role `anon` on 24 public relations (168 privilege entries). This alone does **not** prove data exposure: all 25 public tables have RLS enabled, and no policies explicitly target `anon`/PUBLIC. However, these broad table grants are wider than least privilege and should be compared with the app's actual needs before any revocation.
2. Both `public.document_monthly_summary` and `public.document_report_summary` have SELECT privilege for `anon` and `authenticated`. They aggregate document counts by month/type/status/urgency. Both views are configured with `security_invoker=true`, so their underlying queries should respect the caller's table privileges and RLS. Since no anonymous-targeted RLS policies were found, this is not by itself proof of a data leak. Still, confirm public summaries are intended and test anonymous access before making changes.
3. Four functions appear executable by `anon`/PUBLIC in the privilege check: `private.allocate_document_number(uuid, integer)`, `private.has_permission(text)`, `private.is_admin()`, and `public.set_updated_at()`. The `private` schema has no USAGE for `anon` or PUBLIC, so the three private functions should not be directly addressable by anonymous API clients despite inherited EXECUTE. `set_updated_at()` is a trigger helper. Explicit least-privilege grants/revokes should be validated against the app and triggers before drafting a migration.
4. Catalog shows broad default ACLs for future objects in `public` from both `postgres` and `supabase_admin`, including grants to `anon`, `authenticated`, and `service_role`. Treat as a review item, not an instruction to revoke platform-managed defaults blindly.

## Recommended next step
Inspect actual anonymous REST behavior in a controlled test environment, verify the app's reliance on table/view/function grants, and then prepare a narrowly scoped security migration with regression tests. Do not apply grant/revoke changes to Production based only on this report.

## Important
This report is evidence, not a change request and not a production migration. No secrets or row-level school data were exported.
