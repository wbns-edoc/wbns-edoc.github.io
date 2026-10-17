-- Admin-managed school identity and incoming register sequence settings.
create table if not exists public.system_settings (
  setting_key text primary key,
  setting_value text not null,
  updated_by uuid references public.profiles(id) on delete set null,
  updated_at timestamptz not null default now()
);
alter table public.system_settings enable row level security;
revoke all on public.system_settings from anon, authenticated;
insert into public.system_settings(setting_key, setting_value)
values ('school_name', 'โรงเรียนวัดบึงน้ำใส')
on conflict (setting_key) do nothing;

create or replace function public.get_public_school_name()
returns text
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select coalesce((select setting_value from public.system_settings where setting_key = 'school_name'), 'โรงเรียนวัดบึงน้ำใส');
$$;
revoke all on function public.get_public_school_name() from public;
grant execute on function public.get_public_school_name() to anon, authenticated;

create or replace function public.admin_get_system_settings()
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_uid uuid := auth.uid();
  v_school text;
  v_register_id uuid;
  v_year integer;
  v_current bigint;
begin
  if v_uid is null or not exists (
    select 1 from public.user_roles ur join public.roles r on r.id = ur.role_id
    where ur.user_id = v_uid and r.code = 'system_admin'
  ) then raise exception using errcode = '42501', message = 'system_admin_required'; end if;
  select setting_value into v_school from public.system_settings where setting_key = 'school_name';
  select id, document_year into v_register_id, v_year from public.document_registers
    where direction = 'incoming' and is_active = true order by document_year desc, created_at desc limit 1;
  if v_register_id is not null then
    select current_number into v_current from public.number_sequences where register_id = v_register_id and year = v_year;
  end if;
  return jsonb_build_object('school_name', coalesce(v_school, 'โรงเรียนวัดบึงน้ำใส'),
    'incoming_register_year', v_year, 'incoming_next_number', coalesce(v_current, 0) + 1);
end;
$$;

create or replace function public.admin_save_system_settings(p_school_name text, p_incoming_next_number bigint)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_uid uuid := auth.uid();
  v_register_id uuid;
  v_year integer;
  v_current bigint;
  v_max_registered bigint;
  v_min_next bigint;
  v_old_school text;
begin
  if v_uid is null or not exists (
    select 1 from public.user_roles ur join public.roles r on r.id = ur.role_id
    where ur.user_id = v_uid and r.code = 'system_admin'
  ) then raise exception using errcode = '42501', message = 'system_admin_required'; end if;
  if p_school_name is null or length(btrim(p_school_name)) < 3 or length(btrim(p_school_name)) > 200 then
    raise exception using errcode = '22023', message = 'school_name_must_be_3_to_200_chars';
  end if;
  if p_incoming_next_number is null or p_incoming_next_number < 1 then
    raise exception using errcode = '22023', message = 'incoming_number_must_be_positive';
  end if;

  select setting_value into v_old_school from public.system_settings where setting_key = 'school_name';
  insert into public.system_settings(setting_key, setting_value, updated_by, updated_at)
  values ('school_name', btrim(p_school_name), v_uid, now())
  on conflict (setting_key) do update set setting_value = excluded.setting_value, updated_by = excluded.updated_by, updated_at = now();

  select id, document_year into v_register_id, v_year from public.document_registers
    where direction = 'incoming' and is_active = true order by document_year desc, created_at desc limit 1;
  if v_register_id is null then raise exception using errcode = 'P0001', message = 'active_incoming_register_not_found'; end if;
  insert into public.number_sequences(register_id, year, current_number) values (v_register_id, v_year, 0)
  on conflict (register_id, year) do nothing;
  select current_number into v_current from public.number_sequences
  where register_id = v_register_id and year = v_year for update;
  select coalesce(max(i.registered_number), 0) into v_max_registered
  from public.incoming_document_details i join public.documents d on d.id = i.document_id
  where d.register_id = v_register_id;
  v_min_next := greatest(coalesce(v_current, 0) + 1, v_max_registered + 1);
  if p_incoming_next_number < v_min_next then
    raise exception using errcode = '22023', message = 'incoming_number_cannot_move_backwards';
  end if;
  update public.number_sequences set current_number = p_incoming_next_number - 1, updated_at = now()
  where register_id = v_register_id and year = v_year;
  insert into public.audit_logs(actor_id, action, entity_type, old_data, new_data)
  values (v_uid, 'update_system_settings', 'system_settings',
    jsonb_build_object('school_name', v_old_school),
    jsonb_build_object('school_name', btrim(p_school_name), 'incoming_next_number', p_incoming_next_number, 'incoming_register_year', v_year));
  return jsonb_build_object('ok', true, 'school_name', btrim(p_school_name),
    'incoming_register_year', v_year, 'incoming_next_number', p_incoming_next_number);
end;
$$;
revoke all on function public.admin_get_system_settings() from public, anon;
revoke all on function public.admin_save_system_settings(text, bigint) from public, anon;
grant execute on function public.admin_get_system_settings() to authenticated;
grant execute on function public.admin_save_system_settings(text, bigint) to authenticated;
