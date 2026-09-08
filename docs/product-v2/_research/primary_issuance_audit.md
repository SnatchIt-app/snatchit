# PRIMARY CHECKOUT → PAYMENT → TICKET ISSUANCE — CHAIN AUDIT

**Agent I** · branch `feature/venue-native-and-product-v2` · 2026-09-02
**Scope:** what is required to make the primary issuance journey work **without activating the native
payout/settlement rail**. Read-only audit against shipped bytes. Every claim carries a `file:line`.

**Deployed-state baseline** (`docs/release/PHASE2_DEPLOYMENT_RECORD_20260902.md:1-49`):
migrations 076–092 **are applied to production** (ledger 107). All 5 feature flags false.
PostgREST exposed schemas = `public, graphql_public, kernel` — **`venue` is NOT exposed**
(`docs/release/PHASE2_DEPLOYMENT_RECORD_20260902.md:25-27`). Zero native money rows.

---

## 1. CHAIN TABLE

| # | STEP | EXISTS? | ARTIFACT (file:line) | CONTRACT REF | GAP | RISK |
|---|---|---|---|---|---|---|
| 1a | Buyer reservation | **YES (dark)** | `supabase/migrations/081_venue_inventory.sql:527-666` `venue.reserve_primary_inventory` | RPC §5.3 | Flag gate `feature.native_issuance_enabled` refuses before any counter mutation (`081:581-587`). Two config keys it reads are **unseeded and uncreatable** — see 8a. | **BLOCKER** |
| 1b | Oversell safety | **YES** | counter CHECK `081:75-77`; `FOR UPDATE` choke-point `081:643-647`; AO movement ledger UNIQUE `081:130` | schema §3.2/§3.3.1 (C27) | Sharding **deferred by design** — `create_inventory_batch` refuses `shard_count>0` (`081:14-17`). Aggregate counter is fully oversell-safe; hot-row contention is the only cost. | LOW |
| 1c | Hold TTL | **YES (unset)** | `081:628-640` reads `inventory.hold_ttl_interval`; refuses `hold_ttl_unset` if absent | RPC §5.3 | Key **never seeded** (see 8a). | **BLOCKER** |
| 1d | Per-user hold cap | **YES (fails to zero)** | advisory xact lock `081:613`; `coalesce(cap,0)` `081:615-626` | C5 / AUTHZ-M8 | Key `inventory.per_user_active_hold_max` never seeded ⇒ cap = 0 ⇒ **every reserve refuses `hold_cap_exceeded`**. | **BLOCKER** |
| 1e | Hold expiry sweep | **YES, ARMED** | `venue.sweep_expired_inventory_holds` `081:852-893`; cron `sweep-expired-inventory-holds */2` `081:1114-1123` | RPC §20.3.3 (G-24) | None. `FOR UPDATE SKIP LOCKED` + per-row subtransaction; single-writer preserved via `release_inventory_hold` (`081:878`). Load-bearing: `held` is a stored counter and only this sweep returns it (`081:847-851`). | LOW |
| 1f | Staff hold | **YES (dark)** | `venue.create_inventory_hold` `081:672-758` | RPC §5.4 | No F-1 deletion gate and **no per-user cap** on this arm (staff-authority only, `081:721-725`). | LOW |
| 2 | Checkout creation | **YES (dark)** | `venue.create_primary_checkout` `082:305-460`; writes `venue."order"` `082:74-94` + `venue.order_item` `082:164-173` | RPC §6.1 / EDGE §3.1 | Returns `{status, order_id, total_minor, currency}` (`082:457`). `source` is **hard-coded `'web'`** (E-39, `082:428-439`) — `app`/`door`/`promoter_link` unreachable. **No order→hold linkage is persisted**, forcing a heuristic in finalize (E-58). | MED |
| 2b | Checkout authority | **YES** | `auth.uid()` only, no buyer parameter (`082:329-331`); F-1 pending + ERASED refusals fire first (`082:345-351`) | dsm §3.2 F-1 / E-23 | None. | LOW |
| 2c | Checkout price authority | **YES** | single server snapshot per item, carried forward (`082:399-425`) | §6.1 | None — `total_minor` and line items provably cannot diverge. | LOW |
| 3a | `primary-checkout` edge | **NO — DOES NOT EXIST** | `supabase/functions/` contains 11 functions; no `primary-checkout` | `PHASE_2_EDGE_FUNCTION_SPEC.md:355-397` | Entire artifact missing. Must mint PI (`total_minor`, `usd`, `automatic_payment_methods`, metadata `{rail:'native_primary', order_id, buyer_id, org_id, session_id}`), get-or-create Customer + ephemeral key, PI idempotency key `pi_native_${order_id}_${total}_c${customerId}` with `_r${n}` salt (`EDGE_SPEC:371-381`). | **BLOCKER** |
| 3b | Money-in row (`public.payments`) | **STRUCTURALLY IMPOSSIBLE** | `supabase/migrations/000_baseline_schema.sql:971-1002` | `EDGE_SPEC:373` ("the new `order_id` linkage column") | `listing_id uuid **not null** references public.listings(id)` (`000:973`), `seller_id **not null**` (`000:975`), `mode check in ('buy_now','auction')` (`000:995`), and partial UNIQUE `idx_payments_one_success_per_listing on (listing_id) where status='succeeded'` (`003_payment_integrity.sql:52-54`). **The `order_id` column the spec assumes does not exist in any migration.** A native-primary payments row cannot be inserted. | **BLOCKER — #1** |
| 3c | `stripe-webhook` native branch | **NO** | `supabase/functions/stripe-webhook/index.ts:261-500` | `EDGE_SPEC:1196-1261` | Deployed `payment_intent.succeeded` claims `payments` by PI id (`index.ts:267-273`) then dispatches on `metadata.mode` ∈ {buy_now, auction}; **anything else returns non-2xx `unknown_mode`** (`index.ts:389-397`) — a native PI hitting the live webhook today would loop Stripe retries for 3 days. Native branch must discriminate on `metadata.rail` and leave the legacy arms byte-identical (`EDGE_SPEC:1206-1207`). | **BLOCKER** |
| 3d | Webhook replay guard | **YES, REUSABLE** | claim/complete/fail lease `index.ts:165-243` (migrations 064/069) | `EDGE_SPEC:1202-1204` | None — the native branch inherits it unchanged. | LOW |
| 4a | Finalization | **YES (dark)** | `venue.finalize_primary_order` `085_kernel_money_native.sql:1881-2082`; `service_role` only (`085:2148`) | RPC §6.3, SSCAS #1 | Requires a `public.payments` row: succeeded, buyer-matched, covering the order total, refund-free (`085:1919-1939`). Blocked by 3b. | **BLOCKER (via 3b)** |
| 4b | Mint engine | **YES (dark, doubly)** | `kernel.issue_ticket_atoms` `083_kernel_credential_infrastructure.sql:440-596` | RPC §7.1 | Flag gate `083:494-501`; **active signing key required or fail-closed** `083:514-530`. | **BLOCKER (via 5a)** |
| 4c | Custody ledger | **YES** | `kernel.ticket_ownership_log` sequence 1, `from NULL`, `cause='issue'` (`083:563-567`); head-is-ledger-tail trigger `079:194` | schema §1.6 | None. | LOW |
| 4d | Credential version | **YES** | atoms minted `credential_version = 0`, `signing_key_id` pinned (`083:557-559`) | §7.1 / C33 | None. No secret is ever written (`083:437`). | LOW |
| 4e | Inventory conversion | **YES** | `held -= live-backed` BEFORE `sold += q`, same txn (`085:2018-2043` → `083:570-573`) | E-40 / E-47(b) | Batch attribution is a **heuristic** — 082 persists no hold linkage, so finalize picks the buyer's most recent active hold for the tt/session (`085:1981-1998`, `085:2006-2013`). Correct for single-batch tiers; ambiguous when one ticket_type has multiple batches (e.g. presale + public_sale). | **MED** |
| 4f | Notifications on issuance | **NO** | `finalize_primary_order` calls **no** `notify.emit_event` (`085:1881-2082`) | NOTIF spec | `purchase_confirmed` is emitted only by the **market** rail (`088:1340`). `ticket_ready` and `purchase_failed` templates exist (`092:240-242`) with **zero emitters anywhere**. `ownership_changed` is emitted by 088 only — the primary mint emits nothing. Buyer gets silence. | **MED** |
| 5a | Signing keys | **PARKED — CANNOT BE CREATED** | table `083:49-71`; `kernel.provision_signing_key` **raises unconditionally** `083:375-384`; `rotate_signing_key` likewise `083:385-394` | PFA-18A | The dual-control mechanism for credential lifecycle is unratified; `kernel.approval_request`'s closed sets are money-only. **No sanctioned path can activate a key**, so `issue_ticket_atoms` and `finalize_primary_order` both fail closed. | **BLOCKER — #2** |
| 5b | `credential-sign` edge | **NO** | absent from `supabase/functions/` | `EDGE_SPEC:399-438` | Needed for the **scannable** QR token only. | LOW (for issuance) |
| 5c | Ticket **display** | **YES, ALREADY REACHABLE** | `grant select on kernel.tickets to authenticated` `079:735`; `kernel_tickets_sel_owner` `079:738-741`; `kernel` schema **exposed in prod** | RN §4.4 | None. | — |
| 6 | Payout on finalize | **NONE — BY DESIGN** | `finalize_primary_order` writes no `kernel.payout` row; the only writers are `close_settlement` (`087:341`) / native-sale / `pay_promoter_commission` / `request_org_payout` (`MONEY_AUTHORITY_SPEC:60`) | §10.2 | None — this is the separability the launch depends on. See §2. | — |
| 7a | Refund (execute) | **PARTIAL** | `kernel.refund_primary_order` `085:457-628`, platform-direct or dual-control-delegated (`085:497-520`) | §11.4 / PFA-23 | Creates a `kernel.refund` row; the **Stripe call lives in a `refund-execute` edge that does not exist** (`PHASE2_RELEASE_READINESS_REPORT.md:150`). Refund rows would sit `pending` forever. | **HIGH** |
| 7b | Refund (buyer/org request) | **YES, DEAD** | `kernel.request_order_refund` `085:850-1088` | §6.1 | Every tier operand is a NULL-seeded key (`078:1544-1551`) ⇒ the tier ladder authorizes nothing. | MED |
| 7c | Deletion — pending arm | **YES, TRAP** | `kernel.deletion_blockers_orders` `082:656-665` | BP-12 | **Any** `pending` order blocks account deletion. A pending order is cleared only by `venue.cancel_pending_order` (`082:478-523`), which only the webhook calls on a *terminal* PI failure. An abandoned checkout (user closes the sheet, PI never terminal) = permanent deletion block. | **HIGH** |
| 7d | Deletion — paid arm | **YES, TRAP** | `kernel.deletion_blockers_money` BP-12 arm 2 `085:262-284` | PFA-22 | With any `paid`/`partially_refunded` order present and `deletion.refund_possible_window_hours` NULL (`085:2188-2190`), deletion is **blocked outright**. The **first paid primary order permanently blocks that buyer's account deletion** until the owner seeds the key. Privacy-request-facing. | **HIGH** |
| 7e | Transfer / resale of a primary ticket | **DARK** | market rail `088_market_native_rail.sql`, gated by `feature.native_resale_enabled` (`078:1524`, false) | Gate M | A primary-issued ticket cannot be transferred or resold. Acceptable for an issuance-only launch; must be stated in product copy. | MED |
| 8a | Config: inventory keys | **UNSEEDED + UNCREATABLE** | read at `081:617` / `081:633` / `081:729`; **absent** from the 41-key seed block `078:1520-1580`; `catalog.set_platform_config` raises `unknown_key` for any key with no existing row (`078:1096-1103`) | E-28 (`docs/architecture/_governance/POST_FREEZE_AMENDMENTS.md:1620-1638`) | **A new migration is mandatory** — the sanctioned config RPC provably cannot create these rows. Not tracked in the readiness report's config matrix. | **BLOCKER — #3** |
| 8b | Config: issuance flag | **SEEDED FALSE** | `078:1522` | Gate P | Owner flip required. | — |
| 8c | Exposure | **MISSING** | prod `db_schema = public, graphql_public, kernel` (`PHASE2_DEPLOYMENT_RECORD_20260902.md:25-27`); `venue` grants exist (`076:78`) but PostgREST rejects with `PGRST106` | — | `venue.reserve_primary_inventory` and `venue.create_primary_checkout` are granted to `authenticated` (`081:1088-1097`, `082:684-689`) but unreachable. Adding `venue` to the exposed list is required — an edge wrapper does not avoid this, since it still transits PostgREST. | **BLOCKER** |
| 9 | Client (RN) | **NONE** | zero references to `primary-checkout` / `create_primary_checkout` / `reserve_primary_inventory` in any `.ts`/`.tsx` | RN §4.3a (`PHASE_2_REACT_NATIVE_PRODUCT_SPEC.md`) | Event page tier rows, hold timer, primary checkout screen, "Your ticket is ready", My Tickets detail — all unbuilt. | **BLOCKER** |

