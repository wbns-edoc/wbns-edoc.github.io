-- Keep unresolved childbirth-assistance filing/use deadlines unset.
-- The handbook text conflicts (60-day and 30-day clauses); the school has
-- confirmed only 15 consecutive working days per childbirth event.
-- Never turn either conflicting number into an automatic validation rule.
begin;

update public.staff_leave_policy_versions
   set policy_rules =
       jsonb_set(
         policy_rules #- '{leave_types,assist_spouse_childbirth,use_within_calendar_days_after_childbirth}'
                      #- '{leave_types,assist_spouse_childbirth,file_within_calendar_days_after_childbirth}',
         '{leave_types,assist_spouse_childbirth,deadline_source_note}',
         to_jsonb('Filing/use deadline is unresolved because the source contains conflicting 60-day and 30-day clauses. School confirmation covers only the maximum 15 consecutive working days per childbirth event and prohibits splitting. Do not enforce a deadline until the school authority records an approved rule.'::text),
         true
       )
 where policy_code = 'school-wide'
   and status in ('draft','review')
   and policy_rules ? 'leave_types'
   and policy_rules->'leave_types' ? 'assist_spouse_childbirth';

commit;
