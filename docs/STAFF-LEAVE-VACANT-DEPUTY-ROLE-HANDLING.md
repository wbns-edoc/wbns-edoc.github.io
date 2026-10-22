# Staff Leave: Handling a Defined but Vacant Deputy Director Role

Status: design decision / implementation gate  
Scope: Wat Bueng Nam Sai School staff-leave workflow  
Production effect: none; this document does not change roles, users, database state, or approval authority.

## Confirmed school context

- The school currently has no person holding the Deputy Director position.
- The system still defines a Deputy Director role/permission.
- Keep the role definition. Do not delete it, rename it, or assign it to an arbitrary user merely to make a workflow pass.

## Required system behavior

1. Treat a role definition and a current role holder as different facts. A configured role may have zero active assignees.
2. Do not create a pending approval task addressed to a vacant Deputy Director role, and do not leave a request waiting indefinitely for that nonexistent approver.
3. Do not automatically grant Deputy Director permissions to the Director, registry staff, or another employee. Role inheritance or substitution must never be implicit.
4. Resolve the active approval route against verified, currently active assignees and the approved school policy. The route must fail closed with a clear administrative warning if no authorized approver can be resolved.
5. The proposed operational route for review is: employee submits leave request -> Director reviews/approves, **only where the applicable official rule and school delegation authorize the Director to act directly**. Do not implement this route as production behavior until that authority is verified and recorded.
6. If an acting/substitute approver is later formally appointed, require an explicit authorized assignment/delegation with effective dates, scope, actor, reason, and audit trail. Do not infer acting authority from job title or convenience.
7. Self-approval remains prohibited. Every approval/rejection must be server-authorized and auditable.
8. Notifications must follow the resolved route: notify the employee on submission, notify the actual authorized approver, and notify the employee on decision. Never notify a vacant role as though a person received the task.
9. If there is no resolvable authorized approver, preserve the request and its history, mark it as blocked for administrative resolution, and notify an authorized administrator without granting that administrator approval authority by this notification alone.

## Required tests before release

- Deputy Director role exists but has zero active assignees.
- Submission does not create an approval task for a vacant role.
- No automatic role grant or silent substitution occurs.
- Direct-to-Director route is enabled only after documented authority verification.
- No authorized approver produces a visible blocked state and safe alert, not a dropped request or an unbounded pending task.
- Audit records identify the actual approver and any formal delegation used.
- Notification recipients match the resolved workflow route.
- Self-approval is rejected server-side.

## Release gate

This is a design note only. Do not apply a migration, change Production role assignments, or enable the leave workflow on the strength of this note alone. First verify the official approval authority, current role assignments, authorization helpers/RLS/grants, and isolated migration/test behavior; then obtain explicit release approval.
