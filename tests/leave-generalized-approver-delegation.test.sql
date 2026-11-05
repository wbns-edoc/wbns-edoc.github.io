\\set ON_ERROR_STOP on
begin;

insert into public.profiles(id,full_name,is_active) values
 ('72000000-0000-0000-0000-000000000001','Delegation Director Fixture',true),
 ('72000000-0000-0000-0000-000000000002','Delegation Admin Fixture',true),
 ('72000000-0000-0000-0000-000000000003','Delegation Acting Approver A',true),
 ('72000000-0000-0000-0000-000000000004','Delegation Acting Approver B',true),
 ('72000000-0000-0000-0000-000000000005','Delegation Ordinary User',true)
on conflict(id) do update set is_active=true;

insert into public.roles(id,code,name)
values('72000000-0000-0000-0000-000000000006','system_admin','Delegation Test System Admin')
on conflict(code) do nothing;
insert into public.user_roles(user_id,role_id)
select '72000000-0000-0000-0000-000000000002',id from public.roles where code='system_admin'
on conflict do nothing;

insert into public.staff_leave_approval_route_config(
 singleton,director_user_id,vice_director_user_id,authority_verified,
 direct_to_vice_enabled,no_vice_director_confirmed,authority_reference,verified_by,verified_at
) values(
 true,'72000000-0000-0000-0000-000000000001',null,true,false,true,
 'SCHOOL-AUTHORITY-ORDER-2026','72000000-0000-0000-0000-000000000002',now()
) on conflict(singleton) do update set
 director_user_id=excluded.director_user_id,vice_director_user_id=null,
 authority_verified=true,direct_to_vice_enabled=false,no_vice_director_confirmed=true,
 authority_reference=excluded.authority_reference,verified_by=excluded.verified_by,verified_at=now();

-- Only an explicitly authorized System Admin can create a delegation.
set local role authenticated;
select set_config('request.jwt.claim.sub','72000000-0000-0000-0000-000000000005',true);
do $ordinary$
begin
  begin
    perform public.admin_create_staff_leave_approver_delegation(
      '72000000-0000-0000-0000-000000000003',now(),now()+interval '1 day',
      'Director unavailable','SCHOOL-ORDER-2026-01');
    raise exception 'ordinary_user_must_not_create_delegation';
  exception when others then
    if sqlerrm='ordinary_user_must_not_create_delegation' then raise; end if;
    if sqlerrm not in ('system_admin_required','permission denied') then raise; end if;
  end;
end
$ordinary$;
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub','72000000-0000-0000-0000-000000000002',true);
select public.admin_create_staff_leave_approver_delegation(
 '72000000-0000-0000-0000-000000000003',
 '2026-11-05 00:00:00+07','2026-11-06 00:00:00+07',
 'ผู้อำนวยการไม่สามารถปฏิบัติหน้าที่','SCHOOL-ORDER-2026-01'
) as delegation_id \gset
reset role;

do $created$
begin
 if not exists(select 1 from public.staff_leave_approver_delegations
   where acting_approver_user_id='72000000-0000-0000-0000-000000000003'
   and director_user_id='72000000-0000-0000-0000-000000000001'
   and created_by='72000000-0000-0000-0000-000000000002'
   and revoked_at is null) then
   raise exception 'delegation_not_audited';
 end if;
 if not exists(select 1 from public.staff_leave_active_acting_approver(
   '72000000-0000-0000-0000-000000000001','2026-11-05 12:00:00+07'
 ) where acting_approver_user_id='72000000-0000-0000-0000-000000000003') then
   raise exception 'active_delegation_not_resolved';
 end if;
 if exists(select 1 from public.staff_leave_active_acting_approver(
   '72000000-0000-0000-0000-000000000001','2026-11-06 00:00:00+07'
 )) then raise exception 'delegation_must_expire_at_end_exclusive'; end if;
end
$created$;

-- Reject overlapping validity windows for the same Director.
set local role authenticated;
select set_config('request.jwt.claim.sub','72000000-0000-0000-0000-000000000002',true);
do $overlap$
begin
 begin
  perform public.admin_create_staff_leave_approver_delegation(
   '72000000-0000-0000-0000-000000000004',
   '2026-11-05 23:00:00+07','2026-11-06 23:00:00+07',
   'Overlapping appointment','SCHOOL-ORDER-2026-02');
  raise exception 'overlapping_delegation_must_be_rejected';
 exception when others then
  if sqlerrm='overlapping_delegation_must_be_rejected' then raise; end if;
  if sqlerrm<>'overlapping_active_delegation_exists' then raise; end if;
 end;
end
$overlap$;
select public.admin_revoke_staff_leave_approver_delegation(
 (select id from public.staff_leave_approver_delegations
  where acting_approver_user_id='72000000-0000-0000-0000-000000000003'),
 'Revoked in regression test');
reset role;

do $revoked$
begin
 if exists(select 1 from public.staff_leave_active_acting_approver(
   '72000000-0000-0000-0000-000000000001','2026-11-05 12:00:00+07'
 )) then raise exception 'revoked_delegation_still_resolves'; end if;
 if not exists(select 1 from public.staff_leave_approver_delegations
   where acting_approver_user_id='72000000-0000-0000-0000-000000000003'
   and revoked_by='72000000-0000-0000-0000-000000000002'
   and revoked_at is not null and revocation_reason='Revoked in regression test') then
   raise exception 'revocation_not_audited';
 end if;
end
$revoked$;

rollback;
