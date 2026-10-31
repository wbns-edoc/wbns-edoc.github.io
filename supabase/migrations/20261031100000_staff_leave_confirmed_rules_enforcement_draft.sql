-- Draft-only enforcement for the three school-confirmed staff-leave rules.
-- Production must remain untouched until isolated PostgreSQL replay and CI pass.
begin;

alter table public.staff_leave_requests
  add column if not exists childbirth_event_date date;

alter table public.staff_leave_attachments
  add column if not exists attachment_kind text not null default 'supporting_document';

alter table public.staff_leave_attachments
  drop constraint if exists staff_leave_attachments_kind_chk;
alter table public.staff_leave_attachments
  add constraint staff_leave_attachments_kind_chk
  check (attachment_kind in ('supporting_document','medical_certificate','childbirth_evidence'));

-- A single active request reserves one childbirth event for one applicant.
-- Rejected/cancelled/withdrawn requests release the reservation; approved and
-- in-flight requests continue to reserve it. This also blocks duplicate drafts.
create unique index if not exists staff_leave_one_request_per_childbirth_event
  on public.staff_leave_requests(applicant_id, childbirth_event_date)
  where childbirth_event_date is not null
    and status not in ('rejected','cancelled','withdrawn');

create index if not exists staff_leave_medical_certificate_lookup
  on public.staff_leave_attachments(request_id, attachment_kind);

