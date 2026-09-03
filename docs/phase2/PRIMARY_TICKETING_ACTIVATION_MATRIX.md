# Primary ticketing — activation matrix

**What this is.** For each step of the venue-direct primary rail: what must exist in the database,
what must be configured, which edge function must be deployed, what Stripe state is required, what
signing state is required, which owner ruling governs it, and whether it is ready **today**.

**Status of the system this describes.** Migration 093 is **authored and NOT applied to production**
(production ledger is 107 = migrations 000–092; the repo holds 108 files). No rail is activated. No
edge for this feature is deployed. This matrix describes the repo tip as replayed locally, and marks
separately where production differs.

**Evidence.** Every readiness verdict was checked against a live replay —
`./scripts/rehearsal_reset.sh snatchit_rehears_gates`, **108/108 migrations,
`GATE-2 tables=27 functions=70 policies=37 triggers=24`** matching the CI baseline — not inherited
from a document. Rows marked **[V]** carry an executed result. Analysis and the gate predicates are
in `docs/phase2/_impl/G6_activation_gates.md`.

**Companion document.** `docs/phase2/FINAL_ACTIVATION_BLOCKER_RULINGS.md` (DRAFT, unsigned) rules on
the three owner *values* still outstanding — ticket expiry, maturity interval, the signing ceremony —
plus `deletion.refund_possible_window_hours`. All four appear below. Supplying them is **necessary
and not sufficient**: this matrix additionally names four undeployed edge functions, refund
executability under A9, and an absent payout executor.

**How to read "Currently ready?".** YES means the step works end to end today on an applied 093 with
the prerequisites in its own row satisfied. NO means it does not. There is no third value. Every NO
lists **every** blocker, not the first one, so the full critical path is visible.

---

## The matrix

### 1 · Venue setup

| | |
|---|---|
| **Required DB** | `kernel.organization` (`status in ('approved','active')`), `kernel.org_member`, `catalog.venue` (approved via `catalog.approve_venue`). All present in 077/078. `kernel.set_org_connect_ref` hardened at `093:2717`; `kernel.set_org_payout_destination` hardened at `093:2862`. Connect mirror columns `connect_transfers_active` / `connect_state_synced_at` / `connect_pending_ref` added by 093. **[V] all three exist.** |
| **Required config** | none |
| **Required edge** | `connect-onboarding` — **authored, NOT DEPLOYED** (`supabase/functions/connect-onboarding/index.ts`; E1) |
| **Required Stripe state** | Express account, US, `business_type=company`, `transfers` capability requested, metadata binding the org id (A7) |
| **Required signing state** | none |
| **Required owner ruling** | A6, A7, A9 |
| **Currently ready?** | **NO** |
| **Why not?** | (a) `connect-onboarding` is not deployed, and it is the only server-side minter of an org connected account — A7 forbids a caller-supplied `acct_`, so there is no other path. (b) 093 is not applied to production, so the hardened binders and the mirror columns do not exist there. (c) `kernel.set_org_payout_destination` has **[V] no non-comment caller anywhere in the repo** — every hit is a definition, a grant array, a comment, a rollback or a pgTAP assertion — so an org's payout destination can be bound once and then never re-pointed by any shipped code path. (d) PostgREST must expose `kernel` (it does in production) for the org verbs to be client-reachable. |

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
| **Why not?** | — **[V] The full chain org → venue → event → session → ticket_type → inventory_batch was built with `select count(*) from kernel.signing_key` = 0, `stripe_connect_account_ref IS NULL`, and every owner config key at `'null'::jsonb`.** This is the one gate that is complete and correct. Caveat, not a blocker: `catalog.event_session.ends_at` is nullable and `catalog.create_event_session` requires only `starts_at` (`078:805-807`); a session created without `ends_at` will later be unswept by the expiry sweep (`079:490-492`, fails open) and unpayable by the maturity gate (`maturity_instant_unknown`, fails closed). |

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
| **Why not?** | — but with a **finding, not a blocker**: **[V] `publish_event(event,'on_sale')` succeeded with zero Stripe binding, zero config and zero signing keys.** A8's SALEABLE row reads *"event may transition to `on_sale` **and** be purchased"* and marks it "Requires Connect readiness: **Yes**". Only the purchase half is enforced (row 5). 093's OUT table declined to gate the transition, on the ground that `announced` is harmless marketing state — reasoning that does not extend to `on_sale`. **Consequence:** an event can display as on sale while every purchase refuses. Fail-closed on money, fail-open on the storefront. The client must therefore treat `payout_not_ready` / `service_fee_unset` as a first-class "not on sale yet" state (`G5 §5.4` specifies exactly that copy). **Owner item — see G6 §5.4 for the two options.** |

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
| **Why not?** | (a) `feature.native_issuance_enabled` is **[V] `false`** (`078:1522`) — `venue.reserve_primary_inventory` raises `precondition_failed: feature_disabled` at `081:583`, and `venue.create_inventory_hold` again at `081:703`. **[V] observed.** (b) `inventory.per_user_active_hold_max` is **[V] `null`**; `081:615-626` collapses the cap to **0**, so `0 + 1 > 0` refuses the first hold of every user — **[V] `precondition_failed: hold_cap_exceeded`.** (c) `inventory.hold_ttl_interval` is **[V] `null`**; `081:630-639` raises `hold_ttl_unset` with no default and no coalesce. (d) 093 is not applied to production, so all three key **rows** are absent there and `catalog.set_platform_config` raises `unknown_key` for any key not already present (`078:1103`) — configuration cannot create them. (e) `catalog` and `venue` are **not** exposed over PostgREST in production (`docs/release/PHASE2_DEPLOYMENT_RECORD_20260902.md:25`; `venue` returns `PGRST106`), so no client can call the RPC. **[V] With (a)–(c) removed, the reserve succeeded and returned a live hold.** |

