# ขั้นที่ 1 — ตรวจสอบ Repository สำหรับชุดติดตั้งโรงเรียนใหม่

วันที่ตรวจ: 2026-10-17  
ขอบเขต: อ่านไฟล์จาก GitHub branch `main` เท่านั้น ไม่เปลี่ยน Production

## ผลที่ยืนยันจากไฟล์จริง

### 1. Foundation migration ยังไม่ใช่ SQL ที่ติดตั้งซ้ำได้

ไฟล์ `supabase/migrations/20261007200000_foundation_schema_rbac_rls.sql` มีเพียงข้อความอธิบายว่าระบบใช้ SQL ที่ apply อยู่ใน Supabase Production และไม่มี DDL สำหรับสร้าง schema จากศูนย์

ผล: **ห้ามใช้ migration directory ปัจจุบันเป็นหลักฐานว่า fresh install สำเร็จ** และห้ามแก้ placeholder ด้วยการสร้าง DDL จากการคาดเดา

### 2. Supabase project ref ถูกฝังใน config

ไฟล์ `supabase/config.toml` มี `project_id = "iigzzwyfxxtqbgjawyom"` ซึ่งชี้ไปยังโครงการ WBNS เดิม

ผล: config นี้ไม่ควรถูกนำไปใช้ตรง ๆ กับโรงเรียนใหม่ ต้องสร้าง template config ที่ใช้ placeholder/ค่า project ใหม่ และตรวจทุก environment variable ก่อนติดตั้ง

### 3. Migration อื่น ๆ มีอยู่ แต่ยังไม่ได้พิสูจน์ว่าทำงานจากศูนย์ได้

พบ migration ไฟล์จำนวนมากที่เพิ่ม workflow, RLS, assignment, reports และเลขทะเบียนเอกสารภายหลัง foundation migration แต่การมีไฟล์เหล่านี้ไม่ได้แก้ปัญหา foundation ที่หายไป และไม่ได้พิสูจน์ว่าลำดับทั้งหมด replay ได้ในฐานข้อมูลว่าง

### 4. ความปลอดภัยและการใช้งานจริงยังเป็น gate

ก่อนเผยแพร่ installer ต้องตรวจอย่างน้อย:
- extension และ custom enum/type/domain ที่จำเป็น
- ตาราง, sequence, indexes, constraints, views, functions, triggers
- RLS policies, table/function grants, default privileges และ ownership
- Storage buckets/policies และการอ้างอิง Google Drive
- Supabase Auth settings, Edge Function configuration และ secret names (ไม่ใช่ค่า secret)
- seed data ต้องเป็นข้อมูลสังเคราะห์ ไม่มีผู้ใช้/เอกสารจริง
- ติดตั้งและทดสอบบน disposable DB จากศูนย์ รวม backup/restore

## การเปลี่ยนแปลงที่ทำ

เพิ่มเอกสารตรวจสอบนี้ไว้ใน branch `docs/school-installer-blueprint` เพื่อให้เป็น audit trail ของขั้นแรกเท่านั้น ไม่มีการเปลี่ยน `main`, ไม่ merge PR, ไม่ deploy, ไม่เปลี่ยน Supabase Production และไม่เปลี่ยน secrets

## เกณฑ์ผ่านขั้นที่ 1

- [x] ระบุ placeholder foundation migration
- [x] ระบุ project ref เฉพาะโรงเรียนใน config
- [x] บันทึกว่าห้ามนำ migration ปัจจุบันไปอ้างว่าติดตั้งจากศูนย์ได้
- [ ] สร้าง authoritative baseline จากแหล่งที่ตรวจสอบได้
- [ ] ทำ fresh replay บนฐานข้อมูลทดสอบแยก
- [ ] ผ่าน RLS/workflow/backup-restore tests

**สถานะขั้นที่ 1: ตรวจสอบเบื้องต้นเสร็จแล้ว; ยังไม่ผ่านเกณฑ์พร้อมแจกติดตั้ง**
