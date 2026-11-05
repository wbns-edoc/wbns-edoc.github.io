# Production migration ledger recovery archive — batch 1

Read-only extraction from Production project `iigzzwyfxxtqbgjawyom` and its `supabase_migrations.schema_migrations.statements` ledger.

These entries are already applied in Production. Archival evidence only: **do not copy into `supabase/migrations`, execute, or use for migration repair**. Version, ledger name, and statement text are preserved.

## 20261007133831 — foundation_schema_rbac_rls

```sql
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

```

---

## 20261007134222 — harden_rls_and_indexes

```sql
do $$declare r record;begin for r in select schemaname,tablename,policyname from pg_policies where schemaname='public' loop execute format('drop policy if exists %I on %I.%I',r.policyname,r.schemaname,r.tablename); end loop;end$$;
drop function if exists public.has_permission(text) cascade;
drop function if exists public.is_admin();
drop function if exists public.allocate_document_number(uuid,integer);
create schema if not exists private;
create or replace function private.has_permission(p_permission text) returns boolean language sql security definer set search_path=pg_catalog,public stable as $$select exists(select 1 from public.user_roles ur join public.role_permissions rp on rp.role_id=ur.role_id join public.permissions p on p.id=rp.permission_id join public.profiles pr on pr.id=ur.user_id where ur.user_id=(select auth.uid()) and pr.is_active=true and p.code=p_permission);$$;
create or replace function private.is_admin() returns boolean language sql security definer set search_path=pg_catalog,public stable as $$select private.has_permission('settings.manage');$$;
create or replace function private.allocate_document_number(p_register_id uuid,p_year integer) returns bigint language plpgsql security definer set search_path=pg_catalog,public as $$declare v_number bigint;begin if not private.has_permission('registry.incoming.manage') and not private.has_permission('registry.outgoing.manage') then raise exception 'permission denied';end if;insert into public.number_sequences(register_id,year,current_number) values(p_register_id,p_year,0) on conflict(register_id,year) do nothing;update public.number_sequences set current_number=current_number+1,updated_at=now() where register_id=p_register_id and year=p_year returning current_number into v_number;return v_number;end;$$;
revoke all on schema private from public,anon;grant usage on schema private to authenticated;grant execute on function private.has_permission(text),private.is_admin(),private.allocate_document_number(uuid,integer) to authenticated;
create policy profiles_select_self_or_admin on public.profiles for select to authenticated using (id=(select auth.uid()) or private.has_permission('user.view'));
create policy profiles_update_self_or_admin on public.profiles for update to authenticated using (id=(select auth.uid()) or private.has_permission('user.manage')) with check (id=(select auth.uid()) or private.has_permission('user.manage'));
create policy roles_select_authenticated on public.roles for select to authenticated using (true);
create policy roles_manage_admin on public.roles for all to authenticated using (private.has_permission('role.manage')) with check (private.has_permission('role.manage'));
create policy permissions_select_authenticated on public.permissions for select to authenticated using (true);
create policy permissions_manage_admin on public.permissions for all to authenticated using (private.has_permission('role.manage')) with check (private.has_permission('role.manage'));
create policy user_roles_select_self_or_admin on public.user_roles for select to authenticated using (user_id=(select auth.uid()) or private.has_permission('user.view'));
create policy user_roles_manage_admin on public.user_roles for all to authenticated using (private.has_permission('role.manage')) with check (private.has_permission('role.manage'));
create policy role_permissions_select_authenticated on public.role_permissions for select to authenticated using (true);
create policy role_permissions_manage_admin on public.role_permissions for all to authenticated using (private.has_permission('role.manage')) with check (private.has_permission('role.manage'));
create policy departments_select_authenticated on public.departments for select to authenticated using (true);
create policy departments_manage_admin on public.departments for all to authenticated using (private.has_permission('settings.manage')) with check (private.has_permission('settings.manage'));
create policy registers_select_authorized on public.document_registers for select to authenticated using (private.has_permission('document.view') or private.has_permission('registry.incoming.manage') or private.has_permission('registry.outgoing.manage'));
create policy registers_manage_registry on public.document_registers for all to authenticated using (private.has_permission('settings.manage') or private.has_permission('registry.incoming.manage') or private.has_permission('registry.outgoing.manage')) with check (private.has_permission('settings.manage') or private.has_permission('registry.incoming.manage') or private.has_permission('registry.outgoing.manage'));
create policy senders_select_registry on public.senders for select to authenticated using (private.has_permission('document.view') or private.has_permission('registry.incoming.manage'));
create policy senders_manage_registry on public.senders for all to authenticated using (private.has_permission('registry.incoming.manage')) with check (private.has_permission('registry.incoming.manage'));
create policy documents_select_authorized on public.documents for select to authenticated using (current_owner_id=(select auth.uid()) or created_by=(select auth.uid()) or private.has_permission('document.view'));
create policy documents_insert_authorized on public.documents for insert to authenticated with check (created_by=(select auth.uid()) and private.has_permission('document.create'));
create policy documents_update_authorized on public.documents for update to authenticated using (current_owner_id=(select auth.uid()) or created_by=(select auth.uid()) or private.has_permission('document.update') or private.has_permission('document.assign') or private.has_permission('document.approve')) with check (current_owner_id=(select auth.uid()) or created_by=(select auth.uid()) or private.has_permission('document.update') or private.has_permission('document.assign') or private.has_permission('document.approve'));
create policy incoming_details_select_authorized on public.incoming_document_details for select to authenticated using (exists(select 1 from public.documents d where d.id=document_id));
create policy incoming_details_insert_registry on public.incoming_document_details for insert to authenticated with check (private.has_permission('registry.incoming.manage'));
create policy incoming_details_update_registry on public.incoming_document_details for update to authenticated using (private.has_permission('registry.incoming.manage')) with check (private.has_permission('registry.incoming.manage'));
create policy outgoing_details_select_authorized on public.outgoing_document_details for select to authenticated using (exists(select 1 from public.documents d where d.id=document_id));
create policy outgoing_details_insert_registry on public.outgoing_document_details for insert to authenticated with check (private.has_permission('registry.outgoing.manage'));
create policy outgoing_details_update_registry on public.outgoing_document_details for update to authenticated using (private.has_permission('registry.outgoing.manage')) with check (private.has_permission('registry.outgoing.manage'));
create policy assignments_select_authorized on public.document_assignments for select to authenticated using (assignee_id=(select auth.uid()) or assigned_by=(select auth.uid()) or private.has_permission('document.view'));
create policy assignments_insert_authorized on public.document_assignments for insert to authenticated with check (assigned_by=(select auth.uid()) and private.has_permission('document.assign'));
create policy assignments_update_authorized on public.document_assignments for update to authenticated using (assignee_id=(select auth.uid()) or assigned_by=(select auth.uid()) or private.has_permission('document.assign')) with check (assignee_id=(select auth.uid()) or assigned_by=(select auth.uid()) or private.has_permission('document.assign'));
create policy status_history_select_authorized on public.document_status_history for select to authenticated using (exists(select 1 from public.documents d where d.id=document_id));
create policy approvals_select_authorized on public.approvals for select to authenticated using (approver_id=(select auth.uid()) or private.has_permission('document.view'));
create policy approvals_insert_authorized on public.approvals for insert to authenticated with check (approver_id=(select auth.uid()) and private.has_permission('document.approve'));
create policy approvals_update_authorized on public.approvals for update to authenticated using (approver_id=(select auth.uid()) and private.has_permission('document.approve')) with check (approver_id=(select auth.uid()) and private.has_permission('document.approve'));
create policy deadlines_select_authorized on public.deadlines for select to authenticated using (assigned_to=(select auth.uid()) or private.has_permission('document.view'));
create policy deadlines_manage_authorized on public.deadlines for all to authenticated using (assigned_to=(select auth.uid()) or private.has_permission('document.assign')) with check (assigned_to=(select auth.uid()) or private.has_permission('document.assign'));
create policy comments_select_authorized on public.comments for select to authenticated using (exists(select 1 from public.documents d where d.id=document_id));
create policy comments_insert_own on public.comments for insert to authenticated with check (author_id=(select auth.uid()));
create policy comments_update_own on public.comments for update to authenticated using (author_id=(select auth.uid())) with check (author_id=(select auth.uid()));
create policy notifications_own on public.notifications for select to authenticated using (recipient_id=(select auth.uid()));
create policy notifications_update_own on public.notifications for update to authenticated using (recipient_id=(select auth.uid())) with check (recipient_id=(select auth.uid()));
create policy push_subscriptions_own on public.push_subscriptions for all to authenticated using (user_id=(select auth.uid())) with check (user_id=(select auth.uid()));
create policy audit_logs_admin_read on public.audit_logs for select to authenticated using (private.has_permission('audit.view'));
create policy google_drive_files_authorized on public.google_drive_files for select to authenticated using (private.has_permission('document.view'));
create policy document_files_authorized on public.document_files for select to authenticated using (exists(select 1 from public.documents d where d.id=document_id));
create policy number_sequences_registry_read on public.number_sequences for select to authenticated using (private.has_permission('registry.incoming.manage') or private.has_permission('registry.outgoing.manage') or private.has_permission('settings.manage'));
create policy number_sequences_registry_update on public.number_sequences for update to authenticated using (private.has_permission('registry.incoming.manage') or private.has_permission('registry.outgoing.manage') or private.has_permission('settings.manage')) with check (private.has_permission('registry.incoming.manage') or private.has_permission('registry.outgoing.manage') or private.has_permission('settings.manage'));
create index if not exists idx_departments_parent on public.departments(parent_id);
create index if not exists idx_documents_register on public.documents(register_id);
create index if not exists idx_documents_created_by on public.documents(created_by);
create index if not exists idx_document_assignments_assigned_by on public.document_assignments(assigned_by);
create index if not exists idx_document_status_history_changed_by on public.document_status_history(changed_by);
create index if not exists idx_comments_document on public.comments(document_id);
create index if not exists idx_comments_author on public.comments(author_id);
create index if not exists idx_deadlines_document on public.deadlines(document_id);
create index if not exists idx_deadlines_assigned_to on public.deadlines(assigned_to);
create index if not exists idx_google_drive_files_created_by on public.google_drive_files(created_by);
create index if not exists idx_document_files_drive on public.document_files(google_drive_file_id);
create index if not exists idx_document_files_uploaded_by on public.document_files(uploaded_by);
create index if not exists idx_notifications_document on public.notifications(document_id);
create index if not exists idx_push_subscriptions_user on public.push_subscriptions(user_id);
create index if not exists idx_audit_logs_actor on public.audit_logs(actor_id);
create index if not exists idx_user_roles_assigned_by on public.user_roles(assigned_by);
```

