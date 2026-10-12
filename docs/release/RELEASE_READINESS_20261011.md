# Release readiness: the single consolidated list (A, 2026-10-11)

**Superseded for the candidate's state by `packages/RC_20261012/README.md` (A, 2026-10-12):** the integrated
candidate `48d20ca1` and its checks.

**Status: closed for the storage closeout (A, 2026-10-11, late).** Development is frozen. This record holds the
latest results; the earlier red-CI reports are history. What is still open is in §1 and the release queue below.
Nothing in this record authorises a merge, deployment, distribution or production change.

**Sources.**
- Current origin tips, fetched 2026-10-11 at closeout (table below).
- E's `V3_ACCEPTANCE_RECORD.md` @ `c16c2d8f`, which records B's narrow pass (`92356c9e`), and B's
  `B_NATIVE_REVIEW_9bbeaec6.md`.
- C's v3 handoffs.
- F's `DASHBOARD_V2_HANDOFF.md` on `venue/dashboard-v2` @ `549e0335` and `admin/dashboard-v2` @ `4ef76958`.
- D's records.
- A's records and the checks A ran today.

**Read with these rules:**
- Settled wording and the waived sign-in checks are **not reopened**.
- Spoken VoiceOver is **optional, not a release blocker**.
- The merge to `main`, deployment and app distribution each remain separately gated.

## Tips

| ref | sha | state |
|---|---|---|
| `release/production-gate-20260918` | `abef9506` | Production backend source: 150/151 applied, ledger 164, stripe-webhook v43, enforce-transfer-expiry v42 |
| `feature/web-accounts-foundation` | `0b389584` | Live on `snatchti.com` as `dpl_9n8Jps9W…` |
| `admin/operating-console` | `f7e7e85f` | Live as `dpl_8xPaaBYG…`; the pin is unchanged |
| `v3/midnight-app` | `d27aa449` | The v3 candidate. Its `app/` and `src/` are identical to `9bbeaec6`, the tip B and E reviewed. It adds C's ML7 test fix (`10dbcdf4`), the four default-size Settings frames (C-operated captures, re-diffed by E and reviewed by B: `32c0804a`, `11e50ca0`) and the parity alias fix (`d27aa449`). **v3's own CI is green** (run 38162136552). It contains `v3/consumer-batch2` `6b6b8f48` |
| `integration/s5-trial-20261011-r3` | `5450b348` | A's trial merge of the gate and v3 `d27aa449`, test only. **CI GREEN** (run 38162239127): 182 unit files / 3,084 tests, parity 108 tests, pgTAP 98 files / 5,605 tests |
| `integration/s5-trial-20261011` / `-r2` | `9ed130d5` / `4f162c24` | Earlier trials, red on ML7 (r1) and then on the parity load error (r2). Superseded by r3; kept as record |
| `fix/153-detect-refunds-state-on` | `ce95e503` | Migration 153 (`20261011000000`). CI green (run 38160107004). **Parked; not applied** |
| `release/candidate-20260918` | this commit | A's records |
| `design/frontend-audit-20260917` | `c16c2d8f` | B and E's record, with B's narrow pass. **E's local-only commits are now on origin** (`d9240daa` is an ancestor) |
| `review/d-records-20261005` | `1bca001c` | D's records, sanitised |
| `venue/dashboard-v2` / `admin/dashboard-v2` | `549e0335` / `4ef76958` | F's dashboard v2. "Not deployed, not merged to `main`" |
| `main` | `eadd456a` | 2026-09-01; S7 never authorised |

## 1. Release blockers still open

1. **The native build of the candidate from a fresh install (§5.3 item 4): OUTSTANDING.**
   - Every native result for v3 comes from a **simulator development build**. E's record says so: "Native
     development build only. Not whole-app acceptance."
   - A searched v3's and the audit branch's records. None shows a build of `d27aa449` (or `9bbeaec6`) from a fresh
     install with its build output.
   - It is **not inferred** from the simulator captures. A capture is not a build record.
   - Owner of the work: C/B. It waits for the development freeze to lift.
   - This is separate from G2 (the EAS production build). G2 is in the release queue.
