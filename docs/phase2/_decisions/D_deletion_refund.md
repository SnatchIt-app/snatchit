# DECISION D — ACCOUNT DELETION AND REFUND EXECUTION

**Repo:** `/Users/josetascon/snatchit-consol` · branch `feature/venue-native-and-product-v2`
**Date:** 2026-09-02 · read-only analysis; no migration authored, nothing applied.
**Scope:** the `deletion.refund_possible_window_hours` operand, the direct-ticket deletion path, and
whether a refund executor is a precondition of selling venue-direct tickets.

> **Headline.** A waiting period is **not** architecturally required and is the wrong instrument. The
> tombstone already retains every reference a refund needs, and OR-13/16c Q2 has already ruled that
> *chargebacks* land against the tombstone with **no waiting window** — a refund is strictly easier
> than a chargeback. The real precondition is not *time*, it is an **executor**: today a refund can be
> *recorded* and can never be *paid*, and an unpaid `pending` refund row blocks its buyer's deletion
> **forever** through BP-12 arm 1.

---

## 1. The deletion state machine as built

### 1.1 Three states, one substrate

Three columns on `kernel.identity_ext` — `deletion_state`, `deletion_requested_at`,
`deletion_block_reason` — plus one 2-minute cron sweep
(`docs/architecture/_governance/DELETION_STATE_MACHINE_SPEC.md:28-29`;
`supabase/migrations/077_kernel_identity_orgs_and_roles.sql:2173`).

| State | Entry | Exit |
|---|---|---|
| **ACTIVE** | default; re-entered on withdrawal | a deletion request — **always accepted**, no request-time refusal exists (`DELETION_STATE_MACHINE_SPEC.md:61-66`; `077:1778-1795`) |
| **DELETION_PENDING** | request accepted | withdrawal (`077:1825-1861`) **or** the sweep finding all of BP-1..BP-12 false |
| **ERASED / TOMBSTONED** | the sweep's terminal pass (`078:1801-1806`) | **none.** Terminal in Phase 2; `auth.users` is never deleted (`DSM:114-121`) |

While DELETION_PENDING the account stays **fully usable**: sign-in works, existing tickets **still
scan** (ruled verbatim — `DSM:91-94`), payouts are **paid not forfeited**, disputes proceed, and every
**disposal** verb stays open. Only **acquisition** is frozen (`DSM:89-97`).

### 1.2 The F-clause freeze list (acquisition only)

Ruled surface `DSM:267-291`; shipped sites:

| Clause | Surface | Shipped at |
|---|---|---|
| F-1 | primary reserve / checkout | `081:560`, `082:345` |
| F-2 | native resale purchase (`checkout_buy_now`, offer-accept buyer arm) | `088:1258`, `088:1170` |
| F-3 | `market.make_offer` | `088:1105` |
| F-4 | `market.accept_p2p_transfer` (custody in) | `088:1466` |
| F-5 | live-rail acquisition (PI funding, inbound transfer confirm, RN bids) | `supabase/functions/create-payment-intent/index.ts:258-268`, `confirm-and-release`, `src/screens/PlaceBidScreen.tsx` (E-165) |
| F-6 | role acquisition (`accept_org_invite`, `create_organization`) | 077 role RPCs |
| F-7 | promoter enrolment | `090:473` |

`kernel.is_deletion_pending` is deliberately VOLATILE and takes `FOR SHARE` on the caller's
`identity_ext` row — the F-11 serialization that stops an acquisition racing the terminal pass
(`077:1670-1700`).

### 1.3 The closed blocker set BP-1..BP-12

Evaluated in order by `kernel.sweep_deletion_pending`; the first true one is written to
`deletion_block_reason` and the pass moves on (`078:1709-1761`). The list is **closed over the 57-row
inventory** — adding a predicate requires adding an inventory row first (`DSM:220-221`).

