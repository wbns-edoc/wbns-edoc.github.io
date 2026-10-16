create table if not exists public.document_assignment_reports (
  id uuid primary key default gen_random_uuid(),
  assignment_id uuid not null references public.document_assignments(id) on delete cascade,
  created_by uuid not null references public.profiles(id) on delete restrict default auth.uid(),
  report_type text not null default 'progress' check (report_type in ('progress','completion')),
  percent_complete integer not null default 0 check (percent_complete between 0 and 100),
  result_summary text not null check (length(btrim(result_summary)) between 3 and 5000),
  work_details text,
  issues text,
  next_steps text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists document_assignment_reports_assignment_created_idx
  on public.document_assignment_reports (assignment_id, created_at desc);

alter table public.document_assignment_reports enable row level security;

drop policy if exists assignment_reports_select_participants on public.document_assignment_reports;
create policy assignment_reports_select_participants
on public.document_assignment_reports
for select to authenticated
using (
  created_by = (select auth.uid())
  or exists (
    select 1 from public.document_assignments a
    join public.documents d on d.id = a.document_id
    where a.id = document_assignment_reports.assignment_id
      and (a.assignee_id = (select auth.uid()) or a.assigned_by = (select auth.uid()))
      and private.can_access_document(d.id)
  )
);

drop policy if exists assignment_reports_insert_assignee on public.document_assignment_reports;
create policy assignment_reports_insert_assignee
on public.document_assignment_reports
for insert to authenticated
with check (
  created_by = (select auth.uid())
  and exists (
    select 1 from public.document_assignments a
    join public.documents d on d.id = a.document_id
    where a.id = document_assignment_reports.assignment_id
      and a.assignee_id = (select auth.uid())
      and private.can_access_document(d.id)
  )
);

drop policy if exists assignment_reports_update_author on public.document_assignment_reports;
create policy assignment_reports_update_author
on public.document_assignment_reports
for update to authenticated
using (
  created_by = (select auth.uid())
  and exists (
    select 1 from public.document_assignments a
    join public.documents d on d.id = a.document_id
    where a.id = document_assignment_reports.assignment_id
      and a.assignee_id = (select auth.uid())
      and private.can_access_document(d.id)
  )
)
with check (
  created_by = (select auth.uid())
  and exists (
    select 1 from public.document_assignments a
    join public.documents d on d.id = a.document_id
    where a.id = document_assignment_reports.assignment_id
      and a.assignee_id = (select auth.uid())
      and private.can_access_document(d.id)
  )
);

revoke all on public.document_assignment_reports from anon;
grant select, insert, update on public.document_assignment_reports to authenticated;

drop trigger if exists trg_assignment_reports_set_updated_at on public.document_assignment_reports;
create trigger trg_assignment_reports_set_updated_at
before update on public.document_assignment_reports
for each row execute function public.set_updated_at();
