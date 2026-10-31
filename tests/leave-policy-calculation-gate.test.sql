\set ON_ERROR_STOP on
begin;

insert into public.profiles(id,is_active) values
 ('83000000-0000-0000-0000-000000000001',true),
 ('83000000-0000-0000-0000-000000000002',true)
on conflict(id) do update set is_active=excluded.is_active;

insert into public.staff_leave_types(id,code,name,is_active)
values ('83000000-0000-0000-0000-000000000003','policy_test','Policy test',true)
on conflict(id) do update set is_active=true;

-- Entitlement calculation is explicitly school-wide and must not branch by personnel category.
do $schoolwide_policy_contract$
declare
  v_definition text;
begin
  select pg_get_functiondef(
    'public.staff_leave_create_draft(uuid,date,date,text)'::regprocedure
  ) into v_definition;

  if position('policy_code = ''school-wide''' in lower(v_definition)) = 0 then
    raise exception 'leave calculation must bind only to the school-wide policy';
  end if;
  if position('personnel_category' in lower(v_definition)) > 0 then
    raise exception 'leave calculation must not branch on personnel category';
  end if;
end
$schoolwide_policy_contract$;

-- The recovered handbook is present as a school-wide draft, never auto-approved.
do $handbook_seed$
declare
  v_status text;
  v_rules jsonb;
begin
  select status, policy_rules into v_status, v_rules
  from public.staff_leave_policy_versions
  where policy_code='school-wide' and version=1;
  if v_rules->'leave_types'->'maternity_leave'->>'max_days_per_request' <> '90'
     or v_rules->'leave_types'->'assist_spouse_childbirth'->>'max_days_per_event' <> '15'
     or v_rules->'leave_types'->'assist_spouse_childbirth'->>'use_within_calendar_days_after_childbirth' <> '60'
     or v_rules->'leave_types'->'personal_leave'->>'max_days_per_year' <> '45'
     or v_rules->'leave_types'->'annual_leave'->>'first_year_minimum_service_months' <> '6'
     or v_rules->'leave_types'->'ordination_hajj'->>'minimum_notice_days' <> '60'
     or v_rules->'leave_types'->'military_selection_training'->>'notify_supervisor_within_hours' <> '48'
     or v_rules->'leave_types'->'sick_leave'->>'certificate_threshold_conflict' <> 'true' then
    raise exception 'handbook extraction values or unresolved conflicts do not match source';
  end if;
  if v_status is distinct from 'draft'
     or v_rules->>'verification_status' is distinct from 'pending'
     or v_rules->>'calculation_ready' is distinct from 'false'
     or jsonb_typeof(v_rules->'leave_types') is distinct from 'object'
     or (select count(*) from jsonb_object_keys(v_rules->'leave_types')) <> 11
     or coalesce((v_rules->'calendar'->>'verified')::boolean,true) then
    raise exception 'handbook seed must contain 11 leave types and remain unapproved / not calculation-ready';
  end if;
end
$handbook_seed$;

-- Even a System Admin cannot activate the imported handbook until calendar
-- verification and all special entitlement controls are implemented.
do $policy_guard$
begin
  begin
    update public.staff_leave_policy_versions
       set status='approved',
           reviewed_by='83000000-0000-0000-0000-000000000002',
           reviewed_at=now()
     where policy_code='school-wide' and version=1;
    raise exception 'expected unresolved handbook policy approval to fail';
  exception when sqlstate '55000' then
    if sqlerrm <> 'staff_leave_policy_has_unresolved_implementation_gaps' then raise; end if;
  end;
end
$policy_guard$;

