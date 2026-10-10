-- Explicit department assignment for incoming/outgoing registration.
-- Legacy signatures are retained but fail closed for profiles without a department.
BEGIN;

CREATE OR REPLACE FUNCTION private.register_incoming_document(
  p_subject text,
  p_sender_id uuid,
  p_external_document_no text DEFAULT NULL,
  p_external_document_date date DEFAULT NULL,
  p_received_at timestamptz DEFAULT now(),
  p_urgency public.urgency_level DEFAULT 'normal',
  p_receiving_notes text DEFAULT NULL
)
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
$function$;

CREATE OR REPLACE FUNCTION private.register_incoming_document(
  p_subject text,
  p_sender_id uuid,
  p_external_document_no text,
  p_external_document_date date,
  p_received_at timestamptz,
  p_urgency public.urgency_level,
  p_receiving_notes text,
  p_department_id uuid
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
DECLARE
  v_uid uuid := (SELECT auth.uid());
  v_register uuid;
  v_doc uuid;
  v_no bigint;
BEGIN
  IF v_uid IS NULL OR NOT private.has_permission('registry.incoming.manage') THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'permission denied';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.profiles pr
    WHERE pr.id = v_uid AND pr.is_active = true
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'active_profile_required';
  END IF;

  IF p_department_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.departments d WHERE d.id = p_department_id AND d.is_active = true
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '23503', MESSAGE = 'active_document_department_required';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.senders s WHERE s.id = p_sender_id AND s.is_active = true
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '23503', MESSAGE = 'active_sender_required';
  END IF;

  SELECT id INTO v_register
  FROM public.document_registers
  WHERE direction = 'incoming' AND is_active = true
  ORDER BY document_year DESC, created_at
  LIMIT 1;

  IF v_register IS NULL THEN
    RAISE EXCEPTION 'ไม่พบทะเบียนหนังสือรับที่ใช้งานอยู่';
  END IF;

  v_no := private.allocate_document_number(
    v_register,
    (SELECT document_year FROM public.document_registers WHERE id = v_register)
  );

  INSERT INTO public.documents(
    document_type, register_id, department_id, subject, urgency, status, current_owner_id, created_by
  )
  VALUES(
    'incoming', v_register, p_department_id, p_subject, p_urgency, 'received', v_uid, v_uid
  )
  RETURNING id INTO v_doc;

  INSERT INTO public.incoming_document_details(
    document_id, sender_id, external_document_no, external_document_date,
    received_at, registered_at, registered_number, receiving_notes
  )
  VALUES(
    v_doc, p_sender_id, p_external_document_no, p_external_document_date,
    p_received_at, now(), v_no, p_receiving_notes
  );

  INSERT INTO public.document_status_history(document_id, from_status, to_status, changed_by, reason)
  VALUES(v_doc, NULL, 'received', v_uid, 'รับหนังสือเข้าระบบ');

  RETURN v_doc;
END;
$function$;

CREATE OR REPLACE FUNCTION private.register_outgoing_document(
  p_subject text,
  p_recipient_name text,
  p_recipient_address text DEFAULT NULL,
  p_recipient_contact text DEFAULT NULL,
  p_document_date date DEFAULT NULL,
  p_urgency public.urgency_level DEFAULT 'normal'
)
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
$function$;

CREATE OR REPLACE FUNCTION private.register_outgoing_document(
  p_subject text,
  p_recipient_name text,
  p_recipient_address text,
  p_recipient_contact text,
  p_document_date date,
  p_urgency public.urgency_level,
  p_department_id uuid
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
DECLARE
  v_uid uuid := (SELECT auth.uid());
  v_register uuid;
  v_doc uuid;
  v_no bigint;
BEGIN
  IF v_uid IS NULL OR NOT private.has_permission('registry.outgoing.manage') THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'permission denied';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.profiles pr
    WHERE pr.id = v_uid AND pr.is_active = true
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'active_profile_required';
  END IF;

  IF p_department_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.departments d WHERE d.id = p_department_id AND d.is_active = true
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '23503', MESSAGE = 'active_document_department_required';
  END IF;

  SELECT id INTO v_register
  FROM public.document_registers
  WHERE direction = 'outgoing' AND is_active = true
  ORDER BY document_year DESC, created_at
  LIMIT 1;

  IF v_register IS NULL THEN
    RAISE EXCEPTION 'ไม่พบทะเบียนหนังสือส่งที่ใช้งานอยู่';
  END IF;

  v_no := private.allocate_document_number(
    v_register,
    (SELECT document_year FROM public.document_registers WHERE id = v_register)
  );

  INSERT INTO public.documents(
    document_type, register_id, department_id, subject, urgency, status, current_owner_id, created_by
  )
  VALUES(
    'outgoing', v_register, p_department_id, p_subject, p_urgency, 'draft', v_uid, v_uid
  )
  RETURNING id INTO v_doc;

  INSERT INTO public.outgoing_document_details(
    document_id, outgoing_document_no, document_date, recipient_name,
    recipient_address, recipient_contact, registered_number
  )
  VALUES(
    v_doc, NULL, COALESCE(p_document_date, current_date), p_recipient_name,
    p_recipient_address, p_recipient_contact, v_no
  );

  INSERT INTO public.document_status_history(document_id, from_status, to_status, changed_by, reason)
  VALUES(v_doc, NULL, 'draft', v_uid, 'สร้างหนังสือส่งฉบับร่าง');

  RETURN v_doc;
END;
$function$;

CREATE OR REPLACE FUNCTION public.register_incoming_document(
  p_subject text,
  p_sender_id uuid,
  p_external_document_no text,
  p_external_document_date date,
  p_received_at timestamptz,
  p_urgency public.urgency_level,
  p_receiving_notes text,
  p_department_id uuid
)
RETURNS uuid
LANGUAGE sql
SECURITY INVOKER
SET search_path TO 'pg_catalog', 'public'
AS $function$
  SELECT private.register_incoming_document($1,$2,$3,$4,$5,$6,$7,$8);
$function$;

CREATE OR REPLACE FUNCTION public.register_outgoing_document(
  p_subject text,
  p_recipient_name text,
  p_recipient_address text,
  p_recipient_contact text,
  p_document_date date,
  p_urgency public.urgency_level,
  p_department_id uuid
)
RETURNS uuid
LANGUAGE sql
SECURITY INVOKER
SET search_path TO 'pg_catalog', 'public'
AS $function$
  SELECT private.register_outgoing_document($1,$2,$3,$4,$5,$6,$7);
$function$;

REVOKE ALL ON FUNCTION private.register_incoming_document(text,uuid,text,date,timestamptz,public.urgency_level,text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION private.register_outgoing_document(text,text,text,text,date,public.urgency_level) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.register_incoming_document(text,uuid,text,date,timestamptz,public.urgency_level,text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION private.register_outgoing_document(text,text,text,text,date,public.urgency_level) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.register_incoming_document(text,uuid,text,date,timestamptz,public.urgency_level,text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.register_outgoing_document(text,text,text,text,date,public.urgency_level) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.register_incoming_document(text,uuid,text,date,timestamptz,public.urgency_level,text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.register_outgoing_document(text,text,text,text,date,public.urgency_level) TO authenticated, service_role;

REVOKE ALL ON FUNCTION private.register_incoming_document(text,uuid,text,date,timestamptz,public.urgency_level,text,uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION private.register_outgoing_document(text,text,text,text,date,public.urgency_level,uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.register_incoming_document(text,uuid,text,date,timestamptz,public.urgency_level,text,uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION private.register_outgoing_document(text,text,text,text,date,public.urgency_level,uuid) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.register_incoming_document(text,uuid,text,date,timestamptz,public.urgency_level,text,uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.register_outgoing_document(text,text,text,text,date,public.urgency_level,uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.register_incoming_document(text,uuid,text,date,timestamptz,public.urgency_level,text,uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.register_outgoing_document(text,text,text,text,date,public.urgency_level,uuid) TO authenticated, service_role;

COMMIT;
