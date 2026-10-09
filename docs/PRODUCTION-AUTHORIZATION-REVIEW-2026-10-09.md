# Production Read-Only Authorization Review — 2026-10-09
Status: **FINDINGS FOR REVIEW — NO PRODUCTION CHANGES MADE**
Project: `iigzzwyfxxtqbgjawyom`
Scope: read-only inspection of selected live function definitions and migration history.

## Confirmed observations
1. Supabase production migration history contains 26 entries; repository `main` contains 21 SQL migration files. A filename-level reconciliation report has been recorded separately.
2. Production function `public.admin_remove_user_role(uuid,uuid)` is SECURITY DEFINER. Its current function body checks whether the caller has `user.manage` or `role.manage`, then deletes the requested `user_roles` row. The function body itself does not include a check for the target role being `system_admin`, whether this is the last active administrator, or whether the caller is removing their own assignment. Triggers/constraints/other RPCs may provide additional controls and must be inspected before a final conclusion.
3. Production function `public.admin_set_user_role(uuid,uuid)` is SECURITY DEFINER. Its body checks `user.manage` or `role.manage`, validates that the target profile and role exist, then inserts the assignment. The function body itself does not show a special grant policy for `system_admin`; other controls may exist elsewhere.
4. Production function `private.set_document_deadline(uuid,uuid,timestamptz,timestamptz)` is SECURITY DEFINER and checks for an authenticated actor with `document.assign` permission and a future deadline before inserting a deadline. The inspected function body does not explicitly verify that the target document exists or that the specified user is currently assigned to it. Database foreign keys and other constraints may enforce some integrity; inspect them and test this in non-production.
5. Production function `private.assign_document(uuid,uuid,text,timestamptz)` checks the caller has `document.assign`, checks document existence and that the assignee profile is active, and creates an assignment, updates the document owner/status, creates a notification, and optionally inserts a deadline.
6. Security Advisor currently reports 10 warnings for SECURITY DEFINER functions callable by authenticated users and one warning for leaked-password protection. The warning is a triage signal, not proof that each RPC is exploitable: each function's authorization design must be reviewed.

## Priority follow-up
### P0 — Prevent administrator lockout
- Inspect all triggers, constraints, helper functions, service paths, and RPCs that mutate `user_roles` or deactivate profiles.
- Establish a transaction-safe invariant that at least one active, recoverable `system_admin` remains.
- Define and enforce who can grant `system_admin`, and how self-demotion/emergency recovery work.
- Test two concurrent removals as well as ordinary removal in an isolated database.

### P1 — Deadline integrity
- Verify foreign keys on `deadlines.document_id` and `deadlines.assigned_to`.
- Decide whether a deadline may only be created for an existing document and an active current assignee.
- If required by policy, enforce the rule in a forward-only migration and add negative tests for unrelated users/documents and inactive assignees.

### P1 — Function exposure and audit
- For every exposed SECURITY DEFINER function, confirm caller identity, permission checks, object-level authorization, fixed safe search path, minimal EXECUTE grants, and audit behavior.
- Do not blanket-revoke authenticated EXECUTE without tracing UI and workflow dependencies.
- Re-run the Security Advisor after approved changes.

## Guardrails
- This document records code inspection only; the authorization test matrix remains **not executed**.
- No Production schema, data, role assignment, Auth setting, or migration history was modified.
- Never remove/demote/deactivate the existing Production system administrator as a test.
- Do not deploy a remediation until the migration history is reconciled, a backup/restore is verified, and the change passes isolated non-production tests and school-owner review.
