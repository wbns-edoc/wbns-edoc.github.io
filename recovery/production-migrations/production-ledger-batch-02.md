# Production migration ledger recovery archive — batch 2

Read-only extraction from `supabase_migrations.schema_migrations.statements` on Production project `iigzzwyfxxtqbgjawyom`.

These entries are already applied in Production. This file is archival evidence only: **do not copy into `supabase/migrations`, execute, or use for migration repair**. Each block preserves the recorded version, name, and SQL statement text.

## 20261010085031 — 20261010180000_scope_workflow_assignment_and_status

```sql
-- Enforce document and assignee department scope inside privileged workflow RPCs.
-- Cross-department assignment is not implied by document-wide read/edit rights.
BEGIN;

CREATE OR REPLACE FUNCTION private.assign_document(
  p_document_id uuid,
  p_assignee_id uuid,
  p_instructions text DEFAULT NULL,
  p_due_at timestamptz DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
DECLARE
  v_id uuid;
  v_actor uuid := auth.uid();
  v_subject text;
  v_old public.document_status;
BEGIN
  IF v_actor IS NULL OR NOT private.has_permission('document.assign') THEN
    RAISE EXCEPTION 'permission_denied';
  END IF;
  IF p_due_at IS NOT NULL AND p_due_at <= now() THEN
    RAISE EXCEPTION 'deadline_must_be_future';
  END IF;

  SELECT status, subject INTO v_old, v_subject
  FROM public.documents WHERE id = p_document_id FOR UPDATE;
  IF v_old IS NULL THEN RAISE EXCEPTION 'document_not_found'; END IF;
  IF v_old <> 'registered' THEN RAISE EXCEPTION 'invalid_status_transition'; END IF;
  IF NOT private.can_access_document(p_document_id) THEN
    RAISE EXCEPTION 'document_scope_denied';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = p_assignee_id AND is_active = true
  ) THEN RAISE EXCEPTION 'assignee_not_found'; END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.documents d
    JOIN public.profiles assignee ON assignee.id = p_assignee_id AND assignee.is_active = true
    WHERE d.id = p_document_id
      AND (
        (d.department_id IS NOT NULL AND assignee.department_id = d.department_id)
        OR EXISTS (
          SELECT 1 FROM public.user_roles ur
          JOIN public.roles r ON r.id = ur.role_id
          JOIN public.profiles actor_profile ON actor_profile.id = ur.user_id AND actor_profile.is_active = true
          WHERE ur.user_id = v_actor AND r.code = 'system_admin'
        )
      )
  ) THEN RAISE EXCEPTION 'cross_department_assignment_denied'; END IF;

  INSERT INTO public.document_assignments
    (document_id, assignee_id, assigned_by, instructions, assignment_status)
  VALUES (p_document_id, p_assignee_id, v_actor, p_instructions, 'assigned')
  RETURNING id INTO v_id;

  UPDATE public.documents SET current_owner_id = p_assignee_id, status = 'assigned'
  WHERE id = p_document_id;
  INSERT INTO public.document_status_history
    (document_id, from_status, to_status, changed_by, reason)
  VALUES (p_document_id, v_old, 'assigned', v_actor, 'มอบหมายงาน');
  INSERT INTO public.notifications
    (recipient_id, document_id, type, title, body, priority)
  VALUES (p_assignee_id, p_document_id, 'assignment', 'ได้รับมอบหมายงาน',
    'คุณได้รับมอบหมายเรื่อง: ' || coalesce(v_subject, 'ไม่ระบุเรื่อง'), 'high');

  IF p_due_at IS NOT NULL THEN
    INSERT INTO public.deadlines
      (document_id, assigned_to, due_at, reminder_at, escalation_at, status)
    VALUES (p_document_id, p_assignee_id, p_due_at,
      p_due_at - interval '24 hours', p_due_at, 'open');
  END IF;
  RETURN v_id;
END;
$function$;

CREATE OR REPLACE FUNCTION private.set_document_deadline(
  p_document_id uuid,
  p_assigned_to uuid,
  p_due_at timestamptz,
  p_reminder_at timestamptz DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
DECLARE
  v_id uuid;
  v_actor uuid := auth.uid();
BEGIN
  IF v_actor IS NULL OR NOT private.has_permission('document.assign') THEN
    RAISE EXCEPTION 'permission_denied';
  END IF;
  IF NOT private.can_access_document(p_document_id) THEN
    RAISE EXCEPTION 'document_scope_denied';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.profiles WHERE id = p_assigned_to AND is_active = true
  ) THEN RAISE EXCEPTION 'assignee_not_found'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.documents d
    JOIN public.profiles assignee ON assignee.id = p_assigned_to AND assignee.is_active = true
    WHERE d.id = p_document_id AND (
      (d.department_id IS NOT NULL AND assignee.department_id = d.department_id)
      OR EXISTS (
        SELECT 1 FROM public.user_roles ur
        JOIN public.roles r ON r.id = ur.role_id
        JOIN public.profiles actor_profile ON actor_profile.id = ur.user_id AND actor_profile.is_active = true
        WHERE ur.user_id = v_actor AND r.code = 'system_admin'
      )
    )
  ) THEN RAISE EXCEPTION 'cross_department_assignment_denied'; END IF;
  IF p_due_at <= now() THEN RAISE EXCEPTION 'deadline_must_be_future'; END IF;
  IF p_reminder_at IS NOT NULL AND p_reminder_at > p_due_at THEN
    RAISE EXCEPTION 'reminder_must_be_before_deadline';
  END IF;

  INSERT INTO public.deadlines
    (document_id, assigned_to, due_at, reminder_at, escalation_at, status)
  VALUES (p_document_id, p_assigned_to, p_due_at,
    coalesce(p_reminder_at, p_due_at - interval '24 hours'), p_due_at, 'open')
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$function$;

CREATE OR REPLACE FUNCTION private.update_document_status(
  p_document_id uuid,
  p_to_status public.document_status,
  p_reason text DEFAULT NULL
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
DECLARE
  v_actor uuid := auth.uid();
  v_from public.document_status;
BEGIN
  IF v_actor IS NULL THEN RAISE EXCEPTION 'permission_denied'; END IF;
  SELECT status INTO v_from FROM public.documents WHERE id = p_document_id FOR UPDATE;
  IF v_from IS NULL THEN RAISE EXCEPTION 'document_not_found'; END IF;
  IF NOT private.can_access_document(p_document_id) THEN
    RAISE EXCEPTION 'document_scope_denied';
  END IF;
  IF v_from = p_to_status THEN RETURN true; END IF;
  IF p_to_status IN ('pending_approval', 'approved', 'assigned')
     OR (v_from = 'pending_approval' AND p_to_status = 'draft') THEN
    RAISE EXCEPTION 'use_dedicated_workflow_rpc';
  END IF;
  IF p_to_status = 'completed' THEN
    IF NOT private.has_permission('document.complete') THEN RAISE EXCEPTION 'permission_denied'; END IF;
  ELSIF p_to_status = 'archived' THEN
    IF NOT private.has_permission('document.archive') THEN RAISE EXCEPTION 'permission_denied'; END IF;
  ELSIF NOT private.has_permission('document.update') THEN
    RAISE EXCEPTION 'permission_denied';
  END IF;
  IF NOT private.is_valid_document_transition(p_document_id, v_from, p_to_status) THEN
    RAISE EXCEPTION 'invalid_status_transition';
  END IF;
  UPDATE public.documents SET status = p_to_status WHERE id = p_document_id;
  INSERT INTO public.document_status_history
    (document_id, from_status, to_status, changed_by, reason)
  VALUES (p_document_id, v_from, p_to_status, v_actor, p_reason);
  IF p_to_status IN ('completed', 'archived') THEN
    UPDATE public.deadlines SET status = 'completed', completed_at = coalesce(completed_at, now())
    WHERE document_id = p_document_id AND status = 'open';
  END IF;
  RETURN true;
END;
$function$;

REVOKE ALL ON FUNCTION private.assign_document(uuid, uuid, text, timestamptz) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION private.set_document_deadline(uuid, uuid, timestamptz, timestamptz) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION private.update_document_status(uuid, public.document_status, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.assign_document(uuid, uuid, text, timestamptz) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION private.set_document_deadline(uuid, uuid, timestamptz, timestamptz) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION private.update_document_status(uuid, public.document_status, text) TO authenticated, service_role;

COMMIT;

```

---

## 20261010085034 — 20261010190000_department_aware_document_registration_v1

```sql
-- Explicit department assignment for incoming/outgoing registration.
-- Legacy signatures are retained but fail closed for profiles without a department.
BEGIN;

CREATE OR REPLACE FUNCTION private.register_incoming_document(
  p_subject text,
  p_sender_id uuid,
  p_external_document_no text DEFAULT NULL,
  p_external_document_date date DEFAULT NULL,
  p_received_at timestamptz DEFAULT now(),
  p_urgency public.urgency_level DEFAULT 'normal',
  p_receiving_notes text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
DECLARE
  v_department_id uuid;
BEGIN
  SELECT pr.department_id INTO v_department_id
  FROM public.profiles pr
  WHERE pr.id = (SELECT auth.uid()) AND pr.is_active = true;

  IF v_department_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '23502',
      MESSAGE = 'document_department_required';
  END IF;

  RETURN private.register_incoming_document(
    p_subject, p_sender_id, p_external_document_no, p_external_document_date,
    p_received_at, p_urgency, p_receiving_notes, v_department_id
  );
END;
$function$;

CREATE OR REPLACE FUNCTION private.register_incoming_document(
  p_subject text,
  p_sender_id uuid,
  p_external_document_no text,
  p_external_document_date date,
  p_received_at timestamptz,
  p_urgency public.urgency_level,
  p_receiving_notes text,
  p_department_id uuid
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
DECLARE
  v_uid uuid := (SELECT auth.uid());
  v_register uuid;
  v_doc uuid;
  v_no bigint;
BEGIN
  IF v_uid IS NULL OR NOT private.has_permission('registry.incoming.manage') THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'permission denied';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.profiles pr
    WHERE pr.id = v_uid AND pr.is_active = true
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'active_profile_required';
  END IF;

  IF p_department_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.departments d WHERE d.id = p_department_id AND d.is_active = true
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '23503', MESSAGE = 'active_document_department_required';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.senders s WHERE s.id = p_sender_id AND s.is_active = true
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '23503', MESSAGE = 'active_sender_required';
  END IF;

  SELECT id INTO v_register
  FROM public.document_registers
  WHERE direction = 'incoming' AND is_active = true
  ORDER BY document_year DESC, created_at
  LIMIT 1;

  IF v_register IS NULL THEN
    RAISE EXCEPTION 'ไม่พบทะเบียนหนังสือรับที่ใช้งานอยู่';
  END IF;

  v_no := private.allocate_document_number(
    v_register,
    (SELECT document_year FROM public.document_registers WHERE id = v_register)
  );

  INSERT INTO public.documents(
    document_type, register_id, department_id, subject, urgency, status, current_owner_id, created_by
  )
  VALUES(
    'incoming', v_register, p_department_id, p_subject, p_urgency, 'received', v_uid, v_uid
  )
  RETURNING id INTO v_doc;

  INSERT INTO public.incoming_document_details(
    document_id, sender_id, external_document_no, external_document_date,
    received_at, registered_at, registered_number, receiving_notes
  )
  VALUES(
    v_doc, p_sender_id, p_external_document_no, p_external_document_date,
    p_received_at, now(), v_no, p_receiving_notes
  );

  INSERT INTO public.document_status_history(document_id, from_status, to_status, changed_by, reason)
  VALUES(v_doc, NULL, 'received', v_uid, 'รับหนังสือเข้าระบบ');

  RETURN v_doc;
END;
$function$;

CREATE OR REPLACE FUNCTION private.register_outgoing_document(
  p_subject text,
  p_recipient_name text,
  p_recipient_address text DEFAULT NULL,
  p_recipient_contact text DEFAULT NULL,
  p_document_date date DEFAULT NULL,
  p_urgency public.urgency_level DEFAULT 'normal'
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
DECLARE
  v_department_id uuid;
BEGIN
  SELECT pr.department_id INTO v_department_id
  FROM public.profiles pr
  WHERE pr.id = (SELECT auth.uid()) AND pr.is_active = true;

  IF v_department_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '23502',
      MESSAGE = 'document_department_required';
  END IF;

  RETURN private.register_outgoing_document(
    p_subject, p_recipient_name, p_recipient_address, p_recipient_contact,
    p_document_date, p_urgency, v_department_id
  );
END;
$function$;

CREATE OR REPLACE FUNCTION private.register_outgoing_document(
  p_subject text,
  p_recipient_name text,
  p_recipient_address text,
  p_recipient_contact text,
  p_document_date date,
  p_urgency public.urgency_level,
  p_department_id uuid
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
DECLARE
  v_uid uuid := (SELECT auth.uid());
  v_register uuid;
  v_doc uuid;
  v_no bigint;
BEGIN
  IF v_uid IS NULL OR NOT private.has_permission('registry.outgoing.manage') THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'permission denied';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.profiles pr
    WHERE pr.id = v_uid AND pr.is_active = true
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'active_profile_required';
  END IF;

  IF p_department_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.departments d WHERE d.id = p_department_id AND d.is_active = true
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '23503', MESSAGE = 'active_document_department_required';
  END IF;

  SELECT id INTO v_register
  FROM public.document_registers
  WHERE direction = 'outgoing' AND is_active = true
  ORDER BY document_year DESC, created_at
  LIMIT 1;

  IF v_register IS NULL THEN
    RAISE EXCEPTION 'ไม่พบทะเบียนหนังสือส่งที่ใช้งานอยู่';
  END IF;

  v_no := private.allocate_document_number(
    v_register,
    (SELECT document_year FROM public.document_registers WHERE id = v_register)
  );

  INSERT INTO public.documents(
    document_type, register_id, department_id, subject, urgency, status, current_owner_id, created_by
  )
  VALUES(
    'outgoing', v_register, p_department_id, p_subject, p_urgency, 'draft', v_uid, v_uid
  )
  RETURNING id INTO v_doc;

  INSERT INTO public.outgoing_document_details(
    document_id, outgoing_document_no, document_date, recipient_name,
    recipient_address, recipient_contact, registered_number
  )
  VALUES(
    v_doc, NULL, COALESCE(p_document_date, current_date), p_recipient_name,
    p_recipient_address, p_recipient_contact, v_no
  );

  INSERT INTO public.document_status_history(document_id, from_status, to_status, changed_by, reason)
  VALUES(v_doc, NULL, 'draft', v_uid, 'สร้างหนังสือส่งฉบับร่าง');

  RETURN v_doc;
END;
$function$;

CREATE OR REPLACE FUNCTION public.register_incoming_document(
  p_subject text,
  p_sender_id uuid,
  p_external_document_no text,
  p_external_document_date date,
  p_received_at timestamptz,
  p_urgency public.urgency_level,
  p_receiving_notes text,
  p_department_id uuid
)
RETURNS uuid
LANGUAGE sql
SECURITY INVOKER
SET search_path TO 'pg_catalog', 'public'
AS $function$
  SELECT private.register_incoming_document($1,$2,$3,$4,$5,$6,$7,$8);
$function$;

CREATE OR REPLACE FUNCTION public.register_outgoing_document(
  p_subject text,
  p_recipient_name text,
  p_recipient_address text,
  p_recipient_contact text,
  p_document_date date,
  p_urgency public.urgency_level,
  p_department_id uuid
)
RETURNS uuid
LANGUAGE sql
SECURITY INVOKER
SET search_path TO 'pg_catalog', 'public'
AS $function$
  SELECT private.register_outgoing_document($1,$2,$3,$4,$5,$6,$7);
$function$;

REVOKE ALL ON FUNCTION private.register_incoming_document(text,uuid,text,date,timestamptz,public.urgency_level,text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION private.register_outgoing_document(text,text,text,text,date,public.urgency_level) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.register_incoming_document(text,uuid,text,date,timestamptz,public.urgency_level,text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION private.register_outgoing_document(text,text,text,text,date,public.urgency_level) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.register_incoming_document(text,uuid,text,date,timestamptz,public.urgency_level,text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.register_outgoing_document(text,text,text,text,date,public.urgency_level) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.register_incoming_document(text,uuid,text,date,timestamptz,public.urgency_level,text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.register_outgoing_document(text,text,text,text,date,public.urgency_level) TO authenticated, service_role;

REVOKE ALL ON FUNCTION private.register_incoming_document(text,uuid,text,date,timestamptz,public.urgency_level,text,uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION private.register_outgoing_document(text,text,text,text,date,public.urgency_level,uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.register_incoming_document(text,uuid,text,date,timestamptz,public.urgency_level,text,uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION private.register_outgoing_document(text,text,text,text,date,public.urgency_level,uuid) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.register_incoming_document(text,uuid,text,date,timestamptz,public.urgency_level,text,uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.register_outgoing_document(text,text,text,text,date,public.urgency_level,uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.register_incoming_document(text,uuid,text,date,timestamptz,public.urgency_level,text,uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.register_outgoing_document(text,text,text,text,date,public.urgency_level,uuid) TO authenticated, service_role;

COMMIT;

```

---

## 20261010090253 — guard_last_active_system_admin_role_removal_v1

```sql
-- Prevent removal of the final active System Admin assignment.
-- This is a narrow guard: it preserves existing authorization checks and
-- does not grant or assign any role.
BEGIN;

CREATE OR REPLACE FUNCTION public.admin_remove_user_role(p_user_id uuid, p_role_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
BEGIN
  IF NOT private.has_permission('user.manage') AND NOT private.has_permission('role.manage') THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'insufficient_privilege';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.profiles WHERE id = p_user_id
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'user_profile_not_found';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.user_roles ur
    JOIN public.roles r ON r.id = ur.role_id
    WHERE ur.user_id = p_user_id
      AND ur.role_id = p_role_id
      AND r.code = 'system_admin'
  ) AND (
    SELECT count(DISTINCT ur.user_id)
    FROM public.user_roles ur
    JOIN public.roles r ON r.id = ur.role_id
    JOIN public.profiles pr ON pr.id = ur.user_id
    WHERE r.code = 'system_admin'
      AND pr.is_active = true
  ) <= 1 THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'cannot_remove_last_active_system_admin';
  END IF;

  DELETE FROM public.user_roles
  WHERE user_id = p_user_id AND role_id = p_role_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_remove_user_role(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_remove_user_role(uuid, uuid) TO authenticated, service_role;

COMMIT;
```

---

## 20261011143751 — prevent_global_role_escalation

```sql
-- Prevent ordinary user/role managers from escalating users into global roles.
-- Global roles must be granted through a separately reviewed administrative path.
BEGIN;

CREATE OR REPLACE FUNCTION public.admin_set_user_role(p_user_id uuid, p_role_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
DECLARE
  v_role_code text;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'authentication_required';
  END IF;

  IF NOT private.has_permission('user.manage')
     AND NOT private.has_permission('role.manage') THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'insufficient_privilege';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = p_user_id) THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'user_profile_not_found';
  END IF;

  SELECT code INTO v_role_code
  FROM public.roles
  WHERE id = p_role_id;

  IF v_role_code IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'role_not_found';
  END IF;

  IF v_role_code IN ('system_admin', 'director') THEN
    RAISE EXCEPTION USING ERRCODE = '42501',
      MESSAGE = 'global_role_must_use_global_role_management';
  END IF;

  INSERT INTO public.user_roles(user_id, role_id, assigned_by)
  VALUES (p_user_id, p_role_id, auth.uid())
  ON CONFLICT (user_id, role_id) DO NOTHING;
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_set_user_role(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_set_user_role(uuid, uuid) TO authenticated, service_role;

COMMIT;

```

---

## 20261011144307 — grant_director_global_document_create

```sql
-- Ensure the principal has the requested global document-create capability in the live legacy schema.
BEGIN;

INSERT INTO public.role_permissions(role_id, permission_id)
SELECT r.id, p.id
FROM public.roles r
CROSS JOIN public.permissions p
WHERE r.code = 'director'
  AND p.code IN ('document.create', 'registry.incoming.manage', 'registry.outgoing.manage')
ON CONFLICT (role_id, permission_id) DO NOTHING;

DROP POLICY IF EXISTS documents_insert_authorized ON public.documents;
CREATE POLICY documents_insert_authorized ON public.documents
FOR INSERT TO authenticated
WITH CHECK (
  created_by = (SELECT auth.uid())
  AND private.has_permission('document.create')
  AND (
    department_id IS NULL
    OR department_id = (
      SELECT pr.department_id
      FROM public.profiles pr
      WHERE pr.id = (SELECT auth.uid()) AND pr.is_active = true
    )
    OR EXISTS (
      SELECT 1
      FROM public.user_roles ur
      JOIN public.roles r ON r.id = ur.role_id
      WHERE ur.user_id = (SELECT auth.uid())
        AND r.code IN ('system_admin', 'director')
    )
  )
);

COMMIT;
```

