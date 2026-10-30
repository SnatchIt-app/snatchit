# T2 — pgTAP triage for migration 093 (tests 148 / 151 / 153 / 154 / 155 / 156 / 157)

**Harness:** `scripts/rehearsal_reset.sh snatchit_rehearsal_t2` → `scripts/rehearsal_test.sh snatchit_rehearsal_t2`
(local loopback PostgreSQL 17 + pgTAP 1.3.5). No remote was contacted. No migration was modified.
No commit was made.

**Authorities read:** `docs/phase2/PRIMARY_TICKETING_OWNER_RATIFICATION.md` (ratified 2026-09-02),
`docs/phase2/_impl/093_parts/10_money_settlement.sql` (read-only),
`docs/phase2/093_FINAL_PROPOSED_SCOPE.md`.

**Scope:** the seven files above only. 141/142/143/144/145/146 belong to another agent and were not
touched. The documented local-only deltas in 060/132 were not touched.

---

## Result

| | before | after |
|---|---|---|
| assertions planned | 1376 | 1385 |
| assertions failing | **13** | **0** |
| psql errors | 0 | 0 |

```
148_phase2_kernel_tickets_late_binding_fks.sql       plan=14   ok=14   not_ok=0   psql_err=0  PASS
151_phase2_venue_settlement_and_export.sql           plan=241  ok=241  not_ok=0   psql_err=0  PASS
153_phase2_market_native_rail.sql                    plan=367  ok=367  not_ok=0   psql_err=0  PASS
154_phase2_market_bridge_view_and_late_fk.sql        plan=64   ok=64   not_ok=0   psql_err=0  PASS
155_phase2_venue_promoter_engine.sql                 plan=366  ok=366  not_ok=0   psql_err=0  PASS
156_phase2_kernel_reserve_stub.sql                   plan=39   ok=39   not_ok=0   psql_err=0  PASS
157_phase2_notify_reduced.sql                        plan=294  ok=294  not_ok=0   psql_err=0  PASS
```

**Counts by category — A: 13 · B: 0 · C: 0.** Nine assertions were ADDED (net +9 plan) to keep the
strictness that two of the ratified changes would otherwise have quietly retired, and to cover two
ruling-mandated properties that had no test at all.

---

## Classification table

