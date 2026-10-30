\set ON_ERROR_STOP on
begin;

insert into public.profiles(id,is_active) values
 ('86000000-0000-0000-0000-000000000001',true),
 ('86000000-0000-0000-0000-000000000002',true),
 ('86000000-0000-0000-0000-000000000003',true),
 ('86000000-0000-0000-0000-000000000004',true)
on conflict(id) do update set is_active=excluded.is_active;

-- Reuse the catalog's canonical System Admin role; seed it only for minimal fixtures.
insert into public.roles(id,code,name)
values ('86000000-0000-0000-0000-000000000005','system_admin','System Admin CI fixture')
on conflict do nothing;
insert into public.user_roles(user_id,role_id)
select '86000000-0000-0000-0000-000000000001', id
from public.roles where code='system_admin'
on conflict do nothing;

do $role_fixture$
begin
  if not exists (
    select 1 from public.user_roles ur join public.roles r on r.id=ur.role_id
    where ur.user_id='86000000-0000-0000-0000-000000000001' and r.code='system_admin'
  ) then raise exception 'system_admin_role_fixture_unavailable'; end if;
end
$role_fixture$;

insert into public.staff_leave_types(id,code,name,is_active)
values ('86000000-0000-0000-0000-000000000006','absence_test','Absence test',true)
on conflict(id) do update set is_active=true;

insert into public.staff_leave_policy_versions(
 id,policy_code,version,status,effective_from,policy_rules,reviewed_by,reviewed_at
) values (
 '86000000-0000-0000-0000-000000000007',
 'school-wide',5,'approved',date '2026-01-01',
 '{"fixture":true,"verification_status":"approved","calculation_ready":true,
   "calendar":{"verified":true,"non_working_dates":[]},"implementation_gaps":[],
   "leave_types":{"absence_test":{"counting_basis":"calendar_days"}}}'::jsonb,
 '86000000-0000-0000-0000-000000000001',now()
);

insert into public.staff_leave_approval_route_config(
 singleton,vice_director_user_id,director_user_id,authority_verified,
 direct_to_vice_enabled,no_vice_director_confirmed,
 authority_reference,verified_by,verified_at
) values (
 true,'86000000-0000-0000-0000-000000000002',
 '86000000-0000-0000-0000-000000000003',true,false,false,
 'synthetic-verified-route','86000000-0000-0000-0000-000000000001',now()
) on conflict(singleton) do update set
 vice_director_user_id=excluded.vice_director_user_id,
 director_user_id=excluded.director_user_id,
 authority_verified=true,direct_to_vice_enabled=false,
 no_vice_director_confirmed=false,
 authority_reference=excluded.authority_reference,
 verified_by=excluded.verified_by,verified_at=excluded.verified_at;

insert into public.staff_leave_requests(
 id,applicant_id,leave_type_id,policy_version_id,starts_on,ends_on,day_count,
 reason,policy_snapshot,status,current_approver_user_id,approval_stage,approval_route_snapshot
) values
 (
 '86000000-0000-0000-0000-000000000008',
 '86000000-0000-0000-0000-000000000004',
 '86000000-0000-0000-0000-000000000006',
 '86000000-0000-0000-0000-000000000007',
 date '2026-11-20',date '2026-11-20',1,
 'synthetic no absence evidence route test',
 '{"policy_version_id":"86000000-0000-0000-0000-000000000007","leave_type_code":"absence_test","verification_status":"approved","calculation_ready":true,"calculated_day_count":1}'::jsonb,
 'pending_approval','86000000-0000-0000-0000-000000000002','vice_director_review',
 jsonb_build_object('version',1,'route_kind','vice_director_then_director',
   'vice_director_user_id','86000000-0000-0000-0000-000000000002',
   'director_user_id','86000000-0000-0000-0000-000000000003',
   'authority_reference','synthetic-verified-route',
   'authority_verified_by','86000000-0000-0000-0000-000000000001',
   'authority_verified_at',now(),'captured_at',now())
 ),
 (
 '86000000-0000-0000-0000-000000000009',
 '86000000-0000-0000-0000-000000000004',
 '86000000-0000-0000-0000-000000000006',
 '86000000-0000-0000-0000-000000000007',
 date '2026-11-21',date '2026-11-21',1,
 'synthetic direct vice absence evidence test',
 '{"policy_version_id":"86000000-0000-0000-0000-000000000007","leave_type_code":"absence_test","verification_status":"approved","calculation_ready":true,"calculated_day_count":1}'::jsonb,
 'pending_approval','86000000-0000-0000-0000-000000000002','vice_director_review',
 jsonb_build_object('version',1,'route_kind','vice_director_then_director',
   'vice_director_user_id','86000000-0000-0000-0000-000000000002',
   'director_user_id','86000000-0000-0000-0000-000000000003',
   'authority_reference','synthetic-verified-route',
   'authority_verified_by','86000000-0000-0000-0000-000000000001',
   'authority_verified_at',now(),'captured_at',now())
 );

