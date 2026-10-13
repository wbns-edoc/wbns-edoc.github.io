export type AuthUserPatchInput = {
  email: string;
  password?: string;
  isActive: boolean;
};

/**
 * Build the Supabase Auth admin update payload from the import spreadsheet.
 * The import's is_active column is authoritative: inactive users are banned,
 * and active users are unbanned. Call only from the trusted user-import Edge Function.
 */
export function buildAuthUserPatch(input: AuthUserPatchInput): {
  email: string;
  password?: string;
  ban_duration: string;
} {
  const patch: { email: string; password?: string; ban_duration: string } = {
    email: input.email,
    ban_duration: input.isActive ? "none" : "876000h",
  };
  if (input.password) patch.password = input.password;
  return patch;
}
