do $$
declare
  v_count integer;
begin
  update public.staff_leave_policy_versions
  set policy_rules =
    jsonb_set(
      policy_rules,
      '{leave_types,assist_spouse_childbirth}',
      ((policy_rules #> '{leave_types,assist_spouse_childbirth}') - 'use_within_calendar_days_after_childbirth') ||
      jsonb_build_object(
        'filing_deadline_calendar_days_after_childbirth', 90,
        'filing_may_be_before_or_on_leave_start', true,
        'allow_non_consecutive_periods', false,
        'one_continuous_period_required', true,
        'max_working_days_per_event', 15,
        'deadline_source_note', 'School-provided authoritative excerpt confirmed: submit before or on the leave date, no later than 90 days from childbirth. One continuous period, maximum 15 working days.'
      ),
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
  v_rules jsonb;
begin
  select policy_rules into v_rules
  from public.staff_leave_policy_versions
  where policy_code = 'school-wide' and version = 1 and status = 'draft';
  if (v_rules #>> '{leave_types,assist_spouse_childbirth,filing_deadline_calendar_days_after_childbirth}')::integer <> 90
     or (v_rules #>> '{leave_types,assist_spouse_childbirth,max_working_days_per_event}')::integer <> 15
     or (v_rules #>> '{leave_types,assist_spouse_childbirth,one_continuous_period_required}')::boolean is distinct from true
     or (v_rules #> '{leave_types,assist_spouse_childbirth,use_within_calendar_days_after_childbirth}') is not null then
    raise exception 'Spouse childbirth leave policy verification failed';
  end if;
end $$;