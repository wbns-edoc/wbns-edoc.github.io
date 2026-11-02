-- Draft-only private Storage for staff-leave evidence and supporting files.
-- Apply only in isolated Integration/CI until the full Production release gate passes.
-- Objects are private, request-scoped, and readable only by the applicant or current approver.
begin;

do $preflight$
begin
  if to_regclass('storage.buckets') is null or to_regclass('storage.objects') is null then
    raise exception 'staff_leave_private_storage_requires_supabase_storage_schema';
  end if;
  if to_regclass('public.staff_leave_attachments') is null
     or to_regclass('public.staff_leave_requests') is null then
    raise exception 'staff_leave_private_storage_requires_leave_schema';
  end if;
  if not has_table_privilege('authenticated','storage.objects','INSERT')
     or not has_table_privilege('authenticated','storage.objects','SELECT') then
    raise exception 'staff_leave_private_storage_requires_authenticated_storage_object_api_grants';
  end if;
  if exists (
    select 1 from storage.buckets
    where id='staff-leave-private'
      and (public is distinct from false
        or file_size_limit is distinct from 20971520
        or allowed_mime_types is distinct from array[
          'application/pdf','image/jpeg','image/png'
        ]::text[])
  ) then
    raise exception 'staff_leave_private_bucket_exists_with_unexpected_settings';
  end if;
end;
$preflight$;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values(
  'staff-leave-private',
  'staff-leave-private',
  false,
  20971520,
  array['application/pdf','image/jpeg','image/png']::text[]
)
on conflict(id) do nothing;

-- The first path segment is the request UUID; the second is a generated
-- attachment UUID. No user-controlled filename is used as an object key.
drop policy if exists staff_leave_private_objects_insert_owner
  on storage.objects;
create policy staff_leave_private_objects_insert_owner
on storage.objects for insert to authenticated
with check (
  bucket_id='staff-leave-private'
  and name ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  and exists (
    select 1
    from public.staff_leave_requests r
    join public.profiles p on p.id=r.applicant_id
    where r.id::text=split_part(storage.objects.name,'/',1)
      and r.applicant_id=(select auth.uid())
      and r.status='draft'
      and p.is_active=true
  )
);

drop policy if exists staff_leave_private_objects_select_parties
  on storage.objects;
create policy staff_leave_private_objects_select_parties
on storage.objects for select to authenticated
using (
  bucket_id='staff-leave-private'
  and name ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  and exists (
    select 1
    from public.staff_leave_attachments a
    join public.staff_leave_requests r on r.id=a.request_id
    join public.profiles p on p.id=(select auth.uid()) and p.is_active=true
    where a.storage_bucket_id='staff-leave-private'
      and a.storage_object_key=storage.objects.name
      and r.id=split_part(storage.objects.name,'/',1)::uuid
      and (
        r.applicant_id=(select auth.uid())
        or r.current_approver_user_id=(select auth.uid())
      )
  )
);

create or replace function public.staff_leave_register_private_attachment(
  p_request_id uuid,
  p_object_key text,
  p_original_filename text,
  p_mime_type text,
  p_size_bytes bigint,
  p_attachment_kind text default 'supporting_document'
)
returns uuid
language plpgsql
security definer
set search_path=pg_catalog,public,storage
as $$
declare
  v_actor uuid;
  v_request public.staff_leave_requests%rowtype;
  v_object storage.objects%rowtype;
  v_attachment_id uuid;
begin
  v_actor:=auth.uid();
  if v_actor is null then
    raise exception 'authentication_required' using errcode='28000';
  end if;
  if not exists(select 1 from public.profiles p where p.id=v_actor and p.is_active=true) then
    raise exception 'active_profile_required' using errcode='42501';
  end if;
  if p_request_id is null
     or p_object_key is null
     or p_object_key !~* ('^'||p_request_id::text||'/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') then
    raise exception 'invalid_staff_leave_object_key' using errcode='22023';
  end if;
  if p_original_filename is null or length(btrim(p_original_filename))=0
     or length(p_original_filename)>255 or p_original_filename ~ '[[:cntrl:]/\\]' then
    raise exception 'invalid_staff_leave_filename' using errcode='22023';
  end if;
  if p_mime_type not in ('application/pdf','image/jpeg','image/png')
     or p_size_bytes is null or p_size_bytes<1 or p_size_bytes>20971520 then
    raise exception 'invalid_staff_leave_file_type_or_size' using errcode='22023';
  end if;
  if p_attachment_kind not in ('supporting_document','medical_certificate','childbirth_evidence') then
    raise exception 'invalid_staff_leave_attachment_kind' using errcode='22023';
  end if;

  select * into v_request
  from public.staff_leave_requests r
  where r.id=p_request_id and r.applicant_id=v_actor
  for update;
  if not found then
    raise exception 'leave_request_not_found_or_not_owner' using errcode='42501';
  end if;
  if v_request.status<>'draft' then
    raise exception 'attachments_may_only_be_added_to_draft_requests' using errcode='55000';
  end if;

  select * into v_object
  from storage.objects o
  where o.bucket_id='staff-leave-private' and o.name=p_object_key;
  if not found
     or coalesce(v_object.metadata->>'mimetype','')<>p_mime_type
     or coalesce(v_object.metadata->>'size','') !~ '^[0-9]+$'
     or (v_object.metadata->>'size')::bigint<>p_size_bytes then
    raise exception 'private_storage_object_not_found_or_metadata_mismatch' using errcode='23514';
  end if;

  insert into public.staff_leave_attachments(
    request_id,uploaded_by,storage_object_key,original_filename,
    mime_type,size_bytes,attachment_kind,storage_bucket_id,storage_verified_at
  ) values (
    p_request_id,v_actor,p_object_key,btrim(p_original_filename),
    p_mime_type,p_size_bytes,p_attachment_kind,'staff-leave-private',statement_timestamp()
  ) returning id into v_attachment_id;

  return v_attachment_id;
end;
$$;

revoke all on function public.staff_leave_register_private_attachment(
  uuid,text,text,text,bigint,text
) from public,anon;
grant execute on function public.staff_leave_register_private_attachment(
  uuid,text,text,text,bigint,text
) to authenticated;

comment on table public.staff_leave_attachments is
  'Private staff-leave attachment metadata. Objects are stored only in the non-public staff-leave-private bucket; storage_verified_at is set by the registration RPC after checking the uploaded object metadata.';
comment on function public.staff_leave_register_private_attachment(
  uuid,text,text,text,bigint,text
) is
  'Registers an already-uploaded private Storage object for the authenticated applicant; validates request ownership, draft state, key, MIME type, byte size, and actual Storage object metadata.';

commit;
