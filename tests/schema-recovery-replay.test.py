#!/usr/bin/env python3
"""Parse and phase catalog SQL for a disposable PostgreSQL replay.

Requires pglast==7.10. Never use generated files against Production.
"""
import argparse
import re
from pathlib import Path
from pglast import parse_sql

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "recovery" / "catalog"
RELATIONS = CATALOG / "relations-and-security.sql"
PRIVATE = CATALOG / "private-functions.sql"
PUBLIC = CATALOG / "public-functions.sql"

def statements(path: Path):
    sql = path.read_text(encoding="utf-8")
    if path in (PRIVATE, PUBLIC):
        # pg_get_functiondef snapshots are separated by explicit markers.
        # Parse complete definitions directly instead of using pglast statement
        # offsets, which can truncate function bodies after header comments are
        # filtered or when the parser reports a statement length without the
        # trailing delimiter.
        blocks = sql.split("-- ===== NEXT FUNCTION =====")
        result = []
        for block in blocks:
            lines = block.splitlines()
            lines = [
                line for line in lines
                if not line.strip().startswith((
                    "-- READ-ONLY RECOVERY SNAPSHOT FROM PRODUCTION CATALOG",
                    "-- Project ref:",
                    "-- Captured:",
                    "-- Not a migration.",
                ))
            ]
            statement = "\n".join(lines).strip()
            if not statement:
                continue
            if not statement.upper().startswith(("CREATE OR REPLACE FUNCTION ", "CREATE FUNCTION ")):
                raise AssertionError("Unexpected content in function snapshot: " + statement[:120])
            if not statement.endswith(";"):
                statement += ";"
            parse_sql(statement)
            result.append(statement)
        return result
    # pglast's statement lengths exclude leading comments in some cases, so
    # slicing by stmt_location/stmt_len can produce a comment-only truncated
    # chunk. Remove only known catalog headers/section separators before parse;
    # do not strip arbitrary comments from function bodies.
    metadata_prefixes = (
        "-- READ-ONLY RECOVERY SNAPSHOT FROM PRODUCTION CATALOG",
        "-- Project ref:",
        "-- Captured:",
        "-- IMPORTANT:",
        "-- Review identity/generated columns,",
        "-- Do not execute on Production.",
        "-- Preserve Production view security options.",
        "-- because the view queries read from RLS-protected",
        "-- ===== NEXT FUNCTION =====",
    )
    if path in (PRIVATE, PUBLIC):
        # The captured pg_get_functiondef text omits statement terminators;
        # restore them before parsing/replay, including the final definition.
        sql = sql.replace("$function$\n\n\n-- ===== NEXT FUNCTION =====", "$function$;\n\n\n-- ===== NEXT FUNCTION =====")
        if sql.rstrip().endswith("$function$"):
            sql = sql.rstrip() + ";\n"
    sql = "\n".join(
        line for line in sql.splitlines()
        if not any(line.strip().startswith(prefix) for prefix in metadata_prefixes)
    )
    parsed = parse_sql(sql)
    result = []
    for node in parsed:
        start, length = node.stmt_location, node.stmt_len
        # pglast locations index the decoded SQL text here; slicing UTF-8 bytes
        # can split Thai/non-ASCII characters and raise UnicodeDecodeError.
        chunk = (sql[start:] if length == 0 else sql[start:start + length]).strip()
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
            newline = normalized.find("\n")
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

    # SQL-language bodies are validated at CREATE FUNCTION time. Order those
    # definitions by references to other captured SQL functions so dependencies
    # such as private.user_has_department exist before private.can_access_document.
    function_name = re.compile(
        r"CREATE(?: OR REPLACE)? FUNCTION\\s+((?:public|private)\\.[A-Za-z_][A-Za-z_0-9$]*)\\s*\\(",
        re.IGNORECASE,
    )
    called_name = re.compile(r"\\b(public|private)\\.([A-Za-z_][A-Za-z_0-9$]*)\\s*\\(", re.IGNORECASE)
    named_sql = []
    for statement in sql_functions:
        match = function_name.search(statement)
        if not match:
            raise AssertionError("Could not identify SQL function name: " + statement[:120])
        named_sql.append((match.group(1).lower(), statement))
    sql_names = {name for name, _ in named_sql}
    remaining = list(named_sql)
    ordered_sql = []
    created_names = set()
    while remaining:
        ready = []
        for name, statement in remaining:
            dependencies = {
                (match.group(1) + "." + match.group(2)).lower()
                for match in called_name.finditer(statement)
            } & sql_names
            dependencies.discard(name)
            if dependencies <= created_names:
                ready.append((name, statement))
        if not ready:
            # Preserve evidence and make any genuine dependency cycle visible
            # as a replay failure rather than silently dropping definitions.
            ordered_sql.extend(statement for _, statement in remaining)
            break
        for item in ready:
            ordered_sql.append(item[1])
            created_names.add(item[0])
            remaining.remove(item)
    sql_functions = ordered_sql
    constraints = buckets.get("constraints", [])
    # Add PRIMARY KEY/UNIQUE/CHECK constraints before FOREIGN KEY constraints.
    # A referencing FK may target a table whose primary key would otherwise be
    # added later in the same phase (e.g. approvals -> profiles).
    key_constraints = [s for s in constraints if " FOREIGN KEY " not in s.upper()]
    foreign_keys = [s for s in constraints if " FOREIGN KEY " in s.upper()]
    phases = {
        "01-types.sql": buckets.get("types", []),
        "02-tables.sql": buckets.get("tables", []),
        "03-key-and-check-constraints.sql": key_constraints,
        "04-foreign-key-constraints.sql": foreign_keys,
        "05-indexes.sql": buckets.get("indexes", []),
        "06-functions-plpgsql.sql": plpgsql,
        "07-functions-sql.sql": sql_functions + other_functions,
        "08-rls.sql": buckets.get("rls", []),
        "09-policies.sql": buckets.get("policies", []),
        "10-triggers.sql": buckets.get("triggers", []),
        "11-views.sql": buckets.get("views", []) + view_options,
    }
    if args.out_dir:
        args.out_dir.mkdir(parents=True, exist_ok=True)
        for name, statements_in_phase in phases.items():
            # Catalog snapshots are alphabetically grouped, not dependency ordered.
            # On the disposable replay only, defer function-body validation until
            # all function definitions exist; later views and inventory checks
            # still verify that the complete captured object set can be created.
            # This does not make the snapshot a production migration.
            prefix = "-- GENERATED FOR DISPOSABLE REPLAY ONLY; DO NOT APPLY TO PRODUCTION.\n\n"
            if name in ("06-functions-plpgsql.sql", "07-functions-sql.sql"):
                prefix += "SET check_function_bodies = off;\n"
                suffix = "\nSET check_function_bodies = on;\n"
            else:
                suffix = ""
            (args.out_dir / name).write_text(
                prefix + "\n\n".join(statements_in_phase) + suffix + "\n",
                encoding="utf-8",
            )
    print("Parsed and classified SQL statements (no SQL executed by this script):")
    for name, statements_in_phase in phases.items():
        print(f"  {name}: {len(statements_in_phase)}")
    print("Parser/classification checks passed.")

if __name__ == "__main__":
    main()
