# DECISION A — PRIMARY VENUE MONEY

**Status:** DECISION PACKET — recommendation stated, not executed.
**Scope:** how money moves, and where the venue obligation lives, when a venue sells a first-party ticket.
**Repo:** `/Users/josetascon/snatchit-consol` · branch `feature/venue-native-and-product-v2`
**Constraint:** migrations 076–092 are IMMUTABLE and deployed. Any change is 093+.
**Constraint:** must be compatible with `COMMISSION_FUNDING_SOURCE` Option B (owner-ratified 2026-09-02).

---

## 1. VERIFIED CURRENT STATE

### 1.1 The defect is CONFIRMED, and it is worse than "no payout row"

`087:318` is the **only** `INSERT INTO venue.settlement_line` in the repository. Verified by exhaustive
grep across `supabase/`, `app/`, `src/`, `packages/`, `docs/` and root `*.md`; every other hit is a
`SELECT`, a `NOT EXISTS` guard, an index, a policy, or a pgTAP assertion.

That single INSERT sits inside `kernel.close_settlement`
(`supabase/migrations/087_venue_settlement_and_export.sql:314-322`) and its candidate rows come from
exactly two seam functions, unioned:

| Seam | Authored | Real body | What it emits |
|---|---|---|---|
| `kernel.settlement_royalty_lines` | `087:205` (zero rows) | `088:319` | `market_sale` royalty (**positive**, resale rail) + `chargeback` (**negative**) |
| `kernel.settlement_commission_lines` | `087:211` (zero rows) | `090:1511` | `promoter_commission` (**negative**) |

**Neither emits a primary-sale revenue line. No third seam exists.**
`kernel.close_settlement` has never been `CREATE OR REPLACE`d after `087:289` — verified.

`venue.finalize_primary_order` (`085:1881-2078`), the only function that turns money into tickets, has
this complete write set:

1. `venue.inventory_hold` → `converted` (`085:2031`)
2. `venue.inventory_batch.held` decrement (`085:2041`)
3. `kernel.issue_ticket_atoms` — the mint (`085:2045`)
4. `venue."order"` → `paid` (`085:2056`)
5. `kernel.payment_native` INSERT (`085:2060`)
6. `venue.resolve_order_attribution` — non-raising stub (`085:2065`)

**No `kernel.payout` insert. No `venue.settlement` touch. No `venue.settlement_line` insert.**

### 1.2 The arithmetic consequence

`close_settlement` derives its buckets from the lines it holds (`087:329-333`):

```
gross   = Σ(amount > 0, cause NOT IN ('refund_void','chargeback'))
fees    = Σ(-amount) where amount < 0, non-refund causes
refunds = Σ(-amount) where cause IN ('refund_void','chargeback')
net     = gross - fees - refunds
```

For an event whose only activity is primary sales: **gross = 0**. Add one promoter commission
(negative, `090:1511`) and **net goes negative**. `if v_net > 0` (`087:337`) never fires. No
`kernel.payout` row is minted. A venue that sells 400 tickets is owed money that **no schema row names**.

This is independently corroborated by two frozen-corpus documents:

- `PHASE2_PRIMARY_ACTIVATION_GAP_MATRIX.md:21-33` — "no code path anywhere emits a primary-sale
  settlement line. `087:318` is the only INSERT … Gross is therefore 0."
- `docs/architecture/_governance/POST_FREEZE_AMENDMENTS.md:2469` (E-138) — "no package writes a
  primary-revenue settlement line, so an event settlement's gross is 0."

**The claim under review is upheld in full.**

### 1.3 A SECOND blocker found in passing — primary money-in cannot be recorded at all

`public.payments.listing_id` is `not null references public.listings(id)`
(`supabase/migrations/000_baseline_schema.sql:972`). **No migration relaxes it** (verified: no
`DROP NOT NULL`, no `ALTER COLUMN listing_id` anywhere in `supabase/migrations/`).

But:
- `kernel.payment_native.payment_id` → `references public.payments(id)` (`085:42`)
- `venue.finalize_primary_order` reads `public.payments` and **requires** a row (`085:1919-1929`)
- `PHASE_2_EDGE_FUNCTION_SPEC.md:36` — "Money-in is *only* a `public.payments` row via the frozen webhook."

A native primary order has no listing. **Today a primary sale cannot write its money-in row**, which
means `finalize_primary_order` cannot be called at all with a real payment. Two frozen texts also
contradict each other here: `EDGE_FUNCTION_SPEC.md:373` says the row carries "the new `order_id`
linkage column", while `:1812-1817` (the later resolution) says "**No column is added to the frozen
`public.payments` table — ever**". The deployed table satisfies neither, and neither addresses
`listing_id NOT NULL`.

### 1.4 How money actually moves TODAY (the resale rail) — read, not assumed

**Model: SEPARATE CHARGES AND TRANSFERS. Platform is the merchant of record.**

- **Charge.** `supabase/functions/create-payment-intent/index.ts:514-527` builds `piBody` with exactly:
  `amount`, `currency`, `automatic_payment_methods[enabled]`, `customer`, `setup_future_usage`, and
  four `metadata[*]` keys. **No `transfer_data`, no `on_behalf_of`, no `application_fee_amount`.**
  `_shared/stripe.ts` sets a bare `Authorization: Bearer STRIPE_SECRET_KEY` with **no `Stripe-Account`
  header** — verified by grep across all edge functions. This is a **direct charge on the platform
  account**.
