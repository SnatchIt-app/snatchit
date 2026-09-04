# G6 — The four activation gates (ruling A8), their exact predicates, and what actually enforces them

**Status:** research finding, read-only. No migration, edge, test or CI file was modified. No remote
was touched. No commit was made. The only files written are this one and
`docs/phase2/PRIMARY_TICKETING_ACTIVATION_MATRIX.md`.
**Branch:** `mobile/profile-rpc-compat` working tree of `/Users/josetascon/snatchit-consol`, head `ca0ac0a`.
**Governing ruling:** A8 (`docs/phase2/PRIMARY_TICKETING_OWNER_RATIFICATION.md:299-320`), which
defines DRAFT / PUBLISHABLE / SALEABLE / PAYABLE as *"four separate gates, not one boolean"*.

**Relationship to `docs/phase2/FINAL_ACTIVATION_BLOCKER_RULINGS.md`** (landed in the tree while this
analysis was running, status DRAFT / NOT SIGNED): that document rules on the three *owner values*
still outstanding — G1 ticket expiry, G2 maturity interval, G3 the signing ceremony — plus
`deletion.refund_possible_window_hours` as a fourth. Nothing here contradicts it and its four items
appear in this document's hazard list and critical path. **The scopes differ:** it answers *"which
numbers must the owner supply?"*; this answers *"what must be true before a sale is honourable?"* —
which additionally covers four undeployed edge functions, refund executability under A9, and an
absent payout executor. Setting the four values is necessary and **not** sufficient.

**Method.** Static reading of `supabase/migrations/000..093`, `supabase/functions/`, `src/`, and the
`docs/phase2` corpus, **plus** an executed replay against a local rehearsal database built by
`./scripts/rehearsal_reset.sh snatchit_rehears_gates` — **108/108 migrations applied,
`GATE-2 tables=27 functions=70 policies=37 triggers=24`, matching the CI baseline exactly.** Every
claim marked **[V]** below was executed against that database, not inferred from a document. Where an
executed result contradicts an input document, the executed result governs and the divergence is named.

---

## 0. HEADLINE — six findings

1. **Only ONE of A8's four gates is a real predicate in SQL.** SALEABLE is enforced, as a five-clause
   refusal chain inside `venue.reserve_primary_inventory` and `venue.create_primary_checkout`. DRAFT
   and PUBLISHABLE are enforced only as ordinary role/status checks — correctly, because A8 requires
   nothing of them. **PAYABLE is enforced in two disconnected halves** (an 8-conjunct maturity hold at
   close, and an authority/destination check at request) with **no executor at either end**, so it is
   a gate onto a road that does not exist.

2. **A8's SALEABLE clause has two halves and only one is enforced.** A8 defines SALEABLE as *"event
   may transition to `on_sale` **and** be purchased"*, and marks it "Requires Connect readiness:
   **Yes**". **[V] `catalog.publish_event(event,'on_sale')` succeeds with zero Stripe binding, zero
   config, and zero signing keys.** The transition half is unenforced — deliberately, per 093's OUT
   table (`093_FINAL_PROPOSED_SCOPE.md`, "Gating `publish_event` on Connect readiness"). The purchase
   half is enforced. An event can therefore sit in `on_sale` — the state the whole product treats as
   "tickets are live" — while every purchase attempt refuses. That is fail-closed on money and
   fail-open on the storefront.

3. **The SALEABLE predicate does not require an active signing key, and that is a money defect, not a
   modelling nicety.** **[V] A `venue."order"` row was created with `select count(*) from
   kernel.signing_key = 0`.** The signing key is checked only at `venue.finalize_primary_order` —
   i.e. inside the webhook, **after** the PaymentIntent has been confirmed. With the checkout edge
   deployed, this is: buyer charged, `no_active_signing_key`, no ticket. See §5.1.

4. **Refund executability is a hard precondition of SALEABLE, it is ruled so, and it is not
   satisfied.** Ruling A9 (`PRIMARY_TICKETING_FINAL_OWNER_RULINGS.md:644-684`) is unambiguous:
   *"Venue-direct selling may not be activated until a refund recorded by the database results in
   money actually returning to the buyer."* The built executor does **not** satisfy it — it is not
   deployed, its self-heal `sweep` action is dead (`kernel.list_pending_refunds` **[V] does not
   exist**), and PFA-23's direct arm is **[V] unreachable in both directions**. See §4.

5. **Five owner config values plus one flag flip move the system from "nothing works" to "a primary
   sale order is created".** **[V] Executed as a single continuous replay.** None of the five is
   dual-controlled. Three of them are hidden feature flags for logic whose *other* halves are not
   built. See §6.

6. **The `ticket.expiry_grace` hazard the corpus already named is live and one statement wide.**
   **[V] One `platform_admin`, in one call, set the key to the JSON number `24` and it was accepted.
   `('24'::jsonb #>> '{}')::interval` = `00:00:24` — twenty-four seconds.** `ticket.%` matches no
   dual-control prefix. See §6, H-3.

---

## PART 1 — THE FOUR GATE PREDICATES

