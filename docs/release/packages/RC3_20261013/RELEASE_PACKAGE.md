# RC3 release package (A, 2026-10-13)

**Status:** **FINAL (A, 2026-10-13 ~07:20Z).** RC5 `1e491ac4` is accepted by every lane (C build, D server review, E reconciliation). Nothing is applied, merged into a deployment branch, built for distribution or submitted. What remains is owner decisions and actions (§9).

RC2 `e2b9498b` stays frozen. The owner accepted it on its documented coverage; its evidence and waivers are preserved
in `RC_20261012/`. This sprint's candidate, RC5, is the reviewed RC2 tree plus the fixes the owner directed on 2026-10-13. Nothing in this
package has been applied, merged into a deployment branch, built for distribution or submitted.

## 1. Candidate and PRs

| Item | Identity |
|---|---|
| **RC5 (the candidate)** | **`1e491ac48a2b7cd4ba73c699d16f815402642a6e`** (tree `8257b5aa…`) on `integration/rc3-20261013`; CANDIDATE_MANIFEST amendment 5. It is RC3 `50d8fcf1` plus C's fixes: C-RC3-2 (harness only) and C-RC3-1, the in-app Terms §6 last line not painting. C-RC3-1 was root-caused on device (RN measures a lineHeight'd paragraph with zero slack, and pixel-grid rounding deep in a tall scroll shortens its frame by 1/3 pt) and fixed with paddingBottom 0.5. **RC3 `50d8fcf1` and RC4 `c7c4991d` are not candidates** (both drop that line). |
| Server package (A) | `fix/rc3-marketplace-safety-20261013` @ `3091d30c`: migration 152 (`6a02519d`), console (`534d0268`), header comment fix (D F-152-3) |
| Consumer changes (C) | `v3/rc3-consumer-20261013` @ `f0d174d2` (`e9874236` the C-RC3-1 root-cause fix, `f0d174d2` a dev-only Privacy harness case; earlier `e2621154`/`d1111286`; on top of `e42eed5a`): `a61fa591` refusals + K1, `491f8431` in-app Terms, `cc032e86`/`e42eed5a` tests and harness |
| Gate PR | draft PR SnatchIt-app/snatchit#101 (base `release/production-gate-20260918`). RC2's PR SnatchIt-app/snatchit#100 is marked superseded and left open; do not merge both |
| Website wording (G) | draft PR SnatchIt-app/snatch-it-landing-page#23, stacked on #22 (publication = the owner's merge) |
| Wording source | `RC3_20261013/POLICY_WORDING.md` |

## 2. What changed

**Server: migration 152 (`20261013000000_marketplace_safety_enforcement.sql`, pgTAP 219).**
- **Blocking is server-enforced.** A new bid (trigger `before_bid_guard_parties`) or a new Buy Now reservation (trigger
  on a NEW reservation) between two users who blocked each other, either way, is refused `BLOCKED_PARTY`: "This
  listing isn't available to you." The message never reveals the direction.
- **Operator suspension.** It uses the existing `user_restrict` action with kind `suspended`, for platform_admin and
  platform_risk only. A reason is required, and self-suspension is refused. Who, when and why are recorded in
  `ops.user_restriction`, `ops.action` and `ops.audit`. Restoration is `user_unrestrict` with kind `suspended`; the
  history is kept.
- **What a suspension refuses:**
  - the suspended user's new bids, reservations, listings and listing-text edits (`ACCOUNT_SUSPENDED`);
  - other people's new bids and reservations on the suspended user's listings (`LISTING_UNAVAILABLE`);
  - `can_create_listing` answers `listing_blocked`, so every shipped client already shows "You cannot create listings
    at this time. Contact support."
- **Content check on the server.** Listing create and text edit (`event_name`, `venue`, `restrictions`) run the app's
  existing ten-term list, pattern for pattern (`PROHIBITED_CONTENT`), for every caller: the live web app, direct
  calls and service paths. A unit test pins the server list equal to the app's.