---

## 2. MONEY BOUNDARY — THE DEFINITIVE ANSWER

> **Question:** does taking primary payment require activating native settlement/payout?
> **Answer: NO. Payment collection can be fully activated with settlement and payout execution left dark.**

### Why this is structurally true, not merely convenient

1. **Finalization mints no payout.** `venue.finalize_primary_order` (`085:1881-2082`) writes exactly:
   `venue."order".status='paid'`, `kernel.payment_native`, `kernel.tickets`, `kernel.ticket_ownership_log`,
   `venue.inventory_batch`, `venue.inventory_movement`, and calls the inert attribution stub
   (`085:2065` → `venue.resolve_order_attribution`, a no-op until 090). **It touches `kernel.payout` nowhere.**

2. **Payout rows have exactly four writers, none of which is on the checkout path.**
   `kernel.payout` is written only by `kernel.close_settlement`, the native-sale path,
   `kernel.pay_promoter_commission`, and `request_org_payout`
   (`PHASE_2_MONEY_AUTHORITY_SPEC.md:60`). The primary insert is at `087:338-341`, inside `close_settlement`.

3. **Settlement is human-triggered, never scheduled.** `venue.open_settlement` (`087:227-270`) takes a
   caller-supplied period and requires `venue_finance`/`org_finance`/`org_owner`; `kernel.close_settlement`
   (`087:289`) is the irreversible act that mints the payout. 087's cron entries are exports and CRM only
   (`087:1518-1531`) — **no cron creates or closes a settlement.** Leaving the rail dark = simply never
   calling two RPCs.

