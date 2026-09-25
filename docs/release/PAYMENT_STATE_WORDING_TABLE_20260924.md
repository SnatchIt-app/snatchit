# Payment-state and wording table for the V3 order/transfer screens (A → C, 2026-09-24)

Owner instruction 2026-09-24: "Provide the evidence-backed payment-state and wording table for buyer expired, buyer reversed, seller reversed, and the review/automatic-release deadline. Distinguish order status, recorded refund amount and confirmed payout. State what the UI may truthfully say when evidence is missing."
**Revised 2026-09-24 ~21:30Z (A):** §2d and §2e carry the two seller rulings sent to C at 20:56Z; they supersede the earlier text of those cells. This table is the shared wording reference for C (implementation), B (rendering/gallery) and E (audit).

Every claim below is cited to the gate source at `5b255838` (migrations under `supabase/migrations/`, edges under `supabase/functions/`), which is what production runs as of 2026-09-23 23:22Z (ledger 160; ten functions deployed). Since 2026-09-24 16:55Z production also runs 148 and `enforce-transfer-expiry` v41 from #92; what they change is in `PR92_PRODUCTION_EXECUTION_PACKAGE_20260924.md` §3 E-2 to E-4. Nothing here is inferred from the client.

## 1. The three facts are three different rows/columns — never derive one from another

| Fact | Where it lives | Who writes it | What it means | What it does NOT mean |
|---|---|---|---|---|
| **Order (delivery) status** | `public.transfers.status` — `pending` → `seller_sent` → `buyer_confirmed` / `auto_released` / `disputed` / `expired` / `reversed` (0550 guards every state column; only RPCs write them, 0550:139) | `mark_transfer_sent` (008:100–103: sets `seller_sent`, `seller_sent_at`, `auto_release_at = now()+72h`); `confirm_transfer_received` (`buyer_confirmed`, via confirm-and-release index.ts:197); 039 `apply_auto_release` (:220/:298 `auto_released`), `apply_payout_hold` (:242–243 `payout_review_status='held'`, `payout_hold_until`), `apply_manual_review` (:265 `'manual_review'`); `buyer_dispute_transfer` (`disputed`, `disputed_at`); `enforce_transfer_expiry` (0551:23–27: `pending` past `expires_at` → `expired`, `expired_at=now()`); `mark_transfer_reversed` (0561:114–132: `status='reversed'` where `stripe_transfer_id` matches, called by stripe-webhook v42 on `transfer.reversed`, index.ts:810–817) | the delivery lifecycle and the payout DECISION | that any money moved. `auto_released`/`buyer_confirmed` are decisions; `reversed` sets status ONLY — `payout_released_at` and `stripe_transfer_id` are NOT cleared (0561:132–135 updates one column) |
| **Charge status** | `public.payments.status` — `succeeded` / `refunded` / `failed` / `canceled` (+ `pending`, `processing`) | stripe-webhook, confirm-payment, settle path; refunds through `record_payment_refund` | whether the charge succeeded, and — for `refunded` — that the recorded refunded amount reached the total (20260906120000:515–522) | that a partial refund happened (a partial leaves `succeeded`) |
| **Recorded refund amount** | `payments.amount_refunded_cents` (142; 20260906120000:306), `payments.refunded_at`, `payments.stripe_refund_id` (007) | `record_payment_refund`: amount is non-decreasing and bounded by `total` (20260906120000:425–427); `refunded_at` is stamped only when the amount reaches `total` (:522); a lost dispute (chargeback) is recorded through the same verb with a NULL refund id (stripe-webhook v42 index.ts:661–663); the OLD writer (pre-release) set `status='refunded'` + `refunded_at` on ANY charge.refunded, partial or full, and recorded no amount (142 header) | `amount_refunded_cents` = the money the buyer has been given back, when known | **NULL = unknown, NEVER "fully refunded"** (142 header: "The client must read NULL as amount unknown"); rows refunded before this release can read `status='refunded'`, `refunded_at` set, amount NULL — possibly partial |
| **Confirmed payout** | `transfers.payout_released_at` + `transfers.stripe_transfer_id` | ONLY `record_transfer_payout` (0564:59–60), after the Stripe transfer succeeded; refuses disputed rows (0564 header) | the seller's money actually moved (once) | that it is still with the seller: a later `status='reversed'` means Stripe reversed that transfer (0561; webhook v42:810–817); `payout_released_at` stays set as history |

