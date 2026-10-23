\set ON_ERROR_STOP on
begin;

insert into public.profiles (id, is_active) values
  ('00000000-0000-0000-0000-000000000801', true),
  ('00000000-0000-0000-0000-000000000802', true),
  ('00000000-0000-0000-0000-000000000803', true),
  ('00000000-0000-0000-0000-000000000804', false)
on conflict (id) do update set is_active = excluded.is_active;

insert into public.staff_leave_approval_route_config (
  singleton, vice_director_user_id, director_user_id, authority_verified,
  direct_to_vice_enabled, authority_reference, verified_by, verified_at
) values (
  true, '00000000-0000-0000-0000-000000000803',
  '00000000-0000-0000-0000-000000000802', true, false,
  'synthetic-test-authority-reference', '00000000-0000-0000-0000-000000000802', now()
) on conflict (singleton) do update set
  vice_director_user_id=excluded.vice_director_user_id,
  director_user_id=excluded.director_user_id,
  authority_verified=excluded.authority_verified,
  direct_to_vice_enabled=excluded.direct_to_vice_enabled,
  authority_reference=excluded.authority_reference,
  verified_by=excluded.verified_by, verified_at=excluded.verified_at;

insert into public.staff_leave_types (id, code, name, is_active)
values ('00000000-0000-0000-0000-000000000821', 'decide_test', 'Decision test', true)
on conflict (id) do update set is_active = true;

insert into public.staff_leave_requests (
  id, applicant_id, leave_type_id, starts_on, ends_on, reason, status, current_approver_user_id, approval_stage, approval_route_snapshot
) values
  ('00000000-0000-0000-0000-000000000811',
   '00000000-0000-0000-0000-000000000801',
   '00000000-0000-0000-0000-000000000821',
   date '2026-12-01', date '2026-12-01', 'synthetic approval fixture', 'pending_approval',
   '00000000-0000-0000-0000-000000000802', 'director_final_review', jsonb_build_object('version',1,'route_kind','vice_director_then_director','vice_director_user_id','00000000-0000-0000-0000-000000000803','director_user_id','00000000-0000-0000-0000-000000000802','authority_reference','synthetic-test-authority-reference','authority_verified_by','00000000-0000-0000-0000-000000000802','authority_verified_at',now(),'captured_at',now())),
  ('00000000-0000-0000-0000-000000000812',
   '00000000-0000-0000-0000-000000000803',
   '00000000-0000-0000-0000-000000000821',
   date '2026-12-02', date '2026-12-02', 'synthetic rejection fixture', 'pending_approval',
   '00000000-0000-0000-0000-000000000802', 'director_final_review', jsonb_build_object('version',1,'route_kind','vice_director_then_director','vice_director_user_id','00000000-0000-0000-0000-000000000803','director_user_id','00000000-0000-0000-0000-000000000802','authority_reference','synthetic-test-authority-reference','authority_verified_by','00000000-0000-0000-0000-000000000802','authority_verified_at',now(),'captured_at',now())),
  ('00000000-0000-0000-0000-000000000813',
   '00000000-0000-0000-0000-000000000802',
   '00000000-0000-0000-0000-000000000821',
   date '2026-12-03', date '2026-12-03', 'synthetic self-approval fixture', 'pending_approval',
   '00000000-0000-0000-0000-000000000802', 'director_final_review', jsonb_build_object('version',1,'route_kind','vice_director_then_director','vice_director_user_id','00000000-0000-0000-0000-000000000803','director_user_id','00000000-0000-0000-0000-000000000802','authority_reference','synthetic-test-authority-reference','authority_verified_by','00000000-0000-0000-0000-000000000802','authority_verified_at',now(),'captured_at',now())),
  ('00000000-0000-0000-0000-000000000814',
   '00000000-0000-0000-0000-000000000801',
   '00000000-0000-0000-0000-000000000821',
   date '2026-12-04', date '2026-12-04', 'synthetic two-stage fixture', 'pending_approval',
   '00000000-0000-0000-0000-000000000803', 'vice_director_review', jsonb_build_object('version',1,'route_kind','vice_director_then_director','vice_director_user_id','00000000-0000-0000-0000-000000000803','director_user_id','00000000-0000-0000-0000-000000000802','authority_reference','synthetic-test-authority-reference','authority_verified_by','00000000-0000-0000-0000-000000000802','authority_verified_at',now(),'captured_at',now())),
  ('00000000-0000-0000-0000-000000000815',
   '00000000-0000-0000-0000-000000000801',
   '00000000-0000-0000-0000-000000000821',
   date '2026-12-05', date '2026-12-05', 'synthetic stage-skip fixture', 'pending_approval',
   '00000000-0000-0000-0000-000000000803', 'vice_director_review', jsonb_build_object('version',1,'route_kind','vice_director_then_director','vice_director_user_id','00000000-0000-0000-0000-000000000803','director_user_id','00000000-0000-0000-0000-000000000802','authority_reference','synthetic-test-authority-reference','authority_verified_by','00000000-0000-0000-0000-000000000802','authority_verified_at',now(),'captured_at',now())),
  ('00000000-0000-0000-0000-000000000816',
   '00000000-0000-0000-0000-000000000801',
   '00000000-0000-0000-0000-000000000821',
   date '2026-12-06', date '2026-12-06', 'synthetic inactive-approver fixture', 'pending_approval',
   '00000000-0000-0000-0000-000000000803', 'vice_director_review', jsonb_build_object('version',1,'route_kind','vice_director_then_director','vice_director_user_id','00000000-0000-0000-0000-000000000803','director_user_id','00000000-0000-0000-0000-000000000802','authority_reference','synthetic-test-authority-reference','authority_verified_by','00000000-0000-0000-0000-000000000802','authority_verified_at',now(),'captured_at',now()))
