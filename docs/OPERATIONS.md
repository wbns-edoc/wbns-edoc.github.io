# WBNS e-Document — Operations & Recovery Runbook

## Daily
- Check Supabase project health.
- Check Google Drive health from Admin → Audit/Health Check.
- Review unread notifications and overdue deadlines.
- Review audit log for unexpected admin changes.

## Before schema changes
1. Confirm the change belongs to WBNS infrastructure.
2. Create/verify a database backup.
3. Add a timestamped migration under `supabase/migrations/`.
4. Apply to Production only after the migration is reviewed.
5. Verify migration history.
6. Run smoke tests.

## Database backup
Use a school-controlled operator account and the official Supabase/PostgreSQL connection details. Example:

```bash
pg_dump --format=custom --file=wbns-edoc-YYYYMMDD.dump "$DATABASE_URL"
```

Never commit database dumps, service-account JSON, VAPID private keys, Supabase secret keys, or user passwords to GitHub.

## Google Drive backup
- The school owns the root Drive folder.
- Keep the service account key only in Supabase Secrets / secure school password management.
- Periodically export critical document folders according to the school's retention policy.
- Do not copy school documents into another school's infrastructure.

## Recovery
1. Stop application writes if required.
2. Restore PostgreSQL backup into a controlled recovery target.
3. Apply migrations only up to the verified target version.
4. Verify RLS, roles, permissions and workflow RPCs.
5. Verify Google Drive references.
6. Re-run smoke tests.
7. Switch production only after acceptance.

## Web Push
Required Supabase secrets/configuration:
- VAPID public key → frontend build variable `VITE_VAPID_PUBLIC_KEY`
- VAPID private key → Supabase Secret (server-side only)
- Do not expose the private key to the browser.

## Incident rule
Do not guess credentials or repair another school's resources. Escalate to the school's infrastructure owner when an account, secret, Drive permission, or production setting is missing.
