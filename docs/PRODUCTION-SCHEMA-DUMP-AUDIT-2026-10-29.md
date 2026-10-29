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
