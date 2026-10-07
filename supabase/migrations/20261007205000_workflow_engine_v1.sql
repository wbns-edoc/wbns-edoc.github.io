-- WBNS workflow engine v1
-- Applied to Supabase project iigzzwyfxxtqbgjawyom as migration workflow_engine_v1.

create or replace function public.assign_document(p_document_id uuid,p_assignee_id uuid,p_instructions text default null,p_due_at timestamptz default null) returns uuid
language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_id uuid; v_actor uuid:=auth.uid(); v_subject text; v_old document_status;
begin
 if v_actor is null or not private.has_permission('document.assign') then raise exception 'permission_denied'; end if;
 if not exists(select 1 from public.documents where id=p_document_id) then raise exception 'document_not_found'; end if;
 if not exists(select 1 from public.profiles where id=p_assignee_id and is_active=true) then raise exception 'assignee_not_found'; end if;
 select status,subject into v_old,v_subject from public.documents where id=p_document_id for update;
 insert into public.document_assignments(document_id,assignee_id,assigned_by,instructions,assignment_status) values(p_document_id,p_assignee_id,v_actor,p_instructions,'assigned') returning id into v_id;
 update public.documents set current_owner_id=p_assignee_id,status='assigned' where id=p_document_id;
 if v_old <> 'assigned' then insert into public.document_status_history(document_id,from_status,to_status,changed_by,reason) values(p_document_id,v_old,'assigned',v_actor,'มอบหมายงาน'); end if;
 insert into public.notifications(recipient_id,document_id,type,title,body,priority) values(p_assignee_id,p_document_id,'assignment','ได้รับมอบหมายงาน','คุณได้รับมอบหมายเรื่อง: '||coalesce(v_subject,'ไม่ระบุเรื่อง'),'high');
 if p_due_at is not null then insert into public.deadlines(document_id,assigned_to,due_at,reminder_at,escalation_at,status) values(p_document_id,p_assignee_id,p_due_at,p_due_at-interval '24 hours',p_due_at,'open'); end if;
 return v_id;
end $$;

create or replace function public.update_document_status(p_document_id uuid,p_to_status document_status,p_reason text default null) returns boolean
language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_actor uuid:=auth.uid(); v_from document_status;
begin
 if v_actor is null or not(private.has_permission('document.update') or private.has_permission('document.complete')) then raise exception 'permission_denied'; end if;
 select status into v_from from public.documents where id=p_document_id for update;
 if v_from is null then raise exception 'document_not_found'; end if;
 if v_from=p_to_status then return true; end if;
 update public.documents set status=p_to_status where id=p_document_id;
 insert into public.document_status_history(document_id,from_status,to_status,changed_by,reason) values(p_document_id,v_from,p_to_status,v_actor,p_reason);
 if p_to_status in('completed','archived') then update public.deadlines set status='completed',completed_at=coalesce(completed_at,now()) where document_id=p_document_id and status='open'; end if;
 return true;
end $$;

create or replace function public.create_approval(p_document_id uuid,p_approver_id uuid,p_approval_step integer default 1) returns uuid
language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_id uuid; v_actor uuid:=auth.uid(); v_subject text;
begin
 if v_actor is null or not private.has_permission('document.approve') then raise exception 'permission_denied'; end if;
 if p_approval_step<1 then raise exception 'invalid_approval_step'; end if;
 if not exists(select 1 from public.profiles where id=p_approver_id and is_active=true) then raise exception 'approver_not_found'; end if;
 insert into public.approvals(document_id,approval_step,approver_id,decision) values(p_document_id,p_approval_step,p_approver_id,'pending') returning id into v_id;
 update public.documents set status='pending_approval' where id=p_document_id;
 select subject into v_subject from public.documents where id=p_document_id;
 insert into public.notifications(recipient_id,document_id,type,title,body,priority) values(p_approver_id,p_document_id,'approval','รอการอนุมัติ','มีเอกสารรอการอนุมัติ: '||coalesce(v_subject,'ไม่ระบุเรื่อง'),'high');
 return v_id;
end $$;

create or replace function public.decide_approval(p_approval_id uuid,p_decision approval_decision,p_comment text default null) returns boolean
language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_actor uuid:=auth.uid(); v_doc uuid; v_step integer; v_subject text;
begin
 if v_actor is null or not private.has_permission('document.approve') then raise exception 'permission_denied'; end if;
 select document_id,approval_step into v_doc,v_step from public.approvals where id=p_approval_id and approver_id=v_actor and decision='pending' for update;
 if v_doc is null then raise exception 'approval_not_found_or_not_authorized'; end if;
 update public.approvals set decision=p_decision,comment=p_comment,decided_at=now() where id=p_approval_id;
 if p_decision='approved' then
   if exists(select 1 from public.approvals where document_id=v_doc and approval_step>v_step and decision='pending') then update public.documents set status='pending_approval' where id=v_doc;
   else update public.documents set status='approved' where id=v_doc; end if;
 elsif p_decision in('rejected','returned') then update public.documents set status='draft' where id=v_doc; end if;
 select subject into v_subject from public.documents where id=v_doc;
 insert into public.notifications(recipient_id,document_id,type,title,body,priority) select d.created_by,v_doc,'approval_decision','ผลการอนุมัติ','เอกสาร "'||coalesce(v_subject,'ไม่ระบุเรื่อง')||'" มีผลการพิจารณา: '||p_decision::text,'high' from public.documents d where d.id=v_doc;
 return true;
end $$;

create or replace function public.set_document_deadline(p_document_id uuid,p_assigned_to uuid,p_due_at timestamptz,p_reminder_at timestamptz default null) returns uuid
language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_id uuid; v_actor uuid:=auth.uid();
begin
 if v_actor is null or not private.has_permission('document.assign') then raise exception 'permission_denied'; end if;
 if p_due_at<=now() then raise exception 'deadline_must_be_future'; end if;
 insert into public.deadlines(document_id,assigned_to,due_at,reminder_at,escalation_at,status) values(p_document_id,p_assigned_to,p_due_at,coalesce(p_reminder_at,p_due_at-interval '24 hours'),p_due_at,'open') returning id into v_id;
 return v_id;
end $$;

create index if not exists idx_document_assignments_assignee_status on public.document_assignments(assignee_id,assignment_status,assigned_at desc);
create index if not exists idx_approvals_approver_decision on public.approvals(approver_id,decision,created_at desc);
create index if not exists idx_deadlines_open_due on public.deadlines(status,due_at);
create index if not exists idx_notifications_recipient_unread on public.notifications(recipient_id,read_at,created_at desc);

revoke all on function public.assign_document(uuid,uuid,text,timestamptz) from public;
revoke all on function public.update_document_status(uuid,document_status,text) from public;
revoke all on function public.create_approval(uuid,uuid,integer) from public;
revoke all on function public.decide_approval(uuid,approval_decision,text) from public;
revoke all on function public.set_document_deadline(uuid,uuid,timestamptz,timestamptz) from public;
grant execute on function public.assign_document(uuid,uuid,text,timestamptz) to authenticated;
grant execute on function public.update_document_status(uuid,document_status,text) to authenticated;
grant execute on function public.create_approval(uuid,uuid,integer) to authenticated;
grant execute on function public.decide_approval(uuid,approval_decision,text) to authenticated;
grant execute on function public.set_document_deadline(uuid,uuid,timestamptz,timestamptz) to authenticated;
