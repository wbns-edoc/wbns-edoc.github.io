do $assert$
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
  if has_table_privilege('authenticated', 'public.notifications', 'INSERT') then
    raise exception 'authenticated must not INSERT notifications directly';
  end if;
  if has_table_privilege('authenticated', 'public.notifications', 'DELETE') then
    raise exception 'authenticated must not DELETE notifications';
  end if;
  if has_column_privilege('authenticated', 'public.notifications', 'title', 'UPDATE') then
    raise exception 'authenticated must not update notification content';
  end if;
  if has_table_privilege('anon', 'public.notifications', 'SELECT') then
    raise exception 'anon must not SELECT notifications';
  end if;
  if has_table_privilege('anon', 'public.notifications', 'INSERT') then
    raise exception 'anon must not INSERT notifications';
  end if;
  if has_table_privilege('anon', 'public.notifications', 'UPDATE') then
    raise exception 'anon must not UPDATE notifications';
  end if;
end;
$assert$;