- **Explicitly kept (nothing is cancelled, stranded or erased):**
  - bids placed before a block or suspension stand, and a winning one settles;
  - a live Buy Now hold taken before them completes;
  - every existing order (sending, confirming, reports, disputes, refunds, payouts, notifications, support) is
    untouched: no 152 rule is attached to transfers, payments, refunds or payouts;
  - reports are never refused, and sign-in is not banned;
  - a suspended seller's existing listings stay visible and refuse new activity;
  - payout rules are unchanged for suspended sellers (follow-up FU-2).

**Console (A, `admin/`).** An "Account suspension" panel on the user page shows status, since when and the reason.
Suspend and Restore forms carry copy that says exactly what stops and what continues. A header badge shows a suspended
account. Other roles see an explanation instead of the forms.

**App (C).** `src/lib/moderation/serverRefusal.ts` maps the four hints by exact match to the K2 sentences on bid, Buy Now, create and edit. `BLOCKED_PARTY` and `ACCOUNT_SUSPENDED` are OK-only, with no retry; any other error keeps its earlier copy. Every block confirmation uses K1, and Block is now offered on `transfer/receive` and `transfer/send` (the order is unaffected). The in-app Terms (`legal.tsx`) carry F1, F2, P1-P3 and R1-R3 in both places, and "(or the auto-release window expires)" is gone. The no-service-time guard admits the three refund sentences only by exact text, and its drift control trips

