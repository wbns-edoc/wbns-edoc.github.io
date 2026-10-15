#!/usr/bin/env python3
"""Parse and phase catalog SQL for a disposable PostgreSQL replay.

Requires pglast==7.10. Never use generated files against Production.
"""
import argparse
from pathlib import Path
from pglast import parse_sql

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "recovery" / "catalog"
RELATIONS = CATALOG / "relations-and-security.sql"
PRIVATE = CATALOG / "private-functions.sql"
PUBLIC = CATALOG / "public-functions.sql"

def statements(path: Path):
    sql = path.read_text(encoding="utf-8")
    raw = sql.encode("utf-8")
    parsed = parse_sql(sql)
    result = []
    for node in parsed:
        start, length = node.stmt_location, node.stmt_len
        chunk = (raw[start:] if length == 0 else raw[start:start + length]).decode("utf-8").strip()
        if chunk:
            result.append(chunk.rstrip(";") + ";")
    return result

def classify(statement: str):
    # pglast statement locations may include comments immediately preceding a
    # statement. Remove leading SQL comments for classification while keeping
    # the original statement text intact in generated replay phases.
    normalized = statement.lstrip()
    while True:
        if normalized.startswith("--"):
            newline = normalized.find("\\n")
            normalized = "" if newline < 0 else normalized[newline + 1:].lstrip()
            continue
        if normalized.startswith("/*"):
            end = normalized.find("*/", 2)
            if end < 0:
                raise AssertionError("Unterminated leading SQL comment")
            normalized = normalized[end + 2:].lstrip()
            continue
        break
    normalized = normalized.upper()
    if normalized.startswith("CREATE TYPE "):
        return "types"
    if normalized.startswith("CREATE TABLE "):
        return "tables"
    if normalized.startswith("ALTER TABLE ") and " ADD CONSTRAINT " in normalized:
        return "constraints"
    if normalized.startswith("CREATE UNIQUE INDEX ") or normalized.startswith("CREATE INDEX "):
        return "indexes"
    if normalized.startswith("ALTER TABLE ") and any(x in normalized for x in (
        " ENABLE ROW LEVEL SECURITY", " FORCE ROW LEVEL SECURITY", " DISABLE ROW LEVEL SECURITY"
    )):
        return "rls"
    if normalized.startswith("CREATE POLICY "):
        return "policies"
    if normalized.startswith("CREATE TRIGGER "):
        return "triggers"
    if normalized.startswith("CREATE OR REPLACE VIEW ") or normalized.startswith("CREATE VIEW "):
        return "views"
    if normalized.startswith("ALTER VIEW "):
        return "view_options"
    if normalized.startswith("CREATE OR REPLACE FUNCTION ") or normalized.startswith("CREATE FUNCTION "):
        return "functions"
    raise AssertionError("Unclassified SQL statement: " + statement[:180].replace("\n", " "))

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--out-dir", type=Path, help="write phase SQL for a disposable test database")
    args = parser.parse_args()

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
    assert all(classify(s) == "functions" for s in private_functions), "private snapshot contains non-function SQL"
    assert all(classify(s) == "functions" for s in public_functions), "public snapshot contains non-function SQL"

    view_options = buckets.get("view_options", [])
    for view_name in ("document_monthly_summary", "document_report_summary"):
        assert any(view_name in view and "security_invoker = true" in view for view in view_options), \
            f"missing security_invoker=true for {view_name}"

    # CREATE TABLE definitions are emitted before constraints so every FK target
    # exists. Function bodies are ordered PL/pgSQL first, then SQL functions;
    # this helps SQL wrappers resolve underlying functions in the common case.
    all_functions = private_functions + public_functions
    plpgsql = [s for s in all_functions if "language plpgsql" in s.lower()]
    sql_functions = [s for s in all_functions if "language sql" in s.lower()]
    other_functions = [s for s in all_functions if s not in plpgsql and s not in sql_functions]
    phases = {
        "01-types.sql": buckets.get("types", []),
        "02-tables.sql": buckets.get("tables", []),
        "03-constraints.sql": buckets.get("constraints", []),
        "04-indexes.sql": buckets.get("indexes", []),
        "05-functions-plpgsql.sql": plpgsql,
        "06-functions-sql.sql": sql_functions + other_functions,
        "07-rls.sql": buckets.get("rls", []),
        "08-policies.sql": buckets.get("policies", []),
        "09-triggers.sql": buckets.get("triggers", []),
        "10-views.sql": buckets.get("views", []) + view_options,
    }
    if args.out_dir:
        args.out_dir.mkdir(parents=True, exist_ok=True)
        for name, statements_in_phase in phases.items():
            (args.out_dir / name).write_text(
                "-- GENERATED FOR DISPOSABLE REPLAY ONLY; DO NOT APPLY TO PRODUCTION.\n\n"
                + "\n\n".join(statements_in_phase) + "\n",
                encoding="utf-8",
            )
    print("Parsed and classified SQL statements (no SQL executed by this script):")
    for name, statements_in_phase in phases.items():
        print(f"  {name}: {len(statements_in_phase)}")
    print("Parser/classification checks passed.")

if __name__ == "__main__":
    main()
