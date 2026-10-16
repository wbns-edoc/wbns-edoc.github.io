-- Notify active Director and Deputy Director users when a Registry Officer registers an incoming document.
-- Notification is created transactionally with the incoming-document registration.
CREATE OR REPLACE FUNCTION private.notify_leadership_on_incoming_registration()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
DECLARE
  v_subject text;
  v_registered_number text;
BEGIN
  SELECT d.subject, id.registered_number::text
    INTO v_subject, v_registered_number
  FROM public.documents d
  LEFT JOIN public.incoming_document_details id ON id.document_id = d.id
  WHERE d.id = NEW.document_id
    AND d.document_type = 'incoming';

  IF NOT FOUND THEN
    RETURN NEW;
  END IF;

  INSERT INTO public.notifications
    (recipient_id, document_id, type, title, body, priority)
  SELECT DISTINCT pr.id,
         NEW.document_id,
         'incoming_registered',
         'มีหนังสือรับลงทะเบียนใหม่',
         'เรื่อง: ' || coalesce(v_subject, 'ไม่ระบุเรื่อง')
           || CASE WHEN v_registered_number IS NOT NULL
                   THEN E'\nเลขทะเบียน: ' || v_registered_number ELSE '' END,
         'high'
  FROM public.profiles pr
  WHERE pr.is_active = true
    AND (
      EXISTS (
        SELECT 1
        FROM public.user_roles ur
        JOIN public.roles r ON r.id = ur.role_id
        WHERE ur.user_id = pr.id
          AND r.code IN ('director', 'deputy_director')
      )
      OR EXISTS (
        SELECT 1
        FROM public.user_department_roles udr
        JOIN public.roles r ON r.id = udr.role_id
        WHERE udr.user_id = pr.id
          AND r.code IN ('director', 'deputy_director')
      )
    );

  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_notify_leadership_on_incoming_registration
  ON public.incoming_document_details;

CREATE TRIGGER trg_notify_leadership_on_incoming_registration
AFTER INSERT ON public.incoming_document_details
FOR EACH ROW
EXECUTE FUNCTION private.notify_leadership_on_incoming_registration();

REVOKE ALL ON FUNCTION private.notify_leadership_on_incoming_registration() FROM PUBLIC, anon, authenticated;
