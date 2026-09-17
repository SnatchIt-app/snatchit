# KC — Chargeback accounting: settlement chain and conservation (investigator C)

Repo `/Users/josetascon/snatchit-consol` @ `609e0f4`. Rehearsal DB `snatchit_rehears_c` (full 110-migration replay, GATE-2 baseline matched: tables=27 functions=70 policies=37 triggers=26). Nothing outside this file was written in the repo. Every scenario below ran inside `BEGIN … ROLLBACK`; the only committed objects are `tap` (from `supabase/tests/000_helpers.sql`) and my helper schema `kc`, both in the rehearsal DB only.

Status vocabulary: **[X]** executed on the DB, numbers copied from output; **[R]** read from source; **[U]** unverified.

---

## 1. What I inspected (file:line)

| Object | Where | Fact relied on |
|---|---|---|
| `kernel.dispute_native` | 088:189-215 | `amount_minor >= 0`; terminal set `{won,lost,warning_closed,charge_refunded}`; `UNIQUE(stripe_dispute_ref)` (088:207) — the unique is per Stripe dispute, **not** per payment |
| `kernel.record_dispute_native` | 088:758-871 | freezes only when recorded OPEN (088:804 `v_open := p_status not in (...)`); payout leg 088:839-846: `po.status in ('pending','submitted') and po.hold_state in ('none','probation_hold') and (po.cause_ref = sale_id or po.cause_ref in (select sl.settlement_id from venue.settlement_line sl where sl.cause_ref = coalesce(v_pn.order_id, v_pn.sale_id)))` |
| `kernel.mark_dispute_state` | 088:875-905 | state only; terminal absorbing; **releases nothing** |
| chargeback arm (re-created) | 093:1136-1219 | `cb_candidate` 093:1169-1190: join `venue."order" o on o.order_id = pn.order_id and o.org_id = s.org_id` (093:1187) — **org-scoped, no venue/event/period predicate**; headroom `face − refund_exposure − prior_cb` (093:1196-1198); window `partition by order_id order by created_at, dispute_id`; `debit_minor > 0` else no line (093:1207) |
| refund arm + order deferral | 093:435-560 | `scoped_order` defers an order WHOLE while a `kernel.refund` is `pending/submitted` (093:471-479); `refund_void` only for `succeeded` (093:526); `order_prior_debit` counts chargeback lines (093:492-520) |
| `kernel.close_settlement` (094 body) | 094:552-800 | shortfall branch `elsif v_net < 0` 094:753 → `record_organization_obligation(... 'settlement_shortfall', settlement_id, -v_net ...)` 094:771 |
| `kernel.record_organization_obligation` | 094:320-412 | `settlement_shortfall` amount re-derived from header (094:352-375); `unlined_reversal` guard 094:387-388 = `not exists settlement_line where cause in ('chargeback','refund_void') and cause_ref = p_origin_ref` — **the amount is caller-chosen** (no derivation, no face cap) |
| origin semantics | 094:117-131, 094:181-200; J3 §3 (docs/phase2/_impl/J3_receivable_architecture.md:91-115), J3 §5.2 (:250-268), J7 :120-140, :270-313 | `unlined_reversal` = "dormant-org case, no settlement is ever opened"; "reachable only by an explicit operator call" |
| `venue.open_settlement` gate | 087:237-239 | `has_venue_role(venue_finance) OR has_org_role(org_finance, org_owner)` — no platform arm **[X confirmed: admin_user refused, §2.U]** |
| `kernel.settlement_payout_maturity` | 093:2076-2170 | `dispute_open` counts only the four OPEN statuses (093:2130); a `lost` dispute holds nothing |
| `kernel.get_payout_execution_context` | 093:2266-2400 (095:1014 re-created) | refusal chain 093:2346-2382; staleness operand = `kernel.settlement_unbooked_refund_exposure` (095:963-997) which reads **only `kernel.refund`**, never `dispute_native` |
| `kernel.mark_payout_transfer_state` | 085:1668-1735 | refuses `hold_state <> 'none'`; `submitted→paid|failed`, `paid→reversed`; `paid` calls `venue.on_payout_settled` (087:360) |
| `kernel.get_refund_execution_context` | 093:1038-1069 | `disputed_minor` = Σ lost/charge_refunded (093:1061); executor Σ-guard `prior + disputed + this > total ⇒ refuse` (refund-execute/executor.ts:276-285) |
| `catalog.cancel_event` | 088:1612-1790 | refund amount = Σ voided item prices capped by `total − (Σ non-failed refunds + Σ lost/charge_refunded disputes)` (088:1659-1663) |
| `kernel.pay_promoter_commission` / `settlement_commission_lines` | 090:1401-1509 / 093:889 | commission payout minted `held/unfunded_settlement`, `cause_ref = attribution.id` |
| `kernel.payout` | 085:111-150 | `amount_minor > 0` (a negative net mints nothing) |
| TS callers | `grep -rn record_organization_obligation\|unlined_reversal supabase/functions/` → **0 hits**; stripe-webhook has no `dispute_native` reference (brief §facts confirmed) |