### 5 · Primary sale

| | |
|---|---|
| **Required DB** | `venue.create_primary_checkout` **as replaced by 093** (`093:2325`) — carrying the A8 readiness gate at `093:2458` and the A5 fee gate at `093:2482`/`:2488`; `venue."order"`, `venue.order_item` (082); the `public.payments` relaxation + rail-pairing CHECK (093 item 1) |
| **Required config** | everything in row 4, **plus** `fee.buyer_service_bps` (**[V] `null`**) |
| **Required edge** | `primary-checkout` — **authored, NOT DEPLOYED** (E2). It is the only thing that mints a PaymentIntent. |
| **Required Stripe state** | `stripe_connect_account_ref` bound **AND** `connect_transfers_active` = true; platform Stripe account live (A2: separate charges and transfers, no `transfer_data`, no `on_behalf_of`, no `application_fee_amount`, no `Stripe-Account`) |
| **Required signing state** | **NOT CHECKED BY THE GATE — and it should be.** See "Why not" (f). |
| **Required owner ruling** | A1, A2, A5, A8, **A9** |
| **Currently ready?** | **NO** |
| **Why not?** | (a) 093 is not applied to production, so the A8 gate does not exist there at all. (b) All of row 4's blockers apply — the RPC requires live holds it cannot get. (c) `payout_not_ready` (`093:2458`): `connect_transfers_active` is written **only** by `kernel.sync_org_connect_state` (`093:1966`, service_role only), whose only caller is the `account.updated` organization arm of `stripe-webhook` — **not deployed**. The flag is a self-healing gate with **no writer**. **[V] observed as `precondition_failed: payout_not_ready`.** (d) `fee.buyer_service_bps` is **[V] `null`** → `precondition_failed: service_fee_unset` (`093:2482`). **[V] observed.** (e) `primary-checkout` is not deployed, so no PaymentIntent can be minted even if the RPC returns ok. (f) **The gate does not require an active signing key. [V] An order was created with zero signing keys in the database.** The mint's key check lives at `venue.finalize_primary_order` — i.e. inside the webhook, **after** the charge. With the checkout edge deployed this is: buyer charged, `no_active_signing_key`, no ticket. **G6 finding F-2.** (g) **Ruling A9 makes refund executability a hard precondition of selling and it is not satisfied** — see row 8; A9's approval text is *"selling may not be activated until a refund recorded by the database results in money actually returning to the buyer."* (h) No tax model exists anywhere: **[V] zero config keys and zero functions match `%tax%`**, and no order or payment column carries tax. **[V] With (a)–(d) removed, the RPC returned `{"status":"ok","order_id":…}` and a `pending` order with `total_minor=5000`.** |

