-- RECOVERED SOURCE ARCHIVE — NOT A NEW MIGRATION
-- Read-only extraction from Production supabase_migrations.schema_migrations.statements
-- Production project: iigzzwyfxxtqbgjawyom
-- Applied version: 20261008053608
-- Ledger name: revoke_anon_admin_department_rpc_v1
-- DO NOT place in supabase/migrations or replay against Production.

revoke execute on function public.admin_create_department(text,text,uuid) from anon;
revoke execute on function public.admin_update_department(uuid,text,text,uuid,boolean) from anon;
revoke execute on function public.admin_set_user_department(uuid,uuid) from anon;
