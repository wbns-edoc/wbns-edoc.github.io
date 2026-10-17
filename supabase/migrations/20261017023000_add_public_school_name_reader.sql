-- Allow the app to display the configured school name without exposing admin settings.
create or replace function public.get_public_school_name()
returns text
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select coalesce((select setting_value from public.system_settings where setting_key = 'school_name'), 'โรงเรียนวัดบึงน้ำใส');
$$;
revoke all on function public.get_public_school_name() from public;
grant execute on function public.get_public_school_name() to anon, authenticated;
