-- Regression test: assignment edits must invalidate approval authority until a
-- System Admin explicitly attests to an actual school authority reference.
\set ON_ERROR_STOP on
begin;

insert into public.profiles(id,full_name,is_active) values
 ('71000000-0000-0000-0000-000000000001','Authority Director Fixture',true),
 ('71000000-0000-0000-0000-000000000002','Authority Vice Fixture',true),
 ('71000000-0000-0000-0000-000000000003','Authority Admin Fixture',true),
 ('71000000-0000-0000-0000-000000000004','Authority Ordinary User Fixture',true)
on conflict(id) do update set is_active=excluded.is_active;

insert into public.roles(id,code,name)
values ('71000000-0000-0000-0000-000000000005','system_admin','System Admin Authority Fixture')
on conflict(code) do nothing;
insert into public.user_roles(user_id,role_id)
select '71000000-0000-0000-0000-000000000003',id
from public.roles where code='system_admin'
on conflict do nothing;

insert into public.school_responsibility_settings(singleton,has_vice_director)
values(true,false)
on conflict(singleton) do update set has_vice_director=false;
insert into public.school_responsibility_assignments(responsibility_key,user_id)
values('director','71000000-0000-0000-0000-000000000001')
on conflict(responsibility_key) do update set user_id=excluded.user_id;
insert into public.staff_leave_approval_route_config(
 singleton,director_user_id,vice_director_user_id,authority_verified,
 direct_to_vice_enabled,no_vice_director_confirmed,authority_reference,
 verified_by,verified_at
) values(
 true,'71000000-0000-0000-0000-000000000001',null,true,false,true,
 'stale-reference','71000000-0000-0000-0000-000000000003',now()
) on conflict(singleton) do update set
 director_user_id=excluded.director_user_id,vice_director_user_id=null,
 authority_verified=true,direct_to_vice_enabled=false,
 no_vice_director_confirmed=true,authority_reference='stale-reference',
 verified_by=excluded.verified_by,verified_at=now();

-- Ordinary authenticated users must not be able to attest.
set local role authenticated;
select set_config('request.jwt.claim.sub','71000000-0000-0000-0000-000000000004',true);
do $ordinary$
begin
  begin
    perform public.admin_verify_staff_leave_approval_route('SCHOOL-ORDER-2026-TEST',true);
    raise exception 'ordinary_user_must_not_verify_authority';
  exception when others then
    if sqlerrm='ordinary_user_must_not_verify_authority' then raise; end if;
    if sqlerrm not in ('system_admin_required','permission denied') then raise; end if;
  end;
end
$ordinary$;
reset role;

-- Explicit System Admin attestation enables the route with a non-synthetic
-- evidence reference and records who/when attested.
set local role authenticated;
select set_config('request.jwt.claim.sub','71000000-0000-0000-0000-000000000003',true);
select public.admin_verify_staff_leave_approval_route('SCHOOL-ORDER-2026-TEST',true);
reset role;

do $verified$
begin
  if not exists(
    select 1 from public.staff_leave_approval_route_config
    where singleton=true and authority_verified=true
      and no_vice_director_confirmed=true
      and authority_reference='SCHOOL-ORDER-2026-TEST'
      and verified_by='71000000-0000-0000-0000-000000000003'
      and verified_at is not null
  ) then raise exception 'explicit_authority_attestation_not_persisted'; end if;
end
$verified$;

-- Any subsequent assignment audit must revoke the prior attestation.
insert into public.school_responsibility_audit(
 responsibility_key,previous_user_id,new_user_id,actor_user_id,change_kind
) values(
 'director',null,'71000000-0000-0000-0000-000000000001',
 '71000000-0000-0000-0000-000000000003','assignment_changed'
);

do $invalidated$
begin
  if not exists(
    select 1 from public.staff_leave_approval_route_config
    where singleton=true and authority_verified=false
      and authority_reference is null and verified_by is null
      and verified_at is null and no_vice_director_confirmed=false
  ) then raise exception 'assignment_change_did_not_invalidate_authority'; end if;
end
$invalidated$;

-- Audit row IDs are not authority evidence.
set local role authenticated;
select set_config('request.jwt.claim.sub','71000000-0000-0000-0000-000000000003',true);
do $synthetic$
begin
  begin
    perform public.admin_verify_staff_leave_approval_route('school_responsibility_audit:1',true);
    raise exception 'synthetic_audit_reference_must_be_rejected';
  exception when others then
    if sqlerrm='synthetic_audit_reference_must_be_rejected' then raise; end if;
    if sqlerrm<>'real_authority_reference_required' then raise; end if;
  end;
end
$synthetic$;
reset role;

rollback;
