-- Production release bundle applied to Supabase project wbns-edoc on 2026-11-03.
-- The statements were rehearsed transactionally against the live Production catalog before apply.
-- Policy calculation remains fail-closed until the school-wide leave policy is formally approved.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';
-- Included in the consolidated Production release migration.
-- Applied in the Production release on 2026-11-03 after live-catalog rehearsal.
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


-- Included in the consolidated Production release migration.
-- Applied in the Production release on 2026-11-03 after live-catalog rehearsal.

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


-- Included in the consolidated Production release migration.
-- Late cancellation exceptions are deliberately not enabled until authorized-role
-- configuration and an audited exception workflow are implemented and verified.
-- Applied in the Production release on 2026-11-03 after live-catalog rehearsal.

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


-- Included in the consolidated Production release migration.
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


-- Included in the consolidated Production release migration.
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


-- Included in the consolidated Production release migration.
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


-- Included in the consolidated Production release migration.
-- Production release migration; tracked at the applied version.

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


-- Included in the consolidated Production release migration.
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


-- Included in the consolidated Production release migration.

alter table public.staff_leave_requests add column if not exists approval_route_snapshot jsonb;
alter table public.staff_leave_requests drop constraint if exists staff_leave_route_snapshot_shape_chk;
alter table public.staff_leave_requests add constraint staff_leave_route_snapshot_shape_chk check (
 approval_route_snapshot is null or ((
  jsonb_typeof(approval_route_snapshot)='object'
  and approval_route_snapshot->>'version'='1'
  and approval_route_snapshot->>'route_kind' in ('vice_director_then_director','director_only_confirmed_no_vice')
  and nullif(approval_route_snapshot->>'director_user_id','') is not null
  and nullif(approval_route_snapshot->>'authority_reference','') is not null
  and nullif(approval_route_snapshot->>'authority_verified_by','') is not null
  and nullif(approval_route_snapshot->>'authority_verified_at','') is not null
  and nullif(approval_route_snapshot->>'captured_at','') is not null
  and ((approval_route_snapshot->>'route_kind'='director_only_confirmed_no_vice'
        and approval_route_snapshot->'vice_director_user_id'='null'::jsonb)
    or (approval_route_snapshot->>'route_kind'='vice_director_then_director'
        and nullif(approval_route_snapshot->>'vice_director_user_id','') is not null
        and approval_route_snapshot->>'vice_director_user_id'<>approval_route_snapshot->>'director_user_id'))
 ) is true)
);
-- Prevent later updates from replacing or clearing a captured route, even by
-- privileged application code that might otherwise issue direct UPDATEs.
create or replace function public.staff_leave_guard_route_snapshot_immutable()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
begin
  if old.approval_route_snapshot is not null
     and new.approval_route_snapshot is distinct from old.approval_route_snapshot then
    raise exception 'approval_route_snapshot_immutable' using errcode = '55000';
  end if;
  if old.approval_route_snapshot is null
     and new.approval_route_snapshot is not null
     and current_setting('app.staff_leave_route_snapshot_write', true) is distinct from 'on' then
    raise exception 'approval_route_snapshot_rpc_only' using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists staff_leave_route_snapshot_immutable
  on public.staff_leave_requests;
create trigger staff_leave_route_snapshot_immutable
before update of approval_route_snapshot on public.staff_leave_requests
for each row execute function public.staff_leave_guard_route_snapshot_immutable();

revoke all on function public.staff_leave_guard_route_snapshot_immutable() from public, anon, authenticated;

create or replace function public.staff_leave_submit(p_request_id uuid,p_idempotency_key text)
returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$

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

  -- Freeze the verified route in the same transaction as submission.
  perform set_config('app.staff_leave_route_snapshot_write', 'on', true);
  update public.staff_leave_requests
  set approval_route_snapshot = jsonb_build_object(
    'version', 1,
    'route_kind', case when v_route.no_vice_director_confirmed then
      'director_only_confirmed_no_vice' else 'vice_director_then_director' end,
    'vice_director_user_id', v_route.vice_director_user_id,
    'director_user_id', v_route.director_user_id,
    'authority_reference', v_route.authority_reference,
    'authority_verified_by', v_route.verified_by,
    'authority_verified_at', v_route.verified_at,
    'captured_at', statement_timestamp()
  ), updated_at = statement_timestamp() where id = v_request.id;
  perform set_config('app.staff_leave_route_snapshot_write', 'off', true);

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
create or replace function public.staff_leave_decide(p_request_id uuid,p_decision text,p_reason text,p_idempotency_key text)
returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$

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

  -- Never re-read mutable singleton config for an in-flight request.
  if v_request.approval_route_snapshot is null
     or v_request.approval_route_snapshot->>'version' <> '1'
     or v_request.approval_route_snapshot->>'route_kind' not in
       ('vice_director_then_director','director_only_confirmed_no_vice') then
    raise exception 'approver_route_snapshot_missing_or_invalid' using errcode = '42501';
  end if;
  v_route.director_user_id := nullif(v_request.approval_route_snapshot->>'director_user_id','')::uuid;
  v_route.vice_director_user_id := nullif(v_request.approval_route_snapshot->>'vice_director_user_id','')::uuid;
  v_route.authority_verified := true;
  v_route.no_vice_director_confirmed := v_request.approval_route_snapshot->>'route_kind' = 'director_only_confirmed_no_vice';
  if v_route.director_user_id is null
     or (v_route.no_vice_director_confirmed and v_route.vice_director_user_id is not null)
     or (not v_route.no_vice_director_confirmed and
       (v_route.vice_director_user_id is null or v_route.vice_director_user_id = v_route.director_user_id)) then
    raise exception 'approver_route_snapshot_missing_or_invalid' using errcode = '42501';
  end if;
  if not exists (select 1 from public.profiles p where p.id = v_route.director_user_id and p.is_active = true)
     or (not v_route.no_vice_director_confirmed and
       not exists (select 1 from public.profiles p where p.id = v_route.vice_director_user_id and p.is_active = true)) then
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
revoke all on function public.staff_leave_submit(uuid,text) from public,anon;
grant execute on function public.staff_leave_submit(uuid,text) to authenticated;
revoke all on function public.staff_leave_decide(uuid,text,text,text) from public,anon;
grant execute on function public.staff_leave_decide(uuid,text,text,text) to authenticated;


