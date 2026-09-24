# Refund lifecycle: trace, defects and fix design (A, 2026-09-24)

**Status: RELEASE-READINESS DEFECT, open** (owner, 2026-09-24).
- A owns the implementation; D verifies independently. D registered expectations `a6324b21…` at 22:12:56Z, before
  reading this.
- Nothing here is applied, deployed or enabled. No production read was made.
- Source is the release gate `037092f0`, which production runs: `enforce-transfer-expiry` v41 = blob `432b4898…`;
  `stripe-webhook` v42; 20260906120000 applied.
- The app is C's head `65052bfc`. Stripe facts come from docs.stripe.com, checked 2026-09-24.

The three sections are kept apart as asked: **A. implementation defects** (trace and fix), **B. operational choices**
(the owner's), **C. legal wording** (pending, and not the vehicle for this fix).

---

## A. Implementation defects

### A.1 What Stripe says a refund does (docs.stripe.com, 2026-09-24)

- **Statuses.** `pending`, `requires_action`, `succeeded`, `failed`, `canceled` (/api/refunds/object).
  - The create call can return `pending`: "Stripe holds the refund as pending for card transactions" when the balance
    is short (/refunds).
- **A card refund can succeed and fail later.** "a refund can appear to succeed and later fail". Test card
  4000000000005126 "begins as `succeeded`" and later "transitions to `failed`" (/testing).
  - Money back to the card "can take up to 30 days" (/refunds).
- **On failure,** "you need to arrange an alternative way to provide your customer with a refund"
  (/refunds#failed-refunds). The funds return to the platform balance.
- **Events** (/api/events/types):
  - `refund.created`, `refund.updated` and `refund.failed`.
  - `charge.refunded`: "including partial refunds. Listen to `refund.created` for information about the refund".
  - `charge.refund.updated` is deprecated: "listen to `refund.updated` instead".
  - Stripe recommends listening "at a minimum" to `refund.created`.
  - **Not confirmed in the docs:** whether `charge.refunded` fires on creation (while pending) or only on success.
- **Idempotency** (/api/idempotent_requests; /error-low-level):
  - Keys "expire out of the system after 24 hours".
  - A replay returns the saved result, even a `500`.
  - After the key is pruned, a new request is made. Refunding a fully refunded charge errors with
    `charge_already_refunded` (/error-codes).
- **Webhooks** (/webhooks): order is not guaranteed and duplicates happen. Retrieve the object for its latest
  state.

**Consequence:** a refund's truth is a per-refund state that can move in any direction for up to about 30 days. Adding
one failure event is not enough.

### A.2 What production does today, path by path

**Shared writer:** `record_payment_refund` (20260906120000:457–555).
- It inserts an append-only `payment_refunds` row keyed by `re_…` (:504–509).
- It raises `payments.amount_refunded_cents` to `min(total, Σ)` (:514–518) and sets `stripe_refund_id` once.
- At Σ ≥ total it sets `status='refunded'` and `refunded_at` (:519–522).
- It flags payout reversal when a paid transfer exists (:530–545).
- **The guard makes all of this one-way** (:404–427): `refunded` is terminal, `amount_refunded_cents` never
  decreases, and `refunded_at`/`stripe_refund_id` never change. **The writer takes no refund status.**

**P1. Expiry refund.** enforce-transfer-expiry Phase 1 (:510–700), running about every 2 minutes.
1. The seller hasn't marked sent by `expires_at` (sale + 24 h, 061:111). `enforce_transfer_expiry()` sets
   `transfers.status` from `pending` to `expired` with `expired_at` (0551:11–17).
2. It sends `POST /v1/refunds {payment_intent}` with no amount and the key `refund_expiry_<transfer>` (:598–607). The
   response is typed `{id, amount}`, so **the refund's `status` is never read** (:601).
3. It calls `record_payment_refund(…, refund.amount, 'expiry')` at once, so a refund that is `pending`, or even
   `failed`, is recorded as money returned. The payment becomes `refunded` + `refunded_at`.
4. It sends pushes:
   - buyer: "Refund Processed … **Your full refund has been issued.**"
   - seller: "…The buyer has been refunded." (:640–655).

**P1b. The expiry self-heal** (:700–790) picks expired transfers whose live payment is still `succeeded`, 20 per run,
oldest first. It re-POSTs with the same key, then records the result.

**P0. Unfulfillable-capture refund** (:440–500) works like P1 with the key `refund_unfulfillable_<payment>` and sends
no push. If the writer RPC is missing it falls back to a raw `payments` update to `refunded` (:476–488).

**P2. Buyer-favour dispute outcome.** `resolve_transfer_dispute` (065) sets `dispute_resolution`
`'resolved_buyer_refunded'` or `'resolved_partial_refund'` and writes a `refund_required` decision. **No Stripe call
is made:** `ops-refund-execute` is not deployed (2026-09-22 manifest :172). So a person refunds in the Dashboard, which
is P3.

**P3. Manual Dashboard refund.**
- Stripe creates the refund. `charge.refunded` is subscribed, and webhook v42 handles it (:702–757).
- The webhook fetches the charge with `expand[]=refunds` and calls `record_payment_refund` for **every** refund in
  the list.
- The destructured type has **no `status` field** (:711–716). So a refund that is `pending`, `failed` or `canceled`
  is recorded as money returned. D's reading sharpens this: blind by construction.

**P4. Partial refund.**
- A Dashboard partial refund goes through P3: `amount_refunded_cents` becomes the partial amount and the status stays
  `succeeded`.
- If the order then expires, P1's amount-less POST refunds the **remaining balance**. The buyer's push still says
  "Your full refund has been issued".

**P5. Lost dispute (chargeback)** is recorded through the same writer with a dispute id. It is not a refund object and
is unchanged by this design.

**Events subscribed** (the 11 in G3/V3): of the refund events, only `charge.refunded`. **None of** `refund.created`,
`refund.updated` or `refund.failed`.

### A.3 What the buyer and seller see, including after a later failure

| Moment | Payment row | Buyer: order screen (`refundLine`, transferState.ts) | Buyer: checkout (`settledKind`/`REFUND_COPY`) | Seller |
|---|---|---|---|---|
| Order expired, before the cron | `succeeded` | "A refund is due; it will show here once it's confirmed." | — | "No payout for this order." |
| Refund created, Stripe says `pending` | `refunded`, amount = total, `refunded_at` set | **"Refunded $X"** (false; it is only requested) | **"Full refund recorded: a full refund of $X was recorded"** | push: "The buyer has been refunded." (false) |
| Stripe later sets `failed` (can happen after `succeeded`, up to about 30 days) | **unchanged**: nothing handles the event, and the guard forbids undoing it | **"Refunded $X" forever** (false) | **"Full refund recorded" forever** | unchanged |
| Failure returned at creation (non-card methods) | recorded as refunded by P1 anyway | "Refunded $X" (false) | "Full refund recorded" (false) | "buyer has been refunded" (false) |
| Buyer-favour decision, no Dashboard refund yet | `succeeded` | "A refund is due…" (true) | — | — |
| Partial Dashboard refund, pending | `succeeded`, amount = partial | "Partly refunded $p of $t" (false while pending) | "Partial refund recorded" | — |

**Screens that say "refunded" falsely:** the order screen (`refundLine`), checkout (`REFUND_COPY` via
`isRefundConfirmed`), and the expiry pushes.

### A.4 Retry and recoverability defects

1. **A failed refund closes its own retry path** (D's R5, F3 + F4).
   - A failed refund recorded as settled makes the payment `refunded`.
   - P1's idempotency check (`fullyRefunded`) and P1b's selection (`payments.status='succeeded'`) then skip it.
   - No automation retries, no operator case opens, and no screen changes.
2. **Stripe succeeded but our write failed.**
   - P1 logs the refund id and moves on. P1b replays the same key: inside 24 h this returns the same refund and it is
     recorded.
   - After the key is pruned, the amount-less POST errors (`charge_already_refunded`) on every run, with a Sentry each
     time, and the refund is never recorded. The buyer sees "a refund is due" forever.
   - If the first refund had failed by then, the same POST silently creates a **second** refund: an unreviewed
     automatic retry.
3. **P1b starves.** With the limit of 20 oldest first, 20 permanently erroring rows block every newer one.
4. **P0's fallback** writes `refunded` with no refund state at all.

### A.5 What operators see today

- `ops.detect_refunds` (latest definer 118) opens `refund_pending` (p1) only while `payments.status <> 'refunded'`.
  It opens `refund_failed` only for **ops `refund_execute` actions**, whose executor isn't deployed.
- A Stripe-side failure on a payment already marked `refunded` matches **neither**.
- Sentry sees only POST and write errors, never a later Stripe failure. Alert delivery is off.
- **An operator cannot learn that a refund failed.**

### A.6 The fix (source + tests on `fix/refund-lifecycle-accuracy`; migration **150**, pgTAP **217**)

**Principle:** each Stripe refund gets its own state, taken from Stripe's own object, which the app can read truthfully.
`payments.amount_refunded_cents` / `status` keep their meaning and guards: a one-way "a refund was requested" record
that correctly blocks payout. They are **no longer used for display**.

**M150 `20260925000000_refund_lifecycle_state.sql`** (apply gated by the owner):
- **`public.payment_refund_state`**: one row per `re_…`, holding `payment_id`, `amount_cents`, `status` (Stripe's 5
  values), `failure_reason`, `source`, `first_observed_at`, `last_observed_at` and `last_observed_via`
  (`create_response` | `webhook` | `reconcile`).
  - Any status may replace any other. Stripe allows that, and every writer passes Stripe's current object.
  - RLS is on and only `service_role` can use it.
- **`public.payment_refund_state_log`**: an append-only audit of every observed change.
- **`payments.refund_requested_cents` / `refund_succeeded_cents` / `refund_failed_cents`** (`int NOT NULL DEFAULT
  0`; no table rewrite). Only the writer maintains them. They are client-readable through the existing
  own-row SELECT.
- **`public.record_refund_state(pi, re, status, amount, failure_reason, source, observed_via)`**
  (`SECURITY DEFINER`, `search_path=''`, service_role only) is the one writer:
  - It upserts the state and logs any change.
  - It **counts** a refund through `record_payment_refund` only while its status is `pending`, `requires_action` or
    `succeeded`. A refund first seen as `failed` or `canceled` is never counted.
  - It recomputes the three sums.
  - A refund that fails **after** being counted leaves the one-way columns as they are (payout stays blocked, which
    is safe) and shows in `refund_failed_cents`.
- **`ops.detect_refunds`** is redefined: 118's body is kept verbatim, plus two branches behind a new setting
  **`refund_state_detection_enabled`, seeded `false`** (flags are seeded off; the owner flips them):
  - `refund_failed` (p1): a Stripe refund is `failed` or `canceled` and the payment's succeeded refunds are below the
    total. It clears when succeeded refunds cover the total.
  - `refund_pending` (p1): a Stripe refund is still `pending` or `requires_action` after
    `refund_state_pending_hours` (seeded 120).
  - Keys are merged into 118's own sweep sets, so neither branch auto-resolves the other's cases.
- **No backfill** (D's requirement). Historical `refunded` rows, including the two live rows of 2026-08-04, get no
  state rows. The app shows them as a legacy "Refund recorded", never promoted to "Refunded". Reconciling them is a
  named item needing an authorised Stripe read (B.4).
- Four-file rule: grant manifest, Gate-2 census (+2 tables, +2 functions, +0 policies, +1 trigger), expected grants,
  and a rollback restoring 118's applied `detect_refunds` body.

**stripe-webhook** (deploy gated by the owner; needs the **Stripe subscription change O-R1**):
- It handles `refund.created`, `refund.updated` and `refund.failed`. Each one **re-fetches** `GET /v1/refunds/{id}`
  (latest state, whatever the delivery order) and calls `record_refund_state(…, 'webhook')`. An error answers non-2xx
  so Stripe retries.
- `charge.refunded`: each refund in the expanded list goes through `record_refund_state` with **its own status**. A
  failed or canceled refund is no longer counted.

**enforce-transfer-expiry** (deploy gated by the owner):
- P0, P1 and P1b read `status` and `failure_reason` from the create response and call `record_refund_state(…,
  'create_response')`. P0's raw fallback is removed; a missing writer fails loudly.
- **P1b reconciles first.** It lists `GET /v1/refunds?payment_intent=…`:
  - If a refund that is pending, requires action or succeeded exists: record it, and **don't POST**. This fixes A.4.2.
  - If only failed or canceled refunds exist: record them (the case opens), and **don't POST**. Per Stripe, an
    alternative is arranged instead of an automatic re-refund.
  - If there are none: POST.
  - P1b's selection excludes payments with `refund_failed_cents > 0` (fixes A.4.3).
- **Pushes state the amount and the stage.**
  - `succeeded`: "…We've refunded $X to your original payment method."
  - `pending` / `requires_action`: "…We've requested a refund of $X to your original payment method. It will show on
    your order when it's complete."
  - `failed` / `canceled`: no refund push to the buyer, and a case opens.
  - Seller: "…The order has expired and the buyer is being refunded."
  - "Full" is never said; $X is this refund's own amount (fixes the misleading notice after a partial refund).

**App contract** (C implements; `holdState`/`setupDecision` are gated, so A reviews). One truth table for both the
order screen and checkout. Read `refund_succeeded_cents`, `refund_requested_cents`, `refund_failed_cents`, `total`,
`status` and `amount_refunded_cents`:
1. succeeded ≥ total: "Refunded $total".
2. failed > 0 (succeeded < total): "A refund of $F didn't go through. Contact support@snatchitapp.com." If succeeded > 0,
   "Partly refunded $S of $T." comes first.
3. requested > 0: "Refund of $R requested. It will show as refunded once it's complete." (plus any partial line).
4. 0 < succeeded < total: "Partly refunded $S of $T".
5. All three are 0, but `status='refunded'` or `amount_refunded_cents > 0` (a legacy row or a chargeback): "Refund
   recorded", with no amount and no claim of completion.
6. Otherwise: today's due / pending policy lines.

Until M150 is applied, C ships nothing that depends on these columns. C's current copy stays, and the defect stays
**open**.

### A.7 Tests (TDD; RED on today's code, then GREEN, then mutants with distinct kill sets)

- **pgTAP 217:**
  - objects, grants, and no client EXECUTE;
  - `pending` is counted and sits in the requested sum; `succeeded` moves it to succeeded;
  - **failed after succeeded:** the failed sum is set, `amount_refunded_cents` and `status` are unchanged, and the
    one-way guard holds;
  - **first seen `failed` or `canceled`:** no `payment_refunds` row and the payment stays `succeeded`;
  - an idempotent repeat adds no log row; an unknown payment returns `recorded=false`; a bad status raises; the log is
    append-only;
  - the detector off adds no new cases. With it on: failed opens `refund_failed`; a covering succeeded refund resolves
    it; a stale pending refund opens `refund_pending`; 118's existing owed-refund branch is unchanged.
- **vitest via `tests/helpers/edge-vm`:**
  - webhook `refund.failed` re-fetches and writes `failed` through `record_refund_state`, never `record_payment_refund`;
  - `charge.refunded` with `[succeeded, failed]` passes each status through;
  - Phase 1 with a `pending` response writes `pending`, and the push says "requested" and the amount, never "full";
  - Phase 1 with a `failed` response sends no buyer refund push;
  - Phase 1b: an existing refund means no POST; only failed means no POST; none means POST once with the expiry key;
  - selection excludes `refund_failed_cents > 0`.
- **Negative controls:**
  - mutant M1: the writer counts failed refunds (kills the failed cases);
  - mutant M2: the detector ignores the new state (kills the case assertions);
  - mutant M3: P1b POSTs without reconciling (kills the P1b cases).

---

## B. Operational choices (the owner's; each is a production action needing its own authorisation)

- **O-R1.** Add `refund.created`, `refund.updated` and `refund.failed` to the live Stripe webhook endpoint. This is a
  Dashboard change, made at deployment and not before (the handler must exist first).
- **O-R2.** Flip `refund_state_detection_enabled` to `true` after the apply. This is an audited runtime setting, not a
  migration.
- **O-R3.** Who works `refund_failed` and `refund_pending` cases in `/cases`, and how. With alert delivery off, nobody
  is paged.
  - The recommended handling for a failed refund: Stripe returns the money to the platform balance. Contact the buyer
    from support@ and return the money another way. Record what was done on the case.
  - Don't re-refund automatically.
- **O-R4.** Reconcile the historical refunded rows (7, including 2 live on 2026-08-04). This needs an authorised
  read-only Stripe read of their refunds, then feeding each through `record_refund_state(…, 'reconcile')`. Until then
  they display "Refund recorded".

## C. Legal wording (pending; this fix is not made through the terms)

The draft terms (PAYOUT_REFUND_TERMS_DRAFT_20260924.md §B) stay pending. The reconciliations are tracked there, not
here.
