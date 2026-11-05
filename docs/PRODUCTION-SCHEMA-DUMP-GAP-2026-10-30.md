# Production schema dump vs recovered CI fixture — 2026-10-30

Status: **evidence only; not a deployable baseline**.

## Evidence retained

The user-provided `wbns-production-schema.sql` is retained in the private ChatGPT Library and is intentionally **not copied into this public repository**. It is 200,854 bytes / 4,777 lines and was statically audited on 2026-10-28.

Static inventory from that audit:

- 28 table definitions
- 5 enums
- 2 views
- 69 function definitions / 63 unique signatures
- 14 triggers
- 48 indexes
- 50 RLS policies
- 213 GRANT statements / 63 REVOKE statements
- 104 ownership statements
- 18 ALTER DEFAULT PRIVILEGES statements
- no CREATE EXTENSION, COPY, or INSERT INTO statements

The dump includes references to Supabase-managed `auth.users`. It starts with `SET check_function_bodies = false`, so loading it successfully would not prove that every function body executes. The dump does not create extensions; extension availability and schema placement must be supplied and verified separately.

## Recovered fixture is older and is not exact Production parity

The repository fixture `supabase/tests/fixtures/recovered-production-catalog.sql` was generated on 2026-10-10. The October 15 recovery replay evidence recorded 25 public tables, 5 enums, 45 policies, 12 non-internal public triggers, 54 public/private functions, and 2 views.

The October 28 static dump audit records 28 tables, 50 policies, 14 triggers, and 69 function definitions. These date-stamped inventories are not a row-by-row diff, and the count differences do not identify which exact objects are missing. They do establish that the recovered fixture cannot be described as an exact copy of the later Production schema.

The current Recovered Catalog Fixture CI remains valuable: it checks that the recovered October 10 fixture plus selected forward migrations can be applied in a disposable local Supabase stack and that selected regression suites pass. It does **not** prove full October 28 Production parity.

## Security observations requiring review

- The dump has RLS enabled on 27 public tables.
- The static policy scan found 50 policies and no policy targeting `anon` or `PUBLIC`.
- The dump nevertheless contains broad `GRANT ALL` statements to `anon` on multiple public tables. RLS may deny access in the absence of applicable policies, but effective privileges and policy behavior must be verified in the disposable Supabase replay and against fresh read-only Production evidence. Do not assume the GRANT statements are harmless.
- Ownership, default privileges, extensions, Supabase Auth/Storage dependencies, and function execution privileges all require review.

## Release gate

1. Keep the private SQL dump private; do not commit it to this public repository.
2. Do not replace `20261007200000_foundation_schema_rbac_rls.sql` with this current-state dump.
3. Reconstruct a separately named candidate baseline and replay it in a fresh local Supabase stack.
4. Compare tables/columns/types/constraints/indexes/functions/triggers/views/RLS policies, owners, grants, default ACLs, extension configuration, and Auth/Storage dependencies.
5. Reconcile every Production migration-history row with exact SQL or a reviewed recovery source.
6. Keep Production unchanged until the replay, parity comparison, authorization tests, handbook policy validation, and rollback review all pass.

No Production write, migration, repair, merge, or deployment was performed as part of this evidence review.