---

## 20261012011549 — production_multi_department_membership_v1

```sql
-- Multi-department membership support; keep profiles.department_id as the primary-department compatibility field.
BEGIN;

CREATE TABLE IF NOT EXISTS public.user_departments (
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  department_id uuid NOT NULL REFERENCES public.departments(id) ON DELETE RESTRICT,
  is_primary boolean NOT NULL DEFAULT false,
  assigned_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, department_id)
);

CREATE UNIQUE INDEX IF NOT EXISTS user_departments_one_primary_idx
  ON public.user_departments(user_id) WHERE is_primary;

INSERT INTO public.user_departments(user_id, department_id, is_primary)
SELECT p.id, p.department_id, true
FROM public.profiles p
JOIN public.departments d ON d.id = p.department_id
ON CONFLICT (user_id, department_id) DO UPDATE SET is_primary = true, updated_at = now();

ALTER TABLE public.user_departments ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.user_departments FROM anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.user_departments TO service_role;

CREATE OR REPLACE FUNCTION private.user_has_department(p_user_id uuid, p_department_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM public.user_departments ud
    WHERE ud.user_id = p_user_id AND ud.department_id = p_department_id
  ) OR EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = p_user_id AND p.department_id = p_department_id
  );
$function$;

-- The canonical department-scoped can_access_document implementation is installed by the later authorization correction migration.

CREATE OR REPLACE FUNCTION private.default_document_department()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
BEGIN
  IF NEW.department_id IS NULL AND auth.uid() IS NOT NULL THEN
    SELECT pr.department_id INTO NEW.department_id
    FROM public.profiles pr WHERE pr.id = auth.uid() AND pr.is_active = true;
  END IF;
  RETURN NEW;
END;
$function$;

-- Document insert policy is installed after documents.department_id exists, by the final scoped-RLS migration.

REVOKE ALL ON FUNCTION private.user_has_department(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.user_has_department(uuid, uuid) TO authenticated, service_role;
-- Execute permission for private.can_access_document is granted by its later defining migration.




-- Security-definer registration RPCs must enforce department membership explicitly (RLS is bypassed inside them).
CREATE OR REPLACE FUNCTION private.register_incoming_document(
  p_subject text, p_sender_id uuid, p_external_document_no text,
  p_external_document_date date, p_received_at timestamp with time zone,
  p_urgency public.urgency_level, p_receiving_notes text, p_department_id uuid
)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
DECLARE
  v_uid uuid := (SELECT auth.uid());
  v_register uuid; v_doc uuid; v_no bigint;
BEGIN
  IF v_uid IS NULL OR NOT private.has_permission('registry.incoming.manage') THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'permission denied';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.profiles pr WHERE pr.id = v_uid AND pr.is_active = true) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'active_profile_required';
  END IF;
  IF p_department_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.departments d WHERE d.id = p_department_id AND d.is_active = true
  ) THEN RAISE EXCEPTION USING ERRCODE = '23503', MESSAGE = 'active_document_department_required'; END IF;
  IF NOT private.user_has_department(v_uid, p_department_id)
     AND NOT EXISTS (SELECT 1 FROM public.user_roles ur JOIN public.roles r ON r.id=ur.role_id
       WHERE ur.user_id=v_uid AND r.code='system_admin') THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'department_scope_denied';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.senders s WHERE s.id = p_sender_id AND s.is_active = true) THEN
    RAISE EXCEPTION USING ERRCODE = '23503', MESSAGE = 'active_sender_required';
  END IF;
  SELECT id INTO v_register FROM public.document_registers
    WHERE direction = 'incoming' AND is_active = true ORDER BY document_year DESC, created_at LIMIT 1;
  IF v_register IS NULL THEN RAISE EXCEPTION 'ไม่พบทะเบียนหนังสือรับที่ใช้งานอยู่'; END IF;
  v_no := private.allocate_document_number(v_register,
    (SELECT document_year FROM public.document_registers WHERE id = v_register));
  INSERT INTO public.documents(document_type, register_id, department_id, subject, urgency, status, current_owner_id, created_by)
    VALUES ('incoming', v_register, p_department_id, p_subject, p_urgency, 'received', v_uid, v_uid)
    RETURNING id INTO v_doc;
  INSERT INTO public.incoming_document_details(document_id, sender_id, external_document_no, external_document_date,
    received_at, registered_at, registered_number, receiving_notes)
    VALUES (v_doc, p_sender_id, p_external_document_no, p_external_document_date, p_received_at, now(), v_no, p_receiving_notes);
  INSERT INTO public.document_status_history(document_id, from_status, to_status, changed_by, reason)
    VALUES (v_doc, NULL, 'received', v_uid, 'รับหนังสือเข้าระบบ');
  RETURN v_doc;
END;
$function$;

CREATE OR REPLACE FUNCTION private.register_outgoing_document(
  p_subject text, p_recipient_name text, p_recipient_address text, p_recipient_contact text,
  p_document_date date, p_urgency public.urgency_level, p_department_id uuid
)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
DECLARE
  v_uid uuid := (SELECT auth.uid());
  v_register uuid; v_doc uuid; v_no bigint;
BEGIN
  IF v_uid IS NULL OR NOT private.has_permission('registry.outgoing.manage') THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'permission denied';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.profiles pr WHERE pr.id = v_uid AND pr.is_active = true) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'active_profile_required';
  END IF;
  IF p_department_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.departments d WHERE d.id = p_department_id AND d.is_active = true
  ) THEN RAISE EXCEPTION USING ERRCODE = '23503', MESSAGE = 'active_document_department_required'; END IF;
  IF NOT private.user_has_department(v_uid, p_department_id)
     AND NOT EXISTS (SELECT 1 FROM public.user_roles ur JOIN public.roles r ON r.id=ur.role_id
       WHERE ur.user_id=v_uid AND r.code='system_admin') THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'department_scope_denied';
  END IF;
  SELECT id INTO v_register FROM public.document_registers
    WHERE direction = 'outgoing' AND is_active = true ORDER BY document_year DESC, created_at LIMIT 1;
  IF v_register IS NULL THEN RAISE EXCEPTION 'ไม่พบทะเบียนหนังสือส่งที่ใช้งานอยู่'; END IF;
  v_no := private.allocate_document_number(v_register,
    (SELECT document_year FROM public.document_registers WHERE id = v_register));
  INSERT INTO public.documents(document_type, register_id, department_id, subject, urgency, status, current_owner_id, created_by)
    VALUES ('outgoing', v_register, p_department_id, p_subject, p_urgency, 'draft', v_uid, v_uid)
    RETURNING id INTO v_doc;
  INSERT INTO public.outgoing_document_details(document_id, outgoing_document_no, document_date, recipient_name,
    recipient_address, recipient_contact, registered_number)
    VALUES (v_doc, NULL, COALESCE(p_document_date, current_date), p_recipient_name,
      p_recipient_address, p_recipient_contact, v_no);
  INSERT INTO public.document_status_history(document_id, from_status, to_status, changed_by, reason)
    VALUES (v_doc, NULL, 'draft', v_uid, 'สร้างหนังสือส่งฉบับร่าง');
  RETURN v_doc;
END;
$function$;

-- Assignment validation must consider all active department memberships, not only profiles.department_id.
CREATE OR REPLACE FUNCTION private.assign_document(
  p_document_id uuid,
  p_assignee_id uuid,
  p_instructions text DEFAULT NULL,
  p_due_at timestamp with time zone DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
DECLARE
  v_id uuid;
  v_actor uuid := auth.uid();
  v_subject text;
  v_old public.document_status;
BEGIN
  IF v_actor IS NULL OR NOT private.has_permission('document.assign') THEN
    RAISE EXCEPTION 'permission_denied';
  END IF;
  IF p_due_at IS NOT NULL AND p_due_at <= now() THEN
    RAISE EXCEPTION 'deadline_must_be_future';
  END IF;

  SELECT status, subject INTO v_old, v_subject
  FROM public.documents WHERE id = p_document_id FOR UPDATE;
  IF v_old IS NULL THEN RAISE EXCEPTION 'document_not_found'; END IF;
  IF v_old <> 'registered' THEN RAISE EXCEPTION 'invalid_status_transition'; END IF;
  IF NOT private.can_access_document(p_document_id) THEN
    RAISE EXCEPTION 'document_scope_denied';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = p_assignee_id AND is_active = true
  ) THEN RAISE EXCEPTION 'assignee_not_found'; END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.documents d
    JOIN public.profiles assignee ON assignee.id = p_assignee_id AND assignee.is_active = true
    WHERE d.id = p_document_id
      AND (
        (d.department_id IS NOT NULL AND private.user_has_department(assignee.id, d.department_id))
        OR EXISTS (
          SELECT 1 FROM public.user_roles ur
          JOIN public.roles r ON r.id = ur.role_id
          JOIN public.profiles actor_profile ON actor_profile.id = ur.user_id AND actor_profile.is_active = true
          WHERE ur.user_id = v_actor AND r.code = 'system_admin'
        )
      )
  ) THEN RAISE EXCEPTION 'cross_department_assignment_denied'; END IF;

  INSERT INTO public.document_assignments
    (document_id, assignee_id, assigned_by, instructions, assignment_status)
  VALUES (p_document_id, p_assignee_id, v_actor, p_instructions, 'assigned')
  RETURNING id INTO v_id;

  UPDATE public.documents SET current_owner_id = p_assignee_id, status = 'assigned'
  WHERE id = p_document_id;
  INSERT INTO public.document_status_history
    (document_id, from_status, to_status, changed_by, reason)
  VALUES (p_document_id, v_old, 'assigned', v_actor, 'มอบหมายงาน');
  INSERT INTO public.notifications
    (recipient_id, document_id, type, title, body, priority)
  VALUES (p_assignee_id, p_document_id, 'assignment', 'ได้รับมอบหมายงาน',
    'คุณได้รับมอบหมายเรื่อง: ' || coalesce(v_subject, 'ไม่ระบุเรื่อง'), 'high');

  IF p_due_at IS NOT NULL THEN
    INSERT INTO public.deadlines
      (document_id, assigned_to, due_at, reminder_at, escalation_at, status)
    VALUES (p_document_id, p_assignee_id, p_due_at,
      p_due_at - interval '24 hours', p_due_at, 'open');
  END IF;
  RETURN v_id;
END;
$function$;
REVOKE ALL ON FUNCTION private.assign_document(uuid, uuid, text, timestamptz) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION private.assign_document(uuid, uuid, text, timestamptz) TO authenticated, service_role;

COMMIT;

```

---

## 20261012011559 — production_department_scoped_roles_permissions_v1

```sql
-- Department-scoped role grants and per-department permission matrix.
-- Forward-only migration; validate against recovered catalog before Production.
BEGIN;

CREATE TABLE IF NOT EXISTS public.user_department_roles (
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  department_id uuid NOT NULL REFERENCES public.departments(id) ON DELETE RESTRICT,
  role_id uuid NOT NULL REFERENCES public.roles(id) ON DELETE RESTRICT,
  assigned_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  assigned_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, department_id, role_id)
);
CREATE INDEX IF NOT EXISTS user_department_roles_department_idx
  ON public.user_department_roles(department_id, user_id);

CREATE TABLE IF NOT EXISTS public.department_role_permissions (
  department_id uuid NOT NULL REFERENCES public.departments(id) ON DELETE CASCADE,
  role_id uuid NOT NULL REFERENCES public.roles(id) ON DELETE CASCADE,
  permission_id uuid NOT NULL REFERENCES public.permissions(id) ON DELETE CASCADE,
  enabled boolean NOT NULL DEFAULT true,
  updated_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (department_id, role_id, permission_id)
);

-- Initialize each department's matrix from the current approved role catalogue.
INSERT INTO public.department_role_permissions(department_id, role_id, permission_id, enabled)
SELECT d.id, rp.role_id, rp.permission_id, true
FROM public.departments d
CROSS JOIN public.role_permissions rp
ON CONFLICT (department_id, role_id, permission_id) DO NOTHING;

-- Move ordinary role grants into each user's primary department; keep the two
-- explicitly global roles global. Existing profile department remains canonical.
INSERT INTO public.user_department_roles(user_id, department_id, role_id, assigned_by, assigned_at)
SELECT ur.user_id, p.department_id, ur.role_id, ur.assigned_by, ur.assigned_at
FROM public.user_roles ur
JOIN public.profiles p ON p.id = ur.user_id
JOIN public.roles r ON r.id = ur.role_id
WHERE p.department_id IS NOT NULL
  AND r.code NOT IN ('system_admin', 'director')
ON CONFLICT DO NOTHING;

ALTER TABLE public.user_department_roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.department_role_permissions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.user_department_roles FROM anon, authenticated;
REVOKE ALL ON public.department_role_permissions FROM anon, authenticated;
GRANT SELECT ON public.user_department_roles TO authenticated;
GRANT SELECT ON public.department_role_permissions TO authenticated;
GRANT ALL ON public.user_department_roles TO service_role;
GRANT ALL ON public.department_role_permissions TO service_role;

CREATE OR REPLACE FUNCTION private.has_department_permission(
  p_permission text,
  p_department_id uuid
) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM public.profiles pr
    WHERE pr.id = (SELECT auth.uid())
      AND pr.is_active = true
      AND (
        EXISTS (SELECT 1 FROM public.user_roles ur JOIN public.roles wr ON wr.id = ur.role_id WHERE ur.user_id = (SELECT auth.uid()) AND wr.code IN ('system_admin','director'))
        AND p_permission IN ('document.view','document.create','document.approve','document.update')
        OR EXISTS (
          SELECT 1
          FROM public.user_department_roles udr
          JOIN public.roles r ON r.id = udr.role_id
          JOIN public.department_role_permissions drp
            ON drp.department_id = udr.department_id
           AND drp.role_id = udr.role_id
           AND drp.enabled = true
          JOIN public.permissions p ON p.id = drp.permission_id
          WHERE udr.user_id = pr.id
            AND udr.department_id = p_department_id
            AND p.code = p_permission
        )
      )
  );
$function$;

-- Canonical membership helper used by all scoped authorization functions.
-- Membership is explicit; role grants alone do not create department membership.
CREATE OR REPLACE FUNCTION private.user_has_department(
  p_user_id uuid, p_department_id uuid
) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog','public','private'
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM public.user_departments ud
    WHERE ud.user_id = p_user_id AND ud.department_id = p_department_id
  );
$function$;

REVOKE ALL ON FUNCTION private.user_has_department(uuid,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION private.user_has_department(uuid,uuid) TO authenticated,service_role;

-- Read inheritance is one-way: a child member with document.view in their own
-- department may read its direct parent's documents; sibling scopes never match.
CREATE OR REPLACE FUNCTION private.can_access_document(p_document_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM public.documents d
    JOIN public.profiles pr ON pr.id = (SELECT auth.uid()) AND pr.is_active = true
    WHERE d.id = p_document_id
      AND (
        (private.has_document_wide_read_role() AND private.has_permission('document.view'))
        OR (
          d.department_id IS NOT NULL
          AND (
            (
              private.user_has_department(pr.id, d.department_id)
              AND private.has_department_permission('document.view', d.department_id)
            )
            OR EXISTS (
              SELECT 1 FROM public.user_departments child_ud
              JOIN public.departments child ON child.id = child_ud.department_id
              WHERE child_ud.user_id = pr.id
                AND child.parent_id = d.department_id
                AND private.has_department_permission('document.view', child.id)
            )
            OR (
              private.user_has_department(pr.id, d.department_id)
              AND (
                d.created_by = (SELECT auth.uid())
                OR d.current_owner_id = (SELECT auth.uid())
                OR EXISTS (
                  SELECT 1 FROM public.document_assignments da
                  WHERE da.document_id = d.id AND da.assignee_id = (SELECT auth.uid())
                    AND da.assignment_status = 'assigned'
                )
              )
            )
          )
        )
      )
  );
$function$;

CREATE OR REPLACE FUNCTION public.admin_set_user_department_role(
  p_user_id uuid, p_department_id uuid, p_role_id uuid, p_enabled boolean
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
BEGIN
  IF NOT private.has_permission('user.manage') AND NOT private.has_permission('role.manage') THEN
    RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='insufficient_privilege';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id=p_user_id AND is_active=true) THEN
    RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='user_profile_not_found_or_inactive';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.departments WHERE id=p_department_id AND is_active=true) THEN
    RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='department_not_found_or_inactive';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.roles WHERE id=p_role_id) THEN
    RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='role_not_found';
  END IF;
  IF EXISTS (SELECT 1 FROM public.roles WHERE id=p_role_id AND code IN ('system_admin','director')) THEN
    RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='global_role_must_use_global_role_management';
  END IF;
  IF p_enabled THEN
    IF NOT EXISTS (SELECT 1 FROM public.user_departments
                   WHERE user_id=p_user_id AND department_id=p_department_id) THEN
      RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='user_is_not_member_of_department';
    END IF;
    INSERT INTO public.user_department_roles(user_id,department_id,role_id,assigned_by)
    VALUES (p_user_id,p_department_id,p_role_id,auth.uid())
    ON CONFLICT (user_id,department_id,role_id) DO UPDATE
      SET assigned_by=EXCLUDED.assigned_by, assigned_at=now();
  ELSE
    DELETE FROM public.user_department_roles
    WHERE user_id=p_user_id AND department_id=p_department_id AND role_id=p_role_id;
  END IF;
  INSERT INTO public.audit_logs(actor_id,action,entity_type,entity_id,new_data)
  VALUES (auth.uid(),'department_role.'||CASE WHEN p_enabled THEN 'assigned' ELSE 'removed' END,
          'user',p_user_id,jsonb_build_object('department_id',p_department_id,'role_id',p_role_id,'enabled',p_enabled));
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_set_department_role_permission(
  p_department_id uuid, p_role_id uuid, p_permission_id uuid, p_enabled boolean
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
BEGIN
  IF NOT private.has_permission('user.manage') AND NOT private.has_permission('role.manage') THEN
    RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='insufficient_privilege';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.departments WHERE id=p_department_id AND is_active=true) THEN
    RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='department_not_found_or_inactive';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.roles WHERE id=p_role_id AND code NOT IN ('system_admin','director')) THEN
    RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='global_role_permissions_are_managed_globally';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.permissions WHERE id=p_permission_id) THEN
    RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='permission_not_found';
  END IF;
  INSERT INTO public.department_role_permissions(department_id,role_id,permission_id,enabled,updated_by,updated_at)
  VALUES (p_department_id,p_role_id,p_permission_id,p_enabled,auth.uid(),now())
  ON CONFLICT (department_id,role_id,permission_id) DO UPDATE
    SET enabled=EXCLUDED.enabled, updated_by=EXCLUDED.updated_by, updated_at=now();
  INSERT INTO public.audit_logs(actor_id,action,entity_type,entity_id,new_data)
  VALUES (auth.uid(),'department_role_permission.changed','department',p_department_id,
          jsonb_build_object('role_id',p_role_id,'permission_id',p_permission_id,'enabled',p_enabled));
END;
$function$;

REVOKE ALL ON FUNCTION private.has_department_permission(text,uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.has_department_permission(text,uuid) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.admin_set_user_department_role(uuid,uuid,uuid,boolean) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_set_department_role_permission(uuid,uuid,uuid,boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_set_user_department_role(uuid,uuid,uuid,boolean) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_set_department_role_permission(uuid,uuid,uuid,boolean) TO authenticated, service_role;

COMMIT;

```

---

## 20261012011633 — production_department_role_matrix_seed_fix

```sql
-- Correct scoped-role authorization gaps before any deployment.
BEGIN;

-- Keep global roles out of the per-department permission matrix.
DELETE FROM public.department_role_permissions
WHERE role_id IN (SELECT id FROM public.roles WHERE code IN ('system_admin','director'));

-- Seed only ordinary role grants from the existing catalogue.
INSERT INTO public.department_role_permissions(department_id,role_id,permission_id,enabled)
SELECT d.id, rp.role_id, rp.permission_id, true
FROM public.departments d
JOIN public.role_permissions rp ON true
JOIN public.roles r ON r.id=rp.role_id
WHERE r.code NOT IN ('system_admin','director')
ON CONFLICT (department_id,role_id,permission_id) DO NOTHING;

COMMIT;

```

