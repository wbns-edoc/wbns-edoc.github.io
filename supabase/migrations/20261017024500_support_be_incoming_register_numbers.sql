-- Configure incoming register start numbers and display registration years in Buddhist Era.
insert into public.system_settings(setting_key, setting_value)
values ('incoming_start_number', '1')
on conflict (setting_key) do nothing;

create or replace function public.admin_get_system_settings()
returns jsonb language plpgsql security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_uid uuid := auth.uid();
  v_school text;
  v_register_id uuid;
  v_year integer := extract(year from (now() at time zone 'Asia/Bangkok'))::integer;
  v_current bigint;
  v_start bigint;
begin
  if v_uid is null or not exists (
    select 1 from public.user_roles ur join public.roles r on r.id = ur.role_id
    where ur.user_id = v_uid and r.code = 'system_admin'
  ) then raise exception using errcode = '42501', message = 'system_admin_required'; end if;
  select setting_value into v_school from public.system_settings where setting_key = 'school_name';
  select setting_value::bigint into v_start from public.system_settings where setting_key = 'incoming_start_number';
  select id into v_register_id from public.document_registers
    where direction = 'incoming' and is_active = true order by created_at desc limit 1;
  if v_register_id is not null then
    select current_number into v_current from public.number_sequences where register_id = v_register_id and year = v_year;
  end if;
  return jsonb_build_object('school_name', coalesce(v_school, 'โรงเรียนวัดบึงน้ำใส'),
    'incoming_register_year', v_year + 543,
    'incoming_start_number', greatest(coalesce(v_start, 1), 1),
    'incoming_next_number', coalesce(v_current, coalesce(v_start, 1) - 1) + 1);
end;
$$;

create or replace function public.admin_save_system_settings(
  p_school_name text, p_incoming_start_number bigint, p_incoming_next_number bigint
)
returns jsonb language plpgsql security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_uid uuid := auth.uid();
  v_register_id uuid;
  v_year integer := extract(year from (now() at time zone 'Asia/Bangkok'))::integer;
  v_current bigint;
  v_max_registered bigint;
  v_min_next bigint;
  v_old_school text;
  v_old_start bigint;
begin
  if v_uid is null or not exists (
    select 1 from public.user_roles ur join public.roles r on r.id = ur.role_id
    where ur.user_id = v_uid and r.code = 'system_admin'
  ) then raise exception using errcode = '42501', message = 'system_admin_required'; end if;
  if p_school_name is null or length(btrim(p_school_name)) < 3 or length(btrim(p_school_name)) > 200 then
    raise exception using errcode = '22023', message = 'school_name_must_be_3_to_200_chars';
  end if;
  if p_incoming_start_number is null or p_incoming_start_number < 1 then
    raise exception using errcode = '22023', message = 'incoming_start_number_must_be_positive';
  end if;
  if p_incoming_next_number is null or p_incoming_next_number < 1 then
    raise exception using errcode = '22023', message = 'incoming_number_must_be_positive';
  end if;
  select setting_value into v_old_school from public.system_settings where setting_key = 'school_name';
  select setting_value::bigint into v_old_start from public.system_settings where setting_key = 'incoming_start_number';
  insert into public.system_settings(setting_key, setting_value, updated_by, updated_at)
  values ('school_name', btrim(p_school_name), v_uid, now())
  on conflict (setting_key) do update set setting_value = excluded.setting_value, updated_by = excluded.updated_by, updated_at = now();
  insert into public.system_settings(setting_key, setting_value, updated_by, updated_at)
  values ('incoming_start_number', p_incoming_start_number::text, v_uid, now())
  on conflict (setting_key) do update set setting_value = excluded.setting_value, updated_by = excluded.updated_by, updated_at = now();
  select id into v_register_id from public.document_registers
    where direction = 'incoming' and is_active = true order by created_at desc limit 1;
  if v_register_id is null then raise exception using errcode = 'P0001', message = 'active_incoming_register_not_found'; end if;
  insert into public.number_sequences(register_id, year, current_number)
  values (v_register_id, v_year, p_incoming_start_number - 1)
  on conflict (register_id, year) do nothing;
  select current_number into v_current from public.number_sequences
  where register_id = v_register_id and year = v_year for update;
  select coalesce(max(i.registered_number), 0) into v_max_registered
  from public.incoming_document_details i join public.documents d on d.id = i.document_id
  where d.register_id = v_register_id and i.registered_at is not null
    and extract(year from (i.registered_at at time zone 'Asia/Bangkok'))::integer = v_year;
  v_min_next := greatest(coalesce(v_current, 0) + 1, v_max_registered + 1);
  if p_incoming_next_number < v_min_next then
    raise exception using errcode = '22023', message = 'incoming_number_cannot_move_backwards';
  end if;
  update public.number_sequences set current_number = p_incoming_next_number - 1, updated_at = now()
  where register_id = v_register_id and year = v_year;
  insert into public.audit_logs(actor_id, action, entity_type, old_data, new_data)
  values (v_uid, 'update_system_settings', 'system_settings',
    jsonb_build_object('school_name', v_old_school, 'incoming_start_number', v_old_start),
    jsonb_build_object('school_name', btrim(p_school_name), 'incoming_start_number', p_incoming_start_number,
      'incoming_next_number', p_incoming_next_number, 'incoming_register_year', v_year + 543));
  return jsonb_build_object('ok', true, 'school_name', btrim(p_school_name),
    'incoming_start_number', p_incoming_start_number, 'incoming_register_year', v_year + 543,
    'incoming_next_number', p_incoming_next_number);
