# E4 — THE REFUND EXECUTOR (owner ruling D3), AND AN INSPECTION OF THE PLANNED PAYOUT EXECUTOR

> **SUPERSEDED IN PART by `docs/phase2/_impl/H1_refund_architecture.md`.** Four statements below are now
> stale, and H1 §1 shows the working for each: (a) §3 / §12 item 1 — `kernel.get_refund_execution_context`
> EXISTS (093 slice 10g); (b) §3's trailing note — `kernel.list_pending_refunds` was deliberately NOT built,
> and `kernel.claim_refunds_for_execution` (slice 10i, a LEASED CLAIM) replaces it; (c) §5's matrix omits
> Stripe's 24-hour idempotency-key retention, past which cases 2/3/13 create a SECOND real refund — the claim
> verb's `execution_mode` is what closes that; (d) §7's three authority options are moot, because the DIRECT
> arm's authority is already reachable through `kernel.request_order_refund` (H1 §5;
> `docs/architecture/_governance/PFA23_DIRECT_ARM_CLARIFICATION.md`). §6.1, §5.1 and §11 stand unchanged.


**Ruling implemented:** D3 (`docs/phase2/PRIMARY_TICKETING_OWNER_RATIFICATION.md:327-345`) — *"RATIFIED: BUILD
THE REFUND EXECUTOR NOW … PFA-23's already-frozen executor shape remains authoritative and is implemented as
specified."*
**Shape followed, not redesigned:** `085:2144-2146` names the caller verbatim — *"the refund-execute edge (as
service_role, forwarding the platform JWT for the direct arm)"*.
**Artifacts:** `supabase/functions/refund-execute/index.ts`, `supabase/functions/refund-execute/executor.ts`,
`tests/refund-executor.test.ts` (66 tests, all passing; full suite 218/218).
**Not deployed. No migration authored or applied. No Stripe object created. No commit.** Ruling D3: *"Not
deployed in this train."*

All `NNN:LL` citations are `supabase/migrations/NNN_*.sql` unless stated otherwise.

---

## 1. THE DEFECT, STATED PRECISELY

`kernel.refund_primary_order` (`085:457`) does four things in one transaction:

| Step | Line | Effect |
|---|---|---|
| voids the covered atoms | `085:593` | the buyer's ticket is gone |
| INSERTs `kernel.refund` | `085:599` | born `pending` (default, `085:84`) |
| moves the order | `085:604` | `refunded` / `partially_refunded` |
| writes the audit | `085:609` | `refund.issue` |

Nothing then calls Stripe, and `kernel.mark_refund_state` (`085:1737`) — the **only** transition out of
`pending` — had **zero callers repo-wide**. So the buyer lost the ticket and got no money. Worse, the stranded
`pending` row then blocks that buyer's account deletion **forever**: BP-12 arm 1 (`085:249-262`) blocks on
`r.status in ('pending','submitted')`.

The same shape exists on two other producers that never touch `refund_primary_order` at all:
`kernel.admin_refund` (`085:706`) and `catalog.cancel_event`, which INSERTs `kernel.refund` rows **directly**
at `088:1664` (paid-pending resale), `088:1716` (resold atoms) and `088:1774` (primary orders).

**This document's function is the missing caller of `mark_refund_state`.**

---

## 2. THE CONTRACT

```
POST /functions/v1/refund-execute
```

| action | auth | client used | RPC |
|---|---|---|---|
| `record` | platform JWT | `service_role` (delegated) / caller JWT (direct) | `kernel.refund_primary_order` |
| `admin_refund` | platform JWT | caller JWT (`085:2138` grants it to `authenticated`) | `kernel.admin_refund` |
| `execute` | platform JWT | `service_role` | `kernel.mark_refund_state` |
| `sweep` | `INTERNAL_CRON_SECRET` / service key | `service_role` | `kernel.mark_refund_state` |

**Response:** `{ status, refund_id, stripe_refund_ref?, code?, detail?, retryable? }`.

### 2.1 The invariant everything else serves

**The executor is REFUND-ROW-DRIVEN.** The payment it refunds is read out of `kernel.refund.payment_id` — an
FK with `on delete restrict` (`085:76`) — **inside the database**. There is no request field for a payment, a
PaymentIntent or a charge, and `assertNoClientPaymentReference` **refuses** a request that smuggles one rather
than ignoring it (ignoring it would let a later refactor start reading it).

Being refund-row-driven is also the single design choice that makes event cancellation work with **no special
case**: `catalog.cancel_event`'s rows are executed by `refund_id` like any other.

