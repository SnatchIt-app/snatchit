# RC-20261012: the integrated release candidate (A, 2026-10-12)

**Status update (A, 2026-10-12 ~04:40Z): `48d20ca1` is NOT the shipping candidate.**
- C's read-only critical-flow audit of this code found consumer defects. A and C confirmed each against the source.
  - F4: the 3-D Secure return drops the checkout mode.
  - F5: payout-return claims "Connected" unconditionally.
  - F6: a race can show "Nothing was charged" after a charge.
  - F1–F3 and F7: a crash, two data losses and an auth dead end.
- Fixes are in progress. C authors F1–F5 and F7 on `v3/rc-fixes-20261012`; A authors F6 (gated `setupDecision.ts`)
  on `fix/rc-f6-settled-recheck-20261012`. All are test-first, with mutants.
- RC2 will be gate + S3 + S4 + v3 + those fixes, re-verified by the same checks. Everything below stays true of
  `48d20ca1` and is the baseline for RC2's delta.

**Status:** frozen 2026-10-12 04:19Z. CI is green, and every required gate check is green on the exact head.
Independent lanes are in progress. Nothing is merged, deployed or distributed. Every production step is the owner's
(`DEPLOYMENT_AND_ROLLBACK.md`).

## The candidate

| | |
|---|---|
| **Candidate** | `integration/rc-20261012` @ **`48d20ca1c0d0d53ce51c295c44447f3548496aa8`**, tree `7feadf07bd91186ae4139c614c31625fc9b5b445` |
| **Draft PR into the gate** | SnatchIt-app/snatchit#100 (draft; merging is the owner's step 1) |
| **Base** | gate `release/production-gate-20260918` @ `abef9506` (production backend source) |
| **Composition** (merge commits) | S3 `419bbe59` merges `admin/label-truth-conditions` `789025f3`; S4 `08409f55` merges `web/wording-truth-conditions` `e7130f04`; S5 `48d20ca1` merges `v3/midnight-app` `d27aa449` |

### Identities (A, `git diff`; B and E re-derived the app identity independently)

| Surface | Equal to | Files differing |
|---|---|---|
| `app/`, `src/` | `d27aa449`, the consumer tip B and E reviewed (app code = `9bbeaec6`) | 0 |
| Native-build inputs: `package*.json`, `app.json`, `app.config.*`, `eas.json`, `ios`, `android`, `plugins`, `assets`, babel/metro config, `scripts/patch-stripe-interop.mjs`, `native`, `tsconfig.json` | `d27aa449` | 0 |
| `supabase/` | gate `abef9506`: the 164 ledger files plus the unapplied 121/125/126 | 0 |
| `web/` | live web `feature/web-accounts-foundation` `0b389584` | 0 |
| `admin/` | live console `admin/operating-console` `f7e7e85f` | 0 |
| whole tree vs trial r3 `5450b348` | — | 14 (3 `admin/` from S3, 11 `web/` from S4) |

### Per-merge check (FINAL_INTEGRATION_PLAN §5.1)

| Merge | Branch files | Both-sided | Branch-file mismatches | Unexpected other changes | New blobs |
|---|---|---|---|---|---|
| S3 `419bbe59` | 3 | 0 | 0 | 0 | 0 |
| S4 `08409f55` | 11 | 0 | 0 | 0 | 0 |
| S5 `48d20ca1` | 364 at merge-base `131017a5` (367 at `19b6fc2b`) | 3 at `131017a5` (11 at `19b6fc2b`; 0 when counted by side-exclusive commits) | 0 | 0 | 0 |

- S5's both-sided files are the known criss-cross escrow files: `holdState.ts`, `CheckoutNative.tsx` and
  `checkout-escrow-note-unknown.test.ts`.
- They resolve to v3's version. The gate-side commits `bbd3e1bf`, `9eebcac2` and `19b6fc2b` are ancestors of
  `d27aa449`.

## Release scope

| Surface | Commit | In this release |
|---|---|---|
| Backend (database, edge functions) | `abef9506` | **nothing new**: no migration, function deploy or setting |
| Consumer iOS app | `48d20ca1` | **new build**: G2 EAS production build → TestFlight → submission |
| Web | `0b389584` | nothing (identical) |
| Console | `f7e7e85f` | nothing (identical) |
| Venue dashboard v2 | `venue/dashboard-v2` `549e0335` | **not in this release.** Local preview only; it carries the unapplied `20260910120000_venue_api_read_views` |
| Admin dashboard v2 | `admin/dashboard-v2` `4ef76958` | **not in this release.** Local preview only; replacing the console UI is a separate decision |
| 153 detector logging | `fix/153-detect-refunds-state-on` `ce95e503` | **parked**; no release dependency |
| 152 blocking | — | an owner decision; A recommends not in this release (below) |