The fourteen prerequisites the owner asked about are evaluated for each gate. `REQ` = the gate cannot
be crossed without it. `no` = not required by the predicate as it actually exists. `SHOULD` = not
required by any shipped predicate but argued in §5 to belong in the gate.

| Prerequisite | DRAFT | PUBLISHABLE | SALEABLE | PAYABLE |
|---|---|---|---|---|
| Valid event | **REQ** | **REQ** | **REQ** (`on_sale`/`live`) | **REQ** (via lines) |
| Inventory configured | **REQ** | no | **REQ** (batch + live hold) | no |
| Stripe org linked (`stripe_connect_account_ref`) | no | no | **REQ** | **REQ** |
| `transfers` capability active (`connect_transfers_active`) | no | no | **REQ** | no |
| Buyer service fee configured (`fee.buyer_service_bps`) | no | no | **REQ** | no |
| Tax policy available | no | no | **no — and none exists anywhere** | no |
| Active signing key | no | no | **no — SHOULD (§5.1)** | no |
| Checkout edge deployed | no | no | **no in SQL — SHOULD (§5.2)** | no |
| Webhook deployed | no | no | **no in SQL — SHOULD (§5.2)** | no |
| Refund executor available | no | no | **no in SQL — REQUIRED BY A9 (§4)** | no |
| Payout destination bound | no | no | no | **REQ** (same column) |
| Payout executor existing | no | no | no | **no — and none exists (§5.3)** |
| Settlement maturity policy set | no | no | no | **REQ** |
| PostgREST schema exposure | no (server-side) | no | **REQ for a client** (`catalog`, `venue`) | **REQ for a client** (`kernel`) |

### 1.1 DRAFT — the exact predicate

> An organization with `status in ('approved','active')`, an approved venue whose `org_id` is that
> organization, an event on that venue, at least one `event_session`, at least one
> `venue.ticket_type`, and at least one `venue.inventory_batch`.

No money prerequisite of any kind. **[V] Built end to end on the rehearsal database with 0 signing
keys, `stripe_connect_account_ref IS NULL`, and every owner config key at `'null'::jsonb`.**

**Enforcement: ENFORCED IN SQL**, as ordinary authority and status checks —
`kernel.create_organization`, `catalog.create_venue`, `catalog.approve_venue`, `catalog.create_event`,
`venue.create_ticket_type`, `venue.create_inventory_batch`. This is exactly what A8 ratifies: *"A
venue organization may exist, configure itself, create draft events, create ticket types, and
configure inventory before Stripe onboarding completes."* **The gate is correct and complete.**

### 1.2 PUBLISHABLE — the exact predicate

> `catalog.publish_event(event_id, 'announced', key)` by a caller holding the venue/org authority the
> function requires, on an event that is not terminal.

**[V] Succeeded with no Connect binding, no config, no signing key.** Correct per A8: *"An event may
safely be publicly visible before it becomes saleable, and that possibility is preserved."*

**Enforcement: ENFORCED IN SQL**, and correctly so — there is nothing to gate. `announced` is
marketing state with nothing purchasable behind it.

**But the gate as A8 words it is wider than `announced`.** See §5.4.

### 1.3 SALEABLE — the exact predicate, as five clauses in refusal order

Reconstructed from the executed refusal chain, not from a document. Each line is the *first* refusal
observed once the line above it was satisfied.

| # | Clause | Refusal observed **[V]** | Enforced at |
|---|---|---|---|
| 1 | `feature.native_issuance_enabled` is true | `precondition_failed: feature_disabled` | `081:583` (`venue.reserve_primary_inventory`), `081:703` (`venue.create_inventory_hold`), `083:497` (the mint) |
| 2 | `inventory.per_user_active_hold_max` set | `precondition_failed: hold_cap_exceeded` | `081:615-626` — an absent value collapses the cap to **0**, so `0 + 1 > 0` refuses the first hold of every user |
| 2b | `inventory.hold_ttl_interval` set | `precondition_failed: hold_ttl_unset` | `081:630-639`, `081:727-734` |
| 3 | event `status in ('on_sale','live')`, session not terminal | `precondition_failed: not_on_sale` / `session_terminal` | `093:2420`, `093:2426` |
| 4 | `stripe_connect_account_ref IS NOT NULL` **AND** `connect_transfers_active` | `precondition_failed: payout_not_ready` | `093:2458` (inside `venue.create_primary_checkout`, `093:2325`) |
| 5 | `fee.buyer_service_bps` set, integer `0..10000` | `precondition_failed: service_fee_unset` / `service_fee_out_of_range` | `093:2482`, `093:2488` |

With all five satisfied, **[V] the RPC returned `{"status":"ok","order_id":…}` and a
`venue."order"` row exists with `status='pending'`, `total_minor=5000`.**

**Enforcement: ENFORCED IN SQL.** Clauses 4 and 5 are also re-asserted in
`supabase/functions/primary-checkout/index.ts` as defence in depth — but that function is
**NOT DEPLOYED**, and 093 is explicit about why the SQL location is the load-bearing one: the RPC is
granted to `authenticated` (**[V]** `has_function_privilege('authenticated', 'venue.create_primary_checkout', 'EXECUTE')`
= true), so an edge check alone would be bypassed by one direct PostgREST call.

