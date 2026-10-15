-- READ-ONLY RECOVERY SNAPSHOT FROM PRODUCTION CATALOG
-- Project ref: iigzzwyfxxtqbgjawyom
-- Captured: 2026-10-15
-- IMPORTANT: This is generated from catalog metadata, NOT a pg_dump and NOT a ready-to-apply migration.
-- Review identity/generated columns, view options, grants, sequences, extensions, ownership, and dependency order.
-- Do not execute on Production. Use only for recovery review and isolated test reconstruction.

CREATE TYPE public.approval_decision AS ENUM ('pending', 'approved', 'rejected', 'returned');

CREATE TYPE public.assignment_status AS ENUM ('assigned', 'accepted', 'in_progress', 'completed', 'cancelled');

CREATE TYPE public.document_status AS ENUM ('draft', 'pending_approval', 'approved', 'received', 'registered', 'assigned', 'in_progress', 'completed', 'archived', 'sent', 'cancelled');

CREATE TYPE public.document_type AS ENUM ('incoming', 'outgoing');

CREATE TYPE public.urgency_level AS ENUM ('normal', 'urgent', 'very_urgent', 'critical');

CREATE TABLE public.approvals (id uuid DEFAULT gen_random_uuid() NOT NULL,
  document_id uuid NOT NULL,
  approval_step integer NOT NULL,
  approver_id uuid NOT NULL,
  decision approval_decision DEFAULT 'pending'::approval_decision NOT NULL,
  decided_at timestamp with time zone,
  comment text,
  created_at timestamp with time zone DEFAULT now() NOT NULL);

CREATE TABLE public.audit_logs (id uuid DEFAULT gen_random_uuid() NOT NULL,
  actor_id uuid,
  action text NOT NULL,
  entity_type text NOT NULL,
  entity_id uuid,
  old_data jsonb,
  new_data jsonb,
  request_id text,
  created_at timestamp with time zone DEFAULT now() NOT NULL);

CREATE TABLE public.comments (id uuid DEFAULT gen_random_uuid() NOT NULL,
  document_id uuid NOT NULL,
  author_id uuid NOT NULL,
  body text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  edited_at timestamp with time zone);

CREATE TABLE public.deadlines (id uuid DEFAULT gen_random_uuid() NOT NULL,
  document_id uuid NOT NULL,
  assigned_to uuid,
  due_at timestamp with time zone NOT NULL,
  reminder_at timestamp with time zone,
  escalation_at timestamp with time zone,
  completed_at timestamp with time zone,
  status text DEFAULT 'open'::text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL);

CREATE TABLE public.department_role_permissions (department_id uuid NOT NULL,
  role_id uuid NOT NULL,
  permission_id uuid NOT NULL,
  enabled boolean DEFAULT true NOT NULL,
  updated_by uuid,
  updated_at timestamp with time zone DEFAULT now() NOT NULL);

CREATE TABLE public.departments (id uuid DEFAULT gen_random_uuid() NOT NULL,
  parent_id uuid,
  code text NOT NULL,
  name text NOT NULL,
  is_active boolean DEFAULT true NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL);

CREATE TABLE public.document_assignments (id uuid DEFAULT gen_random_uuid() NOT NULL,
  document_id uuid NOT NULL,
  assignee_id uuid NOT NULL,
  assigned_by uuid NOT NULL,
  assigned_at timestamp with time zone DEFAULT now() NOT NULL,
  accepted_at timestamp with time zone,
  completed_at timestamp with time zone,
  instructions text,
  assignment_status assignment_status DEFAULT 'assigned'::assignment_status NOT NULL);

CREATE TABLE public.document_files (id uuid DEFAULT gen_random_uuid() NOT NULL,
  document_id uuid NOT NULL,
  google_drive_file_id uuid NOT NULL,
  file_role text DEFAULT 'attachment'::text NOT NULL,
  version_no integer DEFAULT 1 NOT NULL,
  is_current boolean DEFAULT true NOT NULL,
  uploaded_by uuid,
  uploaded_at timestamp with time zone DEFAULT now() NOT NULL);

CREATE TABLE public.document_registers (id uuid DEFAULT gen_random_uuid() NOT NULL,
  code text NOT NULL,
  name text NOT NULL,
  direction document_type NOT NULL,
  document_year integer NOT NULL,
  is_active boolean DEFAULT true NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL);

CREATE TABLE public.document_status_history (id uuid DEFAULT gen_random_uuid() NOT NULL,
  document_id uuid NOT NULL,
  from_status document_status,
  to_status document_status NOT NULL,
  changed_by uuid,
  changed_at timestamp with time zone DEFAULT now() NOT NULL,
  reason text);

CREATE TABLE public.documents (id uuid DEFAULT gen_random_uuid() NOT NULL,
  document_type document_type NOT NULL,
  register_id uuid,
  subject text NOT NULL,
  urgency urgency_level DEFAULT 'normal'::urgency_level NOT NULL,
  status document_status DEFAULT 'draft'::document_status NOT NULL,
  current_owner_id uuid,
  created_by uuid NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  department_id uuid,
  deleted_at timestamp with time zone,
  deleted_by uuid,
  deletion_reason text);

