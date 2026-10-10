BEGIN;
SELECT plan(1);

-- Seed a synthetic, authorized admin inside this transaction. The recovered
-- catalog fixture intentionally contains no production user rows.
INSERT INTO auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) VALUES (
  'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee5',
  'authenticated', 'authenticated', 'system-admin-guard@example.invalid', '',
  now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb,
  now(), now()
) ON CONFLICT (id) DO NOTHING;

INSERT INTO public.profiles (id, full_name, email, is_active)
VALUES (
  'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee5',
  'Synthetic System Admin Guard Test',
  'system-admin-guard@example.invalid',
  true
)
ON CONFLICT (id) DO UPDATE SET is_active = true;

INSERT INTO public.user_roles (user_id, role_id)
SELECT 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee5', id
FROM public.roles WHERE code = 'system_admin'
ON CONFLICT (user_id, role_id) DO NOTHING;

SELECT set_config('request.jwt.claim.sub','eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee5',true);
SET LOCAL ROLE authenticated;

SELECT throws_ok(
  $$SELECT public.admin_remove_user_role(
      'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee5',
      (SELECT id FROM public.roles WHERE code='system_admin')
    )$$,
  '42501',
  'cannot_remove_last_active_system_admin',
  'cannot remove the last active System Admin role'
);

RESET ROLE;
SELECT * FROM finish();
ROLLBACK;