on conflict (id) do nothing;

set local role authenticated;
select set_config('request.jwt.claim.sub', '', true);
do $block$
begin
  begin
    perform public.staff_leave_decide(
      '00000000-0000-0000-0000-000000000811', 'approve', null, 'decide-key-unauth'
    );
    raise exception 'expected_authentication_required';
  exception when sqlstate '28000' then
    if sqlerrm <> 'authentication_required' then raise; end if;
  end;
end $block$;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000804', true);
do $block$
begin
  begin
    perform public.staff_leave_decide(
      '00000000-0000-0000-0000-000000000811', 'approve', null, 'decide-key-inactive'
    );
    raise exception 'expected_inactive_profile_denial';
  exception when sqlstate '42501' then
    if sqlerrm <> 'active_profile_required' then raise; end if;
  end;
end $block$;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000803', true);
do $block$
begin
  begin
    perform public.staff_leave_decide(
      '00000000-0000-0000-0000-000000000811', 'approve', null, 'decide-key-unassigned'
    );
    raise exception 'expected_unassigned_approver_denial';
  exception when sqlstate '42501' then
    if sqlerrm <> 'leave_request_not_found_or_not_assigned' then raise; end if;
  end;
end $block$;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000802', true);
do $block$
begin
  begin
    perform public.staff_leave_decide(
      '00000000-0000-0000-0000-000000000813', 'approve', null, 'decide-key-self'
    );
    raise exception 'expected_self_approval_denial';
  exception when sqlstate '42501' then
    if sqlerrm <> 'self_approval_forbidden' then raise; end if;
  end;
  begin
    perform public.staff_leave_decide(
      '00000000-0000-0000-0000-000000000811', null, null, 'decide-key-null'
    );
    raise exception 'expected_invalid_decision_denial';
  exception when sqlstate '22023' then
    if sqlerrm <> 'invalid_leave_decision' then raise; end if;
  end;
  begin
    perform public.staff_leave_decide(
      '00000000-0000-0000-0000-000000000812', 'reject', '   ', 'decide-key-no-reason'
    );
    raise exception 'expected_rejection_reason_required';
  exception when sqlstate '22023' then
    if sqlerrm <> 'rejection_reason_required' then raise; end if;
  end;