---

## 20261007134728 — document_registration_rpc

```sql
create or replace function private.register_incoming_document(
 p_subject text,
 p_sender_id uuid,
 p_external_document_no text default null,
 p_external_document_date date default null,
 p_received_at timestamptz default now(),
 p_urgency urgency_level default 'normal',
 p_receiving_notes text default null
) returns uuid
language plpgsql
security definer
set search_path=pg_catalog,public
as $$
declare
 v_uid uuid := (select auth.uid());
 v_register uuid;
 v_doc uuid;
 v_no bigint;
begin
 if v_uid is null or not private.has_permission('registry.incoming.manage') then
   raise exception 'permission denied';
 end if;
 select id into v_register
 from public.document_registers
 where direction='incoming' and is_active=true
 order by document_year desc, created_at
 limit 1;
 if v_register is null then raise exception 'ไม่พบทะเบียนหนังสือรับที่ใช้งานอยู่'; end if;
 v_no := private.allocate_document_number(v_register, (select document_year from public.document_registers where id=v_register));
 insert into public.documents(document_type,register_id,subject,urgency,status,current_owner_id,created_by)
 values('incoming',v_register,p_subject,p_urgency,'received',v_uid,v_uid)
 returning id into v_doc;
 insert into public.incoming_document_details(document_id,sender_id,external_document_no,external_document_date,received_at,registered_at,registered_number,receiving_notes)
 values(v_doc,p_sender_id,p_external_document_no,p_external_document_date,p_received_at,now(),v_no,p_receiving_notes);
 insert into public.document_status_history(document_id,from_status,to_status,changed_by,reason)
 values(v_doc,null,'received',v_uid,'รับหนังสือเข้าระบบ');
 return v_doc;
end $$;

create or replace function public.register_incoming_document(
 p_subject text,
 p_sender_id uuid,
 p_external_document_no text default null,
 p_external_document_date date default null,
 p_received_at timestamptz default now(),
 p_urgency urgency_level default 'normal',
 p_receiving_notes text default null
) returns uuid
language sql
security invoker
set search_path=pg_catalog,public
as $$select private.register_incoming_document($1,$2,$3,$4,$5,$6,$7);$$;

grant execute on function public.register_incoming_document(text,uuid,text,date,timestamptz,urgency_level,text) to authenticated;

create or replace function private.register_outgoing_document(
 p_subject text,
 p_recipient_name text,
 p_recipient_address text default null,
 p_recipient_contact text default null,
 p_document_date date default null,
 p_urgency urgency_level default 'normal'
) returns uuid
language plpgsql
security definer
set search_path=pg_catalog,public
as $$
declare
 v_uid uuid := (select auth.uid());
 v_register uuid;
 v_doc uuid;
 v_no bigint;
begin
 if v_uid is null or not private.has_permission('registry.outgoing.manage') then raise exception 'permission denied'; end if;
 select id into v_register from public.document_registers where direction='outgoing' and is_active=true order by document_year desc,created_at limit 1;
 if v_register is null then raise exception 'ไม่พบทะเบียนหนังสือส่งที่ใช้งานอยู่'; end if;
 v_no := private.allocate_document_number(v_register,(select document_year from public.document_registers where id=v_register));
 insert into public.documents(document_type,register_id,subject,urgency,status,current_owner_id,created_by)
 values('outgoing',v_register,p_subject,p_urgency,'draft',v_uid,v_uid) returning id into v_doc;
 insert into public.outgoing_document_details(document_id,outgoing_document_no,document_date,recipient_name,recipient_address,recipient_contact,registered_number)
 values(v_doc,null,coalesce(p_document_date,current_date),p_recipient_name,p_recipient_address,p_recipient_contact,v_no);
 insert into public.document_status_history(document_id,from_status,to_status,changed_by,reason)
 values(v_doc,null,'draft',v_uid,'สร้างหนังสือส่งฉบับร่าง');
 return v_doc;
end $$;

create or replace function public.register_outgoing_document(
 p_subject text,
 p_recipient_name text,
 p_recipient_address text default null,
 p_recipient_contact text default null,
 p_document_date date default null,
 p_urgency urgency_level default 'normal'
) returns uuid
language sql
security invoker
set search_path=pg_catalog,public
as $$select private.register_outgoing_document($1,$2,$3,$4,$5,$6);$$;

grant execute on function public.register_outgoing_document(text,text,text,text,date,urgency_level) to authenticated;
```

