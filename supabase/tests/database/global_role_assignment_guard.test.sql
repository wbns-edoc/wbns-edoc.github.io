BEGIN;
SELECT plan(2);

SELECT ok(
  position('global_role_must_use_global_role_management' in pg_get_functiondef('public.admin_set_user_role(uuid,uuid)'::regprocedure)) > 0,
  'ordinary role assignment RPC explicitly rejects global roles'
);

SELECT ok(
  NOT has_function_privilege('anon', 'public.admin_set_user_role(uuid,uuid)', 'EXECUTE'),
  'anonymous role cannot execute global-role assignment RPC'
);

SELECT * FROM finish();
ROLLBACK;
