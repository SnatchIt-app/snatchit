# Payment-state and wording table for the V3 order/transfer screens (A → C, 2026-09-24)

Owner instruction 2026-09-24: "Provide the evidence-backed payment-state and wording table for buyer expired, buyer reversed, seller reversed, and the review/automatic-release deadline. Distinguish order status, recorded refund amount and confirmed payout. State what the UI may truthfully say when evidence is missing."
Every claim below is cited to the gate source at `5b255838` (migrations under `supabase/migrations/`, edges under `supabase/functions/`), which is what production runs as of 2026-09-23 23:22Z (ledger 160; ten functions deployed). Nothing here is inferred from the client.

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
- **May say "Refunded $X":** only when `amount_refunded_cents` is not NULL and equals `total` (or `status='refunded'` AND `amount_refunded_cents = total`).
- **May say "Refund recorded":** when `status='refunded'` or `refunded_at` is set but `amount_refunded_cents` is NULL — no amount, no "in full".
- **May say "Partly refunded $X of $Y":** when `0 < amount_refunded_cents < total` (status will still read `succeeded`).
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
- **May say:** "Payout reversed" (no amount), with the dispute outcome if a dispute record exists; "This order's payout was reversed after a dispute/operator review."
- **Must not say:** "Payout released" or any released date for a `reversed` row — check `status` BEFORE `payout_released_at` (order of precedence: `reversed` > `payout_released_at`); an amount reversed.

### 2e. The review / automatic-release deadline
- **Server facts:** at `seller_sent`, `auto_release_at = seller_sent_at + 72h` (008:100–103). At that time the payout policy (039 header) decides: LOW risk → `auto_released` (039:220/:298) then paid by the cron (Phase 2b) → `payout_released_at`; MEDIUM → `payout_review_status='held'`, `payout_hold_until` = event date + `post_event_grace_hours` (24h default, 039:62), never more than `medium_max_hold_days` (7, 039:64) past `auto_release_at`, then manual review; HIGH → `payout_review_status='manual_review'` (039:265; no date); orders ≥ `high_value_cents` ($200 default) never auto-release on buyer silence (039:57–58); `disputed` rows are excluded from every auto path (039 header). Buyer confirmation (`buyer_confirmed`) releases without waiting for the deadline; the money fact is still `payout_released_at`.
- **Buyer may say:** while `seller_sent`: "Confirm you received the tickets, or report a problem, before <auto_release_at>" — the deadline is the review window the buyer has (the server-enforced fact is that the release decision runs at `auto_release_at`). After it: `auto_released` → existing `buyerAutoReleasedCopy(payout_released_at)` (transferState.ts:186): the decision is stated; "released" money wording only when `payout_released_at` is set.
- **Seller may say:** while `seller_sent` and `payout_review_status` NULL: "Release decision at <auto_release_at>" (existing send screen countdown, app/transfer/send/[id].tsx:153–157 reads `auto_release_at`); `payout_review_status='held'`: "Payout held until <payout_hold_until>"; `'manual_review'`: "Payout under review" (no date — none exists); `auto_released` without `payout_released_at`: "Review window passed" (existing send screen :458); with `payout_released_at`: "Payout released".
- **Must not say:** a countdown after `disputed` (excluded from auto paths); "Payout released" from `auto_released` alone; a date for `manual_review`.

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
