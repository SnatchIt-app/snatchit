# H5 — Promoter economics, proved by execution

**Scope.** Does the ratified `COMMISSION_FUNDING_SOURCE` ruling (Option B) actually hold once 093's
primary-revenue seam gives the commission something to be deducted from? And does anything in this
train pay a promoter?

**Freshness.** The runtime numbers were produced against `093_primary_ticketing.sql` as of HEAD
`7d45cbf` + this train's working tree. Slice 10 grew during the run (a sibling agent appended 10i,
`kernel.claim_refunds_for_execution`, and re-anchored `deletion.post_event_hold_hours`); the additions
are purely additive and 10a-10h are untouched, and every source-level negative in §5 was **re-run
against the current file**, not the one loaded at the start.

**Method.** Every number below was produced by running the real functions against a full
`supabase/migrations` replay (`scripts/rehearsal_reset.sh snatchit_rehears_promo`, 108/108 applied,
GATE-2 `tables=27 functions=70 policies=37 triggers=24` — the CI baseline). Nothing was mocked; no
production object was touched; no migration byte was changed. The generated
`supabase/migrations/093_primary_ticketing.sql` was used as-is, and PART 10 of it is byte-identical to
`docs/phase2/_impl/093_parts/10_money_settlement.sql`.

**Verdict, up front.**

1. Option B holds mechanically. The commission is a negative settlement line that lands in the FEES
   bucket, and the org payout is minted at exactly `gross − fees − refunds`. The venue is never paid
   the commission's dollars. **Proved by execution, twice, with hand-checked arithmetic.**
2. **Ruling A4 holds. `count(*) from kernel.payout where cause='promoter_commission' and hold_state <> 'held'` = 0**
   after both chains, three refund cycles, a chargeback, an event cancellation, a re-close, and a
   DBA-level re-open-and-re-close. Slice 10 contains zero `update kernel.payout`.
3. **The unresolved item is not funding — it is REVERSAL.** A commission funded into a closed
   settlement can never be reduced, and revenue reversed after that close produces no offsetting
   obligation anywhere. It is contained today only because nothing pays a promoter at all. **This
   needs an owner ruling before the hold is ever released.** (§6, severity HIGH-CONTAINED.)

---

## 1. What the code actually does (the three facts everything else rests on)

- **Credit.** `kernel.settlement_primary_lines` (093/10b, new) emits `+order.total_minor` per paid
  order — face value, no platform fee and no Stripe cost subtracted (ruling A5).
- **Debit.** `kernel.settlement_commission_lines` (090:1511, body replaced by 093/10e) calls
  `kernel.pay_promoter_commission` (090:1401), which mints the promoter's `kernel.payout` row
  **born `held` / `unfunded_settlement`**, and returns the line as `−payable`.
- **Waterfall.** `kernel.close_settlement` (093/10d) derives
  `gross = Σ(+, non-refund cause)`, `fees = −Σ(−, non-refund cause)`,
  `refunds = −Σ(refund/chargeback cause)`, `net = gross − fees − refunds`, and mints the org payout at
  `net` **only if `net > 0`**. A commission is a negative, non-refund line, so it lands in **FEES** and
  is subtracted **before** the org payout exists.

`net_minor = gross_minor − fees_minor − refunds_minor` is not a convention; it is a table CHECK:

```
settlement_waterfall_ck  CHECK (status = 'open' OR (… AND net_minor = ((gross_minor - fees_minor) - refunds_minor)))
```

---

## 2. CHAIN 1 — face value → gross → commission funded → distributable reduced → refund before payout → obligations adjust → venue payout

Event A, one session, aged so it has ended 10 days ago.
`payout.settlement_maturity_interval = "7 days"`.

| order | qty × unit | face | promoter | refund |
|---|---|---|---|---|
| oA1 | 2 × 5000 | 10 000 | code `HFIVEP`, 1000 bps | — |
| oA2 | 1 × 5000 | 5 000 | none | full 5 000, `succeeded` **before** the close |

`venue.attribution` for oA1: `commission_kind=bps`, `commission_bps_applied=1000`,
`basis_minor=10000`, `credited_amount_minor=1000`.

