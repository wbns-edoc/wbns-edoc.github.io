-- Draft-only migration: admin-managed school responsibility assignments.
-- Apply only in an isolated test database after reviewing dependencies. Never apply to Production as part of this draft.
begin;

create table if not exists public.school_responsibility_assignments (
  responsibility_key text primary key check (responsibility_key in (
    'director','vice_director','personnel_head','budget_head','academic_head','general_head'
  )),
  user_id uuid null references public.profiles(id) on delete restrict,
  updated_at timestamptz not null default now(),
  updated_by uuid null references public.profiles(id) on delete set null
);

create table if not exists public.school_responsibility_settings (
  singleton boolean primary key default true check (singleton),
  has_vice_director boolean not null default false,
  updated_at timestamptz not null default now(),
  updated_by uuid null references public.profiles(id) on delete set null
);
insert into public.school_responsibility_settings(singleton,has_vice_director)
values(true,false) on conflict(singleton) do nothing;

create table if not exists public.school_responsibility_audit (
  id bigint generated always as identity primary key,
  responsibility_key text not null,
  previous_user_id uuid null,
  new_user_id uuid null,
  actor_user_id uuid not null,
  changed_at timestamptz not null default now(),
  change_kind text not null check (change_kind in ('assignment_changed','vice_director_setting_changed')),
  previous_has_vice_director boolean null,
  new_has_vice_director boolean null
);

alter table public.school_responsibility_assignments enable row level security;
alter table public.school_responsibility_settings enable row level security;
alter table public.school_responsibility_audit enable row level security;
revoke all on public.school_responsibility_assignments from anon, authenticated;
revoke all on public.school_responsibility_settings from anon, authenticated;
revoke all on public.school_responsibility_audit from anon, authenticated;

create or replace function public.admin_get_school_responsibilities()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare result jsonb;
begin
  if auth.uid() is null or not exists (
    select 1 from public.user_roles ur join public.roles r on r.id=ur.role_id
    join public.profiles p on p.id=ur.user_id
    where ur.user_id=auth.uid() and p.is_active=true and r.code='system_admin'
  ) then raise exception 'system_admin_required'; end if;

  select jsonb_build_object(
    'has_vice_director', coalesce((select s.has_vice_director from public.school_responsibility_settings s where s.singleton),false),
    'assignments', coalesce((
      select jsonb_object_agg(a.responsibility_key,jsonb_build_object(
        'user_id',a.user_id,'full_name',p.full_name,'is_active',p.is_active
      ))
      from public.school_responsibility_assignments a
      left join public.profiles p on p.id=a.user_id
    ),'{}'::jsonb),
    'users', coalesce((
      select jsonb_agg(jsonb_build_object('id',p.id,'full_name',p.full_name,'email',p.email,'employee_code',p.employee_code) order by p.full_name)
      from public.profiles p where p.is_active=true
    ),'[]'::jsonb)
  ) into result;
  return result;
end;
$$;

create or replace function public.admin_save_school_responsibilities(
  p_assignments jsonb,
  p_has_vice_director boolean
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  actor uuid := auth.uid();
  k text;
  target_id uuid;
  old_id uuid;
  old_has_vice_director boolean;
  allowed_keys text[] := array['director','vice_director','personnel_head','budget_head','academic_head','general_head'];
  keys_seen text[];
begin
  if actor is null or not exists (
    select 1 from public.user_roles ur join public.roles r on r.id=ur.role_id
    join public.profiles p on p.id=ur.user_id
    where ur.user_id=actor and p.is_active=true and r.code='system_admin'
  ) then raise exception 'system_admin_required'; end if;

  if jsonb_typeof(p_assignments) <> 'object' then raise exception 'invalid_assignments'; end if;
  select array_agg(key) into keys_seen from jsonb_object_keys(p_assignments) as x(key);
  if exists(select 1 from unnest(coalesce(keys_seen,array[]::text[])) x where not (x=any(allowed_keys))) then
    raise exception 'invalid_responsibility_key';
  end if;

  if nullif(p_assignments->>'director','') is null then raise exception 'active_director_required'; end if;
  if p_has_vice_director and nullif(p_assignments->>'vice_director','') is null then
    raise exception 'active_vice_director_required';
  end if;

  foreach k in array allowed_keys loop
    target_id := nullif(p_assignments->>k,'')::uuid;
    if k='director' and target_id is null then raise exception 'active_director_required'; end if;
    if k='vice_director' and not p_has_vice_director then target_id := null; end if;
    if target_id is not null and not exists(select 1 from public.profiles p where p.id=target_id and p.is_active=true) then
      raise exception 'assigned_user_missing_or_inactive';
    end if;
    if k in ('director','vice_director') and target_id is not null and target_id=(nullif(p_assignments->>'director',''))::uuid and k='vice_director' then
      raise exception 'director_and_vice_must_differ';
    end if;

    select a.user_id into old_id from public.school_responsibility_assignments a where a.responsibility_key=k;
    if old_id is distinct from target_id then
      insert into public.school_responsibility_assignments(responsibility_key,user_id,updated_at,updated_by)
      values(k,target_id,now(),actor)
      on conflict(responsibility_key) do update set user_id=excluded.user_id,updated_at=excluded.updated_at,updated_by=excluded.updated_by;
      insert into public.school_responsibility_audit(responsibility_key,previous_user_id,new_user_id,actor_user_id,change_kind)
      values(k,old_id,target_id,actor,'assignment_changed');
    end if;
  end loop;

  select s.has_vice_director into old_has_vice_director from public.school_responsibility_settings s where s.singleton for update;
  if old_has_vice_director is distinct from p_has_vice_director then
    insert into public.school_responsibility_settings(singleton,has_vice_director,updated_at,updated_by)
    values(true,p_has_vice_director,now(),actor)
    on conflict(singleton) do update set has_vice_director=excluded.has_vice_director,updated_at=excluded.updated_at,updated_by=excluded.updated_by;
    insert into public.school_responsibility_audit(responsibility_key,previous_user_id,new_user_id,actor_user_id,change_kind,previous_has_vice_director,new_has_vice_director)
    values('vice_director',null,null,actor,'vice_director_setting_changed',old_has_vice_director,p_has_vice_director);
  end if;
  return public.admin_get_school_responsibilities();
end;
$$;

revoke all on function public.admin_get_school_responsibilities() from public, anon;
revoke all on function public.admin_save_school_responsibilities(jsonb,boolean) from public, anon;
grant execute on function public.admin_get_school_responsibilities() to authenticated;
grant execute on function public.admin_save_school_responsibilities(jsonb,boolean) to authenticated;

commit;
