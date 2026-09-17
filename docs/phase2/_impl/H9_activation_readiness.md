# H9 — Activation readiness: the four gates, re-derived

**Scope: verification and documentation only.** No migration, slice, edge, test or configuration was
changed. Nothing was deployed. No production object was contacted. No commit. This pass owns exactly
two files: this one and `docs/phase2/PRIMARY_TICKETING_ACTIVATION_MATRIX.md`.

**Evidence base.** A full local replay — `./scripts/rehearsal_reset.sh snatchit_rehears_act`,
**108/108 migrations applied**, `GATE-2 tables=27 functions=70 policies=37 triggers=26`, matching the
CI baseline at `.github/workflows/ci.yml:581-584` — plus source reads at
`feature/venue-native-and-product-v2`. Every result marked **[X]** below was executed by this pass in
that database, inside `BEGIN … ROLLBACK`; the database was left with zero fixture residue. Claims
inherited from `H1`–`H8` are marked as such and were re-checked against the replayed catalogue, not
copied.

**Note on the CI baseline.** The matrix and `H4`/`H5`/`H6` all record `triggers=24`. It is now **26**
(`EXPECT_TRIGGERS` was moved 24 → 26 by H6 §8.3 for the two `guard_connect_id_not_org_bound`
triggers). Documents written earlier in the train are stale on that number only.

---

## 1. THE FOUR GATES, WITH ENFORCEMENT STATUS

An unenforced gate is a finding, not a gate. Each predicate below is labelled **SQL** (a database
refusal), **EDGE** (a refusal that exists only in TypeScript), or **DOC** (asserted by a ruling and
enforced by nothing).

### GATE 1 — DRAFT · a venue may build an event

**Predicate:** `kernel.organization.status ∈ ('approved','active')` ∧ `catalog.venue.approval_status
= 'approved'` ∧ caller holds `org_owner`/`org_admin` on the org or `venue_manager` on the venue.

**Enforcement: SQL, complete.** No money, Stripe, config or signing operand participates.

**[X]** The whole chain org → venue → event → session was built in a database with
`select count(*) from kernel.signing_key = 0`, `stripe_connect_account_ref IS NULL`, and every owner
config key at `'null'::jsonb` — confirming G6's original result on the current bytes.

### GATE 2 — PUBLISHABLE · an event may become visible

**Predicate** (`catalog.publish_event`): forward-only transition
`draft→announced→on_sale→live→completed`; caller role as gate 1; **and for `on_sale` only**, at least
one `venue.ticket_type` carrying at least one `venue.inventory_batch` (`empty_inventory`).

**Enforcement: SQL for what it claims. The A8 half that matters is DOC.** Ruling A8 marks `on_sale`
as requiring Connect readiness. `publish_event` reads no Stripe column, no config key and no signing
key — verified by reading the deployed body in the replay. **The transition half of SALEABLE is
enforced by nothing.** 093's OUT table declined to gate it on the ground that `announced` is harmless
marketing state; that reasoning does not extend to `on_sale`, and the consequence is that an event
displays as on sale while every purchase refuses. Unchanged this train, and still an owner item.

### GATE 3 — SALEABLE · a buyer may create a primary order

**Predicate** (`venue.create_primary_checkout`, `093:3845`), in the order the function evaluates it —
**[X] the whole ladder was executed, refusal by refusal**:

