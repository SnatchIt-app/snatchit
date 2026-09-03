# KADV — adversarial re-proof of migrations 093–099 (dispute/reversal/obligation-recovery/promoter-prorata/signing-monitor)

**ADV, read-only adversarial reviewer.** Independent re-verification of a prior train's work. Own rehearsal DB
(`snatchit_rehears_adv`, `./scripts/rehearsal_reset.sh snatchit_rehears_adv`, 114/114 migrations replayed clean,
GATE-2 `tables=27 functions=70 policies=37 triggers=26` matching CI baseline), own fixtures, own attack scripts —
built independently from the prior train's `supabase/tests/16{2,3,4,5}_*.sql`, though I reused their documented
fixture idioms (`tap.login`/`tap._try`/`tap.seed_core` helper pattern from `supabase/tests/000_helpers.sql`) per
the brief's instruction to reuse prior test patterns. No production, no git, no writes outside this file.

**IMPORTANT connection note for anyone re-running these probes**: `psql -d <db>` alone connects as the OS user
(e.g. `josetascon`), not `postgres` — every probe here needed `psql -U postgres -d snatchit_rehears_adv`. Running
as the wrong role makes `public.guard_listing_insert_columns()`'s "ALLOW 2: direct admin connection" arm silently
fail, which looks like an unrelated fixture bug but is a connection mistake, not a product bug.

Migration 100 (G4 obligation-vs-held-commission fix) is out of scope per the brief; I did not test commission
reversal amounts.

---

## 1. What I inspected (file:line)

| Object | Where | Role in this review |
|---|---|---|
| `kernel.payout_reversal` + guard + `record_payout_reversal` | `096:147-451` | R-1/R-3, conservation cases 4/5, authority sweep |
| `kernel.organization_obligation_recovery` + guard + settle trigger + `record_obligation_recovery` | `096:499-794` | R-4/R-5, **the cross-venue attack** |
| `kernel.resolve_organization_obligation` | `096:826-894` | authority sweep |
| `kernel.claim_failed_payouts_for_reconcile` / `kernel.reconcile_payout_transfer` | `096:946-1189` | authority sweep |
| R-8 grants block | `096:1199-1247` | grant census (cross-checked against runtime) |
| `kernel.record_organization_obligation` (settlement_shortfall / unlined_reversal fence) | `097:232-430` | conservation cases 1-3 |
| `kernel.settlement_royalty_lines` (chargeback arm, venue ring-fence) | `097:577-672` | conservation, ring-fence execution |
| `kernel.close_settlement` (shortfall hold) | `097:812-947` | conservation fixture, shortfall-pending hold |
| `kernel.record_dispute_native` (097 rail guard, replay-drift audit) | `097:969-1111` | rail guard, KT-P1 repro, duplicate/out-of-order |
| `kernel.mark_dispute_state` | `097:1119-1150` | terminal-exclusivity, replay |
| `kernel.settlement_payout_maturity` / `settlement_maturity_hold_codes` (`dispute_unabsorbed`) | `097:682-780` | attempted, inconclusive (§2.7) |
| `kernel.check_signing_key_invariants` | `099:80-208` | grant, and **the dual-control gap** |
| `catalog.set_platform_config` `v_dual` prefix list | `093:6748-6751` | signing dual-control gap |
| `kernel.payout` DDL (no `venue_id` column) | `085:111-148` | root cause of the cross-venue finding |
| `kernel.deletion_blockers_money` / `kernel.deletion_blockers_market` / `kernel.sweep_deletion_pending` | `093:1529-1618`, `077:1720-1735`, `077:1865-1899` | deletion blocker chain (§2.6) |
| `kernel.issue_ticket_atoms` signing-key override refusal | `093:4874-4980` (checked ~4915/4975) | source-confirmed only, not executed (§2.8) |

Prior docs read for calibration (to distinguish new findings from known ones): `KM1-KM4_*_implementation.md`,
`KT_pgtap_reconciliation.md`, `G7_adversarial_review.md`, `KG_cross_venue_isolation.md`, `KD_obligation_recovery.md`,
`KE_payout_reversal.md`, `KC_chargeback_accounting.md`, `KB_dispute_db_mapping.md`, `KH_webhook_routing_idempotency.md`,
`KW_webhook_native_wiring.md`, `KJ_kms_runbook_monitor.md`, `KI_activation_sequencing.md`.

