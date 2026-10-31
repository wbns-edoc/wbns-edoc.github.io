\set ON_ERROR_STOP on
begin;

-- End-to-end: audited school responsibility settings must flow through to
-- the immutable approval-route snapshot captured by staff_leave_submit().
insert into public.profiles(id,is_active) values
 ('00000000-0000-0000-0000-000000000801',true), -- applicant
 ('00000000-0000-0000-0000-000000000802',true), -- director
 ('00000000-0000-0000-0000-000000000803',true), -- vice director
 ('00000000-0000-0000-0000-000000000804',true)  -- settings actor
on conflict(id) do update set is_active=excluded.is_active;

insert into public.staff_leave_types(id,code,name,is_active)
values ('00000000-0000-0000-0000-000000000805','route_e2e_test','Route E2E test',true)
on conflict(id) do update set is_active=true;

insert into public.school_responsibility_assignments(responsibility_key,user_id,updated_by)
values
 ('director','00000000-0000-0000-0000-000000000802','00000000-0000-0000-0000-000000000804'),
 ('vice_director','00000000-0000-0000-0000-000000000803','00000000-0000-0000-0000-000000000804')
on conflict(responsibility_key) do update set user_id=excluded.user_id;

update public.school_responsibility_settings
 set has_vice_director=true,updated_by='00000000-0000-0000-0000-000000000804'
 where singleton=true;

insert into public.school_responsibility_audit(
 responsibility_key,previous_user_id,new_user_id,actor_user_id,change_kind
) values (
 'vice_director',null,'00000000-0000-0000-0000-000000000803',
 '00000000-0000-0000-0000-000000000804','assignment_changed'
);

insert into public.staff_leave_policy_versions(
 id,policy_code,version,status,effective_from,policy_rules,reviewed_by,reviewed_at
) values (
 '00000000-0000-0000-0000-000000000807',
 'school-wide',2,'approved',date '2026-01-01',
 '{"fixture":true,"verification_status":"approved","calculation_ready":true,
   "calendar":{"verified":true,"weekend_days":[6,7],"non_working_dates":[]},"implementation_gaps":[],
   "leave_types":{"route_e2e_test":{"counting_basis":"calendar_days"}}}'::jsonb,
 '00000000-0000-0000-0000-000000000804',now()
);

insert into public.staff_leave_requests(id,applicant_id,leave_type_id,policy_version_id,starts_on,ends_on,day_count,reason,policy_snapshot,status)
values (
 '00000000-0000-0000-0000-000000000806',
 '00000000-0000-0000-0000-000000000801',
 '00000000-0000-0000-0000-000000000805',
 '00000000-0000-0000-0000-000000000807',
 date '2026-11-25',date '2026-11-25',1,'synthetic route integration test',
 '{"policy_version_id":"00000000-0000-0000-0000-000000000807","leave_type_code":"route_e2e_test","verification_status":"approved","calculation_ready":true,"calculated_day_count":1}'::jsonb,'draft'
) on conflict(id) do nothing;

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000801',true);
select public.staff_leave_submit('00000000-0000-0000-0000-000000000806','route-e2e-key-0001');
reset role;

do $test$
begin
 if not exists (
   select 1 from public.staff_leave_requests r
   where r.id='00000000-0000-0000-0000-000000000806'
     and r.status='pending_approval'
     and r.approval_stage='vice_director_review'
     and r.current_approver_user_id='00000000-0000-0000-0000-000000000803'
     and r.approval_route_snapshot->>'route_kind'='vice_director_then_director'
     and r.approval_route_snapshot->>'vice_director_user_id'='00000000-0000-0000-0000-000000000803'
     and r.approval_route_snapshot->>'director_user_id'='00000000-0000-0000-0000-000000000802'
 ) then raise exception 'audited_responsibility_did_not_reach_submission_route_snapshot'; end if;
 if not exists (
   select 1 from public.staff_leave_notification_outbox n
   where n.request_id='00000000-0000-0000-0000-000000000806'
     and n.recipient_id='00000000-0000-0000-0000-000000000803'
     and n.event_type='submitted'
 ) then raise exception 'vice_director_submission_notification_not_enqueued'; end if;
end
$test$;

-- Explicitly confirmed no-vice case must route directly to the director.
update public.school_responsibility_settings
 set has_vice_director=false,updated_by='00000000-0000-0000-0000-000000000804'
 where singleton=true;
insert into public.school_responsibility_audit(
 responsibility_key,actor_user_id,change_kind,previous_has_vice_director,new_has_vice_director
) values (
 'vice_director','00000000-0000-0000-0000-000000000804',
 'vice_director_setting_changed',true,false
);

insert into public.staff_leave_requests(id,applicant_id,leave_type_id,policy_version_id,starts_on,ends_on,day_count,reason,policy_snapshot,status)
values (
 '00000000-0000-0000-0000-000000000807',
 '00000000-0000-0000-0000-000000000801',
 '00000000-0000-0000-0000-000000000805',
 '00000000-0000-0000-0000-000000000807',
 date '2026-11-26',date '2026-11-26',1,'synthetic no-vice integration test',
 '{"policy_version_id":"00000000-0000-0000-0000-000000000807","leave_type_code":"route_e2e_test","verification_status":"approved","calculation_ready":true,"calculated_day_count":1}'::jsonb,'draft'
) on conflict(id) do nothing;

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000801',true);
select public.staff_leave_submit('00000000-0000-0000-0000-000000000807','route-e2e-key-0002');
reset role;

do $test$
begin
 if not exists (
   select 1 from public.staff_leave_requests r
   where r.id='00000000-0000-0000-0000-000000000807'
     and r.status='pending_approval'
     and r.approval_stage='director_final_review'
     and r.current_approver_user_id='00000000-0000-0000-0000-000000000802'
     and r.approval_route_snapshot->>'route_kind'='director_only_confirmed_no_vice'
     and r.approval_route_snapshot->'vice_director_user_id'='null'::jsonb
 ) then raise exception 'confirmed_no_vice_did_not_reach_director_only_snapshot'; end if;
 if not exists (
   select 1 from public.staff_leave_notification_outbox n
   where n.request_id='00000000-0000-0000-0000-000000000807'
     and n.recipient_id='00000000-0000-0000-0000-000000000802'
     and n.event_type='submitted'
 ) then raise exception 'director_submission_notification_not_enqueued'; end if;
end
$test$;

rollback;
