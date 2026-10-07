-- Harden workflow RPC exposure.
-- Move SECURITY DEFINER implementations into private schema and expose only SECURITY INVOKER wrappers.
alter function public.assign_document(uuid,uuid,text,timestamptz) set schema private;
alter function public.update_document_status(uuid,document_status,text) set schema private;
alter function public.create_approval(uuid,uuid,integer) set schema private;
alter function public.decide_approval(uuid,approval_decision,text) set schema private;
alter function public.set_document_deadline(uuid,uuid,timestamptz,timestamptz) set schema private;

create or replace function public.assign_document(p_document_id uuid,p_assignee_id uuid,p_instructions text default null,p_due_at timestamptz default null) returns uuid language sql security invoker set search_path=pg_catalog,public,private as $$select private.assign_document($1,$2,$3,$4)$$;
create or replace function public.update_document_status(p_document_id uuid,p_to_status document_status,p_reason text default null) returns boolean language sql security invoker set search_path=pg_catalog,public,private as $$select private.update_document_status($1,$2,$3)$$;
create or replace function public.create_approval(p_document_id uuid,p_approver_id uuid,p_approval_step integer default 1) returns uuid language sql security invoker set search_path=pg_catalog,public,private as $$select private.create_approval($1,$2,$3)$$;
create or replace function public.decide_approval(p_approval_id uuid,p_decision approval_decision,p_comment text default null) returns boolean language sql security invoker set search_path=pg_catalog,public,private as $$select private.decide_approval($1,$2,$3)$$;
create or replace function public.set_document_deadline(p_document_id uuid,p_assigned_to uuid,p_due_at timestamptz,p_reminder_at timestamptz default null) returns uuid language sql security invoker set search_path=pg_catalog,public,private as $$select private.set_document_deadline($1,$2,$3,$4)$$;

revoke all on function public.assign_document(uuid,uuid,text,timestamptz) from public,anon;
revoke all on function public.update_document_status(uuid,document_status,text) from public,anon;
revoke all on function public.create_approval(uuid,uuid,integer) from public,anon;
revoke all on function public.decide_approval(uuid,approval_decision,text) from public,anon;
revoke all on function public.set_document_deadline(uuid,uuid,timestamptz,timestamptz) from public,anon;
grant execute on function public.assign_document(uuid,uuid,text,timestamptz) to authenticated;
grant execute on function public.update_document_status(uuid,document_status,text) to authenticated;
grant execute on function public.create_approval(uuid,uuid,integer) to authenticated;
grant execute on function public.decide_approval(uuid,approval_decision,text) to authenticated;
grant execute on function public.set_document_deadline(uuid,uuid,timestamptz,timestamptz) to authenticated;
