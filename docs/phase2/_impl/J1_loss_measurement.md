# J1 — Post-payout loss measurement (ACCOUNTING / LEDGER)

**Agent A · backend-only train · branch `feature/venue-native-and-product-v2` · HEAD `09e167f`**
**Method:** every number below comes from a real replay of migrations `000`–`093` on a local
rehearsal database (`scripts/rehearsal_reset.sh snatchit_rehears_loss`, 108/108 applied,
GATE-2 `tables=27 functions=70 policies=37 triggers=26` = CI baseline). Orders were created and
finalised through `venue.finalize_primary_order`; settlements through `venue.open_settlement` +
`kernel.close_settlement`; payouts through `kernel.request_org_payout` +
`kernel.mark_payout_transfer_state`; refunds through `kernel.request_order_refund` +
`kernel.mark_refund_state`; disputes through `kernel.record_dispute_native` +
`kernel.mark_dispute_state`. **No production mutation, no remote, no Stripe call.**
Nothing in the repo was modified other than this file.

Fixture shape, used everywhere for comparability: buyer pays **23 000** (`public.payments.total`)
= **19 000** face (`venue."order".total_minor`, the venue's ledger entitlement) + **4 000**
buyer fee. All amounts are integer minor units.

---

## 0. Verification of the three facts I was handed

| Claim | Verdict | Evidence |
|---|---|---|
| `kernel.reserve` is a sealed, empty, org-scoped money table; `balance_minor integer` with **no CHECK** | **TRUE** | `091_kernel_reserve_stub.sql:29-36`; live `\d kernel.reserve` shows no check constraint. It has **zero rows after all ten replays** and **no writer anywhere** — 8 repo references, all inside 091 itself or test census comments. |
| E-149 states a negative balance "is not pre-empted by the stub" | **TRUE, verbatim** | `docs/architecture/_governance/POST_FREEZE_AMENDMENTS.md` E-149: *"`balance_minor` carries NO CHECK (none is stated; a Gate-M receivable posture — a negative balance — is not pre-empted by the stub)"*. |
| Gate-M covers C29/C30/C31 "modeled only"; the native-sale payout writer is Gate-M-deferred | **TRUE** | `SNATCH_IT_CANONICAL_DATA_MODEL.md:510,633,639`; `PHASE_2_IMPLEMENTATION_TRACEABILITY_MATRIX.md:420` (`RATIFIED-MODELED-ONLY(GATE-M)`). |
| **"C30: no dispute or chargeback table exists in any of the sixteen packages"** | **FALSE / STALE** | The matrix line (`…TRACEABILITY_MATRIX.md:341,750`) predates package 088. **`kernel.dispute_native` exists** (`088:189-215`) and **`kernel.identity_obligation` exists** (`085:165-190`, `origin_kind ∈ {chargeback, refund_clawback}`, `status ∈ {outstanding, recovered, written_off}` — a *literal receivable object*). `venue.settlement_line.cause` includes `'chargeback'` (`087:97`). **The tables are there. What is missing is the writers** — see §4. |

---

## 1. What the code actually does (measured, then read back to source)

`kernel.close_settlement` (live body: `093:640-855`) derives
`net = gross − fees − refunds = Σ(all signed lines)` and then:

```sql
if v_net > 0 then   -- 093:723
   insert into kernel.payout (... 'settlement', p_settlement_id, v_net ...)
```

**A settlement whose net is ≤ 0 mints nothing.** The slice says so in its own comment
(`093:375-377`): *"the debit then lands either in a settlement nobody ever opens, or in one that
nets negative and mints no payout, while the money has already left. **A negative net is NOT a
receivable: this schema has no carry-forward object.**"* That is the whole finding, and the
replays confirm it exactly.

Debit generation (`kernel.settlement_primary_lines`, `093:435-551`; chargeback arm in
`kernel.settlement_royalty_lines`, `093:1136-1212`):

* only `kernel.refund.status='succeeded'` is lined; `pending`/`submitted` **defer the whole order**;
  `failed` is never lined (**measured**, world L: net 0).
* only `kernel.dispute_native.status ∈ ('lost','charge_refunded')` is lined; `won` produces
  nothing (**measured**, world L).
* both debits are capped at the order's **face value**, cumulatively across closes and across
  causes. The buyer-fee slice of a refund/chargeback is **platform money and is never charged to
  the venue** (ruling A5) — measured in case B (23 000 disputed → −19 000 lined).
* `settlement_line` carries global unique indexes `settlement_one_primary_sale_line_ever`,
  `settlement_one_refund_void_line_ever`, `attribution_one_commission_line_ever`. **There is no
  equivalent for `cause='chargeback'`** — already a named, deliberately-untouched gap
  (`POST_FREEZE_AMENDMENTS.md` → `CHARGEBACK_CROSS_SETTLEMENT_UNIQUE`, Gate-M/PFA-29). Today the
  seam's own `NOT EXISTS` + `prior_cb_minor` cap is the only thing preventing a double debit.

Because the debit is one-shot **globally**, a third settlement re-run recovers nothing
(**measured**, world A settlement 3: zero lines, net 0). `close_settlement` is forward-only
(`status <> 'open'` → `noop_replay`), so a negative header can never be repaired.

---

## 2. THE TEN CASES — what the database ends up holding

`payouts` column reads `amount/status/hold_state/hold_reason_code`.

### CASE A — venue paid 19 000, entitlement later falls to 13 000

| settlement | status | gross | fees | refunds | net | lines | payout |
|---|---|---|---|---|---|---|---|
| `358688d9` | **paid** | 19000 | 0 | 0 | 19000 | `primary_sale +19000` | 19000 / paid / none |
| `d5627512` | **closed** | 0 | 0 | 6000 | **−6000** | `refund_void −6000` | **NONE** |
| `aec80945` | closed | 0 | 0 | 0 | 0 | *(none)* | NONE |

Durable facts created by the reversal: **one** `kernel.refund` row (6000/succeeded/buyer_request),
**one** `settlement_line` (`refund_void −6000`), **one** settlement header frozen at `closed`
with `net_minor = −6000`, `venue."order".status → partially_refunded`.
Created by nothing: no payout, no `identity_obligation`, no `kernel.reserve` row, no hold, no
audit action naming an exposure. **Exposure 6 000 — confirmed.**

### CASE B — venue paid in full, then a 100 % chargeback

| settlement | status | gross | refunds | net | lines | payout |
|---|---|---|---|---|---|---|
| `9efb9c28` | paid | 19000 | 0 | 19000 | `primary_sale +19000` | 19000 / paid / none |
| `3bbbd75a` | **closed** | 0 | 19000 | **−19000** | `chargeback −19000` | **NONE** |

`kernel.dispute_native` row: 23000 / `lost`. Two ticket atoms moved to
`resale_state='dispute_hold'`. **`payouts_held: 0`** — `record_dispute_native` freezes only
`status ∈ ('pending','submitted')` payouts (`088` payout leg), so an already-`paid` payout is
untouched, and the freeze runs **only while the dispute is open**, so a dispute first observed as
`lost` freezes nothing at all. `kernel.identity_obligation`: **0 rows**.

### CASE C — partial refund(s) after payout

Two refunds (6000 then 13000) on the 19 000 order after a 19 000 payout. Both lined into one
later header: `refund_void −13000` + `refund_void −6000`, net **−19000**, no payout. The
face-value cap held exactly (Σ debits = 19 000 = face, not 23 000 = payment total). Order →
`refunded`.

### CASE D — later settlements recover only PART

| settlement | gross | refunds | net | payout |
|---|---|---|---|---|
| `907da784` | 19000 | 0 | 19000 | 19000 / **paid** |
| `70df24f6` | 5000 | 12000 | **−7000** | **NONE** |
| `88d429fe` | 10000 | 0 | 10000 | 10000 / **paid** |

**This is the most important measurement in the report.** The venue's 5 000 of *new* revenue was
silently consumed (never paid) — a 5 000 recovery of the 12 000 exposure. The **−7 000 residue
did not carry**: the very next settlement paid the venue its full 10 000. Total recovered:
5 000 of 12 000. **The recovered fraction is decided entirely by which revenue happens to sit in
the same close as the debit — an operational accident, not a policy.**

### CASE E — later settlement SMALLER than the outstanding carry

Settlement `70df24f6` above: +5 000 against −12 000 → net −7 000 → **no payout at all**. The
venue receives nothing that period; the platform recovers exactly the gross of that one close;
the remainder is orphaned on close.

### CASE F — later settlement LARGER than the carry

| settlement | gross | refunds | net | payout |
|---|---|---|---|---|
| `90643c77` | 19000 | 0 | 19000 | 19000 / paid |
| `d3f44a1b` | 20000 | 12000 | **8000** | **8000 / paid** |

Full offset, executed cleanly. **"Future payout offset" is real and it works** — but only inside
one `close_settlement` call. It is an emergent property of `net = Σ lines`, not a designed
recovery mechanism: nothing anywhere is named, logged, reported or bounded as an offset.

### CASE G — multiple reversals across multiple events

Two events, one org. Event 1 paid 19 000 then refunded 8 000; event 2 paid 15 000 then a
`lost` dispute of 18 000. A **period-scoped** settlement (`event_id IS NULL`) pooled both:

| settlement | gross | refunds | net | lines | payout |
|---|---|---|---|---|---|
| `b1011d4d` | 0 | 23000 | **−23000** | `chargeback −15000`, `refund_void −8000` | **NONE** |

Cross-event pooling works at the period grain (and the chargeback was correctly capped at the
15 000 face, not the 18 000 disputed). It still cannot produce a receivable.

### CASE H — venue becomes suspended after debt exists

`kernel.organization.status := 'suspended'` after the debt. Measured:

* `venue.open_settlement` and `kernel.close_settlement` — **still work**.
* `kernel.request_org_payout` — **still advances to `submitted`. It never reads
  `kernel.organization.status`.**
* `kernel.get_payout_execution_context` — **refuses**: `execution_eligible: false`,
  `refusal_code: "org_not_active"` (`093:2367`).

Result: payout `a111d620` sits at **7000 / submitted / hold_state=none** forever. It is not
held, not failed, has no lease and no timeout; the settlement stays `closed`. **Suspension does
not recover debt in either direction** — it strands a 7 000 payable to the venue in a state with
no exit, while the earlier settlement `0d9a43a7` had *already* been paid 3 000 net of the
−6 000 debit while the org was suspended (the netting happened in the same close, so the
suspension was irrelevant to it).

### CASE I — venue never sells again

The terminal state of A / B / C / K. Across the whole replay: **7 settlement headers with
`net_minor < 0`, all `status='closed'`, all with zero payout rows.** They are readable by
`org_finance` through `venue_settlement_sel_org`, but:

* `kernel.list_org_payouts` reads `kernel.payout` only — a negative settlement is invisible to it;
* no function, view, cron job or notify type in `076`–`093` aggregates, ages, alerts on or
  reports a negative settlement;
* `kernel.hold_payout` **refuses** a paid payout (`"only an unexecuted payout holds"` — measured);
* there is **no verb at all** that acts on a payout after it reaches `paid`.

The exposure exists only as an arithmetic difference nobody computes.

### CASE J — payout destination changes while debt exists

Debt orphaned first (`d96a6baf`, net −6 000), then `kernel.set_org_payout_destination` by the
org_owner (requires a `connect_pending_ref` minted by the connect-onboarding edge), then new
revenue of 11 000:

* `kernel.request_org_payout` → `{"status":"probation_held"}`, payout `bbf40e1b`
  **11000 / pending / probation_hold / `destination_probation`** — the full 11 000, **not**
  11 000 − 6 000.
* `kernel.release_payout` (platform_admin) → then paid **11 000 in full to the NEW destination**.

The probation control is about *who* gets paid, never *how much*. The orphaned −6 000 is
untouched by a destination change and follows the old destination nowhere.

*(A control-run with `payout.destination_probation_days = 0` produced no probation hold, as
expected — the arm keys on the `org.payout_destination.change` / `org.connect_ref.bind` audit row
inside the window.)*

### CASE K (extra) — event cancellation after payout

`catalog.cancel_event` → `{"atoms_voided": 2, "refunds_created": 1}`. It creates a **`pending`**
`kernel.refund` for **19 000** — `sum(order_item.unit_price_minor)`, i.e. face value only; the
buyer's 4 000 fee is **not** returned on a cancelled event. It **touches `kernel.payout`
nowhere**: the 19 000 payout stayed `paid`. Once the refund reached `succeeded`, the next close
booked `refund_void −19000` → net −19 000 → no payout. Identical terminal state to case A.

---

## 3. Nine questions per reversal type

Legend: **Q1** durable fact · **Q2** venue obligation changes · **Q3** paid venue owes Snatch It ·
**Q4** Snatch It absorbs · **Q5** future venue revenue offsets · **Q6** promoter commission changes ·
**Q7** schema can represent the result · **Q8** state machine can recover it · **Q9** conserved exactly.

| Reversal | Q1 | Q2 | Q3 | Q4 | Q5 | Q6 | Q7 | Q8 | Q9 |
|---|---|---|---|---|---|---|---|---|---|
| **Partial refund** (post-payout) | `kernel.refund` + `settlement_line refund_void` + a `closed` negative header | **Yes** — entitlement drops by the face-capped amount | **Economically yes, ledgerally no** — no obligation row exists | **Yes, by default** | **Only** if new revenue lands in the *same* close | New commission blocked (`o.status` exclusion, `093:918`); **an already-paid commission is never reversed** | **Partly** — `identity_obligation` exists but is identity-scoped and orgs have no equivalent; `kernel.reserve` could hold a negative but is sealed | **No** — forward-only close, no re-mint, `hold_payout` refuses a paid row | Cash yes; **entitlement no** |
| **Full refund** | same, Σ debits capped at face | Yes → 0 | same | Yes | same | same | same | No | same |
| **Dispute (open)** | `dispute_native` + atoms → `dispute_hold` + `pending`/`submitted` payouts → `held`/`dispute` | Not yet | — | — | — | — | Yes | Yes (release path exists) | n/a |
| **Lost dispute / chargeback** | `dispute_native.status='lost'` + `settlement_line chargeback` (face-capped) + negative header | Yes | Economically yes, ledgerally no | Yes — incl. the buyer-fee slice *by design* (A5) | Same one-close rule | Not reversed | Table exists; **no receivable is written** | No | Cash yes; entitlement no |
| **Chargeback after payout** | as above, **`payouts_held: 0`** | Yes | Yes | Yes | Same | Not reversed | as above | **No** — `paid → reversed` exists in the state machine but has **no production caller** (§4) | Cash yes; entitlement no |
| **Event cancellation** | bulk `pending` refunds at face value; **no payout touched**; `event_cancelled` also becomes a permanent `hold_reason` for *future* payouts via `settlement_payout_maturity` | Yes, once refunds settle | Yes | Yes | Same | Not reversed | Yes | No | Cash yes minus the retained buyer fee |
| **Manual risk refund** | identical to a partial refund (`reason_code ∈ {admin_action, auto_compensation, dispute}` are just labels on the same row) | Yes | Yes | Yes | Same | Not reversed | Yes | No | as above |
| **Processor adjustment** | **NOT SUPPORTED.** No table, column, cause or RPC represents a Stripe balance adjustment, dispute fee, or negative-balance sweep. `settlement_line.cause` has no member for it. | — | — | Silently, outside the ledger entirely | No | No | **No** | **No** | **No — invisible** |

---

## 4. Findings the previous train did not have (and corrections to it)

1. **`kernel.dispute_native` has ZERO production writers.**
   `record_dispute_native`, `mark_dispute_state` and `resolve_dispute_native` are called by
   **nothing** in `supabase/functions/`, `app/`, `src/` or `web/` — a repo-wide TypeScript search
   returns nothing. `stripe-webhook/index.ts:951` (`charge.dispute.created`) and `:1048`
   (`charge.dispute.closed`) write **only** the legacy `public.disputes` / `public.transfers` /
   `public.payments` rows. **Consequence: the `chargeback` settlement-line arm (`093:1168-1212`)
   can never fire in production today.** Case B is reachable only by calling the RPC by hand.
2. **`kernel.record_identity_obligation` has ZERO callers** outside pgTAP suite 149.
   The one receivable object the schema *does* own is never written. So the correct statement is
   not "no receivable table exists" but "**a receivable table exists and nothing writes to it, and
   it is scoped to identities, not organizations**".
3. **`kernel.payout` can never reach `reversed` in production.** `payout-execute/executor.ts:799`
   emits `new_status: 'paid'` and nothing else; the `transfer.reversed` webhook branch
   (`stripe-webhook/index.ts:1133-1152`) calls the legacy `mark_transfer_reversed` on
   `public.transfers`. I drove `paid → reversed` by hand: it succeeded, and
   **`venue.settlement.status` stayed `paid`** — `venue.on_payout_settled` fires only on `paid`
   and has no inverse, so a reversed payout permanently strands the venue's entitlement with the
   header still claiming it was paid.
4. **`kernel.request_org_payout` does not check `kernel.organization.status`.** A suspended org
   advances to `submitted`; only the *edge executor's* read (`get_payout_execution_context`)
   refuses. The refusal has no durable form on the payout row — no hold, no failure, no lease.
5. **There is a prospective guard the previous train did not report:**
   `get_payout_execution_context` returns `refund_exposure_stale` when a covered payment carries
   settled refunds that no `refund_void` line has booked yet (`093`, H3 §5 step 4). So the
   corpus already refuses to *pay* into a known exposure — it simply has nothing to do once the
   money has left. The window in which the loss is created is exactly "refund succeeds **after**
   the Stripe transfer", which is precisely case A.
6. **`payout.settlement_maturity_interval` gates everything.** With the key unset (production
   today, seeded `null`) every settlement payout mints `held` / `unbounded_refund_exposure`. The
   loss cases in this report all require the owner to have set that key.

**Net verdict on the previous train:** its *conclusion* ("only 'platform absorbs' is implemented;
'future payout offset' exists accidentally") is **correct and independently reproduced**. Its
*premise* ("no dispute or chargeback table exists") is **wrong** — it copied a stale line from the
traceability matrix. The real defect is one layer down: the tables exist, the causes exist, the
line arms exist, and **the writers do not**.

---

## 5. Conservation equations — integer minor units

Terms, all taken directly from the replayed database:

* `BUYER CASH COLLECTED` = Σ `public.payments.total` over the org's orders
* `BUYER REFUNDS` = Σ `kernel.refund.amount_minor` where `status='succeeded'`
* `PROCESSOR LOSS` = Σ `kernel.dispute_native.amount_minor` where `status ∈ ('lost','charge_refunded')`
* `VENUE POSITION` = the ledger's own entitlement = Σ `venue.settlement.net_minor` over non-open headers
* `UNRECOVERED RECEIVABLE` = cash disbursed − ledger entitlement = Σ paid `kernel.payout.amount_minor` − `VENUE POSITION`
* `PLATFORM POSITION` = collected − refunds − chargebacks − cash disbursed
* `PROMOTER POSITION` = 0 in every case (no attribution bound; and every `promoter_commission`
  payout is minted `held`/`unfunded_settlement` regardless — `090:1487-1491`, asserted in
  `POST_FREEZE_AMENDMENTS.md` "091 and the commission funding leg")

| Case | Collected | − Refunds | − Processor loss | = LHS | Platform | Venue (ledger) | Promoter | **Unrecovered** | RHS | Closes? |
|---|---|---|---|---|---|---|---|---|---|---|
| **A** | 23000 | 6000 | 0 | **17000** | −2000 | 13000 | 0 | **6000** | 17000 | ✅ |
| **B** | 23000 | 0 | 23000 | **0** | −19000 | 0 | 0 | **19000** | 0 | ✅ |
| **C** | 23000 | 19000 | 0 | **4000** | −15000 | 0 | 0 | **19000** | 4000 | ✅ |
| **D/E** | 41000 | 12000 | 0 | **29000** | 0 | 22000 | 0 | **7000** | 29000 | ✅ |
| **F** | 47000 | 12000 | 0 | **35000** | 8000 | 27000 | 0 | **0** | 35000 | ✅ |
| **G** | 41000 | 8000 | 18000 | **15000** | −19000 | 11000 | 0 | **23000** | 15000 | ✅ |
| **H** | 42000 | 6000 | 0 | **36000** | 14000 | 29000 | 0 | **−7000** ¹ | 36000 | ✅ |
| **J3** | 36000 | 6000 | 0 | **30000** | 0 | 24000 | 0 | **6000** | 30000 | ✅ |
| **K** | 23000 | 19000 | 0 | **4000** | −15000 | 0 | 0 | **19000** | 4000 | ✅ |

¹ **negative** = the platform owes the venue: the 7 000 payout stuck at `submitted` behind
`org_not_active`.

**Every equation closes — and that is the finding, not a reassurance.** It closes *only because
`UNRECOVERED RECEIVABLE` is a derived quantity I computed by hand across two schemas.* It
corresponds to **no table, no column, no row, and no function in the corpus.** Restated as the
platform would actually see it — with `UNRECOVERED RECEIVABLE` forced to the 0 the database can
represent — every one of A, B, C, D/E, G, J3 and K **fails to close**, by exactly the amount in
the Unrecovered column: 6 000, 19 000, 19 000, 7 000, 23 000, 6 000 and 19 000.

**Money that goes missing without being anywhere.** In every failing case the gap is the same
object: `venue.settlement.net_minor < 0` on a header stuck at `closed` (7 such headers across the
replay, totalling **−99 000**). It is written, it is append-only, it is readable by
`org_finance` — and it is read by nothing. It ages nowhere, alerts nowhere, offsets nothing
outside its own close, and can never be paid, released, forgiven or written off, because
`venue.settlement.status` has no member for any of those and `close_settlement` is forward-only.

Two smaller non-closures, both **by explicit design** and recorded here only so they are not
rediscovered as bugs:

* **Buyer-fee residue.** A refund is measured against `payments.total` (face + fee) but the
  `refund_void` line is capped at face, per ruling A5. In case A the platform absorbs the fee
  slice silently. In case B the platform absorbs 23 000 − 19 000 = **4 000** of chargeback beyond
  the venue's face.
* **Cancelled-event fee retention.** `catalog.cancel_event` refunds
  `sum(order_item.unit_price_minor)` = 19 000, not `payments.total` = 23 000. The buyer is out
  **4 000** on an event that did not happen. Policy call, not an arithmetic error — but it is
  never disclosed anywhere in the ledger.

---

## 6. USD-only verdict: **YES — the rail is hard USD-only today.** Cross-currency is not a
## configuration away; it is unimplemented at every layer.

**Schema.** Every money-carrying currency column is `text NOT NULL DEFAULT 'USD'`:
`kernel.payment_native`, `kernel.refund`, `kernel.payout`, `kernel.identity_obligation`,
`kernel.dispute_native`, `kernel.reserve`, `venue."order"`, `venue.order_item`,
`venue.ticket_type`, `venue.settlement`, `venue.settlement_line`, `venue.attribution`,
`venue.promoter`, `market.listing_native`, `market.offer`, `market.market_sale`,
`market.p2p_transfer`. `public.payments` — the actual money-in row — **has no currency column at
all**. `public.disputes` defaults `'usd'` (lower case; `record_dispute_native` normalises with
`upper()`, `088:781`). There is **no FX/exchange-rate table anywhere in 108 migrations.**

**Writers.** The only primary-order writer hardcodes the literal:
`093:4192` / `093:4198` (and its 082 ancestor at `082:439` / `082:445`) insert `'USD'` into
`venue."order"` and `venue.order_item` — **a native order cannot be non-USD.**
`catalog.cancel_event`'s market arms hardcode `'USD'` (`088:1665`, `088:1717`).
`089:57` casts `'USD'::text as currency` into the bridge view.

**Refusals.** `kernel.get_payout_execution_context`:
`when upper(coalesce(v_po.currency,'')) <> 'USD' then 'currency_unsupported'` (`093:2360`).
`payout-execute/executor.ts:416` and `refund-execute/executor.ts:287` both refuse non-USD.
`primary-checkout/index.ts:803` refuses `currency !== 'USD'`.
`create-payment-intent/index.ts:514`, `primary-checkout/index.ts:1090`,
`confirm-and-release/index.ts:468` and `_shared/payouts.ts:138` all send the literal `'usd'` to
Stripe.

**And the settlement engine compares rather than converts.** `close_settlement` raises
`precondition_failed` on any candidate or line whose currency differs from the header's
(`093:686-696`); the seams `DROP` mismatched rows rather than raise (`093:462`, `088:346`), and
`settlement_commission_lines` filters `a.currency = v_s.currency` (`093:917`). A second currency
would therefore silently vanish from a settlement or wedge the close — never be converted.

**Conclusion: the architecture may be designed single-currency, and it is enforced as
single-currency at the schema default, the only order writer, three edge executors and the
settlement close. Any Gate-M design work may safely assume USD.**

---

## 7. The six possible outcomes, scored

| Outcome | Implemented? | Evidence |
|---|---|---|
| 1. Platform absorbs the loss | **YES — the default and, on its own, the only terminal one** | 7 orphaned negative headers, −99 000 total, zero payouts |
| 2. Venue owes Snatch It (receivable) | **NO** | `093:376` verbatim: *"A negative net is NOT a receivable: this schema has no carry-forward object."* `kernel.identity_obligation` exists but is identity-scoped **and unwritten**; `kernel.reserve` is org-scoped, could hold a negative, and is sealed empty |
| 3. Future payout offset | **YES, but only inside one `close_settlement` call — and accidental** | Case F (full, 20000−12000→8000 paid) and case D/E (partial, 5000 consumed, 7000 lost). Never named, bounded, logged or reported as an offset |
| 4. Recovery from the buyer | **NO** | `record_identity_obligation` has no caller |
| 5. Reserve / holdback | **NO** | `kernel.reserve`: 0 rows, 0 writers, sealed by 091's contract |
| 6. Write-off with a durable record | **NO** | No status, no reason code, no audit action for forgiving a negative settlement |

Everything a Gate-M design would need to *carry* a debt already exists in shape
(`kernel.reserve` org-scoped with an unchecked `balance_minor`; `kernel.identity_obligation` with
a full `outstanding → recovered | written_off` machine; `settlement_line.cause='settlement'`, an
unused member that could carry a brought-forward balance). **None of it is wired.**

---

## Appendix — reproduction

The harness lives only in the scratch database (schema `lm`, dropped with it); nothing was written
to the repo. To rebuild:

```
export PATH=/opt/homebrew/opt/postgresql@17/bin:$PATH
scripts/rehearsal_reset.sh snatchit_rehears_loss
psql -U postgres -d snatchit_rehears_loss -f supabase/tests/000_helpers.sql
```

then seed `tap.seed_core()`, set `feature.native_issuance_enabled=true`,
`payout.settlement_maturity_interval='0 hours'`, `payout.dual_control_min_minor=999999999`,
`authn.money_role_maturity_hours=0`, and drive the RPC chain named at the head of this document.
The G2 maturity gate additionally requires every covered `catalog.event_session` to carry a past
`ends_at`.