end $block$;

-- The Director must not skip the required Vice Director stage.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000802', true);
do $block$
begin
  begin
    perform public.staff_leave_decide(
      '00000000-0000-0000-0000-000000000815', 'approve', null, 'decide-key-skip-stage'
    );
    raise exception 'expected_director_stage_skip_denial';
  exception when sqlstate '42501' then
    if sqlerrm <> 'leave_request_not_found_or_not_assigned' then raise; end if;
  end;
end $block$;

-- Deputy Director may not reject/finalize a leave request; only forward to Director.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000803', true);
do $block$
begin
  begin
    perform public.staff_leave_decide(
      '00000000-0000-0000-0000-000000000815', 'reject',
      'Deputy cannot make final decision', 'decide-key-deputy-reject'
    );
    raise exception 'expected_deputy_final_rejection_denial';
  exception when sqlstate '42501' then
    if sqlerrm <> 'leave_request_not_found_or_not_assigned' then raise; end if;
  end;
end $block$;

-- Deputy approval must advance to the Director stage, not final-approve.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000803', true);
select public.staff_leave_decide(
  '00000000-0000-0000-0000-000000000814', 'approve', null, 'decide-key-stage-one'
);
-- Exact retry of stage one must be harmless and must not append another route action.
select public.staff_leave_decide(
  '00000000-0000-0000-0000-000000000814', 'approve', null, 'decide-key-stage-one'
);
-- Inspect the post-transition row as the test owner: the deputy's RLS access
-- correctly ends once the request is reassigned to the Director.
reset role;
select id, status, approval_stage, current_approver_user_id, decided_at
from public.staff_leave_requests where id='00000000-0000-0000-0000-000000000814';
do $block$
begin
  if not exists (
    select 1 from public.staff_leave_requests
    where id='00000000-0000-0000-0000-000000000814'
      and status='pending_approval'
      and approval_stage='director_final_review'
      and current_approver_user_id='00000000-0000-0000-0000-000000000802'
      and decided_at is null
  ) then raise exception 'vice_director_must_route_to_director_without_final_approval'; end if;
  if exists (select 1 from public.staff_leave_approval_actions
    where request_id='00000000-0000-0000-0000-000000000814' and action='approved') then
    raise exception 'vice_director_must_not_final_approve';
  end if;
  if (select count(*) from public.staff_leave_approval_actions
      where request_id='00000000-0000-0000-0000-000000000814'
        and action='routed' and metadata->>'idempotency_key'='decide-key-stage-one') <> 1 then
    raise exception 'stage_one_retry_must_append_one_route_action';
  end if;
  if (select count(*) from public.staff_leave_notification_outbox
      where request_id='00000000-0000-0000-0000-000000000814'
        and recipient_id='00000000-0000-0000-0000-000000000802'
        and event_type='approver_assigned'
        and event_key='leave-stage-advance:00000000-0000-0000-0000-000000000814:decide-key-stage-one') <> 1 then
    raise exception 'stage_one_retry_must_enqueue_one_director_notification';
  end if;
end $block$;

-- Only the configured Director can complete the final stage.
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000802', true);
select public.staff_leave_decide(
  '00000000-0000-0000-0000-000000000814', 'approve', null, 'decide-key-stage-two'
);

select public.staff_leave_decide(
  '00000000-0000-0000-0000-000000000811', 'approve', null, 'decide-key-approve-1'
);
-- Retry with the same key must not duplicate the audit action or outbox event.
select public.staff_leave_decide(
  '00000000-0000-0000-0000-000000000811', 'approve', null, 'decide-key-approve-1'
);
do $block$
begin
  begin
    perform public.staff_leave_decide(
      '00000000-0000-0000-0000-000000000811', 'approve', 'different payload', 'decide-key-approve-1'
    );
    raise exception 'expected_idempotency_payload_mismatch';
  exception when sqlstate '22023' then
    if sqlerrm <> 'idempotency_key_reused_with_different_payload' then raise; end if;
  end;
