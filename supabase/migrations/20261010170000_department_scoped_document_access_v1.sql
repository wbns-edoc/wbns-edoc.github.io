-- Department-scoped document and attachment access.
-- Forward-only hardening; validate against recovered catalog fixture before deployment.
BEGIN;

ALTER TABLE public.documents
  ADD COLUMN IF NOT EXISTS department_id uuid
  REFERENCES public.departments(id) ON DELETE RESTRICT;

CREATE INDEX IF NOT EXISTS documents_department_id_idx
  ON public.documents(department_id);

-- A user's department is the default scope for documents they create.
-- Central accounts without a department remain unscoped unless they explicitly
-- provide a department and satisfy the insert policy.
CREATE OR REPLACE FUNCTION private.default_document_department()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
BEGIN
  IF NEW.department_id IS NULL AND auth.uid() IS NOT NULL THEN
    SELECT pr.department_id INTO NEW.department_id
    FROM public.profiles pr
    WHERE pr.id = auth.uid() AND pr.is_active = true;
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS documents_default_department ON public.documents;
CREATE TRIGGER documents_default_department
BEFORE INSERT ON public.documents
FOR EACH ROW EXECUTE FUNCTION private.default_document_department();

CREATE OR REPLACE FUNCTION private.has_document_wide_read_role()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
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
$function$;

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
    WHERE d.id = p_document_id
      AND (
        d.created_by = (SELECT auth.uid())
        OR d.current_owner_id = (SELECT auth.uid())
        OR (
          private.has_permission('document.view')
          AND (
            private.has_document_wide_read_role()
            OR (
              d.department_id IS NOT NULL
              AND EXISTS (
                SELECT 1 FROM public.profiles pr
                WHERE pr.id = (SELECT auth.uid())
                  AND pr.is_active = true
                  AND pr.department_id = d.department_id
              )
            )
          )
        )
      )
  );
$function$;

-- Changing a document's department is a separate administrative action;
-- document.update and director's cross-department editing do not imply this right.
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
$function$;

DROP TRIGGER IF EXISTS documents_guard_department_change ON public.documents;
CREATE TRIGGER documents_guard_department_change
BEFORE UPDATE OF department_id ON public.documents
FOR EACH ROW EXECUTE FUNCTION private.guard_document_department_change();

