-- Production ACL/RLS guard for the four intentionally policy-less public tables.
-- Runs ONLY in the disposable PostgreSQL replay; never run against Production.
BEGIN;

-- The October 15 recovered catalog predates the current system_settings shape
-- and does not preserve every later RLS flag. Add minimal test-only shells where
-- absent and normalize RLS for the four live Production no-policy tables.
-- This is an ACL/RLS behavior fixture, NOT evidence of historical schema parity.
CREATE TABLE IF NOT EXISTS public.system_settings (
  setting_key text PRIMARY KEY,
  setting_value jsonb
);
ALTER TABLE public.system_settings ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.user_departments (
  user_id uuid NOT NULL,
  department_id uuid NOT NULL,
  is_primary boolean NOT NULL DEFAULT false,
  PRIMARY KEY (user_id, department_id)
);
ALTER TABLE public.user_departments ENABLE ROW LEVEL SECURITY;

-- Reproduce only the verified Production API-role grants inside this disposable transaction.
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT SELECT ON public.department_role_permissions, public.user_department_roles TO authenticated;

DO $catalog$
DECLARE
  t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'department_role_permissions',
    'system_settings',
    'user_department_roles',
    'user_departments'
  ] LOOP
    IF NOT EXISTS (
      SELECT 1
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'public'
        AND c.relname = t
        AND c.relkind IN ('r','p')
        AND c.relrowsecurity
    ) THEN
      RAISE EXCEPTION 'expected RLS-enabled public table: %', t;
    END IF;

    IF EXISTS (
      SELECT 1 FROM pg_policies
      WHERE schemaname = 'public' AND tablename = t
    ) THEN
      RAISE EXCEPTION 'intentionally closed table unexpectedly has an RLS policy: %', t;
    END IF;
  END LOOP;

  -- Match the live Production ACL shape observed 2026-11-03:
  -- only two of the four tables expose SELECT privilege to authenticated;
  -- RLS with no policy must still deny every row.
  IF NOT has_table_privilege('authenticated', 'public.department_role_permissions', 'SELECT')
     OR NOT has_table_privilege('authenticated', 'public.user_department_roles', 'SELECT') THEN
    RAISE EXCEPTION 'authenticated SELECT grants missing from the two RPC-only reference tables';
  END IF;

  IF has_table_privilege('authenticated', 'public.system_settings', 'SELECT')
     OR has_table_privilege('authenticated', 'public.user_departments', 'SELECT') THEN
    RAISE EXCEPTION 'authenticated unexpectedly has direct SELECT on system_settings/user_departments';
  END IF;

  FOREACH t IN ARRAY ARRAY[
    'department_role_permissions',
    'system_settings',
    'user_department_roles',
    'user_departments'
  ] LOOP
    IF has_table_privilege('anon', 'public.' || t, 'SELECT') THEN
      RAISE EXCEPTION 'anon unexpectedly has SELECT on intentionally closed table %', t;
    END IF;
  END LOOP;
END
$catalog$;

SET LOCAL ROLE authenticated;
DO $authenticated$
DECLARE
  n integer;
BEGIN
  SELECT count(*) INTO n FROM public.department_role_permissions;
  IF n <> 0 THEN
    RAISE EXCEPTION 'direct authenticated read exposed department_role_permissions rows: %', n;
  END IF;

  SELECT count(*) INTO n FROM public.user_department_roles;
  IF n <> 0 THEN
    RAISE EXCEPTION 'direct authenticated read exposed user_department_roles rows: %', n;
  END IF;

  BEGIN
    EXECUTE 'SELECT count(*) FROM public.system_settings';
    RAISE EXCEPTION 'authenticated unexpectedly queried system_settings directly';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;

  BEGIN
    EXECUTE 'SELECT count(*) FROM public.user_departments';
    RAISE EXCEPTION 'authenticated unexpectedly queried user_departments directly';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;
END
$authenticated$;
RESET ROLE;

ROLLBACK;
