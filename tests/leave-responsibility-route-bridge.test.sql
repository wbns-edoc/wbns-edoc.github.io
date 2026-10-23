\\set ON_ERROR_STOP on
begin;

insert into public.profiles(id,is_active) values
 ('00000000-0000-0000-0000-000000000701',true),
 ('00000000-0000-0000-0000-000000000702',true),
 ('00000000-0000-0000-0000-000000000703',true)
on conflict(id) do update set is_active=excluded.is_active;

insert into public.school_responsibility_assignments(responsibility_key,user_id,updated_by)
values
 ('director','00000000-0000-0000-0000-000000000701','00000000-0000-0000-0000-000000000703'),
 ('vice_director','00000000-0000-0000-0000-000000000702','00000000-0000-0000-0000-000000000703')
on conflict(responsibility_key) do update set user_id=excluded.user_id;

update public.school_responsibility_settings set has_vice_director=true where singleton=true;

insert into public.school_responsibility_audit(
 responsibility_key,previous_user_id,new_user_id,actor_user_id,change_kind
) values (
 'vice_director',null,'00000000-0000-0000-0000-000000000702',
 '00000000-0000-0000-0000-000000000703','assignment_changed'
);

do $test$
begin
 if not exists (
   select 1 from public.staff_leave_approval_route_config
   where singleton=true and authority_verified
     and director_user_id='00000000-0000-0000-0000-000000000701'
     and vice_director_user_id='00000000-0000-0000-0000-000000000702'
     and not no_vice_director_confirmed
     and authority_reference like 'school_responsibility_audit:%'
 ) then raise exception 'responsibility_mapping_did_not_sync_two_stage_route'; end if;
end
$test$;

update public.school_responsibility_settings
 set has_vice_director=false,updated_at=now(),
     updated_by='00000000-0000-0000-0000-000000000703'
 where singleton=true;
insert into public.school_responsibility_audit(
 responsibility_key,actor_user_id,change_kind,
 previous_has_vice_director,new_has_vice_director
) values (
 'vice_director','00000000-0000-0000-0000-000000000703',
 'vice_director_setting_changed',true,false
);

do $test$
begin
 if not exists (
   select 1 from public.staff_leave_approval_route_config
   where singleton=true and authority_verified
     and director_user_id='00000000-0000-0000-0000-000000000701'
     and vice_director_user_id is null
     and no_vice_director_confirmed
 ) then raise exception 'explicit_no_vice_confirmation_did_not_sync_director_only_route'; end if;
end
$test$;

update public.school_responsibility_assignments
 set user_id='00000000-0000-0000-0000-000000000702'
 where responsibility_key='director';
insert into public.school_responsibility_audit(
 responsibility_key,actor_user_id,change_kind
) values (
 'director','00000000-0000-0000-0000-000000000703','assignment_changed'
);

do $test$
begin
 if not exists (
   select 1 from public.staff_leave_approval_route_config
   where singleton=true and not authority_verified
 ) then raise exception 'director_vice_collision_must_fail_closed'; end if;
end
$test$;

rollback;
