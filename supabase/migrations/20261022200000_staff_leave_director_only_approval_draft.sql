-- Draft-only change: the Director is the sole leave approver for Wat Bueng Nam Sai.
-- This migration is intentionally not applied to Production.
begin;

-- The Director is the only configured approver. The authority evidence remains
-- mandatory; this does not enable a guessed account or create delegation.
alter table public.staff_leave_approval_route_config
  drop constraint if exists staff_leave_route_verified_fields_chk;
alter table public.staff_leave_approval_route_config
  add constraint staff_leave_route_verified_fields_chk check (
    not authority_verified or (
      director_user_id is not null
      and nullif(btrim(authority_reference), '') is not null
      and verified_by is not null
      and verified_at is not null
    )
  );
alter table public.staff_leave_approval_route_config
  drop constraint if exists staff_leave_route_exception_requires_verified_chk;
alter table public.staff_leave_approval_route_config
  add constraint staff_leave_route_exception_requires_verified_chk
  check (not direct_to_vice_enabled);
alter table public.staff_leave_approval_route_config
  alter column vice_director_user_id drop not null;
alter table public.staff_leave_requests
  alter column approval_stage set default 'director_final_review';

create or replace function public.staff_leave_submit(
  p_request_id uuid,
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
  v_key text;
  v_reason text;
begin
  v_actor := auth.uid();
  if v_actor is null then
    raise exception 'authentication_required' using errcode = '28000';
  end if;
  if not exists (select 1 from public.profiles p where p.id=v_actor and p.is_active=true) then
    raise exception 'active_profile_required' using errcode = '42501';
  end if;
  if p_request_id is null then raise exception 'request_id_required' using errcode = '22023'; end if;
  if p_idempotency_key is null or length(btrim(p_idempotency_key)) < 8
     or length(btrim(p_idempotency_key)) > 120 then
    raise exception 'invalid_idempotency_key' using errcode = '22023';
  end if;
  v_key := btrim(p_idempotency_key);

  select * into v_request from public.staff_leave_requests r
  where r.id=p_request_id for update;
  if not found or v_request.applicant_id <> v_actor then
    raise exception 'leave_request_not_found_or_not_owner' using errcode = '42501';
  end if;

  if v_request.status = 'pending_approval'
     and v_request.current_approver_user_id is not null
     and exists (
       select 1 from public.staff_leave_approval_actions a
       where a.request_id=v_request.id and a.actor_id=v_actor
         and a.action='submitted' and a.metadata->>'idempotency_key'=v_key
     ) then
    return v_request.id;
  end if;
  if v_request.status = 'blocked_approver_resolution'
     and exists (
       select 1 from public.staff_leave_approval_actions a
       where a.request_id=v_request.id and a.actor_id=v_actor
         and a.action='blocked' and a.metadata->>'idempotency_key'=v_key
     ) then
    return v_request.id;
  end if;
  if v_request.status <> 'draft' then
    raise exception 'leave_request_state_not_submittable' using errcode = '55000';
  end if;

  select * into v_route from public.staff_leave_approval_route_config where singleton=true;
  if not found or not v_route.authority_verified or v_route.director_user_id is null
     or not exists (select 1 from public.profiles p
                    where p.id=v_route.director_user_id and p.is_active=true) then
    update public.staff_leave_requests set status='blocked_approver_resolution',
      submitted_at=statement_timestamp(), current_approver_user_id=null,
      updated_at=statement_timestamp() where id=v_request.id;
    insert into public.staff_leave_approval_actions(request_id,actor_id,action,reason,metadata)
    values(v_request.id,v_actor,'blocked','Director approver configuration is not verified.',
      jsonb_build_object('idempotency_key',v_key,'reason_code','approver_authority_unverified','route_resolved',false));
    insert into public.staff_leave_notification_outbox(event_key,request_id,recipient_id,event_type,channel,safe_payload,status)
    values('leave-submit-blocked:'||v_request.id::text||':'||v_key,v_request.id,v_actor,'blocked','in_app',
      jsonb_build_object('event','leave_blocked','request_id',v_request.id::text,
        'status','blocked_approver_resolution'),'pending')
    on conflict(event_key) do nothing;
    return v_request.id;
  end if;

  update public.staff_leave_requests set status='pending_approval',
    approval_stage='director_final_review', current_approver_user_id=v_route.director_user_id,
    submitted_at=statement_timestamp(), updated_at=statement_timestamp()
  where id=v_request.id;

  insert into public.staff_leave_approval_actions(request_id,actor_id,action,reason,metadata)
  values(v_request.id,v_actor,'submitted',null,
    jsonb_build_object('idempotency_key',v_key,'approver_id',v_route.director_user_id,
      'approval_route','director_only'));
  insert into public.staff_leave_notification_outbox(event_key,request_id,recipient_id,event_type,channel,safe_payload,status)
  values('leave-submit-director:'||v_request.id::text||':'||v_key,v_request.id,
    v_route.director_user_id,'submitted','in_app',
    jsonb_build_object('event','leave_submitted','request_id',v_request.id::text),'pending')
  on conflict(event_key) do nothing;
  return v_request.id;
end;
$$;

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
  v_action text;
  v_key text;
  v_prior_reason text;
  v_event_key text;
begin
  v_actor := auth.uid();
  if v_actor is null then raise exception 'authentication_required' using errcode='28000'; end if;
  if not exists (select 1 from public.profiles p where p.id=v_actor and p.is_active=true) then
    raise exception 'active_profile_required' using errcode='42501';
  end if;
  if p_request_id is null then raise exception 'request_id_required' using errcode='22023'; end if;
  if p_decision is null or p_decision not in ('approve','reject') then
    raise exception 'invalid_leave_decision' using errcode='22023';
  end if;
  if p_decision='reject' and (p_reason is null or length(btrim(p_reason))=0 or length(p_reason)>1000) then
    raise exception 'rejection_reason_required' using errcode='22023';
  end if;
  if p_decision='approve' and p_reason is not null and length(p_reason)>1000 then
    raise exception 'invalid_decision_reason' using errcode='22023';
  end if;
  if p_idempotency_key is null or length(btrim(p_idempotency_key))<8 or length(btrim(p_idempotency_key))>120 then
    raise exception 'invalid_idempotency_key' using errcode='22023';
  end if;
  v_key:=btrim(p_idempotency_key);
  v_action:=case when p_decision='approve' then 'approved' else 'rejected' end;

  select * into v_request from public.staff_leave_requests r where r.id=p_request_id for update;
  if not found then raise exception 'leave_request_not_found_or_not_assigned' using errcode='42501'; end if;
  if v_request.status in ('approved','rejected') then
    select a.reason into v_prior_reason from public.staff_leave_approval_actions a
    where a.request_id=v_request.id and a.actor_id=v_actor and a.action=v_action
      and a.metadata->>'idempotency_key'=v_key limit 1;
    if found then
      if (p_decision='approve' and v_request.status<>'approved')
         or (p_decision='reject' and v_request.status<>'rejected')
         or v_prior_reason is distinct from nullif(btrim(coalesce(p_reason,'')),'') then
        raise exception 'idempotency_key_reused_with_different_payload' using errcode='22023';
      end if;
      return v_request.id;
    end if;
  end if;
  if v_request.applicant_id=v_actor then raise exception 'self_approval_forbidden' using errcode='42501'; end if;
  if v_request.status<>'pending_approval' then
    raise exception 'leave_request_state_not_decidable' using errcode='55000';
  end if;

  select * into v_route from public.staff_leave_approval_route_config where singleton=true;
  if not found or not v_route.authority_verified or v_route.director_user_id is null
     or not exists (select 1 from public.profiles p where p.id=v_route.director_user_id and p.is_active=true) then
    raise exception 'approver_authority_unverified' using errcode='42501';
  end if;
  if v_actor is distinct from v_route.director_user_id
     or v_request.current_approver_user_id is distinct from v_route.director_user_id
     or v_request.approval_stage<>'director_final_review' then
    raise exception 'leave_request_not_found_or_not_assigned' using errcode='42501';
  end if;

  update public.staff_leave_requests set status=v_action, approval_stage='completed',
    decided_at=statement_timestamp(), updated_at=statement_timestamp() where id=v_request.id;
  insert into public.staff_leave_approval_actions(request_id,actor_id,action,reason,metadata)
  values(v_request.id,v_actor,v_action,nullif(btrim(coalesce(p_reason,'')),''),
    jsonb_build_object('idempotency_key',v_key,'decision',p_decision,'approval_route','director_only'));
  v_event_key:='leave-decision:'||v_request.id::text||':'||v_action||':'||v_key;
  insert into public.staff_leave_notification_outbox(event_key,request_id,recipient_id,event_type,channel,safe_payload,status)
  values(v_event_key,v_request.id,v_request.applicant_id,v_action,'in_app',
    jsonb_build_object('event','leave_'||v_action,'request_id',v_request.id::text),'pending')
  on conflict(event_key) do nothing;
  return v_request.id;
end;
$$;

revoke all on function public.staff_leave_submit(uuid,text) from public, anon;
grant execute on function public.staff_leave_submit(uuid,text) to authenticated;
revoke all on function public.staff_leave_decide(uuid,text,text,text) from public, anon;
grant execute on function public.staff_leave_decide(uuid,text,text,text) to authenticated;
commit;