### 6 · Payment confirmation

| | |
|---|---|
| **Required DB** | `public.payments` accepting a native row (093 item 1); `kernel.payment_native`; `venue.finalize_primary_order` (`085:1919`), service_role only |
| **Required config** | as row 5 |
| **Required edge** | `stripe-webhook` **with the native branch** — `native.ts` authored, `index.ts` branches authored, **NOT DEPLOYED**. Production runs the pre-native build (`docs/release/PHASE2_DEPLOYMENT_RECORD_20260902.md:26-29`: *"No other function touched."*) |
| **Required Stripe state** | live webhook endpoint delivering `payment_intent.succeeded` with `metadata.rail = native_primary`; `stripe_livemode = true` |
| **Required signing state** | **an active, in-window `kernel.signing_key` resolvable for the event scope** (`083:514-530`, resolver `085:1948-1960`) |
| **Required owner ruling** | A2, A3, B, E |
| **Currently ready?** | **NO** |
| **Why not?** | (a) The native branch is not deployed. On the deployed build a `native_primary` PaymentIntent falls through to `unknown_mode` → **HTTP 500, retried ~3 days, buyer charged, no ticket** (E3 §1). (b) **[V] Zero signing keys exist** and the 093 bootstrap row is **deliberately commented out** (`093:3656-3663`) pending the KMS ceremony — `finalize_primary_order` raises `precondition_failed: no_active_signing_key`. **[V] observed.** (c) 093 is not applied, so `public.payments` still carries the two `NOT NULL` constraints that make a native row unstorable (`000_baseline_schema.sql:973`), and `venue.finalize_primary_order` raises if no payments row is found (`085:1919-1934`). (d) Row 5's blockers all precede this one. **[V] With one active global signing key row inserted, `finalize_primary_order` returned `{"status":"ok","atom_ids":[…],"order_status":"paid"}`** — so this step is one ceremony and one deployment away, and nothing else. |

### 7 · Ticket issuance

| | |
|---|---|
| **Required DB** | `kernel.tickets` (079), `kernel.issue_ticket_atoms` (083), `kernel.signing_key` (083). **[V] `kernel.tickets.signing_key_id` is `is_nullable = NO`**, with `ON DELETE RESTRICT` to `kernel.signing_key`. |
| **Required config** | `feature.native_issuance_enabled` = true (**[V] false**); `ticket.expiry_grace` set, as a **jsonb string** (**[V] null**) |
| **Required edge** | `stripe-webhook` native branch (row 6). No `credential-sign` edge exists — signature production is off-database and unbuilt. |
| **Required Stripe state** | a succeeded, livemode PaymentIntent |
| **Required signing state** | **one active key, produced by the two-person KMS ceremony** (`docs/phase2/PRODUCTION_SIGNING_KMS_CEREMONY.md`; ruling B) |
| **Required owner ruling** | B, D2 |
| **Currently ready?** | **NO** |
| **Why not?** | (a) **[V] Zero signing keys.** The bootstrap row is commented out in 093 on purpose: *"it must not execute with placeholder values, and it must not execute at all until the KMS ceremony has produced both strings"* (`093:3652-3655`). This is 093's stated critical path because it waits on a human, not on engineering. (b) `feature.native_issuance_enabled` is **[V] false** — the mint's own gate at `083:497`. (c) `ticket.expiry_grace` is **[V] null**, so `kernel.sweep_expired_ticket_atoms` (`079:456`, cron `*/2`) returns `swept_count: 0` **silently, forever** (`079:480-485`). A no-show buyer's atom never expires, and BP-1 (`079:706-717`) blocks that identity's deletion. (d) `stripe-webhook`'s native branch is the only caller of the mint on this rail and is not deployed. (e) No `credential-sign` edge exists, so no issued atom can actually be signed — the DB records the trust state; nothing produces a signature. (f) `catalog.event_session.status` is **never** written to `'completed'` by anything in 076–092 (only `'cancelled'`, `088:1793`), which is why nothing downstream may depend on it. |

