-- Read-only recycle-bin listing for authorized incoming registry staff.
CREATE OR REPLACE FUNCTION public.list_deleted_incoming_documents()
RETURNS TABLE (
  id uuid,
  subject text,
  status text,
  deleted_at timestamptz,
  deletion_reason text,
  department_id uuid,
  registered_number bigint,
  external_document_no text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog','public','private'
AS $function$
DECLARE
  v_actor uuid := (SELECT auth.uid());
BEGIN
  IF v_actor IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.profiles pr WHERE pr.id=v_actor AND pr.is_active=true
  ) THEN
    RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='active_profile_required';
  END IF;
  IF NOT (
    private.has_permission('registry.incoming.manage')
    OR EXISTS (SELECT 1 FROM public.user_roles ur JOIN public.roles r ON r.id=ur.role_id
               WHERE ur.user_id=v_actor AND r.code IN ('system_admin','director'))
  ) THEN
    RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='incoming_delete_permission_denied';
  END IF;
  RETURN QUERY
  SELECT d.id,d.subject,d.status::text,d.deleted_at,d.deletion_reason,d.department_id,
         inc.registered_number,inc.external_document_no
  FROM public.documents d
  LEFT JOIN public.incoming_document_details inc ON inc.document_id=d.id
  WHERE d.document_type='incoming'::public.document_type AND d.deleted_at IS NOT NULL
    AND (
      EXISTS (SELECT 1 FROM public.user_roles ur JOIN public.roles r ON r.id=ur.role_id
              WHERE ur.user_id=v_actor AND r.code IN ('system_admin','director'))
      OR private.user_has_department(v_actor,d.department_id)
    )
  ORDER BY d.deleted_at DESC;
END;
$function$;
REVOKE ALL ON FUNCTION public.list_deleted_incoming_documents() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_deleted_incoming_documents() TO authenticated;
