# RC3 canonical policy wording (A, 2026-10-13)

**One source for every surface.**
- C applies the app rows (§3).
- G applies the website rows (§4), in a PR only; publishing is the owner's.
- The web app rows (§5) are a prepared follow-up: their deploy is a separate production change, and F's web redesign
  keeps today's web wording until the owner rules.

Owner direction (2026-10-13), applied here:
- fees name the sale price as their base;
- a buyer-confirmed payout is kept apart from the automatic release;
- no unconditional 72-hour payout;
- refund initiation, processor status and bank receipt are separated;
- the non-delivery refund is described precisely, including pending or failed refunds;
- the claim-review turnaround promise is removed.

Nothing here adds coverage, exclusions or a service commitment.

## 1. Verified code facts (at `e2b9498b`; unchanged by 152)

| # | Fact | Source |
|---|---|---|
| C1 | **Resale fees** (Buy Now and auction alike): the base is the sale price, i.e. the Buy Now price or the winning bid, for the whole listing. The buyer pays 10% of the base on top; 10% of the base is withheld from the seller's payout. Card charge = base + 10%. | `supabase/functions/_shared/money.ts:12-16,28`; `create-payment-intent/index.ts:711-721` (both modes) |
| C2 | Venue (primary) ticket fees are set per event and returned by `primary-checkout`. No percentage is fixed in code, and no consumer screen sells primary tickets today. | `primary-checkout/index.ts:548-570`; no caller in `app/`, `src/` |
| C3 | **Buyer confirms receipt:** `confirm-and-release` attempts the Stripe transfer to the seller at once, with no risk check (`payout_risk_tier` is read but unused). If the payout cannot be made (for example, the seller's payout account cannot receive it), it is recorded for operator review and the buyer still sees the confirmation. | `confirm-and-release/index.ts:324-400` |
| C4 | **Automatic release:** 72 h after the seller marks the tickets sent with no confirmation or report, the order becomes eligible. Release is risk-gated: low releases; medium is held to an event-relative point (capped at about 7 days, then manual review); high needs an operator. | 039 / 117 / `payout-execute` (A, verified 2026-10-12) |
| C5 | **Bank arrival** of a payout follows the seller's Stripe payout schedule. | Stripe Connect; draft §D 6.4 |
| C6 | **Non-delivery:** a transfer still pending 24 h after the payment settles is expired by `enforce-transfer-expiry` (every 2 min) and an amount-less Stripe refund is issued: the full amount still held, including the service fee. | `20260906100000:142,168` (`expires_at = now() + 24h`); `enforce-transfer-expiry/index.ts:580-711` |
| C7 | A refund's processor state is recorded and can be pending or failed. The app does not show a failed refund to the buyer (D-RC-3). | 150 (`payment_refund_state`); `settledRead.ts:42` |
| C8 | Stripe's own guidance: a card refund appears "approximately 5-10 business days later, depending upon the bank"; a failed refund can take up to 30 days to return. | docs.stripe.com/refunds ("Trace a refund"), read 2026-10-13 |
| C9 | Refunds other than the expiry refund (claims, disputes) are manual: an operator issues them in Stripe after review. Console refund execution is off by default. | `ops.setting refund_execute_enabled = false`; `ops.action_dispatch` |
| C10 | Reports freeze the seller's payout; they never expire on their own. Nothing enforces a review time. | transfers dispute path; POLICY_PROMISES §1 items 1, 2, 6, 7 |

## 2. Canonical sentences

**Fees (resale only; never state a percentage for venue tickets):**
- **F1** "Buyers pay a service fee of 10% of the sale price (the Buy Now price or the winning bid, for the whole listing). It is added to the total at checkout and shown before you confirm."
- **F2** "Sellers pay a marketplace fee of 10% of the same sale price, deducted from the payout."
- **F3** "Your payout is the sale price minus the 10% marketplace fee and minus any refund."

**Payouts:**
- **P1** "When the buyer confirms they received the tickets, Snatch It starts the seller's payout straight away. If the payout can't be made at that moment, for example because the seller's payout account isn't ready, it waits for review by our team."
- **P2** "If the buyer neither confirms nor reports a problem within 72 hours after the seller marks the tickets as sent, the order becomes eligible for release. Snatch It runs risk checks first: depending on the order, the payout is released, held until after the event, or held for manual review."
- **P3** "Once a payout is sent, when it reaches the seller's bank depends on Stripe's payout schedule and the bank. Snatch It doesn't guarantee a date."
- **P4** (unchanged, verified) "Reporting a problem freezes the seller's payout while we review."

**Refunds:**
- **R1** "If the seller doesn't mark the tickets as sent within 24 hours after your payment goes through, the order is cancelled automatically and a full refund of what you paid, including the service fee, is issued to your original payment method."
- **R2** "Issuing a refund starts it with our payment processor, Stripe. It can show as pending for a while, and in rare cases a refund fails. Once it completes, how long it takes to appear depends on your bank or card issuer, typically 5 to 10 business days."
- **R3** "If a refund hasn't appeared after 10 business days, contact support@snatchitapp.com."

**Claims (replaces the turnaround promise; no time is promised):**
- **X1** "We review the claim and you'll see the outcome on your order in the app."

**Blocking and suspension (true only once 152 is applied in production):**
- **K1** (block confirmation) "You won't see their listings in Home or Search, and neither of you will be able to bid on or buy the other's listings. Orders you already have together aren't affected, and you can still report them."
- **K2** (server refusals; the server's own sentences):
  - `BLOCKED_PARTY`: "This listing isn't available to you."
  - `LISTING_UNAVAILABLE`: "This listing isn't available right now."
  - `ACCOUNT_SUSPENDED`: "Your account is suspended, so you can't bid, buy or create listings. Orders you already have aren't affected. Contact support@snatchitapp.com."
  - `PROHIBITED_CONTENT`: 'Listings can't mention "<term>". Please revise your event name, venue, or restrictions and try again.'
- **K3** (operator, console) "Suspend account: stops new bids, Buy Now and listings by this person, and new bids and Buy Now on their listings. Orders that already exist, refunds, payouts and reports continue, and they can still sign in."

## 3. App (C), `app/settings/legal.tsx` and the block copy

| Where (at `e2b9498b`) | Today | Replace with |
|---|---|---|
| `legal.tsx:83-84` and `:202-206` ("transactions are final" / "does not guarantee refunds") | no exception stated | keep the sentences and add R1 + R2 + R3 right after |
| `legal.tsx:87-91` and `:214-216` ("…until the buyer confirms receipt … (or the auto-release window expires), at which point the seller's net payout is released") | unconditional auto-release | "Payment funds are held by Stripe on Snatch It's behalf until the order is released. " + P1 + P2 + P3 |
| `legal.tsx:94-96` and `:211-213` (fee sentence, no base) | no base | F1 + F2 (keep "Snatch It reserves the right to modify fee structures with reasonable notice.") |
| block confirmation (listing detail, profile; plus the two order screens, S5) | "Their listings will be hidden from your feed." | K1 |
| bid, Buy Now, create, edit error paths | generic or raw | map the four K2 hints; no "Try again" for `BLOCKED_PARTY` or `ACCOUNT_SUSPENDED` |

## 4. Website (G), as published on `origin/main`

| Row | Where | Replace with |
|---|---|---|
| T1 | /terms §13 bullet 5 | P2, reworded for the buyer: "…the order becomes eligible for release to the seller; Snatch It runs risk checks first and may release it, hold it until after the event, or hold it for manual review." |
| T2 | /terms §15 bullet 5, §20 last sentence | "Confirming receipt starts the seller's payout. If you neither confirm nor report a problem within the 72-hour window, the order becomes eligible for release after Snatch It's risk checks." |
| T3 | /terms §19 bullet 3 | P1 + P2 + P3 (seller voice). **G's earlier wording applied the risk hold to buyer confirmation; that is wrong (C3).** |
| T4 | /terms §17 bullets 1-2, §19 bullet 2 | F1, F2, F3 |
| T5 | /terms §13 b4, §16 b3, §17 b3, §20 s2; /buyer-guarantee coverage b1, FAQ "never transfers" | R1, keeping each page's voice; add R2 once per page |
| B1 | /buyer-guarantee step 5, FAQ "How long does a refund take" | R2 + R3 |
| B2 | /buyer-guarantee step 4 "Our goal is to review most claims within a few business days; complex claims can take longer." | **remove**; use X1 |
| M1 | `components/faq.tsx:32-33`, `trust-safety.tsx:11`, `json-ld.tsx:66`, `why-snatch-it.tsx:12`, `investors/page.tsx:109,304`, `lib/journal.ts` entries | short form: "The seller isn't paid until you confirm your tickets arrived, or until the 72-hour window passes and the order clears Snatch It's risk checks." Refund short form: "If the seller doesn't send within 24 hours, the order is cancelled and a full refund is issued automatically." Drop "with no human involved" and "instantly". |
| M2 | `investors/page.tsx:278-279` "a 20% gross take on every transaction" | limit it to resale: "…on every resale transaction". Venue fees vary (C2). |

## 5. Web app (prepared follow-up; not in RC3)

| Where (`web/src` at `e2b9498b`) | Today | Replace with |
|---|---|---|
| `app/listing/[id]/page.tsx:263-264` | "If the seller doesn't transfer within 24 hours, you're refunded in full, automatically." | R1 short form (§4 M1) |
| `app/listing/[id]/page.tsx:242,259` | "Seller is paid only after you confirm…" / "held … until you confirm" | M1 payout short form |
| `components/account/PayoutSetup.tsx:27` | "Payouts are deposited automatically when your listings sell." | the app's own `payout-setup.tsx:162` sentence |
| `app/page.tsx:122-123`, `app/sell/page.tsx:71-72` | "You keep 90% of the sale, paid out … once the buyer confirms" | "You keep 90% of the sale price. Your payout starts when the buyer confirms, or after the 72-hour window and Snatch It's risk checks." |
| `components/transfer/BuyerTransferPanel.tsx:187` | "…notifies support." | "This freezes the seller's payout and opens a case for our team." (the app's wording, `app/transfer/receive/[id].tsx:397` at RC5 `1e491ac4`; corrected 2026-10-13, was "freezes the transfer") |
| `components/transfer/SellerTransferPanel.tsx:85` | "…the buyer is refunded automatically." | "…the order is cancelled and the buyer's refund is issued automatically." |

## 6. Buyer Guarantee scope: one recommended proposal (owner decision)

**State of the record:**
- No owner decision on the scope is recorded in `docs/release/`.
- The live /buyer-guarantee page (marked "draft for attorney review" in its source) promises six coverage cases and ten
  exclusions.
- Only case 1 (non-delivery within 24 h) is automated (C6). Cases 2-6 (materially different ticket, event cancelled,
  denied admission for an invalid ticket, wrong recipient, fewer tickets) are honoured only by an operator's manual
  Stripe refund after review (C9).

**Recommendation:**
- **Keep the published coverage and exclusions unchanged.** Removing published rights silently is not allowed, and
  expanding them is not requested.
- Correct only the mechanics above (B1, B2, T5).
- Approve it with its operational implications stated:
  1. Every case 2-6 claim needs a person to review it and issue the refund in Stripe (the console's refund execution
     stays off).
  2. That person works `/reports` and `/cases` daily (owner item O-10). Without a named reviewer, the guarantee's
     promises are not operated.
  3. The 72-hour report window freezes the payout. Claims raised after release (denied admission at the door) can only
     be refunded from Snatch It's own balance, because the payout has gone; the Terms already say so (/terms §22 ¶2).
  4. Counsel review of both the Terms and the Guarantee remains open (both pages say "draft for attorney review").

**Exact approval text:** "Buyer Guarantee: keep the published scope; adopt the wording corrections; I accept the manual
review and refund duty, with <name> reviewing daily."

## 7. Two Terms documents (owner and counsel, not RC3-gating)

- The app shows Terms dated March 20, 2026 (`legal.tsx:3,59`). The website shows Terms "Effective July 14, 2026 ·
  Replaces the version dated March 20, 2026".
- This package aligns the sentences in §2 on both. Which document governs, and whether the app should link to the
  website version, is a decision for the owner and counsel.
