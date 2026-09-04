```
============================================================
SNATCH IT — G4/G5 + RECEIVABLE + 094 REPORT
============================================================
```

**Train:** G4/G5 economic adjudication · receivable architecture · 094/095 hardening.
**Session scope:** backend, database, money, security, production readiness, activation. **No UI work.**
**Date:** 2026-09-03.

---

## REPOSITORY

| | |
|---|---|
| **BRANCH** | `feature/venue-native-and-product-v2` |
| **HEAD** | `e68dc30` |
| **PR** | [#52](https://github.com/SnatchIt-app/snatchit/pull/52), open, base `phase2/consolidation` |
| **CI** | **GREEN** — 7/7 |
| **WORKTREE** | clean |

**Entry discrepancy, recorded as instructed.** The prompt reported HEAD `2a6393f`; the actual head was
**`09e167f`** — one documentation commit from the same prior train above it. Everything else matched.

## PRODUCTION

| | |
|---|---|
| **LEDGER** | **107 rows**, through `092_notify_reduced` plus five timestamped website migrations. Verified at entry and exit. |
| **093 APPLIED** | **NO** |
| **094 APPLIED** | **NO** |
| **MUTATIONS** | **NONE.** Nothing applied, deployed, exposed, configured, flipped, created at Stripe, or rotated. KMS ceremony not executed. |
| **ACTIVATION** | **NO** |

---

## CURRENT POST-PAYOUT BEHAVIOR

**MEASURED CASES.** Eleven, executed on a real replay. Fixture: buyer pays 23 000 = 19 000 face + 4 000 fee.

- **A** paid 19 000 → 6 000 refund → second settlement `net −6 000`, `payout_ids: []`.
- **B** paid → 23 000 dispute lost → `chargeback −19 000`, correctly capped at face; the 4 000 fee slice is platform loss per A5. **`payouts_held: 0`** — the freeze leg only touches `pending`/`submitted` payouts and only while the dispute is *open*.
- **C** two partial refunds → Σ capped exactly at face.
- **D/E** refund 12 000, then 5 000 of new revenue → `net −7 000`, **no payout**, the 5 000 silently consumed. **The −7 000 residue does not carry.** The next close pays the venue its full 10 000.
- **F** refund and a larger order in the *same* close → offset works, 8 000 paid.
- **G** period-scoped pooling → `net −23 000`, no payout.
- **H** suspended org → `request_org_payout` **never read `organization.status`** and advanced to `submitted`.
- **I** venue never sells again → seven negative headers, **−99 000 total**, nothing aggregates, ages or alerts.
- **J** destination changed while debt exists → probation held the **full** 11 000, then paid 11 000 in full to the new destination. **Debt untouched.**
- **K** `cancel_event` after payout → refund at face only (buyer loses the 4 000 fee); `kernel.payout` untouched.

**CURRENT LOSS MODEL.** Platform absorbs. Of six possible accounting outcomes, only that one is implemented.

**ACCIDENTAL FUTURE OFFSET.** **Weaker than every prior report stated.** It is not future-settlement offset at all — the residue does not carry between closes. Recovery happens only when reversing and positive revenue land in the *same* `close_settlement` call, so the recovered fraction is decided by accounting accident rather than policy.

**FAILURES.** The conservation equations close **only because `UNRECOVERED RECEIVABLE` is a quantity derived by hand across two schemas.** It corresponds to no table, column, row or function. Set it to the 0 the database can represent and cases A, B, C, D/E, G, J and K fail to close by 6 000 / 19 000 / 19 000 / 7 000 / 23 000 / 6 000 / 19 000. **The gap is always the same object: `venue.settlement.net_minor < 0` on a permanently closed header.** The money is real; the database had no name for it.

---

## G5 OPTIONS

| | Option | Assessment |
|---|---|---|
| **1** | Platform absorbs | Today's behaviour plus a decision. Worst fraud posture; costs nothing. |
| **2** | Organization obligation (durable record) | Makes the loss *representable*. Nets nothing, recovers nothing by itself. |
| **3** | Negative carry / automatic future offset | **Already partially ships** — the chargeback arm nets org-scoped. This is the option that actually *recovers*, and the one that raises the cross-venue question. |
| **4** | Reserve / hold-back | Reduces exposure rather than recovering it. Compatible with A5 (changes payout timing, not entitlement). Needs an owner percentage and duration. |
| **5** | Stripe fixed reserves | **Unavailable** — private preview, 180-day cap, requires platform-owned liability plus a ToS disclosure. |
| **6** | Hybrid | Record now, decide offset separately, revisit reserves when the Stripe product is GA. |

**RECOMMENDATION: option 6, and only option 2 was built.**

**WHY.** Options 2 and 3 answer different questions and were being conflated: 2 makes the loss *representable*, 3 makes it *recoverable*. Only 2 is unambiguously safe to build without a policy decision, because recording a fact that is already true commits nobody to anything. Deciding that a venue's future earnings are automatically seized to pay an old debt is a commercial decision with a venue-relationship consequence, and it is not mine to make.

**OWNER SIGNATURE REQUIRED: YES** — `docs/phase2/G5_POST_PAYOUT_EXPOSURE_RULING.md`.

---

## RECEIVABLE ARCHITECTURE

| | |
|---|---|
| **OBJECT** | `kernel.organization_obligation` — the structural twin of `kernel.identity_obligation` (`085:165-198`). |
| **SCOPE** | **Organization.** Payout ownership is org-level (`payee_org_id`, no venue equivalent); the existing chargeback debit already attaches org-scoped with no venue predicate; and `catalog.venue.org_id` was rejected as a mutable tenancy pointer. |
| **CURRENCY** | **USD-only, definitively.** Every money currency column is `NOT NULL DEFAULT 'USD'`; the only primary-order writer hardcodes `'USD'`; `close_settlement` **compares** currencies and raises or drops rows — it never converts; four call sites send literal `'usd'` to Stripe. No FX table exists in 110 migrations. The FX risk is hypothetical, and the per-origin shape makes cross-currency netting structurally impossible without new policy. |
| **CREATION** | Booked from `close_settlement`'s previously-empty `v_net <= 0` branch. **The magnitude is not a free parameter** — `settlement_shortfall` re-derives it from the closed header (org match, `net_minor < 0`, `amount = -net_minor`, currency match). No caller can name an amount. |
| **REDUCTION** | Forward-only `outstanding → recovered | written_off`, by an audited platform act. Never automatic. |
| **OUTSTANDING** | `kernel.org_outstanding_obligation_minor(org_id)`, a `STABLE` projection over a partial index on `(org_id) WHERE status='outstanding'`. |
| **IDEMPOTENCY** | `UNIQUE(origin_kind, origin_ref)`. |
| **APPEND-ONLY** | Yes — and chosen on **mechanical** grounds, not house style. The producer is an at-least-once webhook; `balance = balance - X` has **no database-enforceable idempotency** while `INSERT … UNIQUE` does. Every idempotent money writer in this codebase is built the second way; a mutable balance would have been the only member of the money layer without that property. |
| **RECONCILIATION** | A trigger enforces write-once origin/magnitude/currency, terminal-is-terminal, and DELETE always raises — **against the table owner**, not merely one definer. Stronger than the identity-side twin. |
| **NO-FUTURE-SALES CASE** | The obligation persists. Nothing fakes closure. |
| **SUSPENDED-ORG CASE** | Debt remains; payout is now refused at request time by 095's trigger. |

**`kernel.reserve` was evaluated and rejected.** It is the **C29 funding source** — money the platform *holds* — not money an org *owes*. E-149 grants *permission* for a negative balance; it does not *designate* reserve as the receivable. 091 keeps its always-empty property and its droppable rollback. `kernel.payout`'s `CHECK (amount_minor > 0)` is untouched, and no new `settlement_line` cause was added — that was the design's own withdrawn first draft, which would have double-counted against the chargeback arm and reproduced the exact defect 093 had just fixed between `refund_void` and `chargeback`.

**Direction is carried by object identity, never by a sign.** A signed amount invites a negative-payout hack.

---

## SETTLEMENT OFFSET

| | |
|---|---|
| **OFFSET ORDER** | **Not built.** The obligation nets nothing. |
| **PARTIAL / FULL / OVER-OFFSET** | Not applicable — no offset mechanism was added. Over-resolution is impossible at both the RPC and storage layers. |
| **MULTI-EVENT** | A period-scoped settlement already pools causes across events; measured in case G. |
| **MULTI-VENUE** | **The owner question.** See below. |
| **CROSS-ORG** | Isolated; asserted by test. |
| **CROSS-CURRENCY** | Structurally impossible; USD-only proven. |

**The cross-venue question is live whether or not anything from this train ships**, because the chargeback arm already nets org-scoped with no venue predicate. It is not a question this design created. And because `venue.settlement.venue_id` is `NOT NULL` and `venue_finance` can read it, cross-venue netting is a **disclosure** decision as well as an economic one — one venue's finance role would see another venue's loss inside its own numbers.

---

## STRIPE

| | |
|---|---|
| **SEPARATE CHARGES/TRANSFERS** | Platform balance is automatically debited for the disputed amount and fee. |
| **POST-PAYOUT DISPUTE** | The platform pays first and may *attempt* recovery. |
| **TRANSFER REVERSAL** | **Moves the problem; does not solve it.** *"It's only possible to reverse a transfer if the connected account's available balance is greater than the reversal amount or has connected reserves enabled."* Reversal is balance-to-balance and requires the money still to be in the venue's balance — exactly what is gone in the case we fear. Partial and repeatable; **no undo endpoint**; no documented time limit (the 90-day figure belongs to *payout* reversals, a different object). |
| **RESERVES** | A genuine reserve product exists but is **private preview**, 180-day cap, requires platform-owned liability and a ToS disclosure. |
| **PLATFORM LIABILITY** | **Identical between separate and destination charges**, with or without `on_behalf_of` — so changing charge model is not a recovery fix. At 180 days negative, `connect_collection_transfer` fires and the platform pays. |
| **WHAT STRIPE CAN DO** | Reverse against a funded balance; debit negative balances (US supported) *after* a reversal creates the deficit; delay payouts (`delay_days ≤ 31`), manual schedules, minimum balances. **No mechanism extracts money from an empty balance.** |
| **WHAT SNATCH IT CHOOSES** | Nothing new. **No reversal endpoint is called anywhere in the repository** — verified. Whether to automate reversal, enable `debit_negative_balances`, hold venue funds, or pursue preview reserves are all owner decisions, and **who owns negative-balance liability** gates the last two entirely. |

Two official Stripe pages **contradict each other** on whether a reversal can push an account negative. The correct engineering response is not to architect on reversal succeeding.

---

## G4 — PROMOTER REVERSAL

| | |
|---|---|
| **CURRENT DEFECT** | No mechanism reduces an already-funded commission when the revenue reverses. Seven reduction routes were attempted **as the table owner** and all refused: append-only UPDATE/DELETE; `23505` on a compensating line; a new cause rejected by the CHECK; payout reduction and negative payout both rejected by `amount_minor > 0`; re-close returning `noop_replay`. |
| **MEASURED EXPOSURE** | The prior "79%" was a fixture artifact (correctly 75%). What is **not** an artifact: over-funding hits **100% of the commission** on any full reversal, and under-funding hits **100% of what was earned** on any pre-close partial refund — a 4 000 refund on a 10 000 sale leaves the promoter with **nothing** when 600 was earned. |
| **OPTIONS** | 1 final · 2 pro-rata · 3 void-on-full-only · 4 promoter receivable · 5 remain held · 6 hybrid. **Options 5 and "2-at-release" are the only ones representable with zero DDL.** |
| **RECOMMENDATION** | **Option 5 for launch**, with the reduction question decided before the first release. It costs nothing, is already the machine's behaviour, and preserves every other option — while the money is held, 1, 2 and 3 all remain available; the moment it is released, only 4 remains, and 4 needs schema that does not exist. |
| **FUNDED-BUT-HELD** | The whole point. No commission payout has ever left `pending`. Containment is **four independent locks, not one boolean** — a hold was deliberately released in rehearsal and the money still could not move. |
| **POST-RELEASE FUTURE CASE** | Once paid, only a promoter receivable can correct it, and **it cannot be retrofitted onto money already gone**. That is why (ii) below must be answered before the first release. |
| **OWNER SIGNATURE REQUIRED** | **YES** — `docs/phase2/G4_PROMOTER_REVERSAL_RULING.md`. |

**Do not extend the pre-close model.** It keys on order *status* (binary) while the post-close question is an *amount*. Extending its shape is what produces the total-forfeiture case.

---

## PROMOTER CONSERVATION

Case D, executed:

```
+10 000 collected  − 9 000 venue paid  − 10 000 refunded  =  −9 000 cash gap
plus a 1 000 obligation recorded, HELD, never disbursed

exposure R = 10 000 = venue clawback 9 000 + commission obligation extinguished 1 000
```

| | |
|---|---|
| **PRE-PAYOUT REVERSAL** | Reduces the current settlement; no obligation created. |
| **POST-PAYOUT REVERSAL** | Venue owes what it *received*. |
| **VENUE DEBIT** | **9 000, never 10 000.** |
| **PROMOTER DEBIT** | **Zero — it received nothing.** |
| **PLATFORM POSITION** | Holds the 1 000. **It never left**: the commission was funded as a reduction of the venue's distributable, so the platform retained it at close. Voiding a held obligation collects from nobody; it returns the platform's own retained cash. |
| **DOUBLE-DEBIT DEFENSE** | Structural, not procedural — **because FUNDED ≠ PAID**. Charging the venue the full face would bill it for commission money it never held. |

---

## REFUND ACCOUNTING

| | |
|---|---|
| **WHEN VENUE OBLIGATION REDUCES** | On `succeeded` only, with whole-order deferral while any refund is non-terminal (`093:526`, `093:477-479`). |
| **PENDING** | Too early — no refund object is known to exist at Stripe. |
| **SUBMITTED** | Too early — an object exists but Stripe can still retract it (`canceled` maps to our `failed`). |
| **FAILED** | Books nothing. |
| **PAID/EXECUTED** | `succeeded` is the only state where the buyer demonstrably has the money. |
| **REFUND_VOID** | Its own negative line, never an amendment of the original. |
| **FIX** | **None needed — the predicate was already correct.** But it was **completely untested**, so a refactor could have silently reinstated the broken `<> 'failed'` draft with every suite green. 22 assertions added (`159_refund_accounting_timing.sql`). |
| **OWNER RULING REQUIRED** | **No** for the timing. **Yes** for one adjacent defect, folded into G5: booking the reversal *correctly* used to discharge the exposure guard, because it counted lines written rather than obligations discharged. Fixed in 095. |

The two error directions are asymmetric in **reversibility**: booking early is permanent (append-only plus the global unique index), while deferring is recoverable. That asymmetry is why deferral is load-bearing rather than merely cautious.

---

## PAYOUT FAILED-STATE RECOVERY

| | |
|---|---|
| **OLD STATE MACHINE** | `failed` absorbing: `failed→paid`, `failed→reversed`, `failed→submitted` all raise; `request_org_payout` sees only `pending|submitted`; `close_settlement` is forward-only and cannot re-mint. |
| **DEFECT** | A transient Stripe failure would **permanently strand the venue's money.** |
| **NEW RECOVERY** | `kernel.rearm_failed_payout` — **a new verb, not a widened CHECK.** Returns the payout to `pending + held/'failed_rearm'`; money then moves only through the existing ladder. |
| **AUTHORITY** | **A re-arm is an offer, not an authorization: the platform actor offers, the org actor authorizes.** Two authority domains, three humans above threshold. Explicitly `revoke execute … from service_role`. |
| **DESTINATION PIN** | `destination_ref` is not in the UPDATE statement; amount, currency, cause and key likewise. |
| **IDEMPOTENCY** | Refuses any payout already carrying a `tr_…`; a ref-less failure re-executes in `reconcile` mode. Append-only audit means a re-arm cannot reset the attempt clock. |
| **DOUBLE-PAY DEFENSE** | Two locks (above). Named residual: a **ref-bearing** `failed` payout stays stranded — an owner item. |

**Partial reversal.** Now read from `amount_reversed` in **both** blind spots (`planPayoutStateSync` and `planReconcile`, the latter of which would have adopted a reversed transfer as a payment). Explicit choice: **neither `paid` nor `reversed`** — `paid` fires `on_payout_settled`, and `reversed` is only reachable *through* `paid`. **The state machine cannot represent a partial reversal** — one amount column, and it is the obligation. Recorded as an owner item rather than forced. Full reversal is treated as **benign** (Stripe may reverse first on async payment failure for platforms created ≥2025-01-01); only partial pages.

---

## SUSPENDED ORGANIZATION

| | |
|---|---|
| **SALE** | **Already closed, and the matrix was stale.** `venue.create_primary_checkout` selects `o.status` and refuses `org_not_active`, placed *before* the connect gate so the operator learns the fundamental fact first. The activation matrix still recorded this as open; corrected this train. |
| **PAYOUT REQUEST** | **Fixed in 095** — a `BEFORE INSERT OR UPDATE` trigger on `kernel.payout` guarding the single `→submitted` edge. Chosen over editing the function body because it binds **every** writer and is unbypassable (`service_role` holds no DML grant on the table). All five CHECK members enumerated from `pg_get_constraintdef`: `applied`/`suspended`/`closed` refuse; `approved`/`active` pass. |
| **PAYOUT EXECUTION** | Already enforced by `get_payout_execution_context`. |
| **FIXES** | The request-time gap was the last one; the exposure window between request and execution is now closed. |

---

## SETTLEMENT INTEGRITY

| | |
|---|---|
| **HEADER REOPEN** | Possible for a superuser or a postgres-owned definer — `service_role` has **no grant at all**. |
| **SEVERITY** | **Ledger/audit integrity, not money movement.** It cannot overpay (the mint is idempotent), but it *can* strand a payout (a rewritten `net_minor` yields a permanent `amount_ledger_mismatch` on a row still reading `submitted`), corrupt the waterfall, and produce a hold reported but never applied. |
| **FIX** | Forward-only trigger added in 095. All three legitimate writers enumerated and proved to pass live. Superuser `DISABLE TRIGGER` is acknowledged, not papered over. |
| **SELF-CLEARING HOLDS** | **None, by design.** |
| **FINAL MODEL** | **Human-initiated retry by the payee**, re-evaluating the whole conjunction — `kernel.retry_held_payout`, `authenticated`-only, revoked from `service_role`. **No sweeper, no cron.** A maturity hold is a clock, not a risk decision, but a payout must never be released merely because time passed. Three tests prove it is a *machine* maturity hold (`held_by IS NULL`, reason in `settlement_maturity_hold_codes()` asserted against the source so the two cannot drift). Still-holding refreshes the reason to what is failing *now*. |

---

## A9 ENFORCEMENT

| | |
|---|---|
| **CURRENT POLICY** | Selling may not activate until refunds are actually executable, **or** a named written manual process exists. |
| **CURRENT MACHINE** | Checkout does not know whether `refund-execute` is deployed. The only two occurrences of `refund` inside `create_primary_checkout` are comments. |
| **FIX** | **None applied, deliberately.** A `feature.primary_refund_executor_ready` flag would be a dishonest "trust me" value — it asserts a deployment fact the database cannot observe, and the owner's own instruction forbids exactly that shape. |
| **DEPLOYMENT READINESS SIGNAL** | This remains an **operational gate**, not a machine gate. A9's second disjunct — the named written process — still does not exist anywhere in the corpus. Closing this honestly requires either deploying the executor or writing that process and naming its accountable human. |

---

## MIGRATION 094

| | |
|---|---|
| **FILE** | `supabase/migrations/094_organization_obligation.sql` (831 lines) + `supabase/rollbacks/094_organization_obligation_rollback.sql` |
| **HASH** | `1beb85aa6973d3748fa181895e39f9c1` |
| **TABLES** | 1 (`kernel.organization_obligation`) |
| **COLUMNS** | 12 on the new table; none added to an existing table |
| **FUNCTIONS** | 4 — `record_organization_obligation`, `resolve_organization_obligation`, `org_outstanding_obligation_minor`, `organization_obligation_guard` |
| **TRIGGERS** | 2 (`set_updated_at`, the immutability guard) |
| **POLICIES** | 0 — deny-all RLS |
| **ENUMS** | 0 new enum types; `origin_kind` is a CHECK over `settlement_shortfall`/`unlined_reversal` |
| **EXISTING ROW MUTATIONS** | **NONE** — proven by identical `relfilenode` on `payments`, `payout`, `settlement`, `organization` and `refund` before and after |
| **GATE-2 DELTA** | **NONE.** `tables=27 functions=70 policies=37 triggers=26`, matching the CI baseline. Nothing added to `public`. |

**Also 095** — `095_payout_state_machine_recovery.sql`, md5 `cb85cac5183d974c392b6422877b2aa4`. The two are disjoint (094 re-creates `close_settlement`; 095 re-creates `get_payout_execution_context`) with independent rollbacks; 094 applies first. One `create or replace` each, both copied verbatim from 093 with a single reviewed hunk.

**093 was NOT modified.** These are post-093 concerns and the assembler gate still passes byte-for-byte.

---

## PAYOUT EXECUTOR

| | |
|---|---|
| **CODE READY** | **YES** |
| **SAFE TO DEPLOY** | **NO** |
| **BLOCKERS** | G5 unsigned (the ruling gates deployment in terms); `unlined_reversal` inert until the dispute writers have callers; no organization has a payout destination; 093/094/095 unapplied; the schemas unexposed; a ref-bearing `failed` payout still stranded; and the partial-reversal state remains unrepresentable. |
| **RECEIVABLE INTEGRATED** | **Partially, and deliberately.** The obligation is a *projection*, not a gate — nothing in 094 consumes it. Wiring it into the payout predicate is the owner's option-3 decision, not an implementation detail. |
| **RETRY** | Reconcile mode past the 20h window; never writes `failed`. |
| **REVERSAL RACE** | The exposure guard now discharges only when the header is closed/paid **and** `net_minor >= 0`. The fix does **not** depend on the obligation object and imposes no ordering constraint. |
| **DESTINATION** | Pinned at claim, re-verified at execution. |
| **MATURITY** | Re-evaluated at mint, request and transfer. |

---

## ACTIVATION

| Gate | State |
|---|---|
| **DRAFT** | **YES** |
| **PUBLISHABLE** | **YES** |
| **SALEABLE** | **NO** |
| **PAYABLE** | **NO** |

**REMAINING SALEABLE BLOCKERS:** 093/094/095 unapplied; `catalog`/`venue` unexposed over PostgREST; `primary-checkout` and the webhook native branch undeployed; `fee.buyer_service_bps` unset; no signing key (G3); no bound payout destination; A9 unenforced by any code.

**REMAINING PAYABLE BLOCKERS:** all of the above, plus G5 unsigned, the executor undeployed, and no organization payout destination in existence.

**THE ORDERED CRITICAL PATH**, re-derived against a live 110-migration replay:

> **0a** sign G5 · **0a′ Gate-M re-attestation** (gates *applying* 094 — see below) · **0b–0g** the remaining rulings · **1** apply 093 → 094 → 095 (ledger 107 → 110; order is mandatory, and the three were verified disjoint) · **2** expose `catalog` and `venue` over PostgREST · **3** deploy `connect-onboarding` · **4** deploy `stripe-webhook` · **5** deploy `refund-execute` · **6** onboard one organization · **7** the KMS ceremony · **8** owner config values in order · **9** deploy `primary-checkout` · **10** flip `feature.native_issuance_enabled`.

**A distinction worth stating plainly, because it is easy to misread:** signing G5 makes the payout executor **deployable**; it makes nothing **pay**. Execution is blocked independently — venue setup and settlement maturity are both NO, all four `payout.*` keys are null, and `request_org_payout` returns `step_up_unavailable`. The two gates are not the same gate.

**And a precondition that is not a signature.** Applying 094 needs a **Gate-M re-attestation**, separately from G5. `PHASE_2_MONEY_AUTHORITY_SPEC.md:67` ratified Gate-M as "not required" **because payout is settlement-cadenced** — a premise written when no venue could be paid at all. That premise should be re-attested rather than obeyed or overridden, and 094 records the ratification row as a **deploy** precondition, not a build one.

---

## G1 / G2 / G3

| | |
|---|---|
| **G1** | Unchanged — `"72 hours"`, still recommended, still unsigned. |
| **G2** | Unchanged — `max(session.ends_at)` + 7 days, still unsigned. |
| **G3** | Unchanged — prepared, rehearsed, **not executed**, still unsigned. |

**CHANGED BY THIS TRAIN: NO.**

---

## SECURITY

**P0: 0.**

**P1: 3, all fixed.** The partial-reversal blind spot marking a reversed transfer `paid` at full face value; the exposure guard defeated by booking the reversal correctly (found independently by two agents); the suspended-organization payout request advancing without a status check.

**P2: recorded, not fixed.** A ref-bearing `failed` payout stays stranded; the partial-reversal state is unrepresentable; `kernel.payout` can never reach `reversed` on its own; the dispute writers have zero callers; superuser `DISABLE TRIGGER` remains possible.

---

## ADVERSARIAL REVIEW

**CLAIMS OVERTURNED — five, including two of my own.**

1. **"No dispute or chargeback table exists in any of the sixteen packages."** I passed this to the agents from the traceability matrix. It predates package 088 and is **wrong** — `kernel.dispute_native` and `kernel.identity_obligation` both exist. The real defect is one layer down: the writers have zero callers.
2. **"Auto-offset would be a departure from the ratified pattern."** My framing. True for identities, **false for orgs** — `identity_obligation` nets nothing because an identity has no settlement ledger to net into. That is structure, not policy. The real departure would be to *stop* netting.
3. The working "accidental future offset" — it does not carry between closes.
4. The promoter exposure figure (79% → 75%, both fixture artifacts; the real findings are the two 100% cases).
5. `kernel.reserve` as the receivable — it is the C29 *funding source*, not a debt object.

**DEFECTS FOUND: 9. DEFECTS FIXED: 6.**

**OPEN FINDINGS:** ref-bearing `failed` payouts; partial-reversal representability; dispute-writer wiring; A9 machine enforcement; `unlined_reversal` inert; the cross-venue netting question.

---

## TESTING

| | |
|---|---|
| **PGTAP** | **3260 planned, 3256 pass** — the 4 are the documented local-only deltas (060's two TODOs, 132's two `cron.job.database` name artifacts). New: `160_organization_obligation.sql` (90/90), `161_payout_state_machine.sql` (86/86), `159_refund_accounting_timing.sql` (22/22). |
| **VITEST** | **375/375**, 10 files |
| **TYPECHECK** | clean |
| **LINT** | 0 errors |
| **WEB** | passes |
| **MOBILE** | typecheck clean; no shared contract changed |
| **FRESH DB** | **110/110** replay, Gate-2 matching the CI baseline |
| **IMMUTABILITY** | pass — 000-093 byte-identical |
| **ASSEMBLER** | G-4 gate pass; 093 still in sync byte-for-byte |
| **CI** | **GREEN**, 7/7 |

Coverage was **added** for every property this train established, including the boundary case that matters most: **a pre-payout refund reduces the settlement and books no obligation.**

---

## OWNER DECISIONS

| | |
|---|---|
| **G1** | Ticket expiry — `"72 hours"`. Unchanged. **PENDING.** |
| **G2** | Payout maturity — `max(session.ends_at)` + 7 days. Unchanged. **PENDING.** |
| **G3** | Signing ceremony — prepared, not executed. **PENDING.** |
| **G4** | **Promoter commission on reversed revenue.** Recommendation: option 5 (remain held) for launch, with the reduction question decided before the first release. **PENDING.** |
| **G5** | **Post-payout exposure.** Recommendation: option 6 — record now (built), decide offset separately. **PENDING.** Gates deploying the payout executor. |
| **G6+** | **None created.** Every other question this train raised was either derivable or folded into G4/G5. |

---

## PRODUCTION

**PRODUCTION CHANGES: NONE.**

**PRODUCTION ACTIVATION AUTHORIZED: NO.**

---

## FINAL STATUS

| | |
|---|---|
| **G4 ARCHITECTURE READY** | **YES** — analysis complete, ruling drafted, zero-DDL option identified |
| **G5 ARCHITECTURE READY** | **YES** |
| **RECEIVABLE IMPLEMENTED** | **YES** — as a record. Not as a recovery mechanism, deliberately. |
| **094 IMPLEMENTATION READY** | **YES** |
| **REFUND ACCOUNTING READY** | **YES** — was already correct; now tested |
| **VENUE PAYOUT EXECUTOR CODE READY** | **YES** |
| **VENUE PAYOUT EXECUTOR SAFE TO DEPLOY** | **NO** — G5 unsigned |
| **PRIMARY SALEABLE BACKEND READY** | **NO** |
| **PRIMARY PAYABLE BACKEND READY** | **NO** |
| **093 PRODUCTION READY** | **NO** — G1/G2 values and the refund-claim verb's ratification come first |
| **094 PRODUCTION READY** | **NO** — G5 signature is a **deploy** precondition; a ratification row for the org-side carry is required per `PHYSICAL_POSTGRES_SCHEMA_SPEC.md:1186` |
| **KMS CEREMONY SHOULD RUN NEXT** | **NO** — but schedule it in parallel; it is the longest pole and the only irreversible item |

**RECOMMENDED NEXT CLAUDE A TRAIN**

**The dispute-writer wiring and activation-sequencing train.** Three of this train's open findings share one root: `record_dispute_native`, `mark_dispute_state` and `resolve_dispute_native` have **zero callers**, so the chargeback line arm cannot fire, `unlined_reversal` is inert, and `kernel.payout` can never reach `reversed`. Wiring the webhook's dispute branches to the native tables closes all three and is the last piece that makes the money lifecycle observable end to end.

It should carry the two small owner-item fixes that need no new policy — the ref-bearing `failed` payout, and a decision on representing a partial reversal — and then produce the **activation runbook**: the exact ordered sequence of applies, exposures, deploys, ceremony and config values, with the constraint that `kernel.payout.destination_ref` must exist before `payout.dual_control_min_minor` is ever set.

Everything else on the critical path is now owner signature or deployment sequencing rather than engineering.
