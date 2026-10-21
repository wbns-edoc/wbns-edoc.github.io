-- Draft-only notification outbox lease and in-app delivery primitives.
-- Never apply to Production without review and explicit release approval.
begin;

alter table public.staff_leave_notification_outbox
  add column if not exists lease_token uuid,
  add column if not exists lease_expires_at timestamptz,
  add column if not exists last_attempt_at timestamptz;

create table if not exists public.staff_leave_notifications (
  id uuid primary key default gen_random_uuid(),
  recipient_id uuid not null references public.profiles(id) on delete restrict,
  event_key text not null,
  request_id uuid not null references public.staff_leave_requests(id) on delete restrict,
  event_type text not null check (event_type in (
    'submitted','approver_assigned','approved','rejected','cancelled','blocked','overdue'
  )),
  safe_payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  read_at timestamptz,
  constraint staff_leave_notifications_recipient_event_unique unique (recipient_id, event_key)
);
create index if not exists staff_leave_notifications_recipient_created_idx
  on public.staff_leave_notifications(recipient_id, created_at desc);

alter table public.staff_leave_notifications enable row level security;
drop policy if exists staff_leave_notifications_recipient_read on public.staff_leave_notifications;
create policy staff_leave_notifications_recipient_read
  on public.staff_leave_notifications for select to authenticated
  using (
    recipient_id = (select auth.uid())
    and exists (
      select 1 from public.profiles p
      where p.id = (select auth.uid()) and p.is_active = true
    )
  );
drop policy if exists staff_leave_notifications_recipient_mark_read on public.staff_leave_notifications;
create policy staff_leave_notifications_recipient_mark_read
  on public.staff_leave_notifications for update to authenticated
  using (
    recipient_id = (select auth.uid())
    and exists (
      select 1 from public.profiles p
      where p.id = (select auth.uid()) and p.is_active = true
    )
  )
  with check (
    recipient_id = (select auth.uid())
    and exists (
      select 1 from public.profiles p
      where p.id = (select auth.uid()) and p.is_active = true
    )
  );

revoke all privileges on table public.staff_leave_notifications from public, anon, authenticated;
grant select on public.staff_leave_notifications to authenticated;
grant update (read_at) on public.staff_leave_notifications to authenticated;

create or replace function public.staff_leave_outbox_claim(p_limit integer default 20, p_lease_seconds integer default 90)
returns table (
  outbox_id uuid,
  lease_token uuid,
  event_key text,
  request_id uuid,
  recipient_id uuid,
  event_type text,
  channel text,
  safe_payload jsonb,
  attempts integer
)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if p_limit is null or p_limit < 1 or p_limit > 100
     or p_lease_seconds is null or p_lease_seconds < 15 or p_lease_seconds > 600 then
    raise exception 'INVALID_CLAIM_PARAMETERS' using errcode = '22023';
  end if;

  return query
  with candidates as (
    select o.id
    from public.staff_leave_notification_outbox o
    where (
      (o.status in ('pending','retry') and o.available_at <= now())
      or (o.status = 'processing' and o.lease_expires_at <= now())
    )
    order by o.available_at, o.created_at, o.id
    for update skip locked
    limit p_limit
  ), claimed as (
    update public.staff_leave_notification_outbox o
    set status = 'processing',
        lease_token = gen_random_uuid(),
        lease_expires_at = now() + make_interval(secs => p_lease_seconds),
        attempts = o.attempts + 1,
        last_attempt_at = now(),
        last_error_code = null
    from candidates c
    where o.id = c.id
    returning o.id, o.lease_token, o.event_key, o.request_id, o.recipient_id,
      o.event_type, o.channel, o.safe_payload, o.attempts
  )
  select c.id, c.lease_token, c.event_key, c.request_id, c.recipient_id,
    c.event_type, c.channel, c.safe_payload, c.attempts
  from claimed c;
end;
$$;

create or replace function public.staff_leave_outbox_deliver_in_app(p_outbox_id uuid, p_lease_token uuid)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  o public.staff_leave_notification_outbox%rowtype;
begin
  select * into o
  from public.staff_leave_notification_outbox
  where id = p_outbox_id
  for update;

  if not found or o.status <> 'processing' or o.lease_token is distinct from p_lease_token
     or o.lease_expires_at <= now() then
    raise exception 'OUTBOX_LEASE_INVALID' using errcode = '55000';
  end if;
  if o.channel <> 'in_app' then
    raise exception 'CHANNEL_NOT_IMPLEMENTED' using errcode = '0A000';
  end if;

  insert into public.staff_leave_notifications
    (recipient_id, event_key, request_id, event_type, safe_payload)
  values
    (o.recipient_id, o.event_key, o.request_id, o.event_type, o.safe_payload)
  on conflict (recipient_id, event_key) do nothing;

  update public.staff_leave_notification_outbox
  set status = 'sent', sent_at = now(), lease_token = null,
      lease_expires_at = null, last_error_code = null
  where id = o.id;

  return true;
end;
$$;

create or replace function public.staff_leave_outbox_fail(
  p_outbox_id uuid, p_lease_token uuid, p_error_code text, p_permanent boolean default false
)
returns text
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  o public.staff_leave_notification_outbox%rowtype;
  v_status text;
  v_delay integer;
  v_code text;
begin
  select * into o
  from public.staff_leave_notification_outbox
  where id = p_outbox_id
  for update;

  if not found or o.status <> 'processing' or o.lease_token is distinct from p_lease_token
     or o.lease_expires_at <= now() then
    raise exception 'OUTBOX_LEASE_INVALID' using errcode = '55000';
  end if;

  v_code := case
    when p_error_code ~ '^[A-Z0-9_]{1,64}$' then p_error_code
    else 'DELIVERY_FAILED'
  end;
  if coalesce(p_permanent, false) or o.attempts >= 8 then
    v_status := 'dead_letter';
  else
    v_status := 'retry';
  end if;
  v_delay := least(3600, 15 * (2 ^ least(greatest(o.attempts - 1, 0), 8))::integer);

  update public.staff_leave_notification_outbox
  set status = v_status,
      available_at = case when v_status = 'retry' then now() + make_interval(secs => v_delay) else available_at end,
      lease_token = null, lease_expires_at = null, last_error_code = v_code
  where id = o.id;

  return v_status;
end;
$$;

revoke all on function public.staff_leave_outbox_claim(integer, integer) from public, anon, authenticated;
revoke all on function public.staff_leave_outbox_deliver_in_app(uuid, uuid) from public, anon, authenticated;
revoke all on function public.staff_leave_outbox_fail(uuid, uuid, text, boolean) from public, anon, authenticated;
grant execute on function public.staff_leave_outbox_claim(integer, integer) to service_role;
grant execute on function public.staff_leave_outbox_deliver_in_app(uuid, uuid) to service_role;
grant execute on function public.staff_leave_outbox_fail(uuid, uuid, text, boolean) to service_role;

commit;
