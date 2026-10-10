-- Owner-approved RBAC change: director receives document editing permission by role.
-- Idempotent forward-only migration. This grants a role permission, not a role to any user.
BEGIN;

DO $$
DECLARE
  v_director_role_id uuid;
  v_update_permission_id uuid;
BEGIN
  SELECT id INTO v_director_role_id
  FROM public.roles
  WHERE code = 'director';

  SELECT id INTO v_update_permission_id
  FROM public.permissions
  WHERE code = 'document.update';

  IF v_director_role_id IS NULL THEN
    RAISE EXCEPTION 'Required role code director is missing; refusing partial permission migration';
  END IF;

  IF v_update_permission_id IS NULL THEN
    RAISE EXCEPTION 'Required permission code document.update is missing; refusing partial permission migration';
  END IF;

  INSERT INTO public.role_permissions (role_id, permission_id)
  VALUES (v_director_role_id, v_update_permission_id)
  ON CONFLICT (role_id, permission_id) DO NOTHING;
END
$$;

COMMIT;
