# H4 — Settlement maturity & ledger integrity (adversarial verification)

Scope: verification only. **No code was changed.** No migration was edited, nothing was
assembled, nothing was deployed, no commit was made. Every claim marked *(exec)* was produced
by execution against a local rehearsal database (`snatchit_rehears_mat`, 108/108 migrations,
GATE-2 baseline matched, tables=27 functions=70 policies=37 triggers=24). All fixtures ran
inside `BEGIN … ROLLBACK`; the temporary `h4` helper schema was dropped and the database
re-reset afterwards, and the pgTAP suite was re-run on the clean database to prove no residue.

Source of truth read: `docs/phase2/_impl/093_parts/10_money_settlement.sql` (canonical slice),
assembled into `supabase/migrations/093_primary_ticketing.sql`.

---

## PART 1 — The predicate, as it actually exists

`kernel.close_settlement`, at the payout mint only, reached only when `v_net > 0`.
Verbatim from `10_money_settlement.sql:799-812`:

```sql
v_hold_reason := case
  when v_maturity is null                                    then 'unbounded_refund_exposure'
  when v_maturity < interval '0'                             then 'maturity_policy_invalid'
  when coalesce(v_unresolved, 1) > 0                         then 'covered_set_unresolvable'
  when coalesce(v_cancelled, true)                           then 'event_cancelled'
  when coalesce(v_sess_n, 0) = 0
    or coalesce(v_sess_no_end, 1) > 0
    or v_anchor is null                                      then 'maturity_instant_unknown'
  when now() < v_anchor + v_maturity                         then 'maturity_not_elapsed'
  when coalesce(v_refund_open, true)                         then 'refund_in_flight'
  when coalesce(v_dispute_open, true)                        then 'dispute_open'
  else null
end;
v_held := v_hold_reason is not null;
```

Operands are declared pre-set to the holding value
(`v_unresolved := 1; v_sess_n := 0; v_sess_no_end := 1; v_cancelled := true;
v_refund_open := true; v_dispute_open := true`), and the policy read is wrapped in
`begin … exception when others then v_maturity := null; end`. Eight distinct reason codes over
seven named predicates. The anchor is
`max(catalog.event_session.ends_at)` over the sessions resolved from **this settlement's own
money lines** (five causes), not from the header's scope.

### Confirmed by execution — the four questions asked

| Question | Result |
|---|---|
| Can a payout become executable merely because the config key is non-null? | **NO.** Key = `'7 days'`, event 10 days in the future → `maturity_not_elapsed`, payout `held`. *(exec)* |
| Does each predicate, broken in isolation, hold with its own code? | **YES**, all eight. Table below. *(exec)* |
| Does an all-satisfied control release? | **YES.** `hold=NONE net=10000 payouts=1[none/-/10000]`. *(exec)* |
| Does an uncomputable predicate hold rather than release? | **YES.** Unparseable interval (`"not-an-interval"`) and JSON `null` both collapse to `unbounded_refund_exposure`; `ends_at IS NULL` → `maturity_instant_unknown`; a line whose `cause_ref` resolves to nothing → `covered_set_unresolvable`; a settlement whose only line is a non-seam cause (`import`) → `maturity_instant_unknown`. *(exec)* |

Executed matrix (all *(exec)*, `payout.settlement_maturity_interval = '7 days'` unless stated):

| # | Input | Outcome |
|---|---|---|
| 1 | key unset | `unbounded_refund_exposure` |
| 2 | key = `"-3 days"` | `maturity_policy_invalid` |
| 3 | key = `"not-an-interval"` | `unbounded_refund_exposure` |
| 4 | key = JSON `null` | `unbounded_refund_exposure` |
| 5 | hand line, bogus `cause_ref` | `covered_set_unresolvable` (payout minted `held/15000`) |
| 6 | session `status='cancelled'` | `event_cancelled` |
| 7 | event `status='cancelled'` | `event_cancelled` |
| 8 | `ends_at IS NULL` | `maturity_instant_unknown` |
| 9 | only line is `cause='import'` | `maturity_instant_unknown` |
| 10 | event ended 3 days ago | `maturity_not_elapsed` |
| 11 | two sessions, day-2 in future | `maturity_not_elapsed` — **anchor is `max`**, verified |
| 12 | refund `pending` | `refund_in_flight` |
| 13 | refund `submitted` | `refund_in_flight` |
| 14 | refund `failed` | **RELEASED** (terminal, buyer not paid) |
| 15 | refund `succeeded` | net → 0; seam emitted the `refund_void` line; **no payout minted** |
| 16 | dispute `needs_response` | `dispute_open` |
| 17 | dispute `won` | **RELEASED** |
| 18 | all satisfied | **RELEASED**, `hold_state='none'` |

