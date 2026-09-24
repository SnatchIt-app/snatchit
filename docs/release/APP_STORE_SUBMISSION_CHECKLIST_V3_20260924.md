# App Store submission checklist — V3 production candidate (A, 2026-09-24; DRAFT under D's review)

**Revised 2026-09-24 ~16:10Z** after the owner's message approving D1–D6: §5, §5b P6/P7, §6, §7 and §8 were corrected
in place. The owner's actions now live **only in §8**.

**Status: DRAFT.** A owns this consolidation. D independently reviews its consequential payment and operational
claims. **Nothing here was executed.** No key was changed, nothing was deployed, no review inventory was created, no
charge or refund was made, no Apple response was sent, and nothing was submitted. This document **supersedes** the
five historical documents in §1 as the current checklist. Every fact carries its source; a fact without one is marked
unknown.

**Evidence classes used below.**
- **[SRC]** source at an exact commit.
- **[REC]** a dated repository or memory record.
- **[D-PROD]** D's production reads for this review. D has put the scope of those reads to the owner; A has not
  re-run them, and they are not independently corroborated.
- **[OWNER]** something only the owner can observe: a dashboard, ASC or Stripe.
- **[UNK]** unknown.

## 1. Historical documents — do not execute, do not paste

| Document | Its own date / status | Why it is historical | Hazard if reused |
|---|---|---|---|
| `docs/app-review-checkout-rca-2026-07-30.md` | 2026-07-30; last edit 2026-07-31 | RCA for the Build 9 rejection. Its fix was carried out 2026-08-03/04 [REC] | its "Fix" block contains `supabase secrets set STRIPE_SECRET_KEY=…` for production and a live webhook add; its verification loop uses `scripts/check-stripe-env.sh` and the `diag-stripe-env` function, **both absent** from this branch and from main, and the function was deleted from production 2026-08-04 [REC]. Re-running any of it would change production keys |
| `docs/app-review-response-2026-07-21.md` | "DRAFT — do not send until founder approval"; for submission `c23833b4`, version 1.0 (7) | answers a July Guideline 2.1 request about a build and inventory that no longer exist | quotes $330/$247.50/$275 listings (ended 2026-08-23) and build 9; its resubmission checklist targets build 9 |
| `docs/payout-rollout.md` | 2026-07-15 | rollout plan for migration 039 and build 8 | its procedure runs `supabase db push`, `psql "$PROD_DB_URL"` and `supabase functions deploy` against production, and a rollback that DROPs payout tables and columns; this bypasses the owner-gated, frozen-script apply path (AUTODEPLOY-1, `DEPLOYMENT_PATHS.md`). **Never execute** |
| `docs/product/APP_STORE_METADATA.md` | review notes "Updated 2026-08-04"; last edit 2026-08-25 | name, subtitle, keywords, categories, URLs and privacy section may still apply; **the review-notes block is stale** | names Build 13 as current; $2 Buy Now / $2.20; $1 bids; "active through late August 2026"; several unverified operational promises (§4) |
| `docs/product/LAUNCH_PLAN.md` | pre-TestFlight plan, July | Sections G (test-mode Connect seeding) and I ("paste verbatim" review notes) describe a test-mode world | pasting Section I would tell Apple the seller is onboarded in TEST mode |
| `docs/product/APP_STORE_LAUNCH_CHECKLIST.md` | "as of 2026-07-12: SUBMITTED — build 7" | build 7 was rejected 2026-07-20 | its steps target build 7 |
| `docs/security/STRIPE_APP_STORE_AUDIT.md` | audit date 2026-05-10 | predates live mode, 039, Phase 2 and V3 | findings describe the May stack |
| `scripts/appreview-hide-stale-listings.sql`, `scripts/seed-demo.ts` | July | production data mutations for July inventory | review inventory is not authorised; any future inventory needs its own owner-approved plan |

## 2. Stripe live/test mismatch — what closes it, and exactly what that covers

| Step | Evidence | Class |
|---|---|---|
| 2026-07-29: Build 9 rejected. The server key was test-mode; the build shipped `pk_live` | RCA §Root cause | [REC] |
| 2026-07-30: first key swap stored an invalid key; checkout returned 500 | RCA §Update | [REC] |
| 2026-08-03/04: live key and live webhook in place; four server-side root causes fixed; first live payout 2026-08-04; the two test purchases refunded and their transfers reversed; migration 045 added `payments.stripe_livemode`; `diag-stripe-env` deleted from production | A's August record, memory `snatchit-aug3-payment-incident` | [REC] |
| Build 13 (1.0.0 (13), EAS `cb5646b5`, commit `3c67dfc`, pk_live only) attached to version 1.0 on 2026-08-04; Resubmit left to the owner | same record | [REC] |
| Production payments split by `stripe_livemode`: 49 `false`, 2026-03-25 to 2026-07-29 19:51:05Z; then 8 `true`, 2026-08-04 01:00:22Z to 2026-09-03 14:40:20Z; no interleaving. Live sample: 2 succeeded, 2 refunded, 3 pending, 1 failed | D's read | [D-PROD] |