- **Where funds land.** The platform's own Stripe balance. No Connect object holds the money.
- **How the seller is paid.** Later, by `_shared/payouts.ts:133-145`:
  `POST /v1/transfers` with `destination` = the seller's Connect account, and
  **`source_transaction` = the funding charge id**. The header comment (`payouts.ts:16-24`) records why:
  a same-day charge left the platform available balance at $0 and transfers failed with "Insufficient
  funds"; `source_transaction` makes Stripe settle the transfer against *that* charge as it becomes
  available.
- **Idempotency.** `payout_<transferId>_<destination>_src`, deterministic and destination-salted
  (`_shared/payout-logic.ts:23`).
- **Pre-flight.** Destination capability probe then funding-charge probe, both before the key is spent
  (`payouts.ts:81-131`) — a not-ready destination returns `destination_not_ready` without burning it.
- **Connect account model.** `create-connect-account/index.ts:203-206` — `type: 'express'`,
  `business_type: 'individual'`, `capabilities[transfers][requested]: 'true'`.
  **Transfers-only Express.** `card_payments` is not requested, so these accounts **cannot** be the
  destination of a destination charge or the account of a direct charge without re-onboarding.
- **Seller account id.** `public.profiles.stripe_connect_id` (`confirm-and-release/index.ts:522`).
- **Org account id.** `kernel.organization.stripe_connect_account_ref` (`077:114`), set by
  `kernel.set_org_payout_destination` (`085:1601`). **No org-facing Connect onboarding edge function
  exists** — `create-connect-account` serves individual sellers only.
- **Fee model.** `_shared/money.ts` — buyer pays base + 10%, seller receives base − 10%, both computed
  from the base in integer cents, half-up. Stored in `public.payments.amount / buyer_fee / seller_fee /
  total` (`000_baseline_schema.sql:982-985`).

**Nothing in the primary rail's frozen design changes this.** `EDGE_FUNCTION_SPEC.md:355-373`
(`primary-checkout`) mints an ordinary platform PaymentIntent with `metadata.rail='native_primary'`.
The platform receives primary money first, exactly as it receives resale money first.

### 1.5 The money schema — what each table can hold, and who writes it

| Table | Facts it can hold | Writers found | Client access |
|---|---|---|---|
| `kernel.payment_native` (`085:41-62`) | `payment_id` → `order_id` **XOR** `sale_id`; `amount_minor`; `currency`; `instrument_fingerprint`. AO. | `venue.finalize_primary_order` (`085:2054`); `088` sale arm | `revoke all from anon, authenticated` (`085:70`) — service_role only |
| `kernel.refund` (`085:75-100`) | `payment_id`, `reason_code` (6-value closed set), `amount_minor > 0`, `status` pending→submitted→succeeded\|failed, `stripe_refund_ref` (write-once, paired by CHECK) | `kernel.refund_primary_order` (`085:457`), `admin_refund`, `mark_refund_state` (`085:1738`) | `revoke all` (`085:104`) |
| `kernel.payout` (`085:114-152`) | `payee_kind` org\|identity; **`cause ∈ ('settlement','market_sale','promoter_commission','refund_void')`**; `cause_ref` (no FK); `amount_minor > 0`; status pending/submitted/paid/failed/reversed; 4-column hold overlay; **`stripe_transfer_ref` write-once**; unique `idempotency_key` | `kernel.close_settlement` (`087:339`), `kernel.pay_promoter_commission` (`090`), `request_org_payout` (advance only), `mark_payout_transfer_state` (`085:1668`) | `revoke all` (`085:162`) |
| `kernel.identity_obligation` (`085:161-186`) | chargeback / refund_clawback debt owed by an **identity**; `outstanding`/`recovered`/`written_off` | webhook via `record_identity_obligation` | `revoke all`; **`revoke delete` even from service_role** |
| `venue.settlement` (`087:44-67`) | org/venue/event/period header; status open→closed→paid; **4 write-once money columns** with a table CHECK enforcing `net = gross − fees − refunds` | `open_settlement` (`087:227`), `close_settlement` (`087:334`), `on_payout_settled` (`087:392`) — the sole writer of `paid` | `grant select`; org-finance + venue-finance + platform policies |
| `venue.settlement_line` (`087:92-106`) | **AO, signed** `amount_minor`; `cause` from the D3 closed set — which **includes `primary_sale`, `issue`, `door_sale`, `refund_void`**; `cause_ref`; `is_rounding_bearer`; `UNIQUE(settlement_id, cause, cause_ref)` | **`087:318` ONLY** | `grant select`; **`revoke update, delete` from service_role** (`087:115`) |
| `public.payments` (`000:971`) | resale money-in: amount / buyer_fee / seller_fee / total; **`listing_id NOT NULL`** | frozen webhook + `create-payment-intent` | frozen RLS |

**The cause code `primary_sale` is legal in `venue.settlement_line` and has existed since `087:96`.
It has never been written. The gap is a missing writer, not a missing concept.**

### 1.6 What the frozen contract SAYS should happen

`PHASE_2_RPC_FUNCTION_CONTRACTS.md` §10.2 (`:1578-1620`) contracts `close_settlement` to compute
`gross_minor` = "**Σ the positive revenue lines**". That phrasing presupposes positive revenue lines
exist. It names `venue.settlement_line`, `venue.attribution` and `market.market_sale` as reads — and
`market.market_sale` is the *resale* rail. **§10.2 never assigns a package the job of writing a
primary-sale line.**

`PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md` §3.14 (`:3139-3161`) is more explicit:
"**Write authority: the settlement close engine.**" So the frozen architecture places primary revenue
lines **at close, written by `close_settlement` via a candidate seam** — the same mechanism 088 and
090 used. It simply assigns the work to nobody.

`PHASE_2_VENUE_DASHBOARD_PRODUCT_SPEC.md:1075` lists `primary_sale` first among the causes the
dashboard's settlement view renders. **The product spec renders a line the database never mints.**

### 1.7 The already-ratified promoter decision (Option B)

`POST_FREEZE_AMENDMENTS.md:2469` (E-138) and the forward-obligation entry
`COMMISSION_FUNDING_SOURCE` record:

> **OWNER RULING (2026-09-02) — POLICY CLOSED / OWNER-RATIFIED · IMPLEMENTATION OBLIGATION OPEN:**
> OPTION B — promoter commissions are funded FROM PRIMARY TICKET REVENUE THROUGH THE VENUE SETTLEMENT
> ACCOUNTING MODEL (primary ticket revenue → promoter commission liability → venue distributable
> settlement).

Rejected as the normal mechanism: (A) carry-forward of an unfunded negative net, (C) arbitrary org
Stripe-balance debit, (D) platform advance/absorption. Until the funding leg is implemented, tested and
authorized, **every commission payout is minted and REMAINS HELD `unfunded_settlement`**
(`090:1401`); `kernel.release_payout` is a per-payout Control-5 action, not a funding rail.

The amendment names 13 things the implementation must prove: the exact primary revenue source · the
exact settlement-line representation · commission deducted ONCE · conservation · no duplicate funding ·
refund behaviour · chargeback behaviour · cancellation behaviour · held-payout release condition ·
payout destination readiness · settlement-close concurrency · no platform advance · no arbitrary
Stripe-balance debit.

**Decision A is the funding leg of Option B.** Any recommendation that does not put primary revenue as
a positive line in the same `venue.settlement` header where the commission is already a negative line
fails Option B by construction.

### 1.8 Lifecycle inventory — what the DEPLOYED schema can and cannot represent

| Event | Representable? | Written by anything? | Evidence |
|---|---|---|---|
| **Refund reduces a venue obligation** | **YES** — `cause='refund_void'` is in the D3 set (`087:96-98`) and is bucketed into `refunds_minor` (`087:332`) | **NO WRITER.** `kernel.refund_primary_order` (`085:457`) writes `kernel.refund` and voids atoms; it never lines a settlement. The only `settlement_line` references in the void path (`085:369`, `085:435`) are **reads**. | A refund after close does not reduce the venue's next settlement. |
| **Chargeback** | **YES** | **YES** — the chargeback CTE in `088:351-362` emits a negative line joining `dispute_native → payment_native.order_id → venue."order".org_id`. This is the **primary-order arm**, and it works. | Asymmetric: the debit lands, the credit it should offset never existed. Net goes negative, no payout, debt uncollected — E-138's exact pathology. |
| **Event cancellation** | Partially | `catalog.cancel_event` (088) drives refunds through `kernel.refund`. **No settlement line.** | Same gap as refunds. |
| **Payout execution offline for a week** | **YES, cleanly** | `venue.settlement` stays `closed`; `kernel.payout` stays `pending`. Obligation is fully intact. | This part of the design is sound — *once the obligation row exists*. |
| **Stripe transfer failure** | **YES, cleanly** | `kernel.mark_payout_transfer_state` (`085:1668`) writes `failed` with a **mandatory** `failure_code` (`085:1707`); the payout row survives; `venue.on_payout_settled` (`087:381`) refuses to advance the header to `paid` while any settlement payout is non-paid. | Obligation survives payout failure. Correct by design. |
| **Venue Connect account disconnected** | **YES** | `_shared/payouts.ts:81-96` capability pre-flight returns `destination_not_ready` **without spending the idempotency key**; payout stays `pending`. | Correct. Reusable for the org rail unchanged. |
| **Buyer disputes AFTER the venue was paid** | **PARTIALLY** | Negative `chargeback` line in the org's **next** settlement (`088:351`) — recovery by netting only. `kernel.identity_obligation` (`085:161`) covers **identity**-scoped losses, not org ones. Money spec §9.4 (`:1486-1505`): "**No reserve. No clawback. No instant payout.**" Org-side clawback is Gate-M. | Recovery depends entirely on future primary revenue lines existing to net against. Another argument for the fix. |

### 1.9 The five questions, answered against the deployed system

1. **Who receives the buyer payment first, and what Stripe object owns the money?**
   **Snatch It (the platform).** The money is owned by a PaymentIntent/Charge on the **platform**
   Stripe account (`create-payment-intent/index.ts:514-527` — no Connect parameters of any kind).
   No connected account touches it. This is true for resale today and is what the frozen primary
   design specifies (`EDGE_FUNCTION_SPEC.md:355-373`).

2. **When is the venue obligation recognized, and what exact immutable row says "Snatch It owes Venue
   X $Y for sale Z"?**
   **It is never recognized. No such row exists or can be produced by any deployed code path.**
   The row that *should* say it is `venue.settlement_line(cause='primary_sale', cause_ref=<order_id>,
   amount_minor=+Y)` — a legal, AO, service-role-un-deletable row whose cause code has existed since
   `087:96` and which nothing writes.

