-- Give the school director the same global document-create and registry-entry rights
-- as System Admin in the legacy single-department production schema.
BEGIN;

INSERT INTO public.role_permissions(role_id, permission_id)
SELECT r.id, p.id
FROM public.roles r
CROSS JOIN public.permissions p
WHERE r.code = 'director'
  AND p.code IN ('document.create', 'registry.incoming.manage', 'registry.outgoing.manage')
ON CONFLICT (role_id, permission_id) DO NOTHING;

DROP POLICY IF EXISTS documents_insert_authorized ON public.documents;
CREATE POLICY documents_insert_authorized ON public.documents
FOR INSERT TO authenticated
WITH CHECK (
  created_by = (SELECT auth.uid())
  AND private.has_permission('document.create')
  AND (
    department_id IS NULL
    OR department_id = (
      SELECT pr.department_id
      FROM public.profiles pr
      WHERE pr.id = (SELECT auth.uid()) AND pr.is_active = true
    )
    OR EXISTS (
      SELECT 1
      FROM public.user_roles ur
      JOIN public.roles r ON r.id = ur.role_id
      WHERE ur.user_id = (SELECT auth.uid())
        AND r.code IN ('system_admin', 'director')
    )
  )
);

COMMIT;