### Settlement lines actually written (S1 = `5dfc13ef`)

```
cause                | amount_minor | cause_ref
---------------------+--------------+-----------------------------
primary_sale         |       10000  | oA1
primary_sale         |        5000  | oA2
promoter_commission  |       -1000  | attribution(oA1)
refund_void          |       -5000  | refund(oA2)
```

### Waterfall (read back from `venue.settlement`)

```
status  gross  fees  refunds   net   gross-fees-refunds
closed  15000  1000     5000  9000                 9000
```

**Hand check.** gross 15 000 = 10 000 (oA1 face) + 5 000 (oA2 face — a refunded order still emits its
credit; the refund is a separate debit). fees 1 000 = the single commission debit
`floor(10 000 × 1000 / 10 000) = 1000`. refunds 5 000 = the settled refund, capped at oA2's face.
net = 15 000 − 1 000 − 5 000 = **9 000**. ✓

### Every `kernel.payout` row after the close

```
cause                | payee_kind   | amount | status  | hold_state | hold_reason_code    | held_by
---------------------+--------------+--------+---------+------------+---------------------+--------
promoter_commission  | identity     |   1000 | pending | held       | unfunded_settlement | NULL
settlement           | organization |   9000 | pending | none       | NULL                | NULL
```

The close returned `payout_hold: null` — all seven G2 maturity predicates passed (policy set, covered
set resolvable, nothing cancelled, anchor known, anchor + 7d elapsed, no refund in flight, no dispute
open), so the venue's money is genuinely releasable. The promoter's is not, and never was.

**Conservation.** venue 9 000 + commission 1 000 = **10 000** = gross 15 000 − refunds 5 000. Exact.

---

## 3. CHAIN 2 — face value → commission funded → event completes → venue payout → later chargeback

Event B. oB1 = 2 × 4 000 = **8 000 face**, code `HFIVEP` → commission
`floor(8 000 × 1000/10 000) = 800`. The buyer's card was charged **8 800** (8 000 face + 800
buyer-side service fee). Session aged 9 days into the past.

### S2 (`6b048c95`) — the event completes and the venue is paid

```
lines:  primary_sale +8000 (oB1) | promoter_commission -800 (attribution(oB1))
gross 8000  fees 800  refunds 0  net 7200        8000 - 800 - 0 = 7200  ✓
payout_hold: null
```

```
promoter_commission | identity     |  800 | pending | held | unfunded_settlement
settlement          | organization | 7200 | pending | none |
```

**This is the temptation case in its purest form** (§4): gross 8 000 would more than cover the venue,
and the commission was already funded. The venue payout is **7 200, not 8 000**.

### The chargeback

`kernel.record_dispute_native('dp_h5_b1', …, 8800, 'usd', 'fraudulent', 'needs_response', …)`.
Its payout leg fires only while the dispute is open and only for payouts whose `cause_ref` is a
settlement carrying a line for the disputed order:

```
settlement          | 7200 | pending | held | dispute              <- frozen
promoter_commission |  800 | pending | held | unfunded_settlement  <- untouched
```

The commission payout is **not reachable** by that leg — its `cause_ref` is an attribution id, never a
settlement id (this is E-132, confirmed live: `commission_payouts_with_dispute_hold = 0`).

Then `mark_dispute_state('dp_h5_b1','lost')`, and the next close over the same event:

### S3 (`b8518920`) — the chargeback books

```
lines:  chargeback -8000 (dispute)
gross 0  fees 0  refunds 8000  net -8000        0 - 0 - 8000 = -8000  ✓
payout_ids: []
```

**Hand check on the cap.** The dispute was **8 800** but the line is **−8 000**: 093/10h caps the
chargeback at the order's face value less its senior refund exposure
(`least(disputed, face − refund_exposure − prior_cb)` = `least(8800, 8000 − 0 − 0)`). The 800
buyer-side service fee stays with the platform, which is ruling A5. Without the 093 fix this line
would have been −8 800 and the venue would have been charged Snatch It's own revenue.

