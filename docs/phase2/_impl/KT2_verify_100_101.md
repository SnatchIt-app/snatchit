# KT2 — verification + reconciliation of migrations 100/101

Verifier T2. Scope: census bump for 100, one new pgTAP test (167) proving 101's
fix for ADV P0-1, full-suite reconciliation, rollback battery. **Migration and
rollback files were never edited** — only `supabase/tests/*`.

## 1. Census bump for migration 100 (+1 kernel function: `kernel.converge_held_commission`)

KM5 §13 listed six files/locations. All six were bumped exactly as specified,
**plus three more literal `280`-routine assertions KM5's own list omitted**
(148:75, 156:45, 157:197) — these are the SAME five-schema routine total
(`kernel`+`venue`+`catalog`+`market`+`notify`) asserted a second time per file
and would have failed post-100 if left at 280. Grep-verified afterward: zero
remaining live `), 146` or `), 280` assertions anywhere in `supabase/tests/*`.

| File | Assertion(s) | Old → New | plan() |
|---|---|---|---|
| `supabase/tests/141_phase2_identity_orgs_deletion.sql:164` | A14, kernel fn census | 146 → 147 | 213 (unchanged) |
| `supabase/tests/142_phase2_catalog_config_and_seeds.sql:1327,1361` | K3, kernel fn census | 146 → 147 | 261 (unchanged) |
| `supabase/tests/143_phase2_ticket_custody_kernel.sql:143,175` | A32, kernel fn census | 146 → 147 | 155 (unchanged) |
| `supabase/tests/144_phase2_venue_staff_authz.sql:94,125` | A14, kernel fn census | 146 → 147 | 118 (unchanged) |
| `supabase/tests/148_phase2_kernel_tickets_late_binding_fks.sql:75` | (unlisted by KM5) five-schema routines | 280 → 281 | 14 (unchanged) |
| `supabase/tests/148_phase2_kernel_tickets_late_binding_fks.sql:120,137,175` | B2/B4, five-schema + kernel fn census | 280→281, 146→147 | 14 (unchanged) |
| `supabase/tests/154_phase2_market_bridge_view_and_late_fk.sql:49,78` | A10, market/kernel/catalog triple | 22/146/16 → 22/147/16 | 64 (unchanged) |
| `supabase/tests/156_phase2_kernel_reserve_stub.sql:45` | (unlisted by KM5) A20, five-schema routines | 280 → 281 | 39 (unchanged) |
| `supabase/tests/157_phase2_notify_reduced.sql:197` | (unlisted by KM5) A46, five-schema routines | 280 → 281 | 294 (unchanged) |
| `supabase/tests/167_recovery_venue_scope.sql` | new file | — | 24 |

All nine touched files ran green at their new literals on the final full-suite
run (below): 141=213/213, 142=261/261, 143=155/155, 144=118/118, 148=14/14,
154=64/64, 156=39/39, 157=294/294.

## 2. New test: `supabase/tests/167_recovery_venue_scope.sql` (plan 24)

Proves migration 101's fix for ADV P0-1 (`docs/phase2/_impl/KADV_adversarial_reproof.md`):
`kernel.organization_obligation_recovery_guard()` (096:518-582, body-only
re-created by 101) now refuses a `transfer_reversal` recovery whose reversed
payout's venue differs from the obligation's own `venue_id`.

