# D — Promoter commission (Option B) vs. the three Stripe charge models

**Scope.** Does the ratified `COMMISSION_FUNDING_SOURCE` ruling (Option B) survive each candidate
primary-ticketing charge model? Where it does not, the conflict is named, not discarded.

**Status of this document.** Analysis only. No migration authored, no byte changed, nothing applied.
Every implementation claim carries `file:line`.

---

## 1. The ratified ruling, verbatim

`docs/architecture/_governance/POST_FREEZE_AMENDMENTS.md:2469` (E-138):

> **OWNER RULING (2026-09-02) — POLICY CLOSED / OWNER-RATIFIED · IMPLEMENTATION OBLIGATION OPEN:**
> OPTION B — promoter commissions are funded FROM PRIMARY TICKET REVENUE THROUGH THE VENUE SETTLEMENT
> ACCOUNTING MODEL (primary ticket revenue → promoter commission liability → venue distributable
> settlement): a commission is an economic deduction from the venue's primary-sale proceeds before the
> corresponding distributable venue money leaves the settlement system. NOT chosen: (A) generic
> carry-forward of an unfunded negative settlement as the primary mechanism, (C) arbitrary collection
> from the org's Stripe balance as the normal mechanism, (D) platform-funded commissions / platform
> absorption. FUNDING IS NOT ACTIVATED by this ruling: until the primary-revenue settlement funding
> leg is mechanically implemented, tested and authorized, ALL promoter commission payouts REMAIN HELD
> (`unfunded_settlement`) — 090's behaviour stands; nothing is advanced or released on the strength of
> the policy.

`POST_FREEZE_AMENDMENTS.md:2482` (the register entry) restates the target economics and the proof
obligations:

> **`COMMISSION_FUNDING_SOURCE`** (E-138) — **OWNER POLICY: RESOLVED (2026-09-02, OPTION B) ·
> IMPLEMENTATION: OPEN.** TARGET ECONOMICS: commission funded from primary ticket revenue before venue
> distributable settlement money leaves the system (primary ticket revenue → promoter commission
> liability → venue distributable settlement). Rejected as the normal mechanism: carry-forward of an
> unfunded negative net (A), arbitrary org Stripe-balance debit (C), platform advance/absorption (D).
> The implementation must eventually prove: the exact primary revenue source · the exact
> settlement-line representation · the commission deducted ONCE · conservation · no duplicate funding ·
> refund behaviour · chargeback behaviour · cancellation behaviour · the held-payout release condition ·
> payout destination readiness · settlement-close concurrency · no platform advance · no arbitrary
> Stripe-balance debit.

### 1.1 The ORDER of operations the ruling fixes

Three orderings are stated, and they are the whole of the ruling's mechanical content:

1. **Arrow ordering** — `primary ticket revenue → promoter commission liability → venue distributable
   settlement`. The commission liability is interposed *between* the revenue and the venue's
   distributable amount. It is not a downstream adjustment.
2. **Temporal ordering** — "**before** the corresponding distributable venue money **leaves the
   settlement system**". The deduction must land while the money is still inside the system.
3. **Negative ordering** — the three rejected mechanisms are precisely the three shapes a
   *post-hoc* funding takes: carry a negative forward (A), reach into the org's Stripe balance
   afterwards (C), or have the platform eat it (D).

**The load-bearing presupposition.** "Before venue money leaves the settlement system" only has
meaning if the venue's money is *inside* the settlement system at close. Option B therefore assumes
the platform holds the venue's primary proceeds at the moment `close_settlement` runs. Any charge
model that puts the venue's money in the venue's own Stripe balance at the moment of sale removes the
object the ruling operates on. That is the axis on which the three models separate.

### 1.2 A second constraint, from the implementation rather than the ruling

