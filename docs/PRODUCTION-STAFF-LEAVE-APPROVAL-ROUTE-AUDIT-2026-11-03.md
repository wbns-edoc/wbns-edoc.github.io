# Production approval-route verification — 2026-11-03

Status: **BLOCKED / fail-closed**. Read-only catalog and metadata inspection only.

## Live Production observations

Project: `wbns-edoc` (`iigzzwyfxxtqbgjawyom`).

- `staff_leave_approval_route_config` has no singleton row.
- `school_responsibility_settings` has `has_vice_director=false`.
- `school_responsibility_assignments` has no director or vice-director assignment.
- There is one active account holding the `director` role and zero active accounts holding `deputy_director`; identities are intentionally not copied into this report.
- Therefore, the database has not yet recorded which active Director account is the formally appointed current school Director, nor a verifiable appointment/authority reference. The submission RPC must remain blocked.

## Implementation concern discovered

The current `staff_leave_sync_route_from_responsibility_audit()` trigger treats any row written to `school_responsibility_audit` by the System Admin assignment RPC as sufficient to set `authority_verified=true`, and synthesizes `authority_reference='school_responsibility_audit:' || audit_id`.

That audit row proves that a System Admin changed an assignment; it does **not by itself prove** the underlying appointment/delegation instrument. Before go-live, the Integration implementation should separate:
1. assigning the Director/Vice Director responsibility;
2. recording the actual authority/appointment reference and verifier; and
3. activating the immutable approval route only after an explicit verification action.

A route change must reset authority verification until the new assignment is verified. For a school with no appointed Vice Director, the route must require an explicit, audited confirmation of that fact and direct the request to the verified Director. Do not let an ordinary assignment edit silently enable approval.

## Required safe next step

Prepare an Integration-only migration/RPC/UI/test change that requires a non-empty authority reference and explicit System Admin verification before setting `authority_verified=true`; add positive and negative tests for missing reference, wrong role, inactive Director, missing Vice Director, no-Vice confirmation, and route change invalidation. Run all required CI. Do not apply it to Production or configure live approvers without the school's actual appointment reference.

## Boundary

No Production data/schema/ACL change was made by this check. No real identity, appointment reference, or approval route was guessed.