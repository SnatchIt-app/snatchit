# Phase 2 — Implementation Specification Cross-Spec Review

**The final consistency pass over the six implementation specs.** Its sole job: verify that the physical schema, migration plan, RLS spec, RPC contracts, edge-function spec, and React Native product spec **all describe the same system** — and to fix the inconsistencies **in the specifications only** (no code, no migrations, no production change).

**Specs under review (all repo-root, design-only):**
1. `PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md` · 2. `PHASE_2_SUPABASE_MIGRATION_PLAN.md` · 3. `PHASE_2_RLS_PERMISSION_SPEC.md` · 4. `PHASE_2_RPC_FUNCTION_CONTRACTS.md` · 5. `PHASE_2_EDGE_FUNCTION_SPEC.md` · 6. `PHASE_2_REACT_NATIVE_PRODUCT_SPEC.md`. Binding shared vocabulary: `PHASE_2_SPEC_FOUNDATION.md` (committed copy of the session SPEC_FOUNDATION).

**Method.** Six principal verification lenses (below), plus a mechanical cross-spec trace of every shared concept (names, states, roles, RPCs, edge→RPC calls) verified against the actual spec text line-by-line. Every claim here was grep-verified against the files, not inferred.

---

## 0. VERDICT

# IMPLEMENTATION SPECIFICATION READY

The six specs describe one coherent system. Seven cross-spec inconsistencies were found; **three were structural gaps and have been fixed in the schema spec by this review** (R2 `kernel.org_invite`, R3 door-freeze signal, R4 `p2p_transfer.completed`); two were already consistent (R5, R7); one is a documented-alias naming drift now pinned by a canonical registry (R1); one is a clarification that prevents a frozen-table change (R6). The remaining open items are **policy defaults**, not architectural gaps, and are given recommended values below. Every Gate-P decision (C26/C27/C33/C35/C36/C41/C42/D1–D3) is represented consistently across all specs that touch it. The frozen money core and live external marketplace are untouched by every spec.

An engineering team can begin implementation package-by-package (migration `071`→`086`): **the five propagation addenda in §5 are APPLIED and CLOSED** (pre-implementation consolidation session, 2026-08-24) — the migration/RLS/RPC/edge/RN specs all reflect the schema fixes this review made.

---

## 1. The verification board (six lenses)

| Lens | Verdict | One-line |
|---|---|---|
| Principal PostgreSQL Engineer | ✅ same system | Schema is the SoT; 44+2 tables; every RPC-only table has exactly one writer set; the C26/C27 proofs hold. Fixed: org_invite, door_open_at, p2p.completed. |
| Principal Supabase Engineer | ✅ same system | Migration `071–086` creates exactly the schema's tables, additively, flag-gated; text+CHECK enums match; phase0-chain precondition stated. Addenda A1–A5 applied (§5 CLOSED). |
| Principal Security Engineer | ✅ same system | RLS covers all tables; money/custody = RPC-only-write; C36 disjoint roles are structural; `has_*_role` is the only role test in both RLS and RPC; redacted history read consistent. |
| Principal Backend Engineer | ✅ same system | Every RPC maps to schema tables + an SSCAS member + lock order; no unnamed cross-aggregate txn; edge functions call RPCs, never bypass. Naming aliases pinned (R1). |
| Principal React Native Engineer | ✅ same system | Every UI state maps to a backend state after R2/R3/R4 fixes; product-language firewall intact; external marketplace preserved. |
| Principal Ticketing Product Engineer | ✅ same system | Two-rail honesty, resale modes, door/scan, comps, promoter all trace end-to-end; MVP scope (Miami, GA, no re-entry) held; deferrals are extension points, not holes. |

Chair (Staff Engineer): consolidated verdict **READY**; the §5 addenda are applied and closed.

---

## 2. Cross-spec consistency traces (the mechanical checks the brief mandated)

