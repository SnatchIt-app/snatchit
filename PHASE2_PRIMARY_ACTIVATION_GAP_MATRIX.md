# PHASE 2 — PRIMARY ACTIVATION GAP MATRIX
## VENUE CORE → PRIMARY INVENTORY → PRIMARY TICKET ISSUANCE

**Authored:** 2026-09-02 · branch `feature/venue-native-and-product-v2` · repo `/Users/josetascon/snatchit-consol`
**Status of this document:** ANALYSIS ARTIFACT. It changes no byte, activates nothing, and is not an authority.
Authority order remains `docs/architecture/_governance/PHASE_2_ARCHITECTURE_FREEZE.md` §4 →
`POST_FREEZE_AMENDMENTS.md` → the frozen corpus → the shipped migrations.
**Evidence rule applied throughout:** where the corpus and the shipped bytes disagree, THE SHIPPED BYTES WIN.
Every disagreement found is flagged in §7.

---

## 0a. CORRECTION — the money-boundary claim was too strong (adversarial finding J-1)

This document's §6 headline said payment collection is "verified separable" from settlement and
payout. **That framing is withdrawn.** It is true in the narrow technical sense and misleading in
the sense that matters.

What is actually true:

- `venue.finalize_primary_order` writes no payout and no settlement row, so taking a payment does
  not require the payout rail to be lit. That much stands.
- **But no code path anywhere emits a primary-sale settlement line.** `087:318` is the only INSERT
  into `venue.settlement_line` in the repository, and its two sources are the resale royalty seam
  and the promoter commission seam, which is negative. Gross is therefore 0, `close_settlement`'s
  `if v_net > 0` never fires, and no organization payout is ever minted. Turning the payout rail on
  later does not fix this; the line does not exist to be paid.
- Money-in lands in the **platform's** Stripe balance. The PaymentIntent carries no
  `transfer_data`, no `on_behalf_of` and no application fee, and a venue organization has no
  connected account.

**The honest statement:** a venue that sells 400 tickets is owed money that no schema row names and
no code path can pay. Collection can be switched on without the payout rail, but doing so creates an
obligation the system cannot represent. That is an owner decision about how venues actually get
paid, not an engineering detail, and it gates the first activation train.

## 0. GROUND TRUTH CORRECTION (read this first)

Two of the three "already-classified obligation ledgers" this analysis was told to reuse are **STALE on the
single most important fact**, and reusing them uncorrected would produce a wrong matrix.

| Claim | Source | Reality | Evidence |
|---|---|---|---|
| "nothing of 076–092 is applied anywhere" | `docs/architecture/_governance/PHASE_2_FINAL_STATE_CENSUS.md` §10 | **FALSE as of 2026-09-02 20:43Z.** All 17 migrations are applied to PRODUCTION. | `docs/release/PHASE2_DEPLOYMENT_RECORD_20260902.md:14-17` — "17 migrations applied in 93 s. Ledger 90 → 107"; V1–V18 pass |
| "production remains at migration 20260902003623 with NONE of 076–092 applied" | `docs/release/PHASE2_RELEASE_READINESS_REPORT.md:5-7` | Same — that report is the PRE-apply release candidate; the deployment record supersedes it. | `docs/release/PHASE2_DEPLOYMENT_RECORD_20260902.md:5-6` |

Both documents were written **before** the apply window and were never revised. Their per-rail *classifications*
(the §9 forward-obligation ledger and §13 rail matrix) remain valid and ARE reused below; their *deployment
state* assertions are not.

**Therefore the correct frame for this matrix is:** the DB substrate is LIVE in production and DARK. The gap is
no longer "apply the migrations" — it is flags, config, PostgREST exposure, edge functions, five parked DB
bodies, and an entirely absent client.

**Current production posture (all from `docs/release/PHASE2_DEPLOYMENT_RECORD_20260902.md`):**
- Migrations 076–092 applied; ledger 107 rows (`:14-15`)
- PostgREST exposed schemas: **`public, graphql_public, kernel`** — `catalog`, `venue`, `market`, `notify` are NOT exposed (`:19-21`)
- Feature flags 5/5 false; owner-unset money keys 3/3 NULL (`:34`)
- Native money rows 0; no rail activated (`:39-41`)
- Edge functions deployed: legacy 11 only. **No Phase-2 edge function exists.** (`:22-25`)

---

## 1. THE GAP MATRIX

STATUS legend (exactly as specified):
`COMPLETE` · `PARTIAL` · `SCHEMA-ONLY` · `CODE-ONLY` · `UI-MISSING` · `EDGE-MISSING` · `CONFIG-MISSING` ·
`SECRET/CREDENTIAL-MISSING` · `OWNER-DECISION-BLOCKED` · `PFA-BLOCKED` · `NOT IMPLEMENTED`

Where a capability is complete in the database but has no client, the STATUS is `UI-MISSING` (the DB is not the
gap). Where the DB itself refuses, the STATUS names the refusal.

### A. VENUE CORE — org, venue, staff

| # | CAPABILITY | STATUS | EXISTING ARTIFACT | SOURCE LOCATION | FROZEN ARCHITECTURE REFERENCE | MISSING WORK | DEPENDENCY | RISK | PRODUCTION ACTIVATION REQUIREMENT |
|---|---|---|---|---|---|---|---|---|---|
| A1 | Platform-admin authority exists (bootstrap) | **COMPLETE** | `public.admin_users` allowlist read by `kernel.is_platform` | `supabase/migrations/077_kernel_identity_orgs_and_roles.sql:468-489`; table `supabase/migrations/033_marketplace_expansion.sql:102` | RPC §20.1.4 "the first platform_admin cannot be granted by a platform_admin" | none | — | LOW — a legacy table now confers Phase-2 platform authority; verify the row list before activation | Confirm the intended humans are the only `public.admin_users` rows |
| A2 | Grant `platform_support` / `platform_risk` | **PFA-BLOCKED** | `kernel.grant_platform_role` is a hard-raise stub | `supabase/migrations/077_kernel_identity_orgs_and_roles.sql:1591` — `raise exception 'precondition_failed: dual_control_unavailable … PFA-4'` | PFA-4, `POST_FREEZE_AMENDMENTS.md` | Owner ruling on a dual-control mechanism, then a 093+ body replacement | A1 | LOW for primary issuance — **not on the critical path** (only `platform_admin` is needed, and A1 supplies it) | None for primary issuance. Required only for support/risk staffing |
| A3 | Create an organization | **UI-MISSING** | `kernel.create_organization` — real body, grants `authenticated` | `supabase/migrations/077_kernel_identity_orgs_and_roles.sql:767-822` | RPC §20.1; ROLE_MODEL §orgs | Client surface; `kernel` is already exposed so this is callable today | A1 | LOW. Note E-3: no command-key column ⇒ replay creates a second inert org | None (DB+API ready). Build UI |
| A4 | Org member invite / accept / role change | **UI-MISSING** | `invite_org_member`, `accept_org_invite`, `change_org_role`, `remove_org_member`, `revoke_org_invite` | `077:1015`, `077:1094`, `077:1167`, `077:1286`, `077:1348` | RPC §20.1.2–20.1.3 | Client surface | A3 | LOW | Build UI |
| A5 | Create a venue | **UI-MISSING** | `catalog.create_venue` → `approval_status='draft'` | `supabase/migrations/078_catalog_reference_data_and_flags.sql:510-563` | RPC §3.1 | Client surface + **`catalog` PostgREST exposure** | A3, C1 | LOW | Expose `catalog`; build UI |
| A6 | Approve a venue (the Miami gate) | **UI-MISSING** | `catalog.approve_venue` — `platform_admin` only | `078:564-622` (gate at `:589`) | RPC §3.2 "the Miami approved-venues gate" | Admin client surface | A1, A5 | MEDIUM — an unapproved venue is invisible to `anon` (`catalog_venue_sel_anon` requires `approval_status='approved'`, `078:307-310`); a forgotten approval silently hides the whole event | Expose `catalog`; build an admin approval surface |
| A7 | Venue/event staff roles | **UI-MISSING** | `venue.staff_role` + `venue.grant_staff_role` / `revoke_staff_role` | `supabase/migrations/080_venue_staff_roles_and_predicates.sql:30`, `:121`, `:249` | RPC §20.5; AUTHZ-PKG1 | Client surface + **`venue` exposure** | A3, C2 | LOW | Expose `venue`; build UI |
| A8 | Authority predicates | **COMPLETE** | `kernel.has_venue_role` / `has_event_role` / `has_org_role_over_venue` / `has_org_role_over_event` | `080:60`, `:78`, `:93`, `:105` | RLS §16.10a | none | — | LOW | None |

### B. EVENT + PRIMARY INVENTORY

