# October 10 fixture vs October 15 Production catalog — drift report

Updated: 2026-10-15  
Scope: read-only textual inventory comparison; this is not a semantic schema diff and does not authorize deployment.

## Sources compared

- Historical test fixture on `main`: `supabase/tests/fixtures/recovered-production-catalog.sql`
  - Blob SHA: `bec1ab334cd2b9896d1a800b68a1bbbbeccb63ac`
  - Header says it was generated 2026-10-10 and is test-only; it contains an explicit test-only patch to `attach_document_file_version`.
- October 15 catalog evidence on branch `recovery/production-schema-catalog-2026-10-15`:
  - `catalog/relations-and-security.sql`, blob SHA `d57c1b2fa617ea28308908e258ff614e5046150f`
  - `catalog/private-functions.sql`
  - `catalog/public-functions.sql`

## Inventory comparison (name-level only)

| Object class | Oct 10 fixture | Oct 15 recovered artifacts | Result |
|---|---:|---:|---|
| Public/private tables detected by CREATE TABLE text | 22 | 25 | Three current tables are absent from the fixture |
| Functions detected by CREATE FUNCTION text | 28 | 50 | The current artifacts include 22 function names not found in the fixture |
| Public enum types detected by CREATE TYPE AS ENUM text | 0 | 5 | The fixture parser/count is not a reliable enum inventory for this comparison; use the Oct 15 catalog capture as the current evidence |
| Views detected by CREATE VIEW text | 0 | 2 | The fixture representation does not match the simple CREATE VIEW pattern; do not infer view absence from this count |
| Production migration ledger rows | — | 55 | GitHub main contains 31 migration SQL files, with multiple missing historical sources |

### Current tables missing from the Oct 10 fixture

- `public.department_role_permissions`
- `public.user_department_roles`
- `public.user_departments`

These are significant because department-scoped role permissions and multi-department membership are core authorization features. The Oct 10 fixture cannot be used as the current clean-install baseline without a reviewed reconstruction.

### Function names present in the Oct 15 artifacts but not detected in the Oct 10 fixture

- `private.admin_get_user_department_memberships_impl`
- `private.admin_set_user_department_membership_impl`
- `private.can_access_document`
- `private.default_document_department`
- `private.delete_incoming_document`
- `private.finalize_permanent_delete_incoming_document`
- `private.guard_document_department_change`
- `private.has_department_permission`
- `private.has_document_wide_read_role`
- `private.prepare_permanent_delete_incoming_document`
- `private.user_has_department`
- `public.admin_get_department_permission_catalog`
- `public.admin_get_user_department_memberships`
- `public.admin_get_user_department_roles`
- `public.admin_set_department_role_permission`
- `public.admin_set_global_user_role`
- `public.admin_set_user_department_membership`
- `public.admin_set_user_department_role`
- `public.delete_incoming_document`
- `public.finalize_permanent_delete_incoming_document`
- `public.list_deleted_incoming_documents`
- `public.prepare_permanent_delete_incoming_document`

This is a name-level comparison only. A function missing by name may reflect later functionality, a different signature, or a parser limitation; function bodies, overloads, privileges, dependencies, and behavior must be compared before any candidate is accepted.

## Decision

1. **Do not use the October 10 fixture as the clean-install baseline.** It is stale for at least the three current tables and the department-membership/security function set, and it contains a test-only function patch.
2. **Do not apply the October 15 snapshots directly to Production.** They capture current definitions but do not fully establish owners, grants, default ACLs, all platform objects, extension setup, Auth/Storage compatibility, or historical migration ordering.
3. Use the Oct 15 artifacts as the current evidence source, and reconstruct a separate candidate baseline in a new isolated path. Keep the production migration chain untouched until a clean Supabase replay and full catalog/security parity review pass.
4. Continue collecting exact definitions and dependency/privilege evidence for missing historical changes. Do not invent SQL based only on migration names.

## Validation status

- The inventory comparison was generated from repository files with read-only fetches; no database write was performed.
- Latest disposable PostgreSQL replay: [run 38757712321](https://github.com/wbns-edoc/wbns-edoc.github.io/actions/runs/38757712321) — PASS.
- Latest snapshot CI: [run 38757712729](https://github.com/wbns-edoc/wbns-edoc.github.io/actions/runs/38757712729) — PASS.
- Full Supabase clean-install parity: NOT PROVEN.
- Production migration reproducibility: BLOCKED.
- Production deployment: NOT APPROVED.
