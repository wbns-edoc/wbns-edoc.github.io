-- Executable structural/security regression checks for the responsibility-settings draft.
-- Run only after applying 20261022130000_school_responsibility_assignments_draft.sql
-- to an isolated test database. This does not replace authenticated RPC integration tests.
begin;

do $test$
declare
  v_name text;
  v_rls boolean;
begin
  if to_regclass('public.school_responsibility_assignments') is null
     or to_regclass('public.school_responsibility_settings') is null
     or to_regclass('public.school_responsibility_audit') is null then
    raise exception 'responsibility_tables_missing';
  end if;

  foreach v_name in array array[
    'school_responsibility_assignments',
    'school_responsibility_settings',
    'school_responsibility_audit'
  ] loop
    select c.relrowsecurity into v_rls
      from pg_class c where c.oid=to_regclass('public.'||v_name);
    if v_rls is distinct from true then
      raise exception 'rls_not_enabled_on_%',v_name;
    end if;
  end loop;

  if not exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='school_responsibility_audit'
      and column_name='previous_has_vice_director' and data_type='boolean'
  ) or not exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='school_responsibility_audit'
      and column_name='new_has_vice_director' and data_type='boolean'
  ) then raise exception 'vice_director_setting_audit_columns_missing'; end if;

  if has_table_privilege('anon','public.school_responsibility_assignments','SELECT')
     or has_table_privilege('authenticated','public.school_responsibility_assignments','SELECT')
     or has_table_privilege('anon','public.school_responsibility_settings','SELECT')
     or has_table_privilege('authenticated','public.school_responsibility_settings','SELECT')
     or has_table_privilege('anon','public.school_responsibility_audit','SELECT')
     or has_table_privilege('authenticated','public.school_responsibility_audit','SELECT') then
    raise exception 'direct_table_read_privilege_unexpected';
  end if;

  if not has_function_privilege('authenticated','public.admin_get_school_responsibilities()','EXECUTE')
     or not has_function_privilege('authenticated','public.admin_save_school_responsibilities(jsonb,boolean)','EXECUTE') then
    raise exception 'authenticated_rpc_grant_missing';
  end if;
  if has_function_privilege('anon','public.admin_get_school_responsibilities()','EXECUTE')
     or has_function_privilege('anon','public.admin_save_school_responsibilities(jsonb,boolean)','EXECUTE')
     or has_function_privilege('public','public.admin_get_school_responsibilities()','EXECUTE')
     or has_function_privilege('public','public.admin_save_school_responsibilities(jsonb,boolean)','EXECUTE') then
    raise exception 'rpc_execute_grant_too_broad';
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid='public.school_responsibility_assignments'::regclass
      and contype='c'
      and pg_get_constraintdef(oid) like '%director%'
      and pg_get_constraintdef(oid) like '%general_head%'
  ) then raise exception 'responsibility_key_constraint_missing'; end if;

  if not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname='admin_save_school_responsibilities'
      and pg_get_functiondef(p.oid) like '%system_admin_required%'
      and pg_get_functiondef(p.oid) like '%assigned_user_missing_or_inactive%'
      and pg_get_functiondef(p.oid) like '%active_director_required%'
      and pg_get_functiondef(p.oid) like '%active_vice_director_required%'
  ) then raise exception 'server_side_validation_missing'; end if;
end
$test$;

rollback;
