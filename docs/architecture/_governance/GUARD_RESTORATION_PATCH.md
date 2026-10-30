# Guard Restoration — remove the one-time Scheme-B exception

> ## STATUS: APPLIED — 2026-08-26. The Scheme-B exception is RETIRED.
>
> The production ledger repair completed and was verified (ledger = 84 rows, set
> md5 `13e1f0fe5892c370fc21bd205fae7dc4`, 1:1 with the repository; backup table
> `supabase_migrations.schema_migrations_pre_schemeB` intact at 79 rows). This
> patch was then applied to `.github/workflows/migrations-guard.yml`:
> `ALLOWED_RENAMES`, the allowlist-aware deletion loop, and the
> `rename_targets` exclusion are all gone. **Historical renames are forbidden
> again with no standing exception.**
>
> Changes made beyond the prepared patch, all fixes rather than exceptions.
> Items 3–5 were found by adversarial review of the first attempt at this PR and
> are recorded because each was a real defect, not a hypothetical:
> 1. The workflow-level `paths:` filter was removed and replaced by in-job
>    change detection, so the check reports on every PR instead of vanishing on
>    unrelated ones (it could not otherwise be a required status check).
> 2. A **fail-closed base guard**: an empty, non-commit, or non-ancestor base
>    fails the job instead of finding no diff and exiting 0 having verified
>    nothing.
> 3. **The base is taken from `HEAD^1`, not `github.event.pull_request.base.sha`.**
>    That value is pinned at PR creation and goes stale as `main` advances. Live
>    PRs #9 and #11 carried pre-normalization base SHAs; diffing against them
>    produced 48 phantom paths and 17 errors on a PR containing no SQL at all.
>    `git merge-base` does not help — `base.sha` is an ancestor of the merge
>    commit, so the merge-base *is* `base.sha`.
> 4. **`--diff-filter=MT`, not `M`.** Replacing a migration with a **symlink** is
>    a type change, invisible to `M`. The guard reported "no existing migration
>    was modified" and exited 0 while the file's SQL came from outside the
>    directory. CI does not compensate: the discovery proof counts files (a
>    symlink counts) and Gate-2 parity compares object *counts*, so a payload
>    that rewrites a function body or a policy passes both.
> 5. **A filename format gate.** Nothing previously validated version shape:
>    `071a_` (unparseable by the Supabase CLI — the exact class the normalization
>    removed), `71_` and `0999_` (either becomes the lexicographic maximum and
>    permanently blocks every later three-digit version) were all accepted.
>
> An earlier draft of this change also rewrote `ver()` to use `printf '%s'`
> without a newline, which collapsed every version onto one line and made the
> uniqueness and prefix checks pass on any input. Caught in testing; the helper
> now carries a comment explaining why the newline is load-bearing.
>
> This document is retained as the historical record of what the exception was
> and why it was safe. **Do not re-apply it.** A future normalization needs its
> own reviewed, time-boxed change.

**Apply immediately after the production ledger repair is verified.** Prepared in advance so restoring strict append-only enforcement is a mechanical, reviewed step rather than an afterthought.

## What to remove from `.github/workflows/migrations-guard.yml`
1. The whole block delimited by
   `# ONE-TIME SCHEME-B NORMALIZATION EXCEPTION — REMOVE AFTER LEDGER REPAIR`
   through the end of the `ALLOWED_RENAMES` string — i.e. the `ALLOWED_RENAMES`
   variable and its banner comment.
2. In the immutability check, replace the allowlist-aware deletion loop with an
   unconditional failure on any deletion:
   ```
   del="$(git diff --no-renames --diff-filter=D --name-only "$BASE_SHA" HEAD -- "$DIR" || true)"
   if [ -n "$del" ]; then
     echo "::error::Existing migration files were deleted or renamed. Migrations are append-only."
     echo "$del" | sed 's/^/  - /'
     fail=1
   fi
   ```
3. Remove the `rename_targets` exclusion from the `added_files` computation
   (there will be no allowlisted renames left to exclude).

## What to KEEP (these are fixes, not exceptions)
- The **prefix-freeness check** on newly added migrations. This enforces the invariant the whole
  normalization exists to create; without it a future `0700_x.sql` would silently re-introduce the
  tool-dependent ordering that Scheme B removed. **Removing the exception must not remove this.**
- ~~The **blob-hash** based immutability comparison with `--no-renames`. This is
  strictly stronger than the original `--diff-filter=MDR` check, which a
  rename-plus-edit could evade via git's `R98` rename heuristic.~~

  **CORRECTED AT APPLICATION TIME.** This instruction was not followable as
  written, and its justification was wrong. The blob-hash comparison lived
  *inside* the allowlist loop being deleted — it existed to prove an allowlisted
  rename was content-identical, so removing the exception necessarily removed it.
  And `--diff-filter=MDR` does catch a rename-plus-edit (measured: git reports
  `R099` and the `R` filter matches); the claim of being "strictly stronger" was
  not true.

  What the restored guard actually does: rename detection is disabled, so a
  rename appears as delete + add and is caught by the **deletion** check, and
  modification uses **`--diff-filter=MT`**. The `T` is the part that matters and
  that nothing previously covered — replacing a `.sql` file with a **symlink**
  is a type change, invisible to a plain `M` filter.
- The `if [ … ]; then echo; fi` form in the `basemax` subshell. The original
  `[ … ] && echo` made the loop exit non-zero under `set -euo pipefail`,
  aborting the whole step and false-failing **every** newly added `NNN_`
  migration — it would have blocked `071`.

## Verification after restoration
Re-run the guard test matrix. Expected afterwards:
| Case | Expected |
|---|---|
| Any historical rename (incl. the former Scheme-B pairs) | **FAIL** |
| Historical deletion | **FAIL** |
| Historical content modification | **FAIL** |
| Normal new migration `076_` (the next free number) | **PASS** |
| Back-dated new migration | **FAIL** |
| Duplicate version prefix | **FAIL** |

Once merged, historical migration renames are forbidden again with no standing exception.
