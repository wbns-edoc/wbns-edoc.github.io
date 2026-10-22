# Staff leave integration mapping and implementation gate

Status: design artifact only; no Production changes.

## Existing school identity and authorization objects

| Existing object | Intended leave feature use | Required verification before implementation |
|---|---|---|
| `public.profiles` | Requester and staff identity | Confirm primary key, active-state semantics, employee identity, and which profile fields are safe to display |
| `public.departments` | Organizational group/reporting | Confirm parent-child hierarchy and whether the school has a canonical department scope |
| `public.user_departments` | Staff membership in multiple groups | Confirm uniqueness, active/effective dates and membership policy |
| `public.user_department_roles` | Role scoped to a group | Confirm how group-specific permissions are resolved |
| `public.roles`, `public.user_roles` | Global roles | Read exact codes and active status; do not assume `director` or `deputy_director` exist |
| `public.permissions`, `public.role_permissions`, `public.department_role_permissions` | Authorization mapping | Confirm permission code format and whether helpers enforce global and group scope consistently |
| `public.audit_logs` | Potential common audit sink | Inspect its schema, triggers, allowed event shape and insert permissions before reuse |

This is a mapping plan based on the previously observed catalog. It is not proof that all constraints, triggers, RLS definitions, or helper implementations have been fully reviewed.

## Authorization rules

- A requester can create and read only their own draft/submitted request, subject to field-level limits.
- Approver queues must be scoped to verified approval responsibility; global role names alone are not sufficient evidence of scope.
- A requester cannot approve their own request, including when they also hold an approver role.
- System administration does not automatically grant access to private leave reasons or health-related attachments.
- No direct client writes to status, approval fields, policy snapshot, audit history, or notification delivery state.
- Every transition is performed by a server/database function that validates actor, current state, assignment, and allowed transition atomically.
- Action history is append-only; corrections create a new action.
- Private attachments use private storage and short-lived signed URLs after authorization.

## School-wide policy and personnel metadata

The school's stated product requirement is one uniform leave policy for all personnel. Accordingly, personnel category may be stored as a reporting attribute on a staff profile or a request-time snapshot, but it must not be a key that selects policy versions, entitlements, or day-count rules. Before enabling this model for legal compliance, the school must confirm that its uniform-policy decision is compatible with the applicable official rules for every employment category. Until then, unverified entitlements and automatic day counting remain disabled.

## Required implementation sequence

1. Inspect exact columns, foreign keys, constraints, triggers, RLS policies, and helper function definitions read-only.
2. Verify actual global and department role/permission codes without exposing staff personal data.
3. Implement additive schema and narrow transition functions on a non-production branch/environment.
4. Add RLS/API tests for ownership, scoped approver access, self-approval, direct status update, private attachments, immutable history, and duplicate processing.
5. Verify authoritative leave rules and approved day-count basis.
6. Add notification outbox and aggregate dashboard APIs, with idempotent delivery and no private reasons in previews.
7. Run clean-database migration replay, test suite, and CI; inspect results rather than assuming they passed.
8. Pilot using synthetic accounts in isolated staging, then obtain explicit release approval and a rollback plan.

## Release decision

**NO-GO for Production** until steps 1–8 have evidence. The current draft migration is not safe to apply as-is because policy is tied to personnel category and approver SELECT policies are broad. This file does not modify the database and is not executable SQL.
