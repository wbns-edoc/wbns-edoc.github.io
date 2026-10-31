\set ON_ERROR_STOP on
begin;

insert into public.profiles(id,is_active) values
 ('84000000-0000-0000-0000-000000000001',true),
 ('84000000-0000-0000-0000-000000000002',true)
on conflict(id) do update set is_active=excluded.is_active;

insert into public.staff_leave_types(id,code,name,is_active) values
 ('84000000-0000-0000-0000-000000000003','sick_leave','Sick leave',true),
 ('84000000-0000-0000-0000-000000000004','assist_spouse_childbirth','Assist spouse childbirth',true)
on conflict(code) do update set is_active=true;

create temporary table test_leave_type_ids on commit drop as
select code,id from public.staff_leave_types
where code in ('sick_leave','assist_spouse_childbirth');
grant select on test_leave_type_ids to authenticated;

insert into public.staff_leave_policy_versions(
 id,policy_code,version,status,effective_from,policy_rules,reviewed_by,reviewed_at
) values (
 '84000000-0000-0000-0000-000000000005','school-wide',88,'approved',date '2026-01-01',
 '{"verification_status":"approved","calculation_ready":true,
   "calendar":{"weekend_days":[6,7],"non_working_dates":[],"verified":true},
   "implementation_gaps":[],
   "leave_types":{
     "sick_leave":{"counting_basis":"working_days","certificate_from_working_day":3},
     "assist_spouse_childbirth":{"counting_basis":"working_days","max_working_days_per_event":15,
       "one_continuous_period_required":true,"one_entitlement_per_childbirth_event":true}
   }}'::jsonb,
 '84000000-0000-0000-0000-000000000002',now()
);

set local role authenticated;
select set_config('request.jwt.claim.sub','84000000-0000-0000-0000-000000000001',true);

-- PASS: two-day sick leave does not require a certificate.
select public.staff_leave_create_draft(
 (select id from test_leave_type_ids where code='sick_leave'),date '2026-11-02',date '2026-11-03',
 'two day sick leave',null
);
-- PASS: 3-day sick leave with medical certificate is allowed through rule trigger.
select public.staff_leave_create_draft(
 (select id from test_leave_type_ids where code='sick_leave'),date '2026-11-02',date '2026-11-04',
 'three day sick leave with certificate',null
);
reset role;

insert into public.staff_leave_attachments(
 request_id,uploaded_by,storage_object_key,original_filename,mime_type,size_bytes,attachment_kind
)
select id,'84000000-0000-0000-0000-000000000001',
 'test/medical-certificate/'||id::text,'certificate.pdf','application/pdf',100,'medical_certificate'
from public.staff_leave_requests where reason='three day sick leave with certificate';

do $positive$
declare r record;
begin
  select * into r from public.staff_leave_requests where reason='three day sick leave with certificate';
  update public.staff_leave_requests set status='pending_approval' where id=r.id;
  select * into r from public.staff_leave_requests where reason='two day sick leave';
  update public.staff_leave_requests set status='pending_approval' where id=r.id;
end
$positive$;

set local role authenticated;
select set_config('request.jwt.claim.sub','84000000-0000-0000-0000-000000000001',true);
-- PASS: one 15-working-day continuous period, tied to one childbirth event.
select public.staff_leave_create_draft(
 (select id from test_leave_type_ids where code='assist_spouse_childbirth'),date '2026-11-02',date '2026-11-20',
 'childbirth event entitlement','2026-11-01'
);
reset role;

do $negative$
declare v_id uuid;
begin
  select id into v_id from public.staff_leave_requests
   where reason='childbirth event entitlement';
  -- A 16th working day must be refused.
  begin
    update public.staff_leave_requests set day_count=16,status='pending_approval' where id=v_id;
    raise exception 'expected_16_day_childbirth_denial';
  exception when check_violation then
    if sqlerrm not in ('childbirth_leave_rule_violation') then raise; end if;
  end;
  -- Duplicate event is refused at unique-index level.
  begin
    insert into public.staff_leave_requests(
      applicant_id,leave_type_id,starts_on,ends_on,reason,status,childbirth_event_date
    ) values (
      '84000000-0000-0000-0000-000000000001',
      (select id from test_leave_type_ids where code='assist_spouse_childbirth'),
      date '2026-11-23',date '2026-11-23','duplicate event','draft',date '2026-11-01'
    );
    raise exception 'expected_duplicate_childbirth_event_denial';
  exception when unique_violation then null;
  end;
  -- A submitted 3-day sick leave without certificate must be refused.
  insert into public.staff_leave_requests(
    applicant_id,leave_type_id,policy_version_id,starts_on,ends_on,day_count,
    reason,status,policy_snapshot
  ) values (
    '84000000-0000-0000-0000-000000000001',
    (select id from test_leave_type_ids where code='sick_leave'),
    '84000000-0000-0000-0000-000000000005',
    date '2026-11-02',date '2026-11-04',3,'missing medical certificate','draft',
    '{"verification_status":"approved","calculation_ready":true}'::jsonb
  ) returning id into v_id;
  begin
    update public.staff_leave_requests set status='pending_approval' where id=v_id;
    raise exception 'expected_missing_certificate_denial';
  exception when check_violation then
    if sqlerrm<>'medical_certificate_required_for_sick_leave' then raise; end if;
  end;
end
$negative$;

rollback;
