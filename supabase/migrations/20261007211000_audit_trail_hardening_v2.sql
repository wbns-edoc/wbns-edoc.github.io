drop index if exists public.idx_audit_entity;
create or replace function private.audit_row_change() returns trigger
language plpgsql security definer set search_path=pg_catalog,public,private
as $$
declare
  v_actor uuid := auth.uid();
  v_old jsonb := case when TG_OP in ('UPDATE','DELETE') then to_jsonb(OLD) else null end;
  v_new jsonb := case when TG_OP in ('INSERT','UPDATE') then to_jsonb(NEW) else null end;
  v_entity_id uuid;
begin
  begin
    v_entity_id := coalesce((v_new->>'id')::uuid,(v_old->>'id')::uuid,(v_new->>'document_id')::uuid,(v_old->>'document_id')::uuid);
  exception when others then v_entity_id := null;
  end;
  insert into public.audit_logs(actor_id,action,entity_type,entity_id,old_data,new_data)
  values(v_actor,TG_OP,replace(TG_TABLE_NAME,'_',' '),v_entity_id,v_old,v_new);
  if TG_OP='DELETE' then return OLD; end if;
  return NEW;
end $$;