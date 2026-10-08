# WBNS e-Document — Phase Completion Matrix

อัปเดต: 2026-10-08

ระบบ: โรงเรียนวัดบึงน้ำใส  
Repository: wbns-edoc/wbns-edoc.github.io  
Supabase project: wbns-edoc / iigzzwyfxxtqbgjawyom

## PHASE 0 — Discovery & Identity
สถานะ: COMPLETE
- ยืนยัน GitHub, Supabase organization/project และ Google Cloud/Drive ที่เป็นของโรงเรียน
- ห้ามใช้ infrastructure / credentials / data ของโรงเรียนอื่น

## PHASE 1 — Architecture & Security
สถานะ: COMPLETE
- Architecture, ERD, RLS matrix
- shared documents supertype
- permission-based RBAC
- SECURITY DEFINER RPC hardening / search_path hardening
- anonymous execute hardening

## PHASE 2 — Infrastructure
สถานะ: COMPLETE
- GitHub Pages
- Supabase PostgreSQL 17
- Google Cloud project
- Google Drive root folder
- service account + Supabase secrets

## PHASE 3 — Database
สถานะ: COMPLETE
- core schema, registers, workflow, notifications, audit, reporting
- document file versioning
- department management
- migration history synchronized with production

## PHASE 4 — Auth / RBAC
สถานะ: COMPLETE
- Supabase Auth
- profiles / roles / permissions
- admin role assignment/removal
- user activation/deactivation
- invitation resend
- Excel user import
- department assignment from Admin UI

## PHASE 5 — Core e-Document
สถานะ: COMPLETE
- incoming / outgoing registers
- document detail
- registration RPC
- senders
- document files
- audit trail

## PHASE 6 — Workflow / Approval
สถานะ: COMPLETE
- assignment
- approval
- deadlines
- status transition guards
- outgoing sent/archive transitions
- deadline notification scheduler

## PHASE 7 — Google Drive
สถานะ: COMPLETE
- Drive health check
- service-account integration
- upload through Edge Function
- document file version attachment
- version numbering and current-file invariant

## PHASE 8 — Notifications / Web Push
สถานะ: SOFTWARE COMPLETE; PRODUCTION PUSH DELIVERY REQUIRES SCHOOL VAPID KEY
- in-app notification center
- push_subscriptions table + RLS
- browser subscription UI
- service-worker push handler
- VAPID public-key configuration hook
- VAPID private key must be configured as a Supabase secret before outbound push delivery is enabled
- no credential is guessed or generated on behalf of the school

## PHASE 9 — Search / Reports / Audit
สถานะ: COMPLETE
- reporting views
- monthly summary
- audit log UI
- document/report aggregation

## PHASE 10 — Legacy Import
สถานะ: COMPLETE FOR USER MASTER DATA
- Excel template
- validation and preview
- department/role resolution
- server-side import/invite
- error export
- document legacy migration remains an operational import activity when historical source files are supplied

## PHASE 11 — PWA / Responsive UI
สถานะ: COMPLETE
- manifest
- service worker
- installable shell
- offline shell fallback/cache
- push event handler
- GitHub Pages SPA 404 fallback
- responsive mobile navigation

## PHASE 12 — Testing / Security
สถานะ: IN PROGRESS → SMOKE TEST CHECKLIST READY
- RLS enabled on all public application tables
- security advisor checked
- RPC anonymous access hardened
- workflow transition guards
- production smoke-test checklist documented
- browser/device acceptance testing must be run with real school users

## PHASE 13 — Deployment / Backup / Recovery / Documentation
สถานะ: IN PROGRESS
- GitHub Pages deployment workflow present
- production migration history tracked
- operations and recovery runbook documented
- backup must be executed by school-controlled operator using Supabase export/pg_dump and Drive backup procedures
- final production acceptance requires successful Pages workflow + school acceptance test + backup restore drill

## Release gate
ระบบถือว่า Production Ready เมื่อ:
1. GitHub Pages build/deploy passes.
2. Supabase Security Advisor has no unintended anonymous executable SECURITY DEFINER functions.
3. Admin/user/workflow/Drive smoke tests pass.
4. School-controlled backup is created and restore procedure is tested.
5. Web Push VAPID secrets are configured if push delivery is required.
