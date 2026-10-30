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
      'calculated_day_count', v_day_count,
      'policy_rules_snapshot', v_policy_rules
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
       or new.policy_snapshot->>'policy_version_id' <> new.policy_version_id::text
       or coalesce((new.policy_snapshot->>'calculated_day_count')::numeric,0) <> new.day_count then
      raise exception 'leave_policy_not_verified_or_day_count_missing'
        using errcode = '55000';
    end if;

    select lt.code into v_type_code
    from public.staff_leave_types lt
    where lt.id = new.leave_type_id and lt.is_active = true;

    if v_type_code is null
       or jsonb_typeof(v_policy_rules->'leave_types'->v_type_code) is distinct from 'object'
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


-- Import the recovered handbook rules as a school-wide draft policy.
-- This row is intentionally NOT approved: no working-day calculation may be
-- used until the school calendar, service history, leave subtypes, and
-- evidence-dependent rules have been implemented and verified.
insert into public.staff_leave_policy_versions (
  policy_code, version, status, policy_document_ref,
  policy_document_hash, policy_rules
) values (
  'school-wide',
  1,
  'draft',
  'private_library:คู่มือการลาของเจ้าหน้าที่-ศทก_page-0001(1).pdf',
  'fb5e8939663af60abcc18f1b1b0ba724b8c011061447eb7d5e9d2cf98a4cf1f7',
  $handbook_policy$
  {
    "source": {
      "title": "คู่มือการปฏิบัติงานเกี่ยวกับการลาประเภทต่าง ๆ ของข้าราชการ",
      "issuer": "ศูนย์เทคโนโลยีสารสนเทศและการสื่อสาร สำนักงานปลัดกระทรวงศึกษาธิการ",
      "page_count": 33,
      "rules_pages": "printed pages 1-11",
      "sha256": "fb5e8939663af60abcc18f1b1b0ba724b8c011061447eb7d5e9d2cf98a4cf1f7"
    },
    "scope": {
      "policy_code": "school-wide",
      "applies_to_all_school_personnel": true,
      "personnel_category_differentiation": false
    },
    "verification_status": "pending",
    "calculation_ready": false,
    "calendar": {
      "basis": "school_work_calendar",
      "weekend_days": [6, 7],
      "non_working_dates": [],
      "verified": false,
      "requires_school_calendar_review": true
    },
    "leave_types": {
      "sick_leave": {
        "counting_basis": "working_days",
        "max_days_per_year": 60,
        "exceptional_extension_max_days": 60,
        "certificate_from_day": 3,
        "mandatory_certificate_from_day": 30,
        "exceptional_extension_requires_higher_authority": true,
        "requires_annual_usage_accumulator": true
      },
      "maternity_leave": {
        "counting_basis": "calendar_days",
        "max_days_per_request": 90,
        "includes_holidays": true,
        "paid_days": 90,
        "medical_certificate_required": false
      },
      "assist_spouse_childbirth": {
        "counting_basis": "working_days",
        "max_days_per_event": 15,
        "allow_non_consecutive_periods": true,
        "use_within_calendar_days_after_childbirth": 90,
        "file_within_calendar_days_after_childbirth": 30,
        "requires_childbirth_event_date": true
      },
      "personal_leave": {
        "counting_basis": "working_days",
        "max_days_per_year": 45,
        "first_service_year_max_paid_days": 15,
        "requires_annual_usage_accumulator": true,
        "childcare_subtype": {
          "max_days_after_maternity": 150,
          "counting_basis": "working_days",
          "paid": false,
          "must_follow_maternity": true,
          "recall_for_official_necessity": false,
          "requires_subtype_field": true
        }
      },
      "annual_leave": {
        "counting_basis": "working_days",
        "days_per_fiscal_year": 10,
        "carryover_total_cap_days": 20,
        "carryover_total_cap_after_service_years": 10,
        "carryover_total_cap_after_10_service_years": 30,
        "first_year_minimum_service_months": 2,
        "requires_service_start_date": true,
        "requires_carryover_balance": true,
        "requires_fiscal_year_accumulator": true
      },
      "ordination_hajj": {
        "counting_basis": "calendar_days",
        "max_days_per_service_lifetime": 120,
        "paid_days": 120,
        "minimum_service_months": 12,
        "once_per_service_lifetime": true,
        "minimum_notice_days": 20,
        "complete_ordination_or_departure_within_days": 10,
        "return_report_within_days": 5,
        "requires_prior_use_history": true
      },
      "military_selection_training": {
        "counting_basis": "calendar_days",
        "paid": true,
        "notify_supervisor_within_hours": 48,
        "return_report_within_days": 7,
        "maximum_return_extension_days": 15,
        "requires_official_summons": true
      },
      "study_training_research": {
        "counting_basis": "calendar_days",
        "must_pass_probation": true,
        "minimum_service_years": 1,
        "max_paid_years": 4,
        "max_total_years_with_extension": 5,
        "course_duration_years": {
          "below_bachelor": "course_duration",
          "master": 2,
          "doctorate": 4
        },
        "max_extension_semesters": 2,
        "max_extension_academic_years": 1,
        "service_return_multiplier": 1,
        "requires_service_agreement": true,
        "requires_course_evidence": true
      },
      "international_organization": {
        "counting_basis": "calendar_days",
        "type_1_max_years": 5,
        "type_2_max_years": 1,
        "paid": false,
        "salary_top_up_if_external_salary_is_lower": true,
        "service_return_multiplier": 1,
        "minimum_prior_service_years": 5,
        "un_minimum_prior_service_years": 2,
        "repeat_type_2_minimum_service_years": 2,
        "repeat_type_2_max_age": 52,
        "requires_organization_type": true,
        "requires_service_agreement": true
      },
      "spouse_following": {
        "counting_basis": "calendar_days",
        "initial_max_years": 2,
        "extension_max_years": 2,
        "absolute_max_years": 5,
        "paid": false,
        "requires_spouse_assignment_evidence": true
      },
      "vocational_rehabilitation": {
        "counting_basis": "calendar_days",
        "max_months": 12,
        "requires_qualifying_injury_or_disability": true,
        "requires_recognized_course": true,
        "requires_evidence": true
      }
    },
    "implementation_gaps": [
      "verified school/public holiday calendar",
      "per-year usage accumulators for sick and personal leave",
      "annual leave service-start date and carry-over balance",
      "personal leave childcare subtype and maternity linkage",
      "childbirth event date and prior use checks",
      "ordination/Hajj once-per-service history",
      "military summons and return evidence",
      "study eligibility, course duration, and service agreement",
      "international organization category, age, and service history",
      "spouse-following evidence and cumulative duration",
      "vocational rehabilitation eligibility and course evidence"
    ]
  }
  $handbook_policy$::jsonb
)
on conflict (policy_code, version) do nothing;


-- Prevent a handbook policy from being activated while any required control
-- (school calendar, annual balance, eligibility evidence, or special subtype)
-- remains unresolved. This is a database-level fail-closed guard.
create or replace function public.staff_leave_policy_review_guard()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $
begin
  if new.status = 'approved' then
    if new.policy_rules->>'verification_status' is distinct from 'approved'
       or new.policy_rules->>'calculation_ready' is distinct from 'true'
       or coalesce((new.policy_rules->'calendar'->>'verified')::boolean, false) is not true
       or (
         jsonb_typeof(new.policy_rules->'implementation_gaps') = 'array'
         and jsonb_array_length(new.policy_rules->'implementation_gaps') > 0
       ) then
      raise exception 'staff_leave_policy_has_unresolved_implementation_gaps'
        using errcode = '55000';
    end if;
  end if;
  return new;
end;
$;

drop trigger if exists staff_leave_policy_review_guard
  on public.staff_leave_policy_versions;
create trigger staff_leave_policy_review_guard
before insert or update of status, policy_rules
on public.staff_leave_policy_versions
for each row execute function public.staff_leave_policy_review_guard();

revoke all on function public.staff_leave_policy_review_guard()
  from public, anon, authenticated;

commit;
