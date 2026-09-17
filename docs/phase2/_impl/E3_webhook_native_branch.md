# E3 — `stripe-webhook`: the NATIVE PRIMARY branch and the `account.updated` organization arm

Owner rulings **A2** (separate charges and transfers, platform is merchant of record),
**A3** (durable internal obligation facts), **A6** (the Connect account belongs to the
organization), **A8** (payment gating derives from the `transfers` capability).

Spec: `docs/architecture/PHASE_2_EDGE_FUNCTION_SPEC.md` §4 (extend, do not fork).
Ratification: `docs/phase2/PRIMARY_TICKETING_OWNER_RATIFICATION.md`.

**Status: authored, typechecked, unit-tested. NOT DEPLOYED. No remote was touched, no
Stripe call was made, no migration was applied, nothing was committed.**

## Files

| File | Change |
|---|---|
| `supabase/functions/stripe-webhook/native.ts` | **NEW.** Import-free decision logic (dispatch, replay/idempotency, out-of-order, error classification, plane selection). |
| `supabase/functions/stripe-webhook/index.ts` | Three branches added; the I/O shell for the above. |
| `tests/stripe-webhook-native.test.ts` | **NEW.** 81 vitest cases. |

Nothing outside `stripe-webhook/` was modified. `primary-checkout/`, `connect-onboarding/`,
`refund-execute/`, `create-connect-account/`, `_shared/` and every migration are untouched.

---

## 1. Dispatch table — before and after

The contract is keyed off **`metadata.rail`** (spec §3.1:373, §4:1206; restated at
`093:809`). `primary-checkout` writes `rail` and `mode` with the identical value
`native_primary` (`:974-975`); `create-payment-intent` writes neither `rail` nor a native
`mode`. **Absence of `rail` is the only legitimate resale signal.**

### `payment_intent.succeeded`

| `metadata.rail` | `metadata.mode` | BEFORE | AFTER |
|---|---|---|---|
| absent | `buy_now` | `mark_listing_sold` + transfer row + push · 200 | **unchanged, byte for byte** |
| absent | `auction` | `complete_auction_payment` + transfer row + push · 200 | **unchanged, byte for byte** |
| absent | anything else | `unknown_mode` → **HTTP 500, retried ~3 days** | **unchanged** (a genuine resale typo still fails closed and retryable) |
| `native_primary` | `native_primary` | **fell through to `unknown_mode` → HTTP 500, retried ~3 days, buyer charged, no ticket** | claim payments row → verify rail/buyer → read fingerprint → `venue.finalize_primary_order` · 200 |
| `native_primary` | ≠ `native_primary` | (unreachable) | `rail_mode_mismatch` → **200 + Sentry** (fail closed, no money path) |
| absent | `native_primary` | `unknown_mode` → **HTTP 500, retried ~3 days** | `rail_mode_mismatch` → **200 + Sentry** |
| `native_resale` (or any other) | — | `unknown_mode` → HTTP 500 | `unknown_rail` → **non-2xx + Sentry**, deliberately held for replay |

### `payment_intent.payment_failed` / `payment_intent.canceled`

| Event | rail | BEFORE | AFTER |
|---|---|---|---|
| `payment_failed` | absent | claim `failed`, `release_reservation` if `buy_now` · 200 | **unchanged** |
| `payment_failed` | `native_primary` | fell to the legacy claim, which matched the native row and marked it `failed` — then did nothing else | mark `failed` (guarded against `succeeded` **and** `refunded`); order left **pending** unless the PI is terminal |
| `canceled` | absent | terminal `else` → ack only · 200 | **unchanged** (same log line, same 200) |
| `canceled` | `native_primary` | terminal `else` → ack only, order stranded `pending` forever | `venue.cancel_pending_order(order, 'payment_failed', key)` · 200 |

`canceled` is the only PaymentIntent status from which no confirmation is possible, so it
is the only terminality signal. A `payment_failed` is **per attempt**: §3.1's retry contract
lets the buyer re-confirm the same PI in the same PaymentSheet, and cancelling the order on
a decline would destroy an order still being paid for. Capacity returns via the §20.3.3
hold-TTL sweep — 082 persists no order→hold linkage to release directly.

### `account.updated`

| Account | BEFORE | AFTER |
|---|---|---|
| seller profile (`profiles.stripe_connect_id` match) | 4 columns written · 200 | **unchanged**, and it still runs first |
| **organization** (`metadata.snatchit_plane='organization'` or `metadata.org_id`) | matched 0 profiles, logged `matched_profiles: 0` **inside a success line**, 200 — created and then never monitored | `kernel.sync_org_connect_state(org_id, acct_ref, transfers_active, observed_at, key)` · 200 |
| matches neither plane | success line · 200 | **200 + `captureException`** — `matched: 'none'` is no longer a success |
| matches **both** planes | (invisible) | **200 + `captureException`** — cross-plane reuse, forbidden by A7/A9 |

