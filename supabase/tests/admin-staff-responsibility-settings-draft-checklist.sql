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
     or exists (
       select 1
       from pg_proc p
       cross join lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) acl
       where p.oid in (
         'public.admin_get_school_responsibilities()'::regprocedure,
         'public.admin_save_school_responsibilities(jsonb,boolean)'::regprocedure
       )
       and acl.grantee=0 and acl.privilege_type='EXECUTE'
     ) then
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


-- RPC integration checks with disposable identities. All data is rolled back below.
do $rpc_test$
declare
  v_admin uuid := '00000000-0000-0000-0000-000000000001';
  v_staff uuid := '00000000-0000-0000-0000-000000000002';
  v_director uuid := '00000000-0000-0000-0000-000000000003';
  v_vice uuid := '00000000-0000-0000-0000-000000000004';
  v_inactive uuid := '00000000-0000-0000-0000-000000000005';
  v_role uuid := '00000000-0000-0000-0000-000000000011';
  v_result jsonb;
  v_rejected boolean;
begin
  insert into public.profiles(id,full_name,email,employee_code,is_active) values
    (v_admin,'CI System Admin','admin@example.invalid','CI001',true),
    (v_staff,'CI Staff','staff@example.invalid','CI002',true),
    (v_director,'CI Director','director@example.invalid','CI003',true),
    (v_vice,'CI Vice Director','vice@example.invalid','CI004',true),
    (v_inactive,'CI Inactive','inactive@example.invalid','CI005',false);
  insert into public.roles(id,code,name) values(v_role,'system_admin','System Admin');
  insert into public.user_roles(user_id,role_id) values(v_admin,v_role);

  perform set_config('request.jwt.claim.sub',v_staff::text,true);
  v_rejected := false;
  begin
    perform public.admin_get_school_responsibilities();
  exception when others then
    if sqlerrm = 'system_admin_required' then v_rejected := true; else raise; end if;
  end;
  if not v_rejected then raise exception 'non_admin_rpc_access_not_rejected'; end if;

  perform set_config('request.jwt.claim.sub',v_admin::text,true);
  v_result := public.admin_save_school_responsibilities(
    jsonb_build_object('director',v_director::text,
      'vice_director','','personnel_head','','budget_head','',
      'academic_head','','general_head',''),false);
  if (v_result->>'has_vice_director')::boolean is distinct from false then
    raise exception 'vice_director_optional_setting_not_saved';
  end if;
  if not exists(select 1 from public.school_responsibility_audit
      where responsibility_key='director' and new_user_id=v_director
        and actor_user_id=v_admin and change_kind='assignment_changed') then
    raise exception 'assignment_audit_missing';
  end if;

  v_rejected := false;
  begin
    perform public.admin_save_school_responsibilities(
      jsonb_build_object('director',v_director::text,'vice_director','','personnel_head','',
        'budget_head','','academic_head','','general_head',''),true);
  exception when others then
    if sqlerrm = 'active_vice_director_required' then v_rejected := true; else raise; end if;
  end;
  if not v_rejected then raise exception 'missing_vice_director_not_rejected'; end if;

  v_rejected := false;
  begin
    perform public.admin_save_school_responsibilities(
      jsonb_build_object('director',v_inactive::text,'vice_director',v_vice::text,
        'personnel_head','','budget_head','','academic_head','','general_head',''),true);
  exception when others then
    if sqlerrm = 'assigned_user_missing_or_inactive' then v_rejected := true; else raise; end if;
  end;
  if not v_rejected then raise exception 'inactive_assignee_not_rejected'; end if;

  v_result := public.admin_save_school_responsibilities(
    jsonb_build_object('director',v_director::text,'vice_director',v_vice::text,
      'personnel_head','','budget_head','','academic_head','','general_head',''),true);
  if (v_result->>'has_vice_director')::boolean is distinct from true then
    raise exception 'vice_director_enabled_setting_not_saved';
  end if;
  if not exists(select 1 from public.school_responsibility_audit
      where responsibility_key='vice_director'
        and change_kind='vice_director_setting_changed'
        and previous_has_vice_director=false and new_has_vice_director=true
        and actor_user_id=v_admin) then
    raise exception 'vice_director_setting_audit_missing';
  end if;
end
$rpc_test$;

rollback;
