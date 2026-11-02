-- RECOVERED SOURCE ARCHIVE — NOT A NEW MIGRATION
-- Read-only extraction from Production supabase_migrations.schema_migrations.statements
-- Production project: iigzzwyfxxtqbgjawyom
-- Applied version: 20261008042634
-- Ledger name: admin_department_management_v1
-- DO NOT place in supabase/migrations or replay against Production.

create or replace function public.admin_create_department(p_code text,p_name text,p_parent_id uuid default null)
returns public.departments
language plpgsql security definer
set search_path=pg_catalog,public,private
as $$
declare v public.departments;
begin
 if not private.has_permission('user.manage') and not private.has_permission('role.manage') then
   raise exception using errcode='42501',message='insufficient_privilege';
 end if;
 if btrim(coalesce(p_code,''))='' or btrim(coalesce(p_name,''))='' then
   raise exception using errcode='22023',message='department_code_and_name_required';
 end if;
 if exists(select 1 from public.departments where lower(code)=lower(btrim(p_code))) then
   raise exception using errcode='23505',message='department_code_exists';
 end if;
 insert into public.departments(code,name,parent_id,is_active)
 values(btrim(p_code),btrim(p_name),p_parent_id,true)
 returning * into v;
 return v;
end $$;

create or replace function public.admin_update_department(p_department_id uuid,p_code text,p_name text,p_parent_id uuid,p_is_active boolean)
returns public.departments
language plpgsql security definer
set search_path=pg_catalog,public,private
as $$
declare v public.departments;
begin
 if not private.has_permission('user.manage') and not private.has_permission('role.manage') then
   raise exception using errcode='42501',message='insufficient_privilege';
 end if;
 if not exists(select 1 from public.departments where id=p_department_id) then
   raise exception using errcode='22023',message='department_not_found';
 end if;
 if btrim(coalesce(p_code,''))='' or btrim(coalesce(p_name,''))='' then
   raise exception using errcode='22023',message='department_code_and_name_required';
 end if;
 if exists(select 1 from public.departments where lower(code)=lower(btrim(p_code)) and id<>p_department_id) then
   raise exception using errcode='23505',message='department_code_exists';
 end if;
 update public.departments
 set code=btrim(p_code),name=btrim(p_name),parent_id=p_parent_id,is_active=coalesce(p_is_active,true),updated_at=now()
 where id=p_department_id
 returning * into v;
 return v;
end $$;

revoke all on function public.admin_create_department(text,text,uuid) from public;
revoke all on function public.admin_update_department(uuid,text,text,uuid,boolean) from public;
grant execute on function public.admin_create_department(text,text,uuid) to authenticated;
grant execute on function public.admin_update_department(uuid,text,text,uuid,boolean) to authenticated;