| # | CAPABILITY | STATUS | EXISTING ARTIFACT | SOURCE LOCATION | FROZEN ARCHITECTURE REFERENCE | MISSING WORK | DEPENDENCY | RISK | PRODUCTION ACTIVATION REQUIREMENT |
|---|---|---|---|---|---|---|---|---|---|
| B1 | Create an event | **UI-MISSING** | `catalog.create_event` → `status='draft'` | `078:829-900` | RPC §4.1 | Client surface | A5, A6, C1 | LOW | Expose `catalog`; build UI |
| B2 | Create event sessions | **UI-MISSING** | `catalog.create_event_session` | `078:749-828` | RPC §4.3 | Client surface | B1 | LOW | Build UI |
| B3 | Update event / session | **UI-MISSING** | `catalog.update_event`, `catalog.update_event_session` | `078:901`, `supabase/migrations/079_kernel_ticket_atom_and_ownership_log.sql:518` | RPC §4.1a/§4.3a | Client surface | B1, B2 | LOW — `update_event_session` carries the atoms-issued schedule guard | Build UI |
| B3a | Schedule-move guard after atoms are issued | **CONFIG-MISSING — LIVE FAIL-OPEN** | `door.schedule_move_grace_interval` is a PFA-9 CLASS A key that is **not seeded**, and the 079 schedule-move guard reads it | `catalog.update_event_session` `079:518`; key absent from the 078 seed block `078:1520-1590` | **PFA-9 CLASS A residual** (`POST_FREEZE_AMENDMENTS.md:626`, restated `:703`) — filed as a **FAIL-OPEN EXPOSURE against 079**: a NULL config makes the guard never fire, so a published session's schedule moves freely once atoms exist | Owner seeds the value **and** 079's guard is made fail-to-safe (absent ⇒ no later move) — a 093+ body change | B2, G4 | **MEDIUM — the only fail-OPEN found in the whole primary path.** Harmless while zero atoms exist; becomes real the moment issuance activates | Seed the key + fail-safe the guard **before** E3 is flipped |
| B4 | Create ticket types | **UI-MISSING** | `venue.create_ticket_type` — **no feature-flag gate**; authority = `venue_manager` or `org_owner/org_admin` | `supabase/migrations/081_venue_inventory.sql:175-245`; authority at `:220-223`; grant to `authenticated` at `:1086` | RPC §5.1 | Client surface + `venue` exposure | A7, B1, C2 | LOW. Works **today**, flag-independent | Expose `venue`; build UI |
| B5 | Set ticket-type price | **UI-MISSING** | `venue.set_ticket_type_price` | `081:246-319` | RPC §5.2 | Client surface | B4 | LOW | Build UI |
| B6 | Create inventory batches | **UI-MISSING** | `venue.create_inventory_batch` — **no feature-flag gate** | `081:320-407` (authority `:379-381`) | RPC §5.5 | Client surface | B4 | LOW. Works today | Build UI |
| B7 | Set batch capacity | **UI-MISSING** | `venue.set_batch_capacity` | `081:408-526` | RPC §5.6 | Client surface | B6 | LOW | Build UI |
| B8 | Counters readable by staff | **COMPLETE** | E-29 resolution: `remaining` is generated + column-scoped; raw counters returned in RPC result JSON | `081:990-1010` (RLS/grants); `POST_FREEZE_AMENDMENTS.md:1640-1650` (E-29) | RLS §9.2 fn.23 | none | B6 | LOW | UI must read counters from RPC result JSON, never a table SELECT |
| B9 | Publish event to `on_sale` | **UI-MISSING** | `catalog.publish_event` — forward-only transitions, refuses `empty_inventory` | `081:899-964`; empty-inventory gate `:945-952`; grant `authenticated` `:1093` | RPC §4.2; SEAM-1 | Client surface | B4, B6 | LOW | Build UI |
| B10 | Cancel an event | **UI-MISSING** | `catalog.cancel_event` (shipped in 088, not 081) | `supabase/migrations/088_market_native_rail.sql:1612`; grant `:1849` | RPC §4.4 | Client surface | B1 | LOW | Build UI |
| B11 | Hold-expiry sweep | **COMPLETE** | `venue.sweep_expired_inventory_holds` + cron `sweep-expired-inventory-holds` `*/2` | `081:852-897`; cron `:1119-1123` | CRON_SCHEDULE_REGISTER row 081 | none | — | LOW — running in production now, no-op on an empty table | None |

### C. REACHABILITY — the API boundary

| # | CAPABILITY | STATUS | EXISTING ARTIFACT | SOURCE LOCATION | FROZEN ARCHITECTURE REFERENCE | MISSING WORK | DEPENDENCY | RISK | PRODUCTION ACTIVATION REQUIREMENT |
|---|---|---|---|---|---|---|---|---|---|
| C1 | `catalog` reachable over PostgREST | **CONFIG-MISSING** | Exposure is `public, graphql_public, kernel` | `docs/release/PHASE2_DEPLOYMENT_RECORD_20260902.md:19-21` | **E-166** (`POST_FREEZE_AMENDMENTS.md:2542`) — "`catalog`/`venue`/`market`/`notify` exposure rides each rail's activation"; 076 GRANT boundary | Add `catalog` to the project's exposed schemas (Supabase API settings) | — | LOW — `anon` already holds `catalog` USAGE (`076:76`) and every catalog table has a fail-closed RLS policy (`078:307-345`), so exposure leaks nothing beyond approved venues / non-draft events | **Operational config change, NOT a migration** |
| C2 | `venue` reachable over PostgREST | **CONFIG-MISSING** | Same | Same | **E-166** (`POST_FREEZE_AMENDMENTS.md:2542`); 076 GRANT boundary | Add `venue` to exposed schemas | — | LOW — `anon` has NO `venue` USAGE (`076:70-74`), so anon requests get 42501 at the schema wall | **Operational config change, NOT a migration** |
| C3 | `kernel` reachable | **COMPLETE** | Cutover done in the deployment window | `docs/release/PHASE2_DEPLOYMENT_RECORD_20260902.md:19-21` — "kernel reachable + anon walled (42501)" | — | none | — | LOW | None |
| C4 | `service_role` can reach `venue` / `kernel` (webhook path) | **COMPLETE** | PFA-15 + PFA-21 delivered **USAGE ONLY** | `supabase/migrations/085_kernel_money_native.sql:2088-2095` | PFA-15, PFA-21 (owner-signed) | none | — | LOW | None. **See §7 disagreement D2** — 082's comment still says PFA-15 is open; 085 closed it |
| C5 | Generated TypeScript `Database` types covering non-public schemas | **NOT IMPLEMENTED** | No types file exists anywhere | acknowledged at `src/types/index.ts:34` — ".rpc() infers {}" | ENGINEERING_STANDARDS | Generate types for `public, kernel, catalog, venue`; wire the `Database` generic into both clients | C1, C2, C3 | MEDIUM — every Phase-2 call is currently untyped and needs `(supabase as any)` (`app/settings/index.tsx:117`) | Client-side build work |
| C6 | Web client can address a non-`public` schema | **NOT IMPLEMENTED** | Three web clients, none uses `.schema()` | `web/src/lib/supabase/client.ts:17`, `server.ts:22`, `proxy.ts:18` | RN_PRODUCT_SPEC §2 | Client construction change | C5 | MEDIUM — web has **no path at all** to venue/kernel/catalog today | Client-side build work |

### D. DISCOVERY + SELECTION

| # | CAPABILITY | STATUS | EXISTING ARTIFACT | SOURCE LOCATION | FROZEN ARCHITECTURE REFERENCE | MISSING WORK | DEPENDENCY | RISK | PRODUCTION ACTIVATION REQUIREMENT |
|---|---|---|---|---|---|---|---|---|---|
| D1 | Anonymous browse of venues / events / sessions | **SCHEMA-ONLY** | RLS policies `catalog_venue_sel_anon`, `catalog_event_sel_anon`, `catalog_event_session_sel_anon` | `078:307-310`, `:325-328`, `:336-341` | RLS §8.1–8.3; R3-3a | `catalog` exposure + client surface | C1 | LOW. The R3-3a fix is shipped (`status <> 'draft'`, not `>= 'announced'`) | Expose `catalog`; build UI |
| D2 | Anonymous view of ticket types + prices | **OWNER-DECISION-BLOCKED** | `venue_ticket_type_sel_public` is scoped to `authenticated` ONLY | `081:1006-1010`; rationale `081:997-1001` | **PFA-14** (`POST_FREEZE_AMENDMENTS.md:965`, owner-signed `:1011`, forward obligation `:1039`, OWNER: UNASSIGNED) — E-30 (`:1653`) was RECLASSIFIED into it. Delivery boundary amended to "a separately reviewed public storefront/server/edge read surface" | Ratify a public projection preserving RLS §9.1/§9.2 semantics without exposing raw `venue`, OR accept an authenticated-only launch | C2 | **MEDIUM — a real product gap.** A logged-out visitor can see an event exists but not what a ticket costs. **Authenticated-only launch is the frozen posture** (`:1023`) | Owner ruling on PFA-14's forward obligation, or ship authenticated-only |
| D3 | Reserve inventory (create a hold) | **CONFIG-MISSING** | `venue.reserve_primary_inventory` — real body, `authenticated` | `081:527-661`; flag gate `:578-585`; TTL gate `:625-635`; cap gate `:608-623` | RPC §5.3; C27 oversell choke-point | **Two config keys must exist** (see E1/E2) **and** the flag must flip | C2, E1, E2, E3 | **HIGH — the hard stop.** Missing TTL ⇒ `hold_ttl_unset`; missing cap ⇒ fail-to-ZERO ⇒ `hold_cap_exceeded` on every call | 093+ migration to SEED the two keys, then `catalog.set_platform_config` to value them |
| D4 | Release a hold | **UI-MISSING** | `venue.release_inventory_hold` | `081:764-851` | RPC §5.4a | Client surface | D3 | LOW | Build UI |
| D5 | Staff / comp holds | **UI-MISSING** | `venue.create_inventory_hold` — staff authority, flag-gated | `081:672-763`; flag `:697-703` | RPC §5.4 | Client surface | D3 | LOW | Build UI |