| BP | Blocks on | Clearing event | Body |
|---|---|---|---|
| 1 | own atom in `issued`/`active` | scan · void · expire · transfer out | `079:706` |
| 2 | `wallet_pass` `status='issued'` | supersede / lifecycle sweep | `083:351` |
| 3 | open `market_sale` | complete or compensate | `088:469` |
| 4 | open `p2p_transfer` | accept / decline / TTL | `088:469` |
| 5 | payout `pending`/`submitted` | **paid** (never forfeited) | `085:237-240` |
| 6 | payout `hold_state <> 'none'`; live `transfers` hold | release / review | `085:242-245`, `078:1719-1723` |
| 7 | open or disputed live transfer | terminal status / dispute closes | `078:1725-1732`, `088` native twin |
| 8 | in-flight buy-now reservation | payment lands or release | `078:1734-1736` |
| 9 | won-unsettled auction / live high bid | settles or resolves away | `078:1738-1746` |
| 10 | `identity_obligation status='outstanding'` | recovered / written off | `085:291-297` |
| 11 | sole `org_owner` | ownership transferred | `078:1750-1758`, re-verified under org locks `078:1779-1799` |
| **12** | **open order / live refund path** | **see §2** | `082:656-665` + `085:246-284` |

**Deliberately not predicates:** every append-only audit/adjudication ledger, and the two
AO-CASCADE aborts. Under the tombstone no DELETE is ever issued, so their RESTRICT walls are never
evaluated — they become **retention classes**, not blockers (`DSM:182-196`). This is the load-bearing
consequence of 16a.

### 1.4 The terminal: what is retained, what is erased

Terminal entry (`078:1801-1858`) does exactly five things:

1. `deletion_state := 'ERASED'`; **`deletion_requested_at` is retained** — the durable record that the
   person asked (`078:1803-1806`).
2. Delete `org_member` / `platform_role`; revoke pending invites (`078:1812-1818`).
3. Cancel the deleter's own live auctions on the legacy rail (`078:1824-1833`).
4. Call the four `on_identity_erased_*` hooks (`078:1836-1839`).
5. Best-effort `account_deletion_completed` notice (`078:1850-1858`).

**Terminal action beyond retained+erased: NONE** (`DSM:370`).

**Retained by design** (`DSM:358-370`): `public.payments` (incl. `stripe_payment_intent_id`,
`stripe_livemode`, `refunded_at`, `stripe_refund_id`), `public.transfers`, `kernel.payment_native`,
`kernel.refund`, `kernel.payout`, `venue."order"` and `order_item`, the whole
`kernel.ticket_ownership_log`, `kernel.admin_audit`, `venue.scan`, `dispute_resolutions.actor_id`,
`seller_flags` / `seller_risk_scores` ("deletion must not erase fraud history"), `user_blocks`, the
consent/pref event ledgers, `organization.payout_destination_set_by`, `venue.promoter` and
`promoter_code.created_by`, and sold/completed listings and accepted offers.

**Erased / cleaned:** role grants, pending invites, never-sold listings and non-accepted offers, TTL
holds, the deleter's unreferenced storage media, and the ability to sign in.

**Not erased and explicitly OPEN:** the credential-revocation *mechanism* itself (`DSM:318-324`,
OPEN-7 — no package writes `auth.users`), and whether the demographic answer row is hard-deleted
(OPEN-6a, recorded-not-implemented at `078:1841-1842`).

**Sufficiency of the retained set.**

- **(a) Honour a refund** — YES. `kernel.refund.payment_id → public.payments(id) ON DELETE RESTRICT`
  (`085:76`) and `public.payments.stripe_payment_intent_id` (`000_baseline_schema.sql:988`) both
  survive. A Stripe refund is issued against the **PaymentIntent**, not the customer object.
- **(b) Answer a chargeback** — YES, and this is already ruled: 16c Q2 *"ALLOW later chargebacks
  against the tombstone (no waiting window)"* (`DSM:123-125`). The evidence rows (payments, transfers,
  ownership log, scans, disputes) are all retention-class.
- **(c) Tax / financial record-keeping** — YES. Nothing in the money plane is touched at ERASED;
  `kernel.payout` and `kernel.payment_native` carry `raise_append_only` guards (`085:64-66`, E-50).