Commission payable is **computed at settlement close from live state**, not at sale:
`kernel.pay_promoter_commission` recomputes the basis from surviving (non-voided) atoms at
`090:1466-1473`, zeroes a refunded order at `090:1461-1464`, and applies the *attribution's* rate
snapshot (`090:1474-1475`). This matters because every Stripe mechanism that deducts *at charge
creation* (`application_fee_amount`, `transfer_data[amount]`) requires the commission amount to be
known when the buyer pays. It is not known then, by design.

---

## 2. Where the implementation actually stands

### 2.1 The settlement substrate (087)

- `venue.settlement` — `087:44`. Money columns `gross_minor / fees_minor / refunds_minor / net_minor`
  are NULL while open and written exactly once at close. The waterfall is a table CHECK:
  `net_minor = gross_minor - fees_minor - refunds_minor` (`087:61-66`).
- `venue.settlement_line` — `087:92`. `amount_minor` is **signed**: credits positive, debits negative
  (`087:99`, and the sign convention is restated at `087:283-289`). Append-only
  (`087:111-113`), `revoke update, delete ... from service_role` (`087:117`).
- **Uniqueness:** `constraint settlement_line_cause_uq unique (settlement_id, cause, cause_ref)` —
  `087:105`. Scoped **per settlement**.
- `kernel.close_settlement` — `087:289`. Under the header's `FOR UPDATE` (`087:298`) it:
  1. unions the two seams and inserts their candidates as lines (`087:311-322`);
  2. derives the buckets purely from the sign convention (`087:328-332`):
     `gross = Σ(amount > 0, non-refund cause)`, `fees = −Σ(amount < 0, non-refund cause)`,
     `refunds = −Σ(refund-cause amounts)`;
  3. `v_net := v_gross - v_fees - v_refunds` (`087:333`), i.e. **net is the arithmetic sum of every
     line**;
  4. mints an org payout **only if** `if v_net > 0` (`087:340`), amount `v_net`, `cause='settlement'`,
     `status='pending'` (`087:341-343`).

**Sign convention for a commission line: NEGATIVE.** The seam emits
`-((x ->> 'amount_minor')::bigint)` at `090:1542`. A commission therefore lands in the **fees** bucket
(`087:329`: negative, non-refund cause) and reduces `net_minor` directly. Mechanically, *within the
ledger*, Option B's arrow ordering is already correct: the commission debit is subtracted before the
org payout is computed, and the org payout is minted at exactly the post-commission net.

### 2.2 The gross is structurally zero

There is exactly **one** `insert into venue.settlement_line` in the entire migration set — `087:318`,
inside `close_settlement` — and its only inputs are the two seams: royalty (`088:320`) and commission
(`090:1511`). **Nothing writes a `primary_sale` revenue line.** The cause code exists in the enum
(`087:96`) and nowhere else as a settlement writer; `venue.finalize_primary_order` (085) writes no
settlement, no line and no payout. This is independently recorded in
`docs/phase2/_decisions/A_venue_money.md` and `docs/phase2/PRIMARY_TICKETING_OWNER_DECISION_PACKET.md:19-30`.

Consequence: for an event settlement whose only line is a commission, `gross = 0`,
`fees = commission`, `net = −commission`, the `v_net > 0` gate at `087:340` fails, **no org payout is
minted, and the org's debit is recorded but never collected**. This is exactly what E-138
(`POST_FREEZE_AMENDMENTS.md:2469`) describes and why 090 mints under a hold.

### 2.3 The seam is not a pure line generator — confirmed

`kernel.settlement_commission_lines` was created at `087:211` as a **`stable`** zero-row stub, and the
087 header contract at `087:204-207` states the seams are *"STABLE, pure, MUST NOT raise (a raise
would roll back close_settlement)"*.

090 replaces it at `090:1511` with a **`volatile` plpgsql** body that:

- takes a per-org transaction advisory lock (`090:1519`);
- selects the eligible attribution set with a `NOT EXISTS` over prior commission lines (`090:1536`)
  and terminal-class exclusions (`090:1537-1539`);
