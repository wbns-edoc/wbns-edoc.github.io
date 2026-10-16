-- Grant Director the ability to assign registered documents.
-- Keep the global role permission list and the server-side department permission
-- helper in sync so the UI and assign_document RPC enforce the same capability.

INSERT INTO public.role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM public.roles r
JOIN public.permissions p ON p.code = 'document.assign'
WHERE r.code = 'director'
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
