-- Require the selected approver to be active and hold document.approve.
create or replace function private.create_approval(
  p_document_id uuid,
  p_approver_id uuid,
  p_approval_step integer default 1
)
returns uuid
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $function$
declare
  v_id uuid;
  v_actor uuid := auth.uid();
  v_subject text;
  v_status public.document_status;
begin
  if v_actor is null or not private.has_permission('document.approve') then
    raise exception 'permission_denied';
  end if;

  if p_approval_step < 1 then
    raise exception 'invalid_approval_step';
  end if;

  if not exists (
    select 1
    from public.profiles pr
    join public.user_roles ur on ur.user_id = pr.id
    join public.role_permissions rp on rp.role_id = ur.role_id
    join public.permissions p on p.id = rp.permission_id
    where pr.id = p_approver_id
      and pr.is_active = true
      and p.code = 'document.approve'
  ) then
    raise exception 'approver_not_authorized';
  end if;

  select status, subject into v_status, v_subject
  from public.documents
  where id = p_document_id
  for update;

  if v_status is null then
    raise exception 'document_not_found';
  end if;

  if v_status <> 'draft' then
    raise exception 'document_not_in_draft';
  end if;

  insert into public.approvals(document_id, approval_step, approver_id, decision)
  values (p_document_id, p_approval_step, p_approver_id, 'pending')
  returning id into v_id;

  update public.documents set status = 'pending_approval' where id = p_document_id;

  insert into public.notifications(recipient_id, document_id, type, title, body, priority)
  values (
    p_approver_id, p_document_id, 'approval', 'รอการอนุมัติ',
    'มีเอกสารรอการอนุมัติ: ' || coalesce(v_subject, 'ไม่ระบุเรื่อง'), 'high'
  );

  return v_id;
end;
$function$;