---

## 2. BP-12 and the `deletion.refund_possible_window_hours` key

BP-12 is split across **two** functions.

**Arm 0 — pending order** (`kernel.deletion_blockers_orders`, `082:656-665`): any `venue."order"` with
`buyer_id = :id AND status = 'pending'`. Clears when the order terminates. Correct and bounded.

**Arm 1 — refund in flight** (`kernel.deletion_blockers_money`, `085:246-261`): a `kernel.refund` row on
one of the buyer's orders with `status IN ('pending','submitted')`, **or** a pending
`approval_request` with `action='refund.issue'` on one of their orders.

**Arm 2 — the refund-possible window** (`085:262-284`), executing PFA-22 verbatim
(`POST_FREEZE_AMENDMENTS.md:1909-1922`):

```
if exists (order with buyer_id = :id and status in ('paid','partially_refunded')) then
   v_window := config('deletion.refund_possible_window_hours')          -- 085:271-274
   if v_window is null then  return 'BP-12: refund-possible window unset …'   -- 085:275-277
   if exists (candidate with created_at > now() - v_window hours) then blocked -- 085:278-283
```

Seeded `'null'::jsonb`, visibility `restricted`, at `085:2188-2190`.

### 2.1 What this actually does today

- **NULL is fail-closed, candidate-scoped.** With no paid order, NULL does not block (owner ruling
  honoured exactly). With **one** paid order, NULL blocks **and never stops blocking**, because
  `venue."order"` is immutable and a normally-consumed order stays `status='paid'` for ever. The
  candidate set never empties.
- Therefore **the first paid direct order makes that buyer permanently undeletable** while the key is
  unset. Confirmed: `PHASE2_RELEASE_READINESS_REPORT.md:195` lists the key as NULL-safe *"BP-12
  fail-closed"* — safe for a **dark** apply, not for a live direct rail.
- The key **controls deletion safety only**; it "does not create refund eligibility and does not change
  buyer refund policy" (PFA-22, `POST_FREEZE_AMENDMENTS.md:1917-1918`).
- A value of `0` cleanly disables arm 2: `created_at > now() - 0 hours` is `created_at > now()`, which
  is false for every existing row. **No migration is needed to remove the window** — it is a
  `catalog.set_platform_config` write.

### 2.2 The second, worse permanent block

**Arm 1 blocks on `kernel.refund.status IN ('pending','submitted')`, and nothing in the system ever
advances a refund out of `pending`.** `kernel.refund_primary_order` inserts the row at `085:599-600`
and makes **no Stripe call**; `kernel.mark_refund_state` refuses any transition without a
`stripe_refund_ref` (`085:1765-1767`) and is granted to `service_role` only (`085:2152`). There is no
cron tick over pending refunds (`CRON_SCHEDULE_REGISTER.md` — the only 085 job is
`sweep-expired-refund-requests`, `085:2180`).

So today: **record a refund → the buyer's account can never be deleted, and the buyer is never paid.**
Setting the window to 0 does not fix this; only an executor does.

---

## 3. The direct-ticket trace

*A buyer holds a venue-direct ticket for a future event and requests deletion.*

1. **The request is accepted** — unconditionally (`077:1778-1795`). State becomes DELETION_PENDING,
   pending approvals authored by the buyer auto-expire (Q5, `077:1800-1805` → `085:304-332`), the
   `account_deletion_pending` notice is emitted best-effort.
2. **BP-1 blocks.** The atom is `issued`/`active` and owned by the buyer (`079:706`). BP-12 arm 2 also
   blocks while the key is NULL.
3. **Can they transfer or sell it first? NO — on three independent counts.**
   - `market.create_listing` refuses while `feature.native_resale_enabled` is false
     (`088:957-960`); the flag is seeded `false` (`078:1524`).
   - `market.create_p2p_transfer` is **parked fail-closed unconditionally** — the p2p TTL is unnamed in
     the frozen corpus, so the function raises `p2p_ttl_unavailable` before opening any transfer
     (`088:1390`, terminal raise at the end of the body). Flipping the resale flag does **not** unpark it.
   - `kernel.transfer_ticket_ownership` is definer-only; it has no client entry point outside the
     market rail.