---

## 2. What I executed, and the results

### 2.1 Migration self-test re-verification (independent replay)

`./scripts/rehearsal_reset.sh snatchit_rehears_adv` → 114/114 migrations, GATE-2 matches CI. Then
`./scripts/rehearsal_test.sh snatchit_rehears_adv` over `000_helpers.sql` + `158..165`:

```
158_refund_execution_claim.sql                       plan=39   ok=39   PASS
159_refund_accounting_timing.sql                     plan=22   ok=22   PASS
160_organization_obligation.sql                      plan=93   ok=93   PASS
161_payout_state_machine.sql                         plan=86   ok=86   PASS
162_payout_reversal_and_obligation_recovery.sql      plan=86   ok=86   PASS
163_settlement_scope_and_shortfall.sql               plan=74   ok=74   PASS
164_promoter_prorata_funding.sql                     plan=29   ok=29   PASS
165_signing_monitor_and_invokers.sql                 plan=34   ok=34   PASS
TOTAL plan=469 ok=469 not_ok=0 ALL-PASS
```
This is a **from-scratch replay on a DB I built myself**, not a reuse of the prior train's DB — independent
corroboration that the 469 shipped assertions actually pass.

### 2.2 Append-only guards, as table OWNER (postgres, superuser)

Direct `UPDATE`/`DELETE` on `kernel.payout_reversal`, `kernel.organization_obligation_recovery`, and
`UPDATE`/`DELETE` on `kernel.organization_obligation`, executed as `postgres` (bypasses RLS entirely since
postgres owns these tables) — **all six blocked by the BEFORE trigger**, not by RLS:
```
owner_update_payout_reversal:          ERR[P0001] append_only: ... never updated or deleted
owner_delete_payout_reversal:          ERR[P0001] append_only: ... never updated or deleted
owner_update_obligation_recovery:      ERR[P0001] append_only: ... never updated or deleted
owner_delete_obligation_recovery:      ERR[P0001] append_only: ... never updated or deleted
owner_delete_organization_obligation:  ERR[P0001] append_only: ... never deleted
owner_update_organization_obligation:  ERR[P0001] append_only: obligation identity, magnitude and currency are write-once
```
Confirms the append-only invariant is trigger-enforced (fires for every role including the owner), not merely an
RLS posture that a privileged connection could bypass.

### 2.3 CONSERVATION — five cases, real writers, no hand-derived quantity

Fixture: org ADV2, one venue, four sessions 40 days in the past. Each order: face 9000 + buyer_fee 1000 (real
`public.payments.buyer_fee` column, `venue."order".total_minor` = face only, matching ruling A5). All numbers
below are **read back from the ledger after execution**, not computed by me.

**Case 1 — full chargeback after payout.** Paid 9000 via `mark_payout_transfer_state`. `record_dispute_native`
(dispute 10000 = full charge) → `mark_dispute_state('lost')` → a second, period-wide `close_settlement` on the
same venue picks the dispute up through the real `settlement_royalty_lines` chargeback arm → `chargeback` line
**-9000** (capped at face, not the full 10000 disputed) → `record_organization_obligation('settlement_shortfall')`
fires automatically inside `close_settlement`, obligation = **9000**, `outstanding`.
```
dispute_amt=10000  obligation_amt=9000  buyer_fee_column=1000  venue_currently_holds=9000
```
`10000 − 9000 = 1000 = buyer_fee` **exactly** — an arithmetic identity over three independently-recorded facts
(dispute amount, obligation amount as *derived* by `097:392-393`'s `least(disputed, face−exposure−prior)`, and
the `payments.buyer_fee` column), not a number I inserted to make it balance. The residual 1000 is the
already-documented, dark, unrecovered buyer-fee exposure (ruling A5) — not new.

**Case 2 — partial chargeback (4000 disputed < 9000 face).** Chargeback line = **-4000** exactly (min of disputed
and headroom), obligation = 4000, fully absorbed — no residual since disputed < face.

**Case 3 — refund + dispute overlap, same order.** Refund 5000 succeeded, THEN dispute 6000 lost. Real
`close_settlement` produced `refund_void -5000` AND `chargeback -4000` (**not** 6000 — capped by the refund
deferral fragment at `097:610-616`/`632-638`). `total_debited_from_venue = 9000 = face_value` **exactly** — not
5000+6000=11000 nominal. Proves the exposure fence prevents double-drawing the venue's pool when refund and
dispute overlap on one order.