**Fixture** (modeled on 162's payout-reversal/obligation-recovery idiom and
163's two-venue-one-org shape): org1 with venue A and venue B, each with its
own event/session/order.
- Venue A: settlement SA1 paid (50000) → a lost dispute on that order → a
  second, period-scoped close SA2 nets -50000 → 097's automatic
  `settlement_shortfall` booking stamps `venue_id = venue A` (obligation
  `obA`, the 163 A8-A13 shape reused). Venue A's own paid SA1 payout is then
  fully reversed (`kernel.record_payout_reversal`) → fact `trr_167a`, bound
  via payout → SA1 → `venue_id = venue A`.
- Venue B (same org1): settlement SB1 paid (30000), fully reversed → fact
  `trr_167b`, bound to venue B.
- org2/venue X: an independent settlement_shortfall obligation `obX` (20000),
  built the same way, for the cross-org proof.

**Assertions** (24 total; `01`-`10` are fixture control — nets, paid state,
obligation shape/venue_id/status):
- **(a) `11`** — `record_obligation_recovery(obA, 20000, 'transfer_reversal', 'trr_167b', …)` is **REFUSED**: `precondition_failed: reversal_venue_mismatch — trr_167b reversed a payout of venue <B>, the obligation originates at venue <A> (no cross-venue netting, ruling G5)`. `12`/`13`: obA is untouched, still outstanding at 50000. **This is the P0 closing.**
- **(c) `14`-`16`** — a `manual` recovery of 20000 on obA succeeds (`status='ok'`), outstanding falls to 30000, still `outstanding` — proving 101's venue predicate only gates `source_kind='transfer_reversal'`, exactly as designed.
- **(b) `17`-`19`** — the SAME obA, completed by venue A's own `trr_167a` (30000): `obligation_status='recovered'`, `resolution_reason_code='recovered:transfer_reversal'`, outstanding reads 0. **Matching-venue recovery is allowed.**
- Cross-org fixture (`20`-`21`): obX booked, `venue_id = venue X`, org2.
- **(d) `22`** — `record_obligation_recovery(obX, 5000, 'transfer_reversal', 'trr_167b', …)` is **REFUSED**: `precondition_failed: reversal_org_mismatch — trr_167b reversed a payout of organization <org1>, the obligation belongs to <org2>` — proving 096's original org-level check (untouched by 101) still fires, and fires *first* (101:96-99 precedes 101:105-113). `23`/`24`: obX untouched, still outstanding at 20000.

Note on fixture design: `(d)` deliberately reuses `trr_167b` (never actually
linked to an obligation — the `(a)` attempt threw *before* any insert) rather
than the already-consumed `trr_167a`; citing `trr_167a` a second time would
have hit `kernel.record_obligation_recovery`'s own `recovery_source_already_
linked` uniqueness guard (096:755) first, for an unrelated reason, and not
have exercised the org-mismatch predicate at all.

Two authoring bugs found and fixed while iterating to green (both in my own
167 file, not in 100/101 or any other test):
1. `record_payout_reversal`'s `p_stripe_transfer_ref` regex is `^tr_[A-Za-z0-9]+$` — **no underscore permitted after the `tr_` prefix**. My first draft used `tr_167_a` etc.; renamed to `tr_167a`/`tr_167b`/`tr_167x`.
2. `throws_like`/`sqlerrm` returns the raw exception message text with **no `P0001:` SQLSTATE prefix** — my expected strings incorrectly prepended one; removed.

## 3. Full-suite reconciliation — STOP, do not edit 100/101

`./scripts/rehearsal_reset.sh snatchit_rehears_t2` → **REPLAY OK: 116/116**,
Gate-2 `tables=27 functions=70 policies=37 triggers=26` unchanged (matches CI
baseline) on every run.

`./scripts/rehearsal_test.sh snatchit_rehears_t2` does **NOT** report "matches
the expected local baseline." After my 167 fixes, the suite is deterministic
and stable at:

```
TOTAL plan=3569 ok=3539 not_ok=8 FAILURES

==============================================================
 LOCAL-ONLY DELTAS vs the CI (real Supabase stack) run
==============================================================
  expected   060_payments_money.sql: 2 known local-only/TODO failure(s) — see header.
  expected   132_replay_parity.sql: 2 known local-only/TODO failure(s) — see header.
  REGRESSION 153_phase2_market_native_rail.sql: not_ok=1, expected 0.
  REGRESSION 155_phase2_venue_promoter_engine.sql: not_ok=1, expected 0.
  REGRESSION 164_promoter_prorata_funding.sql: 169 psql error(s) — the file aborted; assertions did not all run.
  REGRESSION 166_venue_obligation_excludes_held_commission.sql: not_ok=1, expected 0.
==============================================================
 RESULT: REGRESSION — a failure outside the documented delta set.
```

166 is **migration 100's own test** (KM5's deliverable). Per the brief:
**STOP — do not edit 100.** Reported below rather than worked around. 153,
155 and 164 are pre-existing, frozen tests (packages 088/090/098 respectively
— none of them mine, none touched by this verification pass) that newly
regress under 100. All four failures were reproduced on repeat full resets
(not transient) and traced to file:line evidence; 166 alone, run in isolation,
passes — the failure is order/timing-dependent, not a fixture bug in 166
itself, and root-caused below.

### Finding 1 (P0) — 166 B4 / migration 100's own convergence lookups have no deterministic tiebreaker

`supabase/tests/166_venue_obligation_excludes_held_commission.sql:301` (B4)
expects the "current" `kernel.payout` row for a converged attribution to read
`hold_reason_code = 'commission_converged'`, via
`tap._commrow166` (166:152-155):
```sql
SELECT po FROM kernel.payout po WHERE po.cause='promoter_commission' AND po.cause_ref=p_attr
  ORDER BY po.created_at DESC LIMIT 1
```
`kernel.payout.created_at` (085:134) is `timestamptz not null default now()`.
Postgres's `now()` is **frozen for the whole transaction** — and every pgTAP
test file runs as one `BEGIN…ROLLBACK`. `kernel.converge_held_commission`
(100:675-778) VOIDS the original row (`hold_reason_code = 'commission_
converged'`, status/hold_state unchanged) and, when surviving > 0, INSERTs a
**second** row for the same `cause_ref` (100:750-759) — in the **same
transaction**, so both rows carry the **identical** `created_at`. `ORDER BY
created_at DESC LIMIT 1` over a tie has no defined winner — Postgres breaks
it by physical scan order, which is not guaranteed stable run-to-run (heap
layout, buffer state, planner choice). This is exactly the "transient…
catalog-cache artifact" KM5 §12 flagged as unconfirmed and asked the
orchestrator to watch for; it reproduced here, deterministically, once run as
part of the full suite (not once in 13 runs as KM5 saw — every full-suite run
in this session hit it). `kernel.close_settlement`'s own `v_conv_live` lookup
(100:585-590) and `kernel.converge_held_commission`'s own `v_live` lookup
(100:731-737) use the identical `ORDER BY created_at DESC … LIMIT 1` pattern
internally — those happen to be safe today only because their `WHERE`
clause already excludes converged rows, leaving at most one candidate at the
time they run; `tap._commrow166` carries no such filter (166:152-155
comment: "any state — chained convergence can leave several") and is the one
that actually observes the tie. **Not a data-correctness bug in 100's own
kernel bodies** (the converge logic itself is idempotent and DB-bound), but a
latent nondeterminism whenever anything — this test included — reads back
"the most recent" `kernel.payout` row for an attribution without a tiebreaker
past `created_at`. Fix candidates (not applied — out of scope): add
`payout_id`/a serial ordinal as a secondary `ORDER BY` key everywhere this
pattern appears, or give `kernel.payout` a monotonic sequence column.

### Finding 2 (P0) — 155 B18: 100 adds a SECOND minter of `cause='promoter_commission'` payouts

`supabase/tests/155_phase2_venue_promoter_engine.sql:311-313` (B18) is a
writer-fence: exactly one function in `venue|kernel|market|catalog` may
contain both the literal `promoter_commission',` and `insert into
kernel.payout`. `kernel.converge_held_commission` (100:750-759) contains
both — it INSERTs a fresh `cause='promoter_commission'` row when
`p_surviving_minor > 0` (100:748-759, documented by 100's own header,
100:107-116, as deliberate: "a FRESH payout row is minted… to every OTHER
reader it is indistinguishable from a commission funded fresh"). B18 now
counts 2 (`pay_promoter_commission` and `converge_held_commission`), fails
the `= 1` assertion. This is a genuine, intentional design choice in 100
that conflicts with a previously-ratified single-writer invariant a frozen,
pre-100 test encodes. Whether B18's invariant should be relaxed (a second,
narrowly-scoped, DB-gated minter is arguably still "one contracted path") is
an owner call, not mine to make.

### Finding 3 (P0) — 164 G4: 100's convergence directly contradicts the G4 "no reduction" ruling a frozen test encodes

`supabase/tests/164_promoter_prorata_funding.sql:196-197` (G4) — Case A: a
funded/held commission payout, then a refund AFTER the commission line
exists, then a second close — asserts the payout **stays** `held`/
`unfunded_settlement` with its original `amount_minor = 1000`, captioned
*"no release, no reduction (PROMO §5.3: the org absorbs, the promoter's
already-funded claim is not pursued)"*. This is precisely 100-B's trigger
shape (100:568-591: any close whose `venue.settlement_line` carries a
`chargeback`/`refund_void` line joined to an attribution via `order_id`), so
100's own converge loop now fires on it, voids the original row, and 164's
next statement (line ~206, `format($$SELECT kernel.mark_payout_transfer_
state(%L, …)$$, (SELECT po.payout_id FROM kernel.payout po WHERE
po.cause='promoter_commission' AND po.cause_ref = …))`) hits `ERROR: more
than one row returned by a subquery used as an expression` — there are now
two `kernel.payout` rows for that `cause_ref` — aborting the rest of the file
(169 downstream statements report "current transaction is aborted"; the
actual G4 assertion itself reports `not ok 7`, `have: unfunded_settlement`
i.e. the assertion's own single-row assumption already breaks before the
abort). KM5 §13's own search for a "combined fixture" (a real funded
commission AND a post-payout chargeback/dispute on the same order) checked
164 specifically and concluded "unaffected by construction," but only
examined 164's **dispute**-based cases (`dp_98_1`/`dp_98_2`, pre-close by
construction); it did not examine Case A's **refund**-based G4 scenario
(164:184-197), which is exactly the missed combined fixture — a real,
post-payout `refund_void` line landing in a second close on an order that
already carries a funded/held commission. This is the load-bearing finding:
**100's stated purpose (exclude held commission from the venue's chargeback
exposure) is implemented by actively reducing/voiding held commission on a
post-payout reversal, which is the literal opposite of the G4 owner ruling
already shipped and tested** ("no release, no reduction… the promoter's
already-funded claim is not pursued"). Whether 100 is a deliberate,
owner-approved *supersession* of G4's no-reduction posture (100's header
frames it that way — "the venue obligation... excludes held commission" is a
different claim than "the commission itself is reduced," but the shipped
mechanism does reduce/void the commission row, not just the obligation
computation) or whether it has overreached the ruling is exactly the kind of
call this train's boundary reserves for the owner, not T2.