---

## 2. What I executed, and the results

### 2.0 Harness (exact SQL, committed once in the rehearsal DB)

Fixture = the `finalize_primary_order` triple, byte-shape of `supabase/tests/159` `tap._ord159`, plus minted atoms so `record_dispute_native`'s atom leg and `cancel_event` have something real to act on. `payout.settlement_maturity_interval` set to `"0 hours"` and sessions 30 days in the past so the mint is **not** held (the maturity clock is not the subject). Venue payout to `paid` = owner `UPDATE … status='submitted', hold_state='none'` followed by the real writer `kernel.mark_payout_transfer_state(id,'paid','tr_…',null,key)`. Disputes go through the real writers: `kernel.record_dispute_native('dp_kc_<t>','ch_kc_<t>',pi,amount,'usd','fraudulent',<status>,now()+7d,key)` then `kernel.mark_dispute_state('dp_kc_<t>','lost',key)`.

```sql
-- kc.mk_order(session, org, face, fee, tag)
insert into venue."order" (order_id, buyer_id, event_session_id, org_id, status, source, total_minor, currency, command_idempotency_key)
values (v_ord, tap.buyer(), p_session, p_org, 'paid', 'app', p_face, 'USD', 'kc-ord-'||p_tag);
insert into public.payments (id, buyer_id, amount, buyer_fee, seller_fee, total, stripe_payment_intent_id, status, mode, paid_at)
values (v_pay, tap.buyer(), p_face, p_fee, 0, p_face + p_fee, 'pi_kc_'||p_tag, 'succeeded', 'native_primary', now());
insert into kernel.payment_native (payment_id, order_id, amount_minor, currency) values (v_pay, v_ord, p_face + p_fee, 'USD');
-- kc.mk_atoms: venue.order_item (qty, unit) + kernel.tickets (issued, owner=buyer) + ticket_ownership_log (seq 1, cause 'issue', cause_ref = order_item.id)
-- kc.open  = tap.login(owner) → venue.open_settlement(org, venue, event|null, period, key)
-- kc.close = tap.login(admin_user) → kernel.close_settlement(sid, key)
-- kc.pay   = update kernel.payout set hold_state='none', hold_reason_code=null, held_at=null, held_by=null, status='submitted' where cause='settlement' and cause_ref=sid;
--            kernel.mark_payout_transfer_state(payout_id, 'paid', 'tr_kc…', null, key)
-- kc.conserve(org, tag): payments.total / order.total_minor / buyer_fee / Σ succeeded refunds / Σ pending-submitted refunds /
--            Σ lost+charge_refunded dispute amount / Σ settlement payouts status=paid / Σ pending-submitted / Σ commission payouts unpaid /
--            Σ primary_sale, refund_void, chargeback, promoter_commission lines / kernel.org_outstanding_obligation_minor(org)
```
Full scripts: `/private/tmp/claude-501/-Users-josetascon-snatchit/226e0974-71a3-4e30-897f-20b2cfa4dc90/scratchpad/kc/{00_setup,A_*,B_*,C_*,C4_*,D_*,E_*,F_*,G_*,H_*,I_*,U_*,X_*}.sql` with `.out` beside each.

