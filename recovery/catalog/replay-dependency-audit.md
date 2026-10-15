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

The `relations-and-security.sql` snapshot mixes table definitions, constraints, indexes, RLS, policies, triggers, views, and view options. A naive replay of this file as one unit before the function snapshots can fail when trigger creation references functions not yet created. Applying all functions first can also fail because functions refer to captured types and tables.

## Disposable replay harness

The branch now includes:

- `tests/schema-recovery-replay.test.py`: uses pinned `pglast==7.10` to parse top-level statements and generate dependency phases. It does not execute SQL.
- `tests/schema-recovery-replay-bootstrap.sql`: minimal compatibility objects for a disposable database only; its `auth.uid()` stub reads the test JWT subject setting and is not a full Supabase Auth implementation.
- `tests/schema-recovery-rls-behavior.sql`: isolated regression checks for System Admin/director access, parent/subgroup boundaries, and multi-department membership.
- `.github/workflows/schema-recovery-postgres-replay.yml`: starts an isolated PostgreSQL 17 service, generates phases, replays them with `ON_ERROR_STOP=1`, and checks the expected object counts.

The intended phase order is:

1. enum types;
2. table definitions;
3. constraints;
4. indexes;
5. PL/pgSQL functions;
6. SQL/other functions;
7. RLS enablement;
8. policies;
9. triggers;
10. views and view options.

The generated SQL includes a warning header and is for disposable replay only. Do not connect this workflow to Production or use the generated files as a migration.

## Known limitations / acceptance criteria

A passing run would prove only that the captured statements can be replayed against this particular disposable PostgreSQL harness with the expected counts. It would **not** prove complete equivalence to Supabase Production. In particular, the current harness does not yet establish fidelity for ownership, grants, default privileges, extension configuration, Auth/Storage internals, publication settings, external dependencies, or all runtime behavior.

Before the snapshot can replace the placeholder foundation migration, the team must:
- verify the replay workflow is green and inspect any failures rather than assuming success;
- compare object definitions and security settings against a fresh read-only Production catalog export;
- resolve function dependencies/cycles and any platform-specific objects;
- add least-privilege grant/default-privilege evidence and review;
- add behavior tests for RLS and the required admin/principal and department/subgroup access rules;
- keep the recovery PR draft until those gates pass and a reviewed, reproducible migration is prepared.

## Current status

- Catalog evidence and static assertions have passed.
- On 2026-10-15, disposable PostgreSQL 17 replay completed successfully, including the object-count inventory checks (25 public tables, 5 public enums, 45 policies, 12 non-internal public triggers, 54 non-extension-owned public/private functions, and 2 public views).
- The replay workflow passed the isolated behavior test for admin/director access, parent/subgroup visibility boundaries, and users with multiple department memberships on the latest corrected test commit `e1e2417f714dde994ece54f8d938026611579e86` (run [38752648315](https://github.com/wbns-edoc/wbns-edoc.github.io/actions/runs/38752648315)). Earlier run `38748131969` covered the base behavior checks before the multi-membership assertion was added.
- This successful replay proves that the captured statements can be replayed in the compatibility harness; it does **not** establish full schema parity with Production or faithful Supabase Auth/Storage/runtime behavior.
- The follow-up CI assertions for RLS enabled on every public table, `security_invoker=true` on both public views, and no policies targeting anon/PUBLIC passed on 2026-10-15 (static snapshot CI run `38748132095`; replay run `38748131969`). Treat this as evidence for the captured snapshot only, not proof of full Production parity.
- No Production schema changes are authorized or performed by this recovery work.
