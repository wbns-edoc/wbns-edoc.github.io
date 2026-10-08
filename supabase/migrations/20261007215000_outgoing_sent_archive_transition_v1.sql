create or replace function private.is_valid_document_transition(p_document_id uuid,p_from document_status,p_to document_status)
returns boolean
language plpgsql
stable
security definer
set search_path=pg_catalog,public,private
as $$
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
  if p_from='sent' and p_to='archived' then return v_type='outgoing'; end if;
  return false;
end $$;