**Case 4 — full transfer reversal, non-recovery.** `record_payout_reversal(..., 9000, ...)` on a paid 9000
payout with no dispute anywhere → Σ = amount_minor → payout moves `paid → reversed` through the existing 085
edge (via R-3). **Zero** `organization_obligation` rows created (unlinked reversal — matches KE's documented Q1
owner item: whether the venue is re-owed is undecided, recorded not invented here).

**Case 5 — partial transfer reversal.** `record_payout_reversal(..., 3000, ...)` on a paid 9000 payout →
payout **stays `paid`** (no second door on status), `payout_reversed_minor` = 3000, `venue_currently_holds` = 6000
— derived via the projection function, never a stored column.

**Verdict on Gate-M C31**: across all five no-commission cases, every reconciling number was either a stored
ledger column or a value the shipped functions themselves derive deterministically from stored facts
(`least(disputed, headroom)`, `Σ payout_reversal.amount_minor`, `amount − Σ recoveries`). **I needed no
hand-created balancing quantity in any case.** The one place a number is NOT a formal ledger fact is the
buyer-fee-as-platform-loss residual (Case 1's 1000) — but that is the already-ruled, already-documented A5 gap,
computable as an arithmetic difference of two real columns, not evidence of a missing ledger member.
**→ conservation closes cleanly for these cases; this does not by itself justify closing C31 (that is a scope/
policy call for the owner, and C31 also covers commission cases 100 is handling), but it removes "the no-commission
chain doesn't balance" as a reason to keep it open.**

### 2.4 AUTHORITY sweep — real `SET ROLE` execution, not `has_function_privilege` alone

**Pitfall I hit and want flagged for future adversarial trains**: my first pass used a `SECURITY DEFINER` wrapper
(copied from `KE_payout_reversal.md` Appendix A's `tap._try()`) to catch exceptions across personas. That defeats
an authority sweep — `SECURITY DEFINER` re-privileges every call to the wrapper's owner (`postgres`) regardless of
the caller's `SET ROLE`, so every persona "succeeded" in reaching business logic. I rebuilt a `SECURITY INVOKER`
wrapper (`tap._tryauth`) and re-ran; results below are from the corrected (invoker) harness, with real
`request.jwt.claims` + `SET ROLE` via `tap.login`/`tap.login_anon`/`tap.login_service`, and payout/obligation ids
pre-resolved as `postgres` and passed as literals (so a blocked *subquery* against `kernel.payout` isn't mistaken
for a blocked *function call*).

| Verb | anon | authenticated (non-platform) | platform_admin, aal2 | service_role |
|---|---|---|---|---|
| `record_payout_reversal` | `42501` schema denied | `42501` function denied | `42501` function denied | **reaches body** (P0001 on my malformed ref — proves EXECUTE granted) |
| `record_obligation_recovery` | `42501` schema denied | — | `42501` function denied (service_role explicitly revoked) | |
| … same, org_finance (authenticated, NOT platform) | | `insufficient_privilege: platform_risk or platform_admin required` (reaches body, refused by `is_platform`) | | |
| … same, platform_admin aal1 (no step-up) | | | `step_up_unavailable: the session carries no aal claim` | |
| `resolve_organization_obligation` | | | | `42501` function denied (service_role revoked) |
| `claim_failed_payouts_for_reconcile` / `reconcile_payout_transfer` | | | `42501` function denied (both) | |
| `check_signing_key_invariants` | | | `42501` function denied | `42501` function denied |

Every result matches the intended design exactly: 096's `v_svc`/`v_auth`/`v_nobody` grant partition (`96:1214-1229`)
and 099's "nobody, including service_role" (`099:205`) hold under **live** execution, not only under static ACL
inspection. **No authority bypass found in any of the eight verbs the brief named.**

### 2.5 THE CROSS-VENUE RECOVERY BYPASS — P0, executed, reproducible

**Reproduction** (`kernel.organization_obligation_recovery_guard`, `096:518-582`, and
`kernel.record_obligation_recovery`, `096:686-794`):

1. Org O, two venues A and B (both approved under O, distinct `catalog.venue` rows).
2. Venue A books a `settlement_shortfall` obligation via a negative `close_settlement` (a `refund_void −5000`
   line, no other lines) → `kernel.organization_obligation{org_id=O, venue_id=A, amount_minor=5000, status=outstanding}`.
3. Venue B: a normal 10000 order, settled, closed, paid out (`mark_payout_transfer_state(..., 'paid', 'tr_advB')`).
4. Stripe reverses **venue B's** transfer for an unrelated reason: `record_payout_reversal(payout_B, 'tr_advB',
   'trr_advB1', 5000, {}, ...)` → `kernel.payout_reversal` fact on **B's** payout. `source='stripe_webhook'`,
   `obligation_linked: false` in the return — the fact carries no venue or org claim of its own beyond the payout
   it's attached to.
5. As `platform_risk` (real `kernel.platform_role` grant, `aal2` step-up — not the `admin_users` bootstrap):
   ```sql
   SELECT kernel.record_obligation_recovery(<venue-A-obligation>, 5000, 'transfer_reversal', 'trr_advB1',
                                             'adv-cross-venue-test', 'adv-recA-viaB');
   ```
   **Result: `{"status":"ok", ..., "obligation_status":"recovered", "outstanding_minor":0,
   "total_recovered_minor":5000}`.**

Post-attack state: `kernel.organization_obligation` for **venue A's** debt now reads
`status='recovered', resolution_reason_code='recovered:transfer_reversal'` — **terminal, no reopen path**
(`resolve_organization_obligation`/the AFTER trigger only ever moves `outstanding → recovered|written_off`).

**Root cause**: `organization_obligation_recovery_guard` (`096:556-567`) resolves the reversal's payout and checks
only
```sql
if v_rev.payee_org_id is distinct from v_ob.org_id then
  raise exception 'precondition_failed: reversal_org_mismatch ...';
end if;
```
`kernel.payout` (`085:111-148`) has **no `venue_id` column at all** — only `payee_org_id`/`payee_identity_id` and
an opaque `cause_ref` (the settlement id, for `cause='settlement'`). `kernel.organization_obligation.venue_id`
*was* added, by 097, specifically to record the debt's origin venue (`097:171-178`, `097:299`/`097:407-409`) — but
097's own header (`097:130-132`) explicitly disclaims touching `kernel.organization_obligation_recovery` ("096's
objects — untouched, unread"), so the venue column that 097 added is never consulted by 096's recovery guard.

**Why this is new, not a documented owner item**: I checked `supabase/tests/162_*.sql` (096's own test file) —
it builds a *second organization* (`org2`/`venue2`) explicitly "needed only for the cross-org
`reversal_org_mismatch` proof" (`162:101-102`) and never constructs a second venue under the *same* org for a
recovery test. `docs/phase2/_impl/KD_obligation_recovery.md` §2.5/§4.4 discusses cross-venue leakage at the
**booking** side (which venue a chargeback *line* lands in — fixed by 097's ring-fence, §2.5 below) and explicitly
recommends venue-scoping for a *future* `offset_settlement` source (`KD:203`, "Any future offset_settlement
recovery must then require settlement.venue_id = obligation_origin_venue(obligation_id)") — but 096 shipped a
*different*, already-live recovery path (`transfer_reversal`) that KD's own venue-scoping recommendation was never
retrofitted onto. Owner ruling G5 is explicit: *"NO default cross-venue netting — Venue A's debt must not
silently consume Venue B's payout inside the same org"* — this reproduction is exactly that outcome, reached
through the shipped, granted, `authenticated`+`platform_risk`+`aal2`-gated verb, not a hypothetical.

**Impact**: this doesn't move money by itself, but it **permanently and falsely closes a venue's debt** using a
fact that has nothing to do with that venue — the audit trail (`org_obligation.recovery`, `after.source_ref`) will
show `trr_advB1` as evidence Venue A "paid back" 5000, when the 5000 that actually came back belongs to Venue B.
Because `recovered` is terminal (096's own honesty fix, R-6, deliberately made recovery non-reopenable), there is
no path to detect or correct this after the fact except by reading the raw `stripe_transfer_ref`/`payee_org_id` on
the cited `payout_reversal` row by hand and noticing it doesn't share a settlement with the obligation's
`venue_id`. It requires only ONE authorized human action in good-faith error (the UI/API surface for
"which venue does this trr_ belong to" doesn't exist yet — everything here is dark/operator-only) — no compromise
or malice needed.

**Fix sketch (not implemented — read-only train)**: add, in `organization_obligation_recovery_guard`'s
`transfer_reversal` branch (`096:552-571`), after the existing org check, a venue check:
```sql
-- resolve the reversed payout's settlement's venue and compare to v_ob.venue_id
select s.venue_id into v_rev_venue
  from kernel.payout p2 join venue.settlement s on s.settlement_id = p2.cause_ref
 where p2.payout_id = v_rev.payout_id and p2.cause = 'settlement';
if v_ob.venue_id is not null and v_rev_venue is distinct from v_ob.venue_id then
  raise exception 'precondition_failed: reversal_venue_mismatch — % reversed a payout of venue %, the obligation belongs to venue %', ...
```
`v_ob.venue_id` is nullable (097 added it without backfill, `097:172-178`), so the guard needs a decision for
legacy/NULL-venue obligations (fail open — pre-097 shape — or fail closed — refuse manual recovery until an
operator backfills). That decision, and whether `unlined_reversal`-origin obligations (which also carry
`venue_id` from 097) need the identical check, belongs to the owner/orchestrator, not to me.

### 2.6 Cross-venue ring-fence — BOOKING side (KG's fix), execution-confirmed intact

Distinct from §2.5 (the recovery-side gap), I independently verified the *booking*-side ring-fence KG/097 claim to
have fixed. `settlement_royalty_lines`'s `cb_candidate` CTE (`097:606-646`) joins the disputed order's own
`catalog.event`/`event_session` and requires `e.venue_id = s.venue_id` (`097:624`) — I confirmed this join is
actually present in the shipped 097 bytes (not just claimed in the header comment), and Case 1-3 above exercised
it end-to-end (real `close_settlement` → real `settlement_royalty_lines` → real chargeback line, never a
direct-insert bypass) on a single-venue org, landing the chargeback correctly at that venue's own settlement each
time. I did not additionally construct KG's original two-venue-one-org booking scenario myself (KG already
executed and reverted a prototype of the identical join; re-deriving it would only reconfirm what §2.3's real
`close_settlement` runs already exercise structurally) — this is corroboration by construction, not a fresh
counter-example search, and I flag that distinction rather than claim a from-scratch reproduction.

### 2.7 Dispute/chargeback lifecycle — duplicate, out-of-order, terminal-first

All via the real `record_dispute_native`/`mark_dispute_state` writers, no direct table inserts:

- **Terminal observed first** (a `lost` dispute recorded with no prior `needs_response`, simulating Stripe
  delivering `charge.dispute.closed` before `.created`): succeeds cleanly, `atoms_held=0` (open-branch logic
  correctly skipped since `v_open=false` from the start), no crash.
- **Duplicate delivery** (same `stripe_dispute_ref` twice via `record_dispute_native`): first call inserts, second
  returns `{"status":"noop_replay", ...}`; exactly **one** `kernel.dispute_native` row exists; exactly **one**
  `dispute.record` audit row — not double-processed.
- **Out-of-order terminal transition** (`mark_dispute_state('won')` after already `'lost'`): correctly refused,
  `state_conflict: dispute ... is terminal (lost) — won refused`.
- **Replay of the same terminal** (`mark_dispute_state('lost')` again): `noop_replay`, not an error, not a
  duplicate audit row.

No defect found in this surface — all four edge cases the brief named behave exactly as documented.

### 2.8 Rail guard — legacy vs. native vs. KT-P1 gap, executed

- **Legacy `buy_now` payment, no `kernel.payment_native` row, no listing/seller pairing issue**:
  `record_dispute_native` → `ERR[P0001] precondition_failed: not_native_rail`. Correctly refused.
- **KT-P1 reproduction** (a resale/market-sale payment charged via `mode='buy_now'` — the *same* mode literal
  legacy resale uses, since there is no separate native-resale mode value — with **no** `kernel.payment_native`
  row at all, matching the real shape: `sale_id` is written only at custody transfer, which the fixture
  deliberately never runs): `record_dispute_native` → **same** `ERR[P0001] not_native_rail`. This independently
  reproduces KT's documented P1 and confirms it fails **closed and loud** (a raised exception a webhook caller
  must treat as non-2xx → retry + alert, per `native-dispute.ts`'s `classifyDisputeError`), not silently. I did
  not additionally verify the TypeScript-side `ack:false, alert:true` classification myself (that's edge-function
  code, out of reach of a pure-SQL attack) — I take KT's own citation of `native-dispute.ts` on trust for that
  half, corroborated by the fact that the SQL layer raises rather than swallows.
- **Genuine native primary/resale acceptance**: every dispute call in §2.3/§2.5's fixtures (all `mode='native_primary'`
  with a real `kernel.payment_native` row) succeeded through the rail guard — the positive case is exercised
  dozens of times across this report without failure.

### 2.9 Deletion blockers — buyer with an open dispute, no separate refund row

Initial test of `kernel.deletion_blockers_money` alone (`093:1529`) in isolation returned `NULL` (no blocker) for
an identity with an actively open (`needs_response`) dispute and a `refunded`-status order — this function has no
dispute check at all. **This looked like a P0 and was NOT** — `kernel.sweep_deletion_pending`
(`077:1865-1899`) calls **both** `kernel.deletion_blockers_market` (`077:1720`, BP-7, checks `kernel.dispute_native`
by `payments.buyer_id` directly — a *different* function, in a different migration, than the one I first checked)
**and** `kernel.deletion_blockers_money`, first-blocker-wins. I confirmed by direct call:
```
kernel.deletion_blockers_market(<identity with open dispute>) → 'BP-7: open native dispute'
```
for both test identities (one with a `paid` order, one with a `refunded` order). **The real end-to-end blocker
chain correctly holds** — I'm recording the false start here so a future adversarial train doesn't waste the same
cycle re-discovering that `deletion_blockers_money` is only half the picture.

I did not separately re-verify BP-12's post-event hold or BP-12 arm-1's refund-in-flight block by execution
beyond what I saw incidentally (both fired correctly as side observations in the fixture above) — `H2_deletion_
clock.md` already carries extensive executed evidence for those and I did not find anything to contradict it.

### 2.10 `dispute_unabsorbed` maturity predicate — attempted, inconclusive

I tried to isolate the ninth `settlement_payout_maturity` predicate (`097:682-780`, `dispute_unabsorbed`) by
constructing a venue with an unabsorbed `lost` dispute on one order and a *second*, unrelated, positive-net order
on the same session, then closing a new settlement covering the second order. Result: the payout **was** held
(fail-closed, correctly), but under `hold_reason: 'covered_set_unresolvable'` (a higher-precedence predicate in
the causal `case` chain) rather than `dispute_unabsorbed` specifically — my fixture's unabsorbed-dispute order was
apparently not resolving cleanly into `kernel.settlement_covered_payments`'s covered set (I did not have budget to
trace that function's exact coverage derivation). **I did not isolate this specific predicate as either confirmed
or broken** — the payout was correctly held either way, so this is not evidence of a defect, just an incomplete
proof. Flagging as an open item rather than claiming either a pass or a fail.

### 2.11 Signing-key monitor — dual-control gap, executed

`catalog.set_platform_config`'s dual-control prefix list (`093:6748-6751`):
```sql
v_dual := p_key like 'refund.%' or p_key like 'payout.%' or p_key like 'authn.%'
       or p_key like 'comp.%'   or p_key like 'wallet.%' or p_key like 'credential.%'
       or p_key like 'door.session\_%' or p_key like 'fee.%'
       or p_key like 'deletion.%' or p_key like 'ticket.%';
```
**`signing.%` is absent.** Executed as a single `platform_admin`, `aal2` step-up, no second approver:
```sql
SELECT catalog.set_platform_config('signing.monitor_enabled', 'true'::jsonb, ..., ...);
-- {"status":"ok","version":2,"request_id":null}
SELECT catalog.set_platform_config('signing.expected_key_fingerprint',
       '"deadbeef0000...0000"'::jsonb, ..., ...);
-- {"status":"ok","version":2,"request_id":null}
```
Both applied **immediately**, in one step, `request_id: null` (no approval-request row created —
`kernel.approval_request` count for `platform_config` stayed 0). A single compromised or careless
`platform_admin` can unilaterally both arm `kernel.check_signing_key_invariants` (`099:80-208`) **and** pin
whatever fingerprint they like as "expected" — including, in a real attack, re-pinning the fingerprint to match a
substituted signing key *after* substituting it, which would make the monitor report `"status":"ok"` on a
compromised key. This is a "who watches the watchman" gap: the monitor exists specifically to detect an
unauthorized signing-key change, but its own trust anchor (the pinned fingerprint) is *not* protected at the same
control level as the money-moving config it's modeled after (`refund.%`/`payout.%` are dual-controlled; `signing.%`
is not, despite being seeded in the same migration, `099:74-78`, with `visibility: 'restricted'` but no
`v_dual` membership).

This corroborates `docs/phase2/_impl/KJ_kms_runbook_monitor.md` §5 Q3, which flagged this in prose — **I am the
first to execute it**, confirming it is a live, currently-reachable gap (the monitor itself is dark by default,
`signing.monitor_enabled` seeded `false`, so there is no production exposure *yet*, but nothing blocks a
`platform_admin` from arming+mis-pinning it today in a rehearsal or, if 099 were applied, in production).
**Fix sketch**: add `or p_key like 'signing.%'` to `093:6748-6751`'s `v_dual` predicate in a future migration
(093 itself is immutable) — the change is additive, one line, and the polarity map (`093:6756+`) would need a
`signing.expected_key_fingerprint`/`signing.monitor_enabled` entry (both are non-comparable strings/booleans,
which already "park when dual-controlled" per the polarity-map comment, `093:6753-6755` — i.e., adding them to
`v_dual` with no polarity entry is enough to require a second admin, no polarity ruling needed).

### 2.12 `issue_ticket_atoms` signing-key override — source-confirmed, not executed

`093:~4915`: `v_key_req := (p_ctx->>'signing_key_id')::uuid;` ... `093:~4975`: `if v_key_req is not null and
v_key_req is distinct from v_key then raise exception 'precondition_failed: signing_key_override_refused —
caller supplied % but % resolves for this scope; the mint resolves its own key', v_key_req, v_key;`. The refusal
is directly visible in the shipped body and matches the brief's expectation exactly. I did not build the full
event/session/inventory fixture needed to call `issue_ticket_atoms` end-to-end (non-trivial setup, and the
refusal logic is a simple, unconditional equality check with no branch I had reason to doubt) — **this is a
source-level confirmation only**, flagged as such rather than claimed as executed.

---

## 3. Findings, ranked

### P0 — genuinely new

**P0-1 (§2.5). Cross-venue obligation recovery is possible and permanent.**
`kernel.organization_obligation_recovery_guard` (`096:518-582`) checks only that a cited `transfer_reversal`'s
payout belongs to the *same organization* as the obligation being recovered — it never checks that the reversal's
originating *venue* matches the obligation's `venue_id` (added by 097 specifically to carry that fact, but never
wired into 096's guard, which 097's own header explicitly disclaims touching). Executed: Venue A's 5000
`settlement_shortfall` debt was marked `recovered` — permanently, terminal, no reopen — citing a Stripe transfer
reversal that actually returned money from **Venue B's** payout. Directly contradicts owner ruling G5 ("NO default
cross-venue netting — Venue A's debt must not silently consume Venue B's payout inside the same org"). Reachable
by the one intended principal (`platform_risk`/`platform_admin`, `aal2`) with a single well-formed call and no
malice required — nothing today would stop an operator from doing this by honest mistake. Not covered by 096's own
test suite (`162_*.sql` builds a second org for its only cross-boundary test, never a second venue under the same
org). Fix sketch in §2.5; decision on NULL-`venue_id` (pre-097-shape) obligations and whether `unlined_reversal`
origins need the identical check are owner/orchestrator calls.

