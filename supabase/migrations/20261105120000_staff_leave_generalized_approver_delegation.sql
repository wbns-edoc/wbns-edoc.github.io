-- Generalized, auditable acting-approver delegation.
-- Integration/CI only. Do not apply to Production until route snapshot RPCs,
-- UI, and the full regression suite are reviewed and pass.
begin;

create table if not exists public.staff_leave_approver_delegations (
  id uuid primary key default gen_random_uuid(),
  director_user_id uuid not null references public.profiles(id),
  acting_approver_user_id uuid not null references public.profiles(id),
  valid_from timestamptz not null,
  valid_until timestamptz not null,
  reason text not null,
  authority_reference text not null,
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default statement_timestamp(),
  revoked_by uuid references public.profiles(id),
  revoked_at timestamptz,
  revocation_reason text,
  constraint staff_leave_delegation_distinct_users_chk
    check (director_user_id <> acting_approver_user_id),
  constraint staff_leave_delegation_period_chk
    check (valid_until > valid_from),
  constraint staff_leave_delegation_reason_chk
    check (length(btrim(reason)) between 3 and 1000),
  constraint staff_leave_delegation_reference_chk
    check (length(btrim(authority_reference)) between 3 and 500),
  constraint staff_leave_delegation_revocation_chk check (
    (revoked_at is null and revoked_by is null and revocation_reason is null)
    or (revoked_at is not null and revoked_by is not null
        and nullif(btrim(revocation_reason),'') is not null)
  )
);
create index if not exists staff_leave_delegations_director_period_idx
  on public.staff_leave_approver_delegations(director_user_id,valid_from,valid_until)
  where revoked_at is null;
create index if not exists staff_leave_delegations_actor_period_idx
  on public.staff_leave_approver_delegations(acting_approver_user_id,valid_from,valid_until)
  where revoked_at is null;

alter table public.staff_leave_approver_delegations enable row level security;
revoke all on table public.staff_leave_approver_delegations from public,anon,authenticated;

create or replace function public.admin_create_staff_leave_approver_delegation(
  p_acting_approver_user_id uuid,
  p_valid_from timestamptz,
  p_valid_until timestamptz,
  p_reason text,
  p_authority_reference text
)
returns uuid
language plpgsql security definer
set search_path=pg_catalog,public
as $$
declare
  v_actor uuid:=auth.uid();
  v_director uuid;
  v_id uuid;
begin
  if v_actor is null then raise exception 'authentication_required' using errcode='28000'; end if;
  if not exists(select 1 from public.profiles p where p.id=v_actor and p.is_active) then
    raise exception 'active_profile_required' using errcode='42501';
  end if;
  if not exists(
    select 1 from public.user_roles ur join public.roles r on r.id=ur.role_id
    where ur.user_id=v_actor and r.code='system_admin'
  ) then raise exception 'system_admin_required' using errcode='42501'; end if;

  if p_acting_approver_user_id is null or p_valid_from is null or p_valid_until is null
     or p_valid_until<=p_valid_from then
    raise exception 'invalid_delegation_parameters' using errcode='22023';
  end if;
  if p_reason is null or length(btrim(p_reason)) not between 3 and 1000 then
    raise exception 'delegation_reason_required' using errcode='22023';
  end if;
  if p_authority_reference is null or length(btrim(p_authority_reference)) not between 3 and 500 then
    raise exception 'delegation_authority_reference_required' using errcode='22023';
  end if;

  select c.director_user_id into v_director
  from public.staff_leave_approval_route_config c
  where c.singleton=true and c.authority_verified=true
    and c.no_vice_director_confirmed=true
  for update;
  if not found or v_director is null then
    raise exception 'verified_director_only_route_required' using errcode='55000';
  end if;
  if not exists(select 1 from public.profiles p where p.id=v_director and p.is_active) then
    raise exception 'active_director_required' using errcode='55000';
  end if;
  if p_acting_approver_user_id=v_director
     or not exists(select 1 from public.profiles p where p.id=p_acting_approver_user_id and p.is_active) then
    raise exception 'active_distinct_acting_approver_required' using errcode='22023';
  end if;

  -- Serialize creates for this Director, then reject any overlapping live period.
  perform pg_advisory_xact_lock(hashtextextended(v_director::text, 0));
  if exists(
    select 1 from public.staff_leave_approver_delegations d
    where d.director_user_id=v_director and d.revoked_at is null
      and tstzrange(d.valid_from,d.valid_until,'[)') &&
          tstzrange(p_valid_from,p_valid_until,'[)')
  ) then
    raise exception 'overlapping_active_delegation_exists' using errcode='23P01';
  end if;

  insert into public.staff_leave_approver_delegations(
    director_user_id,acting_approver_user_id,valid_from,valid_until,
    reason,authority_reference,created_by
  ) values (
    v_director,p_acting_approver_user_id,p_valid_from,p_valid_until,
    btrim(p_reason),btrim(p_authority_reference),v_actor
  ) returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.admin_revoke_staff_leave_approver_delegation(
  p_delegation_id uuid,
  p_reason text
)
returns uuid
language plpgsql security definer
set search_path=pg_catalog,public
as $$
declare
  v_actor uuid:=auth.uid();
  v_row public.staff_leave_approver_delegations%rowtype;