**What clause 4 does NOT prove.** `connect_transfers_active` is written only by
`kernel.sync_org_connect_state` (`093:1966`, service_role only), whose only caller is the
`account.updated` organization arm of `stripe-webhook` — **also not deployed**. So the flag is false
forever until that webhook ships, *or* until someone writes the column by hand. It is a
self-healing gate with no writer.

### 1.4 PAYABLE — the exact predicate, in two disconnected halves

**Half A — the maturity hold, at `kernel.close_settlement` (`093:618`).** An 8-conjunct
conjunction (`093:853-867`); the first failing conjunct names itself:

| # | Conjunct | Hold reason code |
|---|---|---|
| 1 | `payout.settlement_maturity_interval` is set | `unbounded_refund_exposure` |
| 2 | the interval is `>= 0` | `maturity_policy_invalid` |
| 3 | every settlement line resolves to a payment **and** a session | `covered_set_unresolvable` |
| 4 | no covered session/event is cancelled | `event_cancelled` |
| 5 | at least one covered session, none with `ends_at IS NULL`, anchor computable | `maturity_instant_unknown` |
| 6 | `now() >= max(ends_at) + interval` | `maturity_not_elapsed` |
| 7 | no `kernel.refund` in flight on a covered payment | `refund_in_flight` |
| 8 | no open `kernel.dispute_native` on a covered payment | `dispute_open` |

Every operand is pre-set to its holding value and every branch is `coalesce(…, <holding value>)`, so
a path that fails to compute an operand can only fail toward the hold.

**[V] Executed.** With the maturity key set to `"7 days"` and the event 20 days in the future, a
close minted `kernel.payout` `cause=settlement status=pending hold_state=held
hold_reason_code=maturity_not_elapsed`, and the settlement header carried
`status=closed gross=5000 net=5000`. **The ledger records the full obligation while the money is
held — A3 is satisfied.**

**Half B — the request, at `kernel.request_org_payout`.** Requires: the settlement `closed`;
`stripe_connect_account_ref IS NOT NULL` (else `no_payout_destination`); an aal2 step-up
(**[V]** `step_up_unavailable: the session carries no aal claim`); a matured money role
(`authn.money_role_maturity_hours` = 72, seeded); and the payout not held —
`kernel.release_payout` (platform_risk / platform_admin) is the sole exit.

**Enforcement: ENFORCED IN SQL, both halves.** This is the best-enforced gate in the train.

**And it leads nowhere.** See §5.3.

---

## PART 2 — ENFORCEMENT CENSUS

| Gate | Enforced in SQL | Enforced in an edge | Merely documented |
|---|---|---|---|
| DRAFT | **Yes** — role/status checks across `kernel`/`catalog`/`venue` creators | — | — |
| PUBLISHABLE (`announced`) | **Yes** — `catalog.publish_event` authority | — | — |
| SALEABLE (purchase) | **Yes** — 5 clauses, §1.3 | defence-in-depth only, in `primary-checkout` — **NOT DEPLOYED** | — |
| SALEABLE (`on_sale` transition) | **No** | **No** | **A8's table only.** **[V] The transition succeeds with nothing configured.** → **FINDING F-1** |
| SALEABLE ∧ signing key | **No** | **No** | `093_FINAL_PROPOSED_SCOPE.md` item 2 ("no ticket of any kind can exist without this row") → **FINDING F-2** |
| SALEABLE ∧ refund executable | **No** | **No** | **Ruling A9 approval text** → **FINDING F-3** |
| SALEABLE ∧ tax modelled | **No** | **No** | `G5 §6` ("tax remains unmodelled on both rails") → **FINDING F-4** |
| PAYABLE (maturity) | **Yes** — `093:853-867` | — | — |
| PAYABLE (authority/destination) | **Yes** — `kernel.request_org_payout`, `kernel.release_payout` | — | — |
| PAYABLE → money actually moves | **n/a** | **No — no payout edge function exists** | `093_FINAL_PROPOSED_SCOPE.md` ("no payout executor exists") → **FINDING F-5** |

**An unenforced gate is a finding, not a gate.** F-1 through F-5 are carried to the matrix as
blockers with citations.

---

## PART 3 — THE EXECUTED REPLAY

Database `snatchit_rehears_gates`, 108/108 migrations, GATE-2 matched. Fixture:
`tap.seed_core()` + `org → venue(approved) → event → session → ticket_type → inventory_batch`.

### 3.1 The six checks the task named — all confirmed

