-- Department-scoped role grants and per-department permission matrix.
-- Forward-only migration; validate against recovered catalog before Production.
BEGIN;

CREATE TABLE IF NOT EXISTS public.user_department_roles (
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  department_id uuid NOT NULL REFERENCES public.departments(id) ON DELETE RESTRICT,
  role_id uuid NOT NULL REFERENCES public.roles(id) ON DELETE RESTRICT,
  assigned_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  assigned_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, department_id, role_id)
);
CREATE INDEX IF NOT EXISTS user_department_roles_department_idx
  ON public.user_department_roles(department_id, user_id);

CREATE TABLE IF NOT EXISTS public.department_role_permissions (
  department_id uuid NOT NULL REFERENCES public.departments(id) ON DELETE CASCADE,
  role_id uuid NOT NULL REFERENCES public.roles(id) ON DELETE CASCADE,
  permission_id uuid NOT NULL REFERENCES public.permissions(id) ON DELETE CASCADE,
  enabled boolean NOT NULL DEFAULT true,
  updated_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (department_id, role_id, permission_id)
);

-- Initialize each department's matrix from the current approved role catalogue.
INSERT INTO public.department_role_permissions(department_id, role_id, permission_id, enabled)
SELECT d.id, rp.role_id, rp.permission_id, true
FROM public.departments d
CROSS JOIN public.role_permissions rp
ON CONFLICT (department_id, role_id, permission_id) DO NOTHING;

-- Move ordinary role grants into each user's primary department; keep the two
-- explicitly global roles global. Existing profile department remains canonical.
INSERT INTO public.user_department_roles(user_id, department_id, role_id, assigned_by, assigned_at)
SELECT ur.user_id, p.department_id, ur.role_id, ur.assigned_by, ur.assigned_at
FROM public.user_roles ur
JOIN public.profiles p ON p.id = ur.user_id
JOIN public.roles r ON r.id = ur.role_id
WHERE p.department_id IS NOT NULL
  AND r.code NOT IN ('system_admin', 'director')
ON CONFLICT DO NOTHING;

