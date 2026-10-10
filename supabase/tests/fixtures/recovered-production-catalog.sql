-- GENERATED READ-ONLY CATALOG SNAPSHOT for isolated tests only.
-- Source project: iigzzwyfxxtqbgjawyom. Generated 2026-10-10.
-- NOT a historical migration, NOT intended for Production deployment.
-- Contains no production user/document rows. Recovered definitions must be reviewed.
-- TEST-ONLY PATCH: qualify public.documents.id inside attach_document_file_version to avoid a known PL/pgSQL output-column ambiguity during fixture lint. This is NOT a Production fix; a forward-only migration and live catalog verification are still required.
SET check_function_bodies = off;
SET search_path = public, private, extensions, pg_catalog;
CREATE SCHEMA IF NOT EXISTS private;
CREATE SCHEMA IF NOT EXISTS extensions;
CREATE EXTENSION IF NOT EXISTS "pg_trgm" WITH SCHEMA "extensions";
CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "extensions";

CREATE TYPE public."approval_decision" AS ENUM ('pending', 'approved', 'rejected', 'returned');
CREATE TYPE public."assignment_status" AS ENUM ('assigned', 'accepted', 'in_progress', 'completed', 'cancelled');
CREATE TYPE public."document_status" AS ENUM ('draft', 'pending_approval', 'approved', 'received', 'registered', 'assigned', 'in_progress', 'completed', 'archived', 'sent', 'cancelled');
CREATE TYPE public."document_type" AS ENUM ('incoming', 'outgoing');
CREATE TYPE public."urgency_level" AS ENUM ('normal', 'urgent', 'very_urgent', 'critical');