### E. CONFIGURATION — the activation switches

| # | CAPABILITY | STATUS | EXISTING ARTIFACT | SOURCE LOCATION | FROZEN ARCHITECTURE REFERENCE | MISSING WORK | DEPENDENCY | RISK | PRODUCTION ACTIVATION REQUIREMENT |
|---|---|---|---|---|---|---|---|---|---|
| E1 | `inventory.hold_ttl_interval` | **NOT IMPLEMENTED** | **No row exists.** Read at `081:627-631`; refuses `hold_ttl_unset` when absent | `081:625-635`; absence provable — the key does not appear in the 078 seed block `078:1520-1590` | E-28 (`POST_FREEZE_AMENDMENTS.md:1624-1639`) — PFA-9 CLASS A, "seeds NEITHER" | **093+ migration to INSERT the registry row**, then an owner value | — | **HIGH** | `catalog.set_platform_config` **cannot create a key** — it raises `unknown_key` (`078:1099-1102`). A migration is mandatory |
| E2 | `inventory.per_user_active_hold_max` | **NOT IMPLEMENTED** | **No row exists.** Read at `081:611-616`; `coalesce(…, 0)` ⇒ fail-to-ZERO ⇒ every reserve refuses | `081:608-623`; absence provable in `078:1520-1590` | E-28 (same) | Same — 093+ registry row + owner value | — | **HIGH** | Same as E1 |
| E3 | `feature.native_issuance_enabled` | **CONFIG-MISSING** | Seeded `false` | `078:1522`. Consumed at exactly three sites: `081:583` (reserve), `081:701` (staff hold), `083:497` (mint) | Gate P / §15.A | Owner flip via `catalog.set_platform_config` | E1, E2, F-series, G-series | **HIGH** — flipping this before E1/E2/G1 exist converts silent `feature_disabled` refusals into confusing `hold_ttl_unset` / `no_active_signing_key` refusals | Flip **last**, after every other row in this table is green |
| E4 | `deletion.refund_possible_window_hours` | **CONFIG-MISSING** | Seeded `null` | `085:2185-2188` | **PFA-22** (`POST_FREEZE_AMENDMENTS.md:1909`, semantics `:1915-1918`) | Owner value | E3 | **MEDIUM — upgraded. Activating issuance ARMS this key.** NULL is fail-closed *only when a qualifying `paid`/`partially_refunded` candidate order exists*. Today there are none, so it blocks nothing. **The first real primary sale makes every affected account-deletion request hang** until the owner sets it | Becomes required the moment the first order is paid. Set it in the same window as the E3 flip |
| E5 | `notify.delivery_lease_interval` | **CONFIG-MISSING** | Seeded `null`; `claim_deliveries` refuses | `PHASE_2_FINAL_STATE_CENSUS.md` §9 (`NOTIFY_DELIVERY_LEASE_VALUE`, E-154) | E-154 | Owner value ('5 minutes' recommended) | — | LOW for issuance; blocks push delivery only | Required only if push notices ship with issuance |
| E6 | `retention.backup_window_days` | **CONFIG-MISSING** | Seeded `null` | `078:1587` | PFA-9 / DEMOG §8.5 | Owner value from the dashboard's real PITR window | — | LOW — unrelated to issuance | Not required for issuance |
| E7 | Money keys (`refund.*` 7, `payout.*` 4, `authn.*` 2) | **CONFIG-MISSING** | Seeded `null` (owner decision D-3) | `078:1541-1560` | MONEY §7.2 | Owner values | — | LOW for issuance — see §6 | **Not required for issuance.** Required only for refunds/payouts |

### F. PRIMARY CHECKOUT + PAYMENT COLLECTION

| # | CAPABILITY | STATUS | EXISTING ARTIFACT | SOURCE LOCATION | FROZEN ARCHITECTURE REFERENCE | MISSING WORK | DEPENDENCY | RISK | PRODUCTION ACTIVATION REQUIREMENT |
|---|---|---|---|---|---|---|---|---|---|
| F1 | Build a pending order from holds | **COMPLETE** (DB) | `venue.create_primary_checkout` — real body, C16 idempotent, server-authoritative price snapshot, F-1/E-23 deletion gates | `supabase/migrations/082_venue_orders.sql:305-460`; grant `authenticated` `:684` | RPC §6.1 | none in DB | D3, C2 | LOW | None (DB ready) |
| F2 | `primary-checkout` edge function | **EDGE-MISSING** | **Does not exist.** `supabase/functions/` contains 11 legacy functions only | `ls supabase/functions/` — no `primary-checkout`; corroborated `PHASE_2_FINAL_STATE_CENSUS.md` §6 | `PHASE_2_EDGE_FUNCTION_SPEC.md:355-397`; matrix row `:1775` | Author + deploy. Class A (caller-JWT for the RPC), service_role for Stripe + limiter. Rate limit `5/60` fail-closed | F1, F3, F4 | **HIGH.** Copying `create-payment-intent` verbatim produces a **Class A violation** (EA-1/T-1/T-2/T-4) — that function builds its client from the service-role key | Author, deploy, `verify_jwt: true` |
| F3 | Stripe PI with the `rail` metadata contract | **EDGE-MISSING** | Legacy `create-payment-intent` sets `listing_id/buyer_id/seller_id/mode` and **no `rail` key** | `supabase/functions/create-payment-intent/index.ts:520-525` | `PHASE_2_EDGE_FUNCTION_SPEC.md:371-374` — metadata `{rail:'native_primary', order_id, buyer_id, org_id, session_id}` | Set `rail` in the new function | F2 | **HIGH** — see F7 | Part of F2 |
| F4 | `public.payments` can represent a primary payment | **OWNER-DECISION-BLOCKED** | `public.payments` requires `listing_id NOT NULL → public.listings`, `seller_id NOT NULL → auth.users`, `mode CHECK IN ('buy_now','auction')` | `supabase/migrations/000_baseline_schema.sql:971-1001` (listing_id `:972`, seller_id `:974`, mode `:993`) | **`PUBLIC_PAYMENTS_NATIVE_SHAPE`** — `POST_FREEZE_AMENDMENTS.md:2392` | Owner decision on the shape, then a **093+ migration** (nullable `listing_id`/`seller_id` + a native `mode` label, or an equivalent) | F2 | **HIGH — hard structural blocker.** A primary order has no listing and no individual seller. `venue.finalize_primary_order` reads `public.payments` (`085:1917-1919`) and `kernel.payment_native.payment_id` FKs it (`085:41`). No fake listing row is permitted by the amendment | 093+ migration + owner ruling |
| F5 | Webhook `native_primary` success branch | **EDGE-MISSING** | `stripe-webhook` has **zero** native branches | `grep 'rail\|native' supabase/functions/stripe-webhook/index.ts` → 1 unrelated comment at `:713` | `PHASE_2_EDGE_FUNCTION_SPEC.md:1206-1211` | Add a `metadata.rail` router + the `payment_intent.succeeded` → `venue.finalize_primary_order(order_id, payment_id, command_key, instrument_fingerprint)` branch | F3, G-series | **HIGH** | Extend the existing signed endpoint — do **not** fork it (SPEC:1198-1200) |
| F6 | Webhook terminal-failure branch | **EDGE-MISSING** (DB side COMPLETE) | `venue.cancel_pending_order` — real body, service_role only, never raises on replay | `082:478-529`; grant service_role `:690` | RPC §20.7.9; `EDGE_FUNCTION_SPEC:1213` | The webhook branch. Cancel only on a **terminal** PI | F5 | MEDIUM — a per-attempt decline must not cancel; capacity returns via the B11 sweep | Part of F5 |
| F7 | Legacy PIs keep routing to the legacy path | **NOT IMPLEMENTED** | No default rule exists | Legacy webhook branches on `metadata.mode` (`supabase/functions/stripe-webhook/index.ts:376-395`) | Spec is silent — flagged by the edge-spec analysis | Write an explicit rule: **absent `rail` ⇒ `external`** | F5 | **HIGH — regression risk to the live money rail.** Without it, every in-flight legacy PI falls through the new router | Must land in the same deploy as F5 |
| F8 | `instrument_fingerprint` capture | **EDGE-MISSING** | Column exists, written by finalize | `085:52-56`, written `085:2054-2056` | `EDGE_FUNCTION_SPEC:1211` | Fetch `latest_charge`, extract fingerprint. **A fetch failure passes NULL and STILL finalizes** | F5 | LOW — never log it; never let it delay issuance | Part of F5 |
| F9 | Promoter code / link at checkout | **EDGE-MISSING** | `venue.preview_promoter_code`, `venue.bind_order_attribution` exist | `supabase/migrations/090_venue_promoter_engine.sql:948`, `:984` | `PRIMARY_CHECKOUT_CODE_PARAMS`, `PROMOTER_CODE_PREVIEW_EDGE` (`FINAL_STATE_CENSUS` §9); `EDGE_FUNCTION_SPEC:725-758` | `promoter-code-preview` edge + optional `code`/`link_slug` params on F2 | F2 | LOW — **explicitly non-blocking**: no attribution failure may abort checkout (SPEC:751-753) | Optional for first activation |
| F10 | Order `source` classification | **OWNER-DECISION-BLOCKED** | `source` is **hardcoded `'web'`** even for app orders; the CHECK admits `app\|web\|door\|promoter_link` | hardcode `082:433`; CHECK `082:82-83`; rationale `082:424-427` | **E-39** (`POST_FREEZE_AMENDMENTS.md:1783`) — an owner-owed-forward classification explicitly scoped **"resolved BEFORE native issuance activates"** | Owner picks the label rule, or a 093+ signature amendment adds a `source` param to §6.1 | F1 | **MEDIUM — upgraded.** Not merely analytics: `venue.bind_order_attribution` gates box-office binding on `source='door'` (E-137, `:2467`), so a permanently-`'web'` source silently disables door attribution | Owner ruling — the amendment names activation as its deadline |
| F11 | CRM contact consent at checkout | **PARTIAL** | `kernel.grant_org_contact_consent` exists and is `authenticated`-granted, but `create_primary_checkout` never calls it | RPCs `082:530`, `:591`, `:636`; grants `082:686-688`; **absent** from the checkout body `082:305-460` | RPC §20.9 | Client must call it as a separate step | F1 | LOW | Build UI step |
| F12 | Consent notice-version registry | **OWNER-DECISION-BLOCKED** | `grant_org_contact_consent`'s `p_notice_version` is contracted as "validated against the known list" — **no registry exists**; 082 validates presence only | `082:530-590` | **E-38** (`POST_FREEZE_AMENDMENTS.md:1776`) — open forward obligation, scoped "before consent capture goes live" | Spec owner supplies a notice-version registry, or the clause is relaxed | F11 | LOW — blocks consent capture, not issuance | Owner ruling before consent capture ships |

