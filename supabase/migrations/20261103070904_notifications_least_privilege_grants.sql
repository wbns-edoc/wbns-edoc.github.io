-- Production release migration: verified and applied on 2026-11-03.
-- Authenticated clients may read rows allowed by RLS and update only read_at.
begin;

do $preflight$
begin
  if to_regclass('public.notifications') is null then
    raise exception 'notifications_acl_preflight_failed: public.notifications is missing';
  end if;

  if not exists (
    select 1 from pg_catalog.pg_class c
    join pg_catalog.pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname = 'notifications' and c.relrowsecurity
  ) then
    raise exception 'notifications_acl_preflight_failed: RLS must be enabled';
  end if;

  if not exists (
    select 1 from pg_catalog.pg_policies
    where schemaname = 'public' and tablename = 'notifications'
      and cmd = 'SELECT' and 'authenticated' = any(roles)
      and coalesce(qual, '') like '%recipient_id%'
      and coalesce(qual, '') like '%auth.uid%'
  ) then
    raise exception 'notifications_acl_preflight_failed: recipient-scoped SELECT policy is missing';
  end if;

  if not exists (
    select 1 from pg_catalog.pg_policies
    where schemaname = 'public' and tablename = 'notifications'
      and cmd = 'UPDATE' and 'authenticated' = any(roles)
      and coalesce(qual, '') like '%recipient_id%'
      and coalesce(qual, '') like '%auth.uid%'
      and coalesce(with_check, '') like '%recipient_id%'
      and coalesce(with_check, '') like '%auth.uid%'
  ) then
    raise exception 'notifications_acl_preflight_failed: recipient-scoped UPDATE policy is missing';
  end if;

  if not exists (
    select 1 from pg_catalog.pg_attribute
    where attrelid = 'public.notifications'::regclass
      and attname = 'read_at' and attnum > 0 and not attisdropped
  ) then
    raise exception 'notifications_acl_preflight_failed: read_at column is missing';
  end if;
end;
$preflight$;

-- Revoke table-level rights and any legacy column-level rights separately.
revoke all privileges on table public.notifications from public, anon, authenticated;

do $column_revokes$
declare
  v_column text;
begin
  for v_column in
    select a.attname
    from pg_catalog.pg_attribute a
    where a.attrelid = 'public.notifications'::regclass
      and a.attnum > 0 and not a.attisdropped
  loop
    execute format(
      'revoke all privileges (%I) on table public.notifications from public, anon, authenticated',
      v_column
    );
  end loop;
end;
$column_revokes$;

grant select on table public.notifications to authenticated;
grant update (read_at) on table public.notifications to authenticated;

commit;
