\\set ON_ERROR_STOP on
begin;

insert into public.profiles (id, is_active) values
  ('00000000-0000-0000-0000-000000000601', true),
  ('00000000-0000-0000-0000-000000000602', true),
  ('00000000-0000-0000-0000-000000000603', false)
on conflict (id) do update set is_active = excluded.is_active;

insert into public.staff_leave_types (id, code, name, is_active)
values ('00000000-0000-0000-0000-000000000604', 'submit_test', 'Submit test', true)
on conflict (id) do update set is_active = true;

insert into public.staff_leave_requests (
  id, applicant_id, leave_type_id, starts_on, ends_on, reason, status
) values
  ('00000000-0000-0000-0000-000000000605',
   '00000000-0000-0000-0000-000000000601',
   '00000000-0000-0000-0000-000000000604',
   date '2026-11-20', date '2026-11-20', 'synthetic draft', 'draft'),
  ('00000000-0000-0000-0000-000000000606',
   '00000000-0000-0000-0000-000000000601',
   '00000000-0000-0000-0000-000000000604',
   date '2026-11-20', date '2026-11-20', 'synthetic other draft', 'draft')
on conflict (id) do nothing;

set local role authenticated;
select set_config('request.jwt.claim.sub', '', true);
do $block$
begin
  begin
    perform public.staff_leave_submit(
      '00000000-0000-0000-0000-000000000605', 'submit-key-unauth'
    );
    raise exception 'expected_authentication_required';
  exception when sqlstate '28000' then
    if sqlerrm <> 'authentication_required' then raise; end if;
  end;
end $block$;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000601', true);
select public.staff_leave_submit(
  '00000000-0000-0000-0000-000000000605', 'submit-key-0001'
);
-- Exact retry is idempotent and must not duplicate the blocked audit event.
select public.staff_leave_submit(
  '00000000-0000-0000-0000-000000000605', 'submit-key-0001'
);

do $block$
begin
  if not exists (
    select 1 from public.staff_leave_requests
    where id = '00000000-0000-0000-0000-000000000605'
      and status = 'blocked_approver_resolution'
      and submitted_at is not null
      and current_approver_user_id is null
  ) then
    raise exception 'unverified_authority_must_block_without_assigning_approver';
  end if;
  if (select count(*) from public.staff_leave_approval_actions
      where request_id = '00000000-0000-0000-0000-000000000605'
        and action = 'blocked'
        and metadata->>'reason_code' = 'approver_authority_unverified') <> 1 then
    raise exception 'submit_retry_must_append_exactly_one_blocked_action';
  end if;
end $block$;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000602', true);
do $block$
begin
  begin
    perform public.staff_leave_submit(
      '00000000-0000-0000-0000-000000000606', 'submit-key-other'
    );
    raise exception 'expected_owner_only_denial';
  exception when sqlstate '42501' then
    if sqlerrm <> 'leave_request_not_found_or_not_owner' then raise; end if;
  end;
end $block$;

reset role;
do $block$
begin
  if has_function_privilege('anon', 'public.staff_leave_submit(uuid,text)', 'EXECUTE') then
    raise exception 'anon_must_not_execute_staff_leave_submit';
  end if;
  if not has_function_privilege('authenticated', 'public.staff_leave_submit(uuid,text)', 'EXECUTE') then
    raise exception 'authenticated_must_execute_staff_leave_submit';
  end if;
end $block$;

rollback;
