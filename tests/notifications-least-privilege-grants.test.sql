do $assert$
declare
  v_column text;
begin
  if not (select relrowsecurity from pg_class where oid = 'public.notifications'::regclass) then
    raise exception 'notifications RLS must remain enabled';
  end if;
  if not has_table_privilege('authenticated', 'public.notifications', 'SELECT') then
    raise exception 'authenticated must retain SELECT subject to RLS';
  end if;
  if not has_column_privilege('authenticated', 'public.notifications', 'read_at', 'UPDATE') then
    raise exception 'authenticated must update read_at';
  end if;
  if has_table_privilege('authenticated', 'public.notifications', 'INSERT')
     or has_table_privilege('authenticated', 'public.notifications', 'DELETE')
     or has_table_privilege('authenticated', 'public.notifications', 'UPDATE')
     or has_table_privilege('authenticated', 'public.notifications', 'TRUNCATE')
     or has_table_privilege('authenticated', 'public.notifications', 'REFERENCES')
     or has_table_privilege('authenticated', 'public.notifications', 'TRIGGER')
     or has_table_privilege('authenticated', 'public.notifications', 'MAINTAIN') then
    raise exception 'authenticated has an unintended table-level privilege';
  end if;

  for v_column in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'public.notifications'::regclass
      and a.attnum > 0 and not a.attisdropped
  loop
    if v_column <> 'read_at'
       and has_column_privilege('authenticated', 'public.notifications', v_column, 'UPDATE') then
      raise exception 'authenticated must not UPDATE column %', v_column;
    end if;
    if has_column_privilege('anon', 'public.notifications', v_column, 'SELECT')
       or has_column_privilege('anon', 'public.notifications', v_column, 'INSERT')
       or has_column_privilege('anon', 'public.notifications', v_column, 'UPDATE')
       or has_column_privilege('anon', 'public.notifications', v_column, 'REFERENCES') then
      raise exception 'anon has an unintended column privilege on %', v_column;
    end if;
  end loop;

  if has_table_privilege('anon', 'public.notifications', 'SELECT')
     or has_table_privilege('anon', 'public.notifications', 'INSERT')
     or has_table_privilege('anon', 'public.notifications', 'UPDATE')
     or has_table_privilege('anon', 'public.notifications', 'DELETE')
     or has_table_privilege('anon', 'public.notifications', 'TRUNCATE')
     or has_table_privilege('anon', 'public.notifications', 'REFERENCES')
     or has_table_privilege('anon', 'public.notifications', 'TRIGGER')
     or has_table_privilege('anon', 'public.notifications', 'MAINTAIN') then
    raise exception 'anon has an unintended table-level privilege';
  end if;

  if not exists (
    select 1 from pg_catalog.pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public' and tablename = 'notifications'
  ) then
    raise exception 'notifications must be published to supabase_realtime';
  end if;
end;
$assert$;