end $block$;
select public.staff_leave_decide(
  '00000000-0000-0000-0000-000000000812', 'reject', 'Policy requires correction', 'decide-key-reject-1'
);

reset role;
do $block$
begin
  if not exists (
    select 1 from public.staff_leave_requests
    where id = '00000000-0000-0000-0000-000000000811'
      and status = 'approved' and decided_at is not null
  ) then
    raise exception 'assigned_approver_must_approve_request';
  end if;
  if not exists (
    select 1 from public.staff_leave_requests
    where id = '00000000-0000-0000-0000-000000000812'
      and status = 'rejected' and approval_stage = 'completed' and decided_at is not null
  ) then
    raise exception 'assigned_approver_must_reject_request';
  end if;
  if not exists (select 1 from public.staff_leave_requests where id='00000000-0000-0000-0000-000000000814' and status='approved' and approval_stage='completed') then
    raise exception 'director_must_complete_final_approval_stage';
  end if;
  if (select count(*) from public.staff_leave_approval_actions
      where request_id = '00000000-0000-0000-0000-000000000811'
        and action = 'approved'
        and metadata->>'idempotency_key' = 'decide-key-approve-1') <> 1 then
    raise exception 'decision_retry_must_append_one_approval_action';
  end if;
  if (select count(*) from public.staff_leave_notification_outbox
      where request_id = '00000000-0000-0000-0000-000000000811'
        and event_type = 'approved') <> 1 then
    raise exception 'approval_must_enqueue_one_private_notification';
  end if;
  if (select count(*) from public.staff_leave_notification_outbox
      where request_id = '00000000-0000-0000-0000-000000000812'
        and event_type = 'rejected') <> 1 then
    raise exception 'rejection_must_enqueue_one_private_notification';
  end if;
  if has_function_privilege('anon', 'public.staff_leave_decide(uuid,text,text,text)', 'EXECUTE') then
    raise exception 'anon_must_not_execute_staff_leave_decide';
  end if;
  if not has_function_privilege('authenticated', 'public.staff_leave_decide(uuid,text,text,text)', 'EXECUTE') then
    raise exception 'authenticated_must_execute_staff_leave_decide';
  end if;
end $block$;

-- A configured approver becoming inactive must fail closed.
update public.profiles set is_active = false
where id = '00000000-0000-0000-0000-000000000803';
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000802', true);
do $block$
begin
  begin
    perform public.staff_leave_decide(
      '00000000-0000-0000-0000-000000000816', 'approve', null, 'decide-key-inactive-route'
    );
    raise exception 'expected_inactive_configured_approver_denial';
  exception when sqlstate '42501' then
    if sqlerrm <> 'configured_approver_inactive_or_missing' then raise; end if;
  end;
end $block$;
reset role;


-- Verified submission route test runs after the two-stage migration creates route config.
insert into public.profiles (id, is_active) values
  ('00000000-0000-0000-0000-000000000610', true),
  ('00000000-0000-0000-0000-000000000611', true)
on conflict (id) do update set is_active=excluded.is_active;

insert into public.staff_leave_requests (
  id, applicant_id, leave_type_id, starts_on, ends_on, reason, status
) values (
  '00000000-0000-0000-0000-000000000818',
  '00000000-0000-0000-0000-000000000801',
  '00000000-0000-0000-0000-000000000821',
  date '2026-12-08', date '2026-12-08', 'synthetic verified submit route', 'draft'
) on conflict (id) do nothing;