### 2.2 Order of operations, never reordered

```
1. RPC first   — DB records the intent + voids atoms atomically, under the payment lock, Σ-guarded
2. THEN Stripe — POST /v1/refunds, Idempotency-Key: refund_<refund_id>
3. THEN callback — kernel.mark_refund_state(refund_id, 'submitted', re_…, null, command_key)
```

A crash at any point leaves a row that a later `sweep` replays under the **same** Stripe key. Replay is never
re-pay.

### 2.3 What was reused, per ruling D3

D3 says extend the proven path rather than invent one. `enforce-transfer-expiry/index.ts:264` and `:387` are
the only `POST /v1/refunds` in the repo. Reused verbatim in shape: the endpoint and form body, the
`payment_intent`-scoped refund, the deterministic-key discipline (`refund_expiry_${transfer_id}` →
`refund_${refund_id}`), the mode boundary (`stripe_livemode = true` only, `:365-372`, migration 045), the
"one failure never blocks the batch" loop, and the self-heal sweep (Phase 1b, `:355-410` → our `action:sweep`).
Changed deliberately: `stripeFetchRaw` instead of `stripeFetch`, because `_shared/stripe.ts:79` throws away
Stripe's `error.code` and the whole retry/terminal taxonomy depends on it — and `_shared/stripe.ts` is shared
with functions other agents own, so it was not modified.

---

## 3. THE ONE DB ARTIFACT THAT DOES NOT EXIST — AND WHY IT IS NOT GUESSED

`service_role` holds **USAGE only** on `kernel` (`085:2092-2096`, PFA-21: *"No table/DML grants"*) plus
EXECUTE on exactly six functions (`v_svc`, `085:2148-2156`). It therefore **cannot `SELECT kernel.refund` or
`kernel.payment_native`.** The only refund reader that exists, `kernel.list_org_refunds` (`085:1487`), is
`authenticated`-only, org-scoped, and deliberately returns `has_stripe_ref` as a **boolean** (`085:1512`)
rather than the reference.

**There is consequently no path today from `refund_id` → `payment_id` → `stripe_payment_intent_id`.** PFA-23
named the caller but never gave that caller its read.

The edge names the read it needs (`kernel.get_refund_execution_context`), and when it is absent **fails closed
with HTTP 501 and a message that names the gap** — it never guesses a binding. Required shape, for owner
ratification and authoring by whoever owns migration 093 (**deliberately not authored here**: the migration
ledger is 1:1 with the repo and this train applies nothing):

```sql
-- service_role-only, SECURITY DEFINER, read-only. Returns exactly the operands
-- the executor validates; no atom, no identity, no demographic field.
create or replace function kernel.get_refund_execution_context(p_refund_id uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'refund_id', r.refund_id, 'payment_id', r.payment_id,
    'order_id', pn.order_id, 'sale_id', pn.sale_id,
    'amount_minor', r.amount_minor, 'currency', r.currency,
    'reason_code', r.reason_code, 'status', r.status,
    'stripe_refund_ref', r.stripe_refund_ref,
    'payment_total_minor', p.total, 'payment_status', p.status,
    'stripe_payment_intent_id', p.stripe_payment_intent_id,
    'stripe_livemode', p.stripe_livemode,
    'prior_non_failed_minor', coalesce((select sum(r2.amount_minor) from kernel.refund r2
        where r2.payment_id = r.payment_id and r2.status <> 'failed' and r2.refund_id <> r.refund_id), 0),
    'disputed_minor', coalesce((select sum(d.amount_minor) from kernel.dispute_native d
        where d.payment_id = r.payment_id and d.status in ('lost','charge_refunded')), 0))
  from kernel.refund r
  join kernel.payment_native pn on pn.payment_id = r.payment_id
  join public.payments p on p.id = r.payment_id
  where r.refund_id = p_refund_id;
$$;
-- plus kernel.list_pending_refunds(int) → {refunds:[{refund_id, created_at, status}]}
-- revoke all from public, anon, authenticated;  grant execute to service_role;
```

Two properties this shape must keep: it is **read-only** (no state machine in a reader), and it exposes
**no identity, demographic or atom field** — X-6 and ruling F stay intact.

**Second, separate, owner-visible finding — see §7:** the DIRECT arm of `refund_primary_order` is also
unreachable as written.

---

## 4. THE BINDING DEFENCE — "incapable of refunding the wrong payment or order"

This is the property the ruling weights above all others. It is defended in five independent layers, each of
which alone would have to fail:

| L | Guard | Where |
|---|---|---|
| **L1** | The caller **cannot name money.** No request field for payment/PI/charge exists, and one that appears is a 400 refusal, not an ignored key. | `executor.ts` `assertNoClientPaymentReference` |
| **L2** | The payment is the refund row's own FK, resolved in the DB. `on delete restrict` means it cannot even be substituted by deletion. | `085:76`, `085:42` |
| **L3** | The `payment_native` XOR (`085:56-58`) is **re-asserted** on the assembled context. A context resolving to both an order and a sale, or to neither, means the join was wrong — and a wrong join is exactly how you refund the wrong order. Refused. | `planRefund`, `binding_subject_ambiguous` |
| **L4** | `expected_order_id` is the caller's **assertion**, used *only* to refuse a mismatch — never to select the payment. An operator who pastes the wrong refund id gets a refusal, not someone else's refund. | `binding_order_mismatch` |
| **L5** | The Stripe key is derived from the refund row's **own primary key**, and `amount` is sent even for a full refund so Stripe binds the parameters to the key. A replay with a mutated amount returns `idempotency_error` instead of quietly doing something else. | `buildRefundIdempotencyKey`, `EDGE_FUNCTION_SPEC.md:559-560` |

Plus the pre-flight refusals: malformed PI, non-livemode payment, payment not `succeeded`/`refunded`, amount
over the payment total, amount over remaining headroom, unsupported currency.

"**Wrong venue**" has no surface at all: a refund is payment-scoped and **no venue or org id is a parameter of
the executor anywhere**. Org authority lives in the RPCs (`admin_refund`'s role checks, `refund_primary_order`'s
platform/delegated arms). The test suite pins that absence so a refactor cannot quietly add one.

---

## 5. FAILURE-MODE MATRIX

`re_…` = a Stripe Refund object exists. **The create-error rule** (`EDGE_FUNCTION_SPEC.md:552-556`): if
`POST /v1/refunds` *itself* errors there is no `re_…` — nothing was left with Stripe — so the executor calls
`mark_refund_state` **not at all**. `failed` is reserved for a refund Stripe **accepted** and then could not
settle, which carries a ref; `refund_ref_pairing_ck` (`085:93`) makes the wrong reading unstorable.
`classifyStripeRefundError` returns `writesState: false` on **every** class, and a test asserts that
exhaustively.

| # | Failure | DB after | Money after | Recovery | Double-refund possible? |
|---|---|---|---|---|---|
| 1 | Stripe create errors (4xx/5xx) | `pending` | not moved | sweep replays same key | No |
| 2 | **Stripe timeout after creation** | `pending` | **moved** | sweep replays same key → Stripe returns the ORIGINAL object → callback runs | **No** — Stripe dedupes on the key |
| 3 | **Stripe succeeded, `mark_refund_state` failed** | `pending` | moved | sweep replays → same `re_…` → callback re-runs | No |
| 4 | Partial callback (`submitted` landed, `succeeded` lost) | `submitted` | moved | forward-only machine; a direct re-execute is `noop_replay` | No |
| 5 | Worker retries a completed refund | terminal | moved once | `planRefund` → `noop_replay`; **Stripe is never contacted again** | No |
| 6 | Two workers race one refund | one write | moved once | loser's write raises `refund_state_backwards` (`085:1757`), classified **`converged`**, not retried | No |
| 7 | Duplicate `record` (same command key) | one row | — | `refund_primary_order` returns `idempotency_replay` with the **same** `refund_id` (`085:484-487`, `:616-621`) | No |
| 8 | Already-refunded order | unchanged | — | RPC raises `precondition_failed` (`085:526`); the executor's own headroom re-check refuses before Stripe | No |
| 9 | Over-refund | unchanged | — | Σ-guard `085:545` in the RPC + `amount_exceeds_headroom` in the executor | No |
| 10 | Chargeback took the money first | unchanged | — | `disputed_minor` (lost/charge_refunded, per `088:1659-1661`) consumes headroom; Stripe's own `charge_disputed` / `charge_already_refunded` are **terminal, paged, never retried** | No |
| 11 | Amount mutated between attempts | unchanged | moved once | same key + different params ⇒ Stripe `idempotency_error` ⇒ classified as a **code bug**: never retried, always paged | No |
| 12 | Row corrupt (`pending` **with** a ref) | unchanged | — | `impossible_pending_with_ref` refusal + Sentry | No |
| 13 | Stripe 2xx with an unrecordable body | `pending` | moved | paged immediately; sweep replays and gets the same object | No |
| 14 | Two **different** refs on one row | unchanged | — | `conflict_locked` (`085:1766`) classified `conflict` → **paged**, never retried | No |
| 15 | Test-era / unclassified payment | unchanged | — | `stripe_livemode !== true` refuses (fail closed, migration 045) | No |