### Finding 4 (P2, cosmetic) — 153 H58: comment-text false positive, not a real numeric/float regression

`supabase/tests/153_phase2_market_native_rail.sql:850-852` (H58) greps
`kernel.settlement_royalty_lines`'s `prosrc` for `numeric|float|double|real`
(case-insensitive, no word boundary) to prove the seam does integer-only
arithmetic. Migration 100 Section 2 body-only re-creates that function and
its new comments contain the plain-English words "**real** commission" and
"not **double**-counted" (100:~320,~326) — substring matches, not SQL type
usage. No actual float/numeric/double/real type or cast was introduced
(confirmed by reading the full re-created body, migration 100:279-393). Not
a functional regression; a future migration touching this function's
comments would clear it. Lowest severity of the four, listed for
completeness since it is still a real, reproducible non-match against the
documented delta set.

## 4. Rollback battery (fresh 000-101 replay, no test data — `snatchit_rehears_t2_rb`)

Applied in reverse order directly against the migrated-only database (before
any pgTAP file ran, so 100's rollback data-guard — refuses while any
`hold_reason_code='commission_converged'` or `kernel.organization_obligation`
row exists — is vacuously satisfied):

```
$ psql -f supabase/rollbacks/101_recovery_venue_scope_rollback.sql
BEGIN / CREATE FUNCTION / REVOKE / DROP TRIGGER / CREATE TRIGGER / COMMIT
EXIT=0
  kernel fn count: 147 (unchanged — 101 is body-only)
  organization_obligation_recovery_guard prosrc ~ 'reversal_venue_mismatch': f
    (confirms the guard body is back to 096's org-only-check text — the P0
    is deliberately reopened by this rollback, exactly as its own header warns)

$ psql -f supabase/rollbacks/100_venue_obligation_excludes_held_commission_rollback.sql
BEGIN / DO / CREATE FUNCTION / CREATE FUNCTION / CREATE FUNCTION / DROP FUNCTION / COMMIT
EXIT=0
  kernel fn count: 146 (the pre-100 state — converge_held_commission dropped)
  kernel.converge_held_commission exists: f
  close_settlement prosrc ~ 'commission_converged': f
    (confirms close_settlement's 100-B convergence loop is gone, body
    restored to 097's text)
```