-- Tables
CREATE TABLE public.approvals (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  document_id uuid NOT NULL,
  approval_step integer NOT NULL,
  approver_id uuid NOT NULL,
  decision approval_decision DEFAULT 'pending'::approval_decision NOT NULL,
  decided_at timestamp with time zone,
  comment text,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.audit_logs (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  actor_id uuid,
  action text NOT NULL,
  entity_type text NOT NULL,
  entity_id uuid,
  old_data jsonb,
  new_data jsonb,
  request_id text,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.comments (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  document_id uuid NOT NULL,
  author_id uuid NOT NULL,
  body text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  edited_at timestamp with time zone
);

CREATE TABLE public.deadlines (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  document_id uuid NOT NULL,
  assigned_to uuid,
  due_at timestamp with time zone NOT NULL,
  reminder_at timestamp with time zone,
  escalation_at timestamp with time zone,
  completed_at timestamp with time zone,
  status text DEFAULT 'open'::text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.departments (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  parent_id uuid,
  code text NOT NULL,
  name text NOT NULL,
  is_active boolean DEFAULT true NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.document_assignments (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  document_id uuid NOT NULL,
  assignee_id uuid NOT NULL,
  assigned_by uuid NOT NULL,
  assigned_at timestamp with time zone DEFAULT now() NOT NULL,
  accepted_at timestamp with time zone,
  completed_at timestamp with time zone,
  instructions text,
  assignment_status assignment_status DEFAULT 'assigned'::assignment_status NOT NULL
);

CREATE TABLE public.document_files (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  document_id uuid NOT NULL,
  google_drive_file_id uuid NOT NULL,
  file_role text DEFAULT 'attachment'::text NOT NULL,
  version_no integer DEFAULT 1 NOT NULL,
  is_current boolean DEFAULT true NOT NULL,
  uploaded_by uuid,
  uploaded_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.document_registers (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  code text NOT NULL,
  name text NOT NULL,
  direction document_type NOT NULL,
  document_year integer NOT NULL,
  is_active boolean DEFAULT true NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.document_status_history (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  document_id uuid NOT NULL,
  from_status document_status,
  to_status document_status NOT NULL,
  changed_by uuid,
  changed_at timestamp with time zone DEFAULT now() NOT NULL,
  reason text
);

CREATE TABLE public.documents (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  document_type document_type NOT NULL,
  register_id uuid,
  subject text NOT NULL,
  urgency urgency_level DEFAULT 'normal'::urgency_level NOT NULL,
  status document_status DEFAULT 'draft'::document_status NOT NULL,
  current_owner_id uuid,
  created_by uuid NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.google_drive_files (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  drive_file_id text NOT NULL,
  drive_url text,
  name text NOT NULL,
  mime_type text,
  size_bytes bigint,
  checksum text,
  folder_id text,
  created_by uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.incoming_document_details (
  document_id uuid NOT NULL,
  sender_id uuid NOT NULL,
  external_document_no text,
  external_document_date date,
  received_at timestamp with time zone,
  registered_at timestamp with time zone,
  registered_number bigint,
  receiving_notes text
);

CREATE TABLE public.notifications (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  recipient_id uuid NOT NULL,
  document_id uuid,
  type text NOT NULL,
  title text NOT NULL,
  body text NOT NULL,
  priority text DEFAULT 'normal'::text NOT NULL,
  read_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.number_sequences (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  register_id uuid NOT NULL,
  year integer NOT NULL,
  prefix text,
  current_number bigint DEFAULT 0 NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.outgoing_document_details (
  document_id uuid NOT NULL,
  outgoing_document_no text,
  document_date date,
  recipient_name text NOT NULL,
  recipient_address text,
  recipient_contact text,
  sent_at timestamp with time zone,
  registered_number bigint
);

CREATE TABLE public.permissions (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  code text NOT NULL,
  name text NOT NULL,
  description text,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.profiles (
  id uuid NOT NULL,
  employee_code text,
  full_name text NOT NULL,
  email text,
  phone text,
  department_id uuid,
  is_active boolean DEFAULT true NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.push_subscriptions (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  user_id uuid NOT NULL,
  endpoint text NOT NULL,
  p256dh text NOT NULL,
  auth text NOT NULL,
  user_agent text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  revoked_at timestamp with time zone
);

CREATE TABLE public.role_permissions (
  role_id uuid NOT NULL,
  permission_id uuid NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.roles (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  code text NOT NULL,
  name text NOT NULL,
  description text,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.senders (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  organization_name text NOT NULL,
  department_name text,
  address text,
  contact_name text,
  contact_phone text,
  contact_email text,
  is_active boolean DEFAULT true NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.user_roles (
  user_id uuid NOT NULL,
  role_id uuid NOT NULL,
  assigned_at timestamp with time zone DEFAULT now() NOT NULL,
  assigned_by uuid
);

-- Constraints
ALTER TABLE approvals ADD CONSTRAINT approvals_approval_step_check CHECK (approval_step > 0);
ALTER TABLE approvals ADD CONSTRAINT approvals_document_id_approval_step_key UNIQUE (document_id, approval_step);
ALTER TABLE approvals ADD CONSTRAINT approvals_pkey PRIMARY KEY (id);
ALTER TABLE audit_logs ADD CONSTRAINT audit_logs_pkey PRIMARY KEY (id);
ALTER TABLE comments ADD CONSTRAINT comments_pkey PRIMARY KEY (id);
ALTER TABLE deadlines ADD CONSTRAINT deadlines_pkey PRIMARY KEY (id);
ALTER TABLE deadlines ADD CONSTRAINT deadlines_status_check CHECK (status = ANY (ARRAY['open'::text, 'completed'::text, 'overdue'::text, 'cancelled'::text]));
ALTER TABLE departments ADD CONSTRAINT departments_code_key UNIQUE (code);
ALTER TABLE departments ADD CONSTRAINT departments_pkey PRIMARY KEY (id);
ALTER TABLE document_assignments ADD CONSTRAINT document_assignments_pkey PRIMARY KEY (id);
ALTER TABLE document_files ADD CONSTRAINT document_files_document_id_google_drive_file_id_key UNIQUE (document_id, google_drive_file_id);
ALTER TABLE document_files ADD CONSTRAINT document_files_pkey PRIMARY KEY (id);
ALTER TABLE document_files ADD CONSTRAINT document_files_version_no_check CHECK (version_no > 0);
ALTER TABLE document_registers ADD CONSTRAINT document_registers_code_document_year_key UNIQUE (code, document_year);
ALTER TABLE document_registers ADD CONSTRAINT document_registers_direction_document_year_key UNIQUE (direction, document_year);
ALTER TABLE document_registers ADD CONSTRAINT document_registers_document_year_check CHECK (document_year >= 2000 AND document_year <= 2200);
ALTER TABLE document_registers ADD CONSTRAINT document_registers_pkey PRIMARY KEY (id);
ALTER TABLE document_status_history ADD CONSTRAINT document_status_history_pkey PRIMARY KEY (id);
ALTER TABLE documents ADD CONSTRAINT documents_pkey PRIMARY KEY (id);
ALTER TABLE google_drive_files ADD CONSTRAINT google_drive_files_drive_file_id_key UNIQUE (drive_file_id);
ALTER TABLE google_drive_files ADD CONSTRAINT google_drive_files_pkey PRIMARY KEY (id);
ALTER TABLE incoming_document_details ADD CONSTRAINT incoming_document_details_pkey PRIMARY KEY (document_id);
ALTER TABLE notifications ADD CONSTRAINT notifications_pkey PRIMARY KEY (id);
ALTER TABLE notifications ADD CONSTRAINT notifications_priority_check CHECK (priority = ANY (ARRAY['normal'::text, 'high'::text, 'critical'::text]));
ALTER TABLE number_sequences ADD CONSTRAINT number_sequences_current_number_check CHECK (current_number >= 0);
ALTER TABLE number_sequences ADD CONSTRAINT number_sequences_pkey PRIMARY KEY (id);
ALTER TABLE number_sequences ADD CONSTRAINT number_sequences_register_id_year_key UNIQUE (register_id, year);
ALTER TABLE number_sequences ADD CONSTRAINT number_sequences_year_check CHECK (year >= 2000 AND year <= 2200);
ALTER TABLE outgoing_document_details ADD CONSTRAINT outgoing_document_details_pkey PRIMARY KEY (document_id);
ALTER TABLE permissions ADD CONSTRAINT permissions_code_key UNIQUE (code);
ALTER TABLE permissions ADD CONSTRAINT permissions_pkey PRIMARY KEY (id);
ALTER TABLE profiles ADD CONSTRAINT profiles_employee_code_key UNIQUE (employee_code);
ALTER TABLE profiles ADD CONSTRAINT profiles_pkey PRIMARY KEY (id);
ALTER TABLE push_subscriptions ADD CONSTRAINT push_subscriptions_endpoint_key UNIQUE (endpoint);
ALTER TABLE push_subscriptions ADD CONSTRAINT push_subscriptions_pkey PRIMARY KEY (id);
ALTER TABLE role_permissions ADD CONSTRAINT role_permissions_pkey PRIMARY KEY (role_id, permission_id);
ALTER TABLE roles ADD CONSTRAINT roles_code_key UNIQUE (code);
ALTER TABLE roles ADD CONSTRAINT roles_pkey PRIMARY KEY (id);
ALTER TABLE senders ADD CONSTRAINT senders_pkey PRIMARY KEY (id);
ALTER TABLE user_roles ADD CONSTRAINT user_roles_pkey PRIMARY KEY (user_id, role_id);
ALTER TABLE approvals ADD CONSTRAINT approvals_approver_id_fkey FOREIGN KEY (approver_id) REFERENCES profiles(id) ON DELETE RESTRICT;
ALTER TABLE approvals ADD CONSTRAINT approvals_document_id_fkey FOREIGN KEY (document_id) REFERENCES documents(id) ON DELETE RESTRICT;
ALTER TABLE audit_logs ADD CONSTRAINT audit_logs_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES profiles(id) ON DELETE RESTRICT;
ALTER TABLE comments ADD CONSTRAINT comments_author_id_fkey FOREIGN KEY (author_id) REFERENCES profiles(id) ON DELETE RESTRICT;
ALTER TABLE comments ADD CONSTRAINT comments_document_id_fkey FOREIGN KEY (document_id) REFERENCES documents(id) ON DELETE RESTRICT;
ALTER TABLE deadlines ADD CONSTRAINT deadlines_assigned_to_fkey FOREIGN KEY (assigned_to) REFERENCES profiles(id) ON DELETE RESTRICT;
ALTER TABLE deadlines ADD CONSTRAINT deadlines_document_id_fkey FOREIGN KEY (document_id) REFERENCES documents(id) ON DELETE RESTRICT;
ALTER TABLE departments ADD CONSTRAINT departments_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES departments(id) ON DELETE RESTRICT;
ALTER TABLE document_assignments ADD CONSTRAINT document_assignments_assigned_by_fkey FOREIGN KEY (assigned_by) REFERENCES profiles(id) ON DELETE RESTRICT;
ALTER TABLE document_assignments ADD CONSTRAINT document_assignments_assignee_id_fkey FOREIGN KEY (assignee_id) REFERENCES profiles(id) ON DELETE RESTRICT;
ALTER TABLE document_assignments ADD CONSTRAINT document_assignments_document_id_fkey FOREIGN KEY (document_id) REFERENCES documents(id) ON DELETE RESTRICT;
ALTER TABLE document_files ADD CONSTRAINT document_files_document_id_fkey FOREIGN KEY (document_id) REFERENCES documents(id) ON DELETE RESTRICT;
ALTER TABLE document_files ADD CONSTRAINT document_files_google_drive_file_id_fkey FOREIGN KEY (google_drive_file_id) REFERENCES google_drive_files(id) ON DELETE RESTRICT;
ALTER TABLE document_files ADD CONSTRAINT document_files_uploaded_by_fkey FOREIGN KEY (uploaded_by) REFERENCES profiles(id) ON DELETE RESTRICT;
ALTER TABLE document_status_history ADD CONSTRAINT document_status_history_changed_by_fkey FOREIGN KEY (changed_by) REFERENCES profiles(id) ON DELETE RESTRICT;
ALTER TABLE document_status_history ADD CONSTRAINT document_status_history_document_id_fkey FOREIGN KEY (document_id) REFERENCES documents(id) ON DELETE RESTRICT;
ALTER TABLE documents ADD CONSTRAINT documents_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE RESTRICT;
ALTER TABLE documents ADD CONSTRAINT documents_current_owner_id_fkey FOREIGN KEY (current_owner_id) REFERENCES profiles(id) ON DELETE RESTRICT;
ALTER TABLE documents ADD CONSTRAINT documents_register_id_fkey FOREIGN KEY (register_id) REFERENCES document_registers(id) ON DELETE RESTRICT;
ALTER TABLE google_drive_files ADD CONSTRAINT google_drive_files_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE RESTRICT;
ALTER TABLE incoming_document_details ADD CONSTRAINT incoming_document_details_document_id_fkey FOREIGN KEY (document_id) REFERENCES documents(id) ON DELETE RESTRICT;
ALTER TABLE incoming_document_details ADD CONSTRAINT incoming_document_details_sender_id_fkey FOREIGN KEY (sender_id) REFERENCES senders(id) ON DELETE RESTRICT;
ALTER TABLE notifications ADD CONSTRAINT notifications_document_id_fkey FOREIGN KEY (document_id) REFERENCES documents(id) ON DELETE RESTRICT;
ALTER TABLE notifications ADD CONSTRAINT notifications_recipient_id_fkey FOREIGN KEY (recipient_id) REFERENCES profiles(id) ON DELETE RESTRICT;
ALTER TABLE number_sequences ADD CONSTRAINT number_sequences_register_id_fkey FOREIGN KEY (register_id) REFERENCES document_registers(id) ON DELETE RESTRICT;
ALTER TABLE outgoing_document_details ADD CONSTRAINT outgoing_document_details_document_id_fkey FOREIGN KEY (document_id) REFERENCES documents(id) ON DELETE RESTRICT;
ALTER TABLE profiles ADD CONSTRAINT profiles_department_id_fkey FOREIGN KEY (department_id) REFERENCES departments(id) ON DELETE RESTRICT;
ALTER TABLE profiles ADD CONSTRAINT profiles_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE RESTRICT;
ALTER TABLE push_subscriptions ADD CONSTRAINT push_subscriptions_user_id_fkey FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE RESTRICT;
ALTER TABLE role_permissions ADD CONSTRAINT role_permissions_permission_id_fkey FOREIGN KEY (permission_id) REFERENCES permissions(id) ON DELETE CASCADE;
ALTER TABLE role_permissions ADD CONSTRAINT role_permissions_role_id_fkey FOREIGN KEY (role_id) REFERENCES roles(id) ON DELETE CASCADE;
ALTER TABLE user_roles ADD CONSTRAINT user_roles_assigned_by_fkey FOREIGN KEY (assigned_by) REFERENCES profiles(id) ON DELETE RESTRICT;
ALTER TABLE user_roles ADD CONSTRAINT user_roles_role_id_fkey FOREIGN KEY (role_id) REFERENCES roles(id) ON DELETE RESTRICT;
ALTER TABLE user_roles ADD CONSTRAINT user_roles_user_id_fkey FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE RESTRICT;

-- Non-constraint indexes
CREATE INDEX idx_approvals_approver_decision ON public.approvals USING btree (approver_id, decision);
CREATE INDEX idx_audit_logs_actor ON public.audit_logs USING btree (actor_id);
CREATE INDEX idx_audit_logs_created_at ON public.audit_logs USING btree (created_at DESC);
CREATE INDEX idx_audit_logs_entity ON public.audit_logs USING btree (entity_type, entity_id, created_at DESC);
CREATE INDEX idx_comments_author ON public.comments USING btree (author_id);
CREATE INDEX idx_comments_document ON public.comments USING btree (document_id);
CREATE INDEX idx_deadlines_assigned_to ON public.deadlines USING btree (assigned_to);
CREATE INDEX idx_deadlines_assignee_due ON public.deadlines USING btree (assigned_to, due_at) WHERE (status = 'open'::text);
CREATE INDEX idx_deadlines_document ON public.deadlines USING btree (document_id);
CREATE INDEX idx_deadlines_due ON public.deadlines USING btree (due_at) WHERE (status = 'open'::text);
CREATE INDEX idx_deadlines_open_due ON public.deadlines USING btree (status, due_at);
CREATE INDEX idx_departments_parent ON public.departments USING btree (parent_id);
CREATE INDEX idx_assignments_assignee_status ON public.document_assignments USING btree (assignee_id, assignment_status);
CREATE INDEX idx_assignments_document ON public.document_assignments USING btree (document_id);
CREATE INDEX idx_document_assignments_assigned_by ON public.document_assignments USING btree (assigned_by);
CREATE INDEX idx_document_assignments_assignee_status ON public.document_assignments USING btree (assignee_id, assignment_status, assigned_at DESC);
CREATE INDEX idx_document_files_drive ON public.document_files USING btree (google_drive_file_id);
CREATE INDEX idx_document_files_uploaded_by ON public.document_files USING btree (uploaded_by);
CREATE UNIQUE INDEX uq_document_files_current_role ON public.document_files USING btree (document_id, file_role) WHERE (is_current = true);
CREATE INDEX idx_document_status_history_changed_by ON public.document_status_history USING btree (changed_by);
CREATE INDEX idx_status_history_document ON public.document_status_history USING btree (document_id, changed_at DESC);
CREATE INDEX idx_documents_created_at ON public.documents USING btree (created_at DESC);
CREATE INDEX idx_documents_created_by ON public.documents USING btree (created_by);
CREATE INDEX idx_documents_owner ON public.documents USING btree (current_owner_id);
CREATE INDEX idx_documents_register ON public.documents USING btree (register_id);
CREATE INDEX idx_documents_status ON public.documents USING btree (status);
CREATE INDEX idx_documents_status_urgency_created ON public.documents USING btree (status, urgency, created_at DESC);
CREATE INDEX idx_documents_subject ON public.documents USING gin (to_tsvector('simple'::regconfig, subject));
CREATE INDEX idx_documents_subject_trgm ON public.documents USING gin (subject gin_trgm_ops);
CREATE INDEX idx_documents_urgency ON public.documents USING btree (urgency);
CREATE INDEX idx_google_drive_files_created_by ON public.google_drive_files USING btree (created_by);
CREATE INDEX idx_incoming_external_no ON public.incoming_document_details USING btree (external_document_no);
CREATE INDEX idx_incoming_registered_no ON public.incoming_document_details USING btree (registered_number);
CREATE INDEX idx_incoming_sender ON public.incoming_document_details USING btree (sender_id);
CREATE INDEX idx_notifications_document ON public.notifications USING btree (document_id);
CREATE INDEX idx_notifications_recipient_unread ON public.notifications USING btree (recipient_id, created_at DESC) WHERE (read_at IS NULL);
CREATE INDEX idx_outgoing_registered_no ON public.outgoing_document_details USING btree (registered_number);
CREATE INDEX idx_profiles_department ON public.profiles USING btree (department_id);
CREATE INDEX idx_push_subscriptions_user ON public.push_subscriptions USING btree (user_id);
CREATE INDEX idx_role_permissions_permission ON public.role_permissions USING btree (permission_id);
CREATE INDEX idx_senders_org_trgm ON public.senders USING gin (organization_name gin_trgm_ops);
CREATE INDEX idx_user_roles_assigned_by ON public.user_roles USING btree (assigned_by);
CREATE INDEX idx_user_roles_role ON public.user_roles USING btree (role_id);


-- Functions captured from live catalog (not a security approval).
CREATE OR REPLACE FUNCTION public.admin_create_department(p_code text, p_name text, p_parent_id uuid DEFAULT NULL::uuid)
 RETURNS departments
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
declare v public.departments;
begin
 if not private.has_permission('user.manage') and not private.has_permission('role.manage') then
   raise exception using errcode='42501',message='insufficient_privilege';
 end if;
 if btrim(coalesce(p_code,''))='' or btrim(coalesce(p_name,''))='' then
   raise exception using errcode='22023',message='department_code_and_name_required';
 end if;
 if exists(select 1 from public.departments where lower(code)=lower(btrim(p_code))) then
   raise exception using errcode='23505',message='department_code_exists';
 end if;
 insert into public.departments(code,name,parent_id,is_active)
 values(btrim(p_code),btrim(p_name),p_parent_id,true)
 returning * into v;
 return v;
end $function$;


CREATE OR REPLACE FUNCTION public.admin_remove_user_role(p_user_id uuid, p_role_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
begin
  if not private.has_permission('user.manage') and not private.has_permission('role.manage') then
    raise exception using errcode='42501',message='insufficient_privilege';
  end if;
  delete from public.user_roles where user_id=p_user_id and role_id=p_role_id;
end $function$;


CREATE OR REPLACE FUNCTION public.admin_set_user_department(p_user_id uuid, p_department_id uuid DEFAULT NULL::uuid)
 RETURNS profiles
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
declare
  v public.profiles;
  old_department uuid;
begin
  if auth.uid() is null then
    raise exception using errcode='42501',message='authentication_required';
  end if;

  if not private.has_permission('user.manage') and not private.has_permission('role.manage') then
    raise exception using errcode='42501',message='insufficient_privilege';
  end if;

  if not exists(select 1 from public.profiles where id=p_user_id) then
    raise exception using errcode='22023',message='user_profile_not_found';
  end if;

  if p_department_id is not null
     and not exists(select 1 from public.departments where id=p_department_id and is_active=true) then
    raise exception using errcode='22023',message='active_department_not_found';
  end if;

  select department_id into old_department
  from public.profiles
  where id=p_user_id;

  update public.profiles
     set department_id=p_department_id,
         updated_at=now()
   where id=p_user_id
   returning * into v;

  insert into public.audit_logs(
    actor_id,action,entity_type,entity_id,old_data,new_data
  )
  values(
    auth.uid(),
    'user_department_changed',
    'profile',
    p_user_id,
    jsonb_build_object('department_id',old_department),
    jsonb_build_object('department_id',p_department_id)
  );

  return v;
end
$function$;


CREATE OR REPLACE FUNCTION public.admin_set_user_role(p_user_id uuid, p_role_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
begin
  if not private.has_permission('user.manage') and not private.has_permission('role.manage') then
    raise exception using errcode='42501',message='insufficient_privilege';
  end if;
  if not exists(select 1 from public.profiles where id=p_user_id) then raise exception using errcode='22023',message='user_profile_not_found'; end if;
  if not exists(select 1 from public.roles where id=p_role_id) then raise exception using errcode='22023',message='role_not_found'; end if;
  insert into public.user_roles(user_id,role_id,assigned_by)
  values(p_user_id,p_role_id,auth.uid())
  on conflict (user_id,role_id) do nothing;
end $function$;


CREATE OR REPLACE FUNCTION public.admin_update_department(p_department_id uuid, p_code text, p_name text, p_parent_id uuid, p_is_active boolean)
 RETURNS departments
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
declare v public.departments;
begin
 if not private.has_permission('user.manage') and not private.has_permission('role.manage') then
   raise exception using errcode='42501',message='insufficient_privilege';
 end if;
 if not exists(select 1 from public.departments where id=p_department_id) then
   raise exception using errcode='22023',message='department_not_found';
 end if;
 if btrim(coalesce(p_code,''))='' or btrim(coalesce(p_name,''))='' then
   raise exception using errcode='22023',message='department_code_and_name_required';
 end if;
 if exists(select 1 from public.departments where lower(code)=lower(btrim(p_code)) and id<>p_department_id) then
   raise exception using errcode='23505',message='department_code_exists';
 end if;
 update public.departments
 set code=btrim(p_code),name=btrim(p_name),parent_id=p_parent_id,is_active=coalesce(p_is_active,true),updated_at=now()
 where id=p_department_id
 returning * into v;
 return v;
end $function$;


CREATE OR REPLACE FUNCTION public.assign_document(p_document_id uuid, p_assignee_id uuid, p_instructions text DEFAULT NULL::text, p_due_at timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
declare v_id uuid; v_actor uuid:=auth.uid(); v_subject text; v_old document_status;
begin
 if v_actor is null or not private.has_permission('document.assign') then raise exception 'permission_denied'; end if;
 if not exists(select 1 from public.documents where id=p_document_id) then raise exception 'document_not_found'; end if;
 if not exists(select 1 from public.profiles where id=p_assignee_id and is_active=true) then raise exception 'assignee_not_found'; end if;
 if p_due_at is not null and p_due_at<=now() then raise exception 'deadline_must_be_future'; end if;
 select status,subject into v_old,v_subject from public.documents where id=p_document_id for update;
 if v_old<>'registered' then raise exception 'invalid_status_transition'; end if;
 insert into public.document_assignments(document_id,assignee_id,assigned_by,instructions,assignment_status) values(p_document_id,p_assignee_id,v_actor,p_instructions,'assigned') returning id into v_id;
 update public.documents set current_owner_id=p_assignee_id,status='assigned' where id=p_document_id;
 insert into public.document_status_history(document_id,from_status,to_status,changed_by,reason) values(p_document_id,v_old,'assigned',v_actor,'มอบหมายงาน');
 insert into public.notifications(recipient_id,document_id,type,title,body,priority) values(p_assignee_id,p_document_id,'assignment','ได้รับมอบหมายงาน','คุณได้รับมอบหมายเรื่อง: '||coalesce(v_subject,'ไม่ระบุเรื่อง'),'high');
 if p_due_at is not null then insert into public.deadlines(document_id,assigned_to,due_at,reminder_at,escalation_at,status) values(p_document_id,p_assignee_id,p_due_at,p_due_at-interval '24 hours',p_due_at,'open'); end if;
 return v_id;
end $function$;


CREATE OR REPLACE FUNCTION public.attach_document_file_version(p_document_id uuid, p_google_drive_file_id uuid, p_file_role text DEFAULT 'main'::text)
 RETURNS TABLE(id uuid, document_id uuid, google_drive_file_id uuid, file_role text, version_no integer, is_current boolean, uploaded_by uuid, uploaded_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
declare
  v_id uuid;
  v_version integer;
begin
  if auth.uid() is null then
    raise exception using errcode='42501',message='authentication_required';
  end if;

  if not private.has_permission('document.update') then
    raise exception using errcode='42501',message='insufficient_privilege';
  end if;

  if p_file_role is null or btrim(p_file_role)='' then
    raise exception using errcode='22023',message='file_role_required';
  end if;

  if not exists(select 1 from public.documents where public.documents.id=p_document_id) then
    raise exception using errcode='22023',message='document_not_found';
  end if;

  if not exists(select 1 from public.google_drive_files where id=p_google_drive_file_id) then
    raise exception using errcode='22023',message='google_drive_file_not_found';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(p_document_id::text || ':' || p_file_role, 0)
  );

  select coalesce(max(df.version_no),0)+1
    into v_version
  from public.document_files df
  where df.document_id=p_document_id
    and df.file_role=p_file_role;

  update public.document_files
     set is_current=false
   where document_id=p_document_id
     and file_role=p_file_role
     and is_current=true;

  update public.google_drive_files
     set created_by=coalesce(created_by,auth.uid())
   where id=p_google_drive_file_id;

  insert into public.document_files(
    document_id,google_drive_file_id,file_role,version_no,is_current,uploaded_by
  )
  values(
    p_document_id,p_google_drive_file_id,p_file_role,v_version,true,auth.uid()
  )
  returning document_files.id into v_id;

  return query
  select df.id,df.document_id,df.google_drive_file_id,df.file_role,
         df.version_no,df.is_current,df.uploaded_by,df.uploaded_at
  from public.document_files df
  where df.id=v_id;
end
$function$;


CREATE OR REPLACE FUNCTION public.create_approval(p_document_id uuid, p_approver_id uuid, p_approval_step integer DEFAULT 1)
 RETURNS uuid
 LANGUAGE sql
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$select private.create_approval($1,$2,$3)$function$;


CREATE OR REPLACE FUNCTION public.decide_approval(p_approval_id uuid, p_decision approval_decision, p_comment text DEFAULT NULL::text)
 RETURNS boolean
 LANGUAGE sql
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$select private.decide_approval($1,$2,$3)$function$;


CREATE OR REPLACE FUNCTION public.get_my_permissions()
 RETURNS TABLE(permission_code text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
  select distinct p.code
  from public.user_roles ur
  join public.role_permissions rp on rp.role_id=ur.role_id
  join public.permissions p on p.id=rp.permission_id
  join public.profiles pr on pr.id=ur.user_id
  where ur.user_id=auth.uid()
    and pr.is_active=true
  order by p.code;
$function$;


CREATE OR REPLACE FUNCTION public.register_incoming_document(p_subject text, p_sender_id uuid, p_external_document_no text DEFAULT NULL::text, p_external_document_date date DEFAULT NULL::date, p_received_at timestamp with time zone DEFAULT now(), p_urgency urgency_level DEFAULT 'normal'::urgency_level, p_receiving_notes text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE sql
 SET search_path TO 'pg_catalog', 'public'
AS $function$select private.register_incoming_document($1,$2,$3,$4,$5,$6,$7);$function$;


CREATE OR REPLACE FUNCTION public.register_outgoing_document(p_subject text, p_recipient_name text, p_recipient_address text DEFAULT NULL::text, p_recipient_contact text DEFAULT NULL::text, p_document_date date DEFAULT NULL::date, p_urgency urgency_level DEFAULT 'normal'::urgency_level)
 RETURNS uuid
 LANGUAGE sql
 SET search_path TO 'pg_catalog', 'public'
AS $function$select private.register_outgoing_document($1,$2,$3,$4,$5,$6);$function$;


CREATE OR REPLACE FUNCTION public.set_document_deadline(p_document_id uuid, p_assigned_to uuid, p_due_at timestamp with time zone, p_reminder_at timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
declare v_id uuid; v_actor uuid:=auth.uid();
begin
 if v_actor is null or not private.has_permission('document.assign') then raise exception 'permission_denied'; end if;
 if not exists(select 1 from public.documents where id=p_document_id) then raise exception 'document_not_found'; end if;
 if not exists(select 1 from public.profiles where id=p_assigned_to and is_active=true) then raise exception 'assignee_not_found'; end if;
 if p_due_at<=now() then raise exception 'deadline_must_be_future'; end if;
 if p_reminder_at is not null and p_reminder_at>p_due_at then raise exception 'reminder_must_be_before_deadline'; end if;
 insert into public.deadlines(document_id,assigned_to,due_at,reminder_at,escalation_at,status) values(p_document_id,p_assigned_to,p_due_at,coalesce(p_reminder_at,p_due_at-interval '24 hours'),p_due_at,'open') returning id into v_id;
 return v_id;
end $function$;


CREATE OR REPLACE FUNCTION public.set_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public'
AS $function$
begin
  new.updated_at = now();
  return new;
end;
$function$;


CREATE OR REPLACE FUNCTION public.update_document_status(p_document_id uuid, p_to_status document_status, p_reason text DEFAULT NULL::text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
declare
  v_actor uuid := auth.uid();
  v_from public.document_status;
begin
  if v_actor is null then
    raise exception 'permission_denied';
  end if;

  select status into v_from
  from public.documents
  where id = p_document_id
  for update;

  if v_from is null then
    raise exception 'document_not_found';
  end if;

  if v_from = p_to_status then
    return true;
  end if;

  -- These transitions have mandatory side effects and must use their dedicated RPCs.
  if p_to_status in ('pending_approval', 'approved', 'assigned')
     or (v_from = 'pending_approval' and p_to_status = 'draft') then
    raise exception 'use_dedicated_workflow_rpc';
  end if;

  if p_to_status = 'completed' then
    if not private.has_permission('document.complete') then
      raise exception 'permission_denied';
    end if;
  elsif p_to_status = 'archived' then
    if not private.has_permission('document.archive') then
      raise exception 'permission_denied';
    end if;
  elsif not private.has_permission('document.update') then
    raise exception 'permission_denied';
  end if;

  if not private.is_valid_document_transition(p_document_id, v_from, p_to_status) then
    raise exception 'invalid_status_transition';
  end if;

  update public.documents
     set status = p_to_status
   where id = p_document_id;

  insert into public.document_status_history
    (document_id, from_status, to_status, changed_by, reason)
  values
    (p_document_id, v_from, p_to_status, v_actor, p_reason);

  if p_to_status in ('completed', 'archived') then
    update public.deadlines
       set status = 'completed',
           completed_at = coalesce(completed_at, now())
     where document_id = p_document_id
       and status = 'open';
  end if;

  return true;
end
$function$;


CREATE OR REPLACE FUNCTION private.allocate_document_number(p_register_id uuid, p_year integer)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$declare v_number bigint;begin if not private.has_permission('registry.incoming.manage') and not private.has_permission('registry.outgoing.manage') then raise exception 'permission denied';end if;insert into public.number_sequences(register_id,year,current_number) values(p_register_id,p_year,0) on conflict(register_id,year) do nothing;update public.number_sequences set current_number=current_number+1,updated_at=now() where register_id=p_register_id and year=p_year returning current_number into v_number;return v_number;end;$function$;


CREATE OR REPLACE FUNCTION private.assign_document(p_document_id uuid, p_assignee_id uuid, p_instructions text DEFAULT NULL::text, p_due_at timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
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
$function$;


CREATE OR REPLACE FUNCTION private.audit_row_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
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
end $function$;


CREATE OR REPLACE FUNCTION private.create_approval(p_document_id uuid, p_approver_id uuid, p_approval_step integer DEFAULT 1)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  v_id uuid;
  v_actor uuid := auth.uid();
  v_subject text;
  v_status public.document_status;
begin
  if v_actor is null or not private.has_permission('document.approve') then
    raise exception 'permission_denied';
  end if;

  if p_approval_step < 1 then
    raise exception 'invalid_approval_step';
  end if;

  if not exists (
    select 1
    from public.profiles pr
    join public.user_roles ur on ur.user_id = pr.id
    join public.role_permissions rp on rp.role_id = ur.role_id
    join public.permissions p on p.id = rp.permission_id
    where pr.id = p_approver_id
      and pr.is_active = true
      and p.code = 'document.approve'
  ) then
    raise exception 'approver_not_authorized';
  end if;

  select status, subject into v_status, v_subject
  from public.documents
  where id = p_document_id
  for update;

  if v_status is null then
    raise exception 'document_not_found';
  end if;

  if v_status <> 'draft' then
    raise exception 'document_not_in_draft';
  end if;

  insert into public.approvals(document_id, approval_step, approver_id, decision)
  values (p_document_id, p_approval_step, p_approver_id, 'pending')
  returning id into v_id;

  update public.documents set status = 'pending_approval' where id = p_document_id;

  insert into public.notifications(recipient_id, document_id, type, title, body, priority)
  values (
    p_approver_id, p_document_id, 'approval', 'รอการอนุมัติ',
    'มีเอกสารรอการอนุมัติ: ' || coalesce(v_subject, 'ไม่ระบุเรื่อง'), 'high'
  );

  return v_id;
end;
$function$;


CREATE OR REPLACE FUNCTION private.decide_approval(p_approval_id uuid, p_decision approval_decision, p_comment text DEFAULT NULL::text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
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
$function$;


CREATE OR REPLACE FUNCTION private.has_permission(p_permission text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$select exists(select 1 from public.user_roles ur join public.role_permissions rp on rp.role_id=ur.role_id join public.permissions p on p.id=rp.permission_id join public.profiles pr on pr.id=ur.user_id where ur.user_id=(select auth.uid()) and pr.is_active=true and p.code=p_permission);$function$;


CREATE OR REPLACE FUNCTION private.is_admin()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$select private.has_permission('settings.manage');$function$;


CREATE OR REPLACE FUNCTION private.is_valid_document_transition(p_document_id uuid, p_from document_status, p_to document_status)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
declare v_type text;
begin
  select document_type::text into v_type from public.documents where id=p_document_id;
  if v_type is null then return false; end if;
  if p_to='cancelled' and p_from not in ('completed','archived','cancelled') then return true; end if;
  if p_from='draft' and p_to='pending_approval' then return true; end if;
  if p_from='pending_approval' and p_to in ('approved','draft') then return true; end if;
  if p_from='approved' and p_to='received' then return v_type='incoming'; end if;
  if p_from='approved' and p_to='sent' then return v_type='outgoing'; end if;
  if p_from='received' and p_to='registered' then return v_type='incoming'; end if;
  if p_from='registered' and p_to='assigned' then return true; end if;
  if p_from='assigned' and p_to='in_progress' then return true; end if;
  if p_from='in_progress' and p_to='completed' then return true; end if;
  if p_from='completed' and p_to='archived' then return true; end if;
  if p_from='sent' and p_to='archived' then return v_type='outgoing'; end if;
  return false;
end $function$;


CREATE OR REPLACE FUNCTION private.process_deadline_notifications()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
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
end $function$;


CREATE OR REPLACE FUNCTION private.register_incoming_document(p_subject text, p_sender_id uuid, p_external_document_no text DEFAULT NULL::text, p_external_document_date date DEFAULT NULL::date, p_received_at timestamp with time zone DEFAULT now(), p_urgency urgency_level DEFAULT 'normal'::urgency_level, p_receiving_notes text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
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
end $function$;


CREATE OR REPLACE FUNCTION private.register_outgoing_document(p_subject text, p_recipient_name text, p_recipient_address text DEFAULT NULL::text, p_recipient_contact text DEFAULT NULL::text, p_document_date date DEFAULT NULL::date, p_urgency urgency_level DEFAULT 'normal'::urgency_level)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
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
end $function$;


CREATE OR REPLACE FUNCTION private.set_document_deadline(p_document_id uuid, p_assigned_to uuid, p_due_at timestamp with time zone, p_reminder_at timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare v_id uuid; v_actor uuid := auth.uid();
begin
  if v_actor is null or not private.has_permission('document.assign') then raise exception 'permission_denied'; end if;
  if p_due_at <= now() then raise exception 'deadline_must_be_future'; end if;

  insert into public.deadlines(document_id,assigned_to,due_at,reminder_at,escalation_at,status)
  values(p_document_id,p_assigned_to,p_due_at,coalesce(p_reminder_at,p_due_at-interval '24 hours'),p_due_at,'open')
  returning id into v_id;
  return v_id;
end;
$function$;


CREATE OR REPLACE FUNCTION private.update_document_status(p_document_id uuid, p_to_status document_status, p_reason text DEFAULT NULL::text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
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
$function$;


-- Views
CREATE OR REPLACE VIEW public."document_monthly_summary" WITH (security_invoker=true) AS
 SELECT date_trunc('month'::text, created_at)::date AS month,
    document_type,
    count(*) AS total_documents,
    count(*) FILTER (WHERE status = 'completed'::document_status) AS completed_documents,
    count(*) FILTER (WHERE urgency = ANY (ARRAY['urgent'::urgency_level, 'very_urgent'::urgency_level, 'critical'::urgency_level])) AS urgent_documents
   FROM documents
  GROUP BY (date_trunc('month'::text, created_at)::date), document_type
  ORDER BY (date_trunc('month'::text, created_at)::date) DESC;;

CREATE OR REPLACE VIEW public."document_report_summary" WITH (security_invoker=true) AS
 SELECT document_type,
    status,
    urgency,
    count(*) AS total_documents,
    count(*) FILTER (WHERE created_at >= date_trunc('month'::text, now())) AS current_month
   FROM documents
  GROUP BY document_type, status, urgency;;

-- Triggers
CREATE TRIGGER audit_approvals AFTER INSERT OR DELETE OR UPDATE ON approvals FOR EACH ROW EXECUTE FUNCTION private.audit_row_change();
CREATE TRIGGER audit_deadlines AFTER INSERT OR DELETE OR UPDATE ON deadlines FOR EACH ROW EXECUTE FUNCTION private.audit_row_change();
CREATE TRIGGER departments_updated_at BEFORE UPDATE ON departments FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER audit_document_assignments AFTER INSERT OR DELETE OR UPDATE ON document_assignments FOR EACH ROW EXECUTE FUNCTION private.audit_row_change();
CREATE TRIGGER audit_document_files AFTER INSERT OR DELETE OR UPDATE ON document_files FOR EACH ROW EXECUTE FUNCTION private.audit_row_change();
CREATE TRIGGER audit_documents AFTER INSERT OR DELETE OR UPDATE ON documents FOR EACH ROW EXECUTE FUNCTION private.audit_row_change();
CREATE TRIGGER documents_updated_at BEFORE UPDATE ON documents FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER number_sequences_updated_at BEFORE UPDATE ON number_sequences FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER profiles_updated_at BEFORE UPDATE ON profiles FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER senders_updated_at BEFORE UPDATE ON senders FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- RLS settings
ALTER TABLE public."approvals" ENABLE ROW LEVEL SECURITY;
ALTER TABLE public."audit_logs" ENABLE ROW LEVEL SECURITY;
ALTER TABLE public."comments" ENABLE ROW LEVEL SECURITY;
ALTER TABLE public."deadlines" ENABLE ROW LEVEL SECURITY;
ALTER TABLE public."departments" ENABLE ROW LEVEL SECURITY;
ALTER TABLE public."document_assignments" ENABLE ROW LEVEL SECURITY;
ALTER TABLE public."document_files" ENABLE ROW LEVEL SECURITY;
ALTER TABLE public."document_registers" ENABLE ROW LEVEL SECURITY;
ALTER TABLE public."document_status_history" ENABLE ROW LEVEL SECURITY;
ALTER TABLE public."documents" ENABLE ROW LEVEL SECURITY;
ALTER TABLE public."google_drive_files" ENABLE ROW LEVEL SECURITY;
ALTER TABLE public."incoming_document_details" ENABLE ROW LEVEL SECURITY;
ALTER TABLE public."notifications" ENABLE ROW LEVEL SECURITY;
ALTER TABLE public."number_sequences" ENABLE ROW LEVEL SECURITY;
ALTER TABLE public."outgoing_document_details" ENABLE ROW LEVEL SECURITY;
ALTER TABLE public."permissions" ENABLE ROW LEVEL SECURITY;
ALTER TABLE public."profiles" ENABLE ROW LEVEL SECURITY;
ALTER TABLE public."push_subscriptions" ENABLE ROW LEVEL SECURITY;
ALTER TABLE public."role_permissions" ENABLE ROW LEVEL SECURITY;
ALTER TABLE public."roles" ENABLE ROW LEVEL SECURITY;
ALTER TABLE public."senders" ENABLE ROW LEVEL SECURITY;
ALTER TABLE public."user_roles" ENABLE ROW LEVEL SECURITY;
CREATE POLICY "approvals_insert_authorized" ON public."approvals" AS PERMISSIVE FOR INSERT TO "authenticated"
 WITH CHECK (((approver_id = ( SELECT auth.uid() AS uid)) AND private.has_permission('document.approve'::text)));
CREATE POLICY "approvals_select_authorized" ON public."approvals" AS PERMISSIVE FOR SELECT TO "authenticated"
 USING (((approver_id = ( SELECT auth.uid() AS uid)) OR private.has_permission('document.view'::text)));
CREATE POLICY "approvals_update_authorized" ON public."approvals" AS PERMISSIVE FOR UPDATE TO "authenticated"
 USING (((approver_id = ( SELECT auth.uid() AS uid)) AND private.has_permission('document.approve'::text)))
 WITH CHECK (((approver_id = ( SELECT auth.uid() AS uid)) AND private.has_permission('document.approve'::text)));
CREATE POLICY "audit_logs_admin_read" ON public."audit_logs" AS PERMISSIVE FOR SELECT TO "authenticated"
 USING (private.has_permission('audit.view'::text));
CREATE POLICY "comments_insert_own" ON public."comments" AS PERMISSIVE FOR INSERT TO "authenticated"
 WITH CHECK ((author_id = ( SELECT auth.uid() AS uid)));
CREATE POLICY "comments_select_authorized" ON public."comments" AS PERMISSIVE FOR SELECT TO "authenticated"
 USING ((EXISTS ( SELECT 1
   FROM documents d
  WHERE (d.id = comments.document_id))));
CREATE POLICY "comments_update_own" ON public."comments" AS PERMISSIVE FOR UPDATE TO "authenticated"
 USING ((author_id = ( SELECT auth.uid() AS uid)))
 WITH CHECK ((author_id = ( SELECT auth.uid() AS uid)));
CREATE POLICY "deadlines_manage_authorized" ON public."deadlines" AS PERMISSIVE FOR ALL TO "authenticated"
 USING (((assigned_to = ( SELECT auth.uid() AS uid)) OR private.has_permission('document.assign'::text)))
 WITH CHECK (((assigned_to = ( SELECT auth.uid() AS uid)) OR private.has_permission('document.assign'::text)));
CREATE POLICY "deadlines_select_authorized" ON public."deadlines" AS PERMISSIVE FOR SELECT TO "authenticated"
 USING (((assigned_to = ( SELECT auth.uid() AS uid)) OR private.has_permission('document.view'::text)));
CREATE POLICY "departments_manage_admin" ON public."departments" AS PERMISSIVE FOR ALL TO "authenticated"
 USING (private.has_permission('settings.manage'::text))
 WITH CHECK (private.has_permission('settings.manage'::text));
CREATE POLICY "departments_select_authenticated" ON public."departments" AS PERMISSIVE FOR SELECT TO "authenticated"
 USING (true);
CREATE POLICY "assignments_insert_authorized" ON public."document_assignments" AS PERMISSIVE FOR INSERT TO "authenticated"
 WITH CHECK (((assigned_by = ( SELECT auth.uid() AS uid)) AND private.has_permission('document.assign'::text)));
CREATE POLICY "assignments_select_authorized" ON public."document_assignments" AS PERMISSIVE FOR SELECT TO "authenticated"
 USING (((assignee_id = ( SELECT auth.uid() AS uid)) OR (assigned_by = ( SELECT auth.uid() AS uid)) OR private.has_permission('document.view'::text)));
CREATE POLICY "assignments_update_authorized" ON public."document_assignments" AS PERMISSIVE FOR UPDATE TO "authenticated"
 USING (((assignee_id = ( SELECT auth.uid() AS uid)) OR (assigned_by = ( SELECT auth.uid() AS uid)) OR private.has_permission('document.assign'::text)))
 WITH CHECK (((assignee_id = ( SELECT auth.uid() AS uid)) OR (assigned_by = ( SELECT auth.uid() AS uid)) OR private.has_permission('document.assign'::text)));
CREATE POLICY "document_files_authorized" ON public."document_files" AS PERMISSIVE FOR SELECT TO "authenticated"
 USING ((EXISTS ( SELECT 1
   FROM documents d
  WHERE (d.id = document_files.document_id))));
CREATE POLICY "registers_manage_registry" ON public."document_registers" AS PERMISSIVE FOR ALL TO "authenticated"
 USING ((private.has_permission('settings.manage'::text) OR private.has_permission('registry.incoming.manage'::text) OR private.has_permission('registry.outgoing.manage'::text)))
 WITH CHECK ((private.has_permission('settings.manage'::text) OR private.has_permission('registry.incoming.manage'::text) OR private.has_permission('registry.outgoing.manage'::text)));
CREATE POLICY "registers_select_authorized" ON public."document_registers" AS PERMISSIVE FOR SELECT TO "authenticated"
 USING ((private.has_permission('document.view'::text) OR private.has_permission('registry.incoming.manage'::text) OR private.has_permission('registry.outgoing.manage'::text)));
CREATE POLICY "status_history_select_authorized" ON public."document_status_history" AS PERMISSIVE FOR SELECT TO "authenticated"
 USING ((EXISTS ( SELECT 1
   FROM documents d
  WHERE (d.id = document_status_history.document_id))));
CREATE POLICY "documents_insert_authorized" ON public."documents" AS PERMISSIVE FOR INSERT TO "authenticated"
 WITH CHECK (((created_by = ( SELECT auth.uid() AS uid)) AND private.has_permission('document.create'::text)));
CREATE POLICY "documents_select_authorized" ON public."documents" AS PERMISSIVE FOR SELECT TO "authenticated"
 USING (((current_owner_id = ( SELECT auth.uid() AS uid)) OR (created_by = ( SELECT auth.uid() AS uid)) OR private.has_permission('document.view'::text)));
CREATE POLICY "documents_update_authorized" ON public."documents" AS PERMISSIVE FOR UPDATE TO "authenticated"
 USING (((current_owner_id = ( SELECT auth.uid() AS uid)) OR (created_by = ( SELECT auth.uid() AS uid)) OR private.has_permission('document.update'::text) OR private.has_permission('document.assign'::text) OR private.has_permission('document.approve'::text)))
 WITH CHECK (((current_owner_id = ( SELECT auth.uid() AS uid)) OR (created_by = ( SELECT auth.uid() AS uid)) OR private.has_permission('document.update'::text) OR private.has_permission('document.assign'::text) OR private.has_permission('document.approve'::text)));
CREATE POLICY "google_drive_files_authorized" ON public."google_drive_files" AS PERMISSIVE FOR SELECT TO "authenticated"
 USING (private.has_permission('document.view'::text));
CREATE POLICY "incoming_details_insert_registry" ON public."incoming_document_details" AS PERMISSIVE FOR INSERT TO "authenticated"
 WITH CHECK (private.has_permission('registry.incoming.manage'::text));
CREATE POLICY "incoming_details_select_authorized" ON public."incoming_document_details" AS PERMISSIVE FOR SELECT TO "authenticated"
 USING ((EXISTS ( SELECT 1
   FROM documents d
  WHERE (d.id = incoming_document_details.document_id))));
CREATE POLICY "incoming_details_update_registry" ON public."incoming_document_details" AS PERMISSIVE FOR UPDATE TO "authenticated"
 USING (private.has_permission('registry.incoming.manage'::text))
 WITH CHECK (private.has_permission('registry.incoming.manage'::text));
CREATE POLICY "notifications_own" ON public."notifications" AS PERMISSIVE FOR SELECT TO "authenticated"
 USING ((recipient_id = ( SELECT auth.uid() AS uid)));
CREATE POLICY "notifications_update_own" ON public."notifications" AS PERMISSIVE FOR UPDATE TO "authenticated"
 USING ((recipient_id = ( SELECT auth.uid() AS uid)))
 WITH CHECK ((recipient_id = ( SELECT auth.uid() AS uid)));
CREATE POLICY "number_sequences_registry_read" ON public."number_sequences" AS PERMISSIVE FOR SELECT TO "authenticated"
 USING ((private.has_permission('registry.incoming.manage'::text) OR private.has_permission('registry.outgoing.manage'::text) OR private.has_permission('settings.manage'::text)));
CREATE POLICY "number_sequences_registry_update" ON public."number_sequences" AS PERMISSIVE FOR UPDATE TO "authenticated"
 USING ((private.has_permission('registry.incoming.manage'::text) OR private.has_permission('registry.outgoing.manage'::text) OR private.has_permission('settings.manage'::text)))
 WITH CHECK ((private.has_permission('registry.incoming.manage'::text) OR private.has_permission('registry.outgoing.manage'::text) OR private.has_permission('settings.manage'::text)));
CREATE POLICY "outgoing_details_insert_registry" ON public."outgoing_document_details" AS PERMISSIVE FOR INSERT TO "authenticated"
 WITH CHECK (private.has_permission('registry.outgoing.manage'::text));
CREATE POLICY "outgoing_details_select_authorized" ON public."outgoing_document_details" AS PERMISSIVE FOR SELECT TO "authenticated"
 USING ((EXISTS ( SELECT 1
   FROM documents d
  WHERE (d.id = outgoing_document_details.document_id))));
CREATE POLICY "outgoing_details_update_registry" ON public."outgoing_document_details" AS PERMISSIVE FOR UPDATE TO "authenticated"
 USING (private.has_permission('registry.outgoing.manage'::text))
 WITH CHECK (private.has_permission('registry.outgoing.manage'::text));
CREATE POLICY "permissions_manage_admin" ON public."permissions" AS PERMISSIVE FOR ALL TO "authenticated"
 USING (private.has_permission('role.manage'::text))
 WITH CHECK (private.has_permission('role.manage'::text));
CREATE POLICY "permissions_select_authenticated" ON public."permissions" AS PERMISSIVE FOR SELECT TO "authenticated"
 USING (true);
CREATE POLICY "profiles_select_self_or_admin" ON public."profiles" AS PERMISSIVE FOR SELECT TO "authenticated"
 USING (((id = ( SELECT auth.uid() AS uid)) OR private.has_permission('user.view'::text)));
CREATE POLICY "profiles_update_self_or_admin" ON public."profiles" AS PERMISSIVE FOR UPDATE TO "authenticated"
 USING (((id = ( SELECT auth.uid() AS uid)) OR private.has_permission('user.manage'::text)))
 WITH CHECK (((id = ( SELECT auth.uid() AS uid)) OR private.has_permission('user.manage'::text)));
CREATE POLICY "push_subscriptions_own" ON public."push_subscriptions" AS PERMISSIVE FOR ALL TO "authenticated"
 USING ((user_id = ( SELECT auth.uid() AS uid)))
 WITH CHECK ((user_id = ( SELECT auth.uid() AS uid)));
CREATE POLICY "role_permissions_manage_admin" ON public."role_permissions" AS PERMISSIVE FOR ALL TO "authenticated"
 USING (private.has_permission('role.manage'::text))
 WITH CHECK (private.has_permission('role.manage'::text));
CREATE POLICY "role_permissions_select_authenticated" ON public."role_permissions" AS PERMISSIVE FOR SELECT TO "authenticated"
 USING (true);
CREATE POLICY "roles_manage_admin" ON public."roles" AS PERMISSIVE FOR ALL TO "authenticated"
 USING (private.has_permission('role.manage'::text))
 WITH CHECK (private.has_permission('role.manage'::text));
CREATE POLICY "roles_select_authenticated" ON public."roles" AS PERMISSIVE FOR SELECT TO "authenticated"
 USING (true);
CREATE POLICY "senders_manage_registry" ON public."senders" AS PERMISSIVE FOR ALL TO "authenticated"
 USING (private.has_permission('registry.incoming.manage'::text))
 WITH CHECK (private.has_permission('registry.incoming.manage'::text));
CREATE POLICY "senders_select_registry" ON public."senders" AS PERMISSIVE FOR SELECT TO "authenticated"
 USING ((private.has_permission('document.view'::text) OR private.has_permission('registry.incoming.manage'::text)));
CREATE POLICY "user_roles_manage_admin" ON public."user_roles" AS PERMISSIVE FOR ALL TO "authenticated"
 USING (private.has_permission('role.manage'::text))
 WITH CHECK (private.has_permission('role.manage'::text));
CREATE POLICY "user_roles_select_self_or_admin" ON public."user_roles" AS PERMISSIVE FOR SELECT TO "authenticated"
 USING (((user_id = ( SELECT auth.uid() AS uid)) OR private.has_permission('user.view'::text)));

-- Reconstruct current API grants for isolated tests only.
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA public, private FROM PUBLIC, anon, authenticated, service_role;
GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public.approvals TO anon;
GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public.approvals TO authenticated;
GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public.approvals TO service_role;
GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public.audit_logs TO anon;
GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public.audit_logs TO authenticated;
GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public.audit_logs TO service_role;
GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public.comments TO anon;
GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public.comments TO authenticated;
GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public.comments TO service_role;
GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public.deadlines TO anon;
GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public.deadlines TO authenticated;
GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public.deadlines TO service_role;
GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public.departments TO anon;
GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public.departments TO authenticated;
GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public.departments TO service_role;
GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public.document_assignments TO anon;
GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public.document_assignments TO authenticated;
GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public.document_assignments TO service_role;
GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public.document_files TO anon;
GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public.document_files TO authenticated;
GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public.document_files TO service_role;
GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public.document_monthly_summary TO anon;
GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public.document_monthly_summary TO authenticated;
GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public.document_monthly_summary TO service_role;
GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public.document_registers TO anon;
GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public.document_registers TO authenticated;
GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public.document_registers TO service_role;
GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public.document_report_summary TO anon;
GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public.document_report_summary TO authenticated;
GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public.document_report_summary TO service_role;
GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public.document_status_history TO anon;
GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public.document_status_history TO authenticated;
GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public.document_status_history TO service_role;
GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public.documents TO anon;
GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public.documents TO authenticated;
GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public.documents TO service_role;
GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public.google_drive_files TO anon;
GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public.google_drive_files TO authenticated;
GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public.google_drive_files TO service_role;
GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public.incoming_document_details TO anon;
GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public.incoming_document_details TO authenticated;
GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public.incoming_document_details TO service_role;
GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public.notifications TO anon;
GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public.notifications TO authenticated;
GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public.notifications TO service_role;
GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public.number_sequences TO anon;
GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public.number_sequences TO authenticated;
GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public.number_sequences TO service_role;
GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public.outgoing_document_details TO anon;
GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public.outgoing_document_details TO authenticated;
GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public.outgoing_document_details TO service_role;
GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public.permissions TO anon;
GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public.permissions TO authenticated;
GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public.permissions TO service_role;
GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public.profiles TO anon;
GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public.profiles TO authenticated;
GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public.profiles TO service_role;
GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public.push_subscriptions TO anon;
GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public.push_subscriptions TO authenticated;
GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public.push_subscriptions TO service_role;
GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public.role_permissions TO anon;
GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public.role_permissions TO authenticated;
GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public.role_permissions TO service_role;
GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public.roles TO anon;
GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public.roles TO authenticated;
GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public.roles TO service_role;
GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public.senders TO anon;
GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public.senders TO authenticated;
GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public.senders TO service_role;
GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public.user_roles TO anon;
GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public.user_roles TO authenticated;
GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public.user_roles TO service_role;
GRANT EXECUTE ON FUNCTION admin_create_department(text,text,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION admin_create_department(text,text,uuid) TO service_role;
GRANT EXECUTE ON FUNCTION admin_remove_user_role(uuid,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION admin_remove_user_role(uuid,uuid) TO service_role;
GRANT EXECUTE ON FUNCTION admin_set_user_department(uuid,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION admin_set_user_department(uuid,uuid) TO service_role;
GRANT EXECUTE ON FUNCTION admin_set_user_role(uuid,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION admin_set_user_role(uuid,uuid) TO service_role;
GRANT EXECUTE ON FUNCTION admin_update_department(uuid,text,text,uuid,boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION admin_update_department(uuid,text,text,uuid,boolean) TO service_role;
GRANT EXECUTE ON FUNCTION assign_document(uuid,uuid,text,timestamp with time zone) TO authenticated;
GRANT EXECUTE ON FUNCTION assign_document(uuid,uuid,text,timestamp with time zone) TO service_role;
GRANT EXECUTE ON FUNCTION attach_document_file_version(uuid,uuid,text) TO authenticated;
GRANT EXECUTE ON FUNCTION attach_document_file_version(uuid,uuid,text) TO service_role;
GRANT EXECUTE ON FUNCTION create_approval(uuid,uuid,integer) TO authenticated;
GRANT EXECUTE ON FUNCTION create_approval(uuid,uuid,integer) TO service_role;
GRANT EXECUTE ON FUNCTION decide_approval(uuid,approval_decision,text) TO authenticated;
GRANT EXECUTE ON FUNCTION decide_approval(uuid,approval_decision,text) TO service_role;
GRANT EXECUTE ON FUNCTION get_my_permissions() TO authenticated;
GRANT EXECUTE ON FUNCTION get_my_permissions() TO service_role;
GRANT EXECUTE ON FUNCTION private.allocate_document_number(uuid,integer) TO PUBLIC;
GRANT EXECUTE ON FUNCTION private.allocate_document_number(uuid,integer) TO authenticated;
GRANT EXECUTE ON FUNCTION private.assign_document(uuid,uuid,text,timestamp with time zone) TO authenticated;
GRANT EXECUTE ON FUNCTION private.assign_document(uuid,uuid,text,timestamp with time zone) TO service_role;
GRANT EXECUTE ON FUNCTION private.create_approval(uuid,uuid,integer) TO authenticated;
GRANT EXECUTE ON FUNCTION private.create_approval(uuid,uuid,integer) TO service_role;
GRANT EXECUTE ON FUNCTION private.decide_approval(uuid,approval_decision,text) TO authenticated;
GRANT EXECUTE ON FUNCTION private.decide_approval(uuid,approval_decision,text) TO service_role;
GRANT EXECUTE ON FUNCTION private.has_permission(text) TO PUBLIC;
GRANT EXECUTE ON FUNCTION private.has_permission(text) TO authenticated;
GRANT EXECUTE ON FUNCTION private.is_admin() TO PUBLIC;
GRANT EXECUTE ON FUNCTION private.is_admin() TO authenticated;
GRANT EXECUTE ON FUNCTION private.register_incoming_document(text,uuid,text,date,timestamp with time zone,urgency_level,text) TO PUBLIC;
GRANT EXECUTE ON FUNCTION private.register_outgoing_document(text,text,text,text,date,urgency_level) TO PUBLIC;
GRANT EXECUTE ON FUNCTION private.set_document_deadline(uuid,uuid,timestamp with time zone,timestamp with time zone) TO authenticated;
GRANT EXECUTE ON FUNCTION private.set_document_deadline(uuid,uuid,timestamp with time zone,timestamp with time zone) TO service_role;
GRANT EXECUTE ON FUNCTION private.update_document_status(uuid,document_status,text) TO authenticated;
GRANT EXECUTE ON FUNCTION private.update_document_status(uuid,document_status,text) TO service_role;
GRANT EXECUTE ON FUNCTION register_incoming_document(text,uuid,text,date,timestamp with time zone,urgency_level,text) TO PUBLIC;
GRANT EXECUTE ON FUNCTION register_incoming_document(text,uuid,text,date,timestamp with time zone,urgency_level,text) TO anon;
GRANT EXECUTE ON FUNCTION register_incoming_document(text,uuid,text,date,timestamp with time zone,urgency_level,text) TO authenticated;
GRANT EXECUTE ON FUNCTION register_incoming_document(text,uuid,text,date,timestamp with time zone,urgency_level,text) TO service_role;
GRANT EXECUTE ON FUNCTION register_outgoing_document(text,text,text,text,date,urgency_level) TO PUBLIC;
GRANT EXECUTE ON FUNCTION register_outgoing_document(text,text,text,text,date,urgency_level) TO anon;
GRANT EXECUTE ON FUNCTION register_outgoing_document(text,text,text,text,date,urgency_level) TO authenticated;
GRANT EXECUTE ON FUNCTION register_outgoing_document(text,text,text,text,date,urgency_level) TO service_role;
GRANT EXECUTE ON FUNCTION set_document_deadline(uuid,uuid,timestamp with time zone,timestamp with time zone) TO authenticated;
GRANT EXECUTE ON FUNCTION set_document_deadline(uuid,uuid,timestamp with time zone,timestamp with time zone) TO service_role;
GRANT EXECUTE ON FUNCTION set_updated_at() TO PUBLIC;
GRANT EXECUTE ON FUNCTION set_updated_at() TO anon;
GRANT EXECUTE ON FUNCTION set_updated_at() TO authenticated;
GRANT EXECUTE ON FUNCTION set_updated_at() TO service_role;
GRANT EXECUTE ON FUNCTION update_document_status(uuid,document_status,text) TO authenticated;
GRANT EXECUTE ON FUNCTION update_document_status(uuid,document_status,text) TO service_role;
GRANT USAGE ON SCHEMA extensions TO anon;
GRANT USAGE ON SCHEMA extensions TO authenticated;
GRANT USAGE ON SCHEMA extensions TO service_role;
GRANT USAGE ON SCHEMA private TO authenticated;
GRANT USAGE ON SCHEMA public TO PUBLIC;
GRANT USAGE ON SCHEMA public TO anon;
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT USAGE ON SCHEMA public TO service_role;

-- Reference configuration only. No user, document, sender, audit, or file records are copied.
INSERT INTO public.roles(code,name,description) VALUES ('deputy_director','Deputy Director','Deputy director oversight and approval') ON CONFLICT (code) DO UPDATE SET name=EXCLUDED.name, description=EXCLUDED.description;
INSERT INTO public.roles(code,name,description) VALUES ('director','Director','Director oversight and approval') ON CONFLICT (code) DO UPDATE SET name=EXCLUDED.name, description=EXCLUDED.description;
INSERT INTO public.roles(code,name,description) VALUES ('registry_officer','Registry Officer','Correspondence registry operations') ON CONFLICT (code) DO UPDATE SET name=EXCLUDED.name, description=EXCLUDED.description;
INSERT INTO public.roles(code,name,description) VALUES ('school_admin','School Admin','School administration') ON CONFLICT (code) DO UPDATE SET name=EXCLUDED.name, description=EXCLUDED.description;
INSERT INTO public.roles(code,name,description) VALUES ('staff','Staff','School staff') ON CONFLICT (code) DO UPDATE SET name=EXCLUDED.name, description=EXCLUDED.description;
INSERT INTO public.roles(code,name,description) VALUES ('system_admin','System Admin','Technical system administration') ON CONFLICT (code) DO UPDATE SET name=EXCLUDED.name, description=EXCLUDED.description;
INSERT INTO public.roles(code,name,description) VALUES ('teacher','Teacher','Teaching staff') ON CONFLICT (code) DO UPDATE SET name=EXCLUDED.name, description=EXCLUDED.description;
INSERT INTO public.permissions(code,name,description) VALUES ('audit.view','View Audit Logs','View audit logs') ON CONFLICT (code) DO UPDATE SET name=EXCLUDED.name, description=EXCLUDED.description;
INSERT INTO public.permissions(code,name,description) VALUES ('dashboard.view','View Dashboard','View dashboard') ON CONFLICT (code) DO UPDATE SET name=EXCLUDED.name, description=EXCLUDED.description;
INSERT INTO public.permissions(code,name,description) VALUES ('document.approve','Approve Documents','Approve authorized documents') ON CONFLICT (code) DO UPDATE SET name=EXCLUDED.name, description=EXCLUDED.description;
INSERT INTO public.permissions(code,name,description) VALUES ('document.archive','Archive Documents','Archive documents') ON CONFLICT (code) DO UPDATE SET name=EXCLUDED.name, description=EXCLUDED.description;
INSERT INTO public.permissions(code,name,description) VALUES ('document.assign','Assign Documents','Assign/reassign work') ON CONFLICT (code) DO UPDATE SET name=EXCLUDED.name, description=EXCLUDED.description;
INSERT INTO public.permissions(code,name,description) VALUES ('document.complete','Complete Documents','Complete assigned work') ON CONFLICT (code) DO UPDATE SET name=EXCLUDED.name, description=EXCLUDED.description;
INSERT INTO public.permissions(code,name,description) VALUES ('document.create','Create Documents','Create documents') ON CONFLICT (code) DO UPDATE SET name=EXCLUDED.name, description=EXCLUDED.description;
INSERT INTO public.permissions(code,name,description) VALUES ('document.update','Update Documents','Update authorized documents') ON CONFLICT (code) DO UPDATE SET name=EXCLUDED.name, description=EXCLUDED.description;
INSERT INTO public.permissions(code,name,description) VALUES ('document.view','View Documents','Read authorized documents') ON CONFLICT (code) DO UPDATE SET name=EXCLUDED.name, description=EXCLUDED.description;
INSERT INTO public.permissions(code,name,description) VALUES ('registry.incoming.manage','Manage Incoming Registry','Receive/register incoming correspondence') ON CONFLICT (code) DO UPDATE SET name=EXCLUDED.name, description=EXCLUDED.description;
INSERT INTO public.permissions(code,name,description) VALUES ('registry.outgoing.manage','Manage Outgoing Registry','Prepare/register outgoing correspondence') ON CONFLICT (code) DO UPDATE SET name=EXCLUDED.name, description=EXCLUDED.description;
INSERT INTO public.permissions(code,name,description) VALUES ('report.view','View Reports','View reports') ON CONFLICT (code) DO UPDATE SET name=EXCLUDED.name, description=EXCLUDED.description;
INSERT INTO public.permissions(code,name,description) VALUES ('role.manage','Manage Roles','Manage roles and permissions') ON CONFLICT (code) DO UPDATE SET name=EXCLUDED.name, description=EXCLUDED.description;
INSERT INTO public.permissions(code,name,description) VALUES ('settings.manage','Manage Settings','Manage school settings') ON CONFLICT (code) DO UPDATE SET name=EXCLUDED.name, description=EXCLUDED.description;
INSERT INTO public.permissions(code,name,description) VALUES ('user.manage','Manage Users','Create/update/deactivate users') ON CONFLICT (code) DO UPDATE SET name=EXCLUDED.name, description=EXCLUDED.description;
INSERT INTO public.permissions(code,name,description) VALUES ('user.view','View Users','View users') ON CONFLICT (code) DO UPDATE SET name=EXCLUDED.name, description=EXCLUDED.description;
INSERT INTO public.role_permissions(role_id,permission_id) SELECT r.id,p.id FROM public.roles r CROSS JOIN public.permissions p WHERE r.code='deputy_director' AND p.code='dashboard.view' ON CONFLICT DO NOTHING;
INSERT INTO public.role_permissions(role_id,permission_id) SELECT r.id,p.id FROM public.roles r CROSS JOIN public.permissions p WHERE r.code='deputy_director' AND p.code='document.approve' ON CONFLICT DO NOTHING;
INSERT INTO public.role_permissions(role_id,permission_id) SELECT r.id,p.id FROM public.roles r CROSS JOIN public.permissions p WHERE r.code='deputy_director' AND p.code='document.view' ON CONFLICT DO NOTHING;
INSERT INTO public.role_permissions(role_id,permission_id) SELECT r.id,p.id FROM public.roles r CROSS JOIN public.permissions p WHERE r.code='deputy_director' AND p.code='report.view' ON CONFLICT DO NOTHING;
INSERT INTO public.role_permissions(role_id,permission_id) SELECT r.id,p.id FROM public.roles r CROSS JOIN public.permissions p WHERE r.code='director' AND p.code='dashboard.view' ON CONFLICT DO NOTHING;
INSERT INTO public.role_permissions(role_id,permission_id) SELECT r.id,p.id FROM public.roles r CROSS JOIN public.permissions p WHERE r.code='director' AND p.code='document.approve' ON CONFLICT DO NOTHING;
INSERT INTO public.role_permissions(role_id,permission_id) SELECT r.id,p.id FROM public.roles r CROSS JOIN public.permissions p WHERE r.code='director' AND p.code='document.view' ON CONFLICT DO NOTHING;
INSERT INTO public.role_permissions(role_id,permission_id) SELECT r.id,p.id FROM public.roles r CROSS JOIN public.permissions p WHERE r.code='director' AND p.code='report.view' ON CONFLICT DO NOTHING;
INSERT INTO public.role_permissions(role_id,permission_id) SELECT r.id,p.id FROM public.roles r CROSS JOIN public.permissions p WHERE r.code='registry_officer' AND p.code='dashboard.view' ON CONFLICT DO NOTHING;
INSERT INTO public.role_permissions(role_id,permission_id) SELECT r.id,p.id FROM public.roles r CROSS JOIN public.permissions p WHERE r.code='registry_officer' AND p.code='document.archive' ON CONFLICT DO NOTHING;
INSERT INTO public.role_permissions(role_id,permission_id) SELECT r.id,p.id FROM public.roles r CROSS JOIN public.permissions p WHERE r.code='registry_officer' AND p.code='document.assign' ON CONFLICT DO NOTHING;
INSERT INTO public.role_permissions(role_id,permission_id) SELECT r.id,p.id FROM public.roles r CROSS JOIN public.permissions p WHERE r.code='registry_officer' AND p.code='document.complete' ON CONFLICT DO NOTHING;
INSERT INTO public.role_permissions(role_id,permission_id) SELECT r.id,p.id FROM public.roles r CROSS JOIN public.permissions p WHERE r.code='registry_officer' AND p.code='document.create' ON CONFLICT DO NOTHING;
INSERT INTO public.role_permissions(role_id,permission_id) SELECT r.id,p.id FROM public.roles r CROSS JOIN public.permissions p WHERE r.code='registry_officer' AND p.code='document.update' ON CONFLICT DO NOTHING;
INSERT INTO public.role_permissions(role_id,permission_id) SELECT r.id,p.id FROM public.roles r CROSS JOIN public.permissions p WHERE r.code='registry_officer' AND p.code='document.view' ON CONFLICT DO NOTHING;
INSERT INTO public.role_permissions(role_id,permission_id) SELECT r.id,p.id FROM public.roles r CROSS JOIN public.permissions p WHERE r.code='registry_officer' AND p.code='registry.incoming.manage' ON CONFLICT DO NOTHING;
INSERT INTO public.role_permissions(role_id,permission_id) SELECT r.id,p.id FROM public.roles r CROSS JOIN public.permissions p WHERE r.code='registry_officer' AND p.code='registry.outgoing.manage' ON CONFLICT DO NOTHING;
INSERT INTO public.role_permissions(role_id,permission_id) SELECT r.id,p.id FROM public.roles r CROSS JOIN public.permissions p WHERE r.code='registry_officer' AND p.code='report.view' ON CONFLICT DO NOTHING;
INSERT INTO public.role_permissions(role_id,permission_id) SELECT r.id,p.id FROM public.roles r CROSS JOIN public.permissions p WHERE r.code='school_admin' AND p.code='dashboard.view' ON CONFLICT DO NOTHING;
INSERT INTO public.role_permissions(role_id,permission_id) SELECT r.id,p.id FROM public.roles r CROSS JOIN public.permissions p WHERE r.code='school_admin' AND p.code='report.view' ON CONFLICT DO NOTHING;
INSERT INTO public.role_permissions(role_id,permission_id) SELECT r.id,p.id FROM public.roles r CROSS JOIN public.permissions p WHERE r.code='school_admin' AND p.code='role.manage' ON CONFLICT DO NOTHING;
INSERT INTO public.role_permissions(role_id,permission_id) SELECT r.id,p.id FROM public.roles r CROSS JOIN public.permissions p WHERE r.code='school_admin' AND p.code='settings.manage' ON CONFLICT DO NOTHING;
INSERT INTO public.role_permissions(role_id,permission_id) SELECT r.id,p.id FROM public.roles r CROSS JOIN public.permissions p WHERE r.code='school_admin' AND p.code='user.manage' ON CONFLICT DO NOTHING;
INSERT INTO public.role_permissions(role_id,permission_id) SELECT r.id,p.id FROM public.roles r CROSS JOIN public.permissions p WHERE r.code='school_admin' AND p.code='user.view' ON CONFLICT DO NOTHING;
INSERT INTO public.role_permissions(role_id,permission_id) SELECT r.id,p.id FROM public.roles r CROSS JOIN public.permissions p WHERE r.code='staff' AND p.code='dashboard.view' ON CONFLICT DO NOTHING;
INSERT INTO public.role_permissions(role_id,permission_id) SELECT r.id,p.id FROM public.roles r CROSS JOIN public.permissions p WHERE r.code='staff' AND p.code='document.complete' ON CONFLICT DO NOTHING;
INSERT INTO public.role_permissions(role_id,permission_id) SELECT r.id,p.id FROM public.roles r CROSS JOIN public.permissions p WHERE r.code='staff' AND p.code='document.update' ON CONFLICT DO NOTHING;
INSERT INTO public.role_permissions(role_id,permission_id) SELECT r.id,p.id FROM public.roles r CROSS JOIN public.permissions p WHERE r.code='staff' AND p.code='document.view' ON CONFLICT DO NOTHING;
INSERT INTO public.role_permissions(role_id,permission_id) SELECT r.id,p.id FROM public.roles r CROSS JOIN public.permissions p WHERE r.code='system_admin' AND p.code='audit.view' ON CONFLICT DO NOTHING;
INSERT INTO public.role_permissions(role_id,permission_id) SELECT r.id,p.id FROM public.roles r CROSS JOIN public.permissions p WHERE r.code='system_admin' AND p.code='dashboard.view' ON CONFLICT DO NOTHING;
INSERT INTO public.role_permissions(role_id,permission_id) SELECT r.id,p.id FROM public.roles r CROSS JOIN public.permissions p WHERE r.code='system_admin' AND p.code='document.approve' ON CONFLICT DO NOTHING;
INSERT INTO public.role_permissions(role_id,permission_id) SELECT r.id,p.id FROM public.roles r CROSS JOIN public.permissions p WHERE r.code='system_admin' AND p.code='document.archive' ON CONFLICT DO NOTHING;
INSERT INTO public.role_permissions(role_id,permission_id) SELECT r.id,p.id FROM public.roles r CROSS JOIN public.permissions p WHERE r.code='system_admin' AND p.code='document.assign' ON CONFLICT DO NOTHING;
INSERT INTO public.role_permissions(role_id,permission_id) SELECT r.id,p.id FROM public.roles r CROSS JOIN public.permissions p WHERE r.code='system_admin' AND p.code='document.complete' ON CONFLICT DO NOTHING;
INSERT INTO public.role_permissions(role_id,permission_id) SELECT r.id,p.id FROM public.roles r CROSS JOIN public.permissions p WHERE r.code='system_admin' AND p.code='document.create' ON CONFLICT DO NOTHING;
INSERT INTO public.role_permissions(role_id,permission_id) SELECT r.id,p.id FROM public.roles r CROSS JOIN public.permissions p WHERE r.code='system_admin' AND p.code='document.update' ON CONFLICT DO NOTHING;
INSERT INTO public.role_permissions(role_id,permission_id) SELECT r.id,p.id FROM public.roles r CROSS JOIN public.permissions p WHERE r.code='system_admin' AND p.code='document.view' ON CONFLICT DO NOTHING;
INSERT INTO public.role_permissions(role_id,permission_id) SELECT r.id,p.id FROM public.roles r CROSS JOIN public.permissions p WHERE r.code='system_admin' AND p.code='registry.incoming.manage' ON CONFLICT DO NOTHING;
INSERT INTO public.role_permissions(role_id,permission_id) SELECT r.id,p.id FROM public.roles r CROSS JOIN public.permissions p WHERE r.code='system_admin' AND p.code='registry.outgoing.manage' ON CONFLICT DO NOTHING;
INSERT INTO public.role_permissions(role_id,permission_id) SELECT r.id,p.id FROM public.roles r CROSS JOIN public.permissions p WHERE r.code='system_admin' AND p.code='report.view' ON CONFLICT DO NOTHING;
INSERT INTO public.role_permissions(role_id,permission_id) SELECT r.id,p.id FROM public.roles r CROSS JOIN public.permissions p WHERE r.code='system_admin' AND p.code='role.manage' ON CONFLICT DO NOTHING;
INSERT INTO public.role_permissions(role_id,permission_id) SELECT r.id,p.id FROM public.roles r CROSS JOIN public.permissions p WHERE r.code='system_admin' AND p.code='settings.manage' ON CONFLICT DO NOTHING;
INSERT INTO public.role_permissions(role_id,permission_id) SELECT r.id,p.id FROM public.roles r CROSS JOIN public.permissions p WHERE r.code='system_admin' AND p.code='user.manage' ON CONFLICT DO NOTHING;
INSERT INTO public.role_permissions(role_id,permission_id) SELECT r.id,p.id FROM public.roles r CROSS JOIN public.permissions p WHERE r.code='system_admin' AND p.code='user.view' ON CONFLICT DO NOTHING;
INSERT INTO public.role_permissions(role_id,permission_id) SELECT r.id,p.id FROM public.roles r CROSS JOIN public.permissions p WHERE r.code='teacher' AND p.code='dashboard.view' ON CONFLICT DO NOTHING;
INSERT INTO public.role_permissions(role_id,permission_id) SELECT r.id,p.id FROM public.roles r CROSS JOIN public.permissions p WHERE r.code='teacher' AND p.code='document.complete' ON CONFLICT DO NOTHING;
INSERT INTO public.role_permissions(role_id,permission_id) SELECT r.id,p.id FROM public.roles r CROSS JOIN public.permissions p WHERE r.code='teacher' AND p.code='document.update' ON CONFLICT DO NOTHING;
INSERT INTO public.role_permissions(role_id,permission_id) SELECT r.id,p.id FROM public.roles r CROSS JOIN public.permissions p WHERE r.code='teacher' AND p.code='document.view' ON CONFLICT DO NOTHING;
INSERT INTO public.document_registers(code,name,direction,document_year,is_active) VALUES ('IN-2026','ทะเบียนหนังสือรับ','incoming',2026,true) ON CONFLICT (code,document_year) DO UPDATE SET name=EXCLUDED.name,direction=EXCLUDED.direction,is_active=EXCLUDED.is_active;
INSERT INTO public.document_registers(code,name,direction,document_year,is_active) VALUES ('OUT-2026','ทะเบียนหนังสือส่ง','outgoing',2026,true) ON CONFLICT (code,document_year) DO UPDATE SET name=EXCLUDED.name,direction=EXCLUDED.direction,is_active=EXCLUDED.is_active;

SET check_function_bodies = on;