### The ten candidate predicates — enforced, and where

| # | Candidate | Verdict | Citation |
|---|---|---|---|
| 0 | *(Event not cancelled)* | **Enforced at close only** (`event_cancelled`). `catalog.cancel_event` does not touch `kernel.payout`, so a cancellation *after* the close leaves the payout unheld. **See D-1b.** | `:803`; *(exec)* |
| 1 | Event/session complete | **Enforced**, as the *time* facts `maturity_instant_unknown` + `maturity_not_elapsed`. Deliberately not `status='completed'`: nothing in 076-093 ever writes that value. | `10_money_settlement.sql:804-807` |
| 2 | Configured maturity policy | **Enforced**, two codes. `payout.%` prefix ⇒ dual control on every set. | `:800-801`; `077/078:1145-1147` |
| 3 | Settlement closed | **Enforced downstream**, and structurally at the mint: the `UPDATE … status='closed'` precedes the `INSERT`. | `kernel.request_org_payout`, `087:423-425` |
| 4 | No unresolved refund | **Enforced at close**, and more strongly at line generation — `kernel.settlement_primary_lines` defers an order with a non-terminal refund entirely (no credit, no debit). **Not re-evaluated after close** — see D-1. | `:808`; `10_money_settlement.sql:268-290` |
| 5 | No unresolved dispute | **Enforced at close** only, and the independent freeze in `kernel.record_dispute_native` has a blind spot: it fires only for an *open* dispute, so a dispute first observed `lost`/`charge_refunded` holds nothing. **See D-1c.** | `:809`; `088:804` |
| 6 | Payout destination valid | **Enforced, elsewhere.** `stripe_connect_account_ref is null` ⇒ `no_payout_destination`. Correctly not duplicated in the mint. | `087:447-449` |
| 7 | **Stripe transfers active** | **NOT ENFORCED ON ANY PAYOUT PATH.** *(exec)* `connect_transfers_active` is read by exactly three routines: `create_primary_checkout` (the *sale* gate), `get_org_connect_state` (read model), `sync_org_connect_state` (the writer). `kernel.request_org_payout` does not reference it, and 093 does not redefine that function (no `create or replace function kernel.request_org_payout` exists in 088-093). **See D-3.** | pg_proc sweep; `093_parts/30_connect_org.sql:651` |
| 8 | Obligation positive | **Enforced twice**: `if v_net > 0` guards the mint, and `payout_amount_minor_check CHECK (amount_minor > 0)` makes a negative payout unstorable. | `:present at mint`; `085` DDL |
| 9 | No prior payout | **Enforced twice**: a re-close of a non-`open` settlement returns `noop_replay` before reaching the mint, and `on conflict (idempotency_key) do nothing` on `'settlement:'||settlement_id`. *(exec)* — a forced reopen + re-close still minted exactly one payout and one line. | `10_money_settlement.sql:585-590`, `:828` |
| 10 | Promoter deduction funded | **Not a maturity predicate, and correctly not one** — the commission is a *negative settlement line*, so the org's `net_minor` is already net of it and the platform retains the money. The inverse is the real exposure: commission payouts are minted `held`/`unfunded_settlement` and **nothing releases them automatically** (see D-5). | `090:1487-1491` |

**Predicate that should exist and does not:** #7. Predicates #3, #4, #5 and the
cancellation predicate all exist but only as a **close-time snapshot** — see D-1, which is the
single most important finding in this document.

### Does `request_org_payout` re-evaluate any of the eight? No — but it honours the hold.

Asked because the honest fix may be to *move* a check rather than duplicate it. Answer, from the
frozen 087 body: `kernel.request_org_payout` evaluates settlement-closed, a pending payout
exists, SoD-1 setter exclusion, money-role grant maturity, AAL2 step-up, destination cool-down,
destination non-null, and destination probation. **None of the eight maturity predicates is
re-derived.** It does refuse a payout whose `hold_state <> 'none'` (`payout_held`, `087:463-465`),
so a hold set at close is respected — the hold is *durable*, it is simply never *recomputed*.
That asymmetry is the whole of D-1.

