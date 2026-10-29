-- Draft-only two-stage approval enforcement. Do not apply to Production.
-- Routing is fail-closed until a trusted authority mapping is explicitly verified.
begin;

alter table public.staff_leave_requests
  add column if not exists approval_stage text not null default 'vice_director_review'
  check (approval_stage in ('vice_director_review','director_final_review','completed'));

create table if not exists public.staff_leave_approval_route_config (
  singleton boolean primary key default true check (singleton),
  vice_director_user_id uuid references public.profiles(id),
  director_user_id uuid references public.profiles(id),
  authority_verified boolean not null default false,
  direct_to_vice_enabled boolean not null default false,
  authority_reference text,
  verified_by uuid references public.profiles(id),
  verified_at timestamptz,
  updated_at timestamptz not null default now(),
  constraint staff_leave_route_verified_fields_chk check (
    not authority_verified or (
      vice_director_user_id is not null and director_user_id is not null
      and vice_director_user_id <> director_user_id
      and nullif(btrim(authority_reference), '') is not null
      and verified_by is not null and verified_at is not null
    )
  ),
  constraint staff_leave_route_exception_requires_verified_chk check (
    not direct_to_vice_enabled or authority_verified
  )
);
alter table public.staff_leave_approval_route_config enable row level security;
revoke all on table public.staff_leave_approval_route_config from public, anon, authenticated;
-- Intentionally no client read/write policies or grants. Trusted administrators must
-- provision this configuration out-of-band after legal/role verification.

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
  v_event_key text;
  v_prior_reason text;
  v_next_approver uuid;
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

  select * into v_route from public.staff_leave_approval_route_config where singleton = true;
  if not found or not v_route.authority_verified then
    raise exception 'approver_authority_unverified' using errcode = '42501';
  end if;
  if not exists (select 1 from public.profiles p where p.id = v_route.director_user_id and p.is_active = true)
     or not exists (select 1 from public.profiles p where p.id = v_route.vice_director_user_id and p.is_active = true) then
    raise exception 'configured_approver_inactive_or_missing' using errcode = '42501';
  end if;

  if p_decision = 'reject' then
    if v_request.current_approver_user_id is distinct from v_actor
       or (v_request.approval_stage = 'vice_director_review' and v_actor <> v_route.vice_director_user_id)
       or (v_request.approval_stage = 'director_final_review' and v_actor <> v_route.director_user_id) then
      raise exception 'leave_request_not_found_or_not_assigned' using errcode = '42501';
    end if;
    v_action := 'rejected';
    update public.staff_leave_requests set status='rejected', approval_stage='completed',
      decided_at=statement_timestamp(), updated_at=statement_timestamp() where id=v_request.id;
  else
    if v_request.approval_stage = 'vice_director_review' then
      if v_actor <> v_route.vice_director_user_id
         or v_request.current_approver_user_id is distinct from v_actor then
        raise exception 'leave_request_not_found_or_not_assigned' using errcode = '42501';
      end if;

      -- Exceptional direct-to-Deputy final approval is only available when the
      -- trusted, verified route explicitly enables it. Default remains two-stage.
      if v_route.direct_to_vice_enabled then
        v_action := 'approved';
        update public.staff_leave_requests set status='approved', approval_stage='completed',
          decided_at=statement_timestamp(), updated_at=statement_timestamp() where id=v_request.id;
      else
        update public.staff_leave_requests set approval_stage='director_final_review',
          current_approver_user_id=v_route.director_user_id, updated_at=statement_timestamp()
          where id=v_request.id;
        insert into public.staff_leave_approval_actions(request_id,actor_id,action,reason,metadata)
        values(v_request.id,v_actor,'routed',nullif(btrim(coalesce(p_reason,'')),''),
          jsonb_build_object('idempotency_key',v_key,'decision','approve',
            'from_stage','vice_director_review','to_stage','director_final_review',
            'next_approver_id',v_route.director_user_id));
        insert into public.staff_leave_notification_outbox(event_key,request_id,recipient_id,event_type,channel,safe_payload,status)
        values('leave-stage-advance:'||v_request.id::text||':'||v_key,v_request.id,v_route.director_user_id,
          'approver_assigned','in_app',jsonb_build_object('event','leave_approver_assigned',
          'request_id',v_request.id::text,'stage','director_final_review'),'pending')
        on conflict(event_key) do nothing;
        return v_request.id;
      end if;
    elsif v_request.approval_stage = 'director_final_review' then
      if v_actor <> v_route.director_user_id
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

revoke all on function public.staff_leave_decide(uuid,text,text,text) from public, anon;
grant execute on function public.staff_leave_decide(uuid,text,text,text) to authenticated;
commit;
