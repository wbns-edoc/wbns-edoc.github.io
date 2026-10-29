# Read-only Production catalog checkpoint — 2026-10-29

## Scope and safety

Collected from the Supabase Production project `iigzzwyfxxtqbgjawyom` using read-only catalog queries on 2026-10-29. This report is evidence only; it contains no row-level user/document data and no secret values. No Production writes were performed.

## Enum types observed in Production

The `public` schema currently contains these enum types and labels:

- `approval_decision`: `pending`, `approved`, `rejected`, `returned`
- `assignment_status`: `assigned`, `accepted`, `in_progress`, `completed`, `cancelled`
- `document_status`: `draft`, `pending_approval`, `approved`, `received`, `registered`, `assigned`, `in_progress`, `completed`, `archived`, `sent`, `cancelled`
- `document_type`: `incoming`, `outgoing`
- `urgency_level`: `normal`, `urgent`, `very_urgent`, `critical`

This confirms the `document_status` enum exists in live Production. It does not recover the original Foundation SQL or prove a clean migration replay.

## Staff leave schema checkpoint

A read-only information_schema query found no `public` table whose name contains `leave` at the time of this check. The `public.notifications` table does exist.

Implication: staff-leave work tracked in draft PRs #46/#47 and related branches has not been deployed as public leave tables in Production. Do not describe the leave module as Production-ready or enable submissions until the schema, approval route, notifications, UI, and policy rules have been fully validated and deployed through an approved release.

## Release interpretation

- Production catalog evidence is useful for comparison but is not a canonical migration source.
- The repository Foundation migration remains a placeholder.
- The generated `supabase/tests/fixtures/recovered-production-catalog.sql` remains test-only and includes test-specific patches.
- Do not apply the fixture or guessed DDL to Production.
- Required next gate: recover trusted source SQL, replay in an isolated Supabase environment with fail-fast settings, compare catalog/security state, run end-to-end tests, verify backup/rollback, and obtain explicit release approval.

**Status: Production remains unchanged. Clean replay and staff-leave release are not yet verified.**