| # | Refusal | Operand | Enf. |
|---|---|---|---|
| 1 | `deletion_pending` / `identity_erased` | buyer's `kernel.identity_ext.deletion_state` | SQL |
| 2 | *(idempotency short-circuit — returns the original order)* | `venue."order".command_idempotency_key` | SQL |
| 3 | `no items` / `not_found: session` | request shape; session exists | SQL |
| 4 | `not_on_sale` / `session_terminal` | `catalog.event.status ∈ ('on_sale','live')`; session not `completed`/`cancelled` | SQL |
| 5 | **`payout_not_ready`** (`093:3983`) | `org.stripe_connect_account_ref IS NOT NULL` **∧** `org.connect_transfers_active IS TRUE` | SQL |
| 6 | **`no_active_signing_key`** (`093:4033`) | one `kernel.signing_key` `status='active'`, in `not_before`/`not_after` window, resolvable `per_event → per_venue → global` | SQL |
| 7 | **`service_fee_unset`** / `service_fee_out_of_range` (`093:4062`) | `fee.buyer_service_bps` present and integer `0..10000` | SQL |
| 8 | hold/inventory refusals | `feature.native_issuance_enabled`, `inventory.hold_ttl_interval`, `inventory.per_user_active_hold_max` (consumed upstream by `venue.reserve_primary_inventory`) | SQL |

**[X] Executed, in one continuous fixture:**

```
STEP 1  org unbound                                   -> precondition_failed: payout_not_ready
STEP 2  acct_ bound + connect_transfers_active=true,
        select count(*) from kernel.signing_key = 0   -> precondition_failed: no_active_signing_key
                                                         — an active signing key must resolve for the
                                                           event scope before a ticket can be sold
STEP 3  one active global signing key inserted        -> precondition_failed: service_fee_unset
```

**This retires the "F-2" finding.** See §4, correction C-1.

**What is NOT in the SALEABLE predicate**, verified by reading the deployed body: refund
executability (the only two occurrences of the string `refund` in the function are comments, at its
internal lines 142 and 325 — **[X]**); any tax operand (**[X]** zero functions, zero columns and zero
config keys match `%tax%` across `kernel`/`venue`/`catalog`/`public`); the payout executor; any
`payout.*` or `refund.*` policy key; and `kernel.organization.status` (see §5, F-13).

### GATE 4 — PAYABLE · venue money may leave the platform

Not one predicate — **three, at three instants**, which is the material change this train made.

**4a · MINT (`kernel.close_settlement`, `093:640`).** Calls
`kernel.settlement_payout_maturity(settlement_id)` (`093:2076`) to decide the minted payout's
`hold_state`. Eight reason codes — **[X]** confirmed present in the deployed body:
`unbounded_refund_exposure` · `maturity_policy_invalid` · `covered_set_unresolvable` ·
`event_cancelled` · `maturity_instant_unknown` · `maturity_not_elapsed` · `refund_in_flight` ·
`dispute_open`. **SQL.**

**4b · REQUEST (`kernel.request_org_payout`, `093:1743`).** `org_owner`/`org_finance`; settlement
closed; SoD-1 setter exclusion; money-role maturity (`authn.money_role_maturity_hours`, seeded 72);
aal2 step-up; destination cool-down; destination non-NULL (`no_payout_destination`); a `pending`
payout exists; `hold_state = 'none'`; dual control above `payout.dual_control_min_minor`. **New this
train:** it re-runs `settlement_payout_maturity` and returns `maturity_held`, and it writes
`kernel.payout.destination_ref` on **both** `pending → submitted` arms. **SQL.**

**4c · EXECUTION (`kernel.get_payout_execution_context`, `093:2266`, reached through
`kernel.claim_payouts_for_execution`, `093:2638`).** Refusal ladder, first-failing-wins:
`destination_changed` · `org_not_active` · `connect_transfers_inactive` · `destination_cooldown` ·
`amount_ledger_mismatch` · `org_mismatch` · `destination_individual_plane` · `maturity_not_elapsed` ·
`event_cancelled` · `refund_in_flight` · **`refund_exposure_stale`** (`093:2383`, this instant only) ·
`unbounded_refund_exposure` · `payout_held` · `transfer_already_recorded` · `destination_not_bound`.
**SQL.**

**And then it stops.** The transfer itself needs `supabase/functions/payout-execute/` —
**[X] present in the tree, undeployed**, and declared NOT SHIPPABLE by H8 §9 and ruling G5. The
reachable terminal state of a settlement payout today is `submitted` with
`stripe_transfer_ref = NULL`.

**Enforcement gaps that survive inside PAYABLE:**

