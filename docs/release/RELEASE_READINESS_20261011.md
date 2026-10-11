# Release readiness: the single consolidated list (A, 2026-10-11)

**Sources.**
- Current origin tips, fetched 2026-10-11 ~17:50Z (table below).
- E's `V3_ACCEPTANCE_RECORD.md` @ `6f284925` ("the only current summary") and B's `B_NATIVE_REVIEW_9bbeaec6.md`.
- C's v3 handoffs.
- F's `DASHBOARD_V2_HANDOFF.md` on `venue/dashboard-v2` @ `549e0335` and `admin/dashboard-v2` @ `4ef76958`.
- D's records @ `66e691c8`.
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
| `v3/midnight-app` | `d27aa449` | The v3 candidate. Its `app/` and `src/` are identical to `9bbeaec6`, the tip B and E reviewed. It adds C's ML7 test fix (`10dbcdf4`), E's four frames (`32c0804a`, `11e50ca0`) and the parity alias fix (`d27aa449`). v3's own CI is green (run 38162136552). It contains `v3/consumer-batch2` `6b6b8f48` |
| `integration/s5-trial-20261011-r3` | `5450b348` | **A's trial merge of the gate and v3 `d27aa449`, test only. CI GREEN** (run 38162239127): 182 unit files / 3,084 tests, parity 108 tests, pgTAP 98 files / 5,605 tests |
| `integration/s5-trial-20261011` (-r2) | `9ed130d5` (`4f162c24`) | Earlier trials, red on ML7 (r1) and then on the parity load error (r2). Kept as record |
| `fix/153-detect-refunds-state-on` | `ce95e503` | Migration 153 (`20261011000000`), prepared and tested. CI green (run 38160107004, pgTAP 99 files / 5,625 tests PASS). **Not applied** |
| `release/candidate-20260918` | this commit | A's records |
| `design/frontend-audit-20260917` | `6f284925` | B and E's record, pushed |
| `review/d-records-20261005` | `66e691c8` | D's records, pushed and sanitised |
| `venue/dashboard-v2` / `admin/dashboard-v2` | `549e0335` / `4ef76958` | F's dashboard v2. "Not deployed, not merged to `main`" |
| `main` | `eadd456a` | 2026-09-01; S7 never authorised |

## 1. Release blockers (must close before the v3 app ships)

1. **RESOLVED (2026-10-11 18:06Z): v3 CI was red; it is now green at `d27aa449`.** It had two stacked failures:
   - `tests/v3-mylistings-bids-stage.test.ts` › ML7 expects "Sold Sat 17 Oct" for `2026-10-17T21:00-04:00`.
   - The UTC runner prints "Sold Sun 18 Oct".
   - It has failed on every `v3/midnight-app` push since at least 2026-10-07, including `9bbeaec6`
     (run 38028668549). 1 of 178 files.
   - It is not caused by the merge: the S5 trial fails identically.
   - **(a) ML7:** fixed by C in the test only (`10dbcdf4`). `soldOnLabel` deliberately stays in the device's zone;
     ML7b now defends that.
   - **(b) The parity suite never loaded:** `core/tests/domain-parity.test.ts` reported "Cannot find package
     '@/src/lib/money'".
     - It had been hidden behind ML7, and it had failed since 2026-09-24, when `90235b74` (v3 only; not on the gate)
       made `src/config/app.ts` import through the `@/` alias, which `packages/vitest.config.ts` never declared.
     - Fixed by C in `d27aa449`, in the config only.
   - **A gap that existed, not only a bug fixed.** For 17 days the 11 APP_CONFIG parity assertions did not execute,
     while the job reported its first failure instead.
     - Those assertions cover `BUYER_FEE_RATE`, `SELLER_FEE_RATE`, and `STRIPE_PUBLISHABLE_KEY` as the only intended
       omission.
     - No value had drifted: all 108 pass at r3.
     - C's negative control: a non-money key mutated kills exactly that test.
   - Trial r3 (`5450b348`) is green on every step.
2. **E's one open evidence item: captured; B's review owed.** C pushed the four frames (`32c0804a`, labelled `11e50ca0`).
   B's narrow review is owed. B cannot receive messages, so E's acceptance record is the channel.
   - Four fresh default-size frames at `9bbeaec6`: `settings-hub-default-{light,dark}` and
     `appearance-default-{light,dark}`. C has the simulator window.
   - Then B reviews those four frames only.
   - E: "Open: one evidence item"; it is the only open line in E's current summary.
