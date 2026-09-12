# KT — pgTAP reconciliation after 096–099 (payout reversal, obligation recovery, settlement scope/shortfall, promoter pro-rata, signing monitor)

Agent T. Repo `snatchit-consol` @ branch `feature/venue-native-and-product-v2`. All work done against private
rehearsal databases (`snatchit_rehears_recon` for iteration, `snatchit_rehears_final` for the clean verification
replay). No migration, rollback, edge, or non-test-doc file touched. No git commit.

**Note on task setup**: the task pointed at `scratchpad/TRAIN_BRIEF.md` for context; that file describes an
unrelated investigator-only train in a different repo (`snatchit-consol` under a "never touch `/Users/josetascon/snatchit`"
rule, read-only). It was treated as stale/irrelevant context, per the explicit orchestrator instructions for
this task, which are self-contained. `/Users/josetascon/snatchit` (the shell's cwd) has no migrations past 045
and no `supabase/tests/`; all required files (096-099, KM1-4, tests 141-165) live in `/Users/josetascon/snatchit-consol`,
where all work below was performed.

---

## 1. Final result

```
$ ./scripts/rehearsal_reset.sh snatchit_rehears_final     (fresh replay, 114/114 migrations)
GATE-2  tables=27 functions=70 policies=37 triggers=26
        CI baseline: tables=27 functions=70 policies=37 triggers=26 (ci.yml EXPECT_*)

$ ./scripts/rehearsal_test.sh snatchit_rehears_final
TOTAL plan=3486 ok=3482 not_ok=4 FAILURES

==============================================================
 LOCAL-ONLY DELTAS vs the CI (real Supabase stack) run
==============================================================
  expected   060_payments_money.sql: 2 known local-only/TODO failure(s) — see header.
  expected   132_replay_parity.sql: 2 known local-only/TODO failure(s) — see header.
==============================================================
 RESULT: pgTAP suite matches the expected local baseline.
 Reminder: nothing here exercises pg_cron firing, net.http_post delivery,
 or vault secret decryption. Those are inert stand-ins (see
 scripts/rehearsal_bootstrap.sql fidelity ledger).

exit code: 0
```

Every file 141–165 is `PASS` except the four documented local-only deltas (`060_payments_money.sql` — two
pinned TODO markers; `132_replay_parity.sql` — two cron `database` column mismatches, a rehearsal-DB-name
artifact, not schema drift). No migration, rollback, or edge file was modified. Gate-2 (public schema census)
unchanged: tables=27 functions=70 policies=37 triggers=26, matching the CI baseline before and after.

---

## 2. Files touched (18 test files; nothing else)

Modified (14): `141_phase2_identity_orgs_deletion.sql`, `142_phase2_catalog_config_and_seeds.sql`,
`143_phase2_ticket_custody_kernel.sql`, `144_phase2_venue_staff_authz.sql`,
`147_phase2_kernel_credential_infrastructure.sql`, `148_phase2_kernel_tickets_late_binding_fks.sql`,
`149_phase2_kernel_money_native.sql`, `153_phase2_market_native_rail.sql`,
`154_phase2_market_bridge_view_and_late_fk.sql`, `155_phase2_venue_promoter_engine.sql`,
`156_phase2_kernel_reserve_stub.sql`, `157_phase2_notify_reduced.sql`, `160_organization_obligation.sql`,
`161_payout_state_machine.sql`.

New, fixed in place (4 — authored by M1-M4 as AUTHOR-ONLY, never executed before this task):
`162_payout_reversal_and_obligation_recovery.sql`, `163_settlement_scope_and_shortfall.sql`,
`164_promoter_prorata_funding.sql`, `165_signing_monitor_and_invokers.sql`.

`145_phase2_venue_inventory.sql`, `146_phase2_venue_orders.sql`, `150_phase2_venue_door_and_scan.sql`,
`151_phase2_venue_settlement_and_export.sql`, `152_crm_export_x6.sql`, `158_refund_execution_claim.sql`,
`159_refund_accounting_timing.sql` — untouched, already correct.

---

## 3. Ground-truth counts (verified against the live catalog on `snatchit_rehears_final`, not assumed)

| Object | 000-095 | 096-099 |
|---|---|---|
| kernel tables (`pg_class` relkind='r') | 29 | **31** (+2: `payout_reversal`, `organization_obligation_recovery`, 096 R-1/R-4) |
| kernel functions (`pg_proc`) | 136 | **146** (+9 from 096 R-1..R-7; +0 from 097/098 — body-only re-creates; +1 from 099 `check_signing_key_invariants`) |
| kernel RLS-on tables | 29 | 31 (both new tables ship RLS-on/zero-policy) |
| five-schema relations (kernel+venue+catalog+market+notify) | 76 | **78** (+2, kernel's two new tables) |
| five-schema routines | 270 | **280** (+9 kernel from 096, +1 kernel from 099) |
| `cron.job` | 19 | **22** (+3: `monitor-signing-key-invariants`, `refund-execute-tick`, `payout-execute-tick`, all 099) |
| `catalog.platform_config` total | 49 | **54** (+5, all 099, all restricted, all v1) |
| `catalog.platform_config` restricted | 41 | **46** |
| `catalog.platform_config` public | 8 | 8 (unaffected — all five 099 keys are restricted) |
| money keys (`refund.%`/`payout.%`/`authn.%`) | 16 | **18** (+2: `refund.executor_enabled`, `payout.executor_enabled`) |
| catalog-referencing cron jobs (command/jobname ILIKE `%catalog%`) | 2 | **4** (+2: `payout-execute-tick`/`refund-execute-tick`'s inline `catalog.platform_config` read; `monitor-signing-key-invariants`' command text does NOT match — it only calls `kernel.check_signing_key_invariants()`, whose *body* reads catalog.platform_config, not its cron command string) |
| `kernel.settlement_maturity_hold_codes()` | 8 | **9** (+1: `dispute_unabsorbed`, 097) |
| F2 (kernel EXEC authenticated) | 64 | **66** (+2: `record_obligation_recovery` new, `resolve_organization_obligation` re-classified in) |
| F3 (kernel EXEC service_role) | 50 | **54** (+5 new: `claim_failed_payouts_for_reconcile`, `obligation_outstanding_minor`, `payout_reversed_minor`, `reconcile_payout_transfer`, `record_payout_reversal`; −1: `resolve_organization_obligation` moved OUT to F2) |

Every added/removed grant was cross-checked against the migration bodies and confirmed to match the intended
design stated in the task brief exactly (096 grants `record_obligation_recovery`/`resolve_organization_obligation`
to authenticated only, revoking service_role; 096 grants the five R-1/R-3/R-4/R-7 verbs to service_role only;
`record_organization_obligation` stays service_role-only; 099's `check_signing_key_invariants` is granted to
nobody — `revoke all ... from public, anon, authenticated, service_role`). No discrepancy found; nothing was
"copied blind."

---

## 4. Census files reconciled (141, 142, 143, 144, 147, 148, 149, 154, 156, 157)

Each file's kernel-table/kernel-function/five-schema-relation/five-schema-routine/cron/config literals were
bumped per §3's table, with comments added citing the exact migration/ref responsible. Representative diffs:

- **141**: A13 `29→31`, A14 `136→146` (comment enumerates all 14 re-created-not-added names across 096-099),
  C1 `29→31`, F2 count `64→66` + `record_obligation_recovery`/`resolve_organization_obligation` added to the
  `bag_eq` name list at their correct alphabetical position, F3 count `50→54` + the five new names inserted
  and `resolve_organization_obligation` removed from the name list.
- **142**: A12 `2→4`, D1 `49→54`, D4 `41→46`, D40 `16→18`, K1 `28/29→31` (label was already stale, undercounting
  094's table before this task even started — fixed to the live number), K3 `132→146` (same pre-existing
  staleness — the literal had never been updated for 094's +4, let alone 096/099's; corrected in one pass to
  the live catalog value).
- **143**: A1 `29→31` (label fix, same staleness pattern as 142/K1), A32 `132→146` (same pattern as 142/K3).
- **144**: A14 `132→146`.
- **147**: A1 `29→31` (label fix).
- **148**: B1 `76→78`, B2 `270→280`, B4 `(29,136)→(31,146)`.
- **149**: A1 `29→31` (label fix).
- **154**: the `'22/136/16'` market/kernel/catalog function-count string `→ '22/146/16'`; A10 comment updated;
  A12 (cron census) `19→22`.
- **156**: A19 `29→31` (label fix), A20 `270→280`, A22 `19→22`, A23 `49→54`.
- **157**: A17 (cron) `19→22`, A20 (distinct config keys) `49→54`, A43 (kernel tables) `29→31`, A45
  (five-schema relations) `76→78`, A46 (five-schema routines) `266→280` — this literal was ALSO already stale
  before 096-099 (comment chain topped out at 095's 266, never updated for 094's own +4 before this task);
  corrected to the live 280 (228+15+16+7+4+9+1) in one pass.

All of the "already stale before this task" literals (142/K1/K3, 143/A1/A32, 147/A1, 149/A1, 157/A46) were
identified by comparing the file's own literal against the live catalog count directly — none were guessed
from the delta comments, several of which undercounted (missing 094's contribution) even before 096-099 landed.

---

## 5. Behavioural test files (160, 161, 162, 163, 164, 165, 155) — arithmetic and fixture changes

### 161 — `settlement_maturity_hold_codes()`, 8→9
A9: `array_length(...)` `8→9` (097 adds `dispute_unabsorbed` after `dispute_open`). A9a self-derives from the
live function body and needed no edit.

### 160 — `organization_obligation` (094, re-touched by 096/097)
- **A13/C1** (kernel tables) `29→31`, **A14** (kernel functions) `136→146` — with the full 096-099 delta chain
  documented inline (9 new from 096, 0 net from 097/098, +1 from 099).
- **B6**: was `service_role ONLY... strictly tighter than the identity twin` — REVERSED per 096 R-6 (KD P1-1
  fix): `resolve_organization_obligation` is now **authenticated ONLY, service_role explicitly revoked**,
  matching (not exceeding) its identity twin `resolve_identity_obligation` (confirmed `authenticated=t,
  service_role=f` directly against the live catalog for both functions).
- **F8/F10** — the `pg_get_functiondef(...) !~ 'organization_obligation'` form is **false by construction**
  under 097 (the ninth maturity predicate and the ring-fence's bidirectional fence both now read the table for
  the `unlined_reversal` check). Replaced with the KM2-suggested pattern:
  `pg_get_functiondef(...) ~ 'organization_obligation' AND ~ 'unlined_reversal'` — proving the reference exists
  ONLY inside the fence check, not as a general gate. **F4** had the same defect (`!~ 'kernel\.payout'` — false,
  since 097's post-payout proof JOINs `kernel.payout` read-only inside `record_organization_obligation`); split
  into F4 (no verb *writes* to `kernel.payout`) + new **F4a** (the other three verbs still never *name* it).
- **D9a (new) / D10 (rebuilt)**: the original D10 passed a fake UUID (`'…cc'`) as an `unlined_reversal` origin —
  097's fence now resolves the origin to a real `lost`/`charge_refunded` dispute or `succeeded` refund and
  rejects anything else (`not_found: unlined origin … is neither…`). Added D9a to prove the fence fires on a
  fake origin (`throws_like … '%not_found%unlined origin%'`), then rebuilt D10 on a REAL post-payout origin:
  a lost dispute (amount 2500) on `oKeep` (already paid out via `sPre`, C3), with `sPre`'s payout flipped to
  `status='paid'` by a direct UPDATE (095's `guard_payout_org_payable` only fires on the `→'submitted'` edge,
  so this is a safe fixture shortcut) to satisfy the post-payout-proof gate. Arithmetic: face 10000, no
  succeeded refund on this payment ⇒ exposure=0 ⇒ `v_derived = least(2500, 10000-0) = 2500` — the same literal
  the original fixture asserted, so D11/D12 needed no change.
- **E-section rebuilt**: `resolve_organization_obligation`'s body now requires **aal2** (096 adds a step-up
  check since the verb is human-reachable) and refuses `resolution='recovered'` outright unless receipts
  already sum to the debt (`precondition_failed: recovery_facts_required`) — 'recovered' became a
  *consequence* of `kernel.record_obligation_recovery` receipts, not a resolve() act. `tap._resolve160` was
  extended to set aal2 unconditionally (E5's buyer still fails earlier, at the `is_platform` gate, so this is
  harmless there); a new `tap._recover160` wrapper was added for the recovery verb. New sequence: **E6**
  records a full-amount (10000) recovery receipt (`status='ok'`) — the AFTER trigger
  (`organization_obligation_recovery_settle`) auto-flips the row to `recovered` as a *consequence*; new
  **E6a** confirms `status||reason_code = 'recovered|recovered:manual'`; **E7** (was the original resolve call)
  now correctly expects `noop_replay` (the row is already recovered — resolve is confirmatory); **E11**'s
  expected reason code changed from the caller-supplied `'off_platform_payment'` to the trigger's own
  `'recovered:manual'` shape; **E13**'s admin_audit IN-list widened to include `'org_obligation.recovery'`
  (E7/E8 write zero `org_obligation.resolve` rows now — both are early-return/throw paths), count stays 4
  (3 record + 1 recovery).
- **Plan**: `90 → 93` (three net-new assertions: D9a, E6a, F4a).

### 162 — new file, package 096 (86 assertions, unchanged plan)
Five `record_organization_obligation(..., 'unlined_reversal', gen_random_uuid(), ...)` calls used a fake
origin UUID — refused outright by 097's fence (`not_found: unlined origin ... is neither...`). Each was
rebuilt on a REAL post-payout lost dispute, matching the ORIGINAL literal amount exactly so every downstream
number (K1-K-series, L-series, M-series, N-series) needed no further change:
- **O1** (K-section, amount 6000): a real lost dispute (6000) on `ordA`/`s1`/`p1` (already `status='paid'`
  from Fixture P1's own flow, line ~201) — `v_exposure=0` (dispute case) ⇒ `v_derived = least(6000, 10000) =
  6000`.
- **O3** (L-section, amount 1000) and **O4** (amount 500): each got a NEW order (`ordL`/`ordM`, face 3000/2000)
  through the full `_cov162`→`_settle162`→`_request162`→`mark_payout_transfer_state('paid')` cycle, plus a
  matching lost dispute at the exact original amount.
- **O2** (L-section, amount 3000, org2): needed a whole second venue/event/session for `org2` (which the
  original fixture only ever used for the cross-org `reversal_org_mismatch` proof, with no venue of its own) —
  added `venue2`/`event2`/`sessOld2`, an `org_finance` grant to `tap.other_user()` for org2 (mirroring org1's
  own grant, needed by `tap._request162`'s `request_org_payout` call), and a Connect capability
  (`acct_CK96TWO`) — then the same real-order-plus-dispute pattern.
- **oN** (N-section, amount 5500): `ordN` already existed with its payout marked `paid`; added a matching real
  lost dispute at the full face.
- No plan change (86 stays 86) — every fix replaced a fake origin with a real one at the identical amount.

### 163 — new file, package 097 (74 assertions, unchanged plan)
This file had never been executed before this task (AUTHOR ONLY per KM2). Six independent, pre-existing
fixture defects surfaced on first real run, none caused by 096-099's design:
1. `catalog.create_venue(...,'downtown',...)` — `'downtown'` is not in `venue_neighborhood_check`'s admitted
   set; the correct label is `'downtown miami'`.
2. `tap._pay163` called `kernel.mark_payout_transfer_state(payout,'paid',...)` directly on a still-`pending`
   payout — 085's forward-only state machine has always required the `pending→submitted` hop
   (`request_org_payout`) first. Fixed by having the helper derive the payout's org/settlement and request it
   (as `tap.seller()`, org O's org_owner, aal2) before marking paid, when the payout is still pending.
3. `tap._settle163` hardcoded `tap.login(tap.seller())` as the settlement opener regardless of which org was
   passed — fails for org P (owned by `tap.other_user()`) with `insufficient_privilege`. Added an optional
   `p_owner` parameter (default `tap.seller()`, every existing call site unaffected); org P's one call site
   passes `tap.other_user()`.
4. The V8 cross-org scenario created `oC1`'s dispute (`dC1`) *before* `SCp`'s first-ever close — `cb_candidate`
   (097, unchanged from 093 in this respect) has NO "already paid out" precondition, so the dispute would have
   been netted into `SCp` itself (30000 credit − 30000 debit = net 0), contradicting both A18 (want 30000) and
   A19 (want `dC1` unlined). Fixed by moving `dC1`'s creation to *after* `SCp` closes (mirroring org O's own
   pay-then-dispute pattern used earlier in the same file).
5. A `is(bigint_expr, integer_expr::bare, text)` overload didn't resolve for pgTAP's `is()` (conservation
   block, A20) — added an explicit `::bigint` cast on the RHS; arithmetic unchanged.
6. The C14 sale-arm-origin-refused fixture cited a bare `gen_random_uuid()` for `kernel.payment_native.sale_id`
   — refused by `fk_payment_native_sale` (a REAL FK, 089). Built the minimal real chain (one
   `venue.ticket_type`, one `kernel.signing_key`, one `kernel.tickets` atom, one `catalog.resale_policy`, one
   `market.listing_native`, one `market.market_sale`) so the FK resolves.
7. D-section: `poA9`'s settlement (`SA9`) was opened scoped to event `evA2`, but `oA9` (the order it needed to
   capture) lives on session `sessA`, which belongs to event `evA` — `SA9` netted 0/minted no payout at all
   (`_settlepo163` returned NULL). Fixed by opening `SA9` against `evA` (SA8 had already consumed `oA8` at its
   own close, so a second `evA` settlement legitimately captures only the new order).
8. D6's `kernel.retry_held_payout(...)` was called with NO session claims at all (bypassing the `tap._retry163`
   wrapper every other call site in the file uses), so it failed at the authority gate
   (`insufficient_privilege`) before ever reaching the maturity-code predicate the assertion is actually about.
   Routed through `tap._retry163`.

None of these eight fixes touch 096-099's design; all are pre-existing AUTHOR-ONLY fixture defects this task
surfaced by actually executing the file for the first time.

### 164 — new file, package 098 (29 assertions, unchanged plan)
One type-mismatch bug: `is((SELECT net_minor ...), 5400::bigint, ...)` — `venue.settlement.net_minor` is
`integer`; pgTAP couldn't resolve `is(integer, bigint, unknown)`. Dropped the `::bigint` literal cast; value
unchanged.

### 165 — new file, package 099 (34 assertions, unchanged plan)
- G1's bootstrap signing-key row used `public_key = 'PUBKEY'`, which is not valid base64 — the monitor
  recomputes `sha256(decode(pem,'base64'))` against exactly this row and threw `invalid base64 end sequence`.
  Replaced with `'UFVCS0VZ'` (base64 of the literal bytes "PUBKEY") — the K/L/M section rows
  (`'PUBKEY-SHADOW'`/`'-ROT'`/`'-REV'`) never get `decode()`'d by the function (only the bootstrap
  `key_id='...b0'` row is), so they needed no change.
- E4 originally called `kernel.check_signing_key_invariants()` a SECOND time expecting a fresh
  (non-deduped) `deduped='false'` result — but E1/E2 together already invoked the function TWICE with
  identical alert content, so by E4's own (third) call the 24h dedupe had already fired once (E2 deduped
  against E1) and would fire again at E4 (deduped against either prior call), making the assertion's actual
  live value `'true'`, not `'false'`. Fixed by capturing E1's single real call
  (`tap._store165('e1', kernel.check_signing_key_invariants()::text)`) and having E1/E2/E4 all read off that
  ONE jsonb result instead of each making an independent call. Section F's own "immediate re-run" (line ~128)
  is now genuinely the first repeat, so its `deduped='true'` proof is unaffected.

### 155 — package 090/093, re-touched by 098 (366 assertions, unchanged plan)
Thirteen originally-failing assertions plus one downstream cascade (G43b), all traced to a single root cause:
**098 replaces 090/093's ATOM-SURVIVAL commission basis (counting live vs. voided ticket atoms as a value
proxy) with a REAL-FACT basis** — `v_surviving = greatest(0, face − least(face, Σ succeeded kernel.refund) −
capped Σ lost/charge_refunded kernel.dispute_native)` — and the G-section's own fixture used
`kernel.force_void_ticket` (a pure custody act, no `kernel.refund`/`kernel.dispute_native` row) and a raw
`UPDATE venue."order" SET status='refunded'` (also no real refund row) as its "partial refund" proxies.
Neither survives translation to 098's rule as a reduction — both leave the order's surviving face **full**.

**Recomputed, order by order** (all under `s1`, bps unless noted):
| Order | Face | Terms | Old basis (atom-survival) | 098 surviving face | 098 commission |
|---|---|---|---|---|---|
| o1 | 15000 (3 tickets) | v1, bps 1000 | 10000 (2 of 3 atoms, after G1's `force_void_ticket`) | **15000** (no real refund/dispute row) | floor(15000×1000/10000) = **1500** (was 1000) |
| o2 | 5000 | v1, bps 1000 | excluded (`status='refunded'`, 090/093's terminal-class list) | **5000** (098's eligible-set excludes only `cancelled`; no real refund row to defer/reduce) | floor(5000×1000/10000) = **500** (was excluded/0) |
| o3–o6 | 5000 each | v1, bps 1000 | 5000 (no void) | 5000 (unchanged) | 500 each (unchanged) |
| o11 | 5000 | v2, bps 2000 | 5000 | 5000 (unchanged) | 1000 (unchanged) |
| o14 | 10000 (2 tickets) | v1, flat 300/ticket | 10000 | 10000 (unchanged) | floor(10000/5000)=2 capped at qty 2 × 300 = 600 (unchanged) |
| o12, o13 | — | — | HELD (unreviewed self-deal flag) | HELD (self-deal holds are orthogonal to the basis formula — unaffected by 098) | no line |

New line count: **8** (was 7 — o2 joins). New Σ: `-(1500+500+500+500+500+500+1000+600) = -5600` (was -4600).
Every number was cross-checked by executing the file's own fixture up through the `close_settlement` call on a
disposable probe database and reading the live `venue.settlement_line`/`venue.settlement`/`kernel.payout` rows
directly (not derived by hand alone) — confirmed: 8 lines, Σ=-5600, `gross_minor=100000` (unaffected — o2's
status flip never touches the credit side), `fees_minor=5600`, `net_minor=94400`, `status='closed'`, 8
`promoter_commission` payouts, org settlement payout `94400 USD pending/held/unbounded_refund_exposure`.

Assertions updated: **G6** (7→8 lines, updated order list), **G7** (o1's line `-1000→-1500`), **G9**
(Σ `-4600→-5600`), **G10** (`fees_minor 4600→5600`, `net_minor 95400→94400`), **G10c** (org payout amount
`95400→94400`), **G11** (7→8 payouts), **G13** (o1's payout `1000→1500`), **G18** (the audit `held[]` check —
replaced the old *negative* "o2 is NOT held for `basis_zero`" with a *positive*, stronger
`jsonb_array_length(held)=2` (exactly o12/o13, nobody else) + `lines_written` `7→8`), **G20b** (`14→16`, the
re-close noop check: 8 lines + 8 payouts).

**G41c/G41d/G42/G43/G43b** — per KM3's own flagged concern and recommended fix (option (b)): the original
fixture flipped `o13`'s `order.status` to `'partially_refunded'` with **no real `kernel.refund` row behind
it**. Under 098 that flip is inert (only `'cancelled'` is excluded structurally; the deferral predicate
requires a real pending/submitted refund row). Rebuilt on the 159/164 idiom: a REAL `kernel.refund` row,
`status='pending'`, amount 1000, on `o13`'s payment — `s4pr`'s close now correctly defers the WHOLE
attribution via the real "could still succeed" predicate (0 lines — **G41c** — and 0 payout — **G41d**), not
via a status-based exclusion that no longer exists. The refund is then flipped to `status='failed'`
(`stripe_refund_ref` set, satisfying `refund_ref_pairing_ck`) before `s4` closes — Σ succeeded stays 0, so
o13's surviving face is its full 5000, giving the SAME literal `floor(5000×2000/10000)=1000` (terms v2) the
original **G42** asserted, so no downstream number needed re-deriving there. **G43**/**G43b** (total
commission payouts/lines across all four of this file's settlements) move `9→10`, carrying G6/G11's own +1
for o2 forward.

No new/removed assertions anywhere in 155 — every touched line/label is a value or comment correction; `plan(366)` is unchanged.

---

## 6. STOP / findings — genuine issues found in the SHIPPED migrations, not papered over

**Finding (P1, 097 — `kernel.record_dispute_native`'s rail guard has a real gap for market-sale payments
mid-transfer).** 097's rail guard (`v_pay.mode <> 'native_primary' and not exists (payment_native row)`)
correctly protects genuine native/resale payments, but `kernel.payment_native.sale_id` is written ONLY at
custody transfer (R-34, `088:716-719`), never at `mark_sale_paid_state` (which only flips `market_sale.
sale_state` to `'paid_pending_transfer'`). A Stripe dispute arriving on a resale payment while its sale is
still `paid_pending_transfer` (charged, not yet transferred) is therefore REFUSED by `record_dispute_native`
with `not_native_rail` — even though the money is real and the sale is real. This is not a silent hole: the
webhook's `classifyDisputeError` (`supabase/functions/stripe-webhook/native-dispute.ts`) treats an
unclassified `precondition_failed` as `ack:false, alert:true`, so Stripe retries and `platform_risk` is
paged — the dispute self-heals once the transfer eventually completes (or stays permanently unrecorded, with
an outstanding alert, if it never does). Discovered via `supabase/tests/153_phase2_market_native_rail.sql`'s
existing J6a-d scenario ("a charged-back sale payment: finalize refuses; the void hook compensates" —
088-era coverage of exactly this "prevent transfer of already-disputed money" property), which could no longer
be exercised via the real RPC path once 097 shipped. Per the task's strict boundary this was NOT fixed in the
migration; the test (153, §J6a-d, see full comment in the file) was adapted to (a) prove the fence fires
honestly (`not_native_rail` on the pre-transfer payment) and (b) preserve the ORIGINAL security property under
test — `finalize_market_sale` still blocks custody moves on charged-back money, and `on_atom_voided` still
compensates — by seeding the same charged-back FACT directly into `kernel.dispute_native` (bypassing only the
now-fenced RPC, not the fact itself). Recommend the owner consider extending 097's guard (or a follow-up
migration) to also recognize a payment linked via `market.market_sale.payment_id` in `'paid_pending_transfer'`
state as on-rail — KB's own report (`docs/phase2/_impl/KB_dispute_db_mapping.md` §"For P1-1", option O6)
already names exactly this trade-off ("the sale arm must be exempted by `exists payment_native.sale_id` or the
rail decided per KH") without resolving the pre-transfer sub-case.

No other migration-level defect was found. Every other failure traced to either (a) a stale/undercounted
literal in a census test that predates 096-099 (142/K1/K3, 143/A1/A32, 147/A1, 149/A1, 157/A46 — all fixed to
the live catalog value), or (b) a pre-existing AUTHOR-ONLY fixture bug in 162/163/164/165/155 that had never
been executed before this task (fake origin UUIDs, an invalid neighborhood label, a skipped
`pending→submitted` payout hop, a hardcoded wrong persona, a mis-scoped settlement event, an unauthenticated
RPC call, non-base64 placeholder key material, a triple-invoked dedupe-sensitive function call, an FK'd fake
`sale_id`, and a status flip with no backing money fact) — all fixed as TEST/fixture changes only, none by
weakening a security, authority, RLS, or exact-grant-list assertion.

---

## 7. Final verification command (verbatim, exit 0)

```
$ ./scripts/rehearsal_reset.sh snatchit_rehears_final && ./scripts/rehearsal_test.sh snatchit_rehears_final
...
TOTAL plan=3486 ok=3482 not_ok=4 FAILURES

==============================================================
 LOCAL-ONLY DELTAS vs the CI (real Supabase stack) run
==============================================================
  expected   060_payments_money.sql: 2 known local-only/TODO failure(s) — see header.
  expected   132_replay_parity.sql: 2 known local-only/TODO failure(s) — see header.
==============================================================
 RESULT: pgTAP suite matches the expected local baseline.
$ echo $?
0
```