| Check | Result **[V]** |
|---|---|
| The three feature flags are false | `feature.native_issuance_enabled=false`, `feature.native_resale_enabled=false`, `feature.native_scanning_enabled=false`. Exactly three keys exist in the `feature.` namespace. |
| The owner-set config keys are null | **All six** are `'null'::jsonb`: the five 093 keys — `inventory.per_user_active_hold_max` (`093:3356`), `inventory.hold_ttl_interval` (`093:3373`), `ticket.expiry_grace` (`093:3470`), `fee.buyer_service_bps` (`093:3530`), `payout.settlement_maturity_interval` (`093:3597`) — plus the pre-existing `deletion.refund_possible_window_hours` (`085:2189`). |
| The maturity key was renamed | `payout.settlement_maturity_interval` **exists**; `settlement.refund_window_interval` **does not exist as a row** — it survives only as an explanatory comment at `093:105`. |
| Zero signing keys exist | `select count(*) from kernel.signing_key` = **0**. The 093 bootstrap row is deliberately **commented out** (`093:3656-3663`) pending the KMS ceremony. |
| `kernel.tickets.signing_key_id` is NOT NULL | `is_nullable = NO`. |
| No payout edge function exists | `ls supabase/functions/` has no payout function. Nothing in `supabase/functions/` or `src/` references `stripe_transfer_ref` or `kernel.release_payout` — **zero hits**. |
| `set_org_payout_destination` has no non-comment caller | Every hit repo-wide is a definition (`085:1601`, `093:2862`), a grant array (`085:2115`, `085:2137`), a comment (`077:991`, `093:2746`, `connect-onboarding/index.ts:33`), a rollback, or a pgTAP assertion. **No application code calls it.** The re-point verb is unreachable by any shipped path. |

### 3.2 The gate walk — one blocker removed at a time

| Step | State of the world | Result **[V]** |
|---|---|---|
| D | 0 signing keys, no Stripe, all config null | DRAFT chain built: 1 ticket type, 1 batch |
| P1 | same | `publish_event → announced` = **OK** |
| P2 | same | `publish_event → on_sale` = **OK** ← **F-1** |
| S1 | same | `reserve_primary_inventory` → `ERR feature_disabled` |
| S2 | `+ feature.native_issuance_enabled = true` | → `ERR hold_cap_exceeded` |
| S3 | `+ inventory.hold_ttl_interval`, `+ inventory.per_user_active_hold_max` | → **OK**, hold created |
| S4 | same | `create_primary_checkout` → `ERR payout_not_ready` |
| S5 | `+ stripe_connect_account_ref`, `+ connect_transfers_active` | → `ERR service_fee_unset` |
| S6 | `+ fee.buyer_service_bps = 1000` | → **OK, `venue."order"` created, `pending`, `total_minor=5000`, with 0 signing keys** ← **F-2** |
| I1 | order exists, payments row exists, 0 signing keys | `finalize_primary_order` → `ERR no_active_signing_key` |
| I3 | `+ one active global signing key row` | → **OK, atom minted, order `paid`** |
| Y1 | `+ payout.settlement_maturity_interval = "7 days"`, matured `org_finance` | `close_settlement` → **OK**, payout `pending/held/maturity_not_elapsed` |
| Y4 | same | `request_org_payout` → `ERR step_up_unavailable` |
| Y8 | end state | payout `stripe_transfer_ref = NONE`, and nothing in the repo can ever write it ← **F-5** |

**Read the S-column as one sentence: six owner-controlled writes — one flag, four config values and
one column pair — take the system from total refusal to a created primary-sale order.**

### 3.3 Refund executability, executed

| Probe | Result **[V]** |
|---|---|
| `kernel.refund_primary_order` as `service_role` | `ERR 42501 insufficient_privilege: refund_primary_order is platform (direct) or dual-control-delegated only` — `auth.uid()` is NULL under service_role, so `is_platform` fails |
| `kernel.refund_primary_order` as `authenticated` (platform admin) | `ERR 42501 permission denied for function refund_primary_order` — EXECUTE is `service_role` only (`085:2152`; `085:2129-2130` records the deliberate exclusion) |
| `kernel.list_pending_refunds` exists? | **0 rows in `pg_proc`** |
| `kernel.get_refund_execution_context` exists? | **exists, service_role only** — 093 authored it (`093:1087`), closing E4 §3's first gap |
| `kernel.resolve_dispute_native` | always raises `precondition_failed: dual_control_unavailable` with zero mutation (`088:913-931`) |

---

## PART 4 — THE CENTRAL QUESTION: WHAT MAKES A SALE HONOURABLE?

The owner gave two rules that pull in opposite directions. They are resolved, not split.

### 4.1 Rule one: PAYABLE is NOT a precondition of SALEABLE. **Upheld.**

The owner is explicit and the architecture agrees three separate ways:

* **A2 ratifies the separation by name:** *"Payment collection, internal obligation accounting, and
  payout execution remain separate concepts. **No venue payout is implied by successful
  collection.**"*
* **A8's own table** marks PAYABLE as requiring *"Connect readiness, **plus settlement
  prerequisites**"* — a strictly larger set than SALEABLE's. A gate defined as a superset of another
  cannot be that other's precondition.
