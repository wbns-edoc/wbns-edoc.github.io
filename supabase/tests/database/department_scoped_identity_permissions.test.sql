BEGIN;
SELECT plan(3);

SELECT ok(
  position('user_department_roles' IN pg_get_functiondef('public.get_my_permissions()'::regprocedure)) > 0,
  'get_my_permissions includes department-scoped role assignments'
);

SELECT ok(
  position('department_role_permissions' IN pg_get_functiondef('public.get_my_permissions()'::regprocedure)) > 0,
  'get_my_permissions includes enabled department permission grants'
);

SELECT ok(
  has_function_privilege('authenticated', 'public.get_my_permissions()', 'EXECUTE')
  AND NOT has_function_privilege('anon', 'public.get_my_permissions()', 'EXECUTE'),
  'permission RPC is callable by authenticated users only'
);

SELECT * FROM finish();
ROLLBACK;
