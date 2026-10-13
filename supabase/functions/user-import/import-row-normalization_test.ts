import { assertEquals } from "jsr:@std/assert@1";
import { parseIsActive } from "./import-row-normalization.ts";

Deno.test("defaults a missing status to active for backward-compatible imports", () => {
  assertEquals(parseIsActive(undefined), true);
  assertEquals(parseIsActive(""), true);
});

Deno.test("accepts common true and false spreadsheet encodings", () => {
  for (const value of [true, 1, "true", "TRUE", "yes", "1", "active", "ใช่", "ใช้งาน"]) {
    assertEquals(parseIsActive(value), true);
  }
  for (const value of [false, 0, "false", "FALSE", "no", "0", "inactive", "ไม่", "ไม่ใช่", "ระงับ"]) {
    assertEquals(parseIsActive(value), false);
  }
});

Deno.test("rejects ambiguous account status values instead of activating accounts", () => {
  assertEquals(parseIsActive("maybe"), null);
  assertEquals(parseIsActive(2), null);
  assertEquals(parseIsActive({}), null);
});
