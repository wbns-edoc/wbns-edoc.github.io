-- Behavioral denial tests for approval routing on the disposable recovered-catalog fixture.
BEGIN;
SELECT plan(3);

INSERT INTO auth.users (id,aud,role,email,encrypted_password,email_confirmed_at,created_at,updated_at)
VALUES
 ('a3100000-0000-4000-8000-000000000001','authenticated','authenticated','approval-actor@example.invalid','',now(),now(),now()),
 ('a3100000-0000-4000-8000-000000000002','authenticated','authenticated','approval-no-membership@example.invalid','',now(),now(),now()),
 ('a3100000-0000-4000-8000-000000000003','authenticated','authenticated','approval-inactive-dept@example.invalid','',now(),now(),now()),
 ('a3100000-0000-4000-8000-000000000004','authenticated','authenticated','approval-stale-role@example.invalid','',now(),now(),now())
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.departments(id,code,name,is_active)
VALUES
 ('a3200000-0000-4000-8000-000000000001','TEST-APPROVAL-ACTIVE','Approval test active department',true),
 ('a3200000-0000-4000-8000-000000000002','TEST-APPROVAL-INACTIVE','Approval test inactive department',false)
ON CONFLICT (id) DO UPDATE SET is_active=EXCLUDED.is_active;

INSERT INTO public.profiles(id,full_name,is_active,department_id)
VALUES
 ('a3100000-0000-4000-8000-000000000001','Approval test actor',true,NULL),
 ('a3100000-0000-4000-8000-000000000002','Approver without membership',true,'a3200000-0000-4000-8000-000000000001'),
 ('a3100000-0000-4000-8000-000000000003','Approver in inactive department',true,'a3200000-0000-4000-8000-000000000002'),
 ('a3100000-0000-4000-8000-000000000004','Approver with stale role only',true,'a3200000-0000-4000-8000-000000000001')
ON CONFLICT (id) DO UPDATE SET is_active=EXCLUDED.is_active,department_id=EXCLUDED.department_id;

INSERT INTO public.user_roles(user_id,role_id)
SELECT 'a3100000-0000-4000-8000-000000000001',id FROM public.roles WHERE code='system_admin'
ON CONFLICT DO NOTHING;

INSERT INTO public.user_departments(user_id,department_id,is_primary)
VALUES
 ('a3100000-0000-4000-8000-000000000003','a3200000-0000-4000-8000-000000000002',true)
ON CONFLICT (user_id,department_id) DO UPDATE SET is_primary=true;

INSERT INTO public.user_department_roles(user_id,department_id,role_id)
SELECT 'a3100000-0000-4000-8000-000000000004','a3200000-0000-4000-8000-000000000001',id
FROM public.roles WHERE code='teacher'
ON CONFLICT DO NOTHING;

INSERT INTO public.documents(id,document_type,department_id,subject,status,created_by,current_owner_id)
VALUES ('a3300000-0000-4000-8000-000000000001','incoming',
        'a3200000-0000-4000-8000-000000000001','Approval authorization regression','draft',
        'a3100000-0000-4000-8000-000000000001','a3100000-0000-4000-8000-000000000001')
ON CONFLICT (id) DO UPDATE SET department_id=EXCLUDED.department_id,subject=EXCLUDED.subject,status='draft';

SELECT set_config('request.jwt.claim.sub','a3100000-0000-4000-8000-000000000001',true);
SET LOCAL ROLE authenticated;

SELECT throws_ok(
 $$SELECT private.create_approval('a3300000-0000-4000-8000-000000000001','a3100000-0000-4000-8000-000000000002',1)$$,
 'P0001','approver_not_authorized',
 'approval creation rejects an active profile with no department membership'
);

SELECT throws_ok(
 $$SELECT private.create_approval('a3300000-0000-4000-8000-000000000001','a3100000-0000-4000-8000-000000000003',1)$$,
 'P0001','approver_not_authorized',
 'approval creation rejects membership in an inactive department'
);

SELECT throws_ok(
 $$SELECT private.create_approval('a3300000-0000-4000-8000-000000000001','a3100000-0000-4000-8000-000000000004',1)$$,
 'P0001','approver_not_authorized',
 'approval creation rejects stale department role without active membership'
);

RESET ROLE;
SELECT * FROM finish();
ROLLBACK;
