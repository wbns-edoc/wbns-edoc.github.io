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
