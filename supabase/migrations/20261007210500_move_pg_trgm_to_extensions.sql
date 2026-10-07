-- Keep pg_trgm outside public schema and preserve search indexes.
drop index if exists public.idx_documents_subject_trgm;
drop index if exists public.idx_senders_org_trgm;
drop extension if exists pg_trgm;
create extension pg_trgm with schema extensions;
create index idx_documents_subject_trgm on public.documents using gin(subject extensions.gin_trgm_ops);
create index idx_senders_org_trgm on public.senders using gin(organization_name extensions.gin_trgm_ops);