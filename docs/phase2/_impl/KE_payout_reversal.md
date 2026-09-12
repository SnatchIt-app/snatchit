# KE — payout reversal state machine (full + partial) and the ref-bearing failed payout

**Investigator E.** Investigation only — nothing implemented, nothing deployed, no remote, no Stripe call.
Every execution below ran on the local rehearsal database `snatchit_rehears_e` (fresh replay of all 110
migrations via `scripts/rehearsal_reset.sh`, GATE-2 `tables=27 functions=70 policies=37 triggers=26`, then
`supabase/tests/000_helpers.sql` loaded as `postgres`). Fixture SQL is reproduced in Appendix A so any
result here can be re-run verbatim.

Repo: `/Users/josetascon/snatchit-consol` @ `609e0f4` (`feature/venue-native-and-product-v2`).

---

## 1. What I inspected (file:line)

| Object | Where | What matters here |
|---|---|---|
| `kernel.payout` DDL | `supabase/migrations/085_kernel_money_native.sql:111-160` | 18 columns (+`destination_ref` from 093:1685). **No amount column other than `amount_minor` (the obligation).** `stripe_transfer_ref text` — "written ONLY by mark_payout_transfer_state, write-once" (085:133). **No unique index on `stripe_transfer_ref`** (catalog: only `payout_pkey`, `payout_idempotency_uq`, three btrees, the hold queue partial). |
| `kernel.mark_payout_transfer_state(uuid,text,text,text,text)` | 085:1668-1735 | Signature `(p_payout_id, p_new_status, p_stripe_transfer_ref, p_failure_code, p_command_key)`. **No amount parameter.** Edges: `submitted→paid|failed`, `paid→reversed` (085:1699-1703). Ref mandatory for `paid|reversed` (085:1704); **not forbidden for `failed`** — `coalesce(v_row.stripe_transfer_ref, p_stripe_transfer_ref)` stores whatever arrives (085:1719). **No shape check on the ref.** Fires `venue.on_payout_settled` on `paid` only (085:1729-1732). service_role only (085:2116-2151). |
| `venue.on_payout_settled(uuid)` | `087_venue_settlement_and_export.sql:360-384` | closed→paid iff no `cause='settlement'` sibling is non-paid. **No inverse exists** (no writer of paid→anything; 095 E-5 trigger forbids it, 095:856-862). |
| `venue.settlement` / `settlement_line` | 087:37-118 | Header forward-only after 095 E-5. Line cause set (catalog): `issue, primary_sale, comp, door_sale, p2p_transfer, market_sale, auction_sale, admin_action, refund_void, import, promoter_commission, settlement, chargeback`. **No reversal-shaped cause.** |
| `kernel.request_org_payout` | 087:408-575, re-created 093:1703-1958 (10k) | Selects only `status in ('pending','submitted')` (087:451-453). Probation arm reads `payout.state_sync` audit rows with `after->>'status'='paid'` (087:479-481). |
| 093 slices 10j-10q | 093:1626-2780 | 10j `destination_ref` pin; 10n `get_payout_execution_context` refusal order (`payout_held` → `payout_not_submitted` → `transfer_already_recorded` …, 093:2351-2380 / 095:1074-1110); 10o `hold_payout_destination_changed` refuses `stripe_transfer_ref is not null` (093:2497); 10p `claim_payouts_for_execution` selects `status='submitted' and hold_state='none' and stripe_transfer_ref is null and destination_ref is not null` (093:2661-2672), mode `reconcile` only when the FIRST `payout.execute_claim` audit row is >20h old (093:2686-2690). |
| 095 in full | `095_payout_state_machine_recovery.sql:1-1156` | E-2 `rearm_failed_payout` refuses `transfer_already_recorded` (095:320-323); E-4 `hold_payout_transfer_reversed(uuid,text,integer,integer,jsonb,text)` submitted-only, refuses `paid` with the "partial is unrepresentable (owner item J5 §8)" message (095:718-724), stores the `tr_` **only in the audit row** (095:745, 755). Named residuals 095:254-261, 646-648. |
| Executor | `supabase/functions/payout-execute/executor.ts` | `classifyTransferReversal` reads `amount_reversed` (286-318); `planReconcile` returns `kind:'reversed'` for ANY `amount_reversed>0` on the single group transfer (702-719) — never `adopt`, never `create_allowed`; `authorizeTransfer` body sets `transfer_group=payout_<id>` and `metadata[payout_id|settlement_id|org_id|source=payout-execute]` (768-777); `PAYOUT_STATE_SYNC_TARGETS=['paid']` (874); `buildTransferGroup` (364-367). |
| Executor shell | `payout-execute/index.ts` | `holdReversedTransfer` → `hold_payout_transfer_reversed` from both the reconcile read (394-406) and the post-create sync (471-484). Reconcile mode fetches `GET /v1/transfers?transfer_group=…&limit=100` (263-272) — **only for a claimed (`submitted`) payout**; a `failed` row is never claimed (093:2664). |
| Legacy payout | `_shared/payouts.ts:80-160` | `createSellerPayout` sets `source_transaction`, `metadata[transfer_id|payment_id|seller_id]`, **no `transfer_group`** (134-144). `_shared/payout-logic.ts:24` key `payout_<transferId>_<dest>_src`. |
| Webhook | `stripe-webhook/index.ts:1133-1152` | `transfer.reversed` → `public.mark_transfer_reversed(tr.id)` (0561:114-135, `UPDATE public.transfers … WHERE stripe_transfer_id = $1`; "`> 0`, NOT `= 1`: transfers.stripe_transfer_id has no unique index", 0561:129). Zero rows ⇒ "no-op" ⇒ `markProcessed()` ⇒ event completed and **never replayed** (307-323). No native branch; `resolveRail` (native.ts:115-133) is applied to PI/charge metadata only (index.ts:398, 791). |
| Tests | `tests/payout-executor.test.ts:411-500, 596-660`; `supabase/tests/161_payout_state_machine.sql` §B, §C (C15/C15a), §F | Executor never writes `failed`; reconcile adopts an orphan, refuses two transfers, refuses amount/payee mismatch; 161 C15 pins the ref-bearing-failed strand as the named residual. |
| 094 obligation | `094_organization_obligation.sql:177-246, 320-415, 431-476, 504-513, 740-776` | `record_organization_obligation(uuid,text,uuid,text,integer,text,text,text)`; origin `settlement_shortfall` is existence+amount-verified against the header (352-375); **`unlined_reversal` verifies only "not lined" — origin existence is NOT verified** (376-385). `resolve_organization_obligation(uuid,text,text,text)` — **no amount: all-or-nothing** (431-476). |
| Prior evidence | J5 §5, §8 (owner items 1-3); J2 §4 (trr_ object, `reversed` false on partial, Stripe may reverse on its own — 4.3), §7.4; G5 §1 case table, §5; H8 §5 | Adopted as read; nothing contradicted by execution. |

