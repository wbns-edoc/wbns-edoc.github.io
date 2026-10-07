-- Notification + deadline engine for WBNS.
create extension if not exists pg_cron with schema pg_catalog;
grant usage on schema cron to postgres;
grant all privileges on all tables in schema cron to postgres;
create schema if not exists extensions;
create extension if not exists pg_trgm with schema extensions;
create index if not exists idx_documents_subject_trgm on public.documents using gin(subject extensions.gin_trgm_ops);
create index if not exists idx_senders_org_trgm on public.senders using gin(organization_name extensions.gin_trgm_ops);
create index if not exists idx_documents_status_urgency_created on public.documents(status,urgency,created_at desc);
create index if not exists idx_deadlines_assignee_due on public.deadlines(assigned_to,due_at) where status='open';
create or replace function private.process_deadline_notifications() returns integer language plpgsql security definer set search_path=pg_catalog,public,private as $$
declare v_count integer:=0; d record; r record; v_subject text;
begin
 for d in select dl.id,dl.document_id,dl.assigned_to,dl.due_at,dl.reminder_at,doc.subject,doc.status from public.deadlines dl join public.documents doc on doc.id=dl.document_id where dl.status='open' and doc.status not in('completed','archived','cancelled') and ((dl.reminder_at is not null and dl.reminder_at<=now() and dl.due_at>now()) or dl.due_at<=now()) loop
  v_subject:=coalesce(d.subject,'ไม่ระบุเรื่อง');
  if d.due_at<=now() then
   if d.assigned_to is not null and not exists(select 1 from public.notifications n where n.document_id=d.document_id and n.recipient_id=d.assigned_to and n.type='deadline_overdue' and n.created_at>=d.due_at) then
    insert into public.notifications(recipient_id,document_id,type,title,body,priority) values(d.assigned_to,d.document_id,'deadline_overdue','เกินกำหนดงาน','งานเรื่อง "'||v_subject||'" เกินกำหนดแล้ว กรุณาดำเนินการทันที','high'); v_count:=v_count+1;
   end if;
   for r in select distinct ur.user_id from public.user_roles ur join public.roles ro on ro.id=ur.role_id where ro.code in('director','deputy_director') loop
    if not exists(select 1 from public.notifications n where n.document_id=d.document_id and n.recipient_id=r.user_id and n.type='deadline_escalation' and n.created_at>=d.due_at) then
     insert into public.notifications(recipient_id,document_id,type,title,body,priority) values(r.user_id,d.document_id,'deadline_escalation','แจ้งเตือนผู้บริหาร: เกินกำหนด','เอกสารเรื่อง "'||v_subject||'" เกินกำหนดดำเนินการแล้ว','critical'); v_count:=v_count+1;
    end if;
   end loop;
  else
   if d.assigned_to is not null and not exists(select 1 from public.notifications n where n.document_id=d.document_id and n.recipient_id=d.assigned_to and n.type='deadline_reminder' and n.created_at>=d.reminder_at) then
    insert into public.notifications(recipient_id,document_id,type,title,body,priority) values(d.assigned_to,d.document_id,'deadline_reminder','ใกล้ครบกำหนดงาน','งานเรื่อง "'||v_subject||'" ใกล้ครบกำหนด กรุณาตรวจสอบและดำเนินการ','high'); v_count:=v_count+1;
   end if;
   for r in select distinct ur.user_id from public.user_roles ur join public.roles ro on ro.id=ur.role_id where ro.code in('director','deputy_director') loop
    if not exists(select 1 from public.notifications n where n.document_id=d.document_id and n.recipient_id=r.user_id and n.type='deadline_reminder_management' and n.created_at>=d.reminder_at) then
     insert into public.notifications(recipient_id,document_id,type,title,body,priority) values(r.user_id,d.document_id,'deadline_reminder_management','แจ้งเตือนผู้บริหาร: ใกล้ครบกำหนด','เอกสารเรื่อง "'||v_subject||'" ใกล้ครบกำหนดดำเนินการ','high'); v_count:=v_count+1;
    end if;
   end loop;
  end if;
 end loop;
 return v_count;
end $$;
revoke all on function private.process_deadline_notifications() from public,anon,authenticated;
select cron.unschedule(jobid) from cron.job where jobname='wbns-deadline-notifications';
select cron.schedule('wbns-deadline-notifications','*/15 * * * *',$$select private.process_deadline_notifications();$$);