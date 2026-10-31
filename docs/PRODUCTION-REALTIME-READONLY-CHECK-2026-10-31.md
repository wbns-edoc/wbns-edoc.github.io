# Production Realtime publication check — 2026-10-31

**Project:** `wbns-edoc` (`iigzzwyfxxtqbgjawyom`)  
**Method:** read-only SQL catalog inspection through the Supabase project connector.  
**Scope:** Supabase Realtime publication membership and the existing `public.notifications` relation.  
**No DDL, DML, publication change, migration repair, deployment, or secret read was performed.**

## Observed Production state

- The `supabase_realtime` publication exists.
- Publication flags observed: `puballtables=false`, `pubinsert=true`, `pubupdate=true`, `pubdelete=true`, `pubtruncate=true`.
- `pg_publication_tables` returned **zero rows** for `supabase_realtime`; in particular, `public.notifications` is not a published table.
- `public.notifications` exists and has RLS enabled.
- Its observed policies are recipient-scoped: authenticated users may select/update rows only where `recipient_id = auth.uid()`.
- No staff-leave tables were returned by the public-table inventory query; the leave schema/RPC work remains a draft integration workstream, not a Production feature.

## Consequence

The existing in-app notification table is protected by recipient-scoped RLS, but it is not currently a member of the Realtime publication. Therefore, a client relying on Supabase Postgres Changes subscriptions to `public.notifications` cannot receive those row changes from the current publication configuration. This is a concrete Production blocker for any workflow that claims live Realtime notification delivery.

## SECURITY DEFINER follow-up — read-only static inspection

A second catalog query inspected all 19 `public` SECURITY DEFINER overloads/functions returned by Production's catalog:

- All inspected functions have an explicit fixed `search_path`.
- The 18 functions executable by `authenticated` are the 18 signatures identified by the Security Advisor; one legacy two-argument `admin_save_system_settings(text,bigint)` overload is executable only by `service_role`.
- The 18 authenticated-callable functions include permission gates, explicit active-System-Admin checks, document-scope checks, or user-scoped reads using `auth.uid()`. The public school-name reader is intentionally callable by `anon` and reads only the school-name setting.
- Static source-pattern inspection is not equivalent to role-impersonation testing. In particular, it does not prove helper-function behavior, all data paths, or resistance to privilege escalation. No grants or function bodies were changed.

**Required next security test:** execute each RPC under anon, ordinary authenticated, scoped department member, Registry Officer, Director, and System Admin identities; assert both allowed and denied cases, including cross-department document IDs and global-role mutations. Preserve the intentionally public school-name endpoint only if the school confirms that behavior.

## Draft implementation candidate

Integration contains `supabase/migrations/20261030110000_notifications_realtime_publication_draft.sql`, which checks for the table and publication and then adds `public.notifications` to `supabase_realtime`. Its paired assertion is `tests/assert-notifications-realtime-publication.sql`.

This candidate is intentionally draft-only. Before any Production application:
1. Run the migration and assertion in an isolated Supabase environment with the same relevant publication settings.
2. Verify subscription delivery with two authenticated synthetic users and confirm RLS prevents cross-recipient event visibility.
3. Verify the frontend subscription lifecycle, reconnect behavior, and fallback polling/refetch.
4. Include this change in the reviewed Production migration sequence only after Foundation/history reconciliation and the overall release gate pass.

## CI follow-up

After the prior documentation-only audit commit, all eight workflows on commit `afc82687973d531bdcdd6c838354c410ea6a565f` completed successfully: Frontend Build, Drive Upload, Schema Recovery PostgreSQL Replay, Workflow RPC Security, Staff Leave Schema RLS, School Responsibility Settings, Supabase Snapshot and Staff Leave Replay, and Recovered Catalog Fixture. This confirms those CI jobs passed on that branch head; it does not constitute Production E2E acceptance.

**Release status:** not approved. Keep Production unchanged.