### G. ISSUANCE — the mint

| # | CAPABILITY | STATUS | EXISTING ARTIFACT | SOURCE LOCATION | FROZEN ARCHITECTURE REFERENCE | MISSING WORK | DEPENDENCY | RISK | PRODUCTION ACTIVATION REQUIREMENT |
|---|---|---|---|---|---|---|---|---|---|
| G1 | An ACTIVE `kernel.signing_key` row can exist | **PFA-BLOCKED** | `kernel.provision_signing_key` and `rotate_signing_key` are **hard-raise stubs** — zero mutation | `supabase/migrations/083_kernel_credential_infrastructure.sql:375-393`; the raise at `:381`; park rationale `:363-372` | **PFA-18A** (`POST_FREEZE_AMENDMENTS.md:1252-1305`, owner-signed 2026-08-31) | Owner ruling on a credential-compatible dual-control mechanism, then a **093+ `CREATE OR REPLACE`** of the real bodies | — | **CRITICAL — THE #1 BLOCKER.** No key can be provisioned by anyone; `083:432` states it plainly: "No key can be provisioned while the lifecycle is parked (PFA-18A), so the mint cannot run" | Owner ruling + 093+ migration. **Nothing else in this document matters until this is resolved** |
| G2 | The mint refuses without a key | **COMPLETE** (as designed) | `kernel.issue_ticket_atoms` fails closed on `no_active_signing_key`, scope-coherent | `083:517-533`; `venue.finalize_primary_order` resolves the key first `085:1944-1960` | RPC §7.1 activation boundary | none | G1 | LOW — this is correct fail-closed behavior, recorded here so nobody "fixes" it | None |
| G3 | KMS signer + `signing-key-provision` edge | **SECRET/CREDENTIAL-MISSING** + **EDGE-MISSING** | Neither the edge nor the KMS provider exists | `PHASE_2_EDGE_FUNCTION_SPEC.md:579-592`; open item recon #3 at `:1822-1825` | EDGE_FUNCTION_SPEC §; PFA-18 | Choose a KMS provider + algorithm (Ed25519 preferred / ECDSA-P256), provision `KMS_SIGNER_ROLE_ARN`, author the edge | G1 | **HIGH** — DB stores `public_key` + `kms_handle_ref` only; **no key material in env, ever** | Owner picks provider; provision IAM; author edge |
| G4 | Mint ticket atoms | **COMPLETE** (DB) | `kernel.issue_ticket_atoms` — real body, session-lock serial draw, C27 oversell backstop, idempotent | `083:440-598` | RPC §7.1; SSCAS #1 | none in DB | E3, G1 | LOW | None (DB ready) |
| G5 | Money→tickets, atomically | **COMPLETE** (DB) | `venue.finalize_primary_order` — payment-is-authority (C35), coverage check, refund check, deterministic batch pre-lock, E-40 hold conversion, replay-safe | `085:1881-2078`; service_role-only grant `085:2149` | RPC §6.3; SSCAS #1 | none in DB | F4, F5, G1 | LOW. RLS §11: "an authenticated grant here is the single highest-severity migration defect" — the grant is correctly service_role-only | None (DB ready) |
| G6 | Batch attribution on finalize | **PARTIAL** | **Heuristic, not linked.** 082's immutable `order_item` persists no hold linkage, so finalize re-derives the batch from the buyer's reservation | `085:1985-1999` + comment `:1988-1992` (E-58) | E-58 | Optional 093+ that persists `hold_ids` on the order | G5 | MEDIUM — with multiple batches per ticket-type/session the heuristic can pick a different batch than the one held. Acceptable at single-batch scale; audit before multi-batch events | Accept at MVP scale; file for multi-batch |
| G6a | Re-verify `issue_ticket_atoms`' comp/door/import service_role callers | **NOT IMPLEMENTED** | PFA-21's kernel USAGE grant made dormant service_role EXECUTE grants (077/081/082/083) runtime-live; the boundary was **accepted and disclosed, not narrowed** | `085:2160-2166` (the disclosure in the bytes) | **E-59** (`POST_FREEZE_AMENDMENTS.md:2037`, obligation `:2049`) — an explicit forward obligation **"at native-issuance activation"** | Verify (or author) that every comp/door/import caller of `issue_ticket_atoms` enforces its own authority in-DB | E3, G1 | **MEDIUM — a security obligation the corpus names for exactly this gate.** The mint's non-`issue` causes (`comp`, `door_sale`, `import`, `083:479`) have no in-DB principal check today | Complete the verification before flipping E3; owner sign-off if grants are tightened |
| G6b | In-DB principal checks on un-parked bodies | **NOT IMPLEMENTED** | Parked bodies rely on edge-fronting for authority today | — | **E-47(a)** (`POST_FREEZE_AMENDMENTS.md:1869`) — "un-parking packages **must add in-DB principal checks** to parked bodies" | When M1 un-parks `provision_signing_key`, add the principal check in the body, not only in the edge | G1 | MEDIUM — a trap for the 093 author | Must be satisfied inside the 093 that un-parks G1 |
| G6c | Custody head/tail lock discipline | **COMPLETE** (verify at activation) | The mint takes the rank-1 session lock and the batch lock; the head-is-tail trigger is live | `083:535-556`; trigger `079:194` | **E-22** (`POST_FREEZE_AMENDMENTS.md:1547`) — every ledger-appending engine MUST hold the atom's `kernel.tickets` row `FOR UPDATE` across head write + append | Re-verify at activation (the mint inserts head+tail in one statement pair, so no naked append exists) | G4 | LOW | Verification only |
| G7 | Ticket read by its owner | **COMPLETE** | `kernel.tickets` owner-scoped SELECT policy; `kernel` is exposed | policy `079:737-741`; grant `079:735`; exposure `DEPLOYMENT_RECORD:19-21` | RLS §7.x | none | C3 | LOW | None — callable today |
| G8 | Ticket rendered with event/venue context | **CONFIG-MISSING** | Cross-schema embedding needs both schemas exposed | `catalog` not exposed (`DEPLOYMENT_RECORD:19-21`) | — | Expose `catalog` | C1 | LOW | Operational config change |
| G9 | Custody history readable | **NOT IMPLEMENTED** (by design) | `kernel.ticket_ownership_log` is RLS-on with **zero policies** and no grant | `079:751-754` | RLS §7; reads arrive via `market.get_ticket_history` (088) | `market` exposure + client, if history is wanted | — | LOW — not required for issuance | Optional |
| G10 | QR / entry credential | **EDGE-MISSING** | `credential-sign` does not exist | `PHASE_2_EDGE_FUNCTION_SPEC.md:399-437` | EDGE_FUNCTION_SPEC §5 (`:1264-1598`) | Author the edge (Class A, owner-only, reads only, KMS sign) | G3 | MEDIUM | **NOT required for a ticket to exist or be shown** — see §6. Required for door scanning |
| G11 | Apple Wallet pass | **PFA-BLOCKED** | Every wallet RPC is a fail-closed stub | `083:611-690` (raises at `:621`, `:636`, `:650`, `:665`, `:680`) | **PFA-20** — bearer-token crypto unratified | Owner crypto ruling + 093+ bodies + pass-type cert | G1, G3 | LOW — out of scope for issuance | Not required |

### H. NOTIFICATION OF THE BUYER

