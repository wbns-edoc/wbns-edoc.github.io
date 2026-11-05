# แผนทดสอบความปลอดภัยระบบบริหารการลา (ก่อน Migration)

สถานะ: Test plan / ยังไม่ใช่ผลทดสอบที่รันแล้ว  
สาขา: `feat/staff-leave-management-design`

## ผลตรวจสิทธิ์ฐานข้อมูลที่อ่านได้

พบฟังก์ชันเดิม:
- `private.has_permission(p_permission text)`
- `private.has_department_permission(p_permission text, p_department_id uuid)`
- `private.user_has_department(p_user_id uuid, p_department_id uuid)`
- `private.audit_row_change()`

พบ RLS policy ตัวอย่าง:
- `profiles_select_self_or_admin`: อ่านโปรไฟล์ตนเองหรือผู้มี `user.view`
- `audit_logs_admin_read`: อ่าน audit log ผ่าน `audit.view`
- `departments_select_authenticated`: ผู้ใช้ที่ยืนยันตัวตนอ่านรายชื่อหน่วยงานได้

การอ่าน catalog นี้ไม่ใช่การตรวจสอบ implementation ภายในฟังก์ชันทุกตัว และไม่ได้ยืนยันว่า RLS ของตารางระบบลาใหม่ปลอดภัยแล้ว

## Test matrix ที่ต้องทำใน local/staging

| ID | สถานการณ์ | ผลที่ต้องได้ |
|---|---|---|
| LEAVE-RLS-001 | ผู้ใช้ A อ่านคำขอของ A | อนุญาตเฉพาะข้อมูลที่ตนมีสิทธิ์ |
| LEAVE-RLS-002 | ผู้ใช้ A อ่าน/แก้คำขอของ B โดยตรงผ่าน API | ปฏิเสธหรือไม่คืนข้อมูล |
| LEAVE-RLS-003 | ผู้อนุมัติที่ได้รับมอบหมายอ่านคำขอในขอบเขต | อนุญาตเฉพาะรายการที่ได้รับมอบหมายและข้อมูลจำเป็น |
| LEAVE-RLS-004 | ผู้อนุมัติจากหน่วยงานอื่นพยายามอ่านคำขอ | ปฏิเสธหากไม่มีอำนาจ/การมอบหมาย |
| LEAVE-RLS-005 | ผู้ยื่นพยายามอนุมัติคำขอตนเอง | ปฏิเสธ |
| LEAVE-RLS-006 | ผู้ใช้พยายามเปลี่ยนสถานะเป็น approved ด้วย UPDATE ตรง | ปฏิเสธ; ต้องผ่าน transition RPC/server ที่ตรวจสิทธิ์ |
| LEAVE-RLS-007 | ผู้ใช้ทั่วไปอ่านเหตุผล/ไฟล์แนบของบุคคลอื่น | ปฏิเสธ |
| LEAVE-RLS-008 | ดาวน์โหลดไฟล์ด้วย object key ของผู้อื่น | ปฏิเสธ; bucket ต้องเป็น private |
| LEAVE-RLS-009 | เปลี่ยน personnel category หลังยื่นคำขอ | ไม่เปลี่ยนประเภท/นโยบายย้อนหลังของคำขอเดิมโดยเงียบ ๆ |
| LEAVE-AUDIT-010 | แก้ไข/ลบประวัติการอนุมัติเดิม | ปฏิเสธ; เพิ่ม action ใหม่แทน |
| LEAVE-LEDGER-011 | ประมวลผลอนุมัติคำขอเดิมซ้ำ | ต้องไม่หักยอดซ้ำ |
| LEAVE-WF-012 | ผู้ใช้ส่งคำขอซ้ำ/เปลี่ยนสถานะข้ามขั้น | ปฏิเสธ transition ที่ไม่ถูกต้อง |
| LEAVE-PRIV-013 | System Admin แต่ไม่มีหน้าที่งานบุคคลอ่านเหตุผล/เอกสารสุขภาพ | ปฏิเสธตามหลัก least privilege |
| LEAVE-PRIV-014 | เรียก RPC โดยไม่ authenticated | ปฏิเสธ |

## เงื่อนไขก่อนเริ่มเขียน migration

1. ตรวจโครงสร้าง schema, enum, constraints, triggers และ policies ปัจจุบันครบถ้วน
2. ตรวจ source code ของ helper functions และรูปแบบ migration ใน repository
3. ยืนยันชื่อสิทธิ์เฉพาะระบบลา และผู้รับผิดชอบการกำหนดสิทธิ์
4. สร้าง migration แบบ additive บน feature branch เท่านั้น
5. เพิ่ม tests และรันใน local/staging ที่แยกจาก Production
6. ตรวจ diff และผล CI ก่อนเสนอ PR; ห้าม deploy อัตโนมัติโดยถือว่าเอกสาร test plan คือผลผ่าน

## ขอบเขตที่ยังไม่ผ่านการยืนยัน

- ยังไม่ได้รัน test cases ข้างต้น
- ยังไม่ได้สร้างตารางหรือ migration ระบบลา
- ยังไม่ได้ตรวจนิยาม source code ของทุก helper function และทุก policy ที่เกี่ยวข้อง
- ยังไม่ได้เปิดใช้การคำนวณสิทธิ์/ยอดคงเหลือ
