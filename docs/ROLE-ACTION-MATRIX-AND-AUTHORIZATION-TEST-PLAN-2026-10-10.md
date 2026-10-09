# Role–Action Matrix and Authorization Test Plan
**Project:** ระบบสารบรรณอิเล็กทรอนิกส์ โรงเรียนวัดบึงน้ำใส  
**Status:** Proposal for owner review; not an approved production permission specification  
**Date:** 2026-10-10

## 1. Non-negotiable organization model

The four departments are:
1. กลุ่มบริหารงานวิชาการ
2. กลุ่มบริการงบประมาณ
3. กลุ่มบริหารงานบุคคล
4. กลุ่มบริหารงานทั่วไป

These four roles are central roles, not members of any of the four departments:
- System Admin
- เจ้าหน้าที่ธุรการ
- ผู้อำนวยการสถานศึกษา
- รองผู้อำนวยการสถานศึกษา

Do not force central-role profiles to have `profiles.department_id`. A central role must be represented by an explicit role assignment, not by inventing a department membership. A user with no department and no authorized central role must be denied department-scoped operations by default.

## 2. Proposed role–action matrix (owner must approve)

Legend: **P** = proposed capability, still subject to owner approval; **D** = deny by default; **G** = only if separately and explicitly granted; **T** = technical administration, not document authority.

| Action | System Admin | เจ้าหน้าที่ธุรการ | ผู้อำนวยการสถานศึกษา | รองผู้อำนวยการสถานศึกษา | Staff in a department |
|---|---|---|---|---|---|
| Manage accounts, roles, system configuration | T/P | D | D | D | D |
| View ordinary document content | G; not implied by admin status | P/G; owner must decide whether registry work requires school-wide content visibility | P within approved authority | P only within approved authority/delegation | P within own department and assigned permissions |
| Register incoming/outgoing documents | D by default; separate grant only | P across departments if confirmed as registry duty | D by default | D by default | P only if assigned registry permission in own scope |
| Create ordinary department document | D by default | D by default unless acting in a specifically granted workflow | D by default | D by default | P in own department |
| Assign/route a document | D by default; technical role is not workflow authority | P for registry routing if approved | P as authorized by school rules | P only within documented delegation | P within own department and allowed workflow |
| Review/approve/issue a command | D unless separately authorized | D unless separately authorized | P across departments within official authority | P only under recorded delegation/authority | D unless a specific approval role is granted |
| Attach a file to a document | G, with scope enforced by server | P only for documents in approved registry scope | P if the workflow grants it | P if the workflow grants it | P only for documents they may update in their department |
| Read/change role assignments | T/P with safeguards | D | D | D | D |
| Access another department’s document | G only through an explicit, audited grant; never from admin role alone | P only if cross-department registry access is explicitly approved | P according to approved school-wide authority | P according to explicit delegation | D unless explicit documented delegation |
| Delete/void records or bypass workflow | D by default; privileged audited break-glass only if approved | D by default | D unless formal policy grants it | D unless formally delegated | D by default |

This table is intentionally conservative. It is not an assertion that the school has approved every proposed permission. In particular, school-wide registry visibility, director/deputy visibility, document voiding, and the scope of System Admin access require explicit approval.

## 3. Authorization rules to implement

1. **Deny by default.** Every action must pass a server-side permission check and a scope check. Hiding a button in the frontend is not authorization.
2. **Separate role from department.** Central-role users may have no `department_id`; department staff must have an explicitly approved department assignment. Do not infer department from role names or email.
3. **Document scope is authoritative.** A document's owning/handling department and any explicit cross-department delegation must be checked on every read, update, assignment, status transition, deadline change, and file attachment.
4. **No global permission shortcut.** A generic permission such as `document.view` or `document.update` must not alone authorize access to every department's documents.
5. **Creator/current-owner access is not permanent scope.** Creator or previous-owner status must not bypass current scope after a transfer unless an explicit retention rule is approved.
6. **Registry scope must be explicit.** If เจ้าหน้าที่ธุรการ is authorized to operate across departments, model that as a specific central registry capability with audited actions—not as fake department membership or an undocumented blanket grant.
7. **Deputy delegation must be explicit and revocable.** Record who delegated, the delegate, permitted actions/scope, start/end, and revocation; no assumed equivalence to the director.
8. **System Admin is not automatically a business approver.** Technical administration and routine document-content access are separate privileges. Any break-glass access must be approved, logged, time-bounded, and reviewed.
9. **Preserve an active System Admin.** Any role-management operation must prevent removal/demotion of the last active System Admin and guard against accidental self-lockout. Do not test destructive cases against the only Production admin.
10. **Enforce scope inside trusted server paths.** RLS and server-side RPC/Edge Function logic must agree. Never rely solely on a frontend pre-check or a prior SELECT policy.

