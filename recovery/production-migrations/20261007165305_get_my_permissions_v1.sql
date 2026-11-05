-- RECOVERED SOURCE ARCHIVE — NOT A NEW MIGRATION
-- Read-only extraction from Production supabase_migrations.schema_migrations.statements
-- Production project: iigzzwyfxxtqbgjawyom
-- Applied version: 20261007165305
-- Ledger name: get_my_permissions_v1
-- DO NOT place in supabase/migrations or replay against Production.

create or replace function public.get_my_permissions()
returns table(permission_code text)
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select distinct p.code
  from public.user_roles ur
  join public.role_permissions rp on rp.role_id=ur.role_id
  join public.permissions p on p.id=rp.permission_id
  join public.profiles pr on pr.id=ur.user_id
  where ur.user_id=auth.uid()
    and pr.is_active=true
  order by p.code;
$$;

revoke all on function public.get_my_permissions() from public;
grant execute on function public.get_my_permissions() to authenticated;
