# Phase 2 — Money Authority Specification (Refund + Payout)

**Status:** BUILD-READY DELTA SPEC — **LIVE, not superseded.** **Design-only — no SQL, no migrations, no
implementation code.** Snippets inside this document are illustrative predicate prose, never DDL to copy.

> **RECONCILIATION BANNER (`AUTHZ-C1A` / `AUTHZ-C1B`; ratification rows `D14` · `D15` · `C75`).**
> **This document was excluded from the authz remediation pass that produced ratification rows C57 and C58,
> and until this pass it still stated the C-1a defect as its contract.** §6.2 branched the approval authority
> on `pending_approval` vs `pending_platform_review` — **two strings that are §6.1's return statuses and are
> stored nowhere** — so an implementer working from this file alone would have built a branch that routes
> **every** parked refund to the org arm, including the above-ceiling and consumed-atom cases the tier table
> deliberately sends to platform review. §6.6 defined the approval object with no tier column; §6.7 listed
> three added preconditions on `request_org_payout` and no grant-maturity conjunct; §8 contracted
> `set_org_payout_destination` without one. **All four are reconciled here** onto
> `(action, required_approver_class)` and `kernel.money_role_grant_matured(org_id)`, matching
> `PHASE_2_RPC_FUNCTION_CONTRACTS.md` §17.1/§17.2/§17.7 and `PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md`
> §1.13.2/§1.13.3. The itemized list of what changed is **§13**.
>
> **Why this file is live rather than retired** — stated because a reader may reasonably ask why a document a
> remediation pass skipped is still authority. `ARCHITECTURE_FREEZE.md` lists it by path in the covered set as
> an **owner-ruling delta (O-1, O-3)**, *"same tier as the implementation specs in the authority order …
> and covered by Rule 1"*. It is the ratified design behind record rows **O-1** and **O-3**. Record row **D6**
> applied **this document's** corrected §7.6 money matrix into the constitution and **rejected** the competing
> instruction from the role-model spec. And it is cited as live authority by RLS §11.3 (*"money spec §2.3 —
> replaces the corresponding §11.1 rows"*), by RPC §17.2 (*"The money spec §7.3 says…"*) and by schema §1.13
> (*"MONEY §6.6, §12 ADDITIVE-1"*). It carries no supersession banner and does not sit under `_superseded/`.
> **It is therefore reconciled, never retired** — retiring it would delete the only ratified statement of §4
> read scoping, §5 request-vs-execute, §7 thresholds and §8's control set, which no sibling document covers.
>
> **Which side was conformed to which, and why.** RPC §17.x is treated as authority for the authority branch
> because it carries the `AUTHZ-C1A` / `AUTHZ-C1B` remediation tags ratified as **C57** and **C58**, and this
> document carried none: one side states a **ratified correction**, the other states **the text that
> correction replaced**. That is a reading of the ratification record, **not** a precedence ruling between
> delta specs — **no such rule exists in the corpus**, which is why the defect survived. The gap is recorded
> as row **C75**, open decision **O11**, and is an **OWNER decision this pass does not make**. See §13.2.

**Purpose.** Resolve the ratified owner rulings **O-1 (refund authority)** and **O-3 (payout visibility /
requests)** against the frozen constitutions, and produce the exact corrected text that a later integration
pass drops into `PHASE_2_RLS_PERMISSION_SPEC.md` §7.9/§7.10/§11 and `SNATCH_IT_DOMAIN_ARCHITECTURE.md` §7.6.
**This document does not edit the constitutions.** It is the delta; integration is a separate, later act.

**Binding inputs (authority order).**
1. **Owner rulings O-1, O-2, O-3** — RATIFIED. Designed to, not relitigated.
2. `docs/architecture/PHASE_2_SPEC_FOUNDATION.md` — §2 integrate-never-rewrite, §8 security invariants.
3. `docs/architecture/SNATCH_IT_DOMAIN_ARCHITECTURE.md` — **R7 money-single-path** (§5.3), §7.2 role catalog,
   §7.4 SoD, §7.5 step-up, §7.6 permission matrix, §3.1 ticket state machine, §10.5.
4. `docs/architecture/SNATCH_IT_CANONICAL_DATA_MODEL.md` — §1.1 Payout/Refund/Admin-Audit, §15 C12 SSCAS +
   global lock order, C28 closure-at-fifteen.
5. `docs/architecture/PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md` — §1.2, §1.5, §1.8, §1.9, §1.10, §1.12, §2.4, §3.7, §3.8, §3.13, **and §1.13 / §1.13.2 / §1.13.3 / §1.13.4 — the physical definition of `kernel.approval_request` and of `kernel.org_member.granted_at`, which govern §6.6 and §6.7 of this document** (`D13`).
6. `docs/architecture/PHASE_2_RLS_PERMISSION_SPEC.md` — §7.9, §7.10, §11, §15.
7. `docs/architecture/PHASE_2_RPC_FUNCTION_CONTRACTS.md` — §0 conventions, §7, §10, §11, **and §17.1 / §17.2 / §17.7, which carry the `AUTHZ-C1A` / `AUTHZ-C1B` remediation this document is reconciled to. The *defining* contract of `kernel.money_role_grant_matured` belongs to that spec's §1 predicate-helper substrate (§1.1 … today §1.1d) and is NOT written here** (`D13`; see §6.7a for the reference and the four properties this document depends on).
8. `docs/architecture/PHASE_2_EDGE_FUNCTION_SPEC.md` — §3.4, §3.5, §9.1 (OBS-1).
9. `docs/architecture/PHASE_2_VENUE_DASHBOARD_PRODUCT_SPEC.md` — §5, §13, §14, §21, §22.1/§22.3.
10. `docs/architecture/_governance/PHASE_2_RATIFICATION_RECORD.md` — C28, C29/C30/C31 (Gate M), OBS-1.

**Invariant attestation (checked before anything below was written).**

| Invariant | Status under this design |
|---|---|
| **R7 money-single-path** | **PRESERVED.** `kernel.refund` is still written only by `kernel.refund_primary_order` / `kernel.admin_refund` / the C25 sweep. `kernel.payout` is still written only by `kernel.close_settlement` / native-sale path / `kernel.pay_promoter_commission` / `request_org_payout`+`hold`/`release` state advances. Every new object in §6 **requests**; none writes a money row. |
| **OBS-1 — no column ever added to `public.payments`** | **HONORED.** Zero changes to `public.*`. |
| **Frozen Stripe core** | **UNTOUCHED.** No new Stripe API surface; `refund-execute` / `payout-execute` gain actions, not integrations. `_shared/payouts.ts`, `payout-logic.ts`, `buildPayoutIdempotencyKey` reused verbatim. |
| **GP-1 / GP-2** (no direct client DML; no DELETE) | **HONORED.** Every new write is `R` (RPC-only); no new DELETE path. |
| **C35 server-derived actor** | **HONORED**, and §8.3 closes a previously-unstated hole that would have broken it on the EDGE-fronted money paths. |
| **C36 scope-qualified roles** | **HONORED.** Every predicate below is `has_org_role` / `has_venue_role` / `is_platform`. |
| **C28 SSCAS closed at fifteen** | **ARGUED, NOT ASSUMED.** See §7.4 — no sixteenth member is claimed; the argument is stated and flagged for reviewer confirmation. |
| **Gate M (C29 reserve / C31 double-entry) not required** | **CONFIRMED.** Nothing here needs a reserve, a clawback, or instant payout. MVP payout stays settlement-cadenced. |

**No STOP condition was reached.** O-1 and O-3 are both satisfiable without touching the frozen money core
and without violating R7.

---

## 1. The contradictions, restated with citations

### 1.1 Refund (the assigned contradiction — CONFIRMED)

| Source | Says |
|---|---|
| RLS §7.10 matrix | `org_owner/admin/member → D D D D`. No org role has refund SELECT; only `org_finance` has `V(own-org refunds)`. EXEC belongs to `platform_support` (capped), `platform_risk`, `platform_admin`. |
| RLS §11 EXEC table | `kernel.refund_primary_order` → *"owner (buyer-request, capped) · `has_org_role([org_finance])` · `is_platform([platform_support, platform_admin])`"*. |
| Domain §7.6 row *Issue refund (> micro)* | **Org Owner ✔ᴰ✱**, Org Finance ✔ᴰ✱, Buyer ◐(own request). |
| Domain §7.2 | Organization Owner *"Inherits: Org Admin, Org Finance"*. |
| Dashboard §22.1 | Flags the collision; follows RLS; requests a ruling. |

**Why the inheritance prose cannot save it** (the dashboard spec is right about this): `kernel.org_member.role`
is **single-valued** (schema §1.3, `UNIQUE(org_id, identity_id)`), and C36 forbids anything but a literal
membership-row label test. There is no mechanism by which an `org_owner` row satisfies
`has_org_role(org_id,[org_finance])`. **Domain §7.2's "Inherits" is prose, not a predicate**, and for money
actions it must be deleted rather than reinterpreted — see §3.3.

**O-1 resolves it:** org owners MAY initiate/request refunds for their own organization's orders.

### 1.2 Payout (the assigned contradiction — CONFIRMED)

| Source | Says |
|---|---|
| RLS §7.9 matrix | `org_member/owner/admin → D` on SELECT. Only `org_finance` gets `V(own-org payouts)`. |
| RPC §10.3 `request_org_payout` | Role: **`has_org_role([org_finance, org_owner])`**. |
| RPC §10.1 `open_settlement` | Role: `has_venue_role([venue_finance])` OR **`has_org_role([org_finance, org_owner])`**. |
| Domain §7.6 | Org Owner **✔✱** *Initiate payout (≤ threshold)*, **✔ᴰ✱** *(> threshold)*, **✔✱** *Change payout/bank account*. |
| Dashboard §22.3 | *"`org_owner` can request a payout it cannot read."* Flags it. |

The RLS spec **already contradicts itself**: §11 grants `org_owner` the payout request while §7.9 denies the
read. **O-3 resolves it in favor of §11 + domain §7.6:** `org_owner` reads the org payout ledger and requests
payouts. RLS §7.9's SELECT row is the text that is wrong.

### 1.3 A third contradiction found in passing (not assigned; corrected here)

Domain §7.6 row *"Release held funds"* marks **Org Finance ✔ᴰ✱**. RPC §11.3 `kernel.release_payout` is
`is_platform([platform_risk, platform_admin])` only, and **domain §7.4 SoD-3** says *"Whoever freezes funds does
not unilaterally release them."* A risk-placed hold on an org's payout released by that same org is the
control inverted. **Corrected in §3.3:** the Org Finance cell on *Release held funds* becomes blank.

---

## 2. Corrected RLS matrices — drop-in replacements

These are written in the RLS spec's own vocabulary (§1.2 cell legend: **A** allow · **D** deny · **R**
RPC-only · **V** view-only-via-scoped-RPC · superscript = column/scope note) and its own row ordering, so they
can replace §7.9 and §7.10 verbatim. `SPEC CORRECTION` throughout — **no table gains a client-writable path.**

### 2.1 Replacement for RLS §7.9 — `kernel.payout`