---

## 20261007135044 — seed_school_registers_2026

```sql

insert into public.document_registers(code,name,direction,document_year,is_active)
values
('IN-2026','ทะเบียนหนังสือรับ','incoming',2026,true),
('OUT-2026','ทะเบียนหนังสือส่ง','outgoing',2026,true)
on conflict do nothing;

```

---

## 20261007135356 — workflow_engine_v1

```sql
-- Workflow operations for WBNS Electronic Document System
-- Applied to Supabase project iigzzwyfxxtqbgjawyom as migration workflow_engine_v1.

create or replace function public.assign_document(
  p_document_id uuid,
  p_assignee_id uuid,
  p_instructions text default null,
  p_due_at timestamptz default null
) returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_id uuid;
  v_actor uuid := auth.uid();
  v_subject text;
begin
  if v_actor is null or not private.has_permission('document.assign') then
    raise exception 'permission_denied';
  end if;
  if not exists (select 1 from public.documents where id=p_document_id) then
    raise exception 'document_not_found';
  end if;
  if not exists (select 1 from public.profiles where id=p_assignee_id and is_active=true) then
    raise exception 'assignee_not_found';
  end if;

  insert into public.document_assignments(document_id,assignee_id,assigned_by,instructions,assignment_status)
  values(p_document_id,p_assignee_id,v_actor,p_instructions,'assigned')
  returning id into v_id;

  update public.documents
    set current_owner_id=p_assignee_id,status='assigned'
    where id=p_document_id;

  insert into public.document_status_history(document_id,from_status,to_status,changed_by,reason)
  select id,status,'assigned',v_actor,'มอบหมายงาน'
  from public.documents where id=p_document_id and status <> 'assigned';

  select subject into v_subject from public.documents where id=p_document_id;

  insert into public.notifications(recipient_id,document_id,type,title,body,priority)
  values(p_assignee_id,p_document_id,'assignment','ได้รับมอบหมายงาน',
         'คุณได้รับมอบหมายเรื่อง: '||coalesce(v_subject,'ไม่ระบุเรื่อง'),
         'high');

  if p_due_at is not null then
    insert into public.deadlines(document_id,assigned_to,due_at,reminder_at,escalation_at,status)
    values(p_document_id,p_assignee_id,p_due_at,p_due_at - interval '24 hours',p_due_at,'open');
  end if;

  return v_id;
end;
$$;

create or replace function public.update_document_status(
  p_document_id uuid,
  p_to_status document_status,
  p_reason text default null
) returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_actor uuid := auth.uid();
  v_from document_status;
begin
  if v_actor is null or not (private.has_permission('document.update') or private.has_permission('document.complete')) then
    raise exception 'permission_denied';
  end if;

  select status into v_from from public.documents where id=p_document_id for update;
  if v_from is null then raise exception 'document_not_found'; end if;
  if v_from = p_to_status then return true; end if;

  update public.documents set status=p_to_status where id=p_document_id;

  insert into public.document_status_history(document_id,from_status,to_status,changed_by,reason)
  values(p_document_id,v_from,p_to_status,v_actor,p_reason);

  if p_to_status in ('completed','archived') then
    update public.deadlines set status='completed',completed_at=coalesce(completed_at,now())
    where document_id=p_document_id and status='open';
  end if;

  return true;
end;
$$;

create or replace function public.create_approval(
  p_document_id uuid,
  p_approver_id uuid,
  p_approval_step integer default 1
) returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare v_id uuid; v_actor uuid := auth.uid(); v_subject text;
begin
  if v_actor is null or not private.has_permission('document.approve') then raise exception 'permission_denied'; end if;
  if p_approval_step < 1 then raise exception 'invalid_approval_step'; end if;
  if not exists(select 1 from public.profiles where id=p_approver_id and is_active=true) then raise exception 'approver_not_found'; end if;

  insert into public.approvals(document_id,approval_step,approver_id,decision)
  values(p_document_id,p_approval_step,p_approver_id,'pending')
  returning id into v_id;

  update public.documents set status='pending_approval' where id=p_document_id;
  select subject into v_subject from public.documents where id=p_document_id;
  insert into public.notifications(recipient_id,document_id,type,title,body,priority)
  values(p_approver_id,p_document_id,'approval','รอการอนุมัติ',
         'มีเอกสารรอการอนุมัติ: '||coalesce(v_subject,'ไม่ระบุเรื่อง'),'high');
  return v_id;
end;
$$;

create or replace function public.decide_approval(
  p_approval_id uuid,
  p_decision approval_decision,
  p_comment text default null
) returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare v_actor uuid := auth.uid(); v_doc uuid; v_step integer; v_subject text;
begin
  if v_actor is null or not private.has_permission('document.approve') then raise exception 'permission_denied'; end if;

  select document_id,approval_step into v_doc,v_step
  from public.approvals
  where id=p_approval_id and approver_id=v_actor and decision='pending'
  for update;
  if v_doc is null then raise exception 'approval_not_found_or_not_authorized'; end if;

  update public.approvals
    set decision=p_decision,comment=p_comment,decided_at=now()
    where id=p_approval_id;

  if p_decision='approved' then
    if exists(select 1 from public.approvals where document_id=v_doc and approval_step>v_step and decision='pending') then
      update public.documents set status='pending_approval' where id=v_doc;
    else
      update public.documents set status='approved' where id=v_doc;
    end if;
  elsif p_decision in ('rejected','returned') then
    update public.documents set status='draft' where id=v_doc;
  end if;

  select subject into v_subject from public.documents where id=v_doc;
  insert into public.notifications(recipient_id,document_id,type,title,body,priority)
  select distinct p.created_by,v_doc,'approval_decision','ผลการอนุมัติ',
         'เอกสาร "'||coalesce(v_subject,'ไม่ระบุเรื่อง')||'" มีผลการพิจารณา: '||p_decision::text,'high'
  from public.documents p where p.id=v_doc and p.created_by is not null;

  return true;
end;
$$;

create or replace function public.set_document_deadline(
  p_document_id uuid,
  p_assigned_to uuid,
  p_due_at timestamptz,
  p_reminder_at timestamptz default null
) returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare v_id uuid; v_actor uuid := auth.uid();
begin
  if v_actor is null or not private.has_permission('document.assign') then raise exception 'permission_denied'; end if;
  if p_due_at <= now() then raise exception 'deadline_must_be_future'; end if;

  insert into public.deadlines(document_id,assigned_to,due_at,reminder_at,escalation_at,status)
  values(p_document_id,p_assigned_to,p_due_at,coalesce(p_reminder_at,p_due_at-interval '24 hours'),p_due_at,'open')
  returning id into v_id;
  return v_id;
end;
$$;

create index if not exists idx_document_assignments_assignee_status on public.document_assignments(assignee_id,assignment_status,assigned_at desc);
create index if not exists idx_approvals_approver_decision on public.approvals(approver_id,decision,created_at desc);
create index if not exists idx_deadlines_open_due on public.deadlines(status,due_at);
create index if not exists idx_notifications_recipient_unread on public.notifications(recipient_id,read_at,created_at desc);

revoke all on function public.assign_document(uuid,uuid,text,timestamptz) from public;
revoke all on function public.update_document_status(uuid,document_status,text) from public;
revoke all on function public.create_approval(uuid,uuid,integer) from public;
revoke all on function public.decide_approval(uuid,approval_decision,text) from public;
revoke all on function public.set_document_deadline(uuid,uuid,timestamptz,timestamptz) from public;
grant execute on function public.assign_document(uuid,uuid,text,timestamptz) to authenticated;
grant execute on function public.update_document_status(uuid,document_status,text) to authenticated;
grant execute on function public.create_approval(uuid,uuid,integer) to authenticated;
grant execute on function public.decide_approval(uuid,approval_decision,text) to authenticated;
grant execute on function public.set_document_deadline(uuid,uuid,timestamptz,timestamptz) to authenticated;

```

