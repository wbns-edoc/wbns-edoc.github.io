BEGIN;
SELECT plan(27);

SELECT has_column('public', 'documents', 'department_id',
  'documents has a department scope column');

SELECT has_function('private', 'can_access_document', ARRAY['uuid'],
  'document access is centralized in a scoped helper');

SELECT has_function('private', 'has_document_wide_read_role', ARRAY[]::text[],
  'only the explicit schoolwide reader roles have a scope bypass');

SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgrelid = 'public.documents'::regclass
      AND tgname = 'documents_default_department'
      AND NOT tgisinternal
  ),
  'new documents default to the creator profile department'
);

SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgrelid = 'public.documents'::regclass
      AND tgname = 'documents_guard_department_change'
      AND NOT tgisinternal
  ),
  'department changes are guarded separately from document editing'
);

SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_policy
    WHERE polrelid = 'public.documents'::regclass
      AND polname = 'documents_select_authorized'
      AND pg_get_expr(polqual, polrelid) LIKE '%can_access_document%'
  ),
  'document reads use the scoped access helper'
);

SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_policy
    WHERE polrelid = 'public.documents'::regclass
      AND polname = 'documents_insert_authorized'
      AND pg_get_expr(polwithcheck, polrelid) LIKE '%department_id%'
  ),
  'document creation is restricted to the actor department or System Admin'
);

SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_policy
    WHERE polrelid = 'public.documents'::regclass
      AND polname = 'documents_update_authorized'
      AND pg_get_expr(polqual, polrelid) LIKE '%can_access_document%'
  ),
  'document edits must pass scoped access'
);

SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_policy
    WHERE polrelid = 'public.document_files'::regclass
      AND polname = 'document_files_authorized'
      AND pg_get_expr(polqual, polrelid) LIKE '%can_access_document%'
  ),
  'file links inherit parent document scope'
);

SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_policy
    WHERE polrelid = 'public.document_status_history'::regclass
      AND polname = 'status_history_select_authorized'
      AND pg_get_expr(polqual, polrelid) LIKE '%can_access_document%'
  ),
  'status history inherits parent document scope'
);

SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_policy
    WHERE polrelid = 'public.comments'::regclass
      AND polname = 'comments_select_authorized'
      AND pg_get_expr(polqual, polrelid) LIKE '%can_access_document%'
  ),
  'comments inherit parent document scope'
);

SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_policy
    WHERE polrelid = 'public.approvals'::regclass
      AND polname = 'approvals_select_authorized'
      AND pg_get_expr(polqual, polrelid) LIKE '%can_access_document%'
  ),
  'approval records inherit parent document scope'
);

SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_policy
    WHERE polrelid = 'public.google_drive_files'::regclass
      AND polname = 'google_drive_files_authorized'
      AND pg_get_expr(polqual, polrelid) LIKE '%document_files%'
  ),
  'Drive metadata is only visible when linked to an accessible document'
);

SELECT ok(
  position('private.can_access_document' IN pg_get_functiondef(
    'public.attach_document_file_version(uuid,uuid,text)'::regprocedure
  )) > 0,
  'attachment RPC checks document scope'
);

SELECT ok(
  position('file_already_linked_to_another_document' IN pg_get_functiondef(
    'public.attach_document_file_version(uuid,uuid,text)'::regprocedure
  )) > 0,
  'attachment RPC blocks linking a file to a different document'
);

SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_policy
    WHERE polrelid = 'public.incoming_document_details'::regclass
      AND polname = 'incoming_details_select_authorized'
      AND pg_get_expr(polqual, polrelid) LIKE '%can_access_document%'
  ),
  'incoming document details inherit parent document scope'
);

SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_policy
    WHERE polrelid = 'public.outgoing_document_details'::regclass
      AND polname = 'outgoing_details_select_authorized'
      AND pg_get_expr(polqual, polrelid) LIKE '%can_access_document%'
  ),
  'outgoing document details inherit parent document scope'
);

SELECT ok(
  position('private.can_access_document' IN pg_get_functiondef(
    'private.assign_document(uuid,uuid,text,timestamp with time zone)'::regprocedure
  )) > 0,
  'assignment RPC enforces document scope'
);

SELECT ok(
  position('cross_department_assignment_denied' IN pg_get_functiondef(
    'private.assign_document(uuid,uuid,text,timestamp with time zone)'::regprocedure
  )) > 0,
  'assignment RPC blocks cross-department assignment without System Admin'
);

SELECT ok(
  position('private.can_access_document' IN pg_get_functiondef(
    'private.update_document_status(uuid,public.document_status,text)'::regprocedure
  )) > 0,
  'status mutation RPC enforces document scope'
);


SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'register_incoming_document'
      AND p.pronargs = 8 AND 'p_department_id' = ANY(p.proargnames)
  ),
  'incoming registration exposes an explicit department argument'
);

SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'register_outgoing_document'
      AND p.pronargs = 7 AND 'p_department_id' = ANY(p.proargnames)
  ),
  'outgoing registration exposes an explicit department argument'
);

SELECT ok(
  position('active_document_department_required' IN pg_get_functiondef(
    'private.register_incoming_document(text,uuid,text,date,timestamp with time zone,urgency_level,text,uuid)'::regprocedure
  )) > 0
  AND position('department_id' IN pg_get_functiondef(
    'private.register_incoming_document(text,uuid,text,date,timestamp with time zone,urgency_level,text,uuid)'::regprocedure
  )) > 0,
  'incoming registration validates and persists the selected active department'
);

SELECT ok(
  position('active_document_department_required' IN pg_get_functiondef(
    'private.register_outgoing_document(text,text,text,text,date,urgency_level,uuid)'::regprocedure
  )) > 0
  AND position('department_id' IN pg_get_functiondef(
    'private.register_outgoing_document(text,text,text,text,date,urgency_level,uuid)'::regprocedure
  )) > 0,
  'outgoing registration validates and persists the selected active department'
);

SELECT ok(
  position('document_department_required' IN pg_get_functiondef(
    'private.register_incoming_document(text,uuid,text,date,timestamp with time zone,urgency_level,text)'::regprocedure
  )) > 0
  AND position('document_department_required' IN pg_get_functiondef(
    'private.register_outgoing_document(text,text,text,text,date,urgency_level)'::regprocedure
  )) > 0,
  'legacy registration signatures fail closed when the actor has no department'
);


SELECT ok(
  NOT has_function_privilege('anon', 'public.register_incoming_document(text,uuid,text,date,timestamp with time zone,urgency_level,text)'::regprocedure, 'EXECUTE')
  AND NOT has_function_privilege('anon', 'public.register_outgoing_document(text,text,text,text,date,urgency_level)'::regprocedure, 'EXECUTE')
  AND NOT has_function_privilege('anon', 'public.register_incoming_document(text,uuid,text,date,timestamp with time zone,urgency_level,text,uuid)'::regprocedure, 'EXECUTE')
  AND NOT has_function_privilege('anon', 'public.register_outgoing_document(text,text,text,text,date,urgency_level,uuid)'::regprocedure, 'EXECUTE'),
  'anonymous role cannot execute any document registration RPC'
);

SELECT ok(
  has_function_privilege('authenticated', 'public.register_incoming_document(text,uuid,text,date,timestamp with time zone,urgency_level,text,uuid)'::regprocedure, 'EXECUTE')
  AND has_function_privilege('authenticated', 'public.register_outgoing_document(text,text,text,text,date,urgency_level,uuid)'::regprocedure, 'EXECUTE'),
  'authenticated users can call the explicit-department registration RPCs'
);

SELECT * FROM finish();
ROLLBACK;
