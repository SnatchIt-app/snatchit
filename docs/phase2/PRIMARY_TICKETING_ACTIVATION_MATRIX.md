# Primary ticketing — activation matrix

**What this is.** For each step of the venue-direct primary rail: what must exist in the database,
what must be configured, which edge function must be deployed, what Stripe state is required, what
signing state is required, which owner ruling governs it, and whether it is ready **today**.

**Status of the system this describes.** Migration 093 is **authored and NOT applied to production**
(production ledger is 107 = migrations 000–092; the repo holds 108 files). No rail is activated. No
edge for this feature is deployed. This matrix describes the repo tip as replayed locally, and marks
separately where production differs.

**Evidence.** Every readiness verdict was checked against a live replay —
`./scripts/rehearsal_reset.sh snatchit_rehears_act`, **108/108 migrations,
`GATE-2 tables=27 functions=70 policies=37 triggers=26`** matching the CI baseline
(`.github/workflows/ci.yml:581-584`) — not inherited from a document. Rows marked **[V]** carry an
executed result. The gate predicates, the enforcement audit and the corrections this revision applies
are in `docs/phase2/_impl/H9_activation_readiness.md`; the underlying work is in
`docs/phase2/_impl/H1`–`H8`.

**Revised 2026-09-03 by the refund / deletion-clock / payout backend train.** Twelve corrections were
applied, including the retirement of finding **F-2** (the checkout gate *does* check signing state —
**[V]** re-executed), the resolution of the `source_transaction` cardinality question, the arrival of
a dark payout executor, and the removal of three single-flip config hazards. Every correction is
itemised with its evidence in `H9 §4`. **All `093:NNNN` citations were re-derived — 093 is now 7 198
lines and the previous citations were wrong by more than a thousand lines.**

**Companion document.** `docs/phase2/FINAL_ACTIVATION_BLOCKER_RULINGS.md` (DRAFT, unsigned) now rules
on **five** owner decisions — ticket expiry, maturity interval, the signing ceremony, funded promoter
commission on reversed revenue (G4), and post-payout chargeback exposure (G5). Supplying them is
**necessary and not sufficient**: this matrix additionally names five undeployed edge functions,
refund executability under A9, and an unshippable payout executor.

**How to read "Currently ready?".** YES means the step works end to end today on an applied 093 with
the prerequisites in its own row satisfied. NO means it does not. There is no third value. Every NO
lists **every** blocker, not the first one, so the full critical path is visible.

---

## The matrix

### 1 · Venue setup

| | |
|---|---|
| **Required DB** | `kernel.organization` (`status in ('approved','active')`), `kernel.org_member`, `catalog.venue` (approved via `catalog.approve_venue`). All present in 077/078. `kernel.set_org_connect_ref` hardened at `093:4229`; `kernel.set_org_payout_destination` at `093:4442`; `kernel.sync_org_connect_state` at `093:3486`; `kernel.get_org_connect_ref` at `093:4742`. Connect mirror columns `connect_transfers_active` / `connect_state_synced_at` / `connect_pending_ref` added by 093 — **[V] all three exist.** **New this train:** `kernel.authorize_org_payout_dashboard` (`093:5067`) and `kernel.guard_connect_id_not_org_bound` + 2 triggers (`093:5220`). |
| **Required config** | none |
| **Required edge** | `connect-onboarding` — **authored, NOT DEPLOYED** (`supabase/functions/connect-onboarding/index.ts`; E1, H6 §1.2) |
| **Required Stripe state** | Express account, US, `business_type=company`, `transfers` capability requested, metadata binding the org id (A7) |
| **Required signing state** | none |
| **Required owner ruling** | A6, A7, A9 |
| **Currently ready?** | **NO** |
| **Why not?** | (a) `connect-onboarding` is not deployed, and it is the only server-side minter of an org connected account — A7 forbids a caller-supplied `acct_`, so there is no other path. It is also the **first** writer of `connect_transfers_active` (`index.ts:1151` → `kernel.sync_org_connect_state`), which every sale depends on. (b) 093 is not applied to production, so the hardened binders, the mirror columns, the dashboard-authority verb and the reverse cross-plane triggers do not exist there. (c) PostgREST must expose `kernel` (it does in production) for the org verbs to be client-reachable. (d) **Day-2 gap, not a launch blocker — H6 F-5.** `kernel.set_org_payout_destination` has **[V] no non-comment caller anywhere in the repo**, *and* it is **unreachable**: it requires a staged `connect_pending_ref`, and `connect-onboarding` stages only inside its `if (!accountId)` branch, so a bound org has no staging producer at all. **BIND-ONCE plus an unreachable re-point means a mis-bound organization is permanently mis-bound**, while the edge's `409 destination_unusable` arm advertises a recovery ("contact support to change your payout destination") that has no working verb behind it. The launch binder is `kernel.set_org_connect_ref`, which fully establishes the destination; do **not** build a speculative caller for the re-point verb — build a `mode:'replace'` branch in the edge when a venue first rotates an entity. (e) **New surface this train, and it closes a real hole:** the Express Dashboard login link is the only path that edits the **bank account behind** a bound `acct_`, and it previously rode the edge's endpoint gate with `org_finance`, no aal2, no audit row and no notification. `kernel.authorize_org_payout_dashboard` now requires `org_owner` only (SoD-1), aal2, org status ∈ (`approved`,`active`) and a bound destination, and writes an audit row plus a `security_payout_destination_changed` notification. |

### 2 · Event drafting

| | |
|---|---|
| **Required DB** | `catalog.event`, `catalog.event_session`, `venue.ticket_type`, `venue.inventory_batch` — all in 078/081 |
| **Required config** | none |
| **Required edge** | none |
| **Required Stripe state** | **none** — A8 ratifies this explicitly |
| **Required signing state** | none |
| **Required owner ruling** | A8 (DRAFT) |
| **Currently ready?** | **YES** |
| **Why not?** | — **[V] The chain org → venue → event → session was rebuilt this train with `select count(*) from kernel.signing_key` = 0, `stripe_connect_account_ref IS NULL`, and every owner config key at `'null'::jsonb`.** This is the one gate that is complete and correct. Caveat, not a blocker: `catalog.event_session.ends_at` is nullable and `catalog.create_event_session` requires only `starts_at` (`078:805-807`). A session created without `ends_at` is unswept by the expiry sweep (`079:490-492`, fails open) and unpayable by the maturity gate (`maturity_instant_unknown`, fails closed) — but it is **not** un-erasable: H2's deletion clock deliberately falls back to `starts_at` rather than blocking forever (`093:1579`), because this gate has no human exit and an erasure request that can never complete is a worse failure than the one it would prevent. |

