# H1 — THE REFUND EXECUTION ARCHITECTURE: verification, the missing claim primitive, and PFA-23's direct arm

**Predecessor:** `docs/phase2/_impl/E4_refund_executor.md` (ruling D3). This document VERIFIES E4 against the
code, closes the one artifact E4 named and did not author, and resolves the authority question E4 left open
as "three options, none taken".

**What this train changed:** `docs/phase2/_impl/093_parts/10_money_settlement.sql` §10i (one new
`service_role`-only function), `supabase/functions/refund-execute/{index.ts,executor.ts}`,
`supabase/tests/158_refund_execution_claim.sql` (new, 39 assertions), `tests/refund-executor.test.ts`, and
eight kernel-census assertions (116 → 117 functions; 250 → 251 five-schema routines).

**What this train did NOT do:** no deploy, no remote, no Stripe call, no production contact, no commit, no
migration applied anywhere but a local rehearsal database, no edit to `supabase/migrations/000-092`, and no
hand-edit of the generated `093_primary_ticketing.sql` (re-assembled by `scripts/assemble_093.sh`; the G-4
integrity gate passes).

All `NNN:LL` citations are `supabase/migrations/NNN_*.sql` unless stated otherwise.

---

## 1. VERIFICATION — WHAT HELD, AND WHAT DID NOT

Every claim below was re-derived from the code and, where it is a database fact, from a full local replay of
`000`–`093` (`snatchit_rehears_refund`).

| Prior claim | Verdict |
|---|---|
| The executor exists and substantially conforms to PFA-23 | **HELD.** `supabase/functions/refund-execute/{index.ts,executor.ts}` exist, are refund-row-driven, and `assertNoClientPaymentReference` refuses (not ignores) a request that names a payment. |
| Stripe idempotency is `refund_<refund_id>` | **HELD.** `buildRefundIdempotencyKey` derives it from the row's own primary key and throws on a non-uuid; `amount` is sent even on a full refund so Stripe binds parameters to the key. |
| Tombstoned buyers work | **HELD.** `kernel.refund.payment_id` is `on delete restrict` (`085:76`); `kernel.sweep_deletion_pending` (`077:1865-2050`) touches neither `public.payments` nor `kernel.refund`; and the Stripe body carries `payment_intent` + `amount` and no customer or identity field. |
| `kernel.list_pending_refunds` is absent | **HELD, and now proven rather than asserted.** A full local replay of `000`–`093` reports the function absent; the only occurrence in the tree was a comment. `refund-execute`'s sweep answered 501. |
| `kernel.get_refund_execution_context` is missing | **OVERTURNED — it exists.** E4 §3 described it as unauthored; it was subsequently written into slice 10 (`10_money_settlement.sql:1030`, artifact `093:1087`) and is `service_role`-only. E4 §3 and §12 item 1 are stale on this point. |
| PFA-23's direct arm is unreachable because PostgREST binds one role per request | **HELD as a statement about `kernel.refund_primary_order`.** |
| …and platform-direct refunds therefore cannot be executed | **OVERTURNED. This is the most consequential correction in this document — see §5.** The authority is fully reachable today, through `kernel.request_order_refund`, and suite `149` D2 already asserts it. |
| E4 §5's failure matrix proves double-refund is impossible | **OVERTURNED IN ONE PLACE.** Cases 2, 3 and 13 all recover by replaying `refund_<refund_id>` and relying on Stripe returning the original object. **Stripe retains an idempotency key's result for 24 hours.** A `pending` row replayed after that window creates a **second, real refund**. E4's matrix has no row for it. See §4.3. |
| The sweep recovers every interrupted refund | **OVERTURNED.** `planSweep` filtered `status === 'pending'` (`executor.ts:497`), so E4 §5 case 4's row — stranded at `submitted` when a worker dies between the two `mark_refund_state` calls — was **unreachable by anything**. It also keeps BP-12 arm 1 (`085:249-262`) blocking that buyer's account deletion forever: the same defect ruling D3 was issued to close, one state later. |

---

## 2. THE FULL LIFECYCLE

