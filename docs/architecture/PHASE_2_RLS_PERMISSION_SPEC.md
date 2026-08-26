# Phase 2 — RLS & Permission Specification

**Status:** BUILD-READY DESIGN SPEC. Design-only — **no SQL, no policy code**. This file is the
conceptual role × operation authority matrix an implementing engineer authors RLS policies, `REVOKE`/`GRANT`
statements, and scoped read RPCs from **without making an authorization decision**. Where a decision remained
open it is flagged under §15 RECONCILIATION.

**Binding inputs (authority order):**
1. `docs/architecture/PHASE_2_SPEC_FOUNDATION.md` (committed copy of the session SPEC_FOUNDATION) — **BINDING**: §4 C35/C36 role model, §6 table inventory + RLS class,
   §8 Phase-0 security invariants, §7 market bridge rule.
2. `docs/architecture/PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md` — the authoritative table set, each table's stated RLS
   classification, write authority, and read authority. Every table below uses its exact name and honors its
   stated classification.
3. `docs/architecture/PHASE_1_FOUNDATION.md` + `docs/architecture/SNATCH_IT_ENGINEERING_STANDARDS.md` — the Phase-0 RLS/definer
   discipline (§7 RLS policy, §8 SECURITY DEFINER policy, §9 payment protection) that every table preserves.
4. the five RN reconciliation targets (session working file; all five CONSUMED and CLOSED — see `docs/architecture/_superseded/PHASE_2_IMPLEMENTATION_SPEC_REVIEW.md` §2.2/§5) — the five RN reconciliation targets, consumed in §14 (esp. #5
   redacted ownership-history read).

**Coverage:** all **43** MVP objects (kernel 12 · catalog 5 · venue 20 · market 6-incl.-bridge-view). EXT
tables (`kernel.reserve`, `venue.inventory_unit`) are specified with their MVP deny-all posture and marked
DO-NOT-BUILD. Deferred schemas (`social`/`analytics`/`notify`/`adapter`, money-ledger) are out of scope.

---

## 1. How to read this document

### 1.1 Roles (the 15 principals) and how each is tested

Human "roles" here are **application roles**, not Postgres roles. The only Postgres roles are `anon`,
`authenticated`, and `service_role`. Every app-role test is a **scope-qualified predicate** (C36, §2) run
inside an RLS policy or RPC — never a bare string comparison.

| # | Role (matrix label) | Postgres role | How the policy tests it | Scope |
|---|---|---|---|---|
| 1 | `anon` | `anon` | unauthenticated request | none |
| 2 | `fan` (authenticated fan) | `authenticated` | `auth.uid()` present, no org/venue/platform role | self |
| 3 | `owner` (row owner) | `authenticated` | `auth.uid() = <row owner col>` (buyer/seller/current_owner/identity/from/to) | row |
| 4 | `o_mbr` (org_member) | `authenticated` | `has_org_role(org_id,[org_member])` | org |
| 5 | `o_own` (org_owner) | `authenticated` | `has_org_role(org_id,[org_owner])` | org |
| 6 | `o_adm` (org_admin) | `authenticated` | `has_org_role(org_id,[org_admin])` | org |
| 7 | `o_fin` (org_finance) | `authenticated` | `has_org_role(org_id,[org_finance])` | org |
| 8 | `v_mgr` (venue_manager) | `authenticated` | `has_venue_role(venue_id,[venue_manager])` | venue |
| 9 | `v_door` (venue_door) | `authenticated`/door_pin device principal | `has_venue_role(venue_id,[venue_door])` or valid `venue.door_pin` for the session | venue/session |
| 10 | `v_fin` (venue_finance) | `authenticated` | `has_venue_role(venue_id,[venue_finance])` | venue |
| 11 | `promo` (promoter) | `authenticated` | `has_venue_role(venue_id,[venue_promoter])` (enum label = `venue_promoter`) | venue |
| 12 | `p_sup` (platform_support) | `authenticated` | `is_platform([platform_support])` | platform |
| 13 | `p_rsk` (platform_risk) | `authenticated` | `is_platform([platform_risk])` | platform |
| 14 | `p_adm` (platform_admin) | `authenticated` | `is_platform([platform_admin])` | platform |
| 15 | `svc` (service_role) | `service_role` | machine identity (Supabase service key / definer context) | machine only |

> **`promo` ↔ `venue_promoter`.** The prompt's `promoter` is the C36 **venue-scope** `venue_promoter` label,
> tested by `has_venue_role`. It is NOT an org or platform role. Its data visibility is deliberately narrow
> (own links/attributions/commission only — CDM §8; never the back office).

> **`service_role` is a machine identity, NEVER a human authority path** (Phase-0 056b/063, SPEC_FOUNDATION
> §8). It bypasses RLS by Postgres design, so it appears as `A` on reads — but the discipline is: no human
> ever authenticates as `service_role`; it is used only by edge functions and as the effective privilege the
> `postgres`-owned `SECURITY DEFINER` RPCs run with. A `svc` write cell is always **the definer path**, never
> a UI path.

### 1.2 Operations & cell vocabulary

Columns per matrix: **SEL** (SELECT) · **INS** (INSERT) · **UPD** (UPDATE) · **DEL** (DELETE) ·
**EXEC** (which write RPCs the role may invoke).

