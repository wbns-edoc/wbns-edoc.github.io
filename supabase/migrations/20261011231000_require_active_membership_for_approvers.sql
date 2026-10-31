-- Ensure selected approvers still have active membership in the document department.
-- This closes stale user_department_roles rows after a membership is removed.
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
          JOIN public.user_departments ud
            ON ud.user_id=udr.user_id AND ud.department_id=udr.department_id
          JOIN public.departments dept
            ON dept.id=ud.department_id AND dept.is_active=true
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

REVOKE ALL ON FUNCTION private.create_approval(uuid,uuid,integer) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION private.create_approval(uuid,uuid,integer) TO authenticated,service_role;
COMMIT;
