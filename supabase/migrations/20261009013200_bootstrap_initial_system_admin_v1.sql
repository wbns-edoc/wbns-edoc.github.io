-- One-time, guarded bootstrap for the first WBNS e-Document system administrator.
-- This migration intentionally targets only the verified school-controlled email.
DO $$
DECLARE
  v_user_id uuid;
  v_email text;
  v_role_id uuid;
  v_user_count integer;
BEGIN
  SELECT count(*)
    INTO v_user_count
    FROM auth.users
   WHERE lower(email) = lower('wbns.59@gmail.com')
     AND email_confirmed_at IS NOT NULL;

  IF v_user_count <> 1 THEN
    RAISE EXCEPTION 'Bootstrap aborted: expected exactly one confirmed auth user for the designated email';
  END IF;

  SELECT id, email
    INTO v_user_id, v_email
    FROM auth.users
   WHERE lower(email) = lower('wbns.59@gmail.com')
     AND email_confirmed_at IS NOT NULL;

  IF EXISTS (
    SELECT 1
      FROM public.user_roles ur
      JOIN public.roles r ON r.id = ur.role_id
     WHERE r.code = 'system_admin'
  ) THEN
    RAISE EXCEPTION 'Bootstrap aborted: a system_admin role assignment already exists';
  END IF;

  SELECT id INTO v_role_id
    FROM public.roles
   WHERE code = 'system_admin';

  IF v_role_id IS NULL THEN
    RAISE EXCEPTION 'Bootstrap aborted: system_admin role is missing';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.profiles
     WHERE id = v_user_id
       AND email IS NOT NULL
       AND lower(email) <> lower(v_email)
  ) THEN
    RAISE EXCEPTION 'Bootstrap aborted: existing profile email does not match the confirmed auth user';
  END IF;

  INSERT INTO public.profiles (id, full_name, email, is_active)
  VALUES (v_user_id, 'ผู้ดูแลระบบโรงเรียนวัดบึงน้ำใส', v_email, true)
  ON CONFLICT (id) DO NOTHING;

  IF NOT EXISTS (
    SELECT 1 FROM public.profiles
     WHERE id = v_user_id
       AND is_active = true
  ) THEN
    RAISE EXCEPTION 'Bootstrap aborted: profile is missing or inactive';
  END IF;

  INSERT INTO public.user_roles (user_id, role_id, assigned_by)
  VALUES (v_user_id, v_role_id, v_user_id);

  INSERT INTO public.audit_logs (actor_id, action, entity_type, entity_id, new_data)
  VALUES (
    v_user_id,
    'initial_system_admin_bootstrap',
    'user_roles',
    v_user_id,
    jsonb_build_object('email', v_email, 'role', 'system_admin', 'method', 'guarded_migration')
  );
END
$$;
