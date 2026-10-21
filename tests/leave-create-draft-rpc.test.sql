\set ON_ERROR_STOP on
begin;

insert into public.profiles (id, is_active) values
  ('00000000-0000-0000-0000-000000000101', true),
  ('00000000-0000-0000-0000-000000000102', false)
on conflict (id) do update set is_active = excluded.is_active;

insert into public.staff_leave_types (id, code, name, is_active)
values ('00000000-0000-0000-0000-000000000201', 'test_leave', 'Test leave', true)
on conflict (id) do update set is_active = true;

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000101', true);

create temporary table created_leave_request (id uuid);
insert into created_leave_request
select public.staff_leave_create_draft(
  '00000000-0000-0000-0000-000000000201',
  date '2026-11-10', date '2026-11-11', 'test draft'
);

do $$
declare
  v_id uuid;
begin
  select id into v_id from created_leave_request;
  if not exists (
    select 1 from public.staff_leave_requests
    where id = v_id
      and applicant_id = auth.uid()
      and status = 'draft'
      and day_count is null
      and policy_version_id is null
      and current_approver_user_id is null
  ) then
    raise exception 'draft_create_must_use_actor_and_leave_policy_fields_must_not_be_client_assigned';
  end if;
end $$;

do $$
begin
  begin
    perform public.staff_leave_create_draft(
      '00000000-0000-0000-0000-000000000201',
      date '2026-11-12', date '2026-11-11', 'invalid dates'
    );
    raise exception 'expected_invalid_date_range';
  exception when sqlstate '22023' then
    if sqlerrm <> 'invalid_leave_date_range' then raise; end if;
  end;

  begin
    perform public.staff_leave_create_draft(
      '00000000-0000-0000-0000-000000000201',
      date '2026-11-12', date '2026-11-12', '   '
    );
    raise exception 'expected_invalid_reason';
  exception when sqlstate '22023' then
    if sqlerrm <> 'invalid_leave_reason' then raise; end if;
  end;
end $$;

reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000102', true);
set local role authenticated;
do $$
begin
  begin
    perform public.staff_leave_create_draft(
      '00000000-0000-0000-0000-000000000201',
      date '2026-11-12', date '2026-11-12', 'inactive user'
    );
    raise exception 'expected_inactive_profile_denial';
  exception when sqlstate '42501' then
    if sqlerrm <> 'active_profile_required' then raise; end if;
  end;
end $$;

reset role;
do $$
begin
  if has_function_privilege('anon', 'public.staff_leave_create_draft(uuid,date,date,text)', 'EXECUTE') then
    raise exception 'anon_must_not_execute_staff_leave_create_draft';
  end if;
  if not has_function_privilege('authenticated', 'public.staff_leave_create_draft(uuid,date,date,text)', 'EXECUTE') then
    raise exception 'authenticated_must_execute_staff_leave_create_draft';
  end if;
end $$;

rollback;