| Predicate | 4b request | 4c execution |
|---|---|---|
| `connect_transfers_active` | **MISSING** — **[X]** the column is read by exactly five routines: `get_org_connect_state`, `sync_org_connect_state`, `venue.create_primary_checkout`, `get_payout_execution_context`, `hold_payout_destination_changed`. `request_org_payout` is not among them. | **ENFORCED** (new) |
| `organization.status ∈ ('approved','active')` | **MISSING** — **[X]** the body carries no org-status arm (H6 F-6) | **ENFORCED** (new) |
| destination pinned at authorization | **ENFORCED** (new, `destination_ref`) | **ENFORCED** (new) |
| receivable for a post-payout debit | **DOC only** — G5, unbuilt | **DOC only** |

**Promoter payout** is a fourth instant and its gate is *never*: commission payouts are minted
`held`/`unfunded_settlement` and **[X]** nothing in the corpus clears that hold. That is ruling A4
working, enforced by absence, and G4 must be signed before it is ever released.

---

## 2. THE OWNER'S SIX QUESTIONS ABOUT SALEABLE

> Can SALEABLE be YES if —

| Condition | Answer | Why |
|---|---|---|
| the **refund executor** is unavailable | **YES** | No refund operand exists in the gate. **[X]** verified against the deployed body. A9 forbids this; **A9 is enforced by nothing in code.** See §3. |
| **signing** is unavailable | **NO** | `no_active_signing_key`, refusal #6. **[X]** executed. |
| **tax** is unresolved | **YES** | **[X]** zero tax functions, columns or config keys anywhere. Nothing to check, so nothing is checked. |
| **fee** is unset | **NO** | `service_fee_unset`, refusal #7. **[X]** executed. |
| the **payout executor** is unavailable | **YES** | No operand. And this answer is now *worse* than it was: H4 D-4 rated post-payout loss acceptable **because** no executor existed. One exists now. It is dark, and G5 is unsigned. |
| the **payout destination** is unavailable | **NO** | `payout_not_ready`, refusal #5, requires a bound `acct_` **and** a live `transfers` capability. Two caveats: it is the *org*-plane destination only (a promoter has none, and none is required to sell), and it does not check that the destination is correctable — H6 F-5's BIND-ONCE gap means a mis-bound org sells into an account it cannot re-point. |

**SALEABLE and PAYABLE are not equated here, and should not be.** A sale can be honoured with money
held: the buyer receives a ticket, the venue's money sits in a durable ledger obligation, and A3 is
satisfied. That is a legitimate launch posture with a disclosure obligation attached (G6 §4.1) — not a
defect. What a sale must never outrun is the **refund** obligation, which is the buyer's money, not
the venue's.

---

## 3. RULING A9 — DOES THIS TRAIN SATISFY IT?

A9's operative text (`PRIMARY_TICKETING_FINAL_OWNER_RULINGS.md:644-684`, quoted at
`G6_activation_gates.md:293-299`):

> *"Venue-direct selling may not be activated until a refund recorded by the database results in money
> actually returning to the buyer, **by an automated executor or by a named written process with a
> named accountable human and a defined write-back step**. A refund path that voids a buyer's ticket
> without returning their money is not acceptable at any volume, including a single sale."*

G6 held the built executor failed this on **three** independent grounds. Two are now closed:

| G6 ground | Status after this train |
|---|---|
| The self-heal `sweep` is dead — `kernel.list_pending_refunds` does not exist, the action answers 501 | **CLOSED.** The verb was deliberately never built; H1 §3 replaced it with **`kernel.claim_refunds_for_execution`** (`093:1311`), a claim/lease primitive in the `064` house pattern. **[X]** the function exists, is `service_role`-only, and `refund-execute/index.ts:644` calls it. A `submitted` row stranded mid-flight is now claimable, and the 24-hour idempotency hole is closed by the DB-issued `execution_mode`. |
| PFA-23's direct arm is unreachable in both directions | **CLOSED, and the prior finding was wrong.** The authority was never missing: `kernel.request_order_refund` (`085:850`) is granted to `authenticated`, carries `auth.uid()`, evaluates the same `is_platform` predicates and the same cap under the same payment lock, and calls `refund_primary_order` definer→definer. `refund-execute/index.ts:750` now routes the direct arm there. Recorded citably at `docs/architecture/_governance/PFA23_DIRECT_ARM_CLARIFICATION.md`. |
| **It is not deployed** | **OPEN.** `supabase/functions/refund-execute/` is authored and undeployed; the production record lists three deployed edges and *"No other function touched."* (`docs/release/PHASE2_DEPLOYMENT_RECORD_20260902.md:25-29`). |

