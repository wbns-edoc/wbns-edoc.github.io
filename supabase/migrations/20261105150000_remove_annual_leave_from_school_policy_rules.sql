-- Keep the legacy annual_leave catalog key inactive for history compatibility,
-- but remove annual/vacation leave from the school-wide policy rule set entirely.
-- No entitlement, balance, carry-over, or policy gap is calculated for this workflow.
begin;

update public.staff_leave_types
   set is_active = false,
       updated_at = statement_timestamp()
 where code = 'annual_leave'
   and is_active is distinct from false;

update public.staff_leave_policy_versions p
   set policy_rules =
     jsonb_set(
       p.policy_rules #- '{leave_types,annual_leave}',
       '{implementation_gaps}',
       coalesce((
         select jsonb_agg(to_jsonb(g.value) order by g.ordinality)
         from jsonb_array_elements_text(
           case
             when jsonb_typeof(p.policy_rules->'implementation_gaps') = 'array'
               then p.policy_rules->'implementation_gaps'
             else '[]'::jsonb
           end
         ) with ordinality as g(value, ordinality)
         where g.value not ilike '%annual leave%'
       ), '[]'::jsonb),
       true
     )
 where p.policy_code = 'school-wide'
   and p.status in ('draft','review')
   and (
     p.policy_rules #> '{leave_types,annual_leave}' is not null
     or exists (
       select 1
       from jsonb_array_elements_text(
         case
           when jsonb_typeof(p.policy_rules->'implementation_gaps') = 'array'
             then p.policy_rules->'implementation_gaps'
           else '[]'::jsonb
         end
       ) g(value)
       where g.value ilike '%annual leave%'
     )
   );

commit;
