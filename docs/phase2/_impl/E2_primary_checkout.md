# E2 — `primary-checkout` edge function

**Artifact:** `supabase/functions/primary-checkout/index.ts` (new)
**Status:** AUTHORED, NOT DEPLOYED. Never deployed, never run against a remote, no Stripe call made
during development, no migration applied, no commit.
**Frozen contract:** `docs/architecture/PHASE_2_EDGE_FUNCTION_SPEC.md` §3.1 (`:355-397`).
**Owner rulings:** `docs/phase2/PRIMARY_TICKETING_OWNER_RATIFICATION.md` — **A2** (charge
architecture), **A5** (economics), **A8** (payment gating). Supporting: A1, A3, A6, A9.
**Deploy posture:** `POST` + `OPTIONS`, `verify_jwt: true`.

**It is inert today.** 093 is authored but not applied, so `venue.create_primary_checkout` refuses
before any side effect; once applied, it refuses again at the A5 rate STOP until the owner sets
`fee.buyer_service_bps`. That is the designed behaviour while the direct rail is dark, not an accident.

---

## 1. What this function is

A thin, fail-closed shell around `venue.create_primary_checkout` (migration 082). The database
creates the order, snapshots the price, proves the holds, and proves the buyer. The edge adds exactly
three things SQL cannot do: it talks to Stripe, it applies the buyer-side service fee from
configuration, and it re-asserts the money gates as defence in depth.

It does **not** reimplement pricing, does **not** decide who may sell, and does **not** confirm the
payment. Issuance happens when `payment_intent.succeeded` reaches the extended `stripe-webhook`.

---

## 2. Request contract

`POST /functions/v1/primary-checkout`
`Authorization: Bearer <supabase user JWT>` — required; absent or invalid ⇒ `401`.

```jsonc
{
  "session_id":  "uuid",              // catalog.event_session.session_id
  "items": [                          // 1..50 entries
    { "ticket_type_id": "uuid", "quantity": 1 }   // quantity 1..100, integer
  ],
  "hold_ids":    ["uuid"],            // 1..100 — the buyer's own live holds
  "command_key": "string",            // 1..200 chars; the RPC idempotency handle
  "expected_total_cents": 12345       // OPTIONAL client cross-check, integer
}
```

**Every field is a selector. None carries authority.**

| Not accepted | Why |
|---|---|
| any price / `unit_price` / `amount` | The RPC snapshots `venue.ticket_type.price_minor` server-side. A client price is not merely ignored — it is not parsed. |
| `org_id` | Server-derived from the session's event (`catalog.event_session → catalog.event.org_id`), then re-derived from the created order and compared. |
| `buyer_id` | `auth.uid()` / `user.id` only (C35). |
| any `acct_…` / connected account | The PI is minted on the platform account. No account id is ever read from a request. |
| `rail` / `mode` | Fixed by this function. |

`expected_total_cents` is **compared and discarded** via the rail-neutral `totalMismatch`
(`_shared/money.ts`). A client that sends nothing skips the check; the server charges its own
calculation either way.

---

## 3. Response contract

`200`:

```jsonc
{
  "order_id":                   "uuid",     // venue."order".order_id
  "clientSecret":               "pi_..._secret_...",
  "paymentIntentId":            "pi_...",
  "amount":                     10000,      // FACE total — venue entitlement basis
  "buyer_fee":                  1000,       // buyer-side service fee (A5)
  "seller_fee":                 0,          // no individual seller on this rail
  "total":                      11000,      // ← THE ALL-IN CHARGE
  "currency":                   "USD",
  "customerId":                 "cus_...",
  "customerEphemeralKeySecret": "ek_..."
}
```

Shape mirrors `create-payment-intent` per §3.1 "Response", plus `order_id` and `currency`.

**The same shape is returned on an `idempotency_replay`**, with `amount`/`buyer_fee`/`total` read back
from the stored `payments` row rather than recomputed — see §10. A replay never re-prices.

### The all-in contract (`src/lib/pricing/allIn.ts`)

`total` is the single honest number. **AB-11 is CLOSED:** `allIn.ts` was rewritten for A5 and no
longer accepts a single "server total" a caller could fill in with `order.total_minor`. It now demands
the face value and the buyer fee separately. Pass the whole response to the purpose-built reader:

```ts
import { allInFromPrimaryCheckout } from '@/src/lib/pricing/allIn';

const price = allInFromPrimaryCheckout(res);            // res = this 200 body
// price.kind === 'all-in'  -> price.totalMinor is THE charge (= amount + buyer_fee)
//                             price.faceValueMinor / price.buyerServiceFeeMinor itemize it
// price.kind === 'unavailable' -> render no all-in claim; see price.reason
```

or, when the three numbers are already destructured:

