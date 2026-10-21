-- Draft-only additive schema for the Wat Bueng Nam Sai School staff leave workflow.
-- Do not apply to Production. RPCs, grants, isolated migration replay, and RLS tests
-- must be implemented and reviewed before this migration can be considered release-ready.
-- Leave policy versions are school-wide: personnel category is NOT an entitlement key.
begin;

create table if not exists public.staff_leave_types (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  description text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

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
as $
begin
  raise exception 'staff_leave_approval_actions is append-only'
    using errcode = '55000';
end;
$;

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

-- Outbox intentionally has no authenticated SELECT policy: delivery state/payloads
-- are backend internals and must not be exposed to browser clients.
commit;
