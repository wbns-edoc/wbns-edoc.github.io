-- Behavior regression checks for the recovered document RLS policy.
-- This is test-only SQL for the disposable PostgreSQL replay workflow.
-- Never run against Supabase Production.
BEGIN;

INSERT INTO auth.users(id) VALUES
 ('10000000-0000-0000-0000-000000000001'),
 ('10000000-0000-0000-0000-000000000002'),
 ('10000000-0000-0000-0000-000000000003'),
 ('10000000-0000-0000-0000-000000000004'),
 ('10000000-0000-0000-0000-000000000005'),
 ('10000000-0000-0000-0000-000000000006');

INSERT INTO public.profiles(id, full_name, is_active) VALUES
 ('10000000-0000-0000-0000-000000000001', 'Replay System Admin', true),
 ('10000000-0000-0000-0000-000000000002', 'Replay Director', true),
 ('10000000-0000-0000-0000-000000000003', 'Replay Parent Group User', true),
 ('10000000-0000-0000-0000-000000000004', 'Replay Subgroup User', true),
 ('10000000-0000-0000-0000-000000000005', 'Replay Other Group User', true),
 ('10000000-0000-0000-0000-000000000006', 'Replay Multi Group User', true);

INSERT INTO public.departments(id, parent_id, code, name, is_active) VALUES
 ('20000000-0000-0000-0000-000000000001', NULL, 'REPLAY_A', 'Replay Group A', true),
 ('20000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000001', 'REPLAY_A1', 'Replay Subgroup A1', true),
 ('20000000-0000-0000-0000-000000000003', NULL, 'REPLAY_B', 'Replay Group B', true);

INSERT INTO public.roles(id, code, name) VALUES
 ('30000000-0000-0000-0000-000000000001', 'system_admin', 'Replay System Admin'),
 ('30000000-0000-0000-0000-000000000002', 'director', 'Replay Director'),
 ('30000000-0000-0000-0000-000000000003', 'replay_clerk', 'Replay Clerk');

INSERT INTO public.permissions(id, code, name) VALUES
 ('40000000-0000-0000-0000-000000000001', 'document.view', 'View documents'),
 ('40000000-0000-0000-0000-000000000002', 'document.create', 'Create documents'),
 ('40000000-0000-0000-0000-000000000003', 'document.update', 'Update documents'),
 ('40000000-0000-0000-0000-000000000004', 'document.approve', 'Approve documents');

INSERT INTO public.user_roles(user_id, role_id) VALUES
 ('10000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001'),
 ('10000000-0000-0000-0000-000000000002', '30000000-0000-0000-0000-000000000002');

INSERT INTO public.user_departments(user_id, department_id, is_primary) VALUES
 ('10000000-0000-0000-0000-000000000003', '20000000-0000-0000-0000-000000000001', true),
 ('10000000-0000-0000-0000-000000000004', '20000000-0000-0000-0000-000000000002', true),
 ('10000000-0000-0000-0000-000000000005', '20000000-0000-0000-0000-000000000003', true),
 ('10000000-0000-0000-0000-000000000006', '20000000-0000-0000-0000-000000000001', true),
 ('10000000-0000-0000-0000-000000000006', '20000000-0000-0000-0000-000000000003', false);

INSERT INTO public.user_department_roles(user_id, department_id, role_id) VALUES
 ('10000000-0000-0000-0000-000000000003', '20000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000003'),
 ('10000000-0000-0000-0000-000000000004', '20000000-0000-0000-0000-000000000002', '30000000-0000-0000-0000-000000000003'),
 ('10000000-0000-0000-0000-000000000005', '20000000-0000-0000-0000-000000000003', '30000000-0000-0000-0000-000000000003'),
 ('10000000-0000-0000-0000-000000000006', '20000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000003'),
 ('10000000-0000-0000-0000-000000000006', '20000000-0000-0000-0000-000000000003', '30000000-0000-0000-0000-000000000003');

INSERT INTO public.department_role_permissions(department_id, role_id, permission_id, enabled) VALUES
 ('20000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000003', '40000000-0000-0000-0000-000000000001', true),
 ('20000000-0000-0000-0000-000000000002', '30000000-0000-0000-0000-000000000003', '40000000-0000-0000-0000-000000000001', true),
 ('20000000-0000-0000-0000-000000000003', '30000000-0000-0000-0000-000000000003', '40000000-0000-0000-0000-000000000001', true);

