-- Reporting views must respect the querying user's RLS context.
create or replace view public.document_report_summary with (security_invoker=true) as
select document_type,status,urgency,count(*) as total_documents,count(*) filter (where created_at>=date_trunc('month',now())) as current_month
from public.documents
group by document_type,status,urgency;

create or replace view public.document_monthly_summary with (security_invoker=true) as
select date_trunc('month',created_at)::date as month,document_type,count(*) as total_documents,
count(*) filter (where status='completed'::document_status) as completed_documents,
count(*) filter (where urgency in ('urgent'::urgency_level,'very_urgent'::urgency_level,'critical'::urgency_level)) as urgent_documents
from public.documents
group by date_trunc('month',created_at)::date,document_type
order by date_trunc('month',created_at)::date desc;
