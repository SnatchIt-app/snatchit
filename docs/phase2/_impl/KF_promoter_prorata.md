# KF — Promoter reversal accounting and pre-close pro-rata funding (investigator F)

Rehearsal DB `snatchit_rehears_f` (110 migrations, Gate-2 27/70/37/26 = CI baseline). All numbers
below were executed there; nothing in migrations/tests/edges was changed; no git commit.
Fixture and scripts: `scratchpad/kf_setup.sql`, `kf_cases.sql`, `kf_conserv.sql`, `kf_probes2.sql`
(scratchpad only, not in the repo). Shape: org `KF Co` → venue `KF Hall` → events A–H, one session
each ended 30 days ago; promoter P = `other_user`, org-wide, `bps 1000`, code `FCODE`; every order is
finalized through `venue.finalize_primary_order` (the real resolver runs; `attribution.basis_minor
= 10000, credited_amount_minor = 1000` on every order); refunds go through
`kernel.refund_primary_order` + `kernel.mark_refund_state` except where the 30-day-old session is
transfer-frozen (`kernel.is_transfer_frozen`, 079:264 — `refund_primary_order` parks a FULL refund at
085:571-573 `frozen:`), where the 159 fixture shape (`kernel.refund` row + the 085:601-604 status rule,
as table owner) was used instead — noted per case.

---

## 1. What I inspected

