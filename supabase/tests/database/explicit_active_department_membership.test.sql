-- Regression test: department scope comes only from explicit active membership.
-- Runs only against the disposable recovered-catalog fixture.
BEGIN;
SELECT plan(4);

INSERT INTO auth.users (id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
VALUES
 ('a1100000-0000-4000-8000-000000000001','authenticated','authenticated','member-active@example.invalid','',now(),now(),now()),
 ('a1100000-0000-4000-8000-000000000002','authenticated','authenticated','profile-only@example.invalid','',now(),now(),now()),
 ('a1100000-0000-4000-8000-000000000003','authenticated','authenticated','member-inactive-dept@example.invalid','',now(),now(),now())
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.departments(id,code,name,is_active)
VALUES
 ('a2100000-0000-4000-8000-000000000001','TEST-MEMBER-ACTIVE','Membership test active',true),
 ('a2100000-0000-4000-8000-000000000002','TEST-MEMBER-INACTIVE','Membership test inactive',false)
ON CONFLICT (id) DO UPDATE SET is_active=EXCLUDED.is_active;

INSERT INTO public.profiles(id,full_name,is_active,department_id)
VALUES
 ('a1100000-0000-4000-8000-000000000001','Active department member',true,'a2100000-0000-4000-8000-000000000001'),
 ('a1100000-0000-4000-8000-000000000002','Profile only without membership',true,'a2100000-0000-4000-8000-000000000001'),
 ('a1100000-0000-4000-8000-000000000003','Member in inactive department',true,'a2100000-0000-4000-8000-000000000002')
ON CONFLICT (id) DO UPDATE SET is_active=EXCLUDED.is_active,department_id=EXCLUDED.department_id;

INSERT INTO public.user_departments(user_id,department_id,is_primary)
VALUES
 ('a1100000-0000-4000-8000-000000000001','a2100000-0000-4000-8000-000000000001',true),
 ('a1100000-0000-4000-8000-000000000003','a2100000-0000-4000-8000-000000000002',true)
ON CONFLICT (user_id,department_id) DO UPDATE SET is_primary=true;

SELECT ok(
  private.user_has_department('a1100000-0000-4000-8000-000000000001','a2100000-0000-4000-8000-000000000001'),
  'active explicit membership grants department scope'
);
SELECT ok(
  NOT private.user_has_department('a1100000-0000-4000-8000-000000000002','a2100000-0000-4000-8000-000000000001'),
  'profiles.department_id alone does not grant department scope'
);
SELECT ok(
  NOT private.user_has_department('a1100000-0000-4000-8000-000000000003','a2100000-0000-4000-8000-000000000002'),
  'membership in an inactive department grants no scope'
);
UPDATE public.profiles SET is_active=false WHERE id='a1100000-0000-4000-8000-000000000001';
SELECT ok(
  NOT private.user_has_department('a1100000-0000-4000-8000-000000000001','a2100000-0000-4000-8000-000000000001'),
  'inactive user profile grants no department scope'
);

SELECT * FROM finish();
ROLLBACK;