REVOKE ALL ON FUNCTION private.default_document_department() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.has_document_wide_read_role() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION private.can_access_document(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION private.guard_document_department_change() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION private.has_document_wide_read_role() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION private.can_access_document(uuid) TO authenticated, service_role;

-- Documents: creator/current owner retain access to their workflow items;
-- department members see only their own department; System Admin and Director
-- bypass department filtering for reads when they have document.view.
DROP POLICY IF EXISTS documents_select_authorized ON public.documents;
CREATE POLICY documents_select_authorized ON public.documents
FOR SELECT TO authenticated
USING (private.can_access_document(id));

DROP POLICY IF EXISTS documents_insert_authorized ON public.documents;
CREATE POLICY documents_insert_authorized ON public.documents
FOR INSERT TO authenticated
WITH CHECK (
  created_by = (SELECT auth.uid())
  AND private.has_permission('document.create')
  AND (
    department_id IS NULL
    OR department_id = (
      SELECT pr.department_id FROM public.profiles pr
      WHERE pr.id = (SELECT auth.uid()) AND pr.is_active = true
    )
    OR EXISTS (
      SELECT 1
      FROM public.user_roles ur
      JOIN public.roles r ON r.id = ur.role_id
      WHERE ur.user_id = (SELECT auth.uid()) AND r.code = 'system_admin'
    )
  )
);

DROP POLICY IF EXISTS documents_update_authorized ON public.documents;
CREATE POLICY documents_update_authorized ON public.documents
FOR UPDATE TO authenticated
USING (
  private.can_access_document(id)
  AND (
    created_by = (SELECT auth.uid())
    OR current_owner_id = (SELECT auth.uid())
    OR private.has_permission('document.update')
    OR private.has_permission('document.assign')
    OR private.has_permission('document.approve')
  )
)
WITH CHECK (
  private.can_access_document(id)
  AND (
    created_by = (SELECT auth.uid())
    OR current_owner_id = (SELECT auth.uid())
    OR private.has_permission('document.update')
    OR private.has_permission('document.assign')
    OR private.has_permission('document.approve')
  )
);

-- Child records must inherit the parent document's scope.
DROP POLICY IF EXISTS approvals_select_authorized ON public.approvals;
CREATE POLICY approvals_select_authorized ON public.approvals
FOR SELECT TO authenticated
USING (
  approver_id = (SELECT auth.uid())
  OR private.can_access_document(document_id)
);

DROP POLICY IF EXISTS approvals_insert_authorized ON public.approvals;
CREATE POLICY approvals_insert_authorized ON public.approvals
FOR INSERT TO authenticated
WITH CHECK (
  approver_id = (SELECT auth.uid())
  AND private.has_permission('document.approve')
  AND private.can_access_document(document_id)
);

DROP POLICY IF EXISTS approvals_update_authorized ON public.approvals;
CREATE POLICY approvals_update_authorized ON public.approvals
FOR UPDATE TO authenticated
USING (
  approver_id = (SELECT auth.uid())
  AND private.has_permission('document.approve')
  AND private.can_access_document(document_id)
)
WITH CHECK (
  approver_id = (SELECT auth.uid())
  AND private.has_permission('document.approve')
  AND private.can_access_document(document_id)
);

DROP POLICY IF EXISTS comments_select_authorized ON public.comments;
CREATE POLICY comments_select_authorized ON public.comments
FOR SELECT TO authenticated
USING (private.can_access_document(document_id));

DROP POLICY IF EXISTS comments_insert_own ON public.comments;
CREATE POLICY comments_insert_own ON public.comments
FOR INSERT TO authenticated
WITH CHECK (
  author_id = (SELECT auth.uid())
  AND private.can_access_document(document_id)
);

DROP POLICY IF EXISTS comments_update_own ON public.comments;
CREATE POLICY comments_update_own ON public.comments
FOR UPDATE TO authenticated
USING (author_id = (SELECT auth.uid()) AND private.can_access_document(document_id))
WITH CHECK (author_id = (SELECT auth.uid()) AND private.can_access_document(document_id));

DROP POLICY IF EXISTS assignments_select_authorized ON public.document_assignments;
CREATE POLICY assignments_select_authorized ON public.document_assignments
FOR SELECT TO authenticated
USING (
  assignee_id = (SELECT auth.uid())
  OR assigned_by = (SELECT auth.uid())
  OR private.can_access_document(document_id)
);

DROP POLICY IF EXISTS assignments_insert_authorized ON public.document_assignments;
CREATE POLICY assignments_insert_authorized ON public.document_assignments
FOR INSERT TO authenticated
WITH CHECK (
  assigned_by = (SELECT auth.uid())
  AND private.has_permission('document.assign')
  AND private.can_access_document(document_id)
);

DROP POLICY IF EXISTS assignments_update_authorized ON public.document_assignments;
CREATE POLICY assignments_update_authorized ON public.document_assignments
FOR UPDATE TO authenticated
USING (
  private.can_access_document(document_id)
  AND (
    assignee_id = (SELECT auth.uid())
    OR assigned_by = (SELECT auth.uid())
    OR private.has_permission('document.assign')
  )
)
WITH CHECK (
  private.can_access_document(document_id)
  AND (
    assignee_id = (SELECT auth.uid())
    OR assigned_by = (SELECT auth.uid())
    OR private.has_permission('document.assign')
  )
);

DROP POLICY IF EXISTS document_files_authorized ON public.document_files;
CREATE POLICY document_files_authorized ON public.document_files
FOR SELECT TO authenticated
USING (private.can_access_document(document_id));

DROP POLICY IF EXISTS status_history_select_authorized ON public.document_status_history;
CREATE POLICY status_history_select_authorized ON public.document_status_history
FOR SELECT TO authenticated
USING (private.can_access_document(document_id));

DROP POLICY IF EXISTS deadlines_select_authorized ON public.deadlines;
CREATE POLICY deadlines_select_authorized ON public.deadlines
FOR SELECT TO authenticated
USING (
  assigned_to = (SELECT auth.uid())
  OR private.can_access_document(document_id)
);

DROP POLICY IF EXISTS deadlines_manage_authorized ON public.deadlines;
CREATE POLICY deadlines_manage_authorized ON public.deadlines
FOR ALL TO authenticated
USING (
  private.can_access_document(document_id)
  AND (
    assigned_to = (SELECT auth.uid())
    OR private.has_permission('document.assign')
  )
)
WITH CHECK (
  private.can_access_document(document_id)
  AND (
    assigned_to = (SELECT auth.uid())
    OR private.has_permission('document.assign')
  )
);

-- File metadata is visible only when linked to a document the caller can access.
DROP POLICY IF EXISTS google_drive_files_authorized ON public.google_drive_files;
CREATE POLICY google_drive_files_authorized ON public.google_drive_files
FOR SELECT TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.document_files df
    WHERE df.google_drive_file_id = google_drive_files.id
      AND private.can_access_document(df.document_id)
  )
);

