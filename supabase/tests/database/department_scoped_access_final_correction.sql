BEGIN;
SELECT plan(5);

SELECT ok(
  position('has_document_wide_read_role' IN pg_get_functiondef('private.can_access_document(uuid)'::regprocedure)) = 0,
  'scoped access helper does not depend on an optional legacy helper'
);

SELECT ok(
  position('system_admin' IN pg_get_functiondef('private.can_access_document(uuid)'::regprocedure)) > 0
  AND position('director' IN pg_get_functiondef('private.can_access_document(uuid)'::regprocedure)) > 0,
  'System Admin and director have explicit schoolwide document read'
);

SELECT ok(
  position('document.view' IN pg_get_functiondef('private.has_department_permission(text,uuid)'::regprocedure)) > 0
  AND position('document.create' IN pg_get_functiondef('private.has_department_permission(text,uuid)'::regprocedure)) > 0
  AND position('document.update' IN pg_get_functiondef('private.has_department_permission(text,uuid)'::regprocedure)) > 0
  AND position('document.approve' IN pg_get_functiondef('private.has_department_permission(text,uuid)'::regprocedure)) > 0,
  'global roles have explicit read, create, update and approve permissions'
);

SELECT ok(
  position('child.parent_id=d.department_id' IN pg_get_functiondef('private.can_access_document(uuid)'::regprocedure)) > 0,
  'read inheritance is only from child department to its direct parent'
);

SELECT ok(
  position('private.user_has_department(pr.id,d.department_id)' IN pg_get_functiondef('private.can_access_document(uuid)'::regprocedure)) > 0,
  'ordinary direct-department access remains explicitly membership scoped'
);

SELECT * FROM finish();
ROLLBACK;
