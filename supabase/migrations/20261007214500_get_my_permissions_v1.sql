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
