# Guard Restoration — remove the one-time Scheme-B exception

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
- The **blob-hash** based immutability comparison with `--no-renames`. This is
  strictly stronger than the original `--diff-filter=MDR` check, which a
  rename-plus-edit could evade via git's `R98` rename heuristic.
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
| Normal new migration `071_` | **PASS** |
| Back-dated new migration | **FAIL** |
| Duplicate version prefix | **FAIL** |

Once merged, historical migration renames are forbidden again with no standing exception.