```ts
allInPrice({
  rail: 'direct',
  faceValueMinor: asCents(res.amount),                              // face — NOT the price
  buyerServiceFee: { source: 'server-quote', feeMinor: asCents(res.buyer_fee) },
  chargeTotalMinor: asCents(res.total),                             // ← the charge, cross-checked
  currency: res.currency,
});
```

**Feed it `total`, never `amount`.** The module now enforces this rather than asking for it: it
verifies `total === amount + buyer_fee` and refuses with `quote-incoherent` if not, which is the
client twin of this function's own `quote_incoherent` 500. An absent `buyer_fee` refuses with
`service-fee-unset`, the client mirror of the `503` in §4. `amount` and `buyer_fee` exist to itemize
a receipt, never to be displayed as "the price". Contract: `docs/phase2/_impl/G5_pricing_contract.md`.
See **AB-10**.

---

## 4. Error contract

| Status | `code` | Meaning |
|---|---|---|
| 400 | — | Malformed body / failed selector validation |
| 401 | `unauthenticated` | Missing, invalid, or expired JWT |
| 403 | `account_deletion_pending` | Buyer has a pending deletion (OR-17 F-5) |
| 403 | `identity_erased` | Buyer identity ERASED (E-23) |
| 404 | `not_found` / `org_not_found` | Session, event, ticket type, or organization missing |
| 405 | — | Method other than POST/OPTIONS |
| 409 | `not_on_sale` / `session_terminal` | Event not `on_sale`/`live`, or session terminal |
| 409 | `hold_invalid` | Holds expired or do not cover the requested quantities |
| 409 | `precondition_failed` | Any other RPC precondition, **surfaced with the RPC's own text** |
| 409 | `total_mismatch` | Client's claimed total ≠ server total (`server_total_cents` returned) |
| 409 | `already_paid` | The idempotent replay returned an already-succeeded PI |
| 409 | `unsupported_currency` | Order currency is not USD |
| 429 | — | Rate limit `check_rate_limit(user,'primary-checkout',5,60)` |
| 503 | `service_fee_unset` | **AB-1** — RPC's A5 owner STOP: `fee.buyer_service_bps` has no value. Sentry-flagged as an activation blocker, `Retry-After: 300` |
| 503 | `service_fee_out_of_range` | RPC: rate is not an integer `0..10000`. Owner typo; also Sentry-flagged |
| 409 | `org_not_eligible` | RPC's `payout_not_ready` — the SQL twin of the edge eligibility check |
| 409 | `quote_unavailable` | Replay whose original PaymentIntent is missing or dead — the quote cannot be reconstructed. Client must retry with a **new `command_key`** |
| 500 | `quote_incoherent` | RPC returned a success result whose fee/charge fields are absent or fail `charge = face + fee` |
| 503 | `replay_recovery_failed` | Replay lookup could not complete |
| 503 | `org_id_unavailable` | **E2-RT-A-6** — RPC returned no `org_id`; the frozen metadata contract cannot be written. Sentry `activation_blocker` |
| 409 | `command_key_session_mismatch` | A `command_key` replayed against a different session (see §10) |
| 503 | `org_eligibility_unverified` | **AB-4/6** — eligibility could not be proven |
| 503 | `payments_shape_unmigrated` | **AB-5** — `public.payments` cannot store the row |
| 503 | `eligibility_unverified` | Deletion-state probe failed |
| 500 | — | Genuine fault; Sentry-captured, generic message to the client |

RPC refusals are surfaced **faithfully**, not swallowed. Message text is passed through only for the
enumerated precondition families whose strings are authored in our own migrations; an unrecognized
Postgres error becomes a generic `500` so no unexpected database message is reflected to a client.

---

## 5. THE STRIPE METADATA CONTRACT

**The webhook dispatches on this. Treat it as a wire protocol: additive only, never renamed.**

### Keys written

| Key | Value | Source |
|---|---|---|
| `rail` | `"native_primary"` | constant — **the dispatch key** |
| `mode` | `"native_primary"` | constant — identical value, corroborating |
| `order_id` | uuid | `venue."order".order_id` |
| `buyer_id` | uuid | `auth.users.id` |
| `org_id` | uuid | `venue."order".org_id` (server-derived) |
| `session_id` | uuid | `catalog.event_session.session_id` |

### Why both `rail` and `mode`

The frozen corpus pins **`rail`**, and only `rail`:

- `PHASE_2_EDGE_FUNCTION_SPEC.md` §3.1 `:373` — metadata `{ rail:'native_primary', order_id,
  buyer_id, org_id, session_id }`.
- `PHASE_2_EDGE_FUNCTION_SPEC.md` §4 `:1206` — *"New / modified branches, all keyed off
  `metadata.rail`"*, followed by a routing table whose second column is headed `metadata.rail` with
  values `native_primary`, `native_resale`, `native_*`.