**Verdict: A9 is NOT satisfied, and the residual is now a single deploy act rather than three
structural defects.** Two things must be said with it:

1. **A9's second disjunct is unwritten.** No named written process with a named accountable human and
   a defined write-back step exists anywhere in the corpus. If the owner intends to launch on that
   disjunct rather than on the executor, the document does not exist yet.
2. **E4 §6.1 is still open and this train sharpened it.** The executor is what makes
   `kernel.refund.status = 'failed'` reachable for the first time, and slice 10b books the venue's
   negative `refund_void` line for any refund with `status <> 'failed'` — i.e. while still `pending`.
   A Stripe-accepted-then-unsettled refund leaves the buyer unpaid **and** the venue permanently
   debited in an append-only ledger. Four shapes, none chosen (H1 §6).

**And the structural point the owner should hear plainly: A9 is a policy gate with no code behind
it.** Nothing in `venue.create_primary_checkout` refuses a sale because refunds cannot execute. The
only thing enforcing A9 today is that `primary-checkout` is not deployed either. When it is deployed,
A9 becomes a promise kept by deploy ordering and by nothing else.

---

## 4. CORRECTIONS TO THE ACTIVATION MATRIX

Each was verified this pass, not inherited.

**C-1 — `MATRIX:92,95`, the known stale claim. The checkout gate DOES check signing state.**
The matrix reads *"Required signing state: NOT CHECKED BY THE GATE — and it should be"* and
*"[V] An order was created with zero signing keys in the database … G6 finding F-2."* That was
contradicted by code in the same commit (`fc88320`) that wrote it. **[X] Executed:** with the org
bound and transfers active and zero signing keys, `create_primary_checkout` raises
`no_active_signing_key` at **quote** time, before any order row exists. The buyer-charged-then-no-key
hazard is closed *before* the charge. F-2 is retired. The consequence H7 §2 item 2 draws is the one
that matters: **once 093 applies, no primary checkout can be quoted at all until the KMS ceremony has
run** — the ceremony moved from a webhook-time dependency to a storefront-time one.

**C-2 — `MATRIX:95(c)` and `H7 §3` Reason 1: `connect_transfers_active` has TWO writers, not one.**
Both documents say the only caller of `kernel.sync_org_connect_state` is the `account.updated` arm of
`stripe-webhook`. **[X]** `connect-onboarding/index.ts:1151` calls it too — it is the mirror write at
the end of the onboarding flow (H6 §1.2). Both edges are undeployed, so the conclusion — no writer in
production — is unchanged, but the citation is wrong and the fix is one deploy earlier in the path
than the matrix implies.

**C-3 — `MATRIX:132(c)` and critical-path step 3: `kernel.list_pending_refunds` is retired, not
pending.** It was never built and will not be; the sweep's 501 is gone. Step 3 of the critical path
("a small migration") is deleted and replaced by H1 §5.4's **ratification** of
`claim_refunds_for_execution` — a `service_role` verb that enumerates money in flight, which by E4's
own standard needs a signature before 093 applies.

**C-4 — `MATRIX:132(d)`: PFA-23's direct arm is reachable.** The matrix's *"a refund can be recorded,
just never executed"* is now wrong on the authority axis (it stays right on the deployment axis).
E4 §7's three options are moot.

