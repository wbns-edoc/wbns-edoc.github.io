-- Make attachment RPC reject cross-document file reuse and remove PL/pgSQL output-column ambiguity.
BEGIN;

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
  v_id uuid;
  v_version integer;
  v_department uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION USING errcode='42501',message='authentication_required';
  END IF;

  SELECT d.department_id INTO v_department
  FROM public.documents AS d
  WHERE d.id = p_document_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING errcode='22023',message='document_not_found';
  END IF;

  IF v_department IS NULL
     OR NOT private.can_access_document(p_document_id)
     OR NOT private.has_department_permission('document.update',v_department) THEN
    RAISE EXCEPTION USING errcode='42501',message='document_scope_denied';
  END IF;

  IF p_file_role IS NULL OR btrim(p_file_role) = '' THEN
    RAISE EXCEPTION USING errcode='22023',message='file_role_required';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.google_drive_files AS f
    WHERE f.id = p_google_drive_file_id
  ) THEN
    RAISE EXCEPTION USING errcode='22023',message='google_drive_file_not_found';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.document_files AS existing_file
    WHERE existing_file.google_drive_file_id = p_google_drive_file_id
      AND existing_file.document_id <> p_document_id
  ) THEN
    RAISE EXCEPTION USING
      errcode='23505',
      message='file_already_linked_to_another_document';
  END IF;

  PERFORM pg_advisory_xact_lock(
    hashtextextended(p_document_id::text || ':' || p_file_role, 0)
  );

  SELECT coalesce(max(df.version_no), 0) + 1 INTO v_version
  FROM public.document_files AS df
  WHERE df.document_id = p_document_id
    AND df.file_role = p_file_role;

  UPDATE public.document_files AS df
  SET is_current = false
  WHERE df.document_id = p_document_id
    AND df.file_role = p_file_role
    AND df.is_current = true;

  UPDATE public.google_drive_files AS gdf
  SET created_by = coalesce(gdf.created_by, auth.uid())
  WHERE gdf.id = p_google_drive_file_id;

  INSERT INTO public.document_files(
    document_id, google_drive_file_id, file_role, version_no, is_current, uploaded_by
  )
  VALUES (
    p_document_id, p_google_drive_file_id, p_file_role, v_version, true, auth.uid()
  )
  RETURNING document_files.id INTO v_id;

  RETURN QUERY
  SELECT df.id, df.document_id, df.google_drive_file_id, df.file_role,
         df.version_no, df.is_current, df.uploaded_by, df.uploaded_at
  FROM public.document_files AS df
  WHERE df.id = v_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.attach_document_file_version(uuid,uuid,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.attach_document_file_version(uuid,uuid,text) TO authenticated, service_role;

COMMIT;
