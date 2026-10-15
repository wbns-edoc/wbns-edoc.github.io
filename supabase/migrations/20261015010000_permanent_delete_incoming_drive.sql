-- Permanent purge for soft-deleted incoming registrations.
-- Drive objects are removed by the authenticated Edge Function before finalize is called.
CREATE OR REPLACE FUNCTION private.prepare_permanent_delete_incoming_document(
  p_document_id uuid,
  p_reason text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
DECLARE
  v_actor uuid := (SELECT auth.uid());
  v_doc public.documents%ROWTYPE;
  v_can_manage boolean;
  v_files jsonb;
BEGIN
  IF v_actor IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.profiles pr WHERE pr.id=v_actor AND pr.is_active=true
  ) THEN
    RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='active_profile_required';
  END IF;
  IF p_reason IS NULL OR length(btrim(p_reason)) < 5 OR length(btrim(p_reason)) > 1000 THEN
    RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='deletion_reason_required';
  END IF;

  v_can_manage := private.has_permission('registry.incoming.manage')
    OR EXISTS (
      SELECT 1 FROM public.user_roles ur JOIN public.roles r ON r.id=ur.role_id
      WHERE ur.user_id=v_actor AND r.code IN ('system_admin','director')
    );
  IF NOT v_can_manage THEN
    RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='incoming_delete_permission_denied';
  END IF;

  SELECT d.* INTO v_doc FROM public.documents d WHERE d.id=p_document_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0002', MESSAGE='document_not_found'; END IF;
  IF v_doc.deleted_at IS NULL THEN RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='soft_delete_required_first'; END IF;
  IF v_doc.document_type <> 'incoming' THEN RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='only_incoming_documents_can_be_purged'; END IF;
  IF v_doc.status NOT IN ('received','registered') THEN RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='document_already_in_workflow'; END IF;
  IF NOT private.can_access_document(p_document_id) THEN
    -- can_access_document excludes soft-deleted rows; authorization is checked against department membership below.
    IF NOT EXISTS (
      SELECT 1 FROM public.user_roles ur JOIN public.roles r ON r.id=ur.role_id
      WHERE ur.user_id=v_actor AND r.code IN ('system_admin','director')
    ) AND NOT private.user_has_department(v_actor,v_doc.department_id) THEN
      RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='document_scope_denied';
    END IF;
  END IF;
  IF NOT EXISTS (
       SELECT 1 FROM public.user_roles ur JOIN public.roles r ON r.id=ur.role_id
       WHERE ur.user_id=v_actor AND r.code IN ('system_admin','director')
     ) AND NOT private.user_has_department(v_actor,v_doc.department_id) THEN
    RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='incoming_delete_department_scope_denied';
  END IF;
  IF EXISTS (SELECT 1 FROM public.document_assignments WHERE document_id=p_document_id)
     OR EXISTS (SELECT 1 FROM public.approvals WHERE document_id=p_document_id) THEN
    RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='document_already_assigned_or_approved';
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'metadata_id', gd.id,
    'drive_file_id', gd.drive_file_id,
    'name', gd.name,
    'delete_drive', NOT EXISTS (
      SELECT 1 FROM public.document_files other_df
      WHERE other_df.google_drive_file_id=gd.id AND other_df.document_id<>p_document_id
    )
  ) ORDER BY gd.id), '[]'::jsonb)
  INTO v_files
  FROM public.document_files df
  JOIN public.google_drive_files gd ON gd.id=df.google_drive_file_id
  WHERE df.document_id=p_document_id;

  RETURN jsonb_build_object(
    'document_id', v_doc.id,
    'subject', v_doc.subject,
    'document_type', v_doc.document_type,
    'status', v_doc.status,
    'department_id', v_doc.department_id,
    'reason', btrim(p_reason),
    'files', v_files
  );
END;
$function$;

CREATE OR REPLACE FUNCTION private.finalize_permanent_delete_incoming_document(
  p_document_id uuid,
  p_reason text
) RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
DECLARE
  v_actor uuid := (SELECT auth.uid());
  v_doc public.documents%ROWTYPE;
  v_file_summary jsonb;
