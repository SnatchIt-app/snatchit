# J5 — the payout state machine: failed-state recovery, org guards, self-clear, header integrity

**Status:** implemented, **NOT DEPLOYED**, **NOT SHIPPABLE**. **Scope:** backend only.
**No production mutation, no deploy, no remote, no Stripe API call, no config change and no money
movement was performed to produce this.** Every result below comes from the local rehearsal database
`snatchit_rehears_psm` (`./scripts/rehearsal_reset.sh`, full chain replayed) and from the pgTAP
suite run against it.

**Migration claimed:** `supabase/migrations/095_payout_state_machine_recovery.sql`
(**renumbered off 094** — see §9). Rollback:
`supabase/rollbacks/095_payout_state_machine_recovery_rollback.sql`.
Tests: `supabase/tests/161_payout_state_machine.sql` (86 assertions, all passing).
Edge changes: `supabase/functions/payout-execute/executor.ts` + `index.ts`.

---

## 1. ITEM 1 — `failed` is absorbing, and the recovery design

### 1.1 Re-verified, by execution

Against a fresh replay, with a real `kernel.payout` row:

| attempt | result |
|---|---|
| `submitted → failed` | `ok` |
| `failed → paid` | `precondition_failed: payout_state_backwards (failed → paid)` |
| `failed → reversed` | `precondition_failed: payout_state_backwards (failed → reversed)` |
| `failed → submitted` | `invalid_input: … takes paid\|failed\|reversed` |
| `request_org_payout` on that settlement | `precondition_failed: no pending payout for this settlement` |

`kernel.close_settlement` is forward-only (a re-close returns `noop_replay`) and its mint carries
`on conflict (idempotency_key) do nothing`, so nothing can re-mint. **A transient Stripe failure
therefore destroyed the venue's obligation permanently.** The executor's refusal to ever write
`'failed'` (`PAYOUT_STATE_SYNC_TARGETS` has one member) is a mitigation in one client of a verb
granted to `service_role`; it is not a lifecycle.

### 1.2 The design: a new verb, not a widened transition

`kernel.rearm_failed_payout(p_payout_id, p_reason_code, p_command_key)`.
The status `CHECK` is untouched — asserted structurally at **A10**.

```
failed
  │  kernel.rearm_failed_payout            platform_risk|platform_admin, aal2, reason mandatory
  ▼
pending + held/'failed_rearm'  (held_by = the re-armer)
  │  kernel.release_payout (085:807, UNCHANGED — 095 adds no second release path)
  ▼
pending + none
  │  kernel.request_org_payout (093 slice 10k, UNCHANGED)
  ▼                                        org_owner|org_finance, aal2, SoD-1 setter exclusion,
submitted                                  money-grant maturity, destination cool-down,
                                           destination probation, the G2 maturity conjunction,
                                           and dual control above payout.dual_control_min_minor
```

**The authority model in one line: a re-arm is not an authorization.** The platform actor can only
*offer* the obligation back to the org; only an org money role can produce `'submitted'`, and only
from a session that passes the whole ladder. Two authority domains, and three humans above the
dual-control threshold. No single principal moves money.

### 1.3 The properties, and where each is proved

