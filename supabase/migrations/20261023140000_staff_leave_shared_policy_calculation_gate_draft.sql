-- Draft-only shared-policy binding, day calculation, and submit gate.
-- One school-wide policy applies to all personnel; category is reporting metadata only.
-- No entitlement is seeded here. Without an approved rule and explicit calendar,
-- drafts remain drafts and cannot enter the approval workflow.
begin;

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

  -- Only a reviewed, approved school-wide policy can provide a calculation.
  -- Personnel category is deliberately not consulted.
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
      -- Unsupported or incomplete rule definitions never fall back to guesses.
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
    v_policy_snapshot := jsonb_build_object(
      'policy_code', 'school-wide',
      'policy_version_id', v_policy_id,
      'policy_version', v_policy_version,
      'leave_type_code', v_type_code,
      'verification_status', 'approved',
      'calculation_ready', true,
      'counting_basis', v_counting_basis,
      'calculated_day_count', v_day_count
    );
  else
    v_policy_snapshot := jsonb_build_object(
      'leave_type_code', v_type_code,
      'verification_status', 'pending',
      'calculation_ready', false
    );
  end if;

  insert into public.staff_leave_requests (
    applicant_id, leave_type_id, policy_version_id, starts_on, ends_on,
    day_count, reason, policy_snapshot, status
  ) values (
    v_actor, p_leave_type_id, v_policy_id, p_starts_on, p_ends_on,
    v_day_count, btrim(p_reason), v_policy_snapshot, 'draft'
  )
  returning id into v_request_id;

  return v_request_id;
end;
$$;

revoke all on function public.staff_leave_create_draft(uuid,date,date,text)
  from public, anon;
grant execute on function public.staff_leave_create_draft(uuid,date,date,text)
  to authenticated;

create or replace function public.staff_leave_require_verified_policy_before_submit()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_policy_rules jsonb;
  v_type_code text;
begin
  if old.status = 'draft' and new.status = 'pending_approval' then
    if new.policy_version_id is null or new.day_count is null or new.day_count <= 0 then
      raise exception 'leave_policy_not_verified_or_day_count_missing'
        using errcode = '55000';
    end if;

    select pv.policy_rules into v_policy_rules
    from public.staff_leave_policy_versions pv
    where pv.id = new.policy_version_id
      and pv.policy_code = 'school-wide'
      and pv.status = 'approved'
      and pv.policy_rules->>'verification_status' = 'approved'
      and pv.policy_rules->>'calculation_ready' = 'true';

    if not found
       or new.policy_snapshot->>'verification_status' <> 'approved'
       or new.policy_snapshot->>'calculation_ready' <> 'true'
       or new.policy_snapshot->>'policy_version_id' <> new.policy_version_id::text then
      raise exception 'leave_policy_not_verified_or_day_count_missing'
        using errcode = '55000';
    end if;

    select lt.code into v_type_code
    from public.staff_leave_types lt
    where lt.id = new.leave_type_id and lt.is_active = true;

    if v_type_code is null
       or jsonb_typeof(v_policy_rules->'leave_types'->v_type_code) <> 'object'
       or new.policy_snapshot->>'leave_type_code' <> v_type_code then
      raise exception 'leave_policy_rule_missing_for_type'
        using errcode = '55000';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists staff_leave_require_verified_policy_before_submit
  on public.staff_leave_requests;
create trigger staff_leave_require_verified_policy_before_submit
before update of status on public.staff_leave_requests
for each row execute function public.staff_leave_require_verified_policy_before_submit();

revoke all on function public.staff_leave_require_verified_policy_before_submit()
  from public, anon, authenticated;

commit;
