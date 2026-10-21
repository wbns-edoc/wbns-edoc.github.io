\set ON_ERROR_STOP on
begin;

insert into public.profiles (id, is_active)
values
 ('10000000-0000-0000-0000-000000000001', true),
 ('10000000-0000-0000-0000-000000000002', true)
on conflict (id) do nothing;

insert into public.staff_leave_types (id, code, name, is_active)
values ('20000000-0000-0000-0000-000000000001', 'TEST', 'Test leave', true)
on conflict (id) do nothing;

insert into public.staff_leave_requests
  (id, applicant_id, leave_type_id, starts_on, ends_on, reason, status)
values
 ('30000000-0000-0000-0000-000000000001',
  '10000000-0000-0000-0000-000000000001',
  '20000000-0000-0000-0000-000000000001',
  current_date + 2, current_date + 2, 'fixture only', 'draft')
on conflict (id) do nothing;

insert into public.staff_leave_notification_outbox
  (event_key, request_id, recipient_id, event_type, channel, safe_payload)
values
 ('test-event-key-001',
  '30000000-0000-0000-0000-000000000001',
  '10000000-0000-0000-0000-000000000002',
  'submitted', 'in_app',
  '{"title":"A leave request needs attention","href":"/leave"}'::jsonb)
on conflict (event_key) do nothing;

do $$
begin
  if has_function_privilege('authenticated',
       'public.staff_leave_outbox_claim(integer,integer)', 'EXECUTE') then
    raise exception 'authenticated must not execute outbox claim';
  end if;
  if not has_function_privilege('service_role',
       'public.staff_leave_outbox_claim(integer,integer)', 'EXECUTE') then
    raise exception 'service_role must execute outbox claim';
  end if;
  if has_table_privilege('authenticated',
       'public.staff_leave_notification_outbox', 'SELECT') then
    raise exception 'authenticated must not read outbox';
  end if;
end;
$$;

create temporary table claimed_events (
  outbox_id uuid,
  lease_token uuid,
  event_key text,
  request_id uuid,
  recipient_id uuid,
  event_type text,
  channel text,
  safe_payload jsonb,
  attempts integer
) on commit drop;

insert into claimed_events
select * from public.staff_leave_outbox_claim(10, 90)
where event_key = 'test-event-key-001';

do $$
declare
  c claimed_events%rowtype;
begin
  select * into c from claimed_events where event_key = 'test-event-key-001';
  if not found then raise exception 'expected due event to be claimed'; end if;
  if c.attempts <> 1 then raise exception 'attempt counter must increment on claim'; end if;
  if c.lease_token is null then raise exception 'claim must issue a lease token'; end if;
  if not public.staff_leave_outbox_deliver_in_app(c.outbox_id, c.lease_token) then
    raise exception 'delivery should return true';
  end if;
  if not exists (
    select 1 from public.staff_leave_notifications
    where recipient_id = c.recipient_id and event_key = c.event_key
  ) then raise exception 'notification feed row missing'; end if;
  if (select status from public.staff_leave_notification_outbox where id = c.outbox_id) <> 'sent' then
    raise exception 'outbox should be sent after successful insert';
  end if;
  begin
    perform public.staff_leave_outbox_deliver_in_app(c.outbox_id, c.lease_token);
    raise exception 'stale lease must not deliver';
  exception when sqlstate '55000' then null;
  end;
end;
$$;

-- A retry uses a sanitized code and clears the lease; no raw provider response is stored.
insert into public.staff_leave_notification_outbox
  (event_key, request_id, recipient_id, event_type, channel, safe_payload)
values
 ('test-event-key-002',
  '30000000-0000-0000-0000-000000000001',
  '10000000-0000-0000-0000-000000000002',
  'approved', 'in_app', '{"title":"Leave request updated"}'::jsonb);

do $$
declare
  c record;
  v_status text;
begin
  select * into c from public.staff_leave_outbox_claim(10, 90)
  where event_key = 'test-event-key-002';
  if c.lease_token is null then raise exception 'second event was not claimed'; end if;
  v_status := public.staff_leave_outbox_fail(c.outbox_id, c.lease_token, 'TEMP_PROVIDER_ERROR', false);
  if v_status <> 'retry' then raise exception 'transient error should retry'; end if;
  if (select last_error_code from public.staff_leave_notification_outbox where id = c.outbox_id) <> 'TEMP_PROVIDER_ERROR' then
    raise exception 'sanitized error code not stored';
  end if;
  if (select lease_token from public.staff_leave_notification_outbox where id = c.outbox_id) is not null then
    raise exception 'lease must clear after failure';
  end if;
end;
$$;

rollback;