---

## 2. What I executed, and the results

All probes ran as `postgres` through `tap._try()` (dynamic SQL in a sub-block that returns the error text
instead of aborting). Org `KE Co` (approved, `acct_KE1`, `connect_transfers_active`), venue approved, one
session ended 40 days ago, `other_user` = matured `org_finance`, `payout.dual_control_min_minor` set high so
requests advance directly. Money lines are inserted as owner, then `kernel.close_settlement` as admin.

### 2.1 Scenario 1 — paid 10 000, then FULL reversal through the shipped edge

```
1a minted   status=pending  hold=none ref=-       amount=10000 dest=-
1b request  {"status":"submitted"}            dest=acct_KE1
1c paid     mark_payout_transfer_state(p1,'paid','tr_KE1',NULL) → ok
            payout: status=paid ref=tr_KE1 | settlement status=paid gross=10000 net=10000
1d reversed, NULL ref      → ERR invalid_input: stripe_transfer_ref is mandatory for reversed
1e reversed, 'tr_OTHER'    → ERR conflict_locked: stripe_transfer_ref is write-once (tr_KE1 vs tr_OTHER)
1f reversed, 'trr_KE1'     → ERR conflict_locked (the trr_ reversal id is NOT storable anywhere)
1g hold_payout_transfer_reversed(p1,'tr_KE1',10000,6000) on a PAID row
                           → ERR precondition_failed: payout is paid — … PARTIAL reversal is unrepresentable (owner item J5 §8)
1h reversed, 'tr_KE1'      → ok {"new_status":"reversed"}
            payout: status=reversed ref=tr_KE1 amount=10000
            settlement: status=paid gross=10000 fees=0 refunds=0 net=10000      ← UNCHANGED
1i replay reversed         → noop_replay
1j after 'reversed':
   paid    → payout_state_backwards (reversed → paid)
   failed  → payout_state_backwards (reversed → failed)
   rearm   → precondition_failed: payout is reversed, not failed
   request → precondition_failed: no pending payout for this settlement
   hold    → precondition_failed: payout … is reversed — only an unexecuted payout holds
   release → noop_replay
   ctx     → refusal_code = payout_not_submitted ;  claim → 0 rows ;  re-close → noop_replay
1k organization_obligation rows for the org → 0
1l record_organization_obligation(org,'unlined_reversal', origin_ref := p1.payout_id, NULL, 10000, …)
                           → ok (obligation_id …)   ← accepted; origin existence not checked
1m audit p1: payout.request/submitted · payout.state_sync/paid · payout.state_sync/reversed   (no amount anywhere)
1n audit s1: settlement.open · settlement.close · settlement.paid/payout_settled              (nothing after the reversal)
```

**Answers to the brief's §14 questions.** `paid→reversed` requires only the same `tr_` (write-once
equality) and a non-held row; it takes **no amount**; it does **not** touch the settlement header
(`paid` stays `paid`); `venue.on_payout_settled` has **no inverse** and E-5 makes one unwritable. After
`reversed` the row is absorbing: every verb in the corpus refuses it, nothing re-mints (`settlement:<id>`
idempotency + `noop_replay` on re-close), and the venue's 10 000 — which Stripe has pulled back to the
platform — exists in no table. The ledger reads "settlement paid, payout reversed, org owes nothing".

### 2.2 Scenario 2 — the ref-bearing failed payout (brief §14 second half)

```
request  → submitted
2a mark_payout_transfer_state(p2,'failed','tr_KE2','transfer_failed') → ok {"new_status":"failed"}
   payout: status=failed hold=none ref=tr_KE2 amount=4000 dest=acct_KE1   ← the ref IS stored on 'failed'
   settlement: status=closed net=4000
2b every exit:
   rearm_failed_payout      → precondition_failed: transfer_already_recorded — payout … carries tr_KE2 …
   paid (same ref)          → payout_state_backwards (failed → paid)
   reversed (same ref)      → payout_state_backwards (failed → reversed)
   failed again, same ref   → noop_replay
   failed, different ref    → payout_state_backwards (failed → failed)   (write-once holds)
   hold_payout_transfer_reversed → precondition_failed: payout is failed, not submitted
   hold_payout_destination_changed → precondition_failed: transfer_already_recorded
   hold_payout              → only an unexecuted payout holds
   release_payout           → noop_replay
   request_org_payout       → no pending payout for this settlement
   retry_held_payout        → no pending payout for this settlement
   get_payout_execution_context → refusal_code = payout_not_submitted
   claim_payouts_for_execution  → 0 rows
   close_settlement (re)    → noop_replay
   row afterwards: status=failed ref=tr_KE2 amount=4000   (unchanged)
```

**Stranding proved end to end.** Twelve verbs, twelve refusals, and the executor cannot even *see* the
row (claim requires `submitted`), so its `reconcile` mode — which is where the Stripe-observed facts
live — never runs for it. Note also *what this state means*: a Stripe Transfer has no accepted-then-failed
lifecycle (executor.ts:902-905 — `POST /v1/transfers` returns a `tr_` or errors), so `failed`+`tr_` is a
state the Stripe object model cannot produce for this rail; it can only be written by a service_role
caller asserting it (a mis-sync, a future client, or an operator using the verb by hand).

### 2.3 Scenario 3 — the ref's shape is not validated

```
mark_payout_transfer_state(p3,'failed','not a transfer id','weird') → ok
payout: status=failed ref='not a transfer id'
```

A non-`tr_` string is storable in the write-once column. Contrast `hold_payout_transfer_reversed`, which
enforces `^tr_[A-Za-z0-9]+$` (095:688).

### 2.4 Scenario 4 — one `tr_` on two payouts

```
mark_payout_transfer_state(p4,'paid','tr_KE1')   (tr_KE1 already on p1) → ok
payouts carrying tr_KE1 = 2  →  p1:reversed, p4:paid
```

