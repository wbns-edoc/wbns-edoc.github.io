# Explicit approver authority attestation — 2026-11-03

## Change on Integration

The prior responsibility-audit trigger inferred approval authority from an administrative assignment audit row and populated a synthetic `school_responsibility_audit:<id>` reference. That was insufficient evidence of appointment/delegation authority.

Added candidate migration:
- `supabase/migrations/20261103120000_staff_leave_explicit_approver_authority_draft.sql`

It changes the trigger so every Director/Vice responsibility audit:
1. Refreshes the candidate route identities from the responsibility tables.
2. Forces `authority_verified=false`.
3. Clears the previous authority reference, verifier, timestamp, direct-Vice exception, and no-Vice confirmation.
4. Never manufactures an authority reference from the audit ID.

It adds `admin_verify_staff_leave_approval_route(text, boolean)`:
- Requires an authenticated active profile with `system_admin`.
- Requires a non-empty, non-synthetic authority reference.
- Requires the explicit no-Vice confirmation to match the current school setting.
- Re-reads the active Director and, when configured, active Vice Director from responsibility assignments.
- Stores verifier and timestamp, and only then enables the route.

## Regression test

`tests/leave-approval-authority-verification.test.sql` checks:
- ordinary authenticated user cannot attest;
- System Admin attestation records the reference, actor, and time;
- audit-row-shaped references are rejected;
- any subsequent assignment audit invalidates the prior attestation.

The Staff Leave Schema RLS workflow now includes the migration and regression test in its apply/test sequence.

## Safety boundary

This is Integration/CI candidate code only. It has not been applied to Production, and it does not itself prove that a supplied reference points to a genuine appointment instrument. A System Admin must inspect the actual school order/delegation record before using the RPC. No production assignment, authority attestation, policy approval, merge, or Pages deployment is performed by this change.

The migration/test still require a green CI result on the latest PR head. The release remains NO-GO until the other policy, real-user RPC/Storage/Realtime E2E, migration parity, and restore/rollback gates are closed.