CREATE TABLE public.google_drive_files (id uuid DEFAULT gen_random_uuid() NOT NULL,
  drive_file_id text NOT NULL,
  drive_url text,
  name text NOT NULL,
  mime_type text,
  size_bytes bigint,
  checksum text,
  folder_id text,
  created_by uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL);

CREATE TABLE public.incoming_document_details (document_id uuid NOT NULL,
  sender_id uuid NOT NULL,
  external_document_no text,
  external_document_date date,
  received_at timestamp with time zone,
  registered_at timestamp with time zone,
  registered_number bigint,
  receiving_notes text);

CREATE TABLE public.notifications (id uuid DEFAULT gen_random_uuid() NOT NULL,
  recipient_id uuid NOT NULL,
  document_id uuid,
  type text NOT NULL,
  title text NOT NULL,
  body text NOT NULL,
  priority text DEFAULT 'normal'::text NOT NULL,
  read_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now() NOT NULL);

CREATE TABLE public.number_sequences (id uuid DEFAULT gen_random_uuid() NOT NULL,
  register_id uuid NOT NULL,
  year integer NOT NULL,
  prefix text,
  current_number bigint DEFAULT 0 NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL);

CREATE TABLE public.outgoing_document_details (document_id uuid NOT NULL,
  outgoing_document_no text,
  document_date date,
  recipient_name text NOT NULL,
  recipient_address text,
  recipient_contact text,
  sent_at timestamp with time zone,
  registered_number bigint);

CREATE TABLE public.permissions (id uuid DEFAULT gen_random_uuid() NOT NULL,
  code text NOT NULL,
  name text NOT NULL,
  description text,
  created_at timestamp with time zone DEFAULT now() NOT NULL);

CREATE TABLE public.profiles (id uuid NOT NULL,
  employee_code text,
  full_name text NOT NULL,
  email text,
  phone text,
  department_id uuid,
  is_active boolean DEFAULT true NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL);

CREATE TABLE public.push_subscriptions (id uuid DEFAULT gen_random_uuid() NOT NULL,
  user_id uuid NOT NULL,
  endpoint text NOT NULL,
  p256dh text NOT NULL,
  auth text NOT NULL,
  user_agent text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  revoked_at timestamp with time zone);

CREATE TABLE public.role_permissions (role_id uuid NOT NULL,
  permission_id uuid NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL);

CREATE TABLE public.roles (id uuid DEFAULT gen_random_uuid() NOT NULL,
  code text NOT NULL,
  name text NOT NULL,
  description text,
  created_at timestamp with time zone DEFAULT now() NOT NULL);

CREATE TABLE public.senders (id uuid DEFAULT gen_random_uuid() NOT NULL,
  organization_name text NOT NULL,
  department_name text,
  address text,
  contact_name text,
  contact_phone text,
  contact_email text,
  is_active boolean DEFAULT true NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL);

CREATE TABLE public.user_department_roles (user_id uuid NOT NULL,
  department_id uuid NOT NULL,
  role_id uuid NOT NULL,
  assigned_by uuid,
  assigned_at timestamp with time zone DEFAULT now() NOT NULL);

CREATE TABLE public.user_departments (user_id uuid NOT NULL,
  department_id uuid NOT NULL,
  is_primary boolean DEFAULT false NOT NULL,
  assigned_by uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL);

CREATE TABLE public.user_roles (user_id uuid NOT NULL,
  role_id uuid NOT NULL,
  assigned_at timestamp with time zone DEFAULT now() NOT NULL,
  assigned_by uuid);