## 4. Required authorization test matrix

Run against an isolated test environment with synthetic users and documents only. Do not seed test records or change roles in Production.

| ID | Scenario | Expected result |
|---|---|---|
| AUTH-01 | User has no department and no central role attempts document list/read/create/update | Deny; no document data leaked |
| AUTH-02 | Central-role user has no department | Allow only actions explicitly approved for that role; unrelated actions denied |
| AUTH-03 | Department A staff reads/updates a Department A document with required permission | Allow only the permitted action |
| AUTH-04 | Department A staff reads/updates/assigns a Department B document | Deny without explicit delegation |
| AUTH-05 | Staff has generic `document.view` but no scope grant for a foreign department | Deny |
| AUTH-06 | Creator or previous owner attempts access after document transfer out of scope | Deny unless an explicit retention rule permits it |
| AUTH-07 | Current owner in scope reads/updates document | Allow only actions covered by permission and workflow state |
| AUTH-08 | Registry clerk registers incoming/outgoing item without a department assignment | Allow only if the approved central registry role authorizes the operation; server must establish all trusted fields |
| AUTH-09 | Registry clerk attempts a non-registry action not granted to the role | Deny |
| AUTH-10 | Director performs an approved school-wide review/approval action | Allow only if the action and workflow state are authorized and audited |
| AUTH-11 | Deputy attempts director-only action without active delegation | Deny |
| AUTH-12 | Deputy performs action within active delegation; then delegation expires/revokes | Allow while valid; deny after expiry/revocation |
| AUTH-13 | Client directly calls file-attachment RPC for a foreign-department document | Deny at trusted server/RPC boundary, even if the UI is bypassed |
| AUTH-14 | User tries to attach a file to a document they can view but cannot update | Deny |
| AUTH-15 | Department changes or document is transferred; old access is retested | New scope applies immediately; no stale creator/owner bypass |
| AUTH-16 | Attempt to demote/delete the last active System Admin | Deny atomically |
| AUTH-17 | System Admin has no document-content grant | Technical admin actions allowed as assigned; ordinary document content remains denied |
| AUTH-18 | Every denied action is checked for response/body/log leakage | No sensitive document metadata or file URLs leaked; audit event contains only approved minimum detail |

## 5. Database and API implementation gates

The current Production inspection recorded in the linked design review found that `profiles.department_id` exists but `documents.department_id` does not; document SELECT policy branches for creator/current owner/global `document.view` do not establish complete department isolation. The incoming/outgoing registry implementations also insert documents without a department field, assignment lacks a department/delegation check, and the file-attachment SECURITY DEFINER routine does not independently enforce document scope.

Therefore, before implementation:
- Decide whether document scope is represented by owning department, handling department, multiple participants, or a combination; define transfer semantics.
- Reconcile migration history with repository SQL before preparing a migration. Do not blindly rerun existing workflow hardening migrations.
- Design a safe migration for existing records and trusted registry creation paths before making any scope field non-null.
- Review every relevant RLS policy, SECURITY DEFINER routine, RPC, Edge Function, and storage/file URL path as one authorization boundary.
- Add tests for both direct table access and RPC/Edge Function calls.
- Keep changes in a reviewed branch until migration, backup/restore, and authorization tests pass and the owner approves release.

## 6. Owner decisions still required

1. Confirm the proposed role–action matrix, especially registry-wide content visibility and director/deputy review/approval authority.
2. Define whether the director and deputy can read all document content, or only metadata / assigned workflow items / documents under their formal authority.
3. Define whether System Admin may access document content and the break-glass approval/audit procedure.
4. Define the exact deputy delegation process, permitted actions, duration, and who can revoke it.
5. Define document ownership/handling department and transfer/retention rules.
6. Confirm who in each department may register, assign, review, approve, attach, void, or close documents.

## 7. Change safety

This file is design/test documentation only. It does not change Production schema, policies, roles, data, Edge Functions, or billing resources. Do not create a paid Supabase project/branch. Keep additional infrastructure cost at 0 THB. Do not merge or deploy based on this document alone.
