# Workflow RPC migration-order guard findings

Date: 2026-10-10
Branch: `fix/drive-upload-metadata-atomicity-2026-10-09`

## What CI established

The Workflow RPC Security CI run `37967869355` failed at the static migration-order guard, before installing the Supabase CLI or starting database containers. This is a security regression signal, not a successful security test.

Source review confirms:
- `supabase/migrations/20261007212000_workflow_safety_hardening_v2.sql` recreates `public.assign_document` and `public.set_document_deadline` as `SECURITY DEFINER` after the earlier hardening migration moved the implementations to `private` and introduced public invoker wrappers.
- `supabase/migrations/20261009005230_enforce_status_transition_permissions_v1.sql` recreates `public.update_document_status` as `SECURITY DEFINER`.
- `supabase/migrations/20261009005407_protect_dedicated_workflow_rpc_transitions_v1.sql` recreates `public.update_document_status` again as `SECURITY DEFINER`.

The static guard was updated to recognize both untagged dollar quotes (`$$`) and tagged quotes (such as `$function$`) when reading SQL function headers. The next CI run must verify this parser change.

## Why no corrective migration was applied

The repository's first foundation migration remains a placeholder rather than the full SQL used to create the Production schema. Production records 26 migrations, and the repository cannot currently reproduce the database from scratch. Creating a corrective migration before reconciling the authoritative schema and function history would be unsafe.

## Required remediation sequence

1. Recover the complete, authoritative foundation migration and reconcile all 26 applied migrations with version-controlled SQL.
2. Review function dependencies, ownership, grants, and behavior before restoring public SECURITY INVOKER wrappers and private implementations.
3. Add explicit catalog tests for wrapper security mode, anon denial, authenticated access, and required internal function privileges.
4. Run the full migrations and pgTAP tests against a disposable local database.
5. Test department isolation and role-based central access using test identities; verify last-System-Admin protection.
6. Review backup/restore and obtain explicit owner approval before any Production migration.

## Safety statement

No Production schema, RLS policy, grants, rows, or user roles were changed. No new Supabase project or branch was created.
