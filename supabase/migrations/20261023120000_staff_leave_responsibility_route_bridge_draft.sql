-- Draft-only bridge: make admin-managed school responsibilities the source of truth
-- for leave approvers. Apply only in disposable CI/test databases; never Production.
begin;

alter table public.staff_leave_approval_route_config
  add column if not exists no_vice_director_confirmed boolean not null default false;

-- The earlier draft constraint assumed a deputy always existed. Replace it with
-- a constraint that permits a director-only route only when explicitly confirmed.
alter table public.staff_leave_approval_route_config
  drop constraint if exists staff_leave_route_verified_fields_chk;
alter table public.staff_leave_approval_route_config
  drop constraint if exists staff_leave_route_exception_requires_verified_chk;
alter table public.staff_leave_approval_route_config
  add constraint staff_leave_route_verified_fields_chk check (
    not authority_verified or (
      director_user_id is not null
      and nullif(btrim(authority_reference), '') is not null
      and verified_by is not null and verified_at is not null
      and (
        (no_vice_director_confirmed and vice_director_user_id is null)
        or
        (not no_vice_director_confirmed and vice_director_user_id is not null
         and vice_director_user_id <> director_user_id)
      )
    )
  );
alter table public.staff_leave_approval_route_config
  add constraint staff_leave_route_exception_requires_verified_chk
  check (not no_vice_director_confirmed or authority_verified);

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
  -- Only the audited admin RPC writes this audit table. Every change refreshes
  -- the trusted route mapping from the authoritative assignments/settings.
  select a.user_id into v_director
    from public.school_responsibility_assignments a
   where a.responsibility_key='director';
  select a.user_id into v_vice
    from public.school_responsibility_assignments a
   where a.responsibility_key='vice_director';
  select s.has_vice_director into v_has_vice
    from public.school_responsibility_settings s where s.singleton=true;

  if coalesce(v_has_vice,false) then
    if v_director is null or v_vice is null or v_director=v_vice
       or not exists(select 1 from public.profiles p where p.id=v_director and p.is_active=true)
       or not exists(select 1 from public.profiles p where p.id=v_vice and p.is_active=true) then
      update public.staff_leave_approval_route_config
         set authority_verified=false, no_vice_director_confirmed=false,
             updated_at=statement_timestamp()
       where singleton=true;
      return new;
    end if;
  else
    if v_director is null
       or not exists(select 1 from public.profiles p where p.id=v_director and p.is_active=true) then
      update public.staff_leave_approval_route_config
         set authority_verified=false, no_vice_director_confirmed=false,
             updated_at=statement_timestamp()
       where singleton=true;
      return new;
    end if;
    v_vice := null;
  end if;

  insert into public.staff_leave_approval_route_config(
    singleton,vice_director_user_id,director_user_id,authority_verified,
    direct_to_vice_enabled,no_vice_director_confirmed,authority_reference,
    verified_by,verified_at,updated_at
  ) values (
    true,v_vice,v_director,true,false,not coalesce(v_has_vice,false),
    'school_responsibility_audit:'||new.id::text,new.actor_user_id,new.changed_at,statement_timestamp()
  )
  on conflict(singleton) do update set
    vice_director_user_id=excluded.vice_director_user_id,
    director_user_id=excluded.director_user_id,
    authority_verified=excluded.authority_verified,
    direct_to_vice_enabled=false,
    no_vice_director_confirmed=excluded.no_vice_director_confirmed,
    authority_reference=excluded.authority_reference,
    verified_by=excluded.verified_by,
    verified_at=excluded.verified_at,
    updated_at=excluded.updated_at;

  return new;
end;
$$;

drop trigger if exists staff_leave_sync_route_from_responsibility_audit
  on public.school_responsibility_audit;
create trigger staff_leave_sync_route_from_responsibility_audit
after insert on public.school_responsibility_audit
for each row execute function public.staff_leave_sync_route_from_responsibility_audit();

revoke all on function public.staff_leave_sync_route_from_responsibility_audit() from public, anon, authenticated;

-- Structural guard: the leave submit RPC and admin settings must use one route table.
do $test$
begin
  if to_regclass('public.school_responsibility_assignments') is null
     or to_regclass('public.school_responsibility_settings') is null
     or to_regclass('public.school_responsibility_audit') is null then
    raise exception 'school_responsibility_dependency_missing';
  end if;
  if not exists(select 1 from information_schema.columns
    where table_schema='public' and table_name='staff_leave_approval_route_config'
      and column_name='no_vice_director_confirmed') then
    raise exception 'explicit_no_vice_setting_missing';
  end if;
end
$test$;

commit;
