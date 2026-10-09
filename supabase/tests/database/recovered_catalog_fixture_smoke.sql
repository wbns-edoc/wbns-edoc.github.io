begin;
select plan(6);

select ok(to_regclass('public.documents') is not null,
  'documents table exists in recovered catalog');
select ok((select count(*) from pg_tables where schemaname = 'public') = 22,
  'recovered public base-table count matches the observed catalog');
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
