/**
 * Pure policy helpers for compensating cleanup after a partially completed upload.
 * Keep these decisions isolated so failure paths can be tested without live Google Drive
 * or Supabase credentials.
 */
export type AttachmentLookupState = "lookup-failed" | "already-attached" | "unattached";

/** Only a positively confirmed unattached metadata row is eligible for cleanup. */
export function mayDeleteUploadResources(state: AttachmentLookupState): boolean {
  return state === "unattached";
}

/** If metadata deletion fails, preserve the Drive object for later reconciliation. */
export function mayDeleteDriveObject(metadataDeleteFailed: boolean): boolean {
  return !metadataDeleteFailed;
}
