# WBNS e-Document

ระบบสารบรรณอิเล็กทรอนิกส์ โรงเรียนวัดบึงน้ำใส

## Stack
- React + Vite + TypeScript
- Supabase Auth + PostgreSQL + Edge Functions
- Google Drive for document files
- PWA + Web Push

## Development
1. Copy `.env.example` to `.env.local`.
2. Set `VITE_SUPABASE_URL` and `VITE_SUPABASE_PUBLISHABLE_KEY`.
3. Run `npm install`.
4. Run `npm run dev`.

Never commit service-role keys, OAuth secrets, Google credentials, or VAPID private keys.

## Deployment
GitHub Actions builds and deploys the PWA to GitHub Pages. Repository Actions variables should contain only the Supabase project URL and publishable key.

## Documents
- `docs/ARCHITECTURE.md`
- `docs/ERD.md`
- `docs/RLS-MATRIX.md`