ALTER TABLE public.approvals ADD CONSTRAINT approvals_approval_step_check CHECK ((approval_step > 0));
ALTER TABLE public.approvals ADD CONSTRAINT approvals_approver_id_fkey FOREIGN KEY (approver_id) REFERENCES profiles(id) ON DELETE RESTRICT;
ALTER TABLE public.approvals ADD CONSTRAINT approvals_document_id_approval_step_key UNIQUE (document_id, approval_step);
ALTER TABLE public.approvals ADD CONSTRAINT approvals_document_id_fkey FOREIGN KEY (document_id) REFERENCES documents(id) ON DELETE RESTRICT;
ALTER TABLE public.approvals ADD CONSTRAINT approvals_pkey PRIMARY KEY (id);
ALTER TABLE public.audit_logs ADD CONSTRAINT audit_logs_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES profiles(id) ON DELETE RESTRICT;
ALTER TABLE public.audit_logs ADD CONSTRAINT audit_logs_pkey PRIMARY KEY (id);
ALTER TABLE public.comments ADD CONSTRAINT comments_author_id_fkey FOREIGN KEY (author_id) REFERENCES profiles(id) ON DELETE RESTRICT;
ALTER TABLE public.comments ADD CONSTRAINT comments_document_id_fkey FOREIGN KEY (document_id) REFERENCES documents(id) ON DELETE RESTRICT;
ALTER TABLE public.comments ADD CONSTRAINT comments_pkey PRIMARY KEY (id);
ALTER TABLE public.deadlines ADD CONSTRAINT deadlines_assigned_to_fkey FOREIGN KEY (assigned_to) REFERENCES profiles(id) ON DELETE RESTRICT;
ALTER TABLE public.deadlines ADD CONSTRAINT deadlines_document_id_fkey FOREIGN KEY (document_id) REFERENCES documents(id) ON DELETE RESTRICT;
ALTER TABLE public.deadlines ADD CONSTRAINT deadlines_pkey PRIMARY KEY (id);
ALTER TABLE public.deadlines ADD CONSTRAINT deadlines_status_check CHECK ((status = ANY (ARRAY['open'::text, 'completed'::text, 'overdue'::text, 'cancelled'::text])));
ALTER TABLE public.department_role_permissions ADD CONSTRAINT department_role_permissions_department_id_fkey FOREIGN KEY (department_id) REFERENCES departments(id) ON DELETE CASCADE;
ALTER TABLE public.department_role_permissions ADD CONSTRAINT department_role_permissions_permission_id_fkey FOREIGN KEY (permission_id) REFERENCES permissions(id) ON DELETE CASCADE;
ALTER TABLE public.department_role_permissions ADD CONSTRAINT department_role_permissions_pkey PRIMARY KEY (department_id, role_id, permission_id);
ALTER TABLE public.department_role_permissions ADD CONSTRAINT department_role_permissions_role_id_fkey FOREIGN KEY (role_id) REFERENCES roles(id) ON DELETE CASCADE;
ALTER TABLE public.department_role_permissions ADD CONSTRAINT department_role_permissions_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES profiles(id) ON DELETE SET NULL;
ALTER TABLE public.departments ADD CONSTRAINT departments_code_key UNIQUE (code);
ALTER TABLE public.departments ADD CONSTRAINT departments_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES departments(id) ON DELETE RESTRICT;
ALTER TABLE public.departments ADD CONSTRAINT departments_pkey PRIMARY KEY (id);
ALTER TABLE public.document_assignments ADD CONSTRAINT document_assignments_assigned_by_fkey FOREIGN KEY (assigned_by) REFERENCES profiles(id) ON DELETE RESTRICT;
ALTER TABLE public.document_assignments ADD CONSTRAINT document_assignments_assignee_id_fkey FOREIGN KEY (assignee_id) REFERENCES profiles(id) ON DELETE RESTRICT;
ALTER TABLE public.document_assignments ADD CONSTRAINT document_assignments_document_id_fkey FOREIGN KEY (document_id) REFERENCES documents(id) ON DELETE RESTRICT;
ALTER TABLE public.document_assignments ADD CONSTRAINT document_assignments_pkey PRIMARY KEY (id);
ALTER TABLE public.document_files ADD CONSTRAINT document_files_document_id_fkey FOREIGN KEY (document_id) REFERENCES documents(id) ON DELETE RESTRICT;
ALTER TABLE public.document_files ADD CONSTRAINT document_files_document_id_google_drive_file_id_key UNIQUE (document_id, google_drive_file_id);
ALTER TABLE public.document_files ADD CONSTRAINT document_files_google_drive_file_id_fkey FOREIGN KEY (google_drive_file_id) REFERENCES google_drive_files(id) ON DELETE RESTRICT;
ALTER TABLE public.document_files ADD CONSTRAINT document_files_pkey PRIMARY KEY (id);
ALTER TABLE public.document_files ADD CONSTRAINT document_files_uploaded_by_fkey FOREIGN KEY (uploaded_by) REFERENCES profiles(id) ON DELETE RESTRICT;
ALTER TABLE public.document_files ADD CONSTRAINT document_files_version_no_check CHECK ((version_no > 0));
ALTER TABLE public.document_registers ADD CONSTRAINT document_registers_code_document_year_key UNIQUE (code, document_year);
ALTER TABLE public.document_registers ADD CONSTRAINT document_registers_direction_document_year_key UNIQUE (direction, document_year);
ALTER TABLE public.document_registers ADD CONSTRAINT document_registers_document_year_check CHECK (((document_year >= 2000) AND (document_year <= 2200)));
ALTER TABLE public.document_registers ADD CONSTRAINT document_registers_pkey PRIMARY KEY (id);
ALTER TABLE public.document_status_history ADD CONSTRAINT document_status_history_changed_by_fkey FOREIGN KEY (changed_by) REFERENCES profiles(id) ON DELETE RESTRICT;
ALTER TABLE public.document_status_history ADD CONSTRAINT document_status_history_document_id_fkey FOREIGN KEY (document_id) REFERENCES documents(id) ON DELETE RESTRICT;
ALTER TABLE public.document_status_history ADD CONSTRAINT document_status_history_pkey PRIMARY KEY (id);
ALTER TABLE public.documents ADD CONSTRAINT documents_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE RESTRICT;
ALTER TABLE public.documents ADD CONSTRAINT documents_current_owner_id_fkey FOREIGN KEY (current_owner_id) REFERENCES profiles(id) ON DELETE RESTRICT;
ALTER TABLE public.documents ADD CONSTRAINT documents_deleted_by_fkey FOREIGN KEY (deleted_by) REFERENCES profiles(id) ON DELETE RESTRICT;
ALTER TABLE public.documents ADD CONSTRAINT documents_department_id_fkey FOREIGN KEY (department_id) REFERENCES departments(id) ON DELETE RESTRICT;
ALTER TABLE public.documents ADD CONSTRAINT documents_pkey PRIMARY KEY (id);
ALTER TABLE public.documents ADD CONSTRAINT documents_register_id_fkey FOREIGN KEY (register_id) REFERENCES document_registers(id) ON DELETE RESTRICT;
ALTER TABLE public.google_drive_files ADD CONSTRAINT google_drive_files_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE RESTRICT;
ALTER TABLE public.google_drive_files ADD CONSTRAINT google_drive_files_drive_file_id_key UNIQUE (drive_file_id);
ALTER TABLE public.google_drive_files ADD CONSTRAINT google_drive_files_pkey PRIMARY KEY (id);
ALTER TABLE public.incoming_document_details ADD CONSTRAINT incoming_document_details_document_id_fkey FOREIGN KEY (document_id) REFERENCES documents(id) ON DELETE RESTRICT;
ALTER TABLE public.incoming_document_details ADD CONSTRAINT incoming_document_details_pkey PRIMARY KEY (document_id);
ALTER TABLE public.incoming_document_details ADD CONSTRAINT incoming_document_details_sender_id_fkey FOREIGN KEY (sender_id) REFERENCES senders(id) ON DELETE RESTRICT;
ALTER TABLE public.notifications ADD CONSTRAINT notifications_document_id_fkey FOREIGN KEY (document_id) REFERENCES documents(id) ON DELETE RESTRICT;
ALTER TABLE public.notifications ADD CONSTRAINT notifications_pkey PRIMARY KEY (id);
ALTER TABLE public.notifications ADD CONSTRAINT notifications_priority_check CHECK ((priority = ANY (ARRAY['normal'::text, 'high'::text, 'critical'::text])));
ALTER TABLE public.notifications ADD CONSTRAINT notifications_recipient_id_fkey FOREIGN KEY (recipient_id) REFERENCES profiles(id) ON DELETE RESTRICT;
ALTER TABLE public.number_sequences ADD CONSTRAINT number_sequences_current_number_check CHECK ((current_number >= 0));
ALTER TABLE public.number_sequences ADD CONSTRAINT number_sequences_pkey PRIMARY KEY (id);
ALTER TABLE public.number_sequences ADD CONSTRAINT number_sequences_register_id_fkey FOREIGN KEY (register_id) REFERENCES document_registers(id) ON DELETE RESTRICT;
ALTER TABLE public.number_sequences ADD CONSTRAINT number_sequences_register_id_year_key UNIQUE (register_id, year);
ALTER TABLE public.number_sequences ADD CONSTRAINT number_sequences_year_check CHECK (((year >= 2000) AND (year <= 2200)));
ALTER TABLE public.outgoing_document_details ADD CONSTRAINT outgoing_document_details_document_id_fkey FOREIGN KEY (document_id) REFERENCES documents(id) ON DELETE RESTRICT;
ALTER TABLE public.outgoing_document_details ADD CONSTRAINT outgoing_document_details_pkey PRIMARY KEY (document_id);
ALTER TABLE public.permissions ADD CONSTRAINT permissions_code_key UNIQUE (code);
ALTER TABLE public.permissions ADD CONSTRAINT permissions_pkey PRIMARY KEY (id);
ALTER TABLE public.profiles ADD CONSTRAINT profiles_department_id_fkey FOREIGN KEY (department_id) REFERENCES departments(id) ON DELETE RESTRICT;
ALTER TABLE public.profiles ADD CONSTRAINT profiles_employee_code_key UNIQUE (employee_code);
ALTER TABLE public.profiles ADD CONSTRAINT profiles_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE RESTRICT;
ALTER TABLE public.profiles ADD CONSTRAINT profiles_pkey PRIMARY KEY (id);
ALTER TABLE public.push_subscriptions ADD CONSTRAINT push_subscriptions_endpoint_key UNIQUE (endpoint);
ALTER TABLE public.push_subscriptions ADD CONSTRAINT push_subscriptions_pkey PRIMARY KEY (id);
ALTER TABLE public.push_subscriptions ADD CONSTRAINT push_subscriptions_user_id_fkey FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE RESTRICT;
ALTER TABLE public.role_permissions ADD CONSTRAINT role_permissions_permission_id_fkey FOREIGN KEY (permission_id) REFERENCES permissions(id) ON DELETE CASCADE;
ALTER TABLE public.role_permissions ADD CONSTRAINT role_permissions_pkey PRIMARY KEY (role_id, permission_id);
ALTER TABLE public.role_permissions ADD CONSTRAINT role_permissions_role_id_fkey FOREIGN KEY (role_id) REFERENCES roles(id) ON DELETE CASCADE;
ALTER TABLE public.roles ADD CONSTRAINT roles_code_key UNIQUE (code);
ALTER TABLE public.roles ADD CONSTRAINT roles_pkey PRIMARY KEY (id);
ALTER TABLE public.senders ADD CONSTRAINT senders_pkey PRIMARY KEY (id);
ALTER TABLE public.user_department_roles ADD CONSTRAINT user_department_roles_assigned_by_fkey FOREIGN KEY (assigned_by) REFERENCES profiles(id) ON DELETE SET NULL;
ALTER TABLE public.user_department_roles ADD CONSTRAINT user_department_roles_department_id_fkey FOREIGN KEY (department_id) REFERENCES departments(id) ON DELETE RESTRICT;
ALTER TABLE public.user_department_roles ADD CONSTRAINT user_department_roles_pkey PRIMARY KEY (user_id, department_id, role_id);
ALTER TABLE public.user_department_roles ADD CONSTRAINT user_department_roles_role_id_fkey FOREIGN KEY (role_id) REFERENCES roles(id) ON DELETE RESTRICT;
ALTER TABLE public.user_department_roles ADD CONSTRAINT user_department_roles_user_id_fkey FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE;
ALTER TABLE public.user_departments ADD CONSTRAINT user_departments_assigned_by_fkey FOREIGN KEY (assigned_by) REFERENCES profiles(id) ON DELETE SET NULL;
ALTER TABLE public.user_departments ADD CONSTRAINT user_departments_department_id_fkey FOREIGN KEY (department_id) REFERENCES departments(id) ON DELETE RESTRICT;
ALTER TABLE public.user_departments ADD CONSTRAINT user_departments_pkey PRIMARY KEY (user_id, department_id);
ALTER TABLE public.user_departments ADD CONSTRAINT user_departments_user_id_fkey FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE;
ALTER TABLE public.user_roles ADD CONSTRAINT user_roles_assigned_by_fkey FOREIGN KEY (assigned_by) REFERENCES profiles(id) ON DELETE RESTRICT;
ALTER TABLE public.user_roles ADD CONSTRAINT user_roles_pkey PRIMARY KEY (user_id, role_id);
ALTER TABLE public.user_roles ADD CONSTRAINT user_roles_role_id_fkey FOREIGN KEY (role_id) REFERENCES roles(id) ON DELETE RESTRICT;
ALTER TABLE public.user_roles ADD CONSTRAINT user_roles_user_id_fkey FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE RESTRICT;

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
CREATE INDEX documents_department_id_idx ON public.documents USING btree (department_id);
CREATE INDEX documents_not_deleted_idx ON public.documents USING btree (created_at DESC) WHERE (deleted_at IS NULL);
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
CREATE INDEX user_department_roles_department_idx ON public.user_department_roles USING btree (department_id, user_id);
CREATE UNIQUE INDEX user_departments_one_primary_idx ON public.user_departments USING btree (user_id) WHERE is_primary;
CREATE INDEX idx_user_roles_assigned_by ON public.user_roles USING btree (assigned_by);
CREATE INDEX idx_user_roles_role ON public.user_roles USING btree (role_id);

