-- Integration-style RLS regression test for the draft leave schema.
-- Run only against a disposable local PostgreSQL database after applying the candidate migration.
\set ON_ERROR_STOP on

insert into public.profiles(id) values
 ('10000000-0000-0000-0000-000000000001'),
 ('10000000-0000-0000-0000-000000000002'),
 ('10000000-0000-0000-0000-000000000003'),
 ('10000000-0000-0000-0000-000000000004');
update public.profiles set is_active = false where id = '10000000-0000-0000-0000-000000000004';

insert into public.staff_leave_types(id, code, name)
values ('20000000-0000-0000-0000-000000000001', 'annual', 'Annual leave');

insert into public.staff_leave_policy_versions(
 id, policy_code, version, status, reviewed_by, reviewed_at, policy_rules
) values (
 '30000000-0000-0000-0000-000000000001', 'school-wide', 1, 'approved',
 '10000000-0000-0000-0000-000000000001', now(), '{"fixture":true}'::jsonb
);

insert into public.staff_leave_requests(
 id, applicant_id, leave_type_id, policy_version_id, starts_on, ends_on, reason,
 status, current_approver_user_id, policy_snapshot
) values (
 '40000000-0000-0000-0000-000000000001',
 '10000000-0000-0000-0000-000000000001',
 '20000000-0000-0000-0000-000000000001',
 '30000000-0000-0000-0000-000000000001',
 date '2026-11-01', date '2026-11-01', 'synthetic fixture',
 'pending_approval', '10000000-0000-0000-0000-000000000002',
 '{"fixture":true}'::jsonb
);

insert into public.staff_leave_approval_actions(id, request_id, actor_id, action)
values (
 '50000000-0000-0000-0000-000000000001',
 '40000000-0000-0000-0000-000000000001',
 '10000000-0000-0000-0000-000000000001', 'submitted'
);

insert into public.staff_leave_attachments(
 id, request_id, uploaded_by, storage_object_key, original_filename, size_bytes
) values (
 '60000000-0000-0000-0000-000000000001',
 '40000000-0000-0000-0000-000000000001',
 '10000000-0000-0000-0000-000000000001',
 'private-fixture/object-1', 'fixture.pdf', 1
);

insert into public.staff_leave_notification_outbox(
 id, event_key, request_id, recipient_id, event_type
) values (
 '70000000-0000-0000-0000-000000000001',
 'fixture:submitted:recipient-1', '40000000-0000-0000-0000-000000000001',
 '10000000-0000-0000-0000-000000000002', 'submitted'
);

-- The local fixture grants table privileges so these assertions exercise RLS policies.
grant usage on schema public to authenticated;
grant select, insert, update, delete on public.staff_leave_types,
 public.staff_leave_policy_versions, public.staff_leave_requests,
 public.staff_leave_approval_actions, public.staff_leave_attachments,
 public.staff_leave_notification_outbox to authenticated;

set role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', false);
do $$
declare n integer;
begin
  select count(*) into n from public.staff_leave_requests;
  if n <> 1 then raise exception 'applicant should see own request, got %', n; end if;
  select count(*) into n from public.staff_leave_approval_actions;
  if n <> 1 then raise exception 'applicant should see own action history, got %', n; end if;
  select count(*) into n from public.staff_leave_attachments;
  if n <> 1 then raise exception 'applicant should see own attachment metadata, got %', n; end if;
  select count(*) into n from public.staff_leave_notification_outbox;
  if n <> 0 then raise exception 'browser client must not read outbox, got %', n; end if;
end $$;

select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000002', false);
do $$
declare n integer;
begin
  select count(*) into n from public.staff_leave_requests;
  if n <> 1 then raise exception 'assigned approver should see assigned request, got %', n; end if;
  select count(*) into n from public.staff_leave_approval_actions;
  if n <> 1 then raise exception 'assigned approver should see assigned history, got %', n; end if;
end $$;

select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000003', false);
do $$
declare n integer;
begin
  select count(*) into n from public.staff_leave_requests;
  if n <> 0 then raise exception 'unrelated staff must not see request, got %', n; end if;
  select count(*) into n from public.staff_leave_approval_actions;
  if n <> 0 then raise exception 'unrelated staff must not see history, got %', n; end if;
  select count(*) into n from public.staff_leave_attachments;
  if n <> 0 then raise exception 'unrelated staff must not see attachment metadata, got %', n; end if;
end $$;

select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000004', false);
do $
declare n integer;
begin
  select count(*) into n from public.staff_leave_requests;
  if n <> 0 then raise exception 'inactive profiles must not see leave requests, got %', n; end if;
  select count(*) into n from public.staff_leave_approval_actions;
  if n <> 0 then raise exception 'inactive profiles must not see action history, got %', n; end if;
  select count(*) into n from public.staff_leave_attachments;
  if n <> 0 then raise exception 'inactive profiles must not see attachment metadata, got %', n; end if;
  select count(*) into n from public.staff_leave_types;
  if n <> 0 then raise exception 'inactive profiles must not see leave types, got %', n; end if;
end $;

select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', false);

-- RLS without a write policy must reject direct client mutations.
do $$
begin
  begin
    insert into public.staff_leave_requests(
      applicant_id, leave_type_id, starts_on, ends_on, reason
    ) values (
      '10000000-0000-0000-0000-000000000003',
      '20000000-0000-0000-0000-000000000001',
      date '2026-11-02', date '2026-11-02', 'should be blocked'
    );
    raise exception 'direct client INSERT unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;
end $$;
reset role;
select 'staff leave RLS draft tests passed' as result;
