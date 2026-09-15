# Migration 132 / pgTAP 199 — pre-mint checkout group claim (DESIGN · PROPOSED · nothing written)

**Author:** Claude B, 2026-09-15 · **Status:** allocated by A as PROPOSED; **no SQL until the owner places it** (this candidate, or the production gate alongside 131) · **Base:** `release/candidate-20260918` (121–130, edges #64/#66/#67).

## 1. The defect (D's disposition, accepted)
130 serializes a checkout only when a **pending payment row already exists**, because the claim lives on that row. Two concurrent requests from one buyer that both find **no** pending row each mint at Stripe. Their idempotency key (`pi_{listing}_{buyer}_{mode}_{total}_c{customer}[_r{failed}]`) normally matches, so Stripe replays one intent. It diverges in three ways:
1. the canceled-replay retry adds `_u{randomUUID}`;
2. the seller re-prices between the two reads;
3. `failedAttempts` flips between the two reads.

Each divergence yields **two intents with two secrets and two captured charges**. The second capture collides with `idx_payments_one_success_per_listing`, is recorded `unfulfillable`, and is refunded by the next Phase 0 sweep, but only if the sweep is healthy and the Stripe refund succeeds. This is an open money defect with automated remediation, visible to the customer.

## 2. Options
| Option | Verdict |
|---|---|
| **A. Insert the pending payment row before minting** | **Rejected.** It needs a `payments` row with no intent id. Every reader of pending rows would see it: 127's live-sibling rule, `get_unsettled_payments`, retirement, reservation cleanup, account-deletion blockers, and the ops `paid_unsettled` detector. A unique "one live attempt per group" index would also break #64's order, which inserts P2 before cancelling P1. |
| **B. A group claim table the edge takes before any mint** | **Recommended.** |
| C. Advisory lock | Rejected. PostgREST gives no transaction to hold it in. |

## 3. Recommended design (B)
- **Where it lives:** `public.checkout_group_claim (listing_id uuid, buyer_id uuid, mode text, claim_token uuid not null, claimed_at timestamptz not null, primary key (listing_id, buyer_id, mode))`.
  - RLS enabled, no policies, no client grants.
  - Written only by two `service_role` RPCs.
  - One row per active group; release deletes it.
- **Claim:** `claim_checkout_group(listing, buyer, mode)` → `{claimed, claim_token, reason}`. It is one statement: `insert … on conflict (pk) do update set claim_token = excluded.claim_token, claimed_at = now() where checkout_group_claim.claimed_at < now() - interval '120 seconds' returning claim_token`.
  - A returned row means claimed; no row means `claim_held`.
  - The primary key makes it atomic without taking payments or listings locks, so it adds no lock-order interaction with settlement.
- **Release:** `release_checkout_group(listing, buyer, mode, token)` deletes the row only when the token matches.
- **Edge placement:** one group claim per request, taken after the entitlement checks and `ensureStripeCustomer`, **before** the prior-payments read.
  - Held through every hand-out: fresh mint, reuse and supersede; released in `finally`.
  - `claim_held` retries 10 × 200 ms, then answers 409 with no secret.
  - A second concurrent request therefore never reaches a mint. Once the first commits its pending row, the next request takes the reuse or supersede path.
- **Idempotency salt:** unchanged. The three divergences become harmless because only one request per group mints at a time. The `_u` retry stays request-unique but serialized.
- **23505 recovery:** unreachable between two claimed requests of the same group. Kept as a defence for a stale reclaim (a holder that crashed after the Stripe create but before its insert), and still guarded by E-1's token re-read.
- **E-1:** the same mechanism. The budget clock starts at the group claim, and the token re-read moves to this table: before the insert, before cancelling a superseded intent, and before every secret hand-out.
- **130:** the per-row claim becomes redundant for serialization. The edge stops calling it; its RPCs and columns stay in the database until a separately authorized cleanup.
- **Degradation:**
  - `PGRST202` (132 absent) → fall back to the 130 row claim, which is today's candidate behaviour, and report to Sentry.
  - Any other claim error → 503, fail closed.
  - A crashed holder lapses at 120 s. The holder itself is bounded by E-1's 90 s budget.
- **CI cost:**
  - Census: tables +1, functions +2, policies 0, triggers 0.
  - Grant-decision manifest: 1 table row and 2 function rows (`no-client-execute`).
  - `expected_grants`: the table's `service_role` row.
  - Rollback drops the functions, then the table.
- **Tests:**
  - pgTAP 199: claim, held, stale reclaim, token-bound release, no client access, and RED without 132.
  - Two-session script: two fresh mints in one group, where the second waits and then gets `claim_held`. The control is the same without the primary-key conflict clause, where both claim.
  - vitest: two concurrent fresh mints with no pending row, driven through each of the three divergences, hand out exactly one secret. RED against the candidate edge.
  - **CI green on the PR head before review-ready.**
- **Effort:** SQL and tests about 3–4 h; edge about 2–3 h; A/D review about 2 h; plus CI. About one working day end to end.

## 4. Interim, if 132 is not in this candidate: what exists and what to alert on
- **Today:**
  - `settle_verified_payment` records an unfulfillable capture in `public.webhook_retries` (`error_message` `unfulfillable…`).
  - `enforce-transfer-expiry` (cron `*/2 * * * *`) Phase 0 refunds it once (Stripe idempotency key `refund_unfulfillable_<payment>`) and records the refund through `record_payment_refund`.
  - A capture that already has a transfer is parked as `unfulfillable:manual_review`, with one Sentry capture.
  - **No ops console detector reads `webhook_retries`** (0 references in migrations 115–120).
- **Needed** (ops migrations on D's surface; the owner decides):
  - (a) a detector opening a **p1** case for any unresolved `unfulfillable%` row older than 10 minutes (the sweep is unhealthy or its refund failed), and a **p0** case for `unfulfillable:manual_review`;
  - (b) an alert on the **double-capture signature**: a second succeeded capture for the same (listing, buyer) inside a short window, which is customer-visible even when refunded;
  - (c) confirmation that job health covers the `enforce-transfer-expiry` cron itself (not verified here).

## 5. Owner decision
Place 132 **in this candidate** (about one day including review and CI; the build waits), **or** at the **production gate** alongside 131. In either case, decide whether the interim alerts (a) and (b) ship with the candidate.

## 6. Addendum 2026-09-15 — owner ruling, mechanism choice, as-built (B)
**Owner ruling (2026-09-15):** 132 is **required before production**. The owner does not accept a known double-charge path on the basis that a later job may refund it. B implements and locally verifies the "pending-record-before-intent" fix on an isolated branch. D reviews concurrency, retries, uncertain Stripe outcomes and duplicate prevention; A owns integration. Development and review are authorized; production application is not.

**Mechanism: Option B, a pre-mint group record, not a payments row.** The ruling names a property: a durable, serialized record exists before any mint, and no path mints twice. B re-checked §2's Option A rejection reasons against the code:
- **No longer holds:** #64's P2-before-cancel order. A unique index restricted to intent-less rows would not conflict with P1, which already has an intent.
- **Still holds:** `enforce-transfer-expiry`'s `get_unsettled_payments` consumer calls Stripe retrieve with the row's intent id, which would be null.
- **Still holds:** the account-deletion blockers count any pending row, so a crashed intent-less attempt blocks deletion until something retires it.
- **Still holds:** 127's live-sibling rule would count an abandoned intent-less row as a live attempt.

Option A would move changes onto A's surface (sweep, blockers, 127) days before the release date. Option B satisfies the same property with none of those readers touched. A confirmed Option B and carries "mechanism: pre-mint group record" in the owner checkpoint so the owner can redirect.

**As built** (branch `fix/132-pending-before-intent`, base `aabe029`):
- **SQL:** `public.checkout_group_claim` as §3, with no foreign keys (no lock interaction) and mode limited to `buy_now`/`auction`. `claim_checkout_group` and `release_checkout_group` return `{claimed, claim_token, reason}` and `{released, reason}`.
- **Edge, changed from §3:**
  - 130's row claim is **kept** on reuse and supersede, so a mixed-version deploy stays serialized. The E-1 guard checks the group token first, then the row claim.
  - PGRST202 fails **closed** (503) instead of degrading. Deploy order is 132 before the edge.
- **Added (P1):** a group attempt still `processing` blocks any mint, reuse or supersede with a 409. That is the same money class, found while writing 132: a processing intent may still capture, so a second confirmable secret would collide. It is a separate commit, so it can be dropped on review.
- **Coupling (confirmed for A's packet):**
  - Edge before 132: 503 on every checkout (by design).
  - 132 before edge: the table is unused, and 130's row claim still serializes reuse and supersede. The fresh-mint defect stays open until the edge ships.

**Out of scope, for D to confirm unreachable:** the group is (listing, buyer, mode). Two concurrent checkouts by one buyer in *different* modes, or by two *different* buyers, on one listing are not serialized by 132. They are gated by entitlement and reservation authority, and a collision still ends at `idx_payments_one_success_per_listing` (unfulfillable, refunded).
