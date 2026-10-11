-- Behavioral RLS regression: department isolation and explicitly authorized wide readers.
-- Runs only against the disposable recovered-catalog fixture.
BEGIN;
SELECT plan(11);

INSERT INTO auth.users (id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
VALUES
 ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1','authenticated','authenticated','scope-a@example.invalid','',now(),now(),now()),
 ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2','authenticated','authenticated','scope-b@example.invalid','',now(),now(),now()),
 ('dddddddd-dddd-4ddd-8ddd-ddddddddddd4','authenticated','authenticated','scope-director@example.invalid','',now(),now(),now()),
 ('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee5','authenticated','authenticated','scope-admin@example.invalid','',now(),now(),now()),
 ('ffffffff-ffff-4fff-8fff-fffffffffff6','authenticated','authenticated','scope-child@example.invalid','',now(),now(),now())
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.departments (id, code, name, is_active)
VALUES
 ('a0000000-0000-4000-8000-000000000001','TEST-A','Test Department A',true),
 ('b0000000-0000-4000-8000-000000000002','TEST-B','Test Department B',true),
 ('a1000000-0000-4000-8000-000000000001','TEST-PARENT','Test Parent',true),
 ('a2000000-0000-4000-8000-000000000002','TEST-CHILD','Test Child',true),
 ('a3000000-0000-4000-8000-000000000003','TEST-SIBLING','Test Sibling',true)
ON CONFLICT (id) DO UPDATE SET parent_id=EXCLUDED.parent_id;
UPDATE public.departments SET parent_id='a1000000-0000-4000-8000-000000000001' WHERE id IN ('a2000000-0000-4000-8000-000000000002','a3000000-0000-4000-8000-000000000003');

INSERT INTO public.profiles (id, full_name, is_active, department_id)
VALUES
 ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1','Scope Test A',true,'a0000000-0000-4000-8000-000000000001'),
 ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2','Scope Test B',true,'b0000000-0000-4000-8000-000000000002'),
 ('dddddddd-dddd-4ddd-8ddd-ddddddddddd4','Scope Test Director',true,NULL),
 ('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee5','Scope Test Admin',true,NULL),
 ('ffffffff-ffff-4fff-8fff-fffffffffff6','Scope Test Child',true,'a2000000-0000-4000-8000-000000000002')
ON CONFLICT (id) DO UPDATE SET is_active = true, department_id = EXCLUDED.department_id;

INSERT INTO public.user_roles (user_id, role_id)
SELECT u.user_id, r.id
FROM (VALUES
 ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'::uuid,'teacher'::text),
 ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2'::uuid,'teacher'::text),
 ('dddddddd-dddd-4ddd-8ddd-ddddddddddd4'::uuid,'director'::text),
 ('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee5'::uuid,'system_admin'::text),
 ('ffffffff-ffff-4fff-8fff-fffffffffff6'::uuid,'teacher'::text)
) AS u(user_id, role_code)
JOIN public.roles r ON r.code = u.role_code
ON CONFLICT DO NOTHING;

INSERT INTO public.user_departments(user_id,department_id,is_primary)
VALUES ('ffffffff-ffff-4fff-8fff-fffffffffff6','a2000000-0000-4000-8000-000000000002',true)
ON CONFLICT (user_id,department_id) DO UPDATE SET is_primary=true;
INSERT INTO public.user_department_roles(user_id,department_id,role_id)
SELECT 'ffffffff-ffff-4fff-8fff-fffffffffff6','a2000000-0000-4000-8000-000000000002',r.id
FROM public.roles r WHERE r.code='teacher'
ON CONFLICT DO NOTHING;
INSERT INTO public.department_role_permissions(department_id,role_id,permission_id,enabled)
SELECT 'a2000000-0000-4000-8000-000000000002',r.id,p.id,true
FROM public.roles r CROSS JOIN public.permissions p
WHERE r.code='teacher' AND p.code='document.view'
ON CONFLICT (department_id,role_id,permission_id) DO UPDATE SET enabled=true;
INSERT INTO public.documents (id,document_type,department_id,subject,status,created_by,current_owner_id)
VALUES
 ('c2000000-0000-4000-8000-000000000002','incoming','a1000000-0000-4000-8000-000000000001','Parent document','registered','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2'),
 ('c3000000-0000-4000-8000-000000000003','incoming','a2000000-0000-4000-8000-000000000002','Child document','registered','ffffffff-ffff-4fff-8fff-fffffffffff6','ffffffff-ffff-4fff-8fff-fffffffffff6'),
 ('c4000000-0000-4000-8000-000000000004','incoming','a3000000-0000-4000-8000-000000000003','Sibling document','registered','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2')
ON CONFLICT (id) DO UPDATE SET department_id=EXCLUDED.department_id,subject=EXCLUDED.subject;

INSERT INTO public.documents (id, document_type, department_id, subject, status, created_by, current_owner_id)
VALUES ('c0000000-0000-4000-8000-000000000003','incoming','b0000000-0000-4000-8000-000000000002',
        'Cross-department isolation fixture','registered',
        'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2')
ON CONFLICT (id) DO UPDATE SET department_id = EXCLUDED.department_id,
 subject = EXCLUDED.subject, status = EXCLUDED.status, created_by = EXCLUDED.created_by,
 current_owner_id = EXCLUDED.current_owner_id;

INSERT INTO public.comments (id, document_id, author_id, body)
VALUES ('c1111111-1111-4111-8111-111111111111','c0000000-0000-4000-8000-000000000003',
        'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2','Private to department B')
ON CONFLICT (id) DO NOTHING;

-- Ordinary teacher from department A must not read department B's document or child rows.
SELECT set_config('request.jwt.claim.sub','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1',true);
SET LOCAL ROLE authenticated;
SELECT is((SELECT count(*) FROM public.documents WHERE id='c0000000-0000-4000-8000-000000000003'), 0::bigint,
          'ordinary user cannot read another department document');
SELECT is((SELECT count(*) FROM public.comments WHERE document_id='c0000000-0000-4000-8000-000000000003'), 0::bigint,
          'ordinary user cannot read comments for another department document');
RESET ROLE;

-- Director receives document-wide read and edit via role permissions, not user-specific grants.
SELECT set_config('request.jwt.claim.sub','dddddddd-dddd-4ddd-8ddd-ddddddddddd4',true);
SET LOCAL ROLE authenticated;
SELECT is((SELECT count(*) FROM public.documents WHERE id='c0000000-0000-4000-8000-000000000003'), 1::bigint,
          'director can read a document in another department');
SELECT lives_ok(
  $stmt$UPDATE public.documents
    SET subject='Director cross-department edit verified'
    WHERE id='c0000000-0000-4000-8000-000000000003'$stmt$,
  'director can edit a document in another department'
);
SELECT lives_ok(
  $stmt$INSERT INTO public.documents(id,document_type,department_id,subject,status,created_by,current_owner_id)
    VALUES ('c5000000-0000-4000-8000-000000000005','incoming',
            'b0000000-0000-4000-8000-000000000002','Director cross-department creation','draft',
            'dddddddd-dddd-4ddd-8ddd-ddddddddddd4','dddddddd-dddd-4ddd-8ddd-ddddddddddd4')$stmt$,
  'director can create a document in another department'
);
RESET ROLE;

-- System Admin also has document-wide read.
SELECT set_config('request.jwt.claim.sub','eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee5',true);
SET LOCAL ROLE authenticated;
SELECT is((SELECT count(*) FROM public.documents WHERE id='c0000000-0000-4000-8000-000000000003'), 1::bigint,
          'System Admin can read a document in another department');
RESET ROLE;


-- A child-unit member may read its parent unit's documents, but not sibling-unit documents.
SELECT set_config('request.jwt.claim.sub','ffffffff-ffff-4fff-8fff-fffffffffff6',true);
SET LOCAL ROLE authenticated;
SELECT is((SELECT count(*) FROM public.documents WHERE id='c2000000-0000-4000-8000-000000000002'),1::bigint,
          'child department member can read parent department document');
SELECT is((SELECT count(*) FROM public.documents WHERE id='c3000000-0000-4000-8000-000000000003'),1::bigint,
          'child department member can read own department document');
SELECT is((SELECT count(*) FROM public.documents WHERE id='c4000000-0000-4000-8000-000000000004'),0::bigint,
          'child department member cannot read sibling department document');
WITH changed AS (
  UPDATE public.documents SET subject=subject
  WHERE id='c2000000-0000-4000-8000-000000000002'
  RETURNING id
)
SELECT is((SELECT count(*) FROM changed),0::bigint,
          'child department member cannot edit parent document without parent-scoped edit permission');
WITH changed AS (
  UPDATE public.documents SET subject=subject
  WHERE id='c4000000-0000-4000-8000-000000000004'
  RETURNING id
)
SELECT is((SELECT count(*) FROM changed),0::bigint,
          'child department member cannot edit sibling department document');
RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