### 8 · Refund

| | |
|---|---|
| **Required DB** | `kernel.refund` (085), `kernel.refund_primary_order` (`085:457`), `kernel.admin_refund` (`085:706`), `kernel.mark_refund_state` (`085:1737`), **`kernel.get_refund_execution_context`** (**[V] exists — 093:1087, service_role only**), **`kernel.list_pending_refunds`** (**[V] DOES NOT EXIST**) |
| **Required config** | `refund.*` policy keys — **[V] all null except `refund.scanned_atom_policy` = `"platform_review"`**; `deletion.refund_possible_window_hours` **[V] null** |
| **Required edge** | `refund-execute` — **authored (66 tests green), NOT DEPLOYED** (E4) |
| **Required Stripe state** | `POST /v1/refunds` reachable; the payment `stripe_livemode = true` (migration 045) |
| **Required signing state** | none |
| **Required owner ruling** | **D3** (build the executor now), **A9** (refund executability is a hard precondition of selling), D |
| **Currently ready?** | **NO** |
| **Why not?** | (a) `refund-execute` is not deployed. **Nothing in the repo calls `kernel.mark_refund_state`** except that undeployed edge, and it is the only transition out of `pending`. **So every `kernel.refund` row created today is born `pending` and stays `pending` forever: the buyer loses the ticket and gets no money** (`085:593` voids the atoms, `085:604` moves the order, `085:599` inserts the row). That is precisely the failure A9 names. (b) The stranded `pending` row then blocks that buyer's account deletion permanently — BP-12 arm 1 (`085:249-262`). (c) **`kernel.list_pending_refunds` does not exist [V]**, so the executor's `action: sweep` — the self-heal for a crash between Stripe and the callback, E4 §5 cases 2/3/13 — answers **501** (`refund-execute/index.ts:496-504`). Single refunds would work on deploy day; interrupted ones would be unfindable. (d) **PFA-23's direct arm has no implementation, and the reason is structural. [V] Both refusals executed:** as `service_role` → `insufficient_privilege: refund_primary_order is platform (direct) or dual-control-delegated only` (`auth.uid()` is NULL so `is_platform` fails); as `authenticated` → `permission denied for function` (EXECUTE is `service_role` only, `085:2152`; the exclusion is deliberate, `085:2129-2130`). PostgREST binds one role per request, so *"as service_role, forwarding the platform JWT"* has no single-client implementation with this grant set. **The DELEGATED arm (`req:<uuid>`, dual-control) does work, and `kernel.admin_refund` is [V] granted to `authenticated`** — so a refund can be *recorded*, just never *executed*. (e) 093 is not applied to production, so `get_refund_execution_context` does not exist there either. **Owner decision open (E4 §7, three options); option (iii) — retire the direct arm and route all platform refunds through delegated dual control — costs least and increases control.** |

### 9 · Settlement maturity

| | |
|---|---|
| **Required DB** | `venue.settlement` / `venue.settlement_line` (087, append-only), `kernel.settlement_primary_lines` (**[V] exists — 093:413**), `kernel.close_settlement` **as replaced by 093** (`093:618`) with the 8-conjunct hold at `093:853-867`, the two partial unique indexes (093 item 13) |
| **Required config** | **`payout.settlement_maturity_interval`** — **[V] null**. Renamed this train from `settlement.refund_window_interval`, which **[V] no longer exists as a row**. |
| **Required edge** | none — this is pure SQL |
| **Required Stripe state** | none for the hold decision; `kernel.dispute_native` state informs conjunct 8 |
| **Required signing state** | none |
| **Required owner ruling** | A3, A4, A5, G2 |
| **Currently ready?** | **NO** |
| **Why not?** | (a) 093 is not applied to production; on 092 `close_settlement` still decides the hold with the single line `v_held := v_refund_window is null` and no maturity semantics at all — the defect G2 fixed. (b) `payout.settlement_maturity_interval` is **[V] null**, so every close holds with `unbounded_refund_exposure`. **This is the correct and intended state** — the key must not be set before activation. (c) There is nothing to settle: rows 5–7 are all NO, so no `primary_sale` line can exist. **[V] With the key set to `"7 days"` and a matured `org_finance` caller, a close returned `{"status":"ok","net_minor":5000,"payout_hold":"maturity_not_elapsed"}` and the settlement header carried `closed gross=5000 net=5000` — the obligation is a durable ledger fact while the money is held, which is A3 satisfied.** (d) Residual, not a blocker: the maturity anchor `catalog.event_session.ends_at` is **mutable by the party being paid** — an `ends_at`-only patch takes no time guard (`079:625-659` fires only on `starts_at`/`doors_at`) and needs no `reason_code`. Bounded to the session's own duration by `event_session_time_check`, but not closed. **Owner item (G2 Part 3).** (e) Residual: a chargeback filed after release is covered by no interval; it needs a receivable object or a Stripe fixed reserve plan, neither of which exists (G2 Part 6). |

