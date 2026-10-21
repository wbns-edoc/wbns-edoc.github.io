export type LeaveApprovalRoute =
  | { status: "ready"; step: "deputy"; approverUserId: string }
  | { status: "ready"; step: "director"; approverUserId: string }
  | { status: "blocked_approver_resolution"; reason: "deputy_role_vacant" | "authority_not_verified" | "approver_missing" };

export interface LeaveRouteInput {
  deputyAssigneeUserId: string | null;
  directorAssigneeUserId: string | null;
  /** True only when the applicable official authority/delegation has been verified and recorded. */
  directToDirectorAuthorityVerified: boolean;
}

/**
 * Resolves a leave approver without silently granting roles or routing work to a vacant role.
 * This is a domain guard, not a replacement for server-side authorization.
 */
export function resolveLeaveApprovalRoute(input: LeaveRouteInput): LeaveApprovalRoute {
  if (input.deputyAssigneeUserId?.trim()) {
    return { status: "ready", step: "deputy", approverUserId: input.deputyAssigneeUserId };
  }

  if (!input.directToDirectorAuthorityVerified) {
    return {
      status: "blocked_approver_resolution",
      reason: input.deputyAssigneeUserId === null ? "deputy_role_vacant" : "approver_missing",
    };
  }

  if (!input.directorAssigneeUserId?.trim()) {
    return { status: "blocked_approver_resolution", reason: "approver_missing" };
  }

  return { status: "ready", step: "director", approverUserId: input.directorAssigneeUserId };
}

export function canActorApproveRequest(actorUserId: string, requesterUserId: string): boolean {
  return actorUserId.trim().length > 0 &&
    requesterUserId.trim().length > 0 &&
    actorUserId !== requesterUserId;
}

function bangkokDateParts(date: Date): { year: number; month: number; day: number } {
  const parts = new Intl.DateTimeFormat("en-GB", {
    timeZone: "Asia/Bangkok",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(date);
  const value = (type: string) => Number(parts.find((part) => part.type === type)?.value);
  return { year: value("year"), month: value("month"), day: value("day") };
}

function parseIsoCalendarDate(value: string): number | null {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return null;
  const [year, month, day] = value.split("-").map(Number);
  const timestamp = Date.UTC(year, month - 1, day);
  const date = new Date(timestamp);
  if (date.getUTCFullYear() !== year || date.getUTCMonth() !== month - 1 || date.getUTCDate() !== day) {
    return null;
  }
  return timestamp;
}

/**
 * Enforces the currently specified minimum of one calendar day before leave starts.
 * Uses the school's Asia/Bangkok calendar date. This guard must also be enforced by the server.
 */
export function canCancelLeaveRequest(startDate: string, now: Date): boolean {
  const startTimestamp = parseIsoCalendarDate(startDate);
  if (startTimestamp === null || Number.isNaN(now.getTime())) return false;
  const today = bangkokDateParts(now);
  const todayTimestamp = Date.UTC(today.year, today.month - 1, today.day);
  const oneDayMs = 24 * 60 * 60 * 1000;
  return todayTimestamp <= startTimestamp - oneDayMs;
}
