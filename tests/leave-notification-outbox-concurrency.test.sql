\set ON_ERROR_STOP on

-- Dedicated multi-session test. Fixtures are committed so independent dblink
-- sessions can observe them. Entire test uses disposable CI PostgreSQL only.
create extension if not exists dblink;

insert into public.profiles (id, is_active)
values
 ('11000000-0000-0000-0000-000000000001', true),
 ('11000000-0000-0000-0000-000000000002', true)
on conflict (id) do nothing;

insert into public.staff_leave_types (id, code, name, is_active)
values ('21000000-0000-0000-0000-000000000001', 'CONCURRENCY_TEST', 'Concurrency test', true)
on conflict (id) do nothing;

insert into public.staff_leave_requests
  (id, applicant_id, leave_type_id, starts_on, ends_on, reason, status)
values
 ('31000000-0000-0000-0000-000000000001',
  '11000000-0000-0000-0000-000000000001',
  '21000000-0000-0000-0000-000000000001',
  current_date + 3, current_date + 3, 'fixture only', 'draft')
on conflict (id) do nothing;

insert into public.staff_leave_notification_outbox
  (event_key, request_id, recipient_id, event_type, channel, safe_payload, status, available_at)
values
 ('concurrency-event-001',
  '31000000-0000-0000-0000-000000000001',
  '11000000-0000-0000-0000-000000000002',
  'submitted', 'in_app', '{"title":"Concurrency fixture 1"}'::jsonb, 'pending', now() - interval '2 seconds'),
 ('concurrency-event-002',
  '31000000-0000-0000-0000-000000000001',
  '11000000-0000-0000-0000-000000000002',
  'approved', 'in_app', '{"title":"Concurrency fixture 2"}'::jsonb, 'pending', now() - interval '1 second')
on conflict (event_key) do nothing;

select dblink_connect('claim_a', 'dbname=' || current_database());
select dblink_connect('claim_b', 'dbname=' || current_database());

-- Session A claims the oldest row and keeps its transaction/row lock open.
select dblink_exec('claim_a', 'begin');
create temporary table claim_a_result (
  outbox_id uuid, lease_token uuid, event_key text, request_id uuid,
  recipient_id uuid, event_type text, channel text, safe_payload jsonb, attempts integer
) on commit preserve rows;

insert into claim_a_result
select *
from dblink('claim_a',
  'select outbox_id, lease_token, event_key, request_id, recipient_id, event_type, channel, safe_payload, attempts
   from public.staff_leave_outbox_claim(1, 90)')
as t(outbox_id uuid, lease_token uuid, event_key text, request_id uuid,
     recipient_id uuid, event_type text, channel text, safe_payload jsonb, attempts integer);

do $assert_a$
begin
  if (select count(*) from claim_a_result) <> 1 then
    raise exception 'session A must claim exactly one row';
  end if;
end;
$assert_a$;

-- Session B claims while A still owns its lock. SKIP LOCKED must let B claim
-- the other eligible event instead of waiting for or duplicating A's event.
create temporary table claim_b_result (
  outbox_id uuid, lease_token uuid, event_key text, request_id uuid,
  recipient_id uuid, event_type text, channel text, safe_payload jsonb, attempts integer
) on commit preserve rows;

insert into claim_b_result
select *
from dblink('claim_b',
  'select outbox_id, lease_token, event_key, request_id, recipient_id, event_type, channel, safe_payload, attempts
   from public.staff_leave_outbox_claim(1, 90)')
as t(outbox_id uuid, lease_token uuid, event_key text, request_id uuid,
     recipient_id uuid, event_type text, channel text, safe_payload jsonb, attempts integer);

do $assert_b$
declare
  a claim_a_result%rowtype;
  b claim_b_result%rowtype;
begin
  select * into a from claim_a_result;
  select * into b from claim_b_result;
  if not found then
    raise exception 'session B must claim a different eligible row while A holds its lock';
  end if;
  if a.outbox_id = b.outbox_id then
    raise exception 'concurrent workers must never claim the same outbox row';
  end if;
  if a.lease_token is null or b.lease_token is null or a.lease_token = b.lease_token then
    raise exception 'each concurrent claim must have its own lease token';
  end if;
end;
$assert_b$;

select dblink_exec('claim_a', 'commit');
select dblink_disconnect('claim_a');
select dblink_disconnect('claim_b');

-- Clean up only these dedicated test fixtures.
delete from public.staff_leave_notification_outbox
where event_key in ('concurrency-event-001', 'concurrency-event-002');
delete from public.staff_leave_requests
where id = '31000000-0000-0000-0000-000000000001';
delete from public.staff_leave_types
where id = '21000000-0000-0000-0000-000000000001';
delete from public.profiles
where id in ('11000000-0000-0000-0000-000000000001',
             '11000000-0000-0000-0000-000000000002');