end;
$$;

create or replace function private.register_incoming_document(
  p_subject text, p_sender_id uuid, p_external_document_no text, p_external_document_date date,
  p_received_at timestamptz, p_urgency public.urgency_level, p_receiving_notes text, p_department_id uuid
)
returns uuid language plpgsql security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_uid uuid := auth.uid();
  v_register uuid;
  v_doc uuid;
  v_no bigint;
  v_year integer := extract(year from (now() at time zone 'Asia/Bangkok'))::integer;
  v_start bigint;
begin
  if v_uid is null or not private.has_permission('registry.incoming.manage') then
    raise exception using errcode = '42501', message = 'permission denied';
  end if;
  if not exists (select 1 from public.profiles pr where pr.id = v_uid and pr.is_active = true) then
    raise exception using errcode = '42501', message = 'active_profile_required';
  end if;
  if p_department_id is null or not exists (select 1 from public.departments d where d.id = p_department_id and d.is_active = true) then
    raise exception using errcode = '23503', message = 'active_document_department_required';
  end if;
  if not private.user_has_department(v_uid, p_department_id)
     and not exists (select 1 from public.user_roles ur join public.roles r on r.id=ur.role_id
       where ur.user_id=v_uid and r.code='system_admin') then
    raise exception using errcode = '42501', message = 'department_scope_denied';
  end if;
  if not exists (select 1 from public.senders s where s.id = p_sender_id and s.is_active = true) then
    raise exception using errcode = '23503', message = 'active_sender_required';
  end if;
  select id into v_register from public.document_registers
    where direction = 'incoming' and is_active = true order by created_at desc limit 1;
  if v_register is null then raise exception 'ไม่พบทะเบียนหนังสือรับที่ใช้งานอยู่'; end if;
  select coalesce(setting_value::bigint, 1) into v_start from public.system_settings where setting_key = 'incoming_start_number';
  v_start := greatest(coalesce(v_start, 1), 1);
  insert into public.number_sequences(register_id, year, current_number)
  values (v_register, v_year, v_start - 1)
  on conflict (register_id, year) do nothing;
  v_no := private.allocate_document_number(v_register, v_year);
  insert into public.documents(document_type, register_id, department_id, subject, urgency, status, current_owner_id, created_by)
    values ('incoming', v_register, p_department_id, p_subject, p_urgency, 'received', v_uid, v_uid)
    returning id into v_doc;
  insert into public.incoming_document_details(document_id, sender_id, external_document_no, external_document_date,
    received_at, registered_at, registered_number, receiving_notes)
    values (v_doc, p_sender_id, p_external_document_no, p_external_document_date, p_received_at, now(), v_no, p_receiving_notes);
  insert into public.document_status_history(document_id, from_status, to_status, changed_by, reason)
    values (v_doc, null, 'received', v_uid, 'รับหนังสือเข้าระบบ');
  return v_doc;
end;
$$;

revoke all on function public.admin_save_system_settings(text, bigint) from public, anon;
revoke all on function public.admin_save_system_settings(text, bigint, bigint) from public, anon;
grant execute on function public.admin_get_system_settings() to authenticated;
grant execute on function public.admin_save_system_settings(text, bigint, bigint) to authenticated;