4. **So BP-1 clears only by scan, void, or expiry.**
   - **Scan** requires `feature.native_scanning_enabled` (`086:1077`, seeded false at `078:1523`).
   - **Expiry** requires `ticket.expiry_grace`, a PFA-9 CLASS A key that is **not seeded**;
     `kernel.sweep_expired_ticket_atoms` returns `{"swept_count":0}` and does nothing while it is unset
     (`079:474-485`). **This is a hard operational finding: without `ticket.expiry_grace`, a no-show
     buyer's atom never reaches `expired` and BP-1 never clears.**
   - **Void** is `kernel.force_void_ticket`, platform_admin / platform_risk break-glass (`085:739-751`).
5. **If the event is later CANCELLED**, `catalog.cancel_event` (`088:1612`) runs the void+refund
   cascade. It **never reads deletion state**: it walks `kernel.tickets → ticket_ownership_log(seq 1) →
   order_item → order → payment_native → public.payments`, writes one `kernel.refund` per originating
   order under the payment lock, and voids the atoms (`088:1727-1780`). **An erased or pending-deletion
   holder is handled identically to any other holder** — this path is correct as built.
   - Money reaches the tombstone because the refund is bound to `public.payments.id`, whose
     `stripe_payment_intent_id` survives ERASED untouched. **No Stripe customer object is required** —
     `public.profiles.stripe_customer_id` (`026_stripe_customer_id.sql:18`) is a PaymentSheet
     convenience, not a refund operand. `POST /refunds {payment_intent}` returns funds to the original
     instrument regardless of account state; the proven call site already in this repo is
     `supabase/functions/enforce-transfer-expiry/index.ts:264`.
   - **The refund row created by `cancel_event` is `pending` and nothing executes it.** For an already
     ERASED buyer that is merely money owed and unpaid; for a DELETION_PENDING buyer it is also a
     permanent BP-12 arm-1 block.
   - **Gift-then-delete leak:** a buyer who disposes of the atom via a *free* P2P transfer leaves no
     `market_sale` row, so on cancellation the **primary-order arm** fires and the refund is booked
     against the **original payer** — the tombstone — not the person who actually held the ticket. This
     is consistent (the payer paid) but should be a stated policy, not an accident.
6. **Attendee record and door manifest.** Unaffected. BP-1 guarantees an ERASED identity owns zero
   non-terminal atoms, so an erased identity can never appear on a future session's manifest; a
   DELETION_PENDING holder scans normally by ruling (`DSM:91-94`). `venue.list_attendees` is in any
   case parked fail-closed on PFA-28 (`087:1400-1402`), so no roster projection is live to disagree.

---

## 4. The missing refund executor

### 4.1 What exists

| Object | Line | What it does |
|---|---|---|
| `kernel.refund` | `085:74-98` | ledger row; `status pending→submitted→succeeded\|failed`; `stripe_refund_ref` write-once; unique `idempotency_key` |
| `kernel.refund_primary_order` | `085:457-624` | authority (PFA-23: platform direct, or single-use `req:<id>` delegated), sum-guard, atom voids, **inserts the refund row `pending`**, flips order status. EXEC `service_role` only (`085:2149`) |
| `kernel.admin_refund` | `085:629` | payment-scoped break-glass (platform_risk / platform_admin) |
| `kernel.request_order_refund` | `085:850` | buyer request → tier evaluation → parks an `approval_request` or auto-executes |
| `kernel.approve_refund_request` | `085:1089` | dual control → calls the executor with the delegated key (`085:1310`) |
| `kernel.mark_refund_state` | `085:1737-1788` | the **only** writer of `submitted`/`succeeded`/`failed`; demands a `re_…` |
| `catalog.cancel_event` | `088:1612` | bulk refund-row creation on cancellation |

### 4.2 What does not exist

