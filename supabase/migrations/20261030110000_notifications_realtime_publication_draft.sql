-- Draft-only: publish notification INSERT events to Supabase Realtime.
-- RLS on public.notifications remains the row-level access boundary.
-- Apply only in an isolated test database until the complete release review passes.
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
