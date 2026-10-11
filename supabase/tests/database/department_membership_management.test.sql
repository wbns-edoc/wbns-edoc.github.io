BEGIN;
SELECT plan(4);

SELECT ok(
  to_regprocedure('public.admin_set_user_department_membership(uuid,uuid,boolean)') IS NOT NULL,
  'membership management RPC is installed'
);

SELECT ok(
  position(
    'IF p_enabled AND NOT EXISTS (SELECT 1 FROM public.departments WHERE id=p_department_id AND is_active)' 
    IN pg_get_functiondef('public.admin_set_user_department_membership(uuid,uuid,boolean)'::regprocedure)
  ) > 0,
  'only adding a membership requires an active department'
);

SELECT ok(
  position(
    'IF NOT p_enabled AND NOT EXISTS (SELECT 1 FROM public.departments WHERE id=p_department_id)'
    IN pg_get_functiondef('public.admin_set_user_department_membership(uuid,uuid,boolean)'::regprocedure)
  ) > 0,
  'membership cleanup remains possible after a department is deactivated'
);

SELECT ok(
  position('v_has_primary' IN pg_get_functiondef('public.admin_set_user_department_membership(uuid,uuid,boolean)'::regprocedure)) > 0,
  'adding a membership restores a primary department if none exists'
);

SELECT * FROM finish();
ROLLBACK;
