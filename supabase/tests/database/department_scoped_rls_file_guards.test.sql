BEGIN;
SELECT plan(9);

SELECT ok(
  position('private.can_access_document(p_document_id)' in pg_get_functiondef('public.attach_document_file_version(uuid,uuid,text)'::regprocedure)) > 0,
  'file attachment requires document-scoped access'
);
SELECT ok(
  position('private.has_department_permission(' in pg_get_functiondef('public.attach_document_file_version(uuid,uuid,text)'::regprocedure)) > 0,
  'file attachment requires department-scoped update permission'
);
SELECT ok(
  position('private.can_access_document(document_id)' in pg_get_expr(
    (SELECT polqual FROM pg_policy WHERE polname='comments_select_authorized' AND polrelid='public.comments'::regclass), 'public.comments'::regclass
  )) > 0,
  'comments are visible only with parent document access'
);
SELECT ok(
  position('private.can_access_document(document_id)' in pg_get_expr(
    (SELECT polqual FROM pg_policy WHERE polname='document_files_authorized' AND polrelid='public.document_files'::regclass), 'public.document_files'::regclass
  )) > 0,
  'file metadata is visible only with parent document access'
);
SELECT ok(
  position('private.can_access_document(id)' in pg_get_expr(
    (SELECT polqual FROM pg_policy WHERE polname='documents_select_authorized' AND polrelid='public.documents'::regclass), 'public.documents'::regclass
  )) > 0,
  'document reads use the scoped access helper'
);
SELECT ok(
  position('private.has_department_permission(' in pg_get_expr(
    (SELECT polwithcheck FROM pg_policy WHERE polname='documents_insert_authorized' AND polrelid='public.documents'::regclass), 'public.documents'::regclass
  )) > 0,
  'document creation requires department-scoped permission'
);

SELECT ok(
  position('private.has_department_permission(' in pg_get_expr(
    (SELECT polqual FROM pg_policy WHERE polname='documents_update_authorized' AND polrelid='public.documents'::regclass), 'public.documents'::regclass
  )) > 0,
  'document updates require department-scoped edit permission'
);
SELECT ok(
  position('document.approve' in pg_get_expr(
    (SELECT polqual FROM pg_policy WHERE polname='documents_update_authorized' AND polrelid='public.documents'::regclass), 'public.documents'::regclass
  )) = 0
  AND position('document.assign' in pg_get_expr(
    (SELECT polqual FROM pg_policy WHERE polname='documents_update_authorized' AND polrelid='public.documents'::regclass), 'public.documents'::regclass
  )) = 0,
  'approval and assignment permissions do not implicitly grant document edits'
);

SELECT ok(
  position('JOIN public.user_departments ud' in pg_get_functiondef(
    'private.has_department_permission(text,uuid)'::regprocedure
  )) > 0,
  'scoped role grants require current department membership'
);

SELECT * FROM finish();
ROLLBACK;