insert into public.staff_leave_approval_route_config (
  singleton, vice_director_user_id, director_user_id, authority_verified,
  direct_to_vice_enabled, authority_reference, verified_by, verified_at
) values (
  true, '00000000-0000-0000-0000-000000000610',
  '00000000-0000-0000-0000-000000000611', true, false,
  'synthetic-submit-route-test', '00000000-0000-0000-0000-000000000611', now()
) on conflict (singleton) do update set
  vice_director_user_id=excluded.vice_director_user_id,
  director_user_id=excluded.director_user_id,
  authority_verified=excluded.authority_verified,
  direct_to_vice_enabled=excluded.direct_to_vice_enabled,
  authority_reference=excluded.authority_reference,
  verified_by=excluded.verified_by, verified_at=excluded.verified_at;

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000801', true);
select public.staff_leave_submit(
  '00000000-0000-0000-0000-000000000818', 'submit-key-verified'
);
select public.staff_leave_submit(
  '00000000-0000-0000-0000-000000000818', 'submit-key-verified'
);
reset role;
do $block$
begin
  if not exists (
    select 1 from public.staff_leave_requests
    where id='00000000-0000-0000-0000-000000000818'
      and status='pending_approval'
      and approval_stage='vice_director_review'
      and current_approver_user_id='00000000-0000-0000-0000-000000000610'
  ) then raise exception 'verified_submission_must_route_to_deputy_first'; end if;
  if (select count(*) from public.staff_leave_approval_actions
      where request_id='00000000-0000-0000-0000-000000000818'
        and action='submitted'
        and metadata->>'approval_route'='vice_director_then_director') <> 1 then
    raise exception 'verified_submission_must_record_exactly_one_route_action';
  end if;
  if (select count(*) from public.staff_leave_notification_outbox
      where request_id='00000000-0000-0000-0000-000000000818'
        and recipient_id='00000000-0000-0000-0000-000000000610'
        and event_type='submitted'
        and event_key='leave-submit-vice:00000000-0000-0000-0000-000000000818:submit-key-verified') <> 1 then
    raise exception 'verified_submission_must_notify_deputy_exactly_once';
  end if;
  if exists (select 1 from public.staff_leave_notification_outbox
      where request_id='00000000-0000-0000-0000-000000000818'
        and recipient_id <> '00000000-0000-0000-0000-000000000610') then
    raise exception 'verified_submission_must_not_notify_director_before_deputy_review';
  end if;
end $block$;



-- Route snapshot regression: mutate the singleton after submission. The in-flight
-- request must continue to use the originally captured Vice Director and Director.
update public.staff_leave_approval_route_config set
  vice_director_user_id='00000000-0000-0000-0000-000000000803',
  director_user_id='00000000-0000-0000-0000-000000000802',
  authority_reference='synthetic-route-changed-after-submit',
  verified_by='00000000-0000-0000-0000-000000000802',
  verified_at=now(), authority_verified=true, no_vice_director_confirmed=false
where singleton=true;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000610', true);
select public.staff_leave_decide('00000000-0000-0000-0000-000000000818','approve',null,'snapshot-route-stage-one');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000611', true);
select public.staff_leave_decide('00000000-0000-0000-0000-000000000818','approve',null,'snapshot-route-stage-two');
reset role;
do $block$
begin
 if not exists (select 1 from public.staff_leave_requests
   where id='00000000-0000-0000-0000-000000000818' and status='approved'
   and approval_route_snapshot->>'vice_director_user_id'='00000000-0000-0000-0000-000000000610'
   and approval_route_snapshot->>'director_user_id'='00000000-0000-0000-0000-000000000611') then
   raise exception 'in_flight_request_must_keep_original_route_snapshot';
 end if;
end $block$;

-- The snapshot is immutable once captured; even a direct privileged UPDATE
-- must not be able to rewrite the route for an in-flight request.
do $block$
begin
  begin
    update public.staff_leave_requests
      set approval_route_snapshot = jsonb_build_object('version',1,'route_kind','director_only_confirmed_no_vice')
      where id='00000000-0000-0000-0000-000000000818';
    raise exception 'expected_immutable_route_snapshot_rejection';
  exception when sqlstate '55000' then
    if sqlerrm <> 'approval_route_snapshot_immutable' then raise; end if;
  end;
end $block$;

-- Explicit no-Vice configuration routes directly to the Director and permits
-- only the Director to make the final decision.
insert into public.staff_leave_requests (
  id, applicant_id, leave_type_id, starts_on, ends_on, reason, status
) values (
  '00000000-0000-0000-0000-000000000819',
  '00000000-0000-0000-0000-000000000801',
  '00000000-0000-0000-0000-000000000821',
  date '2026-12-09', date '2026-12-09', 'synthetic no-vice submit route', 'draft'
) on conflict (id) do nothing;

