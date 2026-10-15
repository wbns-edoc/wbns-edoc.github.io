# Schema replay dependency audit

Captured from read-only Production catalog inspection on 2026-10-15. This is an implementation note for recovery work, not a restore procedure.

## Verified dependency facts

The catalog currently contains 12 non-internal triggers across the captured public tables. Their trigger functions are:

| Trigger function | Schema | Required before CREATE TRIGGER |
|---|---|---|
| `audit_row_change()` | `private` | yes |
| `default_document_department()` | `private` | yes |
| `guard_document_department_change()` | `private` | yes |
| `set_updated_at()` | `public` | yes |

The current `relations-and-security.sql` snapshot creates triggers in the same file as tables, constraints, policies and views. The private/public function snapshots are separate files. Therefore a naive replay in the order `relations-and-security.sql` then function files is not valid: trigger creation can fail because the trigger functions have not yet been created. Reversing the entire order is also not valid because many functions reference the captured tables and enum types.

## Safe replay design

1. Create only a disposable PostgreSQL 17 service/container; do not connect this harness to Supabase Production.
2. Provision minimal Supabase compatibility objects required by captured SQL: roles used by policies/grants, `auth` schema and a test-only `auth.uid()` stub, and the exact extensions that are available in the test image.
3. Split the relation snapshot into dependency-aware phases, without changing the evidence snapshot itself:
   - enum types and table definitions;
   - constraints and indexes;
   - functions (private functions before public wrappers, while resolving any function-to-function cycles);
   - policies and triggers after their referenced functions exist;
   - views last, with `security_invoker=true` preserved.
4. Run the phases under `psql -v ON_ERROR_STOP=1` against a clean disposable database.
5. Treat any omitted grants, ownership, default privileges, extensions, auth/storage objects, or external dependencies as unresolved until independently captured and compared.

## Current status

- The catalog evidence and static assertions are passing.
- A clean PostgreSQL replay has **not** yet been proven.
- This report does not authorize applying any snapshot file to Production.
- Do not turn the snapshot into the replacement foundation migration until a replay harness passes and object/grant coverage has been reviewed.

## Next technical gate

Build a deterministic splitter/parser that classifies top-level statements from the snapshot into the phases above, then exercise it against a clean PostgreSQL 17 CI service. Prefer parsing-aware logic over fragile line-based splitting because function bodies and quoted strings contain semicolons. If a parser dependency is used, pin its version and lockfile.