| # | File:line (post-edit) | Assertion | Observed | Cat | Ruling / evidence | Action |
|---|---|---|---|---|---|---|
| 1 | `148:76` | B2: five-schema routines `243` | `246` | **A** | A6 adds `kernel.sync_org_connect_state` + `kernel.get_org_connect_state`; A3 adds `kernel.settlement_primary_lines`. Verified by name against the live catalog and by `grep` over 000–092 (none of the three exists before 093). | expect `246`; delta annotated |
| 2 | `148:99` | B4: kernel = 28 tables / `109` fns | 28 / `112` | **A** | same three kernel routines. **kernel TABLES are unmoved at 28** — the relation half of the guard is untouched. | expect `112` |
| 3 | `151:551` | C40b: stale `venue_finance` open ⇒ `P0002` | `42501` | **A** | A3 conjoins the E-76 current-operator clause onto `venue.open_settlement`'s venue arm (`093:120-124`, the shape `close_settlement` already carries at 087:299-300). Authority now refuses before scope. **Predicted verbatim** by the slice author at `10_money_settlement.sql:31-35`. | expect `42501`; **+C40b2 / +C40b3** added, below |
| 4 | `153:663` | H1: st1 closes at net `15000` | `20000` | **A** | A3/A5 primary revenue seam. st1 is event1-scoped; the seam emits `+5000` for `order3` (finalized at FIX-2 with a `kernel.payment_native` row) on top of the hand-written `primary_sale/15000` for `order1`, which its own dedupe skips. | expect `20000` |
| 5 | `153:770` | H46: st2 `gross 0 … net −15000` | `gross 5000 … net −10000` | **A** | st2 is the PERIOD grain (`event_id` NULL, unbounded period); the seam's period arm — 088:347-351's scope idiom — picks up `order2` (event2/session2 at venue1, 1 × 5000, FIX-3). `refunds_minor` is still exactly `15000`; the OWNER TEST B property is unchanged. | expect `5000 / 0 / 15000 / −10000` |
| 6 | `153:779` | H49: prior settlement `15000` | `20000` | **A** | tracks #4. The property — st1 was never clawed back, carries no `chargeback` line — is asserted identically. | expect `20000` |
| 7 | `154:56` | A10: `market/kernel/catalog = 22/109/16` | `22/112/16` | **A** | as #1. **Market and catalog — the two schemas this guard exists to protect — are unmoved.** | expect `22/112/16` |
| 8 | `155:809` | G10: `gross 0 / fees 4600 / net −4600` | `gross 100000 / fees 4600 / net 95400` | **A** | A5: venue entitlement begins at configured face value. Gross = 16 lines over s1's event1 scope: `o1 15000 · o12 10000 · o14 10000 · 5000 ×13`. `o19` is correctly dropped (EUR vs USD — the seam's currency filter, 088:346's idiom); `odoor` is `pending` with no `payment_native`. **`fees_minor` is byte-unchanged at 4600** — the waterfall claim the row exists to prove. | expect `100000 / 4600 / 0 / 95400` |
| 9 | `155:811` | G10b: `payout_ids = []` | one payout | **A** | net is now positive, so 087's **unmodified** `if v_net > 0` arm mints the settlement payout. This is A4 working as written: `100000 − 4600 = 95400` — commission reduces distributable *before* venue money is released. | rewritten **stricter** (below) + **new G10c** |
| 10 | `156:45` | A20: five-schema routines `243` | `246` | **A** | as #1. 091's own schemas are untouched, so "091 creates NO function" is undiminished. | expect `246` |
| 11 | `156:57` | A23: `catalog.platform_config` rows `43` | `47` | **A** | four new keys, each ONE row at version 1, each seeded OWNER-UNSET (`'null'::jsonb`, PFA-9 shape): `inventory.per_user_active_hold_max`, `inventory.hold_ttl_interval` (scope item 3), `ticket.expiry_grace` (D2), `fee.buyer_service_bps` (A5). Enumerated from `093:2218/2235/2328/2388`. | expect `47` |
| 12 | `157:141` | A20: distinct config keys `43` | `47` | **A** | as #11. | expect `47` |
| 13 | `157:180` | A46: five-schema routines `243` | `246` | **A** | as #1; notify itself unmoved at 17. | expect `246` |

Everything that did **not** move was checked too, and each is a real guard that 093 could have
tripped: five-schema relations `75`, kernel tables `28`, venue tables `29`, market tables `5`,
policy register `72`, `cron.job` `19`, the SEAM-2a register `19` (155 A13) and the 12-hook spot
census (157 A49). 093's only new storage objects are two partial unique indexes, which are not
`relkind` relations, so `75` is correct rather than lucky.

---

## The four properties the brief singled out — all VERIFIED, none category C

Proven behaviourally against the rehearsal database with instrumented copies of the suite
(scratchpad only; nothing committed).

**1. No promoter commission payout is released, unheld, or advanced by anything in 093.**
PASS. After 155's close, all seven commission payouts read
`promoter_commission / pending / held / unfunded_settlement` — G12 and G12c (a held payout cannot be
advanced to `paid`) are green and untouched. `kernel.close_settlement`,
`kernel.settlement_primary_lines` and `kernel.settlement_commission_lines` contain **no** reference
to `hold_state`, `held_at`, `hold_reason` or `release_payout` (checked against `pg_proc.prosrc`).
The single release in the suite (155 G12d) is a deliberate `platform_risk` call through
`kernel.release_payout`, i.e. a test *of* the manual Control-5 path, not an act of 093.
The org settlement payout at G10c is a different payout — `cause='settlement'`, organization payee —
and its existence is exactly what A4 requires once gross is non-zero.

