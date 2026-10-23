-- Draft-only immutable route snapshot; do not apply to Production.
begin;
alter table public.staff_leave_requests add column if not exists approval_route_snapshot jsonb;
alter table public.staff_leave_requests drop constraint if exists staff_leave_route_snapshot_shape_chk;
alter table public.staff_leave_requests add constraint staff_leave_route_snapshot_shape_chk check (
 approval_route_snapshot is null or (
  jsonb_typeof(approval_route_snapshot)='object'
  and approval_route_snapshot->>'version'='1'
  and approval_route_snapshot->>'route_kind' in ('vice_director_then_director','director_only_confirmed_no_vice')
  and nullif(approval_route_snapshot->>'director_user_id','') is not null
  and nullif(approval_route_snapshot->>'authority_reference','') is not null
  and nullif(approval_route_snapshot->>'authority_verified_by','') is not null
  and nullif(approval_route_snapshot->>'authority_verified_at','') is not null
  and nullif(approval_route_snapshot->>'captured_at','') is not null
  and ((approval_route_snapshot->>'route_kind'='director_only_confirmed_no_vice'
        and approval_route_snapshot->'vice_director_user_id'='null'::jsonb)
    or (approval_route_snapshot->>'route_kind'='vice_director_then_director'
        and nullif(approval_route_snapshot->>'vice_director_user_id','') is not null
        and approval_route_snapshot->>'vice_director_user_id'<>approval_route_snapshot->>'director_user_id'))
 ));
create or replace function public.staff_leave_submit(p_request_id uuid,p_idempotency_key text)
returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$

declare
  v_actor uuid;
  v_request public.staff_leave_requests%rowtype;
  v_route public.staff_leave_approval_route_config%rowtype;
  v_key text;
begin
  v_actor := auth.uid();
  if v_actor is null then raise exception 'authentication_required' using errcode='28000'; end if;
  if not exists (select 1 from public.profiles p where p.id=v_actor and p.is_active=true) then
    raise exception 'active_profile_required' using errcode='42501';
  end if;
  if p_request_id is null then raise exception 'request_id_required' using errcode='22023'; end if;
  if p_idempotency_key is null or length(btrim(p_idempotency_key))<8
     or length(btrim(p_idempotency_key))>120 then
    raise exception 'invalid_idempotency_key' using errcode='22023';
  end if;
  v_key:=btrim(p_idempotency_key);

  select * into v_request from public.staff_leave_requests r
  where r.id=p_request_id for update;
  if not found or v_request.applicant_id<>v_actor then
    raise exception 'leave_request_not_found_or_not_owner' using errcode='42501';
  end if;

  if v_request.status='pending_approval'
     and v_request.current_approver_user_id is not null
     and exists (select 1 from public.staff_leave_approval_actions a
       where a.request_id=v_request.id and a.actor_id=v_actor and a.action='submitted'
         and a.metadata->>'idempotency_key'=v_key) then
    return v_request.id;
  end if;
  if v_request.status='blocked_approver_resolution'
     and exists (select 1 from public.staff_leave_approval_actions a
       where a.request_id=v_request.id and a.actor_id=v_actor and a.action='blocked'
         and a.metadata->>'idempotency_key'=v_key) then
    return v_request.id;
  end if;
  if v_request.status<>'draft' then
    raise exception 'leave_request_state_not_submittable' using errcode='55000';
  end if;

  select * into v_route from public.staff_leave_approval_route_config where singleton=true;
  if not found or not v_route.authority_verified
     or v_route.director_user_id is null
     or (v_route.no_vice_director_confirmed and v_route.vice_director_user_id is not null)
     or (not v_route.no_vice_director_confirmed and
       (v_route.vice_director_user_id is null
        or v_route.vice_director_user_id=v_route.director_user_id
        or not exists (select 1 from public.profiles p where p.id=v_route.vice_director_user_id and p.is_active=true)))
     or not exists (select 1 from public.profiles p where p.id=v_route.director_user_id and p.is_active=true) then
    update public.staff_leave_requests set status='blocked_approver_resolution',
      submitted_at=statement_timestamp(), current_approver_user_id=null,
      updated_at=statement_timestamp() where id=v_request.id;
    insert into public.staff_leave_approval_actions(request_id,actor_id,action,reason,metadata)
    values(v_request.id,v_actor,'blocked','Approver configuration is missing or unverified.',
      jsonb_build_object('idempotency_key',v_key,'reason_code','approver_authority_unverified','route_resolved',false));
    insert into public.staff_leave_notification_outbox(event_key,request_id,recipient_id,event_type,channel,safe_payload,status)
    values('leave-submit-blocked:'||v_request.id::text||':'||v_key,v_request.id,v_actor,'blocked','in_app',
      jsonb_build_object('event','leave_blocked','request_id',v_request.id::text,
        'status','blocked_approver_resolution'),'pending')
    on conflict(event_key) do nothing;
    return v_request.id;
  end if;

  -- Freeze the verified route in the same transaction as submission.
  update public.staff_leave_requests
  set approval_route_snapshot = jsonb_build_object(
    'version', 1,
    'route_kind', case when v_route.no_vice_director_confirmed then
      'director_only_confirmed_no_vice' else 'vice_director_then_director' end,
    'vice_director_user_id', v_route.vice_director_user_id,
    'director_user_id', v_route.director_user_id,
    'authority_reference', v_route.authority_reference,
    'authority_verified_by', v_route.verified_by,
    'authority_verified_at', v_route.verified_at,
    'captured_at', statement_timestamp()
  ), updated_at = statement_timestamp() where id = v_request.id;

  if v_route.no_vice_director_confirmed then
    update public.staff_leave_requests set status='pending_approval',
      approval_stage='director_final_review',
      current_approver_user_id=v_route.director_user_id,
      submitted_at=statement_timestamp(),updated_at=statement_timestamp()
    where id=v_request.id;

    insert into public.staff_leave_approval_actions(request_id,actor_id,action,reason,metadata)
    values(v_request.id,v_actor,'submitted',null,
      jsonb_build_object('idempotency_key',v_key,'approver_id',v_route.director_user_id,
        'approval_route','director_only_confirmed_no_vice'));
    insert into public.staff_leave_notification_outbox(event_key,request_id,recipient_id,event_type,channel,safe_payload,status)
    values('leave-submit-director:'||v_request.id::text||':'||v_key,v_request.id,
      v_route.director_user_id,'submitted','in_app',
      jsonb_build_object('event','leave_submitted','request_id',v_request.id::text,
        'stage','director_final_review'),'pending')
    on conflict(event_key) do nothing;
  else
    update public.staff_leave_requests set status='pending_approval',
      approval_stage='vice_director_review',
      current_approver_user_id=v_route.vice_director_user_id,
      submitted_at=statement_timestamp(),updated_at=statement_timestamp()
    where id=v_request.id;

    insert into public.staff_leave_approval_actions(request_id,actor_id,action,reason,metadata)
    values(v_request.id,v_actor,'submitted',null,
      jsonb_build_object('idempotency_key',v_key,'approver_id',v_route.vice_director_user_id,
        'approval_route','vice_director_then_director'));
    insert into public.staff_leave_notification_outbox(event_key,request_id,recipient_id,event_type,channel,safe_payload,status)
    values('leave-submit-vice:'||v_request.id::text||':'||v_key,v_request.id,
      v_route.vice_director_user_id,'submitted','in_app',
      jsonb_build_object('event','leave_submitted','request_id',v_request.id::text,
        'stage','vice_director_review'),'pending')
    on conflict(event_key) do nothing;
  end if;
  return v_request.id;
