-- Enforce transition-specific permissions in the database.
-- Client-side permission checks are UX only and must not be the security boundary.
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

  if p_to_status = 'completed' then
    if not private.has_permission('document.complete') then
      raise exception 'permission_denied';
    end if;
  elsif p_to_status = 'archived' then
    if not private.has_permission('document.archive') then
      raise exception 'permission_denied';
    end if;
  elsif p_to_status = 'assigned' then
    if not private.has_permission('document.assign') then
      raise exception 'permission_denied';
    end if;
  elsif not private.has_permission('document.update') then
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