4. **The charge lands on the platform's own Stripe balance.** The frozen PI contract
   (`EDGE_SPEC:371-374`) specifies amount, currency, `automatic_payment_methods` and metadata — and carries
   **no `on_behalf_of`, no `transfer_data`, no `application_fee_amount`**. The money spec confirms the
   topology by implication: *"No reserve. No clawback. No instant payout… refunds are funded from the Stripe
   balance via `refunds.create` on the original charge, and payouts remain settlement-cadenced"*
   (`PHASE_2_MONEY_AUTHORITY_SPEC.md:1488-1490`). Venue money moves later, as a separate transfer.

5. **Refunds do not depend on the payout rail.** `kernel.refund_primary_order` (`085:457-628`) reads the
   `payment_native` link and voids atoms; it never reads or writes `kernel.payout`. Refund funding is a
   `refunds.create` against the original charge.

### What accumulates as un-settled state (name every object)

**Grows with every paid order:**

| Object | What accumulates | Citation |
|---|---|---|
| Stripe **platform balance** | the full gross of every primary sale, undistributed | `MONEY:1488-1490` |
| `public.payments` | one `succeeded` row per order (once 3b is fixed) | `000:971-1002` |
| `kernel.payment_native` | order↔payment link, AO | `085:40-66` |
| `venue."order"` | `status='paid'`, immutable total | `082:74-94` |
| `venue.order_item` | frozen price snapshot, IMM-after-issuance | `082:164-202` |
| `venue.inventory_batch.sold` | monotonically rising | `083:572` |
| `venue.inventory_movement` | one `issue` row per item | `083:575-577` |
| `kernel.tickets` | N atoms, `credential_version=0` | `083:557-559` |
| `kernel.ticket_ownership_log` | N sequence-1 custody rows | `083:563-567` |