-- Attachments may only be linked to a document the actor can access; do not
-- steal another user's metadata or re-link a file already attached elsewhere.
CREATE OR REPLACE FUNCTION public.attach_document_file_version(
  p_document_id uuid,
  p_google_drive_file_id uuid,
  p_file_role text DEFAULT 'main'
)
RETURNS TABLE(
  id uuid,
  document_id uuid,
  google_drive_file_id uuid,
  file_role text,
  version_no integer,
  is_current boolean,
  uploaded_by uuid,
  uploaded_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
DECLARE
  v_id uuid;
  v_version integer;
  v_file_owner uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='authentication_required';
  END IF;
  IF NOT private.has_permission('document.update')
     OR NOT private.can_access_document(p_document_id) THEN
    RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='insufficient_privilege';
  END IF;
  IF p_file_role IS NULL OR btrim(p_file_role) = '' THEN
    RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='file_role_required';
  END IF;

  SELECT gdf.created_by INTO v_file_owner
  FROM public.google_drive_files gdf
  WHERE gdf.id = p_google_drive_file_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='google_drive_file_not_found';
  END IF;
  IF v_file_owner IS NOT NULL AND v_file_owner <> auth.uid() THEN
    RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='file_not_owned_by_actor';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.document_files df
    WHERE df.google_drive_file_id = p_google_drive_file_id
      AND df.document_id <> p_document_id
  ) THEN
    RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='file_already_linked_to_another_document';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(p_document_id::text || ':' || p_file_role, 0));
  SELECT coalesce(max(df.version_no), 0) + 1 INTO v_version
  FROM public.document_files df
  WHERE df.document_id = p_document_id AND df.file_role = p_file_role;

  UPDATE public.document_files
  SET is_current = false
  WHERE document_id = p_document_id AND file_role = p_file_role AND is_current = true;

  UPDATE public.google_drive_files
  SET created_by = coalesce(created_by, auth.uid())
  WHERE id = p_google_drive_file_id;

  INSERT INTO public.document_files(
    document_id, google_drive_file_id, file_role, version_no, is_current, uploaded_by
  )
  VALUES (p_document_id, p_google_drive_file_id, p_file_role, v_version, true, auth.uid())
  RETURNING document_files.id INTO v_id;

  RETURN QUERY
  SELECT df.id, df.document_id, df.google_drive_file_id, df.file_role,
         df.version_no, df.is_current, df.uploaded_by, df.uploaded_at
  FROM public.document_files df WHERE df.id = v_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.attach_document_file_version(uuid, uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.attach_document_file_version(uuid, uuid, text) TO authenticated, service_role;

-- Incoming/outgoing detail rows contain document content too; registry role alone
-- must not bypass the parent document's department scope.
DROP POLICY IF EXISTS incoming_details_select_authorized ON public.incoming_document_details;
CREATE POLICY incoming_details_select_authorized ON public.incoming_document_details
FOR SELECT TO authenticated
USING (private.can_access_document(document_id));

DROP POLICY IF EXISTS incoming_details_insert_registry ON public.incoming_document_details;
CREATE POLICY incoming_details_insert_registry ON public.incoming_document_details
FOR INSERT TO authenticated
WITH CHECK (
  private.has_permission('registry.incoming.manage')
  AND private.can_access_document(document_id)
);

DROP POLICY IF EXISTS incoming_details_update_registry ON public.incoming_document_details;
CREATE POLICY incoming_details_update_registry ON public.incoming_document_details
FOR UPDATE TO authenticated
USING (
  private.has_permission('registry.incoming.manage')
  AND private.can_access_document(document_id)
)
WITH CHECK (
  private.has_permission('registry.incoming.manage')
  AND private.can_access_document(document_id)
);

DROP POLICY IF EXISTS outgoing_details_select_authorized ON public.outgoing_document_details;
CREATE POLICY outgoing_details_select_authorized ON public.outgoing_document_details
FOR SELECT TO authenticated
USING (private.can_access_document(document_id));

DROP POLICY IF EXISTS outgoing_details_insert_registry ON public.outgoing_document_details;
CREATE POLICY outgoing_details_insert_registry ON public.outgoing_document_details
FOR INSERT TO authenticated
WITH CHECK (
  private.has_permission('registry.outgoing.manage')
  AND private.can_access_document(document_id)
);

DROP POLICY IF EXISTS outgoing_details_update_registry ON public.outgoing_document_details;
CREATE POLICY outgoing_details_update_registry ON public.outgoing_document_details
FOR UPDATE TO authenticated
USING (
  private.has_permission('registry.outgoing.manage')
  AND private.can_access_document(document_id)
)
WITH CHECK (
  private.has_permission('registry.outgoing.manage')
  AND private.can_access_document(document_id)
);

COMMIT;
