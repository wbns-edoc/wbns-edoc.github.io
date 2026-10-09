-- GENERATED READ-ONLY CATALOG SNAPSHOT for isolated tests only.
-- Source project: iigzzwyfxxtqbgjawyom. Generated 2026-10-10.
-- NOT a historical migration, NOT intended for Production deployment.
-- Contains no production user/document rows. Recovered definitions must be reviewed.
SET check_function_bodies = off;
SET search_path = public, private, extensions, pg_catalog;
CREATE SCHEMA IF NOT EXISTS private;
CREATE SCHEMA IF NOT EXISTS extensions;

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
ALTER TABLE approvals ADD CONSTRAINT approvals_approver_id_fkey FOREIGN KEY (approver_id) REFERENCES profiles(id) ON DELETE RESTRICT;
ALTER TABLE approvals ADD CONSTRAINT approvals_document_id_approval_step_key UNIQUE (document_id, approval_step);
ALTER TABLE approvals ADD CONSTRAINT approvals_document_id_fkey FOREIGN KEY (document_id) REFERENCES documents(id) ON DELETE RESTRICT;
ALTER TABLE approvals ADD CONSTRAINT approvals_pkey PRIMARY KEY (id);
ALTER TABLE audit_logs ADD CONSTRAINT audit_logs_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES profiles(id) ON DELETE RESTRICT;
ALTER TABLE audit_logs ADD CONSTRAINT audit_logs_pkey PRIMARY KEY (id);
ALTER TABLE comments ADD CONSTRAINT comments_author_id_fkey FOREIGN KEY (author_id) REFERENCES profiles(id) ON DELETE RESTRICT;
ALTER TABLE comments ADD CONSTRAINT comments_document_id_fkey FOREIGN KEY (document_id) REFERENCES documents(id) ON DELETE RESTRICT;
ALTER TABLE comments ADD CONSTRAINT comments_pkey PRIMARY KEY (id);
ALTER TABLE deadlines ADD CONSTRAINT deadlines_assigned_to_fkey FOREIGN KEY (assigned_to) REFERENCES profiles(id) ON DELETE RESTRICT;
ALTER TABLE deadlines ADD CONSTRAINT deadlines_document_id_fkey FOREIGN KEY (document_id) REFERENCES documents(id) ON DELETE RESTRICT;
ALTER TABLE deadlines ADD CONSTRAINT deadlines_pkey PRIMARY KEY (id);
ALTER TABLE deadlines ADD CONSTRAINT deadlines_status_check CHECK (status = ANY (ARRAY['open'::text, 'completed'::text, 'overdue'::text, 'cancelled'::text]));
ALTER TABLE departments ADD CONSTRAINT departments_code_key UNIQUE (code);
ALTER TABLE departments ADD CONSTRAINT departments_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES departments(id) ON DELETE RESTRICT;
ALTER TABLE departments ADD CONSTRAINT departments_pkey PRIMARY KEY (id);
ALTER TABLE document_assignments ADD CONSTRAINT document_assignments_assigned_by_fkey FOREIGN KEY (assigned_by) REFERENCES profiles(id) ON DELETE RESTRICT;
ALTER TABLE document_assignments ADD CONSTRAINT document_assignments_assignee_id_fkey FOREIGN KEY (assignee_id) REFERENCES profiles(id) ON DELETE RESTRICT;
ALTER TABLE document_assignments ADD CONSTRAINT document_assignments_document_id_fkey FOREIGN KEY (document_id) REFERENCES documents(id) ON DELETE RESTRICT;
ALTER TABLE document_assignments ADD CONSTRAINT document_assignments_pkey PRIMARY KEY (id);
ALTER TABLE document_files ADD CONSTRAINT document_files_document_id_fkey FOREIGN KEY (document_id) REFERENCES documents(id) ON DELETE RESTRICT;
ALTER TABLE document_files ADD CONSTRAINT document_files_document_id_google_drive_file_id_key UNIQUE (document_id, google_drive_file_id);
ALTER TABLE document_files ADD CONSTRAINT document_files_google_drive_file_id_fkey FOREIGN KEY (google_drive_file_id) REFERENCES google_drive_files(id) ON DELETE RESTRICT;
ALTER TABLE document_files ADD CONSTRAINT document_files_pkey PRIMARY KEY (id);
ALTER TABLE document_files ADD CONSTRAINT document_files_uploaded_by_fkey FOREIGN KEY (uploaded_by) REFERENCES profiles(id) ON DELETE RESTRICT;
ALTER TABLE document_files ADD CONSTRAINT document_files_version_no_check CHECK (version_no > 0);
ALTER TABLE document_registers ADD CONSTRAINT document_registers_code_document_year_key UNIQUE (code, document_year);
ALTER TABLE document_registers ADD CONSTRAINT document_registers_direction_document_year_key UNIQUE (direction, document_year);
ALTER TABLE document_registers ADD CONSTRAINT document_registers_document_year_check CHECK (document_year >= 2000 AND document_year <= 2200);
ALTER TABLE document_registers ADD CONSTRAINT document_registers_pkey PRIMARY KEY (id);
ALTER TABLE document_status_history ADD CONSTRAINT document_status_history_changed_by_fkey FOREIGN KEY (changed_by) REFERENCES profiles(id) ON DELETE RESTRICT;
ALTER TABLE document_status_history ADD CONSTRAINT document_status_history_document_id_fkey FOREIGN KEY (document_id) REFERENCES documents(id) ON DELETE RESTRICT;
ALTER TABLE document_status_history ADD CONSTRAINT document_status_history_pkey PRIMARY KEY (id);
ALTER TABLE documents ADD CONSTRAINT documents_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE RESTRICT;
ALTER TABLE documents ADD CONSTRAINT documents_current_owner_id_fkey FOREIGN KEY (current_owner_id) REFERENCES profiles(id) ON DELETE RESTRICT;
ALTER TABLE documents ADD CONSTRAINT documents_pkey PRIMARY KEY (id);
ALTER TABLE documents ADD CONSTRAINT documents_register_id_fkey FOREIGN KEY (register_id) REFERENCES document_registers(id) ON DELETE RESTRICT;
ALTER TABLE google_drive_files ADD CONSTRAINT google_drive_files_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE RESTRICT;
ALTER TABLE google_drive_files ADD CONSTRAINT google_drive_files_drive_file_id_key UNIQUE (drive_file_id);
ALTER TABLE google_drive_files ADD CONSTRAINT google_drive_files_pkey PRIMARY KEY (id);
ALTER TABLE incoming_document_details ADD CONSTRAINT incoming_document_details_document_id_fkey FOREIGN KEY (document_id) REFERENCES documents(id) ON DELETE RESTRICT;
ALTER TABLE incoming_document_details ADD CONSTRAINT incoming_document_details_pkey PRIMARY KEY (document_id);
ALTER TABLE incoming_document_details ADD CONSTRAINT incoming_document_details_sender_id_fkey FOREIGN KEY (sender_id) REFERENCES senders(id) ON DELETE RESTRICT;
ALTER TABLE notifications ADD CONSTRAINT notifications_document_id_fkey FOREIGN KEY (document_id) REFERENCES documents(id) ON DELETE RESTRICT;
ALTER TABLE notifications ADD CONSTRAINT notifications_pkey PRIMARY KEY (id);
ALTER TABLE notifications ADD CONSTRAINT notifications_priority_check CHECK (priority = ANY (ARRAY['normal'::text, 'high'::text, 'critical'::text]));
ALTER TABLE notifications ADD CONSTRAINT notifications_recipient_id_fkey FOREIGN KEY (recipient_id) REFERENCES profiles(id) ON DELETE RESTRICT;
ALTER TABLE number_sequences ADD CONSTRAINT number_sequences_current_number_check CHECK (current_number >= 0);
ALTER TABLE number_sequences ADD CONSTRAINT number_sequences_pkey PRIMARY KEY (id);
ALTER TABLE number_sequences ADD CONSTRAINT number_sequences_register_id_fkey FOREIGN KEY (register_id) REFERENCES document_registers(id) ON DELETE RESTRICT;
ALTER TABLE number_sequences ADD CONSTRAINT number_sequences_register_id_year_key UNIQUE (register_id, year);
ALTER TABLE number_sequences ADD CONSTRAINT number_sequences_year_check CHECK (year >= 2000 AND year <= 2200);
ALTER TABLE outgoing_document_details ADD CONSTRAINT outgoing_document_details_document_id_fkey FOREIGN KEY (document_id) REFERENCES documents(id) ON DELETE RESTRICT;
ALTER TABLE outgoing_document_details ADD CONSTRAINT outgoing_document_details_pkey PRIMARY KEY (document_id);
ALTER TABLE permissions ADD CONSTRAINT permissions_code_key UNIQUE (code);
ALTER TABLE permissions ADD CONSTRAINT permissions_pkey PRIMARY KEY (id);
ALTER TABLE profiles ADD CONSTRAINT profiles_department_id_fkey FOREIGN KEY (department_id) REFERENCES departments(id) ON DELETE RESTRICT;
ALTER TABLE profiles ADD CONSTRAINT profiles_employee_code_key UNIQUE (employee_code);
ALTER TABLE profiles ADD CONSTRAINT profiles_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE RESTRICT;
ALTER TABLE profiles ADD CONSTRAINT profiles_pkey PRIMARY KEY (id);
ALTER TABLE push_subscriptions ADD CONSTRAINT push_subscriptions_endpoint_key UNIQUE (endpoint);
ALTER TABLE push_subscriptions ADD CONSTRAINT push_subscriptions_pkey PRIMARY KEY (id);
ALTER TABLE push_subscriptions ADD CONSTRAINT push_subscriptions_user_id_fkey FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE RESTRICT;
ALTER TABLE role_permissions ADD CONSTRAINT role_permissions_permission_id_fkey FOREIGN KEY (permission_id) REFERENCES permissions(id) ON DELETE CASCADE;
ALTER TABLE role_permissions ADD CONSTRAINT role_permissions_pkey PRIMARY KEY (role_id, permission_id);
ALTER TABLE role_permissions ADD CONSTRAINT role_permissions_role_id_fkey FOREIGN KEY (role_id) REFERENCES roles(id) ON DELETE CASCADE;
ALTER TABLE roles ADD CONSTRAINT roles_code_key UNIQUE (code);
ALTER TABLE roles ADD CONSTRAINT roles_pkey PRIMARY KEY (id);
ALTER TABLE senders ADD CONSTRAINT senders_pkey PRIMARY KEY (id);
ALTER TABLE user_roles ADD CONSTRAINT user_roles_assigned_by_fkey FOREIGN KEY (assigned_by) REFERENCES profiles(id) ON DELETE RESTRICT;
ALTER TABLE user_roles ADD CONSTRAINT user_roles_pkey PRIMARY KEY (user_id, role_id);
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
