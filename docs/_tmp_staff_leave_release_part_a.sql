-- Draft-only additive schema for the Wat Bueng Nam Sai School staff leave workflow.
-- Do not apply to Production. RPCs, grants, isolated migration replay, and RLS tests
-- must be implemented and reviewed before this migration can be considered release-ready.
-- Leave policy versions are school-wide: personnel category is NOT an entitlement key.
-- Fail fast on an incomplete recovered core schema; never mutate public.profiles here.
do $preflight$
declare
  v_profiles_oid oid;
  v_type text;
begin
  v_profiles_oid := pg_catalog.to_regclass('public.profiles');
  if v_profiles_oid is null then
    raise exception 'staff_leave_schema_preflight_failed: public.profiles table is missing; reconcile the isolated core schema with the verified Production catalog before retrying';
  end if;
  select format_type(a.atttypid, a.atttypmod) into v_type
  from pg_catalog.pg_attribute a
  where a.attrelid=v_profiles_oid and a.attname='is_active'
    and a.attnum>0 and not a.attisdropped;
  if v_type is null then
    raise exception 'staff_leave_schema_preflight_failed: public.profiles.is_active is missing; reconcile the isolated core schema with the verified Production catalog before retrying';
  end if;
  if v_type <> 'boolean' then
    raise exception 'staff_leave_schema_preflight_failed: public.profiles.is_active must be boolean (found %); no core schema changes were made',v_type;
  end if;
end;
$preflight$;

create table if not exists public.staff_leave_types (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  description text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);


-- Seed the eleven leave categories from the school's supplied handbook contents.
-- This seeds labels only; it does not invent entitlements, limits, or day-count rules.
insert into public.staff_leave_types(code, name, description)
values
 ('sick_leave', 'การลาป่วย', 'ประเภทการลาตามสารบัญคู่มือ; สิทธิและวิธีนับวันรอตรวจสอบนโยบาย'),
 ('maternity_leave', 'การลาคลอดบุตร', 'ประเภทการลาตามสารบัญคู่มือ; สิทธิและวิธีนับวันรอตรวจสอบนโยบาย'),
 ('assist_spouse_childbirth', 'การลาไปช่วยเหลือภริยาที่คลอดบุตร', 'ประเภทการลาตามสารบัญคู่มือ; สิทธิและวิธีนับวันรอตรวจสอบนโยบาย'),
 ('personal_leave', 'การลากิจส่วนตัว', 'ประเภทการลาตามสารบัญคู่มือ; สิทธิและวิธีนับวันรอตรวจสอบนโยบาย'),
 ('annual_leave', 'การลาพักผ่อน', 'ประเภทการลาตามสารบัญคู่มือ; สิทธิและวิธีนับวันรอตรวจสอบนโยบาย'),
 ('ordination_hajj', 'การลาอุปสมบทหรือการลาไปประกอบพิธีฮัจย์', 'ประเภทการลาตามสารบัญคู่มือ; สิทธิและวิธีนับวันรอตรวจสอบนโยบาย'),
 ('military_selection_training', 'การลาเข้ารับการตรวจเลือกหรือเข้ารับการเตรียมพล', 'ประเภทการลาตามสารบัญคู่มือ; สิทธิและวิธีนับวันรอตรวจสอบนโยบาย'),
 ('study_training_research', 'การลาไปศึกษา ฝึกอบรม ปฏิบัติการวิจัย หรือดูงาน', 'ประเภทการลาตามสารบัญคู่มือ; สิทธิและวิธีนับวันรอตรวจสอบนโยบาย'),
 ('international_organization', 'การลาไปปฏิบัติงานในองค์การระหว่างประเทศ', 'ประเภทการลาตามสารบัญคู่มือ; สิทธิและวิธีนับวันรอตรวจสอบนโยบาย'),
 ('spouse_following', 'การลาติดตามคู่สมรส', 'ประเภทการลาตามสารบัญคู่มือ; สิทธิและวิธีนับวันรอตรวจสอบนโยบาย'),
 ('vocational_rehabilitation', 'การลาไปฟื้นฟูสมรรถภาพด้านอาชีพ', 'ประเภทการลาตามสารบัญคู่มือ; สิทธิและวิธีนับวันรอตรวจสอบนโยบาย')
on conflict (code) do update
set name=excluded.name,
    description=excluded.description,
    updated_at=statement_timestamp();

create table if not exists public.staff_leave_policy_versions (
  id uuid primary key default gen_random_uuid(),
  policy_code text not null,
  version integer not null check (version > 0),
  status text not null default 'draft'
    check (status in ('draft', 'review', 'approved', 'retired')),
  effective_from date,
  effective_until date,
  policy_document_ref text,
  policy_document_hash text,
  policy_rules jsonb not null default '{}'::jsonb,
  reviewed_by uuid references public.profiles(id),
  reviewed_at timestamptz,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  constraint staff_leave_policy_version_unique unique (policy_code, version),
  constraint staff_leave_policy_dates_chk
    check (effective_until is null or effective_from is null or effective_until >= effective_from),
  constraint staff_leave_policy_review_chk
    check (status <> 'approved' or (reviewed_by is not null and reviewed_at is not null))
);

create table if not exists public.staff_leave_requests (
  id uuid primary key default gen_random_uuid(),
  applicant_id uuid not null references public.profiles(id),
  personnel_category_snapshot text,
  leave_type_id uuid not null references public.staff_leave_types(id),
  policy_version_id uuid references public.staff_leave_policy_versions(id),
  starts_on date not null,
  ends_on date not null,
  day_count numeric(7,2),
  reason text not null,
  status text not null default 'draft'
    check (status in ('draft','submitted','blocked_approver_resolution','pending_approval','approved','rejected','cancelled','withdrawn')),
  current_approver_user_id uuid references public.profiles(id),
  policy_snapshot jsonb not null default '{}'::jsonb,
  submitted_at timestamptz,
  decided_at timestamptz,
  cancellation_reason text,
  cancelled_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint staff_leave_request_dates_chk check (ends_on >= starts_on),
  constraint staff_leave_request_day_count_chk check (day_count is null or day_count > 0),
  constraint staff_leave_cancel_fields_chk
    check (status <> 'cancelled' or (cancelled_at is not null and nullif(btrim(cancellation_reason), '') is not null))
);