* **The money is safe where it is.** A2's separate-charges architecture collects onto the **platform**
  Stripe account. A sale with no payout rail leaves the buyer's money on Snatch It's balance and the
  venue's entitlement recorded as a ledger fact — **[V]** `settlement closed gross=5000 net=5000`,
  payout `held`. A3 is satisfied without a payout rail. Stripe's own guidance endorses this shape:
  *"hold funds only when there's a clear purpose and a commitment to transfer them"*
  (https://docs.stripe.com/connect/account-balances), which is precisely a named
  `hold_reason_code` plus a contracted `kernel.release_payout`.

**Two bounds on that answer, which are real and must be written into the launch plan:**

1. **Stripe's manual-payout holding limits are hard.** Funds must be paid out within **2 years (US)**
   or **90 days (most other countries)** (https://docs.stripe.com/connect/manual-payouts, cited in
   G2 Part 5). Selling before the payout rail exists is honourable only inside that window, and the
   US launch posture (A7) puts it at two years. This is comfortable, not infinite.
2. **The venue must be told, in the contract, that money is held and on what precondition.** Stripe's
   ToS requires a reserve policy be disclosed; the same honesty applies to a platform-side hold.
   This is a contract item, not a code item, and it is not written anywhere in the corpus.

### 4.2 Rule two: a sale must not outrun the economic obligation and refund lifecycle. **Upheld, and it bites.**

Ruling A9's approval text is the operative sentence, and it is narrower than "build the executor":

> *"Venue-direct selling may not be activated until a refund recorded by the database results in
> money actually returning to the buyer, **by an automated executor or by a named written process
> with a named accountable human and a defined write-back step**. A refund path that voids a buyer's
> ticket without returning their money is not acceptable at any volume, including a single sale."*

Two disjuncts. Neither is satisfied today.

**Does the built-but-undeployed executor satisfy it? No — on three independent grounds.**

1. **It is not deployed.** `supabase/functions/refund-execute/` exists in the tree; the production
   deployment record (`docs/release/PHASE2_DEPLOYMENT_RECORD_20260902.md:26-29`) lists the only edges
   touched as `delete-account v18`, `create-payment-intent v45`, `confirm-and-release v34`, and
   states *"No other function touched."* An undeployed executor returns no money. A9's test is
   outcome-shaped — *"results in money actually returning"* — not artefact-shaped.
2. **Its self-heal path is dead.** `action: sweep` is the recovery for the two failure modes that
   actually lose money — a crash between `POST /v1/refunds` and the `mark_refund_state` callback
   (E4 §5 cases 2, 3 and 13). It calls `kernel.list_pending_refunds`, which **[V] does not exist**;
   `refund-execute/index.ts:496-504` correctly answers **501** and names the gap. So the deployed-day
   behaviour would be: single refunds work, and any refund interrupted mid-flight is stranded
   `pending` with no automated way to find it. `pending` is exactly the state that blocks the buyer's
   account deletion forever (BP-12 arm 1, `085:249-262`).
3. **PFA-23's direct arm has no implementation, and the reason is structural.** `085:2144-2146`
   specifies the caller as *"the refund-execute edge (as service_role, forwarding the platform JWT
   for the direct arm)"*. **PostgREST derives the database role from the JWT it verifies, one role
   per request.** So a request is either `service_role` — and `auth.uid()` is NULL, so
   `kernel.is_platform` fails — or `authenticated`, and EXECUTE is denied. **[V] Both refusals were
   executed and both fired.** There is no third option with this grant set.

**What survives.** The **DELEGATED** arm (`req:<uuid>` command key bound to an approved
`kernel.approval_request`) reads no `auth.uid()` and works under `service_role`; and
`kernel.admin_refund` **[V] is granted to `authenticated`**, giving platform break-glass a working
sibling. So a refund *can* be recorded today through dual control. But recording is not returning:
nothing calls `kernel.mark_refund_state` (**[V]** `service_role`-only, and the only would-be caller
is the undeployed edge), so **every `kernel.refund` row created today is born `pending` and stays
`pending` forever.** The buyer loses the ticket, gets no money, and becomes permanently undeletable.
That is the exact failure A9 names.

### 4.3 THE ANSWER — the minimum set that makes a sale honourable