**Stays empty (this is the dark rail):** `venue.settlement`, `venue.settlement_line`, `kernel.payout`,
`kernel.approval_request` (payout arm), `kernel.refund` (unless a refund is issued).

### The three consequences the owner must accept before flipping the flag

- **Venues are owed money with no ledger of it.** Until a settlement is opened, `venue.settlement` is empty
  and there is no venue-facing "you are owed $X" surface. The org's only view is the order list
  (`venue_order_sel_org`, `082:143-148`). This is an operational/communications obligation, not a code gap.
- **Refunds can be recorded but not executed.** `refund-execute` does not exist
  (`PHASE2_RELEASE_READINESS_REPORT.md:150`). A refund row would sit `pending` with no Stripe call.
  **Recommendation: do not accept primary payment until a refund path exists**, even a manual
  Stripe-dashboard SOP reconciled by `kernel.mark_refund_state` (`085:1737`, service_role, already granted).
- **Chargebacks land unowned.** `kernel.record_dispute_native` / the dispute webhook branch is 088-side and
  unbuilt; a native-primary dispute would hit the legacy `charge.dispute.created` arm
  (`stripe-webhook/index.ts:566`) which looks for a P2P `transfers` row and finds none.

---

## 3. IDEMPOTENCY AND EXACTLY-ONCE

### Against double payment

| # | Guard | Artifact | Protects |
|---|---|---|---|
| I1 | `venue."order"` UNIQUE `(buyer_id, command_idempotency_key)` | `082:93` | two checkouts from one client command |
| I2 | Checkout replay short-circuit (pre-insert read) | `082:355-361` | fast path, returns the original order |
| I3 | Checkout race arm (`unique_violation` → return winner) | `082:447-455` | concurrent double-submit; never surfaces a raw 23505 |
| I4 | Stripe PI idempotency key `pi_native_${order_id}_${total}_c${customerId}` + `_r${n}` salt | `EDGE_SPEC:379-381` | **not yet built** — a double-tap must return the same PI/clientSecret |
| I5 | Webhook event lease `claim → complete/fail` | `stripe-webhook/index.ts:165-243` (migrations 064/069) | Stripe redelivery at the event grain |
| I6 | `payments` claim UPDATE with `.neq('status','succeeded')` | `stripe-webhook/index.ts:267-273` | double-claim of one PI (legacy idiom the native branch should reuse) |

### Against double issuance

