BEGIN;

SELECT plan(5);

SELECT ok(
  to_regprocedure('public.detach_document_file(uuid)') IS NOT NULL,
  'detach RPC exists'
);

SELECT ok(
  (SELECT p.prosecdef
   FROM pg_proc p
   WHERE p.oid = to_regprocedure('public.detach_document_file(uuid)')),
  'detach RPC uses SECURITY DEFINER for controlled row deletion'
);

SELECT ok(
  has_function_privilege('authenticated', 'public.detach_document_file(uuid)', 'EXECUTE'),
  'authenticated users can call the guarded detach RPC'
);

SELECT ok(
  NOT has_function_privilege('anon', 'public.detach_document_file(uuid)', 'EXECUTE'),
  'anonymous users cannot call the detach RPC'
);

SELECT ok(
  position('private.has_permission' IN pg_get_functiondef(
    to_regprocedure('public.detach_document_file(uuid)')
  )) > 0
  AND position('private.can_access_document' IN pg_get_functiondef(
    to_regprocedure('public.detach_document_file(uuid)')
  )) > 0,
  'detach RPC checks permission and document scope'
);

SELECT * FROM finish();
ROLLBACK;