ALTER TABLE public.user_department_roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.department_role_permissions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.user_department_roles FROM anon, authenticated;
REVOKE ALL ON public.department_role_permissions FROM anon, authenticated;
GRANT SELECT ON public.user_department_roles TO authenticated;
GRANT SELECT ON public.department_role_permissions TO authenticated;
GRANT ALL ON public.user_department_roles TO service_role;
GRANT ALL ON public.department_role_permissions TO service_role;

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
        private.has_document_wide_read_role()
        AND p_permission IN ('document.view','document.approve','document.update')
        OR EXISTS (
          SELECT 1
          FROM public.user_department_roles udr
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

-- Read inheritance is one-way: a child member with document.view in their own
-- department may read its direct parent's documents; sibling scopes never match.
CREATE OR REPLACE FUNCTION private.can_access_document(p_document_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM public.documents d
    JOIN public.profiles pr ON pr.id = (SELECT auth.uid()) AND pr.is_active = true
    WHERE d.id = p_document_id
      AND (
        (private.has_document_wide_read_role() AND private.has_permission('document.view'))
        OR (
          d.department_id IS NOT NULL
          AND (
            (
              private.user_has_department(pr.id, d.department_id)
              AND private.has_department_permission('document.view', d.department_id)
            )
            OR EXISTS (
              SELECT 1 FROM public.user_departments child_ud
              JOIN public.departments child ON child.id = child_ud.department_id
              WHERE child_ud.user_id = pr.id
                AND child.parent_id = d.department_id
                AND private.has_department_permission('document.view', child.id)
            )
            OR (
              private.user_has_department(pr.id, d.department_id)
              AND (
                d.created_by = (SELECT auth.uid())
                OR d.current_owner_id = (SELECT auth.uid())
                OR EXISTS (
                  SELECT 1 FROM public.document_assignments da
                  WHERE da.document_id = d.id AND da.assignee_id = (SELECT auth.uid())
                    AND da.assignment_status = 'assigned'
                )
              )
            )
          )
        )
      )
  );
$function$;

CREATE OR REPLACE FUNCTION public.admin_set_user_department_role(
  p_user_id uuid, p_department_id uuid, p_role_id uuid, p_enabled boolean
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
BEGIN
  IF NOT private.has_permission('user.manage') AND NOT private.has_permission('role.manage') THEN
    RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='insufficient_privilege';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id=p_user_id AND is_active=true) THEN
    RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='user_profile_not_found_or_inactive';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.departments WHERE id=p_department_id AND is_active=true) THEN
    RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='department_not_found_or_inactive';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.roles WHERE id=p_role_id) THEN
    RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='role_not_found';
  END IF;
  IF EXISTS (SELECT 1 FROM public.roles WHERE id=p_role_id AND code IN ('system_admin','director')) THEN
    RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='global_role_must_use_global_role_management';
  END IF;
  IF p_enabled THEN
    IF NOT EXISTS (SELECT 1 FROM public.user_departments
                   WHERE user_id=p_user_id AND department_id=p_department_id) THEN
      RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='user_is_not_member_of_department';
    END IF;
    INSERT INTO public.user_department_roles(user_id,department_id,role_id,assigned_by)
    VALUES (p_user_id,p_department_id,p_role_id,auth.uid())
    ON CONFLICT (user_id,department_id,role_id) DO UPDATE
      SET assigned_by=EXCLUDED.assigned_by, assigned_at=now();
  ELSE
    DELETE FROM public.user_department_roles
    WHERE user_id=p_user_id AND department_id=p_department_id AND role_id=p_role_id;
  END IF;
  INSERT INTO public.audit_logs(actor_id,action,entity_type,entity_id,new_data)
  VALUES (auth.uid(),'department_role.'||CASE WHEN p_enabled THEN 'assigned' ELSE 'removed' END,
          'user',p_user_id,jsonb_build_object('department_id',p_department_id,'role_id',p_role_id,'enabled',p_enabled));
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_set_department_role_permission(
  p_department_id uuid, p_role_id uuid, p_permission_id uuid, p_enabled boolean
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
BEGIN
  IF NOT private.has_permission('user.manage') AND NOT private.has_permission('role.manage') THEN
    RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='insufficient_privilege';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.departments WHERE id=p_department_id AND is_active=true) THEN
    RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='department_not_found_or_inactive';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.roles WHERE id=p_role_id AND code NOT IN ('system_admin','director')) THEN
    RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='global_role_permissions_are_managed_globally';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.permissions WHERE id=p_permission_id) THEN
    RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='permission_not_found';
  END IF;
  INSERT INTO public.department_role_permissions(department_id,role_id,permission_id,enabled,updated_by,updated_at)
  VALUES (p_department_id,p_role_id,p_permission_id,p_enabled,auth.uid(),now())
  ON CONFLICT (department_id,role_id,permission_id) DO UPDATE
    SET enabled=EXCLUDED.enabled, updated_by=EXCLUDED.updated_by, updated_at=now();
  INSERT INTO public.audit_logs(actor_id,action,entity_type,entity_id,new_data)
  VALUES (auth.uid(),'department_role_permission.changed','department',p_department_id,
          jsonb_build_object('role_id',p_role_id,'permission_id',p_permission_id,'enabled',p_enabled));
END;
$function$;

REVOKE ALL ON FUNCTION private.has_department_permission(text,uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.has_department_permission(text,uuid) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.admin_set_user_department_role(uuid,uuid,uuid,boolean) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_set_department_role_permission(uuid,uuid,uuid,boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_set_user_department_role(uuid,uuid,uuid,boolean) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_set_department_role_permission(uuid,uuid,uuid,boolean) TO authenticated, service_role;

COMMIT;