Conservation identity used throughout (all in minor units, per payment):
`platform_cash = collected − refunded − chargeback − venue_paid − commission_paid`; the ledger must explain that number as `platform_fee_retained − platform_fee_lost + obligation_receivable − unpaid_liabilities(pending payouts, held commissions)`.

### 2.a Full-face lost dispute after venue paid — [X] CONSERVES, correct
23,000 charged = 19,000 face + 4,000 fee; S1 `primary_sale +19,000` → net 19,000 → payout paid; dispute recorded `needs_response` (atoms_held=2, payouts_held=0 — the payout is already `paid`) → `lost`; S2:

| | |
|---|---|
| S2 lines | `chargeback −19,000` (capped at face; fee slice 4,000 not charged to venue — A5) |
| S2 header | `gross=0 fees=0 refunds=19000 net=−19000`, `payout_ids=[]` |
| obligation | `settlement_shortfall 19,000 outstanding, origin_ref = S2` |
| cash | 23,000 − 0 − 23,000 − 19,000 = **−19,000** |
| ledger | receivable 19,000 → platform position 0; the 4,000 fee is **platform loss** (A5), Stripe's dispute fee is unmodelled |
| `unlined_reversal` on this dispute | **refused** (`already lined`) — guard works when a line exists |

### 2.b Partial dispute 5,000 after venue paid — [X] CONSERVES, correct
`chargeback −5,000`, net −5,000, `settlement_shortfall 5,000`. Cash 23,000 − 5,000 − 19,000 = −1,000; ledger: fee retained 4,000 − receivable… → platform position −1,000 + 5,000 receivable = +4,000 = the fee. Correct.

### 2.c Lost dispute before payout — three sub-cases

**c-i: dispute lost before any close** [X]: first close lines `primary_sale +19,000` **and** `chargeback −19,000` → net 0, no payout, **no obligation**. Cash −4,000 (fee lost). Correct and conserving.