**2. A refund produces its own NEGATIVE line and never amends the original positive line.**
PASS. Probe: a `kernel.refund` of 4000 against `order1`'s payment, then a close, yields
`refund_void / −4000` and header `g=0 f=0 r=4000 n=−4000`. `order1`'s original `primary_sale` line
is still exactly `+15000`, and exactly **one** `primary_sale` line for that order exists across all
settlements. A second refund of 20000 is capped at the remaining `15000 − 4000 = 11000` headroom, so
the cumulative debit equals face value exactly, across two separate closes.

**3. The same order cannot be lined in two different settlements.**
PASS, and now **asserted** — see 151 C20e/C20f. `settlement_one_primary_sale_line_ever` and
`settlement_one_refund_void_line_ever` both exist with the 090:214-215 shape
(`unique (cause_ref) where cause = '…'`) and raise `23505` on a cross-settlement duplicate.

**4. `close_settlement`'s named conflict clause does NOT swallow a global-index violation.**
PASS, and now **asserted** — see 151 C20g/C20h. The shipped body carries
`on conflict on constraint settlement_line_cause_uq do nothing`. Replaying that exact INSERT form
against a cause_ref already lined in another settlement still raises `23505`; against the same
settlement's own line it is still silently tolerated, which is precisely 087's old behaviour.

---

## Assertions ADDED (net +9). Every one is a strengthening.

