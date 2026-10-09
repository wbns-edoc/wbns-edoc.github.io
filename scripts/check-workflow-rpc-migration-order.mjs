#!/usr/bin/env node
/**
 * Static regression guard for public workflow RPC migration ordering.
 * This does not replace PostgreSQL catalog/integration tests.
 */
import { readdir, readFile } from "node:fs/promises";
import { join } from "node:path";

const migrationDir = "supabase/migrations";
const protectedFunctions = [
  "assign_document",
  "update_document_status",
  "set_document_deadline",
  "create_approval",
  "decide_approval",
];
const definitions = new Map(protectedFunctions.map((name) => [name, []]));
const files = (await readdir(migrationDir))
  .filter((name) => name.endsWith(".sql"))
  .sort();

for (const file of files) {
  const sql = await readFile(join(migrationDir, file), "utf8");
  const pattern = /create\s+(?:or\s+replace\s+)?function\s+public\.([a-z_]+)\s*\(/gi;
  for (const match of sql.matchAll(pattern)) {
    const name = match[1].toLowerCase();
    if (!definitions.has(name)) continue;

    const start = match.index;
    const marker = sql.toLowerCase().indexOf("as $$", start);
    if (marker < 0) {
      console.error(`Cannot determine function header end: ${file}: public.${name}`);
      process.exitCode = 1;
      continue;
    }

    const header = sql.slice(start, marker);
    const mode = /\bsecurity\s+definer\b/i.test(header)
      ? "DEFINER"
      : "INVOKER"; // PostgreSQL's default when SECURITY is omitted.
    definitions.get(name).push({ file, mode });
  }
}

let failed = false;
for (const name of protectedFunctions) {
  const history = definitions.get(name);
  if (history.length === 0) {
    console.error(`FAIL: no version-controlled definition found for public.${name}`);
    failed = true;
    continue;
  }
  const latest = history[history.length - 1];
  if (latest.mode !== "INVOKER") {
    console.error(`FAIL: latest public.${name} definition is SECURITY DEFINER in ${latest.file}`);
    failed = true;
  } else {
    console.log(`PASS: latest public.${name} definition is SECURITY INVOKER/default INVOKER (${latest.file})`);
  }
}

if (failed) {
  console.error("Public workflow RPC migration-order regression detected. Do not deploy until corrected and verified with database tests.");
  process.exit(1);
}
