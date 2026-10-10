import { assertEquals } from "jsr:@std/assert@1";
import { authorizeUserImport } from "./authorization.ts";

Deno.test("requires user.manage for profile import", () => {
  assertEquals(authorizeUserImport({ action: "import", permissionCodes: ["role.manage"], hasRoleAssignment: false }), { allowed: false, reason: "user_manage_required" });
});
Deno.test("role.manage alone cannot authorize account actions", () => {
  for (const action of ["set_active", "resend_invitation"] as const) {
    assertEquals(authorizeUserImport({ action, permissionCodes: ["role.manage"], hasRoleAssignment: false }), { allowed: false, reason: "user_manage_required" });
  }
});
Deno.test("requires role.manage as an additional permission when import assigns a role", () => {
  assertEquals(authorizeUserImport({ action: "import", permissionCodes: ["user.manage"], hasRoleAssignment: true }), { allowed: false, reason: "role_manage_required" });
});
Deno.test("allows profile import without role assignment with user.manage", () => {
  assertEquals(authorizeUserImport({ action: "import", permissionCodes: ["user.manage"], hasRoleAssignment: false }), { allowed: true });
});
Deno.test("allows role assignment only when both permissions are present", () => {
  assertEquals(authorizeUserImport({ action: "import", permissionCodes: ["user.manage", "role.manage"], hasRoleAssignment: true }), { allowed: true });
});
