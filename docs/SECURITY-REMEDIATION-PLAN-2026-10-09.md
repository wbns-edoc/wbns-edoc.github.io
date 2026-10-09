# Security Remediation Plan — Release Gate Review
Date: 2026-10-09
Status: **PLAN ONLY — NOT A PRODUCTION CHANGE**
Branch: `security/release-gate-review-2026-10-09`

## Safety invariants
- Do not modify Production schema, data, Auth settings, migration history, or role assignments as part of this plan.
- Never remove, demote, deactivate, or alter the existing Production `system_admin` assignment during testing.
- Do not merge or deploy this branch to Production until migration source parity, backup/restore, non-production testing, and school-owner approval are documented.
- Do not expose service-role keys, database credentials, backups, or sensitive school records in GitHub.

## Evidence reviewed
- Security Advisor (2026-10-09): 10 `authenticated_security_definer_function_executable` warnings and 1 `auth_leaked_password_protection` warning.
- Read-only role aggregate: one `System Admin` role assignment.
- Read-only counts: 1 profile, 0 departments, 0 documents.
- No Supabase development branches were present at review time.
- Production migration metadata has 26 entries while the repository contains 21 SQL migration files; semantic parity remains unverified.
- These findings are triage signals, not by themselves proof that every function is exploitable.

## Prioritized remediation work

### P0 — Establish safe recovery and test conditions
1. Arrange a second school-controlled administrator account using the approved account-provisioning process. Verify sign-in and role management before any role-guard test. Do not fabricate an identity or insert synthetic staff into Production.
2. Obtain an authorized, encrypted backup of Production database and document-file metadata/storage, then restore to an isolated target. Record the restore test and validation results without placing backup artifacts or secrets in this repository.
3. Recover authoritative SQL/deployment artifacts for all 26 applied Production migrations. Reconcile the 21 repository SQL files and recover missing base migration sources. Do not replay or reset Production migrations.
4. Create or identify a non-production Supabase target. A development branch may require additional cost; obtain explicit cost approval before creating it.

### P1 — Review authorization-critical SECURITY DEFINER functions
For each exposed function, record intended callers, authorization predicate, object-level access check, state-transition constraints, audit coverage, and positive/negative tests. Do not blanket-revoke EXECUTE: that could break intended app workflows.

- `admin_remove_user_role`: implement a transaction-safe last-active-system-admin guard and self-lockout policy after reviewing all role assignment paths and any existing constraints/triggers.
- `admin_set_user_role`: confirm whether `role.manage` may grant `system_admin`; enforce explicit role-delegation policy.
- `attach_document_file_version`: verify the caller can access the target document and that the referenced Drive file belongs to that same document and is valid for the requested file role.
- `set_document_deadline` / `assign_document`: verify object-level authority, active assignee, allowed document status, and concurrency behavior.
- Department create/update functions: validate parent department existence/active state and prevent cycles; confirm foreign-key/trigger behavior.
- Verify audit coverage for role changes, department changes, file-version attachment, assignment, deadline changes, and status transitions.

### P2 — Auth configuration
Enable leaked-password protection through the authorized Supabase Auth project settings only after owner/operator approval. Verify the setting after the change and run sign-in and password-recovery smoke tests with a school-controlled test account. Do not change Production Auth settings from this planning branch.

### P3 — Verification and release gate
- Run positive and negative authorization tests as at least two roles in non-production.
- Test concurrent role-removal attempts and prove the final active system administrator cannot be removed or deactivated.
- Test cross-document file-ID substitution and unauthorized deadline/assignment changes.
- Re-run Security Advisor and record each remaining warning with rationale.
- Run incoming/outgoing document, workflow, file version, audit, notification, and PWA/cache smoke tests.
- Perform an isolated backup restore drill and obtain school-owner acceptance.
- Only then prepare a separately reviewed, forward-only migration and deployment plan.

## Release decision
**NOT PRODUCTION READY.** This file records a safe remediation plan only. It does not assert that any finding is fixed or that any migration has been applied.
