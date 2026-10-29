#!/usr/bin/env bash
set -euo pipefail

migration="supabase/migrations/20261021100000_staff_leave_secure_schema_draft.sql"
if [[ ! -f "$migration" ]]; then
  echo "Missing migration: $migration" >&2
  exit 2
fi

tmpdir="$(mktemp -d)"
dbs=()
cleanup() {
  for db in "${dbs[@]}"; do
    dropdb --if-exists "$db" >/dev/null 2>&1 || true
  done
  rm -rf "$tmpdir"
}
trap cleanup EXIT

expect_preflight_failure() {
  local suffix="$1"
  local fixture_sql="$2"
  local expected="$3"
  local db="leave_preflight_${suffix}_$$"
  dbs+=("$db")
  createdb "$db"

  if [[ -n "$fixture_sql" ]]; then
    psql -X -v ON_ERROR_STOP=1 -d "$db" -c "$fixture_sql" >/dev/null
  fi

  if psql -X -v ON_ERROR_STOP=1 -d "$db" -f "$migration" >"$tmpdir/$suffix.log" 2>&1; then
    echo "FAIL: migration unexpectedly succeeded for $suffix fixture" >&2
    cat "$tmpdir/$suffix.log" >&2
    exit 1
  fi

  if ! grep -Fq "$expected" "$tmpdir/$suffix.log"; then
    echo "FAIL: expected diagnostic missing for $suffix fixture: $expected" >&2
    cat "$tmpdir/$suffix.log" >&2
    exit 1
  fi

  local created
  created="$(psql -X -At -d "$db" -c "select to_regclass('public.staff_leave_types') is not null")"
  if [[ "$created" != "f" ]]; then
    echo "FAIL: leave tables were created despite failed preflight ($suffix)" >&2
    exit 1
  fi
  echo "PASS: $suffix preflight fails closed with expected diagnostic and no leave tables"
}

expect_preflight_failure \
  "missing_profiles" \
  "" \
  "staff_leave_schema_preflight_failed: public.profiles table is missing"

expect_preflight_failure \
  "missing_is_active" \
  "create table public.profiles (id uuid primary key)" \
  "staff_leave_schema_preflight_failed: public.profiles.is_active is missing"

expect_preflight_failure \
  "wrong_is_active_type" \
  "create table public.profiles (id uuid primary key, is_active text)" \
  "staff_leave_schema_preflight_failed: public.profiles.is_active must be boolean (found text)"

echo "All leave schema preflight negative tests passed."
