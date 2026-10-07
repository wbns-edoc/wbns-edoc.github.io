-- Assignment is the registered -> assigned workflow transition.
create or replace function public.assign_document(p_document_id uuid,p_assignee_id uuid,p_instructions text default null,p_due_at timestamptz default null) returns uuid
language plpgsql security definer set search_path=pg_catalog,public,private as $$
declare v_id uuid; v_actor uuid:=auth.uid(); v_subject text; v_old document_status;
begin
 if v_actor is null or not private.has_permission('document.assign') then raise exception 'permission_denied'; end if;
 if not exists(select 1 from public.documents where id=p_document_id) then raise exception 'document_not_found'; end if;
 if not exists(select 1 from public.profiles where id=p_assignee_id and is_active=true) then raise exception 'assignee_not_found'; end if;
 if p_due_at is not null and p_due_at<=now() then raise exception 'deadline_must_be_future'; end if;
 select status,subject into v_old,v_subject from public.documents where id=p_document_id for update;
 if v_old<>'registered' then raise exception 'invalid_status_transition'; end if;
 insert into public.document_assignments(document_id,assignee_id,assigned_by,instructions,assignment_status) values(p_document_id,p_assignee_id,v_actor,p_instructions,'assigned') returning id into v_id;
 update public.documents set current_owner_id=p_assignee_id,status='assigned' where id=p_document_id;
 insert into public.document_status_history(document_id,from_status,to_status,changed_by,reason) values(p_document_id,v_old,'assigned',v_actor,'มอบหมายงาน');
 insert into public.notifications(recipient_id,document_id,type,title,body,priority) values(p_assignee_id,p_document_id,'assignment','ได้รับมอบหมายงาน','คุณได้รับมอบหมายเรื่อง: '||coalesce(v_subject,'ไม่ระบุเรื่อง'),'high');
 if p_due_at is not null then insert into public.deadlines(document_id,assigned_to,due_at,reminder_at,escalation_at,status) values(p_document_id,p_assignee_id,p_due_at,p_due_at-interval '24 hours',p_due_at,'open'); end if;
 return v_id;
end $$;

revoke all on function public.assign_document(uuid,uuid,text,timestamptz) from public;
grant execute on function public.assign_document(uuid,uuid,text,timestamptz) to authenticated;
