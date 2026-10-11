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
