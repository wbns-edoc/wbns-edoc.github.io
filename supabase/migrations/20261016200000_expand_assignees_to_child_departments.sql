-- Allow assignment lookup to follow the department hierarchy downward.
-- A parent department (for example SCHOOL) can find active staff in its child
-- departments; a child department still cannot see staff in sibling departments.
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
