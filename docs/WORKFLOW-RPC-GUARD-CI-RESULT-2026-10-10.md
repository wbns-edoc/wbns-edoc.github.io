# Workflow RPC Guard CI Result — 2026-10-10

Workflow run: https://github.com/wbns-edoc/wbns-edoc.github.io/actions/runs/37968119115

The static migration-order guard completed and reported these exact results:

| Public RPC | Latest definition found in repository | Result |
|---|---|---|
| `assign_document` | `20261007213500_workflow_assignment_transition_guard_v1.sql` | FAIL — SECURITY DEFINER |
| `update_document_status` | `20261009005407_protect_dedicated_workflow_rpc_transitions_v1.sql` | FAIL — SECURITY DEFINER |
| `set_document_deadline` | `20261007212000_workflow_safety_hardening_v2.sql` | FAIL — SECURITY DEFINER |
| `create_approval` | `20261007205500_harden_workflow_rpc.sql` | PASS — SECURITY INVOKER/default INVOKER |
| `decide_approval` | `20261007205500_harden_workflow_rpc.sql` | PASS — SECURITY INVOKER/default INVOKER |

The workflow exited at the static guard, before Supabase CLI setup and database startup. This is an intentional fail-closed outcome: three public workflow RPC definitions still violate the desired invoker-wrapper design.

This guard only evaluates repository migration definitions in filename order. It is not proof of live catalog state or runtime authorization correctness. A full replayable migration source is still missing: `supabase/migrations/20261007200000_foundation_schema_rbac_rls.sql` is a placeholder, while the connected Production project reports 26 applied migrations.

Next steps remain: recover authoritative foundation SQL, reconcile the full migration history, prepare a reviewed forward-only fix, and run database/catalog/authorization tests on a disposable local database. No Production change was made and no new Supabase project or branch was created.