`transfers_active` is `capabilities.transfers === 'active'`, mirroring the shipped payout
probe (`_shared/payouts.ts:96-98`) and the 093 §1 column comment. It is **not** derived from
`charges_enabled`/`payouts_enabled`: `connect-onboarding` requests `capabilities[transfers]`
and deliberately not `card_payments` (`:544`), so `charges_enabled` is **false forever** on a
correctly provisioned org account and a gate built on it would keep every venue dark
permanently. `payouts_enabled` is ruled explicitly not a sale gate (F §3.5).

---

## 2. The exact-once argument

Four independent locks, three of them in Postgres. Money becomes tickets once, or not at all.

**L1 — event level (unchanged, inherited).** `claim_stripe_webhook_event` (migration 064) is
one atomic statement. Concurrent deliveries of one event id cannot both win the lease;
`already_processed` → 200 with no work, `in_flight` → 409. Fails **closed** on claim error.

**L2 — PaymentIntent → payments row.** `public.payments.stripe_payment_intent_id` is UNIQUE,
so a PI names **at most one** payments row. The claim UPDATE carries
`.neq('status','succeeded').neq('status','refunded')`, so the transition to `succeeded` is
itself a claim: the second delivery matches zero rows and is routed by `interpretPaymentClaim`
rather than repeating the write.

**L3 — payments row → order (THE economic anchor).**
`kernel.payment_native.payment_native_payment_uq unique (payment_id)` (085:56). Exactly one
`kernel.payment_native` row may ever exist per payment, and `finalize_primary_order` inserts
it inside the same transaction that mints the atoms and flips the order to `paid`
(085:2058-2062). **A second order can never link to the same payment**, and a second finalize
of the same order cannot commit: the `unique_violation` handler (085:2069-2081) re-reads the
order, finds it `paid`, and returns `idempotency_replay` with the *original* atom set. Under
the lock, an order already `paid` short-circuits before any mint runs (085:1969-1975).

**L4 — mint level.** The command key is forwarded to `kernel.issue_ticket_atoms` as
`key || ':' || order_item.id` and lands under
`ownership_log_command_uq unique (ticket_atom_id, command_idempotency_key)` (079:101), with
the mint's own replay short-circuit at 083:511 and its `unique_violation` twin at 083:583.

**Why the command key is `wh_native_primary:{order_id}:{payment_intent_id}` and NOT the event
id.** This is the one choice in the branch that had to be made correctly. The key is an
invariant of the **economic fact**, not of the delivery. Every delivery of every event about
this payment — a redelivery, a duplicate, a lease stolen after `LEASE_SECONDS`, or a second
Stripe event id naming the same PaymentIntent — presents the **same** key, so L4 recognises
all of them as one command. Keying on `event.id` would have made two event ids look like two
distinct commands to the mint, and L3 would then be the only thing standing between that and
a double issuance.

**Out-of-order.** `payment_intent.succeeded` arriving *after* a refund is refused twice: once
in the edge (the `.neq('status','refunded')` claim guard, then
`out_of_order_refund_precedes_success` → 200 + alert, finalize never called), and once in the
database if the edge is bypassed (`finalize_primary_order`'s `kernel.refund` probe at
085:1936-1938 raises `payment_unverified`). A late `payment_failed` after success cannot
overwrite `succeeded` (guarded), and a late `payment_failed` after a refund cannot reopen it
(guarded — this second guard is native-only; the legacy `payment_failed` already had both).

**No duplicate settlement fact, no duplicate venue obligation.** This branch writes **no**
settlement and **no** payout row. It calls exactly one verb, `finalize_primary_order`, whose
own contract is `0 DDL on any money-ledger table` (093:658). The venue-side obligation is
derived downstream from `kernel.payment_native` ⋈ `venue.order`, both of which L3 makes
single-valued per payment.

---

## 3. Failure modes handled

