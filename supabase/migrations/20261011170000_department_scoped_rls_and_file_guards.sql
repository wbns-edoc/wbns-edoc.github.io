-- Close direct RLS and file attachment paths that bypass department-scoped access.
-- Apply only after the recovered-catalog fixture and regression tests pass.
BEGIN;

-- File attachment is a document mutation: check the target document's department,
-- not merely a legacy global document.update permission.
CREATE OR REPLACE FUNCTION public.attach_document_file_version(
  p_document_id uuid,
  p_google_drive_file_id uuid,
  p_file_role text DEFAULT 'main'
)
RETURNS TABLE(
  id uuid, document_id uuid, google_drive_file_id uuid, file_role text,
  version_no integer, is_current boolean, uploaded_by uuid, uploaded_at timestamptz
)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','public','private'
AS $function$
DECLARE
  v_id uuid; v_version integer; v_department uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION USING errcode='42501',message='authentication_required';
  END IF;
  SELECT d.department_id INTO v_department
    FROM public.documents d WHERE d.id=p_document_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING errcode='22023',message='document_not_found';
  END IF;
  IF v_department IS NULL
     OR NOT private.can_access_document(p_document_id)
     OR NOT private.has_department_permission('document.update',v_department) THEN
    RAISE EXCEPTION USING errcode='42501',message='document_scope_denied';
  END IF;
  IF p_file_role IS NULL OR btrim(p_file_role)='' THEN
    RAISE EXCEPTION USING errcode='22023',message='file_role_required';
  END IF;
  IF NOT EXISTS(SELECT 1 FROM public.google_drive_files f WHERE f.id=p_google_drive_file_id) THEN
    RAISE EXCEPTION USING errcode='22023',message='google_drive_file_not_found';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(p_document_id::text||':'||p_file_role,0));
  SELECT coalesce(max(df.version_no),0)+1 INTO v_version
    FROM public.document_files df
    WHERE df.document_id=p_document_id AND df.file_role=p_file_role;
  UPDATE public.document_files SET is_current=false
    WHERE document_id=p_document_id AND file_role=p_file_role AND is_current=true;
  UPDATE public.google_drive_files SET created_by=coalesce(created_by,auth.uid())
    WHERE id=p_google_drive_file_id;
  INSERT INTO public.document_files(document_id,google_drive_file_id,file_role,version_no,is_current,uploaded_by)
    VALUES(p_document_id,p_google_drive_file_id,p_file_role,v_version,true,auth.uid())
    RETURNING document_files.id INTO v_id;
  RETURN QUERY SELECT df.id,df.document_id,df.google_drive_file_id,df.file_role,
    df.version_no,df.is_current,df.uploaded_by,df.uploaded_at
    FROM public.document_files df WHERE df.id=v_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.attach_document_file_version(uuid,uuid,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.attach_document_file_version(uuid,uuid,text) TO authenticated,service_role;

-- Child records inherit access only through their parent document. Do not use
-- row ownership or legacy global permission checks as an alternative path.
DROP POLICY IF EXISTS comments_select_authorized ON public.comments;
CREATE POLICY comments_select_authorized ON public.comments
  FOR SELECT TO authenticated
  USING (private.can_access_document(document_id));

DROP POLICY IF EXISTS document_files_authorized ON public.document_files;
CREATE POLICY document_files_authorized ON public.document_files
  FOR SELECT TO authenticated
  USING (private.can_access_document(document_id));

DROP POLICY IF EXISTS status_history_select_authorized ON public.document_status_history;
CREATE POLICY status_history_select_authorized ON public.document_status_history
  FOR SELECT TO authenticated
  USING (private.can_access_document(document_id));

DROP POLICY IF EXISTS approvals_select_authorized ON public.approvals;
CREATE POLICY approvals_select_authorized ON public.approvals
  FOR SELECT TO authenticated
  USING (private.can_access_document(document_id));

DROP POLICY IF EXISTS approvals_insert_authorized ON public.approvals;
CREATE POLICY approvals_insert_authorized ON public.approvals
  FOR INSERT TO authenticated
  WITH CHECK (
    approver_id=(SELECT auth.uid())
    AND EXISTS (
      SELECT 1 FROM public.documents d
      WHERE d.id=approvals.document_id
        AND private.can_access_document(d.id)
        AND private.has_department_permission('document.approve',d.department_id)
    )
  );

DROP POLICY IF EXISTS approvals_update_authorized ON public.approvals;
CREATE POLICY approvals_update_authorized ON public.approvals
  FOR UPDATE TO authenticated
  USING (
    approver_id=(SELECT auth.uid())
    AND EXISTS (
      SELECT 1 FROM public.documents d
      WHERE d.id=approvals.document_id
        AND private.can_access_document(d.id)
        AND private.has_department_permission('document.approve',d.department_id)
    )
  )
  WITH CHECK (
    approver_id=(SELECT auth.uid())
    AND EXISTS (
      SELECT 1 FROM public.documents d
      WHERE d.id=approvals.document_id
        AND private.can_access_document(d.id)
        AND private.has_department_permission('document.approve',d.department_id)
    )
  );

DROP POLICY IF EXISTS documents_select_authorized ON public.documents;
CREATE POLICY documents_select_authorized ON public.documents
  FOR SELECT TO authenticated USING (private.can_access_document(id));

DROP POLICY IF EXISTS documents_insert_authorized ON public.documents;
CREATE POLICY documents_insert_authorized ON public.documents
  FOR INSERT TO authenticated
  WITH CHECK (
    created_by=(SELECT auth.uid())
    AND department_id IS NOT NULL
    AND private.has_department_permission('document.create',department_id)
  );

DROP POLICY IF EXISTS documents_update_authorized ON public.documents;
CREATE POLICY documents_update_authorized ON public.documents
  FOR UPDATE TO authenticated
  USING (
    private.can_access_document(id)
    AND department_id IS NOT NULL
    AND (
      private.has_department_permission('document.update',department_id)
      OR private.has_department_permission('document.assign',department_id)
      OR private.has_department_permission('document.approve',department_id)
    )
  )
  WITH CHECK (
    private.can_access_document(id)
    AND department_id IS NOT NULL
    AND (
      private.has_department_permission('document.update',department_id)
      OR private.has_department_permission('document.assign',department_id)
      OR private.has_department_permission('document.approve',department_id)
    )
  );

COMMIT;
