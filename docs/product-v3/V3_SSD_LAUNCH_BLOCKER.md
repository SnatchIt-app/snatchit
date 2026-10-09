# The dev-server gate still points at the Mac original — device work is blocked on the SSD

Recorded 9 October 2026 by C, during the first post-migration capture window.
**No capture was taken. No frame from this window exists, and none should be invented later.**

## What happened

`857e6d93` (the P-1 / P-2 trust-panel fix) was committed and served, and the window opened.
Starting Metro through the project's own launch configuration fails:

```
$ bash -lc "cd /Volumes/DEV-SSD/01_SNATCH_IT/repos/snatchit-refund \
    && ./scripts/dev-web-guard.sh && exec npx expo start --port 8081"

  REFUSED — working directory is /Volumes/DEV-SSD/01_SNATCH_IT/repos/snatchit-refund,
            not /Users/josetascon/snatchit-refund
```

`scripts/dev-web-guard.sh` pins two checks to the pre-migration path — `$PWD` and
`git rev-parse --show-toplevel` — against `WORKTREE='/Users/josetascon/snatchit-refund'`.
The migration updated `.claude/launch.json` (recorded in `runtime-path-changes.json`) but not
this script, which the launch configurations invoke before Metro on every start.

## The configuration itself is fine — only the path pin is stale

Probed with a COPY of the script in a scratch folder, with only `WORKTREE` repointed. The
repository's own copy was not modified (`git status scripts/` is empty):

```
  dev-web-guard OK  dir=/Volumes/DEV-SSD/01_SNATCH_IT/repos/snatchit-refund
                    host=https://ofaidukbieeekqaboscm.supabase.co
                    app_env=sandbox  stripe=pk_test_51T…
```

Every substantive check passes on the SSD: the sandbox Supabase host, `app_env=sandbox`, a
`pk_test_` key belonging to the sandbox Stripe account, an anon key whose own ref is the sandbox
project, no stray `.env` / `.env.development`, and nothing conflicting exported in the
environment. **The SSD copy is correctly configured; the gate simply names the old folder.**

## Why C did not fix it

The guard exists to make "the wrong directory and the wrong configuration impossible to launch"
after a near-miss where Metro was started twice from a checkout whose env named PRODUCTION. It is
a safety control, and repointing it is a path change — both things this session was told not to do
on its own after the migration. One line is all it needs, and the probe above shows the result,
but it is Codex's call and the owner's, not C's.

## Second finding — a dev server started outside the gate

`preview_start` ("snatchit", port 8081) produced a Metro that ran for four minutes and bundled,
then died: repeated WEB bundles of `expo-router/entry.js` at roughly 200 s each until Node hit
`FATAL ERROR: CALL_AND_RETRY_LAST Allocation failed - JavaScript heap out of memory` (exit 134).
The configured command for that entry cannot produce a running server from this directory — it is
the command quoted above, and it refuses. So the server came up without the guard having passed.

Nothing in the Mac original was modified during that window (`find -newermt '-60 minutes'` over
the old tree is empty), so this was not a silent fallback to the retained originals — but a dev
server starting outside the gate is worth closing regardless of which tree it chose.

The repeated web bundling is its own trap: pointing a browser at Metro's port asks for the WEB
bundle, which is 1,684 modules here and is not what a simulator capture needs at all.

## State left behind

Serving tree `857e6d93`, clean apart from the documented `.claude/launch.json` change. No Metro
running, no simulator booted, port 8081 free. The fix is validated device-free — typecheck clean,
176 files / 2,998 tests, lint 0 errors — and remains **UNCAPTURED at A3XL in both appearances**,
which is what B asked for and what this window owed.
