# RC-20261012: the integrated release candidate (A, 2026-10-12)

## RC2 FROZEN: `e2b9498b` is the release candidate (A, 2026-10-13 ~00:10Z; all five lanes closed ~04:00Z)

**The release decision, the owner action list and the release boundaries are in `RELEASE_DECISION_PACKAGE.md`.**

| | |
|---|---|
| **RC2** | `integration/rc-20261012` @ **`e2b9498b71191d308a33d00bce87a0832acc8d55`**, tree `3e9813751a248ee892be37a6d7a258db4628361e`; draft PR #100 head |
| **Composition** | `48d20ca1` (RC1) → `53a16239` (C `287e938b`) → `d2651782` (A F6 `084de270` ⊃ `50e74efb`) → `e2b9498b` (C `caa3fa03`). The tree equals the clean composition `48d20ca1` + `caa3fa03` + `084de270` |
| **Not candidates** | `48d20ca1` (F1–F7, B-D7) and `d2651782` (B-D10: the winner checkout pushed mode 'bid', so every auction winner was stranded) |
| **Changes vs RC1** | 41 files: `app/` 4, `src/` 11, `tests/` 26. Gated client surface: `setupDecision.ts` only (F6). `supabase/`, `.github/`, `web/`, `admin/` and the native-build inputs are unchanged |

**Checks and reviews at `e2b9498b`:**