3. **How are the nine money facts represented?**

   | Fact | Representation today | Status |
   |---|---|---|
   | Gross | `venue.settlement.gross_minor`, derived from positive lines | Column exists, **always 0** |
   | Buyer fee | **Nothing.** `venue."order"` has a single `total_minor` (`082`) with no fee column; `venue.order_item.unit_price_minor` is a per-type snapshot | **UNREPRESENTABLE** |
   | Tax | **Nothing** | **UNREPRESENTABLE** |
   | Discount | Only implicitly, folded into `unit_price_minor` | **NOT SEPARABLE** |
   | Refund | `cause='refund_void'` → `refunds_minor` | Cause legal, **no writer** |
   | Chargeback | `cause='chargeback'` → `refunds_minor` | **WORKS** (`088:351`) |
   | Promoter commission | `cause='promoter_commission'`, negative → `fees_minor` | **WORKS** (`090:1511`), payout **HELD** |
   | Snatch It revenue | A negative line (fee/royalty bucket) | Cause set has no `platform_fee`; would ride as a negative `primary_sale`-adjacent line or be netted. **No writer** |
   | Venue distributable | `venue.settlement.net_minor` + `kernel.payout(cause='settlement')` | **Machinery correct, input empty** |

   **`venue."order"` carrying only `total_minor` is a hard constraint**: the primary rail has no place
   to decompose buyer fee, tax or discount. Whatever split is chosen must be derivable from
   `order_item.unit_price_minor × quantity` and a config rate, or new columns are required.

4. **When does venue money become payable, and how is payout EXECUTION separated from obligation
   ACCOUNTING?**
   Payable at `kernel.close_settlement`, which mints `kernel.payout(cause='settlement',
   cause_ref=settlement_id, status='pending')` (`087:339-345`). Then:
   `request_org_payout` advances `pending→submitted` under the SoD-1 / maturity / step-up / probation
   control set (`087:408`, contracts §10.3, §17.7) → the `payout-execute` edge function performs the
   Stripe transfer → `kernel.mark_payout_transfer_state` writes `paid`/`failed`/`reversed`
   (`085:1668`) → `venue.on_payout_settled` (`087:381`) advances the header `closed→paid`.
   **The separation is already correct and complete.** The obligation (`settlement` +
   `settlement_line` + `payout`) is a different aggregate from the Stripe reference; a failed transfer
   writes `failed` with a mandatory failure code and does not erase the debt; a held payout refuses
   state sync entirely (`085:1690`). **This half of the architecture needs nothing.**

5. **Does the design satisfy "never reconstruct venue debt from Stripe history after the fact"?**
   **No. It fails that test completely for primary sales.** After 400 primary tickets sell, the only
   artefacts are `venue."order"` rows, `kernel.payment_native` links and Stripe charges. The debt is
   *derivable* from orders but is **asserted by no immutable ledger row**, and nothing prevents a
   later change to the derivation rule from silently changing the answer.
   **Minimum addition: one immutable `venue.settlement_line` per primary order, minted
   deterministically, exactly-once, from a candidate seam — plus the partial unique index that makes
   "exactly once" a database fact rather than a query's good behaviour.**

---

## 2. OPTIONS

Four realistic options. They differ on **the Stripe model** and on **where the obligation fact lives**.

---

### OPTION 1 — Platform collects; obligation is a settlement line minted at close (the seam)

**Stripe model:** UNCHANGED. Platform PaymentIntent, funds in the platform balance, org paid later by
`POST /v1/transfers` to `kernel.organization.stripe_connect_account_ref`. Existing transfers-only
Express accounts work as-is.

**Obligation fact:** `venue.settlement_line(cause='primary_sale', cause_ref=<order_id>,
amount_minor=+venue_share, currency)` — AO, `revoke update, delete` even from service_role
(`087:115`), read-visible to org finance and venue finance.

**Where the code goes:** `093` does a `CREATE OR REPLACE` of a candidate seam. Two sub-variants:

- **1a (smallest).** Extend `kernel.settlement_royalty_lines` with a `primary` CTE.
  **Zero DDL. Zero change to `close_settlement`.** Exact precedent: 088 put the chargeback arm in
  this same function rather than in `close_settlement` (`088:310-318` explains why).
  Cost: the function name no longer describes its contents.
- **1b (cleaner).** Add `kernel.settlement_primary_lines` and `CREATE OR REPLACE
  kernel.close_settlement` to union three seams instead of two.
  Cost: replaces the SSCAS #4 function body — a larger, though still body-only, change.

**Advantages**
- No Stripe change at all. No new Connect capability, no re-onboarding, no new charge shape.
- No schema DDL in variant 1a (one additive index recommended regardless — see failure mode 2).
- **Option B compatible by construction.** The commission is *already* a negative line in the same
  header (`090:1511`). Add the positive primary line and `net = gross − commission − fees` holds
  arithmetically, in one place, deducted exactly once, with conservation provable from the header's
  own CHECK constraint (`087:59-65`).
- The chargeback arm already lands in this exact header and finally has a credit to offset.
- Payout execution/accounting separation is already correct and needs no work.
- Aligns with what the frozen corpus already says: §3.14 "**Write authority: the settlement close
  engine**"; §10.2 "Σ the positive revenue lines".
