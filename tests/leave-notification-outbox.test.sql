\set ON_ERROR_STOP on
begin;

insert into public.profiles(id) values
 ('81000000-0000-0000-0000-000000000001'),
 ('81000000-0000-0000-0000-000000000002')
on conflict (id) do nothing;

insert into public.staff_leave_requests(
 id, applicant_id, leave_type_id, starts_on, ends_on, reason, status
)
select
 '82000000-0000-0000-0000-000000000001',
 '81000000-0000-0000-0000-000000000001',
 lt.id, date '2026-11-10', date '2026-11-10',
 'synthetic test only; private medical details must not be copied to notification', 'draft'
from public.staff_leave_types lt
where lt.code='sick_leave'
on conflict (id) do nothing;

insert into public.staff_leave_notification_outbox(
 event_key, request_id, recipient_id, event_type, channel, safe_payload, status
) values (
 'test:leave-submitted:one',
 '82000000-0000-0000-0000-000000000001',
 '81000000-0000-0000-0000-000000000002',
 'submitted', 'in_app',
 '{"reason":"private medical details must never appear in notification previews"}'::jsonb,
 'pending'
);

do $$
declare
  v_count integer;
  v_status text;
  v_body text;
begin
  select count(*) into v_count
  from public.notifications
  where recipient_id='81000000-0000-0000-0000-000000000002'
    and type='staff_leave_submitted';
  if v_count <> 1 then
    raise exception 'expected one in-app leave notification, got %', v_count;
  end if;

  select status into v_status
  from public.staff_leave_notification_outbox
  where event_key='test:leave-submitted:one';
  if v_status <> 'sent' then
    raise exception 'outbox event should be marked sent, got %', v_status;
  end if;

  select body into v_body
  from public.notifications
  where recipient_id='81000000-0000-0000-0000-000000000002'
    and type='staff_leave_submitted';
  if v_body ilike '%medical%' or v_body ilike '%private%' then
    raise exception 'sensitive details leaked into notification preview';
  end if;
end $$;

-- Duplicate event keys must not produce a second notification.
insert into public.staff_leave_notification_outbox(
 event_key, request_id, recipient_id, event_type, channel, safe_payload, status
) values (
 'test:leave-submitted:one',
 '82000000-0000-0000-0000-000000000001',
 '81000000-0000-0000-0000-000000000002',
 'submitted', 'in_app', '{}'::jsonb, 'pending'
) on conflict (event_key) do nothing;

do $$
declare v_count integer;
begin
  select count(*) into v_count
  from public.notifications
  where recipient_id='81000000-0000-0000-0000-000000000002'
    and type='staff_leave_submitted';
  if v_count <> 1 then
    raise exception 'idempotent retry created duplicate notification: %', v_count;
  end if;
end $$;

rollback;
