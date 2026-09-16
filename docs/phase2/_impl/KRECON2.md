# KRECON2 — reconciliation of test 166 / 153 / docs to migration 100's seams-only design

Repo `/Users/josetascon/snatchit-consol`, branch `feature/venue-native-and-product-v2`. Own rehearsal DB `snatchit_rehears_recon2`, `PATH=/opt/homebrew/opt/postgresql@17/bin`. Local rehearsal only — no production, no git commit, no migrations/rollbacks/edge code touched.

## 1. What changed and why

Migration 100 was simplified by the orchestrator, after an earlier draft, to a **seams-only** obligation fix: it re-creates ONLY `kernel.settlement_primary_lines` and `kernel.settlement_royalty_lines` (both cap a post-payout reversal debit at `greatest(0, face − refund_exposure − prior_cb − held_commission_for_order)`). It no longer re-creates `kernel.close_settlement` and no longer ships `kernel.converge_held_commission` — the held-commission **payout** is never touched by 100; convergence is specified/deferred to a future promoter-payout ruling. Read `supabase/migrations/100_venue_obligation_excludes_held_commission.sql`'s header in full for the authoritative statement (339 lines, md5 `58402dbfec629abaa10b6866ec8abf29`).

The old `supabase/tests/166_venue_obligation_excludes_held_commission.sql` tested the removed `converge_held_commission` verb and errored against the shipped migration (31 psql errors on the old plan(59)). It has been rewritten.

## 2. Files touched (tests and docs only — no migration/rollback/edge code)

- `supabase/tests/166_venue_obligation_excludes_held_commission.sql` — REWRITTEN. plan(39), 39/39 passing. Sections A (canonical chargeback), B (refund_void symmetry), C (no commission — regression guard), D (pre-close/same-close — no double-reduce), E (re-close noop_replay), F (static: held commission payout never minted twice/reduced/released — grep both seam bodies), G (`record_organization_obligation` untouched).
- `supabase/tests/153_phase2_market_native_rail.sql` — H58 (~line 851) fixed: `p.prosrc !~* 'numeric|float|double|real'` false-matched the English words "real receipt" and "double-counted" inside 100's own comments in `settlement_royalty_lines`. Fixed to strip `--` line comments before the regex; assertion intent (no float/numeric arithmetic in the seam's *code*) unchanged. Verified: `double-counted` was the actual hit (grep confirmed).
- `docs/phase2/_impl/KM5_100_implementation.md` — REWRITTEN to describe the seams-only design (removed all §§ describing `converge_held_commission`/close_settlement re-creation; corrected canonical-fixture and symmetry sections to the built numbers; census note corrected to 146, unchanged).
- `docs/architecture/_governance/POST_FREEZE_AMENDMENTS.md` — PFA-PT-5 rewritten: RESOLUTION now describes the cap-clarification-only fix; the former "CONVERGENCE MECHANISM" item is explicitly marked NOT built, added as OWNER ITEM (2) "SPECIFIED, DEFERRED, NOT BUILT"; PACKAGE IMPACT corrected to "kernel functions: 146 → 146 (UNCHANGED)"; SECURITY/MONEY IMPACT corrected (no payout-side mechanism to hold to account).
- `docs/phase2/G4_PROMOTER_REVERSAL_RULING.md` — INSPECTED, no change needed. Grepped for "converge", "migration 100", "PFA-PT-5" — zero hits. The file is the pre-100 problem statement (its "question (iii)" is exactly what 100 answers) and never claimed migration 100 resolves anything via convergence; nothing stale to correct.
- `docs/phase2/_impl/KRECON2.md` — this file.

## 3. Test 166 — the five required proofs, executed numbers

All fixtures: face=10000, promoter bps=1000 (10% ⇒ 1000 commission), funded via the real 090/098 path (a genuine settlement close mints and holds the `kernel.payout` row), venue paid via a real `kernel.mark_payout_transfer_state(...,'paid',...)`.

**CANONICAL (§A, chargeback).** First close funds commission 1000, nets 9000, venue's settlement payout marked `paid`. Full lost dispute (10000) → second close: chargeback line **−9000** (not −10000), net **−9000**, obligation **9000** (not 10000). Held commission payout: `amount_minor=1000, status=pending, hold_state=held, hold_reason_code=unfunded_settlement` — IDENTICAL before and after, `_commcount=1` throughout (never minted twice). Conservation (DB rows only): funding side `10000 = kernel.payout(settlement,paid).amount(9000) + kernel.payout(promoter_commission).amount(1000)`; reversal side `dispute.amount(10000) = obligation.amount(9000) + kernel.payout(promoter_commission).amount(1000, still held)`.

**REFUND_VOID SYMMETRY (§B).** Identical shape, post-payout succeeded refund of 10000 instead of a dispute: refund_void line **−9000**, obligation **9000**, held commission payout untouched (`1000|pending|held|unfunded_settlement`, `_commcount=1`).

