-- Scope approval creation and decisions to the document's department while
-- preserving existing state transitions and notifications from the recovered catalog.
BEGIN;

CREATE OR REPLACE FUNCTION private.create_approval(
  p_document_id uuid, p_approver_id uuid, p_approval_step integer DEFAULT 1
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','public','private'
AS $function$
DECLARE
  v_id uuid; v_actor uuid:=auth.uid(); v_subject text;
  v_status public.document_status; v_department uuid;
BEGIN
  IF v_actor IS NULL THEN RAISE EXCEPTION 'permission_denied'; END IF;
  SELECT status,subject,department_id INTO v_status,v_subject,v_department
  FROM public.documents WHERE id=p_document_id FOR UPDATE;
  IF v_status IS NULL THEN RAISE EXCEPTION 'document_not_found'; END IF;
  IF v_department IS NULL OR NOT private.can_access_document(p_document_id)
     OR NOT private.has_department_permission('document.approve',v_department) THEN
    RAISE EXCEPTION 'permission_denied';
  END IF;
  IF p_approval_step < 1 THEN RAISE EXCEPTION 'invalid_approval_step'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.profiles pr
    WHERE pr.id=p_approver_id AND pr.is_active=true
      AND (
        EXISTS (SELECT 1 FROM public.user_roles ur JOIN public.roles r ON r.id=ur.role_id
                WHERE ur.user_id=pr.id AND r.code IN ('system_admin','director'))
        OR EXISTS (
          SELECT 1 FROM public.user_department_roles udr
          JOIN public.department_role_permissions drp
            ON drp.department_id=udr.department_id AND drp.role_id=udr.role_id
            AND drp.enabled=true
          JOIN public.permissions p ON p.id=drp.permission_id
          WHERE udr.user_id=pr.id AND udr.department_id=v_department
            AND p.code='document.approve'
        )
      )
  ) THEN RAISE EXCEPTION 'approver_not_authorized'; END IF;
  IF v_status <> 'draft' THEN RAISE EXCEPTION 'document_not_in_draft'; END IF;

  INSERT INTO public.approvals(document_id,approval_step,approver_id,decision)
  VALUES(p_document_id,p_approval_step,p_approver_id,'pending') RETURNING id INTO v_id;
  UPDATE public.documents SET status='pending_approval' WHERE id=p_document_id;
  INSERT INTO public.notifications(recipient_id,document_id,type,title,body,priority)
  VALUES(p_approver_id,p_document_id,'approval','รอการอนุมัติ',
         'มีเอกสารรอการอนุมัติ: '||coalesce(v_subject,'ไม่ระบุเรื่อง'),'high');
  RETURN v_id;
END;
$function$;

CREATE OR REPLACE FUNCTION private.decide_approval(
  p_approval_id uuid, p_decision public.approval_decision, p_comment text DEFAULT NULL
) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','public','private'
AS $function$
DECLARE
  v_actor uuid:=auth.uid(); v_doc uuid; v_step integer; v_subject text; v_department uuid;
BEGIN
  IF v_actor IS NULL THEN RAISE EXCEPTION 'permission_denied'; END IF;
  SELECT a.document_id,a.approval_step,d.department_id
    INTO v_doc,v_step,v_department
  FROM public.approvals a
  JOIN public.documents d ON d.id=a.document_id
  WHERE a.id=p_approval_id AND a.approver_id=v_actor AND a.decision='pending'
  FOR UPDATE OF a;
  IF v_doc IS NULL THEN RAISE EXCEPTION 'approval_not_found_or_not_authorized'; END IF;
  IF v_department IS NULL OR NOT private.can_access_document(v_doc)
     OR NOT private.has_department_permission('document.approve',v_department) THEN
    RAISE EXCEPTION 'permission_denied';
  END IF;
  IF p_decision NOT IN ('approved','rejected','returned') THEN
    RAISE EXCEPTION 'invalid_approval_decision';
  END IF;

  UPDATE public.approvals SET decision=p_decision,comment=p_comment,decided_at=now()
    WHERE id=p_approval_id;
  IF p_decision='approved' THEN
    IF EXISTS(SELECT 1 FROM public.approvals
              WHERE document_id=v_doc AND approval_step>v_step AND decision='pending') THEN
      UPDATE public.documents SET status='pending_approval' WHERE id=v_doc;
    ELSE
      UPDATE public.documents SET status='approved' WHERE id=v_doc;
    END IF;
  ELSIF p_decision IN ('rejected','returned') THEN
    UPDATE public.documents SET status='draft' WHERE id=v_doc;
  END IF;
  SELECT subject INTO v_subject FROM public.documents WHERE id=v_doc;
  INSERT INTO public.notifications(recipient_id,document_id,type,title,body,priority)
  SELECT DISTINCT d.created_by,v_doc,'approval_decision','ผลการอนุมัติ',
    'เอกสาร "'||coalesce(v_subject,'ไม่ระบุเรื่อง')||'" มีผลการพิจารณา: '||p_decision::text,'high'
  FROM public.documents d WHERE d.id=v_doc AND d.created_by IS NOT NULL;
  RETURN true;
END;
$function$;

REVOKE ALL ON FUNCTION private.create_approval(uuid,uuid,integer) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION private.decide_approval(uuid,public.approval_decision,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION private.create_approval(uuid,uuid,integer) TO authenticated,service_role;
GRANT EXECUTE ON FUNCTION private.decide_approval(uuid,public.approval_decision,text) TO authenticated,service_role;
COMMIT;