-- Included in the consolidated Production release migration.
-- for leave approvers. Apply only in disposable CI/test databases; never Production.

alter table public.staff_leave_approval_route_config
  add column if not exists no_vice_director_confirmed boolean not null default false;

-- The earlier draft constraint assumed a deputy always existed. Replace it with
-- a constraint that permits a director-only route only when explicitly confirmed.
alter table public.staff_leave_approval_route_config
  drop constraint if exists staff_leave_route_verified_fields_chk;
alter table public.staff_leave_approval_route_config
  drop constraint if exists staff_leave_route_exception_requires_verified_chk;
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
alter table public.staff_leave_approval_route_config
  add constraint staff_leave_route_exception_requires_verified_chk
  check (not no_vice_director_confirmed or authority_verified);

create or replace function public.staff_leave_sync_route_from_responsibility_audit()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_director uuid;
  v_vice uuid;
  v_has_vice boolean;
begin
  -- Only the audited admin RPC writes this audit table. Every change refreshes
  -- the trusted route mapping from the authoritative assignments/settings.
  select a.user_id into v_director
    from public.school_responsibility_assignments a
   where a.responsibility_key='director';
  select a.user_id into v_vice
    from public.school_responsibility_assignments a
   where a.responsibility_key='vice_director';
  select s.has_vice_director into v_has_vice
    from public.school_responsibility_settings s where s.singleton=true;

  if coalesce(v_has_vice,false) then
    if v_director is null or v_vice is null or v_director=v_vice
       or not exists(select 1 from public.profiles p where p.id=v_director and p.is_active=true)
       or not exists(select 1 from public.profiles p where p.id=v_vice and p.is_active=true) then
      update public.staff_leave_approval_route_config
         set authority_verified=false, no_vice_director_confirmed=false,
             updated_at=statement_timestamp()
       where singleton=true;
      return new;
    end if;
  else
    if v_director is null
       or not exists(select 1 from public.profiles p where p.id=v_director and p.is_active=true) then
      update public.staff_leave_approval_route_config
         set authority_verified=false, no_vice_director_confirmed=false,
             updated_at=statement_timestamp()
       where singleton=true;
      return new;
    end if;
    v_vice := null;
  end if;

  insert into public.staff_leave_approval_route_config(
    singleton,vice_director_user_id,director_user_id,authority_verified,
    direct_to_vice_enabled,no_vice_director_confirmed,authority_reference,
    verified_by,verified_at,updated_at
  ) values (
    true,v_vice,v_director,true,false,not coalesce(v_has_vice,false),
    'school_responsibility_audit:'||new.id::text,new.actor_user_id,new.changed_at,statement_timestamp()
  )
  on conflict(singleton) do update set
    vice_director_user_id=excluded.vice_director_user_id,
    director_user_id=excluded.director_user_id,
    authority_verified=excluded.authority_verified,
    direct_to_vice_enabled=false,
    no_vice_director_confirmed=excluded.no_vice_director_confirmed,
    authority_reference=excluded.authority_reference,
    verified_by=excluded.verified_by,
    verified_at=excluded.verified_at,
    updated_at=excluded.updated_at;

  return new;
end;
$$;

drop trigger if exists staff_leave_sync_route_from_responsibility_audit
  on public.school_responsibility_audit;
create trigger staff_leave_sync_route_from_responsibility_audit
after insert on public.school_responsibility_audit
for each row execute function public.staff_leave_sync_route_from_responsibility_audit();

revoke all on function public.staff_leave_sync_route_from_responsibility_audit() from public, anon, authenticated;

-- Structural guard: the leave submit RPC and admin settings must use one route table.
do $test$
begin
  if to_regclass('public.school_responsibility_assignments') is null
     or to_regclass('public.school_responsibility_settings') is null
     or to_regclass('public.school_responsibility_audit') is null then
    raise exception 'school_responsibility_dependency_missing';
  end if;
  if not exists(select 1 from information_schema.columns
    where table_schema='public' and table_name='staff_leave_approval_route_config'
      and column_name='no_vice_director_confirmed') then
    raise exception 'explicit_no_vice_setting_missing';
  end if;
end
$test$;


-- Included in the consolidated Production release migration.
-- This uses the existing private-per-recipient public.notifications feed.
-- No email/push provider, secret, scheduled job, or paid service is required.

create or replace function public.staff_leave_deliver_in_app_notification()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_title text;
  v_body text;
  v_priority text;