`mode` is set to the **same** value as a cross-check, because it is also the
`public.payments.mode` member for this rail and a webhook author reaching for the familiar legacy key
must not find it empty. Setting it is safe: the legacy resale handler is a **closed two-branch
selection** on `metadata.mode` over `{buy_now → mark_listing_sold, auction → complete_auction_payment}`
with an explicit error return as its third branch (`stripe-webhook/index.ts:376-395`, documented at
`074_privilege_cleanup.sql:170-177`). So `mode="native_primary"` reaching a legacy path fails
**closed** with `unknown_mode` — it can never take a resale money path.

> **RECONCILIATION NOTE.** The coordinating brief stated the dispatch key is `mode`, citing
> `074:172-177`. That citation describes the **legacy resale** RPC-name selection, not the primary
> rail. The two spec sites it also cited (`:373`, `:1206`) both say `rail`. Writing both keys with an
> identical value makes the question moot for every consumer. **Branch on `rail`; assert
> `mode === rail` before acting. If they ever disagree, the PI was not written by this function —
> fail closed.**

### Keys deliberately absent

`listing_id`, `seller_id` — there is no listing and no individual seller on this rail (ruling A1),
and the 093 rail-pairing CHECK requires both columns NULL on a `native_primary` payments row.
No price or fee fields — money facts live in `public.payments` and on the PI, never in mutable
metadata a reader might mistake for authority.

### Required webhook branch order (fail-closed)

1. `rail === "native_primary"` → **native primary branch**.
2. `rail` absent or `""` → **legacy resale**, which then runs its own existing `mode ∈ {buy_now,
   auction}` selection. `create-payment-intent` sets no `rail` key at all and the production rows
   predate this contract, so **absence is the only legitimate resale signal**.
3. `rail` any other non-empty value → **UNKNOWN. Do not fall through to resale.** Fail closed, alert,
   leave the event for replay. `native_resale` will arrive here as a new value.

### What the native branch resolves, and from where

- **the order** → `metadata.order_id`. There is **no `public.payments.order_id` column and there
  never will be**: EDGE_FUNCTION_SPEC §9 recon #1 supersedes §3.1's earlier "new `order_id` linkage
  column" phrasing — *"No column is added to the frozen `public.payments` table — ever."* The forward
  link lives in `kernel.payment_native`, written at finalize.
- **the payments row** → `SELECT … WHERE stripe_payment_intent_id = <pi.id>` (UNIQUE), exactly as the
  legacy branch does. Its `id` is finalize's `p_payment_id`.
- **issuance** → `venue.finalize_primary_order(p_order_id, p_payment_id, p_command_key,
  p_instrument_fingerprint)` — service_role only, migration 085. It re-verifies the payment is
  `succeeded`, belongs to the order's buyer, and **covers** `order.total_minor` (`085:1919-1934`).
  The service fee is added **on top** of face, so `payments.total ≥ order.total_minor` holds by
  construction and that cover check passes.
- **terminal failure** → `venue.cancel_pending_order(order_id, 'payment_failed', command_key)`.
  `p_reason_code` is a **closed set of one** (082 §20.7.9) — only on a genuinely terminal
  PaymentIntent, never a per-attempt decline.

This function writes the `public.payments` row itself, pre-charge and `pending`, so the webhook never
has to synthesize one.

---

## 6. The `public.payments` row

| Column | Value | Note |
|---|---|---|
| `listing_id` | `NULL` | required NULL by the rail-pairing CHECK |
| `seller_id` | `NULL` | required NULL by the rail-pairing CHECK |
| `buyer_id` | buyer | |
| `amount` | face total | `Σ(order_item.unit_price_minor × quantity)` — venue entitlement basis |
| `buyer_fee` | service fee | the platform's buyer-funded revenue (A5) |
| `seller_fee` | `0` | no individual seller |
| `total` | face + fee | what the card is charged; `≥ order.total_minor` |
| `mode` | `'native_primary'` | the widened CHECK member |
| `status` | `'pending'` | |
| `stripe_payment_intent_id` | `pi.id` | UNIQUE — the retry-safety anchor |
| `stripe_livemode` | Stripe's own `livemode` | never inferred (migration 045) |

The 093 rail-pairing CHECK this is written against:

```sql
((mode in ('buy_now','auction') and listing_id is not null and seller_id is not null)
  or (mode = 'native_primary'   and listing_id is null     and seller_id is null))
```

---

## 7. Fee handling — ruling A5

Economics are **buyer-funded**. Venue entitlement **begins at face value**; nothing is subtracted
from it. The platform's revenue is a service fee **added on top**.

### The rate is resolved in SQL, not here

The edge originally read `catalog.platform_config` itself. It cannot: the key is minted
`visibility='restricted'`, so RLS `catalog_platform_config_sel_restricted` (`078:353-361`) hides it
from a buyer (not `platform_admin`/`platform_risk`), and `service_role` has no `catalog` USAGE
(`076:76`). **093 slice 30 moved the resolution into `venue.create_primary_checkout`**, which is
`SECURITY DEFINER` — its owner is the only credential in the system that can read the key.

