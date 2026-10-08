create or replace function public.attach_document_file_version(
  p_document_id uuid,
  p_google_drive_file_id uuid,
  p_file_role text default 'main'
)
returns table(
  id uuid,
  document_id uuid,
  google_drive_file_id uuid,
  file_role text,
  version_no integer,
  is_current boolean,
  uploaded_by uuid,
  uploaded_at timestamptz
)
language plpgsql
security definer
set search_path=pg_catalog,public,private
as $$
declare
  v_id uuid;
  v_version integer;
begin
  if auth.uid() is null then
    raise exception using errcode='42501',message='authentication_required';
  end if;
  if not private.has_permission('document.update') then
    raise exception using errcode='42501',message='insufficient_privilege';
  end if;
  if p_file_role is null or btrim(p_file_role)='' then
    raise exception using errcode='22023',message='file_role_required';
  end if;
  if not exists(select 1 from public.documents where id=p_document_id) then
    raise exception using errcode='22023',message='document_not_found';
  end if;
  if not exists(select 1 from public.google_drive_files where id=p_google_drive_file_id) then
    raise exception using errcode='22023',message='google_drive_file_not_found';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(p_document_id::text || ':' || p_file_role, 0)
  );

  select coalesce(max(df.version_no),0)+1
    into v_version
  from public.document_files df
  where df.document_id=p_document_id
    and df.file_role=p_file_role;

  update public.document_files
     set is_current=false
   where document_id=p_document_id
     and file_role=p_file_role
     and is_current=true;

  update public.google_drive_files
     set created_by=coalesce(created_by,auth.uid())
   where id=p_google_drive_file_id;

  insert into public.document_files(
    document_id,google_drive_file_id,file_role,version_no,is_current,uploaded_by
  )
  values(
    p_document_id,p_google_drive_file_id,p_file_role,v_version,true,auth.uid()
  )
  returning document_files.id into v_id;

  return query
  select df.id,df.document_id,df.google_drive_file_id,df.file_role,
         df.version_no,df.is_current,df.uploaded_by,df.uploaded_at
  from public.document_files df
  where df.id=v_id;
end
$$;

revoke all on function public.attach_document_file_version(uuid,uuid,text) from public;
grant execute on function public.attach_document_file_version(uuid,uuid,text) to authenticated;

create unique index if not exists uq_document_files_current_role
  on public.document_files(document_id,file_role)
  where is_current=true;
