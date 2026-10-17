# Schema Recovery Inventory — 2026-10-17

สถานะ: **สำรวจจาก catalog แล้วบางส่วน; ยังไม่ใช่ migration baseline ที่รับรองให้ติดตั้งได้**

เอกสารนี้บันทึกผลการสำรวจแบบอ่านอย่างเดียวจาก Supabase SQL Editor และข้อมูลที่ผู้ดูแลส่งมา เพื่อวางแผนทำ template สำหรับโรงเรียนอื่น ห้ามใช้เอกสารนี้แทน SQL backup หรือใช้สร้าง DDL โดยการเดา

## ขอบเขตความปลอดภัย

- การสำรวจในรอบนี้เป็นการอ่าน metadata เท่านั้น ไม่มีการ reset password, reset database, migration, deploy หรือเปลี่ยนแปลง Production
- ห้ามใช้ project ref, user data, document data, Drive identifiers หรือ secrets ของโรงเรียนต้นแบบใน template ใหม่
- Snapshot ที่ export จาก live catalog ไม่ได้พิสูจน์ว่าการสร้างฐานข้อมูลใหม่จากศูนย์ทำซ้ำได้
- ต้องเก็บไฟล์ export ที่มีนิยามฟังก์ชันและนโยบายไว้ในที่ส่วนตัว ไม่ commit รายละเอียดภายในหรือข้อมูลลับโดยไม่ผ่านการตรวจความเหมาะสม

## สิ่งที่มีหลักฐานแล้ว

| รายการ | ผลสำรวจ | ข้อจำกัด |
|---|---:|---|
| Public base tables | 27 | ต้องยืนยัน column/type/default/FK ครบกับ catalog export |
| Public views | 2 | มีนิยาม view ที่ export แล้ว |
| Functions/procedures ใน public และ private | 61 | มี export definitions; ยังต้อง review dependencies, grants, search_path และ authorization |
| User-defined triggers | 14 | export รายการ definitions และสถานะ; ยังต้องทดสอบ behavior ใน disposable DB |
| RLS policies ใน public | 50 | export policy metadata/expressions; ยังต้องทดสอบ effective access และ grants |
| Public indexes | 86 | รายการ index definitions ถูกส่งมาเป็นข้อความครบตาม count ที่ตรวจไว้ |
| Public constraints | 98 | 10 CHECK, 50 FOREIGN KEY, 27 PRIMARY KEY, 11 UNIQUE |
| Columns export | 212 data rows หลังเอา repeated header rows ออก | export เดิมมี 2 header rows ปะปน ต้องยืนยัน object/type coverage ก่อนใช้เป็น authoritative snapshot |

## ตารางที่สำรวจพบ

ตาราง public 27 รายการ:
- approvals
- audit_logs
- comments
- deadlines
- department_role_permissions
- departments
- document_assignment_reports
- document_assignments
- document_files
- document_registers
- document_status_history
- documents
- google_drive_files
- incoming_document_details
- notifications
- number_sequences
- outgoing_document_details
- permissions
- profiles
- push_subscriptions
- role_permissions
- roles
- senders
- system_settings
- user_department_roles
- user_departments
- user_roles

Views ที่พบ:
- document_monthly_summary
- document_report_summary

## Known blockers before a distributable installer

1. **Authoritative baseline missing:** repository migration `20261007200000_foundation_schema_rbac_rls.sql` was previously inspected as a placeholder. Do not reconstruct it by copying guessed DDL from partial exports.
2. **Migration reconciliation incomplete:** Production migration history and checked-in migrations have not been proven semantically equivalent. Need an exact mapping, source provenance, and hash/diff evidence.
3. **Catalog export is not a full backup:** table/column, views, functions, triggers, policies, indexes, and constraints are separate exports. Still verify enum/domain types, extensions, sequences, grants/default privileges, ownership, storage policies/buckets, Auth/Edge Function dependencies, and all object dependencies.
4. **RLS authorization must be tested:** some tables have RLS enabled but no direct policies; verify intended access through approved RPCs and ensure grants do not expose data.
5. **School-specific config must be removed from template:** `supabase/config.toml` previously contained the WBNS project ref. New-school configuration must use placeholders/new project refs.
6. **Seed data must be synthetic:** no actual school users, documents, logs, attachments, Drive IDs, or secrets may be included.
7. **Repeatable install and restore not yet proven:** a disposable local database must replay all migrations from zero, pass security/workflow tests, and complete backup/restore before any second-school pilot.

## Next safe sequence

1. Preserve source exports privately and record export date, SQL used, row counts, and SHA-256 hashes locally.
2. Export remaining catalog items in separate queries to avoid row multiplication and 100-row truncation.
3. Inspect repository migration history and map each production migration entry to an exact source file; do not assume matching version names means equivalent SQL.
4. Build a disposable local Supabase/PostgreSQL test database using only authoritative, reviewed source migrations.
5. Run migration replay, schema comparison, RLS/GRANT tests, workflow tests, Edge Function contract tests, and backup/restore.
6. Prepare a separate-school template only after the above gates pass. Keep the installer PR as Draft until then.

## Acceptance gate

Do not describe the system as ready to distribute or production-install until:
- fresh install from an empty disposable database succeeds;
- all required objects and extensions are present;
- all authorization positive and negative tests pass;
- no project-specific identifiers or secrets remain;
- backup/restore is tested;
- an independent pilot installer completes the guide;
- school owner approves operational, privacy, retention, and cost constraints.