**C-5 — `MATRIX:160` and critical-path step 0a: the `source_transaction` cardinality question is
RESOLVED and is not a paper blocker.** H3 shows the premise assumed `source_transaction` is required
to create a transfer; it is an optional funding hint. The cardinality is
**N charges → N lines → 1 net → 1 payout → 1 transfer → 1 ref**, the payout unit is the
`kernel.payout` row (1:1 with the settlement for `cause='settlement'`), and
`source_transaction_ref` stays NULL on this rail. **No schema change on that axis.** Step 0a is
deleted. What replaces it at the head of the PAYABLE path is **G5** — the receivable/reserve decision
— which is a genuinely open owner ruling.

**C-6 — `MATRIX:143` row 10: a payout executor now exists.** `supabase/functions/payout-execute/`
(`executor.ts` + `index.ts`, 57 tests) is authored, dark and undeployed, and H8 §9 declares it **not
shippable** until (a) the maturity re-evaluation fix — done — and (b) a receivable or reserve object —
not done. The matrix's *"[V] none exists"* is stale.

**C-7 — `MATRIX:139(d)` row 9: the mutable maturity anchor is CLOSED in code.** Slice 40 adds a
backward arm to `catalog.update_event_session` (`093:6907`, refusal at `093:7143`,
`backward_schedule_move_frozen`) that refuses any earlier `ends_at` move on a session carrying
economic weight, and refuses setting a previously-NULL `ends_at` to an already-elapsed instant.
Postponement — the safe direction, which lengthens the hold — still succeeds. G2 Part 3's residual and
its Part 6 owner item should be struck.

**C-8 — the deletion clock is a different key.** `deletion.refund_possible_window_hours` survives as an
**unread orphan** (`platform_config` is append-only; it cannot be withdrawn). The live key is
**`deletion.post_event_hold_hours`** (`093:5808`), anchored to
`max(coalesce(session.ends_at, session.starts_at))` over the identity's paid/partially-refunded
orders, hours-typed, and dual-controlled. **[X]** both keys are present and both read `null`; the
config census is 49 keys.

**C-9 — three hazard rows in the matrix are fixed.** `fee.%`, `deletion.%` and `ticket.%` joined the
dual-control prefix set (`093:6705`). **[X] Executed as a real `platform_admin` (aal2)** against the
live setter:

```
fee.buyer_service_bps            -> {"status":"parked", version 1, request_id …}
deletion.post_event_hold_hours   -> {"status":"parked", …}
ticket.expiry_grace              -> {"status":"parked", …}
payout.settlement_maturity_interval -> {"status":"parked", …}
payout.dual_control_min_minor    -> {"status":"parked", …}
feature.native_issuance_enabled  -> {"status":"ok", version 2}
inventory.hold_ttl_interval      -> {"status":"ok", version 2}
inventory.per_user_active_hold_max -> {"status":"ok", version 2}
```

**C-10 — every `093:NNNN` citation in the matrix moved.** 093 is now **7 198 lines**; the pre-train
citations (`093:2325`, `:2458`, `:2482`, `:1966`, `:1087`, `:2862`, `:2717`, `:413`, `:618`) are all
wrong by more than a thousand lines. Re-cited throughout.

**C-11 — `MATRIX:43` row 1(c) mis-frames `set_org_payout_destination`.** "No non-comment caller" is
true and **[X]** re-confirmed, but H6 §2.2/§2.3 show the verb is **not on the launch path** — the
launch binder is `kernel.set_org_connect_ref`, which fully establishes the destination — and that the
re-point verb is **unreachable**, because its `connect_pending_ref` precondition has no staging
producer for an already-bound org. The correct framing is a **day-2 gap (F-5): BIND-ONCE plus an
unreachable re-point means a mis-bound organization is permanently mis-bound**, while the edge's
`409 destination_unusable` arm advertises a recovery that does not exist.

**C-12 — `MATRIX:15` GATE-2 baseline.** `triggers=24` → **26**.

---

## 5. F-13 — A NEW FINDING: A SUSPENDED ORGANIZATION CAN STILL SELL

