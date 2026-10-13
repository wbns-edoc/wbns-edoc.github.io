begin;
select plan(6);

select ok(to_regclass('public.documents') is not null,
  'documents table exists in recovered catalog');
select ok((
  select count(*)
  from pg_tables
  where schemaname = 'public'
    and tablename = any (array[
      'approvals', 'audit_logs', 'comments', 'deadlines', 'departments',
      'document_assignments', 'document_files', 'document_registers',
      'document_status_history', 'documents', 'google_drive_files',
      'incoming_document_details', 'notifications', 'number_sequences',
      'outgoing_document_details', 'permissions', 'profiles',
      'push_subscriptions', 'role_permissions', 'roles', 'senders', 'user_roles'
    ])
) = 22, 'all 22 observed recovered catalog base tables exist');
select ok((select relrowsecurity from pg_class where oid = 'public.documents'::regclass),
  'documents RLS is enabled');
select ok((select count(*) from pg_policies where schemaname = 'public') = 45,
  'recovered public policy count matches the observed catalog');
select ok(to_regprocedure('public.assign_document(uuid,uuid,text,timestamp with time zone)') is not null,
  'workflow assignment RPC is present');
select ok((select count(*) from public.roles) = 7,
  'only system reference roles are seeded');

select * from finish();
rollback;