end;
$$;
create or replace function public.staff_leave_decide(p_request_id uuid,p_decision text,p_reason text,p_idempotency_key text)
returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$

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

  -- Never re-read mutable singleton config for an in-flight request.
  if v_request.approval_route_snapshot is null
     or v_request.approval_route_snapshot->>'version' <> '1'
     or v_request.approval_route_snapshot->>'route_kind' not in
       ('vice_director_then_director','director_only_confirmed_no_vice') then
    raise exception 'approver_route_snapshot_missing_or_invalid' using errcode = '42501';
  end if;
  v_route.director_user_id := nullif(v_request.approval_route_snapshot->>'director_user_id','')::uuid;
  v_route.vice_director_user_id := nullif(v_request.approval_route_snapshot->>'vice_director_user_id','')::uuid;
  v_route.authority_verified := true;
  v_route.no_vice_director_confirmed := v_request.approval_route_snapshot->>'route_kind' = 'director_only_confirmed_no_vice';
  if v_route.director_user_id is null
     or (v_route.no_vice_director_confirmed and v_route.vice_director_user_id is not null)
     or (not v_route.no_vice_director_confirmed and
       (v_route.vice_director_user_id is null or v_route.vice_director_user_id = v_route.director_user_id)) then
    raise exception 'approver_route_snapshot_missing_or_invalid' using errcode = '42501';
  end if;
  if not exists (select 1 from public.profiles p where p.id = v_route.director_user_id and p.is_active = true)
     or (not v_route.no_vice_director_confirmed and
       not exists (select 1 from public.profiles p where p.id = v_route.vice_director_user_id and p.is_active = true)) then
    raise exception 'configured_approver_inactive_or_missing' using errcode = '42501';
  end if;

  if p_decision = 'reject' then
    -- The Deputy Director may review and forward only; final rejection belongs
    -- exclusively to the Director at the director_final_review stage.
    if v_request.approval_stage <> 'director_final_review'
       or v_actor <> v_route.director_user_id
       or v_request.current_approver_user_id is distinct from v_actor then
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
revoke all on function public.staff_leave_submit(uuid,text) from public,anon;
grant execute on function public.staff_leave_submit(uuid,text) to authenticated;
revoke all on function public.staff_leave_decide(uuid,text,text,text) from public,anon;
grant execute on function public.staff_leave_decide(uuid,text,text,text) to authenticated;
commit;
