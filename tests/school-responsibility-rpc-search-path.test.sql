\set ON_ERROR_STOP on
begin;

do $assert_search_path$
declare
  v_get text[];
  v_save text[];
begin
  select p.proconfig into v_get
  from pg_proc p
  where p.oid='public.admin_get_school_responsibilities()'::regprocedure;
  select p.proconfig into v_save
  from pg_proc p
  where p.oid='public.admin_save_school_responsibilities(jsonb,boolean)'::regprocedure;

  if not ('search_path=pg_catalog, public'=any(coalesce(v_get,array[]::text[]))) then
    raise exception 'admin_get_school_responsibilities_search_path_not_pinned: %',v_get;
  end if;
  if not ('search_path=pg_catalog, public'=any(coalesce(v_save,array[]::text[]))) then
    raise exception 'admin_save_school_responsibilities_search_path_not_pinned: %',v_save;
  end if;
end
$assert_search_path$;

rollback;
