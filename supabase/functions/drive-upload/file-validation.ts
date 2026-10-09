/**
 * Input validation that does not assume a school-specific document format allowlist.
 * File content type and extension are intentionally not restricted until accepted formats
 * are confirmed with the school; this helper only enforces safe transport-level bounds.
 */
export const MAX_UPLOAD_BYTES = 25 * 1024 * 1024;
export const MAX_FILENAME_CODE_POINTS = 255;

export type UploadValidationCode =
  | "EMPTY_FILE"
  | "FILE_TOO_LARGE"
  | "INVALID_FILE_NAME";

export function validateUploadInput(
  file: { name: string; size: number },
): UploadValidationCode | null {
  if (!Number.isFinite(file.size) || file.size <= 0) return "EMPTY_FILE";
  if (file.size > MAX_UPLOAD_BYTES) return "FILE_TOO_LARGE";

  const name = file.name;
  if (
    typeof name !== "string" ||
    name.trim().length === 0 ||
    [...name].length > MAX_FILENAME_CODE_POINTS ||
    /[\u0000-\u001f\u007f]/u.test(name) ||
    name.includes("/") ||
    name.includes("\\")
  ) {
    return "INVALID_FILE_NAME";
  }
  return null;
}