### 10 · Venue payout

| | |
|---|---|
| **Required DB** | `kernel.payout` (085/087), `kernel.request_org_payout`, `kernel.release_payout` (`085:807`), `kernel.set_org_payout_destination` (`093:2862`) |
| **Required config** | `payout.settlement_maturity_interval`; `payout.destination_cooldown_hours` (**[V] null**); `payout.destination_probation_days` (**[V] null**); `payout.dual_control_min_minor` (**[V] null**); `payout.request_auto_max_minor` (**[V] null**); `authn.money_role_maturity_hours` (seeded 72) |
| **Required edge** | **a payout executor — [V] NONE EXISTS.** `ls supabase/functions/` has no payout function, and **[V] nothing in `supabase/functions/` or `src/` writes `stripe_transfer_ref` or calls `kernel.release_payout` — zero hits.** |
| **Required Stripe state** | connected account with `transfers` active; a resolved `source_transaction` per transfer |
| **Required signing state** | none |
| **Required owner ruling** | A2, A3, A5, A6, **A9** (the `source_transaction` mapping must be settled **in writing before** an executor is authored) |
| **Currently ready?** | **NO** |
| **Why not?** | (a) **No payout executor exists at all.** The reachable terminal state of a payout row today is `submitted` with `stripe_transfer_ref = NULL`. **[V] End state after a full replay: `settlement/pending/hold=held/xfer=NONE`.** (b) **The `source_transaction` mapping is unresolved on paper.** One settlement payout has many funding charges; Stripe binds one source transaction per transfer and it cannot be amended after creation; **[V] `kernel.payout` has exactly one `source_transaction_ref` column.** A9's approval text requires this be settled *before* an executor is authored. **This is the true head of the PAYABLE critical path, and it is a paper item.** (c) Rows 1 and 9 are both NO. (d) `kernel.request_org_payout` requires an aal2 step-up — **[V] `precondition_failed: step_up_unavailable: the session carries no aal claim`** — plus a matured money role (72h) and a non-held payout. (e) Four `payout.*` policy keys are **[V] null**. All four are **[V] dual-controlled** (`payout.%` matches `078:1145-1147`), which is correct. (f) `kernel.resolve_dispute_native` **[V] always raises `dual_control_unavailable` with zero mutation** (`088:913-931`, PFA-31), so a lost dispute freezes the org's payout and the buyer's atoms permanently with no exit. A9 records this as *"a known defect with no exit path"* that must close *"before the direct rail carries material volume"* — an explicit volume threshold, not a launch blocker. |

### 11 · Promoter funding

