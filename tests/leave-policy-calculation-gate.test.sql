\set ON_ERROR_STOP on
begin;

insert into public.profiles(id,is_active) values
 ('83000000-0000-0000-0000-000000000001',true),
 ('83000000-0000-0000-0000-000000000002',true)
on conflict(id) do update set is_active=excluded.is_active;

insert into public.staff_leave_types(id,code,name,is_active)
values ('83000000-0000-0000-0000-000000000003','policy_test','Policy test',true)
on conflict(id) do update set is_active=true;

set local role authenticated;
select set_config('request.jwt.claim.sub','83000000-0000-0000-0000-000000000001',true);

-- No approved shared policy: create a draft, but never invent a day count.
select public.staff_leave_create_draft(
 '83000000-0000-0000-0000-000000000003',
 date '2026-11-09',date '2026-11-13','synthetic policy gate test'
) as pending_policy_request_id
\gset

reset role;

do $test$
declare
  v_policy_id uuid;
  v_day_count numeric;
  v_snapshot jsonb;
begin
  select policy_version_id,day_count,policy_snapshot
    into v_policy_id,v_day_count,v_snapshot
  from public.staff_leave_requests
  where id=:'pending_policy_request_id';
  if v_policy_id is not null or v_day_count is not null
     or v_snapshot->>'verification_status'<>'pending' then
    raise exception 'unverified policy must leave the draft uncalculated';
  end if;

  begin
    update public.staff_leave_requests
       set status='pending_approval'
     where id=:'pending_policy_request_id';
    raise exception 'expected unverified policy submission to fail';
  exception when sqlstate '55000' then
    if sqlerrm <> 'leave_policy_not_verified_or_day_count_missing' then raise; end if;
  end;
end
$test$;

insert into public.staff_leave_policy_versions(
 id,policy_code,version,status,effective_from,effective_until,
 policy_rules,reviewed_by,reviewed_at
) values (
 '83000000-0000-0000-0000-000000000004',
 'school-wide',1,'approved',date '2026-01-01',null,
 '{"verification_status":"approved","calculation_ready":true,
   "calendar":{"non_working_dates":["2026-11-11"]},
   "leave_types":{"policy_test":{"counting_basis":"working_days"}}}'::jsonb,
 '83000000-0000-0000-0000-000000000002',now()
);

set local role authenticated;
select set_config('request.jwt.claim.sub','83000000-0000-0000-0000-000000000001',true);
select public.staff_leave_create_draft(
 '83000000-0000-0000-0000-000000000003',
 date '2026-11-09',date '2026-11-13','synthetic verified policy test'
) as verified_policy_request_id
\gset
reset role;

do $test$
declare
  v_policy_id uuid;
  v_day_count numeric;
  v_snapshot jsonb;
begin
  select policy_version_id,day_count,policy_snapshot
    into v_policy_id,v_day_count,v_snapshot
  from public.staff_leave_requests
  where id=:'verified_policy_request_id';
  if v_policy_id <> '83000000-0000-0000-0000-000000000004'
     or v_day_count <> 4
     or v_snapshot->>'verification_status'<>'approved'
     or v_snapshot->>'counting_basis'<>'working_days' then
    raise exception 'shared policy binding or weekday/holiday calculation failed: %, %, %',
      v_policy_id,v_day_count,v_snapshot;
  end if;

  update public.staff_leave_requests
     set status='pending_approval'
   where id=:'verified_policy_request_id';
end
$test$;

rollback;