| # | Guard | Artifact | Protects |
|---|---|---|---|
| E1 | Order-state short-circuit — `status='paid'` returns the existing atom set | `085:1965-1973` | webhook redelivery after a successful finalize |
| E2 | `unique_violation` arm re-reads and returns the winner's atoms | `085:2068-2080` | concurrent redelivery mid-flight |
| E3 | **Mint idempotency anchor**: `ticket_ownership_log (cause='issue', cause_ref=order_item.id)` | `083:507-512`, replay arm `083:588-593` | the exactly-once property; per-item, so a partial retry resumes correctly |
| E4 | Per-item mint command key `p_command_key || ':' || order_item.id` | `085:2051` | distinct anchors per line item |
| E5 | Per-atom log command key `p_command_key || ':' || atom_id` | `083:566` | `ticket_ownership_log` uniqueness |
| E6 | `kernel.payment_native` UNIQUE `(payment_id)` | `085:56` | one order per payment; the AO trigger `085:64-66` blocks mutation |
| E7 | `venue.inventory_movement` UNIQUE `(cause, cause_ref, batch_id, movement_kind)` | `081:130` | double-logging a hold/issue |
| E8 | `venue.inventory_hold` UNIQUE `(identity_id, command_idempotency_key)` | `081:157`, replay `081:567-576` | double reservation |
| E9 | `kernel.refund` UNIQUE `(idempotency_key)` + pre-check | `085:93`, `085:483-487` | double refund |

### SSCAS lock ladder (finalize)

| Rank | Lock | Artifact | Purpose |
|---|---|---|---|
| 1 | `catalog.event_session … FOR UPDATE` | `085:1943`; re-taken by the mint `083:537` | serializes the session-scoped `serial_no` draw; excludes `update_event_session`'s schedule guard (E-46(a)) |
| 3 | `venue."order" … FOR UPDATE` | `085:1964` | state re-check under lock; replay short-circuit |
| 3.5 | **Deterministic batch pre-lock, ascending by `batch_id`** | `085:1985-1998` | two concurrent finalizes over an overlapping batch set can never AB-BA deadlock |
| 4 | `venue.inventory_hold … FOR UPDATE` (per batch, ordered by `hold_id`) | `085:2023-2029` | E-40 — only live holds back the `held` decrement |
| 4b | `venue.inventory_batch … FOR UPDATE` inside the mint | `083:545` | C27 choke-point; batch/ctx coherence check `083:549-551` |

**Oversell backstop of last resort:** the table CHECK `held >= 0 and sold >= 0 and held + sold <= capacity`
(`081:75-77`). Every arithmetic path is preceded by a clean-token check (`085:2037-2039`, `081:645-647`)
so the CHECK should never be the thing that fires — but it is unbypassable if one does.

### Replay behaviour, end to end

A redelivered `payment_intent.succeeded` after a successful finalize: the lease returns
`already_processed` (`index.ts:203`) → if it still ran, the order is `paid` and E1 returns the original
atom array with `status='idempotency_replay'` → if it raced instead, E2 catches → if it somehow reached the
mint, E3's anchor returns the original atoms without minting. **Four independent layers.**

---

## 4. MINIMUM VIABLE PRIMARY ISSUANCE

The smallest artifact set that makes the journey work with settlement/payout dark, scanning dark,
and resale dark. Ordered by dependency.

### A. Migration work (2 migrations)

| # | Artifact | Why | Reference |
|---|---|---|---|
| A1 | **`public.payments` native-primary shape.** Add `order_id uuid references venue."order"(order_id)`; make `listing_id` and `seller_id` nullable; widen `mode` to include a native member; scope `idx_payments_one_success_per_listing` to `where status='succeeded' and listing_id is not null`. | **The #1 blocker.** Today no native payments row is insertable, and finalize cannot run without one. | `000:971-1002`, `003:52-54`, `EDGE_SPEC:373`, `085:1919` |
| A2 | **Seed `inventory.hold_ttl_interval` and `inventory.per_user_active_hold_max`.** `set_platform_config` refuses unknown keys, so this *must* be a migration. Suggested: `"10 minutes"` (matches `resale.buy_now_reservation_ttl_minutes = 10`, `078:1574`) and `10`. Owner-owed values. | Without them every reserve refuses `hold_ttl_unset` / `hold_cap_exceeded`. | `081:617,633`; `078:1096-1103`; E-28 `POST_FREEZE_AMENDMENTS.md:1620-1638` |
| A3 | **Signing-key activation path.** Either ratify a credential dual-control mechanism and replace `provision_signing_key`, or land an owner-signed narrow migration that inserts one `global`-scope `kernel.signing_key` row directly. Nothing else can activate a key. | **Blocker #2.** No key ⇒ `issue_ticket_atoms` and `finalize_primary_order` both fail closed. | `083:375-384`, `083:514-530`, `085:1950-1961` |
| A4 | *(strongly recommended, not strictly blocking)* Seed `deletion.refund_possible_window_hours`. | Otherwise the first paid order permanently blocks that buyer's account deletion. | `085:262-284`, `085:2188-2190` |

