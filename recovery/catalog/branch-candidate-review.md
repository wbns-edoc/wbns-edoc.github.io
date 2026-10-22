# Branch-only migration candidate inventory review

Updated: 2026-10-15  
Reviewed branch: `feature/department-scoped-permissions-2026-10-11`  
Comparison target: October 15 recovered Production catalog artifacts on `recovery/production-schema-catalog-2026-10-15`.

## Purpose and scope

This is a **read-only name/provenance review** of SQL files that exist on the feature branch but are not part of `main`. It is not a semantic equivalence proof, not a clean-install migration chain, and not approval to cherry-pick or deploy.

For each listed file, the blob SHA identifies the exact reviewed file revision. The functions below were extracted from `CREATE FUNCTION` statements in those files and compared by schema-qualified function name with the 54 public/private functions captured in the October 15 catalog. Signatures, overloads, bodies, grants, owners, data transformations, dependencies and side effects still need review.

## Candidate files and blob identities

| Candidate file | Blob SHA | Functions declared |
|---|---|---|
| `20261010160000_multi_department_membership_v1.sql` | `eebe58586808bcb64c28113df0be34017cc0e000` | `private.user_has_department` |
| `20261011100000_department_scoped_roles_permissions_v1.sql` | `323e439c85c2fe6967922fa813bb95a0fe31b2bb` | `private.has_department_permission`, `public.admin_get_user_department_roles`, `public.admin_set_user_department_role`, `public.admin_set_department_role_permission`, `public.admin_get_department_permission_catalog` |
| `20261011120000_department_role_matrix_seed_fix.sql` | `358fd3f8d1b59af88bc0ee1bd77f053baf7fb626` | none |
| `20261011121000_department_scoped_read_rpc_fix.sql` | `a51a2c1d0b882ab13aaf1d712ca6c23e369ec21f` | `private.can_access_document`, `public.admin_get_user_department_roles` |
| `20261011140000_department_scoped_write_rpc_guards.sql` | `763dfc4f61aafbfe013790d262dd392cf6bbc5a5` | `private.register_incoming_document`, `private.register_outgoing_document`, `private.update_document_status`, `private.assign_document`, `private.set_document_deadline` |
| `20261011150000_department_scoped_access_final_correction.sql` | `d027677257f6b5ad727d382cd691e07d48843b5c` | `private.can_access_document` |
| `20261011160000_department_scoped_approval_guards.sql` | `0d1ee406374456858954eff882bc278f5d35c35b` | `private.create_approval`, `private.decide_approval` |
| `20261011170000_department_scoped_rls_and_file_guards.sql` | `12c66b7e7facc1b501083b8922d473da8508307c` | `private.can_access_document`, `public.attach_document_file_version` |
| `20261011180000_close_remaining_department_rls_bypasses.sql` | `76dda1aa1d9189c5108f4e2d232f3d49657b55f8` | `private.can_access_document` |
| `20261011190000_separate_document_edit_from_approve_assign.sql` | `5a9c0bfd90b8fa1e3a44c7b4802ecf81b295b369` | none |
| `20261011200000_guard_document_file_attachment.sql` | `d770b98fdb780d869278531817c91825cfb943cb` | `public.attach_document_file_version` |
| `20261011210000_require_department_membership_for_scoped_permissions.sql` | `c24a755eb7c189dda530c346947d7d939005de08` | `private.has_department_permission` |
| `20261011230000_manage_department_membership_rpc.sql` | `7257a81464ba79b6fc3509f9405ea0b4e6db4458` | `private.admin_get_user_department_memberships_impl`, `private.admin_set_user_department_membership_impl`, `public.admin_get_user_department_memberships`, `public.admin_set_user_department_membership` |
| `20261011231000_require_active_membership_for_approvers.sql` | `667524b6a612935a6f9f98f2a6b09882ff6c91cc` | `private.create_approval` |
| `20261011232000_require_explicit_active_department_membership.sql` | `c23f0eb4aa5a52bea59f889fd925f36d744bf536` | `private.user_has_department` |
| `20261013001230_include_department_scoped_permissions_in_identity.sql` | `705c2bb14b321c6cee5f404e6e6de316aa530c70` | `public.get_my_permissions` |

## Inventory findings

- The 16 reviewed files declare 20 distinct schema-qualified function names.
- All 20 distinct names occur in the captured October 15 function inventory; this is a **name-only consistency signal**, not proof of equivalent signatures or behavior.
- The captured inventory has additional functions not declared by these 16 files. That is expected for a partial set of forward corrections and does not mean those functions are missing from Production.
- The Production migration ledger uses different version/name pairs for many of these corrections. The matrix records these as candidates, not exact historical matches.
- The early foundation, initial seed, audit/reporting, and admin-RPC hardening migrations still need their original SQL or a separately reviewed baseline reconstruction.

## Required next review gates

1. Compare each candidate function's full signature, body, security mode, `search_path`, grants and owner against the October 15 catalog definitions.
2. Compare every table/policy/trigger/seed/data change with the catalog and current data assumptions, including `user_departments`, `user_department_roles`, and `department_role_permissions`.
3. Check ordering and dependencies when combined with the existing main-branch migrations; do not append candidate files blindly because their SQL may duplicate end-state objects.
4. Run on a fresh local Supabase stack with Auth/Storage enabled, then run document numbering, workflow, file/storage access, multi-membership and privilege-negative tests.
5. Require a zero-unexplained-difference catalog comparison before proposing a clean-install baseline. Production stays unchanged until then.

## Safety statement

No migration was applied to Supabase by this review. No branch was merged. Production deployment is **NOT APPROVED**.
