import {
  MAX_FILENAME_CODE_POINTS,
  MAX_UPLOAD_BYTES,
  validateUploadInput,
  isValidFileRole,
} from "./file-validation.ts";

Deno.test("accepts a normal Thai document filename within size limit", () => {
  if (validateUploadInput({ name: "หนังสือราชการ.pdf", size: 1024 }) !== null) {
    throw new Error("expected valid document filename to be accepted");
  }
});

Deno.test("rejects empty or non-finite file sizes", () => {
  for (const size of [0, -1, Number.NaN, Number.POSITIVE_INFINITY]) {
    if (validateUploadInput({ name: "document.pdf", size }) !== "EMPTY_FILE") {
      throw new Error("expected invalid size " + size + " to be rejected");
    }
  }
});

Deno.test("rejects files above the existing 25 MiB limit", () => {
  if (validateUploadInput({ name: "document.pdf", size: MAX_UPLOAD_BYTES + 1 }) !== "FILE_TOO_LARGE") {
    throw new Error("expected oversized file to be rejected");
  }
});

Deno.test("accepts a file exactly at the existing size limit", () => {
  if (validateUploadInput({ name: "document.pdf", size: MAX_UPLOAD_BYTES }) !== null) {
    throw new Error("expected size limit boundary to be accepted");
  }
});

Deno.test("rejects empty, path-like, and control-character filenames", () => {
  for (const name of ["", "   ", "../document.pdf", "folder\\document.pdf", "bad\nname.pdf"]) {
    if (validateUploadInput({ name, size: 1 }) !== "INVALID_FILE_NAME") {
      throw new Error("expected invalid filename to be rejected: " + JSON.stringify(name));
    }
  }
});

Deno.test("rejects filenames longer than 255 Unicode code points", () => {
  const name = "ก".repeat(MAX_FILENAME_CODE_POINTS + 1) + ".pdf";
  if (validateUploadInput({ name, size: 1 }) !== "INVALID_FILE_NAME") {
    throw new Error("expected overlong filename to be rejected");
  }
});

Deno.test("accepts the supported main, cover letter, and unique attachment roles", () => {
  for (const role of ["main", "cover_letter", "attachment:123e4567-e89b-42d3-a456-426614174000"]) {
    if (!isValidFileRole(role)) throw new Error("expected valid file role: " + role);
  }
});

Deno.test("rejects unsupported or malformed attachment roles", () => {
  for (const role of ["", "other", "attachment:not-a-uuid", null, 1]) {
    if (isValidFileRole(role)) throw new Error("expected invalid file role to be rejected: " + role);
  }
});