| # | CAPABILITY | STATUS | EXISTING ARTIFACT | SOURCE LOCATION | FROZEN ARCHITECTURE REFERENCE | MISSING WORK | DEPENDENCY | RISK | PRODUCTION ACTIVATION REQUIREMENT |
|---|---|---|---|---|---|---|---|---|---|
| H1 | Notification registry + templates | **COMPLETE** | 31 `notification_type` rows incl. `purchase_confirmed`, `ticket_ready`; en-US in_app + push templates | `supabase/migrations/092_notify_reduced.sql:236-275` (types), `:281+` (templates) | NOTIF §3.4 | none | — | LOW | None |
| H2 | `purchase_confirmed` on the **primary** rail | **NOT IMPLEMENTED** | `venue.finalize_primary_order` emits **nothing** — the whole body `085:1881-2078` contains no `notify.emit_event*` call. The only shipped producer is the **resale** rail | producer `088:1340` (market_sale, not primary); absence provable by `grep 'notify.emit' 085` → refund arms only (`085:327`, `:1388`, `:1430`) | **E-161** (`POST_FREEZE_AMENDMENTS.md:2520`) → `NOTIFY_PRODUCER_PARITY` (`:2525`) | Body-only `CREATE OR REPLACE` in a **093+** migration | G5 | MEDIUM — buyer gets no confirmation. **See §7 disagreement D3**: E-161 lists `purchase_confirmed` as *shipped* (088), which is true only for resale | 093+ body amendment |
| H3 | `ticket_ready` | **NOT IMPLEMENTED** | Named explicitly in E-161(b) as a 083 producer that shipped without its emit clause | `POST_FREEZE_AMENDMENTS.md:2520` — "`ticket_ready` 083" | E-161 / `NOTIFY_PRODUCER_PARITY` | 093+ body amendment to `kernel.issue_ticket_atoms` | G4 | MEDIUM | 093+ body amendment |
| H4 | `ownership_changed` on mint | **NOT IMPLEMENTED** | Emitted only by the 088 transfer engine | `088:726` | E-161 | 093+ body amendment (if the mint should notify) | G4 | LOW — arguably `ticket_ready` covers the mint case | Owner/product call |
| H5 | In-app inbox delivery | **COMPLETE** | `notify-drain-outbox` cron `*/2` is live and succeeding | `092:1155-1160`; production state `DEPLOYMENT_RECORD:36-38` | NOTIF §4 | none | H2, H3 | LOW | None — the moment a producer emits, the inbox works |
| H6 | Push delivery | **CONFIG-MISSING** + **EDGE-MISSING** | `claim_deliveries` fail-closed on the NULL lease; `notify-dispatch`/`notify-receipts` unauthored and unscheduled | `DEPLOYMENT_RECORD:37-38`; `FINAL_STATE_CENSUS` §5 "NOT scheduled (parked …)" | E-154, E-158 | Owner lease value + two edge functions + two cron rows + Expo creds | E5, H2 | LOW — issuance works without push | Optional for first activation |
| H7 | Email delivery | **OWNER-DECISION-BLOCKED** | Every E-channel delivery born `suppressed / channel_unavailable` | `FINAL_STATE_CENSUS` §9 (`EMAIL_GO_LIVE`) | N1 / O-N3 | Sending domain + DMARC + provider key + templates | — | LOW | Not required for issuance |

### I. VENUE-SIDE VISIBILITY (post-sale)

| # | CAPABILITY | STATUS | EXISTING ARTIFACT | SOURCE LOCATION | FROZEN ARCHITECTURE REFERENCE | MISSING WORK | DEPENDENCY | RISK | PRODUCTION ACTIVATION REQUIREMENT |
|---|---|---|---|---|---|---|---|---|---|
| I1 | Venue/org staff see orders | **UI-MISSING** | `venue_order_sel_org` + `venue_order_sel_venue` RLS policies, `grant select … to authenticated` | `082:129`, `:144-150`, `:151-158` | RLS §6.1 | `venue` exposure + client | C2 | LOW — works via a plain PostgREST table read | Expose `venue`; build UI |
| I2 | Staff see order line items | **UI-MISSING** | `venue_order_item_sel_org` / `_sel_venue` | `082:206`, `:216`, `:223` | RLS §6.2 | Same | C2 | LOW | Same |
| I3 | Buyer sees own orders | **UI-MISSING** | `venue_order_sel_owner`, `venue_order_item_sel_owner` | `082:140`, `:210` | RLS §6.1 | Same | C2 | LOW | Same |
| I4 | **Attendee roster** (`venue.list_attendees`) | **PFA-BLOCKED** | After authz + filter validation the body **raises unconditionally** — zero rows, zero data | `supabase/migrations/087_venue_settlement_and_export.sql:1359-1404`; the terminal raise at `:1401-1402` | **PFA-28** — `CRM_CUSTOMER_REF_CRYPTO`; the projection carries `customer_ref` (HMAC-SHA256) with no ratified in-DB mechanism | Owner HMAC ruling + 093+ body replacement | — | **MEDIUM-HIGH** — "venue sees attendee" is the last journey step and it is dead. Mitigated: I1/I2 give an order-level view without names | Owner ruling + 093+ migration, **or** ship with the order-level view only |
| I5 | Single-attendee lookup | **PFA-BLOCKED** | Same fail-closed park | `087:1417-1430` | PFA-28 | Same as I4 | I4 | MEDIUM | Same as I4 |
| I6 | CSV / CRM export | **PFA-BLOCKED** + **EDGE-MISSING** | `venue.request_export` etc. exist; `crm-export-worker` unauthored; the two cron ticks are live but fail-closed no-ops on the absent Vault secret | RPCs `087:681`, `:863`, `:934`; cron state `DEPLOYMENT_RECORD:31-33` | PFA-28 | Owner ruling + worker edge + `crm_export_worker_secret` | I4 | LOW — not on the issuance path | Not required for issuance |
| I7 | Venue dashboard UI | **UI-MISSING** | **Does not exist as code anywhere.** Only the 1,641-line spec | `docs/architecture/PHASE_2_VENUE_DASHBOARD_PRODUCT_SPEC.md` | VENUE_DASHBOARD_PRODUCT_SPEC §6–§9, §20 read index | Entire greenfield build | C1, C2, C5, C6 | **HIGH — largest single work item** | Build it |
| I8 | Buyer RN/web ticketing UI | **UI-MISSING** | **Zero primary-ticketing client surface exists.** The only Phase-2 client code is two `kernel.identity_ext` deletion probes | `app/settings/index.tsx:117`; `src/screens/PlaceBidScreen.tsx:116` — and nothing else | `PHASE_2_REACT_NATIVE_PRODUCT_SPEC.md` §4 (consumer flows) | Entire greenfield build | C3, C5 | **HIGH** | Build it |

### J. MONEY-OUT (explicitly OUT of the issuance critical path — see §6)

| # | CAPABILITY | STATUS | EXISTING ARTIFACT | SOURCE LOCATION | FROZEN ARCHITECTURE REFERENCE | MISSING WORK | DEPENDENCY | RISK | PRODUCTION ACTIVATION REQUIREMENT |
|---|---|---|---|---|---|---|---|---|---|
| J1 | Settlement open/close | **COMPLETE** (DB), manual | `venue.open_settlement` (`venue_finance`/`org_finance` authority), `kernel.close_settlement` | `087:227-269`, `:289` | RPC §10.1–10.2; SSCAS #4 | Client surface | I7 | LOW — **not triggered by finalize**; nothing auto-creates a settlement | Not required for issuance |
| J2 | Org payout request | **COMPLETE** (DB) | `kernel.request_org_payout` | `087:408` | RPC §10.3 | — | J1 | LOW | Not required for issuance |
| J3 | `payout-execute` edge | **EDGE-MISSING** | Does not exist | `PHASE_2_EDGE_FUNCTION_SPEC.md:461-527` | EDGE_FUNCTION_SPEC | Author + deploy; sole writer of payout `failed` | J2, E7 | LOW for issuance | **Not required for issuance** |
| J4 | `refund-execute` edge | **EDGE-MISSING** | Does not exist; DB bodies (`kernel.refund_primary_order`, `request_order_refund`, `approve_refund_request`) are real | `085:457`, `:850`, `:1089`; spec `EDGE_FUNCTION_SPEC:528-578` | PFA-23 | Author + deploy; owner values for `refund.*` | E7, F4 | **MEDIUM — a policy risk, not a technical one.** Selling tickets with no refund path is a consumer-protection exposure even though it is not a technical blocker | Strongly recommended before real sales, but not technically required |
| J5 | Promoter commission payout | **OWNER-DECISION-BLOCKED** | Every `promoter_commission` payout mints HELD `unfunded_settlement` | `090:1401` (`kernel.pay_promoter_commission`); `FINAL_STATE_CENSUS` §8 | `COMMISSION_FUNDING_SOURCE` (Option B countersigned; implementation OPEN) | The 13-item proof list | J3 | LOW | Not required for issuance |

---

## 2. HEADLINE COUNT BY STATUS