| Id | File | Why it exists |
|---|---|---|
| **C20e** | 151 | ruling A5 / scope item 13: an order lined `primary_sale` in one settlement cannot be lined in another — `23505`. Had **zero** coverage. |
| **C20f** | 151 | same for `refund_void`: a refund is debited exactly once, platform-wide, for all time. |
| **C20g** | 151 | `close_settlement`'s NAMED on-conflict target does not swallow a global-index violation. A bare `do nothing` would drop a revenue line out of gross with no error, in a ledger with no delete. |
| **C20h** | 151 | …while still tolerating exactly what 087 tolerated — a re-close replaying its own settlement's own line. |
| **C40b2** | 151 | **restores the exact `P0002` coverage C40b gave up.** With a caller who genuinely passes the authority gate (org1's `org_owner`), the PERIOD grain still FAILS CLOSED over a room org1 no longer operates — 087:254-255 kept verbatim; A3 widened the EVENT grain only. |
| **C40b3** | 151 | the positive half of ruling A3's booked-event fix: the EVENT grain now OPENS after an operatorship transfer, because `catalog.event.org_id` is still org1. This is the terminal-unsettleability bug A3 exists to close. |
| **G10c** | 155 | pins the new org payout to five facts (organization/org1, `cause=settlement:s1`, `95400`, `USD`, `pending`, `hold_state='none'`) where G10b previously pinned one. A stray second payout, wrong payee, wrong amount or mis-set hold now all fail. |
| **G41c** | 155 | ruling A4's new `partially_refunded` exclusion. 090:1535 excluded only `('refunded','cancelled')`; a direct partial refund voids no atoms (085:571-573), so the surviving-atom basis was unreduced and FULL commission would be paid on partly refunded revenue. Had **zero** coverage. |
| **G41d** | 155 | …and no commission payout is minted for such an order — the exclusion fires before `pay_promoter_commission` runs, so nothing is accrued, held **or** released. |

Coverage that G10b used to carry — *no org payout on a NEGATIVE net* — is **not** lost: 153 H48
(`NEGATIVE_SETTLEMENT_CARRY`) still asserts `payout_ids = []` on a negative close and is unaffected
by 093.

Two fixture cause_refs in 151 were pinned from `gen_random_uuid()` to literals so C20e–C20h can name
them. Same three rows, same causes, same amounts — C16/C16a/C16b arithmetic untouched. Every insert
in C20e–C20g **fails**, so the line ledger gains nothing and C36/C37's censuses are unmoved. This is
the only category-B-shaped edit in the set, and it supports new assertions rather than rescuing an
old one.

---

## Recorded, not fixed

**Coverage gap — the refund arm of `kernel.settlement_primary_lines` is proven but not asserted.**
Property 2 above is verified by probe and is correct. It was **not** landed as a test: 153 is the
only suite of the seven with a real primary-order + payment fixture, and that fixture is load-bearing
in both directions — every payment is either charged back (`pay1`/`pay5`/`pay7`, pinned to zero
refunds by `153:1114` L21) or consumed by `catalog.cancel_event` later in Section L, and a fresh paid
order on `event1` changes `L19`'s `refunds_created` count. Adding a refund there means rebalancing
assertions that have nothing to do with 093, which is a worse trade than the gap. It should be added
deliberately, with its own fixture, rather than wedged into 153's. The probe that proves it is
recorded in full under "the four properties" above.

**Not a defect, worth knowing (155).** `o2` is credited `+5000` by the primary seam even though its
order status is `refunded`, and no offsetting `refund_void` appears. That is correct: 155:772 sets
`status='refunded'` with a bare `UPDATE` and writes **no** `kernel.refund` row, and the debit arm is
keyed on `kernel.refund`. The seam's own contract (`10_money_settlement.sql:199-202`) is that a
refunded order still emits its positive line, because it *was* paid; dropping the credit would leave
a naked negative line and drive net below zero.

**Owner items already surfaced by 093 and unchanged here:** `ticket.expiry_grace` and
`fee.buyer_service_bps` ship seeded OWNER-UNSET (D2 / A5), and Stripe processing-cost allocation has
no ratified ruling (A5). None is encoded in a test, correctly.

---

---

# PASS 2 — the second money train (093 reassembled, md5 `6ab87362e3a6983d0ad1355758835402`, 4038 lines)

Two money P0 fixes and a refund-executor slice landed after pass 1. **`149_phase2_kernel_money_native.sql`
is added to T2's scope** (previously unowned). All eight files re-triaged against a fresh
`rehearsal_reset.sh snatchit_rehearsal_t2`.

| | pass-1 end | pass-2 start | pass-2 end |
|---|---|---|---|
| assertions planned | 1385 (7 files) | 1515 (8 files) | **1529** |
| assertions failing | 0 | **12 + 2 aborted files** | **0** |
| psql errors | 0 | **366** (151: 362, 149: 4) | 0 |

```
148  plan=14   ok=14   151  plan=253  ok=253   154  plan=64   ok=64    156  plan=39   ok=39
149  plan=132  ok=132  153  plan=367  ok=367   155  plan=366  ok=366   157  plan=294  ok=294
```

**Counts by category — A: 8 · B: 6 · C: 0.**

## Pass-2 classification

| # | File | Symptom | Cat | Ruling / evidence | Action |
|---|---|---|---|---|---|
| 14 | 149:665 | file ABORTS — `no_pending_connect_ref` on `set_org_payout_destination` | **B** | A7/A9 (RT-A-3). A bind now requires `kernel.stage_org_connect_ref` (service_role only) to have staged that exact identifier. Closes the P0 where an attacker bound an `acct_` present in neither `public.profiles` nor the archive, straight through the RPC as `authenticated`. | fixture stages as `service_role` then binds as the human; **L3 unchanged byte for byte**. **+L2a/+L2b** added |
| 15 | 151:494 | `set_org_payout_destination('acct_PROB87')` | **B** | same | **+C30a** stages first; C31a unchanged |
| 16 | 151:571 | `set_org_payout_destination('acct_NEW2')` | **B** | same | stage as service_role, restore the `fan151` session; C31m unchanged |
| 17 | 151:363 | file ABORTS — `payout_held` on `request_org_payout` | **A+B** | the unbounded-refund-exposure gate (below) | **+C20i..C20n** prove the held arm and take the contracted exit, so C21–C31i1 run unchanged; **+C28a/+C28b** prove the unheld arm |
| 18 | 153 H2/H6/H11/H12 | the dispute-freeze leg finds the payout already held | **B** | the gate again — but this section exists to prove the DISPUTE hold | fixture sets the key before st1's close so `po1` is minted unheld; **all four assertions unchanged** |
| 19 | 155 G10c | payout is `held`, my pass-1 assertion said `none` | **A** | 155 never sets the key, so `held`/`unbounded_refund_exposure` IS the contract there | assertion **strengthened** — now pins `hold_state`, `hold_reason_code`, `held_by`, `held_at` on top of the previous five facts |
| 20-25 | 148 B2/B4 · 154 A10 · 156 A20/A23 · 157 A20/A46 | census drift | **A** | kernel 112 → **116**, five-schema 246 → **250**, config 47 → **48** | expectations moved to the exact new literals, each with the routine named |

### The seven new kernel routines, named (not inferred from a delta)

`settlement_primary_lines` (A3) · `sync_org_connect_state` + `get_org_connect_state` (A6) ·
`stage_org_connect_ref` + `get_org_connect_ref` (A7/A9, RT-A-3) · `get_refund_execution_context`
(D3) · `is_order_buyer` (F). Verified by `grep` over 000–092: none pre-exists. `close_settlement`,
`set_org_connect_ref`, `set_org_payout_destination`, `settlement_royalty_lines` and
`settlement_commission_lines` are REPLACEMENTS and add nothing. Everything else still holds:
relations 75, kernel tables 28, venue 29, market 5, policies 72, cron 19.

The fifth config key is `settlement.refund_window_interval`, seeded `'null'::jsonb`. **Unset is the
SAFE state** — every settlement payout is minted HELD until it is set — so *setting* this key is the
dangerous act, and both census comments say so.

## The unbounded-refund-exposure gate — now covered on both arms

A refund succeeding AFTER its settlement closed can never be collected: its debit lands in a
settlement nobody opens, or one that nets negative, and a negative net mints no payout and creates
no receivable because the schema has no carry-forward object. Measured: lifetime net 8400 against
19000 paid out over five closes. 093 created the exposure by activating the credit side.

* **key UNSET** — 151 C20i/C20j/C20k/C20l: the close reports `payout_hold`; the payout is minted
  `pending`/`held`/`unbounded_refund_exposure` at the full net with `held_by` NULL; **the header
  still records `net_minor` 8500 / `gross_minor` 10000 and all three lines stand** (the obligation is
  durable — ruling A3; only the money is immobilised); and the hold BITES — a held payout cannot be
  requested.
* **the exit** — 151 C20m/C20n: `kernel.release_payout` (platform_risk/platform_admin, Control-5)
  clears it and `status` was never overwritten.
* **key SET** — 151 C28a/C28b: the close reports no hold and the payout is minted `none`, at the
  full net, with nothing else about it changed.

## Also newly covered

* **151 C20o/C20p/C20q** — `settlement_amount_overflow`. A gross beyond the int4 money columns is
  now refused BY NAME with the remedy in the message, before the UPDATE, so the header is left
  `open` and retryable instead of wedged half-written behind a bare 22003 that named nothing.
* **149 L2a/L2b** — the A7/A9 two-key control: the platform stages what it minted (service_role
  only), and a matured `org_owner` on an aal2 session **still** cannot bind an identifier the
  platform never staged (`connect_ref_not_platform_minted`; `no_pending_connect_ref` is the
  nothing-staged arm). Neither credential alone can bind an account.

## Ruling A4 re-verified under the new pass

Unchanged and still green: all seven promoter commission payouts remain
`pending`/`held`/`unfunded_settlement` (155 G12), a held commission payout cannot be advanced to
`paid` (G12c), and 093 releases nothing. 155 G10c now additionally proves the ORG settlement payout
is held too, so after this pass **no money at all moves out of a close**.

## Verified by probe, not landed as a test (pass 2)

The replaced `kernel.settlement_royalty_lines` shares one per-order headroom pool with `refund_void`,
capped at face, refunds senior. **Both claims confirmed** against the rehearsal database on 153's
fixture (order2, face 5000, `pi_88_6`):

* dispute 5600 (face 5000 + a 600 buyer-side service fee), **no refund** ⇒ the seam offers
  `chargeback:-5000`, **not −5600**. The fee stays with the platform, which is ruling A5.
* the same dispute **plus a succeeded full-face refund** ⇒ the chargeback arm offers **nothing** —
  the refund is senior and consumes the whole headroom, so one exit is debited once, not twice.
  Note the exposure is read from `kernel.refund` directly rather than from lines, so it is correct
  even in an event-scoped settlement where the matching `refund_void` is out of scope.

Not landed for the same reason as the pass-1 refund-arm gap: 153 is the only suite of the eight with
a real primary-order + payment fixture, and every one of its payments is pinned either by `L21` (zero
refunds on `pay1`/`pay7`) or by the `cancel_event` cascade at `L19`. Building the case in place means
rebalancing assertions that have nothing to do with 093. It should be added with its own fixture.

---

# PASS 3 — the settlement-maturity fix (093 md5 `7ff74d6c9a6832ea694f7ffd067c0bc5`, 4249 lines)

The payout hold stopped being `v_held := v_refund_window is null` — one test of one config key,
which made an owner config VALUE a hidden feature flag for payout logic that did not exist. It is
now a conjunction of eight fail-closed predicates in causal order, each with its own
`hold_reason_code`, plus an additive `payout_hold_detail` key carrying the whole vector.

| | pass-3 start | end |
|---|---|---|
| assertions planned | 1529 | **1540** |
| assertions failing | 6 + **1 aborted file** | **0** |
| psql errors | **341** (all 151) | 0 |

**Counts by category — A: 5 · B: 6 · C: 0.**

## Pass-3 classification

| # | File | Symptom | Cat | Evidence | Action |
|---|---|---|---|---|---|
| 26 | 151 C28a/C28b + 341-error cascade | the key was set, but the payout still held | **B** | the settlement's only line was a hand-inserted `primary_sale` with a random `cause_ref`, so the covered set resolved to nothing (`covered_set_unresolvable`) | fixture builds a real past session + order + `kernel.payment_native`; **C28a/C28b unchanged** |
| 27 | 151 s5 (C31a1–C31i1) | same, would have held `p5` | **B** | same | real covered order; the probation lifecycle is unchanged |
| 28 | 151 s9 (C31j–C31q) | same, org2 | **B** | same | real covered order on a past session of event2 |
| 29 | 153 H2/H6/H11/H12 | `po1` held, so the dispute leg had nothing to hold | **B** | st1 covers order1+order3 on `session1`, whose `ends_at` the fixture puts 10 days in the FUTURE ⇒ `maturity_not_elapsed` | `session1` moved to the past for **the duration of the close only** and restored immediately; **all four assertions unchanged** |
| 30-32 | 151, 155, 157, 156, 153 comments | pinned the OLD key name | **A** | the key is `payout.settlement_maturity_interval`; the old spelling is not read as a fallback | every reference updated; the config census stays **48** — pass 3 renamed a key, it did not add one |

### Why the rename is right, recorded so it is not undone

`settlement.refund_window_interval` named refund **eligibility** — how long a buyer may still ask
for money back. That policy exists and is owned by different keys entirely
(`refund.buyer_self_service_window_hours`, `refund.request_ttl_hours`). This value is how long
**after the event** the venue's money must sit still, so it belongs under `payout.%` — and that
prefix is load-bearing rather than cosmetic: `078:1145-1147` puts every `payout.%` key under DUAL
CONTROL, so setting it now parks for a second `platform_admin`. `unbounded_refund_exposure` is
retained verbatim as the policy-unset reason code, which is why 151 C20i..C20n survived untouched.

## NEW COVERAGE — the conjunction (151 C28c..C28l, 11 assertions)

The gate had none. Each case starts from **the exact shape that just released at C28a/C28b** — a
real order on a session that ended 30 days ago, under a 7-day policy — and breaks **exactly one**
predicate. A case that released would mean that predicate was decorative.

| Assertion | Predicate broken | Expected |
|---|---|---|
| C28c | session ended an hour ago, policy 7 days | `maturity_not_elapsed` |
| C28d | covered session has NULL `ends_at` (`078:806` requires only `starts_at`) | `maturity_instant_unknown` |
| C28e | a **pending** `kernel.refund` on a covered payment | `refund_in_flight` |
| C28f | an **open** dispute (`needs_response`) on a covered payment | `dispute_open` |
| C28g | `cause_ref` resolves to no order | `covered_set_unresolvable` |
| C28h | maturity interval of **−1 days** | `maturity_policy_invalid` |
| **C28i** | **nothing** — the control | **`(released)`** |
| C28j | two covered sessions, one long past and one an hour old | `maturity_not_elapsed` — the anchor is `max(ends_at)`, not `min` |
| C28k | — | the seven held probes carry **six distinct** reason codes |
| C28l | — | every one is `held`/`pending`, `held_by` NULL, `held_at` set |
| C28b1 | — | `payout_hold_detail` is NULL when nothing is held |

C28i is what makes C28c..C28h attributable: the fixture is otherwise identical, so each hold is
caused by the one predicate it broke and by nothing else. **No single predicate releases the money
on its own** — which is what the owner's instruction was about.

The anchor is `max(event_session.ends_at)` over the settlement's **own money lines** — not the
header scope, and not `period_end` (nullable, and bound against `starts_at`). C28j pins that it is
the later of two sessions: taking the earlier would pay while an event the money belongs to had
barely finished.

## Fixture helpers added to 151

`tap._sess151` (a session with an explicit, possibly NULL or past, end), `tap._cov151` (payments row
+ `venue."order"` + `kernel.payment_native`, returning the order_id used as a `primary_sale`
cause_ref), and `tap._probe151` (open → one line → close → report the hold reason). Two details are
deliberate and load-bearing:

* the probe order is left **`pending`**, so the covered set resolves through it while
  `kernel.settlement_primary_lines` (which requires paid/partially_refunded/refunded) never sweeps
  it into some other settlement;
* `tap._probe151` is **INVOKER** rights, because `tap.login` calls `set_config('role', …)`, which
  PostgreSQL refuses inside a `SECURITY DEFINER` function.

151 C36/C37 (absolute RLS censuses) move 8 → 16 headers and 11 → 19 lines. That delta is **this
file's own fixture** — s8 plus the eight one-line probe settlements — not a 093 behaviour change,
and the annotation says so. The property is undiminished: org1's finance role reads all of its own
and none of org2's.

## Whole-suite state after pass 3

```
TOTAL plan=2974 ok=2970 not_ok=4
  expected 060_payments_money.sql: 2 known local-only/TODO failure(s)
  expected 132_replay_parity.sql:  2 known local-only/TODO failure(s)
 RESULT: pgTAP suite matches the expected local baseline.
```

Every file in the suite passes. The only four failing assertions are the two documented local-only
delta sets: 060's two pinned `todo()` markers, and 132's two `cron.job."database"` name artifacts
(a rehearsal database cannot be named `postgres`).

## Statement

No test was weakened. Every changed expectation is pinned to an exact literal, with a
`-- 2026-09-02 (package 093)` annotation naming the ratified ruling and the derivation. No assertion
was converted to a range, a tolerance, a `todo()`, or a skip. `supabase/migrations/093_primary_ticketing.sql`,
`docs/phase2/_impl/093_parts/**` and migrations 000–092 were not modified.
