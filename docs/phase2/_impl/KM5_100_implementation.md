# KM5 — migration 100 implementation report (the G4 economic-consistency fix)

Repo `/Users/josetascon/snatchit-consol`, branch `feature/venue-native-and-product-v2`. Boundary: `TRAIN_BRIEF.md`. Local rehearsal DB only (`snatchit_rehears_recon2`); no production, no deploy, no Stripe, no commit.

**2026-09-03 (RECON2 reconciliation).** 100 was simplified by the orchestrator, after this report's original drafting, to a **seams-only** obligation fix. This revision rewrites this report to match the shipped design: §§5-7 and the `converge_held_commission` rows below (an earlier draft's mechanism) are **removed, not just amended** — that verb, and the `close_settlement` re-creation that called it, are not part of 100 as shipped. Test `166_venue_obligation_excludes_held_commission.sql` was rewritten to match (39/39 assertions, no reference to a convergence verb) and the whole suite reconciled — see §12.

## 1. Objects

| Object | Kind | Signature | Note |
|---|---|---|---|
| `kernel.settlement_primary_lines` | body-only re-create | `(uuid) returns setof kernel.settlement_line_candidate` | refund_void cap gains a `held_commission_minor` subtraction (symmetry, §4) |
| `kernel.settlement_royalty_lines` | body-only re-create | `(uuid) returns setof kernel.settlement_line_candidate` | chargeback cap gains the same `held_commission_minor` subtraction |

**No new object of any kind.** No table, no column, no trigger, no policy, no settlement_line cause, no new function. `create or replace function` preserves the ACL of both re-created functions. `kernel.close_settlement` is **not** re-created — it still books `−net` from whatever the (now-correct) candidate lines produced, unchanged since 097. The kernel function census stays at **146** (unchanged from before 100 — confirmed by direct count against the rehearsal DB, §12).

## 2. Files