- **calls `kernel.pay_promoter_commission` (`090:1540`)**, which is where the side effects live;
- only then returns the candidate lines (`090:1541-1544`).

`kernel.pay_promoter_commission` (`090:1401`) is the mint:

- it refuses any caller whose stack does not contain both the seam and `close_settlement`
  (`090:1411-1414`) and re-locks the settlement `for update nowait` (`090:1421-1425`);
- **it INSERTs a `kernel.payout` row born held** — `090:1483-1487`:
  `cause='promoter_commission'`, `cause_ref = attribution_id`, `payee_kind='identity'`,
  `status='pending'`, `hold_state='held'`, `hold_reason_code='unfunded_settlement'`, `held_by = null`,
  idempotency key `'promoter_commission:<attribution_id>:<identity_id>'` (`090:1482`);
- it emits `payout_on_hold` (`090:1489-1492`) and `promoter_commission_accrued` (`090:1497-1500`),
  both swallowing exceptions (BE, OR-14);
- it writes a `settlement.commission` audit row (`090:1503-1506`).

So the prior review is **correct**: the seam mints money rows, writes audit and emits events. It is a
payout minter that also returns lines.

**It can also raise.** `090:1447` raises `precondition_failed: terms_unresolvable` when an
attribution's snapshot carries neither a resolvable bps nor a flat rate. A raise inside the seam
**rolls back the entire `close_settlement`** — the exact outcome `087:204-207` declares must not
happen. Every other rejection path is a `continue` into the `v_held` array (out_of_scope `090:1428`,
already_lined `090:1432`, unreviewed/denied flag `090:1440`, payee_unresolvable `090:1451`,
currency_mismatch `090:1455`, basis_zero `090:1463`/`090:1479`, amount_overflow `090:1481`), so the
raise at `090:1447` is the single non-conforming arm. It is reachable only if a stored attribution
violates its own kind/rate pairing, but the seam contract admits no such exception. **Flagged; not
changed.**

### 2.4 Double-lining

- **Commissions: solved.** `090:214` —
  `create unique index attribution_one_commission_line_ever on venue.settlement_line (cause_ref) where cause = 'promoter_commission'`.
  This is **global and unscoped by settlement**: one commission line per attribution, platform-wide,
  for all time. Belt and braces: the seam pre-filters with `NOT EXISTS` (`090:1536`) and
  `pay_promoter_commission` re-checks defensively (`090:1431-1432`).
- **Primary sales: no equivalent.** The only constraint that would govern a future `primary_sale` line
  is `settlement_line_cause_uq unique (settlement_id, cause, cause_ref)` (`087:105`), which is scoped
  **to one settlement**. The same order could therefore be lined in two settlements. This is not
  hypothetical: `venue.settlement` supports both an event-scoped header and a venue+period header
  (`087:47-50`, `event_id` nullable), and the commission seam's own scope predicate accepts both
  shapes (`090:1530-1535`). An event settlement and an overlapping period settlement over the same
  venue would each be eligible to line the same order. **Any `primary_sale` seam must ship a partial
  unique index of the 090 shape, or double-recognition of revenue is storable.**

### 2.5 Does anything release a held commission payout today? **No. Twice over.**

**Lock 1 — the hold.** `kernel.release_payout` (`085:807`) is the sole release path; it requires
`platform_risk` or `platform_admin` (`085:817-819`) and it is **called by nothing in the repository**.
The only call sites are pgTAP tests: `supabase/tests/155_phase2_venue_promoter_engine.sql:806`,
`supabase/tests/151_phase2_venue_settlement_and_export.sql:416,475,498`,
`supabase/tests/149_phase2_kernel_money_native.sql:546`. It is a manual per-payout Control-5 action,
not a funding rail — as `POST_FREEZE_AMENDMENTS.md:2482` states.

**Lock 2 — the missing advance path, which survives a release.** Even a released commission payout
cannot be paid:

