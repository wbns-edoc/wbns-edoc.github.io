BEGIN;
SELECT plan(1);
SELECT ok(to_regprocedure('public.admin_set_user_department_membership(uuid,uuid,boolean)') IS NOT NULL, 'membership management RPC is installed');
SELECT * FROM finish();
ROLLBACK;