---

## PART 2 — G2's anchor and interval, attacked

**Verdict: KEEP `max(catalog.event_session.ends_at)` + `'7 days'`. No change proposed.**

| Scenario | Behaviour | Verdict |
|---|---|---|
| Normal nightclub event | anchor = session end; matures event+7d | correct |
| Ends after midnight | `ends_at` is `timestamptz`; anchor is that instant | correct |
| **Ends 4–6 AM** | see below | **correct, and no calendar bug exists** |
| Multi-day festival | anchor = `max(ends_at)` = last day *(exec, #11)* | correct |
| Multiple sessions, one matured | held until the last matures *(exec, #11)* | correct — deliberately conservative |
| Postponed | forward `ends_at` move is permitted and extends the hold *(exec)* | correct |
| Cancelled **before** close | `event_cancelled`, two independent predicates *(exec, #6/#7)* | correct |
| Cancelled **after** close | payout left `none`/`pending`, fully payable *(exec)* | **BROKEN — D-1b** |
| Delayed close | all predicates pass at close ⇒ unheld | correct: the risk period already elapsed |
| Refund pending on day 7 | `refund_in_flight` *(exec, #12/#13)* | correct |
| Dispute pending on day 7 | `dispute_open` *(exec, #16)* | correct |
| Payout executor offline | payout sits `pending`; nothing expires it | correct — **but no executor exists at all**, see D-4 |
| Disconnected venue account | `no_payout_destination` at request time | correct, orthogonal |
| Promoter commission funded | untouched by maturity; org net already reduced | correct |
| Post-release chargeback | **not covered by any interval** | PART 3 |
| Chargeback observed first as `lost` | freezes nothing *(exec)* | **BROKEN — D-1c** |

The three broken rows are all the same defect (the gate is a close-time snapshot), not three
faults of the anchor or the interval. **They do not change the PART 2 verdict** — a better anchor
or a longer interval would not fix any of them.

### The 4–6 AM case: it does not matter, and here is why

`close_settlement` performs **pure instant arithmetic**: `now() < v_anchor + v_maturity`, where
`v_anchor` is a `timestamptz`. The function body contains **no `date_trunc`, no `AT TIME ZONE`,
and no `::date`** *(exec — pg_proc regex sweep)*, and `catalog.event_session.home_region` is not
read by the gate. So "the day after the event" and "max(ends_at) + N days" cannot diverge here:
the rule never rounds to a calendar day in any timezone. A Saturday event ending Sunday 05:00
matures at 05:00 the following Sunday; a Saturday event ending 23:00 matures at 23:00 the
following Saturday. Both are exactly 7×24h after the last session ended, which is the intended
semantics.

The calendar question would only become live if the policy were later re-expressed as "the Nth
calendar day after the event" or rendered to an operator as a date. **Recommendation: do not
re-express it that way, and if a UI ever renders `matures_at` as a date, render it with the
instant.** The gate already publishes `matures_at` in `payout_hold_detail` and in the
`settlement.close` audit row, so the operator-facing value is the instant.

### One correction to G2: its residual-risk paragraph is now STALE

G2 PART 3 records "the anchor is mutable by the party being paid" and concludes "**Not closed
here, and deliberately**". **That is no longer true of this HEAD.** Slice 40
(`093_parts/40_config_privacy_freeze.sql:1596-1634`, assembled at `093:5350`) adds a backward
arm to `catalog.update_event_session` that refuses **any** earlier `ends_at` move — and also
refuses newly setting a previously-`NULL` `ends_at` to an already-elapsed instant — on a session
carrying economic weight (an issued atom, a paid/partially-refunded/refunded order, a door scan,
or any settlement on the event), fails closed if the probe itself raises, and demands a mandatory
`reason_code`. `platform_admin` is the only bypass.

Executed against the rehearsal DB as an `org_owner` of the paying org:

* backward move of `starts_at`+`ends_at` by 65 days → **refused**, `backward_schedule_move_frozen`
* `ends_at`-only shortening by 4 hours, no `reason_code` → **refused**, same code
* `ends_at`-only postponement of +30 days → **`ok`** (the safe direction: it lengthens the hold)

So the anchor can be moved *later* by the seller (extending its own hold) and cannot be moved
*earlier*. **G2's PART 3 residual and its PART 6 "Postponement — separately: close the mutability
hole (owner item — DDL)" row should be struck**; the hole is closed in code. That materially
strengthens the case for keeping this anchor.

### On the interval

G2 is right that no evidence derives a number, and honest that 7 days is a risk/commercial
trade. Nothing found here changes the inputs: the anchor is sound, the hold is recoverable, and
the key is dual-controlled and raiseable without a migration. **No change proposed — a different
number would be taste, not evidence.**

---

## PART 3 — Post-payout risk (the critical one)

### What is supported today, from code — verified by execution

Prior docs are **confirmed**: a post-release chargeback lands as a `chargeback` line in the org's
*next* settlement to close (`088:311-316`, `settlement_royalty_lines`, an arm that deliberately
carries no scope predicate), and closing the tail needs a receivable object that does not exist.

Executed, single-org replay:

```
S1  session ended 10d ago, clean            -> net=10000, payout minted UNHELD, marked paid
    settlement status -> 'paid'
    dispute_native('lost', 10000) arrives AFTER the money left
S2  next settlement (period-scoped)         -> lines: chargeback:-10000
                                               gross=0 fees=0 refunds=10000 net=-10000
                                               status='closed', payouts minted = 0
S3  a third settlement                      -> lines: NONE  (the chargeback is never re-offered)
```

The `-10000` is recorded **only** as `venue.settlement.net_minor` on a closed settlement that
mints nothing. It is consumed exactly once by the `not exists` dedupe and is thereafter
unreachable by any verb.

Second replay, measuring the loss when the org keeps trading:

```
org sells 10000, is PAID 10000, then loses a 10000 chargeback
S2  revenue 4000 + chargeback -10000  -> net=-6000, 0 payouts   (4000 withheld = partial recovery;
                                                                 the venue permanently loses it,
                                                                 its primary_sale line is consumed)
S3  revenue 9000, residual -6000 outstanding -> net=9000, 1 payout, hold=NONE  (NO offset)
ORG SOLD 23000 | ENTITLED 13000 | ACTUALLY PAID 19000 | PLATFORM LOSS 6000
```

### The six possible accounting outcomes, scored against the code

| Outcome | Implemented? | Evidence |
|---|---|---|
| Platform absorbs | **Yes — this is the default and the only terminal state.** | S2/S3 replay above |
| Negative venue carry | **No.** `net_minor` is derived from that settlement's own lines only; nothing reads a prior settlement's negative net. *(exec: S3 paid 9000 in full)* | `10d` derivation |
| Venue receivable | **No.** No table, no column, no verb. `kernel.payout` cannot represent it (`payout_amount_minor_check CHECK (amount_minor > 0)`). | schema |
| Reserve | **No.** No Stripe reserve plan, no reserve object. `kernel.reserve` is a stub (156). | 156 |
| Future payout offset | **Partially, and accidentally.** It works only when the chargeback happens to land in a settlement that also carries enough positive lines — recovery is then *complete for that settlement* but the excess is destroyed rather than carried. | S2 replay |
| Manual recovery | **Out of band only.** No RPC. Requires owner-level SQL. | — |

### Judgement for the owner

Two facts supplied by the promoter-economics pass, verified there and not re-derived here, that
bound this picture: the chargeback arm **caps at face value** (an 8800 charge on 8000 face books
`chargeback −8000`, leaving the platform's own 800 buyer fee with the platform — ruling A5 holding
on the debit side), and `request_org_payout` can only select `cause='settlement'`, so it can
neither re-derive an amount nor reach a commission payout. Also: post-event full refunds are
refused by `refund_primary_order` with `transfer-frozen`; the live path is `admin_refund`. Any
runbook that assumes otherwise is wrong.

**Residual R-H4-1 — post-payout debit has no home. Severity: HIGH (financial), but launch-acceptable
with explicit owner risk acceptance and one operational control.**

**D-1 changes the shape of this residual, and must be read into it.** The pre-payout window was
supposed to be the thing that kept the post-payout hole small: hold the money until the risk has
mostly passed, and the uncollectable tail is rare. D-1 shows the pre-payout window is not
actually defended after the close — a cancellation, a terminal-first chargeback, or a post-close
refund all leave the payout releasable. So the two findings are not independent: **D-1 is the
mechanism that feeds R-H4-1.** Every payout that leaves when it should not have is a debit that
then has no home. Fixing D-1 shrinks R-H4-1 to the genuinely irreducible case (a chargeback filed
weeks after a correctly-matured payout); leaving D-1 open makes R-H4-1 reachable by ordinary
operations rather than by a long-tail dispute.

Why it is not a launch blocker *today*:

1. **The loss is bounded by what has actually been paid out**, and at launch that is bounded by
   the 7-day hold plus manual release. A chargeback filed before the payout leaves is caught by
   `dispute_open` at close and by the `chargeback` debit in `net_minor`.
2. **No settlement money can leave the platform automatically at all.** *(exec)* No edge function
   calls `kernel.request_org_payout`, `kernel.mark_payout_transfer_state`, or
   `kernel.release_payout`; there is no payout executor deployed (see D-4). Every disbursement at
   launch is therefore a deliberate human act with the ledger in front of the operator.
3. **The debt is visible, even though it is not collectible.** A negative `net_minor` on a closed
   settlement is a queryable fact. That is enough for a manual invoice or offset while volume is
   small.

Why it must not stay this way:

* The exposure scales linearly with GMV and with automation. The moment a payout executor is
  deployed, condition 2 disappears and the platform is exposed to the full ~120-day post-event
  dispute window on every settled event.
* Recovery is *worse than absent*: the partial-offset path silently confiscates a venue's later
  revenue (S2 replay: the venue lost 4000 with no line item explaining it) while still destroying
  the remainder. That is a dispute with the venue waiting to happen.

**Recommended owner decision (no policy invented here — this is the choice set):**
accept R-H4-1 for initial launch on the strength of (2), and make the *preconditions* of
deploying a payout executor **both** of:

1. **D-1's execution-time re-evaluation** (this is the launch-blocking one of the two, because it
   is cheap, it is a code fix rather than a new object, and without it an automated executor will
   pay out cancelled events); and
2. either (a) a carry-forward/receivable object, or (b) a Stripe fixed reserve plan per event —
   for the irreducible post-payout tail.

Until (1) ships, `payout.settlement_maturity_interval` does not even reliably bound the
*pre-payout* window; until (2) ships it bounds nothing beyond it, exactly as G2 states.

---

## PART 4 — Ledger integrity attacks

| Attack | Result |
|---|---|
| Make a **cancelled** event's payout payable | **SUCCEEDED — D-1b** |
| Make a **lost chargeback** leave the payout payable | **SUCCEEDED — D-1c** |
| Make an obligation **disappear** after a Stripe failure | **SUCCEEDED — D-2 below** |
| Make an obligation **duplicate** after a retry | **Failed to break.** Re-close ⇒ `noop_replay`; forced reopen + re-close ⇒ 1 payout, 1 line (`on conflict` on `settlement_line_cause_uq` and on `idempotency_key`). *(exec)* |
| Corrupt the waterfall with a **negative** obligation | **Failed to break.** A `-5000` hand line closed to `gross=0 fees=5000 refunds=0 net=-5000`; `settlement_waterfall_ck` identity held; 0 payouts minted. *(exec)* |
| **Reopen** a settlement after payout | Possible only as table owner — see D-6. |
| **Race** a refund against a payout | **SUCCEEDED — D-1 below** |

### D-1 — The maturity gate is a snapshot, not an invariant. Severity: HIGH. **The headline finding.**

A predicate evaluated once, at close, is not a gate for anything that can change afterwards.
**Four independent state changes defeat it**, three of them verified here and the fourth supplied
by the promoter-economics pass. In every case the payout row is left `hold_state='none'`,
`status='pending'`, at full face value, and remains payable.

**D-1a — a refund succeeds after the close.** *(exec)* Close clean → payout `none`/`pending`/`10000`.
A **full refund succeeds** against the covered payment → the payout row is **unchanged**.
Advancing it to `paid` transfers full face value for a fully refunded order.
`kernel.request_org_payout` touches `kernel.refund` and `kernel.dispute_native` nowhere. The R-40
gate that would have covered this was deferred to 088 and never landed.
`kernel.settlement_primary_lines`'s order-deferral covers only refunds that exist *before* the
close — slice 10's own comment says so (`10_money_settlement.sql:300-305`). Not exotic: refunds
concentrate in exactly the days after an event, which is exactly the window the 7-day hold creates.

**D-1b — the event is cancelled after the close.** *(exec)*

```
close clean                 -> payout none/pending/10000
catalog.cancel_event(...)   -> 'ok'; session status -> 'cancelled'
payout AFTER cancellation   -> none/pending/10000     (UNCHANGED)
```

`catalog.cancel_event` does not reference `kernel.payout` at all *(exec — pg_proc scan)*. So the
`event_cancelled` predicate — the strongest one in the conjunction — **fires only if the
cancellation precedes the close.** A venue payout for an event that will not happen, and whose
orders are about to be refunded, stays payable.

**D-1c — a dispute is first observed already terminal.** *(exec)* `kernel.record_dispute_native`
computes `v_open := p_status not in ('won','lost','warning_closed','charge_refunded')`
(`088:804`) and runs its atom and payout freeze legs only when `v_open`. A dispute delivered
first as `lost` or `charge_refunded` — an ordinary Stripe delivery order, not a synthetic case —
freezes nothing:

```
LOST-first : status=ok linked=true payouts_held=0 -> payout stays none/pending
OPEN-first : (control)         payouts_held=1 -> payout becomes held/pending
```

The freeze is **inverted relative to risk**: it fires when the outcome is still unknown and does
not fire in the one case where the money is certainly gone. 088's own comment acknowledges
"at terminal via `record_dispute_native` with zero freeze legs" (`088:873`) — it was a known
shape, but pre-093 gross was structurally zero, so no org payout existed to freeze. 093 activates
the credit side and makes it live.

**D-1d — the org's Connect capability dies after the close.** The `connect_transfers_active`
column is never read on the payout path at all; see D-3. Same shape, different operand.

#### The correction is one change, not four

All four are the same defect: **state that the gate depends on is mutable after the gate runs,
and nothing re-runs it.** Patching cancellation, then terminal disputes, then refunds, then
capability, one at a time, will keep producing this class of bug — the next mutable operand
simply becomes the next hole.

**The smallest correct fix: extract the conjunction into one callable predicate and evaluate it
at both ends.** Concretely: lift the `case` at `10_money_settlement.sql:799-812` and its operand
CTE into `kernel.settlement_payout_maturity(p_settlement_id) returns jsonb` (STABLE,
definer-internal, same eight reason codes), have `close_settlement` call it to decide the mint's
`hold_state`, and call it again **immediately before the advance** in the payout request /
execution path, refusing with the same code. That is a *move plus one extra call site*, not a
duplicated predicate — so the two evaluations cannot drift, which is the property that matters.
The freeze-on-terminal gap (D-1c) then stops mattering for payouts, because re-evaluation reads
`dispute_native.status` directly rather than depending on a freeze leg having fired.

**NOT APPLIED, for two reasons.** (1) This is a verification pass. (2) `kernel.request_org_payout`
is **frozen 087 code** and 093 does not currently replace it, so adding a call site there is an
owner decision about a body-only replacement of a frozen migration.

> **COLLISION — coordinator action required.** The payout-executor agent is editing
> `docs/phase2/_impl/093_parts/10_money_settlement.sql` to add a `destination_ref` column and
> execution-time **destination** predicates. That is the *same seam* this fix needs: an
> execution-time re-evaluation point in the payout path. These must be one change, not two
> competing ones. Recommendation: the payout-executor agent owns the call site, and takes
> `kernel.settlement_payout_maturity(...)` plus the destination predicates and D-3's
> `connect_transfers_active` check into it as a single execution-time gate. Flagged, not resolved
> here.

### D-2 — A failed Stripe transfer permanently destroys the obligation. Severity: HIGH.

*(exec)*

```
mark_payout_transfer_state(payout,'failed',...)  -> status='failed'
  retry failed -> 'submitted'  : invalid_input (the verb takes paid|failed|reversed only)
  retry failed -> 'paid'       : precondition_failed: payout_state_backwards (failed -> paid)
  re-close the settlement      : noop_replay, payouts still = 1
```

`'failed'` is terminal with no outbound edge (`085:1698-1701` allows only
`submitted→paid|failed` and `paid→reversed`). `request_org_payout` selects only
`status in ('pending','submitted')`, so a failed payout is invisible to it
(`no pending payout for this settlement`). `close_settlement` is the sole minter of a
`cause='settlement'` payout and is forward-only. **A transient failure — a rate limit, a network
blip, a momentary capability lapse — permanently strands a real debt to the venue, with no
in-corpus recovery verb.** Recovery is superuser SQL.

Note D-2 and D-3 compound: the missing `connect_transfers_active` check makes the *most likely*
cause of a transfer failure reachable, and D-2 makes its consequence permanent.

### D-3 — `connect_transfers_active` gates the sale but not the payout. Severity: MEDIUM.

*(exec)* Proven by pg_proc sweep: no payout-path routine reads the column. An org that passed
the checkout gate and later lost its Stripe `transfers` capability (failed re-verification,
Stripe risk action) can still have a payout requested and advanced to `submitted`; the transfer
then fails at Stripe — and lands in D-2. The ledger asserts `submitted` for an obligation Stripe
will refuse. The column exists, is synced (`kernel.sync_org_connect_state`), and is audited
(`org.connect_ref.capability_lost`) — it simply is not consulted where the money moves.

### D-4 — There is no payout executor at all. Severity: INFORMATIONAL (and it is currently the main mitigation).

*(exec + grep)* No edge function references `request_org_payout`,
`mark_payout_transfer_state`, or `release_payout`. No `cron.job` names payout or settlement.
Every finding above that requires money to actually leave is therefore **latent**, not live.
This is load-bearing for the PART 3 judgement and should be stated to the owner as such: it is
the reason R-H4-1 is acceptable at launch, and it is what changes the moment an executor ships.

### D-5 — No hold ever self-clears. Severity: MEDIUM (operational).

*(exec)* `payout.settlement_maturity_interval` is read by **`kernel.close_settlement` only**
(`catalog.set_platform_config` mentions it in its control map, not as an evaluation). No cron
entry, no sweeper, and `kernel.release_payout` has no time-based arm and no programmatic caller.

Consequence: a settlement closed *before* the anchor + interval mints a payout held
`maturity_not_elapsed` **that stays held forever** until a `platform_risk`/`platform_admin`
manually calls `kernel.release_payout`. This is safe but it is not what "matures at" implies, and
`matures_at` is published to the operator as if it were self-executing. The same applies to
promoter commission payouts minted `held`/`unfunded_settlement` (`090:1487-1491`) — nothing pays
a promoter without a human release. **This needs an operator runbook entry, or a sweep, before
launch.**

### D-6 — Reopen after payout is possible for the table owner, and the re-close reports a hold it does not apply. Severity: LOW.

*(exec)* `venue.settlement` grants `SELECT` only to `authenticated`, nothing to `service_role`,
and carries no forward-only trigger (`tg_settlement_set_updated_at` only). So a `paid→open`
UPDATE succeeds **for the table owner / superuser** — a DBA repair path, not an application path.
The failure mode when it is used is silent: with the settlement reopened and the maturity policy
withdrawn, the re-close **returned `payout_hold = 'unbounded_refund_exposure'` while the payout
row remained `hold_state='none'`** (the mint's `on conflict (idempotency_key) do nothing` skips
the row). An operator reopening a settlement to re-impose a hold gets a report saying it worked
and a payout that is still releasable. Not exploitable; worth a warning in the runbook, or a
forward-only trigger on `venue.settlement.status`.

---

## Regression check

The pgTAP suite was run twice. The first run reported failures in
`141_phase2_identity_orgs_deletion.sql` and `158_refund_execution_claim.sql`; both were traced to
**this pass's own fixture rows** (a permanent `auth.users` + `kernel.platform_role` seed left
outside a transaction), not to any code defect. After dropping the `h4` schema, deleting the
seeds, and re-running `scripts/rehearsal_reset.sh`, those two files return
`TOTAL plan=237 ok=237 not_ok=0 ALL-PASS`, and the **full suite on the clean database returns**

```
TOTAL plan=3020 ok=3016 not_ok=4 FAILURES
  expected   060_payments_money.sql:  2 known local-only/TODO failure(s)
  expected   132_replay_parity.sql:   2 known local-only/TODO failure(s)
 RESULT: pgTAP suite matches the expected local baseline.
```

**No regression was introduced, and none was found in the maturity gate.** (Note: this is a
better baseline than G2's reported `plan=2960 ok=2792 not_ok=12` — the test deltas G2 listed as
consequences of the rename have since been repaired.)
