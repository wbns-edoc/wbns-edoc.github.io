-- Prevent ordinary user/role managers from escalating users into global roles.
-- Global roles must be granted through a separately reviewed administrative path.
BEGIN;

CREATE OR REPLACE FUNCTION public.admin_set_user_role(p_user_id uuid, p_role_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
DECLARE
  v_role_code text;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'authentication_required';
  END IF;

  IF NOT private.has_permission('user.manage')
     AND NOT private.has_permission('role.manage') THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'insufficient_privilege';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = p_user_id) THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'user_profile_not_found';
  END IF;

  SELECT code INTO v_role_code
  FROM public.roles
  WHERE id = p_role_id;

  IF v_role_code IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'role_not_found';
  END IF;

  IF v_role_code IN ('system_admin', 'director') THEN
    RAISE EXCEPTION USING ERRCODE = '42501',
      MESSAGE = 'global_role_must_use_global_role_management';
  END IF;

  INSERT INTO public.user_roles(user_id, role_id, assigned_by)
  VALUES (p_user_id, p_role_id, auth.uid())
  ON CONFLICT (user_id, role_id) DO NOTHING;
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_set_user_role(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_set_user_role(uuid, uuid) TO authenticated, service_role;

COMMIT;