ALTER TABLE public.approvals ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.comments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.deadlines ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.department_role_permissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.departments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.document_assignments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.document_files ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.document_registers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.document_status_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.google_drive_files ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.incoming_document_details ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.number_sequences ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.outgoing_document_details ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.permissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.push_subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.role_permissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.senders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_department_roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_departments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;

CREATE POLICY approvals_insert_authorized ON public.approvals AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK (((approver_id = ( SELECT auth.uid() AS uid)) AND (EXISTS ( SELECT 1
   FROM documents d
  WHERE ((d.id = approvals.document_id) AND private.can_access_document(d.id) AND private.has_department_permission('document.approve'::text, d.department_id))))));
CREATE POLICY approvals_select_authorized ON public.approvals AS PERMISSIVE FOR SELECT TO authenticated USING (private.can_access_document(document_id));
CREATE POLICY approvals_update_authorized ON public.approvals AS PERMISSIVE FOR UPDATE TO authenticated USING (((approver_id = ( SELECT auth.uid() AS uid)) AND (EXISTS ( SELECT 1
   FROM documents d
  WHERE ((d.id = approvals.document_id) AND private.can_access_document(d.id) AND private.has_department_permission('document.approve'::text, d.department_id)))))) WITH CHECK (((approver_id = ( SELECT auth.uid() AS uid)) AND (EXISTS ( SELECT 1
   FROM documents d
  WHERE ((d.id = approvals.document_id) AND private.can_access_document(d.id) AND private.has_department_permission('document.approve'::text, d.department_id))))));