| STATUS | Count | Rows |
|---|---|---|
| UI-MISSING | 21 | A3, A4, A5, A6, A7, B1, B2, B3, B4, B5, B6, B7, B9, B10, D4, D5, I1, I2, I3, I7, I8 |
| COMPLETE | 16 | A1, A8, B8, B11, C3, C4, F1, G2, G4, G5, G6c, G7, H1, H5, J1, J2 |
| NOT IMPLEMENTED | 11 | C5, C6, E1, E2, F7, G6a, G6b, G9, H2, H3, H4 |
| CONFIG-MISSING | 9 | B3a, C1, C2, E3, E4, E5, E6, E7, G8, H6 |
| EDGE-MISSING | 8 | F2, F3, F5, F6, F9, G10, J3, J4 |
| PFA-BLOCKED | 6 | A2 (PFA-4), G1 (PFA-18A), G11 (PFA-20), I4, I5, I6 (PFA-28) |
| OWNER-DECISION-BLOCKED | 6 | D2 (PFA-14), F4, F10, F12, H7, J5 |
| PARTIAL | 3 | F11, G6, I6-order-view |
| SCHEMA-ONLY | 1 | D1 |
| SECRET/CREDENTIAL-MISSING | 1 | G3 |
| CODE-ONLY | 0 | — |

*(A row may carry a compound status where the DB half and the client half differ; it is counted under its blocking
half. B3a is counted under CONFIG-MISSING but is the only **fail-OPEN** row in the document.)*

**The shape of the gap in one sentence:** the database is done, the client does not exist, and five owner
decisions plus one 093+ migration stand between here and a first ticket.

---

## 3. SECTION (a) — EVERY CONFIG KEY THAT MUST CHANGE, AND ITS CURRENT VALUE

Production seeds 43 keys. Only these matter for primary issuance.

### Keys that MUST change (blocking)

| Key | Current value | Where read | Required value | How it changes |
|---|---|---|---|---|
| `inventory.hold_ttl_interval` | **ROW DOES NOT EXIST** | `081:627-631` | an interval (owner policy) | **093+ migration to create the row**, then `catalog.set_platform_config`. `set_platform_config` raises `unknown_key` on a missing row (`078:1099-1102`) — it cannot create keys |
| `inventory.per_user_active_hold_max` | **ROW DOES NOT EXIST** | `081:611-616` | an integer > 0 | Same — 093+ migration then owner value |
| `door.schedule_move_grace_interval` | **ROW DOES NOT EXIST** | the 079 schedule-move guard (`079:518`) | an interval (owner policy) | **093+ migration to create the row + fail-safe the guard.** PFA-9 files this as a live FAIL-OPEN (`POST_FREEZE_AMENDMENTS.md:626`) — absent config ⇒ the guard never fires ⇒ a published session's schedule moves freely once atoms exist |
| `feature.native_issuance_enabled` | `false` (`078:1522`) | `081:583`, `081:701`, `083:497` | `true` | `catalog.set_platform_config` — **flip LAST** |
| `deletion.refund_possible_window_hours` | `null` (`085:2185-2188`) | BP-12 deletion blocker | a number of hours | `catalog.set_platform_config`. **Armed by activation:** inert while no `paid` order exists; blocks every affected account deletion from the first sale onward (PFA-22, `:1915-1918`) |

### Keys that may change (non-blocking for issuance)

| Key | Current value | Blocks | Needed for issuance? |
|---|---|---|---|
| `notify.delivery_lease_interval` | `null` | push claim — `claim_deliveries` fails closed | No — only if push notices ship |
| `retention.backup_window_days` | `null` (`078:1587`) | the purge stamp | No |
| `refund.*` (7 keys, `078:1541-1549`) | `null` except `refund.scanned_atom_policy='platform_review'` | refund execution | No — see §6 |
| `payout.*` (4 keys, `078:1551-1554`) | `null` | payout execution | No — see §6 |
| `authn.money_action_max_age_seconds`, `authn.money_action_required_aal` | `null` | money step-up | No |
| `authn.money_role_maturity_hours` | `72` (PROVISIONAL) | money role maturity | No |
| `wallet.apple.enabled` | `false` (`078:1525`) | Wallet | No |
| `feature.native_scanning_enabled` | `false` (`078:1523`) | door | No |
| `feature.native_resale_enabled` | `false` (`078:1524`) | resale | No |
| `credential.wallet_exp_skew` / `wallet_default_span` / `app_ttl_interval` | `'6 hours'`/`'6 hours'`/`'4 hours'` | — | Already correct |

### Non-config operational settings that must change

| Setting | Current | Required |
|---|---|---|
| PostgREST exposed schemas | `public, graphql_public, kernel` | `public, graphql_public, kernel, catalog, venue` |
| `public.admin_users` rows | unverified | confirm the intended platform admins |

---

## 4. SECTION (b) — EVERY EDGE FUNCTION REQUIRED, AND WHETHER IT EXISTS

`supabase/functions/` contains exactly 11 legacy functions plus `_shared`: `auto-finalize-auctions`,
`confirm-and-release`, `confirm-payment`, `create-connect-account`, `create-payment-intent`, `delete-account`,
`enforce-transfer-expiry`, `notify-report`, `notify-transfer`, `send-push`, `stripe-webhook`.
**Confirmed: no Phase-2 edge function exists on disk or in production.**

| Function | Exists? | Required for primary issuance? | Spec | Blocking notes |
|---|---|---|---|---|
| `primary-checkout` | **NO** | **YES — blocking** | `PHASE_2_EDGE_FUNCTION_SPEC.md:355-397` | Class A. Rate limit 5/60 fail-closed. PI metadata `rail:'native_primary'`. Two idempotency layers (RPC `command_key` + salted PI key) |
| `stripe-webhook` native branches | Function exists, **branches do NOT** | **YES — blocking** | `:1196-1262` | Extend, never fork. Route on `metadata.rail`. Must add the "absent `rail` ⇒ `external`" default (F7) |
| `signing-key-provision` | **NO** | **YES — blocking** (or an equivalent provisioning path) | `:579-592` | Blocked upstream by PFA-18A regardless |
| `credential-sign` | **NO** | **NO** — required for *scanning*, not issuance | `:399-437` | See §6. Owner-only, reads only, no state write (`:415`) |
| `promoter-code-preview` | **NO** | NO — optional | `:725-758` | `verify_jwt:false`; one of only four authorized unauthenticated surfaces (`:1694-1697`) |
| `refund-execute` | **NO** | NO — technically. **Recommended** as consumer protection | `:528-578` | See J4 |
| `payout-execute` | **NO** | **NO** | `:461-527` | See §6 |
| `notify-dispatch` / `notify-receipts` | **NO** | NO — push only | census §6 | Also need owner-named header + Vault secret |
| `crm-export-worker` | **NO** | NO | census §6 | PFA-28 blocked anyway |
| `resale-checkout`, `door-session`, `door-manifest`, `wallet-pass-*`, `pass-cert-provision`, `connect-onboarding` | **NO** | NO | — | Other rails |

**Reusable `_shared` helpers today:** `stripe.ts` (`STRIPE_API_VERSION:34`, `stripeFetch:59`), `money.ts`
(`totalMismatch:94`, `feeBreakdown:99`), `sentry.ts` (`captureException:78`), `payouts.ts`, `payout-logic.ts`,
`payout-policy.ts`.
**NOT shared and must be lifted or copied:** `checkRateLimit` (`create-payment-intent/index.ts:31`),
`getAuthenticatedUser` (`:96`), `ensureStripeCustomerAndEphemeralKey` (`:132`), CORS/security headers (`:64-86`),
`logStage` (`:16`), PI idempotency-key salting (`:409-416`, `:509-511`), `timingSafeEqual`
(`stripe-webhook/index.ts:46`), `verifyStripeSignature` (`:72`), the webhook lease calls (`:182`, `:232`, `:237`).

**Trap:** every existing function builds its Supabase client from `SUPABASE_SERVICE_ROLE_KEY`. Copying
`create-payment-intent` verbatim into `primary-checkout` is a **Class A violation** (EA-1, tests T-1/T-2/T-4).
The RPC client must be built from the caller's `Authorization` header; service_role is for Stripe and the limiter only.

---

## 5. SECTION (c) — WHAT IS ALREADY DONE (DO NOT REBUILD)

**The entire database substrate for the primary journey is built, tested, and LIVE IN PRODUCTION.**
17 migrations, 17 rollbacks, pgTAP suites 140–157 (2,622 assertions green), applied 2026-09-02 20:41–20:43Z.

Already done and working:

