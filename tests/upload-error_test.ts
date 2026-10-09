import { assertEquals } from "jsr:@std/assert@1";
import { getUploadErrorMessage } from "../src/upload-error.ts";

Deno.test("maps filename validation errors to Thai guidance", () => {
  assertEquals(
    getUploadErrorMessage("INVALID_FILE_NAME"),
    "ชื่อไฟล์ไม่ถูกต้อง กรุณาตรวจสอบชื่อไฟล์และลองใหม่",
  );
});

Deno.test("maps oversized and empty uploads to Thai guidance", () => {
  assertEquals(getUploadErrorMessage("FILE_TOO_LARGE"), "ไฟล์มีขนาดเกิน 25 MiB");
  assertEquals(getUploadErrorMessage("EMPTY_FILE"), "ไฟล์ว่างเปล่า กรุณาเลือกไฟล์ใหม่");
});

Deno.test("maps expired sessions and permission denials", () => {
  assertEquals(getUploadErrorMessage("AUTH_INVALID"), "เซสชันหมดอายุ กรุณาเข้าสู่ระบบใหม่");
  assertEquals(getUploadErrorMessage("INSUFFICIENT_PERMISSION"), "คุณไม่มีสิทธิ์แนบไฟล์กับเอกสารนี้");
});

Deno.test("maps missing server configuration to actionable guidance", () => {
  assertEquals(
    getUploadErrorMessage("GOOGLE_DRIVE_CONFIGURATION_MISSING"),
    "ระบบจัดเก็บไฟล์ยังตั้งค่าไม่ครบ กรุณาติดต่อผู้ดูแลระบบ",
  );
});

Deno.test("unknown machine codes remain actionable", () => {
  assertEquals(
    getUploadErrorMessage("GOOGLE_DRIVE_UPLOAD_FAILED"),
    "อัปโหลดไฟล์ไม่สำเร็จ (GOOGLE_DRIVE_UPLOAD_FAILED) กรุณาลองใหม่หรือติดต่อผู้ดูแลระบบ",
  );
  assertEquals(getUploadErrorMessage(undefined), "อัปโหลดไฟล์ไม่สำเร็จ กรุณาลองใหม่");
});

import { getUploadRefreshMessage } from "../src/upload-refresh.ts";

Deno.test("does not report a failed refresh as a failed upload", () => {
  assertEquals(getUploadRefreshMessage(true), null);
  assertEquals(
    getUploadRefreshMessage(false),
    "อัปโหลดไฟล์สำเร็จแล้ว แต่รีเฟรชข้อมูลเอกสารไม่สำเร็จ กรุณาโหลดหน้าใหม่เพื่อตรวจสอบสถานะ",
  );
});

Deno.test("maps server-side Drive and metadata failures to Thai guidance", () => {
  assertEquals(
    getUploadErrorMessage("GOOGLE_DRIVE_CONFIGURATION_INVALID"),
    "การตั้งค่าบัญชีจัดเก็บไฟล์ไม่ถูกต้อง กรุณาติดต่อผู้ดูแลระบบ",
  );
  assertEquals(
    getUploadErrorMessage("FILE_METADATA_SAVE_FAILED"),
    "จัดเก็บไฟล์แล้วแต่เชื่อมโยงกับเอกสารไม่สำเร็จ ระบบอาจต้องตรวจสอบก่อนลองใหม่",
  );
});
