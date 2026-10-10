-- Prevent removal of the final active System Admin assignment.
-- This is a narrow guard: it preserves existing authorization checks and
-- does not grant or assign any role.
BEGIN;

CREATE OR REPLACE FUNCTION public.admin_remove_user_role(p_user_id uuid, p_role_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
BEGIN
  IF NOT private.has_permission('user.manage') AND NOT private.has_permission('role.manage') THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'insufficient_privilege';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.profiles WHERE id = p_user_id
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'user_profile_not_found';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.user_roles ur
    JOIN public.roles r ON r.id = ur.role_id
    WHERE ur.user_id = p_user_id
      AND ur.role_id = p_role_id
      AND r.code = 'system_admin'
  ) AND (
    SELECT count(DISTINCT ur.user_id)
    FROM public.user_roles ur
    JOIN public.roles r ON r.id = ur.role_id
    JOIN public.profiles pr ON pr.id = ur.user_id
    WHERE r.code = 'system_admin'
      AND pr.is_active = true
  ) <= 1 THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'cannot_remove_last_active_system_admin';
  END IF;

  DELETE FROM public.user_roles
  WHERE user_id = p_user_id AND role_id = p_role_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_remove_user_role(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_remove_user_role(uuid, uuid) TO authenticated, service_role;

COMMIT;