begin
  if v_actor is null then raise exception 'authentication_required' using errcode='28000'; end if;
  if not exists(select 1 from public.profiles p where p.id=v_actor and p.is_active) then
    raise exception 'active_profile_required' using errcode='42501';
  end if;
  if not exists(
    select 1 from public.user_roles ur join public.roles r on r.id=ur.role_id
    where ur.user_id=v_actor and r.code='system_admin'
  ) then raise exception 'system_admin_required' using errcode='42501'; end if;
  if p_delegation_id is null or p_reason is null or length(btrim(p_reason)) not between 3 and 1000 then
    raise exception 'delegation_revocation_reason_required' using errcode='22023';
  end if;

  select * into v_row from public.staff_leave_approver_delegations
  where id=p_delegation_id for update;
  if not found then raise exception 'delegation_not_found' using errcode='P0002'; end if;
  if v_row.revoked_at is null then
    update public.staff_leave_approver_delegations
    set revoked_by=v_actor,revoked_at=statement_timestamp(),revocation_reason=btrim(p_reason)
    where id=v_row.id;
  end if;
  return v_row.id;
end;
$$;

create or replace function public.admin_list_staff_leave_approver_delegations()
returns table(
  id uuid,director_user_id uuid,acting_approver_user_id uuid,
  valid_from timestamptz,valid_until timestamptz,reason text,
  authority_reference text,created_by uuid,created_at timestamptz,
  revoked_by uuid,revoked_at timestamptz,revocation_reason text
)
language plpgsql security definer
set search_path=pg_catalog,public
as $$
declare v_actor uuid:=auth.uid();
begin
  if v_actor is null then raise exception 'authentication_required' using errcode='28000'; end if;
  if not exists(select 1 from public.profiles p where p.id=v_actor and p.is_active) then
    raise exception 'active_profile_required' using errcode='42501';
  end if;
  if not exists(
    select 1 from public.user_roles ur join public.roles r on r.id=ur.role_id
    where ur.user_id=v_actor and r.code='system_admin'
  ) then raise exception 'system_admin_required' using errcode='42501'; end if;
  return query select d.id,d.director_user_id,d.acting_approver_user_id,
    d.valid_from,d.valid_until,d.reason,d.authority_reference,d.created_by,d.created_at,
    d.revoked_by,d.revoked_at,d.revocation_reason
  from public.staff_leave_approver_delegations d order by d.created_at desc limit 100;
end;
$$;

create or replace function public.staff_leave_active_acting_approver(
  p_director_user_id uuid,p_at timestamptz default statement_timestamp()
)
returns table(delegation_id uuid,acting_approver_user_id uuid,valid_from timestamptz,valid_until timestamptz)
language sql stable security definer
set search_path=pg_catalog,public
as $$
  select d.id,d.acting_approver_user_id,d.valid_from,d.valid_until
  from public.staff_leave_approver_delegations d
  join public.profiles p on p.id=d.acting_approver_user_id and p.is_active=true
  where d.director_user_id=p_director_user_id and d.revoked_at is null
    and d.valid_from<=p_at and p_at<d.valid_until
  order by d.created_at desc
  limit 1
$$;

revoke all on function public.admin_create_staff_leave_approver_delegation(uuid,timestamptz,timestamptz,text,text) from public,anon;
grant execute on function public.admin_create_staff_leave_approver_delegation(uuid,timestamptz,timestamptz,text,text) to authenticated;
revoke all on function public.admin_revoke_staff_leave_approver_delegation(uuid,text) from public,anon;
grant execute on function public.admin_revoke_staff_leave_approver_delegation(uuid,text) to authenticated;
revoke all on function public.admin_list_staff_leave_approver_delegations() from public,anon;
grant execute on function public.admin_list_staff_leave_approver_delegations() to authenticated;
revoke all on function public.staff_leave_active_acting_approver(uuid,timestamptz) from public,anon,authenticated;

commit;