CREATE POLICY audit_logs_admin_read ON public.audit_logs AS PERMISSIVE FOR SELECT TO authenticated USING (private.has_permission('audit.view'::text));
CREATE POLICY comments_insert_own ON public.comments AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK (((author_id = ( SELECT auth.uid() AS uid)) AND private.can_access_document(document_id)));
CREATE POLICY comments_select_authorized ON public.comments AS PERMISSIVE FOR SELECT TO authenticated USING (private.can_access_document(document_id));
CREATE POLICY comments_update_own ON public.comments AS PERMISSIVE FOR UPDATE TO authenticated USING (((author_id = ( SELECT auth.uid() AS uid)) AND private.can_access_document(document_id))) WITH CHECK (((author_id = ( SELECT auth.uid() AS uid)) AND private.can_access_document(document_id)));
CREATE POLICY deadlines_manage_authorized ON public.deadlines AS PERMISSIVE FOR ALL TO authenticated USING ((EXISTS ( SELECT 1
   FROM documents d
  WHERE ((d.id = deadlines.document_id) AND private.can_access_document(d.id) AND ((deadlines.assigned_to = ( SELECT auth.uid() AS uid)) OR private.has_department_permission('document.assign'::text, d.department_id)))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM documents d
  WHERE ((d.id = deadlines.document_id) AND private.can_access_document(d.id) AND ((deadlines.assigned_to = ( SELECT auth.uid() AS uid)) OR private.has_department_permission('document.assign'::text, d.department_id))))));