**Case 6 deserves emphasis.** The naive implementation treats `refund_state_backwards` as a failure and
retries — turning a healthy race into a hot loop against Stripe. `classifyStateSyncError` separates
*converged* (someone else advanced the row, and because the key is deterministic they hold the same `re_…`)
from *conflict* (two different refs — a genuine reconciliation incident) from *retry* (DB unavailability).

### 5.1 One deliberate, flagged deviation from the letter of the edge spec

`EDGE_FUNCTION_SPEC.md:539-541` assigns `succeeded` to a `charge.refunded` webhook branch. **That branch does
not exist** — `stripe-webhook/index.ts:705-734` only updates legacy `public.payments`, and this train may not
modify that file (another agent owns it). A refund parked at `submitted` **still blocks the buyer's account
deletion** (BP-12 arm 1 blocks on `pending`/`submitted`), so stopping there would close only half the defect.

Therefore: when Stripe's **own returned object** says `status: 'succeeded'`, the executor writes `submitted`
then `succeeded`. That is recording a fact, not inferring one, and both writes are legal moves of the frozen
forward-only machine. When Stripe says `pending`/`requires_action` the executor stops at `submitted` and leaves
the terminal to whoever observes it next. The webhook branch, when written, converges on the same row via
`noop_replay` (`085:1752-1755`). **Flagged here rather than buried, because it is the one place this
implementation goes beyond the spec's letter.**

---

## 6. THE OBLIGATION-RECONCILIATION STORY (and why the edge writes no ledger row)

**`venue.settlement_line` is append-only.** `087:110-112` installs `tg_settlement_line_append_only` (BEFORE
UPDATE OR DELETE → `kernel.raise_append_only()`), and `087:115` additionally does
`revoke update, delete on venue.settlement_line from service_role`. A refund can therefore **never** be
represented by amending the original positive line. It is represented by its **own negative line**:
`cause = 'refund_void'`, `cause_ref = refund_id`, `amount_minor` negative, one per settlement
(`UNIQUE(settlement_id, cause, cause_ref)`, `087:104`).

**How the two connect — precisely:**

* **The reader already exists.** `kernel.close_settlement` (`087:329-331`) computes
  `refunds = -Σ(amount_minor) filter (where cause in ('refund_void','chargeback'))` and
  `net = gross − fees − refunds`, and mints a payout only `if v_net > 0` (`087:340`). A refund line therefore
  *already* reduces what the venue is paid, automatically, the moment such a line exists.
* **The producer did not exist at `092`.** Lines are generated by seam functions —
  `kernel.settlement_royalty_lines` and `kernel.settlement_commission_lines` (`087:311-312`) — and `refund_void`
  had **zero writers through `092`** (the only other `refund_void` occurrences are the *ownership-log* cause at
  `085:356`/`085:369`, a different table entirely). This is the same fact `_rulings/E_refunds_disputes.md` F-3
  reports independently.
* **The producer is being written IN THIS TRAIN, by another agent.** `supabase/migrations/093_primary_ticketing.sql`
  adds a third seam, `kernel.settlement_primary_lines(uuid)`, emitting the positive `primary_sale` credit
  (`093:330-336`) **and** the negative `refund_void` debit (`093:373-379`), capped so Σ debits per order never
  exceed that order's credit (`093:361-371`), cumulative across closes via `refund_prior` (`093:339-347`), and
  emitted at most once per `refund_id` ever (`093:357-358`). It selects candidates with
  **`r.status <> 'failed'`** (`093:354`) — the same operand `085:538-539`'s over-refund accounting uses.
* **The edge's job is the truth, not the ledger.** `mark_refund_state` is documented as touching *"NO atom, NO
  `public.*` table"* (`085:1777`), and the seam — not the edge — is the contracted line writer. So the executor
  writes **no** ledger row. What it produces is a deterministic, truthful selection predicate for the future
  seam: **`kernel.refund` rows whose `status = 'succeeded'`, joined `payment_id → kernel.payment_native →
  venue."order" → org/venue`, are exactly the refunds a settlement must offset.** Before this executor existed
  that predicate selected *nothing*, because no row could ever leave `pending` — the seam could not have been
  written correctly even if someone had tried.

