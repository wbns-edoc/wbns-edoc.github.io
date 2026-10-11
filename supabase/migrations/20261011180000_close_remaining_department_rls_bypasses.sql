-- Close remaining direct-table policy paths that still rely on global legacy permissions.
BEGIN;

DROP POLICY IF EXISTS assignments_insert_authorized ON public.document_assignments;
CREATE POLICY assignments_insert_authorized ON public.document_assignments
  FOR INSERT TO authenticated WITH CHECK (
    assigned_by=(SELECT auth.uid())
    AND EXISTS (SELECT 1 FROM public.documents d
      WHERE d.id=document_assignments.document_id
        AND private.can_access_document(d.id)
        AND private.has_department_permission('document.assign',d.department_id))
  );

DROP POLICY IF EXISTS assignments_update_authorized ON public.document_assignments;
CREATE POLICY assignments_update_authorized ON public.document_assignments
  FOR UPDATE TO authenticated
  USING (EXISTS (SELECT 1 FROM public.documents d
    WHERE d.id=document_assignments.document_id
      AND private.can_access_document(d.id)
      AND (assignee_id=(SELECT auth.uid()) OR assigned_by=(SELECT auth.uid())
        OR private.has_department_permission('document.assign',d.department_id))))
  WITH CHECK (EXISTS (SELECT 1 FROM public.documents d
    WHERE d.id=document_assignments.document_id
      AND private.can_access_document(d.id)
      AND (assignee_id=(SELECT auth.uid()) OR assigned_by=(SELECT auth.uid())
        OR private.has_department_permission('document.assign',d.department_id))));

DROP POLICY IF EXISTS deadlines_manage_authorized ON public.deadlines;
CREATE POLICY deadlines_manage_authorized ON public.deadlines
  FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM public.documents d
    WHERE d.id=deadlines.document_id AND private.can_access_document(d.id)
      AND (assigned_to=(SELECT auth.uid())
        OR private.has_department_permission('document.assign',d.department_id))))
  WITH CHECK (EXISTS (SELECT 1 FROM public.documents d
    WHERE d.id=deadlines.document_id AND private.can_access_document(d.id)
      AND (assigned_to=(SELECT auth.uid())
        OR private.has_department_permission('document.assign',d.department_id))));

DROP POLICY IF EXISTS comments_update_own ON public.comments;
CREATE POLICY comments_update_own ON public.comments
  FOR UPDATE TO authenticated
  USING (author_id=(SELECT auth.uid()) AND private.can_access_document(document_id))
  WITH CHECK (author_id=(SELECT auth.uid()) AND private.can_access_document(document_id));

DROP POLICY IF EXISTS documents_insert_authorized ON public.documents;
CREATE POLICY documents_insert_authorized ON public.documents
  FOR INSERT TO authenticated WITH CHECK (
    created_by=(SELECT auth.uid()) AND department_id IS NOT NULL
    AND private.has_department_permission('document.create',department_id));

DROP POLICY IF EXISTS documents_update_authorized ON public.documents;
CREATE POLICY documents_update_authorized ON public.documents
  FOR UPDATE TO authenticated
  USING (private.can_access_document(id) AND department_id IS NOT NULL
    AND (private.has_department_permission('document.update',department_id)
      OR private.has_department_permission('document.assign',department_id)
      OR private.has_department_permission('document.approve',department_id)))
  WITH CHECK (private.can_access_document(id) AND department_id IS NOT NULL
    AND (private.has_department_permission('document.update',department_id)
      OR private.has_department_permission('document.assign',department_id)
      OR private.has_department_permission('document.approve',department_id)));

DROP POLICY IF EXISTS incoming_details_insert_registry ON public.incoming_document_details;
CREATE POLICY incoming_details_insert_registry ON public.incoming_document_details
  FOR INSERT TO authenticated WITH CHECK (EXISTS (
    SELECT 1 FROM public.documents d WHERE d.id=incoming_document_details.document_id
      AND private.can_access_document(d.id)
      AND private.has_department_permission('registry.incoming.manage',d.department_id)));

DROP POLICY IF EXISTS incoming_details_update_registry ON public.incoming_document_details;
CREATE POLICY incoming_details_update_registry ON public.incoming_document_details
  FOR UPDATE TO authenticated
  USING (EXISTS (SELECT 1 FROM public.documents d
    WHERE d.id=incoming_document_details.document_id AND private.can_access_document(d.id)
      AND private.has_department_permission('registry.incoming.manage',d.department_id)))
  WITH CHECK (EXISTS (SELECT 1 FROM public.documents d
    WHERE d.id=incoming_document_details.document_id AND private.can_access_document(d.id)
      AND private.has_department_permission('registry.incoming.manage',d.department_id)));

DROP POLICY IF EXISTS outgoing_details_insert_registry ON public.outgoing_document_details;
CREATE POLICY outgoing_details_insert_registry ON public.outgoing_document_details
  FOR INSERT TO authenticated WITH CHECK (EXISTS (
    SELECT 1 FROM public.documents d WHERE d.id=outgoing_document_details.document_id
      AND private.can_access_document(d.id)
      AND private.has_department_permission('registry.outgoing.manage',d.department_id)));

DROP POLICY IF EXISTS outgoing_details_update_registry ON public.outgoing_document_details;
CREATE POLICY outgoing_details_update_registry ON public.outgoing_document_details
  FOR UPDATE TO authenticated
  USING (EXISTS (SELECT 1 FROM public.documents d
    WHERE d.id=outgoing_document_details.document_id AND private.can_access_document(d.id)
      AND private.has_department_permission('registry.outgoing.manage',d.department_id)))
  WITH CHECK (EXISTS (SELECT 1 FROM public.documents d
    WHERE d.id=outgoing_document_details.document_id AND private.can_access_document(d.id)
      AND private.has_department_permission('registry.outgoing.manage',d.department_id)));

COMMIT;