**IN the minimum set (all of SALEABLE's five SQL clauses, plus five more):**

| # | Requirement | Why it is minimum |
|---|---|---|
| 1-5 | The five enforced clauses of §1.3 | already enforced |
| 6 | **An active signing key** | The charge precedes the mint. Without a key the buyer pays and the mint raises. Not honourable at n=1. **Currently unenforced — F-2.** |
| 7 | **`primary-checkout` deployed** | It is the only thing that mints a PaymentIntent. Without it no money moves — so its absence is *safe*, but its presence is required for the rail to function at all, and it must be deployed **after** 093 applies and **before** `venue` is exposed (E2 AB-8). |
| 8 | **`stripe-webhook` native branch deployed** | It is the only caller of `venue.finalize_primary_order` and the only writer of `connect_transfers_active`. Without it, money is taken and no ticket is ever issued — the worst state in the matrix. |
| 9 | **A refund path that returns money**: `refund-execute` deployed **AND** `kernel.list_pending_refunds` authored, **or** a named written process with a named human and a defined write-back step | Ruling A9, literally. |
| 10 | **A written resolution of the PFA-23 direct-arm authority question** | E4 §7 offers three options; option (iii) — retire the direct arm, route all platform refunds through delegated dual control — costs least and increases control. Until one is chosen, the "break-glass" path is `admin_refund` by accident rather than by decision. |

**OUT of the minimum set, deliberately:** payout destination re-point, payout executor, settlement
maturity policy, promoter payout. All are venue-side and platform-side concerns; none of them is
something the *buyer* is owed.

**A borderline case, named rather than hidden:** `kernel.resolve_dispute_native` **[V] always raises**
(`088:913-931`, PFA-31). A lost dispute freezes the org's payout and the buyer's atoms permanently,
with no exit. A9's approval text calls this *"a known defect with no exit path"* that *"must be
closed before the direct rail carries material volume"* — i.e. the owner has already ruled it out of
the launch minimum and into the volume threshold. It is recorded here as PAYABLE's standing residual,
not as a SALEABLE blocker.

---

## PART 5 — THE FIVE FINDINGS, STATED AS FINDINGS

### 5.1 F-2 — the checkout gate does not require a signing key

**[V] An order was created with zero signing keys in the database.** The chain is:
`create_primary_checkout` (order + PI) → buyer confirms → `payment_intent.succeeded` →
`finalize_primary_order` → mint → `no_active_signing_key`. The refusal lands **after** the charge.

`kernel.tickets.signing_key_id` is NOT NULL (`079:34`) and the mint requires an active in-window key
resolvable for the event scope (`083:514-530`), so this is not avoidable by a display-only launch —
093's scope document says so in item 2. The gap is that the *sale* door does not read the same fact
the *mint* door does.

**Cheapest correct fix, if the owner wants the gate closed in code:** one additional `EXISTS` clause
in `venue.create_primary_checkout` mirroring the `085:1948-1960` scope resolver. That is a body-only
replacement, the same shape as every other 093 gate. **Not authored here** — this document writes no
SQL.

**Cheapest correct fix operationally:** make the signing-key ceremony strictly precede the
`fee.buyer_service_bps` set in the activation runbook. The key row is `093`'s stated critical path
precisely because it waits on a human ceremony.

### 5.2 F-1 / the edge-deployment ordering hazard

**[V] `on_sale` is reachable with nothing configured.** Combined with the fact that
`venue.create_primary_checkout` is granted to `authenticated`, the only thing standing between a
direct PostgREST call and the checkout RPC is **schema exposure** — an operational dashboard setting,
not a migration and not code.

Production exposure today is `public, graphql_public, kernel`
(`docs/release/PHASE2_DEPLOYMENT_RECORD_20260902.md:25`), with `venue` confirmed rejected
(`PGRST106`). **That is currently the outermost gate on the entire primary rail, and it is a text
field in a dashboard.** E2 AB-8 states the ordering constraint correctly: **apply 093 before exposing
`venue`.** With 093 applied first, the SQL gate stands whether or not the edge is deployed. With
`venue` exposed first, the (undeployed) edge defends nothing.

### 5.3 F-5 — PAYABLE opens onto no road

`kernel.close_settlement` mints the payout. `kernel.release_payout` clears the hold.
`kernel.request_org_payout` moves it to `submitted`. And then **nothing**: **[V] no
`supabase/functions/*payout*` exists, and no TypeScript anywhere writes `stripe_transfer_ref` or
calls `release_payout`.** The payout row's terminal state, reachable today, is `submitted` with
`stripe_transfer_ref = NULL`.

A9 additionally requires a written answer *before* that executor is authored: *"the mapping between
one settlement payout and its many funding charges must be settled in writing, because Stripe binds
one source transaction per transfer and it cannot be amended afterwards."* **[V] `kernel.payout` has
exactly one `source_transaction_ref` column.** That mapping is not settled anywhere in the corpus.
**It is the true head of the PAYABLE critical path, and it is a paper item, not an engineering one.**

### 5.4 F-1 restated as a product statement

A8's SALEABLE row says the event *"may transition to `on_sale` and be purchased"*. Today those two
clauses have different truth values. The owner should choose one of:

* **(a) Accept it** — `on_sale` is advisory, purchase is the real gate, and the storefront must
  handle `payout_not_ready` / `service_fee_unset` as a first-class "not on sale yet" state
  (G5 §5.4 already specifies exactly that copy for the client). **Zero code.**
* **(b) Gate the transition** — a readiness precondition in `catalog.publish_event` for the
  `on_sale` target only. 093 explicitly declined this on the ground that `announced` is harmless;
  that reasoning does not extend to `on_sale`. **A body-only replacement.**

Option (a) is coherent and cheap **provided** the client refuses to show a buy button; option (b) is
the one that makes the ratified sentence true. **Owner item.**

### 5.5 F-4 — there is no tax model at all

**[V] Zero `catalog.platform_config` keys match `%tax%`. Zero functions match `%tax%`.** No column on
`venue."order"` or `public.payments` carries tax. `src/lib/pricing/allIn.ts` has a
`{status:'applies-unknown'}` branch that refuses to quote — the *only* representation of tax anywhere
in the system, and it is client-side and advisory.

A5 fixes the venue's entitlement at face value *"subject only to explicitly modeled adjustments such
as … taxes where economically applicable"*. Nothing models them. For a US event-ticketing launch this
is an owner/counsel item that no gate will surface, because no gate exists to surface it. **Recorded,
not solved.**

---

## PART 6 — THE HAZARD LIST: EVERY SINGLE-CHANGE GATE CROSSING

The owner's standing requirement: **no config value may act as a hidden feature flag for incomplete
logic.** `settlement.refund_window_interval` was exactly that until G2 renamed it. The question is
what else has the same shape.

**The shape, stated precisely.** A hazard is a key where **(i)** one write by one person changes
system behaviour across a gate, **(ii)** the logic the key enables is incomplete or the key's name
does not describe what it controls, and **(iii)** the write is not dual-controlled.

**The dual-control test** (`078:1145-1147`, **[V] executed**): a key parks for a second
`platform_admin` iff it matches `refund.%`, `payout.%`, `authn.%`, `comp.%`, `wallet.%`,
`credential.%`, or `door.session\_%`. **[V] Executed against the live setter as a real
`platform_admin`:**

| Key set by ONE `platform_admin` | Result **[V]** |
|---|---|
| `feature.native_resale_enabled` → `true` | `{"status":"ok","version":2}` — **executed immediately** |
| `fee.buyer_service_bps` → `2500` | `{"status":"ok","version":3}` — **executed immediately** |
| `ticket.expiry_grace` → `24` (a JSON **number**) | `{"status":"ok","version":2}` — **executed immediately** |
| `inventory.per_user_active_hold_max` → `999` | `{"status":"ok","version":3}` — **executed immediately** |
| `payout.settlement_maturity_interval` → `"1 second"` | `{"status":"parked","request_id":"8a0a…"}` — **PARKED. Effective value stayed `"7 days"`.** |

**The rename worked.** It is the only key on the entire activation path that a single administrator
cannot move. Every other one is a single statement.

### The hazards

| # | Single change | Gate it crosses | Dual-controlled? | Intended? |
|---|---|---|---|---|
| **H-1** | `feature.native_issuance_enabled` → `true` | Nothing → holds creatable; the mint arms | **NO** | **YES, and correctly so.** A kill switch that needs a quorum is not a kill switch (078's own `false_is_restrictive` reasoning). But see H-1b. |
| **H-1b** | the same flag, in the **restrictive** direction | live → dark | **NO** | **YES.** Turning it off must never need two people. |
| **H-2** | `fee.buyer_service_bps` → any integer | **`payout_not_ready`-passing org → a sale completes.** This is the **last** gate on the SALEABLE chain. **[V] S5→S6.** | **NO** | **NO — this is the surviving instance of the pattern.** See below. |
| **H-3** | `ticket.expiry_grace` → a JSON **number** | inert sweep → **every active atom on every ended session terminal within two minutes** (cron `*/2`, `079:799-803`) | **NO** | **NO — hazard, already named by G1 and still live.** **[V]** `('24'::jsonb #>> '{}')::interval = 00:00:24`. The row is seeded JSON `null`, so 078's type witness is disarmed for the first write and cannot catch it. |
| **H-4** | `inventory.per_user_active_hold_max` → any integer, **and** `inventory.hold_ttl_interval` → any interval | nothing holdable → holdable | **NO** | **YES** — both fail closed while unset, both are self-announcing, and neither enables logic that is not built. Two changes, not one. |
| **H-5** | `payout.settlement_maturity_interval` → any interval | one conjunct of eight | **YES — parks** | **YES.** The G2 fix. **This is the reference shape.** |
| **H-6** | `deletion.refund_possible_window_hours` → any number | BP-12 arm 2 stops blocking → paid buyers become erasable **while their refunds are still `pending` forever** (§4.2) | **NO** | **NO — hazard.** See below. |
| **H-7** | `UPDATE kernel.organization SET connect_transfers_active = true` (direct SQL) | `payout_not_ready` → passing | n/a — no config key | **NO — hazard.** See below. |
| **H-8** | PostgREST exposed-schema list `+= venue, catalog` (one dashboard field) | server-only → **`venue.create_primary_checkout` directly client-callable** | n/a — not a config key, not in git, not reviewable | **NO — hazard.** See below. |
| **H-9** | `feature.native_resale_enabled` / `feature.native_scanning_enabled` → `true` | arms rails whose own gaps are unclosed (`resolve_dispute_native` parked; door manifests never opened) | **NO** | out of this train's scope; recorded so the census is complete |

### H-2 — the surviving instance of the pattern the owner banned

`fee.buyer_service_bps` is a **restricted-visibility, non-dual-controlled, owner-set number whose
only behavioural effect is to switch a money gate from refusing to permitting.** It is the last
clause in the SALEABLE chain: **[V] with everything else in place, setting it took the system from
`service_fee_unset` to a created order in one statement.**

**It is not the same defect as the old maturity key, and the difference is worth stating fairly.**
The old key gated logic that *had never been written*. This key gates logic that **is** written — the
rounding, the `charge_total_minor`, the client contract, all shipped and tested (G5 §4, 310 tests
green). Its name is honest. Its fail-closed direction is correct. Its refusal is self-announcing.

**But condition (ii) still bites, on the things that are downstream of it and not built:** at the
moment `fee.buyer_service_bps` becomes set, the checkout gate stops refusing, and **nothing else on
the SALEABLE chain is checked** — not the signing key (F-2), not refund executability (F-3), not tax
(F-4). The key is a single-writer switch that moves the system across A8's SALEABLE boundary while
three of A9's preconditions are unmet.

**Three ways to close it, in increasing cost:**

1. **Rename into the dual-control namespace.** `fee.%` matches no prefix. `payout.%` does. But `fee.`
   is semantically right and `payout.` would be a second lie of exactly the kind G2 just removed —
   **rejected on the same grounds G2 used.**
2. **Widen the dual-control prefix test to include `fee.%`.** One line at `078:1145-1147` — but 078
   is frozen, so it is a body-only replacement in a later migration, and every `fee.%` key inherits
   the two-person requirement. **Cheapest honest fix. Recommended.**
3. **Close F-2 and F-3 in code**, so that setting the fee is no longer sufficient. Strictly better,
   strictly more expensive, and F-3's half is a deployment, not a migration.

**Recommendation: (2) now, (3) as the activation sequence.** They are complementary: (2) makes the
crossing require two humans; (3) makes the crossing require the system to be finished.

### H-6 — the second surviving instance, and it is quieter

`deletion.refund_possible_window_hours` (`085:2189`, consumer `085:268-283`) is fail-**closed** and
therefore looks safe. It is not, for a reason G1 §3.1 establishes and this analysis extends:

* Today it is the **only** thing keeping a paid buyer un-erased while their refund is stranded.
* **[V]** No refund can leave `pending` (nothing calls `mark_refund_state`).
* So setting this key — one `platform_admin`, one statement, `deletion.%` matches no dual-control
  prefix — makes buyers erasable **whose money has provably not been returned**.

The key's *name* is honest and its *consumer* is correct. The hazard is that its safety depends
entirely on a fact outside itself: that refunds actually execute. **It is a hidden flag not for
incomplete logic in its own consumer, but for incomplete logic two systems away.**

**Fix:** set it only *after* the refund executor is deployed and `list_pending_refunds` exists. That
is an ordering constraint for the activation runbook, not a code change. **It belongs in the runbook
in writing, because nothing enforces it.**

### H-7 — the config-shaped hazard that is not a config key

`connect_transfers_active` is a boolean column with exactly one writer
(`kernel.sync_org_connect_state`, `093:1966`, service_role only) whose only caller is an **undeployed**
webhook branch. Until that branch ships, the only way the column becomes true is a direct `UPDATE` —
which is what **[V] this replay did**, and which is precisely how the SALEABLE gate got crossed here.

The 093 scope document requires the flag be **non-monotonic** *"or an account Stripe later disables
stays sellable forever."* That property is only real if a writer runs. **An unattended
`connect_transfers_active = true` is a permanent, per-organization, un-audited SALEABLE grant.**
The no-direct-SQL operational policy is the only control on it, and that policy is a person
remembering.

### H-8 — the outermost gate is a dashboard text field

Adding `venue` and `catalog` to PostgREST's exposed-schema list is one field, not in git, not
reviewable in a PR, not covered by a migration guard, and it is what makes
`venue.create_primary_checkout` (granted to `authenticated`) reachable by any signed-in user's
browser. **[V]** Production is currently `public, graphql_public, kernel` and `venue` returns
`PGRST106`.

**This is intended as an operational control and it is a reasonable one — but it is not a gate in
A8's sense, because nothing in the system can observe it.** It should be named in the activation
runbook as an explicit, ordered, two-person step, and E2 AB-8's ordering constraint (093 applies
first) should be restated beside it.

---

## PART 7 — WHAT WOULD MAKE EACH GATE TRUE

Ordered as a critical path. This is analysis, not authorization; nothing here is scheduled.

1. **Paper first** — the `source_transaction` mapping (A9), the PFA-23 direct-arm decision (E4 §7),
   the processing-cost allocation (A5's open item, E2 AB-10), the tax question (F-4), and the
   `on_sale` gating choice (F-1). None of these needs an engineer and all of them block later steps.
2. **Apply 093.** The SALEABLE gate does not exist until it does.
3. **The KMS ceremony** (`PRODUCTION_SIGNING_KMS_CEREMONY.md`) and the bootstrap row. Owner-paced;
   it is 093's stated critical path and F-2 makes it a SALEABLE precondition in practice.
4. **Author `kernel.list_pending_refunds`** (E4 §3 gives the shape;
   `kernel.get_refund_execution_context` **[V] already exists**). One small migration.
5. **Deploy the edges in order:** `connect-onboarding` → `stripe-webhook` (native branch, which is
   also the only writer of `connect_transfers_active`) → `refund-execute` → `primary-checkout`.
   The checkout edge is last because it is the only one that can take money.
6. **Expose `catalog` then `venue`** over PostgREST — after step 2, never before.
7. **Set the config, in this order:** the two inventory keys → `fee.buyer_service_bps` →
   `feature.native_issuance_enabled` last. `ticket.expiry_grace` must be set as a **jsonb string in
   hours** (G1 §7 recommends `'"72 hours"'`), and `deletion.refund_possible_window_hours` only after
   step 5 (H-6).
8. **PAYABLE stays dark** until the `source_transaction` mapping is written and a payout executor
   exists. `payout.settlement_maturity_interval` parks for two admins, which is correct and should
   not be changed.

---

**Nothing in this document has been authorised, authored, applied, deployed or committed. Two files
were written: this one and the matrix. The rehearsal database is local and disposable.**