### 6.1 A NEW INTERACTION THIS EXECUTOR CREATES — flag for the 093 seam author and the owner

**This executor is the first and only caller of `mark_refund_state`, so it is the first thing in the system's
history that can make a `kernel.refund` row reach `'failed'`.** Until now `failed` was unreachable, which is
why a seam predicate of `status <> 'failed'` was, in practice, indistinguishable from `status is not null`.

That is no longer true, and the two artifacts meet badly on one path:

1. `093:354` books the venue's negative `refund_void` line for any refund with `status <> 'failed'` — i.e. as
   soon as the row exists, while it is still `pending`. That is deliberately the fail-closed direction for
   *venue* money: the venue is not paid against a refund that is probably about to happen.
2. This executor then drives the row `pending → submitted → failed` when Stripe **accepts** the refund and
   subsequently **cannot settle it** (`planStateSync`, from Stripe's own `status: 'failed'`).
3. `venue.settlement_line` is append-only and `093:357-358` writes a `refund_void` line **at most once per
   `refund_id`, ever**. So the debit stands, permanently, for a refund that returned **no money to the buyer**.

Net: the buyer is not refunded **and** the venue is debited. Both sides lose. The window is narrow (it requires
a Stripe-accepted-then-unsettled refund, and a close in between), but it is append-only, so it cannot be
corrected — only offset by hand.

**Three shapes resolve it; this document takes none of them, because the seam and the settlement model are
another agent's and the owner's:**

| Option | Effect | Cost |
|---|---|---|
| Seam selects `status in ('submitted','succeeded')` | never debits on a bare `pending` intent | narrows, does not close: `submitted → failed` is the actual failure edge |
| Seam selects `status = 'succeeded'` only | debits exactly the money that actually moved | fail-**open** for venue money: a venue can be paid while a real refund is in flight |
| Keep `<> 'failed'`, add a compensating **positive** line when a refund reaches `failed` | append-only-correct, arithmetically exact | needs a distinct cause (the `refund_void`/`cause_ref` pair is already consumed) and therefore a `087:97` CHECK widening |

The third is the only one that is both append-only-honest and fail-closed. A fourth, cheaper mitigation is
available immediately and **inside this executor's own scope** if the owner prefers it: have the executor never
write `failed` at all and leave every unsettled refund at `submitted` for human reconciliation — at the cost of
the BP-12 deletion block staying on (§5.1). Flagged, not taken.

**Also carried forward:** the cross-settlement double-lining defect named at `_decisions/A_venue_money.md` FM-2
applies to the new `refund_void` arm identically; `093:391+` appears to address it with partial unique indexes,
which is the settlement agent's to confirm, not this document's.

---

## 7. AUTHORITY — PFA-23'S DIRECT ARM IS NOT REACHABLE AS WRITTEN

`refund_primary_order` selects its arm by command key alone (`085:494-520`):

* **DELEGATED** (`req:<uuid>`) binds to an already-`approved` `kernel.approval_request` matching the order
  **and the amount**, is single-use via `refund_idempotency_uq`, and reads **no `auth.uid()`**.
* **DIRECT** requires `kernel.is_platform(['platform_admin'])` or `['platform_support']`, i.e. `auth.uid()`.

But the grant set is: `service_role` **only** (`v_svc`, `085:2152`), explicitly **not** `authenticated`
(`085:2129-2130`: *"refund_primary_order is NOT here — PFA-23 makes it EXEC DEF"*). PostgREST derives the
database role from the JWT it verifies, so a single request is **either** `service_role` (and `auth.uid()` is
NULL ⇒ `is_platform` fails) **or** `authenticated` (and EXECUTE is denied). **"As service_role, forwarding the
platform JWT" has no single-client implementation with this grant set.**

* **The DELEGATED arm works today**, and is the safer default anyway — dual control is already enforced
  upstream by `request_order_refund` / `approve_refund_request`.
* **The DIRECT arm is still routed** (on the caller's own client, the only client carrying the platform
  identity) so the resulting `42501` is a precise, logged, denial-witnessed refusal instead of silence.
* `kernel.admin_refund` **is** granted to `authenticated` (`085:2138`), so platform break-glass has a working
  sibling today.

**Owner decision required (three options, not resolved here):** (i) grant EXECUTE on `refund_primary_order` to
`authenticated` — contradicts PFA-23's explicit exclusion; (ii) an owner-ratified mechanism for a
service-role session carrying a human `sub`; (iii) route **all** platform refunds through the delegated
dual-control path and retire the direct arm. Option (iii) costs the least and increases control.

**Denial witness.** On `insufficient_privilege` / `sod_violation` / `step_up_required` / `step_up_unavailable`
the edge calls `kernel.record_money_denial('refund.execute', …)` **on the caller's own client, in its own
request** — `service_role` is explicitly revoked from it (`085:2174`) and the RPC raises when `auth.uid()` is
NULL, so a service-role call would write nothing on the highest-value fraud signal in the system. `'refund.execute'`
is an accepted action value (`085:1582`).

---

## 8. TESTS

`tests/refund-executor.test.ts` — **66 tests, all passing.** Full repo suite: **218/218, 8 files.**

The Stripe mock implements **real** idempotency-key semantics (same key + same params → the original object,
never a second one; same key + different params → `idempotency_error`) and counts money per PaymentIntent, so
"exactly one refund" is asserted against actual amounts, not against call counts. The `KernelMock` is a
line-for-line port of `kernel.mark_refund_state` (`085:1737-1789`): forward-only, write-once ref, noop-replay,
mandatory `failure_code`.

| Required case | Covered by |
|---|---|
| full refund | `full refund` |
| partial refund | 4 tests incl. two partials on one payment, Σ-guard, over-total |
| duplicate request | `idempotency_replay` on the same command key; re-delivered execute job |
| Stripe timeout | created-then-lost-response → replay converges, **one** refund |
| Stripe succeeds then DB retry | state-sync failure → retry converges; partial-callback variant |
| DB failure then worker retry | `failNextStateSync` + sweep replay |
| tombstoned buyer | §9 below — schema-cited, plus "nothing identity-shaped reaches Stripe" and "reaching `succeeded` unblocks BP-12" |
| cancelled event | single row, N-row fan-out, whole-sweep replay |
| wrong order | `binding_order_mismatch`, XOR violations both directions |
| wrong venue | asserted as an **absence** (no venue/org key can reach the Stripe body) |
| already-refunded order | headroom refusal before Stripe; `charge_already_refunded` terminal |
| concurrent refund | two workers → one Stripe refund; `converged` classification |
| chargeback interaction | dispute consumes headroom; partial-chargeback boundary; `charge_disputed` terminal |

**Written as pure-logic tests because they cannot be unit-tested without a live DB** (stated explicitly
in-file): the support cumulative cap (`085:549-563`), the Σ-guard under the payment `FOR UPDATE` lock
(`085:534-545`), and the delegated-key single-use property — all enforced *inside*
`kernel.refund_primary_order` and unreachable from TypeScript. What **is** tested here is the executor's own
re-check of the same headroom, which is what protects the window between recording the intent and executing
it — the window a queued job actually sits in.

---

## 9. TOMBSTONED BUYERS — VERIFIED, WITH CITATIONS

**Claim: a refund binds to the payment, not the customer, and the Stripe payment reference survives erasure.**

1. `kernel.refund.payment_id references public.payments(id) on delete restrict` (`085:76`), and
   `kernel.payment_native.payment_id … on delete restrict` (`085:42`). The payment row **cannot be deleted out
   from under a refund at all.**
2. `kernel.sweep_deletion_pending` (`077:1865-2050`) is the **only** erasure writer. Its terminal write set is:
   `identity_ext.deletion_state` (`:1985-1988`), `kernel.org_member` / `kernel.platform_role` / `kernel.org_invite`
   (`:1994-1999`), `public.listings` (`:2005-2013`), and four hooks (`:2018-2021`). It touches **neither
   `public.payments`, nor `kernel.payment_native`, nor `kernel.refund`.** `stripe_payment_intent_id`
   (`000_baseline_schema.sql:988`) therefore survives erasure intact.
3. `POST /v1/refunds` here takes `payment_intent` + `amount`. **No Stripe Customer, no
   `profiles.stripe_customer_id`, no buyer identity is a parameter** — the money goes back to the card via the
   PaymentIntent. A test pins that no buyer/customer/identity/email key can appear in the request body.
4. The relationship runs the other way too: **executing the refund is what unblocks deletion.** BP-12 arm 1
   (`085:249-262`) blocks while `status in ('pending','submitted')`. This is exactly why §5.1's decision to
   record `succeeded` matters — a refund parked at `submitted` leaves the account blocked.

---

## 10. EVENT CANCELLATION — VERIFIED

`catalog.cancel_event` (`088:1612+`) **never calls `refund_primary_order`.** It INSERTs `kernel.refund` rows
directly, all born `pending`, with keys `<command_key>:sale:<sale_id>` (`088:1664`, `088:1716`) and
`<command_key>:order:<order_id>` (`088:1774`), each guarded against prior refunds **and** lost/charge_refunded
disputes (`088:1661`, `:1712`, `:1770`), and each emitting `refund_requested` (`088:1670`, `:1719`, `:1777`).

Because the executor is refund-row-driven, those rows execute through the **identical** path — the
`action:sweep` leg drains them oldest-first, bounded, one failure never blocking the batch, each under its own
`refund_<refund_id>` key. Replaying the whole cancellation sweep refunds nothing twice (tested). No
cancellation-specific code exists in the executor, which is the point.

---

## 11. INSPECTION — THE PLANNED PAYOUT EXECUTOR (`payout-execute`)

**Not built. Ruling D3 covers refunds only, and the blocking question below is explicitly an owner/paper
decision, not an engineering one.**

### 11.1 What exists

| Artifact | Location | State |
|---|---|---|
| `kernel.payout` table | `085:111-152` | **Exists.** `cause ∈ (settlement, market_sale, promoter_commission, refund_void)`; `status ∈ (pending, submitted, paid, failed, reversed)`; 4-column hold overlay; `stripe_transfer_ref` **write-once, singular**; `source_transaction_ref` present |
| `kernel.close_settlement` | `087:289` | **Exists.** Mints one `pending` payout per settlement, `if v_net > 0` (`087:340-347`) |
| `kernel.request_org_payout` | `087:408` | **Exists.** `pending → submitted` behind five controls: `org_owner\|org_finance`, SoD-1 setter exclusion, grant maturity, AAL2 step-up, destination cool-down + probation; refuses `no_payout_destination` (`087:445-447`) |
| `kernel.mark_payout_transfer_state` | `085:1668` | **Exists, correct, `service_role`-only — and has ZERO callers.** Refuses `'submitted'` (`085:1683`), refuses a **held** payout with both columns untouched (`085:1690`), forward-only `submitted→paid\|failed`, `paid→reversed`, write-once ref (`085:1712`), and fires the fifth seam `venue.on_payout_settled` on `paid` (`085:1729`) |
| `venue.on_payout_settled` | `087:381` | **Exists.** Advances the settlement header `closed → paid` only when **no** settlement payout is non-paid |
| `kernel.hold_payout` / `release_payout` | `085` `v_auth` | **Exist**, `authenticated` |
| `_shared/payouts.ts` | `:16-24`, `:133-145` | **Exists and works** — the resale rail's capability pre-flight, funding-charge verify, and `transfers.create` with `source_transaction`, under `buildPayoutIdempotencyKey(id, destination)` |
| **`payout-execute` edge** | spec `PHASE_2_EDGE_FUNCTION_SPEC.md:461-527` | **DOES NOT EXIST** |

### 11.2 What is missing

1. **The edge itself.** It is the **sole writer of `failed`** (spec `:487-497`; a transfer that cannot be
   created fails as a *synchronous* Stripe API error — there is no `transfer.failed` event — so `failed` is
   knowable **only** in the request that caught it). Today a failed transfer would read `submitted` forever.
2. **A destination for any org.** `kernel.set_org_payout_destination` (`085:1601`) has **zero callers**
   (only a comment reference in `connect-onboarding/index.ts:33`). With `stripe_connect_account_ref` NULL,
   `request_org_payout` refuses at `087:445-447`, so **no org can be paid at all today** — which also means the
   `source_transaction` question below has never been forced in production.
3. **The same `service_role` read gap as §3.** `payout-execute` needs `payout_id` → org Connect destination →
   funding charge(s). `service_role` has USAGE on `kernel` and no table grants, and no service-role-reachable
   reader exists. Whatever resolves this for refunds must resolve it for payouts too; solving it twice
   differently would be the mistake.
4. **`source_transaction_ref` (`085:134`) has never been written by anything.**
5. **A `transfer.reversed` producer.** `stripe-webhook/index.ts:747-760` observes reversals on the *legacy*
   table only; nothing routes them to `mark_payout_transfer_state(..., 'reversed', ...)`.

### 11.3 The `source_transaction` problem — stated, not resolved

The most valuable operational knowledge in the resale rail is `_shared/payouts.ts:16-24`: funding a transfer
with `source_transaction` is what stopped same-day payouts failing with *"Insufficient funds in Stripe
account"* in the August 2026 incident (a same-day charge leaves the platform **available** balance at $0; its
balance transaction is still `pending`, `available_on` ≈ 7 days out). It works because **one resale payout has
exactly one funding charge**.

