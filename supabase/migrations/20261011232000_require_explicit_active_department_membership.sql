-- Department scope must be based only on explicit membership in an active department.
-- profiles.department_id remains a primary-department display/compatibility field, not an authorization grant.
BEGIN;

CREATE OR REPLACE FUNCTION private.user_has_department(
  p_user_id uuid,
  p_department_id uuid
) RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM public.user_departments ud
    JOIN public.departments d
      ON d.id = ud.department_id
     AND d.is_active = true
    JOIN public.profiles pr
      ON pr.id = ud.user_id
     AND pr.is_active = true
    WHERE ud.user_id = p_user_id
      AND ud.department_id = p_department_id
  );
$function$;

REVOKE ALL ON FUNCTION private.user_has_department(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.user_has_department(uuid, uuid) TO authenticated, service_role;

COMMIT;