2. **D's verification of C4 (§5.3 item 6): owed by D.** A's C4 passed (§5). D's independent check is still to come.

## 2. Owner-waived (not verified; do not re-ask)

- **Repeat signed-in sessions.** Recorded as owner-reported access. Waived checks:
  - web wording on `/account/purchases`, `/account/sales` and a transfer page;
  - the console labels from #98;
  - authenticated flows.
- **E's "untested by design":**
  - authenticated consumer Home;
  - the Edit refusal group;
  - the W-5 Edit platform picker (parity is test-pinned only);
  - the W-6 payout line in its connected state (source-pinned only; its wording is closed on source). **Not a pass.**
- **The 2026-10-08 console sign-in and TOTP** were confirmed from auth records (A, D). That covers access, not wording.

## 3. Unevidenced, not waived (D's class; not a blocker)

- **Refund-state detection has never been observed opening a case in production.**
  - The 16:35Z run after O-R4 scanned 2 and opened 0, the same as before; it is **not** evidence that detection
    works.
  - Only A's rehearsal positive control stands behind the mechanism.
  - The first real failed or pending refund is the natural witness. 153 would make each run's log name the case;
    it is parked.

## Release queue (separate; each step is the owner's, in order)

Not engineering work, and not started by A.
1. **Close §1:** the fresh-install native build of the candidate, and D's C4 check.
2. **Accept the v3 candidate `d27aa449`** on E's stated coverage. B's narrow review is in and passes, so nothing
   else in acceptance is open. Accepted: Home, Listing, Profile, the W batch, and W-4 and S-1/S-1b at default size.
   Screens outside that list are not accepted; the owner accepts on that coverage, or asks for more.
3. **D2: the 152 blocking scope** (`BLOCKING_SCOPE_RECOMMENDATION_20260924.md` §5). Is it in this release?
   - Today a block is only a one-way hide preference: "No server code reads `user_blocks`".
   - If yes: A writes 152 and C the client half, D verifies, and the §5.3 checks re-run (C4 included).
   - If no: ship as it is, with the truthful wording ("hide a seller's listings").
4. **S5:** merge `v3/midnight-app` into the gate.
5. **S7: gate → `main`.** It is migration-bearing. It needs:
   - PR-3 (a merge commit; MAIN_PROTECTION_PROPOSAL §2);
   - a fresh owner visual confirmation that Supabase auto-deploy is off (AUTODEPLOY-1).
6. **X11 / G2:** an EAS production build from the exact candidate sha, then TestFlight, then the owner's submission.

## Parked (not in the release; resume only on the owner's word)

- **Migration 153, detector logging** (F-DETECT-REFUNDS-UNOBSERVABLE-1).
  - Branch `fix/153-detect-refunds-state-on` @ `ce95e503`, on origin.
  - Local RED then GREEN 20/20. CI green: pgTAP 99 files / 5,625 tests.
  - The rollback restores 150's body exactly.
  - Not applied anywhere in production. D's review is not started.
- **CI step masking** (a `ci.yml` change, so a PR into the gate). The quality job runs its steps in sequence, so the
  first failure hides every later step. For 17 days the parity load error hid 11 APP_CONFIG assertions. Recommended:
  `if: ${{ !cancelled() }}` on each independent test step. A has not changed `ci.yml`.

## 4. Optional follow-ups (not release blockers)