**End state of chain 2.** Face credited 8 000, charged back 8 000 ⇒ **surviving revenue for oB1 = 0**.
The venue payout of 7 200 stands (held, `dispute`). The promoter's 800 stands (held,
`unfunded_settlement`). `net = −8 000` mints nothing and **creates no receivable — this schema has no
carry-forward object.** That is the exposure, and it is real; it is only inert because both payouts
happen to be frozen.

---

## 4. The property that matters most: the venue cannot consume the promoter's dollars

**Claim.** For every settlement, `venue payout + Σ commission payouts ≤ gross − refunds`, with
equality when commission is the only fee — and the two payouts are minted from a single arithmetic
derivation, so they cannot both draw the same dollar.

**Structural proof.** There is exactly one derivation and exactly one mint. `v_net` is computed from
the lines this settlement holds and the org payout is inserted at `v_net::integer`. The commission
line is one of the lines summed into `v_fees`. There is no second read of gross, no branch that pays
the venue anything other than `v_net`, and `request_org_payout` can only ever select
`cause = 'settlement' and cause_ref = p_settlement_id` — it cannot re-derive an amount.

**Executed proof — every settlement created in this run:**

```
settlement   gross   fees  refunds     net  identity  venue_payout  payout==max(net,0)  commission_in_settlement
5dfc13ef     15000   1000     5000    9000    t             9000          t                       1000
6b048c95      8000    800        0    7200    t             7200          t                        800
b8518920         0      0     8000   -8000    t                0          t                          0
1899a895     30000   2000     5000   23000    t            23000          t                       2000
24b1005a         0      0    14000  -14000    t                0          t                          0
c567d891         0      0        0       0    t                0          t                          0
ec92882a     10000   1000        0    9000    t             9000          t                       1000
4f34b7f8         0      0    10000  -10000    t                0          t                          0
```

`identity` = `gross − fees − refunds = net` held on every row. `payout==max(net,0)` held on every row:
a positive net mints exactly the net, a negative net mints nothing.

**Money conservation across the line/payout pair:** 5 commission lines, 5 commission payouts,
`mismatched_commission_pairs = 0` — every line's debit equals its payout's credit to the minor unit.

### The attacks

**(a) Can a refund arriving between funding and payout make the sum exceed gross?**
No, and the distinction matters. *Within* a settlement it is arithmetically impossible: refunds are
subtracted in the same derivation (chain 1 — the refund and the commission both reduced the same net;
9 000 + 1 000 = 10 000 = 15 000 − 5 000). *After* the close it is a different failure: the debit lands
in a later settlement with no credit beside it, that settlement nets negative, **no payout is minted
and no receivable is created**. The sum of payouts never exceeds gross; it comes to exceed *surviving
revenue*. Executed (SC2 = `24b1005a`): oC1 fully refunded post-close and oC3 partly refunded post-close
produced `refund_void −10000` and `−4000`, `net = −14 000`, `payout_ids: []`.

The G2 maturity gate is the only thing standing between this and a real loss, and it is a
**pre-close** gate: it holds the venue payout while a refund is in flight *at close time*, and until
`max(session.ends_at) + interval` has elapsed. It does not and cannot see a refund that begins later.

**(b) Can a partial refund leave the commission over-funded relative to surviving revenue?**
**Yes — if the partial refund lands after the funding close.** Executed:

```
order  status              face   refunded  charged_back  commission_funded  commission_on_surviving_revenue
oC1    refunded           10000     10000            0              1000                   0
oC3    partially_refunded 10000      4000            0              1000                 600
oD1    paid (cancelled ev)10000     10000            0              1000                   0
oB1    paid                8000         0         8000               800                   0
oA1    paid               10000         0            0              1000                1000
```

Only oA1 is correctly funded. oC3 is over-funded by 400; oC1, oD1 and oB1 are over-funded by their
entire commission. **3 800 of the 4 800 minor units of commission obligation standing in this
rehearsal are wholly or partly unearned.** None of it can move — every row is `held` — but the ledger
records the wrong number, and nothing reduces it.

**(c) Does the A4 `partially_refunded` exclusion still behave as the deliberate over-correction?**
**Yes, confirmed rather than assumed.** oC2 was partially refunded (5 000 of 10 000) *before* the
close. Result: `oC2_commission_lines = 0`, `oC2_commission_payouts = 0`, order status
`partially_refunded`. The promoter earned nothing on the 5 000 that survived — the over-correction
is real and it is permanent (an order never returns to `paid`). It is also the *only* correct
direction: an over-payment in an append-only ledger is unrecoverable, and §6 shows why.

