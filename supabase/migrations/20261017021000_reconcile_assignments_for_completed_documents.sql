-- Keep assignment status consistent with already-completed documents.
UPDATE public.document_assignments da
SET assignment_status = 'completed',
    completed_at = coalesce(da.completed_at, now())
FROM public.documents d
WHERE d.id = da.document_id
  AND d.status = 'completed'
  AND da.assignment_status IN ('assigned', 'accepted', 'in_progress');
