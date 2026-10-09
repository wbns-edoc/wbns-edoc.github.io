# Follow-up Integrity Review — 2026-10-09
Status: **READ-ONLY FINDINGS; NO PRODUCTION CHANGES**
Target: Supabase production project `iigzzwyfxxtqbgjawyom`.

## Trigger inventory
Read-only catalog inspection found audit triggers on `public.deadlines` and `public.document_assignments`, and an updated-at trigger on `public.profiles`. No non-internal trigger attached directly to `public.user_roles` appeared in the selected table trigger inventory. This means the selected inventory did not show a row-level trigger on `user_roles` enforcing the last-administrator invariant; a complete search of all functions, constraints, and other mutation paths is still required.

## Foreign-key inventory
The live catalog confirms these relationships:
- `deadlines.assigned_to -> profiles.id`
- `deadlines.document_id -> documents.id`
- `document_assignments.assigned_by -> profiles.id`
- `document_assignments.assignee_id -> profiles.id`
- `document_assignments.document_id -> documents.id`
- `user_roles.assigned_by -> profiles.id`
- `user_roles.role_id -> roles.id`
- `user_roles.user_id -> profiles.id`

These foreign keys protect referential integrity (preventing references to nonexistent rows where constraints are enforced), but they do not by themselves prove that an assignee is active, that a user is authorized for a particular document, or that at least one system administrator remains.

## Risk interpretation
### P0 — Last active administrator
The selected live `admin_remove_user_role` body deletes a role assignment after checking the caller's permission, but does not itself check whether this is the final `system_admin` assignment. The selected trigger inventory did not show a trigger on `user_roles` enforcing this invariant. Inspect every write path and effective permissions before making a final determination. Implementing a reliable invariant must account for concurrent transactions and profile deactivation, not only one RPC.

### P1 — Deadline target validation
Foreign keys ensure the referenced document/profile rows exist, but a foreign key does not ensure `profiles.is_active = true` or that the target profile is an assignee of that document. Decide the intended policy and test negative cases in a disposable test environment.

### P1 — Auditability
Audit triggers exist for deadlines and document assignments. The selected inventory did not show a corresponding trigger on `user_roles`; determine whether role changes are audited elsewhere (RPC inserts, event tables, database logs) and ensure grant/revoke outcomes are attributable to actor, target, role, time and outcome.

## Required non-production tests
- Attempt to remove the last `system_admin` through each supported path.
- Concurrently attempt two removals that could leave zero administrators.
- Attempt to assign a deadline to an inactive but existing profile.
- Attempt to create a deadline for a document where the profile is not an active assignee.
- Verify role grant/revoke audit records and ensure failures do not mutate state.

## Guardrails
- Read-only catalog inspection only; no Production data, schema, role, Auth configuration, or migration history was changed.
- Do not execute destructive tests in Production.
- Keep the existing Production system administrator assignment untouched.
- No test result should be marked passed until run against an isolated non-production database.
