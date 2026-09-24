# App Store submission checklist — V3 production candidate (A, 2026-09-24; DRAFT under D's review)

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
- **The server code deployed 2026-09-23:** `create-payment-intent` v48, `confirm-payment` v37, `confirm-and-release`
  v37, `enforce-transfer-expiry` v40, `stripe-webhook` v42. No live payment has run through them; the newest payment
  of any kind is 2026-09-03 [D-PROD].
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

**Residual gap that only a real transaction closes, with the exact bounded proposal.**
- **Not provable without money:** settlement (`payment_intent.succeeded` → settlement → transfer row) on v42/v48; an
  Apple Pay authorisation; refund recording on the new code (`charge.refunded` handler); the payout executor deployed
  2026-09-23, which has never run in production; the post-purchase notifications.
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
| Review notes: "Reports are reviewed within 24 hours" | **omit** | nothing enforces 24 h; disputes get a 72 h case due date, reports none [SRC 115:147, 117:402,523]; alerts undelivered. **The app itself says 24 h** in three places (`report/[type]/[id].tsx:74`, `settings/privacy.tsx:137`, `transferState.ts:182`), and "may remove content or suspend accounts" (`report/[type]/[id].tsx:88`) although no listing-takedown or account-suspension action exists [SRC 144:480-484,830-876]. In-app copy is C's lane; the promise is the owner's policy (§5b) |
| Review notes: "unresolved or disputed orders are refunded per policy" | **omit** | expiry refund code exists (enforce-transfer-expiry Phase 1) but no end-to-end expiry has been confirmed in production [REC SPRINT_STATUS:1258]; a buyer-win dispute records `refund_required` only, and executing it needs the disabled refund executor or a manual Stripe Dashboard refund [SRC 065:130-141, 144:889-914; REC SPRINT_STATUS:1285] |
| Review notes: "if a purchase is completed, we monitor and refund" | **omit as written**; replace only with an owner commitment (§5b) | refunds are manual (Dashboard); no alert reaches an operator |
| Review notes: "Build 13 is the current binary"; "$2 / $2.20"; "active through late August 2026"; "current bid $1" | **replace** | the V3 build number, prices and dates come from V5 and the owner's inventory plan; none exist yet |
| Review notes: button labels "Buy · $X" / "Pay · $X" | **replace** with V3 labels: listing "Buy now · $X" (quantity 1), checkout "Pay $X" | [SRC] `detailState.ts:348-352`, `payControl.ts:90` |
| Review notes: Apple Pay via PaymentSheet, merchant `merchant.com.snatchit` | **keep, after V4** | [SRC] `app.json:73`; certificate [OWNER] |
| Review notes: test phone number +1 800 555 0123 / 789012 | **keep only after the owner confirms** it is still configured in Supabase Auth | [OWNER] |
| Review notes: Settings → Delete Account | **keep**, without "double confirmation" | [SRC] `app/settings/index.tsx:207-210` |
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

## 5. Owner actions (all together)

| # | Action | Why | When |
|---|---|---|---|
| O1 | Decide D1–D6 and D's witness reads on the fixture sheet (`SANDBOX_V3_FIXTURE_APPROVAL_SHEET_20260924.md`, rev 2 `28d3cdb1`) | the phone session needs them | before the phone session |
| O2 | V2/V3: compare the `STRIPE_SECRET_KEY` and `STRIPE_WEBHOOK_SECRET` digests with the live Dashboard values, locally; read the live webhook endpoint's URL, status and event list, and **whether `payment_intent.canceled` is subscribed** (recorded as an open owner decision, `PRODUCTION_RELEASE_PACKAGE.md:177`) | server-side mode, account and webhook cannot be proven from source | before any production-candidate check |
| O3 | V4: confirm the Apple Pay certificate for `merchant.com.snatchit` in live Stripe | Apple Pay reachability | before submission |
| O4 | Confirm the reviewer accounts still exist and their credentials still sign in; the credentials were treated as exposed and rotation is still OPEN [REC `HISTORY_EXPOSURE_MEMO.md:3,48-50`] | review login | before inventory planning |
| O5 | Confirm the Supabase Auth test phone number is still configured, and Twilio auto-recharge (OFF, [REC `PHONE_OTP_DELIVERY_CONFIGURATION_REPORT.md:380`]) | signup OTP for reviewers and real users | before submission |
| O6 | Read the two live `refunded` rows of 2026-08-04 in the Stripe Dashboard: refund or lost dispute, and the amount | the refund record is ambiguous (§4) | before any refund wording |
| O8 | Plan **low-priced** review inventory that a reviewer can exercise without a real $330 charge and a manual refund: listings, prices, end dates, seller. Decide the $300 III Points listing `c8d04339…`, which already carries an uncancelled pending live $330 intent from 2026-09-03 [D-PROD] | a reviewer currently sees one listing, at $300, already encumbered | before submission |
| O7 | Later decisions, not requested yet: V6 (non-charging production checkout plus cancel) and V7 (one $2.20 live purchase plus Dashboard refund); review inventory | each creates production state | after O2–O5 |

## 5b. Owner operating-policy decisions (separate from the actions)

- **P1 — review and response times.** The app promises report review "within 24 hours" in three places, dispute
  review "typically within 24 hours", and support email replies "within 1 to 2 business days". No process or alert
  backs any of them. Choose the promise, or remove it; C then aligns the in-app copy.
- **P2 — who handles disputes and reports, and how they learn of them.** Operator alerts are off, admin push reaches
  no active token, and email is off. The console shows cases only when someone looks.
- **P3 — content removal and suspension.** The app says the team "may remove content or suspend accounts". The
  console has no listing takedown and no suspension; it has only `user_restrict`, which blocks new listings. Either
  build the mechanism or remove the promise.
- **P4 — refunds.** State the refund policy the operation can honour today: manual Dashboard refunds, and expiry
  refunds by the cron once confirmed in production.
- **P5 — refunds of App Review purchases.** Decide whether to commit to refunding any purchase a reviewer completes,
  and who does it.
- **P6 — seller-win disputes.** Until F-DISPUTE-SELLERWIN-1 is fixed, such a payout needs a manual Stripe transfer
  outside the app. Decide who does it, or hold seller-win resolutions until the fix ships.

## 6. Readiness verdict

**Not submission-ready.** Required and not done:
- **Production inventory, the hardest blocker:** 113 listings, **exactly 1** active and unexpired: III Points Saturday
  GA, ends 2026-10-18, Buy Now **$300** (so a reviewer could complete a $330 charge). 66 more are active with an end
  time already past [D-PROD]. A reviewer today sees one purchasable item. Owner action O8;
- the V3 production candidate build (none exists; every build since 13 is a sandbox preview);
- O2–O5;
- inventory planning;
- the claims rewrite approved;
- the phone-session evidence for the expired and held cells;
- appearance evidence measured by **screen**, not by token count. C found three transfer-flow components (DeliveryInfoForm, PlatformInstructions, ProofImageViewer) still on the pre-v2 `colors` module, which a token-based inventory missed; they are migrated at `9c6c9bf4`, and a test now forbids that import [C's report];
- the residual live-transaction gap (§3) decided.

The draft review notes and metadata are in `APP_STORE_REVIEW_NOTES_V3_DRAFT_20260924.md`.
