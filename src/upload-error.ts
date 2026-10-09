export function getUploadErrorMessage(code: unknown): string {
  switch (code) {
    case "FILE_AND_DOCUMENT_REQUIRED":
      return "กรุณาเลือกไฟล์และตรวจสอบว่าเปิดเอกสารที่ต้องการแนบอยู่";
    case "INVALID_MULTIPART_FORM":
      return "ข้อมูลไฟล์ไม่ถูกต้อง กรุณาเลือกไฟล์แล้วลองใหม่";
    case "INVALID_FILE_NAME":
      return "ชื่อไฟล์ไม่ถูกต้อง กรุณาตรวจสอบชื่อไฟล์และลองใหม่";
    case "FILE_TOO_LARGE":
      return "ไฟล์มีขนาดเกิน 25 MiB";
    case "EMPTY_FILE":
      return "ไฟล์ว่างเปล่า กรุณาเลือกไฟล์ใหม่";
    case "AUTH_REQUIRED":
    case "AUTH_INVALID":
      return "เซสชันหมดอายุ กรุณาเข้าสู่ระบบใหม่";
    case "PERMISSION_CHECK_FAILED":
      return "ตรวจสอบสิทธิ์ไม่สำเร็จ กรุณาลองใหม่หรือติดต่อผู้ดูแลระบบ";
    case "INSUFFICIENT_PERMISSION":
      return "คุณไม่มีสิทธิ์แนบไฟล์กับเอกสารนี้";
    case "DOCUMENT_NOT_FOUND_OR_NOT_ACCESSIBLE":
      return "ไม่พบเอกสารหรือคุณไม่มีสิทธิ์เข้าถึงเอกสารนี้";
    case "GOOGLE_DRIVE_CONFIGURATION_INVALID":
      return "การตั้งค่าบัญชีจัดเก็บไฟล์ไม่ถูกต้อง กรุณาติดต่อผู้ดูแลระบบ";
    case "GOOGLE_DRIVE_CONFIGURATION_MISSING":
    case "SERVER_DATABASE_CONFIGURATION_MISSING":
    case "SUPABASE_CONFIGURATION_MISSING":
      return "ระบบจัดเก็บไฟล์ยังตั้งค่าไม่ครบ กรุณาติดต่อผู้ดูแลระบบ";
    default:
      return typeof code === "string" && code.length > 0
        ? `อัปโหลดไฟล์ไม่สำเร็จ (${code}) กรุณาลองใหม่หรือติดต่อผู้ดูแลระบบ`
        : "อัปโหลดไฟล์ไม่สำเร็จ กรุณาลองใหม่";
  }
}
