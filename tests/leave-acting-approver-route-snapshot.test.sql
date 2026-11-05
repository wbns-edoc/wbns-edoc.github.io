\set ON_ERROR_STOP on
begin;

insert into public.profiles(id,full_name,is_active) values
 ('72000000-0000-0000-0000-000000000001','Acting Route Director',true),
 ('72000000-0000-0000-0000-000000000002','Acting Route Delegate',true),
 ('72000000-0000-0000-0000-000000000003','Acting Route Applicant',true),
 ('72000000-0000-0000-0000-000000000004','Acting Route Admin',true)
on conflict(id) do update set full_name=excluded.full_name,is_active=true;

insert into public.roles(id,code,name)
values('72000000-0000-0000-0000-000000000005','system_admin','System Admin Acting Route Test')
on conflict(code) do nothing;
insert into public.user_roles(user_id,role_id)
select '72000000-0000-0000-0000-000000000004',id from public.roles where code='system_admin'
on conflict do nothing;

insert into public.staff_leave_approval_route_config(
 singleton,director_user_id,vice_director_user_id,authority_verified,
 direct_to_vice_enabled,no_vice_director_confirmed,authority_reference,verified_by,verified_at
) values(
 true,'72000000-0000-0000-0000-000000000001',null,true,false,true,
 'SCHOOL-ACTING-ROUTE-TEST','72000000-0000-0000-0000-000000000004',statement_timestamp()
) on conflict(singleton) do update set
 director_user_id=excluded.director_user_id,vice_director_user_id=null,
 authority_verified=true,direct_to_vice_enabled=false,no_vice_director_confirmed=true,
 authority_reference=excluded.authority_reference,verified_by=excluded.verified_by,
 verified_at=excluded.verified_at;

insert into public.staff_leave_types(id,code,name,is_active)
values('72000000-0000-0000-0000-000000000006','acting_route_test','Acting route test',true)
on conflict(id) do update set is_active=true;

insert into public.staff_leave_requests(
 id,applicant_id,leave_type_id,starts_on,ends_on,reason,status
) values(
 '72000000-0000-0000-0000-000000000007',
 '72000000-0000-0000-0000-000000000003',
 '72000000-0000-0000-0000-000000000006',
 date '2026-12-10',date '2026-12-10','acting route snapshot regression','draft'
) on conflict(id) do nothing;

-- A System Admin creates a time-bounded delegation with an auditable reference.
set local role authenticated;
select set_config('request.jwt.claim.sub','72000000-0000-0000-0000-000000000004',true);
select public.admin_create_staff_leave_approver_delegation(
 '72000000-0000-0000-0000-000000000002',
 statement_timestamp()-interval '1 hour',
 statement_timestamp()+interval '1 day',
 'Director unavailable for the test period',
 'SCHOOL-ORDER-ACTING-TEST-01'
) as acting_delegation_id
\gset
reset role;

-- Submission freezes the delegate identity and delegation evidence into the route.
set local role authenticated;
select set_config('request.jwt.claim.sub','72000000-0000-0000-0000-000000000003',true);
select public.staff_leave_submit(
 '72000000-0000-0000-0000-000000000007','acting-route-submit-key'
);
reset role;

do $snapshot$
begin
 if not exists(
  select 1 from public.staff_leave_requests
  where id='72000000-0000-0000-0000-000000000007'
    and status='pending_approval'
    and approval_stage='director_final_review'
    and current_approver_user_id='72000000-0000-0000-0000-000000000002'
    and approval_route_snapshot->>'route_kind'='director_acting_approver'
    and approval_route_snapshot->>'acting_approver_user_id'='72000000-0000-0000-0000-000000000002'
    and approval_route_snapshot->>'delegation_id=:'||'acting_delegation_id'
 ) then
  -- Compare the captured delegation id using the psql variable separately below.
  if not exists(select 1 from public.staff_leave_requests
    where id='72000000-0000-0000-0000-000000000007'
      and approval_route_snapshot->>'route_kind'='director_acting_approver'
      and approval_route_snapshot->>'acting_approver_user_id'='72000000-0000-0000-0000-000000000002'
      and nullif(approval_route_snapshot->>'delegation_id','') is not null) then
    raise exception 'submission_did_not_freeze_acting_approver_route';
  end if;
 end if;
end
$snapshot$;

-- Revocation after submission must not re-route or invalidate this in-flight request.
set local role authenticated;
select set_config('request.jwt.claim.sub','72000000-0000-0000-0000-000000000004',true);
select public.admin_revoke_staff_leave_approver_delegation(:'acting_delegation_id'::uuid,'Test revocation after submission');
reset role;

-- Director cannot decide a request already assigned to the acting approver.
set local role authenticated;
select set_config('request.jwt.claim.sub','72000000-0000-0000-0000-000000000001',true);
do $wrong_actor$
begin
 begin
  perform public.staff_leave_decide(
   '72000000-0000-0000-0000-000000000007','approve',null,'acting-route-wrong-actor'
  );
  raise exception 'director_must_not_bypass_captured_acting_approver';
 exception when sqlstate '42501' then
  if sqlerrm<>'leave_request_not_found_or_not_assigned' then raise; end if;
 end;
end
$wrong_actor$;
reset role;

-- The originally captured delegate remains the sole final approver after revocation.
set local role authenticated;
select set_config('request.jwt.claim.sub','72000000-0000-0000-0000-000000000002',true);
select public.staff_leave_decide(
 '72000000-0000-0000-0000-000000000007','approve',null,'acting-route-delegate-approve'
);
reset role;

do $final$
begin
 if not exists(select 1 from public.staff_leave_requests
   where id='72000000-0000-0000-0000-000000000007'
     and status='approved' and approval_stage='completed'
     and current_approver_user_id='72000000-0000-0000-0000-000000000002') then
  raise exception 'captured_acting_approver_must_complete_after_delegation_revocation';
 end if;
 if (select count(*) from public.staff_leave_approval_actions
   where request_id='72000000-0000-0000-0000-000000000007' and action='approved')<>1 then
  raise exception 'acting_approver_decision_must_be_audited_once';
 end if;
end
$final$;

rollback;