### 3 · Event publish

| | |
|---|---|
| **Required DB** | `catalog.publish_event` (081) |
| **Required config** | none |
| **Required edge** | none |
| **Required Stripe state** | **none for `announced`.** A8 marks `on_sale` as requiring Connect readiness — **that half is not enforced.** |
| **Required signing state** | none |
| **Required owner ruling** | A8 (PUBLISHABLE / SALEABLE) |
| **Currently ready?** | **YES** |
| **Why not?** | — but with a **finding, not a blocker**: **[V] the deployed `publish_event` body reads no Stripe column, no config key and no signing key.** Its only `on_sale` precondition is a forward transition plus at least one `venue.ticket_type` carrying a `venue.inventory_batch` (`empty_inventory`). A8's SALEABLE row reads *"event may transition to `on_sale` **and** be purchased"* and marks it "Requires Connect readiness: **Yes**". Only the purchase half is enforced (row 5). **Consequence:** an event can display as on sale while every purchase refuses. Fail-closed on money, fail-open on the storefront. The client must therefore treat `payout_not_ready` / `no_active_signing_key` / `service_fee_unset` as a first-class "not on sale yet" state (`G5 §5.4` specifies exactly that copy). **Owner item — see G6 §5.4 for the two options.** |

### 4 · Inventory publish

| | |
|---|---|
| **Required DB** | `venue.inventory_batch`, `venue.inventory_hold`, `venue.reserve_primary_inventory` (081) |
| **Required config** | `feature.native_issuance_enabled` = true; `inventory.hold_ttl_interval` set; `inventory.per_user_active_hold_max` set. **[V] all three are currently `false` / `null` / `null`.** |
| **Required edge** | none — the RPC is granted to `authenticated` |
| **Required Stripe state** | none |
| **Required signing state** | none |
| **Required owner ruling** | A8 (DRAFT/SALEABLE boundary), 093 scope item 3 |
| **Currently ready?** | **NO** |
| **Why not?** | (a) `feature.native_issuance_enabled` is **[V] `false`** (`078:1522`) — `venue.reserve_primary_inventory` raises `precondition_failed: feature_disabled` at `081:583`, and `venue.create_inventory_hold` again at `081:703`. (b) `inventory.per_user_active_hold_max` is **[V] `null`**; `081:615-626` collapses the cap to **0**, so `0 + 1 > 0` refuses the first hold of every user (`hold_cap_exceeded`). (c) `inventory.hold_ttl_interval` is **[V] `null`**; `081:630-639` raises `hold_ttl_unset` with no default and no coalesce. (d) 093 is not applied to production, so all three key **rows** are absent there and `catalog.set_platform_config` raises `unknown_key` for any key not already present (`078:1103`) — configuration cannot create them. (e) `catalog` and `venue` are **not** exposed over PostgREST in production (`docs/release/PHASE2_DEPLOYMENT_RECORD_20260902.md:23-25`; `venue` returns `PGRST106`), so no client can call the RPC. **[V] All three keys are settable by a single `platform_admin` — `{"status":"ok"}` on each — and that is intended (H9 §7).** |

### 5 · Primary sale