Both rollbacks exit 0. Function census returns to 147 after 101's rollback
(no change expected — confirmed), then to 146 after 100's rollback (the
pre-100 state — confirmed), and 101's guard/100's converge function are
confirmed removed/reverted by direct catalog inspection, not just by count.

## 5. Files touched (mine only)

- `supabase/tests/141_phase2_identity_orgs_deletion.sql` — census 146→147
- `supabase/tests/142_phase2_catalog_config_and_seeds.sql` — census 146→147
- `supabase/tests/143_phase2_ticket_custody_kernel.sql` — census 146→147
- `supabase/tests/144_phase2_venue_staff_authz.sql` — census 146→147
- `supabase/tests/148_phase2_kernel_tickets_late_binding_fks.sql` — census 280→281 (×2 locations), 146→147
- `supabase/tests/154_phase2_market_bridge_view_and_late_fk.sql` — census 22/146/16→22/147/16
- `supabase/tests/156_phase2_kernel_reserve_stub.sql` — census 280→281 (found beyond KM5 §13's list)
- `supabase/tests/157_phase2_notify_reduced.sql` — census 280→281 (found beyond KM5 §13's list)
- `supabase/tests/167_recovery_venue_scope.sql` — new, plan 24, 24/24 green

No migration, rollback, or edge function file was edited.

## 6. Open questions for the orchestrator/owner

1. Does 100 supersede G4's "no release, no reduction" posture (164's G4
   assertion), or has it overreached? If superseded, 164's G4 case and its
   surrounding assertions need rewriting for the new semantics (not by me —
   164 is frozen and not in my scope) and PFA-PT-5 should say so explicitly.
2. Is a second, DB-gated, call-stack-restricted minter of
   `cause='promoter_commission'` payouts (155 B18) an acceptable widening of
   the single-writer invariant, or does 100 need a different mechanism
   (e.g., UPDATE the existing row's `amount_minor` in place instead of
   void-and-mint, if MB-2's "hold_state never touches status" append-only
   posture allows it — not verified here)?
3. 166's B4 (and any other "most recent payout row" reader without a
   `created_at` tiebreaker) needs a deterministic secondary sort key before
   this train can be called green; recommend fixing in a new migration
   package, not by editing 100 under this train's boundary.
4. 153 H58 is cosmetic only — flagged for awareness, not blocking.
