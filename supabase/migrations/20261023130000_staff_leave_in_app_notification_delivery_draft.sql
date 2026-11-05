-- Draft-only in-app delivery for the staff leave transactional outbox.
-- This uses the existing private-per-recipient public.notifications feed.
-- No email/push provider, secret, scheduled job, or paid service is required.
begin;

create or replace function public.staff_leave_deliver_in_app_notification()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_title text;
  v_body text;
  v_priority text;
begin
  if new.channel <> 'in_app' then
    return new;
  end if;

  case new.event_type
    when 'submitted' then
      v_title := 'มีใบลารอพิจารณา';
      v_body := 'มีคำขอลาใหม่ที่ต้องดำเนินการ';
      v_priority := 'high';
    when 'approver_assigned' then
      v_title := 'มีใบลารอพิจารณา';
      v_body := 'มีคำขอลาที่ส่งต่อมายังขั้นตอนของคุณ';
      v_priority := 'high';
    when 'approved' then
      v_title := 'ใบลาได้รับอนุมัติ';
      v_body := 'คำขอลาของคุณได้รับการอนุมัติแล้ว';
      v_priority := 'normal';
    when 'rejected' then
      v_title := 'ผลการพิจารณาใบลา';
      v_body := 'คำขอลาของคุณไม่ได้รับการอนุมัติ โปรดเข้าสู่ระบบเพื่อตรวจสอบ';
      v_priority := 'normal';
    when 'cancelled' then
      v_title := 'ยกเลิกใบลาแล้ว';
      v_body := 'มีการบันทึกการยกเลิกคำขอลา';
      v_priority := 'normal';
    when 'blocked' then
      v_title := 'ใบลารอการตรวจสอบ';
      v_body := 'คำขอลายังไม่ถูกส่งให้ผู้อนุมัติ เนื่องจากต้องตรวจสอบการกำหนดผู้รับผิดชอบ';
      v_priority := 'high';
    when 'overdue' then
      v_title := 'แจ้งเตือนตรวจสอบการกลับเข้าปฏิบัติงาน';
      v_body := 'มีรายการที่ถึงกำหนดกลับเข้าปฏิบัติงานและรอการตรวจสอบ';
      v_priority := 'high';
    else
      raise exception 'unsupported_staff_leave_notification_event: %', new.event_type;
  end case;

  insert into public.notifications (
    recipient_id, document_id, type, title, body, priority
  ) values (
    new.recipient_id, null, 'staff_leave_' || new.event_type,
    v_title, v_body, v_priority
  );

  update public.staff_leave_notification_outbox
     set status = 'sent',
         sent_at = statement_timestamp(),
         last_error_code = null
   where id = new.id
     and status in ('pending','retry','processing');

  return new;
end;
$$;

drop trigger if exists staff_leave_outbox_deliver_in_app
  on public.staff_leave_notification_outbox;
create trigger staff_leave_outbox_deliver_in_app
after insert on public.staff_leave_notification_outbox
for each row
when (new.channel = 'in_app')
execute function public.staff_leave_deliver_in_app_notification();

revoke all on function public.staff_leave_deliver_in_app_notification()
  from public, anon, authenticated;

commit;