| | |
|---|---|
| **Required DB** | `venue.promoter`, `venue.promoter_code`, `venue.attribution` (090); `kernel.settlement_commission_lines` (087 seam, body replaced by 093 item 14 to exclude `partially_refunded`); `kernel.pay_promoter_commission` (`090:1487`) |
| **Required config** | the commission policy keys the promoter engine reads; row 9's maturity key |
| **Required edge** | none |
| **Required Stripe state** | none — funding is a ledger act, not a transfer |
| **Required signing state** | none |
| **Required owner ruling** | **A4** — *"eligible primary promoter commission is funded from primary-sale economics and reduces venue distributable before venue money is released"*; *"funding a commission is NOT equivalent to paying a commission"* |
| **Currently ready?** | **NO** |
| **Why not?** | (a) There is no revenue to deduct from: rows 5–9 are all NO, so no `primary_sale` line exists and every commission is a debit against nothing. (b) 093 is not applied, so `kernel.settlement_primary_lines` — the seam that produces the revenue — does not exist in production, and the commission seam's `partially_refunded` fix (093 item 14) is not there either. Without that fix, a direct partial refund voids no atoms (`085:562-564`), the commission basis is unreduced, and **full commission is paid on partly refunded revenue** — unrecoverable in an append-only ledger. (c) A4 is asserted by test and holds: **[V] the 093 `close_settlement` body contains no `UPDATE` or `DELETE` on `kernel.payout`, no reference to `venue.promoter` / `venue.attribution` / `kernel.pay_promoter_commission`, and no call to `kernel.release_payout`** — every change it can make moves a payout from unheld to **held**. Nothing in 093 can accidentally release promoter money. |

### 12 · Promoter payout

| | |
|---|---|
| **Required DB** | `kernel.payout` rows with `cause='promoter_commission'`, minted `held` / `unfunded_settlement` by `kernel.pay_promoter_commission` (`090:1487-1491`); `kernel.release_payout` as the sole exit |
| **Required config** | the `payout.*` keys of row 10, all **[V] null** |
| **Required edge** | **a payout executor — [V] none exists** (same absence as row 10) |
| **Required Stripe state** | a connected account or other destination for the promoter — **the promoter payee plane is not the org plane**; `kernel.payout.payee_identity_id` exists but nothing binds a promoter destination |
| **Required signing state** | none |
| **Required owner ruling** | **A4** — *"promoter payout execution remains dark and separately gated"* |
| **Currently ready?** | **NO** |
| **Why not?** | (a) **Nothing releases a promoter commission payout.** They are minted `held` with `unfunded_settlement` and there is no code path that clears that hold — G2 verified **0 `promoter_commission` payouts existed after nine closes**. (b) Row 10's absent executor applies identically. (c) Row 11 is NO, so nothing is funded to pay. (d) **A4 rules this dark on purpose.** This row is NO *by design*, and it is the only NO in the matrix that should stay NO after everything else turns YES. |

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

**Two of twelve.** Both YES rows are the two A8 ruled require nothing: DRAFT and PUBLISHABLE. That is
the ratification working exactly as written — a venue can build its whole event before Stripe exists,
and cannot take a dollar until the rail does.

---

## The critical path, in dependency order

Blockers shared by many rows, ordered so that clearing each one unblocks the next. **Nothing here is
authorized or scheduled; this is the shape of the path, not a plan.**

| Step | Blocker | Unblocks | Kind |
|---|---|---|---|
| **0a** | The `source_transaction` mapping for one payout across many funding charges is unsettled (A9) | 10, 12 | **paper — owner + counsel** |
| **0b** | PFA-23's direct-arm authority question is unresolved (E4 §7) | 8 | **paper — owner** |
| **0c** | Processing-cost allocation is unruled (A5 open item, E2 AB-10) | 5, 9 | **paper — owner** |
| **0d** | No tax model exists anywhere (**[V]** zero keys, zero functions) | 5 | **paper — owner + counsel** |
| **0e** | The `on_sale` gating choice (G6 §5.4) | 3, 5 | **paper — owner** |
| **1** | **093 is not applied** | 1, 4, 5, 6, 8, 9, 11 | migration |
| **2** | **The KMS ceremony and the signing bootstrap row** — **[V] 0 keys**, row commented out at `093:3656` | 6, 7 | **owner ceremony — 093's stated critical path** |
| **3** | `kernel.list_pending_refunds` is unauthored (shape given in E4 §3; `get_refund_execution_context` **[V] already exists**) | 8 | small migration |
| **4** | `connect-onboarding` not deployed | 1 | deploy |
| **5** | `stripe-webhook` native branch not deployed — **also the only writer of `connect_transfers_active`** | 5, 6, 7 | deploy |
| **6** | `refund-execute` not deployed | 8 | deploy |
| **7** | `primary-checkout` not deployed | 5 | deploy — **last, it is the only one that can take money** |
| **8** | PostgREST does not expose `catalog` / `venue` (**[V]** production is `public, graphql_public, kernel`; `venue` → `PGRST106`) | 4, 5 | **operational — and it must come AFTER step 1** (E2 AB-8) |
| **9** | Six owner config values unset | 4, 5, 7, 9, 10 | owner config — **last**, and `feature.native_issuance_enabled` last of all |
| **10** | No payout executor exists | 10, 12 | build — **gated on 0a** |
| **11** | `kernel.resolve_dispute_native` is parked (`088:913-931`) | 10 | **volume threshold, not a launch gate** (A9) |

