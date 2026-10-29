# Production schema dump audit — 2026-10-29

## Purpose and safety boundary

This is a read-only structural audit of the user-provided `wbns-production-schema.sql` file. It is an inventory of the dump, **not** proof that the dump can be replayed successfully or that it exactly matches the live Production database. No Production database changes were made.

The SQL file must remain an audit/recovery artifact and should not be committed into this repository or replayed against Production. Test replay only in an isolated local/test database after prerequisites and extension/auth dependencies are resolved.

## File identity

- File: `wbns-production-schema.sql`
- Size: 200,854 bytes
- Lines: 4,777
- SHA-256: `cc01f34cecef7d11379f52219d6937fd505fbb0dc43d91990933ef664eef9ead`

## Object inventory detected by text scan

| Object | Count |
|---|---:|
| ENUM types in `public` | 5 |
| Tables in `public` | 27 |
| Tables in `private` | 0 |
| Functions in `public` | 34 |
| Functions in `private` | 27 |
| RLS policy declarations | 50 |
| Views in `public`/`private` | 2 |
| `CREATE TRIGGER` statements | 0 |
| Index declarations | 48 |
| `ADD CONSTRAINT` declarations | 88 |

The five public ENUMs found are `approval_decision`, `assignment_status`, `document_status`, `document_type`, and `urgency_level`.

The two views found are `document_monthly_summary` and `document_report_summary`.

## Important findings and release gates

1. **The dump contains `public.document_status`.** This helps explain why a later migration that references this type fails when the historical foundation migration is only a placeholder. It does not by itself reconstruct the original migration chronology.
2. **No leave-module objects were detected by a text scan.** No `staff_leave*`, `leave_requests`, or `leave_types` names were found. The dump therefore does not establish that the staff-leave module exists in this schema.
3. **No `CREATE TRIGGER` statements were detected.** Because prior recovery notes describe triggers in the live catalog, determine whether this dump omitted trigger DDL or whether triggers are defined another way before treating it as a complete recovery artifact.
4. **This is a snapshot, not a verified historical migration chain.** Do not replace the missing foundation migration with this dump or label it as the original migration. Reconstruct chronology only from trusted migration history and a clean replay comparison.
5. **Dependencies need explicit validation.** The dump references Supabase-specific schemas/functions such as `auth.uid()` and `extensions`. An isolated replay must provide compatible prerequisites, role/ownership handling, and required extensions.
6. **Counts are text-scan counts.** They are not a SQL parser result, do not prove semantic validity, and must be checked against catalog queries after replay.

## Recommended next steps

- Preserve the dump and its hash as a recovery reference; do not expose secrets or user document data.
- Obtain a fresh schema-only export from the trusted Production owner environment if possible, including functions, triggers, policies, grants, sequences, and extensions.
- Reconcile the fresh export with this file and the live migration history.
- Create an isolated, zero-cost local PostgreSQL/Supabase test environment and replay the dump there; capture the first error and resolve it without touching Production.
- Separately rebuild and verify the historical migration chain from the earliest trusted baseline.
- Run the document-module regression and security tests before any Production release.
- Keep the staff-leave PR in Draft until the schema, handbook day-counting, approval routing, notifications, cancellation, dashboards, end-to-end tests, and rollback rehearsal pass.

## Status

**Audit completed; replay and Production equivalence are not yet verified. Production was not changed.**

## Live migration-history cross-check — 2026-10-29

A read-only call to Supabase migration history for Production project `iigzzwyfxxtqbgjawyom` returned a recorded foundation migration at version `20261007133831` named `foundation_schema_rbac_rls`, followed by `harden_rls_and_indexes`, `document_registration_rpc`, `seed_school_registers_2026`, and `workflow_engine_v1`. The recorded history continues through `20261017074815` (`support_be_incoming_register_numbers`).

