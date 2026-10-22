-- Draft-only correction: leave requests go to the Deputy Director for review,
-- then the Director for the final decision. Never apply to Production without review.
begin;

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
     or v_route.vice_director_user_id is null or v_route.director_user_id is null
     or v_route.vice_director_user_id=v_route.director_user_id
     or not exists (select 1 from public.profiles p where p.id=v_route.vice_director_user_id and p.is_active=true)
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
  return v_request.id;
end;
$$;

revoke all on function public.staff_leave_submit(uuid,text) from public, anon;
grant execute on function public.staff_leave_submit(uuid,text) to authenticated;
commit;
