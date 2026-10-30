# H3 — Payout unit and the `source_transaction` cardinality question

**Status:** decision, implementable. **Scope:** backend only. **No production mutation, no Stripe
API call, no deploy was performed to produce this.**

**Headline for the owner: this decision requires NO change to `kernel.payout`'s columns.**
`stripe_transfer_ref` keeps its write-once singular shape. `source_transaction_ref` keeps its
shape and stays NULL on the settlement rail. This is not a schema decision; it is an executor
specification. Two *separate* defects are named in §8 that DO want SQL, and neither is created by
this ruling — they are pre-existing and are recommended for a later 094, not for 093.

---

## 1. The premise that was wrong

Every prior report states the contradiction as:

> One settlement payout has many funding charges, but Stripe binds ONE `source_transaction` per
> transfer and it cannot be amended — and `kernel.payout.stripe_transfer_ref` is write-once and
> singular. Therefore the money schema and Stripe's funding API are structurally mismatched.
> (`E4_refund_executor.md:432-437`, `PRIMARY_TICKETING_FINAL_OWNER_RULINGS.md:661`,
> `PRIMARY_TICKETING_ACTIVATION_MATRIX.md:160`)

Both halves of the premise are true. The *conclusion* does not follow, because it silently assumes
`source_transaction` is **required** to create a transfer. It is not. It is an optional funding
hint. Once that assumption is removed the contradiction dissolves without touching a column:

- **Aggregation happens in the ledger, not at Stripe.** N funding charges become N
  `venue.settlement_line` rows, which `kernel.close_settlement` collapses into ONE
  `net = gross − fees − refunds` (`087:330-337`, `093:10d`).
- **Stripe is asked to execute ONE transfer of that net.** Many charges never implied many
  transfers. They implied many *ledger lines*, which is exactly what the schema already models.

The cardinality is therefore **N charges → N lines → 1 net → 1 payout → 1 transfer → 1 ref.**

---

## 2. Chosen payout unit: **the `kernel.payout` row**, which for `cause='settlement'` is 1:1 with `venue.settlement`

**Durable row:** `kernel.payout` (`085:111`). Natural key `idempotency_key = 'settlement:'||settlement_id`
(`087:343`, `093:880`), `unique` at `085:138`, inserted `on conflict (idempotency_key) do nothing`
(`093:885`).

This is not chosen for convenience. It is the only candidate the shipped schema already realises:

