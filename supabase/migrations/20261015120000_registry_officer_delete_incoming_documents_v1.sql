-- Allow Registry Officers to remove mistaken/duplicate incoming registrations safely.
-- Soft-delete only: preserve the document, attachments, register number and audit trail.
BEGIN;

ALTER TABLE public.documents
  ADD COLUMN IF NOT EXISTS deleted_at timestamptz,
  ADD COLUMN IF NOT EXISTS deleted_by uuid REFERENCES public.profiles(id) ON DELETE RESTRICT,
  ADD COLUMN IF NOT EXISTS deletion_reason text;

CREATE INDEX IF NOT EXISTS documents_not_deleted_idx
  ON public.documents (created_at DESC)
  WHERE deleted_at IS NULL;

CREATE OR REPLACE FUNCTION private.can_access_document(p_document_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM public.documents d
    JOIN public.profiles pr ON pr.id=(SELECT auth.uid()) AND pr.is_active=true
    WHERE d.id=p_document_id
      AND d.deleted_at IS NULL
      AND (
        EXISTS (
          SELECT 1 FROM public.user_roles ur
          JOIN public.roles r ON r.id=ur.role_id
          WHERE ur.user_id=pr.id AND r.code IN ('system_admin','director')
        )
        OR (
          d.department_id IS NOT NULL
          AND (
            (
              private.user_has_department(pr.id,d.department_id)
              AND private.has_department_permission('document.view',d.department_id)
            )
            OR EXISTS (
              SELECT 1 FROM public.user_departments ud
              JOIN public.departments child ON child.id=ud.department_id
              WHERE ud.user_id=pr.id AND child.parent_id=d.department_id
                AND private.has_department_permission('document.view',child.id)
            )
          )
        )
      )
  );
$function$;

CREATE OR REPLACE FUNCTION private.delete_incoming_document(
  p_document_id uuid,
  p_reason text
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
DECLARE
  v_actor uuid := (SELECT auth.uid());
  v_doc public.documents%ROWTYPE;
  v_can_manage boolean;
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='authentication_required';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.profiles pr
    WHERE pr.id=v_actor AND pr.is_active=true
  ) THEN
    RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='active_profile_required';
  END IF;

  IF p_reason IS NULL OR btrim(p_reason)='' OR length(btrim(p_reason))>1000 THEN
    RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='deletion_reason_required';
  END IF;

  v_can_manage := private.has_permission('registry.incoming.manage')
    OR EXISTS (
      SELECT 1 FROM public.user_roles ur
      JOIN public.roles r ON r.id=ur.role_id
      WHERE ur.user_id=v_actor AND r.code IN ('system_admin','director')
    );
  IF NOT v_can_manage THEN
    RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='incoming_delete_permission_denied';
  END IF;

  SELECT d.* INTO v_doc
  FROM public.documents d
  WHERE d.id=p_document_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE='P0002', MESSAGE='document_not_found';
  END IF;
  IF v_doc.deleted_at IS NOT NULL THEN
    RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='document_already_deleted';
  END IF;
  IF v_doc.document_type <> 'incoming' THEN
    RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='only_incoming_documents_can_be_deleted';
  END IF;
  IF v_doc.status NOT IN ('received','registered') THEN
    RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='document_already_in_workflow';
  END IF;
  IF NOT private.can_access_document(p_document_id) THEN
    RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='document_scope_denied';
  END IF;
  IF EXISTS (SELECT 1 FROM public.document_assignments da WHERE da.document_id=p_document_id)
     OR EXISTS (SELECT 1 FROM public.approvals a WHERE a.document_id=p_document_id) THEN
    RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='document_already_assigned_or_approved';
  END IF;

  UPDATE public.documents
  SET deleted_at=now(), deleted_by=v_actor, deletion_reason=btrim(p_reason)
  WHERE id=p_document_id;

  INSERT INTO public.audit_logs(actor_id,action,entity_type,entity_id,old_data,new_data)
  VALUES (
    v_actor,
    'delete_incoming_document',
    'documents',
    p_document_id,
    jsonb_build_object(
      'subject',v_doc.subject,
      'document_type',v_doc.document_type,
      'status',v_doc.status,
      'created_by',v_doc.created_by
    ),
    jsonb_build_object(
      'deleted_at',now(),
      'deletion_reason',btrim(p_reason),
      'soft_delete',true
    )
  );

  RETURN true;
END;
$function$;

CREATE OR REPLACE FUNCTION public.delete_incoming_document(
  p_document_id uuid,
  p_reason text
)
RETURNS boolean
LANGUAGE sql
SECURITY INVOKER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
  SELECT private.delete_incoming_document($1,$2);
$function$;

REVOKE ALL ON FUNCTION private.delete_incoming_document(uuid,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.delete_incoming_document(uuid,text) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.delete_incoming_document(uuid,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.delete_incoming_document(uuid,text) TO authenticated, service_role;

CREATE OR REPLACE VIEW public.document_report_summary
WITH (security_invoker=true) AS
SELECT document_type, status, urgency,
       count(*) AS total_documents,
       count(*) FILTER (WHERE created_at >= date_trunc('month',now())) AS current_month
FROM public.documents
WHERE deleted_at IS NULL
GROUP BY document_type,status,urgency;

CREATE OR REPLACE VIEW public.document_monthly_summary
WITH (security_invoker=true) AS
SELECT date_trunc('month',created_at)::date AS month,
       document_type,
       count(*) AS total_documents,
       count(*) FILTER (WHERE status='completed'::public.document_status) AS completed_documents,
       count(*) FILTER (WHERE urgency=ANY(ARRAY['urgent'::public.urgency_level,'very_urgent'::public.urgency_level,'critical'::public.urgency_level])) AS urgent_documents
FROM public.documents
WHERE deleted_at IS NULL
GROUP BY date_trunc('month',created_at)::date,document_type
ORDER BY date_trunc('month',created_at)::date DESC;

COMMIT;
