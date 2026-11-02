-- Draft-only least-privilege grants for the existing per-recipient notification feed.
-- The notification outbox/security-definer trigger remains the only write path
-- for new notifications. Authenticated clients may read rows allowed by RLS and
-- update only read_at (mark-read / mark-all-read).
begin;

do $preflight$
begin
  if to_regclass('public.notifications') is null then
    raise exception 'notifications_acl_preflight_failed: public.notifications is missing';
  end if;

  if not exists (
    select 1 from pg_catalog.pg_class c
    join pg_catalog.pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'notifications'
      and c.relrowsecurity
  ) then
    raise exception 'notifications_acl_preflight_failed: RLS must be enabled';
  end if;

  if not exists (
    select 1 from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = 'notifications'
      and cmd = 'SELECT'
      and 'authenticated' = any(roles)
      and coalesce(qual, '') like '%recipient_id%'
      and coalesce(qual, '') like '%auth.uid%'
  ) then
    raise exception 'notifications_acl_preflight_failed: recipient-scoped SELECT policy is missing';
  end if;

  if not exists (
    select 1 from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = 'notifications'
      and cmd = 'UPDATE'
      and 'authenticated' = any(roles)
      and coalesce(qual, '') like '%recipient_id%'
      and coalesce(qual, '') like '%auth.uid%'
      and coalesce(with_check, '') like '%recipient_id%'
      and coalesce(with_check, '') like '%auth.uid%'
  ) then
    raise exception 'notifications_acl_preflight_failed: recipient-scoped UPDATE policy is missing';
  end if;
end;
$preflight$;

revoke all privileges on table public.notifications from anon, authenticated;
grant select on table public.notifications to authenticated;
grant update (read_at) on table public.notifications to authenticated;

commit;