begin
  if new.channel <> 'in_app' then
    return new;
  end if;

  case new.event_type
    when 'submitted' then
      v_title := 'มีใบลารอพิจารณา';
      v_body := 'มีคำขอลาใหม่ที่ต้องดำเนินการ';
      v_priority := 'high';
    when 'approver_assigned' then
      v_title := 'มีใบลารอพิจารณา';
      v_body := 'มีคำขอลาที่ส่งต่อมายังขั้นตอนของคุณ';
      v_priority := 'high';
    when 'approved' then
      v_title := 'ใบลาได้รับอนุมัติ';
      v_body := 'คำขอลาของคุณได้รับการอนุมัติแล้ว';
      v_priority := 'normal';
    when 'rejected' then
      v_title := 'ผลการพิจารณาใบลา';
      v_body := 'คำขอลาของคุณไม่ได้รับการอนุมัติ โปรดเข้าสู่ระบบเพื่อตรวจสอบ';
      v_priority := 'normal';
    when 'cancelled' then
      v_title := 'ยกเลิกใบลาแล้ว';
      v_body := 'มีการบันทึกการยกเลิกคำขอลา';
      v_priority := 'normal';
    when 'blocked' then
      v_title := 'ใบลารอการตรวจสอบ';
      v_body := 'คำขอลายังไม่ถูกส่งให้ผู้อนุมัติ เนื่องจากต้องตรวจสอบการกำหนดผู้รับผิดชอบ';
      v_priority := 'high';
    when 'overdue' then
      v_title := 'แจ้งเตือนตรวจสอบการกลับเข้าปฏิบัติงาน';
      v_body := 'มีรายการที่ถึงกำหนดกลับเข้าปฏิบัติงานและรอการตรวจสอบ';
      v_priority := 'high';
    else
      raise exception 'unsupported_staff_leave_notification_event: %', new.event_type;
  end case;

  insert into public.notifications (
    recipient_id, document_id, type, title, body, priority
  ) values (
    new.recipient_id, null, 'staff_leave_' || new.event_type,
    v_title, v_body, v_priority
  );

  update public.staff_leave_notification_outbox
     set status = 'sent',
         sent_at = statement_timestamp(),
         last_error_code = null
   where id = new.id
     and status in ('pending','retry','processing');

  return new;
end;
$$;

drop trigger if exists staff_leave_outbox_deliver_in_app
  on public.staff_leave_notification_outbox;
create trigger staff_leave_outbox_deliver_in_app
after insert on public.staff_leave_notification_outbox
for each row
when (new.channel = 'in_app')
execute function public.staff_leave_deliver_in_app_notification();

revoke all on function public.staff_leave_deliver_in_app_notification()
  from public, anon, authenticated;


-- Included in the consolidated Production release migration.
-- One school-wide policy applies to all personnel; category is reporting metadata only.
-- No entitlement is seeded here. Without an approved rule and explicit calendar,
-- drafts remain drafts and cannot enter the approval workflow.

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
       and coalesce((v_policy_rules->'calendar'->>'verified')::boolean, false) is true
       and jsonb_typeof(v_policy_rules->'calendar'->'weekend_days') = 'array'
       and jsonb_typeof(v_policy_rules->'calendar'->'non_working_dates') = 'array' then
      select count(*)::numeric into v_day_count
      from generate_series(p_starts_on, p_ends_on, interval '1 day') as day_value
      where not exists (
          select 1
          from jsonb_array_elements_text(v_policy_rules->'calendar'->'weekend_days') as weekend(value)
          where weekend.value::integer = extract(isodow from day_value)::integer
        )
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
        "certificate_from_working_day": 3,
        "medical_certificate_required": true,
        "certificate_threshold_confirmed_by_school": true,
        "certificate_threshold_confirmation_date": "2026-10-31",
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
        "max_working_days_per_event": 15,
        "allow_non_consecutive_periods": false,
        "one_continuous_period_required": true,
        "one_entitlement_per_childbirth_event": true,
        "use_within_calendar_days_after_childbirth": 60,
        "file_within_calendar_days_after_childbirth": 30,
        "deadline_source_note": "Filing deadline remains unresolved: source text states 60 days in one clause and 30 days in the procedure. School confirmation on 2026-10-31 confirmed consecutive use and 15 working days per childbirth event only; do not auto-configure the filing deadline.",
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
        "first_year_minimum_service_months": 6,
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
        "minimum_notice_days": 60,
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
        "max_paid_years": 5,
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
as $policy_guard$
begin
  if new.status = 'approved' then
    if new.policy_rules->>'verification_status' is distinct from 'approved'
       or new.policy_rules->>'calculation_ready' is distinct from 'true'
       or coalesce((new.policy_rules->'calendar'->>'verified')::boolean, false) is not true
       or jsonb_typeof(new.policy_rules->'calendar'->'weekend_days') is distinct from 'array'
       or jsonb_array_length(
         case
           when jsonb_typeof(new.policy_rules->'calendar'->'weekend_days') = 'array'
             then new.policy_rules->'calendar'->'weekend_days'
           else '[]'::jsonb
         end
       ) = 0
       or exists (
         select 1
         from jsonb_array_elements_text(
           case
             when jsonb_typeof(new.policy_rules->'calendar'->'weekend_days') = 'array'
               then new.policy_rules->'calendar'->'weekend_days'
             else '[]'::jsonb
           end
         ) as weekend(value)
         where length(weekend.value) <> 1
            or weekend.value not in ('1','2','3','4','5','6','7')
       )
       or jsonb_typeof(new.policy_rules->'calendar'->'non_working_dates') is distinct from 'array'
       or exists (
         select 1
         from jsonb_array_elements_text(
           case
             when jsonb_typeof(new.policy_rules->'calendar'->'non_working_dates') = 'array'
               then new.policy_rules->'calendar'->'non_working_dates'
             else '[]'::jsonb
           end
         ) as holiday(value)
         where length(holiday.value) <> 10
            or holiday.value !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}'
       )
       or jsonb_typeof(new.policy_rules->'implementation_gaps') is distinct from 'array'
       or jsonb_array_length(
         case
           when jsonb_typeof(new.policy_rules->'implementation_gaps') = 'array'
             then new.policy_rules->'implementation_gaps'
           else '[]'::jsonb
         end
       ) > 0 then
      raise exception 'staff_leave_policy_has_unresolved_implementation_gaps'
        using errcode = '55000';
    end if;
  end if;
  return new;
end;
$policy_guard$;

drop trigger if exists staff_leave_policy_review_guard
  on public.staff_leave_policy_versions;
create trigger staff_leave_policy_review_guard
before insert or update of status, policy_rules
on public.staff_leave_policy_versions
for each row execute function public.staff_leave_policy_review_guard();

