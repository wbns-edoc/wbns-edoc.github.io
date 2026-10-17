-- Return registration timestamps so deleted incoming items can display the BE register number consistently.

drop function if exists public.list_deleted_incoming_documents();
create function public.list_deleted_incoming_documents()
returns table(
  id uuid, subject text, status text, deleted_at timestamptz, deletion_reason text,
  department_id uuid, registered_number bigint, registered_at timestamptz, external_document_no text
)
language plpgsql stable security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_actor uuid := auth.uid();
begin
  if v_actor is null or not exists (
    select 1 from public.profiles pr where pr.id=v_actor and pr.is_active=true
  ) then raise exception using errcode='42501', message='active_profile_required'; end if;
  if not (
    private.has_permission('registry.incoming.manage')
    or exists (select 1 from public.user_roles ur join public.roles r on r.id=ur.role_id
      where ur.user_id=v_actor and r.code in ('system_admin','director'))
  ) then raise exception using errcode='42501', message='incoming_delete_permission_denied'; end if;
  return query
  select d.id,d.subject,d.status::text,d.deleted_at,d.deletion_reason,d.department_id,
    inc.registered_number,inc.registered_at,inc.external_document_no
  from public.documents d
  left join public.incoming_document_details inc on inc.document_id=d.id
  where d.document_type='incoming'::public.document_type and d.deleted_at is not null
    and (exists (select 1 from public.user_roles ur join public.roles r on r.id=ur.role_id
      where ur.user_id=v_actor and r.code in ('system_admin','director'))
      or private.user_has_department(v_actor,d.department_id))
  order by d.deleted_at desc;
end;
$$;
revoke all on function public.list_deleted_incoming_documents() from public, anon;
grant execute on function public.list_deleted_incoming_documents() to authenticated;
revoke all on function public.admin_save_system_settings(text, bigint) from public, anon, authenticated;

