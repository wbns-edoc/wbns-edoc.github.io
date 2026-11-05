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