The checked-in local file `supabase/migrations/20261007200000_foundation_schema_rbac_rls.sql` contains only a comment saying the full SQL is maintained in the migration applied to Supabase, plus a note that the file is the version-controlled source. It does **not** contain the foundation DDL. The local filename timestamp also differs from the recorded Production migration version.

### Interpretation

- The live migration ledger proves that the foundation migration is recorded as applied; it does not recover the original SQL body.
- The schema dump includes `public.document_status`, while the checked-in foundation file does not create it. A clean replay from the checked-in migration chain is therefore not demonstrated and is known to fail when later workflow SQL expects that type.
- Do not fabricate or backfill the missing foundation SQL from the dump and label it as the historical original. Any reconstructed baseline must be explicitly marked as reconstructed, reviewed against the live catalog, and validated in an isolated database.
- No Production migration was applied and no Production data was modified during this cross-check.

### Next safe gate

Request/export a fresh **schema-only** snapshot from the trusted Production owner environment, including types, tables, sequences, functions, triggers, policies, grants, and extensions; compare it to the supplied dump and current live catalog. Then perform clean replay only in an isolated zero-cost local environment and document semantic/catalog parity before considering release.


## Live catalog trigger cross-check — 2026-10-29

A read-only query against the live Production catalog returned **14 non-internal triggers in schema `public`**, while the supplied dump text scan found zero `CREATE TRIGGER` statements. This is a concrete mismatch that must be resolved before the dump is treated as a complete recovery artifact.

| Table | Trigger | Operation | Function |
|---|---|---|---|
| `approvals` | `audit_approvals` | AFTER INSERT/UPDATE/DELETE | `private.audit_row_change()` |
| `deadlines` | `audit_deadlines` | AFTER INSERT/UPDATE/DELETE | `private.audit_row_change()` |
| `departments` | `departments_updated_at` | BEFORE UPDATE | `public.set_updated_at()` |
| `document_assignment_reports` | `trg_assignment_reports_set_updated_at` | BEFORE UPDATE | `public.set_updated_at()` |
| `document_assignments` | `audit_document_assignments` | AFTER INSERT/UPDATE/DELETE | `private.audit_row_change()` |
| `document_files` | `audit_document_files` | AFTER INSERT/UPDATE/DELETE | `private.audit_row_change()` |
| `documents` | `audit_documents` | AFTER INSERT/UPDATE/DELETE | `private.audit_row_change()` |
| `documents` | `documents_default_department` | BEFORE INSERT | `private.default_document_department()` |
| `documents` | `documents_guard_department_change` | BEFORE UPDATE OF department_id | `private.guard_document_department_change()` |
| `documents` | `documents_updated_at` | BEFORE UPDATE | `public.set_updated_at()` |
| `incoming_document_details` | `trg_notify_leadership_on_incoming_registration` | AFTER INSERT | `private.notify_leadership_on_incoming_registration()` |
| `number_sequences` | `number_sequences_updated_at` | BEFORE UPDATE | `public.set_updated_at()` |
| `profiles` | `profiles_updated_at` | BEFORE UPDATE | `public.set_updated_at()` |
| `senders` | `senders_updated_at` | BEFORE UPDATE | `public.set_updated_at()` |

The live catalog definitions for the trigger functions were also read without changing the database. Important dependencies include audit-log insertion, active-profile department defaults, system-admin-only department changes, and notifications to director/deputy-director users when an incoming registration is inserted.

A separate live catalog count returned 27 public tables, 34 public functions, 27 private functions, 50 public policies, 14 public triggers, 2 public views, 5 public enum types, 86 public indexes, 98 public constraints, and 7 installed extensions (extension count is database-wide). These are live catalog counts, not a claim of parity with the supplied dump; differences in counting scope and SQL text patterns need object-by-object reconciliation.

### Release implication

Do not replay the supplied dump as a complete backup or use it to overwrite a baseline. Obtain a trusted schema-only export including trigger DDL, compare object definitions, then verify a clean replay and catalog parity in an isolated zero-cost environment. Production remains unchanged.
