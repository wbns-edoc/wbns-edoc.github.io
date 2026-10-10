import { mayDeleteDriveObject, mayDeleteUploadResources } from "./cleanup-policy.ts";

function assert(condition: boolean, message: string): void {
  if (!condition) throw new Error(message);
}

Deno.test("lookup failure preserves upload resources", () => {
  assert(!mayDeleteUploadResources("lookup-failed"), "must preserve on lookup failure");
});

Deno.test("already-attached metadata preserves upload resources", () => {
  assert(!mayDeleteUploadResources("already-attached"), "must preserve attached resources");
});

Deno.test("confirmed unattached metadata permits cleanup", () => {
  assert(mayDeleteUploadResources("unattached"), "should permit cleanup only when unattached");
});

Deno.test("metadata deletion failure preserves Drive object", () => {
  assert(!mayDeleteDriveObject(true), "must preserve Drive object if metadata deletion failed");
});

Deno.test("successful metadata deletion permits Drive cleanup", () => {
  assert(mayDeleteDriveObject(false), "should permit Drive cleanup after metadata deletion");
});
