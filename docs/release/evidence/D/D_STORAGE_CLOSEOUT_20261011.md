# D — storage closeout

2026-10-11. Development, hardening, migrations, deployments and test sweeps frozen. Inventory and
preservation only. **No production reads, no corrections, no history rewrite, no prune/reset/clean,
no Mac deletion.**

## 1. SSD paths and branch tips — all five clean and in sync

Root `/Volumes/DEV-SSD/01_SNATCH_IT/repos/`. Drive UUID `6A74DBD6-ACDE-4D44-B19D-9057E671E510`.

| worktree | branch | tip | remote | modified | untracked |
|---|---|---|---|---|---|
| `snatchit-drecords` | `review/d-records-20261005` | `66e691c8ce18` | same | 0 | 0 |
| `snatchit-webword` | `web/wording-truth-conditions` | `e7130f046a62` | same | 0 | 0 |
| `snatchit-labelrel` | `admin/label-console-release` | `1058c8825b97` | same | 0 | 0 |
| `snatchit-integ` | `review/d-integ-94-95` | `486c954cd918` | same | 0 | 0 |
| `snatchit-labelff` | `admin/label-console-release-ff` | `efe03fca5a88` | same | 0 | 0 |

Shared object store: `/Volumes/DEV-SSD/01_SNATCH_IT/repos/snatchit/.git`.

## 2. Local-only refs — private, never pushed, deliberately retained

| ref | tip | holds |
|---|---|---|
| `review/d-records-PREREWRITE-BACKUP` | `f70ca9d9` | pre-first-redaction history, **real ARNs** |
| `review/d-records-PREREWRITE2-BACKUP` | `1046b78e` | pre-second-redaction history, **real ARNs** |
| `refs/original/refs/heads/review/d-records-20261005` | `d889ea57` | filter-branch leftover from the second rewrite |

All three confirmed absent from every remote. **`refs/original` has been left in place deliberately** —
removing it is a cleanup action that would make objects unreachable, and this prompt authorises
neither.

## 3. Uncommitted and ignored items

**Modified/staged: 0. Untracked: 0.** Across all five worktrees.

Ignored, excluding regenerable dependency and build directories: `docs/release/evidence/.DS_Store`,
`web/next-env.d.ts`, `admin/next-env.d.ts`, and three `tsconfig.tsbuildinfo`. **All regenerable; none
preserved and none unique.** The bulk ignored volume (~46k files across two worktrees) is
`node_modules` and build output.

**No ignored configuration of D's own exists** — no `.env*`, no harness config, no launch settings
authored by this session.

## 4. Preserved private evidence — the one thing that was genuinely at risk

**`/Volumes/DEV-SSD/01_SNATCH_IT/private-evidence/D-session-675d5134/`** (outside every git worktree,
verified: `not a git repository`).

| file | why it is unique |
|---|---|
| `proj.json` | Vercel project state **2026-10-07 23:38Z, pre-deployment** — that state no longer exists and cannot be re-read |
| `proj2.json` | after the failed redeploy attempt |
| `proj3.json` | after the successful deployment |
| `r1.out` / `r1.err` | raw Stripe CLI output proving the local CLI was bound to a different account |

These were **only** in the volatile session scratchpad under `/private/tmp`. The committed versions in
`captures_20261008/` are **whitelisted extracts**: verified just now that the raw `proj.json` carries
an `env` array and the committed extract does not. So the raw files hold material deliberately kept
out of the public repository — which is exactly why they go here and not there.

Reproducible and therefore **not** preserved: the `/tmp/*.sql` working copies of migrations and
scripts, all re-derivable from git blobs.

## 5. Owned processes

**This session started no server, watcher, build or capture process. Nothing of D's to stop.**

Running Chrome CDP instances on ports 9589, 9777 and 9788 are **2 to 16 days old**, predate this
session's work and belong to other sessions' browser harnesses. **Not stopped** — not D's to stop. No
PostgreSQL or shared service touched.

## 6. Processes still using an OLD MAC path — for the deletion owner

Two **live Claude Code sessions** hold working directories inside the Mac original:

| pid | cwd |
|---|---|
| `10789` | `/Users/josetascon/snatchit/.claude/worktrees/snatch-it-v3-audit-82536e` |
| `88598` | `/Users/josetascon/snatchit/.claude/worktrees/venue-demo-integration-70c9c6` |

Resolved with `lsof -d cwd`, not inferred from a command line. **Neither is D's and neither was
stopped.** Flagged because deleting the Mac root underneath a live session's working directory is a
hazard Codex should know about before acting.

## 7. Correction: what the redaction did and did not do

D previously wrote that the rewrite left "0 ARN commits on origin". **That claim is narrowed, as it
should be.**

**What D actually verified:** `78d9572a` is **not reachable** from
`origin/review/d-records-20261005`, and an ARN pickaxe over that ref returns **0**.

**What remains true, and D does not claim otherwise:**
- the commit object **still exists** in the SSD shared store, reachable from the two private backup
  refs and from `refs/original` — deliberately, as preservation;
- the retained **Mac copy does not** contain it — checked, not assumed (it is a post-migration commit);
- **D cannot verify what GitHub retains server-side.** A force-pushed commit commonly remains
  fetchable by sha until the remote garbage-collects, and D has neither visibility nor control over
  that. **No claim is made that the values were erased from GitHub** — only that they are not
  reachable from the branch ref D checked.

The old→new mapping is published in `D_RELEASE_HANDOFF_20261011.md` §0 and repeated here:
`78d9572a→99e5cdea`, `45fbe3dd→fefb83a9`, `62829249→f83c9bb9`, `1046b78e→6b9da194`.

## 8. Blocker

**None.** The only unique data at risk was the raw capture set in volatile `/tmp`; it is now preserved
on the encrypted SSD (§4). Nothing else of D's exists solely outside the SSD.

One **caution, not a blocker**: §6 — two live sessions hold cwd inside the Mac root.

## 9. Lane state at close

Historical reconciliation **done** and witnessed. The five test-mode payments remain **excluded and
not expanded**. Optional hardening (including migration 153) **not started** and frozen. Owner-waived
sign-in and wording checks **stay waived**. VoiceOver optional, not a blocker.