**Wording.** One canonical text (`POLICY_WORDING.md`):
- fees on the sale price;
- a buyer-confirmed payout starts at once, apart from the risk-gated 72 h release;
- refund issue, processor state and bank receipt kept apart;
- the non-delivery refund described precisely;
- the claim-review turnaround promise removed.
The app applies it to the in-app Terms (C) and the website to /terms, /buyer-guarantee and the FAQs (G, PR #23).

## 3. Verification (exact results)

| Check | Result |
|---|---|
| Local PG17 replay (168 migrations), every pgTAP file | 98 files clean, 5,672 assertions; RC2 baseline 97 files clean. The only differences: new suite 219, and the 162 census pin raised to 116/43 |
| Suite 219 | 73/73. Negative control (the three guards disabled): 25 assertions fail, exactly the refusal checks (D reproduced: 24) |
| Rollback | md5 of the restored `ops.action_dispatch` and `can_create_listing` equals RC2's **and production's** (`a1b6c7f6…`, `8369a2a6…`, read 2026-10-13). Census back to 111/40. With suspension history the rows are kept and the check stays widened. Re-apply is byte-identical |
| Grant decisions | pass on a clean replay; deleting one 152 row fails them |
| Server/app term parity (unit) | passes; altering one SQL pattern fails it |
| CI 38347870842 on `6a02519d` (server package) | 5/5 jobs. `supabase test db`: Files=99, Tests=5678, PASS (219 ok). Census `functions=116 triggers=43`. Unit: 189 files |
| Admin console | typecheck, lint, unit (17 files / 119 tests), build: pass. Rendered on the local harness (PostgREST + auth stub over a 152 replay): suspend shows "Suspended" with time and reason; restore shows "not suspended" with history; support sees no form |
| D (independent) | **no blocking defect** at `6a02519d` (`review/d-records-20261005` @ `a4b02f2c`, `D_152_VERDICT_6a02519d.md`); coverage, transaction safety, dispatch diff (3 hunks), privacy, locks and rollback confirmed |
| App (C) | C added rc3-server-refusal, rc3-refusal-screens, rc3-block-confirm and rc3-legal-wording, and updated the bid-error, refund-wording and no-promise guards. A reviewed the diff (mapping, Terms text, guard strictness) |
| Integrated RC3 `50d8fcf1` | `rc3_verify.sh` PASS (merge 0/0/0; supabase/.github/admin == `3091d30c`, controls 9; app/src/tests == `e42eed5a`, controls 25; web == live web, controls 11; native inputs 0; nothing outside the owned surfaces). Local stages at `50d8fcf1`: env-pairing, typecheck, lint, unit (193 files / 3,181), parity (108), admin typecheck/lint/unit, replay: all PASS. pgTAP 98 files clean, 5,672 assertions. Admin build PASS. Push CI 38350673788 success (E). **Superseded:** C-RC3-1 |
| Integrated RC4 `c7c4991d` | `rc3_verify.sh` PASS for both merges (RC4 merge 5 files, 0/0/0; app/src/tests == `d1111286`; native inputs 0). **Superseded before its stages ran:** C's exact-sha build showed C-RC3-1 still present. Not used as evidence |
| Integrated RC5 `1e491ac4` | `rc3_verify.sh` PASS for all three merges (app/src/tests == `f0d174d2`, control 27; native inputs 0). Local stages at `1e491ac4` (07:08-07:10Z): env-pairing, typecheck, lint, unit (194 files / 3,187), parity (108), admin typecheck/lint/unit (119), replay: all PASS. pgTAP 98 files clean, 5,672 assertions (219 = 73/73). Admin build PASS. **CI push run 38359262792 on `1e491ac4`: 5/5 success**, pg_prove Files=99 / Tests=5678 PASS, census 34/116/37/43. PR #101: 7 checks pass; `Immutability + ordering` fails only on the owner's AUTODEPLOY-1 line. C's stages at `f0d174d2`: tsc 0, lint 0 errors, unit 194 files / 3,187 (UTC and America/New_York), parity 108 |
| Simulator Release build (C) at RC3 `50d8fcf1` | BUILD EXIT 0. Hermes bundle embedded (sha256 `74eed9ab…`), binary `eabefa5a…`, zip `f0763f28…` (private evidence). Sandbox pairing ALL PASS; Light and Dark cold launches. **Two findings on the changed screens:** C-RC3-1, Terms §6 cut mid-word (product, fixed in RC4); C-RC3-2, order-screen Block entry not rendered under a fixture (harness, fixed in RC4) |
| Simulator Release build (C) at RC4 `c7c4991d` | BUILD EXIT 0 (05:43:58-05:51:08Z). Bundle `356dbb33…`, binary `6ce25b38…`. Pairing ALL PASS; Light and Dark cold launches; Legal top and summary paint. **C-RC3-1 NOT fixed:** §6's second node still drops its last line (at a word boundary); the length hypothesis is refuted. C is finding the real cause; **RC4 will be superseded** |
| **Simulator Release build (C) at RC5 `1e491ac4`** | **BUILD EXIT 0** (06:54:44-07:01:49Z), fresh detached checkout and install. Embedded Hermes bundle sha256 `fc62aa66…`, binary `a2fd354c…`, zip `214a7697…` (private evidence). Sandbox pairing ALL PASS; Light and Dark cold launches. **Frames from this binary:** Legal top/summary whole; §6 end WHOLE (C-RC3-1 fixed); §5 whole; Privacy, 8 pages whole; order → Block the seller → K1 and send → Block Buyer One → K1, verbatim (Cancel, no write). **Not renderable from C's lane:** the four refusal dialogs (they need the server rule live) and K1 on listing/profile (signed-in, waived); unit-proven |
| Privacy screen (same clip mechanism) | **clean on device** (lab binary 6: every paragraph and bullet ends whole; all its text styles carry integral lineHeights). Unchanged |
| **Reconciliation (E)** | **ACCEPTED at RC5 `1e491ac4` on the stated coverage; no engineering blocker** (`V3_ACCEPTANCE_RECORD.md` "CURRENT ACCEPTANCE MATRIX: RC5 1e491ac4", `design/frontend-audit-20260917` @ `af134b07`). E independently verified: identity (36 files since RC2, each equal to its owner branch); CI 38359262792 (5/5 jobs, 68/68 steps); C's build (E recomputed the zip, binary and bundle digests and the pairing); the §6 paint fix; K1 on order and send. E classes the refusal dialogs and listing/profile K1 as source/test only, and the console page and A's stages as author-run. RC2 screens are inherited by import closure with native inputs 0 |

**Evidence class:**
- Local replays and CI use synthetic fixtures. Nothing was exercised against production.
- The simulator build is a Release build, unsigned and sandbox. It is not a distribution artifact.

## 4. Migration 152: scope, rollout order, recovery

**Production now** (read-only, 2026-10-13 04:56-05:00Z):
- ledger 164 rows, tip `20260925010000`; 152 absent;
- 111 public functions, 40 triggers, no name collisions;
- 0 `user_blocks` rows, 0 restrictions;
- 1 active listing (`c8d04339…`, the $300 Buy Now);
- no bids or succeeded payments in 30 days.
**Applying 152 refuses nothing for anyone until someone blocks, an operator suspends, or a new listing names a
prohibited term.**

**Apply method** (the 2026-09-22 targeted method, `PRODUCTION_APPLY_MANIFEST_20260922.md` §6):
- the one file plus its ledger row (`20261013000000`, `marketplace_safety_enforcement`), **never `db push`**;
  `db push` would also offer 121/125/126;
- a fresh pre-apply backup per `PRE_APPLY_BACKUP_20260922.md` first;
- stop on the first read-back that does not match.

**Pre-apply reference (production, read 2026-10-13):**
- `ops.action_dispatch` `a1b6c7f6…`, `can_create_listing` `8369a2a6…`, `reserve_buy_now` `5e01af4e…`;
- kind check `listing_blocked`;
- 111 functions / 40 triggers.
(`validate_and_apply_bid` differs from the repo by the recorded F-PROD-REPO-DRIFT-1, logic identical; 152 does not
redefine it.)

**Post-apply reference (local replay, function definitions):**

| Function | md5 |
|---|---|
| `ops.action_dispatch` | `bfb8b9dc…` |
| `can_create_listing` | `638c7bcc…` |
| `assert_marketplace_parties` | `56c1a6ad…` |
| `guard_bid_parties` | `97922d82…` |
| `guard_listing_reservation_parties` | `96b637a6…` |
| `guard_listing_content` | `afd7f7ac…` |
| `listing_prohibited_term` | `489fe7d8…` |

Also: 116 functions / 43 triggers; kind check widened.

**Order and dependencies (each step is a separate owner approval):**
1. **R-1:** RC5 into the gate (PR #101, merge method), after your `AUTODEPLOY-VERIFIED-OFF` line. No production effect. A then checks the merge tree equals RC5's (`8257b5aa…`).
2. **M-152:** apply 152 to production. Effect: immediate, for every client.
   - The live web app and current app builds show the server's sentences or their generic error copy.
   - The web app's own client-side list differs (FU-1); the server decides.
3. **Console deploy** (`admin/` at RC5), after M-152. Before it, the database answers `not_supported` to kind
   `suspended`.
4. **R-2:** the production-signed EAS build from RC5, then TestFlight, then G1 on the phone.
   - **M-152 must be applied first**, because the app's block copy states the server behaviour (K1), and G1 should see
     it.
5. **Website publication:** merge #23 into #22's branch, then #22 into `main`. Do it before R-3, because reviewers and
   buyers read /terms.
6. **R-3:** submission with manual release. A finalises the review notes (§7) first.
7. **R-4 (independent, later):** gate → `main` (S7). After M-152, 152's ledger row exists, so the integration skips it.
   121/125/126 stay below the tip and need their own targeted apply or explicit deferral, as before.

**Recovery limits:**
- The rollback (`supabase/rollbacks/20261013000000_…_rollback.sql`) restores production's exact bodies and keeps any
  suspension history.
- After a rollback: blocks are a client-side hide again, recorded suspensions are not enforced, and listing text is
  checked only by the app. Lift recorded suspensions first.
- The rollback cannot un-refuse a bid or reservation that was refused while 152 was live. Those were never written.

## 5. Policy wording (final proposal)

`POLICY_WORDING.md` §2 holds the canonical sentences, §3 the app rows and §4 the website rows; G's PR #23 applies §4.

G kept "Stripe's payment-processing costs are borne by Snatch It, not deducted from the seller." in /terms §17 b2.
It is consistent with the code (the seller fee is 10% of the base). Keep it unless you want F2 alone.

## 6. Operational readiness

**Correction to the RC2 record.**
- The RC2 package said "no scheduled refund review exists". That was too strong. A found none in this machine's
  scheduled tasks or claude.ai routines, but the owner reports refund-review triggers appearing in the Codex chat,
  which A cannot inspect.
- A trigger firing does not establish that an authenticated review ran or acted.
- The current production record (below) shows no console activity from any such review.

**Current state** (production, read-only, 2026-10-13 04:56-05:00Z; aggregates only):

| What | Now |
|---|---|
| Detectors | 13 jobs enabled. All 5-minute jobs last succeeded at 04:55Z. `daily_summary` last ran 2026-10-12 13:00Z. `refund_resolution` has never run (its switch is off) |
| Alert delivery | `alert_delivery_enabled = false`: no alert leaves the database. **17 console alerts exist; 15 `p1_case` alerts have been firing since 2026-09-08, with 0 delivered and 0 acknowledged** |
| Delivery path if switched on | `notify-report` (deployed v10, read 2026-10-13): push to every `admin_users` account (**2 admins, 0 registered push devices: no push can arrive today**), plus email to `ADMIN_EMAIL` (default support@snatchitapp.com) **only if the `EMAIL_ENABLED` secret is true and a Resend key is set**. A cannot read secrets, so the email state is UNKNOWN. Report-created and dispute pushes use the same path: 0 delivery claims recorded |
| Reports | 3 pending, the oldest from 2026-06-05; 0 ever resolved |
| Cases | 19 open (dispute_open 5, paid_unsettled 8, report_review 3, refund_pending 2, manual 1), all created 2026-09-08, none assigned |
| Console activity | 5 actions ever (3 setting_set, case_create, case_note), the last on 2026-10-08. The last human case event was on 2026-09-08 |
| Refund state | 2 refunds recorded, both succeeded. Refund-state detection is on |

**Historical (not re-checked):** the 2026-09-24 record that nothing notifies an operator.

**Conclusion:**
- The detectors run, but nobody works their output.
- The "timely responses" part of App Review 1.2 and the Buyer Guarantee's manual remedies depend on a person.
- **Monitoring is not functional until a named person works the queues and leaves a trail.**

**Daily operator workflow (proposed; about 15 minutes):**
1. Console **Today**: note the counts (open cases, alerts, disputes, payout review, paid unsettled, refunds pending,
   reports pending, webhook backlog, transfers overdue).
2. **/reports**: open each pending report and decide `actioned` or `dismissed` (report_resolve, with a reason). For
   an abusive user, apply a listing block or **suspend the account** (admin/risk).
3. **/cases** `refund_pending` / `refund_failed`: check the refund in Stripe (Payments → the payment → Refunds). If it
   failed, refund manually per the Stripe SOP. Add a case note, then resolve the case.
4. **Disputes:** respond in Stripe before the evidence due date (console "Evidence due 72h").
5. **Payouts:** for `payout_review`, `release_stuck`, `paid_unsettled` and failed payouts, follow the runbook; never
   release twice.
6. **Stripe Dashboard:** check refunds with status failed, and Connect payouts failed.
- Each step leaves an `ops.action` or `ops.case_event` row. That trail is the evidence that monitoring works.

## 7. Distribution readiness (read-only checks)

| Item | State | Evidence or reason |
|---|---|---|
| Stripe client pairing | **VERIFIED** (2026-10-13) | the EAS `production` profile's publishable key is live and contains the live account id `acct_1T6Far…`; its Supabase URL is the production project |
| Stripe server key (G4) | **UNKNOWN** | needs the live secret's digest against the production function secret; A has no authorised access |
| Live webhook (G3) | **VERIFIED again** (2026-10-13, Stripe API read) | one live endpoint `we_1TCqy5…`, enabled, pointing at production `stripe-webhook`, with 13 events including refund.* |
| Apple Pay certificate (G5) | **UNKNOWN** | Apple Developer only |
| Signing | EAS signed in as `jdt_inc`; distribution credentials **UNKNOWN** until G2 | `eas whoami` |
| Reviewer access (G7) | open | both review passwords are burned; reset after G2 |
| Review inventory (G6) | open | 1 active production listing (the $300 `c8d04339…`); the 3 review listings are not created |
| Privacy / Support / Terms / Guarantee / FAQ URLs | live (200) | snatchitapp.com/privacy, /support, /terms, /buyer-guarantee, /faq. Metadata lists Support URL = the home page; **recommend `https://snatchitapp.com/support`** |
| ASC metadata and review notes | A cannot see App Store Connect | draft in `APP_STORE_REVIEW_NOTES_V3_DRAFT_20260924.md`; safety text below |
| Edge functions | `primary-checkout` and `ops-refund-execute` are **not deployed** | Supabase list |

**Review-notes safety text (true only after M-152; A inserts it in the draft after M-152):**

> "Blocking: from a listing (⋯ → Block), a profile or an order, a user can block another user. The blocker no longer
> sees the other person's listings in Home or Search, and our servers refuse any new bid or purchase between the two
> of them, in either direction; orders they already have are unaffected. Reporting: any listing or profile can be
> reported; reports go to our moderation queue[, which our team reviews daily — insert ONLY once OA-3 names the person]. Our team can suspend an account, which stops new bids,
> purchases and listings. Listings containing prohibited terms are refused by our servers."

Compliance with App Review Guideline 1.2 is **not claimed**: Apple decides. The text states only behaviour.

## 8. Accepted follow-ups and evidence limits

- **FU-1** (D F-152-2): the web app's own pre-check (`web/src/lib/content-moderation.ts`) is a substring list that
  differs from the app's. The server now governs. Align it, and extend the parity test, in the web track.
- **FU-2:** suspension does not hold payouts to a suspended seller. Consider routing a suspended seller's auto-release
  to manual review. That is a payout-path change and needs its own review.
- **FU-3** (D F-152-6): a suspended seller's listings stay visible, and new activity on them is refused.
- **FU-4:** the web app's wording rows (`POLICY_WORDING.md` §5) are a prepared web deploy.
- **FU-5:** the two-way feed hide and the listing and profile "unavailable" states (BLOCKING_SCOPE_RECOMMENDATION
  §2a/§2d). The server refusal is in RC5; the symmetric hide is not.
- **FU-6** (D F-152-4): a suspension is not two-founder gated. It executes on one admin or risk operator's request,
  like a listing block. Stated for awareness.
- **FU-7:** a seller can block a buyer from an order screen (RC5), but there is still no in-app way to block or report a bidder who never bought (bid rows are not navigable by design). The server refuses both directions once any block exists; the missing piece is the entry point.
- **FU-8** (C): in `legal.tsx`, the chevron and privacy-link text styles have no integral lineHeight. That fractional offset is what exposed C-RC3-1. The 0.5 pt slack fix covers Legal regardless; adding integral lineHeights would be optional hardening. Privacy is clean on device; no other consumer scroll is comparably long.
- **Console page:** checked by A only (local harness, unit, build). D reviewed the database side of suspension; no independent review of the page itself is on record (E).
- **Device-render limits:** the four refusal dialogs need 152 live plus a blocked or suspended signed-in account, and K1 on listing and profile needs a signed-in viewer (waived). They are unit-proven (SR1-6, RS1-5, BR1-4, BK1-2). **G1 on the TestFlight build, after M-152, is the first chance to see them on a device**: recommended there, as one block and one bid attempt between two test accounts.
- **Not covered by 152:** the market rail (dark, flag off) and venue primary checkout (not deployed, no consumer
  caller). Both must gain the rule before they open.
- **Concurrency:** a block or suspension applies to activity that starts after it commits.
- **Carried from RC2:** VoiceOver optional and untested; the signed-in visual waivers stay waived, not passed; the
  simulator is not the device; D-RC2-1/2 and the other non-gating items.
- **Two Terms documents:** the app's (March 20, 2026) and the website's (July 14, 2026). Which governs is for the
  owner and counsel; both are marked draft for attorney review.

## 9. Owner actions (only what remains; recommendation and exact approval text)

Already done; no repeat needed:
- the live webhook (re-read 2026-10-13);
- the client Stripe pairing (verified 2026-10-13);
- the RC2 acceptance.

| # | Decision or action | Why | A recommends | Exact approval text |
|---|---|---|---|---|
| OA-1 | Accept RC5 | the candidate that carries the fixes | accept on the stated coverage (§3; simulator-class; waivers stand) | "Accept RC5 `1e491ac4` on its stated coverage." |
| OA-2 | Buyer Guarantee scope (`POLICY_WORDING.md` §6) | no recorded owner decision; cases 2-6 are manual Stripe refunds | keep the published scope; accept the manual duty | "Buyer Guarantee: keep the published scope; adopt the wording corrections; I accept the manual review and refund duty, with <name> reviewing daily." |
| OA-3 | Name the daily operator (§6 workflow) | 3 reports pending since June, 19 cases unassigned since 2026-09-08, 15 alerts undelivered | a named person, daily, starting before submission | "Daily operator: <name>, from <date>." |
| OA-4 | Alert delivery (production settings; owner-only) | no alert can reach anyone today | (a) sign in to the app once on a phone as an admin account, so a push device exists; (b) optionally set the `EMAIL_ENABLED`, `RESEND_API_KEY` and `ADMIN_EMAIL` secrets; (c) then set `alert_delivery_enabled = true` in the console. Expect the 15 firing alerts to post at once; triage the queue first. | "Enable alert delivery after an admin push device exists; I set the secrets myself." |
| OA-5 | R-1: RC5 into the gate | puts RC5 on the release line; no production effect | first add your line `AUTODEPLOY-VERIFIED-OFF: YYYY-MM-DD` to PR #101's description, after visually confirming in the Supabase dashboard that the GitHub integration's auto-deploy is off. The `Immutability + ordering` check requires it for a migration-bearing PR (E, run 38350746262); edit the description so the check re-runs. Then approve | "Merge PR #101 into the gate with the merge method." |
| OA-6 | M-152: apply migration 152 to production | the server enforcement the app and review notes describe | approve, by the targeted method after a fresh backup (§4). A prepares the commands and reads back each step | "Apply migration 152 (20261013000000) to production by the targeted method, after a fresh pre-apply backup." |
| OA-7 | Console deploy | the operator's suspend and restore controls | after OA-6 | "Deploy the console from RC5's admin/ after 152 is applied." |
| OA-8 | Website publication | Terms, Guarantee and FAQ wording | merge #23 into #22's branch, then #22 into `main` (marketing deploy) before submission. Keep the §17 b2 Stripe-costs sentence | "Publish the website: merge #23, then #22." |
| OA-9 | G4 (server Stripe key digest) and G5 (Apple Pay certificate) | A cannot check either | do both before OA-10 | (checklist G4 and G5 steps) |
| OA-10 | R-2: production-signed build, TestFlight, G1 | the first distribution artifact | after OA-6 and OA-9 | "Build RC5 `1e491ac4` with EAS production and upload it to TestFlight." |
| OA-11 | G7 reviewer resets; G6 review listings, the $300 listing, P5 | App Review must sign in and buy | after OA-10, per REVIEW_INVENTORY_PLAN_V3 | (per plan) |
| OA-12 | Review notes and ASC metadata | the notes must state only verified behaviour | approve §7's safety text once OA-6 is live; set Support URL to `https://snatchitapp.com/support` | "Approve the review notes as A finalises them." |
| OA-13 | R3 Twilio auto-recharge | signups fail when the balance runs out | enable (unchanged from RC2) | Twilio console → Billing → auto-recharge |
| OA-14 | R-3: submission, manual release | — | after OA-1 to OA-13 | Submit in App Store Connect; release manually |
| OA-15 | R-4: gate → `main` (later, independent) | `main` lags the gate; 121/125/126 | after release; fresh auto-deploy-off confirmation; D's pre-merge check | separate |

Not gating, for later: FU-1 to FU-6 (§8) and the web-app wording (FU-4).
