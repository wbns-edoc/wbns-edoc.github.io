-- Private Storage/RLS/metadata-registration regression tests.
-- Run only on a disposable Supabase/PostgreSQL fixture with Storage compatibility tables.
\set ON_ERROR_STOP on
begin;

insert into public.profiles(id,full_name,is_active) values
 ('81000000-0000-0000-0000-000000000001','Leave Storage Applicant',true),
 ('81000000-0000-0000-0000-000000000002','Leave Storage Approver',true),
 ('81000000-0000-0000-0000-000000000003','Unrelated Storage User',true);

insert into public.staff_leave_types(id,code,name,is_active) values
 ('82000000-0000-0000-0000-000000000001','storage_test','Storage test',true);

insert into public.staff_leave_requests(
 id,applicant_id,leave_type_id,starts_on,ends_on,reason,status,current_approver_user_id
) values
 ('83000000-0000-0000-0000-000000000001',
  '81000000-0000-0000-0000-000000000001',
  '82000000-0000-0000-0000-000000000001',
  date '2026-11-03',date '2026-11-03','synthetic storage test','draft',
  '81000000-0000-0000-0000-000000000002'),
 ('83000000-0000-0000-0000-000000000002',
  '81000000-0000-0000-0000-000000000002',
  '82000000-0000-0000-0000-000000000001',
  date '2026-11-04',date '2026-11-04','second user request','draft',
  '81000000-0000-0000-0000-000000000001');

do $bucket_assert$
begin
 if not exists(
  select 1 from storage.buckets
  where id='staff-leave-private' and public=false
    and file_size_limit=20971520
    and allowed_mime_types=array['application/pdf','image/jpeg','image/png']::text[]
 ) then
  raise exception 'private leave bucket configuration is incorrect';
 end if;
end
$bucket_assert$;

grant usage on schema storage to authenticated;
grant select,insert on storage.objects to authenticated;

set role authenticated;
select set_config('request.jwt.claim.sub','81000000-0000-0000-0000-000000000001',false);
insert into storage.objects(id,bucket_id,name,metadata) values (
 '84000000-0000-0000-0000-000000000001',
 'staff-leave-private',
 '83000000-0000-0000-0000-000000000001/84000000-0000-0000-0000-000000000002',
 '{"mimetype":"application/pdf","size":"1234"}'::jsonb
);

select public.staff_leave_register_private_attachment(
 '83000000-0000-0000-0000-000000000001',
 '83000000-0000-0000-0000-000000000001/84000000-0000-0000-0000-000000000002',
 'medical-note.pdf','application/pdf',1234,'medical_certificate'
);

do $owner_assert$
declare n integer;
begin
 select count(*) into n from storage.objects where bucket_id='staff-leave-private';
 if n<>1 then raise exception 'applicant must see own private object, got %',n; end if;
 select count(*) into n from public.staff_leave_attachments
 where storage_verified_at is not null and storage_bucket_id='staff-leave-private';
 if n<>1 then raise exception 'registered attachment must be verified, got %',n; end if;
end
$owner_assert$;

-- Applicant cannot register another applicant's request or an absent object.
do $owner_denial$
begin
 begin
  perform public.staff_leave_register_private_attachment(
   '83000000-0000-0000-0000-000000000002',
   '83000000-0000-0000-0000-000000000002/84000000-0000-0000-0000-000000000099',
   'other.pdf','application/pdf',1234,'supporting_document'
  );
  raise exception 'cross-request registration unexpectedly succeeded';
 exception when insufficient_privilege then null;
 end;
 begin
  perform public.staff_leave_register_private_attachment(
   '83000000-0000-0000-0000-000000000001',
   '83000000-0000-0000-0000-000000000001/84000000-0000-0000-0000-000000000099',
   'missing.pdf','application/pdf',1234,'supporting_document'
  );
  raise exception 'missing object registration unexpectedly succeeded';
 exception when check_violation then null;
 end;
 begin
  perform public.staff_leave_register_private_attachment(
   '83000000-0000-0000-0000-000000000001',
   '83000000-0000-0000-0000-000000000001/84000000-0000-0000-0000-000000000002',
   'medical-note.exe','application/x-msdownload',1234,'medical_certificate'
  );
  raise exception 'unsupported MIME registration unexpectedly succeeded';
 exception when invalid_parameter_value then null;
 end;
 begin
  perform public.staff_leave_register_private_attachment(
   '83000000-0000-0000-0000-000000000001',
   '83000000-0000-0000-0000-000000000001/84000000-0000-0000-0000-000000000002',
   'oversized.pdf','application/pdf',20971521,'supporting_document'
  );
  raise exception 'oversized attachment registration unexpectedly succeeded';
 exception when invalid_parameter_value then null;
 end;
 begin
  insert into storage.objects(id,bucket_id,name,metadata) values (
   '84000000-0000-0000-0000-000000000009',
   'staff-leave-private',
   '83000000-0000-0000-0000-000000000002/84000000-0000-0000-0000-000000000009',
   '{"mimetype":"application/pdf","size":"100"}'::jsonb
  );
  raise exception 'cross-request object upload unexpectedly succeeded';
 exception when insufficient_privilege then null;
 end;
end
$owner_denial$;

select set_config('request.jwt.claim.sub','81000000-0000-0000-0000-000000000002',false);
do $approver_assert$
declare n integer;
begin
 select count(*) into n from storage.objects where bucket_id='staff-leave-private';
 if n<>1 then raise exception 'assigned approver must see request evidence, got %',n; end if;
end
$approver_assert$;

select set_config('request.jwt.claim.sub','81000000-0000-0000-0000-000000000003',false);
do $outsider_assert$
declare n integer;
begin
 select count(*) into n from storage.objects where bucket_id='staff-leave-private';
 if n<>0 then raise exception 'unrelated user must not see private leave objects, got %',n; end if;
 select count(*) into n from public.staff_leave_attachments;
 if n<>0 then raise exception 'unrelated user must not see attachment metadata, got %',n; end if;
end
$outsider_assert$;

reset role;
select 'staff leave private Storage authorization tests passed' as result;
rollback;