### 2.1 Renamed concepts — RESOLVED
| Concept | Schema | RLS | RPC | Edge | RN | Resolution |
|---|---|---|---|---|---|---|
| buyer inventory hold | `venue.reserve_inventory` | `reserve_inventory` | `reserve_primary_inventory` | — | via checkout | **Canonical = `venue.reserve_primary_inventory`** (R1); schema/RLS `reserve_inventory` is the documented alias. |
| staff/comp hold | (write-authority implies) | `reserve_inventory` | `create_inventory_hold` (§5.4) | — | — | Canonical = `venue.create_inventory_hold` (distinct authority); schema §3.2 write-authority note to add it (addendum A4). |
| release hold | `venue.release_hold` | `release_hold` | `release_inventory_hold` | `release_inventory_hold` | — | **Canonical = `venue.release_inventory_hold`**; `release_hold` alias. |
| create order | `venue.create_order` | `create_order` | `venue.create_primary_checkout` | `create_primary_checkout` | order flow | **Canonical = `venue.create_primary_checkout`**; `create_order` alias. |
| finalize/issue | `kernel.issue_ticket_atoms` (+`finalize_primary_order`) | — | `venue.finalize_primary_order`→`issue_ticket_atoms` | `finalize_primary_order` | SSCAS #1 | **Consistent** everywhere. |
| p2p "requested" | `initiated` | — | `initiated` | — | cites CDM `requested` | Canonical = physical **`initiated`**; conceptual `requested` (CDM §3.7) maps to it (R4). |
| trust tier | `inventory_kind`/`rail` | — | — | `inventory_kind` | `inventory_kind` | Both label the same 3-valued set; view uses `rail` discriminator = `inventory_kind` value. Consistent (R7). |

**Canonical function-name registry (BINDING for implementation):** `create_primary_checkout` · `reserve_primary_inventory` · `create_inventory_hold` · `release_inventory_hold` · `finalize_primary_order` · `issue_ticket_atoms` · `transfer_ticket_ownership` · `void_ticket_atom` · `lock_ticket`/`unlock_ticket` · `mark_ticket_scanned` · `create_p2p_transfer`/`accept_p2p_transfer`/`cancel_p2p_transfer` · `create_door_pin`/`revoke_door_pin`/`validate_ticket_online`/`record_scan`/`reconcile_offline_scans` · `close_settlement`/`request_org_payout` · admin set. Implementers MAY keep the schema alias as the physical function name but MUST document the mapping; UI/edge reference the canonical name.

