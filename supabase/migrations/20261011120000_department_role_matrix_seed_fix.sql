-- Correct scoped-role authorization gaps before any deployment.
BEGIN;

-- Keep global roles out of the per-department permission matrix.
DELETE FROM public.department_role_permissions
WHERE role_id IN (SELECT id FROM public.roles WHERE code IN ('system_admin','director'));

-- Seed only ordinary role grants from the existing catalogue.
INSERT INTO public.department_role_permissions(department_id,role_id,permission_id,enabled)
SELECT d.id, rp.role_id, rp.permission_id, true
FROM public.departments d
JOIN public.role_permissions rp ON true
JOIN public.roles r ON r.id=rp.role_id
WHERE r.code NOT IN ('system_admin','director')
ON CONFLICT (department_id,role_id,permission_id) DO NOTHING;

COMMIT;
