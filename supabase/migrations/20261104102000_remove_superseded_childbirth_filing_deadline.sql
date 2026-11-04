do $$
declare
  v_count integer;
begin
  update public.staff_leave_policy_versions
  set policy_rules = jsonb_set(
    policy_rules,
    '{leave_types,assist_spouse_childbirth}',
    (policy_rules #> '{leave_types,assist_spouse_childbirth}') - 'file_within_calendar_days_after_childbirth',
    true
  )
  where policy_code = 'school-wide'
    and version = 1
    and status = 'draft';
  get diagnostics v_count = row_count;
  if v_count <> 1 then
    raise exception 'Expected exactly one draft school-wide policy v1; updated % rows', v_count;
  end if;
end $$;

do $$
declare
  v_rule jsonb;
begin
  select policy_rules #> '{leave_types,assist_spouse_childbirth}' into v_rule
  from public.staff_leave_policy_versions
  where policy_code = 'school-wide' and version = 1 and status = 'draft';
  if (v_rule ->> 'filing_deadline_calendar_days_after_childbirth')::integer <> 90
     or v_rule ? 'file_within_calendar_days_after_childbirth'
     or v_rule ? 'use_within_calendar_days_after_childbirth' then
    raise exception 'Superseded childbirth filing deadline remains in policy';
  end if;
end $$;