## Checks at `48d20ca1` (A)

| Check | Result | Evidence |
|---|---|---|
| CI | **green**: 5/5 jobs, all 68 steps `success` (no skipped step) | run 38203105234, head `48d20ca1` |
| ↳ unit / parity / web / admin | 182 files, 3,084 tests / 3 files, 108 tests / 13 files, 218 tests / 16 files, 117 tests | same run |
| ↳ pgTAP | 98 files / 5,605 tests, `Result: PASS`; equal to the predicted count, because `supabase/` is unchanged from r3 | same run |
| Gate PR-only check "Immutability + ordering" | **pass** | run 38203637726 on PR #100, head `48d20ca1` |
| "Supabase Preview" | `skipping` | PR #100: the integration did nothing |
| **Local LC_ALL=C replay** (`scripts/local/replay.sh`) of the 164 ledger files (unapplied 121/125/126 removed) | `REPLAY OK: 164` in 20 s | `out/replay_run.txt`, `out/replay_fingerprint_diff.txt` |
| ↳ catalog vs the ledger-164 rehearsal DB `pkg151_rehears` (functions with body md5, secdef, config and ACL; columns; relations with RLS and ACL; policies; triggers; indexes; views) | 2,909 objects identical. The 28 extra lines in the rehearsal DB are all harness objects (stand-in ledger, pgTAP helpers); only-in-replay 0 | `fingerprint.sql`, `out/replay_fingerprint_diff.txt` |
| ↳ positive control | 153 applied to a clone changes exactly one line (`ops.detect_refunds()` md5) | same file |
| ↳ tie to production | the 6 functions 150/151 changed match `150_151_20261005/expected/post151.txt`, which production's X3 read-back matched on 2026-10-08: 6/6 | same file |
| **C4 static client-read check** | 63 `.from()` chains and 25 `.rpc()` calls, **MISSING 0**. The 16 UNRESOLVED sites are identical to those resolved by hand at `9bbeaec6`. Identical output against `pkg151_rehears` and against the candidate's own replay | `out/c4_run_48d20ca1.txt`; tool and mutants in `../S5_candidate_20261011/` |
| Local stage runner | self-test PASS (continue after failure, overall fail, exit inside a stage). On the candidate: `env-pairing` PASS; `deno` FAIL (deno not installed here; the runner fails instead of skipping) | `run_stages.sh` |

**The CI masking rule.** CI's quality job runs its steps in sequence. At `48d20ca1` nothing failed, so nothing was
masked: all 68 steps executed. If a later change turns CI red, `run_stages.sh` runs every remaining independent stage
locally and keeps the overall result failed. The `ci.yml` change itself stays parked.

## Lanes (independent of A)

| Lane | Owner | State at writing |
|---|---|---|
| Fresh-install native build of `48d20ca1`: sandbox env, Release configuration, log with exit status, binary sha256, env-pairing grep with positive control, cold launch | C | assigned 04:22Z |
| Consumer regression review of the source; review of C's build as commit + log + binary | B | in progress; the source review carries over (app diff 0, B's own diff) |
| Independent C4 at `48d20ca1`, candidate safety, deployment-plan and migration-scope review, verdict | D | in progress |
| Acceptance matrix keyed to `48d20ca1` | E | in progress; no genuine failures open |
| Dashboards v2 completion as previews | F | in progress; not in this release |

## Migration 152 (blocking): A's recommendation, for the owner's decision

**Recommend: not in this release.** Ship the current hide-only behaviour with its existing, truthful confirmation:
"Their listings will be hidden from your feed. You can unblock anytime in Settings → Blocked users." Then make 152
(BLOCKING_SCOPE_RECOMMENDATION_20260924 §2a–2d; not §2e) the first follow-up release.

- **Why:**
  - 152 is a new migration, which is outside this sprint's authorisation.
  - It also brings C's client half, D's review, a sandbox rehearsal, an apply before distribution, a C4 rerun, a
    native rebuild and full acceptance of the new blocking states.
  - Nothing in the candidate depends on it.
- **Consequences of not shipping it now:**
  - A blocked person can still see, bid on, buy from and report the blocker. The block hides only that seller's
    listings and profile from the blocker.
  - App Review may judge a "Block user" control against Guideline 1.2. Apple decides compliance.
- **If the owner says yes:**
  - New-migration authority is needed.
  - Then: 152 (timestamp-named) and pgTAP 219 (A); the client half (C); D's PASS; sandbox rehearsal; XB1 applied
    **before** distribution; the §5.3 checks rerun.
  - Distribution waits for all of that.
