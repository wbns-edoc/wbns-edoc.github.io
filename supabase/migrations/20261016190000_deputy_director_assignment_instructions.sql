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