**[X] Executed.** With `kernel.organization.status = 'suspended'`, a bound `acct_`,
`connect_transfers_active = true` and one active global signing key, `create_primary_checkout`
passes both money gates and refuses only on the fee key:

```
suspended org + acct_ bound + transfers active + 1 signing key
  -> precondition_failed: service_fee_unset      (NOT org_suspended)
```

`create_primary_checkout` reads `kernel.organization` for exactly two columns
(`stripe_connect_account_ref`, `connect_transfers_active`) and **never reads `status`**. 093 added
`status ∈ ('approved','active')` to *both* Connect binders and to
`kernel.authorize_org_payout_dashboard`; it did not add it to the sale gate, and H6 F-6 records the
same omission in `kernel.request_org_payout`. So **suspension freezes the binder and the dashboard,
and leaves both the storefront and the payout request running.** Severity: MEDIUM — suspension is the
platform's own risk lever, and today it does not stop the platform becoming merchant of record for
that org's tickets. Recorded, not fixed: it is a body change to a money-path function and belongs to a
094 with an owner ruling, not to a documentation pass.

---

## 6. THE CRITICAL PATH — ADJUDICATING KMS

**The prior train said the KMS ceremony was the critical path. H7 said no. H7 is right, and I can now
prove the first of its two reasons by execution rather than by reading.**

**Evidence 1 — the signing key is the *second* refusal, not the first. [X] Executed** (§1, gate 3):
an unbound org refuses `payout_not_ready` and never reaches the resolver. Bootstrapping a key today
changes no observable behaviour anywhere.

**Evidence 2 — `connect_transfers_active` has no writer in production. [X]** Its only writer is
`kernel.sync_org_connect_state`, whose two callers are `connect-onboarding/index.ts:1151` and
`stripe-webhook/index.ts:1268` — **both undeployed** (correction C-2). Production runs three edges,
none of them these (`PHASE2_DEPLOYMENT_RECORD_20260902.md:25-29`).

**Evidence 3 — three deploy acts and one API cutover sit in front of the ceremony.** 093 is not
applied (production ledger 107 = migrations 000–092; the repo holds 108 files, **[X]** all replayed).
`catalog` and `venue` are not exposed over PostgREST in production — the 2026-09-02 cutover set
`public,graphql_public,kernel` and probed `venue` returning `PGRST106`
(`PHASE2_DEPLOYMENT_RECORD_20260902.md:23-25`) — so no client can call `create_primary_checkout` at
all.

**But H7's own framing needs one amendment, and it is the reason the ceremony must still be scheduled
first.** Since G2b, the ceremony gates the first production **quote**, not the first mint. Its lead
time is organizational (D1 unchosen; two named individuals with separated cloud IAM; a booked
window), so it is the only item on the list whose duration is not under engineering control, and it
is the only irreversible one. **It is not the head of the path; it is the longest pole, and it
parallelises.**

### The ordered path to a first production sale

Paper items 0a–0f gate the engineering items that name them; the numbered steps are strictly ordered.

