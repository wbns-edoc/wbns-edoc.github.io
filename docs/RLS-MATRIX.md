# RLS Matrix — WBNS Electronic Document System

## Authorization model

Authorization is permission-based. Roles are bundles of permissions; users may have one or more roles. Department/scope restrictions are evaluated in addition to the permission.

Never trust role values supplied by the browser.

## Permission catalog

| Permission | Purpose |
|---|---|
| dashboard.view | View dashboard |
| user.view | View users |
| user.manage | Create/update/deactivate users |
| role.manage | Manage roles/permissions |
| registry.incoming.manage | Receive/register incoming documents |
| registry.outgoing.manage | Prepare/register outgoing documents |
| document.view | Read authorized documents |
| document.create | Create documents |
| document.update | Update authorized documents |
| document.assign | Assign/reassign work |
| document.approve | Approve authorized documents |
| document.complete | Complete assigned work |
| document.archive | Archive documents |
| report.view | View reports |
| audit.view | View audit logs |
| settings.manage | Manage school settings |

## Role baseline

| Role | Baseline permissions |
|---|---|
| System Admin | All technical/system permissions |
| School Admin | user, role, settings, report; operational permissions only when explicitly granted |
| Director | dashboard, document.view, document.approve, report.view |
| Deputy Director | dashboard, document.view, document.approve, report.view within assigned scope |
| Registry Officer | incoming/outgoing registry, document.view/create/update/assign/archive, report.view |
| Teacher | document.view/update/complete for assigned/authorized work |
| Staff | document.view/update/complete for assigned/authorized work |

## Table policy matrix

Legend:
- R = SELECT
- C = INSERT
- U = UPDATE
- D = DELETE
- A = access only through controlled function; direct table mutation denied

| Table | Anonymous | Authenticated user | Registry | Director/Deputy | Admin |
|---|---|---|---|---|---|
| profiles | — | R own/basic authorized | R | R authorized | R/U |
| roles | — | R effective roles | R | R | R/U |
| permissions | — | R effective permissions | R | R | R/U |
| user_roles | — | R own | R | R | R/C/U |
| departments | — | R authorized | R | R | R/U |
| documents | — | R authorized | R/C/U | R/U approval fields | R/U |
| incoming_details | — | R authorized | R/C/U | R | R/U |
| outgoing_details | — | R authorized | R/C/U | R | R/U |
| senders | — | R authorized | R/C/U | R | R/U |
| assignments | — | R assigned/authorized | R/C/U | R/U oversight | R/U |
| status_history | — | R authorized | R/C | R | R |
| approvals | — | R own/authorized | R | R/C/U own approval | R |
| deadlines | — | R assigned/authorized | R/U | R/U oversight | R/U |
| comments | — | R authorized/C own | R/C | R/C | R |
| google_drive_files | — | R only through document authorization | R/C | R | R/U |
| document_files | — | R authorized/C where permitted | R/C/U | R | R/U |
| notifications | — | R/U own | R/U own | R/U own | R/U |
| push_subscriptions | — | R/C/U own | R/C/U own | R/C/U own | controlled |
| audit_logs | — | — | — | — | R |

## Required RLS rules

### Common
- Enable RLS on every exposed business table.
- No anonymous business-data access.
- `authenticated` access is deny-by-default.
- Use `auth.uid()` to bind records to the signed-in user.
- Policies must verify both role permission and row scope.
- UPDATE policies require both `USING` and `WITH CHECK`.
- DELETE should be denied for legal/audit records; business deletion is replaced by status transitions.
- Audit logs are append-only and should not be directly writable by ordinary users.

### Document visibility
A user can view a document when at least one is true:
1. user has broad `document.view` permission within the document's department/scope;
2. user is current owner;
3. user has an active assignment;
4. user is an authorized approver for the document;
5. user is an admin with the required permission.

### Assignment mutation
A user may create/reassign an assignment only with `document.assign` permission and within their organizational scope.

### Approval mutation
Only the assigned approver with `document.approve` may create/update an approval decision. A client cannot set `approved_by` or equivalent identity fields arbitrarily.

### Audit
Application users may read audit records only with `audit.view`. Writes should be performed by trusted database triggers/functions or privileged server-side code.

## Security-definer rules

Use `SECURITY DEFINER` only when necessary, such as:
- transactional number allocation;
- carefully scoped authorization helper functions;
- audit/logging functions where ordinary users must not have direct insert rights.

Every such function must:
- set a safe `search_path`;
- qualify object names;
- have narrowly scoped EXECUTE grants;
- avoid accepting arbitrary SQL/object names;
- be reviewed for privilege escalation.

## Test matrix

Minimum automated RLS tests:

1. anonymous SELECT -> denied
2. anonymous INSERT -> denied
3. Teacher reads assigned document -> allowed
4. Teacher reads unrelated document -> denied
5. Staff updates assigned task -> allowed
6. Staff updates unrelated task -> denied
7. Registry Officer registers incoming document -> allowed
8. Teacher creates registry number -> denied
9. Director approves assigned approval -> allowed
10. Teacher creates approval decision -> denied
11. Admin manages user role -> allowed
12. ordinary user modifies another user's role -> denied
13. ordinary user deletes audit log -> denied
14. deactivated user accesses business data -> denied
15. cross-department document access -> denied unless explicit scope permission
16. service/Edge Function privileged action -> allowed only for intended operation

## Migration ordering

1. extensions/types
2. departments
3. profiles
4. roles/permissions
5. role mappings
6. document/register/numbering tables
7. document supertype + incoming/outgoing details
8. workflow/assignment/approval/deadline/comment tables
9. Drive/file metadata
10. notifications/push
11. audit infrastructure
12. indexes
13. helper functions
14. triggers
15. RLS
16. grants
17. seed reference data
18. RLS/security tests

No migration should include real school documents, user passwords, OAuth secrets, Google credentials, or VAPID private keys.
