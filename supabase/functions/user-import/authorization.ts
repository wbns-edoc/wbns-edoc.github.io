export type UserImportAction = "import" | "set_active" | "resend_invitation";

export interface UserImportAuthorizationInput {
  action: UserImportAction;
  permissionCodes: Iterable<string>;
  hasRoleAssignment: boolean;
}

/** Profile/account mutations require user.manage; role assignment additionally requires role.manage. */
export function authorizeUserImport(input: UserImportAuthorizationInput): {
  allowed: boolean;
  reason?: "user_manage_required" | "role_manage_required";
} {
  const permissions = new Set(input.permissionCodes);
  if (!permissions.has("user.manage")) return { allowed: false, reason: "user_manage_required" };
  if (input.action === "import" && input.hasRoleAssignment && !permissions.has("role.manage")) {
    return { allowed: false, reason: "role_manage_required" };
  }
  return { allowed: true };
}
