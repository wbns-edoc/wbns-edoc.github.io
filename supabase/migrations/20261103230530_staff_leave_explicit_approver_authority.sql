-- Replace inferred authority with an explicit, auditable System Admin attestation.
-- Integration/CI only. Do not apply to Production until the migration has passed
-- replay, security tests, and the school's authority evidence has been reviewed.
begin;

create or replace function public.staff_leave_sync_route_from_responsibility_audit()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_director uuid;
  v_vice uuid;
  v_has_vice boolean;
begin
  select a.user_id into v_director
    from public.school_responsibility_assignments a
   where a.responsibility_key='director';
  select a.user_id into v_vice
    from public.school_responsibility_assignments a
   where a.responsibility_key='vice_director';
  select s.has_vice_director into v_has_vice
    from public.school_responsibility_settings s where s.singleton=true;

  -- Any responsibility change invalidates the previous attestation. Never
  -- synthesize an authority reference from an audit-row ID.
  if coalesce(v_has_vice,false) then
    if v_director is null or v_vice is null or v_director=v_vice
       or not exists(select 1 from public.profiles p where p.id=v_director and p.is_active=true)
       or not exists(select 1 from public.profiles p where p.id=v_vice and p.is_active=true) then
      v_director := null;
      v_vice := null;
    end if;
  else
    if v_director is null
       or not exists(select 1 from public.profiles p where p.id=v_director and p.is_active=true) then
      v_director := null;
    end if;
    v_vice := null;
  end if;

  insert into public.staff_leave_approval_route_config(
    singleton,vice_director_user_id,director_user_id,authority_verified,
    direct_to_vice_enabled,no_vice_director_confirmed,authority_reference,
    verified_by,verified_at,updated_at
  ) values (
    true,v_vice,v_director,false,false,false,null,null,null,statement_timestamp()
  )
  on conflict(singleton) do update set
    vice_director_user_id=excluded.vice_director_user_id,
    director_user_id=excluded.director_user_id,
    authority_verified=false,
    direct_to_vice_enabled=false,
    no_vice_director_confirmed=false,
    authority_reference=null,
    verified_by=null,
    verified_at=null,
    updated_at=excluded.updated_at;

  return new;
end;
$$;

create or replace function public.admin_verify_staff_leave_approval_route(
  p_authority_reference text,
  p_confirm_no_vice_director boolean
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_actor uuid := auth.uid();
  v_director uuid;
  v_vice uuid;
  v_has_vice boolean;
begin
  if v_actor is null then
    raise exception 'authentication_required' using errcode='28000';
  end if;
  if not exists(select 1 from public.profiles p where p.id=v_actor and p.is_active=true) then
    raise exception 'active_profile_required' using errcode='42501';
  end if;
  if not exists(
    select 1 from public.user_roles ur
    join public.roles r on r.id=ur.role_id
    where ur.user_id=v_actor and r.code='system_admin'
  ) then
    raise exception 'system_admin_required' using errcode='42501';
  end if;
  if p_authority_reference is null
     or length(btrim(p_authority_reference)) < 3
     or length(btrim(p_authority_reference)) > 500
     or lower(btrim(p_authority_reference)) like 'school_responsibility_audit:%' then
    raise exception 'real_authority_reference_required' using errcode='22023';
  end if;
  if p_confirm_no_vice_director is null then
    raise exception 'explicit_no_vice_confirmation_required' using errcode='22023';
  end if;

  select s.has_vice_director into v_has_vice
    from public.school_responsibility_settings s
   where s.singleton=true
   for update;
  if not found then raise exception 'responsibility_settings_missing' using errcode='55000'; end if;
  if p_confirm_no_vice_director = v_has_vice then
    raise exception 'no_vice_confirmation_mismatch' using errcode='22023';
  end if;

  select a.user_id into v_director
    from public.school_responsibility_assignments a
   where a.responsibility_key='director';
  if v_director is null or not exists(
    select 1 from public.profiles p where p.id=v_director and p.is_active=true
  ) then raise exception 'active_director_assignment_required' using errcode='55000'; end if;

  if v_has_vice then
    select a.user_id into v_vice
      from public.school_responsibility_assignments a
     where a.responsibility_key='vice_director';
    if v_vice is null or v_vice=v_director or not exists(
      select 1 from public.profiles p where p.id=v_vice and p.is_active=true
    ) then raise exception 'active_vice_director_assignment_required' using errcode='55000'; end if;
  else
    v_vice := null;
  end if;

  insert into public.staff_leave_approval_route_config(
    singleton,vice_director_user_id,director_user_id,authority_verified,
    direct_to_vice_enabled,no_vice_director_confirmed,authority_reference,
    verified_by,verified_at,updated_at
  ) values (
    true,v_vice,v_director,true,false,p_confirm_no_vice_director,
    btrim(p_authority_reference),v_actor,statement_timestamp(),statement_timestamp()
  )
  on conflict(singleton) do update set
    vice_director_user_id=excluded.vice_director_user_id,
    director_user_id=excluded.director_user_id,
    authority_verified=true,
    direct_to_vice_enabled=false,
    no_vice_director_confirmed=excluded.no_vice_director_confirmed,
    authority_reference=excluded.authority_reference,
    verified_by=excluded.verified_by,
    verified_at=excluded.verified_at,
    updated_at=excluded.updated_at;

  return jsonb_build_object(
    'verified',true,
    'director_user_id',v_director,
    'vice_director_user_id',v_vice,
    'no_vice_director_confirmed',p_confirm_no_vice_director,
    'verified_by',v_actor
  );
end;
$$;

revoke all on function public.staff_leave_sync_route_from_responsibility_audit() from public,anon,authenticated;
revoke all on function public.admin_verify_staff_leave_approval_route(text,boolean) from public,anon;
grant execute on function public.admin_verify_staff_leave_approval_route(text,boolean) to authenticated;

commit;