| # | Stage | Writer | Caller | Authorization | Idempotency boundary | Retry | Stripe object | DB object | Failure state |
|---|---|---|---|---|---|---|---|---|---|
| 1 | REQUEST | `kernel.request_order_refund` `085:850` | `authenticated` (buyer / `org_owner`\|`org_finance` / platform) | `auth.uid()` + role class + `check_rate_limit` + reason-code policy | `approval_request.command_idempotency_key` UNIQUE per requester → `idempotency_replay` | client re-POST returns the original `request_id` | none | `kernel.approval_request` | `insufficient_privilege` / `policy_violation` / `precondition_failed: over_refund` |
| 2 | ELIGIBILITY | same, in the same transaction | — | five D-3 config tiers, all **NULL-seeded ⇒ that arm authorizes nothing**; support cap on the **cumulative** operand under the payment lock | payment row `FOR UPDATE` serializes the Σ-guard | — | none | tier decision (`v_execute`) | `policy_violation` (scanned atom), `sod_violation` (immature org grant) |
| 3 | DURABLE REFUND FACT | `kernel.refund_primary_order` `085:457` (also `admin_refund` `085:706`, and `catalog.cancel_event` INSERTing directly at `088:1664/1716/1774`) | definer→definer from stage 1/2, or `service_role` with a `req:` key | delegated key bound to an **approved** request matching order **and** amount; single-use via `refund_idempotency_uq` | `kernel.refund.idempotency_key` UNIQUE = the command key | duplicate → `idempotency_replay` with the **same** `refund_id` | none | `kernel.refund` born `pending`; atoms voided; order → `refunded`/`partially_refunded` | `custody_moved`, `conflict_locked`, `frozen`, `over_refund` |
| 4 | **CLAIM / WORK LIST** | **`kernel.claim_refunds_for_execution` (NEW, §4)** | `refund-execute` as `service_role` (cron) | `service_role` EXECUTE only; **no parameter names a subject** | lease = an append-only `kernel.admin_audit` row (`refund.execute_claim`); exclusivity = `for update … skip locked` | stale lease recovers after expiry; attempt count is the audit history | none | `kernel.admin_audit` only | none — a claim moves nothing |
| 5 | EXECUTOR | `refund-execute` `executeOne` / `reconcileOne` | cron (`sweep`) or platform JWT (`execute`) | `INTERNAL_CRON_SECRET` / service key for `sweep`; JWT + rate limit for `execute` | `refund_<refund_id>`, DB-derived | one failure never blocks the batch | — | reads `kernel.get_refund_execution_context` | `refused` (binding), `stripe_error`, `state_sync_deferred` |
| 6 | STRIPE REFUND | Stripe | executor | Stripe key, **livemode only** (`stripe_livemode !== true` ⇒ refuse; NULL from 045 fails closed) | `Idempotency-Key: refund_<refund_id>` **for 24h** | create-error ⇒ **no** state write; row stays `pending` | `Refund` (`re_…`) | — | Stripe error class (`classifyStripeRefundError`, `writesState:false` on every class) |
| 7 | DB RECONCILIATION | `kernel.mark_refund_state` `085:1737` | executor as `service_role` | `service_role` only; forward-only; ref write-once; `failure_code` mandatory for `failed` | `noop_replay` on an identical terminal | `refund_state_backwards` ⇒ classified **converged**, never retried | — | `kernel.refund.status` + `admin_audit` | `conflict_locked` (two refs) ⇒ paged |
| 8 | VENUE OBLIGATION | `kernel.settlement_primary_lines` (slice 10b) | `venue.close_settlement` | definer-only (no grant at all) | `UNIQUE(settlement_id, cause, cause_ref)` + `settlement_one_refund_void_line_ever` | append-only ledger — the line is emitted at most once **ever** per `refund_id` | — | negative `refund_void` `venue.settlement_line` | see §6 (open item) |
| 9 | PROMOTER | `kernel.settlement_commission_lines` (slice 10e) | `close_settlement` | definer-only | same unique-line discipline | — | — | commission lines | ruling A4: **no commission on refunded revenue; releases nothing** |
| 10 | FINAL STATE | `mark_refund_state` | executor | — | terminal | — | `succeeded` / `failed` | `kernel.refund.status` | `succeeded` unblocks BP-12; `submitted` does not |

