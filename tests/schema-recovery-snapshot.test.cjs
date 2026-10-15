const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const root = path.resolve(__dirname, "..");
const read = (p) => fs.readFileSync(path.join(root, p), "utf8");
const relations = read("recovery/catalog/relations-and-security.sql");
const privateFunctions = read("recovery/catalog/private-functions.sql");
const publicFunctions = read("recovery/catalog/public-functions.sql");
const readme = read("recovery/README.md");
const security = read("recovery/catalog/security-follow-up.md");
const replayAudit = read("recovery/catalog/replay-dependency-audit.md");
const migrationPlan = read("recovery/catalog/migration-reconstruction-plan.md");

const count = (text, regex) => (text.match(regex) || []).length;

assert.equal(count(relations, /^CREATE TABLE /gm), 25, "expected 25 captured tables");
assert.equal(count(relations, /^CREATE TYPE /gm), 5, "expected 5 enum types");
assert.equal(count(relations, /^CREATE POLICY /gm), 45, "expected 45 RLS policies");
assert.equal(count(relations, /^CREATE TRIGGER /gm), 12, "expected 12 non-internal triggers");
assert.equal(count(relations, /^CREATE OR REPLACE VIEW /gm), 2, "expected 2 views");
assert.equal(count(privateFunctions, /^CREATE OR REPLACE FUNCTION /gm), 26, "expected 26 private functions");
assert.equal(count(publicFunctions, /^CREATE OR REPLACE FUNCTION /gm), 28, "expected 28 public functions");

assert.match(relations, /ALTER VIEW public\.document_monthly_summary SET \(security_invoker = true\);/);
assert.match(relations, /ALTER VIEW public\.document_report_summary SET \(security_invoker = true\);/);
assert.match(readme, /not a verified, standalone schema dump/i);
assert.match(readme, /Never apply these files to Production/i);
assert.match(security, /no policies explicitly target/i);
assert.match(replayAudit, /naive replay/i);
assert.match(replayAudit, /disposable PostgreSQL 17 replay completed successfully/i);
assert.match(migrationPlan, /Do not replace .*foundation_schema_rbac_rls\.sql/i);
assert.match(migrationPlan, /Historical migration reproducibility.*BLOCKED/i);
assert.match(migrationPlan, /Production deployment readiness.*NOT APPROVED/i);
assert.match(migrationPlan, /Never infer SQL from a migration name/i);
assert.match(migrationPlan, /Production schema/i);
for (const fn of ["audit_row_change", "default_document_department", "guard_document_department_change", "set_updated_at"]) {
  assert.ok(privateFunctions.includes(fn) || publicFunctions.includes(fn), `missing captured trigger function: ${fn}`);
}

// Guard this evidence branch from accidentally becoming a destructive migration.
for (const [name, sql] of [
  ["relations", relations],
  ["private functions", privateFunctions],
  ["public functions", publicFunctions],
]) {
  assert.doesNotMatch(sql, /^\s*(DROP\s+(TABLE|SCHEMA|FUNCTION|VIEW)|TRUNCATE\s+)/im,
    name + " snapshot must not contain destructive drop/truncate statements");
}

console.log("Schema recovery snapshot static checks passed. This does not validate replay against PostgreSQL.");