**(d) Can a re-close double-fund?** No, four independent ways.
- `close_settlement` is forward-only: re-closing S(C1) returned `noop_replay`.
- A *fresh* settlement over the same event (SC3 = `c567d891`) wrote **0 lines**, `net 0`,
  `payout_ids: []` — the seams' `NOT EXISTS` dedupes saw the existing lines.
- The storage guarantee is global, not per-settlement:
  `attribution_one_commission_line_ever ON venue.settlement_line (cause_ref) WHERE cause='promoter_commission'`,
  plus 093/10c's `settlement_one_primary_sale_line_ever` and `settlement_one_refund_void_line_ever`.
  A hand-written second commission line for an already-lined attribution raised
  `23505 duplicate key value violates unique constraint "attribution_one_commission_line_ever"`.
- The payout is keyed `promoter_commission:<attribution_id>:<identity_id>` with
  `on conflict (idempotency_key) do nothing`.

**And even a DBA-level re-open cannot.** `venue.settlement.status` has no append-only trigger, so the
table owner can flip a closed header back to `open` (no client can: `authenticated` holds SELECT only,
`service_role` holds nothing on these tables, and `kernel.payout` is granted to `postgres` alone). I
did exactly that on SD1 and re-closed it: the waterfall re-derived **identically** (10000/1000/0/9000),
`payout_ids: []` (idempotency key collision), still one commission line for oD1, and
`a4_violations = 0`. The re-close also correctly reported the new `event_cancelled` predicate.

**(e) Can a cancelled event leave a funded commission against zero revenue?** **Yes.** Executed on
event D: SD1 closed at `gross 10000 / fees 1000 / net 9000`, commission 1 000 funded and held, venue
payout 9 000 minted (held `maturity_not_elapsed` only because event D was still in the future — had it
been in the past the payout would have been minted **unheld**). Then `catalog.cancel_event('weather')`
created a pending 10 000 refund; once settled, SD2 (`4f34b7f8`) booked `refund_void −10000`,
`net = −10 000`, no payout. `catalog.cancel_event` does not touch `kernel.payout` at all
(`cancel_event_touches_payout = f`). The commission payout still reads `1000 held/unfunded_settlement`
against zero surviving revenue.

---

## 5. Ruling A4, restated as a negative with evidence

**Assertion: nothing in this train releases, unholds, or advances a `promoter_commission` payout.**

**Runtime evidence** — after chain 1, chain 2, the chargeback, three refund cycles, an event
cancellation, two extra closes, a `noop_replay` re-close and a DBA re-open + re-close:

```
count(*) from kernel.payout where cause='promoter_commission' and hold_state <> 'held'                     = 0
count(*) from kernel.payout where cause='promoter_commission' and hold_reason_code <> 'unfunded_settlement' = 0
count(*) from kernel.payout where cause='promoter_commission' and held_by is not null                      = 0
count(*) from kernel.payout where cause='promoter_commission' and status <> 'pending'                      = 0
```

Final payout census: 5 × `promoter_commission` (4 800 minor, all `held/unfunded_settlement/pending`),
4 × `settlement` (2 unheld, 1 `dispute`, 1 `maturity_not_elapsed`).

**Source evidence, over the money slice** (`093_parts/10_money_settlement.sql`, 1 618 lines,
line-for-line identical to `093_primary_ticketing.sql:59-1676`). Re-run against the slice as it stands
after the refund-executor work (10i) landed in the same train, so these are current, not stale:

