BEGIN;
SELECT plan(6);

SELECT ok(
  EXISTS (
    SELECT 1 FROM public.role_permissions rp
    JOIN public.roles r ON r.id = rp.role_id
    JOIN public.permissions p ON p.id = rp.permission_id
    WHERE r.code = 'system_admin' AND p.code = 'document.view'
  ),
  'system_admin has document.view'
);
SELECT ok(
  EXISTS (
    SELECT 1 FROM public.role_permissions rp
    JOIN public.roles r ON r.id = rp.role_id
    JOIN public.permissions p ON p.id = rp.permission_id
    WHERE r.code = 'system_admin' AND p.code = 'document.approve'
  ),
  'system_admin has document.approve'
);
SELECT ok(
  EXISTS (
    SELECT 1 FROM public.role_permissions rp
    JOIN public.roles r ON r.id = rp.role_id
    JOIN public.permissions p ON p.id = rp.permission_id
    WHERE r.code = 'system_admin' AND p.code = 'document.update'
  ),
  'system_admin has document.update'
);
SELECT ok(
  EXISTS (
    SELECT 1 FROM public.role_permissions rp
    JOIN public.roles r ON r.id = rp.role_id
    JOIN public.permissions p ON p.id = rp.permission_id
    WHERE r.code = 'director' AND p.code = 'document.view'
  ),
  'director has document.view'
);
SELECT ok(
  EXISTS (
    SELECT 1 FROM public.role_permissions rp
    JOIN public.roles r ON r.id = rp.role_id
    JOIN public.permissions p ON p.id = rp.permission_id
    WHERE r.code = 'director' AND p.code = 'document.approve'
  ),
  'director has document.approve'
);
SELECT ok(
  EXISTS (
    SELECT 1 FROM public.role_permissions rp
    JOIN public.roles r ON r.id = rp.role_id
    JOIN public.permissions p ON p.id = rp.permission_id
    WHERE r.code = 'director' AND p.code = 'document.update'
  ),
  'director automatically has document.update through role_permissions'
);

SELECT * FROM finish();
ROLLBACK;
