create or replace function public.admin_set_user_role(p_user_id uuid,p_role_id uuid)
returns void
language plpgsql
security definer
set search_path=pg_catalog,public,private
as $$
begin
  if not private.has_permission('user.manage') and not private.has_permission('role.manage') then
    raise exception using errcode='42501',message='insufficient_privilege';
  end if;
  if not exists(select 1 from public.profiles where id=p_user_id) then raise exception using errcode='22023',message='user_profile_not_found'; end if;
  if not exists(select 1 from public.roles where id=p_role_id) then raise exception using errcode='22023',message='role_not_found'; end if;
  insert into public.user_roles(user_id,role_id,assigned_by)
  values(p_user_id,p_role_id,auth.uid())
  on conflict (user_id,role_id) do nothing;
end $$;
revoke all on function public.admin_set_user_role(uuid,uuid) from public;
grant execute on function public.admin_set_user_role(uuid,uuid) to authenticated;

create or replace function public.admin_remove_user_role(p_user_id uuid,p_role_id uuid)
returns void
language plpgsql
security definer
set search_path=pg_catalog,public,private
as $$
begin
  if not private.has_permission('user.manage') and not private.has_permission('role.manage') then
    raise exception using errcode='42501',message='insufficient_privilege';
  end if;
  delete from public.user_roles where user_id=p_user_id and role_id=p_role_id;
end $$;
revoke all on function public.admin_remove_user_role(uuid,uuid) from public;
grant execute on function public.admin_remove_user_role(uuid,uuid) to authenticated;