> A1 touches the frozen `public.*` surface, which package 085 explicitly avoided ("OBS-1: zero changes to
> `public.*`", `085:13-14`). This is a **governance escalation**, not a routine migration — flag it as such.

### B. Edge functions (2)

| # | Artifact | Contract |
|---|---|---|
| B1 | **`primary-checkout`** — `verify_jwt: true`; call `venue.create_primary_checkout`; get-or-create Customer + ephemeral key (reuse `ensureStripeCustomerAndEphemeralKey`, `create-payment-intent/index.ts:136-207`); mint PI for `total_minor` with `metadata.rail='native_primary'`; write the `public.payments` row; 409 on `expected_total_cents` mismatch; rate limit `(5, 60)` fail-closed. | `EDGE_SPEC:355-397` |
| B2 | **`stripe-webhook` native branch** — discriminate on `metadata.rail`, leave every legacy arm byte-identical. `payment_intent.succeeded` + `rail='native_primary'` → `venue.finalize_primary_order(order_id, payment_id, command_key, instrument_fingerprint)`. `payment_intent.payment_failed` on a **terminal** PI → `venue.cancel_pending_order(order_id, 'payment_failed', key)`. **Must also fix the `unknown_mode` arm** (`index.ts:389-397`) so a native PI is not treated as a 3-day retry loop. | `EDGE_SPEC:1206-1221` |

`credential-sign` is **NOT required** — see §5 below.

### C. Config and exposure

| # | Action | Reference |
|---|---|---|
| C1 | Add **`venue`** to PostgREST exposed schemas (`public, graphql_public, kernel, venue`). Grants already exist (`076:78`); PostgREST rejects with `PGRST106` today. | `PHASE2_DEPLOYMENT_RECORD_20260902.md:25-27` |
| C2 | Flip `feature.native_issuance_enabled` → `true` via `catalog.set_platform_config` (platform_admin, reason code required). **Last step, after everything else.** | `078:1522`, `078:1082-1086` |
| C3 | Leave FALSE/NULL: `feature.native_scanning_enabled`, `feature.native_resale_enabled`, `wallet.apple.enabled`, all `payout.*`. | `078:1523-1556` |
| C4 | Stripe: add `payment_intent.succeeded` / `payment_intent.payment_failed` to the existing webhook endpoint (already subscribed for the legacy rail — no routing change needed). | `PHASE2_RELEASE_READINESS_REPORT.md:174-180` |

### D. Client (RN)

| # | Surface | Reference |
|---|---|---|
| D1 | Event page — Official Tickets block: one row per ticket type, price, availability, Buy. | RN §4.3 / §4.2 |
| D2 | Primary Checkout screen — quantity (respect the C5 cap), all-in breakdown, **hold countdown** from the returned `expires_at`, pay button; hold-expired and "only N left" error states. | RN §4.3a; `081:661` returns `expires_at` + `remaining` |
| D3 | Call sequence: `venue.reserve_primary_inventory` → `venue.create_primary_checkout` (or fold both behind the edge) → PaymentSheet with `clientSecret`/`customerId`/`ephemeralKeySecret` → poll `venue."order".status` until `paid`. | `EDGE_SPEC:394-395` (confirmation is **not** synchronous) |
| D4 | My Tickets — read `kernel.tickets` directly (owner policy `079:738-741`, `kernel` already exposed). **No QR yet** — show ticket identity, event, tier, serial. | RN §4.4 |

### E. Explicitly OUT of the minimum set

`credential-sign`, `signing-key-provision`, the door/scan rail (086), Wallet (084), `refund-execute`,
`payout-execute`, settlement RPCs, promoter codes (090), the notify producers for `purchase_confirmed` /
`ticket_ready` (see the §6 risk — recommended, not blocking).

---

## 5. DISPLAYABLE vs SCANNABLE — precise answer

**Can tickets be issued and shown to users without the scanning rail active? YES.**

| Property | What it needs | Status |
|---|---|---|
| **Ticket exists** | `kernel.tickets` row minted by `issue_ticket_atoms` | needs an **active signing key row** (`083:516-530`) — the key is pinned into `tickets.signing_key_id` at mint (`083:559`), so key *infrastructure* is required even for display-only |
| **Ticket displayable** | `select` on `kernel.tickets` under `kernel_tickets_sel_owner` | **already works** — grant `079:735`, policy `079:738-741`, `kernel` schema exposed in prod |
| **Ticket scannable** | `credential-sign` edge (KMS-signs `{atom_id, session_id, credential_version, key_id, issued_at, exp}`) + the door rail + `feature.native_scanning_enabled` | **not built**; `EDGE_SPEC:399-438` |

The door never calls `credential-sign` — it verifies against the public key and
`venue.validate_ticket_online` (`EDGE_SPEC:405-407`, `1469-1473`). So display and scanning are cleanly
separable, and issuance can ship first.

**The nuance that matters:** the signing key is *not* optional. `issue_ticket_atoms` refuses to mint
without one resolving for the event scope, and `provision_signing_key` is parked. So **A3 is required
even for a display-only launch** — you cannot skip the key by skipping the QR. The cheapest honest path
is a single `global`-scope key whose `kms_handle_ref` points at a KMS key that nothing signs with yet.

---

## 6. TEST PLAN

Suites live under `supabase/tests/` (pgTAP; the 076–092 floor is 2 622 assertions). New coverage below;
every flag-dependent test flips `feature.native_issuance_enabled` inside a **rolled-back transaction**,
per the 081 §G precedent.

### T1 — Oversell
1. Batch capacity 10. Reserve 10 in one call → `ok`, `remaining=0`. 11th → `oversell_rejected`.
2. Reserve 6 + 4 by two identities → both `ok`; a 5th unit → `oversell_rejected`.
3. Finalize both orders → `sold=10`, `held=0`, `remaining=0`, exactly 10 atoms.
4. **Direct-write attack:** `update venue.inventory_batch set sold = sold + 1` at capacity → must raise on
   `inventory_batch_oversell_check` (`081:75-77`).
5. Hold expiry returns capacity: reserve 10, run `sweep_expired_inventory_holds` past TTL, assert
   `held=0` and `remaining=10`, and that a second sweep is a no-op (`081:803-805`).

### T2 — Concurrency
1. Two sessions reserve the last unit simultaneously → exactly one `ok`, one `oversell_rejected`
   (proves the `FOR UPDATE` at `081:643-647`).
2. Two concurrent `create_primary_checkout` with the **same** `(buyer, command_key)` → one insert, the
   loser returns `idempotency_replay` and **not** a raw 23505 (`082:447-455`).
3. **Deadlock probe:** two finalizes over batch sets `{A,B}` and `{B,A}` → both complete, neither
   deadlocks (proves the ascending pre-lock `085:1985-1998`).
4. Concurrent `release_inventory_hold` × 2 on one hold → one `ok`, one `noop_replay`; `held` decremented
   exactly once (the pre-fix bug this guards is documented at `081:786-791`).
5. Sweep vs finalize race: expire a hold while a finalize holds it locked → the sweep **skips** it
   (`SKIP LOCKED`, `081:871`) and the finalize converts it; `held` never double-decrements.
6. Same-session, different-batch concurrent mints → no `tickets_session_serial_uq` abort (proves the
   rank-1 session lock, `083:532-537`).

### T3 — Webhook replay
1. Deliver `payment_intent.succeeded` twice with the same event id → second returns `already_processed`
   from the lease (`index.ts:203`); atom count unchanged.
2. Deliver twice with **different** event ids, same PI → second finalize returns
   `status='idempotency_replay'` with the identical `atom_ids` array (`085:1965-1973`).
3. Deliver two concurrently → one `ok`, one `idempotency_replay`; assert `count(kernel.tickets) = Σ qty`.
4. Deliver `payment_intent.succeeded` for a PI whose payment row is already `succeeded` but whose order is
   still `pending` (crash-between simulation) → finalize completes and mints.
5. **Regression on the legacy rail:** replay a `buy_now` and an `auction` PI through the modified webhook
   and assert byte-identical behaviour to the pre-change baseline (`EDGE_SPEC:1207`).
6. Native PI with a malformed/missing `metadata.rail` → must **not** fall into the legacy `unknown_mode`
   3-day retry loop (`index.ts:389-397`).

### T4 — Duplicate issuance
1. Call `issue_ticket_atoms` twice with the same `cause_ref` → second returns `idempotency_replay`,
   `sold` incremented once, `inventory_movement` has one row (`081:130`, `083:507-512`).
2. Call `finalize_primary_order` twice with different `command_key`s on a `paid` order → E1 short-circuit;
   no second `kernel.payment_native` insert (blocked by `payment_native_payment_uq`, `085:56`).
3. Assert every atom has exactly one `ticket_ownership_log` row with `sequence=1, from_identity IS NULL,
   cause='issue'`, and that the custody-head trigger holds (`079:194`).
4. **Multi-batch heuristic (E-58):** one ticket_type with two batches (presale + public_sale); buyer holds
   in the presale batch; finalize → assert the atoms are drawn from the **presale** batch and `sold` moved
   there, not on the public batch (`085:2006-2013`). **This is the test most likely to fail.**
5. Finalize with a payment whose `total < order.total_minor` → `payment_unverified` (`085:1931-1934`).
6. Finalize with a payment belonging to a different buyer → `payment_unverified` (`085:1926-1928`).
7. Finalize against a payment that already carries a refund → `payment_unverified` (`085:1937-1939`).
8. Finalize with no active signing key → `no_active_signing_key`, zero atoms (`085:1959-1961`).

### T5 — Failed payment
1. Terminal `payment_intent.payment_failed` → `venue.cancel_pending_order` → order `cancelled`,
   admin_audit row with actor `…f1` (`082:510-518`).
2. Redeliver → `noop_replay`, no raise (`082:503-505`) — critical, because a raising webhook retries forever.
3. Assert the hold is **not** released by cancel; capacity returns only via the TTL sweep
   (`082:513`). Verify `remaining` recovers on the next tick.
4. `cancel_pending_order` on a `paid` order → `order_not_pending`.
5. Non-terminal failure (e.g. `requires_payment_method` with retries available) must **not** cancel.
6. Buyer abandons after `create_primary_checkout` and never pays → order stays `pending` **forever**;
   assert the T6.1 deletion consequence. *(This is a design gap, not just a test.)*

### T6 — Deletion interaction
1. Buyer with a `pending` order requests deletion → blocked with the BP-12 pending-order reason
   (`082:656-665`). Cancel the order → deletion proceeds.
2. Buyer with a `paid` order and `deletion.refund_possible_window_hours` **NULL** → blocked
   (`085:275-277`). Seed the key to `0` → assert deletion proceeds. Seed to `72` with an order created
   1 h ago → blocked; 100 h ago → proceeds (`085:278-283`).
3. `is_deletion_pending` buyer attempting `reserve_primary_inventory` → `deletion_pending` (`081:560-562`);
   same for `create_primary_checkout` (`082:345-347`).
4. ERASED identity → `identity_erased` on checkout (`082:348-351`) and `finalize_primary_order` refuses
   (`085:1912-1916`). **DELETION_PENDING must still finalize** — mid-flight money completes (`085:1910-1911`).
5. Assert an issued atom blocks deletion via `kernel.deletion_blockers_custody` (`079:706`).

### T7 — Money-boundary conservation (the launch-defining assertion)
After a full green run of T1–T6, assert on the test database:

```sql
select count(*) from kernel.payout;          -- must be 0
select count(*) from venue.settlement;       -- must be 0
select count(*) from venue.settlement_line;  -- must be 0
```

and that `Σ venue."order".total_minor where status='paid'` equals
`Σ kernel.payment_native.amount_minor` equals `Σ public.payments.total` for the native rail.
**This is the structural proof that payment collection ran with the payout rail dark.**

---

## 7. TOP RISKS (ranked)

1. **`public.payments` cannot hold a native-primary row** (`000:973-995`, `003:52-54`). The spec assumes an
   `order_id` column that was never migrated. Fixing it means touching the frozen `public.*` surface that
   085 deliberately did not touch (`085:13-14`) — a governance escalation, not a routine change.
2. **No signing key can be activated** (`083:375-384`). PFA-18A parks provisioning pending a credential
   dual-control mechanism that does not exist. Blocks issuance even for a display-only launch.
3. **Two inventory config keys are unseeded and uncreatable via the sanctioned RPC** (`081:617,633`;
   `078:1096-1103`). Requires a migration; not tracked in the readiness report's config matrix.
4. **First paid order permanently blocks that buyer's account deletion** (`085:275-277`). Privacy-request
   exposure the moment the flag flips. Seed `deletion.refund_possible_window_hours` first.
5. **Abandoned checkouts block deletion forever** (`082:656-665` + `082:478-523`). Nothing cancels a
   `pending` order whose PI never reaches a terminal state. Needs a pending-order TTL sweep — which does
   **not** exist.
6. **Refunds can be recorded but not executed.** `refund-execute` is unbuilt
   (`PHASE2_RELEASE_READINESS_REPORT.md:150`); the buyer/org refund tiers are all NULL-gated
   (`078:1544-1551`). Taking money with no refund path is the largest product/legal risk on this list.
7. **The buyer is notified of nothing.** `finalize_primary_order` emits no `notify` event; `ticket_ready`
   and `purchase_failed` have templates (`092:240-242`) and zero emitters anywhere in the tree.
8. **Batch attribution is heuristic** (E-58, `085:1981-1998`). Correct for one-batch tiers; ambiguous the
   moment a ticket_type carries presale + public_sale batches.
9. **`venue` is not exposed to PostgREST** (`PHASE2_DEPLOYMENT_RECORD_20260902.md:25-27`) — a one-line
   setting, but it silently makes every checkout RPC unreachable and is easy to miss.
10. **A native PI reaching today's deployed webhook loops Stripe retries for three days**
    (`stripe-webhook/index.ts:389-397`). Any test PI minted before B2 ships will do this.
11. **`order.source` is hard-coded `'web'`** (E-39, `082:439`) — app-vs-door-vs-promoter attribution is
    unrecoverable for every order issued before it is fixed.