**A settlement payout has N funding charges — one per primary order. But Stripe binds exactly ONE
`source_transaction` per Transfer, and it cannot be amended after creation. And `kernel.payout.stripe_transfer_ref`
is write-once and singular (`085:133`), with `mark_payout_transfer_state` raising `conflict_locked` on a
second, different ref (`085:1712-1717`).**

This is a **structural mismatch between the money schema's shape (one payout, one ref) and Stripe's funding API
(one transfer, one source charge)**. It is not a bug findable in testing; it surfaces on the first real venue
settlement, in production, with a venue waiting to be paid.

The three available shapes, each with a real cost:

| Option | Cost |
|---|---|
| **N transfers per payout** (one per funding charge) | The write-once singular `stripe_transfer_ref` **cannot record them**. The payout row can name only one. Requires a schema change to a frozen, owner-signed money table. |
| **One transfer, no `source_transaction`** | Draws unrestricted platform available balance and **reproduces the August 2026 incident** on every settlement closed before its charges have settled. |
| **One payout per order** | Breaks Option B (the settlement aggregation model) — this is Option 4 of the venue-money decision. |

**How it must be resolved on paper before an executor is written** — the sequence, not the answer:

1. **The owner picks the funding model**, because each option costs something the owner owns: a frozen-schema
   change, a reproduced production incident, or the settlement aggregation model itself. No engineer may pick
   this by writing code, and no default is safe.