No unique index; two settlements were advanced to `paid` off one Stripe transfer id. A lookup
"which payout does `transfer.reversed tr_KE1` belong to" is ambiguous.

### 2.5 Scenario 5 — partial reversal AFTER paid: where can 6 000 live?

```
paid tr_KE5 → payout status=paid amount=10000 | settlement paid net=10000
5a hold_payout_transfer_reversed(paid, 6000)  → refused (as 1g)
5b UPDATE kernel.payout SET amount_minor=4000 (owner session) → OK: 4000   ← nothing guards amount on a terminal row
5c settlement_line cause CHECK: no reversal cause (list above)
5d a second settlement lining cause='settlement' ref=p5.payout_id amt=-6000:
   closes  status=closed gross=0 fees=6000 refunds=0 net=-6000
   → 094 books settlement_shortfall/6000/outstanding   (now 2 obligation rows: unlined_reversal/10000 + settlement_shortfall/6000)
5e settlement_unbooked_refund_exposure(s5) → 0   (a reversal is not a refund; the exposure operand ignores it)
```

So today a partial reversal can only be "represented" by (a) mutating the obligation column (dishonest —
`amount_minor` IS the minted obligation, 095:209-214), or (b) abusing a `cause='settlement'` line in a new
header, which mis-labels a Stripe reversal as a settlement fee (`fees_minor=6000`) and then books a
**second** obligation for a debt the platform may already have recovered — the double count §17 warns about.

### 2.6 Scenario 6 — `transfer.reversed` for a payout still `submitted` (ref not yet stored)

```
hold_payout_transfer_reversed(p6,'tr_KE6',8000,8000) → {"status":"held","fault":"transfer_reversed"}
payout: status=pending hold=held reason=transfer_reversed ref=-           (tr_KE6 only in audit)
6a release_payout → ok ; request_org_payout → submitted
   payout: status=submitted hold=none ref=-  ;  ctx execution_eligible=true  ;  claim mode=create
audit lookup: after->>'stripe_transfer_ref'='tr_KE6' → payout.transfer_reversed_hold, subject p6   (findable, unindexed)
```

Once released and re-requested the row is fully eligible again. What then happens is decided by
executor.ts, not the DB: in `create` mode the deterministic key `payout_<id>_<dest>_v1` replays the SAME
(reversed) transfer inside Stripe's 24 h window and `planPayoutStateSync` holds it again; in `reconcile`
mode `planReconcile` finds `tr_KE6` in the group with `amount_reversed>0` and returns `reversed` (702-719)
— never `create_allowed`. **A settlement payout whose one transfer was fully reversed can therefore never
be paid again through this row; every release→request→execute cycle lands back in the same hold.** The
venue is owed 8 000 with no path to it (see F-4).

### 2.7 Other probes

```
org_outstanding_obligation_minor(org) → 16000        (10000 unlined_reversal + 6000 shortfall — for ONE 6000 economic event + one reversal)
record_organization_obligation(org,'settlement_shortfall', origin := p1.payout_id, …) → not_found: settlement …   (shortfall IS verified)
record_organization_obligation(org,'unlined_reversal', origin := gen_random_uuid(), …, 1) → ok            (a random origin books a debt)
resolve_organization_obligation(o,'recovered') → ok                                                        (no amount: cannot record 2000 of 6000)
087:479 probation predicate — a REVERSED payout still satisfies "a payout was paid since the change" → 1 row
grants: mark_payout_transfer_state svc=t auth=f · hold_payout_transfer_reversed svc=t auth=f · rearm svc=f auth=t
        record/resolve_organization_obligation svc=t auth=f · on_payout_settled nobody
```

---

## 3. Findings, ranked

**P0 — none.** Nothing here moves money wrongly on its own today: `paid→reversed` has no caller,
`transfer.reversed` for a native transfer is dropped (not mis-applied), and every stranding leaves the
row inert rather than paying twice. All of the below are ledger-truth and recoverability defects that
become live the moment venue payouts are activated (Gate-M).

