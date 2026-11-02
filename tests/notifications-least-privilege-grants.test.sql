begin;
select plan(9);

select ok(
  (select relrowsecurity from pg_class where oid = 'public.notifications'::regclass),
  'notifications RLS remains enabled'
);
select ok(has_table_privilege('authenticated', 'public.notifications', 'SELECT'),
  'authenticated can read notifications subject to RLS');
select ok(has_column_privilege('authenticated', 'public.notifications', 'read_at', 'UPDATE'),
  'authenticated can update read_at to mark notifications read');
select ok(not has_table_privilege('authenticated', 'public.notifications', 'INSERT'),
  'authenticated cannot insert notifications directly');
select ok(not has_table_privilege('authenticated', 'public.notifications', 'DELETE'),
  'authenticated cannot delete notifications');
select ok(not has_column_privilege('authenticated', 'public.notifications', 'title', 'UPDATE'),
  'authenticated cannot modify notification content');
select ok(not has_table_privilege('anon', 'public.notifications', 'SELECT'),
  'anon cannot read notifications');
select ok(not has_table_privilege('anon', 'public.notifications', 'INSERT'),
  'anon cannot insert notifications');
select ok(not has_table_privilege('anon', 'public.notifications', 'UPDATE'),
  'anon cannot update notifications');

select * from finish();
rollback;
