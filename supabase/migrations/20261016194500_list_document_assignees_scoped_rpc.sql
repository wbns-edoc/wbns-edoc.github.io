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