---

## 20261012011639 — production_department_scoped_read_rpc_fix

```sql
-- Fix global document read check and expose scoped settings through guarded RPCs.
BEGIN;

CREATE OR REPLACE FUNCTION private.can_access_document(p_document_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog','public','private'
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM public.documents d
    JOIN public.profiles pr ON pr.id=(SELECT auth.uid()) AND pr.is_active=true
    WHERE d.id=p_document_id
      AND (
        EXISTS (
          SELECT 1 FROM public.user_roles ur
          JOIN public.roles r ON r.id=ur.role_id
          WHERE ur.user_id=pr.id AND r.code IN ('system_admin','director')
        )
        OR (
          d.department_id IS NOT NULL
          AND (
            (
              private.user_has_department(pr.id,d.department_id)
              AND private.has_department_permission('document.view',d.department_id)
            )
            OR EXISTS (
              SELECT 1 FROM public.user_departments ud
              JOIN public.departments child ON child.id=ud.department_id
              WHERE ud.user_id=pr.id AND child.parent_id=d.department_id
                AND private.has_department_permission('document.view',child.id)
            )
            OR (
              private.user_has_department(pr.id,d.department_id)
              AND (
                d.created_by=pr.id OR d.current_owner_id=pr.id
                OR EXISTS (
                  SELECT 1 FROM public.document_assignments da
                  WHERE da.document_id=d.id AND da.assignee_id=pr.id
                    AND da.assignment_status='assigned'
                )
              )
            )
          )
        )
      )
  );
$function$;

CREATE OR REPLACE FUNCTION public.admin_get_department_permission_catalog()
RETURNS TABLE (
  department_id uuid, department_name text, department_parent_id uuid,
  role_id uuid, role_code text, role_name text,
  permission_id uuid, permission_code text, permission_name text, enabled boolean
)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog','public','private'
AS $function$
BEGIN
  IF NOT private.has_permission('user.manage') AND NOT private.has_permission('role.manage') THEN
    RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='insufficient_privilege';
  END IF;
  RETURN QUERY
  SELECT d.id,d.name::text,d.parent_id,r.id,r.code::text,r.name::text,
         p.id,p.code::text,p.name::text,COALESCE(drp.enabled,false)
  FROM public.departments d CROSS JOIN public.roles r CROSS JOIN public.permissions p
  LEFT JOIN public.department_role_permissions drp
    ON drp.department_id=d.id AND drp.role_id=r.id AND drp.permission_id=p.id
  WHERE d.is_active=true AND r.code NOT IN ('system_admin','director')
  ORDER BY d.name,r.name,p.name;
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_get_user_department_roles()
RETURNS TABLE(user_id uuid,department_id uuid,role_id uuid,role_code text,role_name text)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog','public','private'
AS $function$
BEGIN
  IF NOT private.has_permission('user.manage') AND NOT private.has_permission('role.manage') THEN
    RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='insufficient_privilege';
  END IF;
  RETURN QUERY
  SELECT udr.user_id,udr.department_id,r.id,r.code::text,r.name::text
  FROM public.user_department_roles udr JOIN public.roles r ON r.id=udr.role_id
  ORDER BY udr.user_id,udr.department_id,r.name;
END;
$function$;

REVOKE ALL ON FUNCTION private.can_access_document(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION private.can_access_document(uuid) TO authenticated,service_role;
REVOKE ALL ON FUNCTION public.admin_get_department_permission_catalog() FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.admin_get_user_department_roles() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.admin_get_department_permission_catalog() TO authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.admin_get_user_department_roles() TO authenticated,service_role;

COMMIT;

```

---

## 20261012011646 — production_department_scoped_write_rpc_guards

```sql
-- Authorization completion gate: department-scope document write RPCs.
-- This migration deliberately does not replace approval workflow RPCs until their
-- full state-transition and notification behavior has isolated regression tests.
-- Forward-only; validate on isolated database before Production.
BEGIN;

CREATE OR REPLACE FUNCTION private.assign_document(
  p_document_id uuid, p_assignee_id uuid, p_instructions text DEFAULT NULL,
  p_due_at timestamptz DEFAULT NULL
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','public','private'
AS $function$
DECLARE
  v_id uuid; v_actor uuid := auth.uid(); v_subject text; v_old public.document_status;
  v_department uuid; v_assignee_department uuid;
BEGIN
  IF v_actor IS NULL THEN RAISE EXCEPTION 'permission_denied'; END IF;
  SELECT status,subject,department_id INTO v_old,v_subject,v_department
    FROM public.documents WHERE id=p_document_id FOR UPDATE;
  IF v_old IS NULL THEN RAISE EXCEPTION 'document_not_found'; END IF;
  IF v_old <> 'registered' THEN RAISE EXCEPTION 'invalid_status_transition'; END IF;
  IF v_department IS NULL OR NOT private.can_access_document(p_document_id)
     OR NOT private.has_department_permission('document.assign',v_department) THEN
    RAISE EXCEPTION 'document_scope_denied';
  END IF;
  IF p_due_at IS NOT NULL AND p_due_at<=now() THEN RAISE EXCEPTION 'deadline_must_be_future'; END IF;
  SELECT department_id INTO v_assignee_department FROM public.profiles
    WHERE id=p_assignee_id AND is_active=true;
  IF NOT FOUND THEN RAISE EXCEPTION 'assignee_not_found'; END IF;
  IF v_assignee_department IS DISTINCT FROM v_department
     AND NOT EXISTS (SELECT 1 FROM public.user_departments ud
                     WHERE ud.user_id=p_assignee_id AND ud.department_id=v_department) THEN
    RAISE EXCEPTION 'cross_department_assignment_denied';
  END IF;
  INSERT INTO public.document_assignments(document_id,assignee_id,assigned_by,instructions,assignment_status)
    VALUES(p_document_id,p_assignee_id,v_actor,p_instructions,'assigned') RETURNING id INTO v_id;
  UPDATE public.documents SET current_owner_id=p_assignee_id,status='assigned' WHERE id=p_document_id;
  INSERT INTO public.document_status_history(document_id,from_status,to_status,changed_by,reason)
    VALUES(p_document_id,v_old,'assigned',v_actor,'มอบหมายงาน');
  INSERT INTO public.notifications(recipient_id,document_id,type,title,body,priority)
    VALUES(p_assignee_id,p_document_id,'assignment','ได้รับมอบหมายงาน',
      'คุณได้รับมอบหมายเรื่อง: '||coalesce(v_subject,'ไม่ระบุเรื่อง'),'high');
  IF p_due_at IS NOT NULL THEN
    INSERT INTO public.deadlines(document_id,assigned_to,due_at,reminder_at,escalation_at,status)
      VALUES(p_document_id,p_assignee_id,p_due_at,p_due_at-interval '24 hours',p_due_at,'open');
  END IF;
  RETURN v_id;
END;
$function$;

CREATE OR REPLACE FUNCTION private.set_document_deadline(
  p_document_id uuid,p_assigned_to uuid,p_due_at timestamptz,p_reminder_at timestamptz DEFAULT NULL
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','public','private'
AS $function$
DECLARE v_id uuid; v_department uuid; v_assignee_department uuid;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'permission_denied'; END IF;
  SELECT department_id INTO v_department FROM public.documents WHERE id=p_document_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'document_not_found'; END IF;
  IF v_department IS NULL OR NOT private.can_access_document(p_document_id)
     OR NOT private.has_department_permission('document.assign',v_department) THEN
    RAISE EXCEPTION 'document_scope_denied';
  END IF;
  SELECT department_id INTO v_assignee_department FROM public.profiles
    WHERE id=p_assigned_to AND is_active=true;
  IF NOT FOUND THEN RAISE EXCEPTION 'assignee_not_found'; END IF;
  IF v_assignee_department IS DISTINCT FROM v_department
     AND NOT EXISTS (SELECT 1 FROM public.user_departments ud
                     WHERE ud.user_id=p_assigned_to AND ud.department_id=v_department) THEN
    RAISE EXCEPTION 'cross_department_assignment_denied';
  END IF;
  IF p_due_at<=now() THEN RAISE EXCEPTION 'deadline_must_be_future'; END IF;
  IF p_reminder_at IS NOT NULL AND p_reminder_at>p_due_at THEN
    RAISE EXCEPTION 'reminder_must_be_before_deadline';
  END IF;
  INSERT INTO public.deadlines(document_id,assigned_to,due_at,reminder_at,escalation_at,status)
    VALUES(p_document_id,p_assigned_to,p_due_at,coalesce(p_reminder_at,p_due_at-interval '24 hours'),p_due_at,'open')
    RETURNING id INTO v_id;
  RETURN v_id;
END;
$function$;

CREATE OR REPLACE FUNCTION private.update_document_status(
  p_document_id uuid,p_to_status public.document_status,p_reason text DEFAULT NULL
) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','public','private'
AS $function$
DECLARE v_actor uuid:=auth.uid(); v_from public.document_status; v_department uuid; v_permission text;
BEGIN
  IF v_actor IS NULL THEN RAISE EXCEPTION 'permission_denied'; END IF;
  SELECT status,department_id INTO v_from,v_department FROM public.documents
    WHERE id=p_document_id FOR UPDATE;
  IF v_from IS NULL THEN RAISE EXCEPTION 'document_not_found'; END IF;
  IF NOT private.can_access_document(p_document_id) THEN RAISE EXCEPTION 'document_scope_denied'; END IF;
  IF v_from=p_to_status THEN RETURN true; END IF;
  IF p_to_status IN ('pending_approval','approved','assigned')
     OR (v_from='pending_approval' AND p_to_status='draft') THEN
    RAISE EXCEPTION 'use_dedicated_workflow_rpc';
  END IF;
  v_permission := CASE WHEN p_to_status='completed' THEN 'document.complete'
                       WHEN p_to_status='archived' THEN 'document.archive'
                       ELSE 'document.update' END;
  IF v_department IS NULL OR NOT private.has_department_permission(v_permission,v_department) THEN
    RAISE EXCEPTION 'permission_denied';
  END IF;
  IF NOT private.is_valid_document_transition(p_document_id,v_from,p_to_status) THEN
    RAISE EXCEPTION 'invalid_status_transition';
  END IF;
  UPDATE public.documents SET status=p_to_status WHERE id=p_document_id;
  INSERT INTO public.document_status_history(document_id,from_status,to_status,changed_by,reason)
    VALUES(p_document_id,v_from,p_to_status,v_actor,p_reason);
  IF p_to_status IN ('completed','archived') THEN
    UPDATE public.deadlines SET status='completed',completed_at=coalesce(completed_at,now())
      WHERE document_id=p_document_id AND status='open';
  END IF;
  RETURN true;
END;
$function$;

REVOKE ALL ON FUNCTION private.assign_document(uuid,uuid,text,timestamptz) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION private.set_document_deadline(uuid,uuid,timestamptz,timestamptz) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION private.update_document_status(uuid,public.document_status,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION private.assign_document(uuid,uuid,text,timestamptz) TO authenticated,service_role;
GRANT EXECUTE ON FUNCTION private.set_document_deadline(uuid,uuid,timestamptz,timestamptz) TO authenticated,service_role;
GRANT EXECUTE ON FUNCTION private.update_document_status(uuid,public.document_status,text) TO authenticated,service_role;

COMMIT;

```

---

## 20261012011653 — production_department_scoped_access_final_correction

```sql
-- Final authorization correction after write guards.
-- Fixes migration-order regression: the scoped access helper must not depend on
-- an optional legacy helper, and global school roles retain explicit requested
-- document read/create/update/approve rights across departments.
BEGIN;

CREATE OR REPLACE FUNCTION private.has_department_permission(
  p_permission text, p_department_id uuid
) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog','public','private'
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles pr
    WHERE pr.id=(SELECT auth.uid()) AND pr.is_active=true
      AND (
        (
          p_permission IN ('document.view','document.create','document.update','document.approve')
          AND EXISTS (
            SELECT 1 FROM public.user_roles ur
            JOIN public.roles r ON r.id=ur.role_id
            WHERE ur.user_id=pr.id AND r.code IN ('system_admin','director')
          )
        )
        OR EXISTS (
          SELECT 1
          FROM public.user_department_roles udr
          JOIN public.department_role_permissions drp
            ON drp.department_id=udr.department_id
           AND drp.role_id=udr.role_id AND drp.enabled=true
          JOIN public.permissions p ON p.id=drp.permission_id
          WHERE udr.user_id=pr.id
            AND udr.department_id=p_department_id
            AND p.code=p_permission
        )
      )
  );
$function$;

CREATE OR REPLACE FUNCTION private.can_access_document(p_document_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog','public','private'
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM public.documents d
    JOIN public.profiles pr ON pr.id=(SELECT auth.uid()) AND pr.is_active=true
    WHERE d.id=p_document_id
      AND (
        EXISTS (
          SELECT 1 FROM public.user_roles ur
          JOIN public.roles r ON r.id=ur.role_id
          WHERE ur.user_id=pr.id AND r.code IN ('system_admin','director')
        )
        OR (
          d.department_id IS NOT NULL
          AND (
            (
              private.user_has_department(pr.id,d.department_id)
              AND private.has_department_permission('document.view',d.department_id)
            )
            OR EXISTS (
              SELECT 1 FROM public.user_departments ud
              JOIN public.departments child ON child.id=ud.department_id
              WHERE ud.user_id=pr.id AND child.parent_id=d.department_id
                AND private.has_department_permission('document.view',child.id)
            )
          )
        )
      )
  );
$function$;

REVOKE ALL ON FUNCTION private.has_department_permission(text,uuid) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION private.can_access_document(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION private.has_department_permission(text,uuid) TO authenticated,service_role;
GRANT EXECUTE ON FUNCTION private.can_access_document(uuid) TO authenticated,service_role;

COMMIT;

```

---

## 20261012011659 — production_department_scoped_approval_guards

```sql
-- Scope approval creation and decisions to the document's department while
-- preserving existing state transitions and notifications from the recovered catalog.
BEGIN;

CREATE OR REPLACE FUNCTION private.create_approval(
  p_document_id uuid, p_approver_id uuid, p_approval_step integer DEFAULT 1
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','public','private'
AS $function$
DECLARE
  v_id uuid; v_actor uuid:=auth.uid(); v_subject text;
  v_status public.document_status; v_department uuid;
BEGIN
  IF v_actor IS NULL THEN RAISE EXCEPTION 'permission_denied'; END IF;
  SELECT status,subject,department_id INTO v_status,v_subject,v_department
  FROM public.documents WHERE id=p_document_id FOR UPDATE;
  IF v_status IS NULL THEN RAISE EXCEPTION 'document_not_found'; END IF;
  IF v_department IS NULL OR NOT private.can_access_document(p_document_id)
     OR NOT private.has_department_permission('document.approve',v_department) THEN
    RAISE EXCEPTION 'permission_denied';
  END IF;
  IF p_approval_step < 1 THEN RAISE EXCEPTION 'invalid_approval_step'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.profiles pr
    WHERE pr.id=p_approver_id AND pr.is_active=true
      AND (
        EXISTS (SELECT 1 FROM public.user_roles ur JOIN public.roles r ON r.id=ur.role_id
                WHERE ur.user_id=pr.id AND r.code IN ('system_admin','director'))
        OR EXISTS (
          SELECT 1 FROM public.user_department_roles udr
          JOIN public.department_role_permissions drp
            ON drp.department_id=udr.department_id AND drp.role_id=udr.role_id
            AND drp.enabled=true
          JOIN public.permissions p ON p.id=drp.permission_id
          WHERE udr.user_id=pr.id AND udr.department_id=v_department
            AND p.code='document.approve'
        )
      )
  ) THEN RAISE EXCEPTION 'approver_not_authorized'; END IF;
  IF v_status <> 'draft' THEN RAISE EXCEPTION 'document_not_in_draft'; END IF;

  INSERT INTO public.approvals(document_id,approval_step,approver_id,decision)
  VALUES(p_document_id,p_approval_step,p_approver_id,'pending') RETURNING id INTO v_id;
  UPDATE public.documents SET status='pending_approval' WHERE id=p_document_id;
  INSERT INTO public.notifications(recipient_id,document_id,type,title,body,priority)
  VALUES(p_approver_id,p_document_id,'approval','รอการอนุมัติ',
         'มีเอกสารรอการอนุมัติ: '||coalesce(v_subject,'ไม่ระบุเรื่อง'),'high');
  RETURN v_id;
END;
$function$;

CREATE OR REPLACE FUNCTION private.decide_approval(
  p_approval_id uuid, p_decision public.approval_decision, p_comment text DEFAULT NULL
) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','public','private'
AS $function$
DECLARE
  v_actor uuid:=auth.uid(); v_doc uuid; v_step integer; v_subject text; v_department uuid;
BEGIN
  IF v_actor IS NULL THEN RAISE EXCEPTION 'permission_denied'; END IF;
  SELECT a.document_id,a.approval_step,d.department_id
    INTO v_doc,v_step,v_department
  FROM public.approvals a
  JOIN public.documents d ON d.id=a.document_id
  WHERE a.id=p_approval_id AND a.approver_id=v_actor AND a.decision='pending'
  FOR UPDATE OF a;
  IF v_doc IS NULL THEN RAISE EXCEPTION 'approval_not_found_or_not_authorized'; END IF;
  IF v_department IS NULL OR NOT private.can_access_document(v_doc)
     OR NOT private.has_department_permission('document.approve',v_department) THEN
    RAISE EXCEPTION 'permission_denied';
  END IF;
  IF p_decision NOT IN ('approved','rejected','returned') THEN
    RAISE EXCEPTION 'invalid_approval_decision';
  END IF;

  UPDATE public.approvals SET decision=p_decision,comment=p_comment,decided_at=now()
    WHERE id=p_approval_id;
  IF p_decision='approved' THEN
    IF EXISTS(SELECT 1 FROM public.approvals
              WHERE document_id=v_doc AND approval_step>v_step AND decision='pending') THEN
      UPDATE public.documents SET status='pending_approval' WHERE id=v_doc;
    ELSE
      UPDATE public.documents SET status='approved' WHERE id=v_doc;
    END IF;
  ELSIF p_decision IN ('rejected','returned') THEN
    UPDATE public.documents SET status='draft' WHERE id=v_doc;
  END IF;
  SELECT subject INTO v_subject FROM public.documents WHERE id=v_doc;
  INSERT INTO public.notifications(recipient_id,document_id,type,title,body,priority)
  SELECT DISTINCT d.created_by,v_doc,'approval_decision','ผลการอนุมัติ',
    'เอกสาร "'||coalesce(v_subject,'ไม่ระบุเรื่อง')||'" มีผลการพิจารณา: '||p_decision::text,'high'
  FROM public.documents d WHERE d.id=v_doc AND d.created_by IS NOT NULL;
  RETURN true;
END;
$function$;

REVOKE ALL ON FUNCTION private.create_approval(uuid,uuid,integer) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION private.decide_approval(uuid,public.approval_decision,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION private.create_approval(uuid,uuid,integer) TO authenticated,service_role;
GRANT EXECUTE ON FUNCTION private.decide_approval(uuid,public.approval_decision,text) TO authenticated,service_role;
COMMIT;

```

---

## 20261012011708 — production_department_scoped_rls_and_file_guards