-- An otherwise complete-looking policy must still fail closed if the
-- implementation_gaps field is omitted rather than explicitly set to [].
do $missing_gaps_guard$
begin
  begin
    insert into public.staff_leave_policy_versions(
      id,policy_code,version,status,effective_from,
      policy_rules,reviewed_by,reviewed_at
    ) values (
      '83000000-0000-0000-0000-000000000005',
      'school-wide',3,'approved',date '2026-01-01',
      '{"verification_status":"approved","calculation_ready":true,
        "calendar":{"non_working_dates":[],"verified":true},
        "leave_types":{"policy_test":{"counting_basis":"calendar_days"}}}'::jsonb,
      '83000000-0000-0000-0000-000000000002',now()
    );
    raise exception 'expected missing implementation_gaps to fail';
  exception when sqlstate '55000' then
    if sqlerrm <> 'staff_leave_policy_has_unresolved_implementation_gaps' then raise; end if;
  end;
end
$missing_gaps_guard$;

-- A policy cannot be approved with a verified flag alone: the school must
-- explicitly define which ISO weekdays are weekends.
do $calendar_shape_guard$
begin
  begin
    insert into public.staff_leave_policy_versions(
      id,policy_code,version,status,effective_from,
      policy_rules,reviewed_by,reviewed_at
    ) values (
      '83000000-0000-0000-0000-000000000006',
      'school-wide',4,'approved',date '2026-01-01',
      '{"verification_status":"approved","calculation_ready":true,
        "calendar":{"non_working_dates":[],"verified":true},
        "implementation_gaps":[],
        "leave_types":{"policy_test":{"counting_basis":"working_days"}}}'::jsonb,
      '83000000-0000-0000-0000-000000000002',now()
    );
    raise exception 'expected missing weekend_days to fail';
  exception when sqlstate '55000' then
    if sqlerrm <> 'staff_leave_policy_has_unresolved_implementation_gaps' then raise; end if;
  end;
end
$calendar_shape_guard$;

set local role authenticated;
select set_config('request.jwt.claim.sub','83000000-0000-0000-0000-000000000001',true);

-- No approved shared policy: create a draft, but never invent a day count.
select public.staff_leave_create_draft(
 '83000000-0000-0000-0000-000000000003',
 date '2026-11-09',date '2026-11-13','synthetic policy gate test'
);

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
  where applicant_id='83000000-0000-0000-0000-000000000001' and reason='synthetic policy gate test';
  if v_policy_id is not null or v_day_count is not null
     or v_snapshot->>'verification_status'<>'pending' then
    raise exception 'unverified policy must leave the draft uncalculated';
  end if;

  begin
    update public.staff_leave_requests
       set status='pending_approval'
     where applicant_id='83000000-0000-0000-0000-000000000001' and reason='synthetic policy gate test';
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
 'school-wide',2,'approved',date '2026-01-01',null,
 '{"verification_status":"approved","calculation_ready":true,
   "calendar":{"weekend_days":[5,6],"non_working_dates":["2026-11-11"],"verified":true},
   "implementation_gaps":[],
   "leave_types":{"policy_test":{"counting_basis":"working_days"}}}'::jsonb,
 '83000000-0000-0000-0000-000000000002',now()
);

set local role authenticated;
select set_config('request.jwt.claim.sub','83000000-0000-0000-0000-000000000001',true);
select public.staff_leave_create_draft(
 '83000000-0000-0000-0000-000000000003',
 date '2026-11-09',date '2026-11-13','synthetic verified policy test'
);
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
  where applicant_id='83000000-0000-0000-0000-000000000001' and reason='synthetic verified policy test';
  if v_policy_id <> '83000000-0000-0000-0000-000000000004'
     or v_day_count <> 3
     or v_snapshot->>'verification_status'<>'approved'
     or v_snapshot->>'counting_basis'<>'working_days' then
    raise exception 'shared policy binding or configured weekend/holiday calculation failed: %, %, %',
      v_policy_id,v_day_count,v_snapshot;
  end if;

  update public.staff_leave_requests
     set status='pending_approval'
   where applicant_id='83000000-0000-0000-0000-000000000001' and reason='synthetic verified policy test';
end
$test$;

rollback;
