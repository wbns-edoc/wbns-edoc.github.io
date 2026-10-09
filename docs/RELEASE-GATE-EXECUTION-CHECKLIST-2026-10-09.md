# Release Gate Execution Checklist — 2026-10-09

## Purpose

Track the remaining work required before the electronic records system for Wat Bueng Nam Sai School can be considered production-ready. This is a release checklist, not a declaration that the system has passed.

## Current confirmed blockers

1. **Migration provenance mismatch** — 21 repository SQL migration files versus 26 recorded Production migration entries. Names differ; exact SQL/provenance must be reconciled before any migration is deployed.
2. **Upload workflow split across trust boundaries** — `drive-upload` creates the Drive binary, while the browser then inserts metadata and calls `attach_document_file_version`. The live RLS inventory has no INSERT policy for `google_drive_files` or `document_files`.
3. **Incomplete object-level authorization review** — `attach_document_file_version` checks `document.update` and row existence but does not visibly enforce the full document/department scope. Its EXECUTE grant is present for `authenticated`.
4. **Admin lockout protection not established** — `admin_remove_user_role` function body does not visibly protect against removing the last system administrator or self-removal. Do not test this against the sole Production admin.
5. **CI reproducibility gap** — `package.json` defines only `dev`, `build`, and `preview`; no package lockfile was found at the repository root on the reviewed branch. CI should not rely on an unpinned install.
6. **Security Advisor warnings remain** — 10 SECURITY DEFINER execution warnings and leaked-password-protection warning were reported in the prior review. Each function must be assessed individually; no blanket revocation is approved.
7. **Operational recovery unproven** — backup restore, upload cleanup, and end-to-end authorization tests have not been demonstrated in an isolated environment.

## Safe implementation sequence

### Gate A — Source and migration integrity
- Export/record exact live migration history and compare each entry to repository SQL and checksums/provenance.
- Identify missing, renamed, consolidated, or manually applied migrations.
- Do not deploy until every difference has an explained, reviewed disposition.
- Add reproducible dependency lockfile and CI checks in a non-production branch.

### Gate B — Upload transaction and access control
- Define document/department access rules for upload, metadata creation, attachment, download, replacement, and deletion.
- Implement a server-side orchestration flow that validates the caller and target document before accepting the file.
- Keep service-role credentials server-side only. If used, restrict the privileged code path and independently validate every caller-controlled identifier.
- Persist metadata and attach the version in a controlled flow. If later steps fail, compensate by deleting the newly created Drive object and any metadata that is safe to roll back.
- Make requests idempotent to prevent duplicate binaries and versions on retry.
- Enforce a file-type allowlist, byte limit, and appropriate content validation; never trust the client-supplied MIME type alone.
- Avoid broad INSERT policies as a workaround.

### Gate C — Admin survivability and SECURITY DEFINER review
- Inventory all role mutation paths, triggers, RPCs, direct table grants, and admin bootstrap logic.
- Add and test protection for the last active system administrator, self-removal, and concurrent role changes.
- Keep the current Production System Admin unchanged during testing.
- Review each SECURITY DEFINER function's caller validation, fixed search_path, row scope, and EXECUTE grants individually.
- Resolve the leaked-password-protection warning through a separately reviewed Auth configuration change after testing.

### Gate D — Automated validation
- Pin dependencies with a committed lockfile.
- CI should run dependency installation from the lockfile, TypeScript/build checks, SQL/static checks, and authorization/integration tests on pull requests.
- Add tests for: anonymous and unauthorized calls; allowed and denied document scopes; inactive users; invalid/oversized file types; missing metadata; attachment failure; duplicate retries; Drive cleanup success/failure; last-admin/self-removal; and concurrent role mutations.
- Do not claim a test passed unless CI or a controlled test environment actually ran it and its output was reviewed.

### Gate E — Recovery and release approval
- Demonstrate a recoverable database backup and a successful restore drill.
- Document Drive retention/deletion behavior, audit logging, secret rotation, and incident response.
- Obtain owner approval of the release candidate, migration plan, backup evidence, test results, and rollback plan.
- Deploy only through a reviewed release path after all prior gates pass.

## Environment and cost guardrails

- Keep the school deployment logically and operationally isolated from other schools.
- Maintain the explicit project cost target of 0 THB/month.
- Do not create a Supabase branch until the exact branch cost has been retrieved, communicated, and explicitly approved by the owner.
- Never expose service-role credentials in browser code or any `VITE_*` variable.
- No Production changes are authorized by this checklist.

## Evidence status

| Item | Status |
|---|---|
| Read-only source and live catalog review | Performed for the issues described in linked review notes |
| Actual upload integration test | Not run |
| Migration reconciliation | Not complete |
| Last-admin protection test | Not run; Production admin was not changed |
| CI workflow / dependency lockfile | Not implemented |
| Backup restore drill | Not demonstrated |
| Production release approval | Not granted |
