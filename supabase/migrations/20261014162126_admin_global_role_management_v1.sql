-- Dedicated management path for school-wide roles.
-- Only an active System Admin may grant or revoke global roles.
CREATE OR REPLACE FUNCTION public.admin_set_global_user_role(
  p_user_id uuid,
  p_role_id uuid,
  p_enabled boolean
)
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

  IF NOT EXISTS (
    SELECT 1
    FROM public.user_roles ur
    JOIN public.roles r ON r.id = ur.role_id
    JOIN public.profiles pr ON pr.id = ur.user_id
    WHERE ur.user_id = auth.uid()
      AND r.code = 'system_admin'
      AND pr.is_active = true
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'system_admin_required_for_global_role_management';
  END IF;

  IF p_enabled IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'enabled_flag_required';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.profiles WHERE id = p_user_id AND is_active = true
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'user_profile_not_found_or_inactive';
  END IF;

  SELECT code INTO v_role_code
  FROM public.roles
  WHERE id = p_role_id;

  IF v_role_code IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'role_not_found';
  END IF;

  IF v_role_code NOT IN ('system_admin', 'director') THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'role_is_not_global';
  END IF;

  IF p_enabled THEN
    INSERT INTO public.user_roles(user_id, role_id, assigned_by)
    VALUES (p_user_id, p_role_id, auth.uid())
    ON CONFLICT (user_id, role_id) DO NOTHING;
  ELSE
    IF v_role_code = 'system_admin'
       AND EXISTS (
         SELECT 1 FROM public.user_roles
         WHERE user_id = p_user_id AND role_id = p_role_id
       )
       AND (
         SELECT count(DISTINCT ur.user_id)
         FROM public.user_roles ur
         JOIN public.roles r ON r.id = ur.role_id
         JOIN public.profiles pr ON pr.id = ur.user_id
         WHERE r.code = 'system_admin' AND pr.is_active = true
       ) <= 1 THEN
      RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'cannot_remove_last_active_system_admin';
    END IF;

    DELETE FROM public.user_roles
    WHERE user_id = p_user_id AND role_id = p_role_id;
  END IF;

  INSERT INTO public.audit_logs(actor_id, action, entity_type, entity_id, new_data)
  VALUES (
    auth.uid(),
    'global_role.' || CASE WHEN p_enabled THEN 'assigned' ELSE 'removed' END,
    'user',
    p_user_id,
    jsonb_build_object('role_code', v_role_code, 'role_id', p_role_id, 'enabled', p_enabled)
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_set_global_user_role(uuid, uuid, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_set_global_user_role(uuid, uuid, boolean) TO authenticated;
