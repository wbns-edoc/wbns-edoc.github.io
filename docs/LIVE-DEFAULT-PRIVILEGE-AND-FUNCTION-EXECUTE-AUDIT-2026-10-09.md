# LIVE DEFAULT PRIVILEGE AND FUNCTION EXECUTE AUDIT — 2026-10-09

## Scope and safety
Read-only catalog inspection of Supabase project `wbns-edoc` (`iigzzwyfxxtqbgjawyom`). No SQL writes, grants, revokes, migrations, branch creation, data changes, or tests were performed. This is an evidence snapshot, not a claim that runtime exploitation was tested.

## Key finding: permissive default privileges in public
The live `pg_default_acl` catalog contains defaults for schema `public` owned by `postgres`:
- Functions (`defaclobjtype = f`): EXECUTE granted to `anon`, `authenticated`, and `service_role`.
- Tables (`r`): all listed table privileges (`arwdDxtm`) granted to `anon`, `authenticated`, and `service_role`.
- Sequences (`S`): `rwU` granted to those roles.

A second set of defaults is present for `public` under grantor `supabase_admin`, also granting function EXECUTE and broad table/sequence privileges to the API roles. The effective meaning of defaults depends on the role that creates each future object. These defaults do not, by themselves, prove every existing object is exposed, and RLS still applies to table access; however, they create a substantial risk that future objects inherit broader privileges than intended. This must be addressed through a carefully scoped, owner-approved privilege plan and tested against existing migrations/application behavior before any changes.

## Function privilege observations
The live effective privilege query reported:
- `private.allocate_document_number(uuid, integer)`, `private.has_permission(text)`, and `private.is_admin()` are SECURITY DEFINER and report effective EXECUTE for both `anon` and `authenticated`. Their explicit ACLs include PUBLIC EXECUTE (`=X`). `private` schema USAGE is false for `anon` and true for `authenticated`; therefore the ACL result alone does not establish that an anonymous API caller can reach these routines.
- `private.register_incoming_document(...)` and `private.register_outgoing_document(...)` are SECURITY DEFINER, have no explicit per-function ACL in the catalog result (default ACL applies), and report effective EXECUTE for `anon` and `authenticated`. The schema USAGE limitation for `anon` still applies.
- Public `register_incoming_document(...)` and `register_outgoing_document(...)` are SECURITY INVOKER and report effective EXECUTE for `anon` and `authenticated`; their explicit ACLs include PUBLIC and anon EXECUTE. Their runtime safety depends on the wrapper body, downstream routine checks, exposed-schema configuration, and request context. No invocation test was run.
- Public `set_updated_at()` also has PUBLIC/anon EXECUTE, but is typically a trigger helper; its actual risk depends on how it is used and whether it is API-exposed.
- Selected public admin and workflow RPCs have authenticated EXECUTE and no anon EXECUTE in the queried effective privilege result. Several remain SECURITY DEFINER and have separately documented behavior/drift concerns.

## Schema/API exposure limits
- Live schema ACL query: `private` USAGE is denied to `anon` and granted to `authenticated`; `public` USAGE is granted to both.
- A query against `pg_settings` for names matching `pgrst`, `exposed`, or `schema` returned no rows. This does **not** establish which schemas PostgREST exposes; the API's effective exposed-schema configuration remains unverified.
- No runtime calls were made using anon or authenticated tokens, and no user data was modified.

## Required remediation approach (design only)
1. Inventory the API-exposed schemas and identify object-creation roles before changing default ACLs.
2. Establish least-privilege defaults for future functions, tables, and sequences, separately for the actual object owner/creator roles; do not assume changing one role's defaults changes the other role's defaults.
3. Review existing object ACLs independently; default-privilege changes do not retroactively fix existing functions/tables.
4. Build per-function allowlists for intentional API RPCs; assess SECURITY DEFINER routines for caller authorization, fixed safe `search_path`, object/department scope, and lockout safeguards.
5. Verify wrappers and migration provenance, then run positive and negative tests with anon, authenticated users in each role, and service role only in an isolated environment that does not incur additional cost. Since no zero-cost isolated Supabase environment is confirmed, do not run potentially mutating tests against production.
6. Re-run Security Advisor and verify System Admin access remains intact before requesting release approval.

## Release status
**BLOCKED.** This audit adds a confirmed default-privilege risk to the existing migration/source drift, workflow-RPC, file-upload/RLS, authorization-test, backup/restore, and approval gates. No production fix was applied. Incremental spend remains constrained to **0 THB**; do not create a Supabase branch or project under the current cost constraint.
