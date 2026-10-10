BEGIN;
SELECT plan(1);

-- The recovered fixture seeds exactly one active System Admin account.
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