revoke all on function public.staff_leave_policy_review_guard()
  from public, anon, authenticated;


-- Included in the consolidated Production release migration.
-- Thresholds come only from an approved school-wide policy version.

alter table public.staff_leave_requests
  add column if not exists is_over_limit boolean not null default false;

alter table public.staff_leave_notification_outbox
  drop constraint if exists staff_leave_notification_outbox_event_type_check;
alter table public.staff_leave_notification_outbox
  add constraint staff_leave_notification_outbox_event_type_check
  check (event_type in (
    'submitted','approver_assigned','approved','rejected','cancelled',
    'blocked','overdue','over_limit'
  ));

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
  v_max_days numeric(7,2);
  v_is_over_limit boolean := false;
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
       and coalesce((v_policy_rules->'calendar'->>'verified')::boolean, false) is true
       and jsonb_typeof(v_policy_rules->'calendar'->'weekend_days') = 'array'
       and jsonb_typeof(v_policy_rules->'calendar'->'non_working_dates') = 'array' then
      select count(*)::numeric into v_day_count
      from generate_series(p_starts_on, p_ends_on, interval '1 day') as day_value
      where not exists (
          select 1
          from jsonb_array_elements_text(v_policy_rules->'calendar'->'weekend_days') as weekend(value)
          where weekend.value::integer = extract(isodow from day_value)::integer
        )
        and not exists (
          select 1
          from jsonb_array_elements_text(v_policy_rules->'calendar'->'non_working_dates') as holiday(value)
          where holiday.value::date = day_value::date
        );
    else
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
    if nullif(v_type_rules->>'max_days_per_request','') is not null then
      v_max_days := (v_type_rules->>'max_days_per_request')::numeric;
      v_is_over_limit := v_day_count > v_max_days;
    end if;
    v_policy_snapshot := jsonb_build_object(
      'policy_code', 'school-wide',
      'policy_version_id', v_policy_id,
      'policy_version', v_policy_version,
      'leave_type_code', v_type_code,
      'verification_status', 'approved',
      'calculation_ready', true,
      'counting_basis', v_counting_basis,
      'calculated_day_count', v_day_count,
      'max_days_per_request', v_max_days,
      'is_over_limit', v_is_over_limit,
      'policy_rules_snapshot', v_policy_rules
    );
  else
    v_policy_snapshot := jsonb_build_object(
      'leave_type_code', v_type_code,
      'verification_status', 'pending',
      'calculation_ready', false,
      'is_over_limit', false
    );
  end if;

  insert into public.staff_leave_requests (
    applicant_id, leave_type_id, policy_version_id, starts_on, ends_on,
    day_count, is_over_limit, reason, policy_snapshot, status
  ) values (
    v_actor, p_leave_type_id, v_policy_id, p_starts_on, p_ends_on,
    v_day_count, v_is_over_limit, btrim(p_reason), v_policy_snapshot, 'draft'
  )
  returning id into v_request_id;

  return v_request_id;
end;
$$;

revoke all on function public.staff_leave_create_draft(uuid,date,date,text)
  from public, anon;
grant execute on function public.staff_leave_create_draft(uuid,date,date,text)
  to authenticated;

create or replace function public.staff_leave_deliver_in_app_notification()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_title text;
  v_body text;
  v_priority text;
begin
  if new.channel <> 'in_app' then
    return new;
  end if;

  case new.event_type
    when 'submitted' then
      v_title := 'มีใบลารอพิจารณา';
      v_body := 'มีคำขอลาใหม่ที่ต้องดำเนินการ';
      v_priority := 'high';
    when 'approver_assigned' then
      v_title := 'มีใบลารอพิจารณา';
      v_body := 'มีคำขอลาที่ส่งต่อมายังขั้นตอนของคุณ';
      v_priority := 'high';
    when 'approved' then
      v_title := 'ใบลาได้รับอนุมัติ';
      v_body := 'คำขอลาของคุณได้รับการอนุมัติแล้ว';
      v_priority := 'normal';
    when 'rejected' then
      v_title := 'ผลการพิจารณาใบลา';
      v_body := 'คำขอลาของคุณไม่ได้รับการอนุมัติ โปรดเข้าสู่ระบบเพื่อตรวจสอบ';
      v_priority := 'normal';
    when 'cancelled' then
      v_title := 'ยกเลิกใบลาแล้ว';
      v_body := 'มีการบันทึกการยกเลิกคำขอลา';
      v_priority := 'normal';
    when 'blocked' then
      v_title := 'ใบลารอการตรวจสอบ';
      v_body := 'คำขอลายังไม่ถูกส่งให้ผู้อนุมัติ เนื่องจากต้องตรวจสอบการกำหนดผู้รับผิดชอบ';
      v_priority := 'high';
    when 'overdue' then
      v_title := 'แจ้งเตือนตรวจสอบการกลับเข้าปฏิบัติงาน';
      v_body := 'มีรายการที่ถึงกำหนดกลับเข้าปฏิบัติงานและรอการตรวจสอบ';
      v_priority := 'high';
    when 'over_limit' then
      v_title := 'คำขอลาเกินเกณฑ์ที่กำหนด';
      v_body := 'มีคำขอลาที่เกินเกณฑ์ตามนโยบายกลาง โปรดตรวจสอบก่อนพิจารณา';
      v_priority := 'high';
    else
      raise exception 'unsupported_staff_leave_notification_event: %', new.event_type;
  end case;

  insert into public.notifications (
    recipient_id, document_id, type, title, body, priority
  ) values (
    new.recipient_id, null, 'staff_leave_' || new.event_type,
    v_title, v_body, v_priority
  );

  update public.staff_leave_notification_outbox
     set status = 'sent',
         sent_at = statement_timestamp(),
         last_error_code = null
   where id = new.id
     and status in ('pending','retry','processing');

  return new;
