-- Draft-only decision RPC. Only the active, explicitly assigned approver may decide.
-- This does not establish the school's legal approval authority; assignment must be
-- produced by a separately verified routing configuration before any Production use.
begin;

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
  v_action text;
  v_target_status text;
  v_key text;
  v_event_key text;
begin
  v_actor := auth.uid();
  if v_actor is null then
    raise exception 'authentication_required' using errcode = '28000';
  end if;
  if not exists (
    select 1 from public.profiles p
    where p.id = v_actor and p.is_active = true
  ) then
    raise exception 'active_profile_required' using errcode = '42501';
  end if;
  if p_request_id is null then
    raise exception 'request_id_required' using errcode = '22023';
  end if;
  if p_decision is null or p_decision not in ('approve', 'reject') then
    raise exception 'invalid_leave_decision' using errcode = '22023';
  end if;
  if p_decision = 'reject'
     and (p_reason is null or length(btrim(p_reason)) = 0 or length(p_reason) > 1000) then
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
  v_action := case when p_decision = 'approve' then 'approved' else 'rejected' end;
  v_target_status := case when p_decision = 'approve' then 'approved' else 'rejected' end;

  select * into v_request
  from public.staff_leave_requests r
  where r.id = p_request_id
  for update;

  if not found then
    raise exception 'leave_request_not_found_or_not_assigned' using errcode = '42501';
  end if;

  -- Idempotent retry only for the exact prior decision and key.
  if v_request.status = v_target_status
     and exists (
       select 1 from public.staff_leave_approval_actions a
       where a.request_id = v_request.id
         and a.actor_id = v_actor
         and a.action = v_action
         and a.metadata->>'idempotency_key' = v_key
     ) then
    return v_request.id;
  end if;

  if v_request.applicant_id = v_actor then
    raise exception 'self_approval_forbidden' using errcode = '42501';
  end if;
  if v_request.current_approver_user_id is distinct from v_actor then
    raise exception 'leave_request_not_found_or_not_assigned' using errcode = '42501';
  end if;
  if v_request.status <> 'pending_approval' then
    raise exception 'leave_request_state_not_decidable' using errcode = '55000';
  end if;

  update public.staff_leave_requests
  set status = v_target_status,
      decided_at = statement_timestamp(),
      updated_at = statement_timestamp()
  where id = v_request.id;

  insert into public.staff_leave_approval_actions (
    request_id, actor_id, action, reason, metadata
  ) values (
    v_request.id, v_actor, v_action, nullif(btrim(coalesce(p_reason, '')), ''),
    jsonb_build_object('idempotency_key', v_key, 'decision', p_decision)
  );

  v_event_key := 'leave-decision:' || v_request.id::text || ':' || v_action || ':' || v_key;
  insert into public.staff_leave_notification_outbox (
    event_key, request_id, recipient_id, event_type, channel, safe_payload, status
  ) values (
    v_event_key, v_request.id, v_request.applicant_id, v_action, 'in_app',
    jsonb_build_object('event', 'leave_' || v_action, 'request_id', v_request.id::text),
    'pending'
  ) on conflict (event_key) do nothing;

  return v_request.id;
end;
$$;

revoke all on function public.staff_leave_decide(uuid, text, text, text) from public, anon;
grant execute on function public.staff_leave_decide(uuid, text, text, text) to authenticated;

commit;