create index if not exists staff_leave_requests_applicant_created_idx
  on public.staff_leave_requests(applicant_id, created_at desc);
create index if not exists staff_leave_requests_approver_status_idx
  on public.staff_leave_requests(current_approver_user_id, status, created_at desc);
create index if not exists staff_leave_requests_dates_idx
  on public.staff_leave_requests(starts_on, ends_on);

create table if not exists public.staff_leave_approval_actions (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references public.staff_leave_requests(id) on delete restrict,
  actor_id uuid not null references public.profiles(id),
  action text not null check (action in (
    'submitted','routed','blocked','approved','rejected','returned',
    'cancellation_requested','cancelled','withdrawn','overdue_notified'
  )),
  reason text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists staff_leave_actions_request_time_idx
  on public.staff_leave_approval_actions(request_id, created_at);

-- Approval history is append-only even for privileged database roles. Workflow RPCs
-- may INSERT events, but no actor may UPDATE, DELETE, or TRUNCATE recorded history.
create or replace function public.staff_leave_approval_actions_reject_mutation()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
begin
  raise exception 'staff_leave_approval_actions is append-only'
    using errcode = '55000';
end;
$$;

drop trigger if exists staff_leave_approval_actions_reject_row_mutation
  on public.staff_leave_approval_actions;
create trigger staff_leave_approval_actions_reject_row_mutation
  before update or delete on public.staff_leave_approval_actions
  for each row execute function public.staff_leave_approval_actions_reject_mutation();

drop trigger if exists staff_leave_approval_actions_reject_truncate
  on public.staff_leave_approval_actions;
create trigger staff_leave_approval_actions_reject_truncate
  before truncate on public.staff_leave_approval_actions
  for each statement execute function public.staff_leave_approval_actions_reject_mutation();

create table if not exists public.staff_leave_attachments (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references public.staff_leave_requests(id) on delete restrict,
  uploaded_by uuid not null references public.profiles(id),
  storage_object_key text not null unique,
  original_filename text not null,
  mime_type text,
  size_bytes bigint not null check (size_bytes > 0),
  created_at timestamptz not null default now()
);
create index if not exists staff_leave_attachments_request_idx
  on public.staff_leave_attachments(request_id);

create table if not exists public.staff_leave_notification_outbox (
  id uuid primary key default gen_random_uuid(),
  event_key text not null unique,
  request_id uuid not null references public.staff_leave_requests(id) on delete restrict,
  recipient_id uuid not null references public.profiles(id),
  event_type text not null check (event_type in (
    'submitted','approver_assigned','approved','rejected','cancelled','blocked','overdue'
  )),
  channel text not null default 'in_app' check (channel in ('in_app','email','push')),
  safe_payload jsonb not null default '{}'::jsonb,
  status text not null default 'pending' check (status in ('pending','processing','sent','retry','dead_letter')),
  attempts integer not null default 0 check (attempts >= 0),
  available_at timestamptz not null default now(),
  sent_at timestamptz,
  last_error_code text,
  created_at timestamptz not null default now()
);
create index if not exists staff_leave_outbox_delivery_idx
  on public.staff_leave_notification_outbox(status, available_at)
  where status in ('pending','retry');

-- RLS is enabled on every new table. No client-side write policies are created.
-- Writes must later be exposed only through narrow, reviewed RPCs with authorization checks.
alter table public.staff_leave_types enable row level security;
alter table public.staff_leave_policy_versions enable row level security;
alter table public.staff_leave_requests enable row level security;
alter table public.staff_leave_approval_actions enable row level security;
alter table public.staff_leave_attachments enable row level security;
alter table public.staff_leave_notification_outbox enable row level security;

drop policy if exists staff_leave_types_select_active on public.staff_leave_types;
create policy staff_leave_types_select_active
  on public.staff_leave_types for select to authenticated
  using (
    is_active = true
    and exists (
      select 1 from public.profiles p
      where p.id = (select auth.uid()) and p.is_active = true
    )
  );

drop policy if exists staff_leave_policy_select_approved on public.staff_leave_policy_versions;
create policy staff_leave_policy_select_approved
  on public.staff_leave_policy_versions for select to authenticated
  using (
    status = 'approved'
    and exists (
      select 1 from public.profiles p
      where p.id = (select auth.uid()) and p.is_active = true
    )
  );

drop policy if exists staff_leave_requests_select_applicant_or_assignee on public.staff_leave_requests;
create policy staff_leave_requests_select_applicant_or_assignee
  on public.staff_leave_requests for select to authenticated
  using (
    exists (
      select 1 from public.profiles actor
      where actor.id = (select auth.uid()) and actor.is_active = true
    )
    and (
      applicant_id = (select auth.uid())
      or current_approver_user_id = (select auth.uid())
    )
  );

drop policy if exists staff_leave_actions_select_request_parties on public.staff_leave_approval_actions;
create policy staff_leave_actions_select_request_parties
  on public.staff_leave_approval_actions for select to authenticated
  using (
    exists (
      select 1 from public.staff_leave_requests lr
      where lr.id = request_id
        and exists (
          select 1 from public.profiles actor
          where actor.id = (select auth.uid()) and actor.is_active = true
        )
        and (
          lr.applicant_id = (select auth.uid())
          or lr.current_approver_user_id = (select auth.uid())
        )
    )
  );

drop policy if exists staff_leave_attachments_select_request_parties on public.staff_leave_attachments;
create policy staff_leave_attachments_select_request_parties
  on public.staff_leave_attachments for select to authenticated
  using (
    exists (
      select 1 from public.staff_leave_requests lr
      where lr.id = request_id
        and exists (
          select 1 from public.profiles actor
          where actor.id = (select auth.uid()) and actor.is_active = true
        )
        and (
          lr.applicant_id = (select auth.uid())
          or lr.current_approver_user_id = (select auth.uid())
        )
    )
  );

-- Reset table ACLs for these new tables, including inherited grants to PUBLIC.
-- Only authenticated read access is granted below; workflow writes must use reviewed RPCs.
revoke all privileges on table
  public.staff_leave_types,
  public.staff_leave_policy_versions,
  public.staff_leave_requests,
  public.staff_leave_approval_actions,
  public.staff_leave_attachments,
  public.staff_leave_notification_outbox
  from public, anon, authenticated;
grant select on public.staff_leave_types,
  public.staff_leave_policy_versions,
  public.staff_leave_requests,
  public.staff_leave_approval_actions,
  public.staff_leave_attachments
  to authenticated;

-- Outbox intentionally has no authenticated SELECT policy: delivery state/payloads
-- are backend internals and must not be exposed to browser clients.


-- Draft-only RPC: create a leave draft using the authenticated actor.
-- Do not apply to Production until the complete workflow and release gates are approved.

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


-- Draft-only RPC: cancel an applicant's own leave request.
-- Late cancellation exceptions are deliberately not enabled until authorized-role
-- configuration and an audited exception workflow are implemented and verified.
-- Do not apply to Production.

create or replace function public.staff_leave_cancel(
  p_request_id uuid,
  p_reason text,
  p_idempotency_key text
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_actor uuid;
  v_request public.staff_leave_requests%rowtype;
  v_event_key text;
  v_today_bangkok date;
  v_prior_reason text;
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
  if p_request_id is null then
    raise exception 'request_id_required' using errcode = '22023';
  end if;
  if p_reason is null or length(btrim(p_reason)) = 0 or length(p_reason) > 1000 then
    raise exception 'invalid_cancellation_reason' using errcode = '22023';
  end if;
  if p_idempotency_key is null or length(btrim(p_idempotency_key)) < 8
     or length(btrim(p_idempotency_key)) > 120 then
    raise exception 'invalid_idempotency_key' using errcode = '22023';
  end if;

  select * into v_request
  from public.staff_leave_requests r
  where r.id = p_request_id
  for update;

  if not found or v_request.applicant_id <> v_actor then
    raise exception 'leave_request_not_found_or_not_owner' using errcode = '42501';
  end if;

  v_event_key := 'leave-cancel:' || v_request.id::text || ':' || btrim(p_idempotency_key);

  -- A retry with the same key is a no-op only if this exact cancellation was recorded.
  if v_request.status = 'cancelled' then
    select a.reason into v_prior_reason
    from public.staff_leave_approval_actions a
    where a.request_id = v_request.id
      and a.actor_id = v_actor
      and a.action = 'cancelled'
      and a.metadata->>'idempotency_key' = btrim(p_idempotency_key)
    limit 1;
    if found then
      if v_prior_reason is distinct from btrim(p_reason) then
        raise exception 'idempotency_key_reused_with_different_payload' using errcode = '22023';
      end if;
      return v_request.id;
    end if;
    raise exception 'leave_request_already_cancelled' using errcode = '55000';
  end if;

  if v_request.status not in ('draft', 'blocked_approver_resolution', 'submitted', 'pending_approval') then
    raise exception 'leave_request_state_not_cancellable' using errcode = '55000';
  end if;

  -- Drafts can be discarded at any time. Submitted requests must be cancelled
  -- no later than the calendar day before leave starts in the school timezone.
  v_today_bangkok := (statement_timestamp() at time zone 'Asia/Bangkok')::date;
  if v_request.status <> 'draft'
     and v_today_bangkok > (v_request.starts_on - 1) then
    raise exception 'cancellation_cutoff_passed' using errcode = '22023';
  end if;

  update public.staff_leave_requests
  set status = 'cancelled',
      cancellation_reason = btrim(p_reason),
      cancelled_at = statement_timestamp(),
      updated_at = statement_timestamp()
  where id = v_request.id;

  insert into public.staff_leave_approval_actions (
    request_id, actor_id, action, reason, metadata
  ) values (
    v_request.id, v_actor, 'cancelled', btrim(p_reason),
    jsonb_build_object('idempotency_key', btrim(p_idempotency_key), 'timezone', 'Asia/Bangkok')
  );

  insert into public.staff_leave_notification_outbox (
    event_key, request_id, recipient_id, event_type, channel, safe_payload, status
  ) values (
    v_event_key, v_request.id, v_actor, 'cancelled', 'in_app',
    jsonb_build_object('event', 'leave_cancelled', 'request_id', v_request.id::text),
    'pending'
  ) on conflict (event_key) do nothing;

  -- If the request had a trusted current assignee, notify that approver too.
  -- Do not guess a recipient for blocked/unrouted requests.
  if v_request.current_approver_user_id is not null
     and v_request.current_approver_user_id <> v_actor then
    insert into public.staff_leave_notification_outbox (
      event_key, request_id, recipient_id, event_type, channel, safe_payload, status
    ) values (
      'leave-cancel-approver:' || v_request.id::text || ':' || btrim(p_idempotency_key),
      v_request.id, v_request.current_approver_user_id, 'cancelled', 'in_app',
      jsonb_build_object('event', 'leave_cancelled', 'request_id', v_request.id::text),
      'pending'
    ) on conflict (event_key) do nothing;
  end if;

  return v_request.id;
end;
$$;

revoke all on function public.staff_leave_cancel(uuid, text, text) from public, anon;
grant execute on function public.staff_leave_cancel(uuid, text, text) to authenticated;


-- Draft-only submission RPC. Authority mapping is not verified, so fail closed:
-- record an explicit blocked state rather than silently assigning an approver.
-- No admin alert is enqueued until an authorized recipient mapping is verified.

create or replace function public.staff_leave_submit(
  p_request_id uuid,
  p_idempotency_key text
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_actor uuid;
  v_request public.staff_leave_requests%rowtype;
  v_key text;
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
  if p_request_id is null then
    raise exception 'request_id_required' using errcode = '22023';
  end if;
  if p_idempotency_key is null or length(btrim(p_idempotency_key)) < 8
     or length(btrim(p_idempotency_key)) > 120 then
    raise exception 'invalid_idempotency_key' using errcode = '22023';
  end if;

  select * into v_request
  from public.staff_leave_requests r
  where r.id = p_request_id
  for update;

  if not found or v_request.applicant_id <> v_actor then
    raise exception 'leave_request_not_found_or_not_owner' using errcode = '42501';
  end if;

  v_key := btrim(p_idempotency_key);

  if v_request.status = 'blocked_approver_resolution'
     and exists (
       select 1 from public.staff_leave_approval_actions a
       where a.request_id = v_request.id
         and a.actor_id = v_actor
         and a.action = 'blocked'
         and a.metadata->>'idempotency_key' = v_key
     ) then
    return v_request.id;
  end if;

  if v_request.status <> 'draft' then
    raise exception 'leave_request_state_not_submittable' using errcode = '55000';
  end if;

  -- Do not route to the vacant Deputy Director position or assume the Director
  -- has delegated authority. Until an approved server-side authority mapping exists,
  -- preserve the request and make the unresolved route explicit.
  update public.staff_leave_requests
  set status = 'blocked_approver_resolution',
      submitted_at = statement_timestamp(),
      updated_at = statement_timestamp()
  where id = v_request.id;

  insert into public.staff_leave_approval_actions (
    request_id, actor_id, action, reason, metadata
  ) values (
    v_request.id, v_actor, 'blocked',
    'Approver authority mapping has not been verified.',
    jsonb_build_object(
      'idempotency_key', v_key,
      'reason_code', 'approver_authority_unverified',
      'route_resolved', false
    )
  );

  -- Confirm the state change to the applicant without guessing an approver.
  -- This is not an approver notification; routing remains blocked until authority is verified.
  insert into public.staff_leave_notification_outbox (
    event_key, request_id, recipient_id, event_type, channel, safe_payload, status
  ) values (
    'leave-submit-blocked:' || v_request.id::text || ':' || v_key,
    v_request.id, v_request.applicant_id, 'blocked', 'in_app',
    jsonb_build_object(
      'event', 'leave_blocked',
      'request_id', v_request.id::text,
      'status', 'blocked_approver_resolution'
    ),
    'pending'
  ) on conflict (event_key) do nothing;

  return v_request.id;
end;
$$;

revoke all on function public.staff_leave_submit(uuid, text) from public, anon;
grant execute on function public.staff_leave_submit(uuid, text) to authenticated;


-- Draft-only decision RPC. Only the active, explicitly assigned approver may decide.
-- This does not establish the school's legal approval authority; assignment must be
-- produced by a separately verified routing configuration before any Production use.

create or replace function public.staff_leave_decide(
  p_request_id uuid,
  p_decision text,
  p_reason text,
  p_idempotency_key text
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_actor uuid;
  v_request public.staff_leave_requests%rowtype;
  v_action text;
  v_target_status text;
  v_key text;
  v_event_key text;
  v_prior_reason text;
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
  if p_request_id is null then
    raise exception 'request_id_required' using errcode = '22023';
  end if;
  if p_decision is null or p_decision not in ('approve', 'reject') then
    raise exception 'invalid_leave_decision' using errcode = '22023';
  end if;
  if p_decision = 'reject'
     and (p_reason is null or length(btrim(p_reason)) = 0 or length(p_reason) > 1000) then
    raise exception 'rejection_reason_required' using errcode = '22023';
  end if;
  if p_decision = 'approve' and p_reason is not null and length(p_reason) > 1000 then
    raise exception 'invalid_decision_reason' using errcode = '22023';
  end if;
  if p_idempotency_key is null or length(btrim(p_idempotency_key)) < 8
     or length(btrim(p_idempotency_key)) > 120 then
    raise exception 'invalid_idempotency_key' using errcode = '22023';
  end if;

  v_key := btrim(p_idempotency_key);
  v_action := case when p_decision = 'approve' then 'approved' else 'rejected' end;
  v_target_status := case when p_decision = 'approve' then 'approved' else 'rejected' end;

  select * into v_request
  from public.staff_leave_requests r
  where r.id = p_request_id
  for update;

  if not found then
    raise exception 'leave_request_not_found_or_not_assigned' using errcode = '42501';
  end if;

  -- Idempotent retry only for the exact prior decision and key.
  if v_request.status = v_target_status then
    select a.reason into v_prior_reason
    from public.staff_leave_approval_actions a
    where a.request_id = v_request.id
      and a.actor_id = v_actor
      and a.action = v_action
      and a.metadata->>'idempotency_key' = v_key
    limit 1;
    if found then
      if v_prior_reason is distinct from nullif(btrim(coalesce(p_reason, '')), '') then
        raise exception 'idempotency_key_reused_with_different_payload' using errcode = '22023';
      end if;
      return v_request.id;
    end if;
  end if;

  if v_request.applicant_id = v_actor then
    raise exception 'self_approval_forbidden' using errcode = '42501';
  end if;
  if v_request.current_approver_user_id is distinct from v_actor then
    raise exception 'leave_request_not_found_or_not_assigned' using errcode = '42501';
  end if;
  if v_request.status <> 'pending_approval' then
    raise exception 'leave_request_state_not_decidable' using errcode = '55000';
  end if;

  update public.staff_leave_requests
  set status = v_target_status,
      decided_at = statement_timestamp(),
      updated_at = statement_timestamp()
  where id = v_request.id;

  insert into public.staff_leave_approval_actions (
    request_id, actor_id, action, reason, metadata
  ) values (
    v_request.id, v_actor, v_action, nullif(btrim(coalesce(p_reason, '')), ''),
    jsonb_build_object('idempotency_key', v_key, 'decision', p_decision)
  );

  v_event_key := 'leave-decision:' || v_request.id::text || ':' || v_action || ':' || v_key;
  insert into public.staff_leave_notification_outbox (
    event_key, request_id, recipient_id, event_type, channel, safe_payload, status
  ) values (
    v_event_key, v_request.id, v_request.applicant_id, v_action, 'in_app',
    jsonb_build_object('event', 'leave_' || v_action, 'request_id', v_request.id::text),
    'pending'
  ) on conflict (event_key) do nothing;

  return v_request.id;
end;
$$;

revoke all on function public.staff_leave_decide(uuid, text, text, text) from public, anon;
grant execute on function public.staff_leave_decide(uuid, text, text, text) to authenticated;


-- Draft-only two-stage approval enforcement. Do not apply to Production.
-- Routing is fail-closed until a trusted authority mapping is explicitly verified.

alter table public.staff_leave_requests
  add column if not exists approval_stage text not null default 'vice_director_review'
  check (approval_stage in ('vice_director_review','director_final_review','completed'));

create table if not exists public.staff_leave_approval_route_config (
  singleton boolean primary key default true check (singleton),
  vice_director_user_id uuid references public.profiles(id),
  director_user_id uuid references public.profiles(id),
  authority_verified boolean not null default false,
  direct_to_vice_enabled boolean not null default false,
  authority_reference text,
  verified_by uuid references public.profiles(id),
  verified_at timestamptz,
  updated_at timestamptz not null default now(),
  constraint staff_leave_route_verified_fields_chk check (
    not authority_verified or (
      vice_director_user_id is not null and director_user_id is not null
      and vice_director_user_id <> director_user_id
      and nullif(btrim(authority_reference), '') is not null
      and verified_by is not null and verified_at is not null
    )
  ),
  constraint staff_leave_route_exception_requires_verified_chk check (
    not direct_to_vice_enabled or authority_verified
  )
);
alter table public.staff_leave_approval_route_config enable row level security;
revoke all on table public.staff_leave_approval_route_config from public, anon, authenticated;
-- Intentionally no client read/write policies or grants. Trusted administrators must
-- provision this configuration out-of-band after legal/role verification.

create or replace function public.staff_leave_decide(
  p_request_id uuid,
  p_decision text,
  p_reason text,
  p_idempotency_key text
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_actor uuid;
  v_request public.staff_leave_requests%rowtype;
  v_route public.staff_leave_approval_route_config%rowtype;
  v_action text;
  v_key text;
  v_event_key text;
  v_prior_reason text;
  v_next_approver uuid;
begin
  v_actor := auth.uid();
  if v_actor is null then
    raise exception 'authentication_required' using errcode = '28000';
  end if;
  if not exists (select 1 from public.profiles p where p.id = v_actor and p.is_active = true) then
    raise exception 'active_profile_required' using errcode = '42501';
  end if;
  if p_request_id is null then raise exception 'request_id_required' using errcode = '22023'; end if;
  if p_decision is null or p_decision not in ('approve','reject') then
    raise exception 'invalid_leave_decision' using errcode = '22023';
  end if;
  if p_decision = 'reject' and (p_reason is null or length(btrim(p_reason)) = 0 or length(p_reason) > 1000) then
    raise exception 'rejection_reason_required' using errcode = '22023';
  end if;
  if p_decision = 'approve' and p_reason is not null and length(p_reason) > 1000 then
    raise exception 'invalid_decision_reason' using errcode = '22023';
  end if;
  if p_idempotency_key is null or length(btrim(p_idempotency_key)) < 8
     or length(btrim(p_idempotency_key)) > 120 then
    raise exception 'invalid_idempotency_key' using errcode = '22023';
  end if;
  v_key := btrim(p_idempotency_key);

  select * into v_request from public.staff_leave_requests r where r.id = p_request_id for update;
  if not found then raise exception 'leave_request_not_found_or_not_assigned' using errcode = '42501'; end if;

  -- Idempotent retry is accepted only for the exact actor/action/key/reason and final state.
  -- A retry of the exact Deputy→Director transition is idempotent too.
  if p_decision = 'approve' and v_request.status = 'pending_approval'
     and v_request.approval_stage = 'director_final_review' then
    select a.reason into v_prior_reason from public.staff_leave_approval_actions a
    where a.request_id = v_request.id and a.actor_id = v_actor and a.action = 'routed'
      and a.metadata->>'idempotency_key' = v_key limit 1;
    if found then
      if v_prior_reason is distinct from nullif(btrim(coalesce(p_reason,'')), '') then
        raise exception 'idempotency_key_reused_with_different_payload' using errcode = '22023';
      end if;
      return v_request.id;
    end if;
  end if;

  if v_request.status in ('approved','rejected') then
    v_action := case when p_decision = 'approve' then 'approved' else 'rejected' end;
    select a.reason into v_prior_reason from public.staff_leave_approval_actions a
    where a.request_id = v_request.id and a.actor_id = v_actor and a.action = v_action
      and a.metadata->>'idempotency_key' = v_key limit 1;
    if found then
      if (p_decision = 'approve' and v_request.status <> 'approved')
         or (p_decision = 'reject' and v_request.status <> 'rejected')
         or v_prior_reason is distinct from nullif(btrim(coalesce(p_reason,'')), '') then
        raise exception 'idempotency_key_reused_with_different_payload' using errcode = '22023';
      end if;
      return v_request.id;
    end if;
  end if;

  if v_request.applicant_id = v_actor then raise exception 'self_approval_forbidden' using errcode = '42501'; end if;
  if v_request.status <> 'pending_approval' then
    raise exception 'leave_request_state_not_decidable' using errcode = '55000';
  end if;

  select * into v_route from public.staff_leave_approval_route_config where singleton = true;
  if not found or not v_route.authority_verified then
    raise exception 'approver_authority_unverified' using errcode = '42501';
  end if;
  if not exists (select 1 from public.profiles p where p.id = v_route.director_user_id and p.is_active = true)
     or (v_route.no_vice_director_confirmed and v_route.vice_director_user_id is not null)
     or (not v_route.no_vice_director_confirmed and
       (v_route.vice_director_user_id is null
        or not exists (select 1 from public.profiles p where p.id = v_route.vice_director_user_id and p.is_active = true))) then
    raise exception 'configured_approver_inactive_or_missing' using errcode = '42501';
  end if;

  if p_decision = 'reject' then
    -- The Deputy Director may review and forward only; final rejection belongs
    -- exclusively to the Director at the director_final_review stage.
    if v_request.approval_stage <> 'director_final_review'
       or v_actor <> v_route.director_user_id
       or v_request.current_approver_user_id is distinct from v_actor then
      raise exception 'leave_request_not_found_or_not_assigned' using errcode = '42501';
    end if;
    v_action := 'rejected';
    update public.staff_leave_requests set status='rejected', approval_stage='completed',
      decided_at=statement_timestamp(), updated_at=statement_timestamp() where id=v_request.id;
  else
    if v_request.approval_stage = 'vice_director_review' then
      if v_actor <> v_route.vice_director_user_id
         or v_request.current_approver_user_id is distinct from v_actor then
        raise exception 'leave_request_not_found_or_not_assigned' using errcode = '42501';
      end if;
      -- A configuration flag is not evidence that the Director is absent.
      -- Until trusted, request-specific absence evidence is checked transactionally,
      -- fail closed and leave the request unchanged.
      if v_route.direct_to_vice_enabled then
        raise exception 'director_absence_evidence_required' using errcode = '42501';
      end if;

      update public.staff_leave_requests set approval_stage='director_final_review',
        current_approver_user_id=v_route.director_user_id, updated_at=statement_timestamp()
        where id=v_request.id;
      insert into public.staff_leave_approval_actions(request_id,actor_id,action,reason,metadata)
      values(v_request.id,v_actor,'routed',nullif(btrim(coalesce(p_reason,'')),''),
        jsonb_build_object('idempotency_key',v_key,'decision','approve',
          'from_stage','vice_director_review','to_stage','director_final_review',
          'next_approver_id',v_route.director_user_id));
      insert into public.staff_leave_notification_outbox(event_key,request_id,recipient_id,event_type,channel,safe_payload,status)
      values('leave-stage-advance:'||v_request.id::text||':'||v_key,v_request.id,v_route.director_user_id,
        'approver_assigned','in_app',jsonb_build_object('event','leave_approver_assigned',
        'request_id',v_request.id::text,'stage','director_final_review'),'pending')
      on conflict(event_key) do nothing;
      return v_request.id;
    elsif v_request.approval_stage = 'director_final_review' then
      if v_actor <> v_route.director_user_id
         or v_request.current_approver_user_id is distinct from v_actor then
        raise exception 'leave_request_not_found_or_not_assigned' using errcode = '42501';
      end if;
      v_action := 'approved';
      update public.staff_leave_requests set status='approved', approval_stage='completed',
        decided_at=statement_timestamp(), updated_at=statement_timestamp() where id=v_request.id;
    else
      raise exception 'leave_request_state_not_decidable' using errcode = '55000';
    end if;
  end if;

  insert into public.staff_leave_approval_actions(request_id,actor_id,action,reason,metadata)
  values(v_request.id,v_actor,v_action,nullif(btrim(coalesce(p_reason,'')),''),
    jsonb_build_object('idempotency_key',v_key,'decision',p_decision,'stage',v_request.approval_stage));
  v_event_key := 'leave-decision:'||v_request.id::text||':'||v_action||':'||v_key;
  insert into public.staff_leave_notification_outbox(event_key,request_id,recipient_id,event_type,channel,safe_payload,status)
  values(v_event_key,v_request.id,v_request.applicant_id,v_action,'in_app',
    jsonb_build_object('event','leave_'||v_action,'request_id',v_request.id::text),'pending')
  on conflict(event_key) do nothing;
  return v_request.id;
end;
$$;

revoke all on function public.staff_leave_decide(uuid,text,text,text) from public, anon;
grant execute on function public.staff_leave_decide(uuid,text,text,text) to authenticated;


-- Draft-only migration: admin-managed school responsibility assignments.
-- Apply only in an isolated test database after reviewing dependencies. Never apply to Production as part of this draft.

create table if not exists public.school_responsibility_assignments (
  responsibility_key text primary key check (responsibility_key in (
    'director','vice_director','personnel_head','budget_head','academic_head','general_head'
  )),
  user_id uuid null references public.profiles(id) on delete restrict,
  updated_at timestamptz not null default now(),
  updated_by uuid null references public.profiles(id) on delete set null
);

create table if not exists public.school_responsibility_settings (
  singleton boolean primary key default true check (singleton),
  has_vice_director boolean not null default false,
  updated_at timestamptz not null default now(),
  updated_by uuid null references public.profiles(id) on delete set null
);
insert into public.school_responsibility_settings(singleton,has_vice_director)
values(true,false) on conflict(singleton) do nothing;

create table if not exists public.school_responsibility_audit (
  id bigint generated always as identity primary key,
  responsibility_key text not null,
  previous_user_id uuid null,
  new_user_id uuid null,
  actor_user_id uuid not null,
  changed_at timestamptz not null default now(),
  change_kind text not null check (change_kind in ('assignment_changed','vice_director_setting_changed')),
  previous_has_vice_director boolean null,
  new_has_vice_director boolean null
);

-- Keep this draft migration safe to re-run in an isolated test database where the
-- audit table may have been created by an earlier draft revision.
alter table public.school_responsibility_audit
  add column if not exists previous_has_vice_director boolean null,
  add column if not exists new_has_vice_director boolean null;

alter table public.school_responsibility_assignments enable row level security;
alter table public.school_responsibility_settings enable row level security;
alter table public.school_responsibility_audit enable row level security;
revoke all on public.school_responsibility_assignments from anon, authenticated;
revoke all on public.school_responsibility_settings from anon, authenticated;
revoke all on public.school_responsibility_audit from anon, authenticated;

create or replace function public.admin_get_school_responsibilities()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare result jsonb;
begin
  if auth.uid() is null or not exists (
    select 1 from public.user_roles ur join public.roles r on r.id=ur.role_id
    join public.profiles p on p.id=ur.user_id
    where ur.user_id=auth.uid() and p.is_active=true and r.code='system_admin'
  ) then raise exception 'system_admin_required'; end if;

  select jsonb_build_object(
    'has_vice_director', coalesce((select s.has_vice_director from public.school_responsibility_settings s where s.singleton),false),
    'assignments', coalesce((
      select jsonb_object_agg(a.responsibility_key,jsonb_build_object(
        'user_id',a.user_id,'full_name',p.full_name,'is_active',p.is_active
      ))
      from public.school_responsibility_assignments a
      left join public.profiles p on p.id=a.user_id
    ),'{}'::jsonb),
    'users', coalesce((
      select jsonb_agg(jsonb_build_object('id',p.id,'full_name',p.full_name,'email',p.email,'employee_code',p.employee_code) order by p.full_name)
      from public.profiles p where p.is_active=true
    ),'[]'::jsonb)
  ) into result;
  return result;
end;
$$;

create or replace function public.admin_save_school_responsibilities(
  p_assignments jsonb,
  p_has_vice_director boolean
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  actor uuid := auth.uid();
  k text;
  target_id uuid;
  old_id uuid;
  old_has_vice_director boolean;
  allowed_keys text[] := array['director','vice_director','personnel_head','budget_head','academic_head','general_head'];
  keys_seen text[];
begin
  if actor is null or not exists (
    select 1 from public.user_roles ur join public.roles r on r.id=ur.role_id
    join public.profiles p on p.id=ur.user_id
    where ur.user_id=actor and p.is_active=true and r.code='system_admin'
  ) then raise exception 'system_admin_required'; end if;

  if jsonb_typeof(p_assignments) <> 'object' then raise exception 'invalid_assignments'; end if;
  select array_agg(key) into keys_seen from jsonb_object_keys(p_assignments) as x(key);
  if exists(select 1 from unnest(coalesce(keys_seen,array[]::text[])) x where not (x=any(allowed_keys))) then
    raise exception 'invalid_responsibility_key';
  end if;

  if nullif(p_assignments->>'director','') is null then raise exception 'active_director_required'; end if;
  if p_has_vice_director and nullif(p_assignments->>'vice_director','') is null then
    raise exception 'active_vice_director_required';
  end if;

  foreach k in array allowed_keys loop
    target_id := nullif(p_assignments->>k,'')::uuid;
    if k='director' and target_id is null then raise exception 'active_director_required'; end if;
    if k='vice_director' and not p_has_vice_director then target_id := null; end if;
    if target_id is not null and not exists(select 1 from public.profiles p where p.id=target_id and p.is_active=true) then
      raise exception 'assigned_user_missing_or_inactive';
    end if;
    if k in ('director','vice_director') and target_id is not null and target_id=(nullif(p_assignments->>'director',''))::uuid and k='vice_director' then
      raise exception 'director_and_vice_must_differ';
    end if;

    select a.user_id into old_id from public.school_responsibility_assignments a where a.responsibility_key=k;
    if old_id is distinct from target_id then
      insert into public.school_responsibility_assignments(responsibility_key,user_id,updated_at,updated_by)
      values(k,target_id,now(),actor)
      on conflict(responsibility_key) do update set user_id=excluded.user_id,updated_at=excluded.updated_at,updated_by=excluded.updated_by;
      insert into public.school_responsibility_audit(responsibility_key,previous_user_id,new_user_id,actor_user_id,change_kind)
      values(k,old_id,target_id,actor,'assignment_changed');
    end if;
  end loop;

  select s.has_vice_director into old_has_vice_director from public.school_responsibility_settings s where s.singleton for update;
  if old_has_vice_director is distinct from p_has_vice_director then
    insert into public.school_responsibility_settings(singleton,has_vice_director,updated_at,updated_by)
    values(true,p_has_vice_director,now(),actor)
    on conflict(singleton) do update set has_vice_director=excluded.has_vice_director,updated_at=excluded.updated_at,updated_by=excluded.updated_by;
    insert into public.school_responsibility_audit(responsibility_key,previous_user_id,new_user_id,actor_user_id,change_kind,previous_has_vice_director,new_has_vice_director)
    values('vice_director',null,null,actor,'vice_director_setting_changed',old_has_vice_director,p_has_vice_director);
  end if;
  return public.admin_get_school_responsibilities();
end;
$$;

revoke all on function public.admin_get_school_responsibilities() from public, anon;
revoke all on function public.admin_save_school_responsibilities(jsonb,boolean) from public, anon;
grant execute on function public.admin_get_school_responsibilities() to authenticated;
grant execute on function public.admin_save_school_responsibilities(jsonb,boolean) to authenticated;


-- Draft-only routing correction. Never apply to Production without review.
-- When the school explicitly confirms there is no Deputy Director, the Director
-- is the sole approver. Missing/unverified configuration still fails closed.

alter table public.staff_leave_approval_route_config
  add column if not exists no_vice_director_confirmed boolean not null default false;

alter table public.staff_leave_approval_route_config
  drop constraint if exists staff_leave_route_verified_fields_chk;
alter table public.staff_leave_approval_route_config
  add constraint staff_leave_route_verified_fields_chk check (
    not authority_verified or (
      director_user_id is not null
      and nullif(btrim(authority_reference), '') is not null
      and verified_by is not null and verified_at is not null
      and (
        (no_vice_director_confirmed and vice_director_user_id is null)
        or
        (not no_vice_director_confirmed and vice_director_user_id is not null
          and vice_director_user_id <> director_user_id)
      )
    )
  );

create or replace function public.staff_leave_submit(
  p_request_id uuid,
  p_idempotency_key text
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_actor uuid;
  v_request public.staff_leave_requests%rowtype;
  v_route public.staff_leave_approval_route_config%rowtype;
  v_key text;
begin
  v_actor := auth.uid();
  if v_actor is null then raise exception 'authentication_required' using errcode='28000'; end if;
  if not exists (select 1 from public.profiles p where p.id=v_actor and p.is_active=true) then
    raise exception 'active_profile_required' using errcode='42501';
  end if;
  if p_request_id is null then raise exception 'request_id_required' using errcode='22023'; end if;
  if p_idempotency_key is null or length(btrim(p_idempotency_key))<8
     or length(btrim(p_idempotency_key))>120 then
    raise exception 'invalid_idempotency_key' using errcode='22023';
  end if;
  v_key:=btrim(p_idempotency_key);

  select * into v_request from public.staff_leave_requests r
  where r.id=p_request_id for update;
  if not found or v_request.applicant_id<>v_actor then
    raise exception 'leave_request_not_found_or_not_owner' using errcode='42501';
  end if;

  if v_request.status='pending_approval'
     and v_request.current_approver_user_id is not null
     and exists (select 1 from public.staff_leave_approval_actions a
       where a.request_id=v_request.id and a.actor_id=v_actor and a.action='submitted'
         and a.metadata->>'idempotency_key'=v_key) then
    return v_request.id;
  end if;
  if v_request.status='blocked_approver_resolution'
     and exists (select 1 from public.staff_leave_approval_actions a
       where a.request_id=v_request.id and a.actor_id=v_actor and a.action='blocked'
         and a.metadata->>'idempotency_key'=v_key) then
    return v_request.id;
  end if;
  if v_request.status<>'draft' then
    raise exception 'leave_request_state_not_submittable' using errcode='55000';
  end if;

  select * into v_route from public.staff_leave_approval_route_config where singleton=true;
  if not found or not v_route.authority_verified
     or v_route.director_user_id is null
     or (v_route.no_vice_director_confirmed and v_route.vice_director_user_id is not null)
     or (not v_route.no_vice_director_confirmed and
       (v_route.vice_director_user_id is null
        or v_route.vice_director_user_id=v_route.director_user_id
        or not exists (select 1 from public.profiles p where p.id=v_route.vice_director_user_id and p.is_active=true)))
     or not exists (select 1 from public.profiles p where p.id=v_route.director_user_id and p.is_active=true) then
    update public.staff_leave_requests set status='blocked_approver_resolution',
      submitted_at=statement_timestamp(), current_approver_user_id=null,
      updated_at=statement_timestamp() where id=v_request.id;
    insert into public.staff_leave_approval_actions(request_id,actor_id,action,reason,metadata)
    values(v_request.id,v_actor,'blocked','Approver configuration is missing or unverified.',
      jsonb_build_object('idempotency_key',v_key,'reason_code','approver_authority_unverified','route_resolved',false));
    insert into public.staff_leave_notification_outbox(event_key,request_id,recipient_id,event_type,channel,safe_payload,status)
    values('leave-submit-blocked:'||v_request.id::text||':'||v_key,v_request.id,v_actor,'blocked','in_app',
      jsonb_build_object('event','leave_blocked','request_id',v_request.id::text,
        'status','blocked_approver_resolution'),'pending')
    on conflict(event_key) do nothing;
    return v_request.id;
  end if;

  if v_route.no_vice_director_confirmed then
    update public.staff_leave_requests set status='pending_approval',
      approval_stage='director_final_review',
      current_approver_user_id=v_route.director_user_id,
      submitted_at=statement_timestamp(),updated_at=statement_timestamp()
    where id=v_request.id;

    insert into public.staff_leave_approval_actions(request_id,actor_id,action,reason,metadata)
    values(v_request.id,v_actor,'submitted',null,
      jsonb_build_object('idempotency_key',v_key,'approver_id',v_route.director_user_id,
        'approval_route','director_only_confirmed_no_vice'));
    insert into public.staff_leave_notification_outbox(event_key,request_id,recipient_id,event_type,channel,safe_payload,status)
    values('leave-submit-director:'||v_request.id::text||':'||v_key,v_request.id,
      v_route.director_user_id,'submitted','in_app',
      jsonb_build_object('event','leave_submitted','request_id',v_request.id::text,
        'stage','director_final_review'),'pending')
    on conflict(event_key) do nothing;
  else
    update public.staff_leave_requests set status='pending_approval',
      approval_stage='vice_director_review',
      current_approver_user_id=v_route.vice_director_user_id,
      submitted_at=statement_timestamp(),updated_at=statement_timestamp()
    where id=v_request.id;

    insert into public.staff_leave_approval_actions(request_id,actor_id,action,reason,metadata)
    values(v_request.id,v_actor,'submitted',null,
      jsonb_build_object('idempotency_key',v_key,'approver_id',v_route.vice_director_user_id,
        'approval_route','vice_director_then_director'));
    insert into public.staff_leave_notification_outbox(event_key,request_id,recipient_id,event_type,channel,safe_payload,status)
    values('leave-submit-vice:'||v_request.id::text||':'||v_key,v_request.id,
      v_route.vice_director_user_id,'submitted','in_app',
      jsonb_build_object('event','leave_submitted','request_id',v_request.id::text,
        'stage','vice_director_review'),'pending')
    on conflict(event_key) do nothing;
  end if;
  return v_request.id;
end;
$$;

revoke all on function public.staff_leave_submit(uuid,text) from public, anon;
grant execute on function public.staff_leave_submit(uuid,text) to authenticated;