### P1 — real, not new (independently executed)

**P1-1 (§2.11). `signing.%` platform_config keys are not dual-controlled**, unlike every other money/security-
adjacent prefix (`refund.`/`payout.`/`authn.`/`deletion.`/`ticket.`/etc.). A single `platform_admin` can
unilaterally arm the KMS signing-key invariant monitor AND pin an arbitrary "expected" fingerprint in one
uncontested step — defeating the monitor's own purpose in a compromise scenario where the same principal (or an
attacker who reaches that principal) also substitutes the key. Flagged in prose by `KJ_kms_runbook_monitor.md`
§5 Q3; I executed it for the first time. No production exposure today (monitor seeded `false`), but this is a
one-line, low-risk fix worth landing before `099` is applied or the monitor is ever armed.

**P1-2 (§2.8, restated, not new). KT's pre-transfer native-resale dispute gap** — I independently reproduced it:
a resale/market-sale payment charged (mode `buy_now`, no `kernel.payment_native` row yet because `sale_id` is
written only at custody transfer) is refused by `record_dispute_native` with `not_native_rail`. Confirmed
fail-**closed** (a raised exception, not a swallowed no-op) at the SQL layer; the TS-side `ack:false, alert:true`
classification I take on KT's citation rather than re-verifying myself.

