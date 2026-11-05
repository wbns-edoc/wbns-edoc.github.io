-- Test-only bootstrap for a disposable local Supabase stack.
-- Supabase already owns auth.users, auth.uid(), API roles, and platform schemas.
-- Never apply this file to Production.
create schema if not exists private;
create extension if not exists pg_trgm with schema extensions;

grant usage on schema public, private, auth to authenticated;
grant execute on function auth.uid() to authenticated;