---

## Hazards — where one change crosses a gate

Full analysis in `G6_activation_gates.md` §6. **[V] Every row below was executed against the live
setter as a real `platform_admin`.**

| Change | Crosses | Dual-controlled? | Intended? |
|---|---|---|---|
| `payout.settlement_maturity_interval` → any value | one conjunct of eight | **YES — [V] `{"status":"parked"}`; the effective value did not move** | **YES — the G2 fix. The reference shape, and the only key on the whole activation path a single admin cannot move.** |
| `feature.native_issuance_enabled` → true/false | dark ↔ live | **NO — [V] executes immediately** | **YES.** A kill switch that needs a quorum is not a kill switch. |
| `fee.buyer_service_bps` → any integer | **[V] `service_fee_unset` → a primary-sale order is created.** The LAST clause of the SALEABLE chain. | **NO — [V] executes immediately** | **NO — the surviving instance of the banned pattern.** Its own logic *is* built and its name *is* honest, unlike the old maturity key — but at the moment it is set, nothing else on the SALEABLE chain is checked: not the signing key (F-2), not refund executability (A9/F-3), not tax (F-4). **Recommended fix: widen the `078:1145-1147` dual-control prefix test to include `fee.%`.** Renaming into `payout.%` is rejected — it would be a second lie of exactly the kind G2 just removed. |
| `ticket.expiry_grace` → a JSON **number** | inert sweep → **every active atom on every ended session terminal within two minutes** (cron `*/2`, `079:799-803`) | **NO — [V] `24` was accepted; `('24'::jsonb #>> '{}')::interval` = `00:00:24`, twenty-four seconds** | **NO — hazard, named by G1 and still live.** The row is seeded JSON `null`, so 078's type witness is disarmed for the first write. **It must be set as a jsonb string in hours** (G1 §7 recommends `'"72 hours"'`). |
| `deletion.refund_possible_window_hours` → any number | BP-12 arm 2 stops blocking → paid buyers become erasable **while their refunds are stranded `pending` forever** | **NO — `deletion.%` matches no prefix** | **NO — hazard.** The key's name and consumer are both honest; its safety depends entirely on a fact two systems away (that refunds execute). **Set it only after step 6 of the critical path. Nothing enforces that ordering — it belongs in the runbook in writing.** |
| `inventory.hold_ttl_interval` **and** `inventory.per_user_active_hold_max` | nothing holdable → holdable | **NO** | **YES.** Both fail closed while unset, both are self-announcing, and neither enables unbuilt logic. Two changes, not one. |
| `UPDATE kernel.organization SET connect_transfers_active = true` (direct SQL) | `payout_not_ready` → passing, permanently, per org, unaudited | **n/a — not a config key** | **NO — hazard.** The column's only writer is an undeployed webhook branch. 093 requires the flag be non-monotonic *"or an account Stripe later disables stays sellable forever"* — a property that is only real once a writer runs. The no-direct-SQL policy is the only control, and that is a person remembering. |
| PostgREST exposed schemas `+= venue, catalog` | server-only → **`venue.create_primary_checkout` (granted to `authenticated`) directly client-callable** | **n/a — a dashboard text field, not in git, not in a PR, not covered by a migration guard** | **NO — hazard, though a reasonable operational control.** It is currently the **outermost gate on the entire primary rail**. It must be a named, ordered, two-person step in the runbook, and it must come after 093 applies (E2 AB-8). |

---

**Nothing in this document has been authorised, authored, applied, deployed or committed. It records
what is true at the repo tip and in production, verified on a local, disposable rehearsal database.**
