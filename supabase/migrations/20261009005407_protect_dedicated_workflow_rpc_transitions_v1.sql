-- Keep approval and assignment side effects behind their dedicated RPCs.
create or replace function public.update_document_status(
  p_document_id uuid,
  p_to_status public.document_status,
  p_reason text default null
)
returns boolean
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $function$
declare
  v_actor uuid := auth.uid();
  v_from public.document_status;
begin
  if v_actor is null then
    raise exception 'permission_denied';
  end if;

  select status into v_from
  from public.documents
  where id = p_document_id
  for update;

  if v_from is null then
    raise exception 'document_not_found';
  end if;

  if v_from = p_to_status then
    return true;
  end if;

  if p_to_status in ('pending_approval', 'approved', 'assigned')
     or (v_from = 'pending_approval' and p_to_status = 'draft') then
    raise exception 'use_dedicated_workflow_rpc';
  end if;

  if p_to_status = 'completed' then
    if not private.has_permission('document.complete') then
      raise exception 'permission_denied';
    end if;
  elsif p_to_status = 'archived' then
    if not private.has_permission('document.archive') then
      raise exception 'permission_denied';
    end if;
  elsif not private.has_permission('document.update') then
    raise exception 'permission_denied';
  end if;

  if not private.is_valid_document_transition(p_document_id, v_from, p_to_status) then
    raise exception 'invalid_status_transition';
  end if;

  update public.documents set status = p_to_status where id = p_document_id;

  insert into public.document_status_history
    (document_id, from_status, to_status, changed_by, reason)
  values
    (p_document_id, v_from, p_to_status, v_actor, p_reason);

  if p_to_status in ('completed', 'archived') then
    update public.deadlines
    set status = 'completed', completed_at = coalesce(completed_at, now())
    where document_id = p_document_id and status = 'open';
  end if;

  return true;
end
$function$;

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
    select 1 from public.profiles
    where id = p_approver_id and is_active = true
  ) then
    raise exception 'approver_not_found';
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
