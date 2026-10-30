const assert = require("node:assert/strict");
const fs = require("node:fs");

const source = fs.readFileSync("src/main.tsx", "utf8");
const start = source.indexOf("function StaffLeave(");
const end = source.indexOf("function AboutSystem(", start);
assert.ok(start >= 0 && end > start, "StaffLeave component must exist");
const leave = source.slice(start, end);

assert.match(leave, /new Set\(roles\.map\(role=>String\(role\)\.trim\(\)\.toLocaleLowerCase\(\)\.replace\(\/\\\\s\+\/g,'_'\)\)\)/,
  "role display names must be normalized before checking access");
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

console.log("Staff leave role visibility regression tests passed.");
