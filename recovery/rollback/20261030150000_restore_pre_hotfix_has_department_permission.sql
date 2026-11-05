-- Emergency rollback definition captured from Production before
-- 20261030150000_require_active_department_for_scoped_permissions.sql.
-- Use only as a new forward rollback migration if the active-department guard
-- causes a verified regression. Do not edit migration history to erase the hotfix.

create or replace function private.has_department_permission(
  p_permission text,
  p_department_id uuid
)
returns boolean
language sql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $function$
  select exists (
    select 1
    from public.profiles pr
    where pr.id = (select auth.uid())
      and pr.is_active = true
      and (
        (
          exists (
            select 1
            from public.user_roles ur
            join public.roles wr on wr.id = ur.role_id
            where ur.user_id = (select auth.uid())
              and wr.code in ('system_admin','director')
          )
          and p_permission in (
            'document.view',
            'document.create',
            'document.approve',
            'document.update',
            'document.assign'
          )
        )
        or (
          p_permission = 'document.assign'
          and exists (
            select 1
            from public.user_roles ur
            join public.roles wr on wr.id = ur.role_id
            where ur.user_id = (select auth.uid())
              and wr.code = 'deputy_director'
          )
        )
        or exists (
          select 1
          from public.user_department_roles udr
          join public.user_departments ud
            on ud.user_id = udr.user_id
           and ud.department_id = udr.department_id
          join public.roles r on r.id = udr.role_id
          join public.department_role_permissions drp
            on drp.department_id = udr.department_id
           and drp.role_id = udr.role_id
           and drp.enabled = true
          join public.permissions p on p.id = drp.permission_id
          where udr.user_id = pr.id
            and udr.department_id = p_department_id
            and p.code = p_permission
        )
      )
  );
$function$;
