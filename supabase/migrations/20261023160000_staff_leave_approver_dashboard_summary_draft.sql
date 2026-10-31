-- Draft-only aggregate dashboard for Director, Vice Director, and System Admin.
-- Returns counts only; it does not bypass request-level RLS or expose employee details.
begin;

create or replace function public.staff_leave_dashboard_summary()
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_actor uuid;
  v_summary jsonb;
begin
  v_actor := auth.uid();
  if v_actor is null then
    raise exception 'authentication_required' using errcode = '28000';
  end if;
  if not exists (
    select 1 from public.profiles p where p.id=v_actor and p.is_active=true
  ) then
    raise exception 'active_profile_required' using errcode = '42501';
  end if;
  if not exists (
    select 1
    from public.user_roles ur
    join public.roles r on r.id=ur.role_id
    where ur.user_id=v_actor
      and r.code in ('director','deputy_director','system_admin')
  ) then
    raise exception 'leave_dashboard_role_required' using errcode = '42501';
  end if;

  select jsonb_build_object(
    'total', count(*)::integer,
    'draft', count(*) filter (where status='draft')::integer,
    'pending', count(*) filter (where status='pending_approval')::integer,
    'approved', count(*) filter (where status='approved')::integer,
    'rejected', count(*) filter (where status='rejected')::integer,
    'cancelled', count(*) filter (where status='cancelled')::integer,
    'over_limit', count(*) filter (where is_over_limit=true)::integer,
    'waiting_vice', count(*) filter (where status='pending_approval' and approval_stage='vice_director_review')::integer,
    'waiting_director', count(*) filter (where status='pending_approval' and approval_stage='director_final_review')::integer
  ) into v_summary
  from public.staff_leave_requests;

  return coalesce(v_summary,'{}'::jsonb);
end;
$$;

revoke all on function public.staff_leave_dashboard_summary() from public, anon;
grant execute on function public.staff_leave_dashboard_summary() to authenticated;

commit;
