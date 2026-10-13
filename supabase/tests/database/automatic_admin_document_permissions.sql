BEGIN;
SELECT plan(10);

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


SELECT ok(
  EXISTS (
    SELECT 1 FROM public.role_permissions rp
    JOIN public.roles r ON r.id = rp.role_id
    JOIN public.permissions p ON p.id = rp.permission_id
    WHERE r.code = 'director' AND p.code = 'document.create'
  ),
  'director has document.create'
);
SELECT ok(
  EXISTS (
    SELECT 1 FROM public.role_permissions rp
    JOIN public.roles r ON r.id = rp.role_id
    JOIN public.permissions p ON p.id = rp.permission_id
    WHERE r.code = 'director' AND p.code = 'registry.incoming.manage'
  ),
  'director can register incoming documents'
);
SELECT ok(
  EXISTS (
    SELECT 1 FROM public.role_permissions rp
    JOIN public.roles r ON r.id = rp.role_id
    JOIN public.permissions p ON p.id = rp.permission_id
    WHERE r.code = 'director' AND p.code = 'registry.outgoing.manage'
  ),
  'director can register outgoing documents'
);
SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname='public' AND tablename='documents'
      AND policyname='documents_insert_authorized'
      AND (
        position('director' IN coalesce(with_check,'')) > 0
        OR position('has_department_permission' IN coalesce(with_check,'')) > 0
      )
  ),
  'document insert RLS permits director cross-department creation'
);

SELECT * FROM finish();
ROLLBACK;
