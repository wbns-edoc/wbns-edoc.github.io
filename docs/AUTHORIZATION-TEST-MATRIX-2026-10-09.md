# Authorization Test Matrix — Role and Document RPCs
Date: 2026-10-09
Status: **TEST SPECIFICATION ONLY — NOT EXECUTED**
Target: isolated non-production database only. Never run destructive cases against Production.

## Evidence basis
The repository migration `20261007215500_admin_role_management_v1.sql` defines:
- `public.admin_set_user_role(uuid,uuid)`: checks `private.has_permission('user.manage')` or `private.has_permission('role.manage')`, then inserts the requested role.
- `public.admin_remove_user_role(uuid,uuid)`: checks the same permission predicate, then deletes the requested role assignment.
Both are SECURITY DEFINER functions exposed to authenticated users. The existing code shown in this migration does not itself demonstrate a last-active-system-admin guard, a prohibition on self-demotion, or a special approval requirement for granting `system_admin`. These protections may exist elsewhere (triggers/constraints/newer migrations), so inspect the live schema and all role-change paths before concluding they are absent.

## Test fixtures (non-production only)
- Two separate administrator test identities, A and B, both controlled by the school/test operator.
- One ordinary staff identity C.
- A test-only role set with known permission assignments.
- Synthetic documents and files with no real school personal data.
- Record the schema/migration version and reset procedure before tests.

## Role-management tests
| ID | Scenario | Expected outcome |
|---|---|---|
| ROLE-01 | Anonymous caller invokes role RPC | Denied |
| ROLE-02 | Authenticated staff without `user.manage` or `role.manage` tries to grant a role | Denied; no row inserted |
| ROLE-03 | Authorized role manager grants a permitted non-privileged role | Succeeds; audit event recorded if required by policy |
| ROLE-04 | Role manager attempts to grant `system_admin` without elevated approval | Denied unless explicit policy permits it |
| ROLE-05 | Admin A attempts to remove B's final active `system_admin` assignment | Denied; B remains administrator |
| ROLE-06 | Admin A and B concurrently attempt to remove each other's admin assignment | Transaction-safe guard preserves at least one active administrator |
| ROLE-07 | Sole administrator attempts self-demotion | Denied |
| ROLE-08 | Repeat removal of a nonexistent role assignment | Safe, predictable result; no privilege escalation |
| ROLE-09 | Inactive/deactivated user retains a role assignment | Effective access is denied; role cleanup follows approved lifecycle policy |
| ROLE-10 | Every grant/revoke attempt | Actor, target, role, outcome and timestamp are auditable without logging secrets |

## Document/workflow authorization tests
| ID | Scenario | Expected outcome |
|---|---|---|
| DOC-01 | Staff attaches a file belonging to a different document | Denied |
| DOC-02 | Staff without access assigns a document to another user | Denied |
| DOC-03 | Assignee references inactive or nonexistent profile | Denied |
| DOC-04 | Unauthorized user changes deadline or reminder | Denied |
| DOC-05 | Status transition skips a required approval step | Denied |
| DOC-06 | Unauthorized user calls exposed SECURITY DEFINER RPC directly via REST | Denied, regardless of hidden/disabled UI controls |
| DOC-07 | Successful permitted action | Correct state change and corresponding audit event |
| DOC-08 | Two concurrent state transitions conflict | One valid transition wins; no invalid mixed state |

## Required implementation review before test execution
1. Enumerate every function, trigger, policy, constraint and service path that can add/remove roles or change account activity.
2. Determine whether the system has a stable user lock strategy for role changes; test concurrent changes inside transactions.
3. Define explicit policy for granting `system_admin`, self-demotion, and emergency recovery.
4. Ensure permission checks fail closed when `auth.uid()` is null.
5. Ensure SECURITY DEFINER functions use a fixed safe `search_path`, schema-qualified objects, minimal grants, and object-level authorization.
6. Reconcile migration history before applying any changes to test database.

## Exit criteria
All negative cases must fail without side effects; all positive cases must succeed only for intended roles; audit events must be complete; at least one administrator must remain recoverable. Capture sanitized test results and rerun the Security Advisor after reviewed fixes.

**Do not mark these tests passed until executed in an isolated environment.**
