#!/usr/bin/env python3
"""Parse and classify the catalog snapshot without executing it.

Requires pglast==7.10. This is a deterministic dependency-planning check, not
a schema replay test. The snapshot remains evidence-only and must not be run
against Production.
"""
from pathlib import Path
from pglast import parse_sql

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "recovery" / "catalog"
RELATIONS = CATALOG / "relations-and-security.sql"
PRIVATE = CATALOG / "private-functions.sql"
PUBLIC = CATALOG / "public-functions.sql"

def statements(path: Path):
    sql = path.read_text(encoding="utf-8")
    parsed = parse_sql(sql)
    # pglast locations/lengths are byte offsets. Keep source as bytes so
    # Unicode identifiers/comments cannot skew statement boundaries.
    raw = sql.encode("utf-8")
    result = []
    for node in parsed:
        start = node.stmt_location
        length = node.stmt_len
        if length == 0:
            chunk = raw[start:].decode("utf-8").strip()
        else:
            chunk = raw[start:start + length].decode("utf-8").strip()
        if chunk:
            result.append(chunk)
    return result

def classify(statement: str):
    normalized = statement.lstrip().upper()
    if normalized.startswith("CREATE TYPE "):
        return "types"
    if normalized.startswith("CREATE TABLE "):
        return "tables"
    if normalized.startswith("ALTER TABLE ") and " ADD CONSTRAINT " in normalized:
        return "constraints"
    if normalized.startswith("CREATE INDEX ") or normalized.startswith("CREATE UNIQUE INDEX "):
        return "indexes"
    if normalized.startswith("ALTER TABLE ") and (
        " ENABLE ROW LEVEL SECURITY" in normalized or
        " FORCE ROW LEVEL SECURITY" in normalized or
        " DISABLE ROW LEVEL SECURITY" in normalized
    ):
        return "rls"
    if normalized.startswith("CREATE POLICY "):
        return "policies"
    if normalized.startswith("CREATE TRIGGER ") or normalized.startswith("ALTER TABLE ") and " TRIGGER " in normalized:
        return "triggers"
    if normalized.startswith("CREATE OR REPLACE VIEW ") or normalized.startswith("CREATE VIEW "):
        return "views"
    if normalized.startswith("ALTER VIEW "):
        return "view_options"
    if normalized.startswith("CREATE OR REPLACE FUNCTION ") or normalized.startswith("CREATE FUNCTION "):
        return "functions"
    raise AssertionError("Unclassified SQL statement: " + statement[:160].replace("\n", " "))

def main():
    relation_statements = statements(RELATIONS)
    buckets = {}
    for statement in relation_statements:
        phase = classify(statement)
        buckets.setdefault(phase, []).append(statement)

    private_functions = statements(PRIVATE)
    public_functions = statements(PUBLIC)
    assert len(buckets.get("types", [])) == 5, "expected 5 enum types"
    assert len(buckets.get("tables", [])) == 25, "expected 25 table definitions"
    assert len(buckets.get("constraints", [])) > 0, "expected captured constraints"
    assert len(buckets.get("policies", [])) == 45, "expected 45 RLS policies"
    assert len(buckets.get("triggers", [])) == 12, "expected 12 triggers"
    assert len(buckets.get("views", [])) == 2, "expected 2 views"
    assert len(private_functions) == 26, f"expected 26 private functions, got {len(private_functions)}"
    assert len(public_functions) == 28, f"expected 28 public functions, got {len(public_functions)}"

    # Function snapshots use explicit separators to make function boundaries
    # deterministic; SQL parsing independently verifies the resulting file.
    assert all(classify(s) == "functions" for s in private_functions), "private snapshot contains non-function SQL"
    assert all(classify(s) == "functions" for s in public_functions), "public snapshot contains non-function SQL"

    for view in buckets["views"]:
        if "document_monthly_summary" in view:
            assert any("document_monthly_summary" in s and "security_invoker = true" in s for s in buckets.get("view_options", []))
        if "document_report_summary" in view:
            assert any("document_report_summary" in s and "security_invoker = true" in s for s in buckets.get("view_options", []))

    print("Parsed snapshot statements:")
    for phase in ("types", "tables", "constraints", "indexes", "rls", "functions", "policies", "triggers", "views", "view_options"):
        if phase in buckets:
            print(f"  {phase}: {len(buckets[phase])}")
    print(f"  private functions: {len(private_functions)}")
    print(f"  public functions: {len(public_functions)}")
    print("SQL parser/classification checks passed; no SQL was executed.")

if __name__ == "__main__":
    main()