---

## 20261007135756 — notification_deadline_engine_v1

```sql
create extension if not exists pg_cron with schema pg_catalog;
grant usage on schema cron to postgres;
grant all privileges on all tables in schema cron to postgres;

create extension if not exists pg_trgm;

create index if not exists idx_documents_subject_trgm on public.documents using gin(subject gin_trgm_ops);
create index if not exists idx_senders_org_trgm on public.senders using gin(organization_name gin_trgm_ops);
create index if not exists idx_documents_status_urgency_created on public.documents(status,urgency,created_at desc);
create index if not exists idx_deadlines_assignee_due on public.deadlines(assigned_to,due_at) where status='open';

create or replace function private.process_deadline_notifications()
returns integer
language plpgsql
security definer
set search_path=pg_catalog,public,private
as $$
declare v_count integer:=0; d record; r record; v_subject text;
begin
 for d in select dl.id,dl.document_id,dl.assigned_to,dl.due_at,dl.reminder_at,doc.subject,doc.urgency,doc.status
 from public.deadlines dl join public.documents doc on doc.id=dl.document_id
 where dl.status='open' and doc.status not in ('completed','archived','cancelled')
 and ((dl.reminder_at is not null and dl.reminder_at<=now() and dl.due_at>now()) or dl.due_at<=now()) loop
  v_subject:=coalesce(d.subject,'ไม่ระบุเรื่อง');
  if d.due_at<=now() then
   if d.assigned_to is not null and not exists(select 1 from public.notifications n where n.document_id=d.document_id and n.recipient_id=d.assigned_to and n.type='deadline_overdue' and n.created_at>=d.due_at) then
    insert into public.notifications(recipient_id,document_id,type,title,body,priority) values(d.assigned_to,d.document_id,'deadline_overdue','เกินกำหนดงาน','งานเรื่อง "'||v_subject||'" เกินกำหนดแล้ว กรุณาดำเนินการทันที','high'); v_count:=v_count+1;
   end if;
   for r in select distinct ur.user_id from public.user_roles ur join public.roles ro on ro.id=ur.role_id where ro.code in('director','deputy_director') loop
    if not exists(select 1 from public.notifications n where n.document_id=d.document_id and n.recipient_id=r.user_id and n.type='deadline_escalation' and n.created_at>=d.due_at) then
     insert into public.notifications(recipient_id,document_id,type,title,body,priority) values(r.user_id,d.document_id,'deadline_escalation','แจ้งเตือนผู้บริหาร: เกินกำหนด','เอกสารเรื่อง "'||v_subject||'" เกินกำหนดดำเนินการแล้ว','critical'); v_count:=v_count+1;
    end if;
   end loop;
  else
   if d.assigned_to is not null and not exists(select 1 from public.notifications n where n.document_id=d.document_id and n.recipient_id=d.assigned_to and n.type='deadline_reminder' and n.created_at>=d.reminder_at) then
    insert into public.notifications(recipient_id,document_id,type,title,body,priority) values(d.assigned_to,d.document_id,'deadline_reminder','ใกล้ครบกำหนดงาน','งานเรื่อง "'||v_subject||'" ใกล้ครบกำหนด กรุณาตรวจสอบและดำเนินการ','high'); v_count:=v_count+1;
   end if;
   for r in select distinct ur.user_id from public.user_roles ur join public.roles ro on ro.id=ur.role_id where ro.code in('director','deputy_director') loop
    if not exists(select 1 from public.notifications n where n.document_id=d.document_id and n.recipient_id=r.user_id and n.type='deadline_reminder_management' and n.created_at>=d.reminder_at) then
     insert into public.notifications(recipient_id,document_id,type,title,body,priority) values(r.user_id,d.document_id,'deadline_reminder_management','แจ้งเตือนผู้บริหาร: ใกล้ครบกำหนด','เอกสารเรื่อง "'||v_subject||'" ใกล้ครบกำหนดดำเนินการ','high'); v_count:=v_count+1;
    end if;
   end loop;
  end if;
 end loop;
 return v_count;
end $$;

revoke all on function private.process_deadline_notifications() from public,anon,authenticated;

select cron.schedule('wbns-deadline-notifications','*/15 * * * *',$$select private.process_deadline_notifications();$$);
```