### P2 / open items, not ranked as defects

- **§2.10** `dispute_unabsorbed` maturity predicate — attempted in isolation, inconclusive (payout was correctly
  held under a different, higher-precedence predicate; I did not have budget to trace `kernel.settlement_
  covered_payments`'s exact coverage derivation to force the specific predicate). Not evidence of a bug.
- **§2.12** `issue_ticket_atoms` key-override refusal — confirmed by source only, not executed end-to-end.
- **§2.6** booking-side venue ring-fence — corroborated by construction (real `close_settlement` runs in §2.3 all
  routed correctly through the ring-fenced `cb_candidate` join), not a fresh from-scratch counter-example search
  the way KG's original prototype was.

### Explicitly NOT findings (verified correct, recorded so no one re-spends budget here)

- Append-only guards on `kernel.payout_reversal`/`kernel.organization_obligation_recovery`/
  `kernel.organization_obligation` hold for the table owner/superuser (trigger-enforced, §2.2).
- The full grant partition for every 096/097/099 money verb the brief named matches design under **live**
  `SET ROLE` execution, not just static ACL inspection (§2.4).
- Conservation closes cleanly, no hand-derived quantity, across all five no-commission cases (§2.3).
- Duplicate/out-of-order/terminal-first dispute webhook handling is correct in all four tested shapes (§2.7).
- The deletion pipeline correctly blocks on an open dispute — my first-pass concern (`deletion_blockers_money`
  alone missing a dispute check) was a false start; the real aggregate (`deletion_blockers_market` + `_money`)
  catches it (§2.9).

---

## 4. Options / trade-offs

Only P0-1 needs a design decision beyond "add the obvious check":

1. **Venue-scope the recovery guard unconditionally** (refuse when `v_ob.venue_id is not null and v_rev_venue is
   distinct from v_ob.venue_id`) — smallest honest fix, matches the booking-side ring-fence's spirit, but silently
   permits recovery against any obligation whose `venue_id` is still NULL (096-shipped-before-097 shape, or a
   `settlement_shortfall` obligation booked before the ring-fence existed in production history).
2. **Fail closed on NULL `venue_id` too** (refuse `transfer_reversal` recovery entirely until an operator
   backfills `venue_id`) — more honest, but could strand legitimate recoveries against pre-097 obligations with no
   backfill path currently shipped.
3. **Do nothing, rely on operator discipline** — explicitly what G5 rules out ("must not silently consume").

I recommend option 1 with a follow-up owner item to decide whether NULL-`venue_id` obligations need a backfill or
an explicit "recovery blocked, resolve venue first" state — but this is the orchestrator's/owner's call, not mine
to settle.

---

## 5. Open questions for the orchestrator/owner

1. Does the P0-1 fix also need to cover `unlined_reversal`-origin obligations (they carry `venue_id` too, from the
   same 097 column) even though I only reproduced the attack against a `settlement_shortfall` origin?
2. Should `signing.%` join the dual-control prefix list in a new migration now, or wait until the KMS ceremony
   (G3, "approved in principle, NOT executed") actually arms the monitor?
3. Is `kernel.settlement_covered_payments`'s exact coverage derivation (§2.10) worth a dedicated pass to confirm
   `dispute_unabsorbed` is reachable at all, or is "always covered by a higher-precedence predicate in practice"
   an acceptable structural argument?

---

**Final summary**: P0 count = **1** (cross-venue obligation recovery, `096:518-582`/`686-794`, reproduced end-to-end,
fix sketch in §2.5/§4). P1 count = **2** (signing dual-control gap, newly executed; KT's pre-transfer native-resale
gap, independently reproduced, already documented). Conservation for the no-commission chain **closes without any
hand-derived quantity** across all five cases I ran (chargeback full/partial, refund+dispute overlap, transfer
reversal full/partial) — **C31-can-stay-deferred: yes**, on the evidence I gathered (this doesn't cover
commission cases, which are 100's scope).