| | |
|---|---|
| **Required DB** | `venue.create_primary_checkout` **as replaced by 093** (`093:3845`); `venue."order"`, `venue.order_item` (082); the `public.payments` relaxation + rail-pairing CHECK (093 item 1) |
| **Required config** | everything in row 4, **plus** `fee.buyer_service_bps` (**[V] `null`**) |
| **Required edge** | `primary-checkout` — **authored, NOT DEPLOYED** (E2). It is the only thing that mints a PaymentIntent. |
| **Required Stripe state** | `stripe_connect_account_ref` bound **AND** `connect_transfers_active` = true; platform Stripe account live (A2: separate charges and transfers, no `transfer_data`, no `on_behalf_of`, no `application_fee_amount`, no `Stripe-Account`) |
| **Required signing state** | **CHECKED, AND REFUSED AT QUOTE TIME.** One `kernel.signing_key`, `status='active'`, in its `not_before`/`not_after` window, resolvable `per_event → per_venue → global` for the event's scope (`093:4033`). **[V] `precondition_failed: no_active_signing_key` was executed this train with the org fully bound and zero keys present.** This **retires finding F-2** — see H9 §4 C-1. Its consequence for the ceremony: **once 093 applies, no primary checkout can be quoted at all until the KMS ceremony has run.** |
| **Required owner ruling** | A1, A2, A5, A8, **A9** |
| **Currently ready?** | **NO** |
| **Why not?** | (a) 093 is not applied to production, so the A8 gate does not exist there at all. (b) All of row 4's blockers apply — the RPC requires live holds it cannot get. (c) **`payout_not_ready`** (`093:3983`, refusal 1 of 3): `connect_transfers_active` is written **only** by `kernel.sync_org_connect_state` (`093:3486`, service_role only), whose **two** callers are `connect-onboarding/index.ts:1151` and the `account.updated` organization arm of `stripe-webhook/index.ts:1268` — **both undeployed**. The flag is a self-healing gate with **no writer in production**. **[V] observed.** (d) **`no_active_signing_key`** (`093:4033`, refusal 2 of 3) — see the signing row; **[V] observed**, and **[V] zero signing keys exist**. (e) **`service_fee_unset`** (`093:4062`, refusal 3 of 3): `fee.buyer_service_bps` is **[V] `null`**. **[V] observed.** (f) `primary-checkout` is not deployed, so no PaymentIntent can be minted even if the RPC returns ok. (g) **Ruling A9 makes refund executability a hard precondition of selling, it is not satisfied, and it is enforced by no code.** A9's text: *"selling may not be activated until a refund recorded by the database results in money actually returning to the buyer, by an automated executor or by a named written process with a named accountable human and a defined write-back step."* **[V] The only two occurrences of the string `refund` inside `create_primary_checkout` are comments** — there is no refund operand in the gate at all. This train closed two of the three grounds on which G6 held the built executor insufficient (the sweep self-heal is alive; PFA-23's direct arm is reachable) and left the third: **it is not deployed**. A9's second disjunct — the named written process — **does not exist anywhere in the corpus**. See row 8 and H9 §3. (h) No tax model exists anywhere: **[V] zero functions, zero columns and zero config keys match `%tax%`** across `kernel`/`venue`/`catalog`/`public`. Nothing to check, so nothing is checked. (i) **NEW — H9 §5, finding F-13. A `suspended` organization can still sell. [V] Executed:** with `kernel.organization.status = 'suspended'`, a bound `acct_`, `connect_transfers_active = true` and one active signing key, the gate refuses only on the fee key. `create_primary_checkout` reads `kernel.organization` for exactly two columns and **never reads `status`**. 093 added `status ∈ ('approved','active')` to both Connect binders and to the dashboard verb; it did not add it to the sale gate, and H6 F-6 records the identical omission in `kernel.request_org_payout`. Suspension is the platform's own risk lever, and today it does not stop the platform becoming merchant of record for that org's tickets. Recorded, not fixed — it is a body change to a money-path function and belongs to a 094 with an owner ruling. |

### 6 · Payment confirmation

| | |
|---|---|
| **Required DB** | `public.payments` accepting a native row (093 item 1); `kernel.payment_native`; `venue.finalize_primary_order` (`085:1919`), service_role only — **[V] not replaced by 093** |
| **Required config** | as row 5 |
| **Required edge** | `stripe-webhook` **with the native branch** — `native.ts` authored, `index.ts` branches authored, **NOT DEPLOYED**. Production runs the pre-native build (`docs/release/PHASE2_DEPLOYMENT_RECORD_20260902.md:25-29`: *"No other function touched."*) |
| **Required Stripe state** | live webhook endpoint delivering `payment_intent.succeeded` with `metadata.rail = native_primary`; `stripe_livemode = true` |
| **Required signing state** | **an active, in-window `kernel.signing_key` resolvable for the event scope** (resolver `085:1948-1960`). Since G2b this is the *second* place the key is required, not the first — row 5 refuses first. |
| **Required owner ruling** | A2, A3, B, E |
| **Currently ready?** | **NO** |
| **Why not?** | (a) The native branch is not deployed. On the deployed build a `native_primary` PaymentIntent falls through to `unknown_mode` → **HTTP 500, retried ~3 days, buyer charged, no ticket** (E3 §1). (b) **[V] Zero signing keys exist** and the 093 bootstrap row is **deliberately commented out** (`093:5867`) pending the KMS ceremony. (c) 093 is not applied, so `public.payments` still carries the two `NOT NULL` constraints that make a native row unstorable (`000_baseline_schema.sql:973`), and `venue.finalize_primary_order` raises if no payments row is found (`085:1919-1934`). (d) Row 5's blockers all precede this one — and **the "buyer charged, then no key, no ticket" hazard the previous revision recorded here is now closed *before* the charge, not after it**, because the signing refusal moved to quote time. |

### 7 · Ticket issuance

| | |
|---|---|
| **Required DB** | `kernel.tickets` (079), `kernel.issue_ticket_atoms` **as replaced by 093** (`093:4831`), `kernel.signing_key` (083). **[V] `kernel.tickets.signing_key_id` is `is_nullable = NO`**, with `ON DELETE RESTRICT` to `kernel.signing_key`. |
| **Required config** | `feature.native_issuance_enabled` = true (**[V] false**); `ticket.expiry_grace` set, as a **jsonb string** (**[V] null**) |
| **Required edge** | `stripe-webhook` native branch (row 6). No `credential-sign` edge exists — signature production is off-database and unbuilt. |
| **Required Stripe state** | a succeeded, livemode PaymentIntent |
| **Required signing state** | **one active key, produced by the two-person KMS ceremony** (`docs/phase2/PRODUCTION_SIGNING_KMS_CEREMONY.md`; rulings B / G3). 093's replaced mint additionally **refuses a caller-supplied key**: a `p_ctx->>'signing_key_id'` that disagrees with the resolved key raises `signing_key_override_refused` (`093:4925` region). **The mint no longer accepts a key; it resolves one.** |
| **Required owner ruling** | B, D2, **G1** (the `ticket.expiry_grace` value) |
| **Currently ready?** | **NO** |
| **Why not?** | (a) **[V] Zero signing keys.** The bootstrap row is commented out in 093 on purpose — it must not execute until the ceremony has produced both strings (`093:5867`). (b) `feature.native_issuance_enabled` is **[V] false** — the mint's own gate. (c) `ticket.expiry_grace` is **[V] null**, so `kernel.sweep_expired_ticket_atoms` (`079:456`, cron `*/2`) returns `swept_count: 0` **silently, forever** (`079:480-485`). **The consequence is now narrower than the previous revision recorded:** H2 re-anchored BP-12 arm 2 to the event, so for any deletion hold ≥ the grace, BP-12 **strictly dominates** BP-1 for every *paid* buyer — and it dominates whatever the grace is set to, including a mistaken one. `ticket.expiry_grace` therefore carries deletion semantics for exactly one population: holders of comp, guest-list and imported atoms, who have no `venue."order"` row at all. Its cost there is erasure *latency*, bounded at the grace. **G1's recommended `'"72 hours"'` stands, now chosen on admissibility grounds alone.** (d) `stripe-webhook`'s native branch is the only caller of the mint on this rail and is not deployed. (e) No `credential-sign` edge exists, so no issued atom can actually be signed — the DB records the trust state; nothing produces a signature. (f) `catalog.event_session.status` is **never** written to `'completed'` by anything in 076–093 (only `'cancelled'`, `088:1793`), which is why nothing downstream may depend on it. |

### 8 · Refund

| | |
|---|---|
| **Required DB** | `kernel.refund` (085), `kernel.refund_primary_order` (`085:457`), `kernel.request_order_refund` (`085:850`), `kernel.admin_refund` (`085:706`), `kernel.mark_refund_state` (`085:1737`), `kernel.get_refund_execution_context` (**[V] exists — `093:1038`, service_role only**), and **`kernel.claim_refunds_for_execution`** (**[V] exists — `093:1311`, service_role only; NEW this train**) |
| **Required config** | `refund.*` policy keys — **[V] all null except `refund.scanned_atom_policy` = `"platform_review"`**. The five D-3 tiers being NULL-seeded means that arm authorizes nothing — fail-closed, and correct until activation. |
| **Required edge** | `refund-execute` — **authored (70 TS tests + 39 pgTAP assertions green), NOT DEPLOYED** (E4, H1) |
| **Required Stripe state** | `POST /v1/refunds` reachable; the payment `stripe_livemode = true` (migration 045; NULL fails closed) |
| **Required signing state** | none |
| **Required owner ruling** | **D3** (build the executor), **A9** (refund executability is a hard precondition of selling), D — **plus a new one: ratification of `kernel.claim_refunds_for_execution`** (H1 §5.4). It is a `service_role` verb that **enumerates money in flight**, and E4's own standard says such a verb deserves its own ratification rather than arriving as a silent passenger in the money slice. **This is a hard gate before 093 is applied.** The ask is narrow: one read-and-lease verb, `service_role` only, projecting no payment, amount, identity or destination, moving no money and transitioning no refund. |
| **Currently ready?** | **NO** |
| **Why not?** | (a) **`refund-execute` is not deployed, and that is now the only structural blocker on this row.** Nothing else in the repo calls `kernel.mark_refund_state`, and it is the only transition out of `pending`. **So every `kernel.refund` row created today is born `pending` and stays `pending` forever: the buyer loses the ticket and gets no money** (`085:593` voids the atoms, `085:604` moves the order, `085:599` inserts the row). That is precisely the failure A9 names. (b) The stranded `pending` row then blocks that buyer's account deletion permanently — BP-12 arm 1 (`085:246-261`), which H2 transcribed byte-for-byte and left untouched. (c) **CORRECTED — the sweep is no longer dead.** The previous revision said `kernel.list_pending_refunds` was missing and the executor's `sweep` answered 501. That verb was **deliberately never built**: a list hands N workers the same N refunds and makes Stripe's 24-hour idempotency key the *first* line of defence instead of the last. H1 §3 replaced it with a claim/lease primitive in the `064` house pattern — `for update … skip locked`, the lease carried by an append-only `kernel.admin_audit` row, `p_limit`/`p_lease_seconds` clamped server-side to `1..100` / `60..3600`, and **no parameter by which a caller can name a refund, payment, order, venue, org, identity, amount or destination**. It also closes a hole E4 never named: Stripe retains an idempotency key for **24 hours**, so a row stranded past that window would have created a *second real refund*; the DB now issues an `execution_mode` per row (`create` inside 20h, `reconcile` outside) and `reconcileOne` **establishes existence before it creates**. **[V] the function exists and `refund-execute/index.ts:644` calls it.** (d) **CORRECTED — PFA-23's direct arm is reachable, and the previous "unimplementable caller" finding was wrong.** `kernel.refund_primary_order`'s DIRECT branch is a **definer-internal branch, not an edge-callable arm**. The authority was never missing: `kernel.request_order_refund` is granted to `authenticated`, carries `auth.uid()`, evaluates the same `kernel.is_platform` predicates and the same `refund.platform_support_max_minor` cap on the same cumulative operand under the same payment lock, and calls `refund_primary_order` definer→definer under a `req:<uuid>` key. Suite `149` D2 already asserted the result is `status: 'executed'` — one platform actor, no second human, no raw SQL. The edge now routes direct → `request_order_refund` (`index.ts:750`) and delegated → `refund_primary_order`. No grant, no function body and no frozen rule changed; `149` D1/D2/D8 stay green unmodified. Recorded at `docs/architecture/_governance/PFA23_DIRECT_ARM_CLARIFICATION.md`. **E4 §7's three options are moot.** (e) 093 is not applied to production, so neither `get_refund_execution_context` nor `claim_refunds_for_execution` exists there. (f) **Open and sharpened, not closed — E4 §6.1.** This executor is what makes `kernel.refund.status = 'failed'` reachable for the first time, and slice 10b books the venue's negative `refund_void` line for any refund with `status <> 'failed'` — i.e. while still `pending`. A Stripe-accepted-then-unsettled refund therefore leaves the buyer unpaid **and** the venue permanently debited in an append-only ledger. Four shapes, none chosen; it is the settlement owner's call. (g) A post-event **full** refund cannot use the routine path: `refund_primary_order` refuses with `frozen: … transfer-frozen`. The post-event path is `kernel.admin_refund` (platform_risk / platform_admin, explicit atom ids). Both write `kernel.refund`, so both reach the `refund_void` seam identically — **any runbook that assumes otherwise is wrong** (H5 §7.3). |

### 9 · Settlement maturity

| | |
|---|---|
| **Required DB** | `venue.settlement` / `venue.settlement_line` (087, append-only), `kernel.settlement_primary_lines` (**[V] `093:435`**), `kernel.settlement_commission_lines` (**[V] `093:889`**), `kernel.close_settlement` **as replaced by 093** (`093:640`), and — **new this train** — **`kernel.settlement_payout_maturity`** (`093:2076`) plus `kernel.settlement_covered_payments` (`093:1988`) |
| **Required config** | **`payout.settlement_maturity_interval`** — **[V] null**. Renamed by the previous train from `settlement.refund_window_interval`, which **[V] no longer exists as a row**. |
| **Required edge** | none — this is pure SQL |
| **Required Stripe state** | none for the hold decision; `kernel.dispute_native` state informs the dispute conjunct |
| **Required signing state** | none |
| **Required owner ruling** | A3, A4, A5, **G2** |
| **Currently ready?** | **NO** |
| **Why not?** | (a) 093 is not applied to production; on 092 `close_settlement` still decides the hold with the single line `v_held := v_refund_window is null` and no maturity semantics at all — the defect G2 fixed. (b) `payout.settlement_maturity_interval` is **[V] null**, so every close holds with `unbounded_refund_exposure`. **This is the correct and intended state** — the key must not be set before activation, and **[V] it is dual-controlled** (`{"status":"parked"}` for a single admin). (c) There is nothing to settle: rows 5–7 are all NO, so no `primary_sale` line can exist. (d) **RESOLVED THIS TRAIN — the maturity gate is no longer a close-time snapshot.** H4 D-1 proved four independent state changes defeated it (a post-close refund succeeding, a post-close event cancellation, a dispute first observed already terminal, and a lost Connect capability), each leaving the payout `hold_state='none'`, at full face value, and payable. The fix was **one change, not four**: the eight predicates moved verbatim into `kernel.settlement_payout_maturity(uuid)` and are now called from **[V] three sites** — `close_settlement` (the mint), `request_org_payout` (immediately before the advance *and* before the park, new result member `maturity_held`), and `get_payout_execution_context` (immediately before the transfer). **One definition, three calls, so the evaluations cannot drift** — which is the property that matters, not the count of checks. The eight codes are **[V]** `unbounded_refund_exposure` · `maturity_policy_invalid` · `covered_set_unresolvable` · `event_cancelled` · `maturity_instant_unknown` · `maturity_not_elapsed` · `refund_in_flight` · `dispute_open`; a ninth, **`refund_exposure_stale`**, exists at execution time only (`093:2383`), because the mint cannot carry it. (e) **RESOLVED THIS TRAIN — the mutable anchor is closed in code.** The previous revision recorded `catalog.event_session.ends_at` as mutable by the party being paid. Slice 40 adds a backward arm to `catalog.update_event_session` (`093:6907`) that refuses any earlier `ends_at` move on a session carrying economic weight — an issued atom, a paid/partially-refunded/refunded order, a door scan, or any settlement on the event — fails closed if the probe itself raises, and demands a mandatory `reason_code`; `platform_admin` is the only bypass (`093:7143`, `backward_schedule_move_frozen`). Postponement, the safe direction, still succeeds and lengthens the hold. **G2 Part 3's residual and its Part 6 owner item should be struck.** (f) **Still open — ruling G5.** A chargeback filed after release is covered by no interval; it needs a receivable object or a Stripe fixed reserve plan, neither of which exists. Executed this train: an org sold 23 000, was paid 19 000, was entitled to 13 000 — **platform loss 6 000**. Of six possible accounting outcomes only *platform absorbs* is implemented; *future payout offset* exists only accidentally and **silently confiscates a venue's later revenue while destroying the excess** — a dispute with the venue waiting to happen. (g) Residual, LOW: `venue.settlement.status` carries no append-only trigger, so the table owner can re-open a closed header, and the re-close then **reports a hold it does not apply** (the mint's `on conflict do nothing` skips the row). Not exploitable; worth a runbook warning or a forward-only trigger (H4 D-6). |

### 10 · Venue payout

| | |
|---|---|
| **Required DB** | `kernel.payout` (085/087) **plus its new `destination_ref` column** (`093:1686`, with an `acct_…` shape CHECK); `kernel.request_org_payout` **as replaced by 093** (`093:1743`); `kernel.release_payout` (`085:807`); and four new execution verbs — `kernel.get_payout_execution_context` (`093:2266`), `kernel.hold_payout_destination_changed` (`093:2478`), `kernel.claim_payouts_for_execution` (`093:2638`), `kernel.record_payout_execution_note` (`093:2744`). **[V] all present, all `service_role`-only.** |
| **Required config** | `payout.settlement_maturity_interval`; `payout.destination_cooldown_hours` (**[V] null — fails OPEN**); `payout.destination_probation_days` (**[V] null**); `payout.dual_control_min_minor` (**[V] null**); `payout.request_auto_max_minor` (**[V] null**); `authn.money_role_maturity_hours` (seeded 72) |
| **Required edge** | **`payout-execute` — authored this train (`executor.ts` + `index.ts`, 57 tests), DARK, NOT DEPLOYED, and declared NOT SHIPPABLE** (H8 §9). **[V] `supabase/functions/payout-execute/` exists.** |
| **Required Stripe state** | connected account with `transfers` active. **`source_transaction` is NOT set on this rail** — see (b). |
| **Required signing state** | none |
| **Required owner ruling** | A2, A3, A5, A6, A9, and **G5** — *"the venue payout executor may not be deployed until: (1) accept with explicit risk acceptance / (2) receivable object first / (3) Stripe reserves"*. **Unsigned.** |
| **Currently ready?** | **NO** |
| **Why not?** | (a) **The executor exists but must not ship.** The reachable terminal state of a settlement payout today is still `submitted` with `stripe_transfer_ref = NULL`. H8 §9 states the shipping gate plainly: post-payout loss is currently tolerable **only because no payout executor exists**, and this function is what removes that protection. Two preconditions of *shipping* (distinct from *writing*): the maturity re-evaluation fix — **done this train** — and **a receivable or reserve object — NOT done**; it is a 094 schema question, and `CHECK (amount_minor > 0)` on `kernel.payout` makes one unrepresentable without DDL. **Deploying this without the receivable object is not safe.** (b) **RESOLVED — the `source_transaction` cardinality question is not a blocker and never required a schema change.** The prior premise assumed `source_transaction` is *required* to create a transfer. It is an optional funding hint: a transfer needs only `amount`, `currency`, `destination`. Aggregation happens in the ledger, not at Stripe — **N charges → N lines → 1 net → 1 payout → 1 transfer → 1 ref.** The payout unit is the `kernel.payout` row, 1:1 with `venue.settlement` for `cause='settlement'`; `stripe_transfer_ref` keeps its write-once singular shape and `source_transaction_ref` stays NULL, meaning *funded from the platform available balance*. The timing gap `source_transaction` exists to solve is **structurally absent** here, because a settlement payout is only executable at least one maturity interval after the last covered session ended — weeks after the earliest funding charge. It could not honestly be used anyway: it is not amendable after creation, it caps the transfer at the source charge, and the settlement net corresponds to no charge amount at all. **Accepted in exchange:** a `balance_insufficient` failure if the platform has swept its own balance between maturity and execution. Controls: a **mandatory** `GET /v1/balance` preflight before any `/transfers` call — never spend an idempotency key on a request that cannot succeed — and an operational requirement that the platform's own Stripe payout schedule be **manual**, or a float maintained above the largest open matured settlement. **The resale rail is unchanged and keeps `source_transaction`.** (c) Rows 1 and 9 are both NO. (d) `kernel.request_org_payout` requires an aal2 step-up — **[V] `precondition_failed: step_up_unavailable`** — plus a matured money role (72h), the SoD-1 setter exclusion, a non-held payout, and now a live `settlement_payout_maturity` re-check returning `maturity_held`. It also **pins `destination_ref`** on both `pending → submitted` arms, so the executor sends the value that was authorized rather than a fresh read; on divergence it calls `kernel.hold_payout_destination_changed`, which **re-derives the fault itself** (a worker cannot demote a healthy payout — it raises `no_destination_fault`) and moves the row `submitted → pending` + `held/destination_changed`, released through the existing human path. **It is never `failed`.** (e) Four `payout.*` policy keys are **[V] null** and **[V] all dual-controlled** (`{"status":"parked"}`), which is correct. **Ordering constraint: `payout.dual_control_min_minor` must never be set before `kernel.payout.destination_ref` exists.** X-12's restrictive reading currently parks every payout, so the approval row's `payload.destination_ref` is the only thing pinning a destination today; the moment that threshold is set, every payout below it advances with **no destination record anywhere**. `destination_ref` ships in 093, so **applying 093 discharges this constraint** — but it is live on production until then. (f) **Gaps that survive inside the payout path.** At **request** time there is still no `connect_transfers_active` predicate (**[V]** the column is read by exactly five routines — `get_org_connect_state`, `sync_org_connect_state`, `venue.create_primary_checkout`, `get_payout_execution_context`, `hold_payout_destination_changed` — and `request_org_payout` is not among them) and **[V] no `organization.status` gate**, so a **suspended** org can still request and advance a payout (H6 F-6, the twin of row 5's F-13). Both are now enforced at **execution** time by `get_payout_execution_context`, so the exposure is bounded to the window between request and execution rather than open-ended. (g) **`failed` is absorbing (H3 §8.1 / H4 D-2). [V] Executed:** `failed → paid` and `failed → reversed` both raise `payout_state_backwards`; `failed → submitted` is not a valid target; `request_org_payout` selects only `status in ('pending','submitted')` so a failed payout is invisible to it; and `close_settlement` is forward-only with `on conflict (idempotency_key) do nothing`. **A transient rate limit would permanently strand a real debt to the venue with no in-corpus recovery verb.** Mitigated in v1 because the executor **never writes `failed`** — every non-success leaves the row `submitted` and writes an immutable `record_payout_execution_note`, so a repeatedly-refused payout is visible rather than indistinguishable from an un-attempted one. The `failed → submitted` re-arm belongs in 094. (h) `kernel.resolve_dispute_native` **[V] still raises `dual_control_unavailable` with zero mutation** (`088:913-931`, PFA-31), so a lost dispute freezes the org's payout and the buyer's atoms permanently with no exit. A9 records this as a known defect that must close *"before the direct rail carries material volume"* — a volume threshold, not a launch blocker. (i) **No hold ever self-clears (H4 D-5).** A settlement closed before maturity mints a payout held `maturity_not_elapsed` that stays held until a human calls `kernel.release_payout`; there is no cron, no sweeper and no time-based arm. `matures_at` is published to the operator as if it were self-executing. **This needs a runbook entry or a sweep before launch.** |

### 11 · Promoter funding

| | |
|---|---|
| **Required DB** | `venue.promoter`, `venue.promoter_code`, `venue.attribution` (090); `kernel.settlement_commission_lines` (087 seam, body replaced at `093:889` to exclude `partially_refunded`); `kernel.pay_promoter_commission` (`090:1487`) |
| **Required config** | the commission policy keys the promoter engine reads; row 9's maturity key |
| **Required edge** | none |
| **Required Stripe state** | none — funding is a ledger act, not a transfer |
| **Required signing state** | none |
| **Required owner ruling** | **A4** — *"eligible primary promoter commission is funded from primary-sale economics and reduces venue distributable before venue money is released"*; *"funding a commission is NOT equivalent to paying a commission"* |
| **Currently ready?** | **NO** |
| **Why not?** | (a) There is no revenue to deduct from: rows 5–9 are all NO, so no `primary_sale` line exists and every commission is a debit against nothing. (b) 093 is not applied, so `kernel.settlement_primary_lines` — the seam that produces the revenue — does not exist in production, and the commission seam's `partially_refunded` fix is not there either. Without that fix, a direct partial refund voids no atoms (`085:562-564`), the commission basis is unreduced, and **full commission is paid on partly refunded revenue** — unrecoverable in an append-only ledger. (c) **Option B holds mechanically, proved by execution twice with hand-checked arithmetic.** The commission is a negative, non-refund settlement line, so it lands in the FEES bucket and is subtracted *before* the org payout exists. `net_minor = gross − fees − refunds` is a table CHECK (`settlement_waterfall_ck`), not a convention. Conservation was exact: venue 9 000 + commission 1 000 = gross 15 000 − refunds 5 000. (d) **A4 holds, asserted as a negative with both runtime and source evidence:** **[V] `count(*) from kernel.payout where cause='promoter_commission' and hold_state <> 'held'` = 0** after two economic chains, three refund cycles, a chargeback, an event cancellation, a re-close and an owner-level re-open; and the money slice contains **zero `update kernel.payout`**. Nothing in 093 can accidentally release promoter money. (e) Residual, unchanged: `kernel.pay_promoter_commission` can still `raise` (`terms_unresolvable`, `090:1447`), and a raise inside a seam rolls back the entire close — which the 087 seam contract (`087:204-207`) says must not happen. Every other rejection is a `continue` into `held[]`. It is the single non-conforming arm. |

### 12 · Promoter payout

| | |
|---|---|
| **Required DB** | `kernel.payout` rows with `cause='promoter_commission'`, minted `held` / `unfunded_settlement` by `kernel.pay_promoter_commission` (`090:1487-1491`); `kernel.release_payout` as the sole exit |
| **Required config** | the `payout.*` keys of row 10, all **[V] null** |
| **Required edge** | the same `payout-execute` as row 10 — and it can never reach these rows. **[V] Read from the deployed `kernel.claim_payouts_for_execution` body, its eligible set is `cause='settlement'` ∧ `payee_kind='organization'` ∧ `status='submitted'` ∧ `hold_state='none'` ∧ `stripe_transfer_ref is null` ∧ `destination_ref is not null`** — a `promoter_commission` payout fails the first two conjuncts and is structurally unclaimable. |
| **Required Stripe state** | a connected account or other destination for the promoter — **the promoter payee plane is not the org plane**; `kernel.payout.payee_identity_id` exists but nothing binds a promoter destination, and the new `kernel.payout.destination_ref` is written only by the two `request_org_payout` arms |
| **Required signing state** | none |
| **Required owner ruling** | **A4** — *"promoter payout execution remains dark and separately gated"* — **and now G4**, unsigned |
| **Currently ready?** | **NO** |
| **Why not?** | (a) **Nothing releases a promoter commission payout.** They are minted `held`/`unfunded_settlement` and there is no code path that clears that hold. (b) Row 10's shipping gate applies, and the executor additionally refuses these rows by construction. (c) Row 11 is NO, so nothing is funded to pay. (d) **A4 rules this dark on purpose.** This row is NO *by design*, and it is the only NO in the matrix that should stay NO after everything else turns YES. (e) **NEW BLOCKER — ruling G4, unsigned.** When the revenue that funded a commission is reversed **after** the close that funded it, there is no mechanism to reduce it, and all four routes are closed by construction: `venue.settlement_line` is append-only (UPDATE and DELETE both raise); a compensating line is **unstorable** (`attribution_one_commission_line_ever` is a global unique index on `cause_ref`, so a second line raises `23505`); the closed header's money columns are write-once; and `kernel.payout` has no reduce, void or cancel verb. In the rehearsal, **3 800 of 4 800 minor units — 79% — across four of five funded attributions stood against reversed revenue**, from four ordinary shapes (post-close full refund, post-close partial refund, post-payout chargeback, post-close event cancellation). **The exposure is HIGH in principle and CONTAINED in practice, and the containment is a single boolean: nobody has released a commission hold.** Until G4 is signed, **`kernel.release_payout` must not be used on a `promoter_commission` payout for any reason.** |

---

## Summary — the "Currently ready?" column

| # | Row | Ready? |
|---|---|---|
| 1 | Venue setup | **NO** |
| 2 | Event drafting | **YES** |
| 3 | Event publish | **YES** |
| 4 | Inventory publish | **NO** |
| 5 | Primary sale | **NO** |
| 6 | Payment confirmation | **NO** |
| 7 | Ticket issuance | **NO** |
| 8 | Refund | **NO** |
| 9 | Settlement maturity | **NO** |
| 10 | Venue payout | **NO** |
| 11 | Promoter funding | **NO** |
| 12 | Promoter payout | **NO** — *and correctly so, per A4* |

**Two of twelve, unchanged.** Both YES rows are the two A8 ruled require nothing: DRAFT and
PUBLISHABLE. That is the ratification working exactly as written — a venue can build its whole event
before Stripe exists, and cannot take a dollar until the rail does. **What changed this train is not
the count but the shape of the NOs.** Rows 8, 9 and 10 moved from *missing mechanism* to *undeployed
mechanism plus an unsigned ruling*: the refund sweep has a claim primitive instead of a 501, the
maturity gate is an invariant instead of a snapshot, and a payout executor exists where none did.
Row 5's signing hole is closed outright. Nothing turned YES, and nothing should have — every one of
those changes moves a blocker from *engineering* to *deploy plus signature*, which is exactly where
this document exists to put them.

---

## The critical path, in dependency order

**Nothing here is authorized or scheduled; this is the shape of the path, not a plan.** Adjudication
and evidence in `H9 §6`.

**The KMS ceremony is NOT the head of the path, and this revision corrects the previous one on that
point.** **[V] Executed:** an unbound org refuses `payout_not_ready` *before* the signing resolver is
ever reached, and `connect_transfers_active` has **no writer in production** — its only writer,
`kernel.sync_org_connect_state`, is called by `connect-onboarding` and `stripe-webhook`, both
undeployed. Bootstrapping a key today changes no observable behaviour anywhere, and three deploy acts
plus an API cutover sit in front of it. **What is nonetheless true:** since G2b the ceremony gates the
first production *quote*, not the first mint; it is the only irreversible item on the list; and its
lead time is human, not engineering. **It is the longest pole, and it parallelises cleanly. Schedule
it now; land it before step 9.**

| Step | Act | Kind | Unblocks |
|---|---|---|---|
| **0a** | **G5** — receivable/reserve object vs. explicit risk acceptance | owner ruling | blocks *deploying* the payout executor; **does not block selling** |
| **0b** | **G3** — provider (D1), two named operators with separated cloud IAM, a booked window | owner ruling + people | 7 |
| **0c** | **G1** (`ticket.expiry_grace`) and **G2** (`payout.settlement_maturity_interval`) values | owner values | 8 |
| **0d** | **Ratify `kernel.claim_refunds_for_execution`** (H1 §5.4) | owner signature | **hard gate before step 1** |
| **0e** | Tax model (**[V]** zero keys, zero functions, zero columns); A5 processing-cost allocation; the `on_sale` gating choice (G6 §5.4) | owner + counsel | 3, 5, 9 |
| **0f** | Acknowledge H2's rename of PFA-22's key: `deletion.refund_possible_window_hours` → **`deletion.post_event_hold_hours`**, re-anchored from the payment clock to `max(coalesce(session.ends_at, session.starts_at))` over the identity's paid orders. Semantics preserved; spelling and anchor changed against an owner-signed ruling. The old key survives as an **unread orphan** (`platform_config` is append-only) | owner acknowledgement | deletion, not selling |
| **0g** | **G4** — funded commission on reversed revenue | owner ruling | **row 12 only**; blocks the first release of any commission hold |
| **1** | **Apply 093** to production (ledger 107 → 108) | migration | 1, 4, 5, 6, 8, 9, 11 |
| **2** | Expose `catalog` + `venue` over PostgREST — **must come after step 1** (E2 AB-8) | operational, two-person | 4, 5 |
| **3** | Deploy **`connect-onboarding`** | deploy | 1 — and the **first** writer of `connect_transfers_active` |
| **4** | Deploy **`stripe-webhook`** (native branch) | deploy | 6, 7 — the ongoing connect-state writer and the only caller of `finalize_primary_order` |
| **5** | Deploy **`refund-execute`** | deploy | 8 — **A9's first disjunct; must precede step 9** |
| **6** | Onboard one organization: mint → stage → bind → verify → sync | operational | makes `connect_transfers_active` true for one org |
| **7** | **KMS ceremony** + insert the bootstrap `kernel.signing_key` row (commented out at `093:5867`) | owner ceremony, **irreversible** | 5, 6, 7 |
| **8** | Owner config, in this order: `inventory.*` (single admin) → `ticket.expiry_grace` (quorum) → `payout.settlement_maturity_interval` (quorum) → `deletion.post_event_hold_hours` (quorum, **only after step 5**) → `fee.buyer_service_bps` (quorum) | owner config | 4, 5, 7, 9 |
| **9** | Deploy **`primary-checkout`** — last; it is the only thing that can take money | deploy | 5 |
| **10** | `feature.native_issuance_enabled = true` — last of all, single admin | config | 4, 5, 7 |

**The PAYABLE tail, after a first sale:** 0a signed → build the receivable or reserve object → deploy
`payout-execute` → only then may `payout.dual_control_min_minor` be set. Separately: arm a sweep or a
runbook entry for held payouts that never self-clear (H4 D-5); land the `failed → submitted` re-arm in
094; and close PFA-31 (`kernel.resolve_dispute_native`) before the rail carries material volume.

**Two ordering constraints not visible from any single row.**

1. `deletion.post_event_hold_hours` must not be set before `refund-execute` is deployed. Setting it
   stops BP-12 arm 2 blocking, and a buyer whose refund is stranded `pending` forever becomes
   erasable. **Nothing enforces this ordering; it belongs in the runbook in writing.**
2. `kernel.payout.destination_ref` must exist before `payout.dual_control_min_minor` is ever set.
   Applying 093 discharges this. Until then, the exposure is created by *configuring* the system, not
   by leaving it unconfigured — the opposite of how a config key is normally reasoned about, which is
   exactly why it needs saying out loud.

**Retired from the previous revision.** *"`kernel.list_pending_refunds` is unauthored — small
migration"* (the verb was deliberately never built; a claim primitive replaced it) and *"the
`source_transaction` mapping for one payout across many funding charges is unsettled — paper, owner +
counsel"* (resolved: it is an optional funding hint, and the payout unit needs no schema change on
that axis).

