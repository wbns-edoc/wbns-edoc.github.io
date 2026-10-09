# PUBLIC REGISTRATION RPC ANONYMOUS-EXECUTE REVIEW — 2026-10-09

## Scope
Read-only inspection of live function definitions, effective ACLs, triggers, and current Supabase Security Advisor. No SQL writes, data changes, grants/revokes, migrations, or runtime calls were performed.

## Findings

### 1. Public registration wrappers are SECURITY INVOKER, not SECURITY DEFINER
The live functions `public.register_incoming_document(...)` and `public.register_outgoing_document(...)` are SQL wrappers with `SET search_path TO 'pg_catalog', 'public'`; their definitions delegate to the matching `private.register_...` implementation. The wrappers have effective EXECUTE for `anon` and `authenticated`, and their ACL includes PUBLIC and anon EXECUTE.

### 2. Private registration implementations contain a caller-authentication and permission check
The live `private.register_incoming_document` body assigns `auth.uid()` and raises `permission denied` if it is null or lacks `registry.incoming.manage`. The outgoing counterpart checks for a non-null `auth.uid()` and `registry.outgoing.manage`. Thus the inspected function bodies contain a defensive check against anonymous callers. This is source inspection only; it is not a runtime test, and it does not establish whether the wrapper schema is exposed through the effective API configuration.

### 3. Number allocation checks registration-management permission
The live `private.allocate_document_number` function checks that the caller has incoming or outgoing registration-management permission before incrementing the sequence. It is SECURITY DEFINER and has PUBLIC EXECUTE in its ACL, but the `private` schema does not grant USAGE to `anon`. Do not infer anonymous API reachability from the function ACL alone. Keep its direct exposure and default grants under review.

### 4. `set_updated_at` appears to be a trigger helper
The public `set_updated_at()` function has PUBLIC/anon EXECUTE in its ACL, but its body only sets `NEW.updated_at = now()` and returns the row. The live trigger inventory found it attached to five tables: `departments`, `documents`, `number_sequences`, `profiles`, and `senders`. No standalone API call was tested. The appropriate remediation question is whether it should be callable through RPC at all, not whether to break the existing triggers.

### 5. Advisor snapshot remains unchanged
The current Security Advisor still reports 10 `authenticated_security_definer_function_executable` warnings and one `auth_leaked_password_protection` warning. The registration wrappers are invoker functions, so their anon EXECUTE ACL is a separate concern from the 10 reported SECURITY DEFINER warnings.

## Safe next actions
1. Confirm actual PostgREST exposed schemas and API routing before concluding reachability.
2. Keep caller checks in private registration implementations and test negative anonymous calls only in a cost-free isolated environment.
3. Decide whether to revoke PUBLIC/anon EXECUTE from the registration wrappers and trigger helper only after verifying application behavior and migration ownership; do not make an untested production change.
4. Review role-specific default privileges separately; changing defaults is not a substitute for reviewing current ACLs.
5. Preserve current System Admin access and zero additional spend. No Supabase branch/project should be created while incremental cost must remain 0 THB.

## Release status
**BLOCKED.** This inspection improves confidence about the registration function bodies but does not close API exposure, default-ACL, integration-test, migration-parity, backup/restore, or owner-approval gates.