-- A caller must not be able to populate a previously empty snapshot directly.
do $block$
begin
  begin
    update public.staff_leave_requests
      set approval_route_snapshot = jsonb_build_object(
        'version', 1,
        'route_kind', 'director_only_confirmed_no_vice',
        'vice_director_user_id', null,
        'director_user_id', '00000000-0000-0000-0000-000000000611',
        'authority_reference', 'synthetic-direct-write-attempt',
        'authority_verified_by', '00000000-0000-0000-0000-000000000611',
        'authority_verified_at', now(),
        'captured_at', now()
      )
      where id='00000000-0000-0000-0000-000000000819';
    raise exception 'expected_rpc_only_route_snapshot_rejection';
  exception when sqlstate '42501' then
    if sqlerrm <> 'approval_route_snapshot_rpc_only' then raise; end if;
  end;
end $block$;



insert into public.staff_leave_approval_route_config (
  singleton, vice_director_user_id, director_user_id, authority_verified,
  direct_to_vice_enabled, authority_reference, verified_by, verified_at,
  no_vice_director_confirmed
) values (
  true, null, '00000000-0000-0000-0000-000000000611', true, false,
  'synthetic-no-vice-route-test', '00000000-0000-0000-0000-000000000611', now(), true
) on conflict (singleton) do update set
  vice_director_user_id=null,
  director_user_id=excluded.director_user_id,
  authority_verified=true,
  direct_to_vice_enabled=false,
  authority_reference=excluded.authority_reference,
  verified_by=excluded.verified_by,
  verified_at=excluded.verified_at,
  no_vice_director_confirmed=true;

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000801', true);
select public.staff_leave_submit(
  '00000000-0000-0000-0000-000000000819', 'submit-key-no-vice'
);
select public.staff_leave_submit(
  '00000000-0000-0000-0000-000000000819', 'submit-key-no-vice'
);
reset role;

do $block$
begin
  if not exists (
    select 1 from public.staff_leave_requests
    where id='00000000-0000-0000-0000-000000000819'
      and status='pending_approval'
      and approval_stage='director_final_review'
      and current_approver_user_id='00000000-0000-0000-0000-000000000611'
  ) then raise exception 'confirmed_no_vice_submission_must_route_directly_to_director'; end if;
  if (select count(*) from public.staff_leave_approval_actions
      where request_id='00000000-0000-0000-0000-000000000819'
        and action='submitted'
        and metadata->>'approval_route'='director_only_confirmed_no_vice') <> 1 then
    raise exception 'no_vice_submission_retry_must_record_one_route_action'; end if;
  if (select count(*) from public.staff_leave_notification_outbox
      where request_id='00000000-0000-0000-0000-000000000819'
        and recipient_id='00000000-0000-0000-0000-000000000611'
        and event_type='submitted'
        and event_key='leave-submit-director:00000000-0000-0000-0000-000000000819:submit-key-no-vice') <> 1 then
    raise exception 'no_vice_submission_must_notify_director_once'; end if;
end $block$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000611', true);
select public.staff_leave_decide(
  '00000000-0000-0000-0000-000000000819', 'approve', null, 'decide-key-no-vice'
);
reset role;

do $block$
begin
  if not exists (select 1 from public.staff_leave_requests
      where id='00000000-0000-0000-0000-000000000819'
        and status='approved' and approval_stage='completed' and decided_at is not null) then
    raise exception 'director_must_final_approve_confirmed_no_vice_request'; end if;
  if (select count(*) from public.staff_leave_notification_outbox
      where request_id='00000000-0000-0000-0000-000000000819'
        and recipient_id='00000000-0000-0000-0000-000000000801'
        and event_type='approved') <> 1 then
    raise exception 'no_vice_final_approval_must_notify_applicant_once'; end if;
end $block$;

rollback;