```sql
-- Close direct RLS and file attachment paths that bypass department-scoped access.
-- Apply only after the recovered-catalog fixture and regression tests pass.
BEGIN;

-- File attachment is a document mutation: check the target document's department,
-- not merely a legacy global document.update permission.
CREATE OR REPLACE FUNCTION public.attach_document_file_version(
  p_document_id uuid,
  p_google_drive_file_id uuid,
  p_file_role text DEFAULT 'main'
)
RETURNS TABLE(
  id uuid, document_id uuid, google_drive_file_id uuid, file_role text,
  version_no integer, is_current boolean, uploaded_by uuid, uploaded_at timestamptz
)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','public','private'
AS $function$
DECLARE
  v_id uuid; v_version integer; v_department uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION USING errcode='42501',message='authentication_required';
  END IF;
  SELECT d.department_id INTO v_department
    FROM public.documents d WHERE d.id=p_document_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING errcode='22023',message='document_not_found';
  END IF;
  IF v_department IS NULL
     OR NOT private.can_access_document(p_document_id)
     OR NOT private.has_department_permission('document.update',v_department) THEN
    RAISE EXCEPTION USING errcode='42501',message='document_scope_denied';
  END IF;
  IF p_file_role IS NULL OR btrim(p_file_role)='' THEN
    RAISE EXCEPTION USING errcode='22023',message='file_role_required';
  END IF;
  IF NOT EXISTS(SELECT 1 FROM public.google_drive_files f WHERE f.id=p_google_drive_file_id) THEN
    RAISE EXCEPTION USING errcode='22023',message='google_drive_file_not_found';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(p_document_id::text||':'||p_file_role,0));
  SELECT coalesce(max(df.version_no),0)+1 INTO v_version
    FROM public.document_files df
    WHERE df.document_id=p_document_id AND df.file_role=p_file_role;
  UPDATE public.document_files SET is_current=false
    WHERE document_id=p_document_id AND file_role=p_file_role AND is_current=true;
  UPDATE public.google_drive_files SET created_by=coalesce(created_by,auth.uid())
    WHERE id=p_google_drive_file_id;
  INSERT INTO public.document_files(document_id,google_drive_file_id,file_role,version_no,is_current,uploaded_by)
    VALUES(p_document_id,p_google_drive_file_id,p_file_role,v_version,true,auth.uid())
    RETURNING document_files.id INTO v_id;
  RETURN QUERY SELECT df.id,df.document_id,df.google_drive_file_id,df.file_role,
    df.version_no,df.is_current,df.uploaded_by,df.uploaded_at
    FROM public.document_files df WHERE df.id=v_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.attach_document_file_version(uuid,uuid,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.attach_document_file_version(uuid,uuid,text) TO authenticated,service_role;

-- Child records inherit access only through their parent document. Do not use
-- row ownership or legacy global permission checks as an alternative path.
DROP POLICY IF EXISTS comments_select_authorized ON public.comments;
CREATE POLICY comments_select_authorized ON public.comments
  FOR SELECT TO authenticated
  USING (private.can_access_document(document_id));

DROP POLICY IF EXISTS document_files_authorized ON public.document_files;
CREATE POLICY document_files_authorized ON public.document_files
  FOR SELECT TO authenticated
  USING (private.can_access_document(document_id));

DROP POLICY IF EXISTS status_history_select_authorized ON public.document_status_history;
CREATE POLICY status_history_select_authorized ON public.document_status_history
  FOR SELECT TO authenticated
  USING (private.can_access_document(document_id));

DROP POLICY IF EXISTS approvals_select_authorized ON public.approvals;
CREATE POLICY approvals_select_authorized ON public.approvals
  FOR SELECT TO authenticated
  USING (private.can_access_document(document_id));

DROP POLICY IF EXISTS approvals_insert_authorized ON public.approvals;
CREATE POLICY approvals_insert_authorized ON public.approvals
  FOR INSERT TO authenticated
  WITH CHECK (
    approver_id=(SELECT auth.uid())
    AND EXISTS (
      SELECT 1 FROM public.documents d
      WHERE d.id=approvals.document_id
        AND private.can_access_document(d.id)
        AND private.has_department_permission('document.approve',d.department_id)
    )
  );

DROP POLICY IF EXISTS approvals_update_authorized ON public.approvals;
CREATE POLICY approvals_update_authorized ON public.approvals
  FOR UPDATE TO authenticated
  USING (
    approver_id=(SELECT auth.uid())
    AND EXISTS (
      SELECT 1 FROM public.documents d
      WHERE d.id=approvals.document_id
        AND private.can_access_document(d.id)
        AND private.has_department_permission('document.approve',d.department_id)
    )
  )
  WITH CHECK (
    approver_id=(SELECT auth.uid())
    AND EXISTS (
      SELECT 1 FROM public.documents d
      WHERE d.id=approvals.document_id
        AND private.can_access_document(d.id)
        AND private.has_department_permission('document.approve',d.department_id)
    )
  );

DROP POLICY IF EXISTS documents_select_authorized ON public.documents;
CREATE POLICY documents_select_authorized ON public.documents
  FOR SELECT TO authenticated USING (private.can_access_document(id));

DROP POLICY IF EXISTS documents_insert_authorized ON public.documents;
CREATE POLICY documents_insert_authorized ON public.documents
  FOR INSERT TO authenticated
  WITH CHECK (
    created_by=(SELECT auth.uid())
    AND department_id IS NOT NULL
    AND private.has_department_permission('document.create',department_id)
  );

DROP POLICY IF EXISTS documents_update_authorized ON public.documents;
CREATE POLICY documents_update_authorized ON public.documents
  FOR UPDATE TO authenticated
  USING (
    private.can_access_document(id)
    AND department_id IS NOT NULL
    AND (
      private.has_department_permission('document.update',department_id)
      OR private.has_department_permission('document.assign',department_id)
      OR private.has_department_permission('document.approve',department_id)
    )
  )
  WITH CHECK (
    private.can_access_document(id)
    AND department_id IS NOT NULL
    AND (
      private.has_department_permission('document.update',department_id)
      OR private.has_department_permission('document.assign',department_id)
      OR private.has_department_permission('document.approve',department_id)
    )
  );

COMMIT;

```

---

## 20261012011719 — production_close_remaining_department_rls_bypasses

```sql
-- Close remaining direct-table policy paths that still rely on global legacy permissions.
BEGIN;

DROP POLICY IF EXISTS assignments_insert_authorized ON public.document_assignments;
CREATE POLICY assignments_insert_authorized ON public.document_assignments
  FOR INSERT TO authenticated WITH CHECK (
    assigned_by=(SELECT auth.uid())
    AND EXISTS (SELECT 1 FROM public.documents d
      WHERE d.id=document_assignments.document_id
        AND private.can_access_document(d.id)
        AND private.has_department_permission('document.assign',d.department_id))
  );

DROP POLICY IF EXISTS assignments_update_authorized ON public.document_assignments;
CREATE POLICY assignments_update_authorized ON public.document_assignments
  FOR UPDATE TO authenticated
  USING (EXISTS (SELECT 1 FROM public.documents d
    WHERE d.id=document_assignments.document_id
      AND private.can_access_document(d.id)
      AND (assignee_id=(SELECT auth.uid()) OR assigned_by=(SELECT auth.uid())
        OR private.has_department_permission('document.assign',d.department_id))))
  WITH CHECK (EXISTS (SELECT 1 FROM public.documents d
    WHERE d.id=document_assignments.document_id
      AND private.can_access_document(d.id)
      AND (assignee_id=(SELECT auth.uid()) OR assigned_by=(SELECT auth.uid())
        OR private.has_department_permission('document.assign',d.department_id))));

DROP POLICY IF EXISTS deadlines_manage_authorized ON public.deadlines;
CREATE POLICY deadlines_manage_authorized ON public.deadlines
  FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM public.documents d
    WHERE d.id=deadlines.document_id AND private.can_access_document(d.id)
      AND (assigned_to=(SELECT auth.uid())
        OR private.has_department_permission('document.assign',d.department_id))))
  WITH CHECK (EXISTS (SELECT 1 FROM public.documents d
    WHERE d.id=deadlines.document_id AND private.can_access_document(d.id)
      AND (assigned_to=(SELECT auth.uid())
        OR private.has_department_permission('document.assign',d.department_id))));

DROP POLICY IF EXISTS comments_update_own ON public.comments;
CREATE POLICY comments_update_own ON public.comments
  FOR UPDATE TO authenticated
  USING (author_id=(SELECT auth.uid()) AND private.can_access_document(document_id))
  WITH CHECK (author_id=(SELECT auth.uid()) AND private.can_access_document(document_id));

DROP POLICY IF EXISTS documents_insert_authorized ON public.documents;
CREATE POLICY documents_insert_authorized ON public.documents
  FOR INSERT TO authenticated WITH CHECK (
    created_by=(SELECT auth.uid()) AND department_id IS NOT NULL
    AND private.has_department_permission('document.create',department_id));

DROP POLICY IF EXISTS documents_update_authorized ON public.documents;
CREATE POLICY documents_update_authorized ON public.documents
  FOR UPDATE TO authenticated
  USING (private.can_access_document(id) AND department_id IS NOT NULL
    AND (private.has_department_permission('document.update',department_id)
      OR private.has_department_permission('document.assign',department_id)
      OR private.has_department_permission('document.approve',department_id)))
  WITH CHECK (private.can_access_document(id) AND department_id IS NOT NULL
    AND (private.has_department_permission('document.update',department_id)
      OR private.has_department_permission('document.assign',department_id)
      OR private.has_department_permission('document.approve',department_id)));

DROP POLICY IF EXISTS incoming_details_insert_registry ON public.incoming_document_details;
CREATE POLICY incoming_details_insert_registry ON public.incoming_document_details
  FOR INSERT TO authenticated WITH CHECK (EXISTS (
    SELECT 1 FROM public.documents d WHERE d.id=incoming_document_details.document_id
      AND private.can_access_document(d.id)
      AND private.has_department_permission('registry.incoming.manage',d.department_id)));

DROP POLICY IF EXISTS incoming_details_update_registry ON public.incoming_document_details;
CREATE POLICY incoming_details_update_registry ON public.incoming_document_details
  FOR UPDATE TO authenticated
  USING (EXISTS (SELECT 1 FROM public.documents d
    WHERE d.id=incoming_document_details.document_id AND private.can_access_document(d.id)
      AND private.has_department_permission('registry.incoming.manage',d.department_id)))
  WITH CHECK (EXISTS (SELECT 1 FROM public.documents d
    WHERE d.id=incoming_document_details.document_id AND private.can_access_document(d.id)
      AND private.has_department_permission('registry.incoming.manage',d.department_id)));

DROP POLICY IF EXISTS outgoing_details_insert_registry ON public.outgoing_document_details;
CREATE POLICY outgoing_details_insert_registry ON public.outgoing_document_details
  FOR INSERT TO authenticated WITH CHECK (EXISTS (
    SELECT 1 FROM public.documents d WHERE d.id=outgoing_document_details.document_id
      AND private.can_access_document(d.id)
      AND private.has_department_permission('registry.outgoing.manage',d.department_id)));

DROP POLICY IF EXISTS outgoing_details_update_registry ON public.outgoing_document_details;
CREATE POLICY outgoing_details_update_registry ON public.outgoing_document_details
  FOR UPDATE TO authenticated
  USING (EXISTS (SELECT 1 FROM public.documents d
    WHERE d.id=outgoing_document_details.document_id AND private.can_access_document(d.id)
      AND private.has_department_permission('registry.outgoing.manage',d.department_id)))
  WITH CHECK (EXISTS (SELECT 1 FROM public.documents d
    WHERE d.id=outgoing_document_details.document_id AND private.can_access_document(d.id)
      AND private.has_department_permission('registry.outgoing.manage',d.department_id)));

COMMIT;

```

---

## 20261012011729 — production_separate_document_edit_from_approve_assign

```sql
-- Prevent assignment/approval privileges from implicitly granting document edits.
-- Workflow RPCs remain responsible for their own state transitions.
BEGIN;

DROP POLICY IF EXISTS documents_update_authorized ON public.documents;
CREATE POLICY documents_update_authorized ON public.documents
  FOR UPDATE TO authenticated
  USING (
    private.can_access_document(id)
    AND department_id IS NOT NULL
    AND private.has_department_permission('document.update',department_id)
  )
  WITH CHECK (
    private.can_access_document(id)
    AND department_id IS NOT NULL
    AND private.has_department_permission('document.update',department_id)
  );

COMMIT;

```

---

## 20261012011736 — production_guard_document_file_attachment

```sql
-- Make attachment RPC reject cross-document file reuse and remove PL/pgSQL output-column ambiguity.
BEGIN;

CREATE OR REPLACE FUNCTION public.attach_document_file_version(
  p_document_id uuid,
  p_google_drive_file_id uuid,
  p_file_role text DEFAULT 'main'
)
RETURNS TABLE(
  id uuid, document_id uuid, google_drive_file_id uuid, file_role text,
  version_no integer, is_current boolean, uploaded_by uuid, uploaded_at timestamptz
)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','public','private'
AS $function$
DECLARE
  v_id uuid;
  v_version integer;
  v_department uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION USING errcode='42501',message='authentication_required';
  END IF;

  SELECT d.department_id INTO v_department
  FROM public.documents AS d
  WHERE d.id = p_document_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING errcode='22023',message='document_not_found';
  END IF;

  IF v_department IS NULL
     OR NOT private.can_access_document(p_document_id)
     OR NOT private.has_department_permission('document.update',v_department) THEN
    RAISE EXCEPTION USING errcode='42501',message='document_scope_denied';
  END IF;

  IF p_file_role IS NULL OR btrim(p_file_role) = '' THEN
    RAISE EXCEPTION USING errcode='22023',message='file_role_required';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.google_drive_files AS f
    WHERE f.id = p_google_drive_file_id
  ) THEN
    RAISE EXCEPTION USING errcode='22023',message='google_drive_file_not_found';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.document_files AS existing_file
    WHERE existing_file.google_drive_file_id = p_google_drive_file_id
      AND existing_file.document_id <> p_document_id
  ) THEN
    RAISE EXCEPTION USING
      errcode='23505',
      message='file_already_linked_to_another_document';
  END IF;

  PERFORM pg_advisory_xact_lock(
    hashtextextended(p_document_id::text || ':' || p_file_role, 0)
  );

  SELECT coalesce(max(df.version_no), 0) + 1 INTO v_version
  FROM public.document_files AS df
  WHERE df.document_id = p_document_id
    AND df.file_role = p_file_role;

  UPDATE public.document_files AS df
  SET is_current = false
  WHERE df.document_id = p_document_id
    AND df.file_role = p_file_role
    AND df.is_current = true;

  UPDATE public.google_drive_files AS gdf
  SET created_by = coalesce(gdf.created_by, auth.uid())
  WHERE gdf.id = p_google_drive_file_id;

  INSERT INTO public.document_files(
    document_id, google_drive_file_id, file_role, version_no, is_current, uploaded_by
  )
  VALUES (
    p_document_id, p_google_drive_file_id, p_file_role, v_version, true, auth.uid()
  )
  RETURNING document_files.id INTO v_id;

  RETURN QUERY
  SELECT df.id, df.document_id, df.google_drive_file_id, df.file_role,
         df.version_no, df.is_current, df.uploaded_by, df.uploaded_at
  FROM public.document_files AS df
  WHERE df.id = v_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.attach_document_file_version(uuid,uuid,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.attach_document_file_version(uuid,uuid,text) TO authenticated, service_role;

COMMIT;

```

---

## 20261012011746 — production_require_department_membership_for_scoped_permissions

```sql
-- Require active department membership for every scoped role grant.
-- Prevent stale role rows from granting permissions after a membership is removed.
BEGIN;

CREATE OR REPLACE FUNCTION private.has_department_permission(
  p_permission text,
  p_department_id uuid
) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM public.profiles pr
    WHERE pr.id = (SELECT auth.uid())
      AND pr.is_active = true
      AND (
        (
          EXISTS (
            SELECT 1
            FROM public.user_roles ur
            JOIN public.roles wr ON wr.id = ur.role_id
            WHERE ur.user_id = (SELECT auth.uid())
              AND wr.code IN ('system_admin','director')
          )
          AND p_permission IN ('document.view','document.create','document.approve','document.update')
        )
        OR EXISTS (
          SELECT 1
          FROM public.user_department_roles udr
          JOIN public.user_departments ud
            ON ud.user_id = udr.user_id
           AND ud.department_id = udr.department_id
          JOIN public.roles r ON r.id = udr.role_id
          JOIN public.department_role_permissions drp
            ON drp.department_id = udr.department_id
           AND drp.role_id = udr.role_id
           AND drp.enabled = true
          JOIN public.permissions p ON p.id = drp.permission_id
          WHERE udr.user_id = pr.id
            AND udr.department_id = p_department_id
            AND p.code = p_permission
        )
      )
  );
$function$;

REVOKE ALL ON FUNCTION private.has_department_permission(text,uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.has_department_permission(text,uuid) TO authenticated, service_role;

COMMIT;

```

---

## 20261012011831 — production_require_explicit_active_department_membership

```sql
-- Department scope must be based only on explicit membership in an active department.
-- profiles.department_id remains a primary-department display/compatibility field, not an authorization grant.
BEGIN;

CREATE OR REPLACE FUNCTION private.user_has_department(
  p_user_id uuid,
  p_department_id uuid
) RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM public.user_departments ud
    JOIN public.departments d
      ON d.id = ud.department_id
     AND d.is_active = true
    JOIN public.profiles pr
      ON pr.id = ud.user_id
     AND pr.is_active = true
    WHERE ud.user_id = p_user_id
      AND ud.department_id = p_department_id
  );
$function$;

REVOKE ALL ON FUNCTION private.user_has_department(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.user_has_department(uuid, uuid) TO authenticated, service_role;

COMMIT;

```

---

## 20261012024902 — secure_department_membership_management_rpc

```sql
BEGIN;

CREATE OR REPLACE FUNCTION private.admin_get_user_department_memberships_impl()
RETURNS TABLE(user_id uuid, department_id uuid, department_code text, department_name text, is_primary boolean)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
BEGIN
  IF auth.uid() IS NULL OR (NOT private.has_permission('user.manage') AND NOT private.has_permission('role.manage')) THEN
    RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='insufficient_privilege';
  END IF;
  RETURN QUERY
    SELECT ud.user_id, ud.department_id, d.code, d.name, ud.is_primary
    FROM public.user_departments ud JOIN public.departments d ON d.id=ud.department_id
    ORDER BY ud.user_id, ud.is_primary DESC, d.code;
END;
$function$;

CREATE OR REPLACE FUNCTION private.admin_set_user_department_membership_impl(
  p_user_id uuid, p_department_id uuid, p_enabled boolean
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
DECLARE
  v_primary boolean;
  v_replacement uuid;
  v_has_primary boolean;
BEGIN
  IF auth.uid() IS NULL OR (NOT private.has_permission('user.manage') AND NOT private.has_permission('role.manage')) THEN
    RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='insufficient_privilege';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id=p_user_id FOR UPDATE) THEN
    RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='user_profile_not_found';
  END IF;
  IF p_enabled AND NOT EXISTS (SELECT 1 FROM public.departments WHERE id=p_department_id AND is_active) THEN
    RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='department_not_found_or_inactive';
  END IF;
  IF NOT p_enabled AND NOT EXISTS (SELECT 1 FROM public.departments WHERE id=p_department_id) THEN
    RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='department_not_found';
  END IF;

  IF p_enabled THEN
    SELECT EXISTS (
      SELECT 1 FROM public.user_departments ud
      JOIN public.departments d ON d.id=ud.department_id AND d.is_active
      WHERE ud.user_id=p_user_id AND ud.is_primary
    ) INTO v_has_primary;
    IF NOT v_has_primary THEN
      UPDATE public.user_departments SET is_primary=false,updated_at=now()
      WHERE user_id=p_user_id AND is_primary;
    END IF;
    INSERT INTO public.user_departments(user_id,department_id,is_primary,assigned_by)
    VALUES(p_user_id,p_department_id,NOT v_has_primary,auth.uid())
    ON CONFLICT(user_id,department_id) DO UPDATE
      SET is_primary = public.user_departments.is_primary OR EXCLUDED.is_primary,
          updated_at = now();
    IF NOT v_has_primary THEN
      UPDATE public.profiles SET department_id=p_department_id,updated_at=now() WHERE id=p_user_id;
    END IF;
  ELSE
    SELECT is_primary INTO v_primary FROM public.user_departments
    WHERE user_id=p_user_id AND department_id=p_department_id FOR UPDATE;
    IF NOT FOUND THEN RETURN; END IF;
    IF EXISTS (SELECT 1 FROM public.user_department_roles WHERE user_id=p_user_id AND department_id=p_department_id) THEN
      RAISE EXCEPTION USING ERRCODE='23503', MESSAGE='remove_department_roles_before_membership';
    END IF;
    DELETE FROM public.user_departments WHERE user_id=p_user_id AND department_id=p_department_id;
    IF v_primary THEN
      SELECT ud.department_id INTO v_replacement
      FROM public.user_departments ud
      JOIN public.departments d ON d.id=ud.department_id AND d.is_active
      WHERE ud.user_id=p_user_id
      ORDER BY ud.created_at,ud.department_id LIMIT 1 FOR UPDATE OF ud;
      IF v_replacement IS NOT NULL THEN
        UPDATE public.user_departments SET is_primary=true,updated_at=now()
        WHERE user_id=p_user_id AND department_id=v_replacement;
      END IF;
      UPDATE public.profiles SET department_id=v_replacement,updated_at=now() WHERE id=p_user_id;
    END IF;
  END IF;

  INSERT INTO public.audit_logs(actor_id,action,entity_type,entity_id,new_data)
  VALUES(auth.uid(),CASE WHEN p_enabled THEN 'department_membership.added' ELSE 'department_membership.removed' END,
         'profile',p_user_id,jsonb_build_object('department_id',p_department_id,'enabled',p_enabled));
END;
$function$;

REVOKE ALL ON FUNCTION private.admin_get_user_department_memberships_impl() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION private.admin_set_user_department_membership_impl(uuid,uuid,boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.admin_get_user_department_memberships_impl() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION private.admin_set_user_department_membership_impl(uuid,uuid,boolean) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.admin_get_user_department_memberships()
RETURNS TABLE(user_id uuid, department_id uuid, department_code text, department_name text, is_primary boolean)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
  SELECT * FROM private.admin_get_user_department_memberships_impl();
$function$;

CREATE OR REPLACE FUNCTION public.admin_set_user_department_membership(
  p_user_id uuid, p_department_id uuid, p_enabled boolean
) RETURNS void
LANGUAGE sql SECURITY INVOKER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
  SELECT private.admin_set_user_department_membership_impl(p_user_id,p_department_id,p_enabled);
$function$;

REVOKE ALL ON FUNCTION public.admin_get_user_department_memberships() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_set_user_department_membership(uuid,uuid,boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_get_user_department_memberships() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_set_user_department_membership(uuid,uuid,boolean) TO authenticated, service_role;

COMMIT;
```

