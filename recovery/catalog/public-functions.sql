-- READ-ONLY RECOVERY SNAPSHOT FROM PRODUCTION CATALOG
-- Project ref: iigzzwyfxxtqbgjawyom
-- Captured: 2026-10-15
-- Not a migration. Review and replay only in an isolated test database.

CREATE OR REPLACE FUNCTION public.admin_create_department(p_code text, p_name text, p_parent_id uuid DEFAULT NULL::uuid)
 RETURNS departments
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
declare v public.departments;
begin
 if not private.has_permission('user.manage') and not private.has_permission('role.manage') then
   raise exception using errcode='42501',message='insufficient_privilege';
 end if;
 if btrim(coalesce(p_code,''))='' or btrim(coalesce(p_name,''))='' then
   raise exception using errcode='22023',message='department_code_and_name_required';
 end if;
 if exists(select 1 from public.departments where lower(code)=lower(btrim(p_code))) then
   raise exception using errcode='23505',message='department_code_exists';
 end if;
 insert into public.departments(code,name,parent_id,is_active)
 values(btrim(p_code),btrim(p_name),p_parent_id,true)
 returning * into v;
 return v;
end $function$


-- ===== NEXT FUNCTION =====

CREATE OR REPLACE FUNCTION public.admin_get_department_permission_catalog()
 RETURNS TABLE(department_id uuid, department_name text, department_parent_id uuid, role_id uuid, role_code text, role_name text, permission_id uuid, permission_code text, permission_name text, enabled boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
BEGIN
  IF NOT private.has_permission('user.manage') AND NOT private.has_permission('role.manage') THEN
    RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='insufficient_privilege';
  END IF;
  RETURN QUERY
  SELECT d.id,d.name::text,d.parent_id,r.id,r.code::text,r.name::text,
         p.id,p.code::text,p.name::text,COALESCE(drp.enabled,false)
  FROM public.departments d CROSS JOIN public.roles r CROSS JOIN public.permissions p
  LEFT JOIN public.department_role_permissions drp
    ON drp.department_id=d.id AND drp.role_id=r.id AND drp.permission_id=p.id
  WHERE d.is_active=true AND r.code NOT IN ('system_admin','director')
  ORDER BY d.name,r.name,p.name;
END;
$function$


-- ===== NEXT FUNCTION =====

CREATE OR REPLACE FUNCTION public.admin_get_user_department_memberships()
 RETURNS TABLE(user_id uuid, department_id uuid, department_code text, department_name text, is_primary boolean)
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
  SELECT * FROM private.admin_get_user_department_memberships_impl();
$function$


-- ===== NEXT FUNCTION =====

CREATE OR REPLACE FUNCTION public.admin_get_user_department_roles()
 RETURNS TABLE(user_id uuid, department_id uuid, role_id uuid, role_code text, role_name text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
BEGIN
  IF NOT private.has_permission('user.manage') AND NOT private.has_permission('role.manage') THEN
    RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='insufficient_privilege';
  END IF;
  RETURN QUERY
  SELECT udr.user_id,udr.department_id,r.id,r.code::text,r.name::text
  FROM public.user_department_roles udr JOIN public.roles r ON r.id=udr.role_id
  ORDER BY udr.user_id,udr.department_id,r.name;
END;
$function$


-- ===== NEXT FUNCTION =====

CREATE OR REPLACE FUNCTION public.admin_remove_user_role(p_user_id uuid, p_role_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
BEGIN
  IF NOT private.has_permission('user.manage') AND NOT private.has_permission('role.manage') THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'insufficient_privilege';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.profiles WHERE id = p_user_id
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'user_profile_not_found';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.user_roles ur
    JOIN public.roles r ON r.id = ur.role_id
    WHERE ur.user_id = p_user_id
      AND ur.role_id = p_role_id
      AND r.code = 'system_admin'
  ) AND (
    SELECT count(DISTINCT ur.user_id)
    FROM public.user_roles ur
    JOIN public.roles r ON r.id = ur.role_id
    JOIN public.profiles pr ON pr.id = ur.user_id
    WHERE r.code = 'system_admin'
      AND pr.is_active = true
  ) <= 1 THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'cannot_remove_last_active_system_admin';
  END IF;

  DELETE FROM public.user_roles
  WHERE user_id = p_user_id AND role_id = p_role_id;
END;
$function$


-- ===== NEXT FUNCTION =====

CREATE OR REPLACE FUNCTION public.admin_set_department_role_permission(p_department_id uuid, p_role_id uuid, p_permission_id uuid, p_enabled boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
BEGIN
  IF NOT private.has_permission('user.manage') AND NOT private.has_permission('role.manage') THEN
    RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='insufficient_privilege';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.departments WHERE id=p_department_id AND is_active=true) THEN
    RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='department_not_found_or_inactive';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.roles WHERE id=p_role_id AND code NOT IN ('system_admin','director')) THEN
    RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='global_role_permissions_are_managed_globally';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.permissions WHERE id=p_permission_id) THEN
    RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='permission_not_found';
  END IF;
  INSERT INTO public.department_role_permissions(department_id,role_id,permission_id,enabled,updated_by,updated_at)
  VALUES (p_department_id,p_role_id,p_permission_id,p_enabled,auth.uid(),now())
  ON CONFLICT (department_id,role_id,permission_id) DO UPDATE
    SET enabled=EXCLUDED.enabled, updated_by=EXCLUDED.updated_by, updated_at=now();
  INSERT INTO public.audit_logs(actor_id,action,entity_type,entity_id,new_data)
  VALUES (auth.uid(),'department_role_permission.changed','department',p_department_id,
          jsonb_build_object('role_id',p_role_id,'permission_id',p_permission_id,'enabled',p_enabled));
