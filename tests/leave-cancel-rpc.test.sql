\set ON_ERROR_STOP on
begin;

insert into public.profiles (id, is_active) values
  ('00000000-0000-0000-0000-000000000301', true),
  ('00000000-0000-0000-0000-000000000302', true),
  ('00000000-0000-0000-0000-000000000303', false)
on conflict (id) do update set is_active = excluded.is_active;

insert into public.staff_leave_types (id, code, name, is_active)
values ('00000000-0000-0000-0000-000000000401', 'cancel_test', 'Cancellation test', true)
on conflict (id) do update set is_active = true;

insert into public.staff_leave_requests (
  id, applicant_id, leave_type_id, starts_on, ends_on, reason, status
) values
  ('00000000-0000-0000-0000-000000000501',
   '00000000-0000-0000-0000-000000000301',
   '00000000-0000-0000-0000-000000000401',
   (now() at time zone 'Asia/Bangkok')::date + 10,
   (now() at time zone 'Asia/Bangkok')::date + 10,
   'fixture future request', 'pending_approval'),
  ('00000000-0000-0000-0000-000000000502',
   '00000000-0000-0000-0000-000000000301',
   '00000000-0000-0000-0000-000000000401',
   (now() at time zone 'Asia/Bangkok')::date,
   (now() at time zone 'Asia/Bangkok')::date,
   'fixture cutoff request', 'pending_approval'),
  ('00000000-0000-0000-0000-000000000503',
   '00000000-0000-0000-0000-000000000301',
   '00000000-0000-0000-0000-000000000401',
   (now() at time zone 'Asia/Bangkok')::date - 10,
   (now() at time zone 'Asia/Bangkok')::date - 10,
   'fixture draft', 'draft'),
  ('00000000-0000-0000-0000-000000000504',
   '00000000-0000-0000-0000-000000000301',
   '00000000-0000-0000-0000-000000000401',
   (now() at time zone 'Asia/Bangkok')::date + 1,
   (now() at time zone 'Asia/Bangkok')::date + 1,
   'fixture exact cutoff boundary', 'pending_approval')
on conflict (id) do nothing;

-- Simulate a request assigned to another active user so cancellation must notify
-- both the applicant and the known current approver.
update public.staff_leave_requests
set current_approver_user_id = '00000000-0000-0000-0000-000000000302'
where id = '00000000-0000-0000-0000-000000000501';

set local role authenticated;
select set_config('request.jwt.claim.sub', '', true);
do $block$
begin
  begin
    perform public.staff_leave_cancel(
      '00000000-0000-0000-0000-000000000501', 'test', 'cancel-key-unauth'
    );
    raise exception 'expected_authentication_required';
  exception when sqlstate '28000' then
    if sqlerrm <> 'authentication_required' then raise; end if;
  end;
end $block$;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000301', true);
select public.staff_leave_cancel(
  '00000000-0000-0000-0000-000000000501', 'เปลี่ยนแผนการลา', 'cancel-key-0001'
);

-- Same request + same idempotency key is safe to retry without duplicate history/outbox.
select public.staff_leave_cancel(
  '00000000-0000-0000-0000-000000000501', 'เปลี่ยนแผนการลา', 'cancel-key-0001'
);

do $block$
begin
  begin
    perform public.staff_leave_cancel(
      '00000000-0000-0000-0000-000000000501', 'ข้อความเปลี่ยนไป', 'cancel-key-0001'
    );
    raise exception 'expected_idempotency_payload_mismatch';
  exception when sqlstate '22023' then
    if sqlerrm <> 'idempotency_key_reused_with_different_payload' then raise; end if;
  end;
end $block$;

do $block$
begin
  if (select count(*) from public.staff_leave_approval_actions
      where request_id = '00000000-0000-0000-0000-000000000501'
        and action = 'cancelled') <> 1 then
    raise exception 'cancellation_retry_must_not_duplicate_action';
  end if;
end $block$;

-- Inspect the private outbox as the migration/test owner, not as authenticated.
-- The production role intentionally has no SELECT privilege on this table.
reset role;
do $block$
begin
  if (select count(*) from public.staff_leave_notification_outbox
      where event_key = 'leave-cancel:00000000-0000-0000-0000-000000000501:cancel-key-0001'
        and recipient_id = '00000000-0000-0000-0000-000000000301'
        and event_type = 'cancelled') <> 1 then
    raise exception 'cancellation_retry_must_not_duplicate_applicant_outbox';
  end if;
  if (select count(*) from public.staff_leave_notification_outbox
      where event_key = 'leave-cancel-approver:00000000-0000-0000-0000-000000000501:cancel-key-0001'
        and recipient_id = '00000000-0000-0000-0000-000000000302'
        and event_type = 'cancelled') <> 1 then
    raise exception 'cancellation_retry_must_notify_known_current_approver_exactly_once';
  end if;
end $block$;
set local role authenticated;

-- Another active user cannot cancel the applicant's request.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000302', true);
do $block$
begin
  begin
    perform public.staff_leave_cancel(
      '00000000-0000-0000-0000-000000000502', 'not owner', 'cancel-key-0002'
    );
    raise exception 'expected_owner_only_denial';
  exception when sqlstate '42501' then
    if sqlerrm <> 'leave_request_not_found_or_not_owner' then raise; end if;
  end;
end $block$;

-- Requests starting today are beyond the one-calendar-day cutoff.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000301', true);
do $block$
begin
  begin
    perform public.staff_leave_cancel(
      '00000000-0000-0000-0000-000000000502', 'late cancellation', 'cancel-key-0003'
    );
    raise exception 'expected_cutoff_denial';
  exception when sqlstate '22023' then
    if sqlerrm <> 'cancellation_cutoff_passed' then raise; end if;
  end;
end $block$;

-- Drafts can be discarded at any time, even when their start date is in the past.
select public.staff_leave_cancel(
  '00000000-0000-0000-0000-000000000503', 'ทดสอบยกเลิกร่าง', 'cancel-key-0004'
);

-- Exact boundary: cancellation on the calendar day immediately before leave starts is allowed.
select public.staff_leave_cancel(
  '00000000-0000-0000-0000-000000000504', 'ยกเลิกก่อนวันลา 1 วัน', 'cancel-key-0005'
);

reset role;
do $block$
begin
  if not exists (
    select 1 from public.staff_leave_requests
    where id = '00000000-0000-0000-0000-000000000504'
      and status = 'cancelled'
  ) then
    raise exception 'cancellation_on_previous_calendar_day_must_be_allowed';
  end if;
end $block$;
do $block$
begin
  if has_function_privilege('anon', 'public.staff_leave_cancel(uuid,text,text)', 'EXECUTE') then
    raise exception 'anon_must_not_execute_staff_leave_cancel';
  end if;
  if not has_function_privilege('authenticated', 'public.staff_leave_cancel(uuid,text,text)', 'EXECUTE') then
    raise exception 'authenticated_must_execute_staff_leave_cancel';
  end if;
  if (select count(*) from public.staff_leave_approval_actions
      where request_id = '00000000-0000-0000-0000-000000000503'
        and action = 'cancelled') <> 1 then
    raise exception 'draft_cancellation_must_append_audit_action';
  end if;
end $block$;

rollback;
