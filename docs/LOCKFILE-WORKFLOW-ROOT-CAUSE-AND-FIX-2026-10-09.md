# Lockfile Workflow Root Cause and Fix — 2026-10-09

## Confirmed root cause

Review of commit `5a2e5e0e8b4e0261a6a52ce68b3394ddcfea1b32` and its changed-file list shows that the commit only added `.github/workflows/commit-lockfile.yml`; it did not add `package-lock.json`.

The workflow used:

```sh
if git diff --quiet -- package-lock.json; then
  echo "Lockfile is already current."
  exit 0
fi
```

Git's `git diff` does not include an untracked file by default. Thus a newly generated, untracked `package-lock.json` can be mistaken for an unchanged lockfile and skipped. This matches the observed green workflow run while the branch tree still had no lockfile.

## Change made on the existing safety PR branch

Updated `.github/workflows/commit-lockfile.yml` on the existing branch `safety/ci-build-config-validation`, without creating another branch:

- Skip only if `package-lock.json` is already tracked and unchanged.
- Otherwise configure the bot identity, stage the generated lockfile, commit, and push as before.

Workflow-change commit: `d52ab4e05e89a8bb6a52d45184374c11178f4d59`.

## Validation status at time of writing

- The lockfile workflow for the changed SHA was queued and then observed in progress.
- The PR CI workflow for the same SHA was queued and then observed in progress.
- At the latest check, `package-lock.json` was not yet present at the branch head. The fix is therefore **not yet confirmed successful**; the workflow must finish, the new file must be visible in the branch tree, and a subsequent CI run must pass `npm ci` against that committed file.
- The previous green CI result was for SHA `5a2e5e0e8b4e0261a6a52ce68b3394ddcfea1b32` and did not establish a committed lockfile.

## Safety boundary

This change is confined to the existing GitHub safety PR branch. No Production deployment was initiated; no Supabase project, schema, role, policy, or data was changed. No additional Supabase resource was created. Production release remains blocked until all independent database, authorization, file upload, backup/restore, and admin-survivability gates are verified.

## Follow-up after the workflow fix

- The corrected workflow completed successfully on SHA `d52ab4e05e89a8bb6a52d45184374c11178f4d59` and created commit `9c2990e35791f051e079b5db47f3b8a324d96570` with message `Add reproducible npm dependency lockfile [skip ci]`.
- The branch tree now confirms that `package-lock.json` exists. This closes the earlier missing-file finding.
- To ensure CI actually validates the committed lockfile, the workflow commit message was then changed to remove `[skip ci]`, so a future lockfile commit will trigger the PR CI. That workflow update is commit `19b66e2a3d023897cfc9fbb0bae259d9bea19694`.
- Latest observed PR CI run for that SHA: https://github.com/wbns-edoc/wbns-edoc.github.io/actions/runs/37949211277 — **in progress** at the latest check.
- Latest observed lockfile workflow run for that SHA: https://github.com/wbns-edoc/wbns-edoc.github.io/actions/runs/37949211246 — **in progress** at the latest check.
- Therefore: lockfile committed = **verified**; CI run on the exact head with committed lockfile = **pending**, not yet passed. The PR remains draft and unmerged.

## Final validation update

- The lockfile is confirmed in the Git tree for both `9c2990e35791f051e079b5db47f3b8a324d96570` and current PR head `19b66e2a3d023897cfc9fbb0bae259d9bea19694`; the lockfile-add commit records 1,980 lines added.
- Pull Request CI run `37949211277` for current head `19b66e2a3d023897cfc9fbb0bae259d9bea19694` completed successfully. The job step list confirms successful dependency installation, artifact upload, `npm ci`, build with non-production configuration, all six configuration-validation cases, and the missing-config negative test.
  https://github.com/wbns-edoc/wbns-edoc.github.io/actions/runs/37949211277
- The lockfile workflow run `37949211246` for the same head also completed successfully.
  https://github.com/wbns-edoc/wbns-edoc.github.io/actions/runs/37949211246
- The earlier absence finding is now resolved on the safety PR branch: the lockfile exists and CI passed on the current head containing it. The PR remains open, draft, and unmerged. No Production deployment or Supabase changes occurred.