- `supabase/migrations/100_venue_obligation_excludes_held_commission.sql` — 339 lines, md5 `58402dbfec629abaa10b6866ec8abf29`. Read in full for this reconciliation — its header is the authoritative statement of what 100 does and, explicitly, does not do.
- `supabase/rollbacks/100_venue_obligation_excludes_held_commission_rollback.sql` — 214 lines. Unguarded (restores both seams to their 097 bodies verbatim); its own header notes 100 "added no new object... so there is nothing to DROP" — confirming the seams-only shape from the rollback side independently.
- `supabase/tests/166_venue_obligation_excludes_held_commission.sql` — 427 lines, plan(39), 39/39 passing. Rewritten this session (RECON2) — the prior version tested the removed `converge_held_commission` verb and errored against the shipped migration.
- `supabase/tests/153_phase2_market_native_rail.sql` — H58 (line ~851) fixed this session: a substring regex (`numeric|float|double|real`) false-matched the English words "real receipt" and "double-counted" inside 100's own comments in `settlement_royalty_lines`. Fixed to strip `--` line comments before the check; the assertion's meaning (no float/numeric arithmetic in the seam's *code*) is unchanged.
- `docs/architecture/_governance/POST_FREEZE_AMENDMENTS.md` — PFA-PT-5 reconciled this session to describe the built obligation-cap fix and list held-commission-payout convergence as a **deferred, future-ruling item**, not a built mechanism.
- `docs/phase2/G4_PROMOTER_REVERSAL_RULING.md` — reconciled this session (see that file's own changelog note).
- This file.

## 3. The mechanism (what 100 actually does, and deliberately does not do)

`kernel.payout.status` has no non-paying terminal for `promoter_commission`, and 098's `kernel.mark_payout_transfer_state` already refuses `cause='promoter_commission'` outright before it even reads `status`/`hold_state` — so no promoter_commission payout can ever reach `paid` through the only verb that pays one. That structural fact is what lets 100 be **read-only with respect to the held commission**: the two seams below only *read* `kernel.payout` to compute a cap; neither inserts nor updates a `kernel.payout` row (proved statically, test 166 §F3/F4, and dynamically — the same row, same amount, same state, before and after every reversal in sections A/B).

The held commission payout is **never converged, never relabeled, never re-minted**. It sits at its originally-funded amount, `pending`/`held`/`unfunded_settlement`, for the life of the fixture — through any number of subsequent post-payout reversals. Converging it down to a pro-rata surviving amount (what an earlier draft of this migration did, inside `close_settlement`, via a `converge_held_commission` verb) is **explicitly out of scope**: G4 rules that a separate owner ruling and architecture is required "before the FIRST future promoter commission payout"; promoter payout is dark (no commission payout ever leaves pending/held) so there is no launch-blocking need to converge it now. That earlier draft also had concrete defects the current header records: a second `promoter_commission` payout row per attribution broke the single-minter fence (155 B18), broke single-row `cause_ref` lookups (164), and made every "latest payout by created_at" reader — including the production promoter-status projection at 090:1325 — nondeterministic. The seams-only design needs none of that machinery.

This is filed as **PFA-PT-5**: item (a), the A5 face-cap clarification, is BUILT (100, this report). Item (b), held-commission-payout convergence, is **SPECIFIED, DEFERRED** to the future promoter-payout ruling — not a built mechanism.

## 4. The chargeback/refund_void cap clarification

```
held_commission(order) := Σ kernel.payout.amount_minor
  WHERE cause='promoter_commission'
    AND status='pending' AND hold_state='held'
    AND coalesce(hold_reason_code,'') <> 'commission_converged'
    AND cause_ref IN (select attribution_id for that order)
```

- `settlement_royalty_lines` (chargeback): `cap := greatest(0, face − refund_exposure − prior_cb − held_commission)`.
- `settlement_primary_lines` (refund_void): `cap := greatest(0, face − held_commission)`.

Both reads are correlated per-order subqueries joined through `venue.attribution.order_id = po.cause_ref` reversed (`venue.attribution.id = po.cause_ref`), scoped to the reversed order.

The `hold_reason_code <> 'commission_converged'` clause is a **defensive, currently-inert** filter: nothing in the shipped kernel ever sets that sentinel (no convergence verb exists to set it). It costs nothing and future-proofs the read if a later, separately-ruled convergence mechanism ever does start setting it — but as shipped, `held_commission_minor` for a given order is a **constant** once funded: it does not shrink across subsequent reversals or subsequent closes, because nothing ever reduces the row it reads. (Contrast this explicitly with an earlier draft, which shrank the held amount via convergence on each qualifying close — that behavior is not what is shipped.)

## 5. THE SYMMETRY DECISION — settlement_primary_lines' refund_void arm

**Decided and proved: YES, the same reduction is needed, and it is applied.**

`settlement_primary_lines` (branch 1) and `settlement_royalty_lines` (branch 2) both run, as pure candidate generators, before `settlement_commission_lines` (branch 3, the only branch with side effects — it inserts the `venue.settlement_line` row and, via `pay_promoter_commission`, the `kernel.payout` row) in `close_settlement`'s `union all`. So:

- A **pre-payout / same-close** refund or chargeback (nothing has ever been funded for this order before this transaction) reads `held_commission_minor = 0` — unchanged from 097 — proved by test 166 §D: a 3000 refund landing before the order's first-ever close lines unreduced at −3000, and the commission funds fresh, in the same close, against the already-refunded face (`floor((10000−3000)×1000/10000)=700`) — two independent reductions of the same 3000, each applied exactly once, not twice.
- A **post-payout** reversal (the order's commission was funded and held in an *earlier*, separate close) reads a real, non-zero `held_commission_minor`, and both arms get the identical reduction: test 166 §A (chargeback) and §B (refund_void) both produce `−9000` (not `−10000`) on a face-10000/bps-1000/venue-paid-9000 fixture, obligation 9000 in both cases.

No "is this post-payout" flag is needed — it falls out of the execution-order argument (and the constancy noted in §4) for free, identically for both arms.

## 6. Canonical fixture result (test 166, section A)

face=10000, commission bps=1000 (funded via the real 090/098 path — a settlement close — so a genuine held `kernel.payout` row exists), venue paid 9000 (a real `mark_payout_transfer_state` to `paid` on the settlement payout), then a FULL post-payout reversal (a lost dispute for the whole face, then a later close):

- chargeback line: **−9000** (not −10000)
- net: **−9000**
- obligation: **9000** (not 10000)
- held commission payout: **UNCHANGED** — `amount_minor=1000`, `status='pending'`, `hold_state='held'`, `hold_reason_code='unfunded_settlement'`, exactly one row, before and after the reversal (A11-A13)
- no promoter payout ever left pending/held (`mark_payout_transfer_state` structurally refuses the cause regardless, unaffected by 100)
- buyer net 0: the dispute's `amount_minor` equals the order's `total_minor` exactly (A5)
- conservation, zero hand-derived quantity, read straight from `kernel.payout`/`kernel.dispute_native`/`kernel.organization_obligation`:
  - funding side: `order.total_minor (10000) = kernel.payout(cause=settlement,paid).amount_minor (9000) + kernel.payout(cause=promoter_commission).amount_minor (1000)` (A14)
  - reversal side: `dispute.amount_minor (10000) = obligation.amount_minor (9000) + kernel.payout(cause=promoter_commission).amount_minor (1000, still held)` (A15)

Section B reproduces the identical numbers for the `refund_void` arm (a post-payout succeeded refund instead of a dispute) — obligation 9000, held commission payout still 1000/pending/held/unfunded_settlement, untouched.

## 7. No-commission and pre-close/same-close (regression guards)

- Test 166 §C: an order with no attribution at all gets `held_commission_minor = 0` throughout — the chargeback stays at the ordinary face cap, `−10000`, byte-identical to 097. No regression.
- Test 166 §D: see §5 above. `held_commission_minor` reads 0 because nothing has been funded yet for the order at seam-run time — not because of any special-case branch. There is no double-reduce: 098's own basis calculation (a completely separate mechanism, unaffected by 100) is what reduces the commission for the already-refunded face; the seams' cap reduction and 098's basis reduction never touch the same 3000 twice.

## 8. The partial-reversal window-cap behavior — still an open item (PFA-PT-5)

The shipped cap arithmetic (093/097, unchanged in shape by 100) is a **window cap** over cumulative reversals on an order, not a per-reversal proportional reduction. Subtracting a constant `held_commission` from that cap only *binds* once cumulative disputes/refunds on the order approach the reduced ceiling (`face − held_commission`); a single reversal well under that ceiling lines at its own full amount, unreduced by the commission term at all (test 166 §D1 demonstrates this directly for a refund). Whether a *proportional* (per-reversal) reduction would be more correct for a partial reversal that does **not** yet trigger the window cap is the same open question KM5's original draft filed under PFA-PT-5 item (2) — it is **not resolved by 100** (100 changes only the cap's operand, not the cap's shape) and remains an open owner-visible choice, tracked as **PFA-PT-5 item (c)**.

## 9. The held-commission payout is never minted twice, never reduced, never released (static + dynamic proof)

Static (test 166 §F): both seam bodies fail a `pg_get_functiondef ~* 'converge_held_commission'` check (absent — F1/F2), neither contains an `insert into kernel.payout` or `update kernel.payout` statement (F3/F4), `kernel.converge_held_commission` does not exist as an object at all (F5), and `kernel.close_settlement`'s own body never names it (F6 — confirming 100 did not re-create `close_settlement`).

Dynamic: sections A and B assert the exact same `kernel.payout` row (by attribution, via `_commcount166=1` and `_commrow166`'s full state tuple) before AND after the reversal that triggers the obligation cap — same `amount_minor`, same `status`/`hold_state`/`hold_reason_code`.

`kernel.record_organization_obligation` is untouched (test 166 §G): its body never names `held_commission` (G1), and its `amount = -net_minor` precondition text is present unchanged from 097 (G2) — 100 changes only what the candidate lines compute; the obligation booking logic downstream of `net` is unmodified.

## 10. Verification results (verbatim)

Full replay, own DB `snatchit_rehears_recon2`, `PATH=/opt/homebrew/opt/postgresql@17/bin`:
```
[rehearsal] REPLAY OK: 116/116 migrations applied to 'snatchit_rehears_recon2'
GATE-2  tables=27 functions=70 policies=37 triggers=26
        CI baseline: tables=27 functions=70 policies=37 triggers=26 (ci.yml EXPECT_*)
```
Kernel function count (`select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='kernel'`): **146** — unchanged, as expected for a body-only, no-new-object migration.

Own test:
```
166_venue_obligation_excludes_held_commission.sql    plan=39   ok=39   not_ok=0   psql_err=0  PASS
```

Full suite:
```
RESULT: pgTAP suite matches the expected local baseline.
```
(only the two documented local-only deltas — 060 ×2 TODO markers, 132 ×2 db-name artifacts — remain; see `docs/phase2/_impl/KRECON2.md` for the verbatim full-suite tally.)

`153_phase2_market_native_rail.sql` H58 fixed (§2) — the only other file this reconciliation touched.

`164_promoter_prorata_funding.sql` (the one file identified as a candidate for a combined held-commission + post-payout-reversal fixture, KM5 §13 original) needed **no change**: its Case A post-close refund (3000 on a face-10000/bps-1000 order whose commission is already held) never exceeds the reduced cap (`10000 − 1000 = 9000`), so the cap never binds and the refund_void amount that case's assertions actually check (commission-line count/amount, not refund_void's own amount — that file doesn't assert refund_void's value in Case A) is unaffected. Passes unchanged, 29/29.

## 11. Census note

Kernel function count stays **146** — 100 adds no function, so no test enumerating "146" needed a bump this session (unlike an earlier draft, which would have required a repo-wide +1 census bump that this reconciliation confirms was correctly reverted/never applied).

## 12. PFA

`PFA-PT-5` reconciled in `docs/architecture/_governance/POST_FREEZE_AMENDMENTS.md` this session to read: item (a) the A5 face-cap clarification — **BUILT** (100, this report); item (b) held-commission-payout convergence — **SPECIFIED, DEFERRED** to the future promoter-payout ruling (FUNDED ≠ PAID; promoter payout dark); item (c) the partial-reversal window-cap-vs-proportional question (§8 above) — **OPEN**, unresolved by 100. PENDING OWNER SIGNATURE on all three.
