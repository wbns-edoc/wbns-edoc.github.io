-- Safely detach one document-file relationship without deleting Drive files or metadata.
BEGIN;

CREATE OR REPLACE FUNCTION public.detach_document_file(p_document_file_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, private
AS $function$
DECLARE
  v_actor uuid := auth.uid();
  v_attachment public.document_files%ROWTYPE;
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'authentication_required';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.profiles pr
    WHERE pr.id = v_actor AND pr.is_active = true
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'active_profile_required';
  END IF;

  IF NOT private.has_permission('document.update') THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'attachment_detach_permission_denied';
  END IF;

  SELECT df.* INTO v_attachment
  FROM public.document_files df
  WHERE df.id = p_document_file_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = 'P0002', MESSAGE = 'attachment_not_found';
  END IF;

  IF NOT private.can_access_document(v_attachment.document_id) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'document_scope_denied';
  END IF;

  -- Delete only the relationship. The audit trigger runs in this transaction
  -- with auth.uid() preserved; the Drive file and its metadata remain intact.
  DELETE FROM public.document_files
  WHERE id = v_attachment.id;

  RETURN jsonb_build_object(
    'attachment_id', v_attachment.id,
    'document_id', v_attachment.document_id,
    'google_drive_file_id', v_attachment.google_drive_file_id,
    'attachment_detached', true,
    'drive_file_trashed', false,
    'drive_file_preserved', true,
    'metadata_preserved', true
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.detach_document_file(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.detach_document_file(uuid) TO authenticated;

COMMIT;