end;
$$;

create or replace function public.staff_leave_notify_over_limit()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_director uuid;
  v_vice_director uuid;
  v_recipient uuid;
begin
  if old.status = 'draft' and new.status = 'pending_approval'
     and new.is_over_limit = true then
    select director_user_id, vice_director_user_id
      into v_director, v_vice_director
    from public.staff_leave_approval_route_config
    where singleton = true and authority_verified = true;

    foreach v_recipient in array array[v_director, v_vice_director] loop
      if v_recipient is not null then
        insert into public.staff_leave_notification_outbox(
          event_key, request_id, recipient_id, event_type, channel, safe_payload, status
        ) values (
          'leave-over-limit:'||new.id::text||':'||v_recipient::text,
          new.id, v_recipient, 'over_limit', 'in_app',
          jsonb_build_object('event','leave_over_limit','request_id',new.id::text),
          'pending'
        ) on conflict (event_key) do nothing;
      end if;
    end loop;
  end if;
  return new;
end;
$$;

drop trigger if exists staff_leave_notify_over_limit
  on public.staff_leave_requests;
create trigger staff_leave_notify_over_limit
after update of status on public.staff_leave_requests
for each row execute function public.staff_leave_notify_over_limit();

revoke all on function public.staff_leave_notify_over_limit()
  from public, anon, authenticated;


-- Included in the consolidated Production release migration.
-- Returns counts only; it does not bypass request-level RLS or expose employee details.

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


-- Included in the consolidated Production release migration.

create table if not exists public.staff_leave_director_absence_evidence (
  id uuid primary key default gen_random_uuid(),
  director_user_id uuid not null references public.profiles(id),
  vice_director_user_id uuid not null references public.profiles(id),
  absence_start date not null,
  absence_end date not null,
  reason text not null,
  authority_reference text not null,
  recorded_by uuid not null references public.profiles(id),
  recorded_at timestamptz not null default statement_timestamp(),
  revoked_by uuid references public.profiles(id),
  revoked_at timestamptz,
  revocation_reason text,
  constraint staff_leave_director_absence_dates_chk check (absence_end >= absence_start),
  constraint staff_leave_director_absence_distinct_users_chk check (director_user_id <> vice_director_user_id),
  constraint staff_leave_director_absence_revocation_chk check (
    (revoked_at is null and revoked_by is null and revocation_reason is null)
    or (revoked_at is not null and revoked_by is not null and nullif(btrim(revocation_reason),'') is not null)
  )
);
create index if not exists staff_leave_director_absence_active_idx
  on public.staff_leave_director_absence_evidence(director_user_id,vice_director_user_id,absence_start,absence_end)
  where revoked_at is null;
alter table public.staff_leave_director_absence_evidence enable row level security;
revoke all on table public.staff_leave_director_absence_evidence from public,anon,authenticated;