**NO COMMISSION (§C, regression guard).** No attribution on the order: chargeback stays at the full face cap, **−10000**, obligation **10000** — byte-identical to 097, no regression.

**PRE-CLOSE / SAME-CLOSE, no double-reduce (§D).** A 3000 refund lands before the order's first-ever close (no `kernel.payout` row exists yet, so `held_commission_minor=0` at seam-run time). First close: refund_void **−3000** (unreduced), commission funds fresh against the already-refunded face — `floor((10000−3000)×1000/10000)=700` — net **6300**, no obligation. The 3000 is reduced exactly once by each of two independent mechanisms (the refund_void seam sees 0 held-commission to subtract; 098's basis calc separately computes against the post-refund face) — proven not to double-count.

**HELD COMMISSION PAYOUT NEVER MINTED TWICE / REDUCED / RELEASED (§F, static).** `pg_get_functiondef` on both seams: neither calls `converge_held_commission` (absent as an object entirely — F5), neither contains `insert into kernel.payout` or `update kernel.payout` (F3/F4); `kernel.close_settlement`'s own body never names `converge_held_commission` (F6, confirming 100 did not re-create it).

## 4. 164 reconciliation — no change needed

`supabase/tests/164_promoter_prorata_funding.sql` Case A's "post-close refund" (a 3000 refund on order `oA` after the commission is funded/held, before any venue payout) was the one file KM5 originally flagged as a combined held-commission + post-payout-reversal fixture. Under the seams-only 100: `held_commission_minor` for order `oA` = 1000 (constant, unconverged), cap = `10000−1000=9000`; the refund is 3000, well under that cap, so it never binds — 164's assertions (which check commission-line count/amount, not `refund_void`'s own amount — that file never asserts `refund_void`'s value in Case A) are unaffected. Confirmed by execution: 164 passes **29/29 unchanged**, no "more than one row" error (there was never a second payout row to begin with, since 100 has no convergence step). No edit made.

## 5. 153 H58 — regex false positive, root cause confirmed

```
$ psql ... | grep -ino converge     → hits inside settlement_primary_lines body (comment prose "never converged", inert filter 'commission_converged')
$ psql ... | grep -io '.{20}double.{20}'  → "...mission — it is not double-counted here and do..."
```
`double-counted` (100's own comment prose in `settlement_royalty_lines`) matched the old `!~* 'numeric|float|double|real'` regex substring-for-substring. Fixed by stripping `--`-prefixed line comments before the regex (confirmed no `/* */` block comments in either seam body). 153 now passes 367/367 in isolation and in the full run.

## 6. Verification — Gate-2, kernel census, full suite (verbatim)

Fresh reset (`./scripts/rehearsal_reset.sh snatchit_rehears_recon2`):
```
[rehearsal] REPLAY OK: 116/116 migrations applied to 'snatchit_rehears_recon2'
GATE-2  tables=27 functions=70 policies=37 triggers=26
        CI baseline: tables=27 functions=70 policies=37 triggers=26 (ci.yml EXPECT_*)
```
Kernel function count: `select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='kernel'` → **146** (unchanged, as expected — 100 adds no function).

Full suite (`./scripts/rehearsal_test.sh snatchit_rehears_recon2`), verbatim tail:
```
060_payments_money.sql                               plan=12   ok=10   not_ok=2   psql_err=0  FAIL
132_replay_parity.sql                                plan=11   ok=9    not_ok=2   psql_err=0  FAIL
153_phase2_market_native_rail.sql                    plan=367  ok=367  not_ok=0   psql_err=0  PASS
164_promoter_prorata_funding.sql                     plan=29   ok=29   not_ok=0   psql_err=0  PASS
166_venue_obligation_excludes_held_commission.sql    plan=39   ok=39   not_ok=0   psql_err=0  PASS
167_recovery_venue_scope.sql                         plan=24   ok=24   not_ok=0   psql_err=0  PASS
TOTAL plan=3549 ok=3545 not_ok=4 FAILURES

==============================================================
 LOCAL-ONLY DELTAS vs the CI (real Supabase stack) run
==============================================================
  expected   060_payments_money.sql: 2 known local-only/TODO failure(s) — see header.
  expected   132_replay_parity.sql: 2 known local-only/TODO failure(s) — see header.
==============================================================
 RESULT: pgTAP suite matches the expected local baseline.
```
(The `TOTAL ... FAILURES` line is the raw per-file tally before the harness's own classification step; the harness's own verdict — the only one that matters — is the `RESULT` line: only the two documented local-only deltas (060×2, 132×2) remain, exactly as specified. Full 000–101 replay applied cleanly.)

## 7. Not touched

No migration, no rollback, no edge function file was edited. `docs/phase2/G4_PROMOTER_REVERSAL_RULING.md` was inspected and required no change (see §2). No git commit made.
