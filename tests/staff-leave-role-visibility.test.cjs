const assert = require("node:assert/strict");
const fs = require("node:fs");

const source = fs.readFileSync("src/main.tsx", "utf8");
const start = source.indexOf("function StaffLeave(");
const end = source.indexOf("function AboutSystem(", start);
assert.ok(start >= 0 && end > start, "StaffLeave component must exist");
const leave = source.slice(start, end);

assert.ok(leave.includes(".replace(/\\s+/g,'_')"),`role display names must be normalized before checking access`);
for (const role of [
  "director",
  "deputy_director",
  "system_admin",
  "ผู้อำนวยการโรงเรียน",
  "รองผู้อำนวยการโรงเรียน",
  "ผู้ดูแลระบบ",
]) {
  assert.ok(leave.includes(role), `missing supported role code/name: ${role}`);
}
assert.match(leave, /const canViewDashboard=.*ผู้อำนวยการโรงเรียน.*รองผู้อำนวยการโรงเรียน/s,
  "Director and Vice Director role names must expose the approver dashboard");
assert.match(leave, /const canManageAbsence=.*system_admin.*ผู้ดูแลระบบ/s,
  "only System Admin role code/name may manage Director absence evidence");

const bellStart = source.indexOf("function NotificationBell(");
const bellEnd = source.indexOf("\nfunction Nav(", bellStart);
assert.ok(bellStart >= 0 && bellEnd > bellStart, "NotificationBell component must exist");
const bell = source.slice(bellStart, bellEnd);
assert.ok(bell.includes("supabase.channel('notifications:'+profile.id"),
  "notification bell must subscribe to the current user's channel");
assert.ok(bell.includes("event:'INSERT',schema:'public',table:'notifications'"),
  "notification bell must receive newly inserted notification rows");
assert.ok(bell.includes("filter:'recipient_id=eq.'+profile.id"),
  "realtime subscription must filter by the authenticated recipient");

console.log("Staff leave role and realtime visibility regression tests passed.");