INSERT INTO public.documents(id, document_type, subject, status, created_by, department_id) VALUES
 ('50000000-0000-0000-0000-000000000001', 'incoming', 'Replay Group A document', 'draft', '10000000-0000-0000-0000-000000000003', '20000000-0000-0000-0000-000000000001'),
 ('50000000-0000-0000-0000-000000000002', 'incoming', 'Replay Subgroup A1 document', 'draft', '10000000-0000-0000-0000-000000000004', '20000000-0000-0000-0000-000000000002'),
 ('50000000-0000-0000-0000-000000000003', 'incoming', 'Replay Group B document', 'draft', '10000000-0000-0000-0000-000000000005', '20000000-0000-0000-0000-000000000003');

-- The harness simulates the authenticated API role; only the disposable DB receives these grants.
GRANT USAGE ON SCHEMA public, private, auth TO authenticated;
GRANT EXECUTE ON FUNCTION auth.uid() TO authenticated;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA private TO authenticated;
GRANT SELECT ON public.documents TO authenticated;
GRANT SELECT ON public.department_role_permissions, public.user_department_roles TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_set_global_user_role(uuid, uuid, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_set_department_role_permission(uuid, uuid, uuid, boolean) TO authenticated;

SET LOCAL ROLE authenticated;

SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);
DO $$ DECLARE n integer; BEGIN
  SELECT count(*) INTO n FROM public.documents;
  IF n <> 3 THEN RAISE EXCEPTION 'system_admin should read all 3 documents; got %', n; END IF;
  IF NOT private.has_department_permission('document.create', '20000000-0000-0000-0000-000000000003') THEN RAISE EXCEPTION 'system_admin should have document.create in every department'; END IF;
  IF NOT private.has_department_permission('document.update', '20000000-0000-0000-0000-000000000003') THEN RAISE EXCEPTION 'system_admin should have document.update in every department'; END IF;
  IF NOT private.has_department_permission('document.approve', '20000000-0000-0000-0000-000000000003') THEN RAISE EXCEPTION 'system_admin should have document.approve in every department'; END IF;
END $$;

SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000002', true);
DO $$ DECLARE n integer; BEGIN
  SELECT count(*) INTO n FROM public.documents;
  IF n <> 3 THEN RAISE EXCEPTION 'director should read all 3 documents; got %', n; END IF;
  IF NOT private.has_department_permission('document.approve', '20000000-0000-0000-0000-000000000003') THEN RAISE EXCEPTION 'director should have document.approve in every department'; END IF;
END $$;

SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000003', true);
DO $$ DECLARE n integer; BEGIN
  SELECT count(*) INTO n FROM public.documents;
  IF n <> 1 THEN RAISE EXCEPTION 'parent group user should read only parent-group document; got %', n; END IF;
END $$;

SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000004', true);
DO $$ DECLARE n integer; BEGIN
  SELECT count(*) INTO n FROM public.documents;
  IF n <> 2 THEN RAISE EXCEPTION 'subgroup user should read parent and own subgroup documents only; got %', n; END IF;
END $$;

SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000005', true);
DO $$ DECLARE n integer; BEGIN
  SELECT count(*) INTO n FROM public.documents;
  IF n <> 1 THEN RAISE EXCEPTION 'other group user should read only own group document; got %', n; END IF;
END $$;

SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000006', true);
DO $ DECLARE n integer; BEGIN
  SELECT count(*) INTO n FROM public.documents;
  IF n <> 2 THEN RAISE EXCEPTION 'multi-group user should read documents from both assigned groups; got %', n; END IF;
  SELECT count(*) INTO n FROM public.user_department_roles;
  IF n <> 0 THEN RAISE EXCEPTION 'direct user_department_roles read should return no rows without a policy; got %', n; END IF;
  SELECT count(*) INTO n FROM public.department_role_permissions;
  IF n <> 0 THEN RAISE EXCEPTION 'direct department_role_permissions read should return no rows without a policy; got %', n; END IF;
END $;

-- SECURITY DEFINER RPCs are callable by authenticated, but must reject users without admin permissions.
SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000006', true);
DO $ BEGIN
  BEGIN
    PERFORM public.admin_set_global_user_role(
      '10000000-0000-0000-0000-000000000006',
      '30000000-0000-0000-0000-000000000002',
      true
    );
    RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='ordinary user unexpectedly changed a global role';
  EXCEPTION WHEN SQLSTATE '42501' THEN
    NULL;
  END;
  BEGIN
    PERFORM public.admin_set_department_role_permission(
      '20000000-0000-0000-0000-000000000001',
      '30000000-0000-0000-0000-000000000003',
      '40000000-0000-0000-0000-000000000001',
      false
    );
    RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='ordinary user unexpectedly changed department permissions';
  EXCEPTION WHEN SQLSTATE '42501' THEN
    NULL;
  END;
END $;

RESET ROLE;
ROLLBACK;
