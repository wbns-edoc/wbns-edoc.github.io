revoke all on function public.admin_remove_user_role(uuid,uuid) from anon;
revoke all on function public.admin_set_user_role(uuid,uuid) from anon;
revoke all on function public.attach_document_file_version(uuid,uuid,text) from anon;
revoke all on function public.get_my_permissions() from anon;
revoke all on function public.assign_document(uuid,uuid,text,timestamptz) from anon;
revoke all on function public.set_document_deadline(uuid,uuid,timestamptz,timestamptz) from anon;
revoke all on function public.update_document_status(uuid,public.document_status,text) from anon;