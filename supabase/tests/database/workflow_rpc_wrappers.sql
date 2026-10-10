begin;
select plan(9);

select ok(
  (select not prosecdef from pg_proc where oid = 'public.assign_document(uuid,uuid,text,timestamp with time zone)'::regprocedure),
  'assign_document public wrapper is SECURITY INVOKER'
);
select ok(
  (select not prosecdef from pg_proc where oid = 'public.set_document_deadline(uuid,uuid,timestamp with time zone,timestamp with time zone)'::regprocedure),
  'set_document_deadline public wrapper is SECURITY INVOKER'
);
select ok(
  (select not prosecdef from pg_proc where oid = 'public.update_document_status(uuid,public.document_status,text)'::regprocedure),
  'update_document_status public wrapper is SECURITY INVOKER'
);

select ok(
  has_function_privilege('authenticated', 'public.assign_document(uuid,uuid,text,timestamp with time zone)', 'EXECUTE'),
  'authenticated can execute assign_document'
);
select ok(
  has_function_privilege('authenticated', 'public.set_document_deadline(uuid,uuid,timestamp with time zone,timestamp with time zone)', 'EXECUTE'),
  'authenticated can execute set_document_deadline'
);
select ok(
  has_function_privilege('authenticated', 'public.update_document_status(uuid,public.document_status,text)', 'EXECUTE'),
  'authenticated can execute update_document_status'
);

select ok(
  not has_function_privilege('anon', 'public.assign_document(uuid,uuid,text,timestamp with time zone)', 'EXECUTE'),
  'anon cannot execute assign_document'
);
select ok(
  not has_function_privilege('anon', 'public.set_document_deadline(uuid,uuid,timestamp with time zone,timestamp with time zone)', 'EXECUTE'),
  'anon cannot execute set_document_deadline'
);
select ok(
  not has_function_privilege('anon', 'public.update_document_status(uuid,public.document_status,text)', 'EXECUTE'),
  'anon cannot execute update_document_status'
);

select * from finish();
rollback;
