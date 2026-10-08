create or replace function public.admin_set_user_department(
  p_user_id uuid,
  p_department_id uuid default null
)
returns public.profiles
language plpgsql
security definer
set search_path=pg_catalog,public,private
as $$
declare
  v public.profiles;
  old_department uuid;
begin
  if auth.uid() is null then
    raise exception using errcode='42501',message='authentication_required';
  end if;

  if not private.has_permission('user.manage') and not private.has_permission('role.manage') then
    raise exception using errcode='42501',message='insufficient_privilege';
  end if;

  if not exists(select 1 from public.profiles where id=p_user_id) then
    raise exception using errcode='22023',message='user_profile_not_found';
  end if;

  if p_department_id is not null
     and not exists(select 1 from public.departments where id=p_department_id and is_active=true) then
    raise exception using errcode='22023',message='active_department_not_found';
  end if;

  select department_id into old_department
  from public.profiles
  where id=p_user_id;

  update public.profiles
     set department_id=p_department_id,
         updated_at=now()
   where id=p_user_id
   returning * into v;

  insert into public.audit_logs(actor_id,action,entity_type,entity_id,old_data,new_data)
  values(
    auth.uid(),
    'user_department_changed',
    'profile',
    p_user_id,
    jsonb_build_object('department_id',old_department),
    jsonb_build_object('department_id',p_department_id)
  );

  return v;
end
$$;

revoke all on function public.admin_set_user_department(uuid,uuid) from public;
revoke all on function public.admin_set_user_department(uuid,uuid) from anon;
grant execute on function public.admin_set_user_department(uuid,uuid) to authenticated;
