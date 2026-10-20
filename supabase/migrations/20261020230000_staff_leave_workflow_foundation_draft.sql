-- STAFF LEAVE WORKFLOW FOUNDATION
-- Draft only: review against current schema and test before applying anywhere.
-- This migration is intentionally additive and does not seed legal entitlements.
-- Approval rules confirmed by school:
--   normal: deputy director review -> director final approval
--   when director is absent: deputy director may approve directly
--   cancellation deadline: at least one calendar day before leave start (Asia/Bangkok)
--
-- DO NOT apply to Production until the complete workflow RPCs, RLS tests,
-- policy/legal verification, and rollback plan are reviewed.

begin;

create table if not exists public.personnel_categories (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  is_active boolean not null default true,
  effective_from date,
  effective_until date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint personnel_categories_effective_dates_chk
    check (effective_until is null or effective_from is null or effective_until >= effective_from)
);

create table if not exists public.leave_types (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  description text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.leave_policy_versions (
  id uuid primary key default gen_random_uuid(),
  personnel_category_id uuid not null references public.personnel_categories(id),
  leave_type_id uuid not null references public.leave_types(id),
  version integer not null check (version > 0),
  status text not null default 'draft'
    check (status in ('draft','review','approved','retired')),
  effective_from date,
  effective_until date,
  policy_source text,
  source_page text,
  reviewed_by uuid references public.profiles(id),
  reviewed_at timestamptz,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  constraint leave_policy_versions_unique unique(personnel_category_id, leave_type_id, version),
  constraint leave_policy_versions_dates_chk
    check (effective_until is null or effective_from is null or effective_until >= effective_from),
  constraint leave_policy_versions_review_chk
    check (status <> 'approved' or (reviewed_by is not null and reviewed_at is not null))
);

create table if not exists public.leave_requests (
  id uuid primary key default gen_random_uuid(),
  applicant_id uuid not null references public.profiles(id),
  personnel_category_id uuid not null references public.personnel_categories(id),
  leave_type_id uuid not null references public.leave_types(id),
  policy_version_id uuid references public.leave_policy_versions(id),
  starts_on date not null,
  ends_on date not null,
  reason text not null,
  status text not null default 'draft'
    check (status in ('draft','submitted','deputy_review','director_review','approved','rejected','cancelled','withdrawn')),
  deputy_director_id uuid references public.profiles(id),
  deputy_decided_at timestamptz,
  deputy_decision text check (deputy_decision in ('approved','rejected','returned')),
  director_id uuid references public.profiles(id),
  director_decided_at timestamptz,
  director_decision text check (director_decision in ('approved','rejected','returned')),
  director_absent_override boolean not null default false,
  director_absent_reason text,
  cancellation_requested_at timestamptz,
  cancellation_reason text,
  cancelled_by uuid references public.profiles(id),
  cancelled_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint leave_requests_date_range_chk check (ends_on >= starts_on),
  constraint leave_requests_director_absence_reason_chk
    check (not director_absent_override or nullif(btrim(director_absent_reason), '') is not null),
  constraint leave_requests_cancel_fields_chk
    check (status <> 'cancelled' or (cancelled_by is not null and cancelled_at is not null))
);

create index if not exists leave_requests_applicant_created_idx
  on public.leave_requests(applicant_id, created_at desc);
create index if not exists leave_requests_status_dates_idx
  on public.leave_requests(status, starts_on, ends_on);
create index if not exists leave_policy_versions_lookup_idx
  on public.leave_policy_versions(personnel_category_id, leave_type_id, status, effective_from);

create table if not exists public.leave_approval_actions (
  id uuid primary key default gen_random_uuid(),
  leave_request_id uuid not null references public.leave_requests(id) on delete restrict,
  actor_id uuid not null references public.profiles(id),
  action text not null check (action in (
    'submitted','deputy_approved','deputy_rejected','sent_to_director',
    'director_approved','director_rejected','deputy_approved_directly',
    'cancellation_requested','cancelled','cancellation_rejected','withdrawn','returned'
  )),
  reason text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists leave_approval_actions_request_time_idx
  on public.leave_approval_actions(leave_request_id, created_at);

alter table public.personnel_categories enable row level security;
alter table public.leave_types enable row level security;
alter table public.leave_policy_versions enable row level security;
alter table public.leave_requests enable row level security;
alter table public.leave_approval_actions enable row level security;

-- Policies intentionally deny ordinary direct writes. Read access is limited
-- to the applicant and the two school approver roles; state transitions must
-- be implemented through reviewed SECURITY DEFINER RPCs before rollout.
drop policy if exists leave_requests_select_applicant_or_approver on public.leave_requests;
create policy leave_requests_select_applicant_or_approver
on public.leave_requests for select to authenticated
using (
  applicant_id = (select auth.uid())
  or exists (
    select 1
    from public.user_roles ur
    join public.roles r on r.id = ur.role_id
    join public.profiles p on p.id = ur.user_id and p.is_active = true
    where ur.user_id = (select auth.uid())
      and r.code in ('director','deputy_director')
  )
);

drop policy if exists leave_approval_actions_select_applicant_or_approver on public.leave_approval_actions;
create policy leave_approval_actions_select_applicant_or_approver
on public.leave_approval_actions for select to authenticated
using (
  exists (
    select 1 from public.leave_requests lr
    where lr.id = leave_request_id
      and (
        lr.applicant_id = (select auth.uid())
        or exists (
          select 1
          from public.user_roles ur
          join public.roles r on r.id = ur.role_id
          join public.profiles p on p.id = ur.user_id and p.is_active = true
          where ur.user_id = (select auth.uid())
            and r.code in ('director','deputy_director')
        )
      )
  )
);

-- No direct INSERT/UPDATE/DELETE policies are created for workflow data.
-- Explicit grants/RPCs must be added only with corresponding security tests.
commit;
