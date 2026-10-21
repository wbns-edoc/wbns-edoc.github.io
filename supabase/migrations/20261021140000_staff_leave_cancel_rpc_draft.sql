-- Draft-only RPC: cancel an applicant's own leave request.
-- Late cancellation exceptions are deliberately not enabled until authorized-role
-- configuration and an audited exception workflow are implemented and verified.
-- Do not apply to Production.
begin;

create or replace function public.staff_leave_cancel(
  p_request_id uuid,
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
  v_event_key text;
  v_today_bangkok date;
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
  if p_reason is null or length(btrim(p_reason)) = 0 or length(p_reason) > 1000 then
    raise exception 'invalid_cancellation_reason' using errcode = '22023';
  end if;
  if p_idempotency_key is null or length(btrim(p_idempotency_key)) < 8
     or length(btrim(p_idempotency_key)) > 120 then
    raise exception 'invalid_idempotency_key' using errcode = '22023';
  end if;

  select * into v_request
  from public.staff_leave_requests r
  where r.id = p_request_id
  for update;

  if not found or v_request.applicant_id <> v_actor then
    raise exception 'leave_request_not_found_or_not_owner' using errcode = '42501';
  end if;

  v_event_key := 'leave-cancel:' || v_request.id::text || ':' || btrim(p_idempotency_key);

  -- A retry with the same key is a no-op only if this exact cancellation was recorded.
  if v_request.status = 'cancelled' then
    if exists (
      select 1 from public.staff_leave_approval_actions a
      where a.request_id = v_request.id
        and a.actor_id = v_actor
        and a.action = 'cancelled'
        and a.metadata->>'idempotency_key' = btrim(p_idempotency_key)
    ) then
      return v_request.id;
    end if;
    raise exception 'leave_request_already_cancelled' using errcode = '55000';
  end if;

  if v_request.status not in ('draft', 'blocked_approver_resolution', 'submitted', 'pending_approval') then
    raise exception 'leave_request_state_not_cancellable' using errcode = '55000';
  end if;

  -- Drafts can be discarded at any time. Submitted requests must be cancelled
  -- no later than the calendar day before leave starts in the school timezone.
  v_today_bangkok := (statement_timestamp() at time zone 'Asia/Bangkok')::date;
  if v_request.status <> 'draft'
     and v_today_bangkok > (v_request.starts_on - 1) then
    raise exception 'cancellation_cutoff_passed' using errcode = '22023';
  end if;

  update public.staff_leave_requests
  set status = 'cancelled',
      cancellation_reason = btrim(p_reason),
      cancelled_at = statement_timestamp(),
      updated_at = statement_timestamp()
  where id = v_request.id;

  insert into public.staff_leave_approval_actions (
    request_id, actor_id, action, reason, metadata
  ) values (
    v_request.id, v_actor, 'cancelled', btrim(p_reason),
    jsonb_build_object('idempotency_key', btrim(p_idempotency_key), 'timezone', 'Asia/Bangkok')
  );

  insert into public.staff_leave_notification_outbox (
    event_key, request_id, recipient_id, event_type, channel, safe_payload, status
  ) values (
    v_event_key, v_request.id, v_actor, 'cancelled', 'in_app',
    jsonb_build_object('event', 'leave_cancelled', 'request_id', v_request.id::text),
    'pending'
  ) on conflict (event_key) do nothing;

  return v_request.id;
end;
$$;

revoke all on function public.staff_leave_cancel(uuid, text, text) from public, anon;
grant execute on function public.staff_leave_cancel(uuid, text, text) to authenticated;

commit;