CREATE POLICY deadlines_select_authorized ON public.deadlines AS PERMISSIVE FOR SELECT TO authenticated USING (private.can_access_document(document_id));
CREATE POLICY departments_manage_admin ON public.departments AS PERMISSIVE FOR ALL TO authenticated USING (private.has_permission('settings.manage'::text)) WITH CHECK (private.has_permission('settings.manage'::text));
CREATE POLICY departments_select_authenticated ON public.departments AS PERMISSIVE FOR SELECT TO authenticated USING (true);
CREATE POLICY assignments_insert_authorized ON public.document_assignments AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK (((assigned_by = ( SELECT auth.uid() AS uid)) AND (EXISTS ( SELECT 1
   FROM documents d
  WHERE ((d.id = document_assignments.document_id) AND private.can_access_document(d.id) AND private.has_department_permission('document.assign'::text, d.department_id))))));
CREATE POLICY assignments_select_authorized ON public.document_assignments AS PERMISSIVE FOR SELECT TO authenticated USING (private.can_access_document(document_id));
CREATE POLICY assignments_update_authorized ON public.document_assignments AS PERMISSIVE FOR UPDATE TO authenticated USING ((EXISTS ( SELECT 1
   FROM documents d
  WHERE ((d.id = document_assignments.document_id) AND private.can_access_document(d.id) AND ((document_assignments.assignee_id = ( SELECT auth.uid() AS uid)) OR (document_assignments.assigned_by = ( SELECT auth.uid() AS uid)) OR private.has_department_permission('document.assign'::text, d.department_id)))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM documents d
  WHERE ((d.id = document_assignments.document_id) AND private.can_access_document(d.id) AND ((document_assignments.assignee_id = ( SELECT auth.uid() AS uid)) OR (document_assignments.assigned_by = ( SELECT auth.uid() AS uid)) OR private.has_department_permission('document.assign'::text, d.department_id))))));
CREATE POLICY document_files_authorized ON public.document_files AS PERMISSIVE FOR SELECT TO authenticated USING (private.can_access_document(document_id));
CREATE POLICY registers_manage_registry ON public.document_registers AS PERMISSIVE FOR ALL TO authenticated USING ((private.has_permission('settings.manage'::text) OR private.has_permission('registry.incoming.manage'::text) OR private.has_permission('registry.outgoing.manage'::text))) WITH CHECK ((private.has_permission('settings.manage'::text) OR private.has_permission('registry.incoming.manage'::text) OR private.has_permission('registry.outgoing.manage'::text)));
CREATE POLICY registers_select_authorized ON public.document_registers AS PERMISSIVE FOR SELECT TO authenticated USING ((private.has_permission('document.view'::text) OR private.has_permission('registry.incoming.manage'::text) OR private.has_permission('registry.outgoing.manage'::text)));
CREATE POLICY status_history_select_authorized ON public.document_status_history AS PERMISSIVE FOR SELECT TO authenticated USING (private.can_access_document(document_id));
CREATE POLICY documents_insert_authorized ON public.documents AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK (((created_by = ( SELECT auth.uid() AS uid)) AND (department_id IS NOT NULL) AND private.has_department_permission('document.create'::text, department_id)));
CREATE POLICY documents_select_authorized ON public.documents AS PERMISSIVE FOR SELECT TO authenticated USING (private.can_access_document(id));
CREATE POLICY documents_update_authorized ON public.documents AS PERMISSIVE FOR UPDATE TO authenticated USING ((private.can_access_document(id) AND (department_id IS NOT NULL) AND private.has_department_permission('document.update'::text, department_id))) WITH CHECK ((private.can_access_document(id) AND (department_id IS NOT NULL) AND private.has_department_permission('document.update'::text, department_id)));
CREATE POLICY google_drive_files_authorized ON public.google_drive_files AS PERMISSIVE FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM document_files df
  WHERE ((df.google_drive_file_id = google_drive_files.id) AND private.can_access_document(df.document_id)))));
