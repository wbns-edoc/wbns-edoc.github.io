-- RECOVERED SOURCE ARCHIVE — NOT A NEW MIGRATION
-- Read-only extraction from Production supabase_migrations.schema_migrations.statements
-- Production project: iigzzwyfxxtqbgjawyom
-- Applied version: 20261007140759
-- Ledger name: reporting_views_v1
-- DO NOT place in supabase/migrations or replay against Production.

create or replace view public.document_report_summary as
select d.document_type,d.status,d.urgency,count(*)::bigint as total_documents,
count(*) filter (where d.created_at >= date_trunc('month',now()))::bigint as current_month
from public.documents d group by d.document_type,d.status,d.urgency;

create or replace view public.document_monthly_summary as
select date_trunc('month',d.created_at)::date as month,d.document_type,count(*)::bigint as total_documents,
count(*) filter (where d.status='completed')::bigint as completed_documents,
count(*) filter (where d.urgency in ('urgent','very_urgent','critical'))::bigint as urgent_documents
from public.documents d group by 1,2 order by 1 desc;
