BEGIN;
CREATE OR REPLACE FUNCTION public.admin_get_user_department_memberships()
RETURNS TABLE(user_id uuid, department_id uuid, department_code text, department_name text, is_primary boolean)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
BEGIN
  IF auth.uid() IS NULL OR (NOT private.has_permission('user.manage') AND NOT private.has_permission('role.manage')) THEN
    RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='insufficient_privilege';
  END IF;
  RETURN QUERY
    SELECT ud.user_id, ud.department_id, d.code, d.name, ud.is_primary
    FROM public.user_departments ud JOIN public.departments d ON d.id=ud.department_id
    ORDER BY ud.user_id, ud.is_primary DESC, d.code;
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_set_user_department_membership(
  p_user_id uuid, p_department_id uuid, p_enabled boolean
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
DECLARE
  v_primary boolean;
  v_replacement uuid;
  v_has_primary boolean;
BEGIN
  IF auth.uid() IS NULL OR (NOT private.has_permission('user.manage') AND NOT private.has_permission('role.manage')) THEN
    RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='insufficient_privilege';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id=p_user_id FOR UPDATE) THEN
    RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='user_profile_not_found';
  END IF;
  -- Adding membership requires an active department. Removing membership must
  -- remain possible after a department is deactivated, otherwise stale access
  -- rows cannot be cleaned up by administrators.
  IF p_enabled AND NOT EXISTS (SELECT 1 FROM public.departments WHERE id=p_department_id AND is_active) THEN
    RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='department_not_found_or_inactive';
  END IF;
  IF NOT p_enabled AND NOT EXISTS (SELECT 1 FROM public.departments WHERE id=p_department_id) THEN
    RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='department_not_found';
  END IF;

  IF p_enabled THEN
    SELECT EXISTS (
      SELECT 1 FROM public.user_departments WHERE user_id=p_user_id AND is_primary
    ) INTO v_has_primary;
    INSERT INTO public.user_departments(user_id,department_id,is_primary,assigned_by)
    VALUES(p_user_id,p_department_id,NOT v_has_primary,auth.uid())
    ON CONFLICT(user_id,department_id) DO UPDATE
      SET is_primary = public.user_departments.is_primary OR EXCLUDED.is_primary,
          updated_at = now();
    IF NOT v_has_primary THEN
      UPDATE public.profiles SET department_id=p_department_id,updated_at=now() WHERE id=p_user_id;
    END IF;
  ELSE
    SELECT is_primary INTO v_primary FROM public.user_departments
    WHERE user_id=p_user_id AND department_id=p_department_id FOR UPDATE;
    IF NOT FOUND THEN RETURN; END IF;
    IF EXISTS (SELECT 1 FROM public.user_department_roles WHERE user_id=p_user_id AND department_id=p_department_id) THEN
      RAISE EXCEPTION USING ERRCODE='23503', MESSAGE='remove_department_roles_before_membership';
    END IF;
    DELETE FROM public.user_departments WHERE user_id=p_user_id AND department_id=p_department_id;
    IF v_primary THEN
      SELECT department_id INTO v_replacement FROM public.user_departments
      WHERE user_id=p_user_id ORDER BY created_at,department_id LIMIT 1 FOR UPDATE;
      IF v_replacement IS NOT NULL THEN
        UPDATE public.user_departments SET is_primary=true,updated_at=now()
        WHERE user_id=p_user_id AND department_id=v_replacement;
      END IF;
      UPDATE public.profiles SET department_id=v_replacement,updated_at=now() WHERE id=p_user_id;
    END IF;
  END IF;

  INSERT INTO public.audit_logs(actor_id,action,entity_type,entity_id,new_data)
  VALUES(auth.uid(),CASE WHEN p_enabled THEN 'department_membership.added' ELSE 'department_membership.removed' END,
         'profile',p_user_id,jsonb_build_object('department_id',p_department_id,'enabled',p_enabled));
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_get_user_department_memberships() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_set_user_department_membership(uuid,uuid,boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_get_user_department_memberships() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_set_user_department_membership(uuid,uuid,boolean) TO authenticated, service_role;
COMMIT;
