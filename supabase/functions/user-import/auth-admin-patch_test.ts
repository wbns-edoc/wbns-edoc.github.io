import { assertEquals } from "jsr:@std/assert@1";
import { buildAuthUserPatch } from "./auth-admin-patch.ts";

Deno.test("syncs email and password and keeps active Auth accounts unbanned", () => {
  assertEquals(buildAuthUserPatch({
    email: "staff@example.org",
    password: "initial-password-123",
    isActive: true,
  }), {
    email: "staff@example.org",
    password: "initial-password-123",
    ban_duration: "none",
  });
});

Deno.test("bans inactive users without changing their password", () => {
  assertEquals(buildAuthUserPatch({
    email: "inactive@example.org",
    isActive: false,
  }), {
    email: "inactive@example.org",
    ban_duration: "876000h",
  });
});

Deno.test("does not include an empty password in Auth updates", () => {
  assertEquals(buildAuthUserPatch({
    email: "staff@example.org",
    password: "",
    isActive: true,
  }), {
    email: "staff@example.org",
    ban_duration: "none",
  });
});