Readable by the client: `transfers` rows where the user is buyer or seller (070:69–73) — all columns, table-level SELECT (no column grants on transfers); `payments` rows where the user is buyer or seller (000:1021/1027) — table-level SELECT, so `status`, `total`, `amount_refunded_cents`, `refunded_at` are readable (D's finding (iii): new payment columns inherit that SELECT).

## 2. The four cells the owner asked for

Notation: **Order** = `transfers.status`; **Refund** = `payments.amount_refunded_cents` / `refunded_at` / `status`; **Payout** = `transfers.payout_released_at` (+ `status <> 'reversed'`).

### 2a. Buyer, transfer `expired`
- **Server facts:** `status='expired'`, `expired_at` set (0551:27) because the seller never marked sent before `expires_at` (0551:23; the window is the value in `transfers.expires_at`, written at creation by `ensure_transfer_exists` 061:109 — read it from the row, do not assume a constant; 039 header line 26 calls it "the 24h unsent-transfer refund"). The refund is issued by the same cron run (enforce-transfer-expiry Phase 1, index.ts:517 onward) with an idempotent Stripe refund and recorded via `record_payment_refund` (fallback: `payments.status='refunded'`, `refunded_at`, `stripe_refund_id`, index.ts:482).
- **May say from `expired` alone:** "Order expired — the seller didn't send the tickets in time." and "A refund is due; it will show here once it's confirmed." (a stated policy, not an asserted fact).
- **SUPERSEDED 2026-09-24 by A's interim refund ruling (ruling 3, §2i):** today's columns cannot tell a requested
  refund from a completed one, so "Refunded $X" and "Partly refunded $X of $Y" are withdrawn. May say: "Refund of $X
  initiated" when `amount_refunded_cents = total`; "Partial refund of $X initiated" when `0 < amount_refunded_cents <
  total`; "Refund recorded" when `status='refunded'` or `refunded_at` is set but the amount is NULL. No timing.
- **Must not say:** "Refunded" on `expired` alone; any amount when the amount is NULL; "Payment refunded" for a refund the payment row does not show (product truth: "Payment refunded only for a confirmed refund").

### 2b. Seller, transfer `expired`
- **Server facts:** as 2a. Payout: `payout_released_at` NULL — no payout ever moved for an expired order (Phase 1 runs on `pending` rows; payout paths require `seller_sent`+).
- **May say:** existing `SELLER_ORDER_CLOSED_COPY.expired` (src/lib/transfer/transferState.ts:82): "Order expired — this order expired before it was marked as sent. Don't transfer the tickets for this order." Money line: "No payout for this order."
- **Must not say:** anything about the buyer's refund amount (the seller can read the payment row, but the refund is the buyer's fact; state at most "the buyer is being refunded" — a policy statement — never an amount).

### 2c. Buyer, transfer `reversed`
- **Server facts:** `reversed` means Stripe reversed the SELLER'S payout transfer (`transfer.reversed` → `mark_transfer_reversed`, v42 index.ts:810–817; 0561). It is reached after a payout had been recorded — typically the operator reversing a payout after a lost dispute (v42 index.ts:674: "Seller already paid? The transfer must be reversed by an operator"). The BUYER'S money position is NOT on the transfer row: a lost dispute is a chargeback recorded on `payments` through `record_payment_refund` (v42:661–663) — `amount_refunded_cents` grows, `refunded_at`/`status='refunded'` only when it reaches `total`. No column records the reversed amount on `public.transfers` (0561 writes status only).
- **May say:** the dispute outcome from the dispute record the buyer can read (024 `disputes`), and the refund/chargeback line from `payments` exactly as in 2a ("Refunded $X" only with a known amount equal to total; "Refund recorded" when the date/status exists without an amount; "Partly refunded $X of $Y").
- **Must not say:** "Reversed" as a buyer-facing money fact (it is the seller's payout event); "your money is back" from `reversed` alone.

### 2d. Seller, transfer `reversed`
- **Server facts:** `status='reversed'`; `payout_released_at` and `stripe_transfer_id` remain set (history), so the row LOOKS paid out unless status is checked first. The reversed amount is not stored (Stripe's `amount_reversed` is in the event only).
- **May say (RULING, A → C 2026-09-24 20:56Z; supersedes this cell's earlier text):** title "Payout reversed"; body "A reversal was recorded on this order's payout. Contact support for details." No amount and no cause.
  - Why: `mark_transfer_reversed` (0561) is the only writer of `'reversed'`, called by stripe-webhook's `transfer.reversed` handler (v42 :810–818) on **any** reversal event. It never compares `amount_reversed` with the transfer amount, so a **partial** reversal also reads `reversed`. The row records no cause.
  - The earlier "reversed after a dispute/operator review" stated a cause, and "the payout was reversed" implied all of it. Both are withdrawn.
- **Must not say:** "Payout released" or any released date for a `reversed` row. Check `status` BEFORE `payout_released_at` (order of precedence: `reversed` > `payout_released_at`). Also never an amount reversed, a cause (dispute, operator review), "fully"/"all", or **any buyer-refund fact**.
  - A reversal (the seller's payout transfer) and a buyer refund (the payment row) are separate facts; neither implies the other.
  - The seller's reversed block takes no refund props. **The gallery's four seller-reversed refund variants are stale.**

### 2e. The review / automatic-release deadline
- **Server facts:** at `seller_sent`, `auto_release_at = seller_sent_at + 72h` (008:100–103). At that time the payout policy (039 header) decides: LOW risk → `auto_released` (039:220/:298) then paid by the cron (Phase 2b) → `payout_released_at`; MEDIUM → `payout_review_status='held'`, `payout_hold_until` = event date + `post_event_grace_hours` (24h default, 039:62), never more than `medium_max_hold_days` (7, 039:64) past `auto_release_at`, then manual review; HIGH → `payout_review_status='manual_review'` (039:265; no date); orders ≥ `high_value_cents` ($200 default) never auto-release on buyer silence (039:57–58); `disputed` rows are excluded from every auto path (039 header). Buyer confirmation (`buyer_confirmed`) releases without waiting for the deadline; the money fact is still `payout_released_at`.
- **Buyer may say:** while `seller_sent`: "Confirm you received the tickets, or report a problem, before <auto_release_at>" — the deadline is the review window the buyer has (the server-enforced fact is that the release decision runs at `auto_release_at`). After it: `auto_released` → existing `buyerAutoReleasedCopy(payout_released_at)` (transferState.ts:186): the decision is stated; "released" money wording only when `payout_released_at` is set.
- **Seller may say:** while `seller_sent` and `payout_review_status` NULL and `auto_release_at` present: **always** "Release decision at <auto_release_at>.", also after that time has passed. It is a scheduled server time, so it stays true. Nothing when `auto_release_at` is absent.
  - **RULING, A → C 2026-09-24 20:56Z:** never "The buyer review window has passed" (`SELLER_WINDOW_PASSED`), and no branch on the device clock or on a countdown reading "Expired".
    - The device clock is not an authority.
    - The sentence is false even with a correct clock: `buyer_dispute_transfer` (0550, latest definer) accepts a report while `status = 'seller_sent'` regardless of `auto_release_at`. The window closes by a **status change** (`apply_auto_release` in the cron, or a buyer confirmation), not by the clock.
  - Keep `SELLER_REPORT_WARNING` while `seller_sent`. The post-window state is the server's `auto_released`/`buyer_confirmed` status with its own copy. `payout_review_status='held'`: "Payout held until <payout_hold_until>"; `'manual_review'`: "Payout under review" (no date — none exists); `auto_released`: see §2g. This cell's earlier "Review window passed" is withdrawn, because `auto_released` does not establish that the window passed.
- **Must not say:** a countdown after `disputed` (excluded from auto paths); "Payout released" from `auto_released` alone; a date for `manual_review`.

### 2f. Buyer: what happens to the payment after purchase (RULING, A, 2026-09-24 ~21:45Z)
- **Withdrawn:** "your payment is held until it reaches you" (checkout confirmation face, `CheckoutView.tsx:316` at C's
  `d374bd3f`) and "Payment is held until your ticket reaches you." (`ESCROW_NOTE_COPY`, `src/lib/checkout/holdState.ts:97`,
  a gated file). Both are pre-existing. The metadata version was already reworded in the submission checklist §4.
  - **The system never observes delivery.** The seller's payout follows one of four things:
    - the buyer's confirmation;
    - the release decision after the review window when there is no report;
    - an operator releasing an unreleased `seller_sent` row (144:807–829 → `admin_release_held_payout`, which sets
      `auto_released`, 0551);
    - since #92, a dispute resolved for the seller.
    None of these depends on the ticket reaching the buyer.
  - "Held" / "on hold" reads as a card authorisation, but the card is charged at checkout.
- **True, and usable:** a report freezes the seller's payout.
  - `buyer_dispute_transfer` (0550) accepts a report only while the order is `seller_sent`.
  - Every release path either needs the row to still be `seller_sent` (operator: 0551's guard, also 144:813 where
    applied; cron decision) or needs `buyer_confirmed`/`auto_released`, which the buyer's report prevents. A report
    sets `disputed` (0550).
  - So an accepted report always comes before any release, and the payout stays frozen until the report is resolved.
- **Compliant example** (C and B may adjust the voice, not the claims). Confirmation face: "Your order is confirmed. The
  seller sends the tickets next. If they don't arrive, report it from your order; a report freezes the seller's payout."
  Escrow note: "You pay now. If the tickets don't arrive, report it from your order; a report freezes the seller's
  payout."
- **Must not say:** that the payment waits for the ticket to arrive; "on hold"; a deadline stated as a guarantee. An
  operator can release before `auto_release_at`, so "you have until <date>" is not a promise the server keeps; "before
  <date>" as an instruction is fine.

### 2g. Seller payout lines and the release cause (RULINGS, A, 2026-09-24 ~22:10Z)
- **`auto_released` states no cause.**
  - It is written by the cron's release decision at `auto_release_at`, **and** by an operator's release of any
    unreleased `seller_sent` row (`admin_release_held_payout`, 0551; `payout_release` is platform_admin only,
    115:519). The operator path works at any time, so it can run before `auto_release_at`.
  - The row records neither which path ran nor that the window passed.
  - What is true for both paths: the order was released without a confirmation or a report. Both need `seller_sent`
    (0551's guard; the cron's decision), while a confirmation sets `buyer_confirmed` and a report sets `disputed` (0550).
  - **Seller:** title "Payout released" only when `payout_released_at` is set, otherwise "Payout pending" (the owner's
    16:51Z rule). Body: "This order was released without a confirmation or a report from the buyer." Then, when
    released: "Your payout has been released."; otherwise guidance such as "Make sure your payout account is set up
    in Settings."
  - **Buyer:** "This order was released to the seller without a confirmation or a report from you." Add "The seller has
    been paid." only when `payout_released_at` is set.
  - **Must not say:** "the review window passed/closed" for `auto_released`.
- **Seller, `pending` (buyer paid, not yet sent):** "The buyer has paid. Payout pending."
  - **Withdrawn:** "Payment is held until they confirm (receipt)" (`transferState.ts:190`, `detailState.ts:228`). It
    states one of four release paths as the rule, and "held" collides with `payout_review_status='held'`, which has
    its own dated copy.
  - C's proposal "…follows the buyer's confirmation or the release decision after the review window" also leaves
    out operator release and a seller-win, so it is not adopted.
- **`disputed`, open (rendered via `disputeOutcome.ts:66`).**
  - The "on hold" wording is withdrawn now. Buyer: "The seller's payout is frozen until this is resolved." Seller: "Your
    payout is frozen until the report is resolved." No "pending review", which asserts a process not evidenced
    (checklist §4).
  - "Our team typically reviews within 24 hours" is **G9 (P1)**, the owner's decision: keep it only if the owner
    commits to it, otherwise remove it.

## 3. When evidence is missing — the truthful minimum

| Situation | Say | Do not say |
|---|---|---|
| Transfer row readable, payment row not yet updated (refund/chargeback pending) | the transfer status word + "we'll update this when the refund is confirmed" | any refund amount, "refunded" |
| `payments.status='refunded'` or `refunded_at` set, `amount_refunded_cents` NULL (pre-release refunds) | "Refund recorded" | "Refunded in full", "$<total> refunded" |
| `amount_refunded_cents` > 0 and < `total` | "Partly refunded $X of $Y" | "Refunded" |
| `payout_released_at` set and `status='reversed'` | "Payout reversed" | "Payout released <date>" |
| `auto_released` / `buyer_confirmed` and `payout_released_at` NULL | "Release approved — payout pending" | "Paid out", "Payout released" |
| `payout_review_status='manual_review'` | "Under review" | any date |
| Any read failed (400/401/network) | the last server-confirmed state, labelled as last checked, or "Can't check right now" | any assumption from the device clock or cached totals |

Rules of precedence when the row carries several facts: `reversed` beats `payout_released_at`; `disputed` beats every deadline; a NULL amount beats a `refunded` status word for amounts; a server timestamp beats the device clock for "expired"/"passed" (the transfer's `expired` status is the only fact that permits the word "expired" — transferState.ts:48 already encodes this).

## 4. What the new release changed for these screens (2026-09-23)
- `record_payment_refund` is now the production refund writer for stripe-webhook v42 (`charge.refunded`, lost disputes) and the sweep: amounts are recorded monotonically and `refunded`/`refunded_at` mean "reached total". Rows refunded BEFORE 2026-09-23 keep the old shape (status + date, amount NULL).
- `enforce-transfer-expiry` v40 + migration 147: a payment under manual review is never re-swept; no client-visible change.
- Refund detection and alert delivery remain OFF; nothing in this table depends on them.

## 2h. Web marketplace status lines (RULING, A, 2026-09-25; D's findings F1-WEB-1/2, verified by A at source)

Scope: `web/src/app/account/purchases/page.tsx` (buyer, `statusLine`) and `web/src/lib/sales.ts` (seller,
`payoutLabel`), at gate `037092f0`. They derive money facts from the transfer status alone. The rules are the same as
the app's; only the surface differs.

- **Buyer, `expired`:** "Expired — refunded in full" (:32) is withdrawn: an expiry is not a refund. Say "Order expired
  — the seller didn't send the tickets in time." The refund line comes separately from the payment row, under
  ruling 3 (§2a). If the page does not read the payment row, it makes no refund statement.
- **Buyer, `disputed`:** "Disputed — support is reviewing" asserts a process the row does not record. Say "Issue
  reported — the seller's payout is frozen until this is resolved." After a decision (`dispute_resolved_at` set), state
  the decision only: `buyer_win` "Resolved in your favour"; `partial_refund` "Resolved"; seller-win "Resolved in the
  seller's favour". Refund facts come only from the payment row.
- **Buyer, `auto_released`:** "Confirmed" is withdrawn, because the buyer confirmed nothing. Say "Released"
  (the app's label). `buyer_confirmed` keeps "Confirmed", unless it came from a seller-win (buyer_confirmed_at NULL
  and `resolved_seller_paid`), which reads "Resolved in the seller's favour".
- **Seller (`payoutLabel`), in this order of precedence:**
  1. `reversed` → "Payout reversed";
  2. `disputed` with no decision → "Payout frozen — the buyer reported an issue". The withdrawn "On hold" wording
     is not used;
  3. `disputed` decided for the buyer → "Resolved for the buyer — no payout for this order";
  4. `expired` → "Order expired — no payout for this order", never "buyer refunded";
  5. `pending` → "Send the tickets";
  6. payout evidence (§2i) → "Payout released", replacing "Paid out";
  7. `manual_review` → "Payout under review";
  8. `held` → "Payout held until <payout_hold_until>", or "Payout held" when there is no end;
  9. `seller_sent` → "Release decision at <auto_release_at>" (§2e);
  10. `buyer_confirmed` / `auto_released` without payout evidence → "Release approved — payout pending".
- **Reads:** all of these columns already exist in production. None depends on migration 150.
- **Owner of the change:** the web surface. It is not C's; C's app already follows these rules.
- **Acceptance bar (D's criteria, adopted by A 2026-09-25; D verifies):**
  1. No string containing "refund" is reachable from a path whose only input is `transfer.status`.
  2. Refund wording stays at ruling 3's ceiling. After 150 is live, the kind contract in §2i applies.
  3. Payout completion requires `payout_released_at IS NOT NULL` and `status <> 'reversed'`. No payout string says
     "received".
  4. "Confirmed" requires `buyer_confirmed_at`. `auto_released` has its own wording. A seller-win is never shown as
     completion, and nothing derives a payout from `resolved_seller_paid`.
  5. No copy asserts a human activity that no record establishes.
  6. A resolved dispute does not render as open.
  7. One asserting test per finding (W-1a/b … W-6). Each predicate gets a positive control showing its compliant branch
     is reachable, and a negative control: revert the predicate and the test fails.
  8. No newly selected column may be one that doesn't yet exist in production.
- **Why W-1a/b is not a brief window:** #94 parks a payment whose refund failed (`refund_failed_cents > 0`) until a
  person handles it. For that whole time, both web lines would tell the buyer and seller the money went back.

## 2i. Payout-completion evidence and the losing buyer (RULINGS, A, 2026-09-25; owner's correction adopted)

- **Payout evidence**, for any audience: `transfers.payout_released_at IS NOT NULL` and `status <> 'reversed'`, with
  `reversed` taking precedence.
  - Every payout writer sets `payout_released_at` together with `stripe_transfer_id`, and only after Stripe accepted
    the transfer (0561:89, 0564:59, 20260906120000:782, 20260924120000:105).
  - So either column is the evidence, and code may check both.
  - A seller-win decision (`resolved_seller_paid`), `buyer_confirmed` or `auto_released` is never payout evidence.
- **Never "received":** we observe the transfer to the seller's Stripe account, not the money arriving at their bank.
  The allowed forms:
  - seller: "Payout released";
  - buyer: "The seller has been paid" / "The seller's payout was released".
- **Losing buyer (seller-win):** the decision only, e.g. "The dispute was resolved in the seller's favour."
  - No payout clause from the decision.
  - A payout clause only from payout evidence.
  - `resolved_seller_paid` is a misnomer: it records a decision, and no copy derives "paid" from it.
- **Refund after 150 is live** (not in this release): kind derived from the three sums.
  - failed: `refund_failed_cents > 0`;
  - completed: `refund_succeeded_cents` covers the amount and `refund_failed_cents = 0`;
  - otherwise: initiated.
  - Failure copy waits on the owner's O-R3 (who contacts the buyer).
  - No client selects `refund_*_cents` before 150 is applied in production. A missing selected column returns a 400.

