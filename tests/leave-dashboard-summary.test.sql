\set ON_ERROR_STOP on
begin;

insert into public.profiles(id,is_active) values
 ('85000000-0000-0000-0000-000000000001',true),
 ('85000000-0000-0000-0000-000000000002',true),
 ('85000000-0000-0000-0000-000000000003',true)
on conflict(id) do update set is_active=excluded.is_active;

insert into public.roles(id,code,name) values
 ('85000000-0000-0000-0000-000000000004','director','Director'),
 ('85000000-0000-0000-0000-000000000005','teacher','Teacher')
on conflict(id) do nothing;

insert into public.user_roles(user_id,role_id) values
 ('85000000-0000-0000-0000-000000000001','85000000-0000-0000-0000-000000000004'),
 ('85000000-0000-0000-0000-000000000003','85000000-0000-0000-0000-000000000005')
on conflict do nothing;

insert into public.staff_leave_types(id,code,name,is_active)
values ('85000000-0000-0000-0000-000000000006','dashboard_test','Dashboard test',true)
on conflict(id) do update set is_active=true;

insert into public.staff_leave_requests(
 id,applicant_id,leave_type_id,starts_on,ends_on,reason,status,is_over_limit,approval_stage
) values
 ('85000000-0000-0000-0000-000000000007','85000000-0000-0000-0000-000000000002',
  '85000000-0000-0000-0000-000000000006',date '2026-12-01',date '2026-12-01','fixture draft','draft',false,'vice_director_review'),
 ('85000000-0000-0000-0000-000000000008','85000000-0000-0000-0000-000000000002',
  '85000000-0000-0000-0000-000000000006',date '2026-12-02',date '2026-12-02','fixture pending','pending_approval',true,'vice_director_review'),
 ('85000000-0000-0000-0000-000000000009','85000000-0000-0000-0000-000000000002',
  '85000000-0000-0000-0000-000000000006',date '2026-12-03',date '2026-12-03','fixture approved','approved',false,'completed')
on conflict(id) do nothing;

set local role authenticated;
select set_config('request.jwt.claim.sub','85000000-0000-0000-0000-000000000001',true);
do $test$
declare v_summary jsonb;
begin
  v_summary := public.staff_leave_dashboard_summary();
  if (v_summary->>'total')::integer <> 3
     or (v_summary->>'draft')::integer <> 1
     or (v_summary->>'pending')::integer <> 1
     or (v_summary->>'approved')::integer <> 1
     or (v_summary->>'over_limit')::integer <> 1
     or (v_summary->>'waiting_vice')::integer <> 1 then
    raise exception 'approver dashboard summary mismatch: %',v_summary;
  end if;
  if v_summary ? 'full_name' or v_summary ? 'reason' then
    raise exception 'aggregate dashboard leaked personal request data';
  end if;
end
$test$;

select set_config('request.jwt.claim.sub','85000000-0000-0000-0000-000000000003',true);
do $test$
begin
  begin
    perform public.staff_leave_dashboard_summary();
    raise exception 'teacher must not read approver dashboard';
  exception when sqlstate '42501' then
    if sqlerrm <> 'leave_dashboard_role_required' then raise; end if;
  end;
end
$test$;

rollback;