**What this evidence covers:** the production project `hqycwntpfoztoinemqns` with a live-mode server key, through
2026-09-03. The binary named in the records is Build 13.

**What it does not cover:**
- **The V3 binary.** Production rows record the environment, not the build.
- **The server code deployed 2026-09-23/24:** `create-payment-intent` v48, `confirm-payment` v37,
  `confirm-and-release` **v38** (2026-09-24 20:31Z, #93), `enforce-transfer-expiry` **v41** (2026-09-24 16:57Z, #92),
  `stripe-webhook` v42. No live payment has run through them; the newest payment of any kind is 2026-09-03 [D-PROD].
- **The current secret values.** Deploys do not change secrets, but nothing re-verified them after 2026-08-04.
- **The August transactions are not verification of the new binary or the new server code.**

## 3. Minimal validation plan for the final production candidate

**Already established without any transaction.**
- **V1 — client pairing** [SRC `2619b9e1`]: the `production` EAS profile carries the production Supabase URL and a
  `pk_live_` key; `sandbox`/`preview`/`development` carry the sandbox URL and `pk_test_` keys.
- `src/config/envGuard.ts` refuses any other pairing with a blocking screen: F2 production must be production plus
  live; F4 no test key on production; F5 the key's account fragment must be `51T6Far`, the live account.
- `app.json`: `merchant.com.snatchit`, bundle `com.jdt-inc.snatchit`, `supportsTablet: false`.
- **To confirm on the actual candidate:** the pinned commit, and that the TestFlight build opens without the guard
  screen [OWNER, no charge]. A production build that launches at all has therefore already proven client-side mode and
  account alignment (D's review). V2, V3 and V6 carry only the server side and the webhook subscription.

| # | Check | How | Who | Charge? |
|---|---|---|---|---|
| V2 | Server key is live **and** of the same account as the build's `pk_live` | Compare the digest shown by `supabase secrets list --project-ref hqycwntpfoztoinemqns` for `STRIPE_SECRET_KEY` with the SHA-256 of the live secret key copied from the Stripe Dashboard, computed locally with `printf %s "$KEY" \| shasum -a 256`; no value is shown to anyone. Alternatively V6 proves it | owner, or A if the owner authorises that one production read of secret names and digests | no |
| V3 | Live webhook configuration | Stripe Dashboard, live mode → Developers → Webhooks: endpoint `https://hqycwntpfoztoinemqns.supabase.co/functions/v1/stripe-webhook` enabled, subscribed to the 11 events the deployed handler processes [SRC gate `stripe-webhook`]: `payment_intent.succeeded`, `payment_intent.payment_failed`, `payment_intent.canceled`, `charge.refunded`, `charge.dispute.created`, `charge.dispute.closed`, `account.updated`, `transfer.created`, `transfer.reversed`, `payout.paid`, `payout.failed`; signing-secret digest compared with `STRIPE_WEBHOOK_SECRET`'s digest, as in V2. V6 then proves delivery end to end | owner | no |
| V4 | Apple Pay reachability | Stripe Dashboard, live → Settings → Payment methods → Apple Pay: `merchant.com.snatchit` certificate active. On the TestFlight candidate, on an iPhone with a Wallet card, the PaymentSheet offers Apple Pay; dismiss it without paying | owner | no |
| V5 | Reviewer login and inventory | The reviewer buyer and seller credentials sign in on the TestFlight candidate. Inventory requirements for the review window: active listings whose end dates outlast the review, a low Buy Now price, approved proof, and a seller that is payout-ready in live mode. **Creating or extending inventory is not authorised** and needs its own owner-approved plan. Reviewer account state since August: [UNK] | owner (login); plan by A | no |
| V6 | **Bounded non-charging production check**, proposed and not requested yet | On the TestFlight candidate as the reviewer buyer: open one review listing's checkout, see the PaymentSheet (also V4), leave without paying. Then the owner cancels that one live PaymentIntent (the §6 step of the fixture sheet, in live mode). Proves, with no charge: the server key is live and of the build's account, because the row has `stripe_livemode` true and the PI is in the live dashboard; `create-payment-intent` v48 in production; webhook delivery, signature and handler v42, because `payment_intent.canceled` moves the row to `failed`. **Writes:** 1 hold for 10 minutes, 1 live PI, 1 payments row, `rate_limits` | owner, then A reads back | no |
| V6a | **Preferred instrument for the webhook half** (D's proposal, 2026-09-24): the owner cancels, in the live Dashboard, one **existing** stale pending live PaymentIntent. Cheapest candidate: the **$2.20** pending payment of 2026-08-06; the others are $88 (auction, 2026-08-05) and **$330 (2026-09-03, on listing `c8d04339-bb33-4bf3-945d-d23d7dd269ca`, the only reviewable listing)** [D-PROD: 3 pending live payments, 11 pending in all]. Proves, with **no new intent and no charge**: the live endpoint subscribes to and delivers `payment_intent.canceled`, the signing secret matches, and handler v42 moves the row `pending → failed`. It also removes stale state. **It does not prove the current `STRIPE_SECRET_KEY`**: the webhook's cancel branch makes no Stripe API call [SRC gate `stripe-webhook:391-458`], so V2 or the V6 checkout is still needed for the key. Precondition: O2 shows the subscription | owner, then A reads back | no |

**Residual gap: what one live $2.20 purchase would and would not exercise (an option only; not authorised).**
- **It would exercise:**
  - settlement (`payment_intent.succeeded` → transfer row) on `stripe-webhook` v42 and `create-payment-intent` v48;
  - an Apple Pay authorisation, if Apple Pay is used;
  - the `charge.refunded` write-back after a full refund from the Dashboard;
  - the post-purchase notifications.
- **It would leave untested:**
  - the payout executor (there is no seller payout; the transfer reverses);
  - the 149 audit writers a1–a4 and the 148 hold refusal (the seller-win and dispute paths);
  - partial refunds.
- **Proposal, for a later owner decision:** one live purchase on the candidate by the reviewer buyer of one review
  listing at the lowest Buy Now price: $2 + $0.20 fee = **$2.20**. Then:
  - verify settlement and the transfer row;
  - refund in full from the Stripe Dashboard;
  - verify the `charge.refunded` write-back with amount and id;
  - no seller payout, so the transfer is reversed.
- **What stays open even then:** the payout executor's first production run. It can be closed only by a real payout
  to a live connected account, a separate decision.
- **Fresh live testing is not authorised; nothing above has been requested.**

## 4. Claims — verified, reworded, or omitted

Rule, from the owner (2026-09-24 ~05:05Z): submission wording comes only from verified behaviour; an unsupported claim
is **omitted**, not offered as a choice. Operating-policy questions are in §5b. Client = V3 candidate `2619b9e1`;
server = gate `5b255838`, deployed 2026-09-23.

| Current claim (metadata / review notes) | Verdict | Evidence |
|---|---|---|
| Live auctions; bid, or Buy Now | **keep** | [SRC] bid path `PlaceBidScreen.tsx:181`; Buy Now `detailState.ts:348` |
| "Your payment stays on hold until your tickets arrive" | **reword**: "You pay at checkout. The seller is paid only after you confirm the tickets arrived, or after a review window with no report." | [SRC] payout gates: buyer confirm (`confirm-and-release`) or risk-based release (039 policy: LOW 72 h, MEDIUM held, HIGH manual review; ≥ $200 never on silence, `PAYMENT_STATE_WORDING_TABLE_20260924.md:45`). "On hold" wrongly suggests a card authorisation; the card is charged at checkout |
| "outbid alerts the second it happens", "instant outbid alerts" | **omit** | outbid push returns early while the legacy `app.settings` values are null [REC `NOTIFICATION_BATCH_1_PLAN.md:36`]; production state of those settings never read; the native app has no reader for the in-app notification rows [SRC, dispute trace] |
| "yours in one tap with Apple Pay or card" | **reword**: "Check out with card or Apple Pay, processed by Stripe." Keep Apple Pay only after V4 | [SRC] `CheckoutNative.tsx:315-355` (Apple Pay detected, cart items); live certificate unverified (V4) |
| "Payouts go straight to your bank through Stripe" | **reword**: "Sellers are paid through Stripe Connect once the sale completes." | legacy path paid 23 transfers, including a live one 2026-08-04 [REC `SPRINT_STATUS:1405,1412`]; the payout code deployed 2026-09-23 has not yet run in production [D-PROD `payout_attempts` 0; REC SPRINT_STATUS:1412] |
| "Confirm receipt and the sale completes" | **keep** | [SRC] `confirm-and-release` |
| "open a dispute and our team steps in" | **reword**: "If the tickets don't arrive, report it in the app; the seller's payout is frozen." Stop there (D's review): a review process is not evidenced, since `dispute_resolutions` holds 0 rows and 5 disputes are open [D-PROD]. | [SRC] `buyer_dispute_transfer` (0550:207-225) sets `disputed_at`, which every payout gate checks. "Our team steps in" is **omitted**: operator alerts are undelivered (`alert_delivery_enabled` false, no dispatcher; admin push to `admin_users` only, 0 of 2 admins with an active push token [REC SPRINT_STATUS:1377]; email off [D-PROD / REC]), and the review promise has no operating process (§5b) |
| "Verified phone numbers on every seller account" | **reword**: "Sellers verify a phone number before listing." | [SRC] `CreateListingScreen.tsx:427`. "Every" account was not checked |
| "Step-by-step transfer guides for 14+ ticketing services" | **keep** | [SRC] `platformInstructions.ts`: 15 named platforms plus "other" |
| "Report, block, and dispute tools built in" | **keep** | [SRC] report `app/report/[type]/[id].tsx:65`; block `Settings → Blocked Users`; dispute as above |
| "Free to browse and bid. You pay only when you win." | **reword**: "…You pay only if you win and complete checkout." | [SRC] a winner pays through checkout; bids are not charged |
| "peer-to-peer marketplace for users 18 and over" | **keep**, with the review-note wording "users confirm they are 18+ at signup" | [SRC] `signup.tsx:71,272` (self-attested checkbox) |
| Review notes: "Reports are reviewed within 24 hours" | **omit** | nothing enforces 24 h; disputes get a 72 h case due date, reports none [SRC 115:147, 117:402,523]; alerts undelivered. **The app itself says 24 h** for reports in two places and for disputes in one (`report/[type]/[id].tsx:78`, `settings/privacy.tsx:144`; disputes `transferState.ts:182`; lines at `9c6c9bf4`), and "may remove content or suspend accounts" (`report/[type]/[id].tsx:88`) although no listing-takedown or account-suspension action exists [SRC 144:480-484,830-876]. In-app copy is C's lane; the promise is the owner's policy (§5b) |
| Review notes: "unresolved or disputed orders are refunded per policy" | **omit** | expiry refund code exists (enforce-transfer-expiry Phase 1) but no end-to-end expiry has been confirmed in production [REC SPRINT_STATUS:1258]; a buyer-win dispute records `refund_required` only, and executing it needs the disabled refund executor or a manual Stripe Dashboard refund [SRC 065:130-141, 144:889-914; REC SPRINT_STATUS:1285] |
| Review notes: "if a purchase is completed, we monitor and refund" | **omit as written**; replace only with an owner commitment (§5b) | refunds are manual (Dashboard); no alert reaches an operator |
| Review notes: "Build 13 is the current binary"; "$2 / $2.20"; "active through late August 2026"; "current bid $1" | **replace** | the V3 build number, prices and dates come from V5 and the owner's inventory plan; none exist yet |
| Review notes: button labels "Buy · $X" / "Pay · $X" | **replace** with V3 labels: listing "Buy now · $X" (quantity 1), checkout "Pay $X" | [SRC] `detailState.ts:348-352`, `payControl.ts:90` |
| Review notes: Apple Pay via PaymentSheet, merchant `merchant.com.snatchit` | **keep, after V4** | [SRC] `app.json:73`; certificate [OWNER] |
| Review notes: test phone number +1 800 555 0123 / 789012 | **keep only after the owner confirms** it is still configured in Supabase Auth | [OWNER] |
| Review notes: Settings → Delete Account (double confirmation) | **keep as written** — the app does ask twice (corrected 2026-09-24 against Build 23) | [SRC `9c6c9bf4`] `app/settings/index.tsx:211-214`, button :367 |
| Review notes: Stripe data handling (card/bank/KYC data stored by Stripe only) | **keep** | unchanged architecture; PaymentSheet and Connect-hosted onboarding |

**Refund facts, three ways, as the owner asked:**
- **Tables record** [D-PROD]: 7 payments `refunded` (5 test-mode, 2 live-mode). 4 carry a `stripe_refund_id`
  (2026-04-01, 04-02, 04-03, 07-04; all test-mode). 3 carry none (2026-03-29 test; both live rows, 2026-08-04 17:20:05Z
  and 17:20:19Z). `amount_refunded_cents` is NULL on all 7. `payment_refunds` holds 0 rows, which is what the
  no-backfill design predicts (142 / 20260906120000). No refund since 2026-08-04.
- **History establishes:** real Stripe refunds occurred in test mode. The two live-mode sibling orders of 2026-08-04
  were refunded and their transfers reversed, per A's August record [REC memory `snatchit-aug3-payment-incident`:
  "Both earlier test purchases refunded, transfers 'reversed'"]. Production corroborates it independently: exactly
  **2** transfers are `reversed`, matching the 2 live-mode refunded payments of 2026-08-04 [D-PROD].
- **Unknown:** how those two live rows, and the 2026-03-29 test row, were written. Source at origin/main, which was
  deployed until 2026-09-23, shows **two code writers** of that exact shape: `refunded` + `refunded_at` + no refund id.
  - The lost-chargeback branch (`stripe-webhook:690-697`) never writes a refund id.
  - The `charge.refunded` branch (`:712-724`) writes the id only when the event payload carries `charge.refunds`,
    which "recent API versions omit… best-effort".
  - A manual runbook `UPDATE` (`DAY7_DAILY_MONITORING_CHECKLIST.md:105`) is a third possibility.
  - So those rows may be real refunds or lost disputes. Whether any of the 7 is a partial refund recorded as full is
    also unknown, because the old code recorded no amount.
  - Only a Stripe read settles it: owner action O6.
- **The new code (gate, deployed 2026-09-23)** records every refund through `record_payment_refund`, with an amount,
  one ledger row per refund, and `status='refunded'` only at the full total. Refund *creation* still happens only in
  `enforce-transfer-expiry` (expiry, unfulfillable), or by a person in the Stripe Dashboard. The ledger executor and the
  ops refund action exist in the tree but are not deployed or are switched off.

**Payout facts:** 23 transfers carry a Stripe transfer id, all written by the legacy path, which recorded ids directly
[SRC origin/main `confirm-and-release:548-555`, `enforce-transfer-expiry:678-688`]. The attempt-based path deployed
2026-09-23 writes ids only through `payout_attempts` [SRC gate `_shared/payouts.ts:455`]; zero attempt rows means it has
not paid yet, not that payouts never happened. Unknown: whether a legacy lost-response duplicate exists among the 23;
20260906120000 says such duplicates were bounded only by Stripe's own dedup.

**Finding F-DISPUTE-SELLERWIN-1 (A, 2026-09-24, source-verified at the gate; not a regression of this release):**
- A dispute resolved "seller wins" (`resolve_transfer_dispute`, 065:119-129) sets the status value `'buyer_confirmed'` and
  clears `disputed_at`, but leaves `buyer_confirmed_at` NULL.
- The payout sweep takes rows with status `'buyer_confirmed'` only when `buyer_confirmed_at` is older than 15 minutes (gate
  `enforce-transfer-expiry:1180-1181`; the same filter is on main at `:804-806`).
- The console's `payout_release` accepts only `seller_sent` (144:813).
- So a seller-win outcome has **no automated or console path that pays the seller**. The money is stuck, not lost; an
  ops `release_stuck` case is expected to surface it.
- **Affected rows today: 0.** All 19 `'buyer_confirmed'` transfers carry a timestamp [D-PROD]. The zero exists only
  because **no dispute has ever been resolved**: `public.dispute_resolutions` holds 0 rows, while **5 disputes are open
  now** (`dispute_resolved_at` NULL, matching the 5 `dispute_open` ops cases) [D-PROD]. The first seller-win resolution
  anyone performs will hit this path. D confirmed the three source anchors independently.
- A bounded fix will be prepared as a source change for review. Nothing is applied.

## 5. Owner actions — superseded by §8 (mapping kept for older references)

| Old | Now | Status |
|---|---|---|
| O1 fixture decisions | §8 **G1** | **decided**: D1–D6 approved at `7dae4815`; execution awaits its three conditions |
| O2 webhook + digests | §8 **G3**, **G4** | open |
| O3 Apple Pay | §8 **G5** | open |
| O4 reviewer accounts | §8 **G7** | open; rotation still OPEN |
| O5 test phone + Twilio | §8 **E7** (optional) + **R3** | open |
| O6 refunded rows | §8 **E4** (optional) | open |
| O7 V6/V7 | §8 **E1–E3** (optional) | not requested |
| O8 inventory | §8 **G6**, plan in `REVIEW_INVENTORY_PLAN_V3_20260924.md` | plan written; decisions open |

## 5b. Owner operating-policy decisions (separate from the actions)

- **P1 — review and response times.** The app promises report review "within 24 hours" in two places, dispute
  review "typically within 24 hours", and support email replies "within 1 to 2 business days". No process or alert
  backs any of them. Choose the promise, or remove it; C then aligns the in-app copy.
- **P2 — who handles disputes and reports, and how they learn of them.** Operator alerts are off, admin push reaches
  no active token, and email is off. The console shows cases only when someone looks.
- **P3 — content removal and suspension.** The app says the team "may remove content or suspend accounts" (`report/[type]/[id].tsx:92`), and also `privacy.tsx:145` ("removed, suspended, or permanently banned"), `legal.tsx:247` and the bad-faith-report suspension lines (`report/[type]/[id].tsx:134`, `privacy.tsx:146`). The
  console has no listing takedown and no suspension; it has only `user_restrict`, which blocks new listings. Either
  build the mechanism or remove the promise.
- **P4 — refunds.** State the refund policy the operation can honour today: manual Dashboard refunds, and expiry
  refunds by the cron once confirmed in production.
- **P5 — refunds of App Review purchases.** Decide whether to commit to refunding any purchase a reviewer completes,
  and who does it.
- **P6 — seller-win disputes.** The fix is PR #92. **R1 executed 2026-09-24: apply 16:55:40Z, deploy 16:57:01Z, run
  check PASS 17:03:42Z** (package §13). **By source and tests, not observed in production** (pgTAP 215/216, vitest
  SW-*/BC-*; production had 0 seller-win rows and 0 payout attempts at D's W2, 20:32Z): a seller-win resolution has a
  payout path that respects holds and manual review (E-4/E-5). The seller's notice is written at once, and about 15 min
  later the sweep pays if nothing holds it. Since 149 and `confirm-and-release` v38 (20:31Z), its audit records state
  the actual buyer confirmation (#93 package §12).
  Resolving any of the 5 open disputes remains the owner's decision; R1 did not authorise it. The first seller-win
  resolution will probably be the first production run of the attempt-based payout executor, so tell A beforehand and
  the outcome can be read back (a separately authorised read). (Superseded: "until R1 executes, do not resolve".)
- **P7 — what a seller is told after a seller-win resolution. DECIDED by the owner (2026-09-24):** "Dispute resolved
  in your favour", with no claim that payout has completed. It is implemented server-side in #92 and client-side in C's
  `ca27d282` / `aee15697` / `404bce38` (A PASS). Server side live since R1 (2026-09-24 16:55:40Z); the client side needs a new build.

## 6. Readiness verdict

**Not submission-ready.** Required and not done:
- **visual acceptance: Build 24 FAILED (G0), and the correction is in progress (B, C);**
- **Production inventory, the hardest blocker:** 113 listings, **exactly 1** active and unexpired: III Points Saturday
  GA, ends 2026-10-18, Buy Now **$300** (so a reviewer could complete a $330 charge). 66 more are active with an end
  time already past [D-PROD]. A reviewer today sees one purchasable item. Owner action O8;
- the V3 production candidate build (none exists; every build since 13 is a sandbox preview);
- G3–G5 and G7 (§8);
- the inventory decisions (G6; the plan exists);
- the claims rewrite approved;
- the phone-session evidence, including the expired and held cells. The decision is made (D5/D6 approved); the evidence is produced by the session (G1);
- appearance evidence measured by **screen**, not by token count. C found three transfer-flow components (DeliveryInfoForm, PlatformInstructions, ProofImageViewer) still on the pre-v2 `colors` module, which a token-based inventory missed; they are migrated at `9c6c9bf4`, and a test now forbids that import [C's report];
- the residual live-transaction gap (§3) decided.

The draft review notes and metadata are in `APP_STORE_REVIEW_NOTES_V3_DRAFT_20260924.md`.

## 7. Build 23 reconciliation (A, 2026-09-24)

**Build 23** is EAS `65cb7633-0eca-4314-b135-fd9c90db8214`, commit `9c6c9bf4`, `preview` profile. It is a **sandbox** binary:
`pk_test`, project `ofaidukbieeekqaboscm`. **It is not a production candidate and cannot be submitted.** It was the client
planned for the device session; Build 24 replaces it (below).
- Every client citation in §3–§4 was re-verified at `9c6c9bf4` by a read-only check. None changed in behaviour or copy;
  some line numbers moved and are updated above. The two commits after the prior candidate change colour and styling only.
- `eas.json`, `app.json` and `envGuard.ts` are unchanged since `2619b9e1`, so V1 holds for Build 23's source.
- **Build 23 is superseded for the phone session by Build 24** [C's report]: EAS `c5b3a615-ff97-4a88-a4ce-2dae24558478`,
  commit `404bce38`, sandbox `preview` profile, authorised by the owner, and compiling on EAS at 11:43 local. A verified
  by ancestry that `404bce38` contains `2ffb10a8` (auth mark, dimmed text, field prompts) and the dispute-copy commits
  `ca27d282` / `aee15697`. Build 24 is still a sandbox binary, so it is **not** a production candidate (G2).
- **§4 citations re-verified at `404bce38` (A, 2026-09-24, read-only):** the copy is unchanged for every §4 claim. Moved
  lines: dispute "typically within 24 hours" `transferState.ts:182` → `:213`; the 18+ checkbox `signup.tsx:71,272` →
  `:276-288`; the listing phone gate `CreateListingScreen.tsx:427` → `:466-482`. Report, privacy and legal lines are
  unchanged (`report/[type]/[id].tsx:78,92,134`, `privacy.tsx:144-145`, `legal.tsx:247`), and `settings/index.tsx` is
  unchanged.
- **New since the last revision.**
  - F-DISPUTE-SELLERWIN-1 now has a fix: **draft PR #92**, head `e73553d2` (all 9 checks green; pgTAP Files=95 /
    Tests=5517 PASS at `e2205bbb`, census 32/108/37/38). **Applied and deployed to production 2026-09-24 (R1); source merged into the gate 2026-09-24 18:12:19Z as `374103c0`.**
  - Build 23 still tells a losing buyer "You confirmed receipt" after a seller-win (`transferState.ts:174-175`) and shows
    "Received" on three surfaces. C's fix is on `v3/midnight-app` (`ca27d282`, `aee15697`, `404bce38`), all A PASS. It is
    **in Build 24, not in Build 23**. The sandbox path still cannot reach a seller-win row.
  - F-LISTING-CRITICAL-TIER-1: the critical risk tier is enforced only by the client. Not a submission claim; an
    operational finding.

## 8. Owner action checklist (consolidated; required gates first; revised 2026-09-24 ~16:10Z)

**Secrets never go into chat, the repo or a document.** Every digest below is computed on the owner's own machine, and
only "match: yes/no" comes back. Dashboard paths were taken from the vendors' current docs on 2026-09-24. Where a doc
names no exact label, the step says so.

### A. Required submission gates (nothing is submittable until all are done)

| # | What, exactly | Bring back | Unblocks |
|---|---|---|---|
| G0 | **Visual acceptance: FAILED on Build 24 (owner, 2026-09-24 ~16:45Z).** B and C are correcting the implementation against the approved V3 mockups. **The app cannot be called submission-ready while this is open.** | the owner's acceptance of a replacement build | G1's session; G2's pin |
| G1 | **Phone session — PAUSED (G0).** Previously planned on Build 24. *Decision: DONE* (owner, 2026-09-24): D1–D6 approved exactly as specified at `7dae4815`. That includes D5 (F-EXP, expired) and D6 (F-HELD, held); **no separate expired/held decision exists.** *Execution* starts only when all three hold: (1) Build 24 is installed and signed in as the DV buyer; (2) the owner is available and says **"go"**; (3) A's sheet §4 preflight passes. **The fixture approval does not gate installing Build 24 or the appearance and navigation checks**, which need no fixture write. One $105 bid on L-BID, one Buy Now on L-CHK, **no Pay tap**, all cleanup deadlines as specified. The owner cancels the W2 test intent when A sends its `pi_…` id (CLI route, `REVIEW_INVENTORY_PLAN_V3_20260924.md` §5); its payment row is never marked failed as a substitute for cancellation | "go" at session time; the Canceled confirmation | device evidence for W1/W2 and the expired/held cells |
| G2 | **Authorise the V3 production-candidate build:** one EAS `production` build (pk_live) + TestFlight upload; A pins the commit. **Pin requirement:** it must contain `2ffb10a8` and `404bce38`. A checks with `git merge-base --is-ancestor` at pin time | the authorisation | V1 on the real binary, V4, V5, G7, G6, the review build number |
| G3 | **Live webhook.** Stripe Dashboard → switch to **Live** → Developers → **Workbench** → **Webhooks** tab (`dashboard.stripe.com/webhooks`) → select the destination `https://hqycwntpfoztoinemqns.supabase.co/functions/v1/stripe-webhook` → **Overview**. On the older Developers dashboard: Developers → Webhooks → the endpoint. The docs don't give the exact Overview labels | enabled yes/no; the event list, and specifically **is `payment_intent.canceled` there?** Expected set (11): `payment_intent.succeeded/.payment_failed/.canceled`, `charge.refunded`, `charge.dispute.created/.closed`, `account.updated`, `transfer.created/.reversed`, `payout.paid/.failed` | V3; whether E1/V6 can prove delivery |
| G4 | **Secret digests, compared locally.** (1) Supabase Dashboard → project `hqycwntpfoztoinemqns` → Edge Functions → **Secrets**: note the **Digest SHA256** of `STRIPE_SECRET_KEY` and `STRIPE_WEBHOOK_SECRET` (the same value `supabase secrets list` prints). (2) Stripe **Live** → `dashboard.stripe.com/apikeys` → Standard keys → **Reveal live key**. Only Stripe-created keys can be revealed; if yours cannot, say so and use E2 instead, **never rotate for this**. In your own terminal: `printf %s '<paste>' \| shasum -a 256`, then clear the clipboard. (3) The same for the signing secret: G3's endpoint → **Reveal secret** (the docs also say "Click to reveal"). Note that Supabase's docs don't state the digest is a plain SHA-256 of the value: a **match** is conclusive, a mismatch is inconclusive | "match: yes/no" ×2, or "not revealable" | V2 (server key live and of the build's account) |
| G5 | **Apple Pay certificate.** Apple Developer → Certificates, Identifiers & Profiles → **Identifiers** → top-right filter **Merchant IDs** → `merchant.com.snatchit` → **Apple Pay Payment Processing Certificate**: status and expiry (valid 25 months). Then Stripe **Live** → `dashboard.stripe.com/settings/ios_certificates` (a support article gives `…/settings/payments/apple_pay` for the same page): the certificate is listed. **Stripe does not show expiry.** If renewal is ever needed: new CSR from Stripe → Apple → upload the `.cer` to Stripe **before** Activate at Apple. Not authorised here | expiry date; listed in Stripe yes/no | any Apple Pay line in the review notes (V4) |
| G6 | **Review inventory**, per `REVIEW_INVENTORY_PLAN_V3_20260924.md`: three listings the owner creates **in the app** as the demo seller after G2 (R-BUY-1/2 at $2 → $2.20, R-BID at $1, 48 h each, re-created at about 40 h if review hasn't started). Decide the $300 listing `c8d04339…` ((a) cancel it and its $330 intent, or (b) leave it) and **P5** (auto-expiry refund vs manual Dashboard refund of any reviewer purchase) | the two decisions; later, "created" | the review-notes navigation; no reviewer lands on a $330 charge |
| G7 | **Reviewer access.** Both passwords are burned (`HISTORY_EXPOSURE_MEMO.md`). **After G2**, on the production candidate: Login → "Use email instead" → email → **Forgot password?** → open the link in that Gmail inbox on the same phone → set a new password (the reset screen signs out all devices). Do this for `snatchitreviewbuyer@gmail.com` and `snatchitreviewseller@gmail.com`, and keep the new passwords only in your password manager. Then App Store Connect → Apps → Snatch It → the version → **App Review Information** → **Sign-in required** → User name / Password (buyer) → **Save**. A sandbox build cannot do this, because the link targets `snatchit://` and a sandbox build talks to the sandbox project | "rotated ×2; sign-in OK ×2" | review-notes credentials |
| G9 | **Policies P1** (review times) **and P3** (removal/suspension): the app states both today | the chosen promise, or "remove" | C aligns the in-app copy; the review-notes safety line |
| G10 | Rule on D's production reads that this checklist cites as **[D-PROD]** (for example the `stripe_livemode` split and the newest-payment date): ratify, or record them as an unauthorised source. **Still open:** the owner's 2026-09-24 rulings cover D's *witness* reads for the #92 (`05c4f5fa`) and 149 (`dddb93a7`) packages; the #92 ruling's record says it "grants no further production reads"; no ruling on these review reads is recorded | the ruling | which figures the checklist may cite |

### B. Required operational gates before release (not App Store review items)

| # | What | Bring back | Unblocks |
|---|---|---|---|
| R1 | **PR #92 production execution: EXECUTED 2026-09-24** (apply 16:55:40Z, deploy v41 16:57:01Z, run check PASS 17:03:42Z; package §13). **#92 merged into the gate 18:12:19Z (`374103c0`), #93 at 18:15:58Z (`037092f0`); 149 + `confirm-and-release` v38 executed 20:31Z** (#93 package §12; A and D PASS) | done: (A)+(B) at `05c4f5fa`; the merge (C); A-149 at `dddb93a7` | seller-win payouts with holds respected; a truthful seller notice (server side live) |
| R2 | Policies **P2** (who handles disputes and reports), **P4** (refund policy), **P5** (App Review purchase refunds; also G6), **P6** (when to resolve the 5 open disputes; R1 done) | decisions | the operating process behind the promises |
| R3 | **Twilio auto-recharge:** `console.twilio.com/us1/billing/manage-billing/billing-overview` → **Enable auto recharge** → Auto Recharge "Enabled" → **Recharge Balance To** / **When Balance Falls Below** (minimum trigger $10) → Select Payment Method → **Save** (today: OFF). The help article is tagged "legacy Console", so use the direct URL | on/off, amounts | signup OTPs keep working when the balance runs out |

### C. Optional additional evidence (each needs its own permission; none is requested here)

| # | What | Residual it closes |
|---|---|---|
| E1 | V6a: cancel the stale **$2.20** live intent: `stripe payment_intents cancel pi_… -d cancellation_reason=abandoned --live` (the Dashboard may not offer Cancel for `requires_payment_method`) | live webhook subscription, signature and handler v42, with no new charge (needs G3) |
| E2 | V6: one non-charging production checkout visit + cancel | server key mode and account (the alternative to G4) |
| E3 | V7: one $2.20 live purchase + refund | settlement and refund recording on the new code |
| E4 | Stripe read of the two live `refunded` rows of 2026-08-04 | only if refund wording is ever added |
| E5 | A first real payout through the attempt-based executor | its first production run (R1's first seller-win may be this) |
| E6 | F-LISTING-CRITICAL-TIER-1: server-side refusal of the critical tier | a server-enforced listing restriction |
| E7 | Supabase Dashboard → Authentication → **Sign In / Providers** → **Phone** → **Test Phone Numbers and OTPs** (format `18005550123=789012`, no `+`) and **Test OTPs Valid Until** (required; past that date the number stops working). Sign-in needs no SMS, so this only matters if the notes mention the number | the review-notes phone line (omitted unless confirmed) |
| E8 | D's read-only sandbox witness of the phone session's T0 and cleanup reads. This was the sheet's 7th tick box and is not in the D1–D6 approval. A's captures are files with md5 that D can check without sandbox access | independent witness |

### D. Housekeeping (no gate)

- H1: redact the plaintext password in `docs/product/LAUNCH_PLAN.md` (lines 623, 624, 665, 670, 776, 777) in a docs-only
  PR. It stays in git history, so treat it as burned too. A can prepare the PR on request.
- H2: about 60 stale local `*_rehears` / `snatchit_*` databases (D's note; about 11 GiB free).
- H3: ~~F-CR-148-SHARED~~ **CLOSED 2026-09-24.** The closure rests on **two** source changes, both at `037092f0` and both in the v38 bundle. That bundle was byte-verified 5/5 by A and independently by D's own download (W2); `confirm-and-release` v38 was deployed at 20:31:30Z.
  - **#92's `_shared/payouts.ts:319`** (`e2205bbb`) adds `PAYOUT_HELD` and `PAYOUT_UNDER_REVIEW` to `PAYOUT_NOT_ELIGIBLE_REASONS`, so a held seller-win reaches `not_eligible` → `payoutDeferred` instead of `db_error`.
  - **#93's `confirm-and-release/index.ts:347-348`** (`buyerConfirmed = Boolean(buyer_confirmed_at)`, `basisCode`), **`:381`/`:383`** (`payoutDeferred`) and **`:425`/`:435`** (the release audit) make the rows it writes truthful.
  - #93 did not touch `payouts.ts` (D, E and A each verified this).
  - These paths are not yet exercised in production.
- H4: the synthetic ops case `650e7344` awaits a console dismissal.

**Prepared by A without these answers:** the draft review notes, the fixture sheet, PR #92 and its production package,
the inventory plan, and this checklist. **Verdict unchanged: not submission-ready.**
