-- Keep the task list in sync when an assigned user completes the document workflow.
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
      SELECT 1 FROM public.document_assignments da
      WHERE da.document_id = p_document_id AND da.assignee_id = v_actor
        AND da.assignment_status IN ('assigned', 'accepted', 'in_progress')
    ) INTO v_is_assignee;
  END IF;
  v_permission := CASE WHEN p_to_status = 'completed' THEN 'document.complete'
                       WHEN p_to_status = 'archived' THEN 'document.archive'
                       ELSE 'document.update' END;
  IF NOT v_is_assignee
     AND (v_department IS NULL OR NOT private.has_department_permission(v_permission, v_department)) THEN
    RAISE EXCEPTION 'permission_denied';
  END IF;
  IF NOT private.is_valid_document_transition(p_document_id, v_from, p_to_status) THEN
    RAISE EXCEPTION 'invalid_status_transition';
  END IF;
  UPDATE public.documents SET status = p_to_status WHERE id = p_document_id;
  IF p_to_status = 'completed' THEN
    UPDATE public.document_assignments
    SET assignment_status = 'completed', completed_at = coalesce(completed_at, now())
    WHERE document_id = p_document_id AND assignee_id = v_actor
      AND assignment_status IN ('assigned', 'accepted', 'in_progress');
  END IF;
  INSERT INTO public.document_status_history(document_id, from_status, to_status, changed_by, reason)
  VALUES (p_document_id, v_from, p_to_status, v_actor, p_reason);
  IF p_to_status IN ('completed', 'archived') THEN
    UPDATE public.deadlines SET status = 'completed', completed_at = coalesce(completed_at, now())
    WHERE document_id = p_document_id AND status = 'open';
  END IF;
  RETURN true;
END;
$function$;
REVOKE ALL ON FUNCTION private.update_document_status(uuid, public.document_status, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION private.update_document_status(uuid, public.document_status, text) TO authenticated;