---

## 20261012024916 — active_department_membership_approval_guard

```sql
-- Ensure selected approvers still have active membership in the document department.
BEGIN;
CREATE OR REPLACE FUNCTION private.create_approval(
  p_document_id uuid, p_approver_id uuid, p_approval_step integer DEFAULT 1
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','public','private'
AS $function$
DECLARE
  v_id uuid; v_actor uuid:=auth.uid(); v_subject text;
  v_status public.document_status; v_department uuid;
BEGIN
  IF v_actor IS NULL THEN RAISE EXCEPTION 'permission_denied'; END IF;
  SELECT status,subject,department_id INTO v_status,v_subject,v_department
  FROM public.documents WHERE id=p_document_id FOR UPDATE;
  IF v_status IS NULL THEN RAISE EXCEPTION 'document_not_found'; END IF;
  IF v_department IS NULL OR NOT private.can_access_document(p_document_id)
     OR NOT private.has_department_permission('document.approve',v_department) THEN
    RAISE EXCEPTION 'permission_denied';
  END IF;
  IF p_approval_step < 1 THEN RAISE EXCEPTION 'invalid_approval_step'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.profiles pr
    WHERE pr.id=p_approver_id AND pr.is_active=true
      AND (
        EXISTS (SELECT 1 FROM public.user_roles ur JOIN public.roles r ON r.id=ur.role_id
                WHERE ur.user_id=pr.id AND r.code IN ('system_admin','director'))
        OR EXISTS (
          SELECT 1 FROM public.user_department_roles udr
          JOIN public.user_departments ud
            ON ud.user_id=udr.user_id AND ud.department_id=udr.department_id
          JOIN public.departments dept
            ON dept.id=ud.department_id AND dept.is_active=true
          JOIN public.department_role_permissions drp
            ON drp.department_id=udr.department_id AND drp.role_id=udr.role_id
            AND drp.enabled=true
          JOIN public.permissions p ON p.id=drp.permission_id
          WHERE udr.user_id=pr.id AND udr.department_id=v_department
            AND p.code='document.approve'
        )
      )
  ) THEN RAISE EXCEPTION 'approver_not_authorized'; END IF;
  IF v_status <> 'draft' THEN RAISE EXCEPTION 'document_not_in_draft'; END IF;
  INSERT INTO public.approvals(document_id,approval_step,approver_id,decision)
  VALUES(p_document_id,p_approval_step,p_approver_id,'pending') RETURNING id INTO v_id;
  UPDATE public.documents SET status='pending_approval' WHERE id=p_document_id;
  INSERT INTO public.notifications(recipient_id,document_id,type,title,body,priority)
  VALUES(p_approver_id,p_document_id,'approval','รอการอนุมัติ',
         'มีเอกสารรอการอนุมัติ: '||coalesce(v_subject,'ไม่ระบุเรื่อง'),'high');
  RETURN v_id;
END;
$function$;
REVOKE ALL ON FUNCTION private.create_approval(uuid,uuid,integer) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION private.create_approval(uuid,uuid,integer) TO authenticated,service_role;
COMMIT;
```

---

## 20261013001230 — include_department_scoped_permissions_in_identity

```sql
CREATE OR REPLACE FUNCTION public.get_my_permissions()
RETURNS TABLE(permission_code text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
  SELECT DISTINCT p.code::text
  FROM public.profiles pr
  JOIN public.user_roles ur ON ur.user_id = pr.id
  JOIN public.role_permissions rp ON rp.role_id = ur.role_id
  JOIN public.permissions p ON p.id = rp.permission_id
  WHERE pr.id = (SELECT auth.uid())
    AND pr.is_active = true

  UNION

  SELECT DISTINCT p.code::text
  FROM public.profiles pr
  JOIN public.user_departments ud
    ON ud.user_id = pr.id
  JOIN public.user_department_roles udr
    ON udr.user_id = ud.user_id
   AND udr.department_id = ud.department_id
  JOIN public.department_role_permissions drp
    ON drp.department_id = udr.department_id
   AND drp.role_id = udr.role_id
   AND drp.enabled = true
  JOIN public.permissions p
    ON p.id = drp.permission_id
  JOIN public.departments d
    ON d.id = ud.department_id
   AND d.is_active = true
  JOIN public.roles r
    ON r.id = udr.role_id
   AND r.code NOT IN ('system_admin', 'director')
  WHERE pr.id = (SELECT auth.uid())
    AND pr.is_active = true
  ORDER BY 1;
$function$;

REVOKE ALL ON FUNCTION public.get_my_permissions() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_permissions() TO authenticated, service_role;
```

---

## 20261014162126 — admin_global_role_management_v1

```sql
-- Dedicated management path for school-wide roles.
-- Only an active System Admin may grant or revoke global roles.
CREATE OR REPLACE FUNCTION public.admin_set_global_user_role(
  p_user_id uuid,
  p_role_id uuid,
  p_enabled boolean
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
DECLARE
  v_role_code text;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'authentication_required';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.user_roles ur
    JOIN public.roles r ON r.id = ur.role_id
    JOIN public.profiles pr ON pr.id = ur.user_id
    WHERE ur.user_id = auth.uid()
      AND r.code = 'system_admin'
      AND pr.is_active = true
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'system_admin_required_for_global_role_management';
  END IF;

  IF p_enabled IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'enabled_flag_required';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.profiles WHERE id = p_user_id AND is_active = true
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'user_profile_not_found_or_inactive';
  END IF;

  SELECT code INTO v_role_code
  FROM public.roles
  WHERE id = p_role_id;

  IF v_role_code IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'role_not_found';
  END IF;

  IF v_role_code NOT IN ('system_admin', 'director') THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'role_is_not_global';
  END IF;

  IF p_enabled THEN
    INSERT INTO public.user_roles(user_id, role_id, assigned_by)
    VALUES (p_user_id, p_role_id, auth.uid())
    ON CONFLICT (user_id, role_id) DO NOTHING;
  ELSE
    IF v_role_code = 'system_admin'
       AND EXISTS (
         SELECT 1 FROM public.user_roles
         WHERE user_id = p_user_id AND role_id = p_role_id
       )
       AND (
         SELECT count(DISTINCT ur.user_id)
         FROM public.user_roles ur
         JOIN public.roles r ON r.id = ur.role_id
         JOIN public.profiles pr ON pr.id = ur.user_id
         WHERE r.code = 'system_admin' AND pr.is_active = true
       ) <= 1 THEN
      RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'cannot_remove_last_active_system_admin';
    END IF;

    DELETE FROM public.user_roles
    WHERE user_id = p_user_id AND role_id = p_role_id;
  END IF;

  INSERT INTO public.audit_logs(actor_id, action, entity_type, entity_id, new_data)
  VALUES (
    auth.uid(),
    'global_role.' || CASE WHEN p_enabled THEN 'assigned' ELSE 'removed' END,
    'user',
    p_user_id,
    jsonb_build_object('role_code', v_role_code, 'role_id', p_role_id, 'enabled', p_enabled)
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_set_global_user_role(uuid, uuid, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_set_global_user_role(uuid, uuid, boolean) TO authenticated;
```

---

## 20261014202558 — registry_officer_delete_incoming_documents_v1

```sql
-- Allow Registry Officers to remove mistaken/duplicate incoming registrations safely.
-- Soft-delete only: preserve the document, attachments, register number and audit trail.
BEGIN;

ALTER TABLE public.documents
  ADD COLUMN IF NOT EXISTS deleted_at timestamptz,
  ADD COLUMN IF NOT EXISTS deleted_by uuid REFERENCES public.profiles(id) ON DELETE RESTRICT,
  ADD COLUMN IF NOT EXISTS deletion_reason text;

CREATE INDEX IF NOT EXISTS documents_not_deleted_idx
  ON public.documents (created_at DESC)
  WHERE deleted_at IS NULL;

CREATE OR REPLACE FUNCTION private.can_access_document(p_document_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM public.documents d
    JOIN public.profiles pr ON pr.id=(SELECT auth.uid()) AND pr.is_active=true
    WHERE d.id=p_document_id
      AND d.deleted_at IS NULL
      AND (
        EXISTS (
          SELECT 1 FROM public.user_roles ur
          JOIN public.roles r ON r.id=ur.role_id
          WHERE ur.user_id=pr.id AND r.code IN ('system_admin','director')
        )
        OR (
          d.department_id IS NOT NULL
          AND (
            (
              private.user_has_department(pr.id,d.department_id)
              AND private.has_department_permission('document.view',d.department_id)
            )
            OR EXISTS (
              SELECT 1 FROM public.user_departments ud
              JOIN public.departments child ON child.id=ud.department_id
              WHERE ud.user_id=pr.id AND child.parent_id=d.department_id
                AND private.has_department_permission('document.view',child.id)
            )
          )
        )
      )
  );
$function$;

CREATE OR REPLACE FUNCTION private.delete_incoming_document(
  p_document_id uuid,
  p_reason text
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
DECLARE
  v_actor uuid := (SELECT auth.uid());
  v_doc public.documents%ROWTYPE;
  v_can_manage boolean;
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='authentication_required';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.profiles pr
    WHERE pr.id=v_actor AND pr.is_active=true
  ) THEN
    RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='active_profile_required';
  END IF;

  IF p_reason IS NULL OR btrim(p_reason)='' OR length(btrim(p_reason))>1000 THEN
    RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='deletion_reason_required';
  END IF;

  v_can_manage := private.has_permission('registry.incoming.manage')
    OR EXISTS (
      SELECT 1 FROM public.user_roles ur
      JOIN public.roles r ON r.id=ur.role_id
      WHERE ur.user_id=v_actor AND r.code IN ('system_admin','director')
    );
  IF NOT v_can_manage THEN
    RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='incoming_delete_permission_denied';
  END IF;

  SELECT d.* INTO v_doc
  FROM public.documents d
  WHERE d.id=p_document_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE='P0002', MESSAGE='document_not_found';
  END IF;
  IF v_doc.deleted_at IS NOT NULL THEN
    RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='document_already_deleted';
  END IF;
  IF v_doc.document_type <> 'incoming' THEN
    RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='only_incoming_documents_can_be_deleted';
  END IF;
  IF v_doc.status NOT IN ('received','registered') THEN
    RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='document_already_in_workflow';
  END IF;
  IF NOT private.can_access_document(p_document_id) THEN
    RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='document_scope_denied';
  END IF;
  IF NOT EXISTS (
       SELECT 1 FROM public.user_roles ur
       JOIN public.roles r ON r.id=ur.role_id
       WHERE ur.user_id=v_actor AND r.code IN ('system_admin','director')
     )
     AND NOT private.user_has_department(v_actor,v_doc.department_id) THEN
    RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='incoming_delete_department_scope_denied';
  END IF;
  IF EXISTS (SELECT 1 FROM public.document_assignments da WHERE da.document_id=p_document_id)
     OR EXISTS (SELECT 1 FROM public.approvals a WHERE a.document_id=p_document_id) THEN
    RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='document_already_assigned_or_approved';
  END IF;

  UPDATE public.documents
  SET deleted_at=now(), deleted_by=v_actor, deletion_reason=btrim(p_reason)
  WHERE id=p_document_id;

  INSERT INTO public.audit_logs(actor_id,action,entity_type,entity_id,old_data,new_data)
  VALUES (
    v_actor,
    'delete_incoming_document',
    'documents',
    p_document_id,
    jsonb_build_object(
      'subject',v_doc.subject,
      'document_type',v_doc.document_type,
      'status',v_doc.status,
      'created_by',v_doc.created_by
    ),
    jsonb_build_object(
      'deleted_at',now(),
      'deletion_reason',btrim(p_reason),
      'soft_delete',true
    )
  );

  RETURN true;
END;
$function$;

CREATE OR REPLACE FUNCTION public.delete_incoming_document(
  p_document_id uuid,
  p_reason text
)
RETURNS boolean
LANGUAGE sql
SECURITY INVOKER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
  SELECT private.delete_incoming_document($1,$2);
$function$;

REVOKE ALL ON FUNCTION private.delete_incoming_document(uuid,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.delete_incoming_document(uuid,text) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.delete_incoming_document(uuid,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.delete_incoming_document(uuid,text) TO authenticated, service_role;

CREATE OR REPLACE VIEW public.document_report_summary
WITH (security_invoker=true) AS
SELECT document_type, status, urgency,
       count(*) AS total_documents,
       count(*) FILTER (WHERE created_at >= date_trunc('month',now())) AS current_month
FROM public.documents
WHERE deleted_at IS NULL
GROUP BY document_type,status,urgency;

CREATE OR REPLACE VIEW public.document_monthly_summary
WITH (security_invoker=true) AS
SELECT date_trunc('month',created_at)::date AS month,
       document_type,
       count(*) AS total_documents,
       count(*) FILTER (WHERE status='completed'::public.document_status) AS completed_documents,
       count(*) FILTER (WHERE urgency=ANY(ARRAY['urgent'::public.urgency_level,'very_urgent'::public.urgency_level,'critical'::public.urgency_level])) AS urgent_documents
FROM public.documents
WHERE deleted_at IS NULL
GROUP BY date_trunc('month',created_at)::date,document_type
ORDER BY date_trunc('month',created_at)::date DESC;

COMMIT;

```

---

## 20261015005425 — permanent_delete_incoming_drive_v1

```sql
-- Permanent purge for soft-deleted incoming registrations.
-- Drive objects are removed by the authenticated Edge Function before finalize is called.
CREATE OR REPLACE FUNCTION private.prepare_permanent_delete_incoming_document(
  p_document_id uuid,
  p_reason text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
DECLARE
  v_actor uuid := (SELECT auth.uid());
  v_doc public.documents%ROWTYPE;
  v_can_manage boolean;
  v_files jsonb;
BEGIN
  IF v_actor IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.profiles pr WHERE pr.id=v_actor AND pr.is_active=true
  ) THEN
    RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='active_profile_required';
  END IF;
  IF p_reason IS NULL OR length(btrim(p_reason)) < 5 OR length(btrim(p_reason)) > 1000 THEN
    RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='deletion_reason_required';
  END IF;

  v_can_manage := private.has_permission('registry.incoming.manage')
    OR EXISTS (
      SELECT 1 FROM public.user_roles ur JOIN public.roles r ON r.id=ur.role_id
      WHERE ur.user_id=v_actor AND r.code IN ('system_admin','director')
    );
  IF NOT v_can_manage THEN
    RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='incoming_delete_permission_denied';
  END IF;

  SELECT d.* INTO v_doc FROM public.documents d WHERE d.id=p_document_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0002', MESSAGE='document_not_found'; END IF;
  IF v_doc.deleted_at IS NULL THEN RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='soft_delete_required_first'; END IF;
  IF v_doc.document_type <> 'incoming' THEN RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='only_incoming_documents_can_be_purged'; END IF;
  IF v_doc.status NOT IN ('received','registered') THEN RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='document_already_in_workflow'; END IF;
  IF NOT private.can_access_document(p_document_id) THEN
    -- can_access_document excludes soft-deleted rows; authorization is checked against department membership below.
    IF NOT EXISTS (
      SELECT 1 FROM public.user_roles ur JOIN public.roles r ON r.id=ur.role_id
      WHERE ur.user_id=v_actor AND r.code IN ('system_admin','director')
    ) AND NOT private.user_has_department(v_actor,v_doc.department_id) THEN
      RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='document_scope_denied';
    END IF;
  END IF;
  IF NOT EXISTS (
       SELECT 1 FROM public.user_roles ur JOIN public.roles r ON r.id=ur.role_id
       WHERE ur.user_id=v_actor AND r.code IN ('system_admin','director')
     ) AND NOT private.user_has_department(v_actor,v_doc.department_id) THEN
    RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='incoming_delete_department_scope_denied';
  END IF;
  IF EXISTS (SELECT 1 FROM public.document_assignments WHERE document_id=p_document_id)
     OR EXISTS (SELECT 1 FROM public.approvals WHERE document_id=p_document_id) THEN
    RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='document_already_assigned_or_approved';
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'metadata_id', gd.id,
    'drive_file_id', gd.drive_file_id,
    'name', gd.name,
    'delete_drive', NOT EXISTS (
      SELECT 1 FROM public.document_files other_df
      WHERE other_df.google_drive_file_id=gd.id AND other_df.document_id<>p_document_id
    )
  ) ORDER BY gd.id), '[]'::jsonb)
  INTO v_files
  FROM public.document_files df
  JOIN public.google_drive_files gd ON gd.id=df.google_drive_file_id
  WHERE df.document_id=p_document_id;

  RETURN jsonb_build_object(
    'document_id', v_doc.id,
    'subject', v_doc.subject,
    'document_type', v_doc.document_type,
    'status', v_doc.status,
    'department_id', v_doc.department_id,
    'reason', btrim(p_reason),
    'files', v_files
  );
END;
$function$;

CREATE OR REPLACE FUNCTION private.finalize_permanent_delete_incoming_document(
  p_document_id uuid,
  p_reason text
) RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
DECLARE
  v_actor uuid := (SELECT auth.uid());
  v_doc public.documents%ROWTYPE;
  v_file_summary jsonb;
BEGIN
  IF v_actor IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.profiles pr WHERE pr.id=v_actor AND pr.is_active=true
  ) THEN
    RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='active_profile_required';
  END IF;
  IF p_reason IS NULL OR length(btrim(p_reason)) < 5 OR length(btrim(p_reason)) > 1000 THEN
    RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='deletion_reason_required';
  END IF;
  IF NOT (
    private.has_permission('registry.incoming.manage')
    OR EXISTS (SELECT 1 FROM public.user_roles ur JOIN public.roles r ON r.id=ur.role_id
               WHERE ur.user_id=v_actor AND r.code IN ('system_admin','director'))
  ) THEN
    RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='incoming_delete_permission_denied';
  END IF;

  SELECT d.* INTO v_doc FROM public.documents d WHERE d.id=p_document_id FOR UPDATE;
  IF NOT FOUND THEN
    -- Idempotent completion: already purged is treated as success.
    RETURN true;
  END IF;
  IF v_doc.deleted_at IS NULL OR v_doc.document_type <> 'incoming' OR v_doc.status NOT IN ('received','registered') THEN
    RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='document_not_eligible_for_permanent_delete';
  END IF;
  IF NOT EXISTS (
       SELECT 1 FROM public.user_roles ur JOIN public.roles r ON r.id=ur.role_id
       WHERE ur.user_id=v_actor AND r.code IN ('system_admin','director')
     ) AND NOT private.user_has_department(v_actor,v_doc.department_id) THEN
    RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='incoming_delete_department_scope_denied';
  END IF;
  IF EXISTS (SELECT 1 FROM public.document_assignments WHERE document_id=p_document_id)
     OR EXISTS (SELECT 1 FROM public.approvals WHERE document_id=p_document_id) THEN
    RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='document_already_assigned_or_approved';
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'name', gd.name,
    'drive_file_id', gd.drive_file_id,
    'shared_with_other_documents', EXISTS (
      SELECT 1 FROM public.document_files other_df
      WHERE other_df.google_drive_file_id=gd.id AND other_df.document_id<>p_document_id
    )
  )), '[]'::jsonb)
  INTO v_file_summary
  FROM public.document_files df JOIN public.google_drive_files gd ON gd.id=df.google_drive_file_id
  WHERE df.document_id=p_document_id;

  INSERT INTO public.audit_logs(actor_id,action,entity_type,entity_id,old_data,new_data)
  VALUES (
    v_actor, 'permanently_delete_incoming_document', 'documents', p_document_id,
    jsonb_build_object(
      'subject',v_doc.subject,
      'document_type',v_doc.document_type,
      'status',v_doc.status,
      'department_id',v_doc.department_id,
      'created_by',v_doc.created_by,
      'deleted_at',v_doc.deleted_at,
      'deleted_by',v_doc.deleted_by,
      'deletion_reason',v_doc.deletion_reason,
      'attachments',v_file_summary
    ),
    jsonb_build_object('permanently_deleted_at',now(),'permanent_deletion_reason',btrim(p_reason),'database_row_removed',true)
  );

  DELETE FROM public.comments WHERE document_id=p_document_id;
  DELETE FROM public.deadlines WHERE document_id=p_document_id;
  DELETE FROM public.document_assignments WHERE document_id=p_document_id;
  DELETE FROM public.approvals WHERE document_id=p_document_id;
  DELETE FROM public.notifications WHERE document_id=p_document_id;
  DELETE FROM public.document_status_history WHERE document_id=p_document_id;
  DELETE FROM public.incoming_document_details WHERE document_id=p_document_id;
  DELETE FROM public.outgoing_document_details WHERE document_id=p_document_id;
  DELETE FROM public.document_files WHERE document_id=p_document_id;
  DELETE FROM public.documents WHERE id=p_document_id;

  -- Remove only metadata no longer referenced by any remaining document.
  DELETE FROM public.google_drive_files gd
  WHERE NOT EXISTS (SELECT 1 FROM public.document_files df WHERE df.google_drive_file_id=gd.id)
    AND EXISTS (SELECT 1 FROM jsonb_array_elements(v_file_summary) f WHERE f->>'drive_file_id'=gd.drive_file_id);

  RETURN true;
END;
$function$;

CREATE OR REPLACE FUNCTION public.prepare_permanent_delete_incoming_document(p_document_id uuid, p_reason text)
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path TO 'pg_catalog','public','private'
AS $function$ SELECT private.prepare_permanent_delete_incoming_document($1,$2); $function$;

CREATE OR REPLACE FUNCTION public.finalize_permanent_delete_incoming_document(p_document_id uuid, p_reason text)
RETURNS boolean LANGUAGE sql SECURITY INVOKER SET search_path TO 'pg_catalog','public','private'
AS $function$ SELECT private.finalize_permanent_delete_incoming_document($1,$2); $function$;

REVOKE ALL ON FUNCTION private.prepare_permanent_delete_incoming_document(uuid,text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION private.finalize_permanent_delete_incoming_document(uuid,text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.prepare_permanent_delete_incoming_document(uuid,text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.finalize_permanent_delete_incoming_document(uuid,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.prepare_permanent_delete_incoming_document(uuid,text) TO authenticated;
GRANT EXECUTE ON FUNCTION private.finalize_permanent_delete_incoming_document(uuid,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.prepare_permanent_delete_incoming_document(uuid,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.finalize_permanent_delete_incoming_document(uuid,text) TO authenticated;

```

