-- Production release migration: verified and applied on 2026-11-03.
-- RLS on public.notifications remains the row-level access boundary.
-- This migration is tracked at the Production-applied version.
begin;

do $publication$
begin
  if to_regclass('public.notifications') is null then
    raise exception 'notifications_realtime_preflight_failed: public.notifications is missing';
  end if;

  if exists (
    select 1 from pg_catalog.pg_publication
    where pubname = 'supabase_realtime'
  ) and not exists (
    select 1 from pg_catalog.pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'notifications'
  ) then
    execute 'alter publication supabase_realtime add table public.notifications';
  end if;
end;
$publication$;

commit;