---

## 3. WHY A CLAIM AND NOT A LIST

E4 §3's trailing note asked for `kernel.list_pending_refunds(integer)`. That verb was refused, deliberately:

1. **A list hands N workers the same N refunds.** With `list_pending_refunds`, two concurrent sweep ticks —
   or one tick and one cron overlap — both send `POST /v1/refunds` for the same row. The money stays right
   only because Stripe deduplicates on the key. **That key is the last line of defence and must never also be
   the first**: it is a 24-hour token held by a third party, and §4.3 is what happens when it lapses.
2. **A list cannot record a first-attempt instant**, and without one there is no way to know whether a
   replay is a dedup or a second payment.
3. The repo already has the right idiom: `064_webhook_event_claim_lease.sql` replaced exactly this shape —
   an existence gate that "fails open on any non-23505 insert error" — with claim / complete / fail and a
   lease timeout. `stripe-webhook` has used it since. Inventing a different one here would be the mistake.

---

## 4. THE CLAIM PRIMITIVE

### 4.1 Exact signature and grant (`093_parts/10_money_settlement.sql` §10i)

```sql
kernel.claim_refunds_for_execution(p_limit integer default 25, p_lease_seconds integer default 900)
  returns jsonb
  language plpgsql security definer set search_path = ''

revoke all on function kernel.claim_refunds_for_execution(integer, integer)
  from public, anon, authenticated;
grant execute on function kernel.claim_refunds_for_execution(integer, integer) to service_role;
```

Returns `{ refunds: [ { refund_id, created_at, status, execution_mode, attempt, command_key } ], lease_seconds, claimed_at }`.

**The name is the whole capability: it claims refunds, for execution.** There is no parameter by which a
caller can name a refund, a payment, an order, a venue, an organization, an identity, an amount or a
destination — `p_limit` and `p_lease_seconds` are throughput only, and both are clamped server-side
(`1..100`, `60..3600`) so a misconfigured or hostile worker cannot use them to widen anything.

### 4.2 How each required property is obtained

| Property | Mechanism |
|---|---|
| The DATABASE decides eligibility | `where r.status in ('pending','submitted') and not exists (recent claim)`, ordered `created_at, refund_id`, bounded by the clamped limit. The worker receives an answer, not a query. |
| The worker cannot select a payment, amount, buyer or destination | None of them is a parameter, and none is projected. The batch carries a **handle and a mode**; the money still has to come from `kernel.get_refund_execution_context` (10g), which is itself `service_role`-only and projects no identity. |
| The PaymentIntent is resolved from durable DB state | Unchanged: 10g is reused verbatim. No second reader was written. |
| Claim/retry semantics prevent double execution | `for update … skip locked` makes the claim exclusive within the transaction; the committed `refund.execute_claim` audit row makes it exclusive for the lease. Same guarantee `064` gets from its single `INSERT … ON CONFLICT`. |
| Stale claims recover safely | The lease is a predicate over `occurred_at`, not a flag anyone must clear. A worker that dies holding one simply stops renewing it. |
| A successful Stripe refund is reconcilable after a crash | Three ways, and they now cover the whole state space: a `pending` row inside the window replays the same key; a `pending` row outside it is searched by `metadata[refund_id]`; a `submitted` row is fetched by its own `stripe_refund_ref`. |
| A DB retry after Stripe success does not create a second Stripe refund | Inside 24h, Stripe returns the original object. Outside 24h the mode is `reconcile`, and `reconcileOne` **establishes before it creates** (§4.3). |
| Keys derive from the durable refund fact | `command_key` is issued by the database as `refund.execute:<refund_id>` (42 chars, inside the 64-char audit budget, no truncation). The edge previously minted `sweep:<uuid>` itself. `planClaimedBatch` **drops** any row whose command key is not the DB-issued one. |

### 4.3 The 24-hour hole, and the mode that closes it

