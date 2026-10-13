export function parseIsActive(value: unknown): boolean | null {
  if (value === undefined || value === null || value === "") return true;
  if (typeof value === "boolean") return value;
  if (typeof value === "number") return value === 1 ? true : value === 0 ? false : null;
  if (typeof value === "string") {
    const normalized = value.trim().toLowerCase();
    if (["true", "1", "yes", "y", "active", "ใช่", "ใช้งาน"].includes(normalized)) return true;
    if (["false", "0", "no", "n", "inactive", "ไม่", "ไม่ใช่", "ระงับ"].includes(normalized)) return false;
    if (!normalized) return true;
  }
  return null;
}
