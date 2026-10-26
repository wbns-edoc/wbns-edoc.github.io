# คู่มือติดตั้ง SchooLnSn01 e-Document สำหรับโรงเรียนใหม่

> สถานะ: ยังไม่พร้อมใช้ติดตั้ง Production เนื่องจาก migration foundation ใน repository ปัจจุบันเป็น placeholder และยังไม่มีชุด migration ที่พิสูจน์แล้วว่าสร้างฐานข้อมูลจากศูนย์ได้ครบ ห้ามใช้กับ Production หรือโรงเรียนจริงจนกว่า blocker จะถูกแก้และทดสอบครบ

## เป้าหมาย
- แต่ละโรงเรียนมี GitHub repository, Supabase project/database/Auth และการจัดเก็บไฟล์ของตนเอง
- ไม่มีการใช้บัญชีผู้ใช้ เอกสาร secrets หรือ Drive folder ร่วมกับโรงเรียนต้นแบบ
- ใช้ข้อมูลจำลองในการทดสอบ
- ติดตั้งซ้ำได้จาก source control และมีหลักฐานทดสอบ restore

## Gate 1 — กู้คืนแหล่งฐานข้อมูล (BLOCKER)
- [ ] หา SQL ต้นฉบับที่เชื่อถือได้สำหรับ foundation schema และ migration ที่ขาด
- [ ] เทียบ migration history ที่เคยใช้จริงกับไฟล์ใน repository พร้อมบันทึกที่มาและความแตกต่าง
- [ ] สร้างฐานข้อมูล disposable local ใหม่จากศูนย์โดยไม่เชื่อม Production
- [ ] ทดสอบ migration replay ทุกไฟล์ตามลำดับ
- [ ] ทดสอบ RLS, grants, enum, indexes, triggers, RPC, views และ Edge Function contracts
- [ ] ทดสอบ negative authorization cases และการแยกข้อมูลระหว่างแผนก
- [ ] ให้ผู้ตรวจทานอิสระอนุมัติ baseline
- [ ] ห้ามสร้าง DDL จากการคาดเดา live catalog เพียงอย่างเดียว

## Gate 2 — ทำ template ให้ปลอดข้อมูลและ credentials
- [ ] แยก project-specific config ออกจาก source; ห้าม hard-code project ref
- [ ] มี .env.example ที่มีแต่ placeholder
- [ ] ตรวจ history/ไฟล์/CI logs ว่าไม่มี service-role keys, passwords, OAuth secrets, private keys, tokens หรือ production data
- [ ] แยก seed data สำหรับ roles/permissions/reference values ออกจาก user data
- [ ] ห้ามนำ Auth users, profiles, documents, attachments, audit logs หรือ Drive IDs ของโรงเรียนต้นแบบไปด้วย
- [ ] กำหนด dependencies และ lockfile ที่ทำซ้ำได้
- [ ] ตรวจ workflow permissions และ secrets scoping

## Gate 3 — ตั้งค่าโรงเรียนใหม่ใน Sandbox
1. เจ้าของโรงเรียนสร้าง repository ของตนเองจาก template ที่ได้รับอนุมัติ
2. เจ้าของโรงเรียนสร้าง Supabase project ใหม่และเก็บข้อมูลการเข้าถึงเป็นความลับ
3. ตั้งค่า local environment ด้วย CLI และ migrations ที่ผ่าน Gate 1 แล้ว
4. deploy Edge Functions เฉพาะที่ต้องใช้
5. ตั้งค่า secrets ผ่าน dashboard/secret manager ของผู้ให้บริการ ไม่ใส่ secrets ใน Git หรือแชต
6. ตั้งค่า Auth redirect URLs และ CORS ให้จำกัดเท่าที่จำเป็น
7. เลือก hosting หลังตรวจเงื่อนไขการใช้งานของ provider; ห้ามถือว่า GitHub Pages เหมาะสำหรับ SaaS หรือข้อมูลอ่อนไหวโดยอัตโนมัติ
8. จดบันทึกค่าใช้จ่ายที่อาจเกิดขึ้น ข้อจำกัดโควตา และนโยบายพัก/ลบ project

## Gate 4 — Security & acceptance test
- [ ] unauthenticated user อ่านข้อมูลธุรกิจไม่ได้
- [ ] ผู้ใช้แต่ละแผนกไม่สามารถอ่านข้อมูลของแผนกอื่นโดยไม่ได้รับอนุญาต
- [ ] System Admin และผู้อำนวยการมีสิทธิ์ตามนโยบายที่อนุมัติไว้
- [ ] ตรวจสิทธิ์ฝั่งฐานข้อมูล ไม่พึ่งการซ่อนปุ่มใน UI
- [ ] ทดสอบ import ผู้ใช้ด้วยข้อมูลจำลองและตรวจ multi-department assignments
- [ ] ทดสอบ upload, download, duplicate handling และ permanent deletion ใน Drive test folder
- [ ] ทดสอบ audit trail และ failure paths
- [ ] ทดสอบ backup และ restore โดยบันทึกผล
- [ ] ทดสอบ build และ automated tests ใน CI
- [ ] ทดสอบ desktop และ mobile

## Gate 5 — Pilot และเปิดใช้งาน
- [ ] ให้โรงเรียนที่สองทดลองติดตั้งโดยผู้ใช้ที่ไม่ใช่ผู้พัฒนาหลัก
- [ ] เก็บขั้นตอนที่ติดขัดและปรับปรุงคู่มือ
- [ ] ให้เจ้าของโรงเรียนอนุมัติ roles, retention, backup, hosting และผู้รับผิดชอบข้อมูล
- [ ] ยืนยันว่าระบบและไฟล์อยู่ในบัญชีที่โรงเรียนควบคุม
- [ ] บันทึกวันเปิดใช้และช่องทางกู้คืน
- [ ] ห้ามประกาศว่า production-ready จนกว่า checklist ที่จำเป็นทั้งหมดจะผ่าน

## หลักการค่าใช้จ่าย
ตั้งเป้าใช้ free tiers และ open-source tools เท่าที่ผู้ให้บริการอนุญาต แต่ไม่รับประกันค่าใช้จ่ายเป็นศูนย์ตลอดอายุการใช้งาน ต้องตรวจ quota, inactivity pause, storage/egress limits, backup options, provider terms และเงื่อนไข hosting ก่อนเริ่มทุกโรงเรียน

## หลักการปกป้องโรงเรียนวัดบึงน้ำใส
- ไม่แก้ Production ของโรงเรียนวัดบึงน้ำใสในกระบวนการสร้าง template
- ไม่ใช้ Supabase project ref เดิมในคำสั่งติดตั้งของโรงเรียนใหม่
- ไม่ใช้ข้อมูลจริงหรือ credentials จากต้นแบบ
- ทดลองบน branch และ disposable local database เท่านั้น
- การ merge เข้า main, deploy หรือเปลี่ยน Production ต้องมีการอนุมัติแยกต่างหาก