Stripe retains an idempotency key's result for **24 hours**. E4 §5's "No" in the double-refund column for
cases 2, 3 and 13 is therefore conditional on a window E4 never names, and the conditions that strand a row
past it — a crashed worker, a paused cron, a paused project, a deploy freeze — are ordinary.

The database decides, per row, which side of the window the row is on, and the worker obeys:

* `create` — no claim has ever been recorded, or the first one is inside the window (20 hours; a 4-hour
  margin against clock skew and against a claim stamped before a long Stripe call). A replay is deduped.
* `reconcile` — the key is not a usable dedup token. `reconcileOne` then:
  * `fetch_ref` when the row carries a `stripe_refund_ref` (every `submitted` row does —
    `refund_ref_pairing_ck`, `085:93`): `GET /v1/refunds/{ref}` and sync. A ref Stripe does not recognise is
    a **non-retryable** incident, never a licence to create a replacement.
  * `search_then_create` otherwise: `GET /v1/refunds?payment_intent=…&limit=100` and match
    `metadata.refund_id`, which `planRefund` writes on **every** refund it creates. Found ⇒ sync it, no second
    refund. Not found and `has_more` false ⇒ existence is *established* as absent, so creating is safe.
    `has_more` true ⇒ **refuse and page**; guessing here spends money.

The window is a constant in the function body, not a parameter and not a config key: a caller-tunable dedup
window is precisely the tampering vector this verb exists to remove.

### 4.4 Why the lease lives in `kernel.admin_audit`

`064` stamps `claimed_at` on its own table. `kernel.refund` is a money-ledger table under an owner-signed
freeze, and 093 does no DDL on one, so the lease is carried by an append-only `kernel.admin_audit` row
(`action = 'refund.execute_claim'`, `subject_kind = 'refund'`, actor = the system identity seeded at
`078:1611`). For this problem that is better than a column, not merely permitted:

* `admin_audit` is UPDATE/DELETE-revoked even for `service_role` (`077:259`) and trigger-guarded
  (`077:261-264`), so a lease and a first-use instant cannot be rewritten;
* `min(occurred_at)` **is** the first-attempt instant §4.3 needs, which one mutable `claimed_at` cannot express;
* `count(*)` is `064`'s `attempt_count`, for free, and durable across crashes.

---

## 5. PFA-23'S DIRECT ARM — CLASSIFICATION: **IMPLEMENTATION CLARIFICATION**

### 5.1 The impossible caller shape is real

`kernel.refund_primary_order`'s DIRECT branch requires `kernel.is_platform([...])`, i.e. `auth.uid()`. EXECUTE
is granted to `service_role` only (`085:2152`) and explicitly withheld from `authenticated`
(`085:2129-2130`). PostgREST derives one database role per request, so a request is either `service_role`
(`auth.uid()` NULL ⇒ `is_platform` fails) or `authenticated` (EXECUTE denied). Both refusals are already
asserted: `149` D1 (42501 for an authenticated caller) and `149` D8 (the grant set). **No caller shape fixes
this**, and every workaround that would is forbidden: a raw-SQL operational path, a leaked or client-side
service role, an arbitrary forwarded JWT, or a function that trusts a user-supplied role claim.

### 5.2 But the authority is not missing — and that is the correction

`kernel.request_order_refund` (`085:850`) is granted to `authenticated` (`085:2130`, the `v_auth` array), is
`security definer`, and therefore carries the caller's `auth.uid()`. It evaluates the **same**
`kernel.is_platform` predicates and the **same** `refund.platform_support_max_minor` cap on the **same**
cumulative operand under the **same** payment lock. For `platform_admin` / `platform_risk`, and for
`platform_support` within cap, it sets `v_execute := true`, writes an auto-approved witness
`kernel.approval_request`, and calls `kernel.refund_primary_order` **definer→definer** under the delegated key
`req:<request_id>` (`085:995-1036`). Suite `149` D2 already asserts the result is `status: 'executed'` — a
single platform actor, no second human, no raw SQL.

So `refund_primary_order`'s DIRECT branch is a **definer-internal branch, not an edge-callable arm**. The
smallest architecture that preserves the intended authority is therefore to change **no grant, no function
body and no frozen rule**, and to correct the *caller* instead:

```
record + `req:<uuid>` key  →  service client  →  kernel.refund_primary_order   (unchanged; PFA-23's own text)
record + any other key     →  caller  client  →  kernel.request_order_refund   (WAS: refund_primary_order → 42501)
```

That is the only code change §5 requires, and it is in `refund-execute/index.ts`.

### 5.3 Why this is a CLARIFICATION and not an AMENDMENT

* **PFA-23's normative ruling never contains the impossible sentence.**
  `docs/architecture/_governance/POST_FREEZE_AMENDMENTS.md:1971-2000` specifies the DIRECT arm only as an
  *authority predicate* and names callers only for the DELEGATED arm — "reachable only definer→definer (from
  `approve_refund_request`/`request_order_refund`, which have already enforced dual control) or via the
  refund-execute edge as service_role". **The words "forwarding the platform JWT" appear nowhere in it.**
* They appear in a **grant-block comment** in an immutable migration (`085:2145-2146`), which is descriptive,
  not normative. E4 §7 read that comment as the frozen shape; it is not.
* Nothing about the authority changes: same predicates, same cap, same operand, same lock, same single-use
  delegated binding, same grants. `149` D1/D2/D8 all stay green **unmodified**.
* Because the correction is to an owner-signed package's comment, it is recorded citably in
  `docs/architecture/_governance/PFA23_DIRECT_ARM_CLARIFICATION.md` rather than left in an impl note.

**Consequence for the record:** E4 §7's three options are moot. Option (i) (grant to `authenticated`) is
unnecessary and would contradict PFA-23; option (ii) (a service-role session with a human `sub`) is
unnecessary and is exactly the forged-principal shape to avoid; option (iii) (retire the direct arm) is
already the de facto state and needs no ruling — the branch is dead code inside a definer, reachable only
through the door that already enforces the tier ladder.

### 5.4 What DOES need the owner — **PENDING OWNER RATIFICATION**

`kernel.claim_refunds_for_execution` is a new `service_role` verb that **enumerates money in flight**. E4 §3
set the standard itself: such a verb "deserves its own ratification rather than arriving as a silent
passenger in the money slice". It is authored, tested and unapplied, and it is the one item in this document
that requires a signature before 093 is applied. The ask is narrow: *one read-and-lease verb, service_role
only, projecting no payment, amount, identity or destination, moving no money and transitioning no refund.*

---

## 6. THE OBLIGATION SIDE — WHAT THIS TRAIN DID NOT TOUCH

The refund → venue/promoter path is unchanged and remains as E4 §6 describes: `refund_void` lines are written
by the seam (`settlement_primary_lines`, slice 10b), never by the edge; `close_settlement` nets them; ruling
A4 releases no commission on refunded revenue; and G2's maturity conjunction refuses to release organization
money while a refund on a covered payment is in flight.

