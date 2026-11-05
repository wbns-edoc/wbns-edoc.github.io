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
const migrationMatrix = read("recovery/catalog/migration-coverage-matrix.md");
const fixtureDrift = read("recovery/catalog/fixture-drift-report.md");
const sourceSearch = read("recovery/catalog/missing-migration-history-search.md");
const branchCandidateReview = read("recovery/catalog/branch-candidate-review.md");
const authorizationSemanticReview = read("recovery/catalog/authorization-semantic-review.md");
const productionReadOnlyValidation = read("recovery/catalog/production-readonly-validation-2026-10-16.md");
const authorizationCandidate = read("recovery/catalog/candidate-has-department-permission-active-department.sql");
const activeDepartmentMigration = read("supabase/migrations/20261030094941_require_active_department_for_scoped_permissions.sql");
const replayWorkflow = read(".github/workflows/schema-recovery-postgres-replay.yml");
const rlsBehavior = read("tests/schema-recovery-rls-behavior.sql");

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
assert.match(migrationPlan, /unavailable historical migration is being guessed from its name/i);
assert.match(migrationPlan, /October 10 fixture vs October 15 catalog/i);
assert.equal(count(migrationMatrix, /^\| 202610[0-9]+ \|/gm), 55, "expected all 55 Production migration history entries in coverage matrix");
assert.match(migrationMatrix, /Foundation placeholder/i);
assert.match(migrationMatrix, /Missing source candidate/i);
assert.match(migrationMatrix, /No Production migration or schema change was applied/i);
assert.match(readme, /fixture-drift-report\.md/);
assert.match(fixtureDrift, /Do not use the October 10 fixture as the clean-install baseline/i);
assert.match(fixtureDrift, /Full Supabase clean-install parity: NOT PROVEN/i);
assert.match(fixtureDrift, /Production deployment: NOT APPROVED/i);
assert.match(fixtureDrift, /public\.user_departments/);
assert.match(fixtureDrift, /No database write was performed/i);
assert.match(readme, /missing-migration-history-search\.md/);
assert.match(sourceSearch, /No commits were returned/i);
assert.match(sourceSearch, /does \*\*not\*\* prove the SQL never existed/i);
assert.match(sourceSearch, /Production deployment remains \*\*NOT APPROVED\*\*/i);
assert.match(readme, /branch-candidate-review\.md/);
assert.match(branchCandidateReview, /16 reviewed files declare 20 distinct schema-qualified function names/i);
assert.match(branchCandidateReview, /name-only consistency signal/i);
assert.match(branchCandidateReview, /Production deployment is \*\*NOT APPROVED\*\*/i);
assert.match(branchCandidateReview, /No migration was applied to Supabase/i);
assert.match(readme, /authorization-semantic-review\.md/);
assert.match(authorizationSemanticReview, /departments\.is_active/);
assert.match(authorizationSemanticReview, /assert create, update, and approve for both System Admin and director/i);
assert.match(authorizationSemanticReview, /No Production writes were performed/i);
assert.match(readme, /production-readonly-validation-2026-10-16\.md/);
assert.match(productionReadOnlyValidation, /Inactive departments \| 0/);
assert.match(productionReadOnlyValidation, /No Production writes were performed/i);
assert.match(productionReadOnlyValidation, /Production deployment is \*\*NOT APPROVED\*\*/i);
assert.match(authorizationCandidate, /JOIN public\.departments d[\s\S]*?d\.is_active = true/i);
assert.match(authorizationCandidate, /wr\.code IN \(\x27system_admin\x27,\x27director\x27\)/i);
assert.match(replayWorkflow, /Apply active-department permission guard \(disposable DB only\)/i);
assert.match(replayWorkflow, /20261030094941_require_active_department_for_scoped_permissions\.sql/);
assert.match(activeDepartmentMigration, /wr\.code = 'deputy_director'/i);
assert.match(activeDepartmentMigration, /p_permission = 'document\.assign'/i);
assert.match(rlsBehavior, /ordinary user must not retain scoped permission in inactive department/i);
assert.match(rlsBehavior, /director global permission exception must remain effective/i);
assert.match(rlsBehavior, /deputy_director must retain the existing global document\.assign exception/i);
assert.match(rlsBehavior, /inactive profile must not retain department-scoped permissions/i);
assert.match(rlsBehavior, /removed department membership must remove scoped permission/i);
assert.match(rlsBehavior, /disabled department permission must not authorize update/i);
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