- `status='submitted'` is written in exactly two places, `087:514` and `087:568`, both inside
  `kernel.request_org_payout`;
- that function selects its payout `where cause = 'settlement' and cause_ref = p_settlement_id`
  (`087:449-450`) — a `promoter_commission` payout is unreachable by it, and it additionally requires
  `payee_kind='organization'` semantics throughout (org roles at `087:418-420`, org row lock at
  `087:430`);
- `kernel.mark_payout_transfer_state` (`085:1668`) refuses a held payout outright (`085:1690-1691`)
  and, for a released one, permits `paid` only from `submitted` (`085:1700-1701`).

So a `promoter_commission` payout is `pending` + `held` with **no contracted transition to
`submitted`**. Releasing the hold moves it to `pending` + `none`, where it still cannot advance.
`kernel.hold_payout` (`085:769`) returns `noop_replay` on an already-held payout (`085:792`) without
comparing the reason — the defect recorded as `COMMISSION_PAYOUT_LIFECYCLE`
(`POST_FREEZE_AMENDMENTS.md:2483`). And 088's dispute payout leg (`088:839-846`) matches on
`po.cause_ref = sale_id` or on settlement ids reached through lines, so it does not reach a payout
whose `cause_ref` is an attribution id — recorded as E-132 (`POST_FREEZE_AMENDMENTS.md:2462`).

**Statement for the record: as the code stands, no automated or human-facing path releases and pays a
promoter commission. The liability is recorded exactly once and no money can leave. That is the
intended fail-to-safe.**

---

## 3. The three charge models against Option B

### 3.0 What the system does today (baseline, for contrast)

**Separate charges and transfers, platform as merchant of record.** The PaymentIntent body at
`supabase/functions/create-payment-intent/index.ts:512-525` contains only `amount`, `currency`,
`automatic_payment_methods[enabled]`, `customer`, `setup_future_usage` and four `metadata` keys —
**no `transfer_data`, no `on_behalf_of`, no `application_fee_amount`**, and `_shared/stripe.ts` sends
no `Stripe-Account` header. The seller is paid later by `POST /v1/transfers` with `destination` and
`source_transaction` (`supabase/functions/confirm-and-release/index.ts:514-537`).

**Connect account shape constrains the options.** `create-connect-account/index.ts:205-206` requests
`business_type: 'individual'` and `capabilities[transfers][requested]: 'true'` only — **`card_payments`
is not requested**. Existing connected accounts therefore cannot be the account of a direct charge or
the destination of a destination charge without re-onboarding. Org destinations live in
`kernel.organization.stripe_connect_account_ref` (`077:114`) and **no org-facing Connect onboarding
edge function exists**.

---

### 3.1 DIRECT — charge created ON the venue's connected account

**1. Where does the venue's money sit at the moment of sale?**
In the **venue's own Stripe balance**, immediately, less Stripe processing fees and less any
`application_fee_amount` set at charge creation. The platform never holds it. No platform-created
transfer object exists to act on.

**2. Can commission be deducted before the money reaches the venue?**
Only by `application_fee_amount`, fixed **at charge creation**. That is incompatible with §1.2: the
payable is computed at close from surviving atoms (`090:1466-1473`) and is zero for a refunded order
(`090:1461-1464`). A charge-time fee would have to guess. A platform-controlled **manual payout
schedule** on the connected account delays the venue's *bank* payout but does **not** move the money to
the platform and does not reduce the venue's Stripe balance — it does not create distributable money
inside our settlement system.
*Needs confirmation:* whether Stripe exposes a platform-initiated debit of a connected account
(outside application fees and refunds) that could serve as a post-hoc collection mechanism. Do not
design against it until confirmed — and note that if it exists it is mechanism (C), which the ruling
**rejected as the normal mechanism** (`POST_FREEZE_AMENDMENTS.md:2469`).