1. **Five schemas** with a deny-by-default GRANT wall (`076:66-95`).
2. **Identity/org plane** — `kernel.organization`, `org_member`, `org_invite`, `platform_role`, `admin_audit`, `approval_request`, plus create/update/invite/accept/change-role/remove/revoke RPCs (077).
3. **Catalog plane** — `catalog.venue`, `event`, `event_session`, `platform_config`, `resale_policy`, with create/approve/update RPCs and correct anon RLS (078). The R3-3a lexicographic bug is fixed.
4. **Config plane** — 43 keys seeded, append-only, versioned, with a `platform_admin`-gated writer (`078:1048`, `:1520-1590`).
5. **Two platform sentinel identities** (SN-VOID, SN-SYSTEM) with profile labels (`078:1600-1660`).
6. **Ticket atom + custody ledger** — `kernel.tickets`, `ticket_ownership_log`, head-is-tail trigger, owner-scoped RLS, expiry sweep (079).
7. **Staff roles + all four authority predicates** (080).
8. **Full inventory substrate** — `ticket_type`, `inventory_batch`, `batch_shard`, `inventory_movement`, `inventory_hold` + 8 RPCs, with the C27 oversell choke-point implemented as `FOR UPDATE` + CHECK (081).
9. **`catalog.publish_event`** with forward-only transitions and the empty-inventory refusal (`081:899`).
10. **Order container** — `venue."order"`, `order_item`, immutability guards, attribution-candidate freeze trigger, and a complete, idempotent, price-snapshotting `create_primary_checkout` (082).
11. **CRM consent plane** — `kernel.org_contact_consent` + grant/withdraw/list RPCs (082).
12. **The mint engine** — `kernel.issue_ticket_atoms`, session-locked serial draw, scope-coherent key check, C27 backstop, idempotent (083).
13. **`venue.finalize_primary_order`** — the only function that turns money into tickets. Payment-is-authority, coverage + refund checks, deterministic batch pre-lock (no AB-BA deadlock), E-40 live-hold conversion, replay-safe, service_role-only (085).
14. **`kernel.payment_native`** link ledger, append-only, with the order/sale XOR (085).
15. **Money plane** — refunds, payouts, obligations, approval requests, 23 RPCs (085) — built, dark.
16. **Settlement + export** (087), **door/scan** (086), **market rail** (088-089), **promoter engine** (090), **notify plane** (092) — all built, all dark.
17. **PFA-15 / PFA-21 CLOSED** — `service_role` has USAGE on `venue` and `kernel` (`085:2088-2095`), so the webhook can reach `finalize_primary_order` and `cancel_pending_order`.
18. **19 cron jobs live and succeeding**, including `sweep-expired-inventory-holds` and `notify-drain-outbox`.
19. **`kernel` exposed over PostgREST**, anon-walled (42501) — verified in the deployment window.
20. **Notification registry** — 31 types and their en-US in_app/push templates, including `purchase_confirmed` and `ticket_ready`.

**In one line: nobody needs to write inventory, order, mint, or finalize logic. It exists, it is correct, it is deployed, and it is refusing to run on purpose.**

---

## 6. PAYMENT COLLECTION vs. SETTLEMENT / PAYOUT EXECUTION

**QUESTION:** can primary issuance be activated WITHOUT turning on the native payout rail?

**ANSWER: YES — the frozen design separates them cleanly, and the shipped bytes confirm it.**

Evidence from the shipped bytes (the authority):

1. **`venue.finalize_primary_order` creates no payout and no settlement.** Its complete write set is:
   `venue."order".status → 'paid'`, `kernel.tickets` + `ticket_ownership_log` (via the mint),
   `venue.inventory_batch` counters, `venue.inventory_movement`, `kernel.payment_native`, and a call to the
   non-raising `venue.resolve_order_attribution` stub. There is **no `kernel.payout` insert and no
   `venue.settlement` touch** anywhere in `085:1881-2078`.
2. **Settlement is manual and separately authorized.** `venue.open_settlement` requires an explicit call by
   `venue_finance` / `org_finance` / `org_owner` (`087:227-240`). Nothing triggers it from a paid order.
3. **Payout execution lives entirely in an unwritten edge function.** `PHASE_2_FINAL_STATE_CENSUS.md` §8:
   "Native money (085) | DARK — refund/payout EXECUTION are edge artifacts … `refund-execute`/`payout-execute`
   not deployed". Money-in is the `public.payments` + Stripe path, untouched by the payout rail.
4. **The rail matrix already separates them.** `PHASE2_RELEASE_READINESS_REPORT.md` §13 lists
   "PRIMARY INVENTORY / ISSUANCE" and "PAYOUTS (native)" as distinct rows with distinct blockers; the issuance
   row's blockers are "flag; primary-checkout + webhook branch + credential-sign + KMS" — **no payout item**.
5. **The edge spec assigns them different packages.** Issuance is 082+083; `payout-execute`/`refund-execute` are
   085 (`PHASE_2_EDGE_FUNCTION_SPEC.md:1775-1780`). Neither appears in the issuance dataflow (`:1249-1254`, `:1637-1646`).

6. **The amendment register agrees, and says so structurally.** PFA-15's forward obligation names exactly two
   reachability targets — `venue.cancel_pending_order` and `venue.finalize_primary_order`
   (`POST_FREEZE_AMENDMENTS.md:1117-1121`). Neither `refund-execute` nor `payout-execute` appears as a
   precondition of `create_primary_checkout`, `finalize_primary_order`, or `issue_ticket_atoms` anywhere in the
   2,547-line register. PFA-15's own impact line reads the dependency the other way: "none while native issuance
   is dark (no orders ⇒ no webhook ⇒ the path is never exercised)" (`:1086-1087`).
7. **The refund rail is independently dark by config alone**, with no reverse dependency: "Inert today: all D-3
   keys are NULL, so no auto tier is satisfiable until the owner sets values" (E-52, `:1953-1954`).
8. **The payout rail is held shut at the money layer while every upstream object works** — commission payouts are
   minted and REMAIN HELD `unfunded_settlement` (`COMMISSION_FUNDING_SOURCE`, `:2482`). Money accrues and is
   recorded correctly; nothing leaves. That is precisely a design that lets sales run before disbursement runs.

**Where the money physically sits during a payout-dark activation:** funds land in the platform Stripe account via
the ordinary PI path. Organizers are not paid by the native rail; they must be settled out-of-band until J1–J3 ship.
**This is a commercial decision, not a technical blocker** — but it must be a conscious one, and E-138 sharpens it:

> "**no package writes a primary-revenue settlement line**, so an event settlement's gross is 0, the commission
> debit drives `net_minor` negative and 087's `close_settlement` mints no org payout (`if v_net > 0`) and carries
> nothing forward — the org's debit is recorded but never collected." — `POST_FREEZE_AMENDMENTS.md:2469`

So settlement is not merely "switched off": with primary revenue never reaching a settlement line, an event's
settlement is *structurally empty*. Turning the payout rail on later is therefore additional work, not a flag flip.

**Three caveats that are NOT payout-rail dependencies but should be decided alongside:**

- **`deletion.refund_possible_window_hours` (E4).** The single coupling that activation actually creates. The
  first `paid` order arms the BP-12 blocker; until the owner sets this value, affected account-deletion requests
  hang (PFA-22, `:1915-1918`). One value, set in the activation window. Explicitly **not** a refund-rail activation.

- **Refunds (J4).** Technically separable and genuinely not required. But selling tickets with no refund
  execution path is a consumer-protection exposure. The DB bodies are ready; only the edge is missing.
- **`public.payments` shape (F4).** This is *money-in* infrastructure, not payout — and it **is** blocking.
  Do not mistake it for a payout dependency.

**Corollary — a second correct separation:** `credential-sign` and the whole KMS signing *service* are NOT
required for issuance either. A ticket atom is fully issued, owned, and displayable without it
(`EDGE_FUNCTION_SPEC:1252`, `:415`, `:1517`). **But a `kernel.signing_key` ROW must exist**, because
`kernel.tickets.signing_key_id` is NOT NULL and both the mint and finalize resolve an active key before minting
(`083:517-533`, `085:1944-1960`). The distinction is exact:
**key row = blocking · signing service = not blocking · QR/door = later.**

---

## 7. WHERE THE CORPUS AND THE SHIPPED BYTES DISAGREE

