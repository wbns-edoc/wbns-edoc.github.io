-- Draft-only submission RPC. Authority mapping is not verified, so fail closed:
-- record an explicit blocked state rather than silently assigning an approver.
-- No admin alert is enqueued until an authorized recipient mapping is verified.
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
  v_key text;
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

  v_key := btrim(p_idempotency_key);

  if v_request.status = 'blocked_approver_resolution'
     and exists (
       select 1 from public.staff_leave_approval_actions a
       where a.request_id = v_request.id
         and a.actor_id = v_actor
         and a.action = 'blocked'
         and a.metadata->>'idempotency_key' = v_key
     ) then
    return v_request.id;
  end if;

  if v_request.status <> 'draft' then
    raise exception 'leave_request_state_not_submittable' using errcode = '55000';
  end if;

  -- Do not route to the vacant Deputy Director position or assume the Director
  -- has delegated authority. Until an approved server-side authority mapping exists,
  -- preserve the request and make the unresolved route explicit.
  update public.staff_leave_requests
  set status = 'blocked_approver_resolution',
      submitted_at = statement_timestamp(),
      updated_at = statement_timestamp()
  where id = v_request.id;

  insert into public.staff_leave_approval_actions (
    request_id, actor_id, action, reason, metadata
  ) values (
    v_request.id, v_actor, 'blocked',
    'Approver authority mapping has not been verified.',
    jsonb_build_object(
      'idempotency_key', v_key,
      'reason_code', 'approver_authority_unverified',
      'route_resolved', false
    )
  );

  return v_request.id;
end;
$$;

revoke all on function public.staff_leave_submit(uuid, text) from public, anon;
grant execute on function public.staff_leave_submit(uuid, text) to authenticated;

commit;