-- Without an active absence record, Vice approval is only the first stage.
set local role authenticated;
select set_config('request.jwt.claim.sub','86000000-0000-0000-0000-000000000002',true);
select public.staff_leave_decide(
 '86000000-0000-0000-0000-000000000008','approve',null,'absence-no-evidence-01'
);
reset role;

do $test$
begin
 if not exists(
   select 1 from public.staff_leave_requests
   where id='86000000-0000-0000-0000-000000000008'
     and status='pending_approval' and approval_stage='director_final_review'
     and current_approver_user_id='86000000-0000-0000-0000-000000000003'
 ) then raise exception 'Vice approval without absence evidence must route to Director, not finalize'; end if;
end
$test$;

-- Only a System Admin can record the Director's dated absence and authority reference.
set local role authenticated;
select set_config('request.jwt.claim.sub','86000000-0000-0000-0000-000000000001',true);
select public.admin_record_staff_leave_director_absence(
 (statement_timestamp() at time zone 'Asia/Bangkok')::date - 1,
 (statement_timestamp() at time zone 'Asia/Bangkok')::date + 1,
 'Director is officially absent',
 'SCHOOL-ORDER-TEST-2026-10'
);
do $test$
declare v_count integer;
begin
 select count(*) into v_count
 from public.admin_list_staff_leave_director_absences()
 where authority_reference='SCHOOL-ORDER-TEST-2026-10' and revoked_at is null;
 if v_count<>1 then raise exception 'System Admin absence evidence listing failed'; end if;
end
$test$;
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub','86000000-0000-0000-0000-000000000002',true);
select public.staff_leave_decide(
 '86000000-0000-0000-0000-000000000009','approve',null,'absence-approved-vice-01'
);
reset role;

do $test$
begin
 if not exists(
   select 1 from public.staff_leave_requests
   where id='86000000-0000-0000-0000-000000000009'
     and status='approved' and approval_stage='completed'
     and current_approver_user_id is null
 ) then raise exception 'Vice Director did not complete final approval during verified Director absence'; end if;
 if not exists(
   select 1 from public.staff_leave_approval_actions
   where request_id='86000000-0000-0000-0000-000000000009'
     and actor_id='86000000-0000-0000-0000-000000000002'
     and action='approved'
     and metadata->>'director_absence_override'='true'
     and metadata ? 'absence_evidence_id'
     and metadata->>'absence_authority_reference'='SCHOOL-ORDER-TEST-2026-10'
 ) then raise exception 'direct Vice approval did not preserve absence evidence in audit metadata'; end if;
 if not exists(
   select 1 from public.staff_leave_notification_outbox
   where request_id='86000000-0000-0000-0000-000000000009'
     and recipient_id='86000000-0000-0000-0000-000000000004'
     and event_type='approved'
 ) then raise exception 'applicant approval notification was not enqueued'; end if;
end
$test$;

-- Revocation is audited and closes the direct-approval exception when no active absence remains.
set local role authenticated;
select set_config('request.jwt.claim.sub','86000000-0000-0000-0000-000000000001',true);
select public.admin_revoke_staff_leave_director_absence(
 (select id from public.admin_list_staff_leave_director_absences()
  where director_user_id='86000000-0000-0000-0000-000000000003'
    and vice_director_user_id='86000000-0000-0000-0000-000000000002'),
 'Director returned to duty'
);
reset role;

do $test$
begin
 if (select direct_to_vice_enabled from public.staff_leave_approval_route_config where singleton=true) then
   raise exception 'direct Vice exception remained enabled after evidence revocation';
 end if;
end
$test$;

rollback;
