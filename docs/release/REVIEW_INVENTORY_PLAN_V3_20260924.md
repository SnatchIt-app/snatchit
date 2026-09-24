# App Review inventory and reviewer access — V3 plan (A, 2026-09-24)

**Status: PLAN ONLY. Nothing here is authorised or created.** Creating listings, rotating credentials, cancelling
intents and any production read each need the owner's own instruction. The plan uses **no SQL and no guard bypass**:
every production write it proposes is made by the owner through the app, on the production candidate build (G2).
Source refs: server = the deployed gate `5b255838`; client = `404bce38` (Build 24's commit). File:line citations come
from a read-only trace of those refs on 2026-09-24.

## 1. What the reviewer must be able to do, and what that requires

| Reviewer action | Requirement | Source |
|---|---|---|
| Sign in with no SMS | email + password is available: Login → "Use email instead". Phone sign-in never creates an account | `login.tsx:14-17,146,219-220`; `phoneAuth.ts:29` |
| Browse, bid, buy | **no phone gate for buyers** ("Browsing, bidding, and buying are NOT gated") | migration `038:12`; `070:23-24` |
| See the listings | Home shows `status='active'` and hides rows whose `ends_at` has passed. Search requires `auction_status='active'` | `home.tsx:221,345,357`; `explore.tsx:133-134` |
| Buy Now | `buy_now_enabled` plus a price; not sold, cancelled, ended, past its clock, or reserved by someone else. The server hold lasts 10 min | `detailState.ts:153-168`; `20260906100000:302-341` |
| Pay | whole-listing price plus a 10% buyer fee: **$2 → 220¢ charged**; the seller nets 180¢ | `_shared/money.ts:37-57`; `create-payment-intent:718-722` |
| Create a listing (seller demo) | a verified phone **and** `profiles.stripe_onboarding_complete` (details submitted, charges enabled, payouts enabled), enforced by RLS; not risk-blocked | `070:36-39`; `038:17-29`; `119:88-100`; `stripe-webhook:878-892` |

**The binding constraint: a listing can live for at most 48 hours through the app.** Duration must be 1/3/6/12/24/48 h
(`000:88`), and `ends_at` is set to now + duration. The app cannot extend `ends_at`: edit is limited to name, venue,
restrictions and platform, with 0 bids (`edit/[id].tsx:89-129`). The July/August inventory was kept alive with
guard-bypass SQL; this plan does not do that.

## 2. Accounts

- **Buyer:** `snatchitreviewbuyer@gmail.com`. This was the ASC sign-in in July and August (`APP_STORE_METADATA.md:65`).
- **Seller:** `snatchitreviewseller@gmail.com`, user id `09f1ec06-…` (`app-review-response-2026-07-21.md:71`).
  Memory records it as phone-verified and "fully live-onboarded" on 2026-08-04. **Not re-verified since.**
- **Both passwords are burned.** They were in public git history, and `HISTORY_EXPOSURE_MEMO.md:47-52` says "must be
  treated as burned", with rotation still OPEN. `seed-demo.ts:46-47` says they are "rotated out of band", but no record
  shows a rotation happened.
- **A separate plaintext password is still in the working tree**, in `docs/product/LAUNCH_PLAN.md` at lines 623, 624,
  665, 670, 776 and 777. It belongs to an older test-mode plan (`review-buyer@` / `review-seller@snatchitapp.com`) and
  differs from the exposed demo password. It must not be reused anywhere, and it should be redacted from the file by a
  separate docs change. It stays in history either way.

## 3. Inventory: three listings, created by the owner in the app as the demo seller

| Listing | Starting bid | Buy Now | All-in | Duration | Purpose |
|---|---|---|---|---|---|
| R-BUY-1 | $1 | $2 | **$2.20** | 48 h | the purchase path (card / Apple Pay sheet) |
| R-BUY-2 | $1 | $2 | $2.20 | 48 h | a spare, so one reviewer bid or hold does not block the purchase path |
| R-BID | $1 | — (off) | — | 48 h | the bid path. A bid is never charged; the client's next bid is +$5 |

- **Content:** real upcoming events and genuine ticket images the owner holds, or can deliver, with a cover image and
  a proof image (both required, `000:98`, `sellState.ts:102-104`). Quantity 1. Photo and title in the owner's words.
  No approval step gates visibility; `proof_status` only drives a badge.
- **Timing:** create them immediately before "Add for Review". If the review has not started about 40 h later, the
  owner cancels and re-creates them in the app: seller → My listings → Cancel; `cancel_listing` is allowed at any time
  unless sold (`0590:41-61`). The review-notes navigation therefore names the listings by title, not by id.
- **A reviewer's bid on R-BID must never win.** After review, the owner cancels R-BID in the app before it ends. A
  cancelled listing settles as unfulfillable.
- **A reviewer's purchase (P5 decides; both paths are safe by source):**
  - **Automatic path:** the owner, as seller, does not mark it sent. After 24 h, `enforce-transfer-expiry` expires the
    transfer and refunds in full through Stripe. This would be the first confirmed production run of the expiry refund,
    which the claims table cannot yet assert.
  - **Manual path:** refund in the Stripe Dashboard (live) → Payments → the payment → Refund. The webhook records it
    through `record_payment_refund`, and the expiry job then skips the payment, because it is already refunded by its
    money facts (`enforce-transfer-expiry:209-213`, idempotency layers 2 and 3).
- **Payout on a completed test sale:** none. With no sent transfer there is no payout.

## 4. The existing $300 listing and the stale live intents (owner decisions)

- **`c8d04339-bb33-4bf3-945d-d23d7dd269ca`** (III Points Saturday GA, Buy Now $300, ends 2026-10-18) is today the only
  active listing, and it carries an uncancelled pending live **$330** intent of 2026-09-03 [D-PROD 05:19Z, as of that read; checklist §9 R4].
  - Whose listing it is is **not in any record**. `STRIPE_NETWORK_TIMEOUT_REPORT.md:3-10` records the owner tapping
    "Pay $330" on their own iPhone on 2026-09-04, which suggests the intent is the owner's own attempt. Unconfirmed.
  - (a) If it is the owner's own or a test listing: cancel it in the app as its seller, and cancel the $330 intent (§5).
  - (b) If it belongs to a real user: leave it. A reviewer could then buy it for $330, and P5 covers that. The review
    notes point to the R-listings by title.
  - Settling this takes the owner's knowledge, or one authorised read of its `seller_id`.
- **Stale pending live intents:** $2.20 (2026-08-06), $88 (2026-08-05, auction) and $330 (above). Cancelling any of them
  is E1/V6a evidence, and each needs the owner's instruction.

## 5. Cancelling a PaymentIntent: correction to earlier instructions

Stripe's docs say the Dashboard can cancel a payment only when it is uncaptured (`requires_capture`). An intent whose
sheet was opened but never paid is `requires_payment_method`. **For those, the Dashboard may offer no Cancel, and the
Stripe CLI (or API) is the reliable route** (docs.stripe.com/refunds#cancel-payment; /api/payment_intents/cancel).
This covers the sandbox W2 intent, the $2.20, $88 and $330 live intents, and V6.

```bash
stripe payment_intents cancel pi_REPLACE_WITH_ID -d cancellation_reason=abandoned
```

- For **live** intents, add `--live`. The CLI must be logged in to the live account (`stripe login`, then
  `stripe login list` to confirm a live context).
- The output must show `"status": "canceled"`.
- `-d cancellation_reason=abandoned` is the documented form. The fixture sheet's `--cancellation-reason=abandoned` is
  an inferred spelling.
- If the Dashboard *does* offer Cancel for the intent, it is equally valid; the result must read **Canceled**.

## 6. Order of operations (after G2 exists)

1. G7: rotate both reviewer passwords (checklist §8 has the steps), then sign in to both on the candidate.
2. G6 decisions: §4 (a) or (b); P5.
3. Owner, in the app as the demo seller: create R-BUY-1, R-BUY-2 and R-BID. **This is production inventory, and the
   owner's instruction to create it is the authorisation.**
4. A, with an authorised read: confirm each listing is `active`/`active`, its `ends_at`, the Buy Now figures, the
   seller's `stripe_onboarding_complete`, and that nothing else is reserved.
5. A fills the review-notes placeholders (`APP_STORE_REVIEW_NOTES_V3_DRAFT_20260924.md`). The owner pastes them into
   App Store Connect and submits. A never submits.
6. During review: re-create at about 40 h if the review has not started.
7. After review: cancel R-BID and any unsold R-BUY, handle any purchase per P5, and record everything.
