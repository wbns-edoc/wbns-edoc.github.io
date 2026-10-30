-- Draft-only over-limit marking and in-app notification fan-out.
-- Thresholds come only from an approved school-wide policy version.
begin;

alter table public.staff_leave_requests
  add column if not exists is_over_limit boolean not null default false;

alter table public.staff_leave_notification_outbox
  drop constraint if exists staff_leave_notification_outbox_event_type_check;
alter table public.staff_leave_notification_outbox
  add constraint staff_leave_notification_outbox_event_type_check
  check (event_type in (
    'submitted','approver_assigned','approved','rejected','cancelled',
    'blocked','overdue','over_limit'
  ));

create or replace function public.staff_leave_create_draft(
  p_leave_type_id uuid,
  p_starts_on date,
  p_ends_on date,
  p_reason text
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_actor uuid;
  v_request_id uuid;
  v_type_code text;
  v_policy_id uuid;
  v_policy_version integer;
  v_policy_rules jsonb;
  v_type_rules jsonb;
  v_counting_basis text;
  v_day_count numeric(7,2);
  v_max_days numeric(7,2);
  v_is_over_limit boolean := false;
  v_policy_snapshot jsonb;
begin
  v_actor := auth.uid();
  if v_actor is null then
    raise exception 'authentication_required' using errcode = '28000';
  end if;
  if not exists (
    select 1 from public.profiles p
    where p.id = v_actor and p.is_active = true
  ) then
    raise exception 'active_profile_required' using errcode = '42501';
  end if;
  if p_starts_on is null or p_ends_on is null or p_ends_on < p_starts_on then
    raise exception 'invalid_leave_date_range' using errcode = '22023';
  end if;
  if p_reason is null or length(btrim(p_reason)) = 0 or length(p_reason) > 4000 then
    raise exception 'invalid_leave_reason' using errcode = '22023';
  end if;

  select lt.code into v_type_code
  from public.staff_leave_types lt
  where lt.id = p_leave_type_id and lt.is_active = true;
  if v_type_code is null then
    raise exception 'active_leave_type_required' using errcode = '22023';
  end if;

  select pv.id, pv.version, pv.policy_rules,
         pv.policy_rules->'leave_types'->v_type_code
    into v_policy_id, v_policy_version, v_policy_rules, v_type_rules
  from public.staff_leave_policy_versions pv
  where pv.policy_code = 'school-wide'
    and pv.status = 'approved'
    and pv.policy_rules->>'verification_status' = 'approved'
    and pv.policy_rules->>'calculation_ready' = 'true'
    and (pv.effective_from is null or pv.effective_from <= p_starts_on)
    and (pv.effective_until is null or pv.effective_until >= p_ends_on)
    and jsonb_typeof(pv.policy_rules->'leave_types'->v_type_code) = 'object'
  order by pv.version desc
  limit 1;

  if v_policy_id is not null then
    v_counting_basis := v_type_rules->>'counting_basis';
    if v_counting_basis = 'calendar_days' then
      v_day_count := (p_ends_on - p_starts_on + 1)::numeric;
    elsif v_counting_basis = 'working_days'
       and jsonb_typeof(v_policy_rules->'calendar'->'non_working_dates') = 'array' then
      select count(*)::numeric into v_day_count
      from generate_series(p_starts_on, p_ends_on, interval '1 day') as day_value
      where extract(isodow from day_value) between 1 and 5
        and not exists (
          select 1
          from jsonb_array_elements_text(v_policy_rules->'calendar'->'non_working_dates') as holiday(value)
          where holiday.value::date = day_value::date
        );
    else
      v_policy_id := null;
      v_policy_version := null;
      v_policy_rules := null;
      v_type_rules := null;
      v_day_count := null;
    end if;
  end if;

  if v_policy_id is not null and (v_day_count is null or v_day_count <= 0) then
    v_policy_id := null;
    v_policy_version := null;
    v_policy_rules := null;
    v_type_rules := null;
    v_day_count := null;
  end if;

  if v_policy_id is not null then
    if nullif(v_type_rules->>'max_days_per_request','') is not null then
      v_max_days := (v_type_rules->>'max_days_per_request')::numeric;
      v_is_over_limit := v_day_count > v_max_days;
    end if;
    v_policy_snapshot := jsonb_build_object(
      'policy_code', 'school-wide',
      'policy_version_id', v_policy_id,
      'policy_version', v_policy_version,
      'leave_type_code', v_type_code,
      'verification_status', 'approved',
      'calculation_ready', true,
      'counting_basis', v_counting_basis,
      'calculated_day_count', v_day_count,
      'max_days_per_request', v_max_days,
      'is_over_limit', v_is_over_limit,
      'policy_rules_snapshot', v_policy_rules
    );
  else
    v_policy_snapshot := jsonb_build_object(
      'leave_type_code', v_type_code,
      'verification_status', 'pending',
      'calculation_ready', false,
      'is_over_limit', false
    );
  end if;

  insert into public.staff_leave_requests (
    applicant_id, leave_type_id, policy_version_id, starts_on, ends_on,
    day_count, is_over_limit, reason, policy_snapshot, status
  ) values (
    v_actor, p_leave_type_id, v_policy_id, p_starts_on, p_ends_on,
    v_day_count, v_is_over_limit, btrim(p_reason), v_policy_snapshot, 'draft'
  )
  returning id into v_request_id;

  return v_request_id;
end;
$$;

revoke all on function public.staff_leave_create_draft(uuid,date,date,text)
  from public, anon;
grant execute on function public.staff_leave_create_draft(uuid,date,date,text)
  to authenticated;

create or replace function public.staff_leave_deliver_in_app_notification()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_title text;
  v_body text;
  v_priority text;
begin
  if new.channel <> 'in_app' then
    return new;
  end if;

  case new.event_type
    when 'submitted' then
      v_title := 'มีใบลารอพิจารณา';
      v_body := 'มีคำขอลาใหม่ที่ต้องดำเนินการ';
      v_priority := 'high';
    when 'approver_assigned' then
      v_title := 'มีใบลารอพิจารณา';
      v_body := 'มีคำขอลาที่ส่งต่อมายังขั้นตอนของคุณ';
      v_priority := 'high';
    when 'approved' then
      v_title := 'ใบลาได้รับอนุมัติ';
      v_body := 'คำขอลาของคุณได้รับการอนุมัติแล้ว';
      v_priority := 'normal';
    when 'rejected' then
      v_title := 'ผลการพิจารณาใบลา';
      v_body := 'คำขอลาของคุณไม่ได้รับการอนุมัติ โปรดเข้าสู่ระบบเพื่อตรวจสอบ';
      v_priority := 'normal';
    when 'cancelled' then
      v_title := 'ยกเลิกใบลาแล้ว';
      v_body := 'มีการบันทึกการยกเลิกคำขอลา';
      v_priority := 'normal';
    when 'blocked' then
      v_title := 'ใบลารอการตรวจสอบ';
      v_body := 'คำขอลายังไม่ถูกส่งให้ผู้อนุมัติ เนื่องจากต้องตรวจสอบการกำหนดผู้รับผิดชอบ';
      v_priority := 'high';
    when 'overdue' then
      v_title := 'แจ้งเตือนตรวจสอบการกลับเข้าปฏิบัติงาน';
      v_body := 'มีรายการที่ถึงกำหนดกลับเข้าปฏิบัติงานและรอการตรวจสอบ';
      v_priority := 'high';
    when 'over_limit' then
      v_title := 'คำขอลาเกินเกณฑ์ที่กำหนด';
      v_body := 'มีคำขอลาที่เกินเกณฑ์ตามนโยบายกลาง โปรดตรวจสอบก่อนพิจารณา';
      v_priority := 'high';
    else
      raise exception 'unsupported_staff_leave_notification_event: %', new.event_type;
  end case;

  insert into public.notifications (
    recipient_id, document_id, type, title, body, priority
  ) values (
    new.recipient_id, null, 'staff_leave_' || new.event_type,
    v_title, v_body, v_priority
  );

  update public.staff_leave_notification_outbox
     set status = 'sent',
         sent_at = statement_timestamp(),
         last_error_code = null
   where id = new.id
     and status in ('pending','retry','processing');

  return new;
end;
$$;

create or replace function public.staff_leave_notify_over_limit()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_director uuid;
  v_vice_director uuid;
  v_recipient uuid;
begin
  if old.status = 'draft' and new.status = 'pending_approval'
     and new.is_over_limit = true then
    select director_user_id, vice_director_user_id
      into v_director, v_vice_director
    from public.staff_leave_approval_route_config
    where singleton = true and authority_verified = true;

    foreach v_recipient in array array[v_director, v_vice_director] loop
      if v_recipient is not null then
        insert into public.staff_leave_notification_outbox(
          event_key, request_id, recipient_id, event_type, channel, safe_payload, status
        ) values (
          'leave-over-limit:'||new.id::text||':'||v_recipient::text,
          new.id, v_recipient, 'over_limit', 'in_app',
          jsonb_build_object('event','leave_over_limit','request_id',new.id::text),
          'pending'
        ) on conflict (event_key) do nothing;
      end if;
    end loop;
  end if;
  return new;
end;
$$;

drop trigger if exists staff_leave_notify_over_limit
  on public.staff_leave_requests;
create trigger staff_leave_notify_over_limit
after update of status on public.staff_leave_requests
for each row execute function public.staff_leave_notify_over_limit();

revoke all on function public.staff_leave_notify_over_limit()
  from public, anon, authenticated;

commit;