| Step | Act | Kind | Gates it clears |
|---|---|---|---|
| **0a** | **G5** — receivable/reserve vs. explicit risk acceptance | owner ruling | blocks *deploying* `payout-execute`; does **not** block selling |
| **0b** | **G3** — provider (D1), two named operators, a booked window | owner ruling + people | step 7 |
| **0c** | **G1** (`ticket.expiry_grace`) and **G2** (`payout.settlement_maturity_interval`) values | owner values | step 8 |
| **0d** | Ratify `kernel.claim_refunds_for_execution` (H1 §5.4) | owner signature | **hard gate before step 1** |
| **0e** | Tax model; A5 processing-cost allocation; the `on_sale` gating choice | owner + counsel | 3, 5, 9 |
| **0f** | H2's rename of PFA-22's key (`deletion.refund_possible_window_hours` → `deletion.post_event_hold_hours`) — an owner-signed spelling changed | owner acknowledgement | deletion, not selling |
| **1** | **Apply 093** to production (ledger 107 → 108) | migration | 1, 4, 5, 6, 8, 9, 11 |
| **2** | Expose `catalog` + `venue` over PostgREST — **after** step 1 (E2 AB-8) | operational, two-person | 4, 5 |
| **3** | Deploy **`connect-onboarding`** | deploy | 1 — and it is the *first* writer of `connect_transfers_active` |
| **4** | Deploy **`stripe-webhook`** (native branch) | deploy | 6, 7 — the ongoing connect-state writer and the only caller of `finalize_primary_order` |
| **5** | Deploy **`refund-execute`** | deploy | 8 — **A9's first disjunct; must precede step 9** |
| **6** | Onboard one organization: mint → stage → bind → verify → sync | operational | makes `connect_transfers_active` true for one org |
| **7** | **KMS ceremony** + insert the bootstrap `kernel.signing_key` row (commented out at `093:5867`) | owner ceremony, irreversible | 5, 6, 7 — **schedule at 0b, land before step 9** |
| **8** | Owner config, in this order: `inventory.*` (single admin) → `ticket.expiry_grace` (quorum) → `payout.settlement_maturity_interval` (quorum) → `deletion.post_event_hold_hours` (quorum, **only after step 5**) → `fee.buyer_service_bps` (quorum) | owner config | 4, 5, 7, 9 |
| **9** | Deploy **`primary-checkout`** — last; it is the only thing that can take money | deploy | 5 |
| **10** | `feature.native_issuance_enabled = true` — last of all, single admin | config | 4, 5, 7 |

**Separately, and after a first sale, the PAYABLE tail:** 0a signed → build the receivable or reserve
object → deploy `payout-execute` → only then may `payout.dual_control_min_minor` be set. And **G4
before any promoter commission hold is released** — never `kernel.release_payout` on a
`promoter_commission` payout until it is signed.

**Two ordering constraints that are not visible from any single row:**

* `deletion.post_event_hold_hours` must not be set before `refund-execute` is deployed. Setting it
  stops BP-12 arm 2 blocking, and a buyer whose refund is stranded `pending` forever becomes
  erasable. **Nothing enforces this ordering; it belongs in the runbook in writing.**
* `kernel.payout.destination_ref` must exist before `payout.dual_control_min_minor` is ever set. It
  ships in 093 (`093:1686`), so **applying 093 discharges this constraint** — but until then, that key
  is settable on production and setting it would let every payout below the threshold advance with no
  destination record anywhere. The exposure is created by *configuring* the system, not by leaving it
  unconfigured.

---

## 7. SINGLE-FLIP HAZARDS

**[X] Every config verdict below was executed against the live setter as a real `platform_admin` on
aal2.** The full single-admin key set was enumerated from the catalogue against the prefix test at
`093:6705`: **18 of 49 keys** are single-admin. Three of them are on the activation path.

