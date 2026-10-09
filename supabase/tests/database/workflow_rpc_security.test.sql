begin;

select plan(15);

-- Public RPCs must be invoker wrappers, not SECURITY DEFINER endpoints.
select ok(
  (select not p.prosecdef from pg_proc p where p.oid = to_regprocedure('public.assign_document(uuid,uuid,text,timestamptz)')),
  'public.assign_document is SECURITY INVOKER'
);
select ok(
  (select not p.prosecdef from pg_proc p where p.oid = to_regprocedure('public.update_document_status(uuid,public.document_status,text)')),
  'public.update_document_status is SECURITY INVOKER'
);
select ok(
  (select not p.prosecdef from pg_proc p where p.oid = to_regprocedure('public.set_document_deadline(uuid,uuid,timestamptz,timestamptz)')),
  'public.set_document_deadline is SECURITY INVOKER'
);
select ok(
  (select not p.prosecdef from pg_proc p where p.oid = to_regprocedure('public.create_approval(uuid,uuid,integer)')),
  'public.create_approval is SECURITY INVOKER'
);
select ok(
  (select not p.prosecdef from pg_proc p where p.oid = to_regprocedure('public.decide_approval(uuid,public.approval_decision,text)')),
  'public.decide_approval is SECURITY INVOKER'
);

-- Anonymous callers must not inherit EXECUTE through PUBLIC.
select ok(not has_function_privilege('anon', 'public.assign_document(uuid,uuid,text,timestamptz)', 'EXECUTE'), 'anon cannot execute assign_document');
select ok(not has_function_privilege('anon', 'public.update_document_status(uuid,public.document_status,text)', 'EXECUTE'), 'anon cannot execute update_document_status');
select ok(not has_function_privilege('anon', 'public.set_document_deadline(uuid,uuid,timestamptz,timestamptz)', 'EXECUTE'), 'anon cannot execute set_document_deadline');
select ok(not has_function_privilege('anon', 'public.create_approval(uuid,uuid,integer)', 'EXECUTE'), 'anon cannot execute create_approval');
select ok(not has_function_privilege('anon', 'public.decide_approval(uuid,public.approval_decision,text)', 'EXECUTE'), 'anon cannot execute decide_approval');

-- Signed-in callers retain the public API grants; function bodies must still enforce permissions.
select ok(has_function_privilege('authenticated', 'public.assign_document(uuid,uuid,text,timestamptz)', 'EXECUTE'), 'authenticated can execute assign_document');
select ok(has_function_privilege('authenticated', 'public.update_document_status(uuid,public.document_status,text)', 'EXECUTE'), 'authenticated can execute update_document_status');
select ok(has_function_privilege('authenticated', 'public.set_document_deadline(uuid,uuid,timestamptz,timestamptz)', 'EXECUTE'), 'authenticated can execute set_document_deadline');
select ok(has_function_privilege('authenticated', 'public.create_approval(uuid,uuid,integer)', 'EXECUTE'), 'authenticated can execute create_approval');
select ok(has_function_privilege('authenticated', 'public.decide_approval(uuid,public.approval_decision,text)', 'EXECUTE'), 'authenticated can execute decide_approval');

select * from finish();
rollback;
