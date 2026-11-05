-- Prevent assignment/approval privileges from implicitly granting document edits.
-- Workflow RPCs remain responsible for their own state transitions.
BEGIN;

DROP POLICY IF EXISTS documents_update_authorized ON public.documents;
CREATE POLICY documents_update_authorized ON public.documents
  FOR UPDATE TO authenticated
  USING (
    private.can_access_document(id)
    AND department_id IS NOT NULL
    AND private.has_department_permission('document.update',department_id)
  )
  WITH CHECK (
    private.can_access_document(id)
    AND department_id IS NOT NULL
    AND private.has_department_permission('document.update',department_id)
  );

COMMIT;
