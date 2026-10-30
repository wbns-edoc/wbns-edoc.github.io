-- Draft-only, auditable Director-absence evidence for exceptional direct Vice approval.
begin;

create table if not exists public.staff_leave_director_absence_evidence (
  id uuid primary key default gen_random_uuid(),
  director_user_id uuid not null references public.profiles(id),
  vice_director_user_id uuid not null references public.profiles(id),
  absence_start date not null,
  absence_end date not null,
  reason text not null,
  authority_reference text not null,
  recorded_by uuid not null references public.profiles(id),
  recorded_at timestamptz not null default statement_timestamp(),
  revoked_by uuid references public.profiles(id),
  revoked_at timestamptz,
  revocation_reason text,
  constraint staff_leave_director_absence_dates_chk check (absence_end >= absence_start),
  constraint staff_leave_director_absence_distinct_users_chk check (director_user_id <> vice_director_user_id),
  constraint staff_leave_director_absence_revocation_chk check (
    (revoked_at is null and revoked_by is null and revocation_reason is null)
    or (revoked_at is not null and revoked_by is not null and nullif(btrim(revocation_reason),'') is not null)
  )
);
create index if not exists staff_leave_director_absence_active_idx
  on public.staff_leave_director_absence_evidence(director_user_id,vice_director_user_id,absence_start,absence_end)
  where revoked_at is null;
alter table public.staff_leave_director_absence_evidence enable row level security;
revoke all on table public.staff_leave_director_absence_evidence from public,anon,authenticated;