CREATE POLICY incoming_details_insert_registry ON public.incoming_document_details AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK ((EXISTS ( SELECT 1
   FROM documents d
  WHERE ((d.id = incoming_document_details.document_id) AND private.can_access_document(d.id) AND private.has_department_permission('registry.incoming.manage'::text, d.department_id)))));
CREATE POLICY incoming_details_select_authorized ON public.incoming_document_details AS PERMISSIVE FOR SELECT TO authenticated USING (private.can_access_document(document_id));
CREATE POLICY incoming_details_update_registry ON public.incoming_document_details AS PERMISSIVE FOR UPDATE TO authenticated USING ((EXISTS ( SELECT 1
   FROM documents d
  WHERE ((d.id = incoming_document_details.document_id) AND private.can_access_document(d.id) AND private.has_department_permission('registry.incoming.manage'::text, d.department_id))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM documents d
  WHERE ((d.id = incoming_document_details.document_id) AND private.can_access_document(d.id) AND private.has_department_permission('registry.incoming.manage'::text, d.department_id)))));
CREATE POLICY notifications_own ON public.notifications AS PERMISSIVE FOR SELECT TO authenticated USING ((recipient_id = ( SELECT auth.uid() AS uid)));
CREATE POLICY notifications_update_own ON public.notifications AS PERMISSIVE FOR UPDATE TO authenticated USING ((recipient_id = ( SELECT auth.uid() AS uid))) WITH CHECK ((recipient_id = ( SELECT auth.uid() AS uid)));
CREATE POLICY number_sequences_registry_read ON public.number_sequences AS PERMISSIVE FOR SELECT TO authenticated USING ((private.has_permission('registry.incoming.manage'::text) OR private.has_permission('registry.outgoing.manage'::text) OR private.has_permission('settings.manage'::text)));
CREATE POLICY number_sequences_registry_update ON public.number_sequences AS PERMISSIVE FOR UPDATE TO authenticated USING ((private.has_permission('registry.incoming.manage'::text) OR private.has_permission('registry.outgoing.manage'::text) OR private.has_permission('settings.manage'::text))) WITH CHECK ((private.has_permission('registry.incoming.manage'::text) OR private.has_permission('registry.outgoing.manage'::text) OR private.has_permission('settings.manage'::text)));
CREATE POLICY outgoing_details_insert_registry ON public.outgoing_document_details AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK ((EXISTS ( SELECT 1
   FROM documents d
  WHERE ((d.id = outgoing_document_details.document_id) AND private.can_access_document(d.id) AND private.has_department_permission('registry.outgoing.manage'::text, d.department_id)))));
CREATE POLICY outgoing_details_select_authorized ON public.outgoing_document_details AS PERMISSIVE FOR SELECT TO authenticated USING (private.can_access_document(document_id));
CREATE POLICY outgoing_details_update_registry ON public.outgoing_document_details AS PERMISSIVE FOR UPDATE TO authenticated USING ((EXISTS ( SELECT 1
   FROM documents d
  WHERE ((d.id = outgoing_document_details.document_id) AND private.can_access_document(d.id) AND private.has_department_permission('registry.outgoing.manage'::text, d.department_id))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM documents d
  WHERE ((d.id = outgoing_document_details.document_id) AND private.can_access_document(d.id) AND private.has_department_permission('registry.outgoing.manage'::text, d.department_id)))));
