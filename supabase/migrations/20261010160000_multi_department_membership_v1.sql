-- Multi-department membership support; keep profiles.department_id as the primary-department compatibility field.
BEGIN;

CREATE TABLE IF NOT EXISTS public.user_departments (
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  department_id uuid NOT NULL REFERENCES public.departments(id) ON DELETE RESTRICT,
  is_primary boolean NOT NULL DEFAULT false,
  assigned_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, department_id)
);

CREATE UNIQUE INDEX IF NOT EXISTS user_departments_one_primary_idx
  ON public.user_departments(user_id) WHERE is_primary;

INSERT INTO public.user_departments(user_id, department_id, is_primary)
SELECT p.id, p.department_id, true
FROM public.profiles p
JOIN public.departments d ON d.id = p.department_id
ON CONFLICT (user_id, department_id) DO UPDATE SET is_primary = true, updated_at = now();

ALTER TABLE public.user_departments ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.user_departments FROM anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.user_departments TO service_role;

CREATE OR REPLACE FUNCTION private.user_has_department(p_user_id uuid, p_department_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM public.user_departments ud
    WHERE ud.user_id = p_user_id AND ud.department_id = p_department_id
  ) OR EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = p_user_id AND p.department_id = p_department_id
  );
$function$;

CREATE OR REPLACE FUNCTION private.can_access_document(p_document_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM public.documents d
    JOIN public.profiles pr ON pr.id = (SELECT auth.uid()) AND pr.is_active = true
    WHERE d.id = p_document_id
      AND (
        (private.has_permission('document.view')
          AND (private.has_document_wide_read_role()
            OR (d.department_id IS NOT NULL AND private.user_has_department(pr.id, d.department_id))))
        OR (d.department_id IS NOT NULL AND (
          d.created_by = (SELECT auth.uid())
          OR d.current_owner_id = (SELECT auth.uid())
          OR EXISTS (SELECT 1 FROM public.document_assignments da
            WHERE da.document_id = d.id AND da.assignee_id = (SELECT auth.uid())
              AND da.assignment_status = 'assigned')
        ))
      )
  );
$function$;

CREATE OR REPLACE FUNCTION private.default_document_department()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
BEGIN
  IF NEW.department_id IS NULL AND auth.uid() IS NOT NULL THEN
    SELECT pr.department_id INTO NEW.department_id
    FROM public.profiles pr WHERE pr.id = auth.uid() AND pr.is_active = true;
  END IF;
  RETURN NEW;
END;
$function$;

DROP POLICY IF EXISTS documents_insert_authorized ON public.documents;
CREATE POLICY documents_insert_authorized ON public.documents
FOR INSERT TO authenticated
WITH CHECK (
  created_by = (SELECT auth.uid())
  AND private.has_permission('document.create')
  AND (
    department_id IS NULL
    OR private.user_has_department((SELECT auth.uid()), department_id)
    OR EXISTS (SELECT 1 FROM public.user_roles ur JOIN public.roles r ON r.id = ur.role_id
      WHERE ur.user_id = (SELECT auth.uid()) AND r.code = 'system_admin')
  )
);

REVOKE ALL ON FUNCTION private.user_has_department(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.user_has_department(uuid, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION private.can_access_document(uuid) TO authenticated, service_role;

COMMIT;
