# KM3 — 098 promoter pro-rata funding: implementation report

AUTHOR ONLY. No DB command was run against any rehearsal database in producing this
migration/rollback/test/PFA — the orchestrator verifies centrally (rehearsal_reset /
rehearsal_test). Every claim below is a claim about the SQL as authored, checked by
reading the source it re-creates and by hand-tracing the arithmetic against the fixture
in `supabase/tests/164_promoter_prorata_funding.sql`, not by execution.

## 1. What was built

- `supabase/migrations/098_promoter_prorata_funding.sql` — ONE transaction, three
  body-only `create or replace function` statements, no DDL:
  1. `kernel.settlement_commission_lines(uuid)` (093:889-925 baseline) — the
     eligible-set status clause `o.status not in ('refunded','partially_refunded',
     'cancelled')` is replaced with `o.status <> 'cancelled'` plus a refund-in-flight
     deferral predicate (the "could still succeed" arithmetic from DESIGN_097_099
     §2.1, copied verbatim into a `not exists (... kernel.payment_native pn ...
     kernel.refund r0 ...)` wrapper — the operands r0/r1/d1/p.total are byte-identical
     to the text M2 is instructed to add to 097's chargeback/primary seams). Every
     other filter (E-104 lock, scope predicate, never-lined-before dedupe, currency
     filter, payee-resolvable filter, deny-decision filter, the `pay_promoter_
     commission` call and its `'seam:'` command key, the negated return projection)
     is byte-identical to 093's text.
  2. `kernel.pay_promoter_commission(uuid, uuid[], text)` (090:1401-1507 baseline) —
     the basis block (the `v_o.status = 'refunded'` short-circuit + the surviving-atom
     lateral, 090:1456-1466) is replaced with the KF §4.2 surviving-FACE computation:
     `v_face` = `order.total_minor`; `v_refunded` = `least(face, Σ kernel.refund.
     amount_minor WHERE status='succeeded')`; `v_disputed` = `least(face −
     v_refunded, Σ kernel.dispute_native.amount_minor WHERE status IN ('lost',
     'charge_refunded'))` (KF §4.4 default: include, capped); `v_surviving` =
     `greatest(0, face − v_refunded − v_disputed)`; `bps` → `floor(surviving × bps /
     10000.0)`; `flat_per_ticket` → `floor(surviving / unit_price_minor)` per order
     item, capped at that item's own quantity, summed, × flat (KF §4.5 option (a)).
     `payable ≤ 0` still holds `basis_zero`, no line — unchanged. Every other line
     (forbidden-caller guard, settlement re-lock, per-attribution loop shape,
     advisory review-lock, self-deal/flagged hold, identity/currency holds,
     amount_overflow guard, the payout MINT under `held`/`unfunded_settlement`, the
     notify.emit_event calls, the trailing `settlement.commission` audit insert) is
     byte-identical to 090's text.
  3. `kernel.mark_payout_transfer_state(uuid, text, text, text, text)`
     (085:1668-1735 baseline) — ONE guard added immediately after the `not_found`
     check: `if v_row.cause =
     'promoter_commission' then raise exception 'precondition_failed:
     promoter_payout_dark — no promoter payout executor exists (ruling A4)'; end if;`
     — no explicit `errcode`, so it raises `P0001` (PL/pgSQL's default), matching the
     sibling `payout_held` raise one line below. Every other predicate (status
     vocabulary, hold refusal, replay rule, forward-only, mandatory-ref/failure-code
     checks, write-once ref, admin_audit write, `venue.on_payout_settled` hook) is
     byte-identical to 085's text.
  `CREATE OR REPLACE` preserves ACLs for all three (095's rollback header states this
  convention explicitly; I follow it) — no `GRANT`/`REVOKE` statement appears in 098.

- `supabase/rollbacks/098_promoter_prorata_funding_rollback.sql` — restores the three
  functions to the pre-098 bodies verbatim (093:889-925, 090:1401-1507, 085:1668-1735).
  No data guard: 098 creates no table/column/index/trigger, so there is no new object
  whose absence could break a held row on rollback. Any commission line/payout
  written under 098's rule stands untouched (append-only) after rollback — only what
  a FUTURE close computes reverts. Second run is idempotent (`CREATE OR REPLACE`).

- `supabase/tests/164_promoter_prorata_funding.sql` — pgTAP, `BEGIN … plan(29) …
  finish() … ROLLBACK`, 29 assertions. One order geometry throughout (2 × 5000 = face
  10000) so every expected number is the KF §4.2 formula applied to one value, each
  case (or case-pair) in its own event/session/ticket_type/batch so settlements never
  cross-contaminate. Covers: A (baseline, −1000/held 1000 — also the fixture for
  re-close-noop and G4), B (−600 line / 600 held payout), C (no line, `basis_zero`
  audited), D1 (a `pending` refund defers the WHOLE attribution — 0 lines, 0
  `settlement.commission` audit rows at all, since `pay_promoter_commission` never
  runs), D2 (the same refund later `failed` — Σ succeeded = 0 → full −1000, not the
  pre-098 permanent forfeiture), E (two attributions in one close: E1 −1000, E2
  −600), H (2 tickets, one direct partial refund of 5000 that voids no atom —
  asserted directly against `kernel.tickets.state` — surviving 5000 → −500), a
  dispute-at-close pair (Disp1: refund 3000 + lost dispute 4000 → surviving 3000 →
  −300, demonstrating disputes count as reversed per KF §4.4; Disp2: refund 9000 +
  lost dispute 5000 → the dispute is capped at the 1000 of headroom the refund left,
  surviving floors at exactly 0 → `basis_zero`, no negative, no error), flat kind
  (promoter F, flat 300; surviving face 5000 on a 2×5000 order → `floor(5000/5000)=1`
  surviving ticket, capped at qty 2, × 300 = −300 — KF §4.5(a)), re-close-noop (a
  second close on A's event lines nothing new), post-close-refund-not-re-funded /
  G4 (a refund issued AFTER A's line exists lines nothing new, and the ORIGINAL
  line/payout are read back unchanged — append-only, G4 stays held), A4-negative
  (forcing A's commission payout to `status='submitted'` as table owner and calling
  `mark_payout_transfer_state('paid', …)` is refused `promoter_payout_dark` — KF
  P2-1's fourth lock is now a refusal, not an absence), and a conservation check on
  B's settlement (`gross(10000) − refund(4000) = commission funded(600) + venue
  distributable(5400)`, checked both as a line-sum and against `venue.settlement.
  net_minor`).

- PFA-PT-4 appended to `docs/architecture/_governance/POST_FREEZE_AMENDMENTS.md`
  (id was unused — checked via grep before filing), status **PENDING OWNER
  SIGNATURE**, following the PFA-29/30/31 block format with FROZEN RULE / CONFLICT /
  EVIDENCE / RESOLUTION / OPTIONS / CLASSIFICATION / a RETROACTIVE NOTE for 093/10e's
  undocumented deviation (KF §5 last paragraph — 093:861-876 called its own exclusion
  "a deliberate, reversible over-correction" but never filed it in this register) /
  OWNER ITEMS OPENED / PACKAGE IMPACT / SECURITY-MONEY IMPACT / OWNER SIGNATURE
  REQUIRED: YES / STATUS: PENDING OWNER SIGNATURE.

## 2. Census deltas: NONE expected

098 re-creates three EXISTING functions body-only (`create or replace function` over
frozen signatures, same schema, same parameter list, same return type). It adds no
table, no column, no index, no trigger, no cause code, no config key, no cron row, no
grant/revoke statement (ACLs are preserved by `CREATE OR REPLACE`). Nothing in the
kernel/venue function census (141/142/143/144/148/154/156/157), Gate-2's table/
function/policy/trigger counts, or the writer registry should move. I did not run
Gate-2 myself (AUTHOR ONLY); this is a structural claim from the diff's shape, for the
orchestrator to confirm against a rehearsal replay.

## 3. Existing pgTAP assertions that need the ORCHESTRATOR to update

Two tests in `supabase/tests/155_phase2_venue_promoter_engine.sql` assert the OLD
093/10e total-forfeiture behaviour by construction; a third depends on the first two.
I did not edit 155 (out of scope for M3). Precise facts, for the orchestrator to act on:

**G41c** (155:961) and **G41d** (155:963) — fixture: attribution on order `o13` (face
5000, 1 ticket, promoter P's terms at binding = bps **2000**, snapshotted after F27's
`update_promoter` at 155:690, confirmed by G42's own comment "attributed under terms
v2"). The fixture sets `order.status = 'partially_refunded'` by a RAW `UPDATE`
(155:953) — **no `kernel.refund` row is ever created for this payment.** Under 098:

- the eligible-set status clause no longer excludes `partially_refunded` (only
  `cancelled` is excluded now), and the refund-in-flight deferral predicate requires
  an ACTUAL `kernel.refund` row in `pending`/`submitted` — there is none — so o13's
  attribution is NOT deferred and NOT excluded; it reaches
  `kernel.pay_promoter_commission`.
- `v_refunded` = 0 (no succeeded refund row exists), `v_disputed` = 0, `v_surviving`
  = `face` = 5000. `commission_bps_applied` = 2000 → `payable` =
  `floor(5000 × 2000 / 10000.0)` = **1000**.

So under 098, at s4pr's close (155:955-960), o13's attribution is lined at **−1000**,
not held with 0 lines. The orchestrator should change:
- G41c's expected value from `tap._lines155(s4pr) = 0` to `= 1`, and add/adjust an
  amount assertion for `-1000` on that line (mirroring G37's pattern one section
  above).
- G41d's expected value from "0 commission payouts" to "1 commission payout, amount
  1000, `hold_state='held'`, `hold_reason_code='unfunded_settlement'`".

Justification: this is exactly PROMO §5.2 row 2 / test 45's stated result (a partial
refund produces a REDUCED single line, not zero) — except this particular fixture
carries NO real partial refund at all (no `kernel.refund` row backs the status flip),
so under the corrected rule there is nothing to reduce and the attribution is priced
at its FULL surviving face. The 093/10e behaviour these two assertions pin (permanent,
silent, zero-line forfeiture merely from an `order.status` flag with no money fact
behind it) is precisely KF P1-1/P1-2's measured defect — the fixture's own comment
(155:945-952) already narrates the defect 098 exists to fix.

**G42** (155:971) — currently expects `tap._lines155(s4) = 1` and a 1000 payout,
asserting the commission line is written at s4's close (after status is restored to
`'paid'`, 155:964). Under 098, because o13's attribution is ALREADY lined at s4pr (per
G41c's corrected behaviour above), the `NOT EXISTS` predicate excludes it at s4's
close — s4 closes with **0** new lines for o13, not 1. The orchestrator has two
honest options, not one I should pick for it:
  (a) change G42's expectation to 0 lines at s4 (since the money was already funded
      one settlement earlier, at the full 1000 — a stronger proof that "release/deny
      supersession still prices correctly" would need re-deriving from G41c's numbers
      instead of G42's own close); or
  (b) rework the G41c/d/42 fixture to back the `partially_refunded` flip with a REAL
      `kernel.refund` row (`pending` then `succeeded`, in the 159 idiom) so the
      original three-step narrative (deferred-while-pending vs. priced-reduced-at-
      close vs. priced-at-terms-v2-after-release) is preserved rather than collapsing
      into "there was never a refund at all."
  I recommend (b) — it keeps G41c/d/42's ORIGINAL teaching intent (supersession +
  partial-refund pricing interacting) rather than accidentally testing a degenerate
  case — but either is honest; I did not implement either, per the boundary.

**151** (`supabase/tests/151_phase2_venue_settlement_and_export.sql`) — checked (grep
for `refunded`/`basis_zero`/`partially_refunded`/`forfeit` near commission context):
its promoter-commission references are all STRUCTURAL (function-existence/signature
checks at 151:150/153/156/229/234, and one hand-INSERTed `promoter_commission` line
used to prove the header rollup sign convention, 151:401 — inserted directly, not via
the seam). None assert 090/093's forfeiture behaviour. **No change needed in 151.**

## 4. Deviations

None from the spec. Two judgment calls made where the spec left an explicit choice,
both flagged in the PFA as owner items rather than decided unilaterally:
- KF §4.4 disputes-at-close default = INCLUDE (capped) — implemented as the default,
  per the spec's explicit instruction ("KF §4.4 default = include").
- KF §4.5 flat-kind option (a) (`floor(surviving_face / unit_price)` per item, capped
  at quantity) — implemented, per the spec's explicit instruction.

One naming note: the spec's line "`kernel.mark_payout_transfer_state (add ONE guard…
)`" — the function's real signature is `(uuid, text, text, text, text)` (payout_id,
new_status, stripe_transfer_ref, failure_code, command_key), confirmed against
085:1668-1671; the added guard reads `v_row.cause`, needs no new parameter, and is
placed exactly where the spec's cross-reference (KF P2-1) points: "after the
not_found check."

## 5. Files

- `supabase/migrations/098_promoter_prorata_funding.sql`
- `supabase/rollbacks/098_promoter_prorata_funding_rollback.sql`
- `supabase/tests/164_promoter_prorata_funding.sql`
- `docs/architecture/_governance/POST_FREEZE_AMENDMENTS.md` (PFA-PT-4 appended)
- `docs/phase2/_impl/KM3_098_implementation.md` (this file)
