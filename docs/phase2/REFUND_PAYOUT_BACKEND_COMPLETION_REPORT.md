```
============================================================
SNATCH IT — REFUND + PAYOUT BACKEND COMPLETION REPORT
============================================================
```

**Train:** refund executability · deletion clock · transfer cardinality · venue payout executor.
**Session scope:** backend, database, money, security, signing, production readiness, activation.
**Date:** 2026-09-02 → 2026-09-03. **No UI work was performed.**

---

## REPOSITORY

| | |
|---|---|
| **BRANCH** | `feature/venue-native-and-product-v2` |
| **HEAD** | `2a6393f` |
| **PR** | [#52](https://github.com/SnatchIt-app/snatchit/pull/52), open, base `phase2/consolidation` |
| **CI** | **GREEN** — 7/7 |
| **WORKTREE** | clean |

**Entry-state discrepancy, recorded as instructed.** The prompt reported head `fc88320`; the actual
head was **`7d45cbf`** — one documentation commit from the same prior train sitting on top. Everything
else matched: clean tree, CI green, 093 at md5 `e139aeb5…`/5226 lines, assembler gate passing 24/24.

## PRODUCTION

| | |
|---|---|
| **LEDGER** | **107 rows**, ending at `092_notify_reduced` plus five timestamped website migrations. Verified at entry and again at exit. |
| **093 APPLIED** | **NO** |
| **MUTATIONS** | **NONE.** No migration applied, no edge deployed, no config set, no flag flipped, no schema exposed, no Stripe object created, no money moved, no secret rotated, no KMS material created. |
| **ACTIVATION** | **NO** |

---

## REFUND ARCHITECTURE

| | |
|---|---|
| **PFA-23** | Conformed. Correction classified **IMPLEMENTATION CLARIFICATION**, not a post-freeze amendment. |
| **PREVIOUS BLOCKER** | **Was wrong.** The prior train reported PFA-23's direct arm as mechanically unimplementable because "service_role forwarding the platform JWT" has no PostgREST realisation. That sentence is not PFA-23's normative text — it is a *grant-block comment* at `085:2145-2146`. The prior finding treated descriptive prose in an immutable migration as normative. |
| **FINAL CALLER MODEL** | `kernel.request_order_refund` (`085:850`) — granted to `authenticated`, `security definer`, carries `auth.uid()`, evaluates the same `is_platform` predicates and support cap, and for platform roles sets `v_execute := true` and calls `refund_primary_order` definer→definer under `req:<id>`. Test `149` D2 already asserted `status:'executed'`. No grant, body or frozen rule changed; only the edge changed. |
| **CLAIM PRIMITIVE** | `kernel.claim_refunds_for_execution(limit, lease)` — `service_role` only. No parameter names any subject; both are throughput and clamped. Exclusivity via `for update … skip locked` plus an append-only `kernel.admin_audit` lease row, chosen over a column because `kernel.refund` is a frozen ledger **and** because `min(occurred_at)` *is* the first-key-use instant the 24h decision needs — a mutable `claimed_at` cannot express it. `kernel.list_pending_refunds` was never built and is now retired: it would have been an enumeration verb over pending money. |
| **EXECUTOR** | Refund-row-driven. The payment resolves from `kernel.refund.payment_id`; there is no request field for a payment, PaymentIntent or charge, and one that appears is a 400 refusal. "Wrong venue" has no surface. |
| **STRIPE IDEMPOTENCY** | `refund_<refund_id>`. **A real hole was found and closed:** Stripe retains idempotency keys for **24 hours**, so a crash-replay past that boundary created a *second real refund*. The DB now issues `execution_mode` — `create` inside a 20h window, `reconcile` outside it — so a late retry must adopt the existing refund rather than mint one. |
| **CRASH RECOVERY** | `reconcile` establishes before it creates: fetch by reference, else search the PaymentIntent for `metadata[refund_id]`, refusing when `has_more`. **Second hole closed:** the sweep filtered `status==='pending'`, so a `submitted` row was reachable by nothing — stranding the refund *and* keeping BP-12 blocking that buyer's deletion forever. |
| **TOMBSTONE SUPPORT** | Verified. `085:76` restrict FK; `sweep_deletion_pending` touches neither payments nor refunds; no customer field reaches Stripe. |
| **REFUND READY** | **In development: YES.** Deployed: **NO** — and that distinction is load-bearing for ruling A9 below. |

Ratification: **`kernel.claim_refunds_for_execution` itself is PENDING OWNER RATIFICATION**, recorded in
`docs/architecture/_governance/PFA23_DIRECT_ARM_CLARIFICATION.md` §B, by the same standard that
retired `list_pending_refunds` — a verb that enumerates pending money deserves a ruling.

**Attacks:** `supabase/tests/158_refund_execution_claim.sql`, 39 assertions, all green. Concurrent
workers, stale claim recovery, lease clamping, terminal refunds never claimed, enumeration returning
SQL NULL, livemode NULL failing closed, `authenticated`/`anon` refused behaviourally. Wrong
venue/org/amount/PaymentIntent are asserted **as absences** — there is no parameter to attack.

---

## DELETION

| | |
|---|---|
| **OLD CLOCK** | `venue."order".created_at` — the payment clock (`085:262-284`). |
| **DEFECT** | Buy early, wait, and the window appears closed: the buyer tombstones **before their event has happened**, while the settlement maturity gate is simultaneously holding the venue's money for exactly that risk. |
| **NEW CLOCK** | `deletion.post_event_hold_hours`, a new key. Old key survives as an unread orphan (085 is immutable and the config table is append-only) — recorded, not hidden. |
| **EVENT ANCHOR** | `max(coalesce(session.ends_at, session.starts_at))` over the identity's paid/partially-refunded orders. `venue."order".event_session_id` is `NOT NULL … ON DELETE RESTRICT` (`082:77`), so the join is total and stable. The old comment's defence — "the only stable timestamp on the immutable 082 table" — is **true and irrelevant**: it compares two payment-clock instants. |
| **REFUND INTERACTION** | Unchanged; an open refund blocks via arm 1. |
| **DISPUTE INTERACTION** | Unchanged; BP-7. |
| **POSTPONEMENT** | The anchor moves with the session, so a postponement extends the block automatically. |
| **EARLY TOMBSTONE TEST** | 28 cases executed. Under the old clock at a 720h hold, **nine** scenarios were erasable before their event — bought-90-days-out, already-partially-refunded, session-cancelled, multi-session, multi-day, postponed, transferred-out, resold, null-`ends_at`. All now blocked at the correct instant. Bounded release still works: event 39 days past with a 30-day hold → **ERASED**. |
| **STATUS** | **CLOSED.** |

**A second defect found by execution, not by reading.** `085:273-276` casts inside an ordered target
list, so the cast hits *every* append-only version. One `"720 hours"` append raises `invalid input
syntax for type numeric` for **every identity**, swallowed by the sweep's exception handler — the
deletion machine silently stops tombstoning anyone, forever, unrecoverable without a migration. Closed
by reading raw jsonb from a subquery with `jsonb_typeof` branching.

**A deliberate asymmetry with G2, carried as a boxed warning so nobody "fixes" it:** this gate falls
back to `starts_at` on a null `ends_at` rather than failing closed. G2 can fail closed because
`release_payout` is a human exit; this gate has **no exit** — nothing can force-tombstone — so failing
closed here means an erasure request that can never complete. The correct harmonisation, if ever
wanted, is to give this gate an exit, not to take G2's failure mode.

---

## G1 — TICKET EXPIRY

| | |
|---|---|
| **CURRENT DRAFT** | `ticket.expiry_grace` seeded `'null'::jsonb`; sweep inert. |
| **RECOMMENDATION** | **Unchanged: `'"72 hours"'::jsonb`.** |
| **EXACT VALUE** | A jsonb **string** spelled in hours. |
| **EVIDENCE** | Re-evaluated after the deletion re-anchor, as instructed. BP-12 now strictly dominates BP-1 for every paid buyer at any hold ≥ grace — verified: a paid buyer 100h post-session with grace `"72 hours"` has the atom expired and BP-1 **cleared** while BP-12 still holds; a comp holder with an active atom and **no order** is blocked by BP-1 only. So this key carries deletion weight for exactly the comp/guest/import population G1 originally named — a claim that was aspirational when written and is now **structural**. The 24h floor (`door.session_absolute_max_interval`) and the 72h ratified human-reaction constant are unchanged. |
| **OWNER SIGNATURE REQUIRED** | **YES** |

**Two guards now stand behind the value, and they compose in the right order.** A bare JSON number is
refused outright at the setter (`093_parts/40:1248`) — it never reaches the approval queue, so nobody
can be asked to rubber-stamp `'24'` meaning 24 seconds. And `ticket.%` gained **dual control** this
train, so a well-typed wrong value needs a second administrator. An earlier draft of this train's own
research claimed the type trap was still live; that was wrong and is corrected in place.

---

## SOURCE_TRANSACTION / TRANSFER CARDINALITY

| | |
|---|---|
| **OLD MODEL** | One Stripe transfer binds one charge; `stripe_transfer_ref` write-once and singular; a settlement aggregates many charges → apparent contradiction. |
| **DEFECT** | **The premise was wrong, not the schema.** Every prior report assumed `source_transaction` is *required*. |
| **STRIPE REQUIREMENT** | It is **optional**. Only `amount`, `currency` and `destination` are required (`docs.stripe.com/api/transfers/create`). Without it, funds come from the platform's available balance (`docs.stripe.com/connect/separate-charges-and-transfers#transfer-availability`). |
| **SNATCH IT ASSUMPTION** | The resale rail sets it for a real reason — the August 2026 incident was a same-day charge with `available_on` ~7 days out, and `source_transaction` makes the transfer succeed regardless of settled balance. **That rail is unchanged.** The gap is absent on the settlement rail because maturity holds the payout until `max(session.ends_at) + ~7 days`, by which point every covered charge is long past `available_on`. |
| **NEW MODEL** | Aggregation belongs to the ledger, not to Stripe: N charges → N settlement lines → 1 net → **1 payout → 1 transfer → 1 ref**. |
| **PAYOUT UNIT** | The `kernel.payout` row, 1:1 with `venue.settlement` for `cause='settlement'`, under `idempotency_key='settlement:'||settlement_id`. Per-order was rejected on evidence: `close_settlement` is the sole minter and is forward-only, and each extra payout costs its own aal2 step-up and its own dual-control approval. |
| **IDEMPOTENCY** | `payout_<payout_id>_<destination>_v1`. The destination is in the key because it can change; `_v1` keeps the space disjoint from resale's `_src`. |
| **STATUS** | **RESOLVED, with no schema change on this axis.** `source_transaction_ref` keeps its shape and gains a meaning: NULL = funded from platform balance. It could not have been used anyway — not amendable, amount capped by a single source charge, and the net (`gross − fees − refunds`) corresponds to no charge amount at all. |

---

## VENUE PAYOUT

| | |
|---|---|
| **EXECUTOR** | `supabase/functions/payout-execute/` — `executor.ts` (pure, testable) + `index.ts` (Deno shell, machine-only, one service-role client). |
| **CLAIM MODEL** | `kernel.claim_payouts_for_execution(limit, lease)`, a line-for-line mirror of the refund claim: clamped operands, `for update skip locked`, lease as an audit row, no subject parameter, DB-derived command key. `execution_mode` flips to `reconcile` past 20h so a >24h retry adopts via `transfer_group` instead of minting a second transfer. |
| **DESTINATION** | **`kernel.payout.destination_ref`, new column.** Pinned at both `pending→submitted` arms of `request_org_payout`; the executor sends that value and never a fresh read. |
| **AMOUNT SOURCE** | The ledger. `kernel.get_payout_execution_context` returns `execution_eligible` + `refusal_code`; the worker adopts the verdict and cannot name an amount, destination, org, settlement, currency or key. `assertNoClientMoneyReference` refuses a request that tries. |
| **MATURITY** | Extracted to `kernel.settlement_payout_maturity(uuid)` and called from **three** sites — mint, request, transfer. |
| **STRIPE TRANSFER** | No `source_transaction`; `transfer_group = payout_<id>`. A mandatory `GET /v1/balance` preflight runs **before** an idempotency key is spent — and the ordering is enforced **by types**: `planPayoutTransfer` cannot produce a key, only `authorizeTransfer` can, and it requires both preflight verdicts as arguments. |
| **RETRY** | Safe. `PAYOUT_STATE_SYNC_TARGETS === ['paid']`, with a test driving every Stripe outcome asserting only `'paid'` is ever attempted. |
| **RECONCILIATION** | 15-code refusal ladder, one code each, all executed. |
| **DARK** | **YES.** Not deployed. |

**The constraint the executor is built around, verified against the shipped state machine:** `failed`
is **absorbing**. `submitted→failed` succeeds; `failed→paid`, `failed→reversed` and `failed→submitted`
all raise; `request_org_payout` sees zero rows for a failed payout; re-mint is blocked by `on conflict
do nothing`. **A failed settlement payout would permanently strand the venue's money.** So the executor
never writes `'failed'` — every non-success leaves the row `submitted` with an audit trail. Two facts
beyond that: `kernel.hold_payout` is **not granted to service_role at all**, so escalation genuinely
cannot be a hold; and a held row refuses the sync with both columns untouched.

---

## PROMOTER

| | |
|---|---|
| **OPTION B** | Holds mechanically. |
| **FUNDED** | Yes — commission is a negative settlement line, so venue net is reduced before any payout is minted. |
| **PAID** | **NO.** `count(*) from kernel.payout where cause='promoter_commission' and hold_state <> 'held'` = **0** after both economic chains, three refund cycles, a chargeback, an event cancellation, a re-close and a DBA-level re-open + re-close. |
| **VENUE DEDUCTION** | Proved. Across eight settlements, `gross − fees − refunds = net` on every row (a table CHECK) and `venue_payout = max(net,0)` on every row; five commission line/payout pairs, **zero mismatches**. `request_org_payout` can only select `cause='settlement'`, so it cannot re-derive an amount or reach a commission payout. **The venue is never paid the commission's dollars.** |
| **REFUND ADJUSTMENT** | Within a settlement, correct. Chain 1: lines `+10000 / +5000 / −1000 / −5000`, waterfall `15000 / 1000 / 5000 / 9000`, venue paid 9000, commission 1000 held, conservation exact. |
| **PAYOUT INTERACTION** | Chain 2: 8000 face charged at 8800; commission 800; venue payout **7200, not 8000**. A lost dispute booked `chargeback −8000`, **not −8800** — the platform's own buyer-side fee stays with the platform, which is ruling A5 holding on the debit side. |

**Static evidence for A4:** no `update kernel.payout` in the money slice; `release_payout` appears only
in comments; corpus-wide, only two functions INSERT payouts and five UPDATE them, and **none mentions
the commission cause**. `mark_payout_transfer_state` refused live with `payout_held`.

---

## G2 — PAYOUT MATURITY

| | |
|---|---|
| **CURRENT DRAFT** | Unchanged and re-confirmed under fresh attack. |
| **START INSTANT** | `max(catalog.event_session.ends_at)` over the settlement's own money lines. |
| **INTERVAL** | **7 days.** |
| **PREDICATES** | Eight codes, seven predicates, every operand pre-set to the holding value: `unbounded_refund_exposure`, `maturity_policy_invalid`, `covered_set_unresolvable`, `event_cancelled`, `maturity_instant_unknown`, `maturity_not_elapsed`, `refund_in_flight`, `dispute_open`. Plus `refund_exposure_stale` at execution, with a face cap. All confirmed by execution: config non-null alone does not release; each predicate breaks in isolation with its own code; the all-satisfied control releases; an uncomputable operand holds. |
| **POSTPONEMENT** | Anchor moves with the session. The prior "seller-mutable anchor" residual is **STRUCK** — a backward `ends_at` move on an economically-weighted session is now refused, re-verified as `org_owner` (−65d refused, `ends_at`-only −4h refused, +30d accepted). |
| **CANCELLATION** | Held via `event_cancelled` — **and a real gap was closed:** the gate was a close-time *snapshot*. `catalog.cancel_event` never touches `kernel.payout`, so a cancelled event previously left a matured payout unheld. Maturity is now re-evaluated at request and transfer, so it is an invariant rather than a snapshot. |
| **PENDING REFUND** | Held. |
| **PENDING DISPUTE** | Held — **and its blind spot was found:** `record_dispute_native` froze only on an **open** dispute, so one first observed as `lost` held nothing. The freeze was inverted relative to risk. |
| **POST-RELEASE CHARGEBACK** | **Not covered.** See below. |
| **RECOMMENDATION** | **Keep both.** The 4–6 AM nightlife case — the most likely source of an off-by-one-day error — does not matter: the gate is pure instant arithmetic on `timestamptz`, with no `date_trunc`, no `AT TIME ZONE`, no `::date`. It would only matter if the policy were re-expressed as a calendar day, and it never should be. |
| **OWNER SIGNATURE REQUIRED** | **YES** |

---

## POST-PAYOUT RISK

| | |
|---|---|
| **REFUND AFTER PAYOUT** | Unrecoverable. |
| **CHARGEBACK AFTER PAYOUT** | Unrecoverable. |
| **CURRENT ACCOUNTING** | Of six possible outcomes, only **platform absorbs** is implemented. *Future payout offset* exists **accidentally**: it works only if the organization's next settlement carries enough positive lines, and when it does it silently confiscates that later revenue while destroying any excess. No receivable object exists, and `CHECK (amount_minor > 0)` makes one unrepresentable without DDL. |
| **MEASURED** | Executed: sold 23000, paid 19000, entitled to 13000 → **platform loss 6000**. |
| **UNRESOLVED POLICY** | Yes — raised as **ruling G5**. |
| **SEVERITY** | **HIGH.** |
| **LAUNCH BLOCKER** | **Not for selling. YES for deploying the payout executor.** |
| **OWNER RISK ACCEPTANCE NEEDED** | **YES** — and the timing matters: this was tolerable only because no executor existed. This train wrote one. The protection was the absence of the thing that now exists. |

---

## PAYOUT DESTINATION

| | |
|---|---|
| **CALLER** | `connect-onboarding` runs the complete sequence: resolve → pre-mint refusals → Stripe mint → **stage** → bind (caller JWT) → verify → sync. The real order is MINT → STAGE → BIND → VERIFY, and that is correct: binding after verification would require carrying the `acct_` across a redirect, which is the stale-callback primitive already closed. |
| **AUTHORITY** | `org_owner` only for the bind; `service_role` for staging. Neither credential alone can bind. |
| **AAL** | aal2 on the bind, and now on the dashboard link. |
| **ACCOUNT SOURCE** | Platform-minted only; the bind must match a staged `connect_pending_ref`, consumed on success. |
| **CROSS-ORG DEFENSE** | Holds — cross-org staging returns `conflict_locked`. |
| **PERSONAL-ACCOUNT DEFENSE** | Forward direction held (live + archive + TOCTOU). **The reverse direction did not**, and is now closed: nothing stopped an org-bound `acct_` being written onto `public.profiles.stripe_connect_id`, which mis-routed seller payouts *and* permanently bricked that org's re-point. Closed with a `BEFORE INSERT OR UPDATE` trigger on both `profiles` and the archive — deliberately **not** in the edge, because the edge writes an id Stripe minted seconds earlier and was never the threat; the real path is a direct service-role UPDATE with no RLS in the way. |
| **REPLACEMENT RACE** | **PROVED and closed.** `kernel.payout` had zero destination columns: a re-point while `status='submitted'` redirected the transfer with no predicate refusing it, and the paid-after-change state sync then **disarmed destination probation for the next payout**. Resolution: bind at claim, re-verify at execution. The payee was decided when `request_org_payout` authorized it behind SoD-1, maturity, aal2 and a second approver; a later re-point passed none of those, so an execution-time re-read would let a new destination inherit an approval it never received. |

**The single most serious finding of this train: the `acct_` was provenance-locked; the bank account
inside it was not.** The Express Dashboard login link (`connect-onboarding:1470`) was reachable by
`org_finance` with **no aal2, no audit row and no notification** — and `org_finance` is precisely the
role SoD-1 exists to exclude from naming the payee. Every control built to protect *which* account is
bound was bypassable by changing *what is inside it*. Now `org_owner` + aal2, audited, notified, with
the authority test in **SQL** rather than the edge so that a future caller which skips the step
produces no authorization row — a detectable absence rather than a silent bypass.

**Two deliberate non-behaviours, each pinned by a test:** the dashboard grant does not stamp
`payout_destination_set_by` (an owner could otherwise clear their own SoD-1 exclusion by opening a
dashboard), and it does not write `org.payout_destination.change` (that would arm probation and hold
the next payout every time someone looked at Stripe).

**Ordering constraint that must survive into operations:** `payout.dual_control_min_minor` is seeded
NULL, so X-12 currently parks every payout and the approval row is the only thing pinning a
destination. **Setting that threshold is what creates the exposure**, so `destination_ref` must land
before that key ever does.

**Day-2 trap, recorded not fixed:** `set_org_payout_destination` is not merely uncalled, it is
**unreachable** — it requires a staged pending ref and the only staging call sits inside
`if (!accountId)`. With bind-once, **a mis-bound organization is permanently mis-bound**, and the edge
advertises a `409 destination_unusable` recovery that does not exist. Not launch-blocking; the fix is a
`mode: 'replace'` branch in the edge.

---

## MIGRATIONS

| | |
|---|---|
| **093 CHANGED** | **YES.** |
| **WHY** | 093 has never reached production, every change belongs to the same primary-ticketing atomic contract, and no intermediate deployed state exists. Each addition is itemised below rather than folded in silently. |
| **HASH** | `0e6729d72cf3f61b0a00c2683962d400`, 7241 lines (from `e139aeb5…`/5226 at entry). |
| **ASSEMBLER** | Invariant intact and re-proved: gate PASS, self-test **24/24** including assembler-level bypasses. The header's "0 DDL on any money-ledger table / 2 new columns" claim became false with `destination_ref` and was corrected in place with the reason. |
| **094 REQUIRED** | **No — but three items are explicitly deferred to it**: the absorbing-`failed` exit, a receivable/negative-obligation object, and the `suspended` org check on `request_org_payout` (the twin of the sale-gate fix landed here). |
| **EXISTING ROW MUTATIONS** | **NONE.** |

**Scope additions to 093, each justified:** `kernel.payout.destination_ref` (a proved replacement race
— the only DDL on a money-ledger table, called out in the assembler header because that rule was
load-bearing); `deletion.post_event_hold_hours`; six new kernel functions for the refund claim, payout
claim/context/maturity/hold and dashboard authority; two triggers for the reverse cross-plane guard;
`fee.%`, `deletion.%` and `ticket.%` added to dual control; and body-only replacements of
`deletion_blockers_money`, `set_platform_config`, `create_primary_checkout`, `request_org_payout`,
`close_settlement` and `issue_ticket_atoms`.

**Gate-2 moved for the first time in the 093 program:** triggers **24 → 26**, verified against reality
(`tg_profiles_connect_id_not_org_bound`, `tg_connect_archive_not_org_bound`) and updated in `ci.yml`.
Tables, functions and policies unchanged. Kernel functions **109 → 125**, re-derived by diffing
`pg_proc` against a 092 build and pinned **by name** with `prosecdef` and grant class, so the next
person to move the count must say what they added.

---

## ACTIVATION

| Gate | State | Enforcement |
|---|---|---|
| **DRAFT** | **YES** | SQL, complete |
| **PUBLISHABLE** | **YES** | SQL for what it claims. A8's "`on_sale` requires Connect readiness" is **documentation only** — `publish_event` reads no Stripe column, config key or signing key. |
| **SALEABLE** | **NO** | SQL. Ladder executed refusal-by-refusal: buyer active → session sellable → **`org_not_active`** → `payout_not_ready` → `no_active_signing_key` → `service_fee_unset`. |
| **PAYABLE** | **NO** | SQL at three instants (mint, request, execution). Then it stops: the executor is dark and G5 says unshippable. |

**REMAINING SALEABLE BLOCKERS:** 093 unapplied; `catalog`/`venue` not exposed over PostgREST;
`primary-checkout` and the webhook native branch undeployed; `fee.buyer_service_bps` unset (G1/G2
values); no signing key (G3); no organization has a bound destination.

**REMAINING PAYABLE BLOCKERS:** everything above, plus the payout executor undeployed, G5 unresolved,
and no organization payout destination in existence.

**The owner's six questions, answered from execution.** SALEABLE *can* be YES with the refund executor
unavailable (the only two `refund` strings in the checkout function are comments), with tax unresolved
(zero functions, columns or keys), and with the payout executor unavailable. It *cannot* be YES with
signing unavailable, the fee unset, or no payout destination.

**Ruling A9, adjudicated honestly.** This train closed two of its three grounds — the sweep self-heal
now exists and PFA-23's direct arm is reachable. The third stands: **not deployed**. And A9's second
disjunct, a named written process, does not exist. So **A9 is currently a policy gate with zero code
behind it**: nothing in checkout refuses a sale because refunds cannot execute. That is a gap between
a ratified ruling and the machine, and it is the owner's to close by choosing deployment or a named
process.

**New finding, closed this train:** a **suspended organization could still sell**. `create_primary_checkout`
read `kernel.organization` for two columns and never `status`, though 093 had already added
`status ∈ ('approved','active')` to both binders and the dashboard verb. Now gate G2a, placed *before*
the connect gate so the operator learns the fundamental fact first.

---

## G3 / KMS

| | |
|---|---|
| **CEREMONY MODIFIED** | No. |
| **PRODUCTION KEY CREATED** | **NO** |
| **PRODUCTION SIGNING ROW** | **NO** |
| **G3 SIGNED** | **NO** |
| **IS G3 NOW THE TRUE NEXT CRITICAL PATH** | **NO** |

**Why.** `payout_not_ready` (`093:3983`) fires *before* `no_active_signing_key` (`093:4033`) — proved by
execution: an unbound organization refuses before the signing resolver is reached. And
`connect_transfers_active` has **two** writers, both undeployed. Ahead of the ceremony sit 093 itself,
PostgREST schema exposure, and two undeployed edge functions — none of which is configuration, contra
ruling G3's framing. **But it is the only irreversible item and it gates the first production *quote*,
so it parallelises and should land before checkout is enabled.**

**Gap classification (§27):** superuser dual-control bypass — ACCEPTED OPERATIONAL RISK; shadow scoped
key — ACCEPTED (subset of the first); `not_after` mutable — FORWARD OBLIGATION, trigger is the first
rotation; in-band revoke parked — ACCEPTED, no consumer exists; door force-close — FORWARD OBLIGATION,
due before the first *scan*, not the first sale; `.gitignore` — ACCEPTED, ceremony runs outside any
repo. **Arming the §9.3 daily invariant query as a real scheduled job with an alert destination is
itself a launch blocker** — a monitor that lives only in a runbook is not a control.

**Runbook staleness, reported not edited:** mint citations predate 093's `issue_ticket_atoms`
replacement; §1.3 is materially incomplete because it omits the quote-time gate, understating the
ceremony as a webhook dependency when it is now a storefront one; §9.4's CI grep now returns nothing.
Confirmed: no example secret, no plausible key material, no real KMS identifier anywhere in it.

---

## SECURITY

**P0 — 2 found, 2 fixed.**
1. The Express Dashboard login link let `org_finance` change the payout bank account with no step-up,
   no audit and no notification.
2. The payout replacement race: a re-point redirected a submitted payout with no predicate refusing it,
   and then disarmed probation for the next one.

**P1 — 6 found, 6 addressed.** The 24h Stripe idempotency window creating a second real refund; the
sweep unable to recover a `submitted` refund (also blocking that buyer's deletion forever); the
deletion clock anchored to payment; the reverse cross-plane injection onto `profiles`; maturity as a
close-time snapshot; a suspended organization able to sell.

**P2 — recorded, not fixed.** The unreachable re-point verb (permanent mis-binding); the config-cast
poisoning vector (fixed for `deletion.%`, the pattern remains elsewhere); `pay_promoter_commission`
still able to raise inside a seam contra the 087 contract; `venue.settlement.status` lacking the
append-only trigger its lines have.

---

## ADVERSARIAL REVIEW

**CLAIMS OVERTURNED — five, including three of my own from prior trains.**
1. PFA-23's direct arm is *not* unimplementable. My prior finding read a **grant-block comment** as
   normative text.
2. `source_transaction` is *not* required. Every prior report's cardinality contradiction rested on it.
3. `get_refund_execution_context` was reported unauthored; it exists.
4. The maturity analysis's "the most a seller can shave is hours, not months" — the backward-move guard
   has since made this moot, but the bound as stated was wrong.
5. This train's own claim that the `ticket.expiry_grace` type trap was still live — it was closed last
   train, and the researcher corrected it in place.

**DEFECTS FOUND: 14. DEFECTS FIXED: 8.**

**OPEN FINDINGS:** the post-payout receivable (G5); funded commission on reversed revenue (G4); the
absorbing-`failed` exit; the unreachable re-point verb; `request_org_payout`'s missing suspended-org
check; A9's missing enforcement.

---

## TESTING

| | |
|---|---|
| **PGTAP** | **3062 planned, 3058 pass.** The 4 failures are the documented local-only deltas (060's two TODOs; 132's two `cron.job.database` name artifacts). |
| **VITEST** | **375/375**, 10 files. |
| **TYPECHECK** | clean, exit 0 |
| **LINT** | 0 errors, 12 pre-existing warnings |
| **WEB** | passes |
| **MOBILE** | typecheck clean; no shared contract changed |
| **FRESH DB** | 108/108 replay, Gate-2 matching the CI baseline |
| **IMMUTABILITY** | pass; migrations 000–092 byte-identical |
| **ASSEMBLER** | gate pass; self-test **24/24** |
| **CI** | **GREEN**, 7/7 |

New coverage added for every property this train established, not merely repaired: the refund claim
(39 assertions in a new file `158`), the payout executor (57 vitest cases), the maturity conjunction's
post-close arms each with a release-at-close **control** so the refusal is attributable, the deletion
anchor across 28 scenarios, and dual-control parking for all three new prefixes.

---

## OWNER DECISIONS STILL REQUIRED

| | |
|---|---|
| **G1** | Ticket expiry — recommendation **unchanged**: `"72 hours"`, now on structural rather than aspirational grounds. **Signature + value.** |
| **G2** | Payout maturity — recommendation **unchanged**: `max(session.ends_at)` + **7 days**, re-confirmed under fresh attack. **Signature + value.** |
| **G3** | Signing ceremony — unchanged, **not** the next critical path but the only irreversible item and the longest pole. **Signature + two named people + a window.** |
| **G4** | **NEW.** Funded promoter commission when the revenue is reversed. No mechanism exists to reduce it; in rehearsal **79% of funded commission stood against reversed revenue**. Contained by exactly one fact — nobody has released a commission hold. **Four options, no recommendation offered:** this is what a promoter is *told* they are owed, not a ledger shape. |
| **G5** | **NEW.** Post-payout refund/chargeback exposure. Only "platform absorbs" is implemented; measured loss 6000 on a single settlement. **Blocks deploying the payout executor, not selling.** |

---

## PRODUCTION

**PRODUCTION CHANGES: NONE.**

**PRODUCTION ACTIVATION AUTHORIZED: NO.**

Money darkness re-verified on a live replay after every change: all feature flags false; all five
owner-set keys null (`ticket.expiry_grace`, `fee.buyer_service_bps`,
`payout.settlement_maturity_interval`, `deletion.post_event_hold_hours`,
`payout.dual_control_min_minor`); **zero signing keys**; no organization has a payout destination; no
edge function deployed.

---

## FINAL STATUS

| | |
|---|---|
| **REFUND BACKEND READY** | **YES** (development; not deployed) |
| **DELETION SEMANTICS READY** | **YES** |
| **VENUE PAYOUT BACKEND READY** | **YES** as code; **NO** to ship — G5 is a precondition |
| **PRIMARY BACKEND SALEABLE READY** | **NO** |
| **PRIMARY BACKEND PAYABLE READY** | **NO** |
| **093 PRODUCTION READY** | **NO** — G1/G2 values, G4 direction, and ratification of the refund claim verb come first |
| **KMS CEREMONY READY** | **YES** — prepared, rehearsed 12/12, not executed |
| **KMS CEREMONY SHOULD RUN NEXT** | **NO** — but schedule it in parallel now; it is the longest pole and must land before checkout is enabled |

**RECOMMENDED NEXT CLAUDE A TRAIN**

**The receivable object and executor-shipping train.** G5 is the one open item that is both a hard
precondition of moving venue money and a genuine schema decision — a receivable or reserve that makes
a negative obligation representable, which `CHECK (amount_minor > 0)` currently forbids. It naturally
carries the two 094 items already identified: an exit from the absorbing `failed` state, and the
suspended-organization check on `request_org_payout`. Those three together are what stand between "the
executor is written" and "the executor can safely be deployed".

Everything else on the critical path is now owner action or deployment sequencing rather than
engineering: apply 093, expose two schemas, deploy four edge functions, run the ceremony, set five
config values in order.

**One sequencing constraint that must not be lost in any of it:** `kernel.payout.destination_ref` must
exist before `payout.dual_control_min_minor` is ever given a value. That key is seeded NULL, so X-12
currently parks every payout and the approval row is the only thing pinning a destination. Setting the
threshold is what creates the exposure — the opposite of how a configuration value normally reads.