| Change | Crosses | Single-flip? | Intended? |
|---|---|---|---|
| `feature.native_issuance_enabled` → true/false | dark ↔ live, in one statement | **YES — [X] `ok`, version 2** | **YES.** A kill switch that needs a quorum is not a kill switch. It is also *last* in the ordering above, so at the moment it is flipped every other clause has already been satisfied. |
| `inventory.hold_ttl_interval` · `inventory.per_user_active_hold_max` | nothing holdable → holdable | **YES — [X] both `ok`** | **YES.** Both fail closed while unset, both are self-announcing, neither enables unbuilt logic, and it takes **two** changes. |
| `fee.buyer_service_bps` | the last clause of the SALEABLE chain | **NO — [X] `parked`** | **FIXED this train.** This was the matrix's "surviving instance of the banned pattern"; `fee.%` is now in the prefix set. |
| `ticket.expiry_grace` | inert sweep → every atom on every ended session terminal within one cron tick | **NO — [X] `parked`** | **FIXED this train**, twice over: the interval type guard (a bare `24` is refused outright as *twenty-four seconds*) composes with `ticket.%` dual control, and the key has no declared polarity so it parks in **both** directions. |
| `deletion.post_event_hold_hours` | BP-12 arm 2 stops blocking → paid buyers erasable | **NO — [X] `parked`**, and shortening parks while lengthening executes | **FIXED this train.** Residual risk is one of *ordering*, not of quorum: see §6. |
| every `payout.*` and `refund.*` key | maturity, dual-control threshold, refund tiers | **NO — [X] `parked`** | **YES.** |
| `UPDATE kernel.organization SET connect_transfers_active = true` (direct SQL, or `sync_org_connect_state` under a leaked `service_role` key) | `payout_not_ready` → passing, permanently, per org, unaudited | **YES — not a config key, so no quorum exists** | **NO — hazard, and unchanged.** H6 A4[4d] proved a leaked key can turn selling on for an organization Stripe has disabled. The RT-A-5 guard blocks only the *unbound* case. The no-direct-SQL policy is the only control, and that is a person remembering. |
| PostgREST exposed schemas `+= venue, catalog` | server-only → `venue.create_primary_checkout` (granted to `authenticated`) directly client-callable | **YES — a dashboard text field: not in git, not in a PR, not covered by any migration guard** | **NO — hazard, though a reasonable operational control.** It is the **outermost gate on the entire primary rail**. It must be a named, ordered, two-person runbook step, and it must come after 093 applies. |
| `insert into kernel.signing_key …` as `postgres` | SALEABLE gate 6 **and** ticket issuance, in one statement | **YES — superuser; H7 Gap 1/Gap 2, ADV-1/2/7/8 all PROVED it** | **ACCEPTED OPERATIONAL RISK**, per H7. Superuser access *is* the deploy path and there is one holder. The compensating control is the §9.3 five-column daily invariant query — and **arming that as a real scheduled job with an alert destination is a launch blocker even though the gap it covers is not.** |
| **Deploying `payout-execute`** | the whole PAYABLE gate, in one act | **YES — one deploy, no quorum** | **NO — hazard, and it is new this train.** H4 D-4 rated post-payout loss acceptable *because no executor existed*; that mitigation ends the moment this ships. G5 must be signed first, and H8 §9 lists the same two preconditions. |

**Is any destructive single-admin key left?** Of the 18 single-admin keys, three are on the activation
path and all three are argued above. Of the remaining fifteen: `door.implicit_freeze_offset_interval`,
`door.manifest_ttl_interval`, `door.manifest_early_open_window` and `door.max_override_interval` are
the only ones that touch custody semantics, and they have **no live consumer** —
`feature.native_scanning_enabled` is `false`, the 086 door rail is unbuilt and no manifest has ever
existed. `notify.*`, `resale.*`, `retention.*` and `crm_export.*` cross no money or identity boundary.
**Conclusion: after this train, no destructive single-admin config key remains on the activation path
except the two that are deliberately single-admin.** The surviving single-flip hazards are all
*non-config*: direct SQL on `connect_transfers_active`, the PostgREST exposure field, a superuser
signing-key insert, and the `payout-execute` deploy.

---

## 8. WHAT THIS PASS DID NOT DO

No migration, slice, edge, test or config was touched. `kernel.request_org_payout`'s missing
org-status gate (F-13 / H6 F-6), the `connect_transfers_active` gap at request time (H4 D-3, closed
only at execution), the `failed → submitted` re-arm (H3 §8.1), the receivable object (G5), the
`mode:'replace'` onboarding branch (H6 F-5) and E4 §6.1's failed-refund/`refund_void` interaction are
all recorded and none is fixed here.

One thing H8 §4 flagged as owed **has since been done and needs no further action**: the assembler
header now calls out `kernel.payout.destination_ref` as a deliberate exception to 093's original
*"0 DDL on any money-ledger table"* rule (`scripts/assemble_093.sh:141-142`), and the generated
artifact carries it at `093:41`. Verified this pass; recorded so the next reader does not re-open it.
