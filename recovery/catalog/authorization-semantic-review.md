# Authorization semantic review — 2026-10-15

Branch reviewed: `feature/department-scoped-permissions-2026-10-11`. Comparison target: read-only Production catalog snapshot.

## Status

Do not merge or deploy candidate migrations yet. This review is read-only; the PostgreSQL replay uses a disposable database and does not modify Production.

## Finding A — inactive department checks differ between helpers

The recovered `private.user_has_department(uuid, uuid)` checks that both the profile and department are active. The recovered `private.has_department_permission(text, uuid)` checks an active profile and explicit department membership/role/permission rows, but does not itself check `departments.is_active`.

Consequently, a caller relying only on `has_department_permission` may still receive a positive result for an inactive department if related rows remain. The current presence of such data has not been established, and this finding is not evidence of a data breach. Review every RLS policy and RPC using this helper to determine whether another guard covers the inactive-department case.

**Affected paths identified in the captured catalog:** the `documents_insert_authorized` and `documents_update_authorized` policies; incoming/outgoing detail insert/update policies; assignment insert/update policies; deadlines management; and the approval, assignment, status-update, and deadline RPCs. Some paths also call `private.can_access_document` or check other conditions, so each call chain must be evaluated rather than assuming all are equally exposed.

**Call-chain review from the captured function bodies:** `private.can_access_document` uses `private.user_has_department` for same-department access and the scoped permission helper for both same-department and parent/subgroup visibility. `private.create_approval` and `private.decide_approval` combine document access with `document.approve`; `private.assign_document` and `private.set_document_deadline` combine document access with `document.assign`; `private.update_document_status` combines document access with a status-dependent permission. The approval-creation RPC separately checks that a non-global approver's department is active. Direct RLS policies for document and incoming/outgoing detail writes also call `has_department_permission`, so the helper itself must enforce active department state.

**Required before deployment:** regression cases now cover inactive profiles, inactive departments, removed membership, and disabled permissions in the disposable harness. Keep reviewing each create/update/approval/assignment/file path, especially direct RLS checks and status-dependent permissions, and verify the System Admin/director exception remains explicit and limited to the intended permission codes.

## Finding B — director global permission test

The disposable test previously asserted director read-all and approve, but omitted explicit create and update assertions. The test has been updated to assert create, update, and approve for both System Admin and director.

## Validation limits

Disposable PostgreSQL replay does not prove a complete Supabase clean install with Auth, Storage, Edge Functions, OAuth, or deployment configuration. Catalog equality, RPC grants, file/storage access, and workflow tests remain required.

## Decision

No Production writes were performed. No migration is approved for deployment. Keep PR #27 Draft until the findings and remaining reconstruction blockers are resolved.


## Follow-up validation — 2026-10-15

A recovery-only candidate was added at `recovery/catalog/candidate-has-department-permission-active-department.sql`. The PostgreSQL Replay workflow applies it **after** replaying the recovered catalog, and only to the disposable PostgreSQL service. The behavioral fixture includes an active ordinary user with a valid role/permission attached to an inactive department and asserts denial, plus an active director and asserts the explicit global-role exception remains effective.

- Disposable PostgreSQL Replay: **PASS** — [run 38764539643](https://github.com/wbns-edoc/wbns-edoc.github.io/actions/runs/38764539643)
- Static Snapshot CI: **PASS** — [run 38764539979](https://github.com/wbns-edoc/wbns-edoc.github.io/actions/runs/38764539979)

An earlier replay attempt failed because the new PL/pgSQL test block had malformed dollar quoting; that test syntax was corrected and the later run passed. The passing run establishes only that this candidate behaves as asserted in the disposable PostgreSQL harness. It does not establish full Supabase compatibility, catalog equivalence, or production readiness. The candidate is not in `supabase/migrations`, was not applied to Production, and remains **NOT APPROVED** for deployment.
