-- Include department-scoped role permissions in the permission list consumed by the frontend.
-- Keep the global-role path intact for System Admin and Director.
CREATE OR REPLACE FUNCTION public.get_my_permissions()
RETURNS TABLE(permission_code text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
  SELECT DISTINCT p.code::text
  FROM public.profiles pr
  JOIN public.user_roles ur ON ur.user_id = pr.id
  JOIN public.role_permissions rp ON rp.role_id = ur.role_id
  JOIN public.permissions p ON p.id = rp.permission_id
  WHERE pr.id = (SELECT auth.uid())
    AND pr.is_active = true

  UNION

  SELECT DISTINCT p.code::text
  FROM public.profiles pr
  JOIN public.user_departments ud
    ON ud.user_id = pr.id
  JOIN public.user_department_roles udr
    ON udr.user_id = ud.user_id
   AND udr.department_id = ud.department_id
  JOIN public.department_role_permissions drp
    ON drp.department_id = udr.department_id
   AND drp.role_id = udr.role_id
   AND drp.enabled = true
  JOIN public.permissions p
    ON p.id = drp.permission_id
  JOIN public.departments d
    ON d.id = ud.department_id
   AND d.is_active = true
  JOIN public.roles r
    ON r.id = udr.role_id
   AND r.code NOT IN ('system_admin', 'director')
  WHERE pr.id = (SELECT auth.uid())
    AND pr.is_active = true
  ORDER BY 1;
$function$;

REVOKE ALL ON FUNCTION public.get_my_permissions() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_permissions() TO authenticated, service_role;