| probe | result |
|---|---|
| `update kernel.payout` | **0 occurrences** |
| `release_payout` | 2 occurrences, **both inside comments** (10d's rationale) |
| `hold_state` / `hold_reason_code` / `held_by` / `held_at`, non-comment | **2 lines, neither a write to a commission payout.** One is the column list of `close_settlement`'s own `insert into kernel.payout` for its `cause='settlement'`, `payee_kind='organization'` row. The other is a **READ** in `kernel.deletion_blockers_money` — `where p.payee_identity_id = p_identity and p.hold_state <> 'none'` — which makes a held commission payout **block** erasure of the promoter's identity (BP-6). That strengthens A4 rather than weakening it. |
| non-comment `promoter_commission` references | 6, all reads: the G2 covered-set resolution (2), the covered-cause whitelist, the seam's never-lined dedupe, the `pay_promoter_commission` call, the negated projection |

**Corpus evidence — the double lock survives everything above.**

- Only two functions ever INSERT a payout: `kernel.close_settlement` and
  `kernel.pay_promoter_commission`.
- Only five functions ever UPDATE one: `hold_payout`, `release_payout`, `mark_payout_transfer_state`,
  `request_org_payout`, `record_dispute_native`. **None mentions the `promoter_commission` cause.**
- `request_org_payout` — the sole writer of `status='submitted'` — selects
  `where cause = 'settlement' and cause_ref = p_settlement_id and status in ('pending','submitted')`.
  A commission payout is unreachable by it.
- `mark_payout_transfer_state` refuses `submitted` as a target state outright and refuses any payout
  with `hold_state <> 'none'`. Executed live against a commission payout:
  `ERROR: precondition_failed: payout_held`.
- `record_dispute_native`'s payout leg reaches payouts whose `cause_ref` is a settlement id; a
  commission payout's `cause_ref` is an attribution id. Confirmed: 0 commission payouts ever acquired
  a `dispute` hold. It can also only move a payout **to** `held`.

**So even a manual `kernel.release_payout` (platform_risk/platform_admin, Control-5) is not enough**:
it clears the hold to `none`, and the row then sits in `pending` with no contracted transition to
`submitted` and therefore none to `paid`. **No path in this train pays a promoter.** I did not exercise
the release verb in this run, precisely so the count above is a fact about the shipped code rather
than about a state I created.

---

## 6. Refund / payout interaction — the open question, stated plainly

**What should happen to a funded commission when its underlying revenue is refunded after the
commission line is already inside a CLOSED settlement?**

**Is there a mechanism today? No. Not one, and not by accident — the ledger is built to make it
impossible:**

- `venue.settlement_line` is append-only (`tg_settlement_line_append_only`). Executed:
  `UPDATE` → `append_only: settlement_line is immutable — UPDATE is not permitted`;
  `DELETE` → the same. The line cannot be amended.
- A *compensating* commission line is **unstorable**: `attribution_one_commission_line_ever` is a
  global unique index on `cause_ref`, so a second line under that cause raises `23505`. Executed.
- A closed header's money columns are write-once, and `close_settlement` is forward-only
  (`noop_replay`).
- `kernel.payout` has **no reduce, void, or cancel verb**. The five UPDATE sites change status,
  hold state and transfer refs; not one changes `amount_minor`.
- There is **no carry-forward / receivable object anywhere in the schema**. A negative net is simply a
  settlement that mints nothing.

**So the only surviving lever is the hold itself** — and that is exactly why the exposure is contained
rather than realised. The commission payout stays `held`/`unfunded_settlement` forever, and nothing
automated will ever release it.

**Size of the exposure.** Per attribution it is bounded by the commission amount itself — the promoter
cannot be over-funded by more than what was funded. Aggregate exposure =
`Σ commission_payout − Σ commission on revenue surviving today`, over every attribution whose order was
reversed after its funding close. In this rehearsal that is **3 800 of 4 800 minor units (79%)** across
four of five funded attributions, from four distinct reversal shapes (post-close full refund, post-close
partial refund, post-payout chargeback, post-close event cancellation). That ratio is an artefact of a
deliberately adversarial fixture, not a forecast — but the *shapes* are all ordinary, and three of the
four (a buyer refund after the event, a chargeback, a cancelled show) are the normal life of a ticketing
business. **The exposure is HIGH in principle and CONTAINED in practice, and the containment is a single
boolean: nobody has released a commission hold.**

### The owner question, in the form it needs to be asked

> **A promoter commission was funded out of a settlement that has since closed. The revenue under it
> was then reversed — refunded, charged back, or cancelled. The ledger cannot amend the line and
> cannot reduce the payout. Which is the policy?**
>
> **(A)** The hold is **never** released for an attribution whose order left `paid` after its funding
> close. (Cheapest: a release-time predicate, no new DDL, no money object. Consequence: a promoter
> loses the whole commission over a small partial refund — the same over-correction direction A4
> already chose.)
> **(B)** A **new settlement-line cause** (e.g. `commission_reversal`, which does *not* exist in
> `settlement_line_cause_ck` today) plus a matching negative-obligation object, so the reversal is a
> durable ledger fact rather than a suppressed release. (New enum member + new DDL on a frozen money
> table.)
> **(C)** A **promoter-level running balance** so an over-funded commission nets against the promoter's
> next one. (New table; this is rejected option (A) — carry-forward — applied to the promoter instead
> of the venue, and the owner rejected that shape once already.)
> **(D)** The platform absorbs it. (Explicitly rejected as option (D) in E-138.)

**093 must not choose.** Nothing in this train invents policy, and nothing needs to: A4 already holds
every commission, so the question is not blocking for this migration. **It is blocking for the first
release of a commission hold**, and that is the sentence that belongs in the activation matrix.

---

## 7. Secondary findings (recorded, not fixed)

1. **The G2 maturity gate is evaluated once, at close, and never re-evaluated.** SD1 minted its venue
   payout with `payout_hold: maturity_not_elapsed`; the event was cancelled *after*. Had the event
   already ended, the payout would have been minted **unheld** and the cancellation would not have
   held it — `catalog.cancel_event` does not touch `kernel.payout` at all. The gate protects the
   *close-time* view of the world only. Not a promoter-economics defect; adjacent to one.
2. **`record_dispute_native`'s payout freeze fires only on an OPEN dispute.** A dispute first observed
   as `lost` / `charge_refunded` (a late webhook, a replay after a gap) takes the `v_open = false`
   branch and holds **nothing** — the venue payout for that settlement stays requestable while the
   chargeback debit is still in the future. Chain 2 only saw the freeze because the fixture recorded
   `needs_response` first.
3. **A post-event full refund cannot use the routine path.** `kernel.refund_primary_order` refuses with
   `frozen: atom … is transfer-frozen — routine refund parked until the episode closes`
   (`kernel.is_transfer_frozen` → `catalog.effective_freeze_at`). The post-event path is
   `kernel.admin_refund` (platform_risk/platform_admin, explicit atom ids). Both write
   `kernel.refund`, so both reach the `refund_void` seam identically — but any runbook that assumes
   `refund_primary_order` works after an event is wrong.
4. **`venue.settlement.status` carries no append-only trigger**, so the table owner can re-open a
   closed header. Proved harmless for promoter money (§4d) — the re-close is idempotent in every
   observable — but it is an asymmetry with `settlement_line`, which *is* trigger-protected.
5. **The seam can still raise.** `kernel.pay_promoter_commission` raises
   `precondition_failed: terms_unresolvable` (090:1447) when a stored attribution violates its own
   kind/rate pairing. A raise inside a seam rolls back the entire close, which the 087 seam contract
   (087:204-207) says must not happen. Every other rejection is a `continue` into `held[]`. Unchanged
   by 093, unreachable in this run, still the single non-conforming arm. Previously flagged in
   `_rulings/D_promoter_settlement.md` §2.3; re-confirmed here.

---

## 8. Reproduction

```
scripts/rehearsal_reset.sh snatchit_rehears_promo
psql -d snatchit_rehears_promo -f supabase/tests/000_helpers.sql
# then the four scenario scripts, in order: fixture, chain 1, chain 2, attacks, final proofs
```

Fixture shape: org `H5 Co` → venue `H5 Hall` → events A/B/C/D, one session each; promoter P
(identity = `tap.other_user()`), org-wide, `bps 1000`, vanity code `HFIVEP`;
`payout.settlement_maturity_interval = "7 days"`. Fixture-only pokes, each isolated to a helper and
none of them a code path: `tap._agesession()` moves a session's `starts_at`/`ends_at` into the past so
the G2 anchor can elapse, and `tap._cfgh5()` writes `catalog.platform_config` as the owner rather than
through the dual-controlled `payout.%` RPC.