- The resale rail is not touched.

**Disadvantages**
- The obligation is asserted at **close**, not at sale. Between the sale and the close, the debt is
  derivable from `venue."order"` but no immutable row states it.
- Depends on an operator (or scheduler) calling `open_settlement` then `close_settlement`. Nothing
  auto-opens a settlement.
- The venue's revenue share % has no frozen key — it is an owner policy input this option needs.

**Failure modes**
1. **Silent non-recognition.** Primary collection is switched on, nobody opens a settlement, real
   money accumulates and the ledger still asserts no debt.
2. **Cross-settlement double-lining.** `UNIQUE(settlement_id, cause, cause_ref)` scopes uniqueness to
   *one* settlement — schema §3.14.1 (`:3163+`) confirms this as a known defect. Overlapping periods,
   a re-opened event settlement, or a venue-level close after an org-level close would line the same
   order **twice** and pay the venue twice. `kernel.payout.idempotency_key` would **not** catch it,
   because the payout's `cause_ref` is the settlement, not the order. 090 fixed this for commissions
   with a partial unique on `cause_ref` (`090:214-215`); `primary_sale` has no equivalent.
3. **Refund between sale and close** changes the correct line amount, and there is still no
   `refund_void` writer.

**Launch implications:** primary collection can ship before this; settlement is a separate finance
action. But **do not switch collection on until the line writer exists**, per the gap matrix's own
correction (`:31-33`).

---

### OPTION 2 — Platform collects; obligation is minted AT SALE inside `finalize_primary_order`

**Stripe model:** UNCHANGED (identical to Option 1).

**Obligation fact:** an immutable row written in the **same transaction as the mint**. Requires a
settlement header to exist at sale time — either auto-open a per-`(org, venue, event)` `open`
settlement, or add a `venue.primary_revenue` accrual table drained at close.

**Advantages**
- The obligation is asserted at the money event itself. "$Y for sale Z" is literally one row created
  by the sale. Strongest possible answer to question 5.
- No dependence on an operator ever opening a settlement.
- Survives every downstream failure by construction.

**Disadvantages**
- `venue.finalize_primary_order` is **SSCAS member #1** with a frozen, itemized Writes set
  (contracts §6.3). Adding a settlement write adds a **new lock rank** to the hottest money path and
  changes its contracted behaviour → this is a **POST-FREEZE AMENDMENT of a frozen RPC contract**,
  not an implementation follow-up.
- A new accrual table is **DDL on a money ledger**, whose declared rollback posture is
  **FORWARD-FIX ONLY FROM FIRST ROW** (`085:29-31`).
- Auto-opening a settlement collides with `open_settlement`'s command-key idempotency (`087:243-258`)
  and its `venue_finance`/`org_finance` authority model — a service-role auto-open has no actor.
- Creates a second source of truth (accrual table vs. settlement lines) requiring reconciliation.