create or replace function public.admin_record_staff_leave_director_absence(
  p_absence_start date,
  p_absence_end date,
  p_reason text,
  p_authority_reference text
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_actor uuid;
  v_route public.staff_leave_approval_route_config%rowtype;
  v_id uuid;
begin
  v_actor:=auth.uid();
  if v_actor is null then raise exception 'authentication_required' using errcode='28000'; end if;
  if not exists(select 1 from public.profiles p where p.id=v_actor and p.is_active=true) then
    raise exception 'active_profile_required' using errcode='42501';
  end if;
  if not exists(
    select 1 from public.user_roles ur join public.roles r on r.id=ur.role_id
    where ur.user_id=v_actor and r.code='system_admin'
  ) then raise exception 'system_admin_required' using errcode='42501'; end if;
  if p_absence_start is null or p_absence_end is null or p_absence_end<p_absence_start then
    raise exception 'invalid_absence_date_range' using errcode='22023';
  end if;
  if p_reason is null or length(btrim(p_reason))=0 or length(p_reason)>1000 then
    raise exception 'absence_reason_required' using errcode='22023';
  end if;
  if p_authority_reference is null or length(btrim(p_authority_reference))=0 or length(p_authority_reference)>500 then
    raise exception 'absence_authority_reference_required' using errcode='22023';
  end if;

  select * into v_route
  from public.staff_leave_approval_route_config
  where singleton=true and authority_verified=true
  for update;
  if not found or v_route.no_vice_director_confirmed
     or v_route.director_user_id is null or v_route.vice_director_user_id is null then
    raise exception 'verified_director_and_vice_assignment_required' using errcode='55000';
  end if;
  if not exists(select 1 from public.profiles p where p.id=v_route.director_user_id and p.is_active=true)
     or not exists(select 1 from public.profiles p where p.id=v_route.vice_director_user_id and p.is_active=true) then
    raise exception 'configured_approver_inactive_or_missing' using errcode='42501';
  end if;

  if exists(
    select 1 from public.staff_leave_director_absence_evidence e
    where e.director_user_id=v_route.director_user_id
      and e.vice_director_user_id=v_route.vice_director_user_id
      and e.revoked_at is null
      and daterange(e.absence_start,e.absence_end,'[]') && daterange(p_absence_start,p_absence_end,'[]')
  ) then raise exception 'overlapping_director_absence_evidence_exists' using errcode='23505'; end if;

  insert into public.staff_leave_director_absence_evidence(
    director_user_id,vice_director_user_id,absence_start,absence_end,
    reason,authority_reference,recorded_by
  ) values(
    v_route.director_user_id,v_route.vice_director_user_id,p_absence_start,p_absence_end,
    btrim(p_reason),btrim(p_authority_reference),v_actor
  ) returning id into v_id;

  update public.staff_leave_approval_route_config
     set direct_to_vice_enabled=true,updated_at=statement_timestamp()
   where singleton=true;
  return v_id;
end;
$$;

create or replace function public.admin_revoke_staff_leave_director_absence(
  p_absence_id uuid,
  p_reason text
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_actor uuid;
  v_row public.staff_leave_director_absence_evidence%rowtype;
begin
  v_actor:=auth.uid();
  if v_actor is null then raise exception 'authentication_required' using errcode='28000'; end if;
  if not exists(select 1 from public.profiles p where p.id=v_actor and p.is_active=true) then
    raise exception 'active_profile_required' using errcode='42501';
  end if;
  if not exists(
    select 1 from public.user_roles ur join public.roles r on r.id=ur.role_id
    where ur.user_id=v_actor and r.code='system_admin'
  ) then raise exception 'system_admin_required' using errcode='42501'; end if;
  if p_absence_id is null or p_reason is null or length(btrim(p_reason))=0 or length(p_reason)>1000 then
    raise exception 'absence_revocation_reason_required' using errcode='22023';
  end if;

  select * into v_row from public.staff_leave_director_absence_evidence
  where id=p_absence_id for update;
  if not found then raise exception 'absence_evidence_not_found' using errcode='P0002'; end if;
  if v_row.revoked_at is not null then return v_row.id; end if;

  update public.staff_leave_director_absence_evidence
     set revoked_by=v_actor,revoked_at=statement_timestamp(),revocation_reason=btrim(p_reason)
   where id=v_row.id;

  if not exists(
    select 1 from public.staff_leave_director_absence_evidence e
    where e.director_user_id=v_row.director_user_id
      and e.vice_director_user_id=v_row.vice_director_user_id
      and e.revoked_at is null
      and e.absence_start <= (statement_timestamp() at time zone 'Asia/Bangkok')::date
      and e.absence_end >= (statement_timestamp() at time zone 'Asia/Bangkok')::date
  ) then
    update public.staff_leave_approval_route_config
       set direct_to_vice_enabled=false,updated_at=statement_timestamp()
     where singleton=true;
  end if;
  return v_row.id;
end;
$$;

create or replace function public.admin_list_staff_leave_director_absences()
returns table(
  id uuid,
  director_user_id uuid,
  vice_director_user_id uuid,
  absence_start date,
  absence_end date,
  reason text,
  authority_reference text,
  recorded_at timestamptz,
  revoked_at timestamptz,
  revocation_reason text
)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare v_actor uuid;
begin
  v_actor:=auth.uid();
  if v_actor is null then raise exception 'authentication_required' using errcode='28000'; end if;
  if not exists(select 1 from public.profiles p where p.id=v_actor and p.is_active=true) then
    raise exception 'active_profile_required' using errcode='42501';
  end if;
  if not exists(
    select 1 from public.user_roles ur join public.roles r on r.id=ur.role_id
    where ur.user_id=v_actor and r.code='system_admin'
  ) then raise exception 'system_admin_required' using errcode='42501'; end if;
  return query
    select e.id,e.director_user_id,e.vice_director_user_id,e.absence_start,e.absence_end,
           e.reason,e.authority_reference,e.recorded_at,e.revoked_at,e.revocation_reason
    from public.staff_leave_director_absence_evidence e
    order by e.recorded_at desc
    limit 30;
end;
$$;

revoke all on function public.admin_record_staff_leave_director_absence(date,date,text,text) from public,anon;
grant execute on function public.admin_record_staff_leave_director_absence(date,date,text,text) to authenticated;
revoke all on function public.admin_list_staff_leave_director_absences() from public,anon;
grant execute on function public.admin_list_staff_leave_director_absences() to authenticated;
revoke all on function public.admin_revoke_staff_leave_director_absence(uuid,text) from public,anon;
grant execute on function public.admin_revoke_staff_leave_director_absence(uuid,text) to authenticated;

create or replace function public.staff_leave_decide(
  p_request_id uuid,
  p_decision text,
  p_reason text,
  p_idempotency_key text
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_actor uuid;
  v_request public.staff_leave_requests%rowtype;
  v_route public.staff_leave_approval_route_config%rowtype;
  v_snapshot_director uuid;
  v_snapshot_vice uuid;
  v_snapshot_kind text;
  v_snapshot_authority_reference text;
  v_action text;
  v_key text;
  v_event_key text;
  v_prior_reason text;
  v_next_approver uuid;
  v_absence_id uuid;
  v_absence_reference text;
  v_absence_start date;
  v_absence_end date;
begin
  v_actor := auth.uid();
  if v_actor is null then
    raise exception 'authentication_required' using errcode = '28000';
  end if;
  if not exists (select 1 from public.profiles p where p.id = v_actor and p.is_active = true) then
    raise exception 'active_profile_required' using errcode = '42501';
  end if;
  if p_request_id is null then raise exception 'request_id_required' using errcode = '22023'; end if;
  if p_decision is null or p_decision not in ('approve','reject') then
    raise exception 'invalid_leave_decision' using errcode = '22023';
  end if;
  if p_decision = 'reject' and (p_reason is null or length(btrim(p_reason)) = 0 or length(p_reason) > 1000) then
    raise exception 'rejection_reason_required' using errcode = '22023';
  end if;
  if p_decision = 'approve' and p_reason is not null and length(p_reason) > 1000 then
    raise exception 'invalid_decision_reason' using errcode = '22023';
  end if;
  if p_idempotency_key is null or length(btrim(p_idempotency_key)) < 8
     or length(btrim(p_idempotency_key)) > 120 then
    raise exception 'invalid_idempotency_key' using errcode = '22023';
  end if;
  v_key := btrim(p_idempotency_key);

  select * into v_request from public.staff_leave_requests r where r.id = p_request_id for update;
  if not found then raise exception 'leave_request_not_found_or_not_assigned' using errcode = '42501'; end if;

  -- Idempotent retry is accepted only for the exact actor/action/key/reason and final state.
  -- A retry of the exact Deputy→Director transition is idempotent too.
  if p_decision = 'approve' and v_request.status = 'pending_approval'
     and v_request.approval_stage = 'director_final_review' then
    select a.reason into v_prior_reason from public.staff_leave_approval_actions a
    where a.request_id = v_request.id and a.actor_id = v_actor and a.action = 'routed'
      and a.metadata->>'idempotency_key' = v_key limit 1;
    if found then
      if v_prior_reason is distinct from nullif(btrim(coalesce(p_reason,'')), '') then
        raise exception 'idempotency_key_reused_with_different_payload' using errcode = '22023';
      end if;
      return v_request.id;
    end if;
  end if;

  if v_request.status in ('approved','rejected') then
    v_action := case when p_decision = 'approve' then 'approved' else 'rejected' end;
    select a.reason into v_prior_reason from public.staff_leave_approval_actions a
    where a.request_id = v_request.id and a.actor_id = v_actor and a.action = v_action
      and a.metadata->>'idempotency_key' = v_key limit 1;
    if found then
      if (p_decision = 'approve' and v_request.status <> 'approved')
         or (p_decision = 'reject' and v_request.status <> 'rejected')
         or v_prior_reason is distinct from nullif(btrim(coalesce(p_reason,'')), '') then
        raise exception 'idempotency_key_reused_with_different_payload' using errcode = '22023';
      end if;
      return v_request.id;
    end if;
  end if;

  if v_request.applicant_id = v_actor then raise exception 'self_approval_forbidden' using errcode = '42501'; end if;
  if v_request.status <> 'pending_approval' then
    raise exception 'leave_request_state_not_decidable' using errcode = '55000';
  end if;

  -- In-flight decisions must use the immutable route captured at submission,
  -- never the mutable singleton configuration for later requests.
  v_snapshot_kind := v_request.approval_route_snapshot->>'route_kind';
  v_snapshot_director := nullif(v_request.approval_route_snapshot->>'director_user_id','')::uuid;
  v_snapshot_vice := nullif(v_request.approval_route_snapshot->>'vice_director_user_id','')::uuid;
  v_snapshot_authority_reference := v_request.approval_route_snapshot->>'authority_reference';

  if v_snapshot_kind not in ('vice_director_then_director','director_only_confirmed_no_vice')
     or v_snapshot_director is null
     or nullif(v_snapshot_authority_reference,'') is null
     or nullif(v_request.approval_route_snapshot->>'authority_verified_by','') is null
     or nullif(v_request.approval_route_snapshot->>'authority_verified_at','') is null then
    raise exception 'approver_authority_unverified' using errcode = '42501';
  end if;
  if not exists (select 1 from public.profiles p where p.id=v_snapshot_director and p.is_active=true)
     or (v_snapshot_kind='vice_director_then_director' and
       (v_snapshot_vice is null or not exists(
         select 1 from public.profiles p where p.id=v_snapshot_vice and p.is_active=true
       )))
     or (v_snapshot_kind='director_only_confirmed_no_vice' and v_snapshot_vice is not null) then
    raise exception 'configured_approver_inactive_or_missing' using errcode = '42501';
  end if;

  if p_decision = 'reject' then
    -- The Deputy Director may review and forward only; final rejection belongs
    -- exclusively to the Director at the director_final_review stage.
    if v_request.approval_stage <> 'director_final_review'
       or v_actor <> v_snapshot_director
       or v_request.current_approver_user_id is distinct from v_actor then
      raise exception 'leave_request_not_found_or_not_assigned' using errcode = '42501';
    end if;
    v_action := 'rejected';
    update public.staff_leave_requests set status='rejected', approval_stage='completed',
      decided_at=statement_timestamp(), updated_at=statement_timestamp() where id=v_request.id;
  else
    if v_request.approval_stage = 'vice_director_review' then
      if v_snapshot_vice is null or v_actor <> v_snapshot_vice
         or v_request.current_approver_user_id is distinct from v_actor then
        raise exception 'leave_request_not_found_or_not_assigned' using errcode = '42501';
      end if;
      -- Direct Vice Director approval is permitted only when a System Admin
      -- recorded an active, date-bounded absence evidence record for this Director.
      select e.id,e.authority_reference,e.absence_start,e.absence_end
        into v_absence_id,v_absence_reference,v_absence_start,v_absence_end
      from public.staff_leave_director_absence_evidence e
      where e.director_user_id=v_snapshot_director
        and e.vice_director_user_id=v_actor
        and e.revoked_at is null
        and e.absence_start <= (statement_timestamp() at time zone 'Asia/Bangkok')::date
        and e.absence_end >= (statement_timestamp() at time zone 'Asia/Bangkok')::date
      order by e.recorded_at desc
      limit 1;
      if found then
        v_action := 'approved';
        update public.staff_leave_requests
           set status='approved',approval_stage='completed',
               current_approver_user_id=null,
               decided_at=statement_timestamp(),updated_at=statement_timestamp()
         where id=v_request.id;

        insert into public.staff_leave_approval_actions(request_id,actor_id,action,reason,metadata)
        values(v_request.id,v_actor,'approved',nullif(btrim(coalesce(p_reason,'')),''),
          jsonb_build_object(
            'idempotency_key',v_key,
            'decision','approve',
            'stage','vice_director_review',
            'director_absence_override',true,
            'absence_evidence_id',v_absence_id,
            'absence_authority_reference',v_absence_reference,
            'absence_start',v_absence_start,
            'absence_end',v_absence_end
          ));

        v_event_key := 'leave-decision:'||v_request.id::text||':approved:'||v_key;
        insert into public.staff_leave_notification_outbox(
          event_key,request_id,recipient_id,event_type,channel,safe_payload,status
        ) values(
          v_event_key,v_request.id,v_request.applicant_id,'approved','in_app',
          jsonb_build_object('event','leave_approved','request_id',v_request.id::text),
          'pending'
        ) on conflict(event_key) do nothing;
        return v_request.id;
      end if;

      update public.staff_leave_requests set approval_stage='director_final_review',
        current_approver_user_id=v_snapshot_director, updated_at=statement_timestamp()
        where id=v_request.id;
      insert into public.staff_leave_approval_actions(request_id,actor_id,action,reason,metadata)
      values(v_request.id,v_actor,'routed',nullif(btrim(coalesce(p_reason,'')),''),
        jsonb_build_object('idempotency_key',v_key,'decision','approve',
          'from_stage','vice_director_review','to_stage','director_final_review',
          'next_approver_id',v_snapshot_director));
      insert into public.staff_leave_notification_outbox(event_key,request_id,recipient_id,event_type,channel,safe_payload,status)
      values('leave-stage-advance:'||v_request.id::text||':'||v_key,v_request.id,v_snapshot_director,
        'approver_assigned','in_app',jsonb_build_object('event','leave_approver_assigned',
        'request_id',v_request.id::text,'stage','director_final_review'),'pending')
      on conflict(event_key) do nothing;
      return v_request.id;
    elsif v_request.approval_stage = 'director_final_review' then
      if v_actor <> v_snapshot_director
         or v_request.current_approver_user_id is distinct from v_actor then
        raise exception 'leave_request_not_found_or_not_assigned' using errcode = '42501';
      end if;
      v_action := 'approved';
      update public.staff_leave_requests set status='approved', approval_stage='completed',
        decided_at=statement_timestamp(), updated_at=statement_timestamp() where id=v_request.id;
    else
      raise exception 'leave_request_state_not_decidable' using errcode = '55000';
    end if;
  end if;

  insert into public.staff_leave_approval_actions(request_id,actor_id,action,reason,metadata)
  values(v_request.id,v_actor,v_action,nullif(btrim(coalesce(p_reason,'')),''),
    jsonb_build_object('idempotency_key',v_key,'decision',p_decision,'stage',v_request.approval_stage));
  v_event_key := 'leave-decision:'||v_request.id::text||':'||v_action||':'||v_key;
  insert into public.staff_leave_notification_outbox(event_key,request_id,recipient_id,event_type,channel,safe_payload,status)
  values(v_event_key,v_request.id,v_request.applicant_id,v_action,'in_app',
    jsonb_build_object('event','leave_'||v_action,'request_id',v_request.id::text),'pending')
  on conflict(event_key) do nothing;
  return v_request.id;
end;
$$;

revoke all on function public.staff_leave_decide(uuid,text,text,text) from public,anon;
grant execute on function public.staff_leave_decide(uuid,text,text,text) to authenticated;

commit;
