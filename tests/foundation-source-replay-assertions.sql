-- Assertions for the recovered historical Foundation source.
-- Run ONLY against a fresh disposable PostgreSQL 17 database.
DO $$
DECLARE
  required_table text;
  required_tables text[] := ARRAY[
    'departments','profiles','roles','permissions','user_roles','role_permissions',
    'document_registers','number_sequences','senders','documents',
    'incoming_document_details','outgoing_document_details','document_assignments',
    'document_status_history','approvals','deadlines','comments','google_drive_files',
    'document_files','notifications','push_subscriptions','audit_logs'
  ];
  required_enum text;
BEGIN
  FOREACH required_table IN ARRAY required_tables LOOP
    IF to_regclass('public.' || required_table) IS NULL THEN
      RAISE EXCEPTION 'foundation_missing_table:%', required_table;
    END IF;
    IF NOT EXISTS (
      SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
      WHERE n.nspname='public' AND c.relname=required_table AND c.relrowsecurity
    ) THEN
      RAISE EXCEPTION 'foundation_rls_not_enabled:%', required_table;
    END IF;
  END LOOP;

  FOREACH required_enum IN ARRAY ARRAY[
    'document_type','urgency_level','document_status','approval_decision','assignment_status'
  ] LOOP
    IF NOT EXISTS (
      SELECT 1 FROM pg_type t JOIN pg_namespace n ON n.oid=t.typnamespace
      WHERE n.nspname='public' AND t.typname=required_enum AND t.typtype='e'
    ) THEN
      RAISE EXCEPTION 'foundation_missing_enum:%', required_enum;
    END IF;
  END LOOP;

  IF to_regprocedure('public.has_permission(text)') IS NULL
     OR to_regprocedure('public.is_admin()') IS NULL
     OR to_regprocedure('public.allocate_document_number(uuid,integer)') IS NULL
     OR to_regprocedure('public.set_updated_at()') IS NULL THEN
    RAISE EXCEPTION 'foundation_missing_expected_function';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='documents' AND policyname='documents_select_authorized')
     OR NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='notifications' AND policyname='notifications_own')
     OR NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='profiles' AND policyname='profiles_select_self_or_admin') THEN
    RAISE EXCEPTION 'foundation_missing_expected_rls_policy';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='documents_updated_at' AND NOT tgisinternal)
     OR NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='profiles_updated_at' AND NOT tgisinternal) THEN
    RAISE EXCEPTION 'foundation_missing_expected_trigger';
  END IF;
END
$$;
