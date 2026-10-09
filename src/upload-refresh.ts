export function getUploadRefreshMessage(refreshSucceeded: boolean): string | null {
  return refreshSucceeded
    ? null
    : "อัปโหลดไฟล์สำเร็จแล้ว แต่รีเฟรชข้อมูลเอกสารไม่สำเร็จ กรุณาโหลดหน้าใหม่เพื่อตรวจสอบสถานะ";
}