**3. If deduction fails, what does recovery look like, and is it reliable?**
Recovery is an off-ledger collection: invoice the venue, or net it against a future settlement (that
is mechanism (A), rejected). Reliability fails in all three stress cases — the venue spends the
balance (nothing to reverse, no transfer object exists), the account goes negative (Stripe's negative
balance is the platform's exposure and recovery becomes a debt-collection problem), the venue
disconnects (no API path remains at all). **Recovery risk: HIGH / effectively unsecured.**

**4. Ordering.**
**INVERTED.** The commission becomes a claw-back on money that already left. Worse, the ruling's
object disappears: there is no "venue distributable" inside the settlement system to reduce, because
the venue was paid at the till. The ledger would still compute `net = −commission` (`087:333`) and
still mint no payout (`087:340`), but the negative would now represent a **receivable from the venue**
rather than a deduction — the precise shape of rejected option (A).

**VERDICT: CONFLICT with Option B.** Direct charges cannot implement the ratified ruling. To proceed
the owner would have to **amend `COMMISSION_FUNDING_SOURCE`** — either (i) re-ratify a claw-back /
receivable model (a form of A), (ii) authorize a charge-time application fee and simultaneously move
commission computation from settlement close to sale time, which contradicts the refund and
surviving-atom semantics at `090:1461-1473`, or (iii) accept (D) platform absorption, explicitly
rejected. It also requires full Connect re-onboarding (`create-connect-account/index.ts:205-206`).

---

### 3.2 DESTINATION / `on_behalf_of` — charge on the platform, funds routed to the venue

**1. Where does the venue's money sit at the moment of sale?**
The charge settles into the **platform** balance and Stripe creates an associated transfer to the
venue's connected account. The venue's share reaches the venue's balance on Stripe's own schedule as
the charge becomes available — **not on ours**. `on_behalf_of` additionally makes the venue the
settlement merchant (fee/tax/statement-descriptor implications); it does not change where funds
ultimately land.

**2. Can commission be deducted before the money reaches the venue?**
Yes, but **only at charge creation**: `transfer_data[amount]` sets exactly what the venue receives, or
`application_fee_amount` retains a slice for the platform. Same timing defect as §3.1 — the payable
is not known at charge time. After the fact the only lever is a **transfer reversal** against the
automatically created transfer, which is a claw-back, not a pre-deduction.

**3. If deduction fails, what does recovery look like, and is it reliable?**
Transfer reversal is a real mechanism and is the strongest of the three recoveries, because a
platform-created transfer object exists to reverse. It is still not reliable:
the venue may have paid the balance out to its bank before we close the settlement; a reversal against
an insufficient balance drives the connected account negative (*needs confirmation of Stripe's exact
behavior when the connected balance is insufficient at reversal time*); a disconnected account cannot
be reversed against. Reversal also has no natural pairing with our ledger — nothing in 085/087/090
records a reversal against a settlement line, and `settlement_line` is append-only (`087:111-117`), so
a reversal would have to be represented as a **new** line, which the closed header cannot accept
(money columns are write-once at close, `087:335-338`). **Recovery risk: MEDIUM, and it has no
ledger representation today.**

**4. Ordering.**
**PRESERVED ONLY** in the narrow case where the commission is known at charge creation and encoded in
`transfer_data[amount]`. In every other case it **inverts into a claw-back → CONFLICT.**

**VERDICT: CONDITIONAL CONFLICT.** Compatible with Option B only under a charge-time-known commission,
which contradicts the ratified computation point. If the owner wants destination charges, the
amendment required is: *commission is fixed at sale from the attribution snapshot and is NOT
recomputed at close* — which forfeits the refund/void correctness at `090:1461-1473`, and needs a
separately ruled treatment of refunds after commission has already been routed. Also requires Connect
re-onboarding (`card_payments` not requested — `create-connect-account/index.ts:205-206`).

---

### 3.3 SEPARATE CHARGES AND TRANSFERS — buyer pays the platform; the venue is paid later

**1. Where does the venue's money sit at the moment of sale?**
Entirely in the **platform's Stripe balance**. The venue holds a **claim**, not funds. This is the
model already proven in production for resale (`create-payment-intent/index.ts:512-525`,
`confirm-and-release/index.ts:514-537`).

**2. Can commission be deducted before the money reaches the venue?**
**Yes — natively, with no Stripe feature at all.** The venue is paid by a platform-initiated transfer
whose amount we choose, and the amount we choose is already defined: `close_settlement` sums every
line including the negative commission line (`087:328-333`) and mints the org payout at exactly
`v_net` (`087:340-343`). The mechanism is therefore *"the later transfer's amount is the settlement
net"* — the deduction happens in our ledger while 100% of the money is still in our balance. This is a
literal, one-for-one implementation of the arrow `primary ticket revenue → promoter commission
liability → venue distributable settlement`.

**3. If deduction fails, what does recovery look like?**
The ordinary path needs no recovery: the commission is never transferred out in the first place. The
residual risk is the opposite one — the platform holds venue money and must not lose it. The controls
already exist: SoD-1 destination-setter check (`087:427-429`), money-role maturity (`087:431-433`),
AAL2 step-up (`087:435-442`), destination cool-down (`087:443-445`), a `no_payout_destination` refusal
(`087:446-448`), and destination probation (`087:474+`). **Recovery risk: LOW / N/A.**

**4. Ordering.**
**PRESERVED, exactly and literally.** No inversion. No claw-back.

**VERDICT: NO CONFLICT.** This is the only model that implements the ratified ruling as written. It
requires **no change to the Stripe charge model** — it is what the code already does.

**Caveat that is not a conflict but is a blocker:** Option B remains inert under this model until a
`primary_sale` revenue line exists. Today `gross = 0` (§2.2), so `net = −commission`, no org payout is
minted (`087:340`), and there is no distributable to reduce. Option B is *compatible* with separate
charges; it is not *active* until the primary-revenue line is written.

---

## 4. Compatibility matrix

| MODEL | Commission deductible pre-payout? | Mechanism | Ordering preserved? | Conflict with Option B? | Recovery risk if it fails |
|---|---|---|---|---|---|
| **DIRECT** (charge on venue's account) | **No** (except a charge-time `application_fee_amount`, which the close-time computation at `090:1466-1473` forbids) | None available post-sale. Manual payout schedule delays the venue's *bank* payout but never moves funds to the platform. Platform-initiated account debit: **needs confirmation**, and would be rejected mechanism (C) | **No — inverted into a claw-back**, and the "venue distributable" the ruling reduces does not exist inside the system | **YES — outright conflict.** Requires amending `COMMISSION_FUNDING_SOURCE` | **HIGH / unsecured.** No transfer object to reverse; venue spends the balance, goes negative, or disconnects and no API path remains |
| **DESTINATION / `on_behalf_of`** | **Only if fixed at charge creation** via `transfer_data[amount]` or `application_fee_amount` | Charge-time `transfer_data[amount]`; post-hoc only **transfer reversal**, which is a claw-back | **Conditionally.** Preserved only for a charge-time-known commission; otherwise inverted | **CONDITIONAL CONFLICT.** Compatible only if commission stops being recomputed at close — forfeiting `090:1461-1473` refund/void correctness | **MEDIUM.** Reversal exists but races the venue's bank payout; behavior on insufficient connected balance **needs confirmation**; a reversal has **no ledger representation** — `settlement_line` is append-only (`087:111-117`) and the closed header's money columns are write-once (`087:335-338`) |
| **SEPARATE CHARGES AND TRANSFERS** | **Yes — natively** | The later platform-initiated transfer is paid at the settlement net; the negative commission line (`090:1542`) is already subtracted by `087:328-333` before the payout is minted at `087:340-343` | **Yes — exactly and literally** | **NO CONFLICT.** The only model that implements the ruling as ratified | **LOW / N/A** — the commission never leaves the platform balance. Residual controls already in `request_org_payout` (`087:427-448`) |

Additional constraint applying to both DIRECT and DESTINATION: existing Connect accounts request
`transfers` only, not `card_payments` (`create-connect-account/index.ts:205-206`), and no org-facing
Connect onboarding function exists. Both models require full re-onboarding before a first sale.

---

## 5. If the venue receives funds directly, is an internal settlement fact still needed?

**Yes.** Nine reasons were considered; they do **not** carry equal weight, and the honest split
matters more than the list.

**Genuinely require a durable internal row (a Stripe query cannot substitute):**

1. **Promoter attribution and commission.** Stripe has no concept of a promoter, an attribution, a
   commission rate snapshot, or a self-deal review. `venue.attribution` and its rate snapshot
   (`090:1474-1475`), the review chain (`090:205-210`), and the one-line-ever constraint (`090:214`)
   exist nowhere else. **Non-negotiable.**
2. **Refund and cancellation semantics.** The payable is defined over **surviving, non-voided ticket
   atoms** (`090:1466-1473`) — a join across `kernel.ticket_ownership_log` and `kernel.tickets` that
   Stripe cannot answer at any price. A Stripe refund object does not tell you which atoms survived.
3. **Revenue share.** Any split percentage between platform and venue is our policy, not Stripe's. The
   packet already flags the split percentage as unruled OWNER POLICY
   (`PRIMARY_TICKETING_OWNER_DECISION_PACKET.md:49-51`).
4. **Reconciliation.** Reconciliation is by definition the comparison of an internal expectation
   against Stripe. With no internal row there is nothing to reconcile *against* — you would only be
   restating Stripe to itself. This is the failure the architecture was built to avoid
   (`PRIMARY_TICKETING_OWNER_DECISION_PACKET.md:31-34`).
5. **Audit.** `kernel.admin_audit` rows (`087:355-356`, `090:1503-1506`) bind a money movement to an
   actor, a reason code and a command key. Stripe records none of that.
6. **Event cancellation.** Cancelling an event has to unwind attributions, holds and obligations
   across many orders atomically. That is a transaction over our tables.

**Materially easier with a durable row, but reconstructable from Stripe with effort:**

7. **Reporting.** Reconstructable, but only by replaying Stripe history per query — unbounded latency,
   rate limits, and no point-in-time correctness.
8. **Tax.** Under DIRECT/`on_behalf_of` the venue is the merchant of record and its own tax filer, so
   the platform's tax need is genuinely reduced; the platform still needs its own fee revenue durable.
9. **Refund mechanics** (as distinct from refund *semantics* in (2)) — the Stripe refund object itself
   is authoritative.

**Summary judgment.** Even under a model where the venue is paid directly and is merchant of record,
items 1, 2, 4, 5 and 6 make a durable internal settlement fact **mandatory**. Direct payment changes
*who holds the money*; it does not change *who owns the meaning of the transaction*.

---

## 6. Minimum durable internal accounting facts, per charge model

Common to all three (the irreducible core):

- **`venue.attribution`** — the promoter, the order, the rate snapshot, the self-deal flag
  (`090:1466-1475`, `090:191-195`). No substitute exists.
- **One `promoter_commission` settlement line per attribution, for all time** — enforced globally at
  `090:214`.
- **A `kernel.payout` row per (attribution, payee)** — the exactly-once liability, keyed
  `promoter_commission:<attribution_id>:<identity_id>` (`090:1482-1487`).
- **`kernel.admin_audit`** for every close and every commission run (`087:355`, `090:1503`).

**A — SEPARATE CHARGES AND TRANSFERS (recommended; no conflict).**
The core, plus:
1. a **`primary_sale` revenue line** (positive, `087:96` cause code already exists) per order, written
   by a third seam at close, **with a global partial unique index of the `090:214` shape** to prevent
   the double-lining described in §2.4;
2. the existing `venue.settlement` header — gross/fees/refunds/net written once at close
   (`087:328-338`);
3. the existing `cause='settlement'` org payout minted at net (`087:340-343`), and its transfer
   reference recorded by `mark_payout_transfer_state` (`085:1668`);
4. a refund arm producing a `refund_void` line so the waterfall stays true.
This set is sufficient. No money-ledger DDL, no new tables.

**B — DESTINATION / `on_behalf_of`.**
Everything in A, **plus**:
5. a durable record of **what Stripe routed to the venue at charge time** (the transfer id and the
   `transfer_data[amount]`), because the split is no longer ours to compute at close — it was decided
   at the till and must be reconciled against;
6. a durable **reversal fact** with a settlement-line representation. `settlement_line` is append-only
   (`087:111-117`) and a closed header's money columns are write-once (`087:335-338`), so a reversal
   cannot amend the settlement it corrects: it needs a new cause and its own line in a later
   settlement. **This cause does not exist in the enum at `087:96` and would be new DDL.**
7. a rule for a commission whose basis shrinks after the routing (refund after transfer) — currently
   `090:1461-1473` handles this by simply not lining; under B the money is already gone.

**C — DIRECT.**
Everything in A and B, **plus**:
8. an **accounts-receivable fact** — a venue-owed balance that is not a settlement line, because a
   settlement line is a deduction from money we hold and under DIRECT we hold none. This is a new
   table and a new money concept. It is also, structurally, rejected option (A) — a carried-forward
   unfunded negative — which is why DIRECT cannot be reconciled with the ruling by adding facts alone.

---

## 7. Findings, plainly stated

1. **Only SEPARATE CHARGES AND TRANSFERS preserves the ratified ordering.** DESTINATION preserves it
   conditionally and only by breaking the close-time commission computation. **DIRECT conflicts
   outright** and cannot be adopted without the owner amending `COMMISSION_FUNDING_SOURCE`.
2. **Nothing releases a held commission payout today, and a release would not be enough.**
   `kernel.release_payout` (`085:807`) is called by nothing outside pgTAP; and even released, no
   contracted path writes `status='submitted'` for `cause='promoter_commission'` (`087:449-450`,
   `087:514`, `087:568`), so `mark_payout_transfer_state` can never reach `paid` (`085:1700-1701`).
   The fail-to-safe is doubled.
3. **The commission seam is a payout minter, not a pure line generator** (`090:1511` → `090:1540` →
   `090:1483`), and it **can raise** at `090:1447`, contradicting the seam contract at `087:204-207`
   that a raise would roll back `close_settlement`. Flagged; not changed.
4. **Commissions cannot be double-lined** (`090:214`, global). **Primary sales could be** — `087:105`
   is per-settlement only, and event-scoped and period-scoped settlements can overlap
   (`087:47-50`, `090:1530-1535`). Any `primary_sale` seam must ship the 090-shaped index.
5. **Option B is compatible with today's charge model but inert**, because no `primary_sale` revenue
   line writer exists (the only `settlement_line` INSERT is `087:318`, fed by two seams only).

## 8. What the owner would have to amend, by model

- **To adopt SEPARATE CHARGES AND TRANSFERS:** nothing in the ruling. Implementation only.
- **To adopt DESTINATION:** amend `COMMISSION_FUNDING_SOURCE` to fix the commission **at sale** from
  the attribution snapshot rather than recomputing at close, and rule separately on refunds arriving
  after routing. Plus Connect re-onboarding.
- **To adopt DIRECT:** amend `COMMISSION_FUNDING_SOURCE` outright. The ruling's mechanism —
  "reduces venue distributable before venue money leaves the settlement system" — has no referent when
  the venue is paid at the till. The owner would be choosing rejected option (A) (a carried receivable)
  or rejected option (D) (platform absorption) under a new name. Plus Connect re-onboarding.
