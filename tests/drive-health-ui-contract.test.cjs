const assert = require("node:assert/strict");
const fs = require("node:fs");

const app = fs.readFileSync("src/main.tsx", "utf8");
const uiStart = app.indexOf("function DriveHealthCheck(");
const uiEnd = app.indexOf("function AuditLogs(", uiStart);
assert.ok(uiStart >= 0 && uiEnd > uiStart, "DriveHealthCheck component must exist");
const ui = app.slice(uiStart, uiEnd);
assert.ok(ui.includes("result.folder_name"), "health UI must display the bridge folder_name field");
assert.ok(!ui.includes("result.root_folder"), "health UI must not expect a root_folder object absent from bridge response");
assert.ok(ui.includes("result.write_test_performed"), "health UI must state whether a write test was performed");

const edge = fs.readFileSync("supabase/functions/drive-health/index.ts", "utf8");
assert.ok(edge.includes("folder_name: result.folder_name"), "Edge Function must expose the bridge folder name");
assert.ok(edge.includes("write_test_performed: false"), "health check must remain read-only");
const config = fs.readFileSync("supabase/config.toml", "utf8");
assert.match(config, /\[functions\.drive-health\][\s\S]*?verify_jwt = true/,
  "drive-health Edge Function must require a verified JWT");

console.log("Drive health UI/Edge Function contract tests passed.");