END;
$function$


-- ===== NEXT FUNCTION =====

CREATE OR REPLACE FUNCTION public.admin_set_global_user_role(p_user_id uuid, p_role_id uuid, p_enabled boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
DECLARE
  v_role_code text;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'authentication_required';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.user_roles ur
    JOIN public.roles r ON r.id = ur.role_id
    JOIN public.profiles pr ON pr.id = ur.user_id
    WHERE ur.user_id = auth.uid()
      AND r.code = 'system_admin'
      AND pr.is_active = true
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'system_admin_required_for_global_role_management';
  END IF;

  IF p_enabled IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'enabled_flag_required';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.profiles WHERE id = p_user_id AND is_active = true
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'user_profile_not_found_or_inactive';
  END IF;

  SELECT code INTO v_role_code
  FROM public.roles
  WHERE id = p_role_id;

  IF v_role_code IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'role_not_found';
  END IF;

  IF v_role_code NOT IN ('system_admin', 'director') THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'role_is_not_global';
  END IF;

  IF p_enabled THEN
    INSERT INTO public.user_roles(user_id, role_id, assigned_by)
    VALUES (p_user_id, p_role_id, auth.uid())
    ON CONFLICT (user_id, role_id) DO NOTHING;
  ELSE
    IF v_role_code = 'system_admin'
       AND EXISTS (
         SELECT 1 FROM public.user_roles
         WHERE user_id = p_user_id AND role_id = p_role_id
       )
       AND (
         SELECT count(DISTINCT ur.user_id)
         FROM public.user_roles ur
         JOIN public.roles r ON r.id = ur.role_id
         JOIN public.profiles pr ON pr.id = ur.user_id
         WHERE r.code = 'system_admin' AND pr.is_active = true
       ) <= 1 THEN
      RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'cannot_remove_last_active_system_admin';
    END IF;

    DELETE FROM public.user_roles
    WHERE user_id = p_user_id AND role_id = p_role_id;
  END IF;

  INSERT INTO public.audit_logs(actor_id, action, entity_type, entity_id, new_data)
  VALUES (
    auth.uid(),
    'global_role.' || CASE WHEN p_enabled THEN 'assigned' ELSE 'removed' END,
    'user',
    p_user_id,
    jsonb_build_object('role_code', v_role_code, 'role_id', p_role_id, 'enabled', p_enabled)
  );
END;
$function$


-- ===== NEXT FUNCTION =====

CREATE OR REPLACE FUNCTION public.admin_set_user_department(p_user_id uuid, p_department_id uuid DEFAULT NULL::uuid)
 RETURNS profiles
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
declare
  v public.profiles;
  old_department uuid;
begin
  if auth.uid() is null then
    raise exception using errcode='42501',message='authentication_required';
  end if;

  if not private.has_permission('user.manage') and not private.has_permission('role.manage') then
    raise exception using errcode='42501',message='insufficient_privilege';
  end if;

  if not exists(select 1 from public.profiles where id=p_user_id) then
    raise exception using errcode='22023',message='user_profile_not_found';
  end if;

  if p_department_id is not null
     and not exists(select 1 from public.departments where id=p_department_id and is_active=true) then
    raise exception using errcode='22023',message='active_department_not_found';
  end if;

  select department_id into old_department
  from public.profiles
  where id=p_user_id;

  update public.profiles
     set department_id=p_department_id,
         updated_at=now()
   where id=p_user_id
   returning * into v;

  insert into public.audit_logs(
    actor_id,action,entity_type,entity_id,old_data,new_data
  )
  values(
    auth.uid(),
    'user_department_changed',
    'profile',
    p_user_id,
    jsonb_build_object('department_id',old_department),
    jsonb_build_object('department_id',p_department_id)
  );

  return v;
end
$function$


-- ===== NEXT FUNCTION =====

CREATE OR REPLACE FUNCTION public.admin_set_user_department_membership(p_user_id uuid, p_department_id uuid, p_enabled boolean)
 RETURNS void
 LANGUAGE sql
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
  SELECT private.admin_set_user_department_membership_impl(p_user_id,p_department_id,p_enabled);
$function$


-- ===== NEXT FUNCTION =====

CREATE OR REPLACE FUNCTION public.admin_set_user_department_role(p_user_id uuid, p_department_id uuid, p_role_id uuid, p_enabled boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
BEGIN
  IF NOT private.has_permission('user.manage') AND NOT private.has_permission('role.manage') THEN
    RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='insufficient_privilege';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id=p_user_id AND is_active=true) THEN
    RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='user_profile_not_found_or_inactive';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.departments WHERE id=p_department_id AND is_active=true) THEN
    RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='department_not_found_or_inactive';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.roles WHERE id=p_role_id) THEN
    RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='role_not_found';
  END IF;
  IF EXISTS (SELECT 1 FROM public.roles WHERE id=p_role_id AND code IN ('system_admin','director')) THEN
    RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='global_role_must_use_global_role_management';
  END IF;
  IF p_enabled THEN
    IF NOT EXISTS (SELECT 1 FROM public.user_departments
                   WHERE user_id=p_user_id AND department_id=p_department_id) THEN
      RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='user_is_not_member_of_department';
    END IF;
    INSERT INTO public.user_department_roles(user_id,department_id,role_id,assigned_by)
    VALUES (p_user_id,p_department_id,p_role_id,auth.uid())
    ON CONFLICT (user_id,department_id,role_id) DO UPDATE
      SET assigned_by=EXCLUDED.assigned_by, assigned_at=now();
  ELSE
    DELETE FROM public.user_department_roles
    WHERE user_id=p_user_id AND department_id=p_department_id AND role_id=p_role_id;
  END IF;
  INSERT INTO public.audit_logs(actor_id,action,entity_type,entity_id,new_data)
  VALUES (auth.uid(),'department_role.'||CASE WHEN p_enabled THEN 'assigned' ELSE 'removed' END,
          'user',p_user_id,jsonb_build_object('department_id',p_department_id,'role_id',p_role_id,'enabled',p_enabled));