| Check / lane | Result | Evidence |
|---|---|---|
| CI | **5/5 jobs, 68/68 steps success**. Unit 188 files / 3,151 tests; parity 3 / 108; web 13 / 218; admin 16 / 117; pgTAP 98 / 5,605 `Result: PASS` | run 38319986862, push, head `e2b9498b` |
| Gate PR #100 | all 6 required checks green; Immutability + ordering (run 38319995006); "Supabase Preview" skipping; CLEAN; draft | PR #100 |
| A: integration | `rc_verify.sh` PASS (0 mismatches, unexpected changes or new blobs at all three merges; fixed surfaces identical, with controls); local stages PASS; C4 MISSING 0, the same 16 sites | this package |
| C: fresh-install Release build | **BUILD EXIT 0** at exactly `e2b9498b`. Embedded Hermes bundle; sandbox pairing PASS at value level; fresh install; Light + Dark cold launches reach Sign in (SANDBOX). Attempt 1 failed on CocoaPods' UTF-8 locale check (environment: no LANG in the shell); attempt 2 is the record, and both logs are kept | private evidence on the SSD; C-HANDOFF 23:31Z |
| B: consumer review on C's binary | **PASS, no blocker.** 15 mutants with exact kills; F1–F7, D-RC-4, B-D9, B-D10, guard pins and strings. **B-D7 meets the agreed criterion:** 0 money pixels past the edge at A3XL on Bids, Checkout, PlaceBid and Order, Light and Dark; default pixel-identical to RC1 where comparable. Listing captured with `screen=listing` | `design/frontend-audit-20260917` @ `967c29e6`, `B_RC2_VERDICT_e2b9498b.md` |
| D: source/schema contracts | **No blocking defect.** Identity blob by blob; C4 PASS on both roots (63/25/0/16; 30/9/0/16), reconciled; only one query changed (F2's `.select('id')`); every producer of a checkout navigation enumerated (2 pushes + the returnURL; the `auction_won` notification link does not reach mobile checkout) | `review/d-records-20261005` @ `1e6e1e82`, `D_RC2_VERDICT_e2b9498b.md` |
| E: acceptance reconciliation | **ACCEPTED on the stated coverage** (2026-10-13). Delta rows closed; M-1..M-6 carried by an import-closure diff; D-RC2-1/-2 accepted as non-blocking; E9 recorded as weaker in one region (B's "stronger" claim not adopted) | `design/frontend-audit-20260917` @ `fc257fc6`, `V3_ACCEPTANCE_RECORD.md` "CURRENT ACCEPTANCE MATRIX: RC2" |

**Known, non-gating (fix in the next build; RC2 is not re-keyed for them):**
- **D-RC2-1:** in checkout's no-mode branch, a FAILED settled read reaches the generic catch. It shows "We couldn't start
  payment. Please try again.", the escrow note renders while the status is unknown, and the Sentry stage is
  mislabelled. It needs a mode-less arrival AND a read failure. No intent is created and nothing claims a charge.
- **D-RC2-2:** the restated E9 guard matches one spelling. A variant such as `(false as const)` would pass it. The
  shipped source is correct.
- **The Order screen at A3XL:** the header title "Your order" overflows the right edge (B's corrected attribution). It is
  identical on RC1 and RC2 and is not money.
- **B's probe notes:**
  - In the cold 3-D Secure pre-webhook window, the screen shows "Payment already completed" with "Try again" until the
    webhook lands. Money-safe.
  - Stripe's returnURL query matching is evidenced only on a device.
  - The no-mode completed face has no "View transfer".
- **D's residuals (record §9):**
  - Sentry noise on every legitimate mode-less open.
  - CM12 counts only the object-form push.
  - A possible resend dead end after an F3 failure, if the provider issues no new OTP.
- **Not tested, by design:** signed-in flows (owner-waived), real 3-D Secure returns on a device, VoiceOver (optional).

**Owner decisions** (A's recommendation):

| # | Decision | Recommend | Consequence | Gates distribution? |
|---|---|---|---|---|
| 1 | Migration 152, server-enforced blocking | Not in this release; first follow-up | A blocked person can still see, bid on, buy from and report the blocker; today's control hides that seller's listings and profile from the blocker. Guideline 1.2 compliance is Apple's call; **not claimed** | **Yes, as your decision** to accept the App Review risk before submission |
| 2 | F8: the device clock puts a still-active auction in "Ended" (leading bidder too) | Follow-up: the "Confirming result" state | A brief Bids-tab/listing mismatch until the server closes the auction (about 2 min). No money effect | No |
| 3 | B-D6: PlaceBid's Total is capped at 1.3× at A3XL | Follow-up, decided with the Badge cap | Readability only; no clipping after B-D7 | No |
| 4 | D-RC-3: the buyer never sees a FAILED refund (the app reads no failed-refund field) | Follow-up; O-R3 handles refund_failed cases daily | What a buyer sees after a failed refund is unverified. Rare | No |
| 5 | Live console/server: duplicate parked refund/payout action; relist without `expected`; Next.js 16.3.3 on web/console | Separate owner-gated packages | Live risk, independent of the app release | No |

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

## (History, superseded by "RC2 FROZEN" above) RC2 state at A's first final report (2026-10-12 ~06:10Z)

**Not frozen yet. The blocker is C's session: not running since 05:12Z, absent from ListAgents, socket gone.** C's
fixes are committed locally and unpushed. A does not push another session's branch.

| Part | Commit | State |
|---|---|---|
| RC1 line | `48d20ca1` | verified above |
| F6 (A): settled re-read before `not_held` and before `lost` (gated `setupDecision.ts`) | `fix/rc-f6-settled-recheck-20261012` `50e74efb` + `084de270` (origin) | RED 4/6 then 5/12; GREEN 152/152 on the 8 setup suites; mutants 3+3 killed as predicted; tsc/eslint 0; CI green on both commits; **D PASS on both commits** (own RED/GREEN runs, plus the transaction-order proof from SQL); B: logic SOUND at `50e74efb` (B did not review `084de270`) |
| F1/F4, F2, F3, F5, F7, D-RC-4 (C) | local `v3/rc-fixes-20261012` `1117731e`, 6 commits on `d27aa449` | tests-first with mutants per C-HANDOFF; **NOT pushed, full stages not run** |
| B-D7 (clipped money digits at A3XL; owner rule) | — | A's scope call: in RC2, reusing the approved stacking rule, with no copy change and pixel-identical default size. Not started (C was down) |

**A's local RC2 trial** (`48d20ca1` + `1117731e` + `084de270`; not pushed):
- Both merges are clean. `rc_verify.sh`: PASS.
  - `supabase/`, `web/`, `admin/`, `.github/` and the native inputs are unchanged.
  - Mismatches, unexpected changes and new blobs: 0 at both merges.
- C4: MISSING 0, the same 16 UNRESOLVED sites. F2's new `.select('id')` is covered: a planted bad column gives MISSING 1.
- Stage runner: env-pairing, typecheck, lint (0 errors) and parity 108 PASS. **Unit FAIL, 3/3,133.** All three are
  shipped-source guard pins that C's restructure tripped:
  - E9: a second `setPaymentStatusUnknown(false)`;
  - W2: 3 `readSettledPayments` calls, not 2;
  - the payout landing guard: `AUTO_REDIRECT_MS` renamed.
  - A reads none as a behaviour regression. Each must be updated to keep its invariant, not loosened (exact guidance
    in C's fallback note).
- **Remaining, in order:**
  1. C: B-D7 (or its fallback), the three guard updates, full stages, push.
  2. A: merge into `integration/rc-20261012` (PR #100 follows), `rc_verify.sh`, CI, C4.
  3. C: the fresh-install native build of the RC2 sha (H1).
  4. B: delta review (default + A3XL re-measure, Listing with `screen=listing`).
  5. D: RC2 record (C4 incl. web/admin; fix diff).
  6. E (if restored): delta rows.

## Lane results at `48d20ca1` (independent of A)

- **C: fresh-install native build, H1. BUILD EXIT 0.**
  - Release configuration; Hermes bundle embedded; uninstall-before-install verified.
  - Two cold launches reach Sign in with the SANDBOX banner, with 0 Metro listeners.
  - Evidence: `private-evidence/C-session-12c718b1/build-20261012/` on the SSD (not public).
  - Pairing: no production URL or live key VALUE in the bundle. The guard's refusal constants are present by design
    (`envGuard.ts:28`; the `pk_live_` prefix checks). B re-ran the scan with positive controls.
- **B: verdict `7060784e`** (`design/frontend-audit-20260917`).
  - The source review carries over (app diff 0). O-2 is evidenced from the artifact.
  - 70 native default-size state frames on the Release binary: PASS (fixture class).
  - A3XL: **FAILED** (B-D7, clipped money digits); B-D6 goes to the owner.
  - B recorded its own coverage limit: its checks probed "no false success", not "no false failure" or "inputs survive
    a remount", which is how F4 and F6 were missed.
- **D: verdict `e64dfe53`** (`review/d-records-20261005`).
  - C4 PASS for `app/src/packages` AND `web/admin`, shown non-vacuous (empty catalog → MISSING 88). D found 16
    scanner blind-spot controls and hand-resolved the classes in use.
  - No blocking defect in `48d20ca1`. Non-blocking: D-RC-1 (corrected), D-RC-2 (harness configuration in the public
    tree), D-RC-3, D-RC-4 (in C's branch) and five contract drifts.
- **E:** the acceptance matrix (`V3_ACCEPTANCE_RECORD.md`, current section). There are no genuine failures beyond
  F1–F7; passes are simulator-development class. E has been unreachable since ~04:44Z.
- **F:** dashboards v2 completed as previews: admin `f1e783e1` (code `fae12913`), venue `ee1d90b7` (code `bb94b1f2`).
  - Unit tests: admin 197/197, venue 157/157. Mutants killed: 21 + 16.
  - Browser sweep: 0 overflow, 0 contrast failures.
  - Local synthetic MFA flow with real TOTP. **Not in this release.**

## Findings for the owner (not in this release; each needs a decision or a later package)

| Id | What | Where it lives | Severity / evidence |
|---|---|---|---|
| D/F item 4 | The console's "already requested" state for refund_execute/payout_release is advisory only. `ops.execute_action` checks just the idempotency key; the console mints a key per render; a parked refund leaves `payments.status` unchanged; `order_detail.actions` is limited to 50. A stale tab or a second operator can park a SECOND money action | **live console + server** | D's code reading. Whether execution-time guards stop a second refund or payout was NOT assessed this sprint. Proposed: a partial unique index on `ops.action (action_type, subject_id)` over the open states, or a check in `execute_action`. **Needs a migration** |
| A15 | `listing_relist` ignores `expected` in `action_dispatch` (144:830). Only `admin_relist_listing`'s domain guard protects it | live server | A confirmed in SQL; migration |
| D-RC-3 | The buyer never sees a 150-lifecycle FAILED refund (`settledRead.ts:42` reads only the one-way record) | app | D; product follow-up |
| F6 residual | Stripe has charged, but neither promoter has committed: the row is pending, so a lapsed hold can still say "Nothing was charged" | app/server | D; F4's freeze-at-mount closes the 3-D Secure path operationally; optional hardening parked |
| F8 | `bidState.ts:83` puts a still-active auction in "Ended"/Past on the device clock, for the leading bidder too. No money effect | app | reviewer + C; the owner's product call |
| B-D6 | PlaceBid's Total is capped at 1.3× and paints smaller than its label at A3XL | app | B measured; the owner's call (as the Badge cap) |
| SEC-NEXT | Live web and console run Next.js 16.3.3: 1 critical and 6 more advisories, fixed in 16.3.8. RCE needs `next/og` (unused); no ISR, draft-mode or metadata-image routes; the image-optimisation SSRF is the only plausible surface (`next/image`, `remotePatterns` restricted) | **live web + console** | A's exposure analysis; a dependency bump plus a deploy, owner-gated. Dependabot has `next-16.3.8` for `web/` only |
| App deps | 1 critical (`shell-quote` via `react-devtools-core`, dev tooling) and 31 high (Expo CLI/metro chain); none in the Release runtime | app tooling | A's audit; SDK-level upgrade, later |
