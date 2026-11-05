-- RECOVERED SOURCE ARCHIVE — NOT A NEW MIGRATION
-- Read-only extraction from Production supabase_migrations.schema_migrations.statements
-- Production project: iigzzwyfxxtqbgjawyom
-- Applied version: 20261008053554
-- Ledger name: harden_admin_department_rpc_execute_v2
-- DO NOT place in supabase/migrations or replay against Production.

revoke all on function public.admin_create_department(text,text,uuid) from public;
revoke all on function public.admin_update_department(uuid,text,text,uuid,boolean) from public;
revoke all on function public.admin_set_user_department(uuid,uuid) from public;
grant execute on function public.admin_create_department(text,text,uuid) to authenticated;
grant execute on function public.admin_update_department(uuid,text,text,uuid,boolean) to authenticated;
grant execute on function public.admin_set_user_department(uuid,uuid) to authenticated;