- **Spoken VoiceOver:** optional.
- **The Badge 1.3× cap** (owner's call; E) and the dispute-branch tier word (a later batch; C).
- **L-2 launch method** (Codex).
- **A shared label/value-row test** (B and C).
- **Legal-text "10%" statements** (owner; E: "not a request from this review").
- **F-MODE-BOUNDARY-DUPLICATED-1:** one shared live-mode rule (hardening).
- **F-CONSOLE-SETTING-STALE-1** (D; UI).
- **The refund-resolution detector:** off by design until the classification console (`3dab1614`) ships.
- **The seller-fee zero default:** a product decision. The NULL path is impossible (F-PAYOUT-FEE-FAILOPEN-1,
  corrected); 0 live rows are affected.
- **D's observation:** 4 of the excluded five carry a `stripe_refund_id` with `amount_refunded_cents` NULL. It is
  pre-existing and untouched.
- **Dashboards v2 (F)** are a separate track, not part of the v3 app release.
  - "Not deployed, not merged to `main`."
  - The venue backend items B1–B11 (`venue_api` "applied nowhere") need the owner's authorisation before any start.
  - The demo access decision is the owner's.
- **Stale documents to retire, which conflict with newer records** (from A's read-only extraction of the B/C/E/F
  reports; A re-checked only E's current summary, not each item):
  - C's `V3_SSD_LAUNCH_BLOCKER.md` (L-1 was resolved at `b0d727ce`);
  - `V3_BATCH8_HANDOFF.md` "Unrated" marked "proposed" (it was decided as W-1);
  - E's top table (R-1–R-4 still shown as "Open") versus E's current summary;
  - F's `REMAINING_WORK.md` (2026-10-06, the demo branch).

## 5. Completed

- **Backend release, 2026-10-07/08:** 150 and 151 applied (ledger 164); stripe-webhook v43 and
  enforce-transfer-expiry v42; S1/S2 gate merges, with CI green.
- **Web #97 live; console #98 live** via the pin plus Redeploy; MM-1 rulesets in place.
- **Stripe live endpoint:** 13 events, refund events included. O-R2 (refund-state detection) enabled. O-R3 operator:
  the owner, daily.
- **O-R4 CLOSED, 2026-10-11. Do not rerun.** Both live historical refunds were reconciled from Stripe's live API,
  run once each on the owner's approved hashes (#6 `d7f31cf1…`, #7 `dca8cb00…`), and witnessed by D (`6b9da194`).
  The five test-mode payments are excluded and unchanged. The public-to-private evidence pointer map, and where
  the private side is kept, are in the package's `EXECUTION_20261011.md`.
- **F-WEBHOOK-LEDGER-GAP-1: complete (explained).** There has been no qualifying live activity since 2026-08-05
  23:39:41Z, and no rejection is evidenced. Stripe, the database and the app logs were compared. Residual: the
  platform's `account.updated` events from 08-06 to about 09-10 cannot be enumerated.
- **The seller-fee query: complete.** 0 affected rows.
- **CI green at the candidate (2026-10-11 18:06Z).**
  - v3 `d27aa449`: run 38162136552.
  - Combined trial r3 `5450b348` (the gate plus `d27aa449`): run 38162239127. Every step was confirmed to execute.
  - Two stacked failures were cleared by C, each fix in test or config only:
    - ML7, a timezone-dependent test (`10dbcdf4`). `soldOnLabel` stays in the device's zone; ML7b defends that.
    - The parity suite's load error (`d27aa449`, `packages/vitest.config.ts`).
  - A gap that existed, not only a bug fixed: the 11 APP_CONFIG parity assertions did not run from 2026-09-24 (v3
    only). No value drifted; all 108 pass at r3.
- **§5.3 items 1, 2, 3 and 5 (A, B, E).**
  - Item 1, changed-surface inventory: `app/` and `src/` identical to `9bbeaec6`.
  - Item 2, CI: green, as above.
  - Item 3, C4 static client-read check: PASS against the ledger-164 schema (63 chains, 25 RPCs, 0 missing; 5/5
    planted defects caught; 16 dynamic sites resolved by hand). It carries over to `d27aa449`, whose only changes
    since `9bbeaec6` are one test file and the vitest config.
  - Item 5, delta acceptance: **B's narrow review passes** (`92356c9e`, recorded by E at `c16c2d8f`). The four
    default-size frames are genuinely re-shot; there are 0 differing pixels below y = 440 px, and B's result matches
    E's independent re-diff. W-4 and S-1/S-1b pass at default size.
- **Branches and records:**
  - D's four branches are pushed (the records branch sanitised); the trial branch `s1-s2` is deleted (redundant).
  - The B/E audit branch is pushed through `c16c2d8f`, including E's formerly local-only record commits.
  - C's v3 branches are pushed.
- **v3 review (B and E agree, closed):** Home, Listing, Profile, the W batch at `9bbeaec6`; wording W-1 to W-6
  decided; L-1 guard path repaired.
