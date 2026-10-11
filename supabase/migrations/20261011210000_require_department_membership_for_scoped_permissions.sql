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
          AND p_permission IN ('document.view','document.approve','document.update')
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
