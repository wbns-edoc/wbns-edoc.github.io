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
  IF v_actor IS NULL THEN RAISE EXCEPTION 'permission_denied'; END IF;
  IF NULLIF(btrim(p_instructions), '') IS NULL THEN RAISE EXCEPTION 'assignment_instructions_required'; END IF;

  SELECT array_agg(x ORDER BY x) INTO v_unique_ids
  FROM (SELECT DISTINCT unnest(coalesce(p_assignee_ids, ARRAY[]::uuid[])) AS x) s;
  IF coalesce(array_length(v_unique_ids, 1), 0) = 0 THEN RAISE EXCEPTION 'assignee_required'; END IF;

  SELECT status, subject, department_id INTO v_old, v_subject, v_department
  FROM public.documents WHERE id = p_document_id AND deleted_at IS NULL FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'document_not_found'; END IF;
  IF v_old <> 'registered' THEN RAISE EXCEPTION 'invalid_status_transition'; END IF;
  IF v_department IS NULL OR NOT private.can_access_document(p_document_id)
     OR NOT private.has_department_permission('document.assign', v_department) THEN
    RAISE EXCEPTION 'document_scope_denied';
  END IF;
  IF p_due_at IS NOT NULL AND p_due_at <= now() THEN RAISE EXCEPTION 'deadline_must_be_future'; END IF;

  -- Validate every selected person before writing anything.
  FOREACH v_assignee IN ARRAY v_unique_ids LOOP
    IF NOT EXISTS (
      SELECT 1 FROM public.profiles pr
      WHERE pr.id = v_assignee AND pr.is_active = true
        AND (
          pr.department_id IN (
            WITH RECURSIVE eligible_departments(id) AS (
              SELECT dep.id FROM public.departments dep WHERE dep.id = v_department AND dep.is_active = true
              UNION
              SELECT child.id FROM public.departments child JOIN eligible_departments parent ON child.parent_id = parent.id WHERE child.is_active = true
            ) SELECT id FROM eligible_departments
          )
          OR EXISTS (
            SELECT 1 FROM public.user_departments ud
            WHERE ud.user_id = pr.id AND ud.department_id IN (
              WITH RECURSIVE eligible_departments(id) AS (
                SELECT dep.id FROM public.departments dep WHERE dep.id = v_department AND dep.is_active = true
                UNION
                SELECT child.id FROM public.departments child JOIN eligible_departments parent ON child.parent_id = parent.id WHERE child.is_active = true
              ) SELECT id FROM eligible_departments
            )
          )
        )
    ) THEN RAISE EXCEPTION 'assignee_not_in_document_scope'; END IF;
  END LOOP;

  FOREACH v_assignee IN ARRAY v_unique_ids LOOP
    INSERT INTO public.document_assignments(document_id, assignee_id, assigned_by, instructions, assignment_status)
    VALUES (p_document_id, v_assignee, v_actor, btrim(p_instructions), 'assigned')
    RETURNING id INTO v_assignment_id;
    v_ids := array_append(v_ids, v_assignment_id);

    INSERT INTO public.notifications(recipient_id, document_id, type, title, body, priority)
    VALUES (v_assignee, p_document_id, 'assignment', 'ได้รับมอบหมายงาน',
      'คุณได้รับมอบหมายเรื่อง: ' || coalesce(v_subject, 'ไม่ระบุเรื่อง')
      || E'\nรายละเอียดจากผู้มอบหมาย: ' || btrim(p_instructions), 'high');

    IF p_due_at IS NOT NULL THEN
      INSERT INTO public.deadlines(document_id, assigned_to, due_at, reminder_at, escalation_at, status)
      VALUES (p_document_id, v_assignee, p_due_at, p_due_at - interval '24 hours', p_due_at, 'open');
    END IF;
  END LOOP;

  UPDATE public.documents SET current_owner_id = v_unique_ids[1], status = 'assigned' WHERE id = p_document_id;
  INSERT INTO public.document_status_history(document_id, from_status, to_status, changed_by, reason)
  VALUES (p_document_id, v_old, 'assigned', v_actor, 'มอบหมายงานให้ ' || array_length(v_unique_ids, 1)::text || ' คน');
  RETURN v_ids;
END;
$function$;

REVOKE ALL ON FUNCTION public.assign_document_many(uuid, uuid[], text, timestamptz) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.assign_document_many(uuid, uuid[], text, timestamptz) TO authenticated;
