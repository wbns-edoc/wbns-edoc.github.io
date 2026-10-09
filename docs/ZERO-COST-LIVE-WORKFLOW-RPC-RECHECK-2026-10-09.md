# Zero-cost live workflow RPC recheck — 2026-10-09

## Scope and safety

Read-only SQL queries against existing Supabase project `iigzzwyfxxtqbgjawyom`; no writes, privilege changes, test uploads, branch creation, or Production deployment were performed. Incremental spend target remains 0 THB. This report is triage evidence, not an integration test or proof of exploitability.

## Fresh live catalog observations

Queried `pg_proc`, `pg_namespace`, `pg_get_functiondef`, and `has_function_privilege` for selected public/private workflow, department, admin, and file-attachment functions.

| Function | Schema | SECURITY DEFINER | authenticated EXECUTE | anon EXECUTE | Triage note |
|---|---|---:|---:|---:|---|
| assign_document | public | yes | yes | no | Live public body contains future-deadline guard, registered-status transition guard, and row lock |
| assign_document | private | yes | yes | no | Private body does not contain those same guards by the simple source checks; behavior differs |
| update_document_status | public | yes | yes | no | Live public body contains transition guard and row lock |
| update_document_status | private | yes | yes | no | Definition length/body differs from public implementation |
| set_document_deadline | public | yes | yes | no | Public body is longer than private body; full behavior parity remains unresolved |
| set_document_deadline | private | yes | yes | no | SECURITY DEFINER implementation; authenticated can execute directly |
| create_approval | public | no | yes | no | SQL wrapper to private implementation |
| create_approval | private | yes | yes | no | Authenticated can execute directly |
| decide_approval | public | no | yes | no | SQL wrapper to private implementation |
| decide_approval | private | yes | yes | no | Authenticated can execute directly |
| attach_document_file_version | public | yes | yes | no | Checks `document.update` and row existence; explicit document/department scope was not visible in inspected definition |
| admin_remove_user_role | public | yes | yes | no | Inspected body has no visible last-admin/self-removal guard |
| admin_create_department | public | yes | yes | no | Inspected body has no visible parent-cycle guard |
| admin_update_department | public | yes | yes | no | Inspected body has no visible parent-cycle guard |

The string-based guard columns used in the SQL query are only triage heuristics. Absence of a matching string does not prove the absence of equivalent logic; full function bodies and runtime behavior must be reviewed before a final finding.

## Admin continuity signal

A separate read-only query returned `system_admin_assignment_count = 1` using role name/code matching for “system admin”. This is a continuity warning, not a definitive identity/authorization audit. Do not change or remove any admin assignment during testing. Before remediation, identify the exact active System Admin through an approved read-only audit and establish a recovery path without modifying the account.

## Security interpretation

- `anon EXECUTE = false` for the listed signatures is a positive observation, but does not remove the risk of authenticated users executing SECURITY DEFINER functions.
- `authenticated EXECUTE = true` for private functions, combined with `authenticated` schema access observed in earlier checks, means the `private` schema must not be treated as an access boundary by name alone. Review effective API exposure, grants, function behavior and caller requirements together.
- Do not blindly rerun `20261007205500_harden_workflow_rpc.sql`: current public implementations contain behavior not visibly present in private bodies.
- Do not broadly revoke EXECUTE from authenticated users, add permissive INSERT policies, or deploy an untested patch.

## Next zero-cost steps

1. Reconcile complete live function definitions against every migration and all callers.
2. Verify API exposed-schema configuration and effective privileges with read-only queries.
3. Prepare forward-only candidate SQL and a review diff only after behavior parity is documented.
4. Write tests for permitted/denied transitions, last-admin protection, department cycles, cross-document attachment and authenticated direct invocation of private functions.
5. Keep integration/release gates blocked until tests run in a genuinely isolated environment. No paid Supabase branch or other billable resource may be created under the 0-THB requirement.

## Status

No Production changes. No tests executed. No billable resource created. Release remains **BLOCKED**.