**E4 §6.1's open item is now sharper, not resolved.** This executor is what makes `kernel.refund.status =
'failed'` reachable for the first time, and slice 10b books the venue's negative `refund_void` line for any
refund with `status <> 'failed'` — i.e. while still `pending`. A Stripe-accepted-then-unsettled refund
therefore leaves the buyer unpaid **and** the venue permanently debited in an append-only ledger. This train
does not choose among E4 §6.1's four shapes; that is the settlement owner's and the owner's call. It is
listed here so the ratification in §5.4 is not mistaken for closing it.

---

## 7. ATTACK RESULTS

`supabase/tests/158_refund_execution_claim.sql` — **39 assertions, all passing** against a full local replay
of `000`–`093`. Full local pgTAP suite: **3016 passing, 4 known local-only deltas** (`060`'s two pinned
TODOs, `132`'s two db-name artifacts) — the documented baseline, unchanged.
`tests/refund-executor.test.ts` — **70 tests**; whole TypeScript suite **318 passing, 9 files**.

| Attack | Result | Where |
|---|---|---|
| duplicate request | one refund row; `idempotency_replay` returns the same `refund_id` | `085:484-487`; `149` D7 |
| concurrent workers | the second claims **nothing** — `for update … skip locked` + the lease predicate | `158` C1 |
| stale claim | recovers after the lease; attempt counter reaches 2 | `158` C3/C4 |
| lease tampering (`p_lease_seconds = 0`) | clamped to 60s; still claims nothing | `158` C2 |
| claim-record tampering | `UPDATE` on the claim row raises `append_only` | `158` F2 |
| Stripe timeout before response | no state write; row stays `pending`; replay under the same key | `executor.ts` `classifyStripeRefundError` (`writesState:false` on every class) |
| Stripe success + worker crash before DB write | next claim replays the same key inside 24h; **outside 24h the mode is `reconcile` and the refund is found by `metadata[refund_id]`** | §4.3 |
| DB failure after Stripe success | `state_sync_deferred`, retried by the next claim; `mark_refund_state` is `noop_replay` on an identical terminal | `085:1752-1755` |
| retry after Stripe success | `noop_replay`; Stripe is never contacted again | `planRefund` |
| worker crash between `submitted` and `succeeded` | **now recoverable** — `submitted` rows are claimable and always `reconcile` | `158` B2, D3 |
| wrong order | `binding_order_mismatch`; the assertion only ever refuses, never selects | `planRefund` |
| wrong PaymentIntent | no surface — resolved from `kernel.refund.payment_id` (`on delete restrict`) | `158` G2 |
| wrong venue / wrong organization | no surface — neither is a parameter or a projection anywhere in the claim, the context read, or the Stripe body | `158` A4, E1, G3 |
| amount tampering | no surface — the amount is never shown to the worker and never accepted from it; `amount` is still bound to the Stripe key | `158` E1 |
| full refund twice | Σ-guard under the payment lock, plus the executor's own headroom re-check | `085:545`; `amount_exceeds_headroom` |
| partial + full interaction | cumulative operand includes parked requests; `over_refund` fires | `149` DP5 |
| refund after event cancellation | no special case — `cancel_event`'s rows are claimed and executed like any other | `088:1664/1716/1774` |
| refund after payout maturity | G2's conjunction refuses release while a refund on a covered payment is in flight | slice 10d |
| refund after venue payout | negative `refund_void` line, capped so Σ debits never exceed that order's credit; **§6 open item stands** | slice 10b |
| promoter commission funded | ruling A4 — no commission on refunded revenue; releases nothing | slice 10e |
| tombstoned buyer | binds to the payment, not the customer; erasure touches neither table; `succeeded` is what unblocks deletion | `085:76`, `077:1865-2050` |
| deleted / deactivated venue operator | no surface — no operator, venue or org identifier participates in refund execution at any stage | `158` A4, G3 |
| service-role misuse | `authenticated` and `anon` are both refused **behaviourally**, not merely by catalogue | `158` I1/I2/I3 |
| forged worker command | a batch row whose `command_key` is not the DB-issued `refund.execute:<refund_id>` is dropped | `planClaimedBatch`; `refund-executor.test.ts` |
| enumeration | an unknown refund id yields SQL NULL, never a partial object | `158` G1 |
| test-era payment | `stripe_livemode !== true` refuses; NULL (045) fails closed | `158` G4 |

**No test in this document depends on a human typing SQL as the normal path.** The claim verb is reached by
the cron sweep as `service_role`; the platform's refund authority is reached by a platform JWT through
`kernel.request_order_refund`; and `158`'s role boundaries are exercised through `tap.login*`, i.e. as the
principals themselves, not as a superuser reading a grant table.

---

## 8. OPEN ITEMS

1. **`kernel.claim_refunds_for_execution` — PENDING OWNER RATIFICATION** (§5.4). Hard gate before 093 applies.
2. **E4 §6.1** — the `failed`-refund / `refund_void`-line interaction. Four shapes, none taken here (§6).
3. **E4 §5.1** — recording `succeeded` from Stripe's own object rather than from a `charge.refunded` webhook
   branch that does not exist. Unchanged by this train; still flagged for ratification or reversal.
4. **`payout-execute`** — untouched. E4 §11.3's `source_transaction` cardinality question is still the owner's
   and still blocks that executor.