2. **If, and only if, a "wait for availability" model is chosen** (`_decisions/A_venue_money.md:566-572`
   recommends *investigating* it first: close the settlement, mint the payout, transfer from platform available
   balance **only once every constituent charge's `available_on` has passed`), then a **charge-readiness
   predicate must be specified and ratified** — it does not exist in any form today, and it must define which
   charges constitute a settlement, where their ids are stored (`kernel.payment_native` has no charge column),
   and what happens when one charge is disputed or refunded mid-window. It trades payout latency for structural
   simplicity and preserves one payout / one ref.
3. **Only then** is `payout-execute` writable, because only then is `stripe_transfer_ref`'s cardinality decided.

**This report deliberately does not choose.** Guessing here would either silently re-open a known production
incident or silently amend a frozen, owner-signed money table.

### 11.4 Two adjacent facts an implementer will need

* **The `O16` choice is unresolved.** `mark_payout_transfer_state` accepts `'paid'` under form (a) — the
  executor asserting a synchronous transfer result (`085:1680-1682`) — and **refuses `'submitted'`** so the
  request path stays the only door. Under form (b) `paid` would come from a `payout.paid` fan-out instead. The
  spec records this as an **owner decision it does not take** (`:498-506`).
* **A held payout is never cleared by the executor.** `mark_payout_transfer_state` refuses outright when
  `hold_state <> 'none'`, leaving **both** columns untouched (`085:1689-1691`). A held payout that Stripe
  reports as paid is a reconciliation incident for `platform_risk`, not a state transition — clearing a hold by
  webhook would defeat §17.7 Control 4 with no role at all.

---

## 12. WHAT THIS WORK DOES NOT DO

No deployment. No migration authored or applied. No commit. No Stripe object created. No production contact.
`stripe-webhook/index.ts`, `create-connect-account/index.ts`, `primary-checkout/` and `connect-onboarding/`
untouched (other agents own them); `_shared/stripe.ts` untouched. The `charge.refunded` / `refund.updated`
webhook reconciliation legs remain unwritten and are owned elsewhere. The `refund_void` settlement-line seam
(§6) and `payout-execute` (§11) remain unwritten by design.

**Four items requiring an owner decision before this function can run:**
1. `kernel.get_refund_execution_context` + `kernel.list_pending_refunds` (§3) — additive, `service_role`-only,
   read-only; the executor fails closed and loud without them. **Hard blocker.**
2. PFA-23's direct arm (§7) — three options offered, none taken. The delegated (dual-control) arm works today.
3. The `failed`-refund / `refund_void`-line interaction with 093's new seam (§6.1) — this executor is what makes
   `failed` reachable for the first time, so the seam's `status <> 'failed'` predicate now has a live edge case.
   Four options offered, none taken.
4. §5.1's decision to record `succeeded` from Stripe's own object rather than wait for a webhook branch that
   does not exist — flagged for ratification or reversal.