| # | Sev | Finding | Evidence |
|---|---|---|---|
| F-1 | **P1** | **Native `transfer.reversed` is silently discarded and the event is completed, never replayed.** The webhook routes the event to `public.mark_transfer_reversed` only; for a native transfer there is no `public.transfers` row, the RPC returns `false`, the handler logs "no-op" and calls `markProcessed()` (index.ts:1141-1149 → `complete_stripe_webhook_event`, 307-323). The `paid→reversed` edge, the only driver of `reversed`, is therefore unreachable in production (J5 §8 item 3, now with the exact consequence). | index.ts:1133-1152; 0561:114-135 |
| F-2 | **P1** | **A full reversal after `paid` leaves the settlement header `paid` and books nothing.** `reversed` is absorbing, `on_payout_settled` has no inverse, E-5 forbids the header moving, no obligation is written, nothing re-mints. The venue's entitlement (ruling A5: face value) vanishes from every table. | §2.1 lines 1h-1n |
| F-3 | **P1** | **A partial reversal after `paid` is unrepresentable** — no column, no verb (E-4 refuses `paid`), no settlement_line cause; the only storable "representations" mutate the obligation or mis-label the reversal as a fee and double-book an obligation. | §2.5 |
| F-4 | **P1** | **A fully-reversed transfer in the transfer_group permanently blocks the settlement from ever being paid.** E-4 holds the row; release + re-request is allowed (no memory of the reversal on the row); the executor then re-holds it forever because `planReconcile` never returns `create_allowed` while the group holds a transfer with `amount_reversed>0`. J2 §4.3: Stripe may reverse on its own initiative (whether that reaches a no-`source_transaction` transfer is **unverified**); a platform-initiated reversal certainly can. | §2.6; executor.ts:702-719 |
| F-5 | **P1** | **The ref-bearing `failed` payout is fully stranded — and the state itself is not a Stripe-producible one.** Twelve refusals; the executor cannot claim it, so the one place with Stripe-observed facts never looks. Known (095:254-261, J5 §8.1) — here proved exhaustively. | §2.2 |
| F-6 | **P1** | **`stripe_transfer_ref` has no uniqueness.** One `tr_` marked two payouts `paid` (two settlements discharged by one Stripe transfer). Any webhook lookup by ref is ambiguous; any reconciliation by ref can attach facts to the wrong payout. 060's F-2 todo notes the same gap on the legacy table (rehearsal_test.sh:69). | §2.4 |
| F-7 | P2 | `mark_payout_transfer_state` stores an arbitrary string as the write-once ref (`'not a transfer id'`), including via `failed`. A future reconcile verb keyed on the ref must treat a malformed stored ref as "unresolvable", not as evidence. | §2.3 |
| F-8 | P2 | `record_organization_obligation('unlined_reversal', …)` verifies only "not already lined"; **origin existence is not checked** — a random uuid, or a payout id, books an outstanding debt. Combined with §2.5 (5d) the same economic event can be booked twice under two origin kinds (`16 000` outstanding for one 6 000 debt). | §2.1 1l, §2.7 |
| F-9 | P2 | `resolve_organization_obligation` is all-or-nothing (no amount). A partial recovery (2 000 of 6 000) cannot be recorded against the obligation; partial recovery and partial reversal are the **same** gap seen from the two sides of the transfer. | 094:431-476 |
| F-10 | P2 | The §10.3 destination-probation disarm reads `payout.state_sync … after->>'status'='paid'` and does not look at the row's current status, so a payout that was paid **and then reversed** still counts as "a payout paid since the destination change" and disarms probation for the next one. | 087:479-481, §2.7 |
| F-11 | P2 | `amount_minor` on a terminal (`paid`/`reversed`/`failed`) row is unguarded against a table-owner/definer write (E-1's trigger binds only `→submitted`). Same reachability caveat as E-5 (095:793-801): not client-reachable, but no invariant. | §2.5 5b |
| F-12 | P2 | E-4 records the `tr_` only in `admin_audit.after` (unindexed jsonb). A webhook that must decide "has this transfer already been observed for this payout" has no keyed fact to consult. | §2.6 audit lookup |

---

## 4. Options, trade-offs, the smallest honest design

### 4.1 Where a (partial) reversal amount can live — brief §15 models A-F

Columns of `kernel.payout` (catalog, §1): `payout_id, payee_kind, payee_org_id, payee_identity_id, cause,
cause_ref, amount_minor, currency, status, hold_state, hold_reason_code, held_by, held_at,
stripe_transfer_ref, source_transaction_ref, idempotency_key, created_at, updated_at, destination_ref`.
There is **nowhere** on the row for "6 000 of 10 000 came back", and `amount_minor` is the minted
obligation (095:209-214; the executor's anti-tamper equality `settlement_net_minor === amount_minor`,
executor.ts:508-513, depends on it never moving).

| Model | Shape | Honest? | Trade-offs |
|---|---|---|---|
| **A** `kernel.payout_reversal` facts table | one row per Stripe `transfer_reversal` (`trr_` UNIQUE), `amount_minor>0`, append-only, Σ-guard trigger `Σ ≤ payout.amount_minor`, derived `fully_reversed := Σ = amount_minor` | **Yes** | Same idiom as every idempotent money writer in the corpus (094:29-40: `INSERT … UNIQUE(origin)` is the idempotency mechanism under at-least-once delivery). Partial is native. One new table on the money layer (additive, own migration 096). Needs a writer verb and a reader; the webhook and the reconcile verb both feed it. |
| B `kernel.payout_adjustment` (signed, generic) | signed rows of any "adjustment" | No | Encodes direction in a sign (the thing 094:44-49 refuses), no natural idempotency key (a reversal has `trr_`; a generic adjustment has nothing), and invites the negative-payout hack. Wider than the fact it needs to record. |
| C `reversed_minor` column + audit events | mutable accumulator on the row | No | `balance = balance + X` under an at-least-once webhook has no DB-enforceable idempotency — the exact argument 094's header makes against a mutable balance (094:28-40). A replayed `transfer.reversed` double-counts and the row carries no evidence it happened. Also widens a frozen table's write set. |
| D a separate Stripe-object mirror (`kernel.transfer` with reversals) | mirror the Transfer object | Over-built | Conflates rails, duplicates `stripe_transfer_ref`, and still needs the reversal facts as child rows — i.e. it is A with an extra parent. |
| E status stays `paid`, reversal facts only (never `reversed`) | A minus the status move | Defensible but leaves a shipped edge dead | Avoids touching `mark_payout_transfer_state`; but `reversed` then never means anything, and a reader must join to know a payout is worthless. 095's own text treats `reversed` as the honest word for the full case (095:713-720). |
| F audit-only (today's E-4 posture extended to paid rows) | jsonb in `admin_audit.after` | **No** | Not queryable by key, no Σ invariant, no `trr_` idempotency, cannot drive an obligation. It is what exists now and it is why F-2/F-3/F-12 exist. |

**Recommendation: A, with E's discipline for the partial case.** Precisely:

* `status` moves to `'reversed'` **only** when `Σ(payout_reversal.amount_minor) = payout.amount_minor`,
  and it moves through the existing edge: the writer verb calls
  `kernel.mark_payout_transfer_state(p_payout_id,'reversed', payout.stripe_transfer_ref, null, p_command_key)`
  in the same transaction (085:1699-1703 accepts it; same-ref equality holds; a held row cannot be `paid`
  so the `payout_held` refusal cannot fire). No second door onto `status`.
* While `Σ < amount_minor` the row **stays `'paid'`** with `hold_state` untouched (a terminal row cannot be
  held — 085:790). "How much of this payout is still with the venue" becomes a derived read
  `amount_minor − Σ`, never a stored column.
* `venue.settlement` **stays `'paid'` in both cases.** The header records that the settlement's payout
  instruction was executed (087:41-42, "written ONLY by venue.on_payout_settled"); after E-5 it is forward-only.
  The economic consequence of a reversal is carried on the obligation side (below), not by rewinding the header.
* Σ-guard: a `BEFORE INSERT` trigger refuses `Σ + new.amount_minor > payout.amount_minor`
  (`reversal_exceeds_transfer`), refuses `payout.status not in ('paid','reversed')`, refuses
  `new.stripe_transfer_ref <> payout.stripe_transfer_ref` (never adopts a caller's pair), and refuses
  UPDATE/DELETE (append-only — with the one exception in 4.4).

**What a partial reversal does to the org's obligation / the settlement header** — this is the load-bearing
question, and the answer is that a reversal has **two possible meanings** and the fact row must say which:

1. **Recovery** of an already-booked `kernel.organization_obligation` (G5 direction: "recovery source may be
   venue-scoped", the reversal is the platform pulling back what the org owes). The reversal fact carries
   `obligation_id`; the obligation's recovered amount is **derived** (`Σ payout_reversal.amount_minor where
   obligation_id = …`), and `resolve_organization_obligation(...,'recovered')` should require Σ = amount
   (today it asserts an off-platform payment with no amount — F-9). The settlement that was paid stays
   `paid`; the venue kept `amount_minor − Σ`; the org's outstanding debt falls by Σ. **One row, both sides,
   no double count.**
2. **Not a recovery** (`obligation_id IS NULL`: Stripe-initiated, an operator error, a dispute on the
   platform side). The venue is now **owed** Σ again and nothing in the schema can pay it: the settlement is
   `paid`, the payout is absorbing, `settlement:<id>` blocks a re-mint. The honest position is that such a
   row is a **platform liability to the venue** that must be surfaced (an `outstanding_to_venue` read =
   Σ of unlinked reversals) and discharged by an owner-designed re-mint (a NEW `kernel.payout` row, cause
   `'settlement'`, same `cause_ref`, `idempotency_key := 'reversal_remint:'||payout_id`, born
   `pending+held`, walking the full ladder) — **not designed here**; it is the mirror of J3's receivable and
   needs the same owner ruling.

What would be dishonest: writing `'reversed'` for a partial (asserts the whole transfer came back); writing
a `refund_void`/`chargeback` line for a reversal (mis-labels the cause and double-nets against the arms
that already net those — the exact 10h defect); mutating `amount_minor`; booking a second
`organization_obligation` for a reversal that recovered an existing one.

### 4.2 The ref-bearing failed payout — reconciliation verb (brief §16)

**Preconditions the executor already satisfies.** Stripe-observed facts already reach the edge for a
`submitted` payout in `reconcile` mode (index.ts:263-272, `GET /v1/transfers?transfer_group=payout_<id>`),
and `planReconcile` already derives adopt/reversed/mismatch from them. **They never reach a `failed` row**
because `claim_payouts_for_execution` selects `status='submitted'` only. So the verb needs its own claim.

Proposed shape (service_role only; **no human-callable variant** — a human path would accept typed
amounts, which is exactly what (d) forbids):

```
kernel.claim_failed_payouts_for_reconcile(p_limit int, p_lease_seconds int) → jsonb
  -- status='failed' AND stripe_transfer_ref IS NOT NULL AND cause='settlement' AND payee_kind='organization'
  -- AND no 'payout.reconcile_claim' audit inside the lease; writes that audit row; returns payout_id + stored ref + transfer_group

kernel.reconcile_payout_transfer(
  p_payout_id uuid, p_stripe_transfer_ref text, p_observed jsonb, p_command_key text) → jsonb
  -- p_observed := {found bool, id, amount, currency, destination, transfer_group,
  --               reversed, amount_reversed, reversals:[{id trr_, amount}], group_count int}
```

Derivation, first failing predicate wins, every branch audited (`payout.reconcile`):

| observed | outcome | writes |
|---|---|---|
| `p_stripe_transfer_ref <> stored ref` or stored ref malformed (F-7) | `ref_mismatch` / `ref_unresolvable` refusal | audit only — **never adopts the caller's pair** |
| `found=false` (404) | **stays `failed`**, audit `transfer_unresolvable`, notify `payout_on_hold`-class page | no status write. A terminal row cannot be held (085:790); the "operator hold" is the audit + page. See Q3 for the only recovery (a 404 twice ≥24 h apart AND an empty transfer_group ⇒ owner-approved rearm that preserves the ref in audit). |
| `amount <> amount_minor` or `currency <> currency` or `destination <> destination_ref` | `amount_ledger_mismatch` / `destination_mismatch`, stays `failed` | audit + page |
| `group_count > 1` | `reconcile_ambiguous`, stays `failed` | audit + page |
| clean (`amount_reversed = 0`) | `failed → paid` | **a new edge.** `mark_payout_transfer_state` refuses `failed→paid` (2.2), and routing through `submitted` is impossible (claim needs `ref IS NULL`, 10n refuses `transfer_already_recorded`). The verb must write `paid` itself and `perform venue.on_payout_settled` (definer→definer; the grant is nobody's, 087:1447). Honest only if this verb is the SOLE writer of that edge, service_role, and the amount/destination equalities above are mandatory. |
| `amount_reversed = amount` | `failed → paid`, then reversal facts for each `reversals[]` (`trr_` unique), Σ = amount ⇒ `paid → reversed` via the existing edge | header ends `paid` (same truth as 2.1) |
| `0 < amount_reversed < amount` | `failed → paid` + reversal facts, stays `paid` | as 4.1 |

(c) Idempotency: replay of `paid` = `noop_replay` (085:1694-1697); reversal facts dedupe on `trr_`;
unresolvable/mismatch outcomes dedupe on `(payout_id, command_key)` in the audit. (d) No arbitrary
amounts: the only amount the verb *stores* is a reversal amount, capped by the Σ-guard and taken from
Stripe's `reversals[]`, never from `p_observed.amount` (which is compared, not stored). "Canceled" is not
a Transfer state (Transfers have no cancel; Payouts do — J2 §4, unverified beyond docs), so it is folded
into `transfer_unresolvable`.

`reversals[]` on the Transfer object is a paginated list (`has_more`); the edge must page
`GET /v1/transfers/{id}/reversals` before calling the verb, or the Σ will be short. **Unverified live.**

### 4.3 `transfer.reversed` → which payout (brief §5)

* **Routing is possible because a Transfer carries its own metadata** (unlike a Dispute). Native transfers
  are minted with `metadata.source='payout-execute'`, `metadata.payout_id`, `metadata.settlement_id`,
  `metadata.org_id` and `transfer_group='payout_<uuid>'` (executor.ts:768-777); legacy transfers carry
  `metadata.transfer_id|payment_id|seller_id` and **no** `transfer_group` (payouts.ts:139-144). Rule,
  mirroring `resolveRail`'s fail-closed posture: `source==='payout-execute' && isUuid(payout_id)` ⇒ native;
  `metadata.transfer_id` present and no `payout_id` ⇒ legacy; both/neither ⇒ `unknown_rail`, `ack:false`,
  alert (native.ts:151-152). **Do not route by DB lookup on the ref** — F-6 makes it ambiguous.
* **Lookup**: by `metadata.payout_id`, then assert `payout.stripe_transfer_ref = tr.id` when the ref is
  stored. Add the missing invariant: `create unique index payout_stripe_transfer_ref_uq on kernel.payout
  (stripe_transfer_ref) where stripe_transfer_ref is not null` (096; safe on an empty rail; also closes F-6).
* **Idempotency**: `trr_` UNIQUE on the facts table + the event-id dedupe already in `markProcessed`.
* **The three states the event can find:**
  * `paid` (ref stored) → `record_payout_reversal` per `reversals[]` entry (4.1).
  * `submitted`, ref NULL (callback not yet written, or lost) → `hold_payout_transfer_reversed` (E-4) —
    but ALSO write the reversal fact keyed to the `tr_` so the executor's later adopt/hold decision and any
    human release have a keyed record (F-12), i.e. the facts table must allow `payout.stripe_transfer_ref
    IS NULL` when `tr_` = `metadata`-derived transfer for that payout (relax the equality guard to "stored
    ref is NULL or equal").
  * `failed` + ref → `reconcile_payout_transfer` (4.2) with the event's object as `p_observed`.
  * `pending+held` (`transfer_reversed*`) → noop (E-4 replay, 095:707-712).
* **Legacy** stays on `mark_transfer_reversed` (all-or-nothing; J2 §7.4 notes it also ignores partials —
  not this train's scope).

### 4.4 Case table (brief §17) — paid 10 000 (`P`, `tr_X`); org owes 6 000 (`O`, `settlement_shortfall`, booked by a later negative close, 094:753-776)

| Case | Rows under 4.1 | `P.status` | `O.status` | Header of `P`'s settlement | Double count? |
|---|---|---|---|---|---|
| Recovery reverses **6 000** | `payout_reversal{P, tr_X, trr_1, 6000, obligation_id=O}` | `paid` (Σ 6 000 < 10 000; venue keeps 4 000) | `recovered` (derived Σ = 6 000 ⇒ resolve, audited) | `paid` | No — one row serves both sides by reference. `org_outstanding_obligation_minor` → 0. |
| Recovery reverses **2 000** | `payout_reversal{…, trr_1, 2000, O}` | `paid` | `outstanding`, recovered_minor (derived) 2 000, residual 4 000 | `paid` | No. A later `trr_2 4000` completes it. Σ per obligation is trigger-capped at `O.amount_minor`. |
| Recovery **impossible** (`balance_insufficient`, J2 §4.1) | none on `P`; audit `org_obligation.recovery_attempt{stripe error}` | `paid` | `outstanding` | `paid` | No rows, no count. G5 §5.3: structurally unrecoverable residual; owner lever is reserve/maturity, not this train. |
| Reversal **after** `O` is already `recovered` (off-platform payment) | linking to a non-outstanding obligation is **refused** (`obligation_not_outstanding`); the reversal fact must then be recorded unlinked (case below) or not attempted | `paid` | `recovered` | `paid` | Refusal is what prevents recovering the same 6 000 twice. |
| Reversal of the **full 10 000 for a non-recovery reason** while `O` is outstanding | `payout_reversal{…, 10000, obligation_id NULL}` ⇒ Σ = amount ⇒ `mark_payout_transfer_state 'reversed'` | `reversed` | `outstanding` 6 000 (untouched: not a recovery) | `paid` (E-5) | No double count, but the ledger now says: org owes 6 000 AND platform owes the venue 10 000 (unlinked Σ). Net 4 000 to the venue — needs the owner's re-mint / netting ruling (4.1 §2, G5 §5.1-5.2: no default cross-venue netting). |
| Reversal (6 000) happened **before** the negative close booked `O` | at reversal time: fact with `obligation_id NULL`; at close: `O` booked 6 000 ⇒ the platform holds the 6 000 AND records a 6 000 debt | `paid` | `outstanding` → must become `recovered` by **linking** | `paid` | **Double count unless linked.** The only mutable field on the facts table is `obligation_id`, set-once NULL→value by a platform human on aal2 (`kernel.link_payout_reversal_to_obligation`), audited; the trigger refuses Σ linked > `O.amount_minor` and refuses linking to an obligation of another org. |

Everything in the table is derivable from three append-only sets (`payout`, `payout_reversal`,
`organization_obligation`) plus one nullable set-once foreign key; no stored balance anywhere.

### 4.5 What is NOT the smallest honest design (named, so it is not chosen by default)

* Widening `status` to `partially_reversed` — puts an amount-dependent state into a column with no amount.
* Auto-netting an unlinked reversal against a later payout of the same org — the cross-venue question G5 §5.1 says is the owner's.
* A human-callable `mark_payout_transfer_state('paid')` for the ref-bearing failed case — 095:232-239's "a service worker cannot self-authorize money" has a mirror: a human cannot assert a Stripe fact they did not observe.

---

## 5. Open questions for the orchestrator / owner

1. **Q1 (owner) — a reversal that is not a recovery: is the venue re-owed?** 4.1 §2 needs a ruling before the re-mint verb is designed; today the amount is destroyed (F-2). A5 says the venue's entitlement is face value.
2. **Q2 (owner) — does a recovery reversal get to touch the header?** Recommended no (header stays `paid`, the fact lives on the obligation). If the owner wants the header to reflect "net received", that is a projection, not a status.
3. **Q3 (owner) — the 404 case.** A stored ref Stripe does not know (F-7 makes it storable) can only be recovered by clearing a write-once column. Proposed gate: two `transfer_unresolvable` audits ≥ 24 h apart AND an empty `transfer_group` listing AND platform_admin on aal2 ⇒ `rearm_failed_payout` accepts it with the old ref preserved in `before`. Alternative: leave it stranded and require a manual Stripe-side transfer + `paid` sync. Not decided here.
4. **Q4 (orchestrator) — the failed→paid edge.** 4.2 requires one new legal edge written by one service_role verb from Stripe-observed facts. Is that acceptable under "no widened transition" (095:11-19), or must the design instead route a ref-bearing failed row through a new intermediate state? I recommend the single-writer edge; the alternative adds a status member.
5. **Q5 (orchestrator) — sequencing with investigators handling `charge.dispute.*`.** The unlined-reversal origin guard (F-8) and the linking verb (4.4 last row) touch 094's surface; whoever owns the dispute-webhook train should own the `origin existence` fix so 096 does not collide.
6. **Q6 (unverified, needs a live read, not a test)** — whether Stripe's own-initiative reversal (J2 §4.3) can hit a transfer with no `source_transaction`; the `reversals[]` pagination shape on the `transfer.reversed` event payload; whether the production webhook endpoint subscribes to `transfer.reversed` at all.
7. **Q7 (orchestrator) — F-10.** The probation disarm counting a reversed payout as "paid since the change" is a one-line predicate fix in a frozen slice (add `and p.status = 'paid'`); it belongs to whoever next re-creates 10k.

---

## Appendix A — fixture and probes (run as `postgres` on `snatchit_rehears_e`, after `000_helpers.sql`)

```sql
\set ON_ERROR_STOP off
BEGIN;
SELECT tap.seed_core();
CREATE TABLE IF NOT EXISTS tap.memo_ke (k text PRIMARY KEY, v text);
CREATE OR REPLACE FUNCTION tap._st(k text, v text) RETURNS void LANGUAGE sql SECURITY DEFINER AS $m$ INSERT INTO tap.memo_ke VALUES (k,v) ON CONFLICT (k) DO UPDATE SET v=excluded.v $m$;
CREATE OR REPLACE FUNCTION tap._fe(k text) RETURNS text LANGUAGE sql SECURITY DEFINER AS $m$ SELECT v FROM tap.memo_ke WHERE k=$1 $m$;
CREATE OR REPLACE FUNCTION tap._aal2() RETURNS void LANGUAGE plpgsql AS $f$ begin perform set_config('request.jwt.claims',
  (coalesce(current_setting('request.jwt.claims',true),'{}')::jsonb || '{"aal":"aal2"}'::jsonb)::text, true); end $f$;
CREATE OR REPLACE FUNCTION tap._try(p_sql text) RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $f$
DECLARE v text; BEGIN EXECUTE p_sql INTO v; RETURN 'OK: ' || coalesce(v,'<null>');
EXCEPTION WHEN others THEN RETURN 'ERR[' || sqlstate || ']: ' || sqlerrm; END $f$;
CREATE OR REPLACE FUNCTION tap._po(p_settlement uuid) RETURNS kernel.payout LANGUAGE sql SECURITY DEFINER SET search_path='' AS
$m$ SELECT p FROM kernel.payout p WHERE p.cause='settlement' AND p.cause_ref = p_settlement ORDER BY p.created_at LIMIT 1 $m$;
CREATE OR REPLACE FUNCTION tap._porow(p_payout uuid) RETURNS text LANGUAGE sql SECURITY DEFINER SET search_path='' AS
$m$ SELECT format('status=%s hold=%s reason=%s held_by=%s ref=%s amount=%s dest=%s', p.status, p.hold_state, coalesce(p.hold_reason_code,'-'),
   coalesce(p.held_by::text,'-'), coalesce(p.stripe_transfer_ref,'-'), p.amount_minor, coalesce(p.destination_ref,'-')) FROM kernel.payout p WHERE p.payout_id = p_payout $m$;
CREATE OR REPLACE FUNCTION tap._srow(p_s uuid) RETURNS text LANGUAGE sql SECURITY DEFINER SET search_path='' AS
$m$ SELECT format('settlement status=%s gross=%s fees=%s refunds=%s net=%s', s.status, s.gross_minor, s.fees_minor, s.refunds_minor, s.net_minor) FROM venue.settlement s WHERE s.settlement_id = p_s $m$;
CREATE OR REPLACE FUNCTION tap._ctx(p_payout uuid) RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path='' AS $m$ SELECT kernel.get_payout_execution_context(p_payout) $m$;
CREATE OR REPLACE FUNCTION tap._claim() RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path='' AS $m$ SELECT kernel.claim_payouts_for_execution(50, 900) $m$;
CREATE OR REPLACE FUNCTION tap._sess(p_event uuid, p_label text, p_end timestamptz) RETURNS uuid LANGUAGE sql SECURITY DEFINER SET search_path='' AS
$m$ INSERT INTO catalog.event_session (event_id, session_label, starts_at, ends_at, status) VALUES (p_event, p_label, p_end - interval '3 hours', p_end, 'completed') RETURNING session_id $m$;
CREATE OR REPLACE FUNCTION tap._cov(p_org uuid, p_session uuid, p_total int, p_tag text) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $m$
DECLARE v_pay uuid; v_order uuid; BEGIN
  INSERT INTO public.payments (buyer_id, amount, buyer_fee, total, status, mode, stripe_payment_intent_id) VALUES (tap.buyer(), p_total, 0, p_total, 'succeeded', 'native_primary', p_tag) RETURNING id INTO v_pay;
  INSERT INTO venue."order" (buyer_id, event_session_id, org_id, status, source, total_minor, command_idempotency_key) VALUES (tap.buyer(), p_session, p_org, 'pending', 'web', p_total, p_tag || '-ord') RETURNING order_id INTO v_order;
  INSERT INTO kernel.payment_native (payment_id, order_id, amount_minor, currency) VALUES (v_pay, v_order, p_total, 'USD');
  PERFORM tap._st(p_tag || '-pay', v_pay::text); RETURN v_order; END $m$;
CREATE OR REPLACE FUNCTION tap._settle(p_org uuid, p_venue uuid, p_lines jsonb, p_key text) RETURNS uuid LANGUAGE plpgsql SET search_path='' AS $m$
DECLARE v_s uuid; v_l jsonb; BEGIN
  PERFORM tap.login(tap.seller()); v_s := (venue.open_settlement(p_org, p_venue, NULL, '{}'::jsonb, p_key) ->> 'settlement_id')::uuid; PERFORM tap.logout();
  FOR v_l IN SELECT jsonb_array_elements(p_lines) LOOP
    INSERT INTO venue.settlement_line (settlement_id, cause, cause_ref, amount_minor) VALUES (v_s, v_l ->> 'cause', (v_l ->> 'ref')::uuid, (v_l ->> 'amt')::integer);
  END LOOP;
  PERFORM tap.login(tap.admin_user()); PERFORM kernel.close_settlement(v_s, p_key || '-c'); PERFORM tap.logout(); RETURN v_s; END $m$;
CREATE OR REPLACE FUNCTION tap._request(p_org uuid, p_s uuid, p_key text) RETURNS text LANGUAGE plpgsql AS $m$
DECLARE v text; BEGIN PERFORM tap.login(tap.other_user()); PERFORM tap._aal2();
  v := tap._try(format('SELECT kernel.request_org_payout(%L,%L,%L)::text', p_org, p_s, p_key)); PERFORM tap.logout(); RETURN v; END $m$;
CREATE OR REPLACE FUNCTION tap._as_admin(p_sql text) RETURNS text LANGUAGE plpgsql AS $m$
DECLARE v text; BEGIN PERFORM tap.login(tap.admin_user()); PERFORM tap._aal2(); v := tap._try(p_sql); PERFORM tap.logout(); RETURN v; END $m$;

-- org1 → venue1 → event1 → session ended 40 days ago; other_user = matured org_finance; destination bound directly
SELECT tap.login(tap.seller()); SELECT tap._st('org1', (kernel.create_organization('KE Co','KE Co','ke-o1') ->> 'org_id')); SELECT tap.logout();
UPDATE kernel.organization SET status='approved' WHERE org_id = tap._fe('org1')::uuid;
SELECT tap.login(tap.seller()); SELECT tap._st('venue1', (catalog.create_venue(tap._fe('org1')::uuid,'KE Hall','wynwood',NULL,'ke-v1') ->> 'venue_id')); SELECT tap.logout();
SELECT tap.login(tap.admin_user()); SELECT catalog.approve_venue(tap._fe('venue1')::uuid,'approved','miami_gate','ke-a1'); SELECT tap.logout();
SELECT tap.login(tap.seller()); SELECT tap._st('event1', (catalog.create_event(tap._fe('venue1')::uuid,'KE Night',
  jsonb_build_object('starts_at',(now()-interval '40 days')::text,'ends_at',(now()-interval '40 days' + interval '4 hours')::text),'ke-e1') ->> 'event_id')); SELECT tap.logout();
SELECT tap._st('sessOld', tap._sess(tap._fe('event1')::uuid, 'old', now() - interval '40 days')::text);
INSERT INTO kernel.org_member (org_id, identity_id, role, granted_by, granted_at) VALUES (tap._fe('org1')::uuid, tap.other_user(), 'org_finance', tap.seller(), now() - interval '40 days');
UPDATE kernel.org_member SET granted_at = now() - interval '40 days' WHERE org_id = tap._fe('org1')::uuid AND identity_id = tap.seller();
UPDATE kernel.organization SET stripe_connect_account_ref = 'acct_KE1', connect_transfers_active = true WHERE org_id = tap._fe('org1')::uuid;
INSERT INTO catalog.platform_config (key, version, value, visibility) SELECT 'authn.money_role_maturity_hours', coalesce(max(version),0)+1, '24'::jsonb, 'restricted' FROM catalog.platform_config WHERE key='authn.money_role_maturity_hours';
INSERT INTO catalog.platform_config (key, version, value, visibility) SELECT 'payout.settlement_maturity_interval', coalesce(max(version),0)+1, '"7 days"'::jsonb, 'restricted' FROM catalog.platform_config WHERE key='payout.settlement_maturity_interval';
INSERT INTO catalog.platform_config (key, version, value, visibility) SELECT 'payout.dual_control_min_minor', coalesce(max(version),0)+1, '100000000'::jsonb, 'restricted' FROM catalog.platform_config WHERE key='payout.dual_control_min_minor';

-- S1 full reversal after paid
SELECT tap._st('ordA', tap._cov(tap._fe('org1')::uuid, tap._fe('sessOld')::uuid, 10000, 'pi_ke_a')::text);
SELECT tap._st('s1', tap._settle(tap._fe('org1')::uuid, tap._fe('venue1')::uuid, jsonb_build_array(jsonb_build_object('cause','primary_sale','ref',tap._fe('ordA'),'amt',10000)), 'ke-s1')::text);
SELECT tap._st('p1', (tap._po(tap._fe('s1')::uuid)).payout_id::text);
SELECT tap._request(tap._fe('org1')::uuid, tap._fe('s1')::uuid, 'ke-r1');
SELECT tap._try(format('SELECT kernel.mark_payout_transfer_state(%L,''paid'',''tr_KE1'',NULL,''ke-m1'')::text', tap._fe('p1')));
SELECT tap._try(format('SELECT kernel.mark_payout_transfer_state(%L,''reversed'',NULL,NULL,''ke-m2'')::text', tap._fe('p1')));
SELECT tap._try(format('SELECT kernel.mark_payout_transfer_state(%L,''reversed'',''tr_OTHER'',NULL,''ke-m3'')::text', tap._fe('p1')));
SELECT tap._try(format('SELECT kernel.mark_payout_transfer_state(%L,''reversed'',''trr_KE1'',NULL,''ke-m3b'')::text', tap._fe('p1')));
SELECT tap._try(format('SELECT kernel.hold_payout_transfer_reversed(%L,''tr_KE1'',10000,6000,''{}''::jsonb,''ke-h1'')::text', tap._fe('p1')));
SELECT tap._try(format('SELECT kernel.mark_payout_transfer_state(%L,''reversed'',''tr_KE1'',NULL,''ke-m4'')::text', tap._fe('p1')));
SELECT tap._porow(tap._fe('p1')::uuid); SELECT tap._srow(tap._fe('s1')::uuid);
-- … then the 1j/1k/1l probes exactly as listed in §2.1 (paid/failed/rearm/request/hold/release/ctx/claim/re-close; obligation count; unlined_reversal with origin=p1)
-- S2 ref-bearing failed: as S1 through request, then
--   mark_payout_transfer_state(p2,'failed','tr_KE2','transfer_failed') and the twelve exits listed in §2.2
-- S3: mark_payout_transfer_state(p3,'failed','not a transfer id','weird')
-- S4: mark_payout_transfer_state(p4,'paid','tr_KE1') ; SELECT count(*) FROM kernel.payout WHERE stripe_transfer_ref='tr_KE1'
-- S5: paid tr_KE5; hold_payout_transfer_reversed(p5,'tr_KE5',10000,6000); UPDATE kernel.payout SET amount_minor=4000 …;
--     tap._settle(org1, venue1, [{cause:'settlement', ref:p5, amt:-6000}], 'ke-s5b'); SELECT * FROM kernel.organization_obligation
-- S6: request p6; hold_payout_transfer_reversed(p6,'tr_KE6',8000,8000); release_payout(p6); request again; tap._ctx(p6); tap._claim()
COMMIT;
```