**c-ii: closed, payout PENDING (hold none), dispute recorded OPEN** [X]:
- cause_ref matching operand: `lines_with_order_ref=1, payouts_reachable=1` → `record_dispute_native` returned `payouts_held: 1`; payout became `pending | held | dispute`. **The freeze fires for a primary order** (the `primary_sale` line's `cause_ref` IS the order_id, which 088:844 matches).
- after `mark_dispute_state → lost`: hold persists (PFA-31). Next close: `chargeback −19,000`, net −19,000, `settlement_shortfall 19,000` booked.
- **Result: obligation 19,000 outstanding AND payout 19,000 pending/held for the same money; venue paid 0.** `settlement_payout_maturity(S1)` → hold_reason `null` (a `lost` dispute is not "open", 093:2130); `get_payout_execution_context` → `payout_held` only because of the dispute overlay.

**c-iii: closed, payout PENDING, dispute first observed already `lost`** [X]: `record_dispute_native` → `atoms_held 0, payouts_held 0` (088:804 freezes only OPEN). Payout stays `pending | none`. Next close books `settlement_shortfall 19,000`. Payout still `pending | none`.

**c-v (extension): bind a destination and advance to submitted** [X]: `get_payout_execution_context` → `refusal_code NULL, execution_eligible TRUE, amount 19,000`. `settlement_unbooked_refund_exposure(S1) = 0` (it reads only `kernel.refund`). So after the shortfall is on the books the never-paid payout is **fully executable**; if it executes, venue receives 19,000 and owes 19,000 (consistent, net 0); if it is never executed, the org "owes" 19,000 it never received. Nothing links the two rows.

### 2.d Lost dispute while a refund is pending — [X] **DOES NOT CONSERVE (phantom debt)**

**d-i (never paid)**: refund `pending` 23,000 + dispute `lost` 23,000, then first close:
- `scoped_order` defers the order whole (093:477-479) → **no `primary_sale` credit**; the chargeback arm has **no in-flight-refund deferral** → `chargeback −19,000` lined alone → net −19,000 → **`settlement_shortfall 19,000` outstanding for a venue that was paid 0**.
- refund executor operands: `amount 23,000, total 23,000, prior 0, disputed 23,000` → `executor_refuses_sum_guard = true` → the refund is refused forever, stays `pending` (no terminal for a never-submitted refund), the order stays deferred forever, the credit never lands. **The debt is permanent and false.**
- If the refund nevertheless reached `succeeded` (forced via `mark_refund_state`): next close lines `primary_sale +19,000`, **no `refund_void`** (093:492-520 — the chargeback already consumed the face headroom) → net +19,000 → **a payout of 19,000 is minted for an order whose money went back to the buyer twice** (obligation 19,000 still outstanding). Rows: `refunded 23,000, chargeback 23,000, venue payout pending 19,000, obligation 19,000`.

**d-ii (venue already paid 19,000)**: same sequence after payout → `chargeback −19,000`, `settlement_shortfall 19,000` — here the obligation is right, but the pending refund is again stranded (`executor_refuses_sum_guard = true`) with no cancel path. 093's refund arm does **skip** (nothing succeeded), so no double debit.

### 2.e Refund succeeded, THEN dispute lost — [X] chargeback arm correct; **094 guard wrong**
- S2 (refund first): `refund_void −19,000`, net −19,000, `settlement_shortfall 19,000`. Correct.
- dispute `lost` 23,000 → S3: **zero lines, net 0, no new obligation**; `settlement_royalty_lines(S3)` candidate probe returns **no row** (refund_exposure 19,000 = face → headroom 0 → no line, not a zero line). Cap dedupe proven.
- `kernel.record_organization_obligation(org,'unlined_reversal', dispute_id, 'dp_kc_E', 19000,…)` → **`status ok`** → org now carries `settlement_shortfall 19,000 + unlined_reversal 19,000 = 38,000` against 19,000 paid. The guard (094:387-388) only asks "does THIS dispute carry a line" — a dispute whose loss was absorbed by `refund_void` passes.
- e-b (refund `succeeded` and dispute `charge_refunded` both unlined in one close): `refund_void −19,000` only; net −19,000; one obligation. Correct.

### 2.f Partial refund 4,000, then dispute 23,000 — [X] correct
S2 lines `refund_void −4,000`, `chargeback −15,000` (=19,000−4,000), net −19,000, `settlement_shortfall 19,000`. Cash 23,000 − 4,000 − 23,000 − 19,000 = −23,000; +19,000 receivable ⇒ −4,000 = fee lost. Conserves.

### 2.g Two disputes on one payment — [X] sum capped; **third dispute leaks through 094**
12,000 (G1) + 12,000 (G2), both lost before S2: lines `chargeback −12,000 (G1)`, `chargeback −7,000 (G2)` — window allocation `(created_at, dispute_id)`; Σ = 19,000 = face; `settlement_shortfall 19,000`. Second `record_dispute_native` reported `atoms_skipped 2` (overlay occupied — correct).
Third dispute G3 (500, `lost`) → S3 zero lines (headroom 0), `g3_lined = 0` → `unlined_reversal` booking **admitted** (`ok`, 500) → outstanding 19,500 > 19,000 face. Same root as 2.e.

### 2.h cancel_event + dispute overlap — [X]
- h-a (paid → cancel → dispute lost): `cancel_event` created one `event_cancelled` refund **19,000 pending** (Σ item prices, not 23,000), voided 2 atoms. Dispute recorded → `atoms_skipped 2` (voided). S2: `chargeback −19,000`, `settlement_shortfall 19,000` (correct: venue was paid). The pending refund: `executor_refuses_sum_guard = true` (19,000 + 23,000 > 23,000) → **stranded pending forever**, no cancel verb for a `kernel.refund` row.
- h-b (paid → dispute lost → cancel): `refunds_created 0`, `atoms_voided 0, atoms_skipped 2`, audit `event.cancel_skip / money_already_returned {prior 23000, total 23000}`; atoms remain `issued | dispute_hold`. The §11.4 guard (088:1659) works. No double return.

### 2.i Promoter Option B — [X] **obligation overstates venue debt by the held commission**
face 10,000, fee 0, commission 10 % (`venue.create_promoter` bps 1000 + `create_promoter_link` + direct `venue.attribution` row):

| step | rows |
|---|---|
| S1 | `primary_sale +10,000`, `promoter_commission −1,000`; header `gross=10000 fees=1000 net=9000`; payouts: `settlement 9,000 pending/none`, `promoter_commission 1,000 pending/held/unfunded_settlement` |
| pay | settlement payout → `paid` 9,000 |
| dispute open | `payouts_held 0` — the commission payout's `cause_ref` is `attribution.id`, unreachable by 088:843-844 (and it was already held) |
| S2 | `chargeback −10,000` (not −9,000); net −10,000; **`settlement_shortfall 10,000`** |
| conserve | collected 10,000 − chargeback 10,000 − venue_paid 9,000 = **−9,000** cash; ledger: obligation 10,000 + commission liability 1,000 (held, never paid) |

Decomposition of the 10,000 shortfall: **venue debt 9,000** (what the venue actually received) · **promoter held claim 1,000** (still `pending/held/unfunded_settlement`, untouched by the reversal — G4 "stays HELD") · **platform fee loss 0** here (fee 0; with the 2.a shape it would be 4,000, outside the shortfall) · **obligation booked 10,000** → overstated by the 1,000 the platform retained. If the commission were later funded and released the numbers would reconcile (venue 9,000 + promoter 1,000 = 10,000 owed back by the org); while it is held, collecting 10,000 from the org takes 1,000 the org never had.

### 2.U Dormant org (item 2) — [X] **`unlined_reversal` collides with `settlement_shortfall`**
paid 19,000 → dispute `lost` 23,000 → operator books `unlined_reversal 23,000` (**accepted; amount uncapped, includes the 4,000 fee**) → org later opens+closes a settlement → `chargeback −19,000` (arm does not read `organization_obligation`) → `settlement_shortfall 19,000` → **outstanding 42,000 against 19,000 paid**. Platform `admin_user` attempting `venue.open_settlement` → `insufficient_privilege` (087:237 confirmed).

### 2.X Cross-venue leak (item 3) — [X] **Venue A's chargeback nets Venue B's payout**
One org, Venue A (19,000 face paid, dispute lost 23,000) and Venue B (30,000 face). Venue B **period-scoped** settlement (`period_start = now−60d, period_end = now`): lines `primary_sale +30,000 (B order)`, **`chargeback −19,000 (VENUE A dispute)`**; header `net=11000`; payout **11,000** minted to the org; **no obligation** (net > 0). Same result for an **event-scoped** Venue B settlement. `settlement_payout_maturity(B)` shows `covered_sessions: 2` — A's session is dragged into B's covered set (so an open dispute on A would also hold B's payout). Venue A never needs to open another settlement; its loss is invisible as a debt and has been recovered from B's revenue by default — the exact thing the G5 direction forbids.

---

## 3. Findings, ranked

**P0-1 — Cross-venue netting by default (item 3).** [X §2.X] `cb_candidate` joins only `o.org_id = s.org_id` (093:1187, transcribed from 088:357 "the org's NEXT settlement to close"). A period- or event-scoped settlement of any venue in the org absorbs any venue's lost disputes. Consequence: G5 "no default cross-venue netting" is violated by the shipped arm; the debt never becomes an `organization_obligation` because the net stays positive, so it is also invisible to any future recovery seam. 094 explicitly declined to touch this (094:98-105 "chargeback… OVER-collects", 160/F10 pins the absence of a scope predicate).

**P0-2 — Phantom obligation when a refund is in flight (2.d-i).** [X] The refund arm defers the order whole (093:477-479) but the chargeback arm has no symmetric deferral, so the debit is booked in a close whose credit is deferred: `settlement_shortfall 19,000` against a venue paid 0. Compounded by the refund executor's Σ-guard (executor.ts:276-285) refusing the refund forever, so the deferral never lifts. Once G5 recovery is deterministic this collects real money for a sale the venue was never paid for. (With H-a it is the *ordinary* cancel-then-dispute timeline.)

**P1-1 — `settlement_shortfall` is booked without reference to whether the offsetting payout was paid (2.c-ii/iii, 2.d-i).** [X] The origin is "a close netted negative", not "post-payout debt". In c-ii the org shows 19,000 outstanding while its own 19,000 payout sits `pending/held/dispute`; in c-iii/c-v the never-paid payout remains `execution_eligible = true` after the shortfall exists. The two rows are unlinked; both "resolve the obligation" and "release the payout" are independent human acts with no invariant between them. G5 direction ("THE durable record of post-payout debt") is not what 094 records.

**P1-2 — `unlined_reversal` is uncapped, caller-priced, and its guard is per-dispute rather than per-order (2.e, 2.g, 2.U).** [X] Bookable at 23,000 (fee included) against a 19,000 face; bookable for a dispute whose loss was already absorbed by `refund_void` (E) or capped away (G3); and the chargeback arm does not read `organization_obligation`, so a later close books the same loss again as `settlement_shortfall` (U: 42,000 outstanding vs 19,000 paid). 094:33-39 calls `UNIQUE(origin_kind, origin_ref)` "the idempotency mechanism" for an at-least-once webhook — but no webhook or TS path calls the verb (0 hits in `supabase/functions/`), and after the dispute writers are wired **nothing changes**: the origin stays operator-only. It is not "reachable" by wiring; it is reachable only by a human typing an amount.

**P1-3 — Promoter case overstates the org's debt by the held commission (2.i).** [X] Chargeback line −10,000 = face; obligation 10,000; venue received 9,000; the 1,000 sits in a `promoter_commission` payout that is `held/unfunded_settlement` and is never touched by any reversal path (088's payout leg cannot reach it: `cause_ref = attribution.id`, 088:843-844 matches settlement ids only; its comment "settlement AND commission payouts alike" at 088:768 is not what the predicate does). No row records "promoter claim reduced by reversal" — G4's "commission stays HELD" is honoured, but the org-side number does not subtract it.

**P1-4 — Stranded pending refunds after a lost dispute (2.d-ii, 2.h-a).** [X] `kernel.refund` has no terminal for "never submitted / superseded by chargeback"; the executor refuses forever; `settlement_primary_lines` defers the order forever; `settlement_payout_maturity.refund_in_flight` would hold any future settlement covering that payment. Already known adjacent (E4/J6) but the dispute wiring makes it the normal outcome of cancel-then-dispute.

**P2-1 — A dispute first observed `lost` freezes nothing (2.c-iii).** [R 088:804, X] Pending payout stays `none`; `settlement_payout_maturity` does not count `lost` as a hold (093:2130) and `settlement_unbooked_refund_exposure` ignores disputes (095:963). Known (093:2087-2097 comment), re-measured: the payout is executable right through the shortfall booking.

**P2-2 — `mark_dispute_state → lost` leaves the dispute hold on the payout with no release path other than `kernel.release_payout` (platform_risk) and PFA-31's parked `resolve_dispute_native`.** [X §2.c-ii] After the shortfall is booked the held payout and the obligation coexist indefinitely.

**P2-3 — Fee slice is platform loss, unrecorded.** [X all cases] The 4,000 buyer-side fee is neither lined nor booked anywhere on a lost dispute (A5 says it is platform money; the loss just vanishes from every ledger object). Not a defect against the rulings, but no object records it.

What is **correct and proven**: face cap (a, b, f), refund seniority and cross-cause dedupe (e, f, g), per-order cumulative cap across multiple disputes (g), pre-payout netting to zero (c-i), cancel_event's §11.4 guard against a prior chargeback (h-b), the OPEN-dispute payout freeze on a primary order (c-ii), and the `already lined` arm of the 094 guard (a).

---

## 4. Options, trade-offs, smallest honest design

### 4.1 Cross-venue leak (P0-1)
- **O1 — venue-scope the chargeback arm** (096 re-creates `settlement_royalty_lines`; add `join catalog.event_session es … join catalog.event e … where e.venue_id = s.venue_id` on the disputed order, period predicate optional). Trade-off: Venue A's dispute is then only ever lined in a Venue A settlement; if Venue A never settles again, the loss is never lined (the "dormant venue" case) — which is exactly what should route to the obligation record instead of into B's payout. Honest, small (one predicate), but leaves a dormant-venue gap that only O3 or a platform-opened settlement closes.
- **O2 — keep org scope, but book the leaked amount as an obligation-with-credit**: a new origin "cross_venue_offset" so that B's absorbed 19,000 is visible. Adds an enum member with a producer, more surface, still nets B by default — dishonest against G5 unless config-gated.
- **O3 — venue-scope the arm AND let the platform open/close a settlement for a dormant venue** (096: add `or kernel.is_platform(array['platform_admin'])` to 087:237's gate; audited). Then every reversal flows through ONE path (line → net → shortfall) and `unlined_reversal` becomes unnecessary. Largest but the only option that makes "one origin per loss" true by construction.
- Smallest honest: **O1 now, O3 as the structural close**. Dishonest: leaving the arm org-scoped while claiming G5 (the 160/F10 test asserts the leak as a feature).

### 4.2 Phantom debt with in-flight refund (P0-2)
- **O4 — mirror 093:477-479 in `cb_candidate`**: `and not exists (select 1 from kernel.refund r0 where r0.payment_id = pn.payment_id and r0.status in ('pending','submitted'))`. One predicate, symmetric with the refund arm, no new object. Then credit and debit land in the same close. Trade-off: while the refund is stranded (P1-4) nothing is lined — safe direction (nothing over-collected), but the loss is invisible until the refund terminates.
- **O5 — give `kernel.refund` a terminal `superseded`/`cancelled` state writable by the dispute path** (bigger: touches a frozen money table, 085) so the deferral lifts.
- Smallest honest: **O4**, with O5 as the follow-up that makes the deferral finite. Dishonest: deferring only the credit and booking the debit (current).

### 4.3 Obligation ≠ post-payout debt (P1-1)
- **O6 — cap the shortfall at what was actually paid**: in the 094 branch, book `least(-v_net, Σ paid settlement payouts of this org [venue?] − Σ obligations already booked)`; if zero, book nothing and leave the negative header as bookkeeping. Trade-off: the "org-level paid pool" is itself a cross-venue netting decision (owner call); computing it venue-scoped needs the venue on the payout (present via `settlement.venue_id`).
- **O7 — keep booking, but link**: when a shortfall is booked while a `pending` settlement payout of the same org exists, hold that payout with a new reason (`shortfall_offset`) and record the pair in the obligation audit. Nothing nets; a human sees both. Smaller, honest about what it does not decide.
- Smallest honest: **O7** (no money decision, one hold write in a branch that already writes an obligation). O6 is the real fix but is a G5 policy act.

### 4.4 `unlined_reversal` (item 2)
Meaning per 094:193-200/J3 §5.2: the dormant-org case — org never opens a settlement, so the chargeback candidate is never offered; recorded by an operator, `origin_ref = dispute_id | refund_id`. After dispute wiring it is **not** newly reachable (no producer is added by the train); it **can** collide with `settlement_shortfall` (2.U) and with `refund_void` absorption (2.e, 2.g).
- **O8 — drop it** (096: `CHECK (origin_kind = 'settlement_shortfall')`; 094 is unapplied so no rows exist) and route the dormant case through O3 (platform-opened settlement). One origin per loss, by construction; the amount is always ledger-derived. Requires 087's gate change.
- **O9 — keep, but make it derive and fence**: amount = the same headroom the arm computes (`face − Σ succeeded refunds − Σ prior chargeback lines − Σ prior obligations on the order`), guard by ORDER not by dispute, require the order's `primary_sale` line to sit in a settlement whose payout is `paid`, and make `cb_candidate` exclude disputes carrying an obligation row. Two bodies change (094 verb, 093 arm); the disjointness J3 claims becomes real.
- **O10 — scope it to "no settlement at all"** (guard: the order has no `primary_sale` line anywhere). Honest reading: if the order was never credited the org was never paid, so there is no org debt — the origin would then be bookable exactly when it is wrong. Reject.
- Smallest honest: **O9's fence half** (derive + order-level guard) if O8 is refused; O8 if the owner accepts the 087 gate change. Dishonest: keeping the free-amount verb and calling `UNIQUE(origin_kind, origin_ref)` its safety.

### 4.5 Promoter (P1-3)
- **O11 — book the shortfall net of held commission**: `-v_net − Σ promoter_commission payouts (pending/held) whose attribution order is among this close's chargeback-lined orders`, and audit the 1,000 as "promoter claim under reversal". Nothing pays or voids the promoter (G4). Small, but couples the branch to attribution lookups.
- **O12 — extend 088's payout leg to reach commission payouts** (`or po.cause_ref in (select a.id from venue.attribution a where a.order_id = v_pn.order_id)`) so the reversal is at least visible on the promoter row (`held/dispute` instead of `held/unfunded_settlement`). Pure observability; no money.
- Smallest honest: O12 now; O11 is a G4 economics decision.

### 4.6 Stranded refunds (P1-4): O5 above; or an executor-side `refund.superseded_by_dispute` audit note plus a `settlement_primary_lines` predicate that ignores a pending refund whose payment has a lost dispute ≥ total. Smallest honest: the predicate (one line), with O5 as the real fix.

---

## 5. Open questions for the orchestrator / owner
1. G5: is the chargeback arm's org scope (088:311-316, re-affirmed 093:1119-1122, pinned by test 160/F10) to be **reversed** to venue scope? The leak is measured (11,000 paid to B instead of 30,000). If yes, does the platform get an `open_settlement` arm (087:237) so dormant venues still get lined?
2. Does `organization_obligation` mean "post-payout debt" (G5 wording) or "negative close residue" (094 as built)? c-ii/c-iii/d-i are three shapes where those differ by the full face.
3. `unlined_reversal`: drop (O8) or fence (O9)? Either way its "at-least-once webhook" justification (094:33-39) is false today and stays false after wiring.
4. G4: should the org's reversal debt be net of a commission the platform still holds (2.i: 10,000 vs 9,000)? Who eventually owns the held 1,000 after a full chargeback — promoter, org, or platform?
5. Refund/dispute overlap: is a `kernel.refund` terminal for "superseded by chargeback" in scope for this train (frozen 085 table), or is the arm-side deferral (O4) the whole answer for now?
6. Does the train want the fee-slice loss (2.a: 4,000) recorded anywhere, or is "platform absorbs, unrecorded" the accepted A5 posture?
