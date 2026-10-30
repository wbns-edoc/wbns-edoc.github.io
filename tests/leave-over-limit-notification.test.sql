\set ON_ERROR_STOP on
begin;

insert into public.profiles(id,is_active) values
 ('84000000-0000-0000-0000-000000000001',true),
 ('84000000-0000-0000-0000-000000000002',true),
 ('84000000-0000-0000-0000-000000000003',true)
on conflict(id) do update set is_active=excluded.is_active;

insert into public.staff_leave_types(id,code,name,is_active)
values ('84000000-0000-0000-0000-000000000004','over_limit_test','Over limit test',true)
on conflict(id) do update set is_active=true;

insert into public.staff_leave_policy_versions(
 id,policy_code,version,status,effective_from,policy_rules,reviewed_by,reviewed_at
) values (
 '84000000-0000-0000-0000-000000000005',
 'school-wide',4,'approved',date '2026-01-01',
 '{"fixture":true,"verification_status":"approved","calculation_ready":true,
   "calendar":{"verified":true,"non_working_dates":[]},"implementation_gaps":[],
   "leave_types":{"over_limit_test":{"counting_basis":"calendar_days","max_days_per_request":1}}}'::jsonb,
 '84000000-0000-0000-0000-000000000003',now()
);

insert into public.staff_leave_approval_route_config(
 singleton,vice_director_user_id,director_user_id,authority_verified,
 direct_to_vice_enabled,authority_reference,verified_by,verified_at
) values (
 true,'84000000-0000-0000-0000-000000000002',
 '84000000-0000-0000-0000-000000000003',true,false,
 'synthetic-over-limit-route-test',
 '84000000-0000-0000-0000-000000000003',now()
) on conflict(singleton) do update set
 vice_director_user_id=excluded.vice_director_user_id,
 director_user_id=excluded.director_user_id,
 authority_verified=excluded.authority_verified,
 direct_to_vice_enabled=false,
 authority_reference=excluded.authority_reference,
 verified_by=excluded.verified_by,
 verified_at=excluded.verified_at;

set local role authenticated;
select set_config('request.jwt.claim.sub','84000000-0000-0000-0000-000000000001',true);
select public.staff_leave_create_draft(
 '84000000-0000-0000-0000-000000000004',
 date '2026-11-10',date '2026-11-11','synthetic over-limit request'
);
reset role;

do $test$
begin
 if not exists (
   select 1 from public.staff_leave_requests
   where applicant_id='84000000-0000-0000-0000-000000000001'
     and reason='synthetic over-limit request'
     and day_count=2 and is_over_limit=true
 ) then raise exception 'request above approved per-request threshold was not marked over-limit'; end if;
end
$test$;

set local role authenticated;
select set_config('request.jwt.claim.sub','84000000-0000-0000-0000-000000000001',true);
select public.staff_leave_submit(
 (select id from public.staff_leave_requests
  where applicant_id='84000000-0000-0000-0000-000000000001'
    and reason='synthetic over-limit request'),
 'over-limit-submit-key-0001'
);
reset role;

do $test$
declare v_count integer;
begin
 select count(*) into v_count
 from public.staff_leave_notification_outbox
 where request_id=(select id from public.staff_leave_requests
   where applicant_id='84000000-0000-0000-0000-000000000001'
     and reason='synthetic over-limit request')
   and event_type='over_limit'
   and recipient_id in ('84000000-0000-0000-0000-000000000002',
                        '84000000-0000-0000-0000-000000000003')
   and status='sent';
 if v_count <> 2 then raise exception 'expected over-limit notifications to Vice and Director, got %',v_count; end if;

 select count(*) into v_count
 from public.notifications
 where recipient_id in ('84000000-0000-0000-0000-000000000002',
                        '84000000-0000-0000-0000-000000000003')
   and type='staff_leave_over_limit';
 if v_count <> 2 then raise exception 'expected two in-app over-limit notifications, got %',v_count; end if;
end
$test$;

rollback;