**Failure modes**
1. **Lock-order inversion.** `close_settlement` takes Settlement → Payout (`087:295`, SSCAS #4).
   `finalize_primary_order` takes Session → Batches → Order. Adding Settlement to the finalize path
   risks deadlock against a concurrent close.
2. A settlement closing mid-flight while checkouts are in progress — the header is write-once at
   close, so a late line has nowhere to go.
3. Reconciliation drift between the accrual table and the settlement lines.

---

### OPTION 3 — Destination charges: the venue becomes the Stripe merchant of record

**Stripe model:** CHANGED. PaymentIntent created with `transfer_data[destination]=acct_…` and
`application_fee_amount`. Money splits at charge time; the venue's share lands in the venue's Connect
balance immediately.

**Obligation fact:** **Stripe owns it.** The database records a reference.

**Advantages**
- No payout rail needed for the base amount. No platform float.
- No "Snatch It owes Venue X" at all — the venue was never owed.
- Venue is paid on Stripe's own schedule.

**Disadvantages**
- **Directly violates the stated requirement** that venue debt must never be reconstructed from Stripe
  history — it makes Stripe the ledger and the database a mirror.
- **Breaks Option B outright.** A commission cannot be deducted from money that already left the
  platform. Commissions revert to platform-funded (explicitly rejected as option D) or to clawback,
  which money spec §9.4 (`:1486`) explicitly does not build.
- Requires the `card_payments` capability. Current accounts are transfers-only Express
  (`create-connect-account/index.ts:203-206`) → **full re-onboarding of every connected account**.
- Refunds and chargebacks debit the connected account, creating negative Connect balances the platform
  cannot control.
- Changes the merchant of record → different tax, regulatory and dispute-liability posture.
- Forks the primary rail from the proven resale rail; two charge models to maintain.

**Failure modes**
1. Negative connected balance on refund, with no platform remedy.
2. Commission permanently unfundable — Option B becomes unimplementable.
3. Chargeback debits the venue's balance; Stripe's automatic debit fails; the platform is liable anyway.

---

### OPTION 4 — Separate charges and transfers, one transfer per order, immediately

**Stripe model:** UNCHANGED charge shape, but each order's venue share is transferred at
`payment_intent.succeeded`, `source_transaction`-funded — exactly what the resale rail does today.

**Obligation fact:** `kernel.payout(cause=<new>, cause_ref=<order_id>)` minted per sale, discharged
within minutes.

**Advantages**
- Closest to the **proven** resale rail; `_shared/payouts.ts` reuses byte-for-byte, including the
  capability pre-flight and the `source_transaction` funding that solved the August 2026 incident.
- Venue is paid fast — a real commercial advantage for venue acquisition.
- `source_transaction` maps 1:1 to a single charge, which is exactly what Stripe's API wants.

**Disadvantages**
- `kernel.payout.cause` CHECK admits only `('settlement','market_sale','promoter_commission',
  'refund_void')` (`085:120-121`). A per-order primary payout has **no legal cause** → **DDL on a
  money ledger** to widen the CHECK. (`085:122-124` anticipates additive widening as E-51, so this is
  contemplated — but it is still DDL under FORWARD-FIX-ONLY posture.)
- **Breaks Option B.** The venue is paid *before* the commission can be deducted. Commissions become
  platform-funded or require clawback — both explicitly rejected.
- `venue.settlement` becomes decorative: the money left before the header existed.
- Refund after transfer = clawback, which §9.4 does not build.

**Failure modes**
1. Refund arrives after the transfer, with no clawback rail — the platform eats it.
2. Commission permanently unfunded.
3. 400 tickets = 400 transfers: Stripe rate limits, per-transfer overhead, and 400 rows to reconcile.

---

## 3. RECOMMENDATION

### **OPTION 1, variant 1b** — platform collects; primary revenue becomes a `primary_sale` settlement line minted at close by a dedicated third seam.

Variant **1b** over 1a: `CREATE OR REPLACE kernel.close_settlement` to union a third seam
`kernel.settlement_primary_lines` is a body-only change to a function whose contract already describes
this behaviour ("Σ the positive revenue lines"), and it keeps each seam's name honest. Overloading
`settlement_royalty_lines` with primary revenue would make the resale rail's seam the owner of primary
money — a naming lie in the single most audited function in the system. The extra cost is one
`CREATE OR REPLACE` of an already-`CREATE OR REPLACE`-shaped function.

**Why this one:**
- It is the only option that satisfies **Option B by construction**: primary revenue (+) and promoter
  commission (−) land in the **same header**, netted once, by the same close, with conservation
  enforced by an existing table CHECK.
- It is the only option that keeps the **working resale rail untouched** — no Stripe change, no
  Connect change, no `create-payment-intent` change.
- It matches what the frozen corpus already assigns: §3.14 "Write authority: the settlement close
  engine"; §10.2's `gross_minor` derivation; the D3 registry's existing `primary_sale` code.
- The obligation-vs-execution separation it relies on is **already built and correct**.
- It is the **smallest** change that makes venue debt a database fact.

### Classification: **IMPLEMENTATION FOLLOW-UP**

No frozen text is contradicted. The cause code exists (`087:96`), the write authority is assigned
(schema §3.14), the derivation is contracted (§10.2), and seam replacement is the established
mechanism (088 and 090 both did it). What is missing is a writer nobody wrote. This discharges the
open `COMMISSION_FUNDING_SOURCE` implementation obligation.

**Three sub-items carry a DIFFERENT classification and must be tracked separately:**

| Sub-item | Classification | Why |
|---|---|---|
| **The primary revenue split** — what fraction of the ticket price is venue distributable vs. Snatch It revenue, and whether a buyer fee sits on top | **OWNER POLICY** | No frozen key exists. The 10/10 resale model (`_shared/money.ts`) is nowhere stated to govern the primary rail. Home: `catalog.platform_config`. |
| **`public.payments.listing_id NOT NULL`** (`000:972`) blocking primary money-in | **POST-FREEZE AMENDMENT** | The minimum fix, `ALTER TABLE public.payments ALTER COLUMN listing_id DROP NOT NULL`, is a change to a frozen `public.*` table, contradicting OBS-1 ("zero changes to `public.*`", `085:13-14`). It is additive and non-breaking for resale, but it needs a signature. **Nothing ships without it.** |
| **Config key values** (`payout.*` 4 keys, `authn.*` 2, seeded `null` at `078:1541-1560`) | **OPERATIONAL CONFIG** | Owner sets values at activation; unset authorizes nothing (C61/X-12). |

### Schema impact (precise)

**093 — required:**
1. `CREATE OR REPLACE FUNCTION kernel.settlement_primary_lines(p_settlement_id uuid) RETURNS SETOF
   kernel.settlement_line_candidate` — emits, for every `venue."order"` with `status='paid'` in the
   settlement's scope (event, or venue + period via `event_session.starts_at`, mirroring `088:344-350`
   exactly): `('primary_sale', order_id, +venue_share_minor, order.currency, 'organization',
   settlement.org_id)`, guarded by
   `NOT EXISTS (SELECT 1 FROM venue.settlement_line l WHERE l.cause='primary_sale' AND l.cause_ref=o.order_id)`
   and by `o.currency = s.currency`. Must be **non-raising** (a raise rolls back the close — `087:196`).
   Must take the org advisory lock the 088 seam takes (`088:329`) or share it.
2. `CREATE OR REPLACE FUNCTION kernel.close_settlement(...)` — union the third seam into the existing
   candidate loop (`087:314-316`). **No other change to its body.**
3. `CREATE UNIQUE INDEX order_one_primary_line_ever ON venue.settlement_line (cause_ref) WHERE cause =
   'primary_sale';` — mirrors `090:214-215` exactly. **This is the fix for failure mode 2 and is not
   optional.** Additive index only.