| # | Disagreement | Corpus says | Bytes say | Resolution |
|---|---|---|---|---|
| D1 | Deployment state | "nothing of 076–092 is applied anywhere" (`FINAL_STATE_CENSUS` §10); "production remains at 20260902003623" (`RELEASE_READINESS` :5-7) | Applied to production 2026-09-02 20:43Z (`DEPLOYMENT_RECORD:14-17`) | **Bytes win.** Both ledgers are pre-apply drafts never revised |
| D2 | PFA-15 status | `082:466-476` says the service_role reachability boundary is "escalated to the owner as PFA-15" and unresolved | `085:2088-2095` grants `service_role` USAGE on `venue` and `kernel` (PFA-15/PFA-21, owner-signed) | **Bytes win.** PFA-15 is CLOSED; 082's comment is stale by three packages |
| D3 | `purchase_confirmed` producer parity | E-161 (`POST_FREEZE_AMENDMENTS.md:2520`) lists `purchase_confirmed` among the **13 shipped** producers (088) | 088's producer is the **market_sale / resale** arm (`088:1340`). The **primary** rail (`085:1881-2078`) emits nothing | **Bytes win.** E-161's tally is right per-type but hides a per-rail gap. `purchase_confirmed` has no primary-rail producer |
| D4 | `PUBLIC_PAYMENTS_NATIVE_SHAPE` scope | Filed as blocking "native resale/settlement" only — the amendment text names `market_sale.payment_id` and `dispute_native.payment_id` (`POST_FREEZE_AMENDMENTS.md:2392`; census §9 "088 owner forks") | `kernel.payment_native.payment_id` FKs `public.payments` (`085:41`) and `venue.finalize_primary_order` reads `public.payments` directly (`085:1917-1919`) — the **primary** rail has the identical dependency, and `public.payments.listing_id`/`seller_id` are NOT NULL (`000_baseline_schema.sql:972-974`) | **Bytes win.** It blocks PRIMARY too. Re-scope the obligation |
| D5 | `primary-checkout` calls `reserve_primary_inventory` | Assumed in the task brief | The edge calls only `venue.create_primary_checkout` (`EDGE_FUNCTION_SPEC:367-368`); reservation is a **prior client-direct PostgREST call** (`RPC_FUNCTION_CONTRACTS` §5.3, actor `auth.uid()`) | **Spec + bytes agree**; the brief's assumption is corrected. This is why `venue` exposure (C2) is blocking |
| D6 | `public.payments.order_id` column | `EDGE_FUNCTION_SPEC:374` says "the new `order_id` linkage column" | `EDGE_FUNCTION_SPEC:1811-1817` (recon #1) supersedes: no column is ever added to frozen `public.payments`; the link lives in `kernel.payment_native` | **Later spec section wins**; matches the shipped 085 DDL |
| D7 | `rail`-absent default | Spec never states that a PI with no `rail` metadata is `external` | Live webhook branches on `metadata.mode` (`stripe-webhook/index.ts:376-395`) and live `create-payment-intent` sets no `rail` (`:520-525`) | **Gap in the corpus.** Must be written explicitly (F7) or the legacy rail regresses |

---

## 8. SECTION (d) — CLASSIFYING EVERY NEW DB NEED

### IS A 093+ MIGRATION NEEDED AT ALL?

# **YES — unambiguously. Three separate, independent, hard requirements.**

There is no configuration-only, exposure-only, or edge-only path to primary issuance. Each item below is a
`CREATE OR REPLACE` or an `INSERT`/`ALTER` that only a migration can perform.

| # | Need | Why a migration is unavoidable | Classification |
|---|---|---|---|
| **M1** | Un-park `kernel.provision_signing_key` (and `rotate_signing_key`) | The body is a hard `raise` (`083:381`, `:391`). No config, flag, role, or edge can make it return. `kernel.tickets.signing_key_id` is NOT NULL and both the mint and finalize require an ACTIVE key (`083:517-533`, `085:1944-1960`). **Without this, zero tickets can ever be issued.** | **OWNER POLICY DECISION → then POST-FREEZE AMENDMENT.** PFA-18A preserved the dual-control *requirement* and rejected single-control fallback. The owner must first ratify a credential-compatible dual-control mechanism; only then may a 093+ author the real bodies |
| **M2** | Seed the three unseeded PFA-9 CLASS A rows — `inventory.hold_ttl_interval`, `inventory.per_user_active_hold_max`, `door.schedule_move_grace_interval` — and fail-safe 079's schedule-move guard | `catalog.set_platform_config` raises `unknown_key` for a key with no row (`078:1099-1102`) — **it cannot create keys, by design**. The first two are read on every reserve (`081:611-635`) and fail CLOSED; the third is a live **fail-OPEN** (`POST_FREEZE_AMENDMENTS.md:626`) that also needs a body change | **IMPLEMENTATION FOLLOW-UP + OPERATIONAL CONFIG.** E-28 (`:1624`) and PFA-9 (`:591`) already anticipate this ("the VALUES are owner-owed forward"). The 093 seeds the rows `null` (the PFA-9 pattern); the owner then sets values. No new amendment needed for the seeds; the guard's fail-safe is a body-only fix PFA-9 already demands |
| **M3** | `public.payments` native shape | `listing_id NOT NULL → public.listings`, `seller_id NOT NULL → auth.users`, `mode CHECK IN ('buy_now','auction')` (`000_baseline_schema.sql:972-993`). A primary order has neither a listing nor an individual seller. The amendment explicitly forbids a fake listing row | **OWNER POLICY DECISION → then POST-FREEZE AMENDMENT.** `PUBLIC_PAYMENTS_NATIVE_SHAPE` (`POST_FREEZE_AMENDMENTS.md:2392`) is filed as "a deployment/live-rail compatibility decision owed before native money activation" — and per §7/D4 it binds PRIMARY, not just resale |

### Strongly recommended but not strictly blocking

| # | Need | Classification | Note |
|---|---|---|---|
| M4 | Emit `purchase_confirmed` + `ticket_ready` on the primary rail | **IMPLEMENTATION FOLLOW-UP** — E-161 / `NOTIFY_PRODUCER_PARITY` pre-authorizes body-only `CREATE OR REPLACE`; "no 092 byte changes" | Buyers otherwise get no confirmation at all |
| M5 | Un-park `venue.list_attendees` / `lookup_attendee` (PFA-28) | **OWNER POLICY DECISION → POST-FREEZE AMENDMENT** | Needs the `customer_ref` HMAC mechanism ruling. **Partially avoidable**: I1/I2 give an order-level venue view today |
| M6 | Persist `hold_ids` on the order to discharge the E-58 batch heuristic | **IMPLEMENTATION FOLLOW-UP** | Only matters with multiple batches per ticket-type/session |
| M7 | Order `source` parameter (E-39) | **POST-FREEZE AMENDMENT** (signature change) | Analytics fidelity only |
| M8 | An `anon` projection for ticket-type prices (E-30) | **OWNER POLICY DECISION** | Or accept a sign-in wall before prices |

### NOT needed as migrations

- PostgREST exposure of `catalog` + `venue` — **OPERATIONAL CONFIG**
- All flag and value flips — **OPERATIONAL CONFIG** via `catalog.set_platform_config`
- Every edge function — **IMPLEMENTATION FOLLOW-UP**, no DB change
- All client/UI work — **IMPLEMENTATION FOLLOW-UP**
- PFA-4 (`grant_platform_role`) — **off the critical path**; `public.admin_users` already supplies `platform_admin`

### Classification summary

| Class | Items |
|---|---|
| **OWNER POLICY DECISION** (must precede code) | M1 (PFA-18A dual control) · M3 (payments shape) · M5 (PFA-28 HMAC) · **F10 / E-39 (order `source`, due before activation)** · **D2 / PFA-14 (anon discovery)** · M8; plus the E1/E2/B3a/E4 values and the E3 flip authorization |
| **POST-FREEZE AMENDMENT** (freeze §4 filing required) | M1, M3, M5, M7 |
| **IMPLEMENTATION FOLLOW-UP** (already authorized) | M2, M4, M6; G6a (E-59 verification); G6b (E-47(a) in-DB checks); all edge functions; all UI; generated types |
| **OPERATIONAL CONFIG** (no code) | schema exposure (E-166); every flag/value flip; `public.admin_users` verification; KMS/IAM provisioning |

---

## 9. THE CRITICAL PATH FOR A PRIMARY-ISSUANCE-ONLY ACTIVATION

Ordered. Each step is blocked by the one above it.

**Five owner decisions gate everything** — they are the true long pole, not the code:

1. **OWNER: ratify a credential dual-control mechanism (PFA-18A).** Nothing downstream can proceed. *(M1)*
2. **OWNER: decide the `public.payments` native shape (`PUBLIC_PAYMENTS_NATIVE_SHAPE`).** *(M3)*
3. **OWNER: choose a KMS provider + signing algorithm.** *(G3)*
4. **OWNER: rule on `venue."order".source` (E-39 — explicitly due before activation).** *(F10)*
5. **OWNER: rule on anonymous discovery (PFA-14) — public projection, or authenticated-only launch.** *(D2)*

Then:

6. **Author migration 093** carrying: the real `provision_signing_key`/`rotate_signing_key` bodies **with in-DB
   principal checks** (E-47(a)); the `public.payments` shape change; the two `inventory.*` registry rows; the
   `door.schedule_move_grace_interval` row **plus the fail-safe for 079's schedule-move guard**; and the
   primary-rail `purchase_confirmed` / `ticket_ready` emit clauses. *(M1+M2+M3+M4+B3a+G6b)*
7. **Operational: expose `catalog` and `venue` over PostgREST** (E-166). *(C1, C2)*
8. **Author the edge functions:** `primary-checkout`, the `stripe-webhook` native branches **with the
   absent-`rail`⇒`external` default**, and `signing-key-provision`. *(F2, F5, F7, G3)*
9. **Provision at least one ACTIVE `kernel.signing_key`** for the event/venue/global scope. *(G1)*
10. **Set `inventory.hold_ttl_interval`, `inventory.per_user_active_hold_max`, `door.schedule_move_grace_interval`,
    and `deletion.refund_possible_window_hours`.** *(E1, E2, B3a, E4)*
11. **Complete the E-59 verification** that every comp/door/import caller of `issue_ticket_atoms` enforces its own
    authority. *(G6a)*
12. **Build the client:** generated types, venue dashboard (events → ticket types → inventory → publish →
    orders), buyer discovery → selection → checkout → my-tickets. *(C5, C6, I7, I8)*
13. **Flip `feature.native_issuance_enabled` to `true` — LAST.** *(E3)*

**Explicitly NOT on this path:** `payout-execute`, `payout.*` / `refund.*` config values, settlement,
`credential-sign`, wallet, door/scanning, resale, CRM export, promoter payouts, PFA-4.

**Judgment call that should be made consciously, not by omission:** `refund-execute` (J4) is technically
off the path but is a consumer-protection exposure once real money is collected. The DB bodies are ready;
only the edge is missing.

---

*Analysis artifact. Cites `file:line` for every claim. Not an authority; files no amendment; changes no byte.*