| property | mechanism | test |
|---|---|---|
| no double payout (a) | refuses any payout carrying a `stripe_transfer_ref` — a Transfer exists and whether its money moved is not a fact this DB can establish | C15, C15a |
| no double payout (b) | a ref-less failure is re-executed in the executor's `reconcile` mode, which reads `transfer_group=payout_<id>` before any create; `kernel.admin_audit` is append-only so a re-arm cannot reset the attempt clock | C10, C14 |
| no replay ambiguity | recognised by the exact triple `pending`/`held`/`failed_rearm` → `noop_replay`; anything not `failed` raises | C9 |
| no arbitrary amount mutation | the `UPDATE` names six columns; amount, currency, cause, cause_ref, idempotency_key, transfer ref are not in the statement | C7 |
| original destination authorization preserved | `destination_ref` (10j) is neither cleared nor rewritten | C6 |
| destination divergence still re-holds | the re-request meets the §10.3 probation arm and the E-85 approval-staleness rule; post-advance divergence is still 10n/10o's | (existing 151 coverage, unchanged) |
| audit trail | one append-only `payout.rearm` row with before/after and the operator's reason | C8 |
| aal2 / multi-party | `is_platform(platform_risk\|platform_admin)` + aal2 to re-arm; a different domain to advance | C1, C2, C2a, C4, C13 |
| **a service worker cannot self-authorize money** | granted to `authenticated`, **explicitly `revoke execute … from service_role`** (085's `record_money_denial` hard edge); and a re-armed payout is `pending`, invisible to `claim_payouts_for_execution` | **A2**, C10, C11 |

### 1.4 The named residual (owner item)

A `failed` payout that **carries** a `tr_…` stays stranded. Recovering it means asserting something
about a Stripe Transfer this database cannot observe. The honest primitives already exist
(`mark_payout_transfer_state` `'paid'` if the money landed, `'reversed'` if it came back); turning
that into a supervised operator flow is an owner decision and was deliberately not invented.
Narrower stranding than today, and named rather than silent.

---

## 2. ITEM 2 — suspended organization at payout request

`kernel.request_org_payout` checked roles, SoD-1, grant maturity, aal2, cool-down and destination
presence — **never `kernel.organization.status`**. A suspended org's payout advanced to
`'submitted'` with a pinned destination and, above threshold, a **consumed approval**; only later
did 10n refuse it (`org_not_active`) and 10o unwind it.

**Fix: `kernel.guard_payout_org_payable()` — a `BEFORE INSERT OR UPDATE` trigger on `kernel.payout`
that fires on exactly one edge, `→ 'submitted'`.** Chosen over a line in 10k's body because the
invariant belongs to the row, not to one caller: it binds every writer including future ones, it
cannot be bypassed (service_role holds no DML grant on `kernel.payout` — PFA-21), and it avoids a
200-line re-creation of a generated slice.

**Payable set copied from 10n/10o verbatim: `status in ('approved','active')`**, so the three sites
cannot disagree. Coverage is **enumerated from the `CHECK`, not guessed** — D0 derives the five
members from `pg_get_constraintdef` and asserts they are the five under test:

| status | verdict | test |
|---|---|---|
| `applied` | refused `org_not_active` | D1 |
| `approved` | **payable** (control) | D2 |
| `active` | **payable** | D3 |
| `suspended` | refused | D4 |
| `closed` | refused | D5 |

End to end: `request_org_payout` for a suspended org now raises, the payout stays `pending` with
**no destination pinned**, and **no approval is parked** (D6, D7, D8).

---

## 3. ITEM 3 — held payouts do not self-clear

### 3.1 Recommendation

**Human-initiated retry by the party owed the money, re-evaluating the whole conjunction. Not a
sweeper, not a cron, and never a release because time passed.**

`kernel.retry_held_payout(p_org_id, p_settlement_id, p_command_key)` — `authenticated` only,
**revoked from `service_role`**, org_owner/org_finance on aal2.

### 3.2 Reasoning

A maturity hold is not an accusation; it says "we have not finished proving this money is the
venue's". Today it can only be cleared by `platform_risk`/`platform_admin` via
`kernel.release_payout`, because `request_org_payout` refuses `hold_state <> 'none'` outright (E2).
That routes a **clock** into a **risk** queue, and it does not scale. The venue asking again is the
right trigger, and the only one that scales.

A sweeper was rejected: a scheduled release is a machine deciding to move money, and the brief's
own rule — do not auto-release merely because time passed — is exactly right, because the clock is
one conjunct of eight.

### 3.3 Every predicate is re-evaluated at release

Nothing is re-implemented. `kernel.settlement_payout_maturity` (10m) is called here **and again
inside `request_org_payout`**, so if a predicate turns between the clear and the advance the hold is
re-imposed by the existing gate.

| predicate | where |
|---|---|
| maturity policy / anchor / elapsed, covered-set resolvability, event or session cancelled, refund non-terminal, dispute open | `kernel.settlement_payout_maturity` (10m), called twice |
| organization status | the E-1 trigger, on the advance edge |
| destination bound, cool-down, probation | `request_org_payout` (10k) |
| destination pin vs current, Connect transfers capability, unbooked refund exposure | `get_payout_execution_context` (10n) |

### 3.4 It cannot launder a risk hold

Three independent tests, all required: `hold_state = 'held'` (a `probation_hold` keeps its own exit
— E11); `held_by IS NULL` (`kernel.hold_payout` stamps the human — E9); and `hold_reason_code ∈
kernel.settlement_maturity_hold_codes()`, the eight codes 10m can emit and nothing else (E10).
**A9a asserts that list against 10m's own source**, so a ninth code cannot appear there without
failing this test.

Behaviour: still immature → hold retained, reason **refreshed** to the predicate failing *now*,
audited, nothing parked (E3–E6). Clean → hold cleared, `payout.maturity_clear` audited under the
human's name, and the advance delegated to `request_org_payout` unchanged (E7, E8).

---

## 4. ITEM 4 — settlement header integrity: the severity call

**Who can actually do it.** On a fresh replay `venue.settlement`'s ACL is
`postgres=arwdDxtm/postgres, authenticated=r/postgres` — nothing else. `anon`/`authenticated` are
SELECT-only; **`service_role` has no grant on the table at all** (PFA-21). The reachable set is
(a) a direct superuser/table-owner session and (b) any postgres-owned `SECURITY DEFINER` function
that writes the header. Not reachable from PostgREST, an edge function, or any client role.

**What actually breaks.** Money does **not** move twice: the mint is idempotent on
`'settlement:<id>'` with `on conflict do nothing`, so a re-close mints nothing and updates no payout.
What breaks is:

* the re-close's maturity verdict is **reported** (return value + `settlement.close` audit) but
  **not applied** — an operator believes a hold was imposed that was not;
* the four money columns are silently rewritten, so `net_minor` can diverge from the amount an
  in-flight payout was authorized for. 10n catches that (`amount_ledger_mismatch`) — so the payout
  becomes permanently **un-executable while still reading `'submitted'`**: stranded money by another
  route;
* a header already advanced to `'paid'` can be walked back to `'open'`, erasing the record that a
  settlement was discharged.

**Severity: a ledger- and audit-integrity defect, not a money-movement one. It cannot overpay. It
can strand a payout, corrupt the reported waterfall, and produce a hold that was reported and never
applied.**

**Safe to close, so it is closed.** Every writer of `venue.settlement` in the corpus was enumerated
first: the `INSERT` at `'open'` (`venue.open_settlement`, whose idempotency arm returns the existing
header and never updates it), the `open→closed` UPDATE that writes the four money columns
(`kernel.close_settlement`), and the `closed→paid` UPDATE (`venue.on_payout_settled`). That is the
complete set, and all three pass `tg_settlement_forward_only` unchanged — proved live at G7 and G8.

Enforced: forward-only `open → closed → paid` (G1, G5, G9); money columns **and scope** write-once
after the close (G2, G2a); a non-open header is not deletable (G3); an unrelated UPDATE still passes
(G4); an open header is still deletable, so the guard protects money records rather than freezing
the table (G6).

**What it does not claim:** a superuser can `ALTER TABLE … DISABLE TRIGGER`. The trigger converts a
convention into an invariant against accident and against a future definer function written without
this context — the same protection `venue.settlement_line` has had since 087, no more.

---

## 5. ITEM 5 (relayed) — `amount_reversed`, and what a partial reversal does

**The defect.** `planPayoutStateSync` read `Transfer.reversed`, which Stripe documents as *full*
reversal only. A partially reversed transfer read as clean and was synced to **`'paid'` at full face
value** — and `'paid'` is not an inert label: it fires `venue.on_payout_settled`. The same blind spot
sat in `planReconcile`, which compares `amount` (unchanged by a reversal) and would have **adopted**
a reversed transfer as a successful payment.

**The choice, stated explicitly: neither `paid` nor `reversed`. The executor writes no status
transition at all.**

* `'paid'` is false — it asserts the venue received `amount_minor`, and it advances the settlement
  header.
* `'reversed'` is false twice over — it asserts the *whole* transfer came back, and it is only
  reachable **through** `'paid'`, so taking it writes the first lie in order to reach the second.
* **The state machine cannot represent a partial reversal.** `kernel.payout` has one amount column
  and it is the obligation. Widening the status `CHECK` would not help, because there is nowhere to
  put "we moved 5000 and 1200 came back". **This is a finding, recorded as an owner item, not
  something forced into the ledger.**

So: `kernel.hold_payout_transfer_reversed` de-authorizes `submitted → pending + held` with the exact
amounts in the audit and a human rules. It writes **no** status transition, never `'failed'`, and
deliberately **does not write `stripe_transfer_ref`** — that column is contracted as
`mark_payout_transfer_state`'s alone (085:133), and writing it would foreclose an owner decision by
making the payout permanently un-executable via 10n. Full-versus-partial is derived from the
**payout's own `amount_minor`**, never from the caller's numbers (F7).

**Full reversal is benign, not an error.** Stripe may reverse on its own initiative (platforms
created on or after 2025-01-01, when an async payment behind the funds fails). It takes the same
hold with its own reason code, is logged rather than paged, and both the reconcile and the sync
paths treat it as an expected observation. Only a **partial** pages, because a human must decide
what the venue is still owed. Tests F1–F8.

**Second relayed fact, confirmed and unchanged:** `paid → reversed` still has no driver in this
package. Nothing here creates one; it remains a state the system can be told about (by a future
`transfer.reversed` webhook) but cannot reach on its own.

---

## 6. ITEM 6 (relayed) — a line written is not a debt recovered

**The defect.** 10n's `refund_exposure_stale` operand subtracted every `refund_void` **line**, in any
settlement, unconditionally. A settlement that nets `<= 0` **mints nothing** (10d guards the mint
with `if v_net > 0`) and therefore **recovers nothing** — the debit lands in a header that pays
nobody, and there is no carry-forward object. So booking the reversal *defeated* the guard that
exists to notice it, and the executor would pay a venue in full for revenue that was entirely
reversed. Reproduced in 161: H2 (guard fires) → H3 (negative-net settlement mints nothing) → H4
(guard still fires, **the fix**).

**The corrected rule.** A `refund_void` line discharges its exposure only if its own header is
`closed`/`paid` **and** `net_minor >= 0`.

* `>= 0`, not `> 0`: a settlement that nets exactly zero because its own revenue cancelled the
  refund **did** absorb it.
* `NULL` net (an open header) never discharges — `coalesce(net_minor, -1)` makes that explicit.
* A negative-net settlement that **partially** absorbs an exposure (gross 4000 against a 10000
  refund) discharges **nothing**, not 4000. A deliberate over-correction in 093's own direction:
  over-holding is reversible by an owner act, over-paying in an append-only ledger is not. The
  residual it leaves is a hold — the recoverable failure mode.

Extracted to `kernel.settlement_unbooked_refund_exposure(uuid)` (H5, H7, H8); the face cap (ruling
A5) is preserved verbatim, because comparing raw refund sums against `refunds_minor` would fire on
every ordinary fee-bearing refund and strand the venue's money.

### **Does this fix depend on the obligation object? NO.**

`kernel.settlement_unbooked_refund_exposure` does **not** reference
`kernel.organization_obligation`, does not require it, and imposes **no ordering constraint**.
Without it an unrecovered exposure simply never discharges and the payout stays held — the safe
direction. **When it lands, this function is the one place to extend:** the discharge predicate gains
"…or the obligation whose `origin_ref` is this line is no longer `outstanding`", so a genuinely
recovered receivable stops holding the payout. That extension is a follow-up, deliberately not
written blind here.

---

## 7. What was claimed in the migration

`supabase/migrations/095_payout_state_machine_recovery.sql`, in a delimited **AGENT E CLAIM BLOCK**:

| § | objects |
|---|---|
| E-1 | `kernel.guard_payout_org_payable()` + trigger `tg_payout_org_payable_guard` on `kernel.payout` |
| E-2 | `kernel.rearm_failed_payout(uuid, text, text)` |
| E-3 | `kernel.settlement_maturity_hold_codes()`, `kernel.retry_held_payout(uuid, uuid, text)` |
| E-4 | `kernel.hold_payout_transfer_reversed(uuid, text, integer, integer, jsonb, text)` |
| E-5 | `kernel.guard_settlement_forward_only()` + trigger `tg_settlement_forward_only` on `venue.settlement` |
| E-6 | `kernel.settlement_unbooked_refund_exposure(uuid)`; **`kernel.get_payout_execution_context(uuid)` RE-CREATED body-only** — 093 slice 10n byte for byte except one expression (`diff` shows a single hunk) |

**Not touched, and verified unchanged:** `kernel.mark_payout_transfer_state`,
`kernel.request_org_payout`, `kernel.close_settlement`, `kernel.settlement_payout_maturity`,
`kernel.release_payout`, `kernel.hold_payout`, and the `kernel.payout.status` `CHECK`.

**The one collision to watch:** `kernel.get_payout_execution_context`. `094_organization_obligation.sql`
re-creates `kernel.close_settlement` and does **not** touch 10n, so the two packages are disjoint and
their rollbacks are independent.

---

## 8. Owner items produced (not invented here)

1. **A `failed` payout carrying a `tr_…` has no recovery flow.** Needs an owner-supervised
   reconcile-or-reverse verb.
2. **`kernel.payout` cannot represent a partially reversed transfer.** One amount column, and it is
   the obligation. 095 makes the unrepresentability loud and recoverable; it does not fix it.
3. **`paid → reversed` still has no driver.** A `transfer.reversed` webhook branch would be one.
4. **A negative-net settlement that partially absorbs an exposure discharges nothing.** Deliberate
   over-correction; the pro-rated rule needs an owner ruling, as at 093 slice 10e.

---

## 9. Renumbering, and the shared merge points

The brief said to author `094`. `094_organization_obligation.sql` (Agent C's receivable object)
landed in the same working tree, and two files sharing a numeric prefix **fails CI** (the migration
job's duplicate-prefix check). This package therefore moved to **`095`**, which is also the correct
order: the obligation object is the more foundational one, and §6's future extension reads it.
The test file moved from `160` to **`161`** for the same reason.

**Shared files edited (merge points, all currently green together):**

* `supabase/tests/141, 142, 143, 144, 148, 154, 156, 157` — the kernel/five-schema function census
  and 141's F2/F3 grant-class name lists. **+7 kernel functions** from this package
  (`get_payout_execution_context` was replaced, not added): +2 `authenticated`
  (`rearm_failed_payout`, `retry_held_payout` — F2 62 → 64) and +2 `service_role`
  (`hold_payout_transfer_reversed`, `settlement_unbooked_refund_exposure` — F3 45 → 47); the other
  three carry **no grant to any principal**, so the 077-F1 sweep stays at zero.
* `supabase/tests/151` C10/C11 — **probe changed, assertion unchanged**, and the reason is recorded
  in the file. Both assert that `settlement_waterfall_ck` makes a bad money shape *unstorable*. They
  demonstrated it by UPDATEing a closed header; E-5's trigger now refuses those writes **earlier**,
  with P0001. The CHECK did not weaken — a stricter guard stands in front of it. The contract is
  re-probed at the one door the trigger deliberately does not cover, `INSERT`, with the same errcode
  and the same two claims. The forward-only behaviour that displaced the old probes is asserted in
  its own right at 161 G1–G9. **No assertion was weakened or removed.**

---

## 10. Verification

* `./scripts/rehearsal_reset.sh snatchit_rehears_psm` — full chain replays clean.
* `./scripts/rehearsal_test.sh snatchit_rehears_psm` — `RESULT: pgTAP suite matches the expected
  local baseline`. The only failures are the four documented local-only deltas
  (`060` ×2 TODO markers, `132` ×2 db-name artifacts).
* `supabase/tests/161_payout_state_machine.sql` — **86/86 pass**.
* Rollback applied to a fresh full replay and then applied **again**: clean, idempotent, all seven
  objects gone, 10n restored to its 093 body.
* GATE-2 (`public` schema census) unchanged: `tables=27 functions=70 policies=37 triggers=26`.

**Nothing became deployable.** No migration was applied anywhere but the local rehearsal database,
no edge function was deployed, no Stripe call was made, no commit and no push.