### 2.2 State ↔ UI ↔ backend (every UI state has a home; every backend state is reachable)
| State machine | Canonical values | Schema | RPC | RN uses | Status |
|---|---|---|---|---|---|
| `kernel.tickets.state` | issued·active·scanned·voided·expired (NO refunded, D2) | ✅ | ✅ | ✅ | consistent |
| `kernel.tickets.resale_state` | none·listed·locked | ✅ | ✅ | ✅ | consistent |
| `venue.order` | pending·paid·partially_refunded·refunded·cancelled | ✅ | ✅ | ✅ | consistent |
| `market.market_sale.terminal_state` | pending·completed·compensated (C26) | ✅ | ✅ (`get_market_sale_status`) | ✅ | **consistent (recon #2 closed)** |
| `market.market_sale.sale_state` | initiated·paid_pending_transfer·settled | ✅ | ✅ | ✅ ("Finalizing…") | consistent |
| `market.p2p_transfer` | initiated·accepted·completed·declined·cancelled·expired | ✅ **(fixed: +completed)** | ✅ | ✅ (failed→cancelled+reason) | **FIXED — R4** |
| `catalog.event.status` | draft·announced·on_sale·live·completed·cancelled | ✅ | ✅ | ✅ | consistent |
| door-freeze | derived `is_transfer_frozen()` from `event_session.door_open_at` | ✅ **(fixed: +column+helper)** | ✅ (recheck) | ✅ (boolean) | **FIXED — R3** |
| `inventory_kind` | native·external_verified·external | ✅ | — | ✅ | consistent (R7) |

### 2.3 Roles → RLS → RPC (no role without RLS; no RLS without an API path)
- Three disjoint scope enums (org/venue/platform) are identical in schema §0.6, RLS §2, and the RPC `has_*_role` model. ✅
- Every RPC-only-write table named in RLS §5 has exactly one writer-RPC set in the RPC spec. ✅ (verified for `ticket_ownership_log`, `payment_native`, `payout`, `refund`, `inventory_batch/movement/hold`, `order`, `settlement`, `market_sale`, `p2p_transfer`, `scan`, `admin_audit`).
- Every role appears in at least one RLS matrix and is testable via a helper; no bare `role='…'` compare anywhere. ✅
- Platform sub-roles (`platform_admin/support/risk`) are consistent across schema/RLS/RPC; the least-privilege split (support=read, risk=fraud freeze/full chain, admin=approve/grant) is adopted (was RLS-flagged; ratified here, §4).

### 2.4 Edge → RPC (no edge bypasses an atomic transition)
- Edge spec rejected `scan-validate`, `scan-reconcile`, and a second webhook as belonging in DB-RPCs/the existing webhook. ✅
- Every edge function names the DB-RPC it calls: `primary-checkout`→`create_primary_checkout`; extended webhook→`finalize_primary_order`; `credential-sign`→KMS (+reads `signing_key`); `refund-execute`→`refund_primary_order`/`void_ticket_atom`; `payout-execute`→`close_settlement`/`request_org_payout`. ✅ No edge writes custody/money except via its RPC or by linking `public.payments`. ✅

### 2.5 Migration ↔ schema (additive, no old-client break, no marketplace regression)
- Migration `071–086` creates exactly the schema's schemas/tables; every package additive-only=YES, marketplace-change=NO. ✅
- **Addenda needed (§5):** the three schema fixes this review made (`org_invite`, `door_open_at`, `p2p.completed`) must be reflected in packages `072` (org_invite), `073`/session (door_open_at + `is_transfer_frozen` helper), `083` (p2p enum). Mechanical.

---

## 3. Resolved-inconsistency register

| ID | Inconsistency | Severity | Resolution | Where fixed |
|----|--------------|----------|-----------|-------------|
| **R1** | Inventory/order RPC names differ across specs (`reserve_inventory`/`reserve_primary_inventory`, `create_order`/`create_primary_checkout`, `release_hold`/`release_inventory_hold`) | Low (documented alias) | Canonical function-name registry (§2.1); aliases allowed if documented | This doc §2.1 (binding) |
| **R2** | `kernel.org_invite` used by RPC §2.2/§2.3 but defined in no schema/migration/RLS | **Med (structural gap)** | **Added `kernel.org_invite` table** (invite_id, org_id, invitee_ref/identity, role, status, invited_by, expires_at, command_key) + RLS org-scoped + migration `072` | ✅ schema §1.3b (applied); addendum A1/A2 |
| **R3** | Door-freeze signal referenced by RLS/RPC/edge/RN but no column in schema; `transfer_frozen` vs `door_open_at` unresolved | **Med (feature-blocking)** | **Canonical = `catalog.event_session.door_open_at` + derived `kernel.is_transfer_frozen(atom_id)` helper**; RPC's assumed `transfer_frozen` column replaced by the helper | ✅ schema §2.3 (applied); addendum A2/A3 |
| **R4** | `p2p_transfer` states inconsistent — schema lacked `completed`; CDM `requested` vs physical `initiated`; `failed` unhomed | **Med (state mismatch)** | **Added `completed` + `reason_code`**; canonical `initiated→accepted→completed\|declined\|cancelled\|expired`; `requested`≡`initiated`; `failed`→`cancelled`+reason | ✅ schema §4.5 (applied); addendum A5 |
| **R5** | `market_sale` status naming | — (already consistent) | `terminal_state` + `sale_state` + `paid_pending_since` identical across schema/RPC/RN | none needed |
| **R6** | Edge hinted `public.payments` might carry a native `order_id` column (would modify the FROZEN table) | **Med (frozen-core risk)** | **PINNED: no column added to `public.payments`.** Order resolution = Stripe PI `metadata.order_id` + `kernel.payment_native` link. Edge §9(1) assumption ratified as metadata-only | this doc §3 (binding); edge §9(1) |
| **R7** | `inventory_kind` values | — (already consistent) | `native·external_verified·external` across schema/RN; bridge `rail` discriminator = same set | none needed |

---

## 4. Policy defaults ratified (were "flagged for reconciliation"; not architectural)

These were deferred by the RLS/RPC authors as policy, not design. Ratified here with recommended MVP defaults so implementation is unblocked:

1. **Settlement-close authority:** `close_settlement` requires `has_org_role(org, [org_owner, org_finance])` (org-level finance owns settlement); `venue_finance` may *view* and *prepare* but not *close*. Rationale: money leaves at the org (payee) boundary.
2. **`request_org_payout` vs auto-disbursement:** MVP requires an explicit `request_org_payout` by `org_owner`/`org_finance` after `close_settlement` (no auto-fire) — matches the deferred-payout discipline and keeps a human in the money-out loop.
3. **`platform_support` refund ceiling:** `platform_support` may initiate a refund only up to a config ceiling (`catalog.platform_config` `support.refund_ceiling_minor`, default e.g. 100_00); above it requires `platform_admin`. Prevents low-tier over-authority.
4. **Platform sub-role split:** support = read/assist (redacted chain); risk = fraud freeze + full unredacted chain; admin = approvals, role grants, key ops, uncapped refunds. Adopted as in RLS §.
5. **`resale_state` on the kernel atom (R34 smell):** accepted as-is for MVP (a market fact physically on the atom) — the alternative (a separate overlay table) is a Gate-L refactor with no MVP benefit; documented, not changed.
6. **Native `market.bid`:** remains an extension point; native auctions in MVP reuse the frozen `public.bids` engine via the bridge. Confirmed consistent across schema/RLS/RPC.

---

## 5. Propagation addenda — **ALL FIVE CLOSED (pre-implementation consolidation session, 2026-08-24)**

All five addenda are now applied across the specs; the mechanical acceptance-gate search (org_invite ·
door_open_at · is_transfer_frozen · transfer_frozen · reserve_primary_inventory · create_inventory_hold ·
release_inventory_hold · requested/initiated/completed/failed · reason_code) returns zero stale live
assumptions and zero SCHEMA-GAP residual.

- **A1 — CLOSED.** `kernel.org_invite` canonical in schema §1.3b; created by migration `072`; RLS matrix §7.3b
  added (org-scoped + addressed-invitee, writes RPC-only, no self-escalation); RPC §2.2/§2.3 reference the
  table directly (stale schema-gap language removed; §16.1 marked CLOSED).
- **A2/A3 — CLOSED.** Canonical door-freeze = `catalog.event_session.door_open_at` (migration `073`) read ONLY
  via `kernel.is_transfer_frozen(atom_id)`; no stored `transfer_frozen` column anywhere; RLS §14.3/§15.2, RPC
  §12.4/§16.2, Edge §9.6, and RN §12(5) all updated to the one helper; edge never decides freeze independently;
  RN consumes a plain eligibility boolean.
- **A4 — CLOSED.** Canonical names `venue.reserve_primary_inventory` (buyer hold) · `venue.create_inventory_hold`
  (staff/comp/promoter hold, distinct authority) · `venue.release_inventory_hold` · `venue.create_primary_checkout`
  propagated into schema write-authority notes, migration flag table, and RLS §15.0; short names remain
  documented physical aliases per the §2.1 registry.
- **A5 — CLOSED.** `market.p2p_transfer` canonical physical states `initiated → accepted → completed | declined |
  cancelled | expired` + `reason_code` in schema §4.5, migration `083`, RPC §8, and RN (§4.5, state table,
  §12(3)); `requested` ≡ `initiated` (conceptual alias only); `failed` is NOT a state (= `cancelled` + reason).

Additionally closed in the same pass: RN §12 items 2 (pollable `get_market_sale_status`), 6 (`credential-sign`
cacheable-token contract), and 8 (redacted `get_ticket_history`) — each now points at its specified backend home.

---

## 6. What the review confirmed is NOT wrong (proportion)

- **No marketplace regression:** every spec preserves `public.*` (profiles/listings/bids/payments/transfers/disputes) untouched; native objects only *link* to `public.payments`; the external rail's `market.transfers` state machine is explicitly kept separate from native `market.p2p_transfer`.
- **No money-state duplication:** `public.payments` remains sole money-in; `kernel.payment_native` links, never re-charges; payouts/refunds ride the frozen idempotency discipline.
- **No ticket-state duplication:** `state` (custody terminal) and `resale_state` (market overlay) are orthogonal and documented as such; the ownership log is the sole custody SoT with `current_owner_id`/`credential_version` as pinned heads.
- **No edge bypassing an atomic transition:** all custody/money transitions are DB-RPCs; edges do only external I/O then call the RPC.
- **No role without RLS / RLS without an API path:** the 15-role × 43-table matrix is complete and every write path is an RPC.
- **Gate-P fully represented:** C26 (idempotency proof), C27 (counter authoritative + remaining≥0 proof), C33 (KMS key-ref, no secret on rows), C35 (server-derived principal + payment re-verify), C36 (disjoint structural roles), C41 (no-re-entry MVP + scan.direction hedge), C42 (nullable seat/unit hedge), D1/D2/D3 (SSCAS language, no refunded terminal, one cause-code registry) — all consistent across the specs that touch them.

---

## 7. Final

**IMPLEMENTATION SPECIFICATION READY.** Six specs, one system. Three structural inconsistencies fixed in-place (R2/R3/R4); the rest consistent, aliased, or ratified as policy. The five mechanical §5 addenda are APPLIED and CLOSED; begin implementation at migration `071` in the Phase A→K order, native issuance and resale flag-gated OFF until their gates clear. No code, migration, or production change was made by this specification phase.
