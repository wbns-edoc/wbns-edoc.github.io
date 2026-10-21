import { assertEquals } from "jsr:@std/assert@1";
import {
  canActorApproveRequest,
  canCancelLeaveRequest,
  resolveLeaveApprovalRoute,
} from "../src/leave-domain.ts";

Deno.test("uses an explicitly assigned deputy as the first approver", () => {
  assertEquals(
    resolveLeaveApprovalRoute({
      deputyAssigneeUserId: "deputy-user",
      directorAssigneeUserId: "director-user",
      directToDirectorAuthorityVerified: false,
    }),
    { status: "ready", step: "deputy", approverUserId: "deputy-user" },
  );
});

Deno.test("does not route to the director when direct approval authority is unverified", () => {
  assertEquals(
    resolveLeaveApprovalRoute({
      deputyAssigneeUserId: null,
      directorAssigneeUserId: "director-user",
      directToDirectorAuthorityVerified: false,
    }),
    { status: "blocked_approver_resolution", reason: "deputy_role_vacant" },
  );
});

Deno.test("allows direct-to-director route only with verified authority and an assigned director", () => {
  assertEquals(
    resolveLeaveApprovalRoute({
      deputyAssigneeUserId: null,
      directorAssigneeUserId: "director-user",
      directToDirectorAuthorityVerified: true,
    }),
    { status: "ready", step: "director", approverUserId: "director-user" },
  );
  assertEquals(
    resolveLeaveApprovalRoute({
      deputyAssigneeUserId: null,
      directorAssigneeUserId: null,
      directToDirectorAuthorityVerified: true,
    }),
    { status: "blocked_approver_resolution", reason: "approver_missing" },
  );
});

Deno.test("rejects self-approval and missing identities", () => {
  assertEquals(canActorApproveRequest("same-user", "same-user"), false);
  assertEquals(canActorApproveRequest(" same-user ", "same-user"), false);
  assertEquals(canActorApproveRequest("approver", " requester "), true);
  assertEquals(canActorApproveRequest("", "requester"), false);
  assertEquals(canActorApproveRequest("   ", "requester"), false);
  assertEquals(canActorApproveRequest("approver", "requester"), true);
});

Deno.test("cancellation must be at least one Bangkok calendar day before leave", () => {
  // 2026-10-21 16:59 UTC is 2026-10-21 23:59 in Bangkok.
  assertEquals(canCancelLeaveRequest("2026-10-22", new Date("2026-10-21T16:59:00Z")), true);
  // 2026-10-21 17:00 UTC is 2026-10-22 00:00 in Bangkok: too late for leave starting Oct 22.
  assertEquals(canCancelLeaveRequest("2026-10-22", new Date("2026-10-21T17:00:00Z")), false);
});

Deno.test("invalid calendar dates fail closed for cancellation", () => {
  assertEquals(canCancelLeaveRequest("2026-02-30", new Date("2026-02-01T00:00:00Z")), false);
  assertEquals(canCancelLeaveRequest("22-10-2026", new Date("2026-10-20T00:00:00Z")), false);
});

Deno.test("normalizes whitespace around resolved approver IDs", () => {
  assertEquals(
    resolveLeaveApprovalRoute({
      deputyAssigneeUserId: "  deputy-user  ",
      directorAssigneeUserId: " director-user ",
      directToDirectorAuthorityVerified: false,
    }),
    { status: "ready", step: "deputy", approverUserId: "deputy-user" },
  );
  assertEquals(
    resolveLeaveApprovalRoute({
      deputyAssigneeUserId: null,
      directorAssigneeUserId: " director-user ",
      directToDirectorAuthorityVerified: true,
    }),
    { status: "ready", step: "director", approverUserId: "director-user" },
  );
});