---

## 20261015005428 — list_deleted_incoming_documents_v1

```sql
-- Read-only recycle-bin listing for authorized incoming registry staff.
CREATE OR REPLACE FUNCTION public.list_deleted_incoming_documents()
RETURNS TABLE (
  id uuid,
  subject text,
  status text,
  deleted_at timestamptz,
  deletion_reason text,
  department_id uuid,
  registered_number bigint,
  external_document_no text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog','public','private'
AS $function$
DECLARE
  v_actor uuid := (SELECT auth.uid());
BEGIN
  IF v_actor IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.profiles pr WHERE pr.id=v_actor AND pr.is_active=true
  ) THEN
    RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='active_profile_required';
  END IF;
  IF NOT (
    private.has_permission('registry.incoming.manage')
    OR EXISTS (SELECT 1 FROM public.user_roles ur JOIN public.roles r ON r.id=ur.role_id
               WHERE ur.user_id=v_actor AND r.code IN ('system_admin','director'))
  ) THEN
    RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='incoming_delete_permission_denied';
  END IF;
  RETURN QUERY
  SELECT d.id,d.subject,d.status,d.deleted_at,d.deletion_reason,d.department_id,
         inc.registered_number,inc.external_document_no
  FROM public.documents d
  LEFT JOIN public.incoming_document_details inc ON inc.document_id=d.id
  WHERE d.document_type='incoming' AND d.deleted_at IS NOT NULL
    AND (
      EXISTS (SELECT 1 FROM public.user_roles ur JOIN public.roles r ON r.id=ur.role_id
              WHERE ur.user_id=v_actor AND r.code IN ('system_admin','director'))
      OR private.user_has_department(v_actor,d.department_id)
    )
  ORDER BY d.deleted_at DESC;
END;
$function$;
REVOKE ALL ON FUNCTION public.list_deleted_incoming_documents() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_deleted_incoming_documents() TO authenticated;

```

---

## 20261015023421 — fix_list_deleted_incoming_status_enum_cast

```sql
CREATE OR REPLACE FUNCTION public.list_deleted_incoming_documents()
RETURNS TABLE (
  id uuid,
  subject text,
  status text,
  deleted_at timestamptz,
  deletion_reason text,
  department_id uuid,
  registered_number bigint,
  external_document_no text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog','public','private'
AS $function$
DECLARE
  v_actor uuid := (SELECT auth.uid());
BEGIN
  IF v_actor IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.profiles pr WHERE pr.id=v_actor AND pr.is_active=true
  ) THEN
    RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='active_profile_required';
  END IF;
  IF NOT (
    private.has_permission('registry.incoming.manage')
    OR EXISTS (SELECT 1 FROM public.user_roles ur JOIN public.roles r ON r.id=ur.role_id
               WHERE ur.user_id=v_actor AND r.code IN ('system_admin','director'))
  ) THEN
    RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='incoming_delete_permission_denied';
  END IF;
  RETURN QUERY
  SELECT d.id,d.subject,d.status::text,d.deleted_at,d.deletion_reason,d.department_id,
         inc.registered_number,inc.external_document_no
  FROM public.documents d
  LEFT JOIN public.incoming_document_details inc ON inc.document_id=d.id
  WHERE d.document_type='incoming'::public.document_type AND d.deleted_at IS NOT NULL
    AND (
      EXISTS (SELECT 1 FROM public.user_roles ur JOIN public.roles r ON r.id=ur.role_id
              WHERE ur.user_id=v_actor AND r.code IN ('system_admin','director'))
      OR private.user_has_department(v_actor,d.department_id)
    )
  ORDER BY d.deleted_at DESC;
END;
$function$;
REVOKE ALL ON FUNCTION public.list_deleted_incoming_documents() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_deleted_incoming_documents() TO authenticated;
```

---

## 20261016042658 — grant_director_document_assignment

```sql

-- Allow the school Director to assign registered documents, consistently with the
-- director's global document access and the assignment workflow.
INSERT INTO public.role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM public.roles r
JOIN public.permissions p ON p.code = 'document.assign'
WHERE r.code = 'director'
  AND NOT EXISTS (
    SELECT 1 FROM public.role_permissions rp
    WHERE rp.role_id = r.id AND rp.permission_id = p.id
  );

CREATE OR REPLACE FUNCTION private.has_department_permission(
  p_permission text,
  p_department_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM public.profiles pr
    WHERE pr.id = (SELECT auth.uid())
      AND pr.is_active = true
      AND (
        (
          EXISTS (
            SELECT 1
            FROM public.user_roles ur
            JOIN public.roles wr ON wr.id = ur.role_id
            WHERE ur.user_id = (SELECT auth.uid())
              AND wr.code IN ('system_admin','director')
          )
          AND p_permission IN (
            'document.view',
            'document.create',
            'document.approve',
            'document.update',
            'document.assign'
          )
        )
        OR EXISTS (
          SELECT 1
          FROM public.user_department_roles udr
          JOIN public.user_departments ud
            ON ud.user_id = udr.user_id
           AND ud.department_id = udr.department_id
          JOIN public.roles r ON r.id = udr.role_id
          JOIN public.department_role_permissions drp
            ON drp.department_id = udr.department_id
           AND drp.role_id = udr.role_id
           AND drp.enabled = true
          JOIN public.permissions p ON p.id = drp.permission_id
          WHERE udr.user_id = pr.id
            AND udr.department_id = p_department_id
            AND p.code = p_permission
        )
      )
  );
$function$;

```

---

## 20261016043117 — deputy_director_assignment_instructions

```sql
-- Allow both Director and Deputy Director to assign documents.
-- Require assignment instructions so the assignee receives meaningful direction.
-- Include those instructions in the notification and retain them on the assignment.

INSERT INTO public.role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM public.roles r
JOIN public.permissions p ON p.code = 'document.assign'
WHERE r.code = 'deputy_director'
  AND NOT EXISTS (
    SELECT 1 FROM public.role_permissions rp
    WHERE rp.role_id = r.id AND rp.permission_id = p.id
  );

CREATE OR REPLACE FUNCTION private.has_department_permission(
  p_permission text,
  p_department_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM public.profiles pr
    WHERE pr.id = (SELECT auth.uid())
      AND pr.is_active = true
      AND (
        (
          EXISTS (
            SELECT 1
            FROM public.user_roles ur
            JOIN public.roles wr ON wr.id = ur.role_id
            WHERE ur.user_id = (SELECT auth.uid())
              AND wr.code IN ('system_admin','director')
          )
          AND p_permission IN (
            'document.view',
            'document.create',
            'document.approve',
            'document.update',
            'document.assign'
          )
        )
        OR (
          p_permission = 'document.assign'
          AND EXISTS (
            SELECT 1
            FROM public.user_roles ur
            JOIN public.roles wr ON wr.id = ur.role_id
            WHERE ur.user_id = (SELECT auth.uid())
              AND wr.code = 'deputy_director'
          )
        )
        OR EXISTS (
          SELECT 1
          FROM public.user_department_roles udr
          JOIN public.user_departments ud
            ON ud.user_id = udr.user_id
           AND ud.department_id = udr.department_id
          JOIN public.roles r ON r.id = udr.role_id
          JOIN public.department_role_permissions drp
            ON drp.department_id = udr.department_id
           AND drp.role_id = udr.role_id
           AND drp.enabled = true
          JOIN public.permissions p ON p.id = drp.permission_id
          WHERE udr.user_id = pr.id
            AND udr.department_id = p_department_id
            AND p.code = p_permission
        )
      )
  );
$function$;

CREATE OR REPLACE FUNCTION private.assign_document(
  p_document_id uuid,
  p_assignee_id uuid,
  p_instructions text DEFAULT NULL::text,
  p_due_at timestamp with time zone DEFAULT NULL::timestamp with time zone
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
DECLARE
  v_id uuid;
  v_actor uuid := auth.uid();
  v_subject text;
  v_old public.document_status;
  v_department uuid;
  v_assignee_department uuid;
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'permission_denied';
  END IF;

  IF NULLIF(btrim(p_instructions), '') IS NULL THEN
    RAISE EXCEPTION 'assignment_instructions_required';
  END IF;

  SELECT status, subject, department_id
    INTO v_old, v_subject, v_department
  FROM public.documents
  WHERE id = p_document_id
  FOR UPDATE;

  IF v_old IS NULL THEN
    RAISE EXCEPTION 'document_not_found';
  END IF;

  IF v_old <> 'registered' THEN
    RAISE EXCEPTION 'invalid_status_transition';
  END IF;

  IF v_department IS NULL
     OR NOT private.can_access_document(p_document_id)
     OR NOT private.has_department_permission('document.assign', v_department) THEN
    RAISE EXCEPTION 'document_scope_denied';
  END IF;

  IF p_due_at IS NOT NULL AND p_due_at <= now() THEN
    RAISE EXCEPTION 'deadline_must_be_future';
  END IF;

  SELECT department_id INTO v_assignee_department
  FROM public.profiles
  WHERE id = p_assignee_id AND is_active = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'assignee_not_found';
  END IF;

  IF v_assignee_department IS DISTINCT FROM v_department
     AND NOT EXISTS (
       SELECT 1 FROM public.user_departments ud
       WHERE ud.user_id = p_assignee_id AND ud.department_id = v_department
     ) THEN
    RAISE EXCEPTION 'cross_department_assignment_denied';
  END IF;

  INSERT INTO public.document_assignments(
    document_id, assignee_id, assigned_by, instructions, assignment_status
  )
  VALUES (p_document_id, p_assignee_id, v_actor, btrim(p_instructions), 'assigned')
  RETURNING id INTO v_id;

  UPDATE public.documents
  SET current_owner_id = p_assignee_id, status = 'assigned'
  WHERE id = p_document_id;

  INSERT INTO public.document_status_history(
    document_id, from_status, to_status, changed_by, reason
  )
  VALUES (p_document_id, v_old, 'assigned', v_actor, 'มอบหมายงาน');

  INSERT INTO public.notifications(
    recipient_id, document_id, type, title, body, priority
  )
  VALUES (
    p_assignee_id,
    p_document_id,
    'assignment',
    'ได้รับมอบหมายงาน',
    'คุณได้รับมอบหมายเรื่อง: ' || coalesce(v_subject, 'ไม่ระบุเรื่อง')
      || E'\nรายละเอียดจากผู้มอบหมาย: ' || btrim(p_instructions),
    'high'
  );

  IF p_due_at IS NOT NULL THEN
    INSERT INTO public.deadlines(
      document_id, assigned_to, due_at, reminder_at, escalation_at, status
    )
    VALUES (
      p_document_id, p_assignee_id, p_due_at,
      p_due_at - interval '24 hours', p_due_at, 'open'
    );
  END IF;

  RETURN v_id;
END;
$function$;

```

---

## 20261016043917 — list_document_assignees_scoped_rpc

```sql
CREATE OR REPLACE FUNCTION public.list_document_assignees(p_document_id uuid)
RETURNS TABLE(id uuid, full_name text, employee_code text)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
DECLARE
  v_department_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'permission_denied';
  END IF;

  SELECT d.department_id
    INTO v_department_id
  FROM public.documents d
  WHERE d.id = p_document_id
    AND d.deleted_at IS NULL
    AND d.status = 'registered';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'document_not_assignable';
  END IF;

  IF NOT private.can_access_document(p_document_id)
     OR NOT private.has_department_permission('document.assign', v_department_id) THEN
    RAISE EXCEPTION 'document_scope_denied';
  END IF;

  RETURN QUERY
  SELECT DISTINCT pr.id, pr.full_name, pr.employee_code
  FROM public.profiles pr
  WHERE pr.is_active = true
    AND (
      pr.department_id = v_department_id
      OR EXISTS (
        SELECT 1
        FROM public.user_departments ud
        WHERE ud.user_id = pr.id
          AND ud.department_id = v_department_id
      )
    )
  ORDER BY pr.full_name;
END;
$function$;

REVOKE ALL ON FUNCTION public.list_document_assignees(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_document_assignees(uuid) TO authenticated;
```

---

## 20261016043936 — expand_document_assignee_lookup_for_approvals

```sql
CREATE OR REPLACE FUNCTION public.list_document_assignees(p_document_id uuid)
RETURNS TABLE(id uuid, full_name text, employee_code text)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
DECLARE
  v_department_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'permission_denied';
  END IF;

  SELECT d.department_id
    INTO v_department_id
  FROM public.documents d
  WHERE d.id = p_document_id
    AND d.deleted_at IS NULL;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'document_not_found';
  END IF;

  IF NOT private.can_access_document(p_document_id)
     OR NOT (
       private.has_department_permission('document.assign', v_department_id)
       OR private.has_department_permission('document.approve', v_department_id)
     ) THEN
    RAISE EXCEPTION 'document_scope_denied';
  END IF;

  RETURN QUERY
  SELECT DISTINCT pr.id, pr.full_name, pr.employee_code
  FROM public.profiles pr
  WHERE pr.is_active = true
    AND (
      pr.department_id = v_department_id
      OR EXISTS (
        SELECT 1
        FROM public.user_departments ud
        WHERE ud.user_id = pr.id
          AND ud.department_id = v_department_id
      )
    )
  ORDER BY pr.full_name;
END;
$function$;

REVOKE ALL ON FUNCTION public.list_document_assignees(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_document_assignees(uuid) TO authenticated;
```

---

## 20261016044811 — expand_assignees_to_child_departments

```sql
CREATE OR REPLACE FUNCTION public.list_document_assignees(p_document_id uuid)
RETURNS TABLE(id uuid, full_name text, employee_code text)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
DECLARE
  v_department_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'permission_denied';
  END IF;

  SELECT d.department_id
    INTO v_department_id
  FROM public.documents d
  WHERE d.id = p_document_id
    AND d.deleted_at IS NULL;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'document_not_found';
  END IF;

  IF NOT private.can_access_document(p_document_id)
     OR NOT (
       private.has_department_permission('document.assign', v_department_id)
       OR private.has_department_permission('document.approve', v_department_id)
     ) THEN
    RAISE EXCEPTION 'document_scope_denied';
  END IF;

  RETURN QUERY
  WITH RECURSIVE eligible_departments(id) AS (
    SELECT dep.id
    FROM public.departments dep
    WHERE dep.id = v_department_id
      AND dep.is_active = true
    UNION
    SELECT child.id
    FROM public.departments child
    JOIN eligible_departments parent ON child.parent_id = parent.id
    WHERE child.is_active = true
  )
  SELECT DISTINCT pr.id, pr.full_name, pr.employee_code
  FROM public.profiles pr
  WHERE pr.is_active = true
    AND (
      pr.department_id IN (SELECT ed.id FROM eligible_departments ed)
      OR EXISTS (
        SELECT 1
        FROM public.user_departments ud
        WHERE ud.user_id = pr.id
          AND ud.department_id IN (SELECT ed.id FROM eligible_departments ed)
      )
    )
  ORDER BY pr.full_name;
END;
$function$;

REVOKE ALL ON FUNCTION public.list_document_assignees(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_document_assignees(uuid) TO authenticated;
```

---

## 20261016152237 — assign_document_to_multiple_staff