---

## 20261007135857 — move_pg_trgm_to_extensions

```sql
drop index if exists public.idx_documents_subject_trgm;
drop index if exists public.idx_senders_org_trgm;
drop extension if exists pg_trgm;
create extension pg_trgm with schema extensions;
create index idx_documents_subject_trgm on public.documents using gin(subject extensions.gin_trgm_ops);
create index idx_senders_org_trgm on public.senders using gin(organization_name extensions.gin_trgm_ops);
```

---

## 20261007140118 — audit_trail_v1

```sql
-- Audit trail hardening and searchable document metadata
create or replace function private.audit_row_change() returns trigger
language plpgsql security definer set search_path=pg_catalog,public,private
as $$
declare
  v_actor uuid := auth.uid();
  v_old jsonb := case when TG_OP in ('UPDATE','DELETE') then to_jsonb(OLD) else null end;
  v_new jsonb := case when TG_OP in ('INSERT','UPDATE') then to_jsonb(NEW) else null end;
  v_entity_id uuid;
begin
  begin
    v_entity_id := coalesce((v_new->>'id')::uuid,(v_old->>'id')::uuid,(v_new->>'document_id')::uuid,(v_old->>'document_id')::uuid);
  exception when others then v_entity_id := null;
  end;
  insert into public.audit_logs(actor_id,action,entity_type,entity_id,old_data,new_data)
  values(v_actor,TG_OP,replace(TG_TABLE_NAME,'_',' '),v_entity_id,v_old,v_new);
  return coalesce(NEW,OLD);
end $$;
revoke all on function private.audit_row_change() from public,anon,authenticated;

drop trigger if exists audit_documents on public.documents;
create trigger audit_documents after insert or update or delete on public.documents for each row execute function private.audit_row_change();
drop trigger if exists audit_document_assignments on public.document_assignments;
create trigger audit_document_assignments after insert or update or delete on public.document_assignments for each row execute function private.audit_row_change();
drop trigger if exists audit_approvals on public.approvals;
create trigger audit_approvals after insert or update or delete on public.approvals for each row execute function private.audit_row_change();
drop trigger if exists audit_deadlines on public.deadlines;
create trigger audit_deadlines after insert or update or delete on public.deadlines for each row execute function private.audit_row_change();
drop trigger if exists audit_document_files on public.document_files;
create trigger audit_document_files after insert or update or delete on public.document_files for each row execute function private.audit_row_change();

create index if not exists idx_audit_logs_created_at on public.audit_logs(created_at desc);
create index if not exists idx_audit_logs_entity on public.audit_logs(entity_type,entity_id,created_at desc);
create index if not exists idx_audit_logs_actor on public.audit_logs(actor_id,created_at desc);
```

---

## 20261007140240 — audit_trail_hardening_v2

```sql
drop index if exists public.idx_audit_entity;
-- Keep the canonical audit indexes introduced by audit_trail_v1.
create or replace function private.audit_row_change() returns trigger
language plpgsql security definer set search_path=pg_catalog,public,private
as $$
declare
  v_actor uuid := auth.uid();
  v_old jsonb := case when TG_OP in ('UPDATE','DELETE') then to_jsonb(OLD) else null end;
  v_new jsonb := case when TG_OP in ('INSERT','UPDATE') then to_jsonb(NEW) else null end;
  v_entity_id uuid;
begin
  begin
    v_entity_id := coalesce((v_new->>'id')::uuid,(v_old->>'id')::uuid,(v_new->>'document_id')::uuid,(v_old->>'document_id')::uuid);
  exception when others then v_entity_id := null;
  end;
  insert into public.audit_logs(actor_id,action,entity_type,entity_id,old_data,new_data)
  values(v_actor,TG_OP,replace(TG_TABLE_NAME,'_',' '),v_entity_id,v_old,v_new);
  if TG_OP='DELETE' then return OLD; end if;
  return NEW;
end $$;
```
