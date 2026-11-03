-- School-confirmed leave-system scope: no annual/vacation leave workflow.
-- Keep the legacy catalog code for referential/history compatibility, but make it unavailable.
-- This does NOT waive any mandatory employment-law entitlement outside this school workflow.
begin;

update public.staff_leave_types
   set is_active = false,
       description = 'ไม่เปิดใช้ในระบบลาของโรงเรียนตามนโยบายที่โรงเรียนยืนยัน; ไม่สร้างยอดคงเหลือหรือยอดสะสม',
       updated_at = statement_timestamp()
 where code = 'annual_leave';

update public.staff_leave_policy_versions
   set policy_rules = jsonb_set(
     jsonb_set(
       policy_rules,
       '{leave_types,annual_leave}',
       '{"enabled":false,"availability":"not_applicable","counting_basis":null,"quota":null,"carryover":false,"reason":"school_confirmed_no_vacation_leave_workflow"}'::jsonb,
       true
     ),
     '{scope,annual_leave}',
     '"excluded_by_school_policy"'::jsonb,
     true
   ),
   updated_at = statement_timestamp()
 where policy_code = 'school-wide'
   and status in ('draft','review');

-- Remove the obsolete annual-leave balance/carry-over gap: it is not part of
-- this school's leave workflow. All other unresolved gaps remain fail-closed.
update public.staff_leave_policy_versions p
   set policy_rules = jsonb_set(
     p.policy_rules,
     '{implementation_gaps}',
     coalesce((
       select jsonb_agg(to_jsonb(gap.value) order by gap.ordinality)
       from jsonb_array_elements_text(p.policy_rules->'implementation_gaps')
            with ordinality as gap(value, ordinality)
       where gap.value <> 'annual leave service-start date and carry-over balance'
     ), '[]'::jsonb),
   true),
   updated_at = statement_timestamp()
 where p.policy_code='school-wide'
   and p.status in ('draft','review')
   and jsonb_typeof(p.policy_rules->'implementation_gaps')='array';

commit;
