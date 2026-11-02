-- RECOVERED SOURCE ARCHIVE — NOT A NEW MIGRATION
-- Source: read-only extraction of supabase_migrations.schema_migrations.statements
-- Production project: iigzzwyfxxtqbgjawyom
-- Recorded version: 20261007133831
-- Recorded name: foundation_schema_rbac_rls
-- Statement count in source history: 1
-- Extracted SQL character count: 26133
-- Do not place this file in supabase/migrations or replay it against Production.
-- Preserve exact source text below; validate against a disposable PostgreSQL 17 fixture first.

-- WBNS Electronic Document System
-- Foundation migration: identity, RBAC, documents, workflow, notifications, audit, RLS

create extension if not exists pgcrypto;

create type public.document_type as enum ('incoming','outgoing');
create type public.urgency_level as enum ('normal','urgent','very_urgent','critical');
create type public.document_status as enum ('draft','pending_approval','approved','received','registered','assigned','in_progress','completed','archived','sent','cancelled');
create type public.approval_decision as enum ('pending','approved','rejected','returned');
create type public.assignment_status as enum ('assigned','accepted','in_progress','completed','cancelled');

create table public.departments (
  id uuid primary key default gen_random_uuid(),
  parent_id uuid references public.departments(id) on delete restrict,
  code text not null unique,
  name text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.profiles (
  id uuid primary key references auth.users(id) on delete restrict,
  employee_code text unique,
  full_name text not null,
  email text,
  phone text,
  department_id uuid references public.departments(id) on delete restrict,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.roles (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  description text,
  created_at timestamptz not null default now()
);

create table public.permissions (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  description text,
  created_at timestamptz not null default now()
);

create table public.user_roles (
  user_id uuid not null references public.profiles(id) on delete restrict,
  role_id uuid not null references public.roles(id) on delete restrict,
  assigned_at timestamptz not null default now(),
  assigned_by uuid references public.profiles(id) on delete restrict,
  primary key (user_id, role_id)
);

create table public.role_permissions (
  role_id uuid not null references public.roles(id) on delete cascade,
  permission_id uuid not null references public.permissions(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (role_id, permission_id)
);

create table public.document_registers (
  id uuid primary key default gen_random_uuid(),
  code text not null,
  name text not null,
  direction public.document_type not null,
  document_year integer not null check (document_year between 2000 and 2200),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (direction, document_year),
  unique (code, document_year)
);

create table public.number_sequences (
  id uuid primary key default gen_random_uuid(),
  register_id uuid not null references public.document_registers(id) on delete restrict,
  year integer not null check (year between 2000 and 2200),
  prefix text,
  current_number bigint not null default 0 check (current_number >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (register_id, year)
);

create table public.senders (
  id uuid primary key default gen_random_uuid(),
  organization_name text not null,
  department_name text,
  address text,
  contact_name text,
  contact_phone text,
  contact_email text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.documents (
  id uuid primary key default gen_random_uuid(),
  document_type public.document_type not null,
  register_id uuid references public.document_registers(id) on delete restrict,
  subject text not null,
  urgency public.urgency_level not null default 'normal',
  status public.document_status not null default 'draft',
  current_owner_id uuid references public.profiles(id) on delete restrict,
  created_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.incoming_document_details (
  document_id uuid primary key references public.documents(id) on delete restrict,
  sender_id uuid not null references public.senders(id) on delete restrict,
  external_document_no text,
  external_document_date date,
  received_at timestamptz,
  registered_at timestamptz,
  registered_number bigint,
  receiving_notes text
);

create table public.outgoing_document_details (
  document_id uuid primary key references public.documents(id) on delete restrict,
  outgoing_document_no text,
  document_date date,
  recipient_name text not null,
  recipient_address text,
  recipient_contact text,
  sent_at timestamptz,
  registered_number bigint
);

create table public.document_assignments (
  id uuid primary key default gen_random_uuid(),
  document_id uuid not null references public.documents(id) on delete restrict,
  assignee_id uuid not null references public.profiles(id) on delete restrict,
  assigned_by uuid not null references public.profiles(id) on delete restrict,
  assigned_at timestamptz not null default now(),
  accepted_at timestamptz,
  completed_at timestamptz,
  instructions text,
  assignment_status public.assignment_status not null default 'assigned'
);

create table public.document_status_history (
  id uuid primary key default gen_random_uuid(),
  document_id uuid not null references public.documents(id) on delete restrict,
  from_status public.document_status,
  to_status public.document_status not null,
  changed_by uuid references public.profiles(id) on delete restrict,
  changed_at timestamptz not null default now(),
  reason text
);

create table public.approvals (
  id uuid primary key default gen_random_uuid(),
  document_id uuid not null references public.documents(id) on delete restrict,
  approval_step integer not null check (approval_step > 0),
  approver_id uuid not null references public.profiles(id) on delete restrict,
  decision public.approval_decision not null default 'pending',
  decided_at timestamptz,
  comment text,
  created_at timestamptz not null default now(),
  unique (document_id, approval_step)
);

create table public.deadlines (
  id uuid primary key default gen_random_uuid(),
  document_id uuid not null references public.documents(id) on delete restrict,
  assigned_to uuid references public.profiles(id) on delete restrict,
  due_at timestamptz not null,
  reminder_at timestamptz,
  escalation_at timestamptz,
  completed_at timestamptz,
  status text not null default 'open' check (status in ('open','completed','overdue','cancelled')),
  created_at timestamptz not null default now()
);

create table public.comments (
  id uuid primary key default gen_random_uuid(),
  document_id uuid not null references public.documents(id) on delete restrict,
  author_id uuid not null references public.profiles(id) on delete restrict,
  body text not null,
  created_at timestamptz not null default now(),
  edited_at timestamptz
);

create table public.google_drive_files (
  id uuid primary key default gen_random_uuid(),
  drive_file_id text not null unique,
  drive_url text,
  name text not null,
  mime_type text,
  size_bytes bigint,
  checksum text,
  folder_id text,
  created_by uuid references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now()
);

create table public.document_files (
  id uuid primary key default gen_random_uuid(),
  document_id uuid not null references public.documents(id) on delete restrict,
  google_drive_file_id uuid not null references public.google_drive_files(id) on delete restrict,
  file_role text not null default 'attachment',
  version_no integer not null default 1 check (version_no > 0),
  is_current boolean not null default true,
  uploaded_by uuid references public.profiles(id) on delete restrict,
  uploaded_at timestamptz not null default now(),
  unique (document_id, google_drive_file_id)
);

create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  recipient_id uuid not null references public.profiles(id) on delete restrict,
  document_id uuid references public.documents(id) on delete restrict,
  type text not null,
  title text not null,
  body text not null,
  priority text not null default 'normal' check (priority in ('normal','high','critical')),
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete restrict,
  endpoint text not null unique,
  p256dh text not null,
  auth text not null,
  user_agent text,
  created_at timestamptz not null default now(),
  revoked_at timestamptz
);

create table public.audit_logs (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid references public.profiles(id) on delete restrict,
  action text not null,
  entity_type text not null,
  entity_id uuid,
  old_data jsonb,
  new_data jsonb,
  request_id text,
  created_at timestamptz not null default now()
);

create index idx_profiles_department on public.profiles(department_id);
create index idx_user_roles_role on public.user_roles(role_id);
create index idx_role_permissions_permission on public.role_permissions(permission_id);
create index idx_documents_status on public.documents(status);
create index idx_documents_urgency on public.documents(urgency);
create index idx_documents_owner on public.documents(current_owner_id);
create index idx_documents_created_at on public.documents(created_at desc);
create index idx_documents_subject on public.documents using gin (to_tsvector('simple', subject));
create index idx_incoming_sender on public.incoming_document_details(sender_id);
create index idx_incoming_external_no on public.incoming_document_details(external_document_no);
create index idx_incoming_registered_no on public.incoming_document_details(registered_number);
create index idx_outgoing_registered_no on public.outgoing_document_details(registered_number);
create index idx_assignments_assignee_status on public.document_assignments(assignee_id, assignment_status);
create index idx_assignments_document on public.document_assignments(document_id);
create index idx_status_history_document on public.document_status_history(document_id, changed_at desc);
create index idx_approvals_approver_decision on public.approvals(approver_id, decision);
create index idx_deadlines_due on public.deadlines(due_at) where status = 'open';
create index idx_notifications_recipient_unread on public.notifications(recipient_id, created_at desc) where read_at is null;
create index idx_audit_entity on public.audit_logs(entity_type, entity_id, created_at desc);

create or replace function public.has_permission(p_permission text)
returns boolean
language sql
security definer
set search_path = pg_catalog, public
stable
as $$
  select exists (
    select 1
    from public.user_roles ur
    join public.role_permissions rp on rp.role_id = ur.role_id
    join public.permissions p on p.id = rp.permission_id
    join public.profiles pr on pr.id = ur.user_id
    where ur.user_id = auth.uid()
      and pr.is_active = true
      and p.code = p_permission
  );
$$;

create or replace function public.is_admin()
returns boolean
language sql
security definer
set search_path = pg_catalog, public
stable
as $$
  select public.has_permission('settings.manage');
$$;

create or replace function public.allocate_document_number(p_register_id uuid, p_year integer)
returns bigint
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_number bigint;
begin
  if not public.has_permission('registry.incoming.manage') and not public.has_permission('registry.outgoing.manage') then
    raise exception 'permission denied';
  end if;
  insert into public.number_sequences(register_id, year, current_number)
  values (p_register_id, p_year, 0)
  on conflict (register_id, year) do nothing;
  update public.number_sequences
     set current_number = current_number + 1,
         updated_at = now()
   where register_id = p_register_id and year = p_year
   returning current_number into v_number;
  return v_number;
end;
$$;

revoke all on function public.allocate_document_number(uuid, integer) from public;
grant execute on function public.allocate_document_number(uuid, integer) to authenticated;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger departments_updated_at before update on public.departments for each row execute function public.set_updated_at();
create trigger profiles_updated_at before update on public.profiles for each row execute function public.set_updated_at();
create trigger senders_updated_at before update on public.senders for each row execute function public.set_updated_at();
create trigger documents_updated_at before update on public.documents for each row execute function public.set_updated_at();
create trigger number_sequences_updated_at before update on public.number_sequences for each row execute function public.set_updated_at();

insert into public.roles(code,name,description) values
('system_admin','System Admin','Technical system administration'),
('school_admin','School Admin','School administration'),
('director','Director','Director oversight and approval'),
('deputy_director','Deputy Director','Deputy director oversight and approval'),
('registry_officer','Registry Officer','Correspondence registry operations'),
('teacher','Teacher','Teaching staff'),
('staff','Staff','School staff')
on conflict (code) do nothing;

insert into public.permissions(code,name,description) values
('dashboard.view','View Dashboard','View dashboard'),
('user.view','View Users','View users'),
('user.manage','Manage Users','Create/update/deactivate users'),
('role.manage','Manage Roles','Manage roles and permissions'),
('registry.incoming.manage','Manage Incoming Registry','Receive/register incoming correspondence'),
('registry.outgoing.manage','Manage Outgoing Registry','Prepare/register outgoing correspondence'),
('document.view','View Documents','Read authorized documents'),
('document.create','Create Documents','Create documents'),
('document.update','Update Documents','Update authorized documents'),
('document.assign','Assign Documents','Assign/reassign work'),
('document.approve','Approve Documents','Approve authorized documents'),
('document.complete','Complete Documents','Complete assigned work'),
('document.archive','Archive Documents','Archive documents'),
('report.view','View Reports','View reports'),
('audit.view','View Audit Logs','View audit logs'),
('settings.manage','Manage Settings','Manage school settings')
on conflict (code) do nothing;

insert into public.role_permissions(role_id,permission_id)
select r.id,p.id from public.roles r cross join public.permissions p
where r.code='system_admin'
on conflict do nothing;

insert into public.role_permissions(role_id,permission_id)
select r.id,p.id from public.roles r join public.permissions p on p.code in
('dashboard.view','user.view','user.manage','role.manage','report.view','settings.manage')
where r.code='school_admin'
on conflict do nothing;

insert into public.role_permissions(role_id,permission_id)
select r.id,p.id from public.roles r join public.permissions p on p.code in
('dashboard.view','document.view','document.approve','report.view')
where r.code in ('director','deputy_director')
on conflict do nothing;

insert into public.role_permissions(role_id,permission_id)
select r.id,p.id from public.roles r join public.permissions p on p.code in
('dashboard.view','registry.incoming.manage','registry.outgoing.manage','document.view','document.create','document.update','document.assign','document.complete','document.archive','report.view')
where r.code='registry_officer'
on conflict do nothing;

insert into public.role_permissions(role_id,permission_id)
select r.id,p.id from public.roles r join public.permissions p on p.code in
('dashboard.view','document.view','document.update','document.complete')
where r.code in ('teacher','staff')
on conflict do nothing;

alter table public.departments enable row level security;
alter table public.profiles enable row level security;
alter table public.roles enable row level security;
alter table public.permissions enable row level security;
alter table public.user_roles enable row level security;
alter table public.role_permissions enable row level security;
alter table public.document_registers enable row level security;
alter table public.number_sequences enable row level security;
alter table public.senders enable row level security;
alter table public.documents enable row level security;
alter table public.incoming_document_details enable row level security;
alter table public.outgoing_document_details enable row level security;
alter table public.document_assignments enable row level security;
alter table public.document_status_history enable row level security;
alter table public.approvals enable row level security;
alter table public.deadlines enable row level security;
alter table public.comments enable row level security;
alter table public.google_drive_files enable row level security;
alter table public.document_files enable row level security;
alter table public.notifications enable row level security;
alter table public.push_subscriptions enable row level security;
alter table public.audit_logs enable row level security;

create policy profiles_select_self_or_admin on public.profiles for select to authenticated
using (id = auth.uid() or public.has_permission('user.view'));
create policy profiles_update_self_or_admin on public.profiles for update to authenticated
using (id = auth.uid() or public.has_permission('user.manage'))
with check (id = auth.uid() or public.has_permission('user.manage'));

create policy roles_select_authenticated on public.roles for select to authenticated
using (true);
create policy roles_manage_admin on public.roles for all to authenticated
using (public.has_permission('role.manage'))
with check (public.has_permission('role.manage'));

create policy permissions_select_authenticated on public.permissions for select to authenticated using (true);
create policy permissions_manage_admin on public.permissions for all to authenticated
using (public.has_permission('role.manage'))
with check (public.has_permission('role.manage'));

create policy user_roles_select_self_or_admin on public.user_roles for select to authenticated
using (user_id = auth.uid() or public.has_permission('user.view'));
create policy user_roles_manage_admin on public.user_roles for all to authenticated
using (public.has_permission('role.manage')) with check (public.has_permission('role.manage'));

create policy role_permissions_select_authenticated on public.role_permissions for select to authenticated using (true);
create policy role_permissions_manage_admin on public.role_permissions for all to authenticated
using (public.has_permission('role.manage')) with check (public.has_permission('role.manage'));

create policy departments_select_authenticated on public.departments for select to authenticated using (true);
create policy departments_manage_admin on public.departments for all to authenticated
using (public.has_permission('settings.manage')) with check (public.has_permission('settings.manage'));

create policy registers_select_authorized on public.document_registers for select to authenticated
using (public.has_permission('document.view') or public.has_permission('registry.incoming.manage') or public.has_permission('registry.outgoing.manage'));
create policy registers_manage_registry on public.document_registers for all to authenticated
using (public.has_permission('settings.manage') or public.has_permission('registry.incoming.manage') or public.has_permission('registry.outgoing.manage'))
with check (public.has_permission('settings.manage') or public.has_permission('registry.incoming.manage') or public.has_permission('registry.outgoing.manage'));

create policy senders_select_registry on public.senders for select to authenticated
using (public.has_permission('document.view') or public.has_permission('registry.incoming.manage'));
create policy senders_manage_registry on public.senders for all to authenticated
using (public.has_permission('registry.incoming.manage')) with check (public.has_permission('registry.incoming.manage'));

create policy documents_select_authorized on public.documents for select to authenticated
using (
  current_owner_id = auth.uid()
  or created_by = auth.uid()
  or public.has_permission('document.view')
);
create policy documents_insert_authorized on public.documents for insert to authenticated
with check (
  created_by = auth.uid()
  and public.has_permission('document.create')
);
create policy documents_update_authorized on public.documents for update to authenticated
using (
  current_owner_id = auth.uid()
  or created_by = auth.uid()
  or public.has_permission('document.update')
  or public.has_permission('document.assign')
  or public.has_permission('document.approve')
)
with check (
  current_owner_id = auth.uid()
  or created_by = auth.uid()
  or public.has_permission('document.update')
  or public.has_permission('document.assign')
  or public.has_permission('document.approve')
);

create policy incoming_details_select_authorized on public.incoming_document_details for select to authenticated
using (exists(select 1 from public.documents d where d.id=document_id));
create policy incoming_details_insert_registry on public.incoming_document_details for insert to authenticated
with check (public.has_permission('registry.incoming.manage'));
create policy incoming_details_update_registry on public.incoming_document_details for update to authenticated
using (public.has_permission('registry.incoming.manage')) with check (public.has_permission('registry.incoming.manage'));

create policy outgoing_details_select_authorized on public.outgoing_document_details for select to authenticated
using (exists(select 1 from public.documents d where d.id=document_id));
create policy outgoing_details_insert_registry on public.outgoing_document_details for insert to authenticated
with check (public.has_permission('registry.outgoing.manage'));
create policy outgoing_details_update_registry on public.outgoing_document_details for update to authenticated
using (public.has_permission('registry.outgoing.manage')) with check (public.has_permission('registry.outgoing.manage'));

create policy assignments_select_authorized on public.document_assignments for select to authenticated
using (assignee_id = auth.uid() or assigned_by = auth.uid() or public.has_permission('document.view'));
create policy assignments_insert_authorized on public.document_assignments for insert to authenticated
with check (assigned_by = auth.uid() and public.has_permission('document.assign'));
create policy assignments_update_authorized on public.document_assignments for update to authenticated
using (assignee_id = auth.uid() or assigned_by = auth.uid() or public.has_permission('document.assign'))
with check (assignee_id = auth.uid() or assigned_by = auth.uid() or public.has_permission('document.assign'));

create policy status_history_select_authorized on public.document_status_history for select to authenticated
using (exists(select 1 from public.documents d where d.id=document_id));
create policy approvals_select_authorized on public.approvals for select to authenticated
using (approver_id = auth.uid() or public.has_permission('document.view'));
create policy approvals_insert_authorized on public.approvals for insert to authenticated
with check (approver_id = auth.uid() and public.has_permission('document.approve'));
create policy approvals_update_authorized on public.approvals for update to authenticated
using (approver_id = auth.uid() and public.has_permission('document.approve'))
with check (approver_id = auth.uid() and public.has_permission('document.approve'));

create policy deadlines_select_authorized on public.deadlines for select to authenticated
using (assigned_to = auth.uid() or public.has_permission('document.view'));
create policy deadlines_manage_authorized on public.deadlines for all to authenticated
using (assigned_to = auth.uid() or public.has_permission('document.assign'))
with check (assigned_to = auth.uid() or public.has_permission('document.assign'));

create policy comments_select_authorized on public.comments for select to authenticated
using (exists(select 1 from public.documents d where d.id=document_id));
create policy comments_insert_own on public.comments for insert to authenticated
with check (author_id = auth.uid());
create policy comments_update_own on public.comments for update to authenticated
using (author_id = auth.uid()) with check (author_id = auth.uid());

create policy notifications_own on public.notifications for select to authenticated using (recipient_id = auth.uid());
create policy notifications_update_own on public.notifications for update to authenticated
using (recipient_id = auth.uid()) with check (recipient_id = auth.uid());

create policy push_subscriptions_own on public.push_subscriptions for all to authenticated
using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy audit_logs_admin_read on public.audit_logs for select to authenticated
using (public.has_permission('audit.view'));

create policy google_drive_files_authorized on public.google_drive_files for select to authenticated
using (public.has_permission('document.view'));
create policy document_files_authorized on public.document_files for select to authenticated
using (exists(select 1 from public.documents d where d.id=document_id));