The RPC's **success** return carries three money fields with three different meanings:

| Field | Meaning | May it be the charge? |
|---|---|---|
| `total_minor` | **FACE VALUE** — venue gross entitlement; what the settlement seam reads | **NEVER** |
| `buyer_fee_minor` | buyer-funded platform revenue | no |
| `charge_total_minor` | the PaymentIntent amount | **this one, and only this one** |

Slice 30 calls folding the fee into `total_minor` *"the single most misreadable line in this
migration"* — it would pay the venue the platform's own revenue, in an append-only ledger with a
write-once header.

**There is exactly one source of truth for the buyer's price: the RPC's return value.** This function
reads `charge_total_minor` or refuses. It computes, infers, rounds and defaults **nothing** — verified
by scan: no `Math.round`, no `10000`/`10_000`, no `* bps`, no `money.ts` rate symbol appears in the
file. A second pricing implementation would be a second answer.

Arithmetic is re-validated before use — `charge_total_minor` must be a positive safe integer,
`buyer_fee_minor` a non-negative safe integer, and `charge = face + fee` — so a missing field can
never reach Stripe as `"undefined"` or `NaN`. A failure is `500 quote_incoherent` + Sentry: a success
return that does not add up is a contract break between this function and the RPC, not a client error.

### The unset-rate STOP

The RPC raises `precondition_failed: service_fee_unset`. The edge surfaces it as **`503`
`service_fee_unset`** with `Retry-After: 300` and a Sentry capture tagged `activation_blocker` — never
a silent zero, never collapsed into a generic 400. It is the refusal that will be seen at activation
if the owner never set the rate, and it names its own cause.

*(A8's "until the owner sets a value, the platform's share on direct sales is zero" describes the
**settlement seam** writing no revenue line. It is not a licence for checkout to quote a 0% total.)*

### Replay carries no fee fields — deliberately (R30-4)

`idempotency_replay` returns only `{status, order_id, total_minor, currency}`. The fee is derived and
**never stored** on `venue."order"`, so re-deriving it would silently re-quote under an
already-minted PaymentIntent if the owner changed the rate in between. See §10.

## 8. Tax handling

**No tax is collected and no tax position is asserted.**

Neither rail models tax. `venue."order"` has no tax column (verified across the whole 082 table
definition, not inferred from one line), `public.payments` has none, and **no owner ruling defines
tax policy, nexus, rate sourcing, or remittance for the direct rail.** A5 lists "taxes where
economically applicable" among the adjustments to venue entitlement, which acknowledges the concept
without pricing it.

So `total` is the complete charge **under a no-tax-collected policy**. The day tax becomes applicable
this function must **refuse rather than under-quote**, mirroring `allInPrice`'s `tax-unmodelled`
refusal (`src/lib/pricing/allIn.ts`, reason `tax-unmodelled`). Inventing a rate, a rounding order, or a jurisdiction
here would make every "all-in" label a lie at the moment it mattered. See **AB-8**.

---

## 9. Authority model — every database call, and the grant that makes it legal

The gap matrix names the Class A trap for this function: *"copying `create-payment-intent` verbatim
produces a Class A violation — that function builds its client from the service-role key."* There is a
second, sharper trap underneath it, found by red-team **RT-A-6**: **`service_role` holds USAGE at most
in the Phase-2 planes and NO table privileges anywhere in them.**

- `085:2088` — *"the venue schema opens to service_role — **USAGE ONLY**"*
- `085:2092` — *"the kernel schema opens to service_role — **USAGE ONLY**"*
- `076:76` — `catalog` USAGE goes to `anon, authenticated` only; service_role gets **nothing**
- No migration grants `service_role` any table privilege in `venue`, `kernel`, `catalog`, or `market`

**The design is that the machine plane reaches these schemas exclusively through `security definer`
RPCs.** Any `.from(<phase-2 table>)` with the service client is a 42501 on *every* request, not an
edge case. Two such reads existed in this function and are gone.

### The inventory

| # | Call | Client | Schema | Grant that makes it legal |
|---|---|---|---|---|
| 1 | `auth.getUser(token)` | `service` | — | GoTrue admin API, not SQL |
| 2 | `rpc('check_rate_limit')` | `service` | `public` | `public` function; service_role holds privileges in `public` |
| 3 | `from('profiles')` select/update | `service` | `public` | `public` table; service_role bypasses RLS and holds table privileges |
| 4 | `rpc('is_deletion_pending')` | `service` + `db:{schema:'kernel'}` | `kernel` | USAGE `085:2095` **+ EXECUTE to service_role**, `077` DEF class (`:2140-2157`) |
| 5 | `rpc('create_primary_checkout')` | **caller JWT** + `db:{schema:'venue'}` | `venue` | USAGE to `authenticated` `076:78` **+ EXECUTE to `authenticated`** (082 §9 / 093 slice 30). **EA-1: must be the caller's JWT** — the RPC derives buyer, holds and gates from `auth.uid()`, and is *not* granted to service_role |
| 6 | `from('payments')` select ×3 / insert | `service` | `public` | `public` table; frozen Phase-0 surface |