```sql
-- Allow one assignment action to target multiple eligible staff atomically.
CREATE OR REPLACE FUNCTION public.assign_document_many(
  p_document_id uuid,
  p_assignee_ids uuid[],
  p_instructions text,
  p_due_at timestamptz DEFAULT NULL
)
RETURNS uuid[]
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
DECLARE
  v_actor uuid := auth.uid();
  v_subject text;
  v_old public.document_status;
  v_department uuid;
  v_assignee uuid;
  v_assignment_id uuid;
  v_ids uuid[] := ARRAY[]::uuid[];
  v_unique_ids uuid[];
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'permission_denied';
  END IF;

  IF NULLIF(btrim(p_instructions), '') IS NULL THEN
    RAISE EXCEPTION 'assignment_instructions_required';
  END IF;

  SELECT array_agg(x ORDER BY x)
    INTO v_unique_ids
  FROM (SELECT DISTINCT unnest(coalesce(p_assignee_ids, ARRAY[]::uuid[])) AS x) s;

  IF coalesce(array_length(v_unique_ids, 1), 0) = 0 THEN
    RAISE EXCEPTION 'assignee_required';
  END IF;

  SELECT status, subject, department_id
    INTO v_old, v_subject, v_department
  FROM public.documents
  WHERE id = p_document_id AND deleted_at IS NULL
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'document_not_found';
  END IF;

  IF v_old <> 'registered' THEN
    RAISE EXCEPTION 'invalid_status_transition';
  END IF;

  IF v_department IS NULL
     OR NOT private.can_access_document(p_document_id)
     OR NOT private.has_department_permission('document.assign', v_department) THEN
    RAISE EXCEPTION 'document_scope_denied';
  END IF;

  IF p_due_at IS NOT NULL AND p_due_at <= now() THEN
    RAISE EXCEPTION 'deadline_must_be_future';
  END IF;

  -- Validate every selected person before writing anything.
  FOREACH v_assignee IN ARRAY v_unique_ids LOOP
    IF NOT EXISTS (
      SELECT 1 FROM public.profiles pr
      WHERE pr.id = v_assignee AND pr.is_active = true
        AND (
          pr.department_id IN (
            WITH RECURSIVE eligible_departments(id) AS (
              SELECT dep.id FROM public.departments dep
              WHERE dep.id = v_department AND dep.is_active = true
              UNION
              SELECT child.id FROM public.departments child
              JOIN eligible_departments parent ON child.parent_id = parent.id
              WHERE child.is_active = true
            ) SELECT id FROM eligible_departments
          )
          OR EXISTS (
            SELECT 1 FROM public.user_departments ud
            WHERE ud.user_id = pr.id
              AND ud.department_id IN (
                WITH RECURSIVE eligible_departments(id) AS (
                  SELECT dep.id FROM public.departments dep
                  WHERE dep.id = v_department AND dep.is_active = true
                  UNION
                  SELECT child.id FROM public.departments child
                  JOIN eligible_departments parent ON child.parent_id = parent.id
                  WHERE child.is_active = true
                ) SELECT id FROM eligible_departments
              )
          )
        )
    ) THEN
      RAISE EXCEPTION 'assignee_not_in_document_scope';
    END IF;
  END LOOP;

  FOREACH v_assignee IN ARRAY v_unique_ids LOOP
    INSERT INTO public.document_assignments(
      document_id, assignee_id, assigned_by, instructions, assignment_status
    ) VALUES (
      p_document_id, v_assignee, v_actor, btrim(p_instructions), 'assigned'
    ) RETURNING id INTO v_assignment_id;

    v_ids := array_append(v_ids, v_assignment_id);

    INSERT INTO public.notifications(
      recipient_id, document_id, type, title, body, priority
    ) VALUES (
      v_assignee, p_document_id, 'assignment', 'ได้รับมอบหมายงาน',
      'คุณได้รับมอบหมายเรื่อง: ' || coalesce(v_subject, 'ไม่ระบุเรื่อง')
        || E'\nรายละเอียดจากผู้มอบหมาย: ' || btrim(p_instructions),
      'high'
    );

    IF p_due_at IS NOT NULL THEN
      INSERT INTO public.deadlines(
        document_id, assigned_to, due_at, reminder_at, escalation_at, status
      ) VALUES (
        p_document_id, v_assignee, p_due_at,
        p_due_at - interval '24 hours', p_due_at, 'open'
      );
    END IF;
  END LOOP;

  UPDATE public.documents
  SET current_owner_id = v_unique_ids[1], status = 'assigned'
  WHERE id = p_document_id;

  INSERT INTO public.document_status_history(
    document_id, from_status, to_status, changed_by, reason
  ) VALUES (
    p_document_id, v_old, 'assigned', v_actor,
    'มอบหมายงานให้ ' || array_length(v_unique_ids, 1)::text || ' คน'
  );

  RETURN v_ids;
END;
$function$;

REVOKE ALL ON FUNCTION public.assign_document_many(uuid, uuid[], text, timestamptz) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.assign_document_many(uuid, uuid[], text, timestamptz) TO authenticated;

```

---

## 20261016161349 — notify_director_and_deputy_on_incoming_registration

```sql
CREATE OR REPLACE FUNCTION private.notify_leadership_on_incoming_registration()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
DECLARE
  v_subject text;
  v_registered_number text;
BEGIN
  SELECT d.subject, id.registered_number::text
    INTO v_subject, v_registered_number
  FROM public.documents d
  LEFT JOIN public.incoming_document_details id ON id.document_id = d.id
  WHERE d.id = NEW.document_id
    AND d.document_type = 'incoming';

  IF NOT FOUND THEN
    RETURN NEW;
  END IF;

  INSERT INTO public.notifications
    (recipient_id, document_id, type, title, body, priority)
  SELECT DISTINCT pr.id,
         NEW.document_id,
         'incoming_registered',
         'มีหนังสือรับลงทะเบียนใหม่',
         'เรื่อง: ' || coalesce(v_subject, 'ไม่ระบุเรื่อง')
           || CASE WHEN v_registered_number IS NOT NULL
                   THEN E'\nเลขทะเบียน: ' || v_registered_number ELSE '' END,
         'high'
  FROM public.profiles pr
  WHERE pr.is_active = true
    AND (
      EXISTS (
        SELECT 1
        FROM public.user_roles ur
        JOIN public.roles r ON r.id = ur.role_id
        WHERE ur.user_id = pr.id
          AND r.code IN ('director', 'deputy_director')
      )
      OR EXISTS (
        SELECT 1
        FROM public.user_department_roles udr
        JOIN public.roles r ON r.id = udr.role_id
        WHERE udr.user_id = pr.id
          AND r.code IN ('director', 'deputy_director')
      )
    );

  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_notify_leadership_on_incoming_registration
  ON public.incoming_document_details;

CREATE TRIGGER trg_notify_leadership_on_incoming_registration
AFTER INSERT ON public.incoming_document_details
FOR EACH ROW
EXECUTE FUNCTION private.notify_leadership_on_incoming_registration();

REVOKE ALL ON FUNCTION private.notify_leadership_on_incoming_registration() FROM PUBLIC, anon, authenticated;
```

---

## 20261016162544 — restrict_sender_directory_management_to_admin_and_registry

```sql
DROP POLICY IF EXISTS senders_manage_registry ON public.senders;

CREATE POLICY senders_insert_admin_registry
ON public.senders
FOR INSERT
TO authenticated
WITH CHECK (
  EXISTS (
    SELECT 1 FROM public.user_roles ur
    JOIN public.roles r ON r.id = ur.role_id
    WHERE ur.user_id = (SELECT auth.uid())
      AND r.code IN ('system_admin', 'school_admin', 'registry_officer')
  )
  OR EXISTS (
    SELECT 1 FROM public.user_department_roles udr
    JOIN public.roles r ON r.id = udr.role_id
    WHERE udr.user_id = (SELECT auth.uid())
      AND r.code IN ('system_admin', 'school_admin', 'registry_officer')
  )
);

CREATE POLICY senders_update_admin_registry
ON public.senders
FOR UPDATE
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.user_roles ur
    JOIN public.roles r ON r.id = ur.role_id
    WHERE ur.user_id = (SELECT auth.uid())
      AND r.code IN ('system_admin', 'school_admin', 'registry_officer')
  )
  OR EXISTS (
    SELECT 1 FROM public.user_department_roles udr
    JOIN public.roles r ON r.id = udr.role_id
    WHERE udr.user_id = (SELECT auth.uid())
      AND r.code IN ('system_admin', 'school_admin', 'registry_officer')
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1 FROM public.user_roles ur
    JOIN public.roles r ON r.id = ur.role_id
    WHERE ur.user_id = (SELECT auth.uid())
      AND r.code IN ('system_admin', 'school_admin', 'registry_officer')
  )
  OR EXISTS (
    SELECT 1 FROM public.user_department_roles udr
    JOIN public.roles r ON r.id = udr.role_id
    WHERE udr.user_id = (SELECT auth.uid())
      AND r.code IN ('system_admin', 'school_admin', 'registry_officer')
  )
);

CREATE POLICY senders_delete_admin_registry
ON public.senders
FOR DELETE
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.user_roles ur
    JOIN public.roles r ON r.id = ur.role_id
    WHERE ur.user_id = (SELECT auth.uid())
      AND r.code IN ('system_admin', 'school_admin', 'registry_officer')
  )
  OR EXISTS (
    SELECT 1 FROM public.user_department_roles udr
    JOIN public.roles r ON r.id = udr.role_id
    WHERE udr.user_id = (SELECT auth.uid())
      AND r.code IN ('system_admin', 'school_admin', 'registry_officer')
  )
);
```

---

## 20261016163640 — allow_document_readers_to_view_assignees

```sql
CREATE OR REPLACE FUNCTION public.list_document_assignees(p_document_id uuid)
RETURNS TABLE(id uuid, full_name text, employee_code text)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
DECLARE
  v_department_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'permission_denied';
  END IF;

  SELECT d.department_id
    INTO v_department_id
  FROM public.documents d
  WHERE d.id = p_document_id
    AND d.deleted_at IS NULL;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'document_not_found';
  END IF;

  -- Document visibility is the authorization boundary. Readers who can
  -- access the document may see its assigned-user list; they do not gain
  -- assignment or approval privileges from this read operation.
  IF NOT private.can_access_document(p_document_id) THEN
    RAISE EXCEPTION 'document_scope_denied';
  END IF;

  RETURN QUERY
  WITH RECURSIVE eligible_departments(id) AS (
    SELECT dep.id
    FROM public.departments dep
    WHERE dep.id = v_department_id
      AND dep.is_active = true
    UNION
    SELECT child.id
    FROM public.departments child
    JOIN eligible_departments parent ON child.parent_id = parent.id
    WHERE child.is_active = true
  )
  SELECT DISTINCT pr.id, pr.full_name, pr.employee_code
  FROM public.profiles pr
  WHERE pr.is_active = true
    AND (
      pr.department_id IN (SELECT ed.id FROM eligible_departments ed)
      OR EXISTS (
        SELECT 1
        FROM public.user_departments ud
        WHERE ud.user_id = pr.id
          AND ud.department_id IN (SELECT ed.id FROM eligible_departments ed)
      )
    )
  ORDER BY pr.full_name;
END;
$function$;
```

---

## 20261016170925 — document_assignment_reports_v1

```sql
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
    select 1
    from public.document_assignments a
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
    select 1
    from public.document_assignments a
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
    select 1
    from public.document_assignments a
    join public.documents d on d.id = a.document_id
    where a.id = document_assignment_reports.assignment_id
      and a.assignee_id = (select auth.uid())
      and private.can_access_document(d.id)
  )
)
with check (
  created_by = (select auth.uid())
  and exists (
    select 1
    from public.document_assignments a
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

```

---

## 20261017065302 — allow_assignees_to_read_assigned_documents

```sql
CREATE OR REPLACE FUNCTION private.can_access_document(p_document_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM public.documents d
    JOIN public.profiles pr ON pr.id = (SELECT auth.uid()) AND pr.is_active = true
    WHERE d.id = p_document_id
      AND d.deleted_at IS NULL
      AND (
        EXISTS (
          SELECT 1
          FROM public.user_roles ur
          JOIN public.roles r ON r.id = ur.role_id
          WHERE ur.user_id = pr.id
            AND r.code IN ('system_admin', 'director')
        )
        OR EXISTS (
          SELECT 1
          FROM public.document_assignments da
          WHERE da.document_id = d.id
            AND da.assignee_id = pr.id
        )
        OR (
          d.department_id IS NOT NULL
          AND (
            (
              private.user_has_department(pr.id, d.department_id)
              AND private.has_department_permission('document.view', d.department_id)
            )
            OR EXISTS (
              SELECT 1
              FROM public.user_departments ud
              JOIN public.departments child ON child.id = ud.department_id
              WHERE ud.user_id = pr.id
                AND child.parent_id = d.department_id
                AND private.has_department_permission('document.view', child.id)
            )
          )
        )
      )
  );
$function$;
```

---

## 20261017065850 — allow_assignees_to_start_assigned_documents

```sql
CREATE OR REPLACE FUNCTION private.update_document_status(
  p_document_id uuid,
  p_to_status public.document_status,
  p_reason text DEFAULT NULL::text
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
DECLARE
  v_actor uuid := auth.uid();
  v_from public.document_status;
  v_department uuid;
  v_permission text;
  v_is_assignee boolean := false;
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'permission_denied';
  END IF;

  SELECT status, department_id
    INTO v_from, v_department
    FROM public.documents
   WHERE id = p_document_id
   FOR UPDATE;

  IF v_from IS NULL THEN
    RAISE EXCEPTION 'document_not_found';
  END IF;

  IF NOT private.can_access_document(p_document_id) THEN
    RAISE EXCEPTION 'document_scope_denied';
  END IF;

  IF v_from = p_to_status THEN
    RETURN true;
  END IF;

  IF p_to_status IN ('pending_approval', 'approved', 'assigned')
     OR (v_from = 'pending_approval' AND p_to_status = 'draft') THEN
    RAISE EXCEPTION 'use_dedicated_workflow_rpc';
  END IF;

  -- The person assigned this document may start work on it, without being
  -- granted broad document.update permission for the whole department.
  IF v_from = 'assigned' AND p_to_status = 'in_progress' THEN
    SELECT EXISTS (
      SELECT 1
        FROM public.document_assignments da
       WHERE da.document_id = p_document_id
         AND da.assignee_id = v_actor
    ) INTO v_is_assignee;
  END IF;

  v_permission := CASE
    WHEN p_to_status = 'completed' THEN 'document.complete'
    WHEN p_to_status = 'archived' THEN 'document.archive'
    ELSE 'document.update'
  END;

  IF NOT v_is_assignee
     AND (v_department IS NULL OR NOT private.has_department_permission(v_permission, v_department)) THEN
    RAISE EXCEPTION 'permission_denied';
  END IF;

  IF NOT private.is_valid_document_transition(p_document_id, v_from, p_to_status) THEN
    RAISE EXCEPTION 'invalid_status_transition';
  END IF;

  UPDATE public.documents
     SET status = p_to_status
   WHERE id = p_document_id;

  INSERT INTO public.document_status_history(document_id, from_status, to_status, changed_by, reason)
  VALUES (p_document_id, v_from, p_to_status, v_actor, p_reason);

  IF p_to_status IN ('completed', 'archived') THEN
    UPDATE public.deadlines
       SET status = 'completed',
           completed_at = coalesce(completed_at, now())
     WHERE document_id = p_document_id
       AND status = 'open';
  END IF;

  RETURN true;
END;
$function$;

REVOKE ALL ON FUNCTION private.update_document_status(uuid, public.document_status, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION private.update_document_status(uuid, public.document_status, text) TO authenticated;
```

---

## 20261017070421 — allow_assignees_to_complete_active_assignments

```sql
CREATE OR REPLACE FUNCTION private.update_document_status(
  p_document_id uuid,
  p_to_status public.document_status,
  p_reason text DEFAULT NULL::text
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
DECLARE
  v_actor uuid := auth.uid();
  v_from public.document_status;
  v_department uuid;
  v_permission text;
  v_is_assignee boolean := false;
BEGIN
  IF v_actor IS NULL THEN RAISE EXCEPTION 'permission_denied'; END IF;

  SELECT status, department_id INTO v_from, v_department
  FROM public.documents WHERE id = p_document_id FOR UPDATE;

  IF v_from IS NULL THEN RAISE EXCEPTION 'document_not_found'; END IF;
  IF NOT private.can_access_document(p_document_id) THEN RAISE EXCEPTION 'document_scope_denied'; END IF;
  IF v_from = p_to_status THEN RETURN true; END IF;

  IF p_to_status IN ('pending_approval', 'approved', 'assigned')
     OR (v_from = 'pending_approval' AND p_to_status = 'draft') THEN
    RAISE EXCEPTION 'use_dedicated_workflow_rpc';
  END IF;

  -- Assignees may start their assigned work and complete it when the assignment is active.
  IF (v_from = 'assigned' AND p_to_status = 'in_progress')
     OR (v_from = 'in_progress' AND p_to_status = 'completed') THEN
    SELECT EXISTS (
      SELECT 1
      FROM public.document_assignments da
      WHERE da.document_id = p_document_id
        AND da.assignee_id = v_actor
        AND (
          (v_from = 'assigned' AND p_to_status = 'in_progress')
          OR (da.assignment_status = 'active' AND v_from = 'in_progress' AND p_to_status = 'completed')
        )
    ) INTO v_is_assignee;
  END IF;

  v_permission := CASE
    WHEN p_to_status = 'completed' THEN 'document.complete'
    WHEN p_to_status = 'archived' THEN 'document.archive'
    ELSE 'document.update'
  END;

  IF NOT v_is_assignee
     AND (v_department IS NULL OR NOT private.has_department_permission(v_permission, v_department)) THEN
    RAISE EXCEPTION 'permission_denied';
  END IF;

  IF NOT private.is_valid_document_transition(p_document_id, v_from, p_to_status) THEN
    RAISE EXCEPTION 'invalid_status_transition';
  END IF;

  UPDATE public.documents SET status = p_to_status WHERE id = p_document_id;
  INSERT INTO public.document_status_history(document_id, from_status, to_status, changed_by, reason)
  VALUES (p_document_id, v_from, p_to_status, v_actor, p_reason);

  IF p_to_status IN ('completed', 'archived') THEN
    UPDATE public.deadlines
    SET status = 'completed', completed_at = coalesce(completed_at, now())
    WHERE document_id = p_document_id AND status = 'open';
  END IF;
  RETURN true;
END;
$function$;

REVOKE ALL ON FUNCTION private.update_document_status(uuid, public.document_status, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION private.update_document_status(uuid, public.document_status, text) TO authenticated;
```

---

## 20261017070749 — fix_assignment_status_enum_check_for_completion

```sql
CREATE OR REPLACE FUNCTION private.update_document_status(
  p_document_id uuid,
  p_to_status public.document_status,
  p_reason text DEFAULT NULL::text
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
DECLARE
  v_actor uuid := auth.uid();
  v_from public.document_status;
  v_department uuid;
  v_permission text;
  v_is_assignee boolean := false;
BEGIN
  IF v_actor IS NULL THEN RAISE EXCEPTION 'permission_denied'; END IF;

  SELECT status, department_id INTO v_from, v_department
  FROM public.documents WHERE id = p_document_id FOR UPDATE;

  IF v_from IS NULL THEN RAISE EXCEPTION 'document_not_found'; END IF;
  IF NOT private.can_access_document(p_document_id) THEN RAISE EXCEPTION 'document_scope_denied'; END IF;
  IF v_from = p_to_status THEN RETURN true; END IF;

  IF p_to_status IN ('pending_approval', 'approved', 'assigned')
     OR (v_from = 'pending_approval' AND p_to_status = 'draft') THEN
    RAISE EXCEPTION 'use_dedicated_workflow_rpc';
  END IF;

  -- Assignees may start assigned work and complete it while their assignment
  -- is in any non-terminal status supported by the assignment_status enum.
  IF (v_from = 'assigned' AND p_to_status = 'in_progress')
     OR (v_from = 'in_progress' AND p_to_status = 'completed') THEN
    SELECT EXISTS (
      SELECT 1
      FROM public.document_assignments da
      WHERE da.document_id = p_document_id
        AND da.assignee_id = v_actor
        AND (
          (v_from = 'assigned' AND p_to_status = 'in_progress'
            AND da.assignment_status IN ('assigned', 'accepted', 'in_progress'))
          OR
          (v_from = 'in_progress' AND p_to_status = 'completed'
            AND da.assignment_status IN ('assigned', 'accepted', 'in_progress'))
        )
    ) INTO v_is_assignee;
  END IF;

  v_permission := CASE
    WHEN p_to_status = 'completed' THEN 'document.complete'
    WHEN p_to_status = 'archived' THEN 'document.archive'
    ELSE 'document.update'
  END;

  IF NOT v_is_assignee
     AND (v_department IS NULL OR NOT private.has_department_permission(v_permission, v_department)) THEN
    RAISE EXCEPTION 'permission_denied';
  END IF;

  IF NOT private.is_valid_document_transition(p_document_id, v_from, p_to_status) THEN
    RAISE EXCEPTION 'invalid_status_transition';
  END IF;

  UPDATE public.documents SET status = p_to_status WHERE id = p_document_id;
  INSERT INTO public.document_status_history(document_id, from_status, to_status, changed_by, reason)
  VALUES (p_document_id, v_from, p_to_status, v_actor, p_reason);

  IF p_to_status IN ('completed', 'archived') THEN
    UPDATE public.deadlines
    SET status = 'completed', completed_at = coalesce(completed_at, now())
    WHERE document_id = p_document_id AND status = 'open';
  END IF;
  RETURN true;
END;
$function$;

REVOKE ALL ON FUNCTION private.update_document_status(uuid, public.document_status, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION private.update_document_status(uuid, public.document_status, text) TO authenticated;
```

---

## 20261017071219 — sync_assignment_when_assignee_completes_document

