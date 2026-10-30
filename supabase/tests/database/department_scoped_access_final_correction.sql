BEGIN;
SELECT plan(12);

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
  AND position('document.approve' IN pg_get_functiondef('private.has_department_permission(text,uuid)'::regprocedure)) > 0
  AND position('document.assign' IN pg_get_functiondef('private.has_department_permission(text,uuid)'::regprocedure)) > 0,
  'System Admin and director retain explicit read, create, update, approve and assign permissions'
);

SELECT ok(
  position('JOIN public.departments d' IN pg_get_functiondef('private.has_department_permission(text,uuid)'::regprocedure)) > 0
  AND position('d.is_active = true' IN pg_get_functiondef('private.has_department_permission(text,uuid)'::regprocedure)) > 0,
  'department-scoped permissions require the target department to remain active'
);

SELECT ok(
  position('wr.code = ''deputy_director''' IN pg_get_functiondef('private.has_department_permission(text,uuid)'::regprocedure)) > 0
  AND position('p_permission = ''document.assign''' IN pg_get_functiondef('private.has_department_permission(text,uuid)'::regprocedure)) > 0,
  'Vice Director retains the existing global document.assign exception'
);

SELECT ok(
  position('child.parent_id=d.department_id' IN pg_get_functiondef('private.can_access_document(uuid)'::regprocedure)) > 0,
  'read inheritance is only from child department to its direct parent'
);

SELECT ok(
  position('private.user_has_department(pr.id,d.department_id)' IN pg_get_functiondef('private.can_access_document(uuid)'::regprocedure)) > 0,
  'ordinary direct-department access remains explicitly membership scoped'
);

SELECT ok(
  position('private.has_department_permission(' IN pg_get_functiondef('private.create_approval(uuid,uuid,integer)'::regprocedure)) > 0,
  'approval creation checks department-scoped approval permission'
);

SELECT ok(
  position('approver_not_authorized' IN pg_get_functiondef('private.create_approval(uuid,uuid,integer)'::regprocedure)) > 0,
  'approval creation rejects approvers without authorization in the document department'
);

SELECT ok(
  position('JOIN public.user_departments ud' IN pg_get_functiondef('private.create_approval(uuid,uuid,integer)'::regprocedure)) > 0
  AND position('dept.is_active=true' IN pg_get_functiondef('private.create_approval(uuid,uuid,integer)'::regprocedure)) > 0,
  'approver selection requires current membership in an active department'
);

SELECT ok(
  position('a.approver_id=v_actor' IN pg_get_functiondef('private.decide_approval(uuid,public.approval_decision,text)'::regprocedure)) > 0
  AND position('private.has_department_permission(' IN pg_get_functiondef('private.decide_approval(uuid,public.approval_decision,text)'::regprocedure)) > 0,
  'approval decisions require the assigned approver and department-scoped approval permission'
);

SELECT * FROM finish();
ROLLBACK;
