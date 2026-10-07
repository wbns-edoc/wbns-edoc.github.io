-- Enforce allowed document status transitions in the database.
create or replace function private.is_valid_document_transition(p_document_id uuid,p_from document_status,p_to document_status) returns boolean
language plpgsql stable security definer set search_path=pg_catalog,public,private as $$
declare v_type text;
begin
 select document_type::text into v_type from public.documents where id=p_document_id;
 if v_type is null then return false; end if;
 if p_to='cancelled' and p_from not in ('completed','archived','cancelled') then return true; end if;
 if p_from='draft' and p_to='pending_approval' then return true; end if;
 if p_from='pending_approval' and p_to in ('approved','draft') then return true; end if;
 if p_from='approved' and p_to='received' then return v_type='incoming'; end if;
 if p_from='approved' and p_to='sent' then return v_type='outgoing'; end if;
 if p_from='received' and p_to='registered' then return v_type='incoming'; end if;
 if p_from='registered' and p_to='assigned' then return true; end if;
 if p_from='assigned' and p_to='in_progress' then return true; end if;
 if p_from='in_progress' and p_to='completed' then return true; end if;
 if p_from='completed' and p_to='archived' then return true; end if;
 return false;
end $$;

create or replace function public.update_document_status(p_document_id uuid,p_to_status document_status,p_reason text default null) returns boolean
language plpgsql security definer set search_path=pg_catalog,public,private as $$
declare v_actor uuid:=auth.uid(); v_from document_status;
begin
 if v_actor is null or not(private.has_permission('document.update') or private.has_permission('document.complete')) then raise exception 'permission_denied'; end if;
 select status into v_from from public.documents where id=p_document_id for update;
 if v_from is null then raise exception 'document_not_found'; end if;
 if v_from=p_to_status then return true; end if;
 if not private.is_valid_document_transition(p_document_id,v_from,p_to_status) then raise exception 'invalid_status_transition'; end if;
 update public.documents set status=p_to_status where id=p_document_id;
 insert into public.document_status_history(document_id,from_status,to_status,changed_by,reason) values(p_document_id,v_from,p_to_status,v_actor,p_reason);
 if p_to_status in('completed','archived') then update public.deadlines set status='completed',completed_at=coalesce(completed_at,now()) where document_id=p_document_id and status='open'; end if;
 return true;
end $$;

revoke all on function private.is_valid_document_transition(uuid,document_status,document_status) from public;
revoke all on function public.update_document_status(uuid,document_status,text) from public;
grant execute on function public.update_document_status(uuid,document_status,text) to authenticated;