> ### 7.9 `kernel.payout` — money-custody-RPC-only
> Write RPCs: `close_settlement`, native-sale payout path, `pay_promoter_commission`, `request_org_payout`
> (state advance), `hold_payout`/`release_payout` (state advance). Idempotency-keyed (Phase-0 discipline).
>
> | Role | SEL | INS | UPD | DEL | EXEC |
> |---|---|---|---|---|---|
> | anon | D | D | D | D | — |
> | fan | D | D | D | D | — |
> | owner (payee identity) | V(own payout)¹⁵ᵃ | D | D | D | — |
> | org_member | D | D | D | D | — |
> | **org_owner** | **V(own-org payouts)**¹⁵ᵇ | D | **R** | D | **`request_org_payout` (own org; ≤ threshold direct, > threshold via approval — §5.2)** |
> | **org_admin** | **D**¹⁵ᶜ | D | D | D | **—** |
> | org_finance | V(own-org payouts)¹⁵ᵇ | D | R | D | `request_org_payout` (own org; same threshold rule) |
> | venue_finance | **V(own-venue *settlement-caused* payouts only)**¹⁵ᵈ | D | D | D | — |
> | venue_manager/door/promoter | D¹⁵ | D | D | D | — |
> | platform_support | V | D | D | D | — |
> | platform_risk | A(money read) | D | R | D | `hold_payout` · `release_payout` (dual-control seam, SoD-3) |
> | platform_admin | A | R | R | D | admin payout ops (audited) · `hold_payout` · `release_payout` |
> | service_role | A(machine) | R(def) | R(def) | D | definer (settlement/native-sale/commission) |
>
> ¹⁵ `promoter` reads own `promoter_commission` payout **only** via a scoped RPC (own attribution), not the org
> payout ledger (CDM §8).
> ¹⁵ᵃ payee-identity read is `payee_identity_id = auth.uid()`, one row set, no org context.
> ¹⁵ᵇ **the ONLY read path is `kernel.list_org_payouts(p_org_id, …)` (§6.4)** — a definer read RPC that
> requires `has_org_role(p_org_id,[org_owner, org_finance])` and filters `payee_org_id = p_org_id`. There is no
> direct table SELECT grant for any org role. Cross-org isolation proof: §4.
> ¹⁵ᶜ **`org_admin` is DENY on the whole money plane** — domain §7.2 states Org Admin *"cannot view or initiate
> payouts/bank changes (that's Finance/Owner)"*, and O-2 constrains `org_admin` to *"general administration but
> not unrestricted financial authority."* See §3.4 (labelled INFERENCE).
> ¹⁵ᵈ **narrowed, and the narrowing is load-bearing.** `kernel.payout` has **no `venue_id`** (schema §1.9:
> `payee_kind ∈ {organization, identity}`, `payee_org_id`/`payee_identity_id`, `cause`, `cause_ref`). A payout's
> venue is derivable **only** for `cause='settlement'`, via `cause_ref → venue.settlement_line →
> venue.settlement.venue_id`, and is **undefined** for `promoter_commission`, `market_sale`, and every
> identity-payee payout. The previous unqualified *"V(own-venue payouts)"* was therefore not expressible against
> the physical schema. `venue_finance` reads settlement-caused payouts for its own venue and is `D` on every
> other cause. Enforced inside `kernel.list_org_payouts` (§6.4), never as a table policy.

### 2.2 Replacement for RLS §7.10 — `kernel.refund`

> ### 7.10 `kernel.refund` — money-custody-RPC-only
> Write RPCs: `refund_primary_order`, `admin_refund`, C25 auto-compensation sweep. **Org and buyer authority
> enters exclusively through `kernel.request_order_refund` (§6.1), which calls `refund_primary_order` as
> definer** — see §5 for why the org never invokes the money writer directly.
>
> | Role | SEL | INS | UPD | DEL | EXEC |
> |---|---|---|---|---|---|
> | anon | D | D | D | D | — |
> | fan | D | D | D | D | — |
> | owner (buyer) | V(own refund) | **R** | D | D | **`request_order_refund` (own order only; capped + windowed by config — §7.2)** |
> | org_member | D | D | D | D | — |
> | **org_owner** | **V(own-org refunds)**²ᵃ | **R** | D | D | **`request_order_refund` · `approve_refund_request` (own org; SoD — §6.2)** |
> | **org_admin** | **D**²ᵇ | D | D | D | **—** |
> | org_finance | V(own-org refunds)²ᵃ | R | D | D | `request_order_refund` · `approve_refund_request` (own org; SoD) |
> | venue_finance | V(own-venue)²ᶜ | D | D | D | — |
> | venue_manager/door/promoter | D | D | D | D | — |
> | platform_support | V | R | D | D | `refund_primary_order` (support-initiated, capped, audited) · `approve_refund_request` (platform-review tier) |
> | platform_risk | A(money read) | R | D | D | `admin_refund` (dispute) · `approve_refund_request` (platform-review tier) |
> | platform_admin | A | R | R | D | `admin_refund` · `refund_primary_order` · `approve_refund_request` |
> | service_role | A(machine) | R(def) | R(def) | D | definer (incl. C25 sweep) |
>
> ²ᵃ **the ONLY read path is `kernel.list_org_refunds(p_org_id, …)` (§6.5).** `kernel.refund` carries no
> `org_id` (schema §1.10 — `payment_id`, `reason_code`, `amount_minor`, `status`, refs). Org scope is resolved
> `kernel.refund.payment_id → kernel.payment_native.payment_id → order_id → venue.order.org_id`
> (`venue.order.org_id` is a real column — schema §3.7 — so this is a two-hop join, not a search). Refunds
> whose `payment_native` link is a `sale_id` (native resale) resolve through
> `market.market_sale → listing → atom.org_id`; **in MVP native resale is `resale_policy='off'` (DA §10.5,
> Gate M), so that arm returns no rows and must fail closed rather than fall through.**
> ²ᵇ `org_admin` DENY on the money plane — see §3.4 (INFERENCE).
> ²ᶜ `venue_finance` own-venue read resolves through the same order join filtered on
> `catalog.event_session → catalog.event.venue_id`; scope is venue, and it is a **read** only — venue roles
> hold no refund EXEC at any tier.

### 2.3 Replacement rows for RLS §11 (EXECUTE-via-RPC authority)

| RPC | May invoke (predicate, live-rechecked) |
|---|---|
| `kernel.refund_primary_order` | **definer** (from `request_order_refund` / `approve_refund_request` / `catalog.cancel_event` / C25 sweep) · `is_platform([platform_support (capped), platform_admin])` |
| `kernel.admin_refund` | `is_platform([platform_risk, platform_admin])` |
| **`kernel.request_order_refund`** *(NEW)* | owner-of-order (capped + windowed) · `has_org_role([org_owner, org_finance])` · `is_platform([platform_support, platform_risk, platform_admin])` |
| **`kernel.approve_refund_request`** *(NEW)* | `has_org_role([org_owner, org_finance])` **AND `approver ≠ requester`** (SoD) · `is_platform([platform_support, platform_risk, platform_admin])` for the platform-review tier |
| **`kernel.cancel_refund_request`** *(NEW)* | the requester · `has_org_role([org_owner, org_finance])` · platform |
| **`kernel.sweep_expired_refund_requests`** *(NEW)* | definer / scheduler only |
| `kernel.request_org_payout` | `has_org_role([org_finance, org_owner])` (unchanged — now consistent with §7.9) |
| **`kernel.list_org_payouts`** *(NEW read RPC)* | `has_org_role([org_owner, org_finance])` · `has_venue_role([venue_finance])` (settlement-cause rows for own venue only) · `is_platform` |
| **`kernel.list_org_refunds`** *(NEW read RPC)* | `has_org_role([org_owner, org_finance])` · `has_venue_role([venue_finance])` (own-venue) · `is_platform` |
| `kernel.set_org_payout_destination` | `has_org_role([org_owner])` **only** · **step-up + SoD + probation** — full control set in §8 |
| `kernel.close_settlement` | `has_org_role([org_finance])` · `has_venue_role([venue_finance])` · platform *(unchanged; `org_owner` still cannot close — see §3.2)* |
| `kernel.hold_payout` / `kernel.release_payout` | `is_platform([platform_risk, platform_admin])` *(unchanged; SoD-3 — no org role, ever)* |
| `catalog.set_platform_config` | `is_platform([platform_admin])`; **for keys in the `refund.*` / `payout.*` / `authn.*` namespaces, dual control is MANDATORY, not a seam** (§7.3) |

### 2.4 Row that does **not** change (stated so no one "helpfully" widens it)

`kernel.organization` §7.2 keeps `org_finance` at `A⁴` **read** on the payout columns and `D` on UPDATE.
`org_finance` **may not change the payout destination.** Domain §7.2 prose says Org Finance may "initiate
payout and bank-account changes"; that half is deleted in §3.3 because under O-3 `org_finance` also requests
payouts, and granting both to one role is precisely the SoD-1 fraud primitive (§8.2).

---

## 3. Corrected Domain §7.6 rows — drop-in replacements

`SPEC CORRECTION`. Legend unchanged (**✔** allowed · **✔ᴰ** dual-control · **✔ᴾ** propose-only · **◐**
scoped · **✱** step-up · blank = denied).

### 3.1 The corrected money rows

| Privileged action | Plat Admin | Support | Risk Ops | Org Owner | Org Admin | Org Finance | Venue Mgr | Box Office | Marketing | Door | Promoter Mgr | Promoter | Seller | Buyer | Ambassador |
|---|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|
| Freeze account / payouts (risk) | ✔ | | ✔ | | | | | | | | | | | | |
| Release held funds | ✔ᴰ✱ | | | | | | | | | | | | | | |
| Initiate payout (≤ threshold) | | | | ✔✱ | | ✔✱ | | | | | | | | | |
| Initiate/approve payout (> threshold) | ✔ᴰ✱ | | | ✔ᴰ✱ | | ✔ᴰ✱ | | | | | | | | | |
| Change payout/bank account | | | | ✔✱ᔆ | | | | | | | | | | | |
| Issue refund (≤ auto-execute threshold) | ✔ | ✔(capped) | ✔ | ✔✱ | | ✔✱ | | | | | | | | ◐(own, capped) | |
| Issue refund (> auto-execute threshold) | ✔ᴰ✱ | ✔ᴾ | ✔ᴾ | ✔ᴰ✱ | | ✔ᴰ✱ | | | | | | | | | |
| Issue refund (> org ceiling / exceptional) | ✔ᴰ✱ | ✔ᴾ | ✔ᴰ✱ | ✔ᴾ | | ✔ᴾ | | | | | | | | | |
| Approve someone else's refund request | ✔ | ✔(tiered) | ✔ | ✔ᔆ | | ✔ᔆ | | | | | | | | | |
| View org/venue finance reports | ◐ | | ◐(risk) | ✔ | | ✔ | ◐(venue ops) | | | | ◐(commission) | ◐(own) | ◐(own) | | ◐(own) |
| **View payout ledger & status** | ✔ | ◐ | ◐ | **✔(own org)** | | ✔(own org) | | | | | | ◐(own commission) | ◐(own) | | ◐(own) |
| **View refund ledger** | ✔ | ◐ | ✔ | **✔(own org)** | | ✔(own org) | ◐(own venue, `venue_finance` only) | | | | | | | ◐(own) | |
| Close settlement (→ payout) | ✔ | | | | | ✔ | | | | | | | | | |

**New legend symbol: `ᔆ` = SoD-constrained** — allowed, but structurally excluded from the paired act by the
same identity. Two uses: (a) *Change payout/bank account* — an `org_owner` who set the current destination can
never themselves request a payout to it (§8.2); (b) *Approve someone else's refund request* — `approver ≠
requester`, always (§6.2).

### 3.2 Changes vs the current §7.6, itemized

| Row | Was | Now | Why |
|---|---|---|---|
| Issue refund (> micro) | one row, Org Owner ✔ᴰ✱ / Org Finance ✔ᴰ✱ / Plat Admin ✔ᴰ✱ | **split into three tiers** | "micro" was never defined and had no config home; the three tiers map 1:1 to the three outcomes of `request_order_refund` (§5.2) |
| Issue refund — Org Owner | ✔ᴰ✱ | **✔✱ below threshold, ✔ᴰ✱ above, ✔ᴾ beyond the org ceiling** | O-1: owners may initiate; dual control and platform review are *tiers*, not a blanket |
| Issue refund — Org Admin | blank | blank (**unchanged, now explicit in RLS too**) | domain §7.2 + O-2; §3.4 |
| Change payout/bank account — Org Finance | ✔✱ | **blank** | SoD-1: `org_finance` requests payouts under O-3; one role may not hold both halves (§8.2) |
| Change payout/bank account — Org Owner | ✔✱ | ✔✱**ᔆ** | O-3 requires strictly stronger controls than a payout request; §8 specifies them |
| Release held funds — Org Finance | ✔ᴰ✱ | **blank** | SoD-3 + RPC §11.3; §1.3 |
| View payout ledger & status | *(row did not exist)* | **new row** | O-3's core grant had no matrix row at all |
| View refund ledger | *(row did not exist)* | **new row** | same |
| Close settlement | *(covered only by "View org/venue finance reports")* | **new row, `org_finance` only** | preserves RPC §10.2 and dashboard §14.4; `org_owner` opens and reads, does not close |

### 3.3 Corrected Domain §7.2 prose

Two sentences in the §7.2 role catalog must change, because they are the source of the refund contradiction
and of a live SoD hole:

1. **Organization Owner, "Inherits: Org Admin, Org Finance"** → replace with:
   > *Inherits: Org Admin (operational surfaces only). **Role inheritance is not implemented for money
   > actions**: `kernel.org_member.role` is single-valued (C36), so every money authority the Owner holds is
   > granted to the `org_owner` label explicitly in the RLS matrices — never derived from Org Finance.*

   This is the sentence dashboard §22.1 asked for a ruling on. It is the honest fix: the *authority* moves
   (O-1), the *inheritance mechanism* is deleted.

2. **Org Finance, "initiate payout and bank-account changes subject to dual-control + step-up"** → replace with:
   > *initiate payouts subject to threshold + step-up; **view** the payout destination. **Cannot change the
   > payout destination** — that is `org_owner`-only and SoD-separated from payout initiation (§7.4 SoD-1).*

### 3.4 `org_admin` — my reading

> **INFERENCE.** O-1 and O-3 name `org_owner` and `org_finance` and are **silent on `org_admin`**. Everything
> below is my inference, not a ruling.

**Reading: `org_admin` holds NO money authority of any kind — not read, not request, not approve.** Concretely
`D` on `kernel.payout` SEL/EXEC, `D` on `kernel.refund` SEL/EXEC, `D` on `set_org_payout_destination`, `D` on
`close_settlement`, and not eligible as the second approver on any money approval.

**Basis (two independent corroborations, so this is a strong inference, not a guess):**
- Domain §7.2, Org Admin, *Cannot* column, verbatim: *"Cannot view or initiate payouts/bank changes (that's
  Finance/Owner)."* The constitution is not actually silent — the rulings are.
- O-2: `org_admin` has *"general administration but **not unrestricted financial authority**."* The ruling
  hands me that phrase explicitly as a design constraint.

**Why the safe choice is total denial rather than a read-only grant.** A read-only payout/refund grant looks
harmless, but `org_admin` is the role most likely to be handed out liberally (it manages venues, events, staff,
promoters — schema §1.3, RLS §7.3), and the payout ledger plus the refund ledger together are the complete
financial picture of the business. "Not unrestricted financial authority" reads more naturally as *bounded
authority* than as *no authority*, so a narrow read grant is arguable — but deny-by-default is the standing
posture (Standards §7, RLS GP-1) and **widening later is a one-line matrix change, while narrowing later is a
migration plus an operator-facing removal.** Deny.

> **BLOCKING OWNER DECISION `D-8` — added 2026-08-28 (reviewer condition 2). NOT RESOLVED HERE, BY DESIGN.**
> **This section and §10.1 of this same document contradict each other**, and the contradiction was found by an
> external reviewer rather than by either author. §3.4 above denies `org_admin` **all** money authority,
> naming `D` on `kernel.refund` SEL. **§10.1 row 35 — "H. Refunds — order list" — carries `org_admin` at `●`
> and labels the row *"unchanged"*.** Venue dashboard §5 row 35 shows the same `●`, and VD §5.2 does not
> supersede row 35, so the dashboard is faithfully inheriting this document. **The defect is here, not
> downstream.** Both positions are stated in full at `D-8` (§11), which is where the decision is registered.
> Neither is adopted here. **The `D-4` entry below covers row 37 (settlement) only and does NOT cover row 35;
> until `D-8` is closed, this document says two different things about the refund ledger.**

**One residual tension I am NOT resolving unilaterally.** RLS §9.13 already grants `org_admin` `A(own-org)`
SELECT on `venue.settlement`, and dashboard §5 row 37 renders that as `●`. A settlement header shows gross,
fees, refunds, net. That is finance data, and it is arguably inconsistent with denying the payout ledger. I am
leaving §9.13 untouched — settlement is an operational reconciliation object scoped to the org, whereas
`kernel.payout` is the money-out ledger and `kernel.refund` is the money-reversal ledger — but I am naming the
inconsistency rather than silently smoothing it. **Owner decision D-4, §11.**

---

## 4. Read scoping — the isolation proof O-3 requires

O-3 grants `org_owner` the payout ledger. The required proof: Venue A cannot read Venue B, and a multi-venue
org's owner sees exactly their own org.

### 4.1 The grain, stated precisely (this is where the intuition misleads)

`kernel.payout` is **org-grain, not venue-grain** (schema §1.9: `payee_kind ∈ {organization, identity}`;
`payee_org_id`; no `venue_id`). Domain §1.2 and dashboard §14 both state the org is the legal payee. Therefore:

> **"Venue B's payout" does not exist as an object.** There are only *org* payouts whose settlement lines
> happen to trace to venue B. Any read model that implies otherwise is inventing a grain the schema does not
> have.

The isolation claim must therefore be stated in two parts, and only one of them is about venues.

### 4.2 Part 1 — cross-ORG isolation (the strong claim)

`kernel.list_org_payouts(p_org_id, …)` is `SECURITY DEFINER`, `search_path` pinned, `REVOKE EXECUTE FROM
anon, public`, GRANT to `authenticated` with an in-body predicate re-check (RPC §0.1). Body:

```
p_org_id is UNTRUSTED (client-supplied).
1. IF NOT kernel.has_org_role(p_org_id, ARRAY['org_owner','org_finance'])
      AND NOT kernel.is_platform(...)
      AND NOT <venue_finance arm, §4.3>
   THEN RAISE insufficient_privilege (42501).   -- no rows, no leak, no fall-through
2. Return rows WHERE payee_org_id = p_org_id.   -- the SAME p_org_id the predicate authorized
```

Two properties carry the proof:
- **`has_org_role` reads `kernel.org_member` live** for `(p_org_id, auth.uid())` (RLS §2.2). An `org_owner`
  of org X has no membership row in org Y, so `has_org_role(Y, …)` is false and the call raises before any
  row is read. A stale JWT cannot re-grant it (C9); a revoke takes effect on the next call.
- **The filter reuses the authorized `p_org_id` and nothing else.** The single most common way this class of
  RPC leaks is a filter on a *different* variable than the one the predicate checked (e.g. authorize
  `p_org_id`, then filter on a caller-supplied `settlement_id` whose org differs). The contract forbids any
  second scope parameter: filters are `(status, cause, date_range, cursor)` only — a **closed enumerated set**,
  none of which widens scope.
- There is **no scope-free form.** `p_org_id` is required. A person who is `org_owner` of two orgs gets two
  separate authorized calls, never a merged ledger — which also matches dashboard §4.3's one-org-at-a-time
  context switching.
- Belt and braces: `kernel.payout` retains **no direct table SELECT grant to `authenticated`** (matrix cell is
  `V`, not `A`). Even a defective RPC cannot be bypassed by a raw PostgREST query on the table.

**Result: cross-org isolation is structural.** ✔

### 4.3 Part 2 — the venue claim, stated honestly

For a **multi-venue org**, the org owner **does** see payouts arising from every venue in their org — and that
is correct, not a leak: the org is the payee and the money is legally the org's. Dashboard §14 already says
*"Settlement rolls up to the org because the org is the legal payee."*

Venue-grain isolation is a claim about **venue roles**, and it holds by a different mechanism:

- A `venue_manager` / `venue_finance` / `venue_door` at venue A holds a `venue.staff_role` row, **not** a
  `kernel.org_member` row. `has_org_role(...)` is therefore false for them, and the org arm of §4.2 denies
  outright. Venue staff cannot reach the org payout ledger at all.
- The **only** venue arm is the narrow `venue_finance` one (matrix note ¹⁵ᵈ), which is:

```
3. ELSIF kernel.has_venue_role(p_venue_id, ARRAY['venue_finance']) THEN
     Return ONLY rows WHERE cause = 'settlement'
       AND cause_ref IN (SELECT sl.id                      -- settlement_line PK is `id` (schema §3.14)
                           FROM venue.settlement_line sl
                           JOIN venue.settlement s USING (settlement_id)
                          WHERE s.venue_id = p_venue_id);  -- venue_id is a real column (schema §3.13)
     -- every other cause (promoter_commission, market_sale, refund_void) is DENIED,
     -- because its venue is undefined at the schema level.
```

  `has_venue_role` reads `venue.staff_role` live for `(p_venue_id, auth.uid(), 'venue_finance')`. Venue A's
  finance staffer has no row for venue B → false → denied. And because the returned set is derived from
  `venue.settlement.venue_id = p_venue_id`, a settlement belonging to venue B is not in the result set even if
  both venues sit in one org.

**Result: Venue A cannot read Venue B — at the venue-role grain, which is the only grain where the claim is
meaningful.** ✔ And the previously-unqualified *"V(own-venue payouts)"* is now expressible, because it is
scoped to the one cause for which a venue exists.

### 4.4 The trap an implementer will hit

`kernel.refund` has **no org column and no venue column** (schema §1.10). `kernel.list_org_refunds` must
resolve scope through `payment_id → kernel.payment_native → order_id → venue.order.org_id`. The tempting
shortcut — "return refunds for payments whose buyer is in my org's order set" — inverts the scope test and
leaks any refund for a buyer who ever bought from you. The contract in §6.5 fixes the join direction and
requires the org filter to be applied on `venue.order.org_id`, the column the authority predicate authorized.
`kernel.payment_native.order_id` is indexed (schema §1.8) and `venue.order` has `(org_id, status)` (schema
§3.7), so the correct direction is also the fast one.

---

## 5. Request vs execute — the decision, and its defence

### 5.1 The decision

> **ONE org-facing entry point (`kernel.request_order_refund`), TWO possible outcomes, and the caller does not
> choose which.** Below the configured threshold the RPC calls the canonical money writer
> `kernel.refund_primary_order` **in the same transaction** and returns `executed`. At or above it, the RPC
> **parks a first-class request object and places a custody hold on the covered atoms**, returning
> `pending_approval` or `pending_platform_review`. Approval (`kernel.approve_refund_request`) releases the hold
> and calls the *same* canonical money writer. **`kernel.refund` is written by exactly one function either
> way.**

Classification: `NEW RPC` ×5 · `ADDITIVE SCHEMA CHANGE` ×3 · `SPEC CORRECTION` throughout · `NEW EDGE
FUNCTION` — none (existing `refund-execute` gains actions).

### 5.2 Why not "just a direct definer call"

Because **dual control cannot be done in one transaction.** O-1 says *"high-risk/exceptional refunds may
require platform review or dual control"*, and domain §7.4 SoD-2 says initiation and approval are *"distinct
acts by distinct principals."* Two humans, two sessions, two points in time ⇒ a durable pending object is
**forced**, whichever way I lean. So the real question is not *request or execute* but *does the below-threshold
path also pay the cost of the pending object*, and the answer is no: the everyday refund ("the buyer emailed,
give them their money back") must be one call, one confirmation, done — anything else trains operators to
route around the product.

### 5.3 Why not "a request object for everything"

Because the pending window is **not free — it is a new attack surface**, and a parked request that does not
hold custody is strictly worse than no dual control at all (§5.4). Paying that cost on every refund, including
the £12 ones, buys nothing and multiplies the hold-related failure modes across the whole refund volume.

### 5.4 The defence — the four races, each answered from the frozen state machine

The pending window is where an org-initiated refund can go wrong, and all four of the prompt's cases live
there. The single mechanism that answers all four:

> **A parked refund request places `kernel.tickets.resale_state := 'refund_hold'` on every covered atom, in the
> same transaction that creates the request.** The atom row is the row the scan path already locks, so the
> guard costs nothing on the door hot path (R8 scan isolation preserved — no cross-schema read is added to
> `record_scan`).

**Race 1 — a refund racing a p2p transfer.**
`market.create_p2p_transfer` calls `kernel.lock_ticket`, whose precondition is `resale_state='none'` and whose
failure is `conflict_locked` (RPC §7.4). An atom already at `refund_hold` therefore **cannot** enter a p2p
transfer — the existing guard does the work, no new check. In the other direction, `request_order_refund` takes
the atom `FOR UPDATE` and reads `resale_state`; an atom at `locked` (open p2p) is **not eligible** and returns
`precondition_failed` naming the open transfer, so the operator cancels the transfer first. Serialization is by
the atom row lock, so exactly one of the two wins and the loser sees a clean, named failure. Note C43's hard
TTL auto-unlock applies to *p2p* locks via `market.sweep_expired_p2p_transfers`, which selects from
`market.p2p_transfer`; a `refund_hold` atom has no p2p row, so that sweep cannot release it. `refund_hold` gets
its **own** TTL sweep (§6.3).

**Race 2 — a refund racing a resale.**
Two sub-cases, and they have different answers.
- *Listed but unsold.* `market.create_listing` also goes through `lock_ticket` (`none → listed`), so a
  `refund_hold` atom cannot be listed. Conversely an atom already `listed` is not eligible for a refund
  request; the operator cancels the listing first. Same lock, same clean failure.
- *Already sold.* Here the atom's `current_owner_id` is a **third party**, and voiding it would confiscate a
  stranger's ticket. Domain §3.1 already rules on this: *"A primary-order refund is refusable if the ticket was
  resold (the new owner holds it) — decided instantly from the ownership_log."* So: **an atom whose
  `current_owner_id ≠ venue.order.buyer_id` is not refundable through this path**, full stop, with error
  `precondition_failed` / `custody_moved`. The economics agree — the reseller already recovered their money in
  the resale, so refunding the primary purchase as well is double recovery. It becomes a platform dispute
  (`admin_refund`), not an org action. *(MVP note: native resale is `resale_policy='off'` until Gate M — DA
  §10.5 — so this arm is dormant at launch. It is specified anyway because it must not be *discovered* the
  week resale ships.)*

**Race 3 — a refund on a ticket that has already been scanned.**
This one is not a race the design can win with a lock, and it exposes a **latent defect in the current
contracts** that I am obliged to report:

> `kernel.void_ticket_atom` (RPC §7.3) requires the atom to be *not already terminal*. Domain §3.1 lists
> `scanned` as **terminal**, and its illegal-transitions table forbids re-animating terminals. There is **no
> `scanned → voided` edge in the frozen state machine.** Therefore, as contracted today,
> `kernel.refund_primary_order` on an order containing a scanned atom raises `precondition_failed` and **the
> entire refund fails — including its money leg.** No spec in the tree says so, and dashboard §13 does not warn
> operators about it.

Refunding an attendee who already walked in is an ordinary goodwill act, so "the whole refund fails" is wrong
product behavior; but "void the scanned atom" is an illegal transition and is *also* the exact shape of an
insider-fraud primitive (staff scans a friend in, then refunds the ticket). The design:

- **Money and custody are decoupled per-atom.** `request_order_refund` partitions the covered atoms into
  `voidable` (`state ∈ {issued, active}`) and `consumed` (`state = 'scanned'`).
- A refund covering only `voidable` atoms behaves exactly as contracted today.
- A refund covering **any** `consumed` atom is an **exceptional refund**: it never voids, never returns
  inventory (the seat *was* consumed — returning it would oversell the room), and its tier is governed by
  `refund.scanned_atom_policy ∈ {refuse, platform_review}` with **`platform_review` as the recommended
  default**. The result names the split explicitly: `{ atoms_voided[], atoms_not_voided[{atom_id, reason:
  'already_scanned'}] }` — never a silent partial.
- The audit row carries `reason_code` plus the consumed-atom list, so the goodwill-vs-collusion pattern is
  queryable after the fact. This is the control that makes the capability safe rather than the refusal.
- **No new ticket state, no new edge in the state machine, no terminal re-animation.** The atom stays
  `scanned`; only money moves.

**Race 4 — partial refunds.**
Today's contract says *"refund a primary order (full/partial) and void the covered atoms"* but never defines
**covered**, which is the whole difficulty. Definition, fully server-derived:

- The atoms of an order are `kernel.ticket_ownership_log` rows with `sequence = 1` whose `cause_ref` is one of
  that order's `venue.order_item.id` values (schema §3.8: the order item *"is the `cause_ref` grain for the
  ownership-log `issue` entries"*). Two joins, both indexed. No schema change.
- **Atoms carry no price** — `kernel.tickets` has no `face_value_cents` (schema §1.5). Per-atom value is
  `venue.order_item.unit_price_minor` for the atom's `ticket_type_id`, which is unique per order
  (`UNIQUE(order_id, ticket_type_id)`) and is an immutable purchase snapshot. Deterministic; no ambiguity.
- The caller passes `p_atom_ids[]` (**untrusted**) and `p_amount_minor` (**untrusted**). The RPC recomputes
  `expected := Σ unit_price_minor(atom) + fee_component(config)` and **rejects any `p_amount_minor` that
  exceeds it**, and separately re-validates `Σ(existing refunds) + p_amount_minor ≤ payment.total` under `FOR
  UPDATE` on `public.payments` (the guard §11.4 already mandates). Amount is never client-authoritative — C35.
- **`p_atom_ids` may legitimately be empty**: a fee-only or goodwill refund with no custody effect. Allowed,
  amount still capped by the payment sum guard, and it is *always* an exceptional-tier refund (there is no
  ticket to point at).
- Whether buyer fees are refundable is policy, not code: `refund.buyer_fee_refundable` (§7.2).
- Idempotency: `kernel.refund.idempotency_key` remains deterministic, and the ownership-log
  `UNIQUE(refund_void, refund_id, atom)` (C26) means a replayed partial voids exactly the same atom set once.
  A **second, different** partial refund on the same order mints a new `refund_id` and therefore a new,
  non-colliding key — so successive partials compose correctly.

### 5.5 The cost this design incurs, stated plainly

A `refund_hold` **stops the ticket working at the door while the request is parked.** That is a
denial-of-admission capability in the hands of every `org_owner`/`org_finance`. It is bounded, not eliminated:

1. Auto-executed refunds place no hold — the hold exists only on the parked tiers.
2. `refund.request_ttl_hours` bounds every hold; `kernel.sweep_expired_refund_requests` releases it (§6.3).
   **A hold with no sweep is a bricked ticket, which is the exact lesson C43 already learned about p2p locks.**
3. A request may not be *parked* on an atom whose session is door-open — reuse the existing
   `kernel.is_transfer_frozen(atom_id)` helper (RPC §12.4, addenda A2/A3), the single sanctioned freeze read.
   Refused with `frozen`. Below-threshold *execution* is unchanged and still voids the ticket at the door;
   dashboard §13.4 already carries the mandatory warning for that.
4. **The buyer must be told.** A ticket that silently stops scanning because someone parked a refund on it is
   the worst failure mode in this document. `NEW RN SURFACE`, §10.2.

---

## 6. RPC contracts

Written in the RPC spec's own format; §0 conventions (definer discipline, C35 actor derivation, C36 role
tests, deny-by-default, audit-in-txn, `p_command_key` idempotency, no DELETE) are inherited and not restated.

### 6.1 `kernel.request_order_refund(p_order_id, p_atom_ids uuid[], p_amount_minor int, p_reason_code, p_command_key)` — **EDGE-FRONTED** · `NEW RPC`

- **Purpose.** The single org-and-buyer-facing refund door. Decides tier, then either executes through the
  canonical money writer or parks an approval request with a custody hold.
- **Role.** owner-of-order (`venue.order.buyer_id = auth.uid()`, capped + windowed by config) ·
  `has_org_role(order.org_id, ['org_owner','org_finance'])` · `is_platform(['platform_support','platform_risk',
  'platform_admin'])`. **`org_admin` and every venue role are forbidden callers.**
- **Params.** All **untrusted**: `p_order_id`, `p_atom_ids[]` (may be empty), `p_amount_minor`, `p_reason_code
  ∈ {buyer_request, oversell_correction}` for org callers — `event_cancelled` is produced only by
  `catalog.cancel_event`, and `dispute`/`admin_action`/`auto_compensation` are platform/system causes
  (schema §1.10) and are **rejected** from this entry point for org and buyer callers.
- **Server-derived.** `p_actor := auth.uid()`; `org_id := venue.order.org_id` (a real column — the client never
  supplies the org); the covered-atom set; `expected_amount`; the tier; **`required_approver_class`**; every
  threshold from `catalog.platform_config` at its current version, **pinned onto the request row** (§7.4).
- **`required_approver_class` is WRITTEN HERE, and it is the only thing that carries the tier forward
  (`AUTHZ-C1A`; RPC §17.1, schema §1.13.2).** The `Outcome` strings in the tier table below —
  `pending_approval`, `pending_platform_review` — are **this function's return values and are stored
  nowhere**: `kernel.approval_request.state` is `pending · approved · denied · cancelled · expired · stale`.
  The tier is persisted as `required_approver_class ∈ {org, platform, platform_admin}`, set server-side from
  the same evaluation that produced the matching row of the table, **pinned exactly as `config_versions` is**
  (a later config change may no more re-class a parked request than re-tier one), **never a parameter and
  never derived from `payload`**.
- **Preconditions.**
  1. Order `status ∈ {paid, partially_refunded}`.
  2. Buyer/order/org relationship verified server-side from live tables (O-1's explicit requirement).
  3. Every named atom belongs to this order (via the §5.4 order-item join). A foreign atom ⇒ `not_found`, and
     never a partial success.
  4. Every named atom has `current_owner_id = order.buyer_id` — else `custody_moved` (§5.4 Race 2).
  5. Every named atom has `resale_state = 'none'` — else `conflict_locked` naming the listing/transfer.
  6. `p_amount_minor ≤ expected_amount` **and** `Σ(refunds for the payment) + p_amount_minor ≤
     payment.total`, the latter under `FOR UPDATE` on `public.payments`.
  7. For the parked branch only: `NOT kernel.is_transfer_frozen(atom)` for every atom — else `frozen`.
- **Tier decision (server-side, from config — §7.2).**

  | Condition | Outcome (**returned**) | `required_approver_class` (**stored**) | Effect |
  |---|---|---|---|
  | buyer caller, within `refund.buyer_self_service_window_hours` and ≤ `refund.buyer_self_service_max_minor` | `executed` | *(none — nothing is parked)* | direct |
  | org caller, `p_amount_minor ≤ refund.org_auto_execute_max_minor`, no consumed atom | `executed` | *(none)* | direct |
  | org caller, ≤ `refund.org_dual_control_max_minor` | `pending_approval` | **`org`** | park + hold |
  | any consumed (scanned) atom, and `refund.scanned_atom_policy = 'platform_review'` | `pending_platform_review` | **`platform`** | park + hold |
  | org caller, > `refund.org_dual_control_max_minor` | `pending_platform_review` | **`platform`** | park + hold |
  | any consumed atom, and `refund.scanned_atom_policy = 'refuse'` | `rejected` | *(none)* | none |

  **The consumed-atom row takes precedence over the amount rows.** A scanned atom routes to `platform` **even
  when the amount is below `refund.org_dual_control_max_minor`** — the trigger for platform review is the
  *consumed custody*, not the size. Stated explicitly because a table read top-to-bottom produces the opposite
  result: the org-amount row matches first and the collusion shape §5.4 Race 3 exists to surface is handed to
  the org arm. Identical to RPC §17.1's statement of the same table.

- **Grant maturity on the org arm (`AUTHZ-C1B`).** An `org_owner`/`org_finance` caller must additionally
  satisfy `kernel.money_role_grant_matured(order.org_id)` — see §6.7a. **It binds the REQUESTER, not only the
  approver:** SoD-2 is a pair, and a control applied to one half of a pair is applied to neither. Failure is
  **`sod_violation`**, not `insufficient_privilege` — the role is genuinely held, and a permission error sends
  the operator to re-check a grant that is correct.

- **Locks & order.** **Order** (`FOR UPDATE`) → **Ticket Atom(s)** ascending `ticket_atom_id` → **Approval** →
  **Payment** (`FOR UPDATE` on `public.payments` for the sum guard). Conforms to the global lock order with
  Approval placed per §7.4.
- **SSCAS.** Executed branch: **member #3** (existing refund-void). Parked branch: see §7.4 — one locked
  aggregate class (Ticket Atom), so `SSCAS: n/a (single locked aggregate class)`.
- **Writes.**
  *Executed branch* — delegates to `kernel.refund_primary_order` in the same txn (definer→definer); that
  function alone writes `kernel.refund`, drives `kernel.void_ticket_atom` per voidable atom, updates
  `venue.order`, returns inventory, and writes `refund.issue` audit. **This function writes no money row.**
  *Parked branch* — `kernel.approval_request` (INSERT, state `pending`, **with `required_approver_class`,
  `subject_kind='order'` and `subject_id := p_order_id`** — the `action ↔ subject_kind` pairing CHECK of
  schema §1.13.3 is satisfied here, not assumed), `kernel.tickets.resale_state :=
  'refund_hold'` on each covered voidable atom, `kernel.admin_audit` (`refund.request`).
- **Idempotency.** `p_command_key` unique per `(actor, key)` on `kernel.approval_request`; the executed branch
  inherits `kernel.refund.idempotency_key`. Replay returns the original outcome, never a second refund.
- **Result.** `{ status ∈ {executed, pending_approval, pending_platform_review, rejected, noop_replay},
  refund_id?, request_id?, amount_minor, atoms_voided[], atoms_not_voided[{atom_id, reason}], tier,
  required_approver_class? }` — **`approval_required_role` is RENAMED to `required_approver_class`** so the
  returned value and the stored column are the same word (RPC §17.1). **Two names for the same fact is how
  the tier went missing in the first place.**
- **Errors.** `insufficient_privilege(42501)` · **`sod_violation`** (grant immature) · `precondition_failed` ·
  `custody_moved` · `conflict_locked` · `frozen` · `not_found` · `over_refund` · `policy_violation` (reason
  code not permitted for this caller) · `step_up_required` · **`step_up_unavailable`** (`AUTHZ-M4`; RPC §17.7).
- **Forbidden.** Any client writing `kernel.refund` directly; `org_admin`; venue roles; a buyer refunding
  another buyer's order; any caller supplying an `org_id` or an actor.

### 6.2 `kernel.approve_refund_request(p_request_id, p_decision, p_reason_code, p_command_key)` — **EDGE-FRONTED** · `NEW RPC`

- **Purpose.** The second act of dual control. On approve, releases the holds and calls the canonical money
  writer. On deny, releases the holds and terminates the request.
- **Role — `AUTHZ-C1A`: the branch is keyed on `(action, required_approver_class)` and on NOTHING ELSE.**

  > **The defect this replaces, stated plainly because a reader who only ever sees this file must learn the
  > trap and not merely the answer.** **This document's previous text branched on `pending_approval` vs
  > `pending_platform_review`. Those two strings are §6.1's return statuses. They are not stored.**
  > `kernel.approval_request.state` is `pending · approved · denied · cancelled · expired · stale`; the table
  > as this document originally specified it (§6.6, §12 ADDITIVE-1) had **no tier column at all**; and this
  > function's own re-evaluation list named the order, the atoms and the amount — **not the tier**. An
  > implementer with that schema in front of them has three discriminators to branch on — `action`, `state`,
  > `org_id` — and **all three route every parked refund to the org arm.** The result is not a mis-routed
  > queue item: **an org executes a refund the §6.1 tier table sent to platform review** — above the
  > dual-control ceiling, or on a **consumed (scanned) atom**, which is precisely the collusion shape §5.4
  > Race 3 and `MD-6` exist to surface. **The control read as present in four documents and was absent in the
  > only place it ran.** Ratified as **C57**; the physical column is schema §1.13.2, and the identical branch
  > is RPC §17.2 and RLS §11.3.

  | `action` | `required_approver_class` | May approve |
  |---|---|---|
  | `refund.issue` | `org` | `has_org_role(request.org_id, ['org_owner','org_finance'])` **AND** `auth.uid() <> request.requested_by` **AND** `kernel.money_role_grant_matured(request.org_id)` |
  | `refund.issue` | `platform` | `is_platform(['platform_support','platform_risk','platform_admin'])`, **`platform_support` bounded by the cap re-evaluated under lock per `AUTHZ-M3`** |
  | `payout.request` | `org` | as `refund.issue`/`org`, **plus the §8.2 destination-setter exclusion applied to the APPROVER** — otherwise the destination-setter simply approves instead of requesting |
  | `payout.request` | `platform` | `is_platform(['platform_risk','platform_admin'])`. **`platform_support` is DENIED** — it holds no payout authority anywhere else, and the generic approval object must not become the place it acquires one |
  | `config.set_money_key` | `platform_admin` | **`is_platform(['platform_admin'])` ONLY**, AND `auth.uid() <> request.requested_by` — §7.3's *"a second distinct `platform_admin`"*, and see `AUTHZ-C1A2` below |

  Common to every arm: **SoD-2** (`auth.uid() <> requested_by`), enforced **structurally** and backed by the
  table constraint pair of `AUTHZ-M1` — `CHECK (approved_by IS NULL OR approved_by <> requested_by)` **and**
  the companion `CHECK (state <> 'approved' OR approved_by IS NOT NULL)`, **without which the first is
  vacuously satisfiable by any writer that forgets the column** (§6.6). Plus step-up per `AUTHZ-M4`
  (an absent `aal`/`amr` claim **raises `step_up_unavailable`** and never evaluates to a pass or a fail).
  **Bound by EDGE-CALLER-JWT** — §8.3c: on a service-role client `auth.uid()` and `auth.jwt()` are empty and
  every predicate above degrades silently.

  **`state = 'pending' AND NOT expired` is an ACTIONABILITY precondition, never an authority input.** Those
  are two questions and they get two columns. **No authority predicate in this function reads `payload`**
  (§6.6's footgun; `T-RPC-AUTHZ-01` asserts it structurally).

  > **`AUTHZ-C1A2` — `config.set_money_key` takes a second distinct `platform_admin`, never `platform_support`
  > or `platform_risk`.** §7.3 of this document says *"a second distinct `platform_admin`"*, and the whole
  > non-org arm was previously written as `is_platform(['platform_support','platform_risk','platform_admin'])`
  > — one predicate spanning three different approval flows. Under it **`platform_support` approves the raise
  > of its own ceiling**: the role capped precisely because it is not trusted with unbounded money is the role
  > that lifts the cap, and the cap it lifts is the one bounding it on the arm directly above. That is why the
  > stored label set is **three** arms (`org` · `platform` · `platform_admin`) and not two (schema §1.13.2).

- **`action`-dispatched. `action` alone is NOT the dispatch key — `(action, required_approver_class)` is.**
  A single `action` spans two approver classes (a refund parked at `org` and a refund parked at `platform`
  are the same action with different authority), which is exactly why branching on `action` was never
  sufficient and why the missing column was invisible.
- **The tier is re-derived and must still equal the pinned class.** The re-evaluation list below names the
  amount, the atoms and the order — **and originally not the tier**, which is the other half of why this
  defect went unnoticed: nothing re-checked a value nothing stored. The recomputed tier (from the **pinned**
  `config_versions`, never from live config) must equal the stored `required_approver_class`; a mismatch is
  **`stale`**, never a re-route. In particular **an atom that became `scanned` while the request was parked
  re-tiers it to `platform`**, and because a re-tier is `stale` rather than a silent escalation the org
  approver is told to re-request rather than finding their approval quietly ineffective. `T-RPC-AUTHZ-02`.
- **Preconditions.** Request `state = 'pending'` and not expired. **Every §6.1 precondition is RE-EVALUATED
  under lock at approval time** — the stored payload is *evidence*, never authority. Specifically: the order is
  still refundable; the atoms are still owned by the buyer; the payment sum guard still passes; the amount is
  recomputed from `venue.order_item` and must still equal the pinned `expected_amount`. A drift ⇒
  `precondition_failed` and the request moves to `stale` (holds released) rather than executing on stale facts.
  *This is the mitigation for the generic-payload footgun in §6.6.*
- **Locks & order.** **Order** → **Ticket Atom(s)** ascending → **Approval** (`FOR UPDATE`) → **Refund/Payment**.
- **SSCAS.** Member #3 (approve branch); single-aggregate (deny branch).
- **Writes.** `kernel.approval_request` (→ `approved` / `denied` / `stale`), `kernel.tickets.resale_state :=
  'none'` per held atom, then on approve **`kernel.refund_primary_order`** (which writes `kernel.refund`, the
  voids, the inventory return, the order status, and `refund.issue`); `kernel.admin_audit`
  (`refund.request_approved` / `refund.request_denied`).
- **Result.** `{ status, request_id, refund_id?, atoms_voided[], atoms_not_voided[] }`.
- **Errors.** **`self_approval`** — its own named failure, distinct from a bare `42501`, so the UI can say
  *"a different person must approve this"* rather than "permission denied" · **`sod_violation`** (grant
  immature, or the payout destination-setter) · `insufficient_privilege` · `precondition_failed` ·
  `not_found` · `conflict_locked` · `step_up_required` · **`step_up_unavailable`**.

### 6.3 `kernel.cancel_refund_request(p_request_id, p_reason_code, p_command_key)` and `kernel.sweep_expired_refund_requests()` — `NEW RPC` ×2

- **`cancel_refund_request`** — the requester, or any `org_owner`/`org_finance` of the org, or platform.
  Releases holds, state → `cancelled`, audit `refund.request_cancelled`. Single-aggregate + atom overlay.
- **`sweep_expired_refund_requests`** — **definer/scheduler only** (pattern: `market.sweep_expired_p2p_transfers`,
  RPC §12.2). Bounded batch; for every request past `expires_at` (= `created_at + refund.request_ttl_hours`):
  release every `refund_hold` overlay, state → `expired`, audit `refund.request_expired`, emit a notification.
  Atoms locked ascending `ticket_atom_id` inside each request; requests processed in `expires_at` order with
  `SKIP LOCKED`. **This function is not optional** — without it a parked request is an unbounded
  denial-of-admission on a paying customer's ticket.

### 6.4 `kernel.list_org_payouts(p_org_id, p_venue_id, p_filters, p_cursor)` — **DB-RPC (read)** · `NEW RPC`

Adopts and closes dashboard **Δ3**, and is the mechanism that makes O-3's read grant real.

- **Role.** `has_org_role(p_org_id, ['org_owner','org_finance'])` · `has_venue_role(p_venue_id,
  ['venue_finance'])` (settlement-cause arm only, §4.3) · `is_platform`. `org_admin`, `org_member`,
  `venue_manager`, `venue_door`, `promoter` ⇒ `insufficient_privilege`.
- **Params.** `p_org_id` **required and untrusted**; `p_venue_id` used only by the venue arm; `p_filters` a
  **closed set** `{status[], cause[], date_from, date_to}`; `p_cursor` opaque. **No parameter may widen scope**
  — the filter is always applied *in addition to* `payee_org_id = p_org_id`.
- **Returns.** `payout_id, cause, cause_ref, amount_minor, currency, status, created_at, updated_at,
  settlement_id?` and a **`stripe_transfer_ref` presence boolean, not the ref itself** for org roles (the raw
  Stripe id is platform-only; an operator needs "has it left?", not the identifier). Never bank data — the
  platform does not hold any (§8.1).
- **Locks / SSCAS.** None; read-only, no `FOR UPDATE`.
- **Errors.** `insufficient_privilege` · `not_found` (unknown org id — indistinguishable from unauthorized by
  design, so the RPC is not an org-existence oracle).

### 6.5 `kernel.list_org_refunds(p_org_id, p_venue_id, p_filters, p_cursor)` — **DB-RPC (read)** · `NEW RPC`

Same shape. Org scope resolved **`kernel.refund.payment_id → kernel.payment_native.payment_id → order_id →
venue.order.org_id`**, filtered on `venue.order.org_id = p_org_id` (§4.4 — the join direction is part of the
contract, not an implementation detail). Returns `refund_id, order_id, reason_code, amount_minor, currency,
status, created_at, atoms_voided_count`. **Buyer PII is not in the projection** — domain §7.6 gives finance
roles `◐(limited)` on buyer PII, and dashboard §9.3 already draws that line. The `sale_id` arm (native resale)
**fails closed** and returns no rows while `resale_policy='off'`.

### 6.6 `kernel.approval_request` — one object, not three

Rather than a refund-specific table, a **single generic approval object** serves (a) org refund dual control,
(b) the money-namespace `platform_config` dual control (§7.3), and (c) the payout-above-threshold dual control
(§9.2). One state machine, one SoD rule, one expiry sweep, one audit vocabulary.

**The physical definition is `PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md` §1.13 (package `077`), and this
section agrees with it rather than restating it loosely.** The columns this document's authority model depends
on, named exactly as the schema names them:

| Column | What this document depends on |
|---|---|
| **`required_approver_class`** text — **not null**, `CHECK IN ('org','platform','platform_admin')` | **ADDED by `AUTHZ-C1A` / ratification row `C57`; it did not exist in this document's original §6.6 or §12, and that omission IS the defect §6.2 now records.** The **stored** discriminator that decides which authority arm may approve the row. Written server-side **at request time** by the requesting function from the tier it computed (§6.1, §9.2, §7.3), **pinned exactly like `config_versions`** — never recomputed at approval time, never supplied by a caller, never derived from `state` or from `payload`. **Three labels, not two:** `platform` admits `platform_support`/`platform_risk`/`platform_admin`, while **`platform_admin` admits only a second distinct `platform_admin`** — §7.3's money-key rule, which a two-label set would have collapsed (`AUTHZ-C1A2`). |
| `action` text — not null, `CHECK IN ('refund.issue','payout.request','config.set_money_key')` | The other half of §6.2's dispatch key. A closed label set, not an FK. |
| `subject_kind` text — not null, `CHECK IN ('order','settlement','config_key')`; `subject_id` uuid — not null | Deliberately **soft** (no FK — three subjects in three packages), constrained instead by the `action ↔ subject_kind` pairing CHECK and by the RPC-side existence assertions `APPR-SUBJ-1`/`APPR-SUBJ-2` (schema §1.13.3, RPC §17.0a). |
| `org_id` uuid — **nullable**, FK→`kernel.organization` | NULL for platform-scope actions (`config.set_money_key`). §6.2's org arm scopes `has_org_role` to it, which is why `CHECK (required_approver_class <> 'org' OR org_id IS NOT NULL)` exists. |
| `payload`, `config_versions` jsonb | Server-computed evidence and the pinned `(key, version)` set (§7.2). **Never authority** — see the footgun below. |
| `requested_by`, `approved_by` uuid | SoD-2's two identities; both server-derived (C35). |
| `state` text — `pending · approved · denied · cancelled · expired · stale` | **Actionability only, never authority.** |
| `reason_code`, `expires_at`, `command_idempotency_key`, `created_at`, `updated_at` | Expiry sweep (§6.3) and C16 replay guard. |

**The SoD CHECK is a pair, not a single constraint (`AUTHZ-M1`).** This document originally specified only
`CHECK (approved_by IS NULL OR approved_by <> requested_by)` — which **every row nobody has approved satisfies
trivially**, including a row an implementation moved to `approved` while leaving `approved_by` NULL. The
constraint that is the entire structural expression of §12 ADDITIVE-1 could therefore be green on a database
in which **no approval was ever attributed to a second human**. Schema §1.13 adds the companions:
`CHECK (state <> 'approved' OR approved_by IS NOT NULL)`, the same on `'denied'`, the `action ↔ subject_kind`
pairing, `CHECK (action <> 'config.set_money_key' OR required_approver_class = 'platform_admin')` and
`CHECK (required_approver_class <> 'org' OR org_id IS NOT NULL)`.

**The footgun, named.** A generic `payload jsonb` invites the approval to become a client-supplied authority
vector ("approve this, amount = X"). **Mitigation, contractual and mandatory:** the payload is
**server-computed at request time** and **re-derived and re-compared at approval time** (§6.2). The stored
payload is evidence for the approver's UI; the executing code trusts nothing in it. A mismatch is `stale`, not
an override. **And the reason that matters is `AUTHZ-C1A`:** with the tier absent from the row, `payload` was
the *only* place a diligent implementer could have found it — so the missing column was actively pushing the
authority branch into the one structure this paragraph forbids it to read.

### 6.7 Contract changes to existing RPCs — `SPEC CORRECTION`

| RPC | Change |
|---|---|
| `kernel.refund_primary_order` (§11.4) | **Role narrows** to `definer` + `is_platform([platform_support (capped), platform_admin])`. Buyer, `org_finance`, and the new `org_owner` reach it only via `request_order_refund`. Adds the **voidable/consumed partition** (§5.4 Race 3): a `scanned` atom is reported in `atoms_not_voided[]`, is **not** voided, and returns **no** inventory; the refund's money leg still completes. Adds `custody_moved` to the failure taxonomy. |
| `kernel.request_org_payout` (§10.3) | **Role unchanged** (`[org_finance, org_owner]` — now consistent with §7.9). **Adds FOUR preconditions — this row said three, and the fourth is what makes the other three mean what they claim (`AUTHZ-C1B`, ratification row `C58`):** the destination-probation hold (§8.4), the SoD-1 destination-setter exclusion (§8.2), the step-up predicate (§8.3) **and `kernel.money_role_grant_matured(p_org_id)` (§6.7a)**. Failure of the maturity conjunct is **`sod_violation`**, never `insufficient_privilege`. **None of the four is ever applied to a deny or a cancel** (schema §13.7 `S-3`): a control that blocks *stopping* a payout is a control pointed the wrong way. Adds the above-threshold approval branch (§9.2), which **writes `required_approver_class`** on the parked arm exactly as §6.1 does. |
| `kernel.set_org_payout_destination` | **Full contract written for the first time** (§8) — it is referenced by RLS §7.2/§11, schema §1.2, and dashboard §5 note 26/§14.5, but was never contracted in the RPC spec. **Role: `has_org_role(p_org_id,['org_owner'])` ONLY, with step-up, AND `kernel.money_role_grant_matured(p_org_id)`** (`AUTHZ-C1B`; RPC §17.7, which states that maturity *"binds the SETTER and not only the requester"*). `org_finance` is excluded entirely (§8.2). |
| `kernel.close_settlement` (§10.2) | Unchanged. `org_owner` still cannot close. Reconciliation item RLS §15.3 / RPC §16.4 (org- vs venue-level close) is **untouched and still open** — O-1/O-3 do not reach it. |
| `catalog.set_platform_config` | Money-namespace keys become genuinely dual-controlled (§7.3). |

### 6.7a `kernel.money_role_grant_matured(p_org_id)` — REFERENCED HERE, DEFINED ELSEWHERE (`AUTHZ-C1B`)

**This document does not define this helper and must not.** Its defining contract belongs to the predicate-helper
substrate of `PHASE_2_RPC_FUNCTION_CONTRACTS.md` §1 (§1.1 … §1.1d today), it is declared in the canonical helper
list of `PHASE_2_SPEC_FOUNDATION.md` §4 (C36) and stated in full in `PHASE_2_RLS_PERMISSION_SPEC.md` §11.3a, and
it was ratified as row **C58**. What follows is a **reference**, deliberately written so that a drift between
that definition and this document's dependence on it is **visible rather than silent** — if any of the four
properties below stops holding at the defining site, every use in §6.1, §6.2, §6.7, §8.2 and §9.2 is wrong and
this section is where a reader finds that out.

**Why it exists at all.** Both money SoD primitives compare `auth.uid()` against a stored identity — SoD-1
compares the payout requester against `payout_destination_set_by` (§8.2), SoD-2 compares the approver against
`requested_by` (§6.2). **An `org_owner` holds the grant authority to mint the second identity** through the
ordinary invite/accept flow. Without a maturity conjunct, both primitives are satisfied by any two distinct
`auth.uid()` values, one of which the attacker creates. **This is the control that makes O-3's ratified SoD-1
collapse survivable in practice rather than only on paper.**

**The four properties this document depends on:**

1. **Shape.** `kernel.money_role_grant_matured(org_id) → boolean`, true **iff** the caller holds a **money
   role** (`org_owner` · `org_finance`) in `org_id` whose live `kernel.org_member.granted_at` is at least
   `authn.money_role_maturity_hours` old. It is a function of **time as well as role** — the only predicate in
   the helper set that is.
2. **Absent config fails CLOSED.** An absent or NULL `authn.money_role_maturity_hours` means **no grant is
   mature** — the helper returns **false**, never true (the standing rule of ratification row `C61`). The
   value itself is an open number (RLS `MD-14`), and it is **not** decided here.
3. **It is a CONJUNCT, never a gate on its own.** It is added beside the role test, never in place of it, and
   it is **never** applied to a deny, a cancel, or a sweep — a control that blocks *stopping* a money movement
   is pointed the wrong way (schema §13.7 `S-3`).
4. **It binds BOTH halves of BOTH pairs.** Requester **and** approver on SoD-2 (§6.1, §6.2); destination
   **setter** (§8.2, RPC §17.7) **and** payout requester (§6.7) on SoD-1. **Applied to one half of a pair it
   is applied to neither** — an `org_owner` who mints a fresh `org_finance` defeats a requester-only check
   simply by moving the fresh account to the other side of the pair.

**Its failure mode is `sod_violation`, never `insufficient_privilege`,** everywhere this document names it: the
role is genuinely held, and a permission error would send an operator to re-check a grant that is correct.
Storage (`kernel.org_member.granted_at`, written by `accept_org_invite` and re-set by `change_org_role` on
promotion **into** a money role) is schema §1.3/§1.13.4, package `077`; the config key is package `078`.

> **TWO CONFLICTS SURFACED, NEITHER DECIDED HERE** — per `PHASE_2_SPEC_FOUNDATION.md` §0 (*"surface the
> conflict; do not silently pick a side"*). Both were found while reconciling this section and are **outside
> the scope of ratification rows `C57`/`C58`**; both belong to the schema owner and are reported, not resolved.
>
> 1. **The failure code is stated two ways.** RPC §17.1 / §17.7 / §10.3 and RLS §11.3a give the immature-grant
>    failure as **`sod_violation`**, explicitly *"**not** `insufficient_privilege`"*. Schema §1.13.4 instead
>    proposes **`precondition_failed ('money_role_too_new')`** *"so the surface can say something true to the
>    operator."* **This document uses `sod_violation`** — solely because RPC §17.x carries the ratified
>    `AUTHZ-C1B` tag and this file must be internally consistent with the branch it now states — and **that is
>    not a ruling against the schema spec's proposal**, which has the better operator-facing message and could
>    perfectly well win as a distinct sub-code. **The two must be made one before implementation:** a control
>    whose denial arrives under two different codes is a control whose alerting cannot be written.
> 2. **Schema §1.13.4 lists `set_platform_config`'s money arm as a maturity site.** That looks wrong on its
>    face: `kernel.money_role_grant_matured(org_id)` takes an **org** and tests **org** money roles
>    (`org_owner` · `org_finance`), while the money-namespace config arm is `platform_admin` (§7.3) and its
>    approval row carries **`org_id IS NULL`** by CHECK — so there is no org to pass it. Either the helper
>    needs a platform-plane counterpart (a **new** control, not a ratified one) or that site is listed in
>    error. **Not resolved here.**

---

## 7. Threshold and configuration model

### 7.1 Where it lives — and the constraint that decides it

`catalog.platform_config`, keyed `(key, version)`, **append-only per version**, old versions retained so an
object governed by an old version stays interpretable (schema §2.4, C11). This is the ratified home for
config-as-values (A8) and O-1's *"thresholds remain configuration/policy, not hard-coded product copy"* lands
here exactly.

### 7.2 The keys

| Key | Type | Governs |
|---|---|---|
| `refund.org_auto_execute_max_minor` | int (minor units) | at/below ⇒ org refund executes immediately |
| `refund.org_dual_control_max_minor` | int | above the first, at/below this ⇒ in-org dual control |
| `refund.request_ttl_hours` | int | parked-request expiry ⇒ hold release (§6.3) |
| `refund.scanned_atom_policy` | enum `refuse` \| `platform_review` | the already-scanned case (§5.4 Race 3); recommended default `platform_review` |
| `refund.buyer_self_service_window_hours` | int | buyer's own capped refund window |
| `refund.buyer_self_service_max_minor` | int | buyer's own cap — gives RPC §11.4's *"capped by policy"* a home for the first time |
| `refund.buyer_fee_refundable` | bool | whether buyer fees ride along on a partial (§5.4 Race 4) |
| `refund.platform_support_max_minor` | int | the support ceiling RLS §15.4 / RPC §16.3 left open — **the key is specified here; the number is still an owner decision (§11 D-3)** |
| `payout.destination_cooldown_hours` | int | feeds `kernel.organization.payout_destination_locked_until` |
| `payout.destination_probation_days` | int | first-payout-held window after a destination change (§8.4) |
| `payout.request_auto_max_minor` | int | at/below ⇒ payout request proceeds directly (domain §7.6 *"≤ threshold"*) |
| `payout.dual_control_min_minor` | int | above ⇒ dual control (domain §7.6 *"> threshold"*) |
| `authn.money_action_max_age_seconds` | int | step-up freshness window (§8.3) |
| `authn.money_action_required_aal` | enum `aal1` \| `aal2` | **the lever that makes the honest MVP answer shippable** (§8.3) |

**Version pinning.** Every `kernel.approval_request` row records the `(key, version)` pair of every threshold
it was evaluated against. A config change mid-flight therefore cannot silently re-tier a parked request, and an
auditor can reconstruct why a given refund took the tier it did. This is the same snapshot-at-decision
discipline as R6 value-copy and `resale_policy_snapshot`.

### 7.3 Who may change a threshold — and yes, that is itself dual control

A threshold that gates money authority is exactly as money-consequential as the action it gates. Raising
`refund.org_auto_execute_max_minor` from £50 to £50,000 is a larger act than any single refund it would then
permit.

- **Authority:** `is_platform(['platform_admin'])` — unchanged.
- **Dual control:** for keys in the `refund.*`, `payout.*`, and `authn.*` namespaces, **mandatory, not a
  seam.** `catalog.set_platform_config` on such a key does not insert a new version directly; it creates a
  `kernel.approval_request` (`action = 'config.set_money_key'`, `subject_kind='config_key'`,
  **`required_approver_class := 'platform_admin'`**, `org_id IS NULL`) which a **second distinct
  `platform_admin`** approves, and only the approval inserts the new `(key, version+1)` row. Non-money keys
  keep today's direct path. **`platform_admin` is a distinct stored class from `platform` precisely so this
  arm cannot be satisfied by `platform_support`** — the role capped by `refund.platform_support_max_minor`
  must not be able to approve a raise of that cap (`AUTHZ-C1A2`, §6.2; schema §1.13.2 carries it as
  `CHECK (action <> 'config.set_money_key' OR required_approver_class = 'platform_admin')`).
- **Direction asymmetry (recommended):** *lowering* a limit (more restrictive) may execute directly; only
  *raising* one requires the second approver. Fail-safe changes should never be friction-gated — a security
  control that is hard to tighten in an incident is a liability.
- Audit: `config.money_key_proposed`, `config.money_key_approved`, both with `before`/`after`.

### 7.4 Per-org override — the answer is NO, and the reason is not architectural taste

**`catalog.platform_config` is world-readable** (RLS §8.4: *"public-read (values not secret)"*, and every one
of the 13 non-admin principals including `anon` holds `A` on SELECT). A per-org refund ceiling or payout limit
is **not public information** — it discloses an organization's financial posture, and the set of keys would
disclose the platform's whole customer list.

Therefore:
- **MVP has one platform-wide threshold set. No per-org override.**
- If per-org limits become a business requirement, they need a **non-public** home: `kernel.org_money_policy`
  (`org_id` PK, the override columns, org-scoped read via `has_org_role([org_owner, org_finance])`,
  platform-only write, versioned, audited). That is an `ADDITIVE SCHEMA CHANGE` I am specifying but **not
  proposing for MVP**, because it doubles the resolution logic (per-org → fall back to platform) at every
  decision point and nothing in O-1/O-3 asks for it.
- **Owner decision D-2 (§11):** does launch need per-org refund/payout limits? If yes, this comes back in.

### 7.5 The lock order, with the approval object placed

The global order (CDM C28, RPC §0.4) is
`Event/Session → Inventory (batch, then shard asc) → Order → Listing → Ticket Atom (asc id) → money-plane
(Payment / Payout / Reserve / Settlement)`.

**`Approval/Request` is placed between Ticket Atom and the money plane.** An approval is always acquired after
the custody rows it holds and before the money rows it authorizes, so no inversion is introducible. Every RPC
in §6 acquires in that order.

**Does this create a sixteenth SSCAS member?** The set is *closed at fifteen; no sixteenth without an
amendment* (C28). My argument that it does not:

- §0.4's own definition: *"A function that touches **one** aggregate class is tagged `SSCAS: n/a
  (single-aggregate)`."* The parked branch of `request_order_refund` takes `FOR UPDATE` on exactly one
  pre-existing aggregate class — **Ticket Atom** (ascending id). The `kernel.approval_request` row is a
  **fresh INSERT**: it contends on nothing, and its only serialization is the trailing unique index on the
  command key, acquired last.
- The `venue.order` and `public.payments` reads in the parked branch are validation reads. `public.payments`
  is taken `FOR UPDATE` for the sum guard — which *is* a money-plane lock — but it is acquired last, in order,
  and released with the txn; it is the same lock member #3 already takes.
- The approve branch is member **#3** (refund-void), already enumerated, with the same lock classes in the
  same order plus the Approval row.

> **FLAGGED FOR REVIEWER CONFIRMATION.** If a reviewer judges `kernel.approval_request` to be an aggregate
> class rather than an intent record, then the parked branch is a genuine sixteenth member and **C28's closure
> requires a formal amendment**. I have argued it is not, and placed it in the global lock order regardless so
> that the amendment — if the board wants one — is a one-line ratification and not a redesign. **Owner decision
> D-1, §11.**

---

## 8. Payout destination change — the control set

O-3: *"Changing bank account / payout destination is a higher-risk operation and must use stronger controls
than merely viewing/requesting a payout."* Domain §7.4 SoD-1 names the fraud primitive: **redirect the bank
account, then release funds to it.** Below is the control set — mechanisms, not adjectives.

### 8.1 What is actually being changed (this materially bounds the blast radius, and it should be said)

Snatch It **holds no bank details.** `kernel.organization.stripe_connect_account_ref` is an opaque Stripe
Connect account id (`acct_…`), and bank details are collected by Stripe's own KYC'd onboarding
(`connect-onboarding`, edge §3.3). "Change the payout destination" therefore means *re-point the org at a
different Stripe Connect account* — an account that has itself passed Stripe identity/bank verification.

Two consequences: (1) the attack requires an attacker-controlled, KYC-passed Connect account, which is a
materially higher bar than typing an IBAN into a form; (2) `before`/`after` in the audit row are Stripe account
ids, which are safe to store — **no control below may ever cause bank numbers to enter our database**, and none
does.

### 8.2 Control 1 — SoD-1, restored (this is the sharpest structural consequence of O-3)

**Before O-3**, `set_org_payout_destination` was `org_owner`-only and `org_owner` had no payout authority, so
SoD-1 held by construction: the destination-changer could not disburse.

**O-3 breaks that.** `org_owner` now requests payouts. If `org_owner` also changes the destination, one
identity holds both halves of the exact named fraud primitive. **A cool-down does not fix this** — it is a
delay, and an attacker who has the credentials can simply wait it out. The pair must be split by identity, not
by time.

**Control (`ADDITIVE SCHEMA CHANGE`):** `kernel.organization.payout_destination_set_by uuid` (nullable,
FK→`auth.users`, on delete restrict) records *who* set the current destination. Then:

> `kernel.request_org_payout` **rejects when `auth.uid() = organization.payout_destination_set_by`**, with
> `sod_violation`, **permanently for that destination** — not merely during the cool-down.

The identity that pointed the money somewhere can never be the identity that sends money there. That is SoD-1
enforced structurally, which is what domain §7.4 demands (*"make it structurally impossible to violate — not
merely discourage"*).

**The operational cost, stated honestly:** an org with exactly one money principal is **blocked** after a
destination change. That is the correct consequence of SoD — but "correct" and "shippable" are different
claims, so the design provides a sanctioned escape rather than a silent bypass:

> **Escalation path:** the first payout after a destination change may be executed by
> `is_platform(['platform_risk','platform_admin'])` via `release_payout`, which already exists (RPC §11.3) and
> already carries a dual-control seam. A one-person org therefore contacts Snatch It for exactly one payout,
> and the second human in the SoD pair is a platform operator. No code path bypasses the rule.

**Owner decision D-5 (§11):** confirm that a single-principal org is expected to escalate. The alternative —
letting the same identity do both after the cool-down — reintroduces the fraud primitive and I do not recommend
it.

`org_finance` is **excluded from destination changes entirely** (§2.4, §3.3) for the same reason: it too holds
payout-request authority under O-3.

**The caller predicate, stated as a contract line — it was not, and that is how the maturity conjunct went
missing here (`AUTHZ-C1B`, ratification row `C58`).**

> `kernel.set_org_payout_destination(p_org_id, p_connect_account_ref, p_reason_code, p_command_key)` —
> **`has_org_role(p_org_id, ['org_owner'])` ONLY**, **AND** step-up per §8.3 (`AUTHZ-M4`: an absent
> `aal`/`amr` claim **raises `step_up_unavailable`** and never evaluates), **AND**
> **`kernel.money_role_grant_matured(p_org_id)`** (§6.7a). **Bound by EDGE-CALLER-JWT** (§8.3c) — and this is
> the RPC where that rule bites hardest, because the step-up predicate reads `auth.jwt()`, which on a
> service-role client carries no `aal` and no `amr` at all. Errors: `insufficient_privilege` ·
> **`sod_violation`** (grant immature) · `step_up_required` · **`step_up_unavailable`** ·
> `precondition_failed` · `not_found`. Identical to RPC §17.7.

**Why maturity binds the SETTER and not only the requester.** SoD-1's whole content is *"the identity that set
the destination may not request the payout to it."* An `org_owner` who mints a second money account satisfies
that by **setting as A and requesting as B** — so a maturity check applied only to the requester is defeated by
moving the fresh account to the other side of the pair. **Both halves of both primitives carry it, or neither
does** (RPC §17.7, in those words).

### 8.3 Control 2 — "recent authentication": the honest answer

This is the control O-3 names and no Phase-2 build spec implements. `aal2` and step-up appear in the
constitutions (domain §7.5) and as *"seams"* in exactly two places in the build specs (comps, C39). There is no
step-up mechanism anywhere in the RPC, RLS, edge, or schema specs today.

**Can it be enforced in-database? Yes — with two hard caveats, and the second is architectural.**

**(a) The predicate is expressible in Postgres.** Under PostgREST the request's verified JWT is available as
`auth.jwt()`. Supabase access tokens carry `aal` (`aal1`/`aal2`) and `amr` (an array of `{method, timestamp}`
entries recording each factor exercised in the session). So both *assurance level* and *recency* are readable
inside a `SECURITY DEFINER` function body:

```
required := config('authn.money_action_required_aal')      -- 'aal1' | 'aal2'
max_age  := config('authn.money_action_max_age_seconds')
IF  auth.jwt()->>'aal' IS DISTINCT FROM required
 OR extract(epoch from now()) - max(entry->>'timestamp')::bigint OVER (auth.jwt()->'amr') > max_age
THEN RAISE step_up_required;
```

The token is signed and PostgREST verifies it before the statement runs, so this is **not** client-forgeable —
it is not the same thing as trusting a client-supplied role claim, and C9's prohibition (which is about
*authority* claims going stale across a revoke) does not apply: an `amr` timestamp can only ever assert that an
authentication happened in the past, and it is not refreshed by a token refresh. Re-authenticating is the only
way to satisfy it. That is precisely the property "recent authentication" needs.

**(b) Caveat 1 — this is NOT enforceable in RLS alone, and the reason is not the one people expect.** It is not
that RLS cannot call `auth.jwt()` (it can). It is that **the money path is not a table policy at all** — every
money mutation is `EXECUTE` on a `SECURITY DEFINER` function (GP-1: *"there is no `A` write cell anywhere in
this spec"*). A table policy never runs. **The step-up predicate must live in the function body**, alongside
the `has_org_role` check. Any design that says "enforce step-up in RLS" is describing a policy that will never
be evaluated on the path that matters.

**(c) Caveat 2 — the EDGE-FRONTED path breaks it entirely unless one unstated requirement is made explicit.**
This is the load-bearing finding of this section. `set_org_payout_destination`, `request_org_payout`, and
`request_order_refund` are all EDGE-fronted. Edge functions hold `SUPABASE_SERVICE_ROLE_KEY` (edge spec §3.4,
§3.5). **If the edge calls the DB-RPC with a service-role client, then inside the RPC `auth.uid()` is NULL and
`auth.jwt()` is the service token — no `aal`, no `amr`, and no `uid`.** Every `has_org_role` check silently
degrades, and the edge would have to *attest* the actor as a parameter — which is exactly the
client-supplied-authority pattern C35 forbids.

> **MANDATORY, and currently unstated anywhere in the edge spec:** `payout-execute` and `refund-execute` **MUST
> invoke the money DB-RPCs on a Supabase client constructed from the caller's own `Authorization` header**, so
> that `auth.uid()` and `auth.jwt()` resolve to the human inside the transaction. The service-role key may be
> used for the function's other work (Stripe calls, callbacks, denial logging) but **never** to invoke a money
> RPC on a human's behalf. This is what makes edge §3.4/§3.5's *"the edge passes ids; the RPC decides — no role
> logic in the edge"* actually true rather than aspirational. `SPEC CORRECTION` to the Edge Function Spec.

**(d) Caveat 3 — nothing enrolls MFA today, so `aal2` on day one locks every operator out.** Supabase `aal2`
requires enrolled factors. No spec in this tree specifies staff MFA enrollment; domain §7.5 asserts *"MFA is
mandatory for all staff and admin principals"* as a requirement, not as a shipped mechanism.

**(e) Caveat 4 — token shape is unverified.** Whether this project's tokens actually carry `amr` with
timestamps depends on the GoTrue version and configuration. `UNVERIFIED:` I have no production access and did
not check a live token. **This must be verified against a real access token before the predicate is
implemented**; if `amr` is absent, freshness falls back to the token's own `iat` combined with a shortened
access-token TTL, which is weaker (it measures token age, not authentication age) and must be labelled as such.

**The shippable position, therefore:**

| | MVP (now) | On staff MFA enrollment |
|---|---|---|
| `authn.money_action_required_aal` | `aal1` | flip to `aal2` — **a config change, not a code change** |
| `authn.money_action_max_age_seconds` | e.g. 900 for destination change | unchanged |
| What the user experiences | re-enter password / re-verify OTP before changing the destination | re-verify second factor |
| What it defeats | a stolen long-lived refresh token, an unattended session, session-riding | additionally: a stolen password |

`aal1` freshness is **not** security theatre: it defeats the most common real attack against a
90-day-refresh-token dashboard, which is an unattended or hijacked session, and it forces an interaction the
attacker must reproduce. Shipping it with the enum in config is what makes `aal2` a same-day flip later.

**Client cost, named:** satisfying the predicate requires a real re-authentication flow and a retry. `NEW
DASHBOARD SURFACE` (§10.1). It is not free and must not be planned as free.

### 8.4 Controls 3–6 — the rest of the set

**Control 3 — cool-down (existing, retained, correctly characterized).**
`set_org_payout_destination` sets `payout_destination_locked_until := now() +
config('payout.destination_cooldown_hours')` (schema §1.2; enforced in `request_org_payout`, RPC §10.3;
surfaced with a named unlock time by dashboard §14.5). **Retained — but it is a *detection window*, not a
control.** It buys time for someone to notice; it stops nobody who is willing to wait. Its value is entirely
contingent on Control 5.

**Control 4 — destination probation (`NO SCHEMA CHANGE`; new precondition).**
Even after the cool-down expires, the **first** payout to a destination changed within
`config('payout.destination_probation_days')` is created at status `held` rather than `submitted`, releasable
only by `is_platform(['platform_risk','platform_admin'])` via the existing `kernel.release_payout` (RPC §11.3).
This reuses machinery that already exists, needs no new column, and puts a human risk operator between "the
destination just changed" and "money left the platform" — which is strictly stronger than any timer.

**Control 5 — out-of-band notification (`NEW EDGE`-adjacent; reuses `send-push`).**
On a destination change, notify **every** `org_owner` and `org_finance` of the org — including the actor — by
push **and** email, immediately, with the actor's name, the timestamp, and a one-tap *"I did not authorize
this"* escalation that calls `kernel.hold_payout` on every pending payout for the org. **Without this, the
cool-down protects nobody**, because nobody is watching. This is the control that converts Control 3 from a
delay into a detection.

**Control 6 — audit, including the denials (`SPEC CORRECTION` to the edge spec).**
`kernel.admin_audit` row `org.payout_destination.change`, `subject_kind='organization'`, before/after =
Stripe account ids, `reason_code` mandatory. Plus, and this is the part that does not work the obvious way:

> **A denied money action currently leaves no trace.** `kernel.admin_audit` is written **in the same
> transaction** as the action (§0.3), and a failed predicate `RAISE`s — which rolls the transaction back,
> taking any audit row with it. Postgres has no autonomous transactions. **Repeated failed attempts to change a
> payout destination or fire a payout are the single highest-value fraud signal in the system, and today they
> are invisible.**
>
> **Fix:** the EDGE function catches `insufficient_privilege` / `sod_violation` / `step_up_required` from a
> money RPC and, *in a separate transaction*, calls a definer-only `kernel.record_money_denial(p_action,
> p_subject_kind, p_subject_id, p_error_code)` which appends a `*.denied` audit row. Definer-only, service_role
> EXECUTE, no human path. Applies to `refund-execute` and `payout-execute`.

### 8.5 The control set, ranked by what it actually stops

| # | Control | Stops | Cost |
|---|---|---|---|
| 1 | **SoD-1 identity split** (§8.2) | the named fraud primitive, structurally | single-principal orgs must escalate |
| 1b | **Grant maturity on BOTH halves** (§6.7a, §8.2) — **ADDED, `AUTHZ-C1B`** | **the identity split being satisfied with an identity the attacker MINTED** — without it control 1 compares two `auth.uid()` values an `org_owner` can create at will, and ranks first while stopping nothing | a genuinely new money principal waits out `authn.money_role_maturity_hours` |
| 2 | **Destination probation hold** (§8.4) | money leaving to a fresh destination unreviewed | a support touch on the first payout |
| 3 | **Out-of-band notification** (§8.4) | a silent takeover | none |
| 4 | **Step-up freshness** (§8.3) | session-riding, stolen refresh tokens | a re-auth flow + retry |
| 5 | **Denial audit** (§8.4) | *nothing on its own* — it is how you find out | one extra edge call on failure |
| 6 | **Cool-down** (§8.4) | a rushed attacker only | operator confusion if unexplained |

Note the ordering: the existing, already-specified control (cool-down) is the **weakest** in the set. O-3's
requirement that destination change be "strictly stronger than payout request" is met by controls 1–4, not by
the timer that exists today.

**Control 1b is placed immediately below control 1 deliberately.** It is not an additional control so much as
the **precondition of control 1 being a control at all**: SoD-1 compares the payout requester against a stored
`auth.uid()`, and the role that changes the destination is the role that can mint the counterparty. Ranked
separately rather than folded into control 1 because the two fail independently — control 1 can be correctly
implemented and still stop nobody.

---

## 9. Payout authority — the rest of the model

### 9.1 What O-3 changes, minimally

- `kernel.payout` SEL: `org_owner` `D → V(own-org payouts)`; `org_admin` explicitly `D`; `venue_finance`
  narrowed to settlement-cause (§2.1).
- The read is realized by `kernel.list_org_payouts` (§6.4) — Δ3 adopted and contracted.
- `request_org_payout` role is **unchanged**; it was already correct in RPC §10.3. The RLS matrix moves to meet it.
- Dashboard §22.3 closes.

### 9.2 Payout above threshold

Domain §7.6 distinguishes *Initiate payout (≤ threshold)* `✔✱` from *Initiate/approve payout (> threshold)*
`✔ᴰ✱`. Realized on the same generic object: above `payout.dual_control_min_minor`, `request_org_payout` does
not advance `pending → submitted`; it creates `kernel.approval_request` (`action = 'payout.request'`,
`subject_kind='settlement'`, `subject_id := p_settlement_id`) and returns `pending_approval`.
`approve_refund_request`'s sibling branch (same function, dispatched on **`(action, required_approver_class)`**
— §6.2, not on `action` alone) performs the advance, subject to the same `approver ≠ requester` SoD, the §6.7a
grant-maturity conjunct, **and** the §8.2 destination-setter exclusion applied to the *approver* as well —
otherwise the destination-setter could simply approve instead of request. **No custody hold** is involved:
a payout holds no tickets.

**This is the third writer of `required_approver_class` (`AUTHZ-C1A`)**, with §6.1 and §7.3. Set server-side
from the same evaluation that decided to park and pinned exactly as `config_versions` is, **never a
parameter**: `'org'` for an org-approvable payout, `'platform'` where the amount or a risk condition sends it
to platform review — **at which point `platform_support` is DENIED on the payout arm** (§6.2), because it
holds no payout authority anywhere else and must not acquire one through the generic approval object. Result:
`{ status ∈ {submitted, pending_approval, pending_platform_review, noop_replay}, payout_id, request_id?,
required_approver_class? }`.

### 9.3 `close_settlement` stays put

`org_owner` may `open_settlement` (RPC §10.1) and read settlements, but **may not close**. Close is the
irreversible act that mints the payout (dashboard §14.4), and keeping it at `org_finance`/`venue_finance` gives
the org an internal separation between "the owner asks for the money" and "finance certifies the numbers."
O-3 does not touch it. RLS §15.3 / RPC §16.4 (org- vs venue-level close) remains open, unchanged.

### 9.4 What is deliberately NOT built

**No reserve. No clawback. No instant payout.** (C29/C30/C31, Gate M; schema §1.11; dashboard §14.5.) Nothing
in O-1/O-3 requires them: refunds are funded from the Stripe balance via `refunds.create` on the original
charge, and payouts remain settlement-cadenced. **No surface may imply an instant-payout capability**, and the
refund tiers above must never be described to an operator as "instant."

---

## 10. Surface implications

### 10.1 Venue dashboard — `NEW DASHBOARD SURFACE` and corrections

**§5 role × surface matrix — corrected rows:**

| # | Surface | o_own | o_adm | o_fin | v_fin | Change |
|---|---|:--:|:--:|:--:|:--:|---|
| 5 | A. Home — Payout status | **○** | — | ● | — | note 5 (§22.3) **resolved**; `○` is now confirmed, not provisional |
| 35 | H. Refunds — order list | ● | **●** ⚠ | ● | ○ | **CONTESTED — `D-8`, BLOCKING.** This `●` and §3.4's *"`org_admin` holds NO money authority of any kind — not read"* cannot both hold. Previously labelled *"unchanged"*, which read as settled. **It is not settled and must not be built from either cell until `D-8` is closed** |
| 36 | H. Refund — initiate | **●** | — | ● | — | **was `—`** with flagged-conflict note 20; O-1 grants it. Note 20 **resolved** |
| 37 | I. Settlement — read | ● | ● | ● | ● | unchanged (see `D-4` — **which covers this row only, not row 35**) |
| 39 | I. Settlement — close | — | — | ● | ● | unchanged |
| 40 | I. Payouts — status & history | **○** | — | ● | **◐** | `○` confirmed; `v_fin` becomes `◐` (settlement-cause rows for own venue only) |
| 41 | I. Payout — request | ● | — | ● | — | unchanged; now consistent with the read |
| 47 | K. Payout destination | **●ˢᵒᵈ** | — | **○** | — | `org_finance` is **read-only** (was implicitly writable via domain §7.2 prose) |
| **NEW** | H. Refund — approval queue | ● | — | ● | — | `NEW DASHBOARD SURFACE` — the second approver's inbox |
| **NEW** | K. Re-authenticate for a money action | ● | — | ● | — | `NEW DASHBOARD SURFACE` — the step-up flow (§8.3) |

**§13.3 copy must change.** It currently reads *"Among venue-side roles, only `org_finance` can initiate a
refund"* and *"Refunds are handled by your organization's finance role."* Corrected:
> *"Refunds are initiated by your organization's owner or finance role. Venue managers can see orders and
> refunds but cannot issue them — ask your org owner or finance lead, or ask Snatch It support."*

The **permission-explained** state for `venue_manager`/`venue_finance` is retained — the spec is right that
invisibility here produces support tickets.

**§13.4 gains a tier disclosure.** Before confirming, the surface states which tier the amount falls into:
*"This refund executes immediately"* / *"This needs a second approver from your team"* / *"This goes to Snatch
It for review."* The operator learns the threshold from the product, never from a rejection.

**§13.5 gains the two new consequences:**
- *"While this is waiting for approval, the ticket will not scan at the door."* — the `refund_hold`
  consequence, stated before the operator parks it, not discovered at 11pm.
- *"This ticket was already scanned — we can refund the money, but the ticket stays used and the seat does not
  come back."* — the consumed-atom case (§5.4 Race 3), which today would fail the whole refund with an
  unexplained `precondition_failed`.

**§14.5 gains the probation explainer.** The existing spec distinguishes *held* from *failed* (correctly — they
have different remedies). A third state joins them: *"Your first payout after a bank change is reviewed by
Snatch It. This usually takes under a business day."* Otherwise the probation hold (§8.4) is indistinguishable
from a risk hold and generates exactly the support call §14.5 is trying to prevent.

**§21 deltas resolved by this spec.** Δ3's `kernel.list_org_payouts` is adopted and contracted (§6.4). Δ1, Δ2,
Δ4–Δ10 are untouched.

**§22 conflicts closed.** §22.1 (refund authority) — **closed by O-1**, resolution recorded in §2.2/§3.3.
§22.3 (`org_owner` can request a payout it cannot read) — **closed by O-3**, resolution in §2.1/§6.4.
§22.2, §22.4–§22.9 are out of scope and remain open.

### 10.2 React Native consumer app — `NEW RN SURFACE`

1. **"Refund pending" on the ticket.** A `refund_hold` atom must render, on both My Ticket detail and the Entry
   Pass, as *"A refund is being reviewed for this ticket — it will not scan until that's resolved."* RN §7's
   state matrix gains a `refund_pending` column for those two screens. **A ticket that silently stops working
   is the worst outcome in this document**; the buyer paid, and the hold is not their doing.
2. **Buyer self-service refund request.** Domain §7.6 has always given Buyer `◐(own request)` and RPC §11.4 has
   always said *"owner (buyer-request, capped)"*, but **no RN surface exists** for it and no cap had a config
   home. Now both do (§7.2). Within window and cap ⇒ executes; outside ⇒ *"we've sent this to the venue"*
   (a parked request, org-visible).
3. **Refund outcome honesty.** RN already knows *"there is no `refunded` ticket state"* (D2). It must also
   handle **money-refunded-but-ticket-still-`scanned`**: *"Refunded — this ticket had already been used."*

### 10.3 Notifications (Agent D's plane — emitters named, not designed here)

`refund.request_parked` (to org approvers) · `refund.request_pending` (to the **buyer**, §10.2) ·
`refund.request_approved` / `_denied` / `_expired` (both parties) · `payout.destination_changed` (**every**
`org_owner` + `org_finance`, out-of-band, §8.4 Control 5) · `payout.probation_hold` (org) ·
`payout.request_pending_approval` (org approvers).

---

## 11. Owner decisions still required

Every one of these is a decision I declined to make alone. None blocks writing the spec; each blocks
implementation of the item named.

| # | Decision | Recommendation | Blocks |
|---|---|---|---|
| **D-1** | Is `kernel.approval_request` an *aggregate class* (⇒ a sixteenth SSCAS member ⇒ a C28 amendment) or an *intent record* (⇒ `SSCAS: n/a`)? | Intent record — argued in §7.4; it is lock-ordered either way, so an amendment is a one-line ratification | §6.1 parked branch |
| **D-2** | Per-org refund/payout thresholds at launch? | **No** — **but the stated basis has since become false and the recommendation must be re-derived before it is acted on.** This row argues from *"`platform_config` is world-readable"*. **It is not**: RLS §8.4 is a two-class model on `visibility` (`AUTHZ-CFG1` / ratification **C71**), and money keys are `restricted`. A non-public home for per-org limits may therefore already exist. **Recorded, not re-decided** (reviewer-conditions pass, 2026-08-28) | §7.4 |
| **D-3** | The actual **numbers**: `refund.org_auto_execute_max_minor`, `refund.org_dual_control_max_minor`, `refund.platform_support_max_minor`, `payout.request_auto_max_minor`, `payout.dual_control_min_minor`, `refund.request_ttl_hours`. The support cap was already open (RLS §15.4 / RPC §16.3); this spec gives it a home but not a value | commercial + risk call; the keys ship, the values are set by an audited `set_platform_config` | tier behavior |
| **D-4** | `org_admin` reads `venue.settlement` (RLS §9.13, dashboard row 37) while being denied the payout/refund ledgers. Keep, or deny settlement too? | Keep — settlement is operational reconciliation, payout is money-out. But the inconsistency is real and I am naming it rather than smoothing it (§3.4) | nothing; consistency only |
| **D-8** | **`org_admin` on the money plane — BLOCKING.** §3.4 of this document denies `org_admin` **all** money authority (`D` on `kernel.payout` and `kernel.refund` SEL/EXEC) and labels its own position **`INFERENCE`**: O-1 and O-3 name `org_owner` and `org_finance` and are **silent on `org_admin`**. **§10.1 row 35 of this same document grants `org_admin` `●` on the refunds order list.** Dashboard §5 row 35 shows the same `●` and VD §5.2 does not supersede it, so the dashboard is inheriting this document rather than diverging from it. **NO RECOMMENDATION IS OFFERED — see §11.1** | **NONE — deliberately.** Every other row in this table carries a recommendation; this one must not, because the two positions are held by the same document and the tie-break is an authority question, not a design question | **Row 35, the refund read path, and the `D-4` settlement question it reopens.** Blocks any build of surface H |
| **D-5** | A single-money-principal org is **blocked** from payouts after a destination change by SoD-1 (§8.2). Escalate to platform, or relax? | **Escalate** via the existing `release_payout`. Relaxing reintroduces the exact named fraud primitive | §8.2 |
| **D-6** | `refund.scanned_atom_policy` default: `refuse` or `platform_review`? | `platform_review` — refunding an attendee is legitimate, but it is also the insider-collusion shape, so it should be seen, not silently allowed or silently blocked | §5.4 Race 3 |
| **D-7** | Ship step-up at `aal1` freshness now and flip to `aal2` on staff MFA enrollment, or block money actions until MFA ships? | Ship at `aal1` with the enum in config (§8.3). Blocking would ship a dashboard nobody can use | §8.3 |

### 11.1 `D-8` stated in full — both positions, the default on silence, and why that default is the unsafe one

**This subsection exists because `D-8` is the one decision in this document that a reader could resolve by
accident.** The other seven are visibly open. `D-8` is a `●` in a table labelled *"unchanged"* — it looks
settled, and an implementer would build it without ever knowing a decision was owed.

**Position A — deny (`§3.4` of this document).** `org_admin` holds **no** money authority of any kind: `D` on
`kernel.payout` SEL/EXEC, `D` on `kernel.refund` SEL/EXEC, `D` on `set_org_payout_destination`, `D` on
`close_settlement`, ineligible as second approver. Two corroborations: Domain §7.2's Org Admin *Cannot* column
verbatim — *"Cannot view or initiate payouts/bank changes (that's Finance/Owner)"* — and O-2's *"general
administration but **not unrestricted financial authority**."* **§3.4 labels its own position `INFERENCE`.**

**Position B — grant (`§10.1` row 35 of this document, and dashboard §5 row 35).** `org_admin` reads the
refunds order list at `●`. The corroboration is that `org_admin` is the role that runs the org day to day, and
an order list is an operational object before it is a financial one — the same argument `D-4` accepts for
settlement. **VD §5.2 does not supersede row 35**, so the dashboard is faithfully inheriting this document.

**The rulings are silent.** O-1 (refund authority) and O-3 (payout visibility/requests) name `org_owner` and
`org_finance` and say nothing about `org_admin`. Neither position is a ruling; both are readings.

**What silence defaults to, mechanically — and it defaults to GRANT.** An implementer resolves silence by
building what RLS says, because RLS is the authority model. RLS currently says:
- **§9.7 `venue.order`** — `org_owner/admin` → `A(own-org orders)` SELECT. This is what backs row 35.
- **§9.13 `venue.settlement`** — `org_admin` → `A(own-org)` SELECT. A settlement header shows gross, fees,
  refunds, net.

**Both grant.** So the outcome of leaving `D-8` open is not "nothing gets built" — it is **Position B, built
silently, with a `D` sitting unread in §3.4.**

**Why that is the unsafe direction, stated plainly.** `org_admin` is, by §3.4's own reasoning, *"the role most
likely to be handed out liberally"* — it manages venues, events, staff and promoters. The order ledger plus
the settlement header is a substantial part of the financial picture of the business. And the asymmetry §3.4
already identified governs the cost of being wrong in each direction: **widening later is a one-line matrix
change; narrowing later is a migration plus an operator-facing removal of a capability people have been using.**
Deny-by-default is the standing posture (Standards §7, RLS `GP-1`). **The default on silence runs against the
standing posture, which is precisely why silence is not an acceptable resolution here.**

**This document does not choose.** Recording which way the default falls is not a recommendation for it — it
is the reason the decision is marked **BLOCKING** rather than deferred. `D-8` is the owner's.

**Verification owed before implementation (not a decision — a fact I could not check).** `UNVERIFIED:` that
this project's Supabase access tokens carry `amr` with per-factor timestamps. No production access was used.
If absent, §8.3's freshness test degrades to token age (`iat` + a shortened access-token TTL), which is weaker
and must be documented as such rather than described as "recent authentication."

---

## 12. Change classification — the complete list

### `SPEC CORRECTION` (no code, no schema; frozen-document deltas for a later integration pass)
1. RLS §7.9 matrix — full replacement (§2.1).
2. RLS §7.10 matrix — full replacement (§2.2).
3. RLS §11 EXEC table — rows in §2.3.
4. RLS §15 — reconciliation items 3 and 4 annotated (support cap now has a config home; settlement-close scope untouched).
5. Domain §7.6 — money rows replaced, three rows added, `ᔆ` legend symbol added (§3.1).
6. Domain §7.2 — Org Owner "Inherits" and Org Finance "bank-account changes" prose corrected (§3.3).
7. RPC §11.4 — role narrowed; voidable/consumed partition; `custody_moved` added (§6.7).
8. RPC §10.3 — three preconditions + the above-threshold branch (§6.7).
9. **Edge spec §3.4/§3.5 — money RPCs MUST be invoked on the caller's JWT, never the service-role client** (§8.3c). *The single highest-severity correction in this document.*
10. Edge spec §3.4/§3.5 — denial audit via `kernel.record_money_denial` (§8.4 Control 6).
11. Dashboard §5 rows 5/36/40/41/47; §13.3/§13.4/§13.5 copy; §14.5 probation state; §22.1 and §22.3 closed (§10.1).
12. RN spec §7 state matrix — `refund_pending` column on My Ticket detail + Entry Pass (§10.2).

### `ADDITIVE SCHEMA CHANGE` (all on Phase-2 tables; nothing in `public.*`)
1. **`kernel.approval_request`** — new table, **placed in package `077`** by schema §1.13 (which is the physical definition; this list is the classification, not the DDL). `request_id` PK · `action` (`refund.issue` · `payout.request` · `config.set_money_key`) · **`required_approver_class` (`org` · `platform` · `platform_admin`) — NOT NULL, `AUTHZ-C1A` / row `C57`; this item originally omitted it, and §6.2 records what that omission did** · `subject_kind` (`order` · `settlement` · `config_key`, CHECKed) / `subject_id` · `org_id` (nullable, FK) · `payload` jsonb (server-computed evidence, never authority) · `config_versions` jsonb (§7.2 pinning) · `requested_by` · `approved_by` (nullable) · `state` (`pending` · `approved` · `denied` · `cancelled` · `expired` · `stale`) · `reason_code` · `expires_at` · `command_idempotency_key` · timestamps. **Unique** `(requested_by, command_idempotency_key)`. **Checks — SoD as a table constraint is a PAIR, not one line (`AUTHZ-M1`):** `approved_by IS NULL OR approved_by <> requested_by` **and** `state <> 'approved' OR approved_by IS NOT NULL` (the first is vacuously satisfiable without the second), the same on `'denied'`, the `action ↔ subject_kind` pairing, `action <> 'config.set_money_key' OR required_approver_class = 'platform_admin'`, and `required_approver_class <> 'org' OR org_id IS NOT NULL`. **Indexes** include `(action, required_approver_class, state)` — §6.2's actual predicate — and a partial `(required_approver_class, created_at) WHERE state='pending'`, because the platform-review queue carries `org_id IS NULL` and is invisible to the `(org_id, state)` index. RLS: RPC-only, org-scoped read via the approval-queue RPC. Append-only-ish state machine; no DELETE.
2. **`kernel.tickets.resale_state` gains the label `refund_hold`** (`ALTER TYPE … ADD VALUE`). Guard sets in RPC §7.2 (transfer preconditions), §7.4 (lock preconditions), §7.5 (scan preconditions) update accordingly — each is a `SPEC CORRECTION` riding this change.
3. **`kernel.organization.payout_destination_set_by uuid`** — nullable, FK→`auth.users`, on delete restrict. Column-scoped exactly like `payout_destination_locked_until` (`org_owner`/`org_finance`/platform). Enables SoD-1 (§8.2).
3a. **`kernel.org_member.granted_at timestamptz`** — NOT NULL, default `now()`, **ADDED by `AUTHZ-C1B` / ratification row `C58`; package `077`, schema §1.3/§1.13.4.** Written on grant by `accept_org_invite` and **re-set by `change_org_role` on promotion INTO a money role**. It is the clock `kernel.money_role_grant_matured` reads (§6.7a), and **without it SoD-1 and SoD-2 both compare two `auth.uid()` values that one `org_owner` can mint.** The companion config key `authn.money_role_maturity_hours` is package `078`; its **value** is an open number (RLS `MD-14`) and is not decided here, but an **absent** key means no grant is mature (row `C61`).
4. *(Conditional on D-2, NOT proposed for MVP)* `kernel.org_money_policy` — per-org threshold overrides in a non-public home (§7.4).

### `NEW RPC`
1. `kernel.request_order_refund` (§6.1) — EDGE-FRONTED.
2. `kernel.approve_refund_request` (§6.2) — EDGE-FRONTED; `action`-dispatched, also serves payout and config approvals.
3. `kernel.cancel_refund_request` (§6.3) — DB-RPC.
4. `kernel.sweep_expired_refund_requests` (§6.3) — DB-RPC, scheduler-only. **Not optional.**
5. `kernel.list_org_payouts` (§6.4) — DB-RPC read. Closes dashboard Δ3.
6. `kernel.list_org_refunds` (§6.5) — DB-RPC read.
7. `kernel.list_approval_requests(p_org_id, p_filters)` — DB-RPC read; the approval queue (§10.1).
8. `kernel.record_money_denial` (§8.4) — DB-RPC, definer/service_role only.
9. `kernel.set_org_payout_destination` — **contract written for the first time** (§8); referenced by four frozen documents, contracted in none.

### `NEW EDGE FUNCTION`
**None.** `refund-execute` and `payout-execute` gain `action` values and the two corrections in §12
`SPEC CORRECTION` items 9–10. No new Stripe surface, no new secret, no new endpoint.

### `NEW DASHBOARD SURFACE`
1. Refund approval queue (second approver's inbox).
2. Step-up re-authentication flow for money actions (§8.3).
3. Payout probation explainer within the existing §14.5 payouts surface.

### `NEW RN SURFACE`
1. `refund_pending` state on My Ticket detail + Entry Pass.
2. Buyer self-service refund request (capped, windowed).
3. Refunded-but-already-scanned outcome copy.

### `NO SCHEMA CHANGE`
Destination probation (§8.4 Control 4) reuses `kernel.payout.status='held'` + the existing
`kernel.release_payout`. Partial-refund atom coverage and per-atom pricing (§5.4 Race 4) derive entirely from
`kernel.ticket_ownership_log` + `venue.order_item`. Org scoping for both read RPCs derives from existing,
indexed columns. Every threshold lives in the existing `catalog.platform_config`.

---

## 13. Correction index — the `AUTHZ-C1A` / `AUTHZ-C1B` reconciliation pass (2026-08-28)

**Authority:** ratification rows **C57** (`AUTHZ-C1A`, `C1A2`, `M1`, `M2`) and **C58** (`AUTHZ-C1B`), both
**RATIFIED · Gate P · MVP-must-implement YES**, recorded 2026-08-27 by the authz remediation pass. **That pass
did not edit this document** — it named RLS, RPC and the schema spec in its target columns and not this file,
which is how a `BUILD-READY DELTA SPEC` came to state a defect as its contract for a full remediation cycle.
This pass applies those two ratified corrections here and files rows **`D14`** (this reconciliation),
**`D15`** (the amendment of C57's and C58's own target columns to name this document) and **`C75`** / open
decision **`O11`** (the missing precedence rule) in
`docs/architecture/_governance/PHASE_2_RATIFICATION_RECORD.md`.

**No new design decision is taken in this pass, and no owner decision is made.** Every substantive rule below
already existed in a ratified row; the only thing that changed is that this document now states it.

### 13.1 What changed, section by section

| § | Before (as it stood at `cbf8926`) | After | Ratified by |
|---|---|---|---|
| header | `**Status:** BUILD-READY DELTA SPEC.` — no indication the document had been skipped by the remediation pass | **LIVE-not-superseded** status + reconciliation banner recording the live-vs-retired determination, its evidence, and which side was conformed to which | `D13` |
| **§6.1** | tier table had two columns (`Outcome`, `Effect`); the tier was computed, returned and **discarded**; result field `approval_required_role?` | tier table carries the **stored** `required_approver_class` column; this function is named as its **first writer**; consumed-atom precedence stated; grant maturity binds the **requester**; result field renamed `required_approver_class?`; `sod_violation` / `step_up_unavailable` added to the taxonomy | `C57`, `C58` |
| **§6.2** | *"For `pending_approval`: `has_org_role(...)` AND `auth.uid() <> requested_by` … For `pending_platform_review`: `is_platform([...])`"* — **a branch on two unstored return strings** | **`AUTHZ-C1A`**: five-row `(action, required_approver_class)` table identical to RPC §17.2, the trap explained rather than merely corrected, `AUTHZ-C1A2`, the *actionability ≠ authority* rule, the re-derived-tier rule (`stale`, never a re-route), and the corrected error taxonomy incl. `self_approval` | `C57` |
| **§6.6** | *"one object, not three"* + the payload footgun; **no tier column, no approver class, one SoD CHECK** | full column set reconciled to schema §1.13.2/§1.13.3 with `required_approver_class` first; the **CHECK pair** of `AUTHZ-M1`; the footgun paragraph now says *why* the missing column was pushing implementers into `payload` | `C57` |
| **§6.7** | `request_org_payout`: *"Adds three preconditions"*; `set_org_payout_destination`: no role predicate at all | **four** preconditions, the fourth being `kernel.money_role_grant_matured`; never applied to a deny or cancel; the destination setter's role predicate written out with the same conjunct | `C58` |
| **§6.7a** | *did not exist* | **NEW** — a *reference*, not a definition, to `kernel.money_role_grant_matured`, with the four properties this document depends on stated so a drift at the defining site is visible | `C58` |
| **§7.3** | the money-key approval object described without a stored class | `required_approver_class := 'platform_admin'`, `org_id IS NULL`, and why the third label exists | `C57` |
| **§8.2** | controls 1–6 described; **no caller predicate stated as a contract**, no maturity conjunct | caller predicate written as a contract line (`org_owner` only + step-up + maturity), and *why maturity binds the SETTER* | `C58` |
| **§8.5** | six ranked controls | control **1b** inserted below control 1, ranked separately because the two fail independently | `C58` |
| **§9.2** | above-threshold payout parks an approval; dispatch described as `action`-based | dispatch is `(action, required_approver_class)`; named as the **third writer** of the class; `platform_support` denied on the payout arm; result shape stated | `C57` |
| **§12** | ADDITIVE item 1 listed the table **without** the tier column and with a **single** SoD CHECK; no `granted_at` item | item 1 carries the column, the full CHECK set and both indexes; **new item 3a** for `kernel.org_member.granted_at` | `C57`, `C58` |

### 13.2 What this pass did NOT do, stated because the boundaries are load-bearing

- **It did not retire this document.** The live-vs-retired question was settled on evidence (banner, §13.3),
  not on the fact that a remediation pass skipped it.
- **It did not define `kernel.money_role_grant_matured`.** That contract belongs to RPC §1's predicate-helper
  substrate and is owed there; §6.7a **references** it and states the four properties this document depends
  on. **If those four and the defining contract disagree, the defining contract wins and §6.7a is the defect.**
- **It did not decide the precedence question.** Two documents both labelled build-ready gave contradictory
  authority branches for the same money RPC, and `PHASE_2_SPEC_FOUNDATION.md` §0 supplies no tie-break — it
  says *"if a source document conflicts with this file, surface the conflict; do not silently pick a side"*,
  and its authority order does not rank delta specs against each other. `ARCHITECTURE_FREEZE.md` Rule 3 ranks
  *tiers* and places every delta spec **in one tier**, so a delta-vs-delta conflict is unresolvable by the
  stated rules. **Ranking delta specs against each other is an OWNER decision** and is recorded as row
  **`C75`** / open decision **`O11`**, not made here. What this pass relied on instead is narrower and does
  not generalize: **RPC §17.x carries the `AUTHZ-C1A`/`AUTHZ-C1B` remediation tags ratified as C57/C58 and
  this document carried none**, so one side stated a ratified correction and the other stated the text that
  correction replaced. That is a reading of the ratification record, available with no precedence rule at all.
- **It touched no SQL, no migration, no code, and nothing under `supabase/` or `.github/`.** It reopened no
  production migration (`071`–`075`), renumbered no package (`076`–`091`), and weakened no CI gate, ratchet or
  floor. **The frozen Stripe money core is untouched** — this pass reconciled *specification text about
  authority*; no money-movement path, idempotency key, funding source or Stripe surface changed, and the
  §Invariant-attestation table above still holds line for line.
- **It made no owner decision.** The open numbers this reconciliation depends on stay open with their existing
  owners: `authn.money_role_maturity_hours` (RLS `MD-14`), `refund.platform_support_max_minor` (§11 `D-3`),
  and §11 `D-1` (whether the approval object is a sixteenth SSCAS member).
- **It resolved neither of the two conflicts it surfaced in §6.7a** — the immature-grant failure code stated
  as `sod_violation` (RPC/RLS) vs `precondition_failed('money_role_too_new')` (schema §1.13.4), and schema
  §1.13.4's listing of `set_platform_config`'s **platform-plane** money arm as a site for an **org-plane**
  maturity predicate. Both are outside `C57`/`C58`, both belong to the schema owner, and both are **reported
  where a reader will hit them** rather than decided.

### 13.3 The live-vs-retired determination, recorded so it is not re-litigated

**Determination: LIVE.** The evidence, in the order a reviewer would check it:

1. **`ARCHITECTURE_FREEZE.md` names this file by path** in the covered set, as an *owner-ruling delta (O-1,
   O-3)*, *"same tier as the implementation specs in the authority order below, and covered by Rule 1 from the
   moment they are ratified into the record."* It is ratified into the record — rows **O-1** and **O-3**.
2. **It is cited as authority by documents that were themselves corrected by the remediation pass** — RLS
   §11.3 (*"money spec §2.3 — replaces the corresponding §11.1 rows"*), RPC §17.2 (*"The money spec §7.3
   says…"*), schema §1.13 (*"MONEY §6.6, §12 ADDITIVE-1"*) and §1.13.2 (tier conditions cited as
   *"MONEY §5.2 / §9.2 / §7.3"*). A retired document cannot be the cited source of a live constraint.
3. **Ratification row `D6` chose THIS document over a sibling** — it applied this spec's corrected §7.6 money
   matrix into the constitution and **rejected** the role-model spec's instruction to delete §7.6 and point
   elsewhere. That is a ratified finding that this document, not the sibling, holds the O-1/O-3 money
   authority statement.
4. **It carries no supersession banner and sits in `docs/architecture/`, not `_superseded/`** — the corpus
   marks retirement by relocation, and four documents already sit there.
5. **Sections nobody else covers.** §4 (read-scoping isolation proof), §5 (request-vs-execute with its four
   races), §7 (threshold and configuration model, incl. the lock-order placement of the approval object) and
   §8's ranked control set are stated in full **only here**. Retiring the file would delete them, and the
   corpus rule the task's own framing states — *do not retire a document that other specs cite as authority
   for sections nobody else covers* — is dispositive on its own.

**Conclusion:** the exclusion was an **oversight of the remediation sweep**, not a signal of retirement. The
remedy is reconciliation plus a ledger row that makes the omission visible (`D15`), not a supersession banner.

---

*End of `docs/architecture/PHASE_2_MONEY_AUTHORITY_SPEC.md`. Design-only; no SQL, no migrations, no
implementation code. Delta against the frozen constitutions — integration is a later, separate act. Produced
under owner rulings O-1, O-2 (context) and O-3; R7, OBS-1, GP-1/GP-2, C26, C28, C35 and C36 verified preserved
in the attestation table above; every inference is labelled, and every decision I declined to make alone is in
§11.*
