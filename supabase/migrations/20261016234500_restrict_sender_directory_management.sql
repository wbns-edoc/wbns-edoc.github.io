-- Only System Admin, School Admin, and Registry Officer may create, update, or delete sender directory entries.
-- Sender removal in the UI is a soft delete (is_active=false) to preserve document history.
DROP POLICY IF EXISTS senders_manage_registry ON public.senders;

CREATE POLICY senders_insert_admin_registry
ON public.senders
FOR INSERT
TO authenticated
WITH CHECK (
  EXISTS (
    SELECT 1 FROM public.user_roles ur
    JOIN public.roles r ON r.id = ur.role_id
    WHERE ur.user_id = (SELECT auth.uid())
      AND r.code IN ('system_admin', 'school_admin', 'registry_officer')
  )
  OR EXISTS (
    SELECT 1 FROM public.user_department_roles udr
    JOIN public.roles r ON r.id = udr.role_id
    WHERE udr.user_id = (SELECT auth.uid())
      AND r.code IN ('system_admin', 'school_admin', 'registry_officer')
  )
);

CREATE POLICY senders_update_admin_registry
ON public.senders
FOR UPDATE
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.user_roles ur
    JOIN public.roles r ON r.id = ur.role_id
    WHERE ur.user_id = (SELECT auth.uid())
      AND r.code IN ('system_admin', 'school_admin', 'registry_officer')
  )
  OR EXISTS (
    SELECT 1 FROM public.user_department_roles udr
    JOIN public.roles r ON r.id = udr.role_id
    WHERE udr.user_id = (SELECT auth.uid())
      AND r.code IN ('system_admin', 'school_admin', 'registry_officer')
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1 FROM public.user_roles ur
    JOIN public.roles r ON r.id = ur.role_id
    WHERE ur.user_id = (SELECT auth.uid())
      AND r.code IN ('system_admin', 'school_admin', 'registry_officer')
  )
  OR EXISTS (
    SELECT 1 FROM public.user_department_roles udr
    JOIN public.roles r ON r.id = udr.role_id
    WHERE udr.user_id = (SELECT auth.uid())
      AND r.code IN ('system_admin', 'school_admin', 'registry_officer')
  )
);

CREATE POLICY senders_delete_admin_registry
ON public.senders
FOR DELETE
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.user_roles ur
    JOIN public.roles r ON r.id = ur.role_id
    WHERE ur.user_id = (SELECT auth.uid())
      AND r.code IN ('system_admin', 'school_admin', 'registry_officer')
  )
  OR EXISTS (
    SELECT 1 FROM public.user_department_roles udr
    JOIN public.roles r ON r.id = udr.role_id
    WHERE udr.user_id = (SELECT auth.uid())
      AND r.code IN ('system_admin', 'school_admin', 'registry_officer')
  )
);