```sql
CREATE OR REPLACE FUNCTION private.update_document_status(
  p_document_id uuid,
  p_to_status public.document_status,
  p_reason text DEFAULT NULL::text
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
DECLARE
  v_actor uuid := auth.uid();
  v_from public.document_status;
  v_department uuid;
  v_permission text;
  v_is_assignee boolean := false;
BEGIN
  IF v_actor IS NULL THEN RAISE EXCEPTION 'permission_denied'; END IF;

  SELECT status, department_id INTO v_from, v_department
  FROM public.documents WHERE id = p_document_id FOR UPDATE;

  IF v_from IS NULL THEN RAISE EXCEPTION 'document_not_found'; END IF;
  IF NOT private.can_access_document(p_document_id) THEN RAISE EXCEPTION 'document_scope_denied'; END IF;
  IF v_from = p_to_status THEN RETURN true; END IF;

  IF p_to_status IN ('pending_approval', 'approved', 'assigned')
     OR (v_from = 'pending_approval' AND p_to_status = 'draft') THEN
    RAISE EXCEPTION 'use_dedicated_workflow_rpc';
  END IF;

  IF (v_from = 'assigned' AND p_to_status = 'in_progress')
     OR (v_from = 'in_progress' AND p_to_status = 'completed') THEN
    SELECT EXISTS (
      SELECT 1
      FROM public.document_assignments da
      WHERE da.document_id = p_document_id
        AND da.assignee_id = v_actor
        AND da.assignment_status IN ('assigned', 'accepted', 'in_progress')
    ) INTO v_is_assignee;
  END IF;

  v_permission := CASE
    WHEN p_to_status = 'completed' THEN 'document.complete'
    WHEN p_to_status = 'archived' THEN 'document.archive'
    ELSE 'document.update'
  END;

  IF NOT v_is_assignee
     AND (v_department IS NULL OR NOT private.has_department_permission(v_permission, v_department)) THEN
    RAISE EXCEPTION 'permission_denied';
  END IF;

  IF NOT private.is_valid_document_transition(p_document_id, v_from, p_to_status) THEN
    RAISE EXCEPTION 'invalid_status_transition';
  END IF;

  UPDATE public.documents SET status = p_to_status WHERE id = p_document_id;

  -- When an assigned staff member completes the document workflow, close that
  -- staff member's active assignment as well so it moves to the Done task view.
  IF p_to_status = 'completed' THEN
    UPDATE public.document_assignments
    SET assignment_status = 'completed',
        completed_at = coalesce(completed_at, now())
    WHERE document_id = p_document_id
      AND assignee_id = v_actor
      AND assignment_status IN ('assigned', 'accepted', 'in_progress');
  END IF;

  INSERT INTO public.document_status_history(document_id, from_status, to_status, changed_by, reason)
  VALUES (p_document_id, v_from, p_to_status, v_actor, p_reason);

  IF p_to_status IN ('completed', 'archived') THEN
    UPDATE public.deadlines
    SET status = 'completed', completed_at = coalesce(completed_at, now())
    WHERE document_id = p_document_id AND status = 'open';
  END IF;
  RETURN true;
END;
$function$;

REVOKE ALL ON FUNCTION private.update_document_status(uuid, public.document_status, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION private.update_document_status(uuid, public.document_status, text) TO authenticated;
```

---

## 20261017071238 — reconcile_assignments_for_completed_documents

```sql
UPDATE public.document_assignments da
SET assignment_status = 'completed',
    completed_at = coalesce(da.completed_at, now())
FROM public.documents d
WHERE d.id = da.document_id
  AND d.status = 'completed'
  AND da.assignment_status IN ('assigned', 'accepted', 'in_progress');
```

---

## 20261017073307 — add_admin_system_settings

```sql

create table if not exists public.system_settings (
  setting_key text primary key,
  setting_value text not null,
  updated_by uuid references public.profiles(id) on delete set null,
  updated_at timestamptz not null default now()
);
alter table public.system_settings enable row level security;
revoke all on public.system_settings from anon, authenticated;
insert into public.system_settings(setting_key, setting_value)
values ('school_name', 'โรงเรียนวัดบึงน้ำใส')
on conflict (setting_key) do nothing;

create or replace function public.admin_get_system_settings()
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_uid uuid := auth.uid();
  v_school text;
  v_register_id uuid;
  v_year integer;
  v_current bigint;
begin
  if v_uid is null or not exists (
    select 1 from public.user_roles ur
    join public.roles r on r.id = ur.role_id
    where ur.user_id = v_uid and r.code = 'system_admin'
  ) then
    raise exception using errcode = '42501', message = 'system_admin_required';
  end if;

  select setting_value into v_school from public.system_settings where setting_key = 'school_name';
  select id, document_year into v_register_id, v_year
  from public.document_registers
  where direction = 'incoming' and is_active = true
  order by document_year desc, created_at desc limit 1;
  if v_register_id is not null then
    select current_number into v_current from public.number_sequences
    where register_id = v_register_id and year = v_year;
  end if;
  return jsonb_build_object(
    'school_name', coalesce(v_school, 'โรงเรียนวัดบึงน้ำใส'),
    'incoming_register_year', v_year,
    'incoming_next_number', coalesce(v_current, 0) + 1
  );
end;
$$;

create or replace function public.admin_save_system_settings(
  p_school_name text,
  p_incoming_next_number bigint
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_uid uuid := auth.uid();
  v_register_id uuid;
  v_year integer;
  v_current bigint;
  v_max_registered bigint;
  v_min_next bigint;
  v_old_school text;
begin
  if v_uid is null or not exists (
    select 1 from public.user_roles ur
    join public.roles r on r.id = ur.role_id
    where ur.user_id = v_uid and r.code = 'system_admin'
  ) then
    raise exception using errcode = '42501', message = 'system_admin_required';
  end if;
  if p_school_name is null or length(btrim(p_school_name)) < 3 or length(btrim(p_school_name)) > 200 then
    raise exception using errcode = '22023', message = 'school_name_must_be_3_to_200_chars';
  end if;
  if p_incoming_next_number is null or p_incoming_next_number < 1 then
    raise exception using errcode = '22023', message = 'incoming_number_must_be_positive';
  end if;

  select setting_value into v_old_school from public.system_settings where setting_key = 'school_name';
  insert into public.system_settings(setting_key, setting_value, updated_by, updated_at)
  values ('school_name', btrim(p_school_name), v_uid, now())
  on conflict (setting_key) do update
    set setting_value = excluded.setting_value, updated_by = excluded.updated_by, updated_at = now();

  select id, document_year into v_register_id, v_year
  from public.document_registers
  where direction = 'incoming' and is_active = true
  order by document_year desc, created_at desc limit 1;
  if v_register_id is null then
    raise exception using errcode = 'P0001', message = 'active_incoming_register_not_found';
  end if;

  insert into public.number_sequences(register_id, year, current_number)
  values (v_register_id, v_year, 0)
  on conflict (register_id, year) do nothing;

  select current_number into v_current from public.number_sequences
  where register_id = v_register_id and year = v_year
  for update;

  select coalesce(max(i.registered_number), 0) into v_max_registered
  from public.incoming_document_details i
  join public.documents d on d.id = i.document_id
  where d.register_id = v_register_id;

  v_min_next := greatest(coalesce(v_current, 0) + 1, v_max_registered + 1);
  if p_incoming_next_number < v_min_next then
    raise exception using errcode = '22023', message = 'incoming_number_cannot_move_backwards';
  end if;

  update public.number_sequences
  set current_number = p_incoming_next_number - 1, updated_at = now()
  where register_id = v_register_id and year = v_year;

  insert into public.audit_logs(actor_id, action, entity_type, old_data, new_data)
  values (v_uid, 'update_system_settings', 'system_settings',
    jsonb_build_object('school_name', v_old_school),
    jsonb_build_object('school_name', btrim(p_school_name), 'incoming_next_number', p_incoming_next_number, 'incoming_register_year', v_year));

  return jsonb_build_object('ok', true, 'school_name', btrim(p_school_name),
    'incoming_register_year', v_year, 'incoming_next_number', p_incoming_next_number);
end;
$$;

revoke all on function public.admin_get_system_settings() from public, anon;
revoke all on function public.admin_save_system_settings(text, bigint) from public, anon;
grant execute on function public.admin_get_system_settings() to authenticated;
grant execute on function public.admin_save_system_settings(text, bigint) to authenticated;

```

---

## 20261017073424 — add_public_school_name_reader

```sql
create or replace function public.get_public_school_name()
returns text
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select coalesce((select setting_value from public.system_settings where setting_key = 'school_name'), 'โรงเรียนวัดบึงน้ำใส');
$$;
revoke all on function public.get_public_school_name() from public;
grant execute on function public.get_public_school_name() to anon, authenticated;
```

---

## 20261017074658 — support_be_incoming_register_numbers

```sql

insert into public.system_settings(setting_key, setting_value)
values ('incoming_start_number', '1')
on conflict (setting_key) do nothing;

create or replace function public.admin_get_system_settings()
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_uid uuid := auth.uid();
  v_school text;
  v_register_id uuid;
  v_year integer := extract(year from (now() at time zone 'Asia/Bangkok'))::integer;
  v_current bigint;
  v_start bigint;
begin
  if v_uid is null or not exists (
    select 1 from public.user_roles ur
    join public.roles r on r.id = ur.role_id
    where ur.user_id = v_uid and r.code = 'system_admin'
  ) then
    raise exception using errcode = '42501', message = 'system_admin_required';
  end if;
  select setting_value into v_school from public.system_settings where setting_key = 'school_name';
  select setting_value::bigint into v_start from public.system_settings where setting_key = 'incoming_start_number';
  select id into v_register_id from public.document_registers
    where direction = 'incoming' and is_active = true order by created_at desc limit 1;
  if v_register_id is not null then
    select current_number into v_current from public.number_sequences
    where register_id = v_register_id and year = v_year;
  end if;
  return jsonb_build_object(
    'school_name', coalesce(v_school, 'โรงเรียนวัดบึงน้ำใส'),
    'incoming_register_year', v_year + 543,
    'incoming_start_number', greatest(coalesce(v_start, 1), 1),
    'incoming_next_number', coalesce(v_current, coalesce(v_start, 1) - 1) + 1
  );
end;
$$;

create or replace function public.admin_save_system_settings(
  p_school_name text,
  p_incoming_start_number bigint,
  p_incoming_next_number bigint
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_uid uuid := auth.uid();
  v_register_id uuid;
  v_year integer := extract(year from (now() at time zone 'Asia/Bangkok'))::integer;
  v_current bigint;
  v_max_registered bigint;
  v_min_next bigint;
  v_old_school text;
  v_old_start bigint;
begin
  if v_uid is null or not exists (
    select 1 from public.user_roles ur
    join public.roles r on r.id = ur.role_id
    where ur.user_id = v_uid and r.code = 'system_admin'
  ) then
    raise exception using errcode = '42501', message = 'system_admin_required';
  end if;
  if p_school_name is null or length(btrim(p_school_name)) < 3 or length(btrim(p_school_name)) > 200 then
    raise exception using errcode = '22023', message = 'school_name_must_be_3_to_200_chars';
  end if;
  if p_incoming_start_number is null or p_incoming_start_number < 1 then
    raise exception using errcode = '22023', message = 'incoming_start_number_must_be_positive';
  end if;
  if p_incoming_next_number is null or p_incoming_next_number < 1 then
    raise exception using errcode = '22023', message = 'incoming_number_must_be_positive';
  end if;

  select setting_value into v_old_school from public.system_settings where setting_key = 'school_name';
  select setting_value::bigint into v_old_start from public.system_settings where setting_key = 'incoming_start_number';
  insert into public.system_settings(setting_key, setting_value, updated_by, updated_at)
  values ('school_name', btrim(p_school_name), v_uid, now())
  on conflict (setting_key) do update
    set setting_value = excluded.setting_value, updated_by = excluded.updated_by, updated_at = now();
  insert into public.system_settings(setting_key, setting_value, updated_by, updated_at)
  values ('incoming_start_number', p_incoming_start_number::text, v_uid, now())
  on conflict (setting_key) do update
    set setting_value = excluded.setting_value, updated_by = excluded.updated_by, updated_at = now();

  select id into v_register_id from public.document_registers
    where direction = 'incoming' and is_active = true order by created_at desc limit 1;
  if v_register_id is null then
    raise exception using errcode = 'P0001', message = 'active_incoming_register_not_found';
  end if;

  insert into public.number_sequences(register_id, year, current_number)
  values (v_register_id, v_year, p_incoming_start_number - 1)
  on conflict (register_id, year) do nothing;

  select current_number into v_current from public.number_sequences
  where register_id = v_register_id and year = v_year for update;

  select coalesce(max(i.registered_number), 0) into v_max_registered
  from public.incoming_document_details i
  join public.documents d on d.id = i.document_id
  where d.register_id = v_register_id
    and i.registered_at is not null
    and extract(year from (i.registered_at at time zone 'Asia/Bangkok'))::integer = v_year;

  v_min_next := greatest(coalesce(v_current, 0) + 1, v_max_registered + 1);
  if p_incoming_next_number < v_min_next then
    raise exception using errcode = '22023', message = 'incoming_number_cannot_move_backwards';
  end if;

  update public.number_sequences
  set current_number = p_incoming_next_number - 1, updated_at = now()
  where register_id = v_register_id and year = v_year;

  insert into public.audit_logs(actor_id, action, entity_type, old_data, new_data)
  values (v_uid, 'update_system_settings', 'system_settings',
    jsonb_build_object('school_name', v_old_school, 'incoming_start_number', v_old_start),
    jsonb_build_object('school_name', btrim(p_school_name), 'incoming_start_number', p_incoming_start_number,
      'incoming_next_number', p_incoming_next_number, 'incoming_register_year', v_year + 543));

  return jsonb_build_object('ok', true, 'school_name', btrim(p_school_name),
    'incoming_start_number', p_incoming_start_number,
    'incoming_register_year', v_year + 543, 'incoming_next_number', p_incoming_next_number);
end;
$$;

create or replace function private.register_incoming_document(
  p_subject text,
  p_sender_id uuid,
  p_external_document_no text,
  p_external_document_date date,
  p_received_at timestamptz,
  p_urgency public.urgency_level,
  p_receiving_notes text,
  p_department_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_uid uuid := auth.uid();
  v_register uuid;
  v_doc uuid;
  v_no bigint;
  v_year integer := extract(year from (now() at time zone 'Asia/Bangkok'))::integer;
  v_start bigint;
begin
  if v_uid is null or not private.has_permission('registry.incoming.manage') then
    raise exception using errcode = '42501', message = 'permission denied';
  end if;
  if not exists (select 1 from public.profiles pr where pr.id = v_uid and pr.is_active = true) then
    raise exception using errcode = '42501', message = 'active_profile_required';
  end if;
  if p_department_id is null or not exists (
    select 1 from public.departments d where d.id = p_department_id and d.is_active = true
  ) then
    raise exception using errcode = '23503', message = 'active_document_department_required';
  end if;
  if not private.user_has_department(v_uid, p_department_id)
     and not exists (select 1 from public.user_roles ur join public.roles r on r.id=ur.role_id
       where ur.user_id=v_uid and r.code='system_admin') then
    raise exception using errcode = '42501', message = 'department_scope_denied';
  end if;
  if not exists (select 1 from public.senders s where s.id = p_sender_id and s.is_active = true) then
    raise exception using errcode = '23503', message = 'active_sender_required';
  end if;
  select id into v_register from public.document_registers
    where direction = 'incoming' and is_active = true order by created_at desc limit 1;
  if v_register is null then raise exception 'ไม่พบทะเบียนหนังสือรับที่ใช้งานอยู่'; end if;

  select coalesce(setting_value::bigint, 1) into v_start
  from public.system_settings where setting_key = 'incoming_start_number';
  v_start := greatest(coalesce(v_start, 1), 1);
  insert into public.number_sequences(register_id, year, current_number)
  values (v_register, v_year, v_start - 1)
  on conflict (register_id, year) do nothing;
  v_no := private.allocate_document_number(v_register, v_year);

  INSERT INTO public.documents(document_type, register_id, department_id, subject, urgency, status, current_owner_id, created_by)
    VALUES ('incoming', v_register, p_department_id, p_subject, p_urgency, 'received', v_uid, v_uid)
    RETURNING id INTO v_doc;
  INSERT INTO public.incoming_document_details(document_id, sender_id, external_document_no, external_document_date,
    received_at, registered_at, registered_number, receiving_notes)
    VALUES (v_doc, p_sender_id, p_external_document_no, p_external_document_date, p_received_at, now(), v_no, p_receiving_notes);
  INSERT INTO public.document_status_history(document_id, from_status, to_status, changed_by, reason)
    VALUES (v_doc, NULL, 'received', v_uid, 'รับหนังสือเข้าระบบ');
  RETURN v_doc;
END;
$$;

revoke all on function public.admin_get_system_settings() from public, anon;
revoke all on function public.admin_save_system_settings(text, bigint) from public, anon;
revoke all on function public.admin_save_system_settings(text, bigint, bigint) from public, anon;
grant execute on function public.admin_get_system_settings() to authenticated;
grant execute on function public.admin_save_system_settings(text, bigint, bigint) to authenticated;

```

---

## 20261017074815 — include_registration_date_in_deleted_incoming_list

```sql

drop function if exists public.list_deleted_incoming_documents();
create function public.list_deleted_incoming_documents()
returns table(
  id uuid, subject text, status text, deleted_at timestamptz, deletion_reason text,
  department_id uuid, registered_number bigint, registered_at timestamptz, external_document_no text
)
language plpgsql stable security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_actor uuid := auth.uid();
begin
  if v_actor is null or not exists (
    select 1 from public.profiles pr where pr.id=v_actor and pr.is_active=true
  ) then raise exception using errcode='42501', message='active_profile_required'; end if;
  if not (
    private.has_permission('registry.incoming.manage')
    or exists (select 1 from public.user_roles ur join public.roles r on r.id=ur.role_id
      where ur.user_id=v_actor and r.code in ('system_admin','director'))
  ) then raise exception using errcode='42501', message='incoming_delete_permission_denied'; end if;
  return query
  select d.id,d.subject,d.status::text,d.deleted_at,d.deletion_reason,d.department_id,
    inc.registered_number,inc.registered_at,inc.external_document_no
  from public.documents d
  left join public.incoming_document_details inc on inc.document_id=d.id
  where d.document_type='incoming'::public.document_type and d.deleted_at is not null
    and (exists (select 1 from public.user_roles ur join public.roles r on r.id=ur.role_id
      where ur.user_id=v_actor and r.code in ('system_admin','director'))
      or private.user_has_department(v_actor,d.department_id))
  order by d.deleted_at desc;
end;
$$;
revoke all on function public.list_deleted_incoming_documents() from public, anon;
grant execute on function public.list_deleted_incoming_documents() to authenticated;
revoke all on function public.admin_save_system_settings(text, bigint) from public, anon, authenticated;

```

---

## 20261030094941 — require_active_department_for_scoped_permissions

```sql
-- Forward-only security hotfix for the existing department permission helper.
-- Adds active-department validation only to department-scoped grants.
-- Preserves the current Production global System Admin/Director permissions and
-- the Vice Director's existing document.assign exception.
-- This migration is additive and does not change table data, role assignments, or RLS policies.

create or replace function private.has_department_permission(
  p_permission text,
  p_department_id uuid
)
returns boolean
language sql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $function$
  select exists (
    select 1
    from public.profiles pr
    where pr.id = (select auth.uid())
      and pr.is_active = true
      and (
        (
          exists (
            select 1
            from public.user_roles ur
            join public.roles wr on wr.id = ur.role_id
            where ur.user_id = (select auth.uid())
              and wr.code in ('system_admin','director')
          )
          and p_permission in (
            'document.view',
            'document.create',
            'document.approve',
            'document.update',
            'document.assign'
          )
        )
        or (
          p_permission = 'document.assign'
          and exists (
            select 1
            from public.user_roles ur
            join public.roles wr on wr.id = ur.role_id
            where ur.user_id = (select auth.uid())
              and wr.code = 'deputy_director'
          )
        )
        or exists (
          select 1
          from public.user_department_roles udr
          join public.user_departments ud
            on ud.user_id = udr.user_id
           and ud.department_id = udr.department_id
          join public.departments d
            on d.id = udr.department_id
           and d.is_active = true
          join public.roles r on r.id = udr.role_id
          join public.department_role_permissions drp
            on drp.department_id = udr.department_id
           and drp.role_id = udr.role_id
           and drp.enabled = true
          join public.permissions p on p.id = drp.permission_id
          where udr.user_id = pr.id
            and udr.department_id = p_department_id
            and p.code = p_permission
        )
      )
  );
$function$;

```