| Cell | Meaning |
|---|---|
| **A** | ALLOW — direct access granted by an RLS policy + column/table GRANT (direct table DML/read). |
| **D** | DENY — no access by this role on this path (absence of policy = deny-by-default, Standards §7). |
| **R** | RPC-ONLY — no direct client DML; the mutation happens **only inside a `SECURITY DEFINER` RPC**. The role may drive it *iff* the EXEC column lists it for that RPC. `R` in a write cell always implies direct DML is REVOKEd. |
| **V** | VIEW-ONLY — read permitted **only** through a scoped/redacted read RPC or a bridge view; **no direct table SELECT**. Used for money/custody/PII surfaces. |
| ⁿ | superscript → a **column-scoped** note (the grant/read is restricted to named columns; see the table's notes). |

### 1.3 Two global postures that apply to EVERY table (stated once)

**GP-1 — Direct client DML is DENY everywhere on Phase-2 tables.** No `anon`/`authenticated` principal (and
therefore no human app-role) ever holds direct `INSERT`/`UPDATE`/`DELETE` on any kernel/venue/market/catalog
table. Every write is `R` (RPC-ONLY) via a `postgres`-owned `SECURITY DEFINER` function with `REVOKE
INSERT,UPDATE,DELETE FROM anon, authenticated` (Standards §7/§8, 067). So in every matrix the INS/UPD/DEL
cells are `R` (the role can drive the write through an authorized RPC) or `D` (the role has no authorized RPC
for that write). **There is no `A` write cell anywhere in this spec** — that is the deny-by-default money/custody
boundary, by construction.

**GP-2 — DELETE is DENY for every role on every table (no row deletion).** All FKs are `ON DELETE RESTRICT`;
ledgers are append-only; state is a column transition (`voided`/`expired`/`cancelled`), never a row removal
(CDM §10, D2). The only cascades (`inventory_batch_shard`←batch, `guest_entry`←guest_list) fire only inside
the parent's RPC, never as a client DELETE. Therefore **DEL = D for all 15 roles on all 43 objects** and is
shown as `D` throughout; corrections are compensating rows / forward state transitions.

Because GP-1/GP-2 make INS/UPD/DEL highly regular, each matrix's **discriminating column is SEL**, and the
write nuance lives in **EXEC** (which RPC, which role). Read the SEL column and the EXEC column carefully;
INS/UPD are `R` for the roles the EXEC column authorizes and `D` otherwise; DEL is always `D`.

---

## 2. C36 — the scope-qualified role model, made STRUCTURAL

C36's mandate: roles are **never bare strings**; scope is always in the predicate; the enum label sets are
**disjoint** so cross-scope confusion is structurally impossible. This is the backbone of every matrix below.

### 2.1 Three disjoint enum label sets (no overlap by construction)

| Scope | Physical table | enum labels (DISJOINT) |
|---|---|---|
| **org** | `kernel.org_member.role` | `org_owner` · `org_admin` · `org_finance` · `org_member` |
| **venue** | `venue.staff_role.role` | `venue_manager` · `venue_finance` · `venue_door` · `venue_promoter` |
| **platform** | `kernel.platform_role.role` | `platform_admin` · `platform_support` · `platform_risk` |

The label sets share **no common string**. There is no bare `finance`, `admin`, or `manager` — only
`org_finance`, `venue_finance`, `platform_admin`, etc. Consequence: a policy can never accidentally accept a
venue-finance staffer where org-finance is required, because the *strings never match* and the *predicate
carries the scope id*. A leaked/confused `role` value cannot cross a scope boundary — it fails the label check
and the scope-id check simultaneously.

### 2.2 The four predicate helpers (the ONLY sanctioned way to test a role)

Conceptual behavior (defined as SECURITY DEFINER helpers in the RPC spec, `search_path` pinned, owned by
`postgres`; **live-table reads, never JWT claims** — C9/§3):

- **`kernel.has_org_role(org_id, role[])`** → reads `kernel.org_member` for `(org_id, auth.uid())` and returns
  true iff the stored `role` ∈ the requested set. Reads the **live** membership row (a demotion/revoke takes
  effect immediately; a stale JWT cannot re-grant).
- **`kernel.has_venue_role(venue_id, role[])`** → reads `venue.staff_role` for `(venue_id, auth.uid(), role)`
  live. Door path also accepts a valid non-expired `venue.door_pin` bound to the session as a `venue_door`
  device principal.
- **`kernel.has_event_role(event_id, role[])`** → **resolves event → venue via `catalog`**
  (`catalog.event.venue_id`), then delegates to `has_venue_role(venue_id, role[])`. This is the single place
  event-grain authorization is turned into venue-grain authority; no table stores an "event role" — it is
  always derived, so there is no second source of venue authority to drift. (Org-level authority over an
  event resolves `catalog.event.org_id` → `has_org_role`.)
- **`kernel.is_platform(role[])`** → reads `kernel.platform_role` for `auth.uid()` live, extending the
  existing `public.admin_users` bootstrap. Platform authority is global (no scope id).

### 2.3 Why a bare `role = 'finance'` comparison is FORBIDDEN

A bare comparison (a) has no scope id, so it would grant a person finance authority over **every** org/venue,
not the one they belong to; (b) relies on a single ambiguous label that could match across scopes; (c) if read
from a JWT claim, survives a revoke (stale-authority bug). The predicate helpers eliminate all three: scope id
is a required argument, the label set is scope-disjoint, and the read is live. **No RLS policy or RPC in this
spec ever compares a bare role string.** Every role cell in every matrix below is realized by exactly one of
the four helpers with an explicit scope argument.

### 2.4 Org→venue authority inheritance (explicit, bounded)

An org's `org_owner`/`org_admin` implicitly has venue-management authority over venues their org operates
(`catalog.venue.org_id = org`). This inheritance is expressed **inside the write RPCs** (e.g.
`venue.grant_staff_role` accepts `has_venue_role(venue_id,[venue_manager]) OR has_org_role(org_of_venue,
[org_owner,org_admin])`), **not** by widening venue RLS to org roles. Read RLS keeps org and venue scopes
separate; where the matrices grant an org role read access to a venue-scoped table, it is because the schema
spec's read authority names the org (e.g. settlement/attribution money rollups), resolved via
`catalog.venue.org_id`.

---

## 3. Phase-0 invariants preserved (the rules), then conformance

Every rule from SPEC_FOUNDATION §8 + Standards §7/§8/§9 is listed, with how this spec enforces it globally.

| # | Phase-0 invariant | How this RLS spec conforms |
|---|---|---|
| I-1 | **Deny-by-default RLS** (absence of policy = no access) | RLS ON for all 43 objects; every SEL cell not marked `A`/`V` is `D`; no table relies on an implicit grant. |
| I-2 | **No broad `USING(true)` on sensitive tables** | Public-read tables (catalog, availability projections, active listings) use a **narrow predicate** (`status='approved'`/`active`/`public`), never `USING(true)`. Money/custody/PII tables are deny-all (RLS on, zero policies). See §5 quick-ref. |
| I-3 | **No direct client writes to money/custody ledgers** | GP-1: every money/custody table is money-custody-RPC-only; `REVOKE INSERT,UPDATE,DELETE FROM anon,authenticated`; only definer RPCs write. See §5 sensitive-write list. |
| I-4 | **Column-scoped grants** (never expose sensitive columns to a broad role) | `identity_ext` (kyc/region), `organization` (payout ref), `signing_key` (`kms_handle_ref`), `door_pin` (`pin_hash`), `tickets`/`market_sale`/`payout`/`refund` money+PII columns are column-restricted; sensitive columns read only via scoped RPC. See §6 column-scoped read list. |
| I-5 | **Live-table recheck for money-consequential actions** (not stale JWT) | All four predicate helpers read live membership/role tables; money RPCs re-read the target row `FOR UPDATE` and re-validate ownership/state (C35, §2.2). No authorization is taken from a JWT claim. |
| I-6 | **SECURITY DEFINER `search_path` pinned** (066) | Every write/read RPC and every predicate helper pins `search_path` and is owned by `postgres` (Standards §8). |
| I-7 | **Explicit REVOKE-then-GRANT** (067) | Each table: `REVOKE ALL FROM anon, authenticated, public` first, then GRANT only the exact SELECT columns / EXECUTE the matrix authorizes. A bare `REVOKE FROM PUBLIC` is insufficient where explicit role grants exist. |
| I-8 | **`service_role` = machine identity, never human authority** (056b/063) | `svc` is never an app-role; no human logs in as it; it is only the edge-fn key + definer effective privilege. Marked `A(machine)` on reads with that caveat. |
| I-9 | **Constant-time secret compare** | `venue.door_pin.pin_hash` is never client-readable and compared constant-time inside the door-auth RPC (§ venue.door_pin). |
| I-10 | **`stripe-webhook` keeps `verify_jwt=false`** | Unchanged; the native rail links to `public.payments` (money-in) via `kernel.payment_native`, never re-implements the webhook (§14.4, §13). |
| I-11 | **No self-grant of authority** (H-2/C9) | `grant_org_role`/`grant_platform_role`/`grant_staff_role` require an *existing* higher authority and forbid the caller granting themselves a role they don't already have the authority to grant; dual-control seam on platform-role + payout-destination. |

---

## 4. Global write posture per RLS class (applies before any table matrix)

Each table carries one RLS class from the schema spec (§0.7). The class fixes the write posture; the matrix
then refines reads and EXEC.

| RLS class | SEL default | INS/UPD default | DEL | Notes |
|---|---|---|---|---|
| **public-read** | `A` for anon+all (narrow predicate) | `R` (RPC-only, platform/org/venue authors) | `D` | reference/discovery data; writes RPC-only. |
| **owner-scoped** | `A` for `owner` (own row) + platform read | `R` (owner or platform via RPC) | `D` | `auth.uid()`-scoped. |
| **org-scoped** | `A` for org roles of the owning org + platform | `R` (org roles via RPC) | `D` | fail-closed on org id. |
| **venue-scoped** | `A` for venue roles of the owning venue + platform | `R` (venue roles via RPC) | `D` | fail-closed on venue id. |
| **money-custody-RPC-only** | **deny-all** (`D` direct); reads = `V` via scoped RPC only | `R` (definer only) | `D` | RLS on, zero policies + `REVOKE ALL`. THE money boundary. |
| **audit-only** | `D` direct; read `V` via `is_platform` RPC only | `R` (definer only, in-txn) | `D` | append-only privileged log. |

---

## 5. Quick-reference — SENSITIVE "RPC-only-write" tables (money / custody)

Deny-all RLS + `REVOKE ALL FROM anon,authenticated` + writers are `postgres`-owned SECURITY DEFINER RPCs ONLY.
**No client (of any app-role) ever writes these directly.** This is the Phase-0 deny-all pattern (Standards §7)
applied to every money/custody ledger — the exact set the prompt requires be RPC-ONLY for clients.

| Table | Class | Sole write path(s) (RPC) | Custody/money role |
|---|---|---|---|
| `kernel.ticket_ownership_log` | money-custody-RPC-only (AO) | `issue_ticket_atoms` · `transfer_ticket_ownership` · `void_ticket_atom` | **custody ledger (SoT)** |
| `kernel.tickets` (atom head) | money-custody-RPC-only | same three + scan RPC (state→scanned) | custody head |
| `kernel.payment_native` | money-custody-RPC-only | `issue_ticket_atoms` · `transfer_ticket_ownership` | money-in link |
| `kernel.payout` | money-custody-RPC-only | `close_settlement` · native-sale payout path · `pay_promoter_commission` | payout ledger |
| `kernel.refund` | money-custody-RPC-only | `refund_primary_order` · `admin_refund` · C25 sweep | refund ledger |
| `kernel.reserve` (EXT stub) | money-custody-RPC-only | none wired in MVP | reserve (Gate M) |
| `kernel.signing_key` (`kms_handle_ref`) | money-custody-RPC-only (col) | `provision/rotate/revoke_signing_key` | credential custody |
| `venue.inventory_batch` (counter) | money-custody-RPC-only (counter cols) | `reserve_inventory` · `release_hold` · `issue_ticket_atoms` · `void_ticket_atom` | oversell guard (SoT) |
| `venue.inventory_batch_shard` | money-custody-RPC-only | same as batch (ordered shard draw) | oversell guard |
| `venue.inventory_movement` | money-custody-RPC-only (AO) | the reserve/issue/void functions (same txn) | inventory audit ledger |
| `venue.inventory_hold` | owner+venue read; **counter effect** RPC-only | `reserve_inventory` · `release_hold` · expiry sweep | held-counter driver |
| `venue.order` (money cols) | owner/org read; money RPC-only | `create_order` · `issue_ticket_atoms` · refund RPCs | order money state |
| `venue.settlement` / `settlement_line` | org-scoped read; RPC-only | `open_settlement` · `close_settlement` | settlement ledger |
| `market.market_sale` | money-custody-RPC-only | `transfer_ticket_ownership` (via market) · C25 sweep | resale consummation (SoT) |
| `market.p2p_transfer` (custody effect) | owner read; RPC-only | `create/accept_p2p_transfer` · expiry sweep | native custody move |
| `kernel.admin_audit` | audit-only | every privileged RPC writes its own row in-txn | privileged-action ledger |
| `venue.scan` | venue read; RPC-only (AO) | `record_scan` · offline-reconciliation batch | admission ledger (custody-adjacent) |
| `venue.comp_allocation` | venue read; RPC-only | `allocate_comp` · `issue_comp` | capacity-drawing (money-adjacent) |
| `venue.attribution` | promoter/org read; RPC-only (AO) | attribution recorder (in `create_order`) | commission basis |

> **Clients receive ownership-log / payout / refund / market_sale / inventory-movement data ONLY as
> `V` (scoped, redacted read RPC).** Raw ledger rows are never SELECTable by `anon`/`authenticated`. See §14.5
> for the redacted ownership-history read (recon #5).

---

## 6. Quick-reference — COLUMN-SCOPED read tables (I-4)

These tables are readable by a role for **some** columns only; the sensitive columns are stripped from the
GRANT and served (if at all) via a scoped RPC. Implements Phase-0 column-scoped grants (041/052/062/068).

| Table | World/broad-readable columns | RESTRICTED columns (scoped RPC / owner / platform only) |
|---|---|---|
| `kernel.identity_ext` | (none broadly) — own row only | `kyc_ref`, `residency_region` → owner + `is_platform` RPC |
| `kernel.organization` | `display_name`, `status` (members) | `stripe_connect_account_ref`, `payout_destination_locked_until`, `legal_name` → `org_owner`/`org_finance`/platform |
| `kernel.tickets` | owner: full own atom; venue: ops cols | `current_owner_id`/PII of *other* owners → never cross-owner; history via redacted RPC only |
| `kernel.signing_key` | `public_key`, `not_before`, `not_after`, `status`, scope target (world) | `kms_handle_ref` → `is_platform` only |
| `kernel.payout` | payee: own payout summary | full ledger → `o_fin`/`v_fin`/platform scoped RPC |
| `kernel.refund` | buyer: own refund summary | full ledger → `o_fin`/platform scoped RPC |
| `venue.ticket_type` | `public` visibility: name/price (world) | `hidden`/`door_only` rows → venue-scoped only |
| `venue.inventory_batch` | `remaining` (computed) projection (world) | `capacity`/`held`/`sold` raw counters → venue staff + platform |
| `venue.door_pin` | `label`, `status`, `expires_at` (venue mgr) | `pin_hash` → **never client-readable**; constant-time compare inside RPC |
| `venue.order` | buyer: own order; org: order summary | payment linkage / other-buyer PII → scoped |
| `market.market_sale` | buyer/seller: own sale (plain verbs) | fee split, `payment_id`, counterpart PII, cause internals → scoped RPC / platform |
| `market.listing_native` | active listing discovery cols (world) | seller PII / `command_idempotency_key` → seller + platform |
| `kernel.ticket_ownership_log` | **none** to clients | entire table → redacted `market.get_ticket_history` RPC (owner-scoped) / platform (§14.5) |

---

## 7. Schema `kernel` — matrices

> Reminder (GP-1/GP-2): INS/UPD = `R` where EXEC authorizes, else `D`; **DEL = `D` for all roles, all tables**.
> `svc` = machine/definer path only (I-8).

### 7.1 `kernel.identity_ext` — owner-scoped (col-scoped: kyc/region)
Write RPC: `kernel.upsert_identity_ext` (self for benign fields; `is_platform` for `residency_region`/`kyc_ref`, audited).

| Role | SEL | INS | UPD | DEL | EXEC |
|---|---|---|---|---|---|
| anon | D | D | D | D | — |
| fan | D | D | D | D | — |
| owner | A¹ | R | R¹ | D | `upsert_identity_ext` (own benign cols) |
| org_member/owner/admin/finance | D | D | D | D | — |
| venue_manager/door/finance | D | D | D | D | — |
| promoter | D | D | D | D | — |
| platform_support | V² | D | D | D | — (support read via RPC) |
| platform_risk | V² | D | D | D | — |
| platform_admin | A | R | R | D | `upsert_identity_ext` (region/kyc override, audited) |
| service_role | A(machine) | R(def) | R(def) | D | definer |

¹ owner reads/writes only own row; `kyc_ref` write is platform-only. ² platform read is `V` via scoped RPC
(region for support/risk decisions), never raw kyc PII unless `platform_admin`.

### 7.2 `kernel.organization` — org-scoped (col-scoped: payout ref/legal_name)
Write RPCs: `create_organization`, `set_org_status` (platform), `set_org_payout_destination` (org_owner, dual-control seam).

| Role | SEL | INS | UPD | DEL | EXEC |
|---|---|---|---|---|---|
| anon | D | D | D | D | — |
| fan | D | R³ | D | D | `create_organization` (apply) |
| owner (applicant) | A(own) | R | D | D | `create_organization` |
| org_member | A⁴ | D | D | D | — |
| org_owner | A | D | R | D | `set_org_payout_destination` (dual-control) |
| org_admin | A | D | R⁴ | D | benign profile fields |
| org_finance | A⁴ | D | D | D | — (reads payout ref⁴) |
| venue_manager/door/finance | D | D | D | D | — |
| promoter | D | D | D | D | — |
| platform_support | A | D | D | D | — |
| platform_risk | A | D | D | D | — |
| platform_admin | A | R | R | D | `set_org_status` (approve/suspend) |
| service_role | A(machine) | R(def) | R(def) | D | definer |

³ any authenticated user may apply to create an org (status starts `applied`); becomes `org_owner` of it.
⁴ `stripe_connect_account_ref`/`legal_name`/payout-lock are col-scoped to `org_owner`/`org_finance`/platform;
`org_member`/`org_admin` see `display_name`/`status` only.

### 7.3 `kernel.org_member` — org-scoped
Write RPCs: `grant_org_role`, `revoke_org_role` (require `has_org_role(org_id,[org_owner,org_admin])`; **no self-grant**; cannot remove last `org_owner`).

| Role | SEL | INS | UPD | DEL | EXEC |
|---|---|---|---|---|---|
| anon | D | D | D | D | — |
| fan | D | D | D | D | — |
| owner (self as member) | A(own membership) | D | D | D | — |
| org_member | A(own org roster) | D | D | D | — |
| org_owner | A | R | R | D⁵ | `grant_org_role`/`revoke_org_role` |
| org_admin | A | R | R | D⁵ | `grant_org_role`/`revoke_org_role` (cannot grant `org_owner`) |
| org_finance | A(roster) | D | D | D | — |
| venue_manager/door/finance | D | D | D | D | — |
| promoter | D | D | D | D | — |
| platform_support | A | D | D | D | — |
| platform_risk | A | D | D | D | — |
| platform_admin | A | R | R | D⁵ | override grant/revoke (audited) |
| service_role | A(machine) | R(def) | R(def) | D | definer |

⁵ revoke is a role-remove via RPC (a row UPDATE→removed inside the revoke RPC), never a client DELETE; the
"≥1 org_owner" invariant is enforced in the RPC. **No self-grant** (I-11): the caller cannot grant themselves a
role tier they do not already have authority over.

### 7.3b `kernel.org_invite` — org-scoped + addressed-invitee (ADDENDUM A1 — schema §1.3b, migration 072)
Write RPCs: `invite_org_member` (require `has_org_role(org_id,[org_owner,org_admin])`; `org_admin` cannot
invite at `org_owner`; **no self-invite to a higher tier**, I-11), `accept_org_invite` (only the addressed
invitee), invite-revoke (inviter-tier or platform). Mirrors `org_member`'s posture; the invite is the
capability *offer*, never the capability itself — membership exists only when accept creates the
`kernel.org_member` row in the same txn.

| Role | SEL | INS | UPD | DEL | EXEC |
|---|---|---|---|---|---|
| anon | D | D | D | D | — |
| fan (not addressed) | D | D | D | D | — |
| addressed invitee | A(own invite) | D | D | D | `accept_org_invite` (own, pending, unexpired) |
| org_member / org_finance | D | D | D | D | — |
| org_owner | A(own-org invites) | R | R | D | `invite_org_member` / revoke |
| org_admin | A(own-org invites) | R | R | D | `invite_org_member` (≤ own tier) / revoke |
| venue_* / promoter | D | D | D | D | — |
| platform_support | A | D | D | D | — |
| platform_risk | A | D | D | D | — |
| platform_admin | A | R | R | D | override (audited) |
| service_role | A(machine) | R(def) | R(def) | D | definer (expiry sweep → `expired`) |

No self-escalation: the invited `role` is CHECK-bound to the org enum and tier-guarded in the RPC; a pending
invite grants nothing until accepted; `expires_at` bounds the window; GP-2 (no client DELETE) holds.

### 7.4 `kernel.platform_role` — audit-only (bootstrap via public.admin_users)
Write RPC: `grant_platform_role`/`revoke_platform_role` (gated on existing `public.admin_users` / `is_platform([platform_admin])` bootstrap + dual-control seam).

| Role | SEL | INS | UPD | DEL | EXEC |
|---|---|---|---|---|---|
| anon | D | D | D | D | — |
| fan / owner | D | D | D | D | — |
| all org roles | D | D | D | D | — |
| all venue roles / promoter | D | D | D | D | — |
| platform_support | V(own roles) | D | D | D | — |
| platform_risk | V(own roles) | D | D | D | — |
| platform_admin | A | R | R | D | `grant/revoke_platform_role` (dual-control, audited) |
| service_role | A(machine) | R(def) | R(def) | D | definer (bootstrap only) |

### 7.5 `kernel.tickets` — money-custody-RPC-only (owner + issuing-venue read)
Write RPCs: `issue_ticket_atoms`, `transfer_ticket_ownership`, `void_ticket_atom`, `record_scan` (state→scanned). **No client write path.**

| Role | SEL | INS | UPD | DEL | EXEC |
|---|---|---|---|---|---|
| anon | D | D | D | D | — |
| fan | D | D | D | D | — |
| owner (current_owner_id) | A⁶ | R⁷ | R⁷ | D | `create_p2p_transfer`/`market.create_listing`/checkout (drive transfer via market/venue RPCs) |
| org_member | D | D | D | D | — |
| org_owner/admin | A⁸(issuer org) | D | D | D | — |
| org_finance | A⁸ | D | D | D | — |
| venue_manager | A⁸(issuing venue ops) | D | D | D | — |
| venue_door | A⁸(scan cols, session) | R⁹ | R⁹ | D | `record_scan` (state→scanned) |
| venue_finance | A⁸ | D | D | D | — |
| promoter | D | D | D | D | — |
| platform_support | V | D | D | D | — |
| platform_risk | V | R | R | D | `void_ticket_atom`(dispute), freeze via `admin_resolve_dispute` |
| platform_admin | A | R | R | D | issue/transfer/void/admin overrides (audited) |
| service_role | A(machine) | R(def) | R(def) | D | definer (issue/transfer/void engines) |

⁶ owner reads own atom in full; **never** another owner's atom. ⁷ owner cannot mutate the atom directly; the
custody change is driven by invoking `market`/`venue` RPCs that call the kernel transfer engine (buyer id is
**server-verified**, C35). ⁸ issuing-venue/org staff read atoms of their own events (ops/manifest) —
current_owner PII col-scoped. ⁹ door writes only the `scanned` state transition via `record_scan`, under the
atom lock, and only for its session (door_pin/venue_door scope).

### 7.6 `kernel.ticket_ownership_log` — money-custody-RPC-only, AO (deny-all direct)
Write RPCs: `issue_ticket_atoms`, `transfer_ticket_ownership`, `void_ticket_atom` (SSCAS choke-points only). **Reads via `kernel.get_ticket_custody_chain` / redacted `market.get_ticket_history` — NO direct SELECT for any client.**

| Role | SEL | INS | UPD | DEL | EXEC |
|---|---|---|---|---|---|
| anon | D | D | D | D | — |
| fan | D | D | D | D | — |
| owner | **V**¹⁰ | R | D¹¹ | D | drives append via market/venue RPCs; reads redacted only |
| org_member | D | D | D | D | — |
| org_owner/admin | V¹² | D | D | D | `get_ticket_custody_chain` (own-event atoms) |
| org_finance | V¹² | D | D | D | reconciliation read (scoped) |
| venue_manager | V¹²(issuing venue) | D | D | D | `get_ticket_custody_chain` |
| venue_door | D | D | D | D | — |
| venue_finance | V¹² | D | D | D | — |
| promoter | D | D | D | D | — |
| platform_support | V | D | D | D | `get_ticket_custody_chain` |
| platform_risk | A(full, risk) | D | D | D | full chain (fraud/dispute) |
| platform_admin | A(full) | D | D | D | full chain (audit) |
| service_role | A(machine) | R(def) | D¹¹ | D | definer (append-only) |

¹⁰ **owner never gets raw log rows** — only the redacted, owner-scoped `market.get_ticket_history` (plain
verbs bought/transferred/scanned; cause-codes + prior-owner PII HIDDEN — recon #5, §14.5). ¹¹ **AO**: no
UPDATE/DELETE by anyone (guard trigger + `REVOKE UPDATE,DELETE`); corrections = compensating rows. ¹² org/venue
staff read the custody chain of atoms they issued via the scoped chain RPC (own-event only), counterpart PII
redacted.

### 7.7 `kernel.signing_key` — public_key public-read; kms_handle_ref custody-RPC-only
Write RPCs: `provision_signing_key`, `rotate_signing_key`, `revoke_signing_key` (platform).

| Role | SEL | INS | UPD | DEL | EXEC |
|---|---|---|---|---|---|
| anon | A¹³ | D | D | D | — |
| fan | A¹³ | D | D | D | — |
| owner | A¹³ | D | D | D | — |
| all org roles | A¹³ | D | D | D | — |
| venue_manager | A¹³ | D | D | D | — |
| venue_door | A¹³ | D | D | D | — (verifies with public_key in manifest) |
| venue_finance/promoter | A¹³ | D | D | D | — |
| platform_support | A¹³ | D | D | D | — |
| platform_risk | A¹³ | D | D | D | — |
| platform_admin | A(incl. kms_handle¹⁴) | R | R | D | provision/rotate/revoke |
| service_role | A(machine) | R(def) | R(def) | D | definer (KMS side-effects in `credential-sign` provisioning) |

¹³ **only** `public_key`, `scope`, target, `status`, `not_before`, `not_after` are readable (door manifest
needs them). ¹⁴ `kms_handle_ref` is col-scoped to `platform_admin`/`svc` — **the private key material is
NEVER in the DB** (C33); the signed token is produced by the `credential-sign` edge fn calling KMS.

### 7.8 `kernel.payment_native` — money-custody-RPC-only
Write RPCs: `issue_ticket_atoms`, `transfer_ticket_ownership` (link only; never re-charge — I-10).

| Role | SEL | INS | UPD | DEL | EXEC |
|---|---|---|---|---|---|
| anon | D | D | D | D | — |
| fan | D | D | D | D | — |
| owner (buyer/seller of linked payment) | V(own link) | D | D | D | — |
| org_member | D | D | D | D | — |
| org_owner/admin | D | D | D | D | — |
| org_finance | V(own-org links) | D | D | D | — |
| venue_finance | V(own-venue links) | D | D | D | — |
| venue_manager/door/promoter | D | D | D | D | — |
| platform_support | V | D | D | D | — |
| platform_risk | A(money read) | D | D | D | — |
| platform_admin | A | D | D | D | — |
| service_role | A(machine) | R(def) | R(def) | D | definer |

### 7.9 `kernel.payout` — money-custody-RPC-only
Write RPCs: `close_settlement`, native-sale payout path, `pay_promoter_commission`. Idempotency-keyed (Phase-0 discipline).

| Role | SEL | INS | UPD | DEL | EXEC |
|---|---|---|---|---|---|
| anon | D | D | D | D | — |
| fan | D | D | D | D | — |
| owner (payee identity) | V(own payout) | D | D | D | — |
| org_member/owner/admin | D | D | D | D | — |
| org_finance | V(own-org payouts) | D | D | D | — |
| venue_finance | V(own-venue payouts) | D | D | D | — |
| venue_manager/door/promoter | D¹⁵ | D | D | D | — |
| platform_support | V | D | D | D | — |
| platform_risk | A(money read) | D | D | D | — |
| platform_admin | A | R | R | D | admin payout ops (audited) |
| service_role | A(machine) | R(def) | R(def) | D | definer (settlement/native-sale/commission) |

¹⁵ `promoter` reads own `promoter_commission` payout **only** via a scoped RPC (own attribution), not the org
payout ledger (CDM §8).

### 7.10 `kernel.refund` — money-custody-RPC-only
Write RPCs: `refund_primary_order`, `admin_refund`, C25 auto-compensation sweep.

| Role | SEL | INS | UPD | DEL | EXEC |
|---|---|---|---|---|---|
| anon | D | D | D | D | — |
| fan | D | D | D | D | — |
| owner (buyer) | V(own refund) | D | D | D | — |
| org_finance | V(own-org refunds) | D | D | D | — |
| org_owner/admin/member | D | D | D | D | — |
| venue_finance | V(own-venue) | D | D | D | — |
| venue_manager/door/promoter | D | D | D | D | — |
| platform_support | V | R | D | D | `refund_primary_order` (support-initiated, capped, audited) |
| platform_risk | A(money read) | R | D | D | `admin_refund` (dispute) |
| platform_admin | A | R | R | D | `admin_refund` |
| service_role | A(machine) | R(def) | R(def) | D | definer (incl. C25 sweep) |

### 7.11 `kernel.reserve` — EXT (Gate M stub) — money-custody-RPC-only, DENY-ALL
**DO NOT BUILD writers in MVP.** Deny-all to every client; no read/write policy. Present only as an empty stub.

| Role | SEL | INS | UPD | DEL | EXEC |
|---|---|---|---|---|---|
| all 14 client roles | D | D | D | D | — (no writers wired) |
| service_role | A(machine) | R(def, future) | R(def, future) | D | Gate-M only |

### 7.12 `kernel.admin_audit` — audit-only, AO
Write: every privileged RPC writes its own audit row **in the same txn** as the action (in-txn side-effect, not a client call).

| Role | SEL | INS | UPD | DEL | EXEC |
|---|---|---|---|---|---|
| anon / fan / owner | D | D | D | D | — |
| all org roles | D | D | D | D | — |
| all venue roles / promoter | D | D | D | D | — |
| platform_support | V¹⁶ | D | D | D | — |
| platform_risk | V¹⁶ | D | D | D | — |
| platform_admin | A | D¹⁷ | D | D | — |
| service_role | A(machine) | R(def) | D | D | definer (in-txn append by each privileged RPC) |

¹⁶ platform_support/risk read the audit log scoped to their support/risk domain via `is_platform` RPC.
¹⁷ **AO**: no direct INSERT even by platform_admin — audit rows are written only as an in-txn side-effect of a
privileged RPC (guard trigger blocks UPDATE/DELETE; `REVOKE UPDATE,DELETE`).

---

## 8. Schema `catalog` — matrices (all public-read; writes RPC-only)

Catalog is world-readable **reference data** with a **narrow** predicate (never `USING(true)` — I-2): only
`approved`/`announced`/`on_sale`/`live` rows are anon-visible; drafts are org/platform-scoped.

### 8.1 `catalog.venue` — public-read (approved); draft org-scoped
Write RPCs: `create_venue`, `set_venue_approval` (platform).

| Role | SEL | INS | UPD | DEL | EXEC |
|---|---|---|---|---|---|
| anon | A(approved only) | D | D | D | — |
| fan | A(approved only) | D | D | D | — |
| owner | A(approved) | D | D | D | — |
| org_member | A(own-org incl. draft) | D | D | D | — |
| org_owner/admin | A(own-org incl. draft) | R | R | D | `create_venue` |
| org_finance | A(own-org) | D | D | D | — |
| venue_manager | A(own venue incl. draft) | D | R¹⁸ | D | benign venue profile edits |
| venue_door/finance/promoter | A(own venue) | D | D | D | — |
| platform_support | A(all) | D | D | D | — |
| platform_risk | A(all) | D | D | D | — |
| platform_admin | A(all) | R | R | D | `set_venue_approval` |
| service_role | A(machine) | R(def) | R(def) | D | definer |

¹⁸ operatorship (`org_id`) change is an audited RPC, not a silent overwrite (CDM §1.2).

### 8.2 `catalog.event` — public-read (announced+); draft org/venue-scoped
Write RPCs: `create_event`, `set_event_status`, `cancel_event`.

| Role | SEL | INS | UPD | DEL | EXEC |
|---|---|---|---|---|---|
| anon | A(announced+) | D | D | D | — |
| fan | A(announced+) | D | D | D | — |
| owner | A(announced+) | D | D | D | — |
| org_member | A(own-org incl. draft) | D | D | D | — |
| org_owner/admin | A(own-org) | R | R | D | `create_event`/`set_event_status`/`cancel_event` |
| org_finance | A(own-org) | D | D | D | — |
| venue_manager | A(own-venue incl. draft) | R | R | D | `create_event`/`set_event_status`/`cancel_event` |
| venue_door/finance/promoter | A(own-venue announced+) | D | D | D | — |
| platform_support | A(all) | D | D | D | — |
| platform_risk | A(all) | D | D | D | — |
| platform_admin | A(all) | R | R | D | override/cancel (audited) |
| service_role | A(machine) | R(def) | R(def) | D | definer |

### 8.3 `catalog.event_session` — public-read
Write RPC: `create_event_session` (also auto-called by `create_event` for one-night events). Toward-ref target of `kernel.tickets.event_session_id`.

| Role | SEL | INS | UPD | DEL | EXEC |
|---|---|---|---|---|---|
| anon / fan / owner | A(sessions of visible events) | D | D | D | — |
| org_member | A(own-org) | D | D | D | — |
| org_owner/admin | A | R | R | D | `create_event_session` |
| org_finance | A | D | D | D | — |
| venue_manager | A(own-venue) | R | R¹⁹ | D | `create_event_session` |
| venue_door | A(own-venue, tonight) | D | D | D | — |
| venue_finance/promoter | A(own-venue) | D | D | D | — |
| platform_support/risk | A(all) | D | D | D | — |
| platform_admin | A(all) | R | R | D | override |
| service_role | A(machine) | R(def) | R(def) | D | definer |

¹⁹ `starts_at` change on an on-sale session is a confirmed op (money-adjacent — affects door-freeze, recon #3).

### 8.4 `catalog.platform_config` — public-read (values not secret); writes platform-only, dual-control
Write RPC: `set_platform_config` (platform; dual-control seam for fee changes; AO-per-version).

| Role | SEL | INS | UPD | DEL | EXEC |
|---|---|---|---|---|---|
| anon → platform_risk (all 13 non-admin) | A(read config values) | D | D | D | — |
| platform_admin | A | R²⁰ | D | D | `set_platform_config` (new version, dual-control) |
| service_role | A(machine) | R(def) | D | D | definer |

²⁰ a config change **inserts a new `(key, version+1)` row** (AO-per-version); old versions retained; no UPDATE.

### 8.5 `catalog.resale_policy` — public-read; writes org/venue-manager + platform
Write RPC: `set_resale_policy`. Listings snapshot `policy_id`+`version` at creation.

| Role | SEL | INS | UPD | DEL | EXEC |
|---|---|---|---|---|---|
| anon / fan / owner | A(policy in force) | D | D | D | — |
| org_member | A | D | D | D | — |
| org_owner/admin | A | R | D²¹ | D | `set_resale_policy` (org events) |
| org_finance | A | D | D | D | — |
| venue_manager | A | R | D²¹ | D | `set_resale_policy` (own venue) |
| venue_door/finance/promoter | A | D | D | D | — |
| platform_support/risk | A | D | D | D | — |
| platform_admin | A | R | D²¹ | D | override |
| service_role | A(machine) | R(def) | D | D | definer |

²¹ AO-per-version (new version row, no in-place UPDATE) — same as platform_config.

---

## 9. Schema `venue` — matrices

### 9.1 `venue.ticket_type` — public-read (`public` visibility); venue-scoped otherwise; price money-consequential
Write RPCs: `create_ticket_type`, `set_ticket_type_price` (C9 live-recheck).

| Role | SEL | INS | UPD | DEL | EXEC |
|---|---|---|---|---|---|
| anon / fan / owner | A(`public` visibility only) | D | D | D | — |
| org_member | A(own-org) | D | D | D | — |
| org_owner/admin | A(own-org incl. hidden) | R | R²² | D | `create_ticket_type`/`set_ticket_type_price` |
| org_finance | A(own-org) | D | D | D | — |
| venue_manager | A(own-venue incl. hidden/door_only) | R | R²² | D | `create_ticket_type`/`set_ticket_type_price` |
| venue_door | A(door_only + public, own session) | D | D | D | — |
| venue_finance | A(own-venue) | D | D | D | — |
| promoter | A(public) | D | D | D | — |
| platform_support/risk | A(all) | D | D | D | — |
| platform_admin | A(all) | R | R | D | override |
| service_role | A(machine) | R(def) | R(def) | D | definer |

²² price/visibility write is money-consequential → live-table recheck (C9), never from JWT.

### 9.2 `venue.inventory_batch` — `remaining` public-read; counters money-custody-RPC-only
Write RPCs: `reserve_inventory`, `release_hold`, `issue_ticket_atoms`, `void_ticket_atom` (single-writer, `FOR UPDATE`).

| Role | SEL | INS | UPD | DEL | EXEC |
|---|---|---|---|---|---|
| anon / fan / owner | A(`remaining` projection²³) | R²⁴ | D | D | `reserve_inventory` (buyer hold via checkout) |
| org_member | A(remaining) | D | D | D | — |
| org_owner/admin | A(full counters, own-org) | R | R | D | `create` batch / manage capacity (audited) |
| org_finance | A(full, own-org) | D | D | D | — |
| venue_manager | A(full counters, own-venue) | R | R | D | batch/capacity RPCs |
| venue_door | A(remaining, own session) | R²⁴ | R²⁴ | D | door-sale reserve/issue path |
| venue_finance | A(full) | D | D | D | — |
| promoter | A(remaining) | D | D | D | — |
| platform_support | A(full) | D | D | D | — |
| platform_risk | A(full) | D | D | D | — |
| platform_admin | A(full) | R | R | D | capacity override (audited) |
| service_role | A(machine) | R(def) | R(def) | D | definer |

²³ **only** the computed `remaining` is world-readable; raw `capacity`/`held`/`sold` are col-scoped to venue
staff + platform. ²⁴ a buyer/door never writes counters directly — the decrement happens **inside**
`reserve_inventory`/`issue_ticket_atoms` under `FOR UPDATE` (GP-1); the cell is `R` meaning "drives via
authorized RPC."

### 9.3 `venue.inventory_batch_shard` — money-custody-RPC-only (same as batch)
Write: the reserve/issue functions (ordered shard draw, `SKIP LOCKED`).

| Role | SEL | INS | UPD | DEL | EXEC |
|---|---|---|---|---|---|
| anon / fan / owner | D²⁵ | R²⁴ | D | D | via `reserve_inventory` |
| org_owner/admin/finance | A(own-org) | D | R | D | via batch RPCs |
| venue_manager | A(own-venue) | R | R | D | via batch RPCs |
| venue_door | D²⁵ | R²⁴ | R²⁴ | D | via door reserve/issue |
| venue_finance | A | D | D | D | — |
| org_member/promoter | D | D | D | D | — |
| platform_support/risk | A | D | D | D | — |
| platform_admin | A | R | R | D | via batch RPCs |
| service_role | A(machine) | R(def) | R(def) | D | definer (ordered draw) |

²⁵ shard rows are an internal decomposition; clients read only the batch's `remaining` projection, never shard
counters.

### 9.4 `venue.inventory_movement` — money-custody-RPC-only, AO
Write: the reserve/issue/void functions (same txn as the counter move).

| Role | SEL | INS | UPD | DEL | EXEC |
|---|---|---|---|---|---|
| anon / fan / owner | D | D | D | D | — |
| org_member | D | D | D | D | — |
| org_owner/admin | V(own-org, scoped) | D | D | D | reconciliation RPC |
| org_finance | V(own-org) | D | D | D | reconciliation RPC |
| venue_manager | V(own-venue) | D | D | D | reconciliation RPC |
| venue_door/promoter | D | D | D | D | — |
| venue_finance | V(own-venue) | D | D | D | reconciliation RPC |
| platform_support | V | D | D | D | — |
| platform_risk | A | D | D | D | — |
| platform_admin | A | D²⁶ | D | D | — |
| service_role | A(machine) | R(def) | D | D | definer (AO append) |

²⁶ **AO**: written only as an in-txn side-effect of the counter functions; no direct INSERT/UPDATE/DELETE.

### 9.5 `venue.inventory_hold` — owner + venue-scoped read; counter effect RPC-only
Write RPCs: `reserve_inventory`, `release_hold`, expiry sweep. Per-user caps via advisory lock/SERIALIZABLE (never COUNT trigger, C5).

| Role | SEL | INS | UPD | DEL | EXEC |
|---|---|---|---|---|---|
| anon | D | D | D | D | — |
| fan | D | R | D | D | `reserve_inventory` (creates own hold) |
| owner (holder) | A(own holds) | R | R | D | `reserve_inventory`/`release_hold` (own) |
| org_member | D | D | D | D | — |
| org_owner/admin | A(own-org) | D | R | D | `release_hold` (venue ops) |
| org_finance | A(own-org) | D | D | D | — |
| venue_manager | A(own-venue) | R | R | D | `reserve_inventory`/`release_hold` |
| venue_door | A(own session) | R | R | D | door reserve/release |
| venue_finance/promoter | A(own-venue)/D | D | D | D | — |
| platform_support/risk | A | D | D | D | — |
| platform_admin | A | R | R | D | admin release |
| service_role | A(machine) | R(def) | R(def) | D | definer (incl. expiry sweep) |

### 9.6 `venue.inventory_unit` — EXT (C42) — DO NOT BUILD/POPULATE in MVP
money-custody-RPC-only when built (unit-rows == seats == shard mechanism). MVP: table absent or empty, deny-all.

| Role | SEL | INS | UPD | DEL | EXEC |
|---|---|---|---|---|---|
| all 14 client roles | D | D | D | D | — (not built) |
| service_role | A(machine) | R(def, future) | R(def, future) | D | Gate: reserved seating |

### 9.7 `venue.order` — owner + org-scoped; money cols RPC-only
Write RPCs: `create_order`, `issue_ticket_atoms` (on paid), refund RPCs.

| Role | SEL | INS | UPD | DEL | EXEC |
|---|---|---|---|---|---|
| anon | D | D | D | D | — |
| fan | D | R | D | D | `create_order` (own) |
| owner (buyer) | A(own order) | R | R²⁷ | D | `create_order` (own) |
| org_member | D | D | D | D | — |
| org_owner/admin | A(own-org orders) | R²⁸ | D | D | `create_order` (door/staff on behalf) |
| org_finance | A(own-org, money summary) | D | D | D | — |
| venue_manager | A(own-venue orders) | R²⁸ | D | D | `create_order` (door) |
| venue_door | A(own session orders) | R²⁸ | D | D | door `create_order` |
| venue_finance | A(own-venue) | D | D | D | — |
| promoter | D²⁹ | D | D | D | — |
| platform_support | V | R | D | D | support order actions (audited) |
| platform_risk | A(money read) | D | D | D | — |
| platform_admin | A | R | R | D | admin order ops |
| service_role | A(machine) | R(def) | R(def) | D | definer (issuance on paid) |

²⁷ buyer cannot mutate money fields; only benign pre-pay edits via RPC; state→paid is server/webhook-driven
(I-10). ²⁸ staff/door create orders `source='door'/'promoter_link'` on a buyer's behalf; buyer id server-set.
²⁹ promoter sees attribution/commission, not the order back office (CDM §8).

### 9.8 `venue.order_item` — inherits order scope; IMM after issuance
Write: `create_order` (pre-pay); frozen after issuance (guard trigger).

| Role | SEL | INS | UPD | DEL | EXEC |
|---|---|---|---|---|---|
| anon | D | D | D | D | — |
| fan | D | R | D | D | via `create_order` |
| owner (buyer) | A(own) | R | D³⁰ | D | via `create_order` |
| org_owner/admin/finance | A(own-org) | R | D³⁰ | D | via `create_order` |
| org_member | D | D | D | D | — |
| venue_manager/door | A(own-venue) | R | D³⁰ | D | via `create_order` |
| venue_finance | A(own-venue) | D | D | D | — |
| promoter | D | D | D | D | — |
| platform_support/risk | V/A | D | D | D | — |
| platform_admin | A | R | D | D | — |
| service_role | A(machine) | R(def) | D | D | definer |

³⁰ **IMM after issuance**: guard trigger blocks UPDATE/DELETE once the parent order is `paid`.

### 9.9 `venue.staff_role` — venue-scoped (C36)
Write RPCs: `grant_staff_role`, `revoke_staff_role` (`has_venue_role(venue_id,[venue_manager])` OR org_owner/admin inheritance; **no self-grant**).

| Role | SEL | INS | UPD | DEL | EXEC |
|---|---|---|---|---|---|
| anon / fan | D | D | D | D | — |
| owner (self as staff) | A(own role rows) | D | D | D | — |
| org_member | D | D | D | D | — |
| org_owner/admin | A(venues of own org) | R | R | D | `grant/revoke_staff_role` (org inheritance) |
| org_finance | D | D | D | D | — |
| venue_manager | A(own-venue roster) | R | R | D³¹ | `grant/revoke_staff_role` (own venue) |
| venue_door/finance/promoter | A(own-venue roster) | D | D | D | — |
| platform_support/risk | A | D | D | D | — |
| platform_admin | A | R | R | D | override |
| service_role | A(machine) | R(def) | R(def) | D | definer |

³¹ revoke via RPC (no client DELETE); **no self-grant** (I-11).

### 9.10 `venue.door_pin` — venue-scoped; `pin_hash` NEVER client-readable
Write RPCs: `issue_door_pin`, `revoke_door_pin`. Constant-time hash compare inside door-auth RPC (I-9).

| Role | SEL | INS | UPD | DEL | EXEC |
|---|---|---|---|---|---|
| anon / fan / owner | D | D | D | D | — |
| org_member | D | D | D | D | — |
| org_owner/admin | A³²(own-org, no hash) | R | R | D | `issue_door_pin`/`revoke_door_pin` |
| org_finance | D | D | D | D | — |
| venue_manager | A³²(own-venue, no hash) | R | R | D | `issue_door_pin`/`revoke_door_pin` |
| venue_door | A³²(own, no hash) | D | D | D | — (authenticates via the pin in the door RPC) |
| venue_finance/promoter | D | D | D | D | — |
| platform_support | A³²(no hash) | D | D | D | — |
| platform_risk | A³²(no hash) | D | D | D | — |
| platform_admin | A³²(no hash) | R | R | D | override |
| service_role | A(machine, incl. hash for compare) | R(def) | R(def) | D | definer |

³² **`pin_hash` is stripped from every client GRANT** — readable only inside the door-auth SECURITY DEFINER
RPC for constant-time comparison; never returned to any client.

### 9.11 `venue.scan_device` — venue-scoped
Write RPCs: `register_scan_device`, manifest-sync RPC.

| Role | SEL | INS | UPD | DEL | EXEC |
|---|---|---|---|---|---|
| anon / fan / owner | D | D | D | D | — |
| org_member | D | D | D | D | — |
| org_owner/admin | A(own-org) | R | R | D | `register_scan_device` |
| org_finance | D | D | D | D | — |
| venue_manager | A(own-venue) | R | R | D | `register_scan_device`/manifest-sync |
| venue_door | A(own device) | D | R³³ | D | manifest-sync (own device) |
| venue_finance/promoter | D | D | D | D | — |
| platform_support/risk | A | D | D | D | — |
| platform_admin | A | R | R | D | override |
| service_role | A(machine) | R(def) | R(def) | D | definer |

³³ door updates only its own device's `last_sync_at`/`manifest_version` via the sync RPC.

### 9.12 `venue.scan` — venue-scoped, AO (custody-adjacent admission ledger)
Write RPCs: `record_scan` (online) + door_pin path, offline-reconciliation batch RPC. C41 first-in-wins partial unique.

| Role | SEL | INS | UPD | DEL | EXEC |
|---|---|---|---|---|---|
| anon / fan | D | D | D | D | — |
| owner (ticket holder) | V³⁴ | D | D | D | own ticket's scan status via redacted history (§14.5) |
| org_member | D | D | D | D | — |
| org_owner/admin | A(own-org events) | D | D | D | — |
| org_finance | D | D | D | D | — |
| venue_manager | A(own-venue) | R | D³⁵ | D | `record_scan` / reconciliation |
| venue_door | A(own session) | R | D³⁵ | D | `record_scan` |
| venue_finance/promoter | D | D | D | D | — |
| platform_support | V | D | D | D | — |
| platform_risk | A(fraud_flag) | R | D | D | fraud-review scan actions |
| platform_admin | A | R | D | D | override |
| service_role | A(machine) | R(def) | D | D | definer (incl. offline reconciliation) |

³⁴ holder learns "scanned/admitted" only through the redacted ownership-history read, not raw scan rows.
³⁵ **AO**: every attempt recorded (incl. duplicate/invalid); no UPDATE/DELETE.

### 9.13 `venue.settlement` — org-scoped (finance); RPC-only writes
Write RPCs: `open_settlement`, `close_settlement` (→ payout, SSCAS #4).

| Role | SEL | INS | UPD | DEL | EXEC |
|---|---|---|---|---|---|
| anon / fan / owner | D | D | D | D | — |
| org_member | D | D | D | D | — |
| org_owner | A(own-org) | R | D | D | `open_settlement` |
| org_admin | A(own-org) | D | D | D | — |
| org_finance | A(own-org) | R | R³⁶ | D | `open_settlement`/`close_settlement` |
| venue_manager | A(own-venue) | R | D | D | `open_settlement` |
| venue_finance | A(own-venue) | R | R³⁶ | D | `open_settlement`/`close_settlement` |
| venue_door/promoter | D | D | D | D | — |
| platform_support | V | D | D | D | — |
| platform_risk | A(money read) | D | D | D | — |
| platform_admin | A | R | R | D | override |
| service_role | A(machine) | R(def) | R(def) | D | definer (close→payout) |

³⁶ close is state→payout under lock; header MUT, lines immutable (§9.14).

### 9.14 `venue.settlement_line` — org-scoped read, AO
Write: the settlement close engine.

| Role | SEL | INS | UPD | DEL | EXEC |
|---|---|---|---|---|---|
| anon / fan / owner | D | D | D | D | — |
| org_member | D | D | D | D | — |
| org_owner/admin | A(own-org) | D | D | D | — |
| org_finance | A(own-org) | D | D | D | — |
| venue_manager | A(own-venue) | D | D | D | — |
| venue_finance | A(own-venue) | D | D | D | — |
| venue_door/promoter | D | D | D | D | — |
| platform_support | V | D | D | D | — |
| platform_risk | A | D | D | D | — |
| platform_admin | A | D³⁷ | D | D | — |
| service_role | A(machine) | R(def) | D | D | definer (AO) |

³⁷ **AO**: written only by the close engine in-txn.

### 9.15 `venue.comp_allocation` — venue-scoped; money-adjacent (live-recheck)
Write RPCs: `allocate_comp`, `issue_comp` (→ `issue_ticket_atoms` cause `comp`; draws real capacity, A4).

| Role | SEL | INS | UPD | DEL | EXEC |
|---|---|---|---|---|---|
| anon / fan | D | D | D | D | — |
| owner (comp recipient) | V(own comp) | D | D | D | — |
| org_member | D | D | D | D | — |
| org_owner/admin | A(own-org) | R | R | D | `allocate_comp`/`issue_comp` |
| org_finance | A(own-org) | D | D | D | — |
| venue_manager | A(own-venue) | R | R | D | `allocate_comp`/`issue_comp` (audited, step-up seam C39) |
| venue_door | A(own session) | D | D | D | — |
| venue_finance/promoter | A(own-venue)/D | D | D | D | — |
| platform_support/risk | V/A | D | D | D | — |
| platform_admin | A | R | R | D | override |
| service_role | A(machine) | R(def) | R(def) | D | definer |

### 9.16 `venue.guest_list` / `venue.guest_entry` — venue-scoped
Write RPCs: guest-list CRUD RPCs; conversion to admission via the named hold function only (A4/A11). `guest_entry` cascades from `guest_list` (via RPC).

| Role | SEL | INS | UPD | DEL | EXEC |
|---|---|---|---|---|---|
| anon / fan / owner | D | D | D | D | — |
| org_member | D | D | D | D | — |
| org_owner/admin | A(own-org) | R | R | D³⁸ | guest-list RPCs |
| org_finance | D | D | D | D | — |
| venue_manager | A(own-venue) | R | R | D³⁸ | guest-list RPCs |
| venue_door | A(own session, check-in) | D | R³⁹ | D | check-in RPC (`status→arrived`) |
| venue_finance/promoter | D | D | D | D | — |
| platform_support/risk | A/V | D | D | D | — |
| platform_admin | A | R | R | D | override |
| service_role | A(machine) | R(def) | R(def) | D | definer |

³⁸ `guest_entry` rows are removed only via the parent guest-list RPC cascade, never client DELETE (GP-2).
³⁹ door updates only `status`/`checked_in_at` on entries for its session.

### 9.17 `venue.promoter` / `venue.promoter_link` / `venue.attribution` (Phase 2D)
Write RPCs: promoter CRUD; attribution recorded in-txn by `create_order` (AO). `promoter_link.slug` globally unique; link IMM.

**`venue.promoter`** and **`venue.promoter_link`** (venue/org-scoped; promoter reads OWN):

| Role | SEL | INS | UPD | DEL | EXEC |
|---|---|---|---|---|---|
| anon / fan / owner | D | D | D | D | — |
| org_member | D | D | D | D | — |
| org_owner/admin | A(own-org) | R | R | D | manage promoters/links |
| org_finance | A(own-org) | D | D | D | — |
| venue_manager | A(own-venue) | R | R | D | manage promoters/links |
| venue_finance | A(own-venue) | D | D | D | — |
| venue_door | D | D | D | D | — |
| promoter | A(**own** promoter row + own links only⁴⁰) | D | D | D | — |
| platform_support/risk | A | D | D | D | — |
| platform_admin | A | R | R | D | override |
| service_role | A(machine) | R(def) | R(def) | D | definer |

**`venue.attribution`** (AO; promoter reads OWN credit only):

| Role | SEL | INS | UPD | DEL | EXEC |
|---|---|---|---|---|---|
| anon / fan / owner | D | D | D | D | — |
| org_owner/admin | A(own-org) | D | D | D | — |
| org_finance | A(own-org) | D | D | D | — |
| venue_manager/finance | A(own-venue) | D | D | D | — |
| org_member/venue_door | D | D | D | D | — |
| promoter | A(**own** attributions⁴⁰) | D | D | D | — |
| platform_support | V | D | D | D | — |
| platform_risk | A | D | D | D | — |
| platform_admin | A | D⁴¹ | D | D | — |
| service_role | A(machine) | R(def) | D | D | definer (recorded in `create_order`) |

⁴⁰ promoter isolation (CDM §8): sees own links/attributions/`promoter_commission` payout only — never the org
back office, other promoters, or buyer PII. ⁴¹ **AO**: attribution recorded once, in-txn with the order.

---

## 10. Schema `market` — matrices (native rail)

### 10.1 `market.listing_native` — public-read (active discovery) + owner-scoped (seller)
Write RPCs: `create_listing` (native), `cancel_listing`. Creating sets atom `resale_state='listed'` (SSCAS #6).

| Role | SEL | INS | UPD | DEL | EXEC |
|---|---|---|---|---|---|
| anon | A(active listings, discovery cols⁴²) | D | D | D | — |
| fan | A(active) | D | D | D | — |
| owner (seller) | A(own listing full) | R⁴³ | R | D | `create_listing`/`cancel_listing` (own atom) |
| org_member | A(active) | D | D | D | — |
| org_owner/admin | A(active + own-venue events) | D | D | D | — |
| org_finance | A(active) | D | D | D | — |
| venue_manager | A(own-venue listings) | D | D | D | — |
| venue_door/finance/promoter | A(active) | D | D | D | — |
| platform_support | A | D | R | D | `cancel_listing` (support, audited) |
| platform_risk | A | D | R | D | freeze/cancel (fraud) |
| platform_admin | A | R | R | D | override |
| service_role | A(machine) | R(def) | R(def) | D | definer |

⁴² discovery cols only (id, rail, event/session, price, seller display, status, cover); seller PII / idem key
col-scoped. ⁴³ seller must own the atom (`kernel.tickets.current_owner_id = auth.uid()`), atom not
`locked`/terminal; enforced under lock in the create RPC.

### 10.2 `market.auction` — public-read; writes RPC-only
Write RPCs: `create_auction`, bid RPC, finalize sweep. (Bids on external `public.bids` where mirrored — CONFLICTS #6.)

| Role | SEL | INS | UPD | DEL | EXEC |
|---|---|---|---|---|---|
| anon | A(active auction, public fields) | D | D | D | — |
| fan | A | D | D | D | — |
| owner (seller of listing) | A(own auction full) | R⁴⁴ | R | D | `create_auction` (own listing) |
| bidder (any authenticated) | A | R⁴⁵ | D | D | bid RPC (via external engine) |
| org roles | A | D | D | D | — |
| venue roles / promoter | A | D | D | D | — |
| platform_support | A | D | R | D | cancel (audited) |
| platform_risk | A | D | R | D | fraud freeze/cancel |
| platform_admin | A | R | R | D | override |
| service_role | A(machine) | R(def) | R(def) | D | definer (finalize sweep) |

⁴⁴ only the listing seller creates its auction. ⁴⁵ bids drive `current_highest_bid_minor` (derived head) via
the bid RPC; the auction row itself is not client-writable.

### 10.3 `market.offer` — owner-scoped (buyer + listing seller)
Write RPCs: `make_offer`, `respond_offer`.

| Role | SEL | INS | UPD | DEL | EXEC |
|---|---|---|---|---|---|
| anon | D | D | D | D | — |
| fan (as buyer) | A(own offers) | R | R⁴⁶ | D | `make_offer` (own) |
| owner (listing seller) | A(offers on own listing) | D | R⁴⁷ | D | `respond_offer` (own listing) |
| org roles | D | D | D | D | — |
| venue roles / promoter | D | D | D | D | — |
| platform_support | V | D | D | D | — |
| platform_risk | A | D | R | D | fraud action |
| platform_admin | A | R | R | D | override |
| service_role | A(machine) | R(def) | R(def) | D | definer |

⁴⁶ buyer may withdraw own pending offer. ⁴⁷ seller accepts/declines (accept→`market_sale` via kernel engine).

### 10.4 `market.market_sale` — money-custody-RPC-only (buyer+seller read); C26 terminal SM
Write: `transfer_ticket_ownership` (via market, SSCAS #2) + C25 auto-compensation sweep. Buyer id **server-verified** (C35).

| Role | SEL | INS | UPD | DEL | EXEC |
|---|---|---|---|---|---|
| anon | D | D | D | D | — |
| fan | D | D | D | D | — |
| owner (buyer or seller) | V⁴⁸ | R⁴⁹ | D | D | drives via checkout/`accept_offer`; reads own sale status (§14.2) |
| org_member | D | D | D | D | — |
| org_owner/admin | D | D | D | D | — |
| org_finance | V(own-venue royalty) | D | D | D | royalty reconciliation |
| venue_manager | V(own-venue) | D | D | D | — |
| venue_finance | V(own-venue royalty) | D | D | D | — |
| venue_door/promoter | D | D | D | D | — |
| platform_support | V | D | D | D | — |
| platform_risk | A(money read) | D | R | D | dispute resolution (SSCAS #8) |
| platform_admin | A | R | R | D | override |
| service_role | A(machine) | R(def) | R(def) | D | definer (transfer engine + C25 sweep) |

⁴⁸ buyer/seller read own sale via `market.get_market_sale_status` (state pending|completed|compensated, **no
cause-codes** — recon #2, §14.2); fee split/counterpart PII col-scoped. ⁴⁹ the sale row is written only inside
the kernel transfer engine; the buyer "drives" it by completing native checkout, buyer id server-verified
against `public.payments`.

### 10.5 `market.p2p_transfer` — owner-scoped (from + to); custody effect RPC-only
Write RPCs: `create_p2p_transfer`, `accept_p2p_transfer` (→ kernel engine), expiry/unlock sweep. Distinct from external `public.transfers`.

| Role | SEL | INS | UPD | DEL | EXEC |
|---|---|---|---|---|---|
| anon | D | D | D | D | — |
| fan (as recipient) | A(transfers to me⁵⁰) | R | R | D | `accept_p2p_transfer` |
| owner (sender `from_identity`) | A(own sent) | R | R | D | `create_p2p_transfer`/cancel |
| org roles | D | D | D | D | — |
| venue roles / promoter | D | D | D | D | — |
| platform_support | V | D | D | D | — |
| platform_risk | A | D | R | D | fraud freeze |
| platform_admin | A | R | R | D | override |
| service_role | A(machine) | R(def) | R(def) | D | definer (incl. expiry/unlock sweep → `expired`) |

⁵⁰ recipient resolved by handle/phone → `to_identity`; before resolution, only the sender sees the pending
transfer. Start sets atom `resale_state='locked'` (SSCAS #7); accept appends `p2p_transfer` + credential bump
(SSCAS #8).

### 10.6 `market.listing_unified` — the bridge VIEW (public-read; inherits underlying policies)
No writes (it is a view). See §14.1 bridge safety.

| Role | SEL | INS | UPD | DEL | EXEC |
|---|---|---|---|---|---|
| anon | A(discovery⁵¹) | D | D | D | — |
| fan / owner | A(discovery) | D | D | D | — |
| all org roles | A(discovery) | D | D | D | — |
| all venue roles / promoter | A(discovery) | D | D | D | — |
| platform_support/risk/admin | A(discovery) | D | D | D | — |
| service_role | A(machine) | D | D | D | — |

⁵¹ the view unions `public.listings` (external) + `market.listing_native` (native) and **inherits each side's
public-read discovery policy** — an active native listing is visible exactly where its base table's policy
allows; a draft/cancelled listing never surfaces. No new authority is created by the view (§14.1).

---

## 11. EXECUTE-via-RPC authority — consolidated (who may invoke each write RPC)

The prompt's fifth operation (`EXECUTE-via-RPC-only`) rolled up. Every RPC is `postgres`-owned SECURITY
DEFINER, `search_path` pinned, `REVOKE EXECUTE FROM anon,authenticated,public` then GRANT EXECUTE only to
`authenticated` **with an in-body predicate re-check** (the GRANT lets the call in; the predicate decides
authority — a demoted user's call fails inside the function via live-table recheck). `svc` = the definer path.

| RPC | May invoke (predicate, live-rechecked) |
|---|---|
| `kernel.upsert_identity_ext` | owner (benign) · `is_platform([platform_admin])` (region/kyc) |
| `kernel.create_organization` | any `authenticated` (applicant) |
| `kernel.set_org_status` | `is_platform([platform_admin])` |
| `kernel.set_org_payout_destination` | `has_org_role([org_owner])` (dual-control) |
| `kernel.grant_org_role`/`revoke_org_role` | `has_org_role([org_owner,org_admin])`; no self-grant; keep ≥1 owner |
| `kernel.grant_platform_role`/`revoke_platform_role` | `is_platform([platform_admin])` + `public.admin_users` bootstrap; dual-control |
| `kernel.issue_ticket_atoms` | `svc`/definer (called by paid-order flow); actor = `auth.uid()` server-derived |
| `kernel.transfer_ticket_ownership` | `svc`/definer (market/venue checkout); buyer **server-verified** vs `public.payments` (C35) |
| `kernel.void_ticket_atom` | `is_platform([platform_admin,platform_risk])` · refund flow (definer) |
| `kernel.refund_primary_order` | owner(buyer-request, capped) · `has_org_role([org_finance])` · `is_platform([platform_support,platform_admin])` |
| `kernel.admin_refund` | `is_platform([platform_risk,platform_admin])` |
| `kernel.close_settlement` | `has_org_role([org_finance])` · `has_venue_role([venue_finance])` · platform |
| `kernel.pay_promoter_commission` | definer (settlement path) |
| `kernel.provision/rotate/revoke_signing_key` | `is_platform([platform_admin])` |
| `catalog.create_venue` | `has_org_role([org_owner,org_admin])` |
| `catalog.set_venue_approval` | `is_platform([platform_admin])` |
| `catalog.create_event`/`set_event_status`/`cancel_event` | `has_org_role([org_owner,org_admin])` OR `has_venue_role([venue_manager])` |
| `catalog.create_event_session` | as create_event |
| `catalog.set_platform_config` | `is_platform([platform_admin])` (dual-control) |
| `catalog.set_resale_policy` | `has_org_role([org_owner,org_admin])` OR `has_venue_role([venue_manager])` · platform |
| `venue.create_ticket_type`/`set_ticket_type_price` | `has_venue_role([venue_manager])` OR org_owner/admin (live-recheck, C9) |
| `venue.reserve_inventory`/`release_hold` | any `authenticated` (own hold) · `has_venue_role([venue_manager,venue_door])` |
| `venue.create_order` | any `authenticated` (own) · door/staff on-behalf (`has_venue_role([venue_door,venue_manager])`) |
| `venue.grant_staff_role`/`revoke_staff_role` | `has_venue_role([venue_manager])` OR org_owner/admin inheritance; no self-grant |
| `venue.issue_door_pin`/`revoke_door_pin` | `has_venue_role([venue_manager])` OR org_owner/admin |
| `venue.register_scan_device` / manifest-sync | `has_venue_role([venue_manager])`; sync also `venue_door` (own device) |
| `venue.record_scan` | `has_venue_role([venue_door,venue_manager])` OR valid `door_pin` device principal |
| `venue.open_settlement`/`close_settlement` | `has_venue_role([venue_finance])` OR `has_org_role([org_finance])` · platform |
| `venue.allocate_comp`/`issue_comp` | `has_venue_role([venue_manager])` OR org_owner/admin (step-up seam C39) |
| `venue.record_offline_scans` | `has_venue_role([venue_door,venue_manager])` |
| `market.create_listing`/`cancel_listing` | owner of the atom · platform (cancel) |
| `market.create_auction` / bid RPC | listing seller (create) · any `authenticated` (bid) |
| `market.make_offer`/`respond_offer` | any `authenticated` (offer) · listing seller (respond) |
| `market.create_p2p_transfer`/`accept_p2p_transfer` | atom owner (create) · resolved recipient (accept) |
| **read RPCs** `get_ticket_custody_chain` · `get_ticket_history` · `get_market_sale_status` | scoped as §14 |

---

## 12. Bridge safety — `market.listing_unified` + native/kernel isolation (§14.1 detail below)

Summarized in §14.1; the rule: the bridge view creates **no new authority**, and native objects never expose
raw `kernel.ticket_ownership_log` to clients (redacted read only).

---

## 13. Existing `public.*` boundary (unchanged)

Phase-2 policies never widen or alter `public.*` RLS. `kernel.payment_native` and `market.market_sale` **link**
to `public.payments` (money-in) but never grant clients write on it; `stripe-webhook` keeps `verify_jwt=false`
(I-10); `public.listings`/`public.bids`/`public.transfers` retain their existing external-rail policies and are
only **read** through the bridge view. `kernel.platform_role` extends (does not replace) `public.admin_users`.

---

## 14. Reconciliation-target consumption (RECON_TARGETS_FROM_RN.md #1–#5)

### 14.1 Bridge safety (view RLS) — feeds #5's isolation rule
`market.listing_unified` is a **read-only view** unioning `public.listings` + `market.listing_native`. Its RLS
posture: **it inherits the row-visibility of its base tables** — Postgres evaluates the underlying tables'
policies for the querying role, so a native listing appears only when `market.listing_native`'s public-read
predicate (`status='active'`) admits it, and an external listing only per `public.listings`' existing policy.
The view is **security_invoker** (evaluates with the caller's privileges, not the definer's) so it cannot
launder authority. It exposes **only** the common discovery column set (id, rail discriminator, event/session,
price, seller display, status, cover) — no money/custody/PII columns, no cross-rail join that would reveal a
seller's other holdings. Checkout **routes by rail** (native → `kernel.transfer_ticket_ownership`; external →
existing path); the view itself performs no writes and **no native object mutates any `public.*` money/custody
row except by linking to a `public.payments` id** (SPEC_FOUNDATION §7).

### 14.2 `paid_pending_transfer` pollable status (#2)
Buyer/seller poll `market.get_market_sale_status(sale_id)` — a scoped read RPC returning **only**
`market.market_sale.terminal_state` (pending|completed|compensated) and `sale_state`
(initiated|paid_pending_transfer|settled), owner-scoped (`buyer_id`/`seller_id` = `auth.uid()`). It **hides
cause-codes** and internal fields, so the RN "Finalizing…" → success/compensated-refund flip needs no raw
table access. The C25 sweep drives the terminal transition (definer). SLO: named in the RPC/edge spec (bounded
dwell); RLS's job is only that the read is owner-scoped and cause-code-free.

### 14.3 Door-freeze signal (#3) — **ADDENDUM A2/A3 CLOSED**
Transfer/Sell must disable once the offline door manifest opens (C6/C43, per-open-manifest-ticket scope).
**Canonical form (RECONCILED — schema §2.3, migration 073):** the stored signal is
`catalog.event_session.door_open_at`; the ONLY authorization read is the derived helper
`kernel.is_transfer_frozen(ticket_atom_id)` — there is **no stored `kernel.tickets.transfer_frozen` column**.
RLS consequence: `market.create_listing`, `market.create_p2p_transfer`, `kernel.lock_ticket`, and
`kernel.mark_ticket_scanned` re-check the helper **under the atom lock** and reject with `frozen`. This is a
live-table recheck (I-5), never a client-trusted flag. The RN client reads the same helper (owner-scoped
boolean via the ticket read) to disable the buttons; the edge layer never independently decides freeze.

### 14.4 Credential offline behavior (#4)
The `credential-sign` edge fn returns a cacheable signed token + `credential_version`. RLS/read consequence:
clients read `kernel.tickets.credential_version` (own atom, owner-scoped) and `kernel.signing_key.public_key`
(world-readable manifest, §7.7) to verify/invalidate; a transfer bumps `credential_version` (invalidating the
cached token). Online doors do a live per-scan verify (C37). No private key is ever DB-readable (C33).

### 14.5 Redacted ownership-history read (#5) — THE custody isolation rule
**RLS denies all clients raw `kernel.ticket_ownership_log` rows** (§7.6: deny-all, `REVOKE ALL`). Owner-facing
history is served **only** by `market.get_ticket_history(ticket_atom_id)` — an owner-scoped SECURITY DEFINER
read RPC that:
- verifies `auth.uid()` is the atom's **current** owner (live `kernel.tickets.current_owner_id`);
- returns **plain verbs** (bought · transferred · scanned · listed) mapped from the log's `cause` — **hiding
  the raw cause-codes** (`market_sale`/`refund_void`/`admin_action`/…) and internal fields
  (`command_idempotency_key`, `credential_version_after`, `state_transition`);
- **redacts prior-owner PII** — no `from_identity`/`to_identity` uuids or names of other people; a prior hop
  reads as "transferred to you"/"you transferred", never identifying the counterpart.

Deeper reads escalate by role, NOT to the raw table for clients:
- **owner** → redacted verbs only (above).
- **issuing venue_manager / org_owner-admin** → `kernel.get_ticket_custody_chain` scoped to own-event atoms,
  counterpart PII still redacted.
- **platform_risk / platform_admin** → full chain (fraud/dispute/audit) via `is_platform` RPC.

This is the single place custody history crosses to a client, and it never leaks cause internals or third-party
PII. It satisfies recon #5 and the SPEC_FOUNDATION §7 "native objects never expose raw
`kernel.ticket_ownership_log` to clients" rule.

### 14.6 Native p2p `expired`/`failed` states (#1)
`market.p2p_transfer.status` includes `expired` (driven by the expiry/unlock sweep, definer) and folds
`failed`→`cancelled` with a reason code. RLS consequence: the sweep writes `expired` via the definer path
(§10.5); the recipient/sender read their own transfer's status owner-scoped; no client writes the terminal
state. No new role authority is needed.

---

## 15. RECONCILIATION — flagged for Wave-2 resolution

Tables/decisions whose correct policy could not be fully determined from the schema spec, or where this spec
made a least-privilege choice the schema spec left generic:

0. **Canonical RPC names (addendum A4 — CLOSED).** Where this spec writes `reserve_inventory` /
   `release_hold` / `create_order`, the **canonical contract names** are `venue.reserve_primary_inventory`
   (buyer hold) / `venue.release_inventory_hold` / `venue.create_primary_checkout`, plus the distinct
   **`venue.create_inventory_hold`** (staff/comp/promoter hold — venue_manager/org authority, never fans; its
   EXEC cells mirror the manager rows of §inventory_hold). The short names are documented physical aliases
   (spec-review §2.1 registry); authority cells are identical under either name.
1. **Platform sub-role split (support vs risk vs admin).** The schema spec states read authority as
   generic `is_platform`/"platform" for most tables. This spec assigns least-privilege sub-roles
   (support = ops `V`, risk = money/fraud read `A`, admin = full `A`/audit). **Confirm the exact
   platform-sub-role read boundary** (esp. whether `platform_support` may read money summaries at all, and
   whether `platform_risk` may read `kernel.admin_audit` fully). Flagged: this is a real authorization choice
   the schema spec delegated.
2. **CLOSED (addenda A2/A3).** Door-freeze canonical form = `catalog.event_session.door_open_at` (schema §2.3,
   migration 073) + the `kernel.is_transfer_frozen(atom_id)` helper as the ONLY authorization read (§14.3
   updated). No stored `transfer_frozen` column; client read and create-RPC recheck target the same helper.
3. **`org_finance` vs `venue_finance` for settlement close.** Both appear plausible as the `close_settlement`
   authority; §11 lists both. Confirm whether settlement close is an org-level or venue-level finance action
   (or both), since it drives payout (money-consequential).
4. **`platform_support`-initiated refund cap.** §7.10 grants support a capped `refund_primary_order`; the
   schema spec names `admin_refund` for platform but is silent on a support tier. Confirm the support refund
   ceiling / whether support may refund at all vs escalate to risk/admin.
5. **`resale_state` on `kernel.tickets` (CONFLICTS #2 / R34).** The atom carries a market fact (`listed`/
   `locked`); the scan/transfer guards need it regardless of physical home, and its read is covered by the
   owner-scoped tickets policy. Flagged only because the schema spec itself flags the dependency-smell for the
   ratification pass — RLS treats it as an owner-readable atom column today.
6. **`market.auction` bid storage (CONFLICTS #6).** MVP reuses the external `public.bids` engine; if a native
   `market.bid` ledger is later added, it needs its own matrix (owner-scoped bidder read, RPC-only write). Not
   built in MVP; noted so it is not forgotten.

Everything else has a determinate policy from the schema spec's stated read/write authority + the Phase-0
class defaults (§4).

---

*End of docs/architecture/PHASE_2_RLS_PERMISSION_SPEC.md. Design-only; no SQL. Companion to the physical schema spec
(deliverable #1) and the RPC contracts (deliverable #4), per SPEC_FOUNDATION §10.*