| Candidate | Verdict |
|---|---|
| **Per payout row (= per settlement)** | **CHOSEN.** Already minted, already the unit of the maturity gate, the hold overlay, dual control, and `venue.on_payout_settled`. |
| Per order | No durable payout row exists per order and none can be minted — `close_settlement` is the sole minter of a `cause='settlement'` payout and is forward-only. Would also require N `request_org_payout` calls, each behind its own aal2 step-up and its own dual-control approval (`087:450`, one payout `limit 1` per call). Destroys the fee/commission netting, which does not decompose per order without an owner ruling that does not exist (093's own A4 note refuses to invent a pro-rata basis for exactly this reason). |
| Per venue/day | **No row represents it anywhere in 076-093.** Rejected on evidence. |
| Per funding charge | Same as per order, plus it makes the settlement net unrepresentable: the net is not the sum of any charge subset. |

**Why the unit is safe:** `venue.on_payout_settled` (`087:376`) advances the header `closed → paid`
only when *no* `cause='settlement'` payout of that settlement is non-paid — a predicate written to
tolerate N siblings, so the one-payout choice is the degenerate case of a shape the schema already
supports. Nothing needs relaxing.

**Governing split preserved.** The transfer `amount` is read from `kernel.payout.amount_minor` and
from nowhere else — never from a charge, never from Stripe. The ledger is authoritative for what is
owed. `stripe_transfer_ref` is written only from Stripe's response. Stripe is authoritative for
whether a transfer executed.

---

## 3. `source_transaction` verdict: **NOT SET on the settlement rail.** `source_transaction_ref` stays NULL for `cause='settlement'`.

### 3.1 It is a Stripe *option*, not a Stripe *requirement*

- Create a transfer requires only `amount`, `currency`, `destination`. `source_transaction` is
  documented `(string, optional)`: "transfer funds from a charge before they are added to your
  available balance." — <https://docs.stripe.com/api/transfers/create>
- Default behaviour without it: "The default behavior is to transfer funds from the platform
  account's available balance." — <https://docs.stripe.com/connect/separate-charges-and-transfers#transfer-availability>
- The only consequence of omitting it is an availability check: "Your Stripe balance must be able
  to cover the transfer amount" (<https://docs.stripe.com/api/transfers/create>); shortfall returns
  `balance_insufficient` — "the associated account doesn't have a sufficient balance available."
  (<https://docs.stripe.com/error-codes>)

So `source_transaction` is a **timing device**, not a correctness device. The belief that it is
mandatory is a **Snatch It implementation assumption**, inherited from `_shared/payouts.ts` and
never re-examined.

### 3.2 What it actually bought the resale rail

`_shared/payouts.ts:12-19` records incident 3 of 2026-08-03/04 verbatim: a **same-day** charge left
the platform available balance at $0 because its balance transaction was still `pending`,
`available_on` ≈ 7 days out. `source_transaction` fixed it because Stripe documents exactly that
carve-out: "the transfer request returns success regardless of your available balance if the related
charge hasn't settled" and "the funds don't become available in the destination account until the
funds from the associated charge are available"
(<https://docs.stripe.com/connect/separate-charges-and-transfers#transfer-availability>).

The resale rail pays out on buyer confirmation, which can be hours after the charge. There the
timing gap is real and `source_transaction` is load-bearing. **Nothing in this ruling changes the
resale rail. It keeps `source_transaction` and its `_src` key generation.**

### 3.3 Why that gap does not exist on the settlement rail

093's maturity gate (`10d`) mints the settlement payout `hold_state='held'` unless *every* predicate
is proven: policy set, covered set resolvable, no covered event cancelled, `max(event_session.ends_at)`
known and elapsed by `payout.settlement_maturity_interval` (proposed 7 days,
`G2_settlement_maturity.md:394`), no covered refund in flight, no covered dispute open. A held
payout cannot be requested (`087:463-465`) and `mark_payout_transfer_state` refuses it outright
(`085:1690`).

A settlement payout is therefore only ever executable **at least one maturity interval after the
last covered session ended** — weeks after the earliest funding charge. Every covered charge's
`available_on` has long passed. **The condition `source_transaction` exists to solve is
structurally absent here.**

### 3.4 Why it could not be used even if we wanted it

1. Not amendable: "You must specify the `source_transaction` when you create a transfer. You can't
   update that attribute later." (<https://docs.stripe.com/connect/separate-charges-and-transfers#transfer-availability>);
   `/v1/transfers/{id}` "accepts only metadata as an argument"
   (<https://docs.stripe.com/api/transfers/update>).
2. Hard per-charge ceiling: "The amount of the transfer must not exceed the amount of the source
   charge" (same URL). The settlement net is not bounded by any one charge.
3. Currency binding: "The currency of the balance transaction associated with the charge must match
   the currency of the transfer" (same URL).
4. The net is `gross − fees − refunds` minus the promoter debit. **It corresponds to no charge
   amount at all.** There is no honest mapping from it to a `source_transaction`.

Note the one direction Stripe *does* permit and that the prior reports missed: many transfers may
share ONE source charge — "You can create multiple transfers with the same `source_transaction`, as
long as the sum … doesn't exceed the source charge" (same URL). The forbidden direction is ours:
one transfer citing many charges. Confirming the asymmetry does not rescue the per-charge model,
because splitting into N transfers reintroduces N refs on a singular column and N approvals.

### 3.5 The risk this direction accepts, and its control

Without `source_transaction` the transfer draws the platform's available balance and Stripe
"doesn't automatically retry failed transfer requests"; "adding funds doesn't automatically retry
the failed action" (<https://docs.stripe.com/connect/top-ups>). **Accepted risk: a settlement
transfer can fail `balance_insufficient` if the platform has swept its balance to its own bank
between maturity and execution.**

Controls, in order:
1. **Balance preflight (code, mandatory).** `GET /v1/balance`; require
   `available[currency=usd].amount ≥ payout.amount_minor`. If short, **do not call `/transfers`** —
   this is incident 2 of `payouts.ts:10-13` (never spend an idempotency key on a request that
   cannot succeed). Record the decision, leave the payout `submitted`, retry later.
2. **Operational (owner/ops, not code).** The platform's own Stripe payout schedule must be
   **manual**, or a float maintained above the largest open matured settlement. `POST /v1/topups` is
   generally available for US platforms and is the remedy of last resort.

**Risk of the direction NOT chosen** (keep `source_transaction`, split into N transfers per charge):
N `stripe_transfer_ref` values on a write-once singular column — a schema change to a frozen,
owner-signed money table; N `request_org_payout` calls each behind aal2 + dual control; and an
amount allocation across charges that no ruling exists for. It converts a bounded operational risk
into an unbounded schema and governance risk. That is why it was rejected.

---

## 4. Schema implications — exactly what changes

| Object | Change |
|---|---|
| `kernel.payout` columns | **NONE.** |
| `stripe_transfer_ref` write-once singular (`085:133`, `conflict_locked` at `085:1712`) | **SURVIVES UNCHANGED.** One payout, one transfer, one ref. |
| `source_transaction_ref` (`085:134`) | **Shape unchanged.** Meaning assigned: NULL ⇒ funded from the platform available balance. Written only if a `cause='market_sale'` kernel payout is ever minted — none is today (the only three `insert into kernel.payout` sites are `087:341`, `090:1483`, `093:877`, causes `settlement` / `promoter_commission` / `settlement`). |
| `kernel.mark_payout_transfer_state` | **Unchanged, unchanged signature, unchanged body.** It is the sole writer of `stripe_transfer_ref` and it already does everything the executor needs. |
| `kernel.close_settlement` / `request_org_payout` / `on_payout_settled` | **Unchanged.** |
| 093 | **No slice edit required.** The generated `093_primary_ticketing.sql` is not touched. |
| Optional, non-blocking | A `COMMENT ON COLUMN kernel.payout.source_transaction_ref` recording the NULL semantics. Cosmetic; skip it rather than reopen 093. |

---

## 5. Executor specification (`payout-execute`)

Runs as `service_role`. Input: `payout_id`.

1. **Claim.** Read the payout row. Refuse unless `status='submitted'`, `hold_state='none'`,
   `stripe_transfer_ref is null`, `cause='settlement'`, `amount_minor > 0`.
   A non-null `stripe_transfer_ref` is the DB-side idempotency stop and takes precedence over
   Stripe's 24h key window (see §6).
2. **Destination.** `kernel.get_org_connect_ref(org_id)` (`093:3225`, `service_role` only). NULL ⇒
   abort, no Stripe call.
3. **Capability preflight.** `GET /v1/accounts/{dest}`; require `capabilities.transfers = 'active'`,
   exactly as `payouts.ts:83-96`. Not active ⇒ abort, no Stripe call, key unspent.
4. **Staleness re-check** (see §7.1). Recompute the covered set's succeeded-refund total; if it
   exceeds the closed header's `refunds_minor`, abort and escalate. No Stripe call.
5. **Balance preflight** (§3.5). Short ⇒ abort, no Stripe call.
6. **Create the transfer.**
   ```
   POST /v1/transfers
     amount               = payout.amount_minor
     currency             = payout.currency (lower-cased)
     destination          = org.stripe_connect_account_ref
     transfer_group       = "payout_" + payout_id
     metadata[payout_id]  = payout_id
     metadata[settlement_id] = payout.cause_ref
     metadata[org_id]     = payout.payee_org_id
     -- NO source_transaction
   Idempotency-Key: payout_<payout_id>_<destination>_v1
   ```
7. **Record.** `kernel.mark_payout_transfer_state(payout_id, 'paid', tr.id, null, command_key)`.
   This fires `venue.on_payout_settled` in the same transaction, advancing the settlement header to
   `paid` (`085:1729`, `087:376`).

### Idempotency key derivation

`payout_${payout_id}_${destination}_v1`

- `payout_id` — immutable, and `amount_minor` is never mutated after mint, so the request body is a
  function of the payout row.
- `destination` — **required in the key**: `set_org_payout_destination` can change it between
  attempts, and reusing a key with different parameters is HTTP 409
  (<https://docs.stripe.com/error-low-level#idempotency>). This is the same reasoning, and the same
  key shape, as `buildPayoutIdempotencyKey` (`payout-logic.ts:23-25`).
- `_v1` (not `_src`) — deliberately disjoint from the resale rail's key space, and it records in the
  key itself which funding generation created any given Stripe transfer.

---

## 6. Partial failure and retry

**The absorbing-state rule (load-bearing).** `mark_payout_transfer_state` allows only
`submitted→paid|failed` and `paid→reversed` (`085:1700-1704`). **There is no edge out of `failed`.**
A failed settlement payout is also unreachable by `request_org_payout` (`status in ('pending','submitted')`,
`087:450`) and can never be re-minted (`close_settlement` is forward-only and the insert is
`on conflict (idempotency_key) do nothing` on `'settlement:'||settlement_id`). **A `failed`
settlement payout permanently strands the venue's money with no operator exit.**

Therefore:

- **The v1 executor NEVER writes `'failed'`.** Every non-success leaves the row `submitted`,
  `stripe_transfer_ref` NULL, and records the reason in `kernel.admin_audit`. A stalled `submitted`
  payout is a *recoverable* hang; a `failed` one is not. Prefer the recoverable failure mode.
- **Retry is a re-run of the whole sequence** under the same idempotency key. Steps 1-5 are
  side-effect-free, so a retry that aborts early costs nothing and spends no key.
- **Beyond 24h the DB is the idempotency of record.** Stripe removes keys "after they're at least
  24 hours old" (<https://docs.stripe.com/api/idempotent_requests>), so a retry a day later would
  create a *second* transfer. Two defences: step 1's `stripe_transfer_ref is null` check, and — for
  the lost-response case where Stripe created a transfer we never recorded — a reconciliation read
  `GET /v1/transfers?transfer_group=payout_<payout_id>` before any retry older than 24h. That is
  what `transfer_group` is set for; it is the only durable handle back to an unrecorded transfer.
- `idempotency_key_in_use` (concurrent duplicate, <https://docs.stripe.com/error-codes>) ⇒ back off
  and re-read; never escalate to a second key.
- A held payout is refused by `mark_payout_transfer_state` with **both columns untouched**
  (`085:1689-1691`), so a race between a human hold and the executor cannot half-write.
- The executor **cannot** call `kernel.hold_payout` to park a problem: it is gated on
  `kernel.is_platform(...)`, which tests `auth.uid()` and is therefore false on a machine session.
  Escalation is an audit row plus a notification, and a human applies the hold.

---

## 7. Refunds

### 7.1 Refund BEFORE payout

- **Before close (the normal case).** `kernel.settlement_primary_lines` (093 slice 10b) emits a
  negative `refund_void` line; `close_settlement` puts it in the refunds bucket and mints the payout
  at the already-reduced net. Nothing special is required. If the net is not positive, no payout is
  minted at all (`if v_net > 0`).
- **After close, before the transfer.** The maturity gate holds the payout while any covered refund
  is `pending` or `submitted` (`093` `refund_in_flight`). But a refund reaching `succeeded` after
  close leaves `refunds_minor` understated, and the lines are immutable
  (`settlement_line_cause_uq`). **This is why executor step 4 exists:** recompute
  `Σ kernel.refund.amount_minor where status='succeeded'` over the covered payments and compare with
  the closed header. Mismatch ⇒ no transfer, leave `submitted`, escalate. The executor never pays a
  stale obligation. Zero SQL; a read-only guard.

### 7.2 Refund AFTER payout

Stripe does nothing for us: "refunding a charge has no impact on any associated transfers"; "It's up
to your platform to reconcile any amount owed"
(<https://docs.stripe.com/connect/separate-charges-and-transfers#issue-refunds>). `reverse_transfer`
on `/v1/refunds` applies to destination charges / `source_transfer`, not to independently created
separate transfers.

The schema already implements Stripe's own recommended remedy — reduce a later transfer. The
`refund_void` arm dedupes on *never lined before* (`093` 10b, `not exists ... l.cause='refund_void'
and l.cause_ref = r.refund_id`), so a post-payout refund lands automatically on the **next**
settlement for that scope and reduces the next net. No manual `TransferReversal` is specified for
v1: it is gated on the connected account's available balance
(<https://docs.stripe.com/connect/separate-charges-and-transfers#reverse-transfers>) and is a human
recovery action, not an executor path.

**Residual, accepted:** if the carry-forward drives the next settlement's net ≤ 0, no payout is
minted and **no org-side obligation row is created** — `kernel.identity_obligation` (`085:165`) is
identity-only. The debt is visible as a negative `venue.settlement.net_minor` but is not a durable
claim. See §8.

---

## 8. Two pre-existing defects this ruling does not create and does not fix

Both are SQL-shaped and belong to a later **094**, not to 093. Neither blocks the executor.

1. **`failed` is absorbing** (§6). Correct fix is a `failed → submitted` re-arm under
   `platform_admin`, as a body-only `CREATE OR REPLACE` of `mark_payout_transfer_state` at its exact
   existing signature. Mitigated in v1 by never writing `failed`.
2. **No org-side obligation row** for a negative carried-forward settlement (§7.2). The identity-side
   analogue (`kernel.identity_obligation`) shows the intended shape.

Also inherited, unchanged and out of scope here: `kernel.set_org_payout_destination` has zero callers,
so no org has a destination and the executor is untestable end-to-end until Connect onboarding lands
(E1); and `kernel.resolve_dispute_native` still raises unconditionally.

---

## 9. Case matrix

| Case | Payouts | Transfers | `source_transaction` | Outcome |
|---|---|---|---|---|
| 1 order → 1 payment → 1 obligation | 1 (settlement) | 1 | none | net = that order's net |
| Many orders → 1 settlement | 1 | 1 | none | N lines → 1 net → 1 transfer |
| Settlement spanning many charges | 1 | 1 | none | identical to the above; charge count is irrelevant |
| Refund before close | 1 (reduced) | 1 | none | `refund_void` line reduces net pre-mint |
| Refund after close, before transfer | 1, unmoved | 0 | — | maturity gate or executor step 4 blocks; escalate |
| Refund after payout | 1 (already paid) | 0 new | — | carries to the next settlement's net |
| Settlement with promoter commission | 2 rows: org net (commission already deducted as a negative line), plus a separate `cause='promoter_commission'` payout minted `held`/`unfunded_settlement` (`090:1483-1491`) | 1 (org only) | none | the executor must never touch the held commission payout |
| Payout retry | 1 | 0 or 1 | none | same idempotency key; DB `stripe_transfer_ref` is the stop; `transfer_group` recovers a lost response |
| Failed Stripe transfer | 1, left `submitted` | 0 | none | audit + escalate; **never** `mark_..._state('failed')` |