-- Preserve the four-argument RPC for existing callers, while adding an explicit
-- event-date parameter for spouse-childbirth leave. The browser is updated below.
create or replace function public.staff_leave_create_draft(
  p_leave_type_id uuid,
  p_starts_on date,
  p_ends_on date,
  p_reason text,
  p_childbirth_event_date date
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
  if v_actor is null then raise exception 'authentication_required' using errcode='28000'; end if;
  if not exists(select 1 from public.profiles p where p.id=v_actor and p.is_active=true) then
    raise exception 'active_profile_required' using errcode='42501';
  end if;
  if p_starts_on is null or p_ends_on is null or p_ends_on < p_starts_on then
    raise exception 'invalid_leave_date_range' using errcode='22023';
  end if;
  if p_reason is null or length(btrim(p_reason))=0 or length(p_reason)>4000 then
    raise exception 'invalid_leave_reason' using errcode='22023';
  end if;

  select lt.code into v_type_code from public.staff_leave_types lt
  where lt.id=p_leave_type_id and lt.is_active=true;
  if v_type_code is null then raise exception 'active_leave_type_required' using errcode='22023'; end if;

  if v_type_code='assist_spouse_childbirth' then
    if p_childbirth_event_date is null then
      raise exception 'childbirth_event_date_required' using errcode='22023';
    end if;
    if p_childbirth_event_date > p_starts_on then
      raise exception 'childbirth_event_must_not_follow_leave_start' using errcode='22023';
    end if;
  elsif p_childbirth_event_date is not null then
    raise exception 'childbirth_event_date_only_for_spouse_childbirth_leave' using errcode='22023';
  end if;

  select pv.id,pv.version,pv.policy_rules,
         pv.policy_rules->'leave_types'->v_type_code
    into v_policy_id,v_policy_version,v_policy_rules,v_type_rules
  from public.staff_leave_policy_versions pv
  where pv.policy_code='school-wide' and pv.status='approved'
    and pv.policy_rules->>'verification_status'='approved'
    and pv.policy_rules->>'calculation_ready'='true'
    and (pv.effective_from is null or pv.effective_from<=p_starts_on)
    and (pv.effective_until is null or pv.effective_until>=p_ends_on)
    and jsonb_typeof(pv.policy_rules->'leave_types'->v_type_code)='object'
  order by pv.version desc limit 1;

  if v_policy_id is not null then
    v_counting_basis:=v_type_rules->>'counting_basis';
    if v_counting_basis='calendar_days' then
      v_day_count:=(p_ends_on-p_starts_on+1)::numeric;
    elsif v_counting_basis='working_days'
      and coalesce((v_policy_rules->'calendar'->>'verified')::boolean,false)
      and jsonb_typeof(v_policy_rules->'calendar'->'weekend_days')='array'
      and jsonb_typeof(v_policy_rules->'calendar'->'non_working_dates')='array' then
      select count(*)::numeric into v_day_count
      from generate_series(p_starts_on,p_ends_on,interval '1 day') d
      where not exists (
        select 1 from jsonb_array_elements_text(v_policy_rules->'calendar'->'weekend_days') w(value)
        where w.value::integer=extract(isodow from d)::integer
      ) and not exists (
        select 1 from jsonb_array_elements_text(v_policy_rules->'calendar'->'non_working_dates') h(value)
        where h.value::date=d::date
      );
    else
      v_policy_id:=null; v_policy_version:=null; v_policy_rules:=null;
      v_type_rules:=null; v_day_count:=null;
    end if;
  end if;

  if v_policy_id is not null and (v_day_count is null or v_day_count<=0) then
    v_policy_id:=null; v_policy_version:=null; v_policy_rules:=null;
    v_type_rules:=null; v_day_count:=null;
  end if;

  if v_policy_id is not null then
    v_policy_snapshot:=jsonb_build_object(
      'policy_code','school-wide','policy_version_id',v_policy_id,
      'policy_version',v_policy_version,'leave_type_code',v_type_code,
      'verification_status','approved','calculation_ready',true,
      'counting_basis',v_counting_basis,'calculated_day_count',v_day_count,
      'policy_rules_snapshot',v_policy_rules
    );
  else
    v_policy_snapshot:=jsonb_build_object(
      'leave_type_code',v_type_code,'verification_status','pending',
      'calculation_ready',false
    );
  end if;

  insert into public.staff_leave_requests(
    applicant_id,leave_type_id,policy_version_id,starts_on,ends_on,
    day_count,reason,policy_snapshot,status,childbirth_event_date
  ) values (
    v_actor,p_leave_type_id,v_policy_id,p_starts_on,p_ends_on,
    v_day_count,btrim(p_reason),v_policy_snapshot,'draft',p_childbirth_event_date
  ) returning id into v_request_id;
  return v_request_id;
exception
  when unique_violation then
    if v_type_code='assist_spouse_childbirth' then
      raise exception 'childbirth_event_entitlement_already_claimed' using errcode='23505';
    end if;
    raise;
end;
$$;

-- Four-argument compatibility wrapper. Spouse-childbirth requests must use the
-- five-argument form so the event identity cannot be omitted.
create or replace function public.staff_leave_create_draft(
  p_leave_type_id uuid,p_starts_on date,p_ends_on date,p_reason text
)
returns uuid language sql security definer
set search_path=pg_catalog,public
as $$
  select public.staff_leave_create_draft(
    p_leave_type_id,p_starts_on,p_ends_on,p_reason,null::date
  );
$$;

revoke all on function public.staff_leave_create_draft(uuid,date,date,text,date) from public,anon;
revoke all on function public.staff_leave_create_draft(uuid,date,date,text) from public,anon;
grant execute on function public.staff_leave_create_draft(uuid,date,date,text,date) to authenticated;
grant execute on function public.staff_leave_create_draft(uuid,date,date,text) to authenticated;

create or replace function public.staff_leave_enforce_confirmed_rules()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,public
as $$
declare
  v_code text;
  v_rules jsonb;
begin
  if new.status in ('draft','rejected','cancelled','withdrawn') then
    return new;
  end if;

  select lt.code into v_code from public.staff_leave_types lt
  where lt.id=new.leave_type_id;
  if v_code is null then raise exception 'leave_type_missing' using errcode='55000'; end if;

  if v_code='sick_leave' then
    if new.day_count is null then
      raise exception 'leave_policy_not_verified_or_day_count_missing' using errcode='55000';
    end if;
    select pv.policy_rules into v_rules
    from public.staff_leave_policy_versions pv
    where pv.id=new.policy_version_id and pv.policy_code='school-wide'
      and pv.status='approved';
    -- The threshold is school-confirmed and fixed here; policy JSON cannot weaken it.
    if new.day_count>=3 and not exists(
      select 1 from public.staff_leave_attachments a
      where a.request_id=new.id and a.attachment_kind='medical_certificate'
        and a.size_bytes>0 and nullif(btrim(a.storage_object_key),'') is not null
    ) then
      raise exception 'medical_certificate_required_for_sick_leave' using errcode='23514';
    end if;
  end if;

  if v_code='assist_spouse_childbirth' then
    if new.childbirth_event_date is null then
      raise exception 'childbirth_event_date_required' using errcode='23514';
    end if;
    if new.childbirth_event_date>new.starts_on then
      raise exception 'childbirth_event_must_not_follow_leave_start' using errcode='23514';
    end if;
    if new.policy_version_id is null or new.day_count is null then
      raise exception 'leave_policy_not_verified_or_day_count_missing' using errcode='55000';
    end if;
    select pv.policy_rules into v_rules
    from public.staff_leave_policy_versions pv
    where pv.id=new.policy_version_id and pv.policy_code='school-wide'
      and pv.status='approved';
    if v_rules->'leave_types'->'assist_spouse_childbirth'->>'one_continuous_period_required' is distinct from 'true'
       or v_rules->'leave_types'->'assist_spouse_childbirth'->>'one_entitlement_per_childbirth_event' is distinct from 'true'
       or v_rules->'leave_types'->'assist_spouse_childbirth'->>'counting_basis' is distinct from 'working_days'
       or new.day_count>15 then
      raise exception 'childbirth_leave_rule_violation' using errcode='23514';
    end if;
    if exists(
      select 1 from public.staff_leave_requests r
      where r.applicant_id=new.applicant_id
        and r.childbirth_event_date=new.childbirth_event_date
        and r.id<>new.id
        and r.status not in ('rejected','cancelled','withdrawn')
    ) then
      raise exception 'childbirth_event_entitlement_already_claimed' using errcode='23505';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists staff_leave_enforce_confirmed_rules on public.staff_leave_requests;
create trigger staff_leave_enforce_confirmed_rules
before insert or update of status,leave_type_id,starts_on,ends_on,day_count,
  policy_version_id,childbirth_event_date
on public.staff_leave_requests
for each row execute function public.staff_leave_enforce_confirmed_rules();

revoke all on function public.staff_leave_enforce_confirmed_rules() from public,anon,authenticated;

commit;