END;
$function$


-- ===== NEXT FUNCTION =====

CREATE OR REPLACE FUNCTION public.admin_set_user_role(p_user_id uuid, p_role_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
DECLARE
  v_role_code text;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'authentication_required';
  END IF;

  IF NOT private.has_permission('user.manage')
     AND NOT private.has_permission('role.manage') THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'insufficient_privilege';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = p_user_id) THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'user_profile_not_found';
  END IF;

  SELECT code INTO v_role_code
  FROM public.roles
  WHERE id = p_role_id;

  IF v_role_code IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'role_not_found';
  END IF;

  IF v_role_code IN ('system_admin', 'director') THEN
    RAISE EXCEPTION USING ERRCODE = '42501',
      MESSAGE = 'global_role_must_use_global_role_management';
  END IF;

  INSERT INTO public.user_roles(user_id, role_id, assigned_by)
  VALUES (p_user_id, p_role_id, auth.uid())
  ON CONFLICT (user_id, role_id) DO NOTHING;
END;
$function$


-- ===== NEXT FUNCTION =====

CREATE OR REPLACE FUNCTION public.admin_update_department(p_department_id uuid, p_code text, p_name text, p_parent_id uuid, p_is_active boolean)
 RETURNS departments
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
declare v public.departments;
begin
 if not private.has_permission('user.manage') and not private.has_permission('role.manage') then
   raise exception using errcode='42501',message='insufficient_privilege';
 end if;
 if not exists(select 1 from public.departments where id=p_department_id) then
   raise exception using errcode='22023',message='department_not_found';
 end if;
 if btrim(coalesce(p_code,''))='' or btrim(coalesce(p_name,''))='' then
   raise exception using errcode='22023',message='department_code_and_name_required';
 end if;
 if exists(select 1 from public.departments where lower(code)=lower(btrim(p_code)) and id<>p_department_id) then
   raise exception using errcode='23505',message='department_code_exists';
 end if;
 update public.departments
 set code=btrim(p_code),name=btrim(p_name),parent_id=p_parent_id,is_active=coalesce(p_is_active,true),updated_at=now()
 where id=p_department_id
 returning * into v;
 return v;