| Object | Where | What it fixes |
|---|---|---|
| Attribution basis at freeze | 090:1116-1120 | `basis = Σ unit_price × qty` (face subtotal), `credited = floor(basis × bps / 10000.0)` — FLOOR, residual to org (090:29-32) |
| Payable at close | 090:1456-1472 (`kernel.pay_promoter_commission`) | order `status='refunded'` ⇒ held `basis_zero`; otherwise basis = Σ `unit_price × SURVIVING (non-voided) atoms`, `floor(basis × bps_applied / 10000.0)` |
| Eligible set (original) | 090:1511-1548 | excludes `o.status in ('refunded','cancelled')`; NOT EXISTS over `settlement_line cause='promoter_commission' and cause_ref = a.id` |
| Eligible set (093 slice 10e) | 093:858-930 | adds `'partially_refunded'` to the exclusion; the comment at 093:861-876 states the defect (direct partial refund voids no atoms ⇒ surviving-atom basis unreduced ⇒ FULL commission) and calls the exclusion a deliberate, reversible over-correction; "A pro-rated basis would require an owner ruling … none exists, and 093 invents none" |
| The money constraint | 090:210-213 | `attribution_one_commission_line_ever UNIQUE (cause_ref) WHERE cause='promoter_commission'` |
| Payout mint | 090:1483-1491 | `cause='promoter_commission', cause_ref=attribution.id, hold_state='held', hold_reason_code='unfunded_settlement', held_by NULL`, idempotency `promoter_commission:<attr>:<identity>` |
| Primary/refund arm | 093:275-560 (10b) | in-flight refund ⇒ order deferred WHOLE (093:477-481); `refund_void` only for `succeeded`, capped at face across closes and across causes (093:487-552) |
| Chargeback arm | 093:1077-1215 (10h) | `lost`/`charge_refunded` disputes; headroom = face − Σ succeeded refunds − prior chargebacks; no scope predicate (lands in the org's next close) |
| Close waterfall | 093:591-720 (10d), 094:544-790 | gross/fees/refunds by sign; commission is a FEES-bucket debit; `net<0` ⇒ `record_organization_obligation('settlement_shortfall', −net)` (094:751-776) |
| Refund status rule | 085:565-568, 085:601-604 | `v_full := amount ≥ order.total`; void scope only when delegated or full; order status set to `refunded`/`partially_refunded` AT REFUND CREATION, never reverted |
| Dispute record | 088:758-870 | payout leg holds `pending/submitted` payouts whose `cause_ref` is a settlement id carrying a line for the disputed ORDER; `mark_dispute_state` (088:875) is state-only |
| Payout locks | 085:1668-1705, 093:2564-2680, 095:1014-1150, 093:1743/1786, 095:485-523, 095:676-700 | see §7 |
| Frozen spec | `PHASE_2_PROMOTER_CODES_SPEC.md` §5.2 (:683-691), §6.1-6.3 (:764-820), tests 44/45 (:1424-1425), OD-3/OD-4 (:1470-1471) | "Partial refund ⇒ basis recomputed from the order's surviving, non-voided items ⇒ a smaller single line"; test 45 "Partially refunded ⇒ one line, amount = recomputed basis" |
| Governance | `POST_FREEZE_AMENDMENTS.md` E-138 (:2469), `COMMISSION_FUNDING_SOURCE` (:2482), `COMMISSION_PAYOUT_LIFECYCLE` (:2483), E-132 (:2462), `PROMOTER_COMMISSION_PAYOUT_HOLD` (:2486); `PRIMARY_TICKETING_OWNER_RATIFICATION.md` A4 (:97-110); `PHASE_2_ARCHITECTURE_FREEZE.md` §4 (:73-95) | funding source ruled (Option B); refund/chargeback/cancellation behaviour listed as obligations "to eventually prove", NOT decided; A4 = "nothing in 093 may accidentally release promoter money" |
| Prior evidence | `J4_promoter_reversal.md` §0, §3, §4, §6.1, §8, §11; `G4_PROMOTER_REVERSAL_RULING.md` (DRAFT, unsigned); `H5_promoter_economics.md` §4(b)(c) | case B = 100% under-funding pre-close; four locks; options 1-6; owner question (i)-(iii) |

---

## 2. What I executed, and the numbers

### 2.1 The measured defect (brief §18) — cases A, B, C, D, E, H

Every order: face 10 000, attribution `bps 1000`, `credited 1000`. Settlement is event-scoped, closed by
`platform_admin`, maturity satisfied (session + 7 d elapsed) so the venue payout is minted unheld.

| Case | Refund state at close | Order status | Lines written | net | Commission line | Commission payout | Pro-rata on surviving face (`floor((face − min(face, Σ succeeded)) × bps / 10000)`) |
|---|---|---|---|---|---|---|---|
| **A** | none | `paid` | `primary_sale +10000`, `promoter_commission −1000` | 9 000 | **−1000** | 1 000 `pending/held/unfunded_settlement` | 1 000 |
| **B** | 4 000 `succeeded` (via `refund_primary_order` → voids nothing) | `partially_refunded` | `primary_sale +10000`, `refund_void −4000` | 6 000 | **none** | **none** | **600** |
| **C** | 10 000 `succeeded` (fixture shape — atoms stay `active`) | `refunded` | `primary_sale +10000`, `refund_void −10000` | 0 | none | none | 0 |
| **D1** | 4 000 **`pending`** | `partially_refunded` (set at creation, 085:601-604) | **nothing** — order deferred whole by 10b (093:477-481) | 0 | none | none | — (deferred) |
| **D2** | that refund **`failed`** (buyer got nothing), second settlement on event D | still `partially_refunded` | `primary_sale +10000` | 10 000 | **none — permanently** | none | **1 000** |
| **E** | E1 clean; E2 4 000 `succeeded` | `paid` / `partially_refunded` | `primary_sale +10000 ×2`, `promoter_commission −1000` (E1), `refund_void −4000` | 15 000 | −1000 (E1 only) | 1 000 held (E1) | 1 000 + **600** |
| **H** | 2 × 5 000, direct partial 5 000 `succeeded` (voids nothing; both atoms `active`) | `partially_refunded` | `primary_sale +10000`, `refund_void −5000` | 5 000 | none | none | **500** |

The `settlement.commission` audit row for B, D, H is **absent**: the eligible-set query at 093:905-921
returned no ids, so `pay_promoter_commission` was never called — the exclusion happens BEFORE the
surviving-basis arithmetic, which never runs.

Surviving-ATOM basis (090:1461-1464) vs surviving-FACE-by-refunds, executed on every attribution:

```
 label  | order_status       | face  | refunded_ok | cb_lost | atom_basis | lined_today | surviving_face | prorata
 A      | paid               | 10000 |     0       |    0    |   10000    |   1000      |   10000        |  1000
 B      | partially_refunded | 10000 |  4000       |    0    |   10000    |      0      |    6000        |   600
 C      | refunded           | 10000 | 10000       |    0    |   10000    |      0      |       0        |     0
 D      | partially_refunded | 10000 |     0       |    0    |   10000    |      0      |   10000        |  1000
 E1     | paid               | 10000 |     0       |    0    |   10000    |   1000      |   10000        |  1000
 E2     | partially_refunded | 10000 |  4000       |    0    |   10000    |      0      |    6000        |   600
 F      | refunded (post)    | 10000 | 10000       |    0    |   10000    |   1000      |       0        |     0   ← G4 territory
 G      | paid               | 10000 |     0       | 11000   |   10000    |   1000      |   10000        |  1000 (0 if lost disputes count)  ← G4 territory
 H      | partially_refunded | 10000 |  5000       |    0    |   10000    |      0      |    5000        |   500
```

`atom_basis` is 10 000 on EVERY row, including C (full refund via the fixture shape) and H (direct
partial): the surviving-atom quantity the frozen spec's basis rule reads (§6.1, §6.3) is never reduced by
a direct refund, because 085:565-568 voids atoms only for a delegated or FULL refund, and a full refund on
a post-event order is parked by the freeze anyway. **The frozen basis mechanism (atom survival) and the
shipped refund mechanism (money-only partial) do not meet.** That is the whole defect; 093/10e's
exclusion is a bandage over it.

### 2.2 Idempotency (brief §18 "idempotent across re-close")

- Re-close of A → `noop_replay`, `net_minor 9000`, same payout id.
- A SECOND event-scoped settlement on event A (`ckf-sA2`) closes with **0 lines**; commission lines for
  attr A = 1; commission payouts for attr A = 1. The NOT EXISTS at 093:910 plus
  `attribution_one_commission_line_ever` hold.
- Wall probes (rolled back): a duplicate commission line for A → `23505 attribution_one_commission_line_ever`;
  cause `commission_reversal` → `settlement_line_cause_check`; `UPDATE settlement_line` → `append_only`;
  `UPDATE payout SET amount_minor = 0` → `payout_amount_minor_check`. **BUT** `UPDATE kernel.payout SET
  amount_minor = 600` on the held commission payout is ACCEPTED by the table (only `> 0` is checked; no
  trigger pins the amount) — and a **first** commission line for B (`−600`) inserted by hand into a
  later settlement is ACCEPTED (the partial unique stops a second line, not a first). Both matter for
  the options in §4.

### 2.3 Conservation (brief §20) — cases F (refund after payout) and G (chargeback after payout)

Both: close → `primary_sale +10000`, `promoter_commission −1000`, net 9 000, org payout minted
`pending/none`; forced `submitted → paid` as table owner (`tr_kfF` / `tr_kfG`, `destination_ref acct_kf1`)
to stand in for the executor.

**F — full refund 10 000 `succeeded` after payout, then next close (`ckf-sF2`):**

```
lines F2      : refund_void −10000           (capped at face; the 1 000 buyer fee is not charged to the venue)
header F2     : gross 0, fees 0, refunds 10000, net −10000
obligation    : settlement_shortfall origin=F2 amount 10000 outstanding        (094:751-776)
unbooked_refund_exposure(F) : 10000 before F2, 10000 AFTER F2  (095 E-6: a negative-net header discharges nothing)
commission payout F : 1000 pending / held / unfunded_settlement — byte-identical
org payout F        : 9000 paid — untouched
```

Tabulated:

| Party | Fact | Amount |
|---|---|---|
| Buyer paid | face + fee | 11 000 |
| Venue received | org payout | **9 000** |
| Platform retained at close (commission funded, held) | fees bucket | 1 000 |
| Buyer refunded (face) | `refund_void`, capped | 10 000 |
| Platform fee slice | the 1 000 buyer fee — if the refund was issued against `payments.total` (11 000) the platform loses it too; the fixture refunded 10 000 so it is retained | 0 / 1 000 |
| **Organization obligation booked** | `settlement_shortfall = −net` | **10 000** |
| Venue debt the arithmetic supports | what it received | **9 000** |
| Promoter held claim | commission payout | 1 000 (still standing) |
| Platform cash | +11 000 − 9 000 − 10 000 | −8 000 (−9 000 if the fee was refunded) |

**The shortfall record overstates the venue's debt by exactly the 1 000 the platform retained as the
funded-but-held commission.** 094 books `−net`, and `net` = `−10000` because F2 has no offsetting
credit and does not know that 1 000 of F's face never reached the venue. The 1 000 is on the books TWICE:
once as the org's obligation and once as the promoter's held payout. Nothing double-collects today (no
recovery path runs and no commission can be paid), so this is an accounting overstatement, not a cash
loss — but it is precisely the "does the chargeback arm overstate by the retained commission" question
in the brief, and the answer is **yes, by construction, for BOTH arms**.

**G — open dispute (`needs_response`, 11 000) after payout, then `lost`, then next close (`ckf-sG2`):**

```
record_dispute_native : atoms_held 1, payouts_held 0   (org payout is 'paid' → out of the leg; commission payout not reached — E-132)
mark_dispute_state    : lost
lines G2              : chargeback −10000   (least(11000, face 10000 − refunds 0 − prior 0)) — the fee is NOT charged to the venue
header G2             : net −10000
obligation            : settlement_shortfall origin=G2 amount 10000 outstanding
commission payout G   : 1000 held unfunded_settlement — byte-identical
```

Same overstatement: obligation 10 000 vs venue received 9 000. Chargeback fee (Stripe's dispute fee)
is not modelled anywhere; the buyer-side 1 000 is lost to the platform when Stripe debits 11 000.

No path in F or G marked a commission payout paid, changed its hold, or created a promoter destination
(`destination_ref` NULL on every commission payout; 0 transfer refs — final census §2.5).

### 2.4 Dispute-hold and lock probes (rolled back)

On event A (org payout `pending/none`; commission payout released first with `kernel.release_payout` so
the leg had a chance to reach it):

```
record_dispute_native('dp_kf_A', … 'needs_response')  → payouts_held 1
  settlement payout A     : pending / held / dispute / held_by NULL
  commission payout A     : pending / none            ← NOT reached (cause_ref = attribution id; 088:826-829 matches settlement ids only)
retry_held_payout(org1, settle A) as org_finance+aal2 → 'not_a_maturity_hold — hold_reason_code=dispute is released only by kernel.release_payout'
mark_dispute_state('won')                            → dispute won; settlement payout A STILL held/dispute
settlement_payout_maturity(A) after 'won'            → hold_reason NULL (nothing machine-side says hold any more)
```

So a `dispute` hold is a human-only hold: `retry_held_payout` refuses it (095:458-475 lists eight
maturity codes; `dispute` is not one), `mark_dispute_state` never releases (088:875 "state only"),
`resolve_dispute_native` is parked fail-closed (088:913), and only `kernel.release_payout`
(`platform_risk`/`platform_admin`, 085:807) clears it — for a dispute the venue WON. Venue-side, but it
answers the brief's "who can release it": nobody but Control-5, and the same verb clears an
`unfunded_settlement` hold with no reason comparison (E-138 (i)).

Lock probes on commission payout A after `release_payout`:

| Probe | Result |
|---|---|
| `mark_payout_transfer_state(po,'paid',…)` from `pending` | `payout_state_backwards (pending → paid)` (085:1698-1703) |
| `claim_payouts_for_execution(50,900)` | `payouts: []` (093:2660-2666 `cause='settlement' and payee_kind='organization' and status='submitted'`) |
| `get_payout_execution_context(po)` | `refusal_code: cause_not_settlement`, `execution_eligible: false` (095:1076) |
| force `status='submitted', destination_ref='acct_kfP'` as table owner → claim | still `[]` |
| … → context | still `cause_not_settlement` |
| … → **`mark_payout_transfer_state(po,'paid','tr_kf_probe')`** | **`ok, new_status: paid`** — the state-sync verb is cause-agnostic (085:1668-1705: hold, replay, forward-only, ref — no cause check) |
| `hold_payout_transfer_reversed(po, 'tr_kfprobe', …)` | `not an organization settlement payout` (095:699) |
| `hold_payout(po,'risk_review')` on an already-held commission payout | `noop_replay`, **0** `payout.hold` audit rows (085:790-792) — E-138 (i) confirmed |

### 2.5 Final census of `snatchit_rehears_f`

```
promoter_commission | pending | held | unfunded_settlement | 4 | 4000 | 0 transfer refs | 0 destinations
settlement          | paid    | none |                     | 2 | 18000 (F, G — forced as owner)
settlement          | pending | none |                     | 5 | 45000
organization_obligation: settlement_shortfall 10000 (F2), settlement_shortfall 10000 (G2)
```

Attributions never lined: B, C, D, E2, H (five of nine). Lined: A, E1, F, G.

---

## 3. Findings, ranked

**P0 — none.** No path executed here pays a promoter through a contracted verb; A4 holds. (The one
"paid" I produced needed table-owner forcing of `status='submitted'` — §2.4 — which no client role can do.)

**P1-1 — Pre-close partial refund forfeits 100% of the earned commission, and the forfeiture is
permanent.** Cases B (0 vs 600), E2 (0 vs 600), H (0 vs 500). Evidence: 093:920 `o.status not in
('refunded','partially_refunded','cancelled')`; no verb ever moves an order back to `paid`
(085:601-604 writes the status forward only). J4 case B measured it; what is new here is that the
audit trail is silent (no `settlement.commission` row, no `held: basis_zero` entry) — an operator
cannot tell a deliberately excluded attribution from one that never existed.

**P1-2 — A refund that FAILS still forfeits the commission forever.** Case D: 4 000 refund `pending` at
close ⇒ status `partially_refunded` at creation (085:601-604) ⇒ 10e excludes; refund then `failed`
(buyer got nothing, 085:86-88) ⇒ 10b correctly credits the venue 10 000 in the next close (093:307-322,
"failed … books NO debit") ⇒ the promoter's attribution is still excluded (`lined_today 0`,
`surviving_face 10000`). The venue is paid face; the promoter earns 0 on an order that was never
refunded. The order-status key is the wrong key: 10b reads `kernel.refund` terminal facts; 10e reads
a status written at refund CREATION. The same mismatch applies to a full refund that fails (status
`refunded`, refund `failed`).

**P1-3 — The post-payout shortfall overstates the venue's debt by the retained commission.** F2 and G2
both book `settlement_shortfall 10000` (094:751-776 books `−net`); the venue received 9 000 and the
platform retained 1 000 as the held commission. The 1 000 is recorded twice (org obligation + promoter
held payout). G5 says the obligation is THE durable record; today that record is wrong by the funded
commission on every reversed attributed order. Not a cash loss while nothing collects and nothing pays,
but any deterministic recovery built on `organization_obligation.amount_minor` (G5 direction) will
over-collect from the venue by the commission unless the promoter's held payout is extinguished first
and the obligation is booked net of it (see §4 option C3).

**P1-4 — The `dispute` hold on a venue payout survives a WON dispute and only Control-5 can clear it.**
§2.4. Venue-side, outside my brief, recorded because it answers "who can release it" for the commission
case too and because `record_dispute_native`'s comment (088:753-757 "settlement AND commission payouts
alike") is false — the leg reaches no commission payout (E-132 confirmed by execution).

**P2-1 — `mark_payout_transfer_state` is cause-agnostic.** With `status='submitted'` forced as table
owner, `submitted → paid` on a commission payout is accepted (§2.4). Every contracted advance to
`submitted` is `cause='settlement'` only (093:1786, 095:523) so this is unreachable by clients, but the
"four locks" are three-and-a-half: the fourth (state machine) refuses only because nothing advances the
row, not because it knows the cause. J4 §6.1 stated "the context still refused" and left the verb
untested.

**P2-2 — `hold_payout` on a `held` commission payout is a silent no-op** (0 audit rows) — E-138 (i)
already records this as an obligation; confirmed.

**P2-3 — The frozen basis definition cannot be computed from the shipped refund mechanics.**
PROMO §6.1 defines basis over "surviving items"; §5.2 and test 45 REQUIRE a reduced single line on a
partial refund; 085's direct partial refund is "money only (voids nothing)" (085:563-564), so surviving
atoms ≠ surviving revenue on every partial refund and on every post-event full refund (freeze).
`atom_basis = 10000` on all nine rows.

---

## 4. What 10e actually keys on, and the pro-rata design

### 4.1 How "refunded" is decided today (brief item 3)

- 10e (093:920): **order status only** — `o.status not in ('refunded','partially_refunded','cancelled')`.
  It reads `kernel.refund` nowhere and `settlement_line` only for its own cause.
- `pay_promoter_commission` (090:1456-1472): `v_o.status = 'refunded'` ⇒ `basis_zero`; then the
  surviving-atom lateral; `payable ≤ 0` ⇒ `basis_zero`. Neither arm reads refund amounts.
- The status is written at refund CREATION (085:601-604), before Stripe has accepted anything, and is
  never reverted on `failed`.
- 10b (093:478-481, 525-530) reads `kernel.refund` directly: defers on `pending/submitted`, debits
  `succeeded` only, caps at face across ALL prior `refund_void`/`chargeback` lines of the order.
- 10h (093:1173-1178) reads `kernel.refund` `succeeded` sums directly ("so it is correct whether or not
  10b has lined those refunds yet, including in this very close where neither cause can see the
  other's uncommitted rows").

So the surviving-face quantity a pro-rata rule can read WITHOUT depending on same-close candidate
lines is exactly 10h's operand: `least(Σ kernel.refund.amount_minor where status='succeeded', face)`,
optionally plus `least(Σ dispute_native.amount_minor where status in ('lost','charge_refunded'), remaining
headroom)`. Reading the same-close candidate lines is NOT safe: the three seams are unioned inside one
`FOR` cursor (093:680-682) and each inserts as it iterates; the commission seam cannot see 10b's rows
of the same close.

No double counting with a LATER settlement is possible for a pre-close rule: the commission line is
written once ever (index), from the refunds that are `succeeded` at that close; a refund that succeeds
after that close is by definition post-close (G4) and never re-enters 10e because the NOT EXISTS at
093:910 already excludes the attribution.

### 4.2 The rule, precisely

```
eligible(a)  :=  a.org/scope/currency/payee/deny filters as today (093:905-921 minus the status clause)
             AND NOT EXISTS commission line for a.id
             AND NOT EXISTS kernel.refund r ON a's payment WITH r.status IN ('pending','submitted')   -- DEFER, mirror 093:478-481
             AND o.status <> 'cancelled'
refunded(a)  :=  least(face, Σ r.amount_minor WHERE r.status = 'succeeded')                            -- 10h's operand, 093:1173-1176
reversed(a)  :=  refunded(a) [+ least(face − refunded(a), Σ d.amount_minor WHERE d.status IN ('lost','charge_refunded'))]   -- OPTION, see §4.4
surviving(a) :=  face − reversed(a)                                                                     -- face = order.total_minor = a.basis_minor (082:424-426)
payable(a)   :=  bps:  floor(surviving(a) × a.commission_bps_applied / 10000.0)                         -- FLOOR, 090:1119 / 090:1466 / PROMO §6.2
                 flat: a.commission_flat_minor_applied × surviving_qty(a)                                -- surviving_qty UNDEFINED for a money-only partial refund; see §5
line         :=  −payable(a)  iff payable(a) > 0  (payable = 0 ⇒ held 'basis_zero', no line, re-eligible — as today 090:1468-1470)
```

Properties, each checked against the executed rows:
- `payable ≤ credited_amount_minor` always (`surviving ≤ face`, same floor) and `payable ≤ surviving
  revenue` (bps ≤ 10000). B → 600, C → 0 (held basis_zero, no line, as today), D2 → 1000, E → 1000 + 600,
  H → 500. Sum over the fixture: 4 700 funded vs 4 000 today vs 5 600 credited.
- Integer-exact: `floor(bigint × int / 10000.0)::bigint` is what 090 already does; residual stays with
  the org (090:31-32). Round-half-even would be a NEW convention and would contradict PROMO §6.2
  ("Rounding: floor, always"); do not introduce it. `is_rounding_bearer` (087) is untouched — the
  commission never claims the residual.
- One line per attribution ever: unchanged (index + NOT EXISTS).
- Idempotent across re-close: unchanged (noop_replay before the seams run, 093:672-676).
- No double funding: the line is −payable, the payout is +payable, same number, one each.
- Post-close refunds not re-funded: unchanged — the attribution is out of the eligible set forever after
  its line exists; that residual is G4's and stays HELD.
- No new cause, no new column, no DDL. Body-only replacement of `kernel.settlement_commission_lines`
  (frozen signature) and of the basis block in `kernel.pay_promoter_commission` (090:1456-1466). Both
  are 093/090 bytes ⇒ a NEW migration (096+), because 093 is immutable.

### 4.3 Where it must NOT be computed

- Not in `pay_promoter_commission`'s atom lateral alone (the atoms are unreduced — §2.1).
- Not from same-close candidate lines (§4.1).
- Not at RELEASE time as the ONLY mechanism (J4's "2-at-release"): that leaves the settlement line at
  the full funded amount and the venue's distributable reduced by money the promoter never earns —
  case B's venue would be paid 6 000 − 1 000 = 5 000 instead of 5 400. Pre-close, the line itself must
  be right; release-time recomputation is for the post-close (G4) residual only.

### 4.4 Should a LOST dispute count as reversed at the funding close?

Argument for: 10b/10h treat refunds and lost chargebacks as one pool of headroom against the order's
face (093:384-390); a commission on face that a chargeback has already removed from the venue's
distributable in the same close is the same over-funding as case B. Argument against: a dispute
pre-close is rare (settle-then-pay), and `charge_refunded` overlaps a refund (double counting is
avoided only with the headroom cap, as 10h does). Smallest honest: include lost/charge_refunded
disputes with 10h's cap (`least(disputed, face − refunded − prior_cb)`), because the alternative funds
a commission on revenue the venue was debited for in the same close. Owner-visible as a one-line
choice; default = include.

### 4.5 What about the flat_per_ticket kind?

`surviving_qty` has no definition for a money-only partial refund (a 5 000 refund on 2 × 5 000 is
one ticket's worth of money but no ticket is voided). Options: (a) `floor(surviving_face / unit_price)`
per item (integer, ≤ qty, exact when the refund is a whole number of tickets); (b) pro-rate the flat
amount: `floor(flat × qty × surviving_face / face)`; (c) exclude flat promoters from pro-rata and keep
10e's forfeiture for them only. (a) is the closest to the frozen "surviving items" wording; (b) is
smoother; (c) is dishonest by omission. This is the one place the rule needs an owner word.

---

## 5. Does pro-rata funding need owner policy beyond the direction given?

**Both sides, honestly.**

*It is already decided (implement as a correction):* PROMO §5.2 row 2 — "Partial refund ⇒ basis
recomputed from the order's surviving, non-voided items ⇒ a smaller single line" — and test 45
("Partially refunded ⇒ one line, amount = recomputed basis") are FROZEN text (`phase2-architecture-v2`).
§6.3's payable rule says `recompute(basis over surviving items, snapshotted terms)`. The INTENT
"promoter earns on what survived, pre-close" is therefore frozen, not open. 093/10e's total exclusion
is the deviation: its own comment (093:861-876) calls it an over-correction taken because "a pro-rated
basis would require an owner ruling on how a partial refund maps onto ticket atoms". E-138 fixes the
FUNDING SOURCE (Option B) and lists "refund behaviour" as an obligation to prove, not as an open policy.
G4 (unsigned) says do not treat reversed revenue as automatically leaving full commission earned —
pro-rata pre-close is the reading of that direction that is also the frozen spec's.

*It is not decided (amendment required):* the frozen BASIS is defined over ATOMS ("surviving,
non-voided items", §6.1; `VERIFIED: D2 — a refunded ticket goes to voided`, §5.2 :689-691). The shipped
refund verb does not void on a direct partial refund (085:563-564) and cannot void a post-event full
refund (freeze). Reading "surviving" as FACE MINUS SETTLED REFUND SHARE is a change of the basis
definition from a custody fact to a money fact. Under FREEZE §4 that is a normative change to §6.1
and §5.2's "VERIFIED D2" sentence ⇒ **a `PFA-<n>` entry with owner signature = YES**. It is not a
"correction the frozen corpus already uniquely determines" because the corpus determines the atom
reading and the atom reading produces the wrong number (10 000 on every row, §2.1).

**Verdict: the pre-close pro-rata rule is a POST-FREEZE AMENDMENT of PROMO §6.1/§5.2 (basis =
face − settled refund share, capped; disputes per §4.4; flat kind per §4.5), recorded as PFA, owner
signature required — even though its outcome (a reduced single line) is what the frozen spec already
asks for.** Implementing it without the PFA would be the "silent edit around a conflict" §4 forbids;
implementing 10e's exclusion was already such a deviation and is recorded only in a migration comment
(093:861-876), not in `POST_FREEZE_AMENDMENTS.md` — worth filing retroactively either way.

What this amendment does NOT touch: G4 (post-close reversal of a funded commission stays HELD, no
release, no reduction); A4 (nothing releases promoter money — the change only alters the AMOUNT minted
under the same hold); E-138 Option B (funding source unchanged); the four locks (§7).

---

## 6. Options

| # | Option | What it does to B/D/E/H | Honest cost | Dishonest if |
|---|---|---|---|---|
| **O0** | Leave 10e as authored | B 0, D 0 forever, E2 0, H 0 | zero | described as "conservative": it is a permanent forfeiture with no audit trace (P1-1) and it forfeits on FAILED refunds (P1-2) |
| **O1** | Fix the KEY only: replace the status clause with the `kernel.refund` terminal-fact predicates (defer in-flight; exclude only when `least(face, Σ succeeded) = face`), keep the full-or-nothing amount | B 0, D2 **1000**, E2 0, H 0 | body-only `settlement_commission_lines` in 096; no basis change; arguably a correction the corpus uniquely determines (10b already reads the same facts) | presented as the pro-rata fix — it repairs P1-2 only |
| **O2** | O1 + pro-rata basis by settled refund share (§4.2), disputes per §4.4, flat kind per §4.5 | B **600**, D2 1000, E2 **600**, H **500** | 096 body-only on two 090/093 functions; PFA on PROMO §6.1/§5.2; one pgTAP file; audit `held: basis_zero` already covers the 0 case | shipped without the PFA, or with round-half-even, or reading same-close lines |
| **O3** | O2 + book post-close shortfalls NET of the funded-and-held commission (`−net − Σ held commission on the reversed orders`) so `organization_obligation` = what the venue received (P1-3) | F2/G2 obligation **9 000** | needs a rule for the held 1 000 (extinguish? keep held?) — that IS G4 (iii); DDL-free but policy-bearing | done before G4 is signed |
| **O4** | Retroactive adjustment close for already-excluded attributions (B/E2/H shape in prod) | lines them at pro-rata in a later settlement | storable today (§2.2: a first line for B is accepted); no verb exists; would need an owner-approved one-shot | done by hand INSERT |
| **O5** | Release-time pro-rata only (J4 2-at-release), leave the funding line at full | line −1000 for B, release 600 | zero DDL | the venue's distributable is wrong by the difference (§4.3) — this is G4's tool, not the pre-close fix |

**Smallest honest design: O2**, with O3 explicitly deferred to G4 and O4 explicitly deferred as
"not needed until a real partially-refunded attributed order exists in prod" (promoter engine is
DARK in prod; ledger 107 = through 092; no `promoter_commission` line exists in prod — unverified
here, per brief no prod access; state it as an assumption to confirm).

What O2 changes, byte-scoped:
1. `kernel.settlement_commission_lines(uuid)` — body only, frozen signature: status clause → the
   §4.2 `eligible` predicates.
2. `kernel.pay_promoter_commission(uuid, uuid[], text)` — body only: the `v_o.status = 'refunded'`
   arm and the atom lateral → `surviving = face − reversed` per §4.2; everything else (holds, review
   lock, payout mint, audit, BE emits) verbatim.
3. A `PFA-<n>` entry: FROZEN RULE = PROMO §6.1 + §5.2 "VERIFIED D2"; CONFLICT = 085:563-568 + freeze;
   proof = §2.1 table (`atom_basis 10000` on nine rows).
4. pgTAP: B → −600 line and 600 held payout; D1 → nothing; D2 → −1000; E → −1000/−600; H → −500;
   C → no line, `basis_zero` audit; re-close noop; second settlement 0 lines; flat kind per the chosen
   §4.5 rule.

---

## 7. The locks that keep promoter payout DARK (brief item 7), with file:line

| # | Lock | file:line | Executed |
|---|---|---|---|
| 1 | Minted `held/unfunded_settlement`; `mark_payout_transfer_state` refuses any `hold_state <> 'none'` | 090:1483-1491; 085:1689-1691 | yes (§2.4 needed `release_payout` first) |
| 2 | State machine: `submitted → paid|failed`, `paid → reversed` only; a commission payout is `pending` and nothing advances it | 085:1698-1703; advancers `request_org_payout` 093:1786 and `retry_held_payout` 095:523 are `cause='settlement'` | yes: `payout_state_backwards (pending → paid)` |
| 3 | Executor claim: `cause='settlement' and payee_kind='organization' and status='submitted' and hold_state='none' and stripe_transfer_ref is null and destination_ref is not null` | 093:2660-2666 | yes: `[]` even after forced `submitted` |
| 4 | Execution context: `cause <> 'settlement' ⇒ cause_not_settlement`, first predicate | 095:1076 (093:2351 original) | yes: `refusal_code cause_not_settlement`, `execution_eligible false` |
| (5) | Reversal verb refuses non-settlement causes | 095:699 | yes: `not an organization settlement payout` |
| (–) | Not a lock: `mark_payout_transfer_state` is cause-agnostic — forced `submitted` ⇒ `paid` accepted | 085:1668-1705 | yes (§2.4) — P2-1 |

Dispute-path interaction: `record_dispute_native` (088:826-829) holds `pending/submitted` payouts whose
`cause_ref` is a settlement id with a line for the disputed ORDER id — the commission payout's
`cause_ref` is the attribution id (E-132) so it is never touched (executed: `payouts_held 1`, the org
payout only). The 088:753-757 comment claiming "settlement AND commission payouts alike" is wrong.
`mark_dispute_state` and the parked `resolve_dispute_native` touch no payout. So no dispute path
touches locks 1-4. The `PROMOTER_COMMISSION_PAYOUT_HOLD` obligation (:2486) is still open: a dispute
on an attributed order does not add a `dispute` hold on the commission payout — today that is moot
(the `unfunded_settlement` hold is stronger), but the moment E-138's release condition is written,
`release_payout` (no reason argument, 085:807-830) would clear the ONE hold and a disputed sale's
commission would be releasable with nothing else standing in the way except locks 2-4. A release
condition for commission payouts must therefore re-derive "no open/lost dispute on the attributed
order" itself rather than rely on a hold that is never placed.

If the answer to "is holding a commission payout under `dispute` fine" were yes, who releases it:
`retry_held_payout` refuses (`dispute` ∉ maturity codes, 095:458-475); only `release_payout`
(platform_risk/platform_admin) — and it clears every reason at once (E-138 (i)).

---

## 8. Open questions for the orchestrator / owner

1. **Basis amendment (PFA):** confirm that "surviving revenue = face − settled refund share (capped),
   read from `kernel.refund` terminal facts" replaces PROMO §6.1's atom reading for the funding
   computation. Signature required (§5). Without it, only O1 (the key fix, P1-2) is a corpus-determined
   correction.
2. **Disputes at the funding close (§4.4):** include `lost`/`charge_refunded` in `reversed`, with 10h's
   cap — default yes?
3. **Flat-per-ticket surviving quantity (§4.5):** (a) `floor(surviving_face / unit_price)`,
   (b) proportional, or (c) exclude. Recommend (a).
4. **P1-3 / G5 interaction:** should `settlement_shortfall` be booked net of funded-and-held commission
   on the reversed orders (O3)? This is G4 (iii) ("does a reduced commission return to the venue or stay
   with the platform") seen from the obligation side; recommend deferring to the G4 signature and
   recording the overstatement in the G5 register now.
5. **Retroactive relining (O4):** is there any attributed, partially refunded order in prod today?
   (Promoter engine dark; expected none — unverified.) If none, O4 is moot.
6. **P2-1:** should `mark_payout_transfer_state` (085, frozen, service_role only) gain a
   `cause='settlement'` guard in 096 as a body-only hardening, or is "no advancer exists" sufficient?
   Recommend the guard: it is the only lock of the four that depends on absence rather than refusal.
7. **P1-4:** a WON dispute leaves the venue payout under a `dispute` hold that only Control-5 clears —
   route to the dispute-train owner (not this report's scope).
8. **10e's exclusion is recorded only in a migration comment** (093:861-876), not in
   `POST_FREEZE_AMENDMENTS.md`; whichever option is chosen, file the deviation from PROMO §5.2/test 45.

---

## 9. Reproduction

```
scripts/rehearsal_reset.sh snatchit_rehears_f
PGUSER=postgres psql -d snatchit_rehears_f -f supabase/tests/000_helpers.sql   # commits the tap schema (must run AS postgres: guard_listing_insert_columns, 072:178)
PGUSER=postgres psql -d snatchit_rehears_f -f <scratchpad>/kf_setup.sql        # one transaction; seed_core guarded for replay
PGUSER=postgres psql -d snatchit_rehears_f -f <scratchpad>/kf_cases.sql        # A, B, C, D, E, H, idempotency (COMMIT)
PGUSER=postgres psql -d snatchit_rehears_f -f <scratchpad>/kf_conserv.sql      # F, G (COMMIT)
PGUSER=postgres psql -d snatchit_rehears_f -f <scratchpad>/kf_probes2.sql      # locks, dispute hold, walls (ROLLBACK)
```

Traps met: `tap.login` is `set_config(.., is_local)` — a script must be ONE transaction;
`refund_primary_order` is service_role-only, call it under `tap.set_claims(admin)` without switching
role; a 30-day-old session is transfer-frozen, so a FULL refund via the verb raises `frozen:` — use the
159 fixture shape for C and F; psql `\gset` lower-cases the variable name.
