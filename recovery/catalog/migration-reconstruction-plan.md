# Migration reconstruction plan — Production recovery

Updated: 2026-10-15

## Decision

**Do not replace `20261007200000_foundation_schema_rbac_rls.sql` with either catalog snapshot yet. Do not merge this recovery PR as a deployable migration.**

The original foundation SQL is absent from version control. Production's current catalog snapshot is a description of the *current end state*, not a historical migration or a faithful `pg_dump`. Replacing the foundation with it and then replaying later migrations can duplicate objects, repeat policy/function changes, or silently omit security configuration.

## Evidence status

| Gate | Result | What it proves |
|---|---|---|
| Static snapshot CI | PASS — [run 38754023251](https://github.com/wbns-edoc/wbns-edoc.github.io/actions/runs/38754023251) | Expected captured inventory and safety assertions remain consistent |
| Disposable PostgreSQL 17 replay | PASS — [run 38754023297](https://github.com/wbns-edoc/wbns-edoc.github.io/actions/runs/38754023297) | Captured SQL phases replay in the compatibility harness and the included RBAC/RLS tests pass |
| Full Supabase clean-install parity | NOT PROVEN | The harness is plain PostgreSQL with compatibility stubs, not full Supabase Auth/Storage/PostgREST |
| Historical migration reproducibility | BLOCKED | Production records 55 migration history entries; main contains 31 SQL files and the foundation file is a 285-byte placeholder |
| Production deployment readiness | NOT APPROVED | Grants, ownership, default ACLs, extensions, platform objects, historical gaps, and runtime parity remain to be reconciled |

## Why the current snapshot is not a replacement migration

- `recovery/catalog/relations-and-security.sql` is assembled from catalog metadata and explicitly excludes a complete guarantee of ownership, grants, default privileges, and platform-managed objects.
- `recovery/catalog/private-functions.sql` and `public-functions.sql` recover current function definitions, not the sequence of function changes that produced them.
- `supabase/tests/fixtures/recovered-production-catalog.sql` was generated on 2026-10-10 for isolated tests. It is a useful compatibility fixture, not the October 15 production state and not a historical foundation migration.
- Production migration history includes entries whose corresponding SQL is absent from main, including multiple department-membership/permission/security corrections recorded on 2026-10-11 through 2026-10-13. These cannot be reconstructed accurately from timestamps or names alone.
- Existing forward migrations may depend on those missing changes. Applying them over an end-state snapshot could duplicate or contradict the captured definitions.

## Required reconstruction sequence

1. **Freeze evidence, not Production.** Keep all catalog queries read-only. Preserve the captured snapshot and record the capture date and source commit.
2. **Reconcile the historical ledger.** For each Production migration history row, classify it as: exact versioned SQL available; represented by an independently reviewed snapshot; or missing/unreconstructable historical change. Do not infer SQL from a migration name.
3. **Build a clean-install candidate in a separate path.** Use an explicitly named candidate baseline and a separate test directory. Never overwrite the placeholder or production migration chain until the candidate passes review.
4. **Reconcile permissions and platform configuration.** Compare grants, ownership, default ACLs, extensions and schemas, views/options, function execute privileges, Auth/Storage dependencies, and publication settings against read-only Production evidence.
5. **Replay in disposable Supabase.** Use a fresh local Supabase stack, not only PostgreSQL stubs. Apply the candidate baseline and every retained forward migration in order. Resolve duplicates and dependency failures in the candidate branch only.
6. **Run behavior and security regressions.** Verify System Admin/principal read, add, edit, and approve access; department and subgroup boundaries; multiple department memberships; unauthorized role-management RPC denial; storage/file access; document numbering; workflow transitions; and deleted-document operations.
7. **Compare final catalog inventories.** Require zero unexplained differences for tables/columns/types/constraints/indexes/functions/owners/grants/default ACLs/RLS policies/triggers/views/options/extensions. Review expected differences explicitly.
8. **Review and approve.** Only after all gates pass should a separate PR propose the clean-install baseline and migration-history strategy. Production rollout needs a backup/rollback plan and an explicitly reviewed maintenance window; this evidence PR alone must not trigger a deploy.

## Stop conditions

Stop and keep Production unchanged if any of these occur:
- an unavailable historical migration is being guessed from its name;
- replay needs a test-only patch that differs from the production function definition;
- any grant, ownership, default privilege, extension, Auth/Storage object, or security setting is unknown;
- a final catalog difference is unexplained;
- a role/RLS regression fails or a destructive operation lacks a tested recovery path.

## Current next action

The latest disposable replay and snapshot CI both pass. The next engineering task is to create and validate a separate clean-install candidate from the best available evidence, then compare it with the October 10 fixture and the October 15 Production catalog. This is a recovery/reconciliation task, not permission to deploy the snapshot.