end $function$


-- ===== NEXT FUNCTION =====

CREATE OR REPLACE FUNCTION public.assign_document(p_document_id uuid, p_assignee_id uuid, p_instructions text DEFAULT NULL::text, p_due_at timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS uuid
 LANGUAGE sql
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
  SELECT private.assign_document(p_document_id, p_assignee_id, p_instructions, p_due_at);
$function$


-- ===== NEXT FUNCTION =====

CREATE OR REPLACE FUNCTION public.attach_document_file_version(p_document_id uuid, p_google_drive_file_id uuid, p_file_role text DEFAULT 'main'::text)
 RETURNS TABLE(id uuid, document_id uuid, google_drive_file_id uuid, file_role text, version_no integer, is_current boolean, uploaded_by uuid, uploaded_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
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
$function$


-- ===== NEXT FUNCTION =====

CREATE OR REPLACE FUNCTION public.create_approval(p_document_id uuid, p_approver_id uuid, p_approval_step integer DEFAULT 1)
 RETURNS uuid
 LANGUAGE sql
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$select private.create_approval($1,$2,$3)$function$


-- ===== NEXT FUNCTION =====

CREATE OR REPLACE FUNCTION public.decide_approval(p_approval_id uuid, p_decision approval_decision, p_comment text DEFAULT NULL::text)
 RETURNS boolean
 LANGUAGE sql
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$select private.decide_approval($1,$2,$3)$function$


-- ===== NEXT FUNCTION =====

CREATE OR REPLACE FUNCTION public.delete_incoming_document(p_document_id uuid, p_reason text)
 RETURNS boolean
 LANGUAGE sql
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
  SELECT private.delete_incoming_document($1,$2);
$function$


-- ===== NEXT FUNCTION =====

CREATE OR REPLACE FUNCTION public.finalize_permanent_delete_incoming_document(p_document_id uuid, p_reason text)
 RETURNS boolean
 LANGUAGE sql
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$ SELECT private.finalize_permanent_delete_incoming_document($1,$2); $function$


-- ===== NEXT FUNCTION =====

CREATE OR REPLACE FUNCTION public.get_my_permissions()
 RETURNS TABLE(permission_code text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
  SELECT DISTINCT p.code::text
  FROM public.profiles pr
  JOIN public.user_roles ur ON ur.user_id = pr.id
  JOIN public.role_permissions rp ON rp.role_id = ur.role_id
  JOIN public.permissions p ON p.id = rp.permission_id
  WHERE pr.id = (SELECT auth.uid())
    AND pr.is_active = true

  UNION

  SELECT DISTINCT p.code::text
  FROM public.profiles pr
  JOIN public.user_departments ud
    ON ud.user_id = pr.id
  JOIN public.user_department_roles udr
    ON udr.user_id = ud.user_id
   AND udr.department_id = ud.department_id
  JOIN public.department_role_permissions drp
    ON drp.department_id = udr.department_id
   AND drp.role_id = udr.role_id
   AND drp.enabled = true
  JOIN public.permissions p
    ON p.id = drp.permission_id
  JOIN public.departments d
    ON d.id = ud.department_id
   AND d.is_active = true
  JOIN public.roles r
    ON r.id = udr.role_id
   AND r.code NOT IN ('system_admin', 'director')
  WHERE pr.id = (SELECT auth.uid())
    AND pr.is_active = true
  ORDER BY 1;
$function$


-- ===== NEXT FUNCTION =====

CREATE OR REPLACE FUNCTION public.list_deleted_incoming_documents()
 RETURNS TABLE(id uuid, subject text, status text, deleted_at timestamp with time zone, deletion_reason text, department_id uuid, registered_number bigint, external_document_no text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
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
$function$


-- ===== NEXT FUNCTION =====

CREATE OR REPLACE FUNCTION public.prepare_permanent_delete_incoming_document(p_document_id uuid, p_reason text)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$ SELECT private.prepare_permanent_delete_incoming_document($1,$2); $function$


-- ===== NEXT FUNCTION =====

CREATE OR REPLACE FUNCTION public.register_incoming_document(p_subject text, p_sender_id uuid, p_external_document_no text DEFAULT NULL::text, p_external_document_date date DEFAULT NULL::date, p_received_at timestamp with time zone DEFAULT now(), p_urgency urgency_level DEFAULT 'normal'::urgency_level, p_receiving_notes text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE sql
 SET search_path TO 'pg_catalog', 'public'
AS $function$select private.register_incoming_document($1,$2,$3,$4,$5,$6,$7);$function$


-- ===== NEXT FUNCTION =====

CREATE OR REPLACE FUNCTION public.register_incoming_document(p_subject text, p_sender_id uuid, p_external_document_no text, p_external_document_date date, p_received_at timestamp with time zone, p_urgency urgency_level, p_receiving_notes text, p_department_id uuid)
 RETURNS uuid
 LANGUAGE sql
 SET search_path TO 'pg_catalog', 'public'
AS $function$
  SELECT private.register_incoming_document($1,$2,$3,$4,$5,$6,$7,$8);
$function$


-- ===== NEXT FUNCTION =====

CREATE OR REPLACE FUNCTION public.register_outgoing_document(p_subject text, p_recipient_name text, p_recipient_address text DEFAULT NULL::text, p_recipient_contact text DEFAULT NULL::text, p_document_date date DEFAULT NULL::date, p_urgency urgency_level DEFAULT 'normal'::urgency_level)
 RETURNS uuid
 LANGUAGE sql
 SET search_path TO 'pg_catalog', 'public'
AS $function$select private.register_outgoing_document($1,$2,$3,$4,$5,$6);$function$


-- ===== NEXT FUNCTION =====

CREATE OR REPLACE FUNCTION public.register_outgoing_document(p_subject text, p_recipient_name text, p_recipient_address text, p_recipient_contact text, p_document_date date, p_urgency urgency_level, p_department_id uuid)
 RETURNS uuid
 LANGUAGE sql
 SET search_path TO 'pg_catalog', 'public'
AS $function$
  SELECT private.register_outgoing_document($1,$2,$3,$4,$5,$6,$7);
$function$


-- ===== NEXT FUNCTION =====

CREATE OR REPLACE FUNCTION public.set_document_deadline(p_document_id uuid, p_assigned_to uuid, p_due_at timestamp with time zone, p_reminder_at timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS uuid
 LANGUAGE sql
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
  SELECT private.set_document_deadline(p_document_id, p_assigned_to, p_due_at, p_reminder_at);
$function$


-- ===== NEXT FUNCTION =====

CREATE OR REPLACE FUNCTION public.set_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public'
AS $function$
begin
  new.updated_at = now();
  return new;
end;
$function$


-- ===== NEXT FUNCTION =====

CREATE OR REPLACE FUNCTION public.update_document_status(p_document_id uuid, p_to_status document_status, p_reason text DEFAULT NULL::text)
 RETURNS boolean
 LANGUAGE sql
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
  SELECT private.update_document_status(p_document_id, p_to_status, p_reason);
$function$

