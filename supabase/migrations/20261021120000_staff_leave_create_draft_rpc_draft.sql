-- Draft-only RPC: create a leave draft using the authenticated actor.
-- Do not apply to Production until the complete workflow and release gates are approved.
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

  if p_leave_type_id is null
     or not exists (
       select 1 from public.staff_leave_types lt
       where lt.id = p_leave_type_id and lt.is_active = true
     ) then
    raise exception 'active_leave_type_required' using errcode = '22023';
  end if;

  if p_starts_on is null or p_ends_on is null or p_ends_on < p_starts_on then
    raise exception 'invalid_leave_date_range' using errcode = '22023';
  end if;

  if p_reason is null or length(btrim(p_reason)) = 0 or length(p_reason) > 4000 then
    raise exception 'invalid_leave_reason' using errcode = '22023';
  end if;

  insert into public.staff_leave_requests (
    applicant_id, leave_type_id, starts_on, ends_on, reason, status
  ) values (
    v_actor, p_leave_type_id, p_starts_on, p_ends_on, btrim(p_reason), 'draft'
  )
  returning id into v_request_id;

  return v_request_id;
end;
$$;

revoke all on function public.staff_leave_create_draft(uuid, date, date, text) from public, anon;
grant execute on function public.staff_leave_create_draft(uuid, date, date, text) to authenticated;

commit;