---

## Hazards — where one change crosses a gate

**[V] Every config verdict below was executed this train against the live setter as a real
`platform_admin` on aal2.** Of the 49 config keys, **18 are single-admin and 31 are dual-controlled**
(prefix test at `093:6705`, now `refund.` `payout.` `authn.` `comp.` `wallet.` `credential.`
`door.session_` **`fee.`** **`deletion.`** **`ticket.`**); three of the 18 are on the activation path
and all three are intended.

| Change | Crosses | Dual-controlled? | Intended? |
|---|---|---|---|
| `payout.settlement_maturity_interval` → any value | one conjunct of eight | **YES — [V] `{"status":"parked"}`** | **YES — the G2 fix, and the reference shape.** |
| `fee.buyer_service_bps` → any integer | the LAST clause of the SALEABLE chain | **YES — [V] `{"status":"parked"}`** | **YES — FIXED THIS TRAIN.** This was the previous revision's *"surviving instance of the banned pattern"*; `fee.%` joined the dual-control prefix set, exactly as that revision recommended, and the rejected alternative (renaming it into `payout.%`) was not taken. |
| `ticket.expiry_grace` → a JSON **number** | inert sweep → **every active atom on every ended session terminal within two minutes** (cron `*/2`, `079:799-803`) | **YES — [V] `{"status":"parked"}`** | **YES — FIXED THIS TRAIN, twice over, and the two guards compose.** The interval type guard refuses a bare `24` **outright** — `('24'::jsonb #>> '{}')::interval` is twenty-four **seconds** — before the dual-control branch is reached, so a second admin can never be asked to rubber-stamp it; and `ticket.%` has no declared polarity, so it parks in **both** directions. Dual control governs only a *well-typed* wrong value. |
| `deletion.post_event_hold_hours` → any number | BP-12 arm 2 stops blocking → paid buyers become erasable | **YES — [V] `{"status":"parked"}`**, and **shortening parks while lengthening executes** | **YES — FIXED THIS TRAIN.** `deletion.%` joined the prefix set, the key is hours-typed (`"720 hours"` is refused as `bad_value` — that spelling belongs to `ticket.expiry_grace`), and the append-only cast-poisoning defect that could **silently stop the deletion machine forever** — one bad historical version, permanently, for every identity — is closed by moving the config read into a subquery. Residual risk is one of **ordering**, not quorum. |
| `feature.native_issuance_enabled` → true/false | dark ↔ live | **NO — [V] `{"status":"ok"}`, executes immediately** | **YES.** A kill switch that needs a quorum is not a kill switch. It is also *last* in the ordering above, so at the moment it is flipped every other clause has already been satisfied. It is also the in-band step 1 of the §13 compromise procedure, deliberately without quorum: stopping the bleeding must not need two people. |
| `inventory.hold_ttl_interval` **and** `inventory.per_user_active_hold_max` | nothing holdable → holdable | **NO — [V] both `{"status":"ok"}`** | **YES.** Both fail closed while unset, both are self-announcing, neither enables unbuilt logic, and it takes **two** changes, not one. |
| `UPDATE kernel.organization SET connect_transfers_active = true` (direct SQL, or `sync_org_connect_state` under a leaked `service_role` key) | `payout_not_ready` → passing, permanently, per org, unaudited | **n/a — not a config key, so no quorum exists** | **NO — hazard, unchanged.** A leaked key can turn selling on for an organization Stripe has disabled, making the platform merchant of record for tickets it cannot settle (H6 A4[4d]); the same key can read every org's full `acct_` id. The RT-A-5 guard blocks only the *unbound* case. The no-direct-SQL policy is the only control, and that is a person remembering. |
| PostgREST exposed schemas `+= venue, catalog` | server-only → **`venue.create_primary_checkout` (granted to `authenticated`) directly client-callable** | **n/a — a dashboard text field: not in git, not in a PR, not covered by any migration guard** | **NO — hazard, though a reasonable operational control.** It is the **outermost gate on the entire primary rail.** It must be a named, ordered, two-person runbook step, and it must come after 093 applies. |
| `insert into kernel.signing_key …` as `postgres` | SALEABLE's signing gate **and** ticket issuance, in one statement | **n/a — superuser; nothing in Postgres implements a two-person rule here and nothing can** | **ACCEPTED OPERATIONAL RISK** (H7 Gap 1/Gap 2; ADV-1/2/7/8 all PROVED it). Superuser access *is* the deploy path and there is one holder. Compensating control: the runbook §9.3 five-column daily invariant query, expected exactly `total_keys=1 \| scoped_keys=0 \| active_global=1 \| bootstrap_fpr=<recorded> \| max_not_after=null`. **Arming that as a real scheduled job with an alert destination is a LAUNCH BLOCKER even though the gap it covers is not — a monitor that exists only in a runbook is not a control.** |
| **Deploying `payout-execute`** | the whole PAYABLE gate, in one act | **n/a — one deploy, no quorum** | **NO — hazard, and NEW this train.** H4 D-4 rated post-payout loss acceptable **because no executor existed**; that mitigation ends the moment this ships. G5 must be signed first and the receivable or reserve object built. H8 §9 says the same thing in the author's own words: *"Deploying this without the receivable object is not safe."* |

**Is any destructive single-admin config key left? No — none on the activation path.** Of the fifteen
single-admin keys not argued above, only `door.implicit_freeze_offset_interval`,
`door.manifest_ttl_interval`, `door.manifest_early_open_window` and `door.max_override_interval` touch
custody semantics, and they have **no live consumer**: `feature.native_scanning_enabled` is `false`,
the 086 door rail is unbuilt and no manifest has ever existed. `notify.*`, `resale.*`, `retention.*`
and `crm_export.*` cross no money or identity boundary. **The surviving single-flip hazards are all
non-config:** direct SQL on `connect_transfers_active`, the PostgREST exposure field, a superuser
signing-key insert, and the `payout-execute` deploy.

---

**Nothing in this document has been authorised, authored, applied, deployed or committed. It records
what is true at the repo tip and in production, verified on a local, disposable rehearsal database.**