CREATE POLICY permissions_manage_admin ON public.permissions AS PERMISSIVE FOR ALL TO authenticated USING (private.has_permission('role.manage'::text)) WITH CHECK (private.has_permission('role.manage'::text));
CREATE POLICY permissions_select_authenticated ON public.permissions AS PERMISSIVE FOR SELECT TO authenticated USING (true);
CREATE POLICY profiles_select_self_or_admin ON public.profiles AS PERMISSIVE FOR SELECT TO authenticated USING (((id = ( SELECT auth.uid() AS uid)) OR private.has_permission('user.view'::text)));
CREATE POLICY profiles_update_self_or_admin ON public.profiles AS PERMISSIVE FOR UPDATE TO authenticated USING (((id = ( SELECT auth.uid() AS uid)) OR private.has_permission('user.manage'::text))) WITH CHECK (((id = ( SELECT auth.uid() AS uid)) OR private.has_permission('user.manage'::text)));
CREATE POLICY push_subscriptions_own ON public.push_subscriptions AS PERMISSIVE FOR ALL TO authenticated USING ((user_id = ( SELECT auth.uid() AS uid))) WITH CHECK ((user_id = ( SELECT auth.uid() AS uid)));
CREATE POLICY role_permissions_manage_admin ON public.role_permissions AS PERMISSIVE FOR ALL TO authenticated USING (private.has_permission('role.manage'::text)) WITH CHECK (private.has_permission('role.manage'::text));
CREATE POLICY role_permissions_select_authenticated ON public.role_permissions AS PERMISSIVE FOR SELECT TO authenticated USING (true);
CREATE POLICY roles_manage_admin ON public.roles AS PERMISSIVE FOR ALL TO authenticated USING (private.has_permission('role.manage'::text)) WITH CHECK (private.has_permission('role.manage'::text));
CREATE POLICY roles_select_authenticated ON public.roles AS PERMISSIVE FOR SELECT TO authenticated USING (true);
CREATE POLICY senders_manage_registry ON public.senders AS PERMISSIVE FOR ALL TO authenticated USING (private.has_permission('registry.incoming.manage'::text)) WITH CHECK (private.has_permission('registry.incoming.manage'::text));
CREATE POLICY senders_select_registry ON public.senders AS PERMISSIVE FOR SELECT TO authenticated USING ((private.has_permission('document.view'::text) OR private.has_permission('registry.incoming.manage'::text)));
CREATE POLICY user_roles_manage_admin ON public.user_roles AS PERMISSIVE FOR ALL TO authenticated USING (private.has_permission('role.manage'::text)) WITH CHECK (private.has_permission('role.manage'::text));
CREATE POLICY user_roles_select_self_or_admin ON public.user_roles AS PERMISSIVE FOR SELECT TO authenticated USING (((user_id = ( SELECT auth.uid() AS uid)) OR private.has_permission('user.view'::text)));

CREATE TRIGGER audit_approvals AFTER INSERT OR DELETE OR UPDATE ON approvals FOR EACH ROW EXECUTE FUNCTION private.audit_row_change();
CREATE TRIGGER audit_deadlines AFTER INSERT OR DELETE OR UPDATE ON deadlines FOR EACH ROW EXECUTE FUNCTION private.audit_row_change();
CREATE TRIGGER departments_updated_at BEFORE UPDATE ON departments FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER audit_document_assignments AFTER INSERT OR DELETE OR UPDATE ON document_assignments FOR EACH ROW EXECUTE FUNCTION private.audit_row_change();
CREATE TRIGGER audit_document_files AFTER INSERT OR DELETE OR UPDATE ON document_files FOR EACH ROW EXECUTE FUNCTION private.audit_row_change();
CREATE TRIGGER audit_documents AFTER INSERT OR DELETE OR UPDATE ON documents FOR EACH ROW EXECUTE FUNCTION private.audit_row_change();
CREATE TRIGGER documents_default_department BEFORE INSERT ON documents FOR EACH ROW EXECUTE FUNCTION private.default_document_department();
CREATE TRIGGER documents_guard_department_change BEFORE UPDATE OF department_id ON documents FOR EACH ROW EXECUTE FUNCTION private.guard_document_department_change();
CREATE TRIGGER documents_updated_at BEFORE UPDATE ON documents FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER number_sequences_updated_at BEFORE UPDATE ON number_sequences FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER profiles_updated_at BEFORE UPDATE ON profiles FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER senders_updated_at BEFORE UPDATE ON senders FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE OR REPLACE VIEW public.document_monthly_summary AS  SELECT (date_trunc('month'::text, created_at))::date AS month,
    document_type,
    count(*) AS total_documents,
    count(*) FILTER (WHERE (status = 'completed'::document_status)) AS completed_documents,
    count(*) FILTER (WHERE (urgency = ANY (ARRAY['urgent'::urgency_level, 'very_urgent'::urgency_level, 'critical'::urgency_level]))) AS urgent_documents
   FROM documents
  WHERE (deleted_at IS NULL)
  GROUP BY ((date_trunc('month'::text, created_at))::date), document_type
  ORDER BY ((date_trunc('month'::text, created_at))::date) DESC;;

CREATE OR REPLACE VIEW public.document_report_summary AS  SELECT document_type,
    status,
    urgency,
    count(*) AS total_documents,
    count(*) FILTER (WHERE (created_at >= date_trunc('month'::text, now()))) AS current_month
   FROM documents
  WHERE (deleted_at IS NULL)
  GROUP BY document_type, status, urgency;;

-- Preserve Production view security options. These must remain in place
-- because the view queries read from RLS-protected public.documents.
ALTER VIEW public.document_monthly_summary SET (security_invoker = true);
ALTER VIEW public.document_report_summary SET (security_invoker = true);
