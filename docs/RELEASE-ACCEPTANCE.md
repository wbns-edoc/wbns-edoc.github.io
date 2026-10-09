# WBNS e-Document — Production Release Acceptance

อัปเดต: 2026-10-08

เอกสารนี้ใช้เป็น gate ก่อนเปิดใช้งานจริง โดยไม่สร้างข้อมูลบุคลากรหรือเอกสารปลอมใน Production

## A. Automated / platform verification

- [x] GitHub Pages workflow build/deploy ผ่าน
- [x] Supabase project อยู่ในสถานะ healthy
- [x] Public application tables เปิด RLS
- [x] ไม่มี anonymous executable SECURITY DEFINER RPC ที่ไม่ได้ตั้งใจ
- [x] Google Drive Edge Functions active และตั้ง `verify_jwt=true`
- [ ] ตรวจสอบว่า migration ที่ apply ทั้งหมดมีไฟล์ใน repository และลำดับตรงกับฐานข้อมูล Production

## B. School acceptance test

ต้องดำเนินการด้วยบัญชีบุคลากรจริงของโรงเรียน

- [ ] Admin login
- [ ] Staff login
- [ ] Create/edit department
- [ ] Assign department and role
- [ ] User activation/deactivation
- [ ] Excel user import with a real approved roster
- [ ] Register one incoming document
- [ ] Upload one real test document to school Drive
- [ ] Verify file version v1 → v2
- [ ] Assign → in_progress → completed → archived
- [ ] Register one outgoing document
- [ ] Approval → sent → archived
- [ ] Verify notification center
- [ ] Verify audit trail

## C. Backup / recovery gate

ต้องทำโดย school-controlled operator

- [ ] Create PostgreSQL backup/export
- [ ] Verify backup can be read
- [ ] Restore into a non-production controlled target
- [ ] Verify schema, RLS, roles, permissions and workflow RPCs
- [ ] Verify Google Drive references
- [ ] Record recovery owner and secure recovery credentials

ห้ามนำ production backup ไป commit ใน GitHub

## D. Web Push gate

ถ้าต้องการ Push จริง:

- [ ] School creates/owns VAPID key pair
- [ ] Public key is supplied as `VITE_VAPID_PUBLIC_KEY`
- [ ] Private key is stored only in Supabase Secrets
- [ ] Browser subscription succeeds
- [ ] End-to-end push delivery is tested

ถ้ายังไม่ต้องการ Push จริง สามารถเปิดใช้งานระบบโดยใช้ In-app notifications ได้ โดยไม่ต้องสร้างหรือเดา credential ใด ๆ

## Release decision

Production Ready เมื่อ A ผ่านทั้งหมด และ B/C ผ่านทั้งหมด

Web Push เป็นเงื่อนไขเพิ่มเติมเฉพาะเมื่อโรงเรียนต้องการใช้งาน Push delivery

## Security rule

ห้ามใช้ infrastructure, credentials หรือข้อมูลของโรงเรียนอื่น และห้ามสร้างข้อมูลบุคลากร/เอกสารปลอมใน Production เพื่อหลอกให้ smoke test ผ่าน
