\set ON_ERROR_STOP on
begin;

insert into public.profiles(id,is_active) values
 ('86000000-0000-0000-0000-000000000001',true),
 ('86000000-0000-0000-0000-000000000002',true),
 ('86000000-0000-0000-0000-000000000003',true),
 ('86000000-0000-0000-0000-000000000004',true)
on conflict(id) do update set is_active=excluded.is_active;

insert into public.roles(id,code,name)
values ('86000000-0000-0000-0000-000000000005','system_admin','System Admin')
on conflict(id) do nothing;
insert into public.user_roles(user_id,role_id)
values ('86000000-0000-0000-0000-000000000001','86000000-0000-0000-0000-000000000005')
on conflict do nothing;

insert into public.staff_leave_types(id,code,name,is_active)
values ('86000000-0000-0000-0000-000000000006','absence_test','Absence test',true)
on conflict(id) do update set is_active=true;

insert into public.staff_leave_policy_versions(
 id,policy_code,version,status,effective_from,policy_rules,reviewed_by,reviewed_at
) values (
 '86000000-0000-0000-0000-000000000007',
 'school-wide',5,'approved',date '2026-01-01',
 '{"verification_status":"approved","calculation_ready":true,
   "calendar":{"non_working_dates":[]},
   "leave_types":{"absence_test":{"counting_basis":"calendar_days"}}}'::jsonb,
 '86000000-0000-0000-0000-000000000001',now()
);

insert into public.staff_leave_approval_route_config(
 singleton,vice_director_user_id,director_user_id,authority_verified,
 direct_to_vice_enabled,no_vice_director_confirmed,
 authority_reference,verified_by,verified_at
) values (
 true,'86000000-0000-0000-0000-000000000002',
 '86000000-0000-0000-0000-000000000003',true,true,false,
 'synthetic-verified-route','86000000-0000-0000-0000-000000000001',now()
) on conflict(singleton) do update set
 vice_director_user_id=excluded.vice_director_user_id,
 director_user_id=excluded.director_user_id,
 authority_verified=true,direct_to_vice_enabled=true,
 no_vice_director_confirmed=false,
 authority_reference=excluded.authority_reference,
 verified_by=excluded.verified_by,verified_at=excluded.verified_at;

insert into public.staff_leave_requests(
 id,applicant_id,leave_type_id,policy_version_id,starts_on,ends_on,day_count,
 reason,policy_snapshot,status,current_approver_user_id,approval_stage
) values (
 '86000000-0000-0000-0000-000000000008',
 '86000000-0000-0000-0000-000000000004',
 '86000000-0000-0000-0000-000000000006',
 '86000000-0000-0000-0000-000000000007',
 date '2026-11-20',date '2026-11-20',1,
 'synthetic director absence approval test',
 '{"policy_version_id":"86000000-0000-0000-0000-000000000007","leave_type_code":"absence_test","verification_status":"approved","calculation_ready":true,"calculated_day_count":1}'::jsonb,
 'pending_approval','86000000-0000-0000-0000-000000000002','vice_director_review'
);

-- A global switch alone is not evidence: direct approval must fail closed.
set local role authenticated;
select set_config('request.jwt.claim.sub','86000000-0000-0000-0000-000000000002',true);
do $test$
begin
  begin
    perform public.staff_leave_decide(
      '86000000-0000-0000-0000-000000000008','approve',null,'absence-no-evidence-01'
    );
    raise exception 'direct vice approval without evidence unexpectedly succeeded';
  exception when sqlstate '42501' then
    if sqlerrm <> 'director_absence_evidence_required' then raise; end if;
  end;
end
$test$;
reset role;

-- Only a System Admin can record the Director's dated absence and authority reference.
set local role authenticated;
select set_config('request.jwt.claim.sub','86000000-0000-0000-0000-000000000001',true);
select public.admin_record_staff_leave_director_absence(
 (statement_timestamp() at time zone 'Asia/Bangkok')::date - 1,
 (statement_timestamp() at time zone 'Asia/Bangkok')::date + 1,
 'Director is officially absent',
 'SCHOOL-ORDER-TEST-2026-10'
);
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub','86000000-0000-0000-0000-000000000001',true);
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
 '86000000-0000-0000-0000-000000000008','approve',null,'absence-approved-vice-01'
);
reset role;

do $test$
begin
 if not exists(
   select 1 from public.staff_leave_requests
   where id='86000000-0000-0000-0000-000000000008'
     and status='approved' and approval_stage='completed'
     and current_approver_user_id is null
 ) then raise exception 'Vice Director did not complete final approval during verified Director absence'; end if;
 if not exists(
   select 1 from public.staff_leave_approval_actions
   where request_id='86000000-0000-0000-0000-000000000008'
     and actor_id='86000000-0000-0000-0000-000000000002'
     and action='approved'
     and metadata->>'director_absence_override'='true'
     and metadata ? 'absence_evidence_id'
     and metadata->>'absence_authority_reference'='SCHOOL-ORDER-TEST-2026-10'
 ) then raise exception 'direct Vice approval did not preserve absence evidence in audit metadata'; end if;
 if not exists(
   select 1 from public.staff_leave_notification_outbox
   where request_id='86000000-0000-0000-0000-000000000008'
     and recipient_id='86000000-0000-0000-0000-000000000004'
     and event_type='approved'
 ) then raise exception 'applicant approval notification was not enqueued'; end if;
end
$test$;

-- Revocation is audited and closes the direct-approval exception when no active absence remains.
set local role authenticated;
select set_config('request.jwt.claim.sub','86000000-0000-0000-0000-000000000001',true);
select public.admin_revoke_staff_leave_director_absence(
 (select id from public.staff_leave_director_absence_evidence
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