| Failure | Response | Why that direction |
|---|---|---|
| native PI reaches the endpoint (the pre-existing hole) | 200 after finalize | the branch now exists |
| `rail` / `mode` disagree | **200 + alert** | a redelivery carries identical metadata; retrying is pure noise on an incident that already needs a human |
| `rail` = an unimplemented value | **non-2xx + alert** | the pinned rule: "fail closed, alert, and leave the event for replay" — a rail we have not deployed is exactly what a retry window is for |
| `order_id` / `buyer_id` missing or malformed | 200 + alert | same snapshot argument |
| payments row absent, event < 15 min old | non-2xx (retry) | absorbs a lagging replica or an insert we overtook |
| payments row absent, event ≥ 15 min old or undateable | 200 + alert | bounded; the alternative is a buried alert under three days of retries |
| payments row is a resale row / another buyer's / violates the rail pairing | 200 + alert | structurally impossible under the 093 CHECK; if it happens it is a migration incident |
| refund preceded the success | 200 + alert, no mint | R6 P2 |
| buyer identity `ERASED` | 200 + alert | OR-17; the acquisition is refused forever |
| order already `cancelled` / `refunded` | 200 + alert | forward-only; no retry can move it back to `pending` |
| `oversell_rejected`, no reservation names a batch | 200 + alert | minting is not the fix |
| **no active signing key** | **non-2xx + alert** | provision one and the very next redelivery mints correctly |
| **missing GRANT (42501)** | **non-2xx + alert** | PFA-15/PFA-21 reachability is ops-fixable inside the window |
| transient Postgres (08\*, 40001, 40P01, 53\*, 55P03, 57\*, 58\*, XX000) | non-2xx | the reason Stripe retries |
| anything unclassified | non-2xx + alert | fail toward not losing the money event |
| fingerprint read fails / times out | ignored, `null` passed | RPC §17.14: no attribution input may delay or fail issuance |
| per-attempt decline | 200, order left `pending` | §3.1 retry contract |
| PI canceled | 200 after `cancel_pending_order` | forward-only; `noop_replay` on a second delivery |
| PI canceled after the order was paid | 200 + alert (`order_not_pending`) | money won |
| org account, org not yet bound | **200, no alert** | expected during onboarding; the gate operand defaults **false**, so a lost "gained" only under-permits, and a lost "lost" is impossible (losing a capability requires the org to already be bound) |
| org account not the org's bound destination | 200 + alert | G-4/A9 — the refusal *is* the correct outcome |
| org sync transient / not granted | **non-2xx + alert** | losing a capability-**lost** observation leaves an organization selling tickets it can no longer be paid for; both arms are idempotent, so redelivery is safe |
| account matches neither plane | 200 + alert | the hole this arm closes |
| one `acct_` on both planes | 200 + alert | cross-plane reuse (A7/A9) |

---

## 4. What cannot be verified without deploying

1. **Everything inside Postgres.** L3 and L4, the order lock, the batch pre-lock ordering,
   the refund probe, the ERASED refusal, `sync_org_connect_state`'s `noop_replay` and its
   `conflict_locked` refusal. These are asserted from the migration text and exercised only
   at the classifier boundary — the exact strings 082/085/093 raise are quoted in the tests,
   but *that they are raised* is a property of the SQL.
2. **PostgREST reachability.** `venue.finalize_primary_order` and `venue.cancel_pending_order`
   need `venue` in PostgREST's exposed-schema list, not merely `GRANT USAGE` (085:2091). 082's
   PART 6 header records this as **PFA-15, owner-owed**. If the schema is not exposed the call
   returns PGRST202, which this branch classifies as *unclassified → retry + alert* — the
   right direction, but the gap is real and is not closed by any code here.
3. **The live signature path** — untouched, and not re-simulated.
4. **The Stripe charge GET.** Written, never executed. It is `GET /v1/charges/{id}` with a 4s
   timeout; it moves no money and every failure path returns `null`.
5. **Concurrency in anger.** Two simultaneous deliveries taking L1 and L3 in opposite orders
   is a property of the database, not of TypeScript.
6. **Whether `event.created` is present** on every delivery. Assumed; the fallbacks are
   conservative in both places that read it.

---

## 5. Contradictions found while implementing

1. **`connect-onboarding/index.ts:684` calls `sync_org_connect_state` with a signature that
   does not exist.** It passes seven arguments —
   `(p_org_id, p_connect_account_id, p_transfers_active, p_payouts_enabled, p_requirements_due,
   p_disabled_reason, p_requirements_deadline)`. The authored function
   (`093:1300`, and `docs/phase2/_impl/093_parts/30_connect_org.sql` §2) is
   **five** arguments: `(p_org_id uuid, p_connect_account_ref text, p_transfers_active boolean,
   p_observed_at timestamptz, p_command_key text)`, and the grant at `093:1408-1410` names that
   arity. That call will fail PGRST202 at runtime. It is currently swallowed (`console.warn`,
   non-fatal), so it fails silently rather than loudly. **Not fixed here — `connect-onboarding`
   is another agent's file.** The webhook uses the authored five-argument signature.
2. **`093:2099` records `R30-2 — nothing calls kernel.sync_org_connect_state yet`.** After this
   change the webhook does. The note is now stale.
3. The brief's `metadata.mode` / `074:172-177` citation was corrected mid-task by the
   coordinator; the implementation is rail-first as built. `074:172-177` describes the *legacy
   resale* RPC-name selection and is not the primary-rail dispatch.