create or replace function public.admin_record_staff_leave_director_absence(
  p_absence_start date,
  p_absence_end date,
  p_reason text,
  p_authority_reference text
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_actor uuid;
  v_route public.staff_leave_approval_route_config%rowtype;
  v_id uuid;
begin
  v_actor:=auth.uid();
  if v_actor is null then raise exception 'authentication_required' using errcode='28000'; end if;
  if not exists(select 1 from public.profiles p where p.id=v_actor and p.is_active=true) then
    raise exception 'active_profile_required' using errcode='42501';
  end if;
  if not exists(
    select 1 from public.user_roles ur join public.roles r on r.id=ur.role_id
    where ur.user_id=v_actor and r.code='system_admin'
  ) then raise exception 'system_admin_required' using errcode='42501'; end if;
  if p_absence_start is null or p_absence_end is null or p_absence_end<p_absence_start then
    raise exception 'invalid_absence_date_range' using errcode='22023';
  end if;
  if p_reason is null or length(btrim(p_reason))=0 or length(p_reason)>1000 then
    raise exception 'absence_reason_required' using errcode='22023';
  end if;
  if p_authority_reference is null or length(btrim(p_authority_reference))=0 or length(p_authority_reference)>500 then
    raise exception 'absence_authority_reference_required' using errcode='22023';
  end if;

  select * into v_route
  from public.staff_leave_approval_route_config
  where singleton=true and authority_verified=true
  for update;
  if not found or v_route.no_vice_director_confirmed
     or v_route.director_user_id is null or v_route.vice_director_user_id is null then
    raise exception 'verified_director_and_vice_assignment_required' using errcode='55000';
  end if;
  if not exists(select 1 from public.profiles p where p.id=v_route.director_user_id and p.is_active=true)
     or not exists(select 1 from public.profiles p where p.id=v_route.vice_director_user_id and p.is_active=true) then
    raise exception 'configured_approver_inactive_or_missing' using errcode='42501';
  end if;

  if exists(
    select 1 from public.staff_leave_director_absence_evidence e
    where e.director_user_id=v_route.director_user_id
      and e.vice_director_user_id=v_route.vice_director_user_id
      and e.revoked_at is null
      and daterange(e.absence_start,e.absence_end,'[]') && daterange(p_absence_start,p_absence_end,'[]')
  ) then raise exception 'overlapping_director_absence_evidence_exists' using errcode='23505'; end if;

  insert into public.staff_leave_director_absence_evidence(
    director_user_id,vice_director_user_id,absence_start,absence_end,
    reason,authority_reference,recorded_by
  ) values(
    v_route.director_user_id,v_route.vice_director_user_id,p_absence_start,p_absence_end,
    btrim(p_reason),btrim(p_authority_reference),v_actor
  ) returning id into v_id;

  update public.staff_leave_approval_route_config
     set direct_to_vice_enabled=true,updated_at=statement_timestamp()
   where singleton=true;
  return v_id;
end;
$$;

create or replace function public.admin_revoke_staff_leave_director_absence(
  p_absence_id uuid,
  p_reason text
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_actor uuid;
  v_row public.staff_leave_director_absence_evidence%rowtype;
begin
  v_actor:=auth.uid();
  if v_actor is null then raise exception 'authentication_required' using errcode='28000'; end if;
  if not exists(select 1 from public.profiles p where p.id=v_actor and p.is_active=true) then
    raise exception 'active_profile_required' using errcode='42501';
  end if;
  if not exists(
    select 1 from public.user_roles ur join public.roles r on r.id=ur.role_id
    where ur.user_id=v_actor and r.code='system_admin'
  ) then raise exception 'system_admin_required' using errcode='42501'; end if;
  if p_absence_id is null or p_reason is null or length(btrim(p_reason))=0 or length(p_reason)>1000 then
    raise exception 'absence_revocation_reason_required' using errcode='22023';
  end if;

  select * into v_row from public.staff_leave_director_absence_evidence
  where id=p_absence_id for update;
  if not found then raise exception 'absence_evidence_not_found' using errcode='P0002'; end if;
  if v_row.revoked_at is not null then return v_row.id; end if;

  update public.staff_leave_director_absence_evidence
     set revoked_by=v_actor,revoked_at=statement_timestamp(),revocation_reason=btrim(p_reason)
   where id=v_row.id;

  if not exists(
    select 1 from public.staff_leave_director_absence_evidence e
    where e.director_user_id=v_row.director_user_id
      and e.vice_director_user_id=v_row.vice_director_user_id
      and e.revoked_at is null
      and e.absence_start <= (statement_timestamp() at time zone 'Asia/Bangkok')::date
      and e.absence_end >= (statement_timestamp() at time zone 'Asia/Bangkok')::date
  ) then
    update public.staff_leave_approval_route_config
       set direct_to_vice_enabled=false,updated_at=statement_timestamp()
     where singleton=true;
  end if;
  return v_row.id;
end;
$$;

create or replace function public.admin_list_staff_leave_director_absences()
returns table(
  id uuid,
  director_user_id uuid,
  vice_director_user_id uuid,
  absence_start date,
  absence_end date,
  reason text,
  authority_reference text,
  recorded_at timestamptz,
  revoked_at timestamptz,
  revocation_reason text
)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare v_actor uuid;
begin
  v_actor:=auth.uid();
  if v_actor is null then raise exception 'authentication_required' using errcode='28000'; end if;
  if not exists(select 1 from public.profiles p where p.id=v_actor and p.is_active=true) then
    raise exception 'active_profile_required' using errcode='42501';
  end if;
  if not exists(
    select 1 from public.user_roles ur join public.roles r on r.id=ur.role_id
    where ur.user_id=v_actor and r.code='system_admin'
  ) then raise exception 'system_admin_required' using errcode='42501'; end if;
  return query
    select e.id,e.director_user_id,e.vice_director_user_id,e.absence_start,e.absence_end,
           e.reason,e.authority_reference,e.recorded_at,e.revoked_at,e.revocation_reason
    from public.staff_leave_director_absence_evidence e
    order by e.recorded_at desc
    limit 30;
end;
$$;

revoke all on function public.admin_record_staff_leave_director_absence(date,date,text,text) from public,anon;
grant execute on function public.admin_record_staff_leave_director_absence(date,date,text,text) to authenticated;
revoke all on function public.admin_list_staff_leave_director_absences() from public,anon;
grant execute on function public.admin_list_staff_leave_director_absences() to authenticated;
revoke all on function public.admin_revoke_staff_leave_director_absence(uuid,text) from public,anon;
grant execute on function public.admin_revoke_staff_leave_director_absence(uuid,text) to authenticated;

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
  v_snapshot_director uuid;
  v_snapshot_vice uuid;
  v_snapshot_kind text;
  v_snapshot_authority_reference text;
  v_action text;
  v_key text;
  v_event_key text;
  v_prior_reason text;
  v_absence_id uuid;
  v_absence_reference text;
  v_absence_start date;
  v_absence_end date;
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

  -- In-flight decisions must use the immutable route captured at submission,
  -- never the mutable singleton configuration for later requests.
  v_snapshot_kind := v_request.approval_route_snapshot->>'route_kind';
  v_snapshot_director := nullif(v_request.approval_route_snapshot->>'director_user_id','')::uuid;
  v_snapshot_vice := nullif(v_request.approval_route_snapshot->>'vice_director_user_id','')::uuid;
  v_snapshot_authority_reference := v_request.approval_route_snapshot->>'authority_reference';

  if v_snapshot_kind not in ('vice_director_then_director','director_only_confirmed_no_vice')
     or v_snapshot_director is null
     or nullif(v_snapshot_authority_reference,'') is null
     or nullif(v_request.approval_route_snapshot->>'authority_verified_by','') is null
     or nullif(v_request.approval_route_snapshot->>'authority_verified_at','') is null then
    raise exception 'approver_authority_unverified' using errcode = '42501';
  end if;
  if not exists (select 1 from public.profiles p where p.id=v_snapshot_director and p.is_active=true)
     or (v_snapshot_kind='vice_director_then_director' and
       (v_snapshot_vice is null or not exists(
         select 1 from public.profiles p where p.id=v_snapshot_vice and p.is_active=true
       )))
     or (v_snapshot_kind='director_only_confirmed_no_vice' and v_snapshot_vice is not null) then
    raise exception 'configured_approver_inactive_or_missing' using errcode = '42501';
  end if;

  if p_decision = 'reject' then
    -- The Deputy Director may review and forward only; final rejection belongs
    -- exclusively to the Director at the director_final_review stage.
    if v_request.approval_stage <> 'director_final_review'
       or v_actor <> v_snapshot_director
       or v_request.current_approver_user_id is distinct from v_actor then
      raise exception 'leave_request_not_found_or_not_assigned' using errcode = '42501';
    end if;
    v_action := 'rejected';
    update public.staff_leave_requests set status='rejected', approval_stage='completed',
      decided_at=statement_timestamp(), updated_at=statement_timestamp() where id=v_request.id;
  else
    if v_request.approval_stage = 'vice_director_review' then
      if v_snapshot_vice is null or v_actor <> v_snapshot_vice
         or v_request.current_approver_user_id is distinct from v_actor then
        raise exception 'leave_request_not_found_or_not_assigned' using errcode = '42501';
      end if;
      -- Direct Vice Director approval is permitted only when a System Admin
      -- recorded an active, date-bounded absence evidence record for this Director.
      select e.id,e.authority_reference,e.absence_start,e.absence_end
        into v_absence_id,v_absence_reference,v_absence_start,v_absence_end
      from public.staff_leave_director_absence_evidence e
      where e.director_user_id=v_snapshot_director
        and e.vice_director_user_id=v_actor
        and e.revoked_at is null
        and e.absence_start <= (statement_timestamp() at time zone 'Asia/Bangkok')::date
        and e.absence_end >= (statement_timestamp() at time zone 'Asia/Bangkok')::date
      order by e.recorded_at desc
      limit 1;
      if found then
        v_action := 'approved';
        update public.staff_leave_requests
           set status='approved',approval_stage='completed',
               current_approver_user_id=null,
               decided_at=statement_timestamp(),updated_at=statement_timestamp()
         where id=v_request.id;

        insert into public.staff_leave_approval_actions(request_id,actor_id,action,reason,metadata)
        values(v_request.id,v_actor,'approved',nullif(btrim(coalesce(p_reason,'')),''),
          jsonb_build_object(
            'idempotency_key',v_key,
            'decision','approve',
            'stage','vice_director_review',
            'director_absence_override',true,
            'absence_evidence_id',v_absence_id,
            'absence_authority_reference',v_absence_reference,
            'absence_start',v_absence_start,
            'absence_end',v_absence_end
          ));

        v_event_key := 'leave-decision:'||v_request.id::text||':approved:'||v_key;
        insert into public.staff_leave_notification_outbox(
          event_key,request_id,recipient_id,event_type,channel,safe_payload,status
        ) values(
          v_event_key,v_request.id,v_request.applicant_id,'approved','in_app',
          jsonb_build_object('event','leave_approved','request_id',v_request.id::text),
          'pending'
        ) on conflict(event_key) do nothing;
        return v_request.id;
      end if;

      update public.staff_leave_requests set approval_stage='director_final_review',
        current_approver_user_id=v_snapshot_director, updated_at=statement_timestamp()
        where id=v_request.id;
      insert into public.staff_leave_approval_actions(request_id,actor_id,action,reason,metadata)
      values(v_request.id,v_actor,'routed',nullif(btrim(coalesce(p_reason,'')),''),
        jsonb_build_object('idempotency_key',v_key,'decision','approve',
          'from_stage','vice_director_review','to_stage','director_final_review',
          'next_approver_id',v_snapshot_director));
      insert into public.staff_leave_notification_outbox(event_key,request_id,recipient_id,event_type,channel,safe_payload,status)
      values('leave-stage-advance:'||v_request.id::text||':'||v_key,v_request.id,v_snapshot_director,
        'approver_assigned','in_app',jsonb_build_object('event','leave_approver_assigned',
        'request_id',v_request.id::text,'stage','director_final_review'),'pending')
      on conflict(event_key) do nothing;
      return v_request.id;
    elsif v_request.approval_stage = 'director_final_review' then
      if v_actor <> v_snapshot_director
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

revoke all on function public.staff_leave_decide(uuid,text,text,text) from public,anon;
grant execute on function public.staff_leave_decide(uuid,text,text,text) to authenticated;


-- Included in the consolidated Production release migration.
-- Production must remain untouched until isolated PostgreSQL replay and CI pass.

alter table public.staff_leave_requests
  add column if not exists childbirth_event_date date;

alter table public.staff_leave_attachments
  add column if not exists attachment_kind text not null default 'supporting_document';

-- Server-controlled evidence that the private Storage upload was verified.
-- No client write policy exists; the future upload backend must set these only
-- after confirming the object in the private bucket. Null means unverified.
alter table public.staff_leave_attachments
  add column if not exists storage_bucket_id text;
alter table public.staff_leave_attachments
  add column if not exists storage_verified_at timestamptz;
comment on column public.staff_leave_attachments.storage_verified_at is
  'Set only by trusted upload backend after verifying the private Storage object; null is unverified.';

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
  v_max_days numeric(7,2);
  v_is_over_limit boolean := false;
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
    if nullif(v_type_rules->>'max_days_per_request','') is not null then
      v_max_days := (v_type_rules->>'max_days_per_request')::numeric;
      v_is_over_limit := v_day_count > v_max_days;
    end if;
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
    day_count,is_over_limit,reason,policy_snapshot,status,childbirth_event_date
  ) values (
    v_actor,p_leave_type_id,v_policy_id,p_starts_on,p_ends_on,
    v_day_count,v_is_over_limit,btrim(p_reason),v_policy_snapshot,'draft',p_childbirth_event_date
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
        and a.storage_bucket_id='staff-leave-private'
        and a.storage_verified_at is not null
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


-- Included in the consolidated Production release migration.
-- Apply only in isolated Integration/CI until the full Production release gate passes.
-- Objects are private, request-scoped, and readable only by the applicant or current approver.

do $preflight$
begin
  if to_regclass('storage.buckets') is null or to_regclass('storage.objects') is null then
    raise exception 'staff_leave_private_storage_requires_supabase_storage_schema';
  end if;
  if to_regclass('public.staff_leave_attachments') is null
     or to_regclass('public.staff_leave_requests') is null then
    raise exception 'staff_leave_private_storage_requires_leave_schema';
  end if;
  if not has_table_privilege('authenticated','storage.objects','INSERT')
     or not has_table_privilege('authenticated','storage.objects','SELECT') then
    raise exception 'staff_leave_private_storage_requires_authenticated_storage_object_api_grants';
  end if;
  if exists (
    select 1 from storage.buckets
    where id='staff-leave-private'
      and (public is distinct from false
        or file_size_limit is distinct from 20971520
        or allowed_mime_types is distinct from array[
          'application/pdf','image/jpeg','image/png'
        ]::text[])
  ) then
    raise exception 'staff_leave_private_bucket_exists_with_unexpected_settings';
  end if;
end;
$preflight$;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values(
  'staff-leave-private',
  'staff-leave-private',
  false,
  20971520,
  array['application/pdf','image/jpeg','image/png']::text[]
)
on conflict(id) do nothing;

-- The first path segment is the request UUID; the second is a generated
-- attachment UUID. No user-controlled filename is used as an object key.
drop policy if exists staff_leave_private_objects_insert_owner
  on storage.objects;
create policy staff_leave_private_objects_insert_owner
on storage.objects for insert to authenticated
with check (
  bucket_id='staff-leave-private'
  and name ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  and exists (
    select 1
    from public.staff_leave_requests r
    join public.profiles p on p.id=r.applicant_id
    where r.id::text=split_part(storage.objects.name,'/',1)
      and r.applicant_id=(select auth.uid())
      and r.status='draft'
      and p.is_active=true
  )
);

drop policy if exists staff_leave_private_objects_select_parties
  on storage.objects;
create policy staff_leave_private_objects_select_parties
on storage.objects for select to authenticated
using (
  bucket_id='staff-leave-private'
  and name ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  and exists (
    select 1
    from public.staff_leave_requests r
    join public.profiles p on p.id=(select auth.uid()) and p.is_active=true
    where r.id::text=split_part(name,'/',1)
      and (
        r.applicant_id=(select auth.uid())
        or r.current_approver_user_id=(select auth.uid())
      )
  )
);

create or replace function public.staff_leave_register_private_attachment(
  p_request_id uuid,
  p_object_key text,
  p_original_filename text,
  p_mime_type text,
  p_size_bytes bigint,
  p_attachment_kind text default 'supporting_document'
)
returns uuid
language plpgsql
security definer
set search_path=pg_catalog,public,storage
as $$
declare
  v_actor uuid;
  v_request public.staff_leave_requests%rowtype;
  v_object storage.objects%rowtype;
  v_attachment_id uuid;
begin
  v_actor:=auth.uid();
  if v_actor is null then
    raise exception 'authentication_required' using errcode='28000';
  end if;
  if not exists(select 1 from public.profiles p where p.id=v_actor and p.is_active=true) then
    raise exception 'active_profile_required' using errcode='42501';
  end if;
  if p_request_id is null
     or p_object_key is null
     or p_object_key !~* ('^'||p_request_id::text||'/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') then
    raise exception 'invalid_staff_leave_object_key' using errcode='22023';
  end if;
  if p_original_filename is null or length(btrim(p_original_filename))=0
     or length(p_original_filename)>255 or p_original_filename ~ '[[:cntrl:]/\\]' then
    raise exception 'invalid_staff_leave_filename' using errcode='22023';
  end if;
  if p_mime_type not in ('application/pdf','image/jpeg','image/png')
     or p_size_bytes is null or p_size_bytes<1 or p_size_bytes>20971520 then
    raise exception 'invalid_staff_leave_file_type_or_size' using errcode='22023';
  end if;
  if p_attachment_kind not in ('supporting_document','medical_certificate','childbirth_evidence') then
    raise exception 'invalid_staff_leave_attachment_kind' using errcode='22023';
  end if;

  select * into v_request
  from public.staff_leave_requests r
  where r.id=p_request_id and r.applicant_id=v_actor
  for update;
  if not found then
    raise exception 'leave_request_not_found_or_not_owner' using errcode='42501';
  end if;
  if v_request.status<>'draft' then
    raise exception 'attachments_may_only_be_added_to_draft_requests' using errcode='55000';
  end if;

  select * into v_object
  from storage.objects o
  where o.bucket_id='staff-leave-private' and o.name=p_object_key;
  if not found
     or coalesce(v_object.metadata->>'mimetype','')<>p_mime_type
     or coalesce(v_object.metadata->>'size','') !~ '^[0-9]+$'
     or (v_object.metadata->>'size')::bigint<>p_size_bytes then
    raise exception 'private_storage_object_not_found_or_metadata_mismatch' using errcode='23514';
  end if;

  insert into public.staff_leave_attachments(
    request_id,uploaded_by,storage_object_key,original_filename,
    mime_type,size_bytes,attachment_kind,storage_bucket_id,storage_verified_at
  ) values (
    p_request_id,v_actor,p_object_key,btrim(p_original_filename),
    p_mime_type,p_size_bytes,p_attachment_kind,'staff-leave-private',statement_timestamp()
  ) returning id into v_attachment_id;

  return v_attachment_id;
end;
$$;

revoke all on function public.staff_leave_register_private_attachment(
  uuid,text,text,text,bigint,text
) from public,anon;
grant execute on function public.staff_leave_register_private_attachment(
  uuid,text,text,text,bigint,text
) to authenticated;

comment on table public.staff_leave_attachments is
  'Private staff-leave attachment metadata. Objects are stored only in the non-public staff-leave-private bucket; storage_verified_at is set by the registration RPC after checking the uploaded object metadata.';
comment on function public.staff_leave_register_private_attachment(
  uuid,text,text,text,bigint,text
) is
  'Registers an already-uploaded private Storage object for the authenticated applicant; validates request ownership, draft state, key, MIME type, byte size, and actual Storage object metadata.';

COMMIT;