3. **The rest of the §5.3 combined-candidate verification** (`packages/S5_candidate_20261011/README.md`):
   - Item 1, changed-surface inventory: **done (A).** `app/` and `src/` are identical to `9bbeaec6`.
   - Item 2, CI green: **DONE.** Trial r3 `5450b348` (run 38162239127); every step was confirmed to execute.
   - Item 3, C4 static client-read check: **PASS (A)**, against the ledger-164 schema.
     - 63 chains and 25 RPCs, 0 missing; 5/5 planted defects caught; 16 dynamic sites resolved by hand.
     - D verifies (item 6).
   - Item 4, native build of the candidate from a fresh install: **owed (C/B).**
   - Item 5, delta acceptance: covered by #2, plus whatever the ML7 fix touches.
4. **Owner approvals on the path** (these are approvals, not engineering defects):
   - **The owner's acceptance of the v3 candidate.** E states its scope: "Native development build only. Not
     whole-app acceptance". Accepted: Home, Listing, Profile and the W batch. Screens outside that list are not
     accepted at `9bbeaec6`; the owner accepts the candidate on that coverage, or asks for more.
   - **S5:** merge `v3/midnight-app` into the gate.
   - **D2: the 152 blocking scope** (`BLOCKING_SCOPE_RECOMMENDATION_20260924.md` §5). Decide whether it is in this
     release. Today a block is only a one-way hide preference: "No server code reads `user_blocks`".
     - If yes: A writes 152 and C the client half, D verifies, and the §5.3 checks re-run (C4 included).
     - If no: ship as it is, with the truthful wording ("hide a seller's listings").
   - **S7: gate → `main`.**
     - It needs PR-3 (a merge commit, MAIN_PROTECTION_PROPOSAL §2) and a fresh owner visual confirmation that
       Supabase auto-deploy is off (AUTODEPLOY-1). It is migration-bearing.
     - 153, if approved by then, rides with it or applies separately.
   - **X11 / G2:** an EAS production build from the exact candidate sha, then TestFlight, then the owner's submission.

## 2. Owner-waived (not verified; do not re-ask)

- **Repeat signed-in sessions.** Recorded as owner-reported access. Waived checks:
  - web wording on `/account/purchases`, `/account/sales` and a transfer page;
  - the console labels from #98;
  - authenticated flows.
- **E's "untested by design":**
  - authenticated consumer Home;
  - the Edit refusal group;
  - the W-5 Edit platform picker (parity is test-pinned only);
  - the W-6 payout line in its connected state (source-pinned only).
- **The 2026-10-08 console sign-in and TOTP** were confirmed from auth records (A, D). That covers access, not wording.

## 3. Unevidenced, not waived (D's class; not a blocker)

- **Refund-state detection has never been observed opening a case in production.**
  - The 16:35Z run after O-R4 scanned 2 and opened 0, the same as before; it is **not** evidence that detection
    works.
  - Only A's rehearsal positive control stands behind the mechanism.
  - The first real failed or pending refund is the natural witness. 153, once applied, makes every tick's run log
    show which case it was.

## 4. Optional follow-ups (not release blockers)

- **CI step masking (A's recommendation; a `ci.yml` change, so a PR into the gate, owner-gated).** The quality job's
  steps run in sequence, so the first failure hides every later step. Twice in a row ML7 hid the parity suite, and the
  parity load error hid 11 assertions; "red on one test" therefore never meant one thing was wrong. Recommended: run
  each independent test step with `if: ${{ !cancelled() }}`, so that every step reports and the job still fails on any
  of them. A has not changed `ci.yml`.
- **Migration 153** (F-DETECT-REFUNDS-UNOBSERVABLE-1). Prepared; CI green; rollback restores 150's body exactly.
  Applying it to production is owner-gated; D reviews the branch.
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
- **O-R4 CLOSED, 2026-10-11.** Both live historical refunds were reconciled from Stripe's live API, run on the owner's
  approved hashes, and witnessed by D (`6b9da194`). The five test-mode payments are excluded and unchanged.
- **F-WEBHOOK-LEDGER-GAP-1: explained.** There has been no qualifying live activity since 2026-08-05 23:39:41Z, and
  no rejection is evidenced. Stripe, the database and the app logs were compared.
- **The seller-fee query:** 0 affected rows.
- **Branches and records:**
  - D's four branches are pushed (the records branch sanitised); the trial branch `s1-s2` is deleted (redundant).
  - The B/E audit branch is pushed; C's v3 branches are pushed.
- **v3 review (B and E agree, closed):** Home, Listing, Profile, the W batch at `9bbeaec6`; wording W-1 to W-6
  decided; L-1 guard path repaired.

## Concrete remaining approvals, in order

1. *(after B's review of the four frames; CI is now green)* **Accept the v3 candidate `d27aa449`** on E's stated coverage.
2. **D2:** is the 152 blocking scope in this release, yes or no?
3. **S5:** merge `v3/midnight-app` into the gate.
4. **S7:** gate → `main`, with PR-3 and a fresh auto-deploy-off confirmation.
5. **X11 / G2:** an EAS production build from the exact candidate sha, then TestFlight, then submission.
6. *(independent, optional)* **Apply 153** to production after D's review.
