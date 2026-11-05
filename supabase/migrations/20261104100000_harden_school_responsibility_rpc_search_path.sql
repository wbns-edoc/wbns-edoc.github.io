-- Pin pg_catalog ahead of public for SECURITY DEFINER school-responsibility RPCs.
-- These functions already enforce active System Admin authorization; this
-- forward-only hardening removes reliance on PostgreSQL's implicit lookup order.
begin;

alter function public.admin_get_school_responsibilities()
  set search_path = pg_catalog, public;

alter function public.admin_save_school_responsibilities(jsonb, boolean)
  set search_path = pg_catalog, public;

commit;
