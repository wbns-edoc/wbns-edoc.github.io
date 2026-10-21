\set ON_ERROR_STOP on
begin;

insert into public.profiles (id, is_active) values
  ('00000000-0000-0000-0000-000000000801', true),
  ('00000000-0000-0000-0000-000000000802', true),
  ('00000000-0000-0000-0000-000000000803', true),
  ('00000000-0000-0000-0000-000000000804', false)
on conflict (id) do update set is_active = excluded.is_active;

insert into public.staff_leave_types (id, code, name, is_active)
values ('00000000-0000-0000-0000-000000000821', 'decide_test', 'Decision test', true)
on conflict (id) do update set is_active = true;

insert into public.staff_leave_requests (
  id, applicant_id, leave_type_id, starts_on, ends_on, reason, status, current_approver_user_id
) values
  ('00000000-0000-0000-0000-000000000811',
   '00000000-0000-0000-0000-000000000801',
   '00000000-0000-0000-0000-000000000821',
   date '2026-12-01', date '2026-12-01', 'synthetic approval fixture', 'pending_approval',
   '00000000-0000-0000-0000-000000000802'),
  ('00000000-0000-0000-0000-000000000812',
   '00000000-0000-0000-0000-000000000803',
   '00000000-0000-0000-0000-000000000821',
   date '2026-12-02', date '2026-12-02', 'synthetic rejection fixture', 'pending_approval',
   '00000000-0000-0000-0000-000000000802'),
  ('00000000-0000-0000-0000-000000000813',
   '00000000-0000-0000-0000-000000000802',
   '00000000-0000-0000-0000-000000000821',
   date '2026-12-03', date '2026-12-03', 'synthetic self-approval fixture', 'pending_approval',
   '00000000-0000-0000-0000-000000000802')
on conflict (id) do nothing;

set local role authenticated;
select set_config('request.jwt.claim.sub', '', true);
do $block$
begin
  begin
    perform public.staff_leave_decide(
      '00000000-0000-0000-0000-000000000811', 'approve', null, 'decide-key-unauth'
    );
    raise exception 'expected_authentication_required';
  exception when sqlstate '28000' then
    if sqlerrm <> 'authentication_required' then raise; end if;
  end;
end $block$;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000804', true);
do $block$
begin
  begin
    perform public.staff_leave_decide(
      '00000000-0000-0000-0000-000000000811', 'approve', null, 'decide-key-inactive'
    );
    raise exception 'expected_inactive_profile_denial';
  exception when sqlstate '42501' then
    if sqlerrm <> 'active_profile_required' then raise; end if;
  end;
end $block$;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000803', true);
do $block$
begin
  begin
    perform public.staff_leave_decide(
      '00000000-0000-0000-0000-000000000811', 'approve', null, 'decide-key-unassigned'
    );
    raise exception 'expected_unassigned_approver_denial';
  exception when sqlstate '42501' then
    if sqlerrm <> 'leave_request_not_found_or_not_assigned' then raise; end if;
  end;
end $block$;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000802', true);
do $block$
begin
  begin
    perform public.staff_leave_decide(
      '00000000-0000-0000-0000-000000000813', 'approve', null, 'decide-key-self'
    );
    raise exception 'expected_self_approval_denial';
  exception when sqlstate '42501' then
    if sqlerrm <> 'self_approval_forbidden' then raise; end if;
  end;
  begin
    perform public.staff_leave_decide(
      '00000000-0000-0000-0000-000000000811', null, null, 'decide-key-null'
    );
    raise exception 'expected_invalid_decision_denial';
  exception when sqlstate '22023' then
    if sqlerrm <> 'invalid_leave_decision' then raise; end if;
  end;
  begin
    perform public.staff_leave_decide(
      '00000000-0000-0000-0000-000000000812', 'reject', '   ', 'decide-key-no-reason'
    );
    raise exception 'expected_rejection_reason_required';
  exception when sqlstate '22023' then
    if sqlerrm <> 'rejection_reason_required' then raise; end if;
  end;
end $block$;

select public.staff_leave_decide(
  '00000000-0000-0000-0000-000000000811', 'approve', null, 'decide-key-approve-1'
);
-- Retry with the same key must not duplicate the audit action or outbox event.
select public.staff_leave_decide(
  '00000000-0000-0000-0000-000000000811', 'approve', null, 'decide-key-approve-1'
);
do $block$
begin
  begin
    perform public.staff_leave_decide(
      '00000000-0000-0000-0000-000000000811', 'approve', 'different payload', 'decide-key-approve-1'
    );
    raise exception 'expected_idempotency_payload_mismatch';
  exception when sqlstate '22023' then
    if sqlerrm <> 'idempotency_key_reused_with_different_payload' then raise; end if;
  end;
end $block$;
select public.staff_leave_decide(
  '00000000-0000-0000-0000-000000000812', 'reject', 'Policy requires correction', 'decide-key-reject-1'
);

reset role;
do $block$
begin
  if not exists (
    select 1 from public.staff_leave_requests
    where id = '00000000-0000-0000-0000-000000000811'
      and status = 'approved' and decided_at is not null
  ) then
    raise exception 'assigned_approver_must_approve_request';
  end if;
  if not exists (
    select 1 from public.staff_leave_requests
    where id = '00000000-0000-0000-0000-000000000812'
      and status = 'rejected' and decided_at is not null
  ) then
    raise exception 'assigned_approver_must_reject_request';
  end if;
  if (select count(*) from public.staff_leave_approval_actions
      where request_id = '00000000-0000-0000-0000-000000000811'
        and action = 'approved'
        and metadata->>'idempotency_key' = 'decide-key-approve-1') <> 1 then
    raise exception 'decision_retry_must_append_one_approval_action';
  end if;
  if (select count(*) from public.staff_leave_notification_outbox
      where request_id = '00000000-0000-0000-0000-000000000811'
        and event_type = 'approved') <> 1 then
    raise exception 'approval_must_enqueue_one_private_notification';
  end if;
  if (select count(*) from public.staff_leave_notification_outbox
      where request_id = '00000000-0000-0000-0000-000000000812'
        and event_type = 'rejected') <> 1 then
    raise exception 'rejection_must_enqueue_one_private_notification';
  end if;
  if has_function_privilege('anon', 'public.staff_leave_decide(uuid,text,text,text)', 'EXECUTE') then
    raise exception 'anon_must_not_execute_staff_leave_decide';
  end if;
  if not has_function_privilege('authenticated', 'public.staff_leave_decide(uuid,text,text,text)', 'EXECUTE') then
    raise exception 'authenticated_must_execute_staff_leave_decide';
  end if;
end $block$;

rollback;
