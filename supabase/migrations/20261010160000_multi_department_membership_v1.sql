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
        (private.has_permission('document.view')
          AND (private.has_document_wide_read_role()
            OR (d.department_id IS NOT NULL AND private.user_has_department(pr.id, d.department_id))))
        OR (d.department_id IS NOT NULL
          AND private.user_has_department(pr.id, d.department_id)
          AND (
            d.created_by = (SELECT auth.uid())
            OR d.current_owner_id = (SELECT auth.uid())
            OR EXISTS (SELECT 1 FROM public.document_assignments da
              WHERE da.document_id = d.id AND da.assignee_id = (SELECT auth.uid())
                AND da.assignment_status = 'assigned')
          ))
      )
  );
$function$;

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

DROP POLICY IF EXISTS documents_insert_authorized ON public.documents;
CREATE POLICY documents_insert_authorized ON public.documents
FOR INSERT TO authenticated
WITH CHECK (
  created_by = (SELECT auth.uid())
  AND private.has_permission('document.create')
  AND (
    department_id IS NULL
    OR private.user_has_department((SELECT auth.uid()), department_id)
    OR EXISTS (SELECT 1 FROM public.user_roles ur JOIN public.roles r ON r.id = ur.role_id
      WHERE ur.user_id = (SELECT auth.uid()) AND r.code = 'system_admin')
  )
);

REVOKE ALL ON FUNCTION private.user_has_department(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.user_has_department(uuid, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION private.can_access_document(uuid) TO authenticated, service_role;



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
  p_instructions text,
  p_due_at timestamp with time zone
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