**`refund-execute`.** Not in `supabase/functions/` (11 functions; none is it). It is named as an
obligation in eight corpus documents — `PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md:1131` (*"→ submitted:
the `refund-execute` edge, synchronously, from the object `stripe.refunds.create` returns"*),
`PHASE_2_RPC_FUNCTION_CONTRACTS.md:6133`, `PHASE_2_MONEY_AUTHORITY_SPEC.md:1318`, PFA-23
(`POST_FREEZE_AMENDMENTS.md:1993`) — and is recorded as **not built** at
`PHASE2_RELEASE_READINESS_REPORT.md:159`.

**Exactly what is missing between "recorded" and "money back on the card":**

1. A **claimer** — something that finds `kernel.refund` rows in `status='pending'`. No reader exists:
   `kernel.list_org_refunds` (`085:1487`) is org-scoped and requires `p_org_id`; there is no
   service_role "give me pending refunds" surface and no cron tick.
2. The **Stripe call** — `POST /v1/refunds { payment_intent, amount }` resolved through
   `kernel.refund.payment_id → public.payments.stripe_payment_intent_id`, with a deterministic
   idempotency key (`refund:<refund_id>`).
3. The **write-back** — `kernel.mark_refund_state(refund_id,'submitted', re_…)` synchronously from the
   create response, then `'succeeded'`/`'failed'` from the webhook.
4. A **livemode guard** — `payments.stripe_livemode` must gate execution, exactly as
   `enforce-transfer-expiry/index.ts:368-370` already does.

**Could an existing edge serve?** Not as-is, but the code to copy exists and is battle-tested:

- `enforce-transfer-expiry/index.ts:264` and `:387` already call `POST /refunds` with `payment_intent`,
  a deterministic idempotency key, a livemode gate and a **self-heal sweep** for dropped calls. This is
  the template; a `refund-execute` is a re-parameterisation of it, not a new integration.
- `stripe-webhook/index.ts:705` already handles `charge.refunded` and writes `public.payments`. It must
  be extended with a `kernel.mark_refund_state` call to close the loop.
- `stripe-webhook` handles `payment_intent.succeeded/payment_failed`, `charge.dispute.created/closed`,
  `charge.refunded`, `transfer.created/reversed`, `payout.paid/failed`, `account.updated`. It does
  **not** handle `payment_intent.canceled`.

`_shared/payouts.ts` and `buildPayoutIdempotencyKey` are already earmarked for reuse verbatim
(`PHASE_2_MONEY_AUTHORITY_SPEC.md:62`).

---

## 5. The legacy comparison — how refunds work TODAY

| Scenario | Money moves? | Mechanism |
|---|---|---|
| Transfer expired (seller ghosts) | **Yes, automatic, full** | `enforce-transfer-expiry/index.ts:264`, 2-min cron (`032_pre_testflight_blocker_fixes.sql:102`), self-heal at `:349-445` |
| `charge.dispute.created` | No | `stripe-webhook/index.ts:566` — freezes payout only |
| Dispute closed `lost` | No (Stripe already pulled the funds) | `stripe-webhook/index.ts:693` marks `status='refunded'`; the code comment is explicit that ops decides, *"don't make autonomous money moves here"* |
| Admin rules for the buyer | **No** | `065_dispute_resolution.sql:41-43,139` writes `dispute_resolutions.refund_required = true` — **and nothing consumes that column** |
| Any other refund | Manual | `docs/operations/DAY5_MANUAL_REFUND_PLAYBOOK.md` (*"Stripe Dashboard → Payments → Refund"*) then hand-SQL in `docs/operations/DAY5_ADMIN_SQL_PACK.sql:84-91` |

`capture_method` appears nowhere in the repo — PIs are auto-capture
(`create-payment-intent/index.ts:513-531`), so "refund" is a real refund, never a skipped capture.

**Conclusion:** there **is** a working, hardened refund executor on the live rail today — it is just
wired to a single trigger. **Extending it is strictly cheaper and lower-risk than replacing it**, and
`dispute_resolutions.refund_required` is a ready-made second input.

---

## 6. Options

### Option A — No waiting period; durable tombstone + retained financial references (`window = 0`)

Set `deletion.refund_possible_window_hours = 0`. BP-12 arm 2 becomes inert. Deletion is gated
exclusively by **event-driven** predicates (BP-1..BP-11 and BP-12 arms 0/1), never by a clock. Refunds
after ERASED execute against the retained PaymentIntent.

**Advantages**
- Consistent with what the owner has *already ruled*: chargebacks land against the tombstone with **no
  waiting window** (16c Q2, `DSM:123-125`). A refund is a superset-easier operation; a window for
  refunds but none for chargebacks is incoherent.
- Consistent with the machine's own principle: resolution is *"event, scan, or settlement — never the
  user"* (`DSM:109-110`). A time window would be the **only** clock-driven blocker in a closed set of
  eleven event-driven ones.
- Requires **no arbitrary number** — the owner's explicit constraint is satisfied by construction.
- Zero code: one `catalog.set_platform_config` write.
- Refunds remain fully possible post-erasure: `cancel_event` is holder-agnostic (`088:1727-1780`) and
  Stripe refunds bind to the PaymentIntent.

**Disadvantages**
- A post-erasure refund is **silent to the customer** — the account has no channel. The bank statement
  is the only notice.
- Support cannot reach the person to explain. Their email may also be permanently unusable for
  re-registration (OPEN-7 is unresolved, `DSM:318-324`).
- Relies on BP-12 arm 1 to be a *real* gate — which requires an executor, else arm 1 is a permanent
  block rather than a transient one.

**Failure modes**
- Executor missing → arm 1 never clears → the buyer is permanently undeletable anyway. **This option is
  only coherent alongside §7's executor.**
- `ticket.expiry_grace` unset → BP-1 never clears for unscanned atoms; window=0 does nothing for them.

**Launch implications:** direct rail can go live. Deletion completes for buyers whose orders are
settled and whose atoms are terminal.

**Consumer-protection exposure:** LOW-MODERATE. Money is returnable indefinitely; the weakness is
notification, not entitlement.

---

### Option B — A refund-policy-derived window (not an arbitrary number)

Set the window to the platform's *actual stated refund promise* for direct tickets — e.g. the same
horizon the venue's refund policy advertises — so it is derived, not invented.

**Advantages**
- Keeps a live account (and a live notification channel) for exactly as long as a refund is *likely*.
- Defensible to a regulator: the number equals a published promise.

**Disadvantages**
- The corpus has **no such published promise yet**; deriving one means writing the buyer refund policy
  first — a larger decision than this one, and PFA-22 explicitly says this key must **not** encode
  refund eligibility (`POST_FREEZE_AMENDMENTS.md:1917-1918`). Using it that way misuses the operand.
- Measured from `order.created_at` (`085:281`), not from the event — so a ticket bought nine months
  out has a window that expires long before the event it is for. The window is misaligned with the
  risk it is meant to cover.
- Still a clock in an event-driven machine.

**Failure modes:** the window expires while a cancellation is still possible → identical to Option A,
but with the extra cost of having pretended otherwise.

**Launch implications:** same as A plus a policy-drafting dependency.
**Consumer-protection exposure:** LOW, but the reasoning is not sound and would not survive review.

---

### Option C — Status quo: leave the key NULL (fail-closed)

**Advantages**
- No decision taken; correct and harmless while the rails are dark.

**Disadvantages**
- **Any buyer who completes one paid direct order becomes permanently undeletable** (§2.1). That is a
  standing failure against App Store Guideline 5.1.1(v) (in-app account deletion) and against GDPR/CCPA
  erasure obligations, produced by a config default rather than a policy.
- The user-visible symptom is a permanent "your deletion is blocked" reason string
  (`085:276`) that never changes and that the user can do nothing about — the exact
  "deletion never completes" outcome 16a was ruled to eliminate.

**Failure modes:** silent, cumulative, and only observable as a growing population of stuck
DELETION_PENDING rows.
**Launch implications:** **direct ticket sales must not go live in this state.**
**Consumer-protection exposure:** HIGH.

---

### Option D — Window = 0, and gate direct-ticket selling on `refund-execute` shipping

Option A **plus** an explicit precondition: no direct ticket is sold until the executor exists and is
deployed.

**Advantages**
- Removes both permanent-block classes at once (arm 2 by config, arm 1 by execution).
- Makes the money-back promise real rather than recorded, before any customer is exposed to it.
- The build is small and precedented (§4.2): the Stripe call, the idempotency discipline, the livemode
  gate and the self-heal sweep all already exist in `enforce-transfer-expiry`.
- Closes the ledger honestly: every refund reaches `succeeded` or `failed` with a `re_…`.

**Disadvantages**
- Adds an engineering item to the critical path (realistically one edge function plus one webhook
  branch plus one service_role reader).
- Does not fix `ticket.expiry_grace` or the scanning flag; those must be handled alongside.

**Failure modes:** if the executor ships without the write-back to `mark_refund_state`, arm 1 still
blocks forever — the write-back is the load-bearing half, not the Stripe call.

**Launch implications:** short delay to direct-ticket go-live; nothing else is blocked.
**Consumer-protection exposure:** LOWEST.

---

## 7. RECOMMENDATION — Option D

**Set `deletion.refund_possible_window_hours = 0`, and treat a refund executor as a hard precondition
of selling venue-direct tickets.**

**On the waiting period.** A waiting period is **not required**. The tombstone is durable, the money
plane is untouched at ERASED, and a Stripe refund binds to a PaymentIntent that survives erasure. The
owner has already ruled that chargebacks — the harder case — need no waiting window; refunds cannot
coherently need one. A clock would also be the sole time-driven member of a closed set of event-driven
predicates, contradicting the machine's own stated resolution principle. **Set the value to 0. Do not
invent a number.**

**On the executor.** A refund executor **is a hard precondition** of selling direct tickets — but the
precondition is *executability*, not specifically an edge function. Precisely:

- **A purely manual path — a human refunding in the Stripe dashboard — is NOT acceptable on its own**,
  because it leaves `kernel.refund` in `pending` for ever. That is not a cosmetic ledger defect: it
  permanently blocks that buyer's account deletion via BP-12 arm 1, it makes the refund ledger lie, and
  it silently disagrees with `public.payments`.
- **A manual path *plus* a named write-back process IS acceptable for a limited launch**, provided the
  process is written down and owned: (1) operator refunds in the Stripe dashboard against the
  `stripe_payment_intent_id`; (2) operator calls
  `kernel.mark_refund_state(refund_id,'submitted',re_…,null,key)` then `'succeeded'` as `service_role`;
  (3) a standing check that no `kernel.refund` row sits `pending` beyond an agreed age. This is the
  same posture the platform already runs on the live rail
  (`docs/operations/DAY5_MANUAL_REFUND_PLAYBOOK.md`, `DAY5_ADMIN_SQL_PACK.sql:84-91`) and it is
  survivable at low volume.
- **But building `refund-execute` is cheaper than operating that process.** The Stripe call, the
  idempotency key discipline, the `stripe_livemode` gate and a self-heal sweep already exist verbatim
  at `enforce-transfer-expiry/index.ts:264-445`. The honest recommendation is to **build it**, and to
  hold the manual runbook only as the documented fallback for the window between first direct sale and
  executor deployment — with an explicit cap on that window.

**Also required before the direct rail goes live (both are BP-1 preconditions, not refund matters):**

- **`ticket.expiry_grace` must be set.** Unset, `kernel.sweep_expired_ticket_atoms` is a no-op
  (`079:474-485`) and a no-show buyer's atom never leaves `active` — BP-1 blocks for ever. This is a
  *larger* permanent-block risk than BP-12, because it needs no money at all to trigger.
- **Decide the disposal story.** With `feature.native_resale_enabled=false` and
  `market.create_p2p_transfer` parked (`088:1390`), a direct-ticket holder has **no way to sell or gift
  the ticket**. That is acceptable if scanning is on and expiry is configured, and unacceptable
  otherwise. State it deliberately.

**Also record as policy:** on cancellation, a ticket that was **gifted** onward refunds the **original
payer**, not the current holder (`088:1727-1780`). Correct, but it must be a stated rule.

---

## 8. Classification

| Item | Classification |
|---|---|
| Whether a waiting period exists at all | **OWNER POLICY** — decided here: none |
| Setting `deletion.refund_possible_window_hours = 0` | **OPERATIONAL CONFIG** — a `catalog.set_platform_config` write; PFA-22 already designates it an owner value (`PHASE2_RELEASE_READINESS_REPORT.md:195`). No migration. |
| Setting `ticket.expiry_grace` | **OPERATIONAL CONFIG** — PFA-9 CLASS A key; consumer is fail-inert |
| Building `refund-execute` (+ the `charge.refunded` → `mark_refund_state` webhook branch) | **IMPLEMENTATION FOLLOW-UP** — deploy artifacts only. The corpus already names the function (edge §3.5), its authority (PFA-23), and its EXECUTE grants (`085:2149`, `085:2152`). Nothing frozen changes. |
| The manual-refund runbook as interim fallback | **OPERATIONAL CONFIG** (a named, owned process) |
| Refund reaching a tombstoned identity | **WITHIN FROZEN ARCHITECTURE** — already works; `cancel_event` is holder-agnostic and the PaymentIntent survives ERASED |
| Gift-then-delete refunds the original payer | **OWNER POLICY** — record the rule; no code change |
| Credential revocation mechanism (OPEN-7) | **OWNER POLICY / POST-FREEZE AMENDMENT** — out of scope here, but still open and it gates the honesty of "the person cannot sign in" |

**No POST-FREEZE AMENDMENT is required for this decision.** PFA-22 already anticipated the value being
set; setting it to 0 is the ruling's own mechanism, not an exception to it.

---

## 9. What a migration 093 would need — *description only, not authored*

**093 is not required for this decision.** Everything above is config plus deploy artifacts. 093 becomes
necessary only if the executor is to be **driven by a database tick** rather than by the webhook and an
operator. In that case it would need, and only these:

1. **A service_role claim reader** — e.g. `kernel.list_pending_refunds(p_limit int)` returning
   `refund_id`, `payment_id`, `amount_minor`, `currency`, and the resolved
   `stripe_payment_intent_id` + `stripe_livemode`, ordered oldest-first with `SKIP LOCKED`. No such
   reader exists; `kernel.list_org_refunds` (`085:1487`) is org-scoped and unusable for this. This is a
   **new function**, additive — it replaces no frozen body and changes no frozen signature.
2. **A cron + `pg_net` tick in the 087 `crm-export` shape** — `cron.schedule` calling the
   `refund-execute` edge. This needs an owner-named **dedicated header name** and an owner-named
   **Vault secret name**, neither of which any frozen byte supplies — precisely the `NOTIFY_DISPATCH_TICK`
   / `E-158` class of external operational requirement
   (`POST_FREEZE_AMENDMENTS.md:2517`, `:2526`). It must fail closed on a missing Vault row.
3. **A `CRON_SCHEDULE_REGISTER.md` row** for the new tick, per the P0-1 per-job discipline.

**Explicitly NOT needed, and to be avoided:** a lease/claim column on `kernel.refund`. That table is
frozen 085 bytes and carries a `set_updated_at` trigger; adding a lease would be a schema amendment.
Double-submission is already prevented without one — `kernel.refund.idempotency_key` is UNIQUE
(`085:93`) and a deterministic Stripe idempotency key (`refund:<refund_id>`) makes a repeated
`POST /refunds` a no-op that returns the same `re_…`, exactly as `enforce-transfer-expiry` already
relies on (`index.ts:264`, `:387` share one key by design). **Prefer the webhook-plus-idempotency design
and skip 093 entirely.**

---

*Prepared read-only. No migration authored, no production object touched, no commit made.*