**Six calls. Two schemas reached with the service key, both RPC-only. Zero direct reads of any
Phase-2 table.**

### What was removed, and why it cannot come back

| Removed | Why it was illegal | Replacement |
|---|---|---|
| `from('platform_config')` (`catalog`) — the fee read | service_role has no `catalog` USAGE at all; a buyer fails RLS `catalog_platform_config_sel_restricted` | Fee resolved inside the definer RPC (§7) |
| `from('event_session')` / `from('event')` (`catalog`) — org resolution | same | `org_id` from the RPC result (§9b below) |
| `from('order')` (`venue`) — order read-back | USAGE without table privileges ⇒ 42501 | `org_id` from the RPC result |
| `from('organization')` (`kernel`) — eligibility re-check | USAGE without table privileges ⇒ 42501 | none needed — the SQL gate is authoritative |

**None of these may be fixed with a grant.** `grant select on venue."order" to service_role` would
hand a leaked edge key the whole order table **including `buyer_id`** — the attendee-roster surface
ruling F exists to close, and the red team has shown the roster is reconstructable by a weaker path.

### §9b — why there is no edge-side A8 eligibility check

The check cannot be written by any legal path from here:

- `kernel.organization` is unreadable by the service client (above), and column-scoped to org staff
  for `authenticated` — a **buyer holds no role on the selling organization**.
- The only definer accessor, `kernel.get_org_connect_state` (slice 30 §6), is granted to
  `authenticated` and **explicitly never to service_role** — *"the machine plane has no business
  enumerating payout state"* — and its body requires `org_owner`/`org_finance`.

It is also unnecessary. The authoritative gate is the `payout_not_ready` precondition **inside**
`venue.create_primary_checkout`: same two operands (`stripe_connect_account_ref` present AND
`connect_transfers_active`), run before any inventory work and before the rate is read, **in the same
transaction as the price snapshot** — strictly stronger than an edge re-read taken moments later
against a row that could have changed in between. Reaching the PaymentIntent at all means it passed.

### §9c — `org_id` comes from the RPC result

`metadata[org_id]` is required by the frozen webhook contract, and the order read-back that used to
supply it is gone. The other fields that read supplied (`buyer_id`, `event_session_id`, `total_minor`)
were being compared against values the RPC had *just derived itself* — checking the RPC against
itself, proving nothing it did not already guarantee.

**OWNER-OWED (E2-RT-A-6):** slice 30 must add `org_id` to the **success** return of
`venue.create_primary_checkout`. `v_org_id` is already resolved at the top of that function for the A8
gate, so this is one key in an existing `jsonb_build_object`. It is **not** needed on the replay
returns — the replay path reuses an existing PaymentIntent and mints no metadata.

Until then the function **fails closed**: `503 org_id_unavailable` + Sentry `activation_blocker`.
Minting a PaymentIntent with an absent or guessed `org_id` would write a metadata contract the webhook
cannot dispatch on, and attribute money to no organization.

## 10. Idempotency and retry safety

**Two independent layers; neither alone is sufficient.**

1. **Order** — `venue.create_primary_checkout` dedupes on `UNIQUE(buyer_id, command_idempotency_key)`
   (C16). A replay returns `status:'idempotency_replay'` with the **same** `order_id`. A retry with
   the same `command_key` cannot create a second order, and the C16 race is caught inside the RPC and
   also returned as a replay rather than a raw 23505.
2. **PaymentIntent** — deterministic key **`pi_native_${order_id}_c${customerId}`**. A double-tap
   replays the **same** PI. The customer id is in the key because it is in the **body**: a customer
   re-created mid-window under an unchanged key would trip Stripe's idempotent-parameters error and
   brick the order's checkout for 24h.

   **The charge total is deliberately NOT in the key** — a change from the resale rail's shape, and
   from this function's own first draft. It is unnecessary (`order_id` is unique per
   `(buyer, command_key)`, so a genuinely new checkout always yields a new key), and it would be
   **unreconstructible on the replay path**, since the RPC returns no fee fields there. A key
   containing the charge total is precisely how a second PaymentIntent gets minted for one order.
   Keying on `order_id` makes "one order, one PaymentIntent" true by construction.
3. **Dead-PI escape** — if the replay returns a `canceled` PI (unconfirmable; returning its
   `client_secret` hard-fails PaymentSheet), one uniquely-salted retry escapes the window. The resale
   rail salts *predictively* from a stored failed-attempt count; this rail cannot, because
   `public.payments` carries no order linkage **by ruling**, so the salt is applied **reactively** on
   observing the dead replay.