BEGIN
  IF v_actor IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.profiles pr WHERE pr.id=v_actor AND pr.is_active=true
  ) THEN
    RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='active_profile_required';
  END IF;
  IF p_reason IS NULL OR length(btrim(p_reason)) < 5 OR length(btrim(p_reason)) > 1000 THEN
    RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='deletion_reason_required';
  END IF;
  IF NOT (
    private.has_permission('registry.incoming.manage')
    OR EXISTS (SELECT 1 FROM public.user_roles ur JOIN public.roles r ON r.id=ur.role_id
               WHERE ur.user_id=v_actor AND r.code IN ('system_admin','director'))
  ) THEN
    RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='incoming_delete_permission_denied';
  END IF;

  SELECT d.* INTO v_doc FROM public.documents d WHERE d.id=p_document_id FOR UPDATE;
  IF NOT FOUND THEN
    -- Idempotent completion: already purged is treated as success.
    RETURN true;
  END IF;
  IF v_doc.deleted_at IS NULL OR v_doc.document_type <> 'incoming' OR v_doc.status NOT IN ('received','registered') THEN
    RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='document_not_eligible_for_permanent_delete';
  END IF;
  IF NOT EXISTS (
       SELECT 1 FROM public.user_roles ur JOIN public.roles r ON r.id=ur.role_id
       WHERE ur.user_id=v_actor AND r.code IN ('system_admin','director')
     ) AND NOT private.user_has_department(v_actor,v_doc.department_id) THEN
    RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='incoming_delete_department_scope_denied';
  END IF;
  IF EXISTS (SELECT 1 FROM public.document_assignments WHERE document_id=p_document_id)
     OR EXISTS (SELECT 1 FROM public.approvals WHERE document_id=p_document_id) THEN
    RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='document_already_assigned_or_approved';
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'name', gd.name,
    'drive_file_id', gd.drive_file_id,
    'shared_with_other_documents', EXISTS (
      SELECT 1 FROM public.document_files other_df
      WHERE other_df.google_drive_file_id=gd.id AND other_df.document_id<>p_document_id
    )
  )), '[]'::jsonb)
  INTO v_file_summary
  FROM public.document_files df JOIN public.google_drive_files gd ON gd.id=df.google_drive_file_id
  WHERE df.document_id=p_document_id;

  INSERT INTO public.audit_logs(actor_id,action,entity_type,entity_id,old_data,new_data)
  VALUES (
    v_actor, 'permanently_delete_incoming_document', 'documents', p_document_id,
    jsonb_build_object(
      'subject',v_doc.subject,
      'document_type',v_doc.document_type,
      'status',v_doc.status,
      'department_id',v_doc.department_id,
      'created_by',v_doc.created_by,
      'deleted_at',v_doc.deleted_at,
      'deleted_by',v_doc.deleted_by,
      'deletion_reason',v_doc.deletion_reason,
      'attachments',v_file_summary
    ),
    jsonb_build_object('permanently_deleted_at',now(),'permanent_deletion_reason',btrim(p_reason),'database_row_removed',true)
  );

  DELETE FROM public.comments WHERE document_id=p_document_id;
  DELETE FROM public.deadlines WHERE document_id=p_document_id;
  DELETE FROM public.document_assignments WHERE document_id=p_document_id;
  DELETE FROM public.approvals WHERE document_id=p_document_id;
  DELETE FROM public.notifications WHERE document_id=p_document_id;
  DELETE FROM public.document_status_history WHERE document_id=p_document_id;
  DELETE FROM public.incoming_document_details WHERE document_id=p_document_id;
  DELETE FROM public.outgoing_document_details WHERE document_id=p_document_id;
  DELETE FROM public.document_files WHERE document_id=p_document_id;
  DELETE FROM public.documents WHERE id=p_document_id;

  -- Remove only metadata no longer referenced by any remaining document.
  DELETE FROM public.google_drive_files gd
  WHERE NOT EXISTS (SELECT 1 FROM public.document_files df WHERE df.google_drive_file_id=gd.id)
    AND EXISTS (SELECT 1 FROM jsonb_array_elements(v_file_summary) f WHERE f->>'drive_file_id'=gd.drive_file_id);

  RETURN true;
END;
$function$;

CREATE OR REPLACE FUNCTION public.prepare_permanent_delete_incoming_document(p_document_id uuid, p_reason text)
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path TO 'pg_catalog','public','private'
AS $function$ SELECT private.prepare_permanent_delete_incoming_document($1,$2); $function$;

CREATE OR REPLACE FUNCTION public.finalize_permanent_delete_incoming_document(p_document_id uuid, p_reason text)
RETURNS boolean LANGUAGE sql SECURITY INVOKER SET search_path TO 'pg_catalog','public','private'
AS $function$ SELECT private.finalize_permanent_delete_incoming_document($1,$2); $function$;

REVOKE ALL ON FUNCTION private.prepare_permanent_delete_incoming_document(uuid,text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION private.finalize_permanent_delete_incoming_document(uuid,text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.prepare_permanent_delete_incoming_document(uuid,text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.finalize_permanent_delete_incoming_document(uuid,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.prepare_permanent_delete_incoming_document(uuid,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.finalize_permanent_delete_incoming_document(uuid,text) TO authenticated;
