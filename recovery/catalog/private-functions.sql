-- READ-ONLY RECOVERY SNAPSHOT FROM PRODUCTION CATALOG
-- Project ref: iigzzwyfxxtqbgjawyom
-- Captured: 2026-10-15
-- Not a migration. Review and replay only in an isolated test database.

CREATE OR REPLACE FUNCTION private.admin_get_user_department_memberships_impl()
 RETURNS TABLE(user_id uuid, department_id uuid, department_code text, department_name text, is_primary boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
BEGIN
  IF auth.uid() IS NULL OR (NOT private.has_permission('user.manage') AND NOT private.has_permission('role.manage')) THEN
    RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='insufficient_privilege';
  END IF;
  RETURN QUERY
    SELECT ud.user_id, ud.department_id, d.code, d.name, ud.is_primary
    FROM public.user_departments ud JOIN public.departments d ON d.id=ud.department_id
    ORDER BY ud.user_id, ud.is_primary DESC, d.code;
END;
$function$


-- ===== NEXT FUNCTION =====

CREATE OR REPLACE FUNCTION private.admin_set_user_department_membership_impl(p_user_id uuid, p_department_id uuid, p_enabled boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
DECLARE
  v_primary boolean;
  v_replacement uuid;
  v_has_primary boolean;
BEGIN
  IF auth.uid() IS NULL OR (NOT private.has_permission('user.manage') AND NOT private.has_permission('role.manage')) THEN
    RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='insufficient_privilege';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id=p_user_id FOR UPDATE) THEN
    RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='user_profile_not_found';
  END IF;
  IF p_enabled AND NOT EXISTS (SELECT 1 FROM public.departments WHERE id=p_department_id AND is_active) THEN
    RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='department_not_found_or_inactive';
  END IF;
  IF NOT p_enabled AND NOT EXISTS (SELECT 1 FROM public.departments WHERE id=p_department_id) THEN
    RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='department_not_found';
  END IF;

  IF p_enabled THEN
    SELECT EXISTS (
      SELECT 1 FROM public.user_departments ud
      JOIN public.departments d ON d.id=ud.department_id AND d.is_active
      WHERE ud.user_id=p_user_id AND ud.is_primary
    ) INTO v_has_primary;
    IF NOT v_has_primary THEN
      UPDATE public.user_departments SET is_primary=false,updated_at=now()
      WHERE user_id=p_user_id AND is_primary;
    END IF;
    INSERT INTO public.user_departments(user_id,department_id,is_primary,assigned_by)
    VALUES(p_user_id,p_department_id,NOT v_has_primary,auth.uid())
    ON CONFLICT(user_id,department_id) DO UPDATE
      SET is_primary = public.user_departments.is_primary OR EXCLUDED.is_primary,
          updated_at = now();
    IF NOT v_has_primary THEN
      UPDATE public.profiles SET department_id=p_department_id,updated_at=now() WHERE id=p_user_id;
    END IF;
  ELSE
    SELECT is_primary INTO v_primary FROM public.user_departments
    WHERE user_id=p_user_id AND department_id=p_department_id FOR UPDATE;
    IF NOT FOUND THEN RETURN; END IF;
    IF EXISTS (SELECT 1 FROM public.user_department_roles WHERE user_id=p_user_id AND department_id=p_department_id) THEN
      RAISE EXCEPTION USING ERRCODE='23503', MESSAGE='remove_department_roles_before_membership';
    END IF;
    DELETE FROM public.user_departments WHERE user_id=p_user_id AND department_id=p_department_id;
    IF v_primary THEN
      SELECT ud.department_id INTO v_replacement
      FROM public.user_departments ud
      JOIN public.departments d ON d.id=ud.department_id AND d.is_active
      WHERE ud.user_id=p_user_id
      ORDER BY ud.created_at,ud.department_id LIMIT 1 FOR UPDATE OF ud;
      IF v_replacement IS NOT NULL THEN
        UPDATE public.user_departments SET is_primary=true,updated_at=now()
        WHERE user_id=p_user_id AND department_id=v_replacement;
      END IF;
      UPDATE public.profiles SET department_id=v_replacement,updated_at=now() WHERE id=p_user_id;
    END IF;
  END IF;

  INSERT INTO public.audit_logs(actor_id,action,entity_type,entity_id,new_data)
  VALUES(auth.uid(),CASE WHEN p_enabled THEN 'department_membership.added' ELSE 'department_membership.removed' END,
         'profile',p_user_id,jsonb_build_object('department_id',p_department_id,'enabled',p_enabled));
END;
$function$


-- ===== NEXT FUNCTION =====

CREATE OR REPLACE FUNCTION private.allocate_document_number(p_register_id uuid, p_year integer)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$declare v_number bigint;begin if not private.has_permission('registry.incoming.manage') and not private.has_permission('registry.outgoing.manage') then raise exception 'permission denied';end if;insert into public.number_sequences(register_id,year,current_number) values(p_register_id,p_year,0) on conflict(register_id,year) do nothing;update public.number_sequences set current_number=current_number+1,updated_at=now() where register_id=p_register_id and year=p_year returning current_number into v_number;return v_number;end;$function$


-- ===== NEXT FUNCTION =====

CREATE OR REPLACE FUNCTION private.assign_document(p_document_id uuid, p_assignee_id uuid, p_instructions text DEFAULT NULL::text, p_due_at timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
DECLARE
  v_id uuid; v_actor uuid := auth.uid(); v_subject text; v_old public.document_status;
  v_department uuid; v_assignee_department uuid;
BEGIN
  IF v_actor IS NULL THEN RAISE EXCEPTION 'permission_denied'; END IF;
  SELECT status,subject,department_id INTO v_old,v_subject,v_department
    FROM public.documents WHERE id=p_document_id FOR UPDATE;
  IF v_old IS NULL THEN RAISE EXCEPTION 'document_not_found'; END IF;
  IF v_old <> 'registered' THEN RAISE EXCEPTION 'invalid_status_transition'; END IF;
  IF v_department IS NULL OR NOT private.can_access_document(p_document_id)
     OR NOT private.has_department_permission('document.assign',v_department) THEN
    RAISE EXCEPTION 'document_scope_denied';
  END IF;
  IF p_due_at IS NOT NULL AND p_due_at<=now() THEN RAISE EXCEPTION 'deadline_must_be_future'; END IF;
  SELECT department_id INTO v_assignee_department FROM public.profiles
    WHERE id=p_assignee_id AND is_active=true;
  IF NOT FOUND THEN RAISE EXCEPTION 'assignee_not_found'; END IF;
  IF v_assignee_department IS DISTINCT FROM v_department
     AND NOT EXISTS (SELECT 1 FROM public.user_departments ud
                     WHERE ud.user_id=p_assignee_id AND ud.department_id=v_department) THEN
    RAISE EXCEPTION 'cross_department_assignment_denied';
  END IF;
  INSERT INTO public.document_assignments(document_id,assignee_id,assigned_by,instructions,assignment_status)
    VALUES(p_document_id,p_assignee_id,v_actor,p_instructions,'assigned') RETURNING id INTO v_id;
  UPDATE public.documents SET current_owner_id=p_assignee_id,status='assigned' WHERE id=p_document_id;
  INSERT INTO public.document_status_history(document_id,from_status,to_status,changed_by,reason)
    VALUES(p_document_id,v_old,'assigned',v_actor,'มอบหมายงาน');
  INSERT INTO public.notifications(recipient_id,document_id,type,title,body,priority)
    VALUES(p_assignee_id,p_document_id,'assignment','ได้รับมอบหมายงาน',
      'คุณได้รับมอบหมายเรื่อง: '||coalesce(v_subject,'ไม่ระบุเรื่อง'),'high');
  IF p_due_at IS NOT NULL THEN
    INSERT INTO public.deadlines(document_id,assigned_to,due_at,reminder_at,escalation_at,status)
      VALUES(p_document_id,p_assignee_id,p_due_at,p_due_at-interval '24 hours',p_due_at,'open');
  END IF;
  RETURN v_id;
END;
$function$


-- ===== NEXT FUNCTION =====

CREATE OR REPLACE FUNCTION private.audit_row_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
declare
  v_actor uuid := auth.uid();
  v_old jsonb := case when TG_OP in ('UPDATE','DELETE') then to_jsonb(OLD) else null end;
  v_new jsonb := case when TG_OP in ('INSERT','UPDATE') then to_jsonb(NEW) else null end;
  v_entity_id uuid;
begin
  begin
    v_entity_id := coalesce((v_new->>'id')::uuid,(v_old->>'id')::uuid,(v_new->>'document_id')::uuid,(v_old->>'document_id')::uuid);
  exception when others then v_entity_id := null;
  end;
  insert into public.audit_logs(actor_id,action,entity_type,entity_id,old_data,new_data)
  values(v_actor,TG_OP,replace(TG_TABLE_NAME,'_',' '),v_entity_id,v_old,v_new);
  if TG_OP='DELETE' then return OLD; end if;
  return NEW;
end $function$


-- ===== NEXT FUNCTION =====

CREATE OR REPLACE FUNCTION private.can_access_document(p_document_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
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
$function$


-- ===== NEXT FUNCTION =====

CREATE OR REPLACE FUNCTION private.create_approval(p_document_id uuid, p_approver_id uuid, p_approval_step integer DEFAULT 1)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
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
$function$


-- ===== NEXT FUNCTION =====

CREATE OR REPLACE FUNCTION private.decide_approval(p_approval_id uuid, p_decision approval_decision, p_comment text DEFAULT NULL::text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
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
$function$


-- ===== NEXT FUNCTION =====

CREATE OR REPLACE FUNCTION private.default_document_department()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
BEGIN
  IF NEW.department_id IS NULL AND auth.uid() IS NOT NULL THEN
    SELECT pr.department_id INTO NEW.department_id
    FROM public.profiles pr WHERE pr.id = auth.uid() AND pr.is_active = true;
  END IF;
  RETURN NEW;
END;
$function$


-- ===== NEXT FUNCTION =====

CREATE OR REPLACE FUNCTION private.delete_incoming_document(p_document_id uuid, p_reason text)
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
  IF NOT EXISTS (
       SELECT 1 FROM public.user_roles ur
       JOIN public.roles r ON r.id=ur.role_id
       WHERE ur.user_id=v_actor AND r.code IN ('system_admin','director')
     )
     AND NOT private.user_has_department(v_actor,v_doc.department_id) THEN
    RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='incoming_delete_department_scope_denied';
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
$function$


-- ===== NEXT FUNCTION =====

CREATE OR REPLACE FUNCTION private.finalize_permanent_delete_incoming_document(p_document_id uuid, p_reason text)
 RETURNS boolean
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
$function$


-- ===== NEXT FUNCTION =====

CREATE OR REPLACE FUNCTION private.guard_document_department_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
BEGIN
  IF NEW.department_id IS DISTINCT FROM OLD.department_id
     AND NOT EXISTS (
       SELECT 1
       FROM public.user_roles ur
       JOIN public.roles r ON r.id = ur.role_id
       JOIN public.profiles pr ON pr.id = ur.user_id
       WHERE ur.user_id = (SELECT auth.uid())
         AND pr.is_active = true
         AND r.code = 'system_admin'
     ) THEN
    RAISE EXCEPTION USING ERRCODE = '42501',
      MESSAGE = 'document_department_change_requires_system_admin';
  END IF;
  RETURN NEW;
END;
$function$


-- ===== NEXT FUNCTION =====

CREATE OR REPLACE FUNCTION private.has_department_permission(p_permission text, p_department_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM public.profiles pr
    WHERE pr.id = (SELECT auth.uid())
      AND pr.is_active = true
      AND (
        (
          EXISTS (
            SELECT 1
            FROM public.user_roles ur
            JOIN public.roles wr ON wr.id = ur.role_id
            WHERE ur.user_id = (SELECT auth.uid())
              AND wr.code IN ('system_admin','director')
          )
          AND p_permission IN ('document.view','document.create','document.approve','document.update')
        )
        OR EXISTS (
          SELECT 1
          FROM public.user_department_roles udr
          JOIN public.user_departments ud
            ON ud.user_id = udr.user_id
           AND ud.department_id = udr.department_id
          JOIN public.roles r ON r.id = udr.role_id
          JOIN public.department_role_permissions drp
            ON drp.department_id = udr.department_id
           AND drp.role_id = udr.role_id
           AND drp.enabled = true
          JOIN public.permissions p ON p.id = drp.permission_id
          WHERE udr.user_id = pr.id
            AND udr.department_id = p_department_id
            AND p.code = p_permission
        )
      )
  );
$function$


-- ===== NEXT FUNCTION =====

CREATE OR REPLACE FUNCTION private.has_document_wide_read_role()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM public.user_roles ur
    JOIN public.roles r ON r.id = ur.role_id
    JOIN public.profiles pr ON pr.id = ur.user_id
    WHERE ur.user_id = (SELECT auth.uid())
      AND pr.is_active = true
      AND r.code IN ('system_admin', 'director')
  );
$function$


-- ===== NEXT FUNCTION =====

CREATE OR REPLACE FUNCTION private.has_permission(p_permission text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$select exists(select 1 from public.user_roles ur join public.role_permissions rp on rp.role_id=ur.role_id join public.permissions p on p.id=rp.permission_id join public.profiles pr on pr.id=ur.user_id where ur.user_id=(select auth.uid()) and pr.is_active=true and p.code=p_permission);$function$


-- ===== NEXT FUNCTION =====

CREATE OR REPLACE FUNCTION private.is_admin()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$select private.has_permission('settings.manage');$function$


-- ===== NEXT FUNCTION =====

CREATE OR REPLACE FUNCTION private.is_valid_document_transition(p_document_id uuid, p_from document_status, p_to document_status)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
declare v_type text;
begin
  select document_type::text into v_type from public.documents where id=p_document_id;
  if v_type is null then return false; end if;
  if p_to='cancelled' and p_from not in ('completed','archived','cancelled') then return true; end if;
  if p_from='draft' and p_to='pending_approval' then return true; end if;
  if p_from='pending_approval' and p_to in ('approved','draft') then return true; end if;
  if p_from='approved' and p_to='received' then return v_type='incoming'; end if;
  if p_from='approved' and p_to='sent' then return v_type='outgoing'; end if;
  if p_from='received' and p_to='registered' then return v_type='incoming'; end if;
  if p_from='registered' and p_to='assigned' then return true; end if;
  if p_from='assigned' and p_to='in_progress' then return true; end if;
  if p_from='in_progress' and p_to='completed' then return true; end if;
  if p_from='completed' and p_to='archived' then return true; end if;
  if p_from='sent' and p_to='archived' then return v_type='outgoing'; end if;
  return false;
end $function$


-- ===== NEXT FUNCTION =====

CREATE OR REPLACE FUNCTION private.prepare_permanent_delete_incoming_document(p_document_id uuid, p_reason text)
 RETURNS jsonb
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
$function$


-- ===== NEXT FUNCTION =====

CREATE OR REPLACE FUNCTION private.process_deadline_notifications()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
declare v_count integer:=0; d record; r record; v_subject text;
begin
 for d in select dl.id,dl.document_id,dl.assigned_to,dl.due_at,dl.reminder_at,doc.subject,doc.urgency,doc.status
 from public.deadlines dl join public.documents doc on doc.id=dl.document_id
 where dl.status='open' and doc.status not in ('completed','archived','cancelled')
 and ((dl.reminder_at is not null and dl.reminder_at<=now() and dl.due_at>now()) or dl.due_at<=now()) loop
  v_subject:=coalesce(d.subject,'ไม่ระบุเรื่อง');
  if d.due_at<=now() then
   if d.assigned_to is not null and not exists(select 1 from public.notifications n where n.document_id=d.document_id and n.recipient_id=d.assigned_to and n.type='deadline_overdue' and n.created_at>=d.due_at) then
    insert into public.notifications(recipient_id,document_id,type,title,body,priority) values(d.assigned_to,d.document_id,'deadline_overdue','เกินกำหนดงาน','งานเรื่อง "'||v_subject||'" เกินกำหนดแล้ว กรุณาดำเนินการทันที','high'); v_count:=v_count+1;
   end if;
   for r in select distinct ur.user_id from public.user_roles ur join public.roles ro on ro.id=ur.role_id where ro.code in('director','deputy_director') loop
    if not exists(select 1 from public.notifications n where n.document_id=d.document_id and n.recipient_id=r.user_id and n.type='deadline_escalation' and n.created_at>=d.due_at) then
     insert into public.notifications(recipient_id,document_id,type,title,body,priority) values(r.user_id,d.document_id,'deadline_escalation','แจ้งเตือนผู้บริหาร: เกินกำหนด','เอกสารเรื่อง "'||v_subject||'" เกินกำหนดดำเนินการแล้ว','critical'); v_count:=v_count+1;
    end if;
   end loop;
  else
   if d.assigned_to is not null and not exists(select 1 from public.notifications n where n.document_id=d.document_id and n.recipient_id=d.assigned_to and n.type='deadline_reminder' and n.created_at>=d.reminder_at) then
    insert into public.notifications(recipient_id,document_id,type,title,body,priority) values(d.assigned_to,d.document_id,'deadline_reminder','ใกล้ครบกำหนดงาน','งานเรื่อง "'||v_subject||'" ใกล้ครบกำหนด กรุณาตรวจสอบและดำเนินการ','high'); v_count:=v_count+1;
   end if;
   for r in select distinct ur.user_id from public.user_roles ur join public.roles ro on ro.id=ur.role_id where ro.code in('director','deputy_director') loop
    if not exists(select 1 from public.notifications n where n.document_id=d.document_id and n.recipient_id=r.user_id and n.type='deadline_reminder_management' and n.created_at>=d.reminder_at) then
     insert into public.notifications(recipient_id,document_id,type,title,body,priority) values(r.user_id,d.document_id,'deadline_reminder_management','แจ้งเตือนผู้บริหาร: ใกล้ครบกำหนด','เอกสารเรื่อง "'||v_subject||'" ใกล้ครบกำหนดดำเนินการ','high'); v_count:=v_count+1;
    end if;
   end loop;
  end if;
 end loop;
 return v_count;
end $function$


-- ===== NEXT FUNCTION =====

CREATE OR REPLACE FUNCTION private.register_incoming_document(p_subject text, p_sender_id uuid, p_external_document_no text DEFAULT NULL::text, p_external_document_date date DEFAULT NULL::date, p_received_at timestamp with time zone DEFAULT now(), p_urgency urgency_level DEFAULT 'normal'::urgency_level, p_receiving_notes text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
DECLARE
  v_department_id uuid;
BEGIN
  SELECT pr.department_id INTO v_department_id
  FROM public.profiles pr
  WHERE pr.id = (SELECT auth.uid()) AND pr.is_active = true;

  IF v_department_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '23502',
      MESSAGE = 'document_department_required';
  END IF;

  RETURN private.register_incoming_document(
    p_subject, p_sender_id, p_external_document_no, p_external_document_date,
    p_received_at, p_urgency, p_receiving_notes, v_department_id
  );
END;
$function$


-- ===== NEXT FUNCTION =====

CREATE OR REPLACE FUNCTION private.register_incoming_document(p_subject text, p_sender_id uuid, p_external_document_no text, p_external_document_date date, p_received_at timestamp with time zone, p_urgency urgency_level, p_receiving_notes text, p_department_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
DECLARE
  v_uid uuid := (SELECT auth.uid());
  v_register uuid; v_doc uuid; v_no bigint;
BEGIN
  IF v_uid IS NULL OR NOT private.has_permission('registry.incoming.manage') THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'permission denied';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.profiles pr WHERE pr.id = v_uid AND pr.is_active = true) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'active_profile_required';
  END IF;
  IF p_department_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.departments d WHERE d.id = p_department_id AND d.is_active = true
  ) THEN RAISE EXCEPTION USING ERRCODE = '23503', MESSAGE = 'active_document_department_required'; END IF;
  IF NOT private.user_has_department(v_uid, p_department_id)
     AND NOT EXISTS (SELECT 1 FROM public.user_roles ur JOIN public.roles r ON r.id=ur.role_id
       WHERE ur.user_id=v_uid AND r.code='system_admin') THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'department_scope_denied';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.senders s WHERE s.id = p_sender_id AND s.is_active = true) THEN
    RAISE EXCEPTION USING ERRCODE = '23503', MESSAGE = 'active_sender_required';
  END IF;
  SELECT id INTO v_register FROM public.document_registers
    WHERE direction = 'incoming' AND is_active = true ORDER BY document_year DESC, created_at LIMIT 1;
  IF v_register IS NULL THEN RAISE EXCEPTION 'ไม่พบทะเบียนหนังสือรับที่ใช้งานอยู่'; END IF;
  v_no := private.allocate_document_number(v_register,
    (SELECT document_year FROM public.document_registers WHERE id = v_register));
  INSERT INTO public.documents(document_type, register_id, department_id, subject, urgency, status, current_owner_id, created_by)
    VALUES ('incoming', v_register, p_department_id, p_subject, p_urgency, 'received', v_uid, v_uid)
    RETURNING id INTO v_doc;
  INSERT INTO public.incoming_document_details(document_id, sender_id, external_document_no, external_document_date,
    received_at, registered_at, registered_number, receiving_notes)
    VALUES (v_doc, p_sender_id, p_external_document_no, p_external_document_date, p_received_at, now(), v_no, p_receiving_notes);
  INSERT INTO public.document_status_history(document_id, from_status, to_status, changed_by, reason)
    VALUES (v_doc, NULL, 'received', v_uid, 'รับหนังสือเข้าระบบ');
  RETURN v_doc;
END;
$function$


-- ===== NEXT FUNCTION =====

CREATE OR REPLACE FUNCTION private.register_outgoing_document(p_subject text, p_recipient_name text, p_recipient_address text DEFAULT NULL::text, p_recipient_contact text DEFAULT NULL::text, p_document_date date DEFAULT NULL::date, p_urgency urgency_level DEFAULT 'normal'::urgency_level)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
DECLARE
  v_department_id uuid;
BEGIN
  SELECT pr.department_id INTO v_department_id
  FROM public.profiles pr
  WHERE pr.id = (SELECT auth.uid()) AND pr.is_active = true;

  IF v_department_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '23502',
      MESSAGE = 'document_department_required';
  END IF;

  RETURN private.register_outgoing_document(
    p_subject, p_recipient_name, p_recipient_address, p_recipient_contact,
    p_document_date, p_urgency, v_department_id
  );
END;
$function$


-- ===== NEXT FUNCTION =====

CREATE OR REPLACE FUNCTION private.register_outgoing_document(p_subject text, p_recipient_name text, p_recipient_address text, p_recipient_contact text, p_document_date date, p_urgency urgency_level, p_department_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
DECLARE
  v_uid uuid := (SELECT auth.uid());
  v_register uuid; v_doc uuid; v_no bigint;
BEGIN
  IF v_uid IS NULL OR NOT private.has_permission('registry.outgoing.manage') THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'permission denied';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.profiles pr WHERE pr.id = v_uid AND pr.is_active = true) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'active_profile_required';
  END IF;
  IF p_department_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.departments d WHERE d.id = p_department_id AND d.is_active = true
  ) THEN RAISE EXCEPTION USING ERRCODE = '23503', MESSAGE = 'active_document_department_required'; END IF;
  IF NOT private.user_has_department(v_uid, p_department_id)
     AND NOT EXISTS (SELECT 1 FROM public.user_roles ur JOIN public.roles r ON r.id=ur.role_id
       WHERE ur.user_id=v_uid AND r.code='system_admin') THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'department_scope_denied';
  END IF;
  SELECT id INTO v_register FROM public.document_registers
    WHERE direction = 'outgoing' AND is_active = true ORDER BY document_year DESC, created_at LIMIT 1;
  IF v_register IS NULL THEN RAISE EXCEPTION 'ไม่พบทะเบียนหนังสือส่งที่ใช้งานอยู่'; END IF;
  v_no := private.allocate_document_number(v_register,
    (SELECT document_year FROM public.document_registers WHERE id = v_register));
  INSERT INTO public.documents(document_type, register_id, department_id, subject, urgency, status, current_owner_id, created_by)
    VALUES ('outgoing', v_register, p_department_id, p_subject, p_urgency, 'draft', v_uid, v_uid)
    RETURNING id INTO v_doc;
  INSERT INTO public.outgoing_document_details(document_id, outgoing_document_no, document_date, recipient_name,
    recipient_address, recipient_contact, registered_number)
    VALUES (v_doc, NULL, COALESCE(p_document_date, current_date), p_recipient_name,
      p_recipient_address, p_recipient_contact, v_no);
  INSERT INTO public.document_status_history(document_id, from_status, to_status, changed_by, reason)
    VALUES (v_doc, NULL, 'draft', v_uid, 'สร้างหนังสือส่งฉบับร่าง');
  RETURN v_doc;
END;
$function$


-- ===== NEXT FUNCTION =====

CREATE OR REPLACE FUNCTION private.set_document_deadline(p_document_id uuid, p_assigned_to uuid, p_due_at timestamp with time zone, p_reminder_at timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
DECLARE v_id uuid; v_department uuid; v_assignee_department uuid;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'permission_denied'; END IF;
  SELECT department_id INTO v_department FROM public.documents WHERE id=p_document_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'document_not_found'; END IF;
  IF v_department IS NULL OR NOT private.can_access_document(p_document_id)
     OR NOT private.has_department_permission('document.assign',v_department) THEN
    RAISE EXCEPTION 'document_scope_denied';
  END IF;
  SELECT department_id INTO v_assignee_department FROM public.profiles
    WHERE id=p_assigned_to AND is_active=true;
  IF NOT FOUND THEN RAISE EXCEPTION 'assignee_not_found'; END IF;
  IF v_assignee_department IS DISTINCT FROM v_department
     AND NOT EXISTS (SELECT 1 FROM public.user_departments ud
                     WHERE ud.user_id=p_assigned_to AND ud.department_id=v_department) THEN
    RAISE EXCEPTION 'cross_department_assignment_denied';
  END IF;
  IF p_due_at<=now() THEN RAISE EXCEPTION 'deadline_must_be_future'; END IF;
  IF p_reminder_at IS NOT NULL AND p_reminder_at>p_due_at THEN
    RAISE EXCEPTION 'reminder_must_be_before_deadline';
  END IF;
  INSERT INTO public.deadlines(document_id,assigned_to,due_at,reminder_at,escalation_at,status)
    VALUES(p_document_id,p_assigned_to,p_due_at,coalesce(p_reminder_at,p_due_at-interval '24 hours'),p_due_at,'open')
    RETURNING id INTO v_id;
  RETURN v_id;
END;
$function$


-- ===== NEXT FUNCTION =====

CREATE OR REPLACE FUNCTION private.update_document_status(p_document_id uuid, p_to_status document_status, p_reason text DEFAULT NULL::text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
DECLARE v_actor uuid:=auth.uid(); v_from public.document_status; v_department uuid; v_permission text;
BEGIN
  IF v_actor IS NULL THEN RAISE EXCEPTION 'permission_denied'; END IF;
  SELECT status,department_id INTO v_from,v_department FROM public.documents
    WHERE id=p_document_id FOR UPDATE;
  IF v_from IS NULL THEN RAISE EXCEPTION 'document_not_found'; END IF;
  IF NOT private.can_access_document(p_document_id) THEN RAISE EXCEPTION 'document_scope_denied'; END IF;
  IF v_from=p_to_status THEN RETURN true; END IF;
  IF p_to_status IN ('pending_approval','approved','assigned')
     OR (v_from='pending_approval' AND p_to_status='draft') THEN
    RAISE EXCEPTION 'use_dedicated_workflow_rpc';
  END IF;
  v_permission := CASE WHEN p_to_status='completed' THEN 'document.complete'
                       WHEN p_to_status='archived' THEN 'document.archive'
                       ELSE 'document.update' END;
  IF v_department IS NULL OR NOT private.has_department_permission(v_permission,v_department) THEN
    RAISE EXCEPTION 'permission_denied';
  END IF;
  IF NOT private.is_valid_document_transition(p_document_id,v_from,p_to_status) THEN
    RAISE EXCEPTION 'invalid_status_transition';
  END IF;
  UPDATE public.documents SET status=p_to_status WHERE id=p_document_id;
  INSERT INTO public.document_status_history(document_id,from_status,to_status,changed_by,reason)
    VALUES(p_document_id,v_from,p_to_status,v_actor,p_reason);
  IF p_to_status IN ('completed','archived') THEN
    UPDATE public.deadlines SET status='completed',completed_at=coalesce(completed_at,now())
      WHERE document_id=p_document_id AND status='open';
  END IF;
  RETURN true;
END;
$function$


-- ===== NEXT FUNCTION =====

CREATE OR REPLACE FUNCTION private.user_has_department(p_user_id uuid, p_department_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM public.user_departments ud
    JOIN public.departments d
      ON d.id = ud.department_id
     AND d.is_active = true
    JOIN public.profiles pr
      ON pr.id = ud.user_id
     AND pr.is_active = true
    WHERE ud.user_id = p_user_id
      AND ud.department_id = p_department_id
  );
$function$