4. A **`refund_void` arm** in the same new seam: for every `kernel.refund` with `status='succeeded'`
   against a primary order already lined, emit `('refund_void', refund_id, −amount_minor, …)`.
   Without this, refunds never reduce a venue obligation. Same partial-unique treatment.
5. Config: a primary revenue-share key in `catalog.platform_config` (value = OWNER POLICY).

**Post-freeze amendment (separate signature):**
6. `ALTER TABLE public.payments ALTER COLUMN listing_id DROP NOT NULL;`

**Explicitly NOT changed:** `venue.settlement`, `venue.settlement_line`, `kernel.payout`,
`kernel.refund`, `kernel.payment_native` — **no DDL on any money ledger table** beyond the two
additive indexes. `venue.finalize_primary_order` — untouched. The resale rail — untouched.

**Deliberately deferred (Gate-M, unchanged):** buyer fee / tax / discount decomposition. `venue."order"`
carries only `total_minor` (`082`), so the primary rail cannot decompose them today. The recommendation
books a single net venue-distributable line and one negative platform-revenue line; anything finer
requires columns on `venue."order"` and is a separate decision.

### Edge impact (precise)

| Function | Status | Change |
|---|---|---|
| `create-payment-intent` | Deployed, working | **NONE** |
| `confirm-payment`, `confirm-and-release`, `stripe-webhook` (resale branches) | Deployed | **NONE** |
| `_shared/payouts.ts`, `payout-logic.ts`, `stripe.ts`, `money.ts` | Deployed | **NONE** — reused |
| `primary-checkout` | **MISSING** (spec'd `EDGE_FUNCTION_SPEC.md:355`) | Author. Must NOT assume an `order_id` column on `public.payments`; the link is `kernel.payment_native` per `:1812-1817`. Must supply a `listing_id` (or rely on the amendment above). |
| `stripe-webhook` `rail:'native_primary'` branch | **MISSING** | Author; calls `venue.finalize_primary_order` |
| `payout-execute` | **MISSING** (spec'd `:461-527`) | Author. **Sole writer of payout `failed`.** Required before any venue is paid. |
| Org Connect onboarding | **MISSING** | `create-connect-account` serves individual sellers only. Orgs need `stripe_connect_account_ref` populated via `kernel.set_org_payout_destination` (`085:1601`). |

### Stripe impact (precise)

**NONE to the charge model.** No `transfer_data`, no `on_behalf_of`, no `application_fee_amount`, no
`Stripe-Account` header, no new Connect capability, no re-onboarding of any existing account.

**One unresolved Stripe design point, flagged (see failure mode 3):** a settlement payout aggregates
N orders and therefore N charges, but `source_transaction` accepts **one** charge, and
`kernel.payout.stripe_transfer_ref` is **write-once and singular** (`085:133`). `payout-execute` must
resolve this before it is written.

---

## 4. THE THREE FAILURE MODES THAT MOST WORRY ME

### FM-1 — Silent non-recognition: nothing auto-opens a settlement

`venue.open_settlement` (`087:227`) is a manual, human-authorized, command-keyed finance action. Nothing
in `finalize_primary_order` or anywhere else creates one. If primary collection is switched on and no
one opens and closes settlements, the system is in **exactly today's state, but with real money in it**:
buyers charged, tickets minted, and a ledger that asserts no debt.

**Why it is dangerous:** it fails silently and asymmetrically. Every buyer-facing surface works
perfectly. Nothing errors. Nothing alerts. The failure is only visible to whoever eventually asks
"what do we owe?" — and by then the answer must be reconstructed from Stripe, which is precisely the
outcome this decision exists to prevent.

**Minimum mitigation:** an alert (or scheduled open/close) on any `venue."order"` with `status='paid'`
older than N days carrying no `settlement_line` with `cause='primary_sale'` and `cause_ref = order_id`.
This query is cheap — `settlement_line_cause_ref_idx` (`087:108`) already exists.

### FM-2 — Cross-settlement double-lining pays a venue twice, and no constraint stops it

`UNIQUE(settlement_id, cause, cause_ref)` (`087:105`) scopes uniqueness to one settlement.
Schema §3.14.1 (`:3163+`) confirms this as a known, named defect: "**nothing stops the same … id being
lined into two different settlements** — an overlapping period, a re-opened event settlement, a
venue-level close after an org-level close, or simply an operator opening a second settlement."

For `promoter_commission`, 090 closed it with a partial unique on `cause_ref` (`090:214-215`).
**For `primary_sale`, nothing does.** The seam's `NOT EXISTS` guard is a *query*, and two concurrent
closes over overlapping scopes can both pass it. `kernel.payout.idempotency_key` is **not** a backstop
here, because the payout's `cause_ref` is the settlement id, not the order id — two settlements produce
two legitimately distinct payouts.

**Why it is dangerous:** it pays real money twice, it is a race so it appears intermittently under
load, and the AO trigger (`087:111`) means the erroneous line **cannot be deleted or corrected** — only
offset by a compensating negative line, by hand.

**This is why the partial unique index is listed as required, not optional.**

### FM-3 — `source_transaction` does not generalize from one charge to a settlement

The single most valuable piece of hard-won knowledge in the resale rail is `_shared/payouts.ts:16-24`:
funding a transfer with `source_transaction` is what stopped same-day payouts failing with
"Insufficient funds in Stripe account." It works because **one resale payout has exactly one funding
charge**.

A settlement payout has **N** funding charges — one per primary order. But:
- Stripe's `source_transaction` accepts a **single** charge id.
- `kernel.payout.stripe_transfer_ref` is **write-once and singular** (`085:133`), and
  `mark_payout_transfer_state` (`085:1712-1717`) raises `conflict_locked` on a second, different ref.

So `payout-execute` has three choices, and each has a real cost:
1. **N transfers per payout** — the write-once singular `stripe_transfer_ref` cannot record them.
   The payout row can only name one.
2. **One transfer, no `source_transaction`** — draws unrestricted platform available balance and
   **reproduces the August 2026 incident** on every settlement closed before the underlying charges
   have settled.
3. **One payout per order** — that is Option 4, which breaks Option B.

**Why it is dangerous:** it is not a bug to be found in testing; it is a structural mismatch between
the money schema's shape (one payout, one ref) and Stripe's funding API (one transfer, one source
charge). It will surface on the very first real venue settlement, in production, with a venue waiting
to be paid. **It must be resolved on paper before `payout-execute` is written.**

The most likely resolution — and the one I would recommend investigating first — is to **wait for
charge availability** rather than to force per-charge funding: close the settlement, mint the payout,
and let `payout-execute` transfer from the platform available balance only once all constituent
charges have settled (`available_on` passed). That preserves one payout / one ref, keeps Option B
intact, and trades payout latency for structural simplicity. It requires a readiness predicate that
does not exist yet.

---

## 5. WHAT THIS DECISION DOES NOT DECIDE

- The revenue split percentage (OWNER POLICY).
- Buyer fee / tax / discount decomposition on the primary rail (Gate-M; needs columns on `venue."order"`).
- The `payout-execute` funding strategy (FM-3) — flagged, not resolved.
- Org-side clawback beyond netting (money spec §9.4 keeps it Gate-M).
- `COMMISSION_PAYOUT_LIFECYCLE` — the advance path for a `promoter_commission` payout, and the
  reason-scoped release that `POST_FREEZE_AMENDMENTS.md` requires alongside the funding ruling.
- Whether commission payouts are released once funding exists — the amendment requires that release to
  be **reason-scoped** to `hold_reason_code='unfunded_settlement'`, because `kernel.hold_payout`
  returns `noop_replay` without comparing reasons and `release_payout` takes no reason argument.

---

## 6. EVIDENCE INDEX

| Claim | File:line |
|---|---|
| Only INSERT into `venue.settlement_line` | `supabase/migrations/087_venue_settlement_and_export.sql:318` |
| Two seams unioned; no third | `087:314-316` |
| Royalty seam real body (market_sale + chargeback) | `088:319`, `088:340-362` |
| Commission seam real body | `090:1511` |
| `close_settlement` never replaced after 087 | `087:289` (sole definition) |
| `if v_net > 0` gate | `087:337` |
| Bucket derivation | `087:329-333` |
| Waterfall CHECK | `087:59-65` |
| `settlement_line` AO + service_role revoke | `087:111`, `087:115` |
| `primary_sale` in the cause CHECK | `087:96` |
| `finalize_primary_order` full write set | `085:1881-2078` (esp. `:2056`, `:2060`, `:2065`) |
| `kernel.payout` cause CHECK | `085:120-121` |
| `stripe_transfer_ref` write-once | `085:133`, `085:1712-1717` |
| Payout state machine + failure handling | `085:1668-1734` |
| `on_payout_settled` closed→paid | `087:381-405` |
| `public.payments.listing_id NOT NULL` | `000_baseline_schema.sql:972` |
| PI has no Connect params | `create-payment-intent/index.ts:514-527` |
| Transfer with `source_transaction` | `_shared/payouts.ts:133-145` |
| `source_transaction` rationale (Aug 2026 incident) | `_shared/payouts.ts:16-24` |
| Express transfers-only accounts | `create-connect-account/index.ts:203-206` |
| Org Connect ref column | `077_kernel_identity_orgs_and_roles.sql:114` |
| `venue."order"` has only `total_minor` | `082_venue_orders.sql:74` (DDL), `:83` (`total_minor`) |
| Option B ruling | `docs/architecture/_governance/POST_FREEZE_AMENDMENTS.md:2469` + `COMMISSION_FUNDING_SOURCE` entry |
| Independent confirmation of the gap | `PHASE2_PRIMARY_ACTIVATION_GAP_MATRIX.md:21-33` |
| `close_settlement` contract | `docs/architecture/PHASE_2_RPC_FUNCTION_CONTRACTS.md:1578-1620` |
| `settlement_line` write authority | `docs/architecture/PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md:3139-3161` |
| Cross-settlement uniqueness defect | `PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md:3163+` |
| No reserve / no clawback | `docs/architecture/PHASE_2_MONEY_AUTHORITY_SPEC.md:1486-1505` |
| `payout-execute` spec | `docs/architecture/PHASE_2_EDGE_FUNCTION_SPEC.md:461-527` |
| `primary-checkout` spec | `PHASE_2_EDGE_FUNCTION_SPEC.md:355-394` |
| No column ever added to `public.payments` | `PHASE_2_EDGE_FUNCTION_SPEC.md:1812-1817` |
