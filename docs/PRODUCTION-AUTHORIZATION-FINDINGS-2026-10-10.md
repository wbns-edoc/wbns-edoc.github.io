# Production Authorization Findings — Follow-up Review
**Project:** ระบบสารบรรณอิเล็กทรอนิกส์ โรงเรียนวัดบึงน้ำใส  
**Review date:** 2026-10-10  
**Environment:** Read-only Production inspection + repository review  
**Status:** Findings only; no Production mutations

## Executive result

The repository and Production database are not yet safe to treat as release-ready for department-level confidentiality. A role/action proposal and 18-case test plan exist, but the live authorization boundary still does not enforce department scope consistently. This review also found a migration-order hazard in the repository: the workflow hardening migration introduces invoker wrappers, but a later migration redefines two public workflow functions as SECURITY DEFINER. Do not assume the earlier hardening remains effective just because its migration file exists.

## Confirmed live-schema findings

Read-only inspection of project `iigzzwyfxxtqbgjawyom` found:
- `public.profiles.department_id` exists and is nullable.
- `public.documents` has no department scope column.
- `documents_select_authorized` currently allows creator, current owner, or anyone with `document.view`; none of those branches is a department-scope predicate.
- `documents_update_authorized` allows creator/current owner or broad `document.update`, `document.assign`, or `document.approve` permissions without a department predicate.
- `document_files_authorized` checks whether a document row exists; whether that row is visible depends on document RLS, but the policy does not itself express file-specific scope.
- `google_drive_files_authorized` allows SELECT based on `document.view` without linking the file metadata to a document scope.
- `public.attach_document_file_version(uuid,uuid,text)` is SECURITY DEFINER and checks authentication, `document.update`, and row existence, but does not independently establish department/document scope or that the metadata was uploaded by an authorized caller.
- `private.assign_document(uuid,uuid,text,timestamptz)` checks the global `document.assign` permission and document existence, but no department membership or explicit delegation.
- Both private registry creation routines insert into `public.documents` without a department scope field.
- `public.admin_remove_user_role(uuid,uuid)` is SECURITY DEFINER and deletes a role assignment after a generic role/user management permission check. The inspected definition has no last-active-System-Admin or self-lockout guard. Do not test this against the only Production admin.

## Confirmed repository migration-order hazard

The repository contains:
- `supabase/migrations/20261007205500_harden_workflow_rpc.sql`, which moves several SECURITY DEFINER implementations into `private` and creates public SECURITY INVOKER wrappers.
- Later, `supabase/migrations/20261007212000_workflow_safety_hardening_v2.sql`, which declares `CREATE OR REPLACE FUNCTION public.assign_document(...)` and `CREATE OR REPLACE FUNCTION public.set_document_deadline(...)` as SECURITY DEFINER.

On a clean migration replay in filename order, the later migration can replace the public invoker wrapper for these two routines with a public SECURITY DEFINER function. That contradicts the intent of the earlier hardening. This is a source-level finding; it is not proof that Production migration history matches the repository or that a specific migration should be replayed.

**Required safe correction path:**
1. Do not edit/replay history blindly against Production. First reconcile the 26 Production migration-history entries with the 21 repository SQL migration files and inspect live function definitions/ACLs.
2. Prepare a new forward-only migration (using the supported Supabase migration workflow) that restores public invoker wrappers and places privileged implementation in `private`; verify schema usage/EXECUTE grants for the wrapper's caller context.
3. Check every affected workflow function, not only the two named above. Verify the final live function security mode and effective grants from the database catalog.
4. Add an automated regression check that fails if these public entry points are redefined as SECURITY DEFINER in a later migration.
5. Run tests against a disposable local/test database at zero additional infrastructure cost; do not create a paid Supabase project or branch.

## Existing permission catalogue (read-only)

The current catalogue includes `document.view`, `document.create`, `document.update`, `document.assign`, `document.approve`, `registry.incoming.manage`, `registry.outgoing.manage`, `user.manage`, `role.manage`, and `settings.manage`. Existing role labels include `System Admin`, `School Admin`, `Registry Officer`, `Director`, `Deputy Director`, `Staff`, and `Teacher`.

These database labels are not yet a complete mapping to the Thai organizational roles supplied by the school owner. Do not auto-assign users or grant permissions based on similar-looking labels without an approved role mapping. The four central roles remain unassigned to departments by design.

## Release blockers

1. Approve the role/action matrix, including school-wide content visibility and deputy delegation.
2. Choose and document document scope/transfer semantics.
3. Reconcile migration history before preparing forward-only SQL.
4. Correct and test department scope for document SELECT/UPDATE, assignment, registry creation, approval/status/deadline RPCs, file metadata, and attachment.
5. Add last-admin protection to role-management operations and test it only in an isolated environment.
6. Run direct table, RPC, and Edge Function authorization tests with synthetic users and documents.
7. Verify backup/restore, review Security Advisor findings, and obtain owner approval before production release.

## Safety statement

This document records observations and a correction plan only. It has not changed Production schema, policies, functions, roles, or data. No deployment or live upload test was performed. Keep additional infrastructure spend at 0 THB.

## Additional lint finding from isolated catalog fixture

The recovered Production catalog fixture was successfully applied to a disposable local Supabase database. Schema lint then reported an ambiguity in `public.attach_document_file_version(uuid,uuid,text)`: `where id=p_document_id` can resolve to either the `RETURNS TABLE(id uuid, ...)` output variable or the `public.documents.id` column. This is a real function-definition concern observed in the recovered catalog, not evidence that a Production fix has been deployed. The test fixture now qualifies `public.documents.id` solely to allow isolated smoke/lint progress and is explicitly marked as a test-only patch. A forward-only Production correction remains blocked until migration history/source is reconciled and the owner approves a tested plan.
