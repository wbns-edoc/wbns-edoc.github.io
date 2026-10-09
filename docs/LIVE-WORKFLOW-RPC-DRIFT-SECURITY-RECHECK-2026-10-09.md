# Live Workflow RPC Drift and Security Advisor Recheck — 2026-10-09

## Executive finding

A fresh read-only comparison of the live Production function catalog, current Security Advisor output, and repository migration source found material differences that must be reconciled before release. In particular, several workflow RPCs that the repository migration `20261007205500_harden_workflow_rpc.sql` intends to expose as SECURITY INVOKER wrappers remain SECURITY DEFINER in the live `public` schema.

This is a confirmed catalog/source mismatch, not a claim that a particular exploit has been exercised. Do not apply a blanket revoke or blindly rerun the migration: reconcile the complete history and test expected UI/API behavior first.

## Evidence

- Project ref: `iigzzwyfxxtqbgjawyom`
- Project status: `ACTIVE_HEALTHY`, region `ap-southeast-1`
- Read-only source: `supabase/migrations/20261007205500_harden_workflow_rpc.sql`
- Live evidence: `pg_proc`, `pg_get_functiondef`, and current Security Advisor findings.
- No Production schema/data/Auth setting/role assignment was changed. No tests were run.

## Confirmed differences

Repository migration source intends to move the following implementations into `private` and expose public SQL SECURITY INVOKER wrappers:
- `assign_document`
- `update_document_status`
- `create_approval`
- `decide_approval`
- `set_document_deadline`

Live catalog results show:
- `public.assign_document` is SECURITY DEFINER (the live definition has its own PL/pgSQL implementation); `private.assign_document` also exists as SECURITY DEFINER.
- `public.update_document_status` is SECURITY DEFINER; its live body contains a transition guard, but it is not the invoker wrapper in the reviewed migration source.
- `public.set_document_deadline` is SECURITY DEFINER; `private.set_document_deadline` also exists as SECURITY DEFINER.
- `public.create_approval` and `public.decide_approval` are SECURITY INVOKER wrappers as expected.
- Current Security Advisor reports 10 authenticated-callable SECURITY DEFINER warnings, including the above and several intentional admin/permission functions.

The live migration history contains 26 entries and does not include an entry named `harden_workflow_rpc`, while the repository contains `20261007205500_harden_workflow_rpc.sql`. Migration names alone are not proof of missing execution, but the function catalog confirms that at least some intended end state differs from the source migration.

## Why this matters

A SECURITY DEFINER function runs with the function owner's privileges, so its own validation must be correct and complete. A live public implementation that differs from the reviewed source can invalidate source-based security assumptions. The live `public.update_document_status` function does include transition and permission checks; do not infer that it is unguarded solely from the SECURITY DEFINER flag. Each function requires behavior-specific review.

## Safe next actions

1. Preserve the exact live definitions and compare their hashes/contents with every relevant repository migration and later migration.
2. Determine whether live implementations were applied manually, renamed, consolidated, or overwritten after the hardening migration.
3. Prepare a forward-only corrective migration in the security branch; do not modify Production directly.
4. In an isolated environment, test all affected RPCs for authorized and unauthorized roles, workflow transitions, audit/history side effects, and expected UI compatibility.
5. Review grants separately from function bodies. Do not revoke EXECUTE from all authenticated users indiscriminately; the UI depends on authorized RPCs.
6. Re-run Security Advisor after any approved isolated fix and inspect each remaining warning.
7. Keep the current Production System Admin untouched during all testing.

## Other live observations

- `admin_remove_user_role` still has a SECURITY DEFINER body that checks `user.manage` or `role.manage` and deletes the role assignment, without a visible last-system-admin or self-removal guard in the function body.
- `admin_create_department` and `admin_update_department` do not visibly reject self-parent or indirect hierarchy cycles.
- `attach_document_file_version` remains SECURITY DEFINER and checks `document.update` plus row existence, but does not visibly enforce the complete document/department scope.
- The Security Advisor currently reports 10 SECURITY DEFINER warnings and one leaked-password-protection warning. The warning count is a snapshot and should be rechecked after reviewed changes.

## Status

- Catalog/source comparison: completed read-only for the functions listed above.
- Forward corrective migration: not written or applied.
- Integration/authorization tests: not run.
- Production changes: none.
- Release gate: blocked pending migration reconciliation and isolated validation.