4. **Payments row** — because the deterministic key means a retry arrives holding the **same** PI id,
   a pre-existing row for that PI **is** this payment: it is returned rather than re-inserted. A
   23505 race is recovered by re-selecting the winner. Net: **one order, one PaymentIntent, one
   payments row.**

A `succeeded` PI or a `succeeded` payments row ⇒ `409 already_paid`, never a spent `client_secret`.

### The replay path — reuse the quote, never re-derive one

On `idempotency_replay` the handler **short-circuits before any pricing or PI creation**. The original
quote survives in two places, and both are read back:

1. **Candidates** — a narrow selector on `public.payments`:
   `(buyer_id, mode='native_primary', amount = total_minor, status IN pending/processing/succeeded)`,
   capped at 10 rows. This is a **filter, not an identification** — two pending orders at the same
   face total would both match.
2. **Confirmation** — each candidate's PaymentIntent is retrieved and must carry
   `metadata.order_id === <this order>` **and** `metadata.rail === 'native_primary'`.
   **The PI metadata is the authority**; the DB selector only narrows the search. This is what makes
   the recovery exact rather than heuristic — necessary because there is no `payments.order_id` column
   (§9 recon #1) and `kernel.payment_native` is not written until finalize, so no order→payment link
   exists at checkout time.

Outcomes:

| Result | Response |
|---|---|
| one live confirmed PI | `200` reusing its `client_secret`, with `amount`/`buyer_fee`/`total` read from the stored `payments` row — **the original quote, not a recomputation** |
| any confirmed PI succeeded | `409 already_paid` |
| none confirmed, or all cancelled | `409 quote_unavailable` — see RES-1 |
| more than one live | `500` + Sentry; never guess which PI the buyer is looking at |
| lookup failed | `503 replay_recovery_failed` |

Stripe's PaymentIntent **search** API was rejected here: it is eventually consistent (~a minute), and
the dominant replay case is a double-tap seconds apart, which search would miss — producing a spurious
"no quote" exactly when the buyer is looking at the sheet.

`expected_total_cents` is still honoured on the replay path, compared against the **recovered** total.

### C16 — the replay match ignores session and items. Decision: check session, not items.

`venue."order"` is UNIQUE on `(buyer_id, command_idempotency_key)` only, so the same `command_key`
replayed with a different session or different line items returns the **original** order rather than
refusing. Slice 30 makes that choice deliberately: *"an order that already exists is a settled fact,
and re-refusing it would turn a harmless client retry into a phantom failure after the money decision
was already taken."* That is correct and is not changed here.

**What is and is not at risk.** `buyer_id` is *in* the uniqueness key, so a replay can only ever return
the caller's **own** earlier order — never someone else's quote. The residual is narrower than "someone
else's quote": a buggy client reusing one `command_key` across two checkouts gets the first order's
quote for the second checkout's intent, silently.

- **SESSION — checked.** The PaymentIntent carries `metadata.session_id`, which `recoverReplayQuote`
  has already fetched. Comparing it to the request costs **no extra read** and converts a silent
  wrong-quote into `409 command_key_session_mismatch`. (That metadata is data we wrote ourselves on the
  platform account, not caller input.)
- **ITEMS — not checked, deliberately.** Proving them needs `venue.order_item`, which no edge
  credential may read (RT-A-6). The `expected_total_cents` cross-check already catches the case that
  matters — a client whose displayed total disagrees with what it is about to be charged. A client
  showing the right total for the wrong basket is a bug this layer cannot see and must not guess at.

**Orphan handling.** A PI that cannot be recorded is **cancelled** — otherwise it strands an
authorization against the buyer's card and leaves a chargeable object the webhook cannot reconcile.

**Ordering rationale.** The A8 eligibility gate and the A5 fee gate both run **before** the checkout
RPC. If they ran after, an ineligible or unpriceable request would leave a `pending` order that
cannot be honestly retired: `venue.cancel_pending_order` accepts the single reason code
`'payment_failed'`, and no payment failed. Gating first means no such order is ever created.

**Residual (RES-1) — the unrecoverable replay.** If the original attempt died between the RPC and the
PaymentIntent (or its PI was cancelled), the order exists but no quote does, and the RPC will not
re-derive one. The charge total **cannot be reconstructed**, and inventing one is the exact failure
R30-4 exists to prevent. The handler returns `409 quote_unavailable` telling the client to start again
with a **new `command_key`** — which takes the success path and gets a real quote. The stranded order
stays `pending`; its capacity returns via the 081 hold-TTL sweep. It is not cancelled, because
`venue.cancel_pending_order` accepts only `'payment_failed'` and no payment failed. Accepted.

---

## 11. ACTIVATION BLOCKERS

Every one of these fails **closed**. The function is inert until they are resolved.

| # | Blocker | Evidence | Effect today | Owner |
|---|---|---|---|---|
| **AB-1** | **The buyer-side service-fee rate is UNSET.** 093 mints `fee.buyer_service_bps` with `'null'::jsonb`, deliberately — A5: *"No percentage is invented anywhere."* And 093 is **not applied**. | `093_parts/40:…`; slice 30 `:471` | RPC raises `service_fee_unset` ⇒ **`503 service_fee_unset`** + Sentry `activation_blocker`. | **OWNER** sets the rate via `set_platform_config`. A5/A8: selling must not be activated while it is unset |
| **AB-2** | ~~Key name unratified~~ — **RESOLVED.** `fee.buyer_service_bps`. | `093:2388` | none | closed |
| **AB-3** | ~~Rate unreadable by the edge~~ — **RESOLVED BY MOVING THE READ INTO SQL.** The key is `restricted`; no edge credential can read it (buyer is not `platform_admin`/`platform_risk`, `076:76` gives `service_role` no `catalog` USAGE). 093 slice 30 resolves it inside `venue.create_primary_checkout`, which is `SECURITY DEFINER`. **The edge no longer reads `catalog` at all.** | slice 30 `:460-478`; `078:353-361`; `076:76` | none — and the edge no longer depends on `catalog` PostgREST exposure either | closed |
| **AB-4** | ~~Value shape undetermined~~ — **RESOLVED.** Bare integer bps `0..10000`, validated in SQL (`service_fee_out_of_range`). | slice 30 `:475-478` | none | closed |
| **AB-4b** | **`venue.create_primary_checkout` does not return `org_id`.** Needed for the frozen `metadata[org_id]`; the read-back that used to supply it was illegal (RT-A-6). | slice 30 return at `:585-588` | `503 org_id_unavailable` + Sentry. | **Slice 30 author** — one key in an existing `jsonb_build_object`; `v_org_id` is already in scope. Success return only |
| **AB-5** | **`venue` is not exposed over PostgREST.** Exposure is `public, graphql_public, kernel`. | `PHASE2_PRIMARY_ACTIVATION_GAP_MATRIX.md:57`, row C2 | The checkout RPC call fails ⇒ `503`. **`catalog` exposure is no longer needed by this function** (AB-3) — but is still needed by the client's prior `reserve_primary_inventory` / event browsing. | **Operational config**, not a migration |
| **AB-6** | **`public.payments` cannot store a native-primary row until 093 APPLIES.** Today `listing_id NOT NULL`, `seller_id NOT NULL`, `mode CHECK IN ('buy_now','auction')`. 093 is authored but **not applied**. | `000_baseline_schema.sql:973`, `:995`; `093:792`, `:869` | `23502`/`23514` ⇒ `503 payments_shape_unmigrated` + orphan PI cancelled. | **Apply 093.** Insert verified to match its rail-pairing CHECK exactly. |
| **AB-7** | **`kernel.organization.connect_transfers_active` does not exist until 093 APPLIES.** 093 adds it `boolean not null default false`, with `connect_state_synced_at` and the service_role-only `kernel.sync_org_connect_state`. | `077:110-126` (absent); `093:1268`, `:1275`, `:1410` | Eligibility read errors (42703) ⇒ `503 org_eligibility_unverified`. **Correct direction.** Post-apply the default `false` means every org is ineligible until Stripe state is synced — also correct. | **Apply 093**, then run the Connect state sync |
| **AB-8** | **The authoritative A8 gate lands only when 093 APPLIES.** 093 §3 puts the readiness precondition *inside* `venue.create_primary_checkout`. | `093:1414+` (§3) | The edge check here is **defence in depth only**. If `venue` were exposed (AB-5) before 093 applies, a direct PostgREST call to the RPC would bypass the edge entirely. **Apply 093 before exposing `venue`.** | ordering constraint below |
| **AB-9** | **TAX IS NOT MODELLED AND MUST NOT BE INVENTED.** No tax column on `venue."order"` or `public.payments`; no ruling defines policy, nexus, rate sourcing, or remittance. | `082` table def; `allIn.ts:32-36`; A5 | Zero tax collected; no tax position asserted. If tax ever applies, this function must **refuse**, not under-quote. | **OWNER POLICY DECISION — unowned** |
| **AB-10** | **Processing-cost allocation is unruled.** A5 surfaced it explicitly: *"no ratified ruling allocates Stripe processing cost on the primary rail"*, and it is **not** encoded in 093. Because A5 fixes venue entitlement at face value and forbids silent subtraction, the cost lands on the platform's side **by elimination — an inference, not a ruling.** | `PRIMARY_TICKETING_OWNER_RATIFICATION.md` A5 open item | Not encoded here. The service fee is the only platform revenue this function creates; whether it must cover processing cost is an owner number. | **OWNER — carried, not closed** |
| **AB-11** | ~~**`src/lib/pricing/allIn.ts` is stale post-A5.**~~ **CLOSED.** The module's direct rail was rewritten for A5: `serverTotalMinor` is gone, replaced by a required `faceValueMinor` + `buyerServiceFee` pair, a cross-checked `chargeTotalMinor`, and `allInFromPrimaryCheckout()`. | `allIn.ts` (rewritten); `docs/phase2/_impl/G5_pricing_contract.md` | The under-show is now unrepresentable: there is no single "total" field to fill in with `order.total_minor`, an unset fee refuses (`service-fee-unset`), and a quote that fails `charge = face + fee` refuses (`quote-incoherent`). | **DONE** — G5 |
| **AB-12** | **No hold can exist, so no checkout can succeed even with all of the above.** `feature.native_issuance_enabled` is `false`, and `inventory.hold_ttl_interval` / `inventory.per_user_active_hold_max` rows **do not exist** — the reserve RPC refuses `hold_ttl_unset` / fails-to-zero on the cap. | gap matrix rows D3, E1, E2, E3 | The RPC returns `holds do not cover` ⇒ `409 hold_invalid`. | 093 (create keys) + owner values + flag flip **last** |
| **AB-13** | **Downstream, not this function: no signing key can exist.** `kernel.provision_signing_key` / `rotate_signing_key` are hard-raise stubs (PFA-18A). | `083:375-393`; gap matrix G1 | Checkout could mint a PI, but `venue.finalize_primary_order` would fail at the mint. **Do not activate collection before issuance can complete** — that is charging for a ticket that cannot be issued. | Owner ruling + 093+ |
| **AB-14** | **Metadata key discrepancy, resolved defensively.** Brief said `mode`; frozen corpus (`:373`, `:1206`) says `rail`. Both are written with the identical value `native_primary`. | §5 above | None — moot for every consumer. Recorded so the webhook author branches on `rail` and asserts `mode === rail`. | Reconcile in the webhook branch |

### Ordering constraints

1. **Apply 093 before exposing `venue` over PostgREST (AB-8 before AB-5).** Exposing the schema while
   093's SQL readiness gate is absent opens `venue.create_primary_checkout` — which is granted to
   `authenticated` — to direct client calls with no gate at all. The edge check would then be
   defending a door it no longer stands in front of.
2. **AB-13 before activation.** Collection must not be switched on ahead of issuance — charging for a
   ticket that cannot be minted is worse than not selling.
3. **`feature.native_issuance_enabled` flips LAST**, after AB-12's inventory keys are seeded and
   valued.

### Note on 093

`supabase/migrations/093_primary_ticketing.sql` was authored by another agent while this function was
being written, and this document has been reconciled against it. **It is authored, not applied.**
Verified points of agreement, byte-for-byte:

- the config key spelling, units, and null value (`093:2388`, `:2364-2370`);
- the widened `mode` CHECK and the rail-pairing CHECK the `payments` INSERT is written against
  (`093:792`, `:869`);
- `connect_transfers_active` / `connect_state_synced_at` column names (`093:1268`, `:1275`);
- and 093's own restatement of the frozen metadata as `{ rail:'native_primary', order_id, buyer_id,
  … }` (`093:809`), which independently corroborates §5's dispatch key.

---

## 12. What this function deliberately does not do

- **No connected-account charge.** Ruling A2: separate charges and transfers. No `transfer_data`, no
  `on_behalf_of`, no `application_fee_amount`, no `Stripe-Account` header — verified absent from the
  source except in prohibitory comments. Snatch It is merchant of record; **a successful charge
  implies no venue payout.**
- **No pricing.** The RPC is the sole price authority.
- **No inventory reservation.** Holds are created by a **prior client-direct** call to
  `venue.reserve_primary_inventory` (gap matrix D5 corrects the contrary assumption).
- **No payment confirmation and no issuance.** Both belong to the webhook.
- **No settlement, no payout, no promoter commission.** Nothing here releases money.
- **No edits to `stripe-webhook`, `create-payment-intent`, or `create-connect-account`** — owned by
  other agents this cycle. The Stripe-customer helper is duplicated locally rather than refactored
  into `_shared/` for that reason; lifting both into `_shared/stripe-customer.ts` is a later,
  separate change.

## 13. Verification performed

- Strict TypeScript check clean (`tsc --strict --noResolve`; only unresolved-URL-import and missing-
  `Deno`-global artifacts remain, both expected outside the Deno toolchain).
- Source scan confirms all four A2-forbidden Stripe parameters appear **only** in prohibitory
  comments, and that no fee percentage and no `money.ts` rate symbol is referenced.
- **Not deployed. No Stripe API call made. No migration applied. No remote touched. No commit.**
