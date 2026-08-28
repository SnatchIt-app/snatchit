# Snatch It — Phase 2 Venue Dashboard Product Spec (UI/UX, build-ready)

**Design-only.** Information architecture, surfaces, states, permissions, and reads. No component code, no JSX, no SQL, no styling code. Another engineer must be able to build every surface in this file without inventing a product decision.

**Binding inputs (authoritative; `docs/architecture/_superseded/` is NOT):**
`docs/architecture/SNATCH_IT_DOMAIN_ARCHITECTURE.md` (venue-ops depth §5/Part 1, roles Part 7, admin plane Part 12) ·
`docs/architecture/PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md` (the `kernel.*` / `catalog.*` / `venue.*` objects this UI sits over) ·
`docs/architecture/PHASE_2_RLS_PERMISSION_SPEC.md` (**§9.x is the binding role matrix — nothing in this file may contradict it**) ·
`docs/architecture/PHASE_2_RPC_FUNCTION_CONTRACTS.md` (the only write paths) ·
`docs/architecture/PHASE_2_REACT_NATIVE_PRODUCT_SPEC.md` (companion consumer/scanner spec; house style, §2 surface split, §8 admin boundary) ·
`docs/architecture/PHASE_2_SPEC_FOUNDATION.md` (§4 Gate-P decisions, §6 table inventory, §8 Phase-0 invariants).

Companion deliverables: schema (1), migration (2), RLS (3), RPC (4), edge (5), RN product (6), **this file (8 — venue dashboard)**.

**Plus the eight Phase-2 delta specs** — door lifecycle, money authority, role model, demographics/privacy, promoter codes, notifications, CRM export, Apple Wallet — integrated as of the consolidation. **The role-model spec is now co-binding with RLS §9.x on labels and capabilities.** Migration packages are `076`–`091` per `docs/architecture/PHASE_2_PACKAGE_REGISTRY.md`; `071`–`075` are applied production security migrations and are **not** Phase-2 packages.

Citations in this file use the short forms **schema §x**, **RLS §x**, **RPC §x**, **domain §x**, **RN §x**, **foundation §x**.

> ### What the integration changed in this file — read before diffing
>
> **This spec was reconciled, not rewritten.** Its structure, its 49-row role matrix, its copy and its judgements are the owner-approved originals except where a ratified ruling or a delta spec required otherwise. The substantive changes:
>
> | Where | Change | Driven by |
> |---|---|---|
> | §5, §15.2, throughout | `venue_door` → **`venue_scanner`**; **`venue_promoter` removed**; four new labels amended in at §5.1 | ratified **O-2** |
> | §5.2 | Corrected money rows (5, 36, 40, 41, 47) + two new surfaces | ruling **O-1**, **O-3** |
> | **§9.1** | Attendee roster becomes **holder-keyed** — it was purchaser-keyed, so a six-ticket order showed one name and omitted the five people who actually walk through the door | CRM **K-1** |
> | §9.5 | Holder count **pinned** to the demographics card's denominator | CRM K-1 / demographics §4.1 |
> | §9.6 | Export allow/deny lists corrected for the marketing roles; platform reads but does not extract | CRM **K-2**, **K-3** |
> | §12.4 | Manifest open/close is now **operable**, freeze scope stated as **session-wide**, door principal **excluded** | **Δ1 closed**, **O-4** |
> | §13.3–§13.7 | Refund authority corrected; tier disclosure; parked-refund and already-scanned consequences; approval queue | ruling **O-1**, money §10.1 |
> | §14.5, §16.9 | Payout probation state; step-up re-auth surface | money §8.3, §8.4 |
> | §22 | **Six of nine collisions resolved**; seven new items raised | the rulings |
> | **§20A** | **NEW — every control mapped to a named backend capability, with ten flagged as unbacked** | the owner's binding rule |
>
> §22.2's *"Needs a ruling"* and §22.7's declined door-authority decision — the two questions this spec deliberately refused to answer alone — **are both now answered**, and §22 records which way each went and why.

---

## 0. Scope, honesty, and what actually exists today

### 0.1 Production reality (state this before anyone builds)

Every `kernel.*`, `catalog.*`, `venue.*`, and `market.*` object referenced in this file is **specification-only**. Production today runs the frozen Phase-0 system: **27 `public.*` tables** (`admin_users`, `ambassador_applications`, `auth_audit_sweep_state`, `bids`, `dispute_resolutions`, `disputes`, `investor_leads`, `listings`, `notification_preferences`, `notifications`, `payments`, `payout_decisions`, `payout_policy`, `profiles`, `push_tokens`, `rate_limits`, `reports`, `saved_listings`, `seller_flags`, `seller_risk_scores`, `stripe_connect_archive`, `stripe_webhook_events`, `transfer_notifications`, `transfers`, `user_blocks`, `venue_partnership_inquiries`, `webhook_retries` — verified by enumerating `CREATE TABLE` across `supabase/migrations/` on this branch). There is **no venue schema in production**, no `catalog.event`, no `venue.order`. This dashboard cannot be built against production; it is built against Phase-2 migrations `076–091` (foundation §3, migration plan; canonical map in `docs/architecture/PHASE_2_PACKAGE_REGISTRY.md`).

Consequence for planning: **nothing in this file is a "wire up the existing tables" task.** Every surface here is gated on its migration package landing first.

### 0.2 MVP scope (honest — do not exceed)

Miami-only, approved venues only. `venue.ticket_type.kind` is **`admission` | `table` only** (schema §3.1, C11) — no bundles, no add-ons, no tier-ladder object, no seat maps (C42 is backend-only). **No re-entry** (C41). No multi-currency. No analytics platform: this dashboard reports **operational counters the venue needs tonight**, not cohorts, funnels, conversion rates, retention, or forecasts. Where a Phase-3 capability would be expected and is absent, the surface says so plainly rather than shipping a hollow chart.

### 0.3 Evidence discipline used throughout

- A table, column, RPC, enum value, or role is named **only** where a binding input contains it, with the citation.
- **`INFERENCE:`** marks a product conclusion I drew from the specs but that no spec states.
- **`UNVERIFIED:`** marks something a sibling architect (A–D) asked for that is **not** in the frozen specs — it is their delta, not mine, and I do not claim it exists.
- Anything the dashboard needs that no one has requested appears **only** in §21 (delta request), never asserted as existing.

---

## 1. Operator product language

The venue dashboard is **operational software for professionals**, so — unlike the consumer app (RN §0) — operators legitimately see domain nouns: *event*, *session*, *ticket type*, *inventory batch*, *hold*, *order*, *settlement*, *payout*, *comp*, *guest list*, *scan*. Precision here prevents door mistakes.

**Still forbidden in every operator label, tooltip, toast, empty state, and error** (architecture leakage, foundation §9):
**kernel · catalog · rail · ticket atom · atom · SSCAS · credential_version · resale_state · market_sale · ownership log · cause-code · shard · RLS · definer.**

| Backend object (internal) | Operator-facing word |
|---|---|
| `kernel.organization` | **Organization** |
| `catalog.venue` | **Venue** |
| `catalog.event` | **Event** |
| `catalog.event_session` | **Session** (a one-night event shows one session as its date, not as a second noun) |
| `venue.ticket_type` | **Ticket type** |
| `venue.inventory_batch` | **Inventory** / a named **release** (Public sale · Promoter hold · Comps · Door · Presale) |
| `venue.inventory_batch_shard` | *(never shown — internal decomposition, RLS §9.3 note 25)* |
| `venue.inventory_hold` | **Hold** |
| `venue.order` / `order_item` | **Order** / **Order line** |
| `kernel.tickets` | **Ticket** (never "atom") |
| `kernel.tickets.state = voided` | **Voided** (never "refunded" — D2: the ticket has no refunded terminal) |
| `venue.scan` | **Scan** / **Check-in** |
| `catalog.event_session.door_open_at` | **Door manifest open** (and its consequence: "Transfers closed") |
| `venue.settlement` / `settlement_line` | **Settlement** / **Settlement line** |
| `kernel.payout` | **Payout** |
| `venue.promoter_link` | **Promoter link** |
| promoter code (Agent C) | **Promoter code** |
| `venue.comp_allocation` | **Comp** |
| `kernel.admin_audit` | *(never shown as such — see §17)* |

**Rule:** every surface below names its backend object for the engineer; that name must not reach rendered copy except where the table above maps it.

---

## 2. Design principles

1. **The dashboard is a client of the RPC surface, never of the tables' write side.** GP-1 (RLS §1.3) makes direct client `INSERT`/`UPDATE`/`DELETE` deny-everywhere on every Phase-2 table. Every button in this file resolves to exactly one named RPC. If a surface has no RPC, it is read-only or it is in §21.
2. **Authority is re-checked at the action, not at render.** A hidden button is a courtesy; the RPC's in-body live-table predicate re-check is the security (RLS §2.2, §11; RPC §0.1). The UI never sends a role or an org id it "knows"; it sends the scope id and lets the server decide. A demoted user's still-open tab fails at the click, and the UI renders that as a permission-denied state, not as a crash.
3. **Cross-organization access is impossible by construction** (§4.4). There is no route, no read, and no aggregate anywhere in this IA that spans organizations.
4. **Never show a number the venue will mistake for money it is owed.** Home shows *gross*; only Settlement shows *net*. Every gross figure carries the disclaimer inline, not in a tooltip.
5. **Capacity truth is one number, computed.** `remaining = capacity − held − sold` (schema §3.2, C27). The dashboard never offers an editable "remaining" field and never displays a second, differently-derived availability number anywhere.
6. **Free is not free.** Comps and guest-list conversions draw real capacity from a real `comp` batch (domain §1.6, A4). Any comp surface that could imply otherwise is wrong.
7. **Destructive and money actions state their blast radius before confirming.** Cancel event, refund, close settlement, open the door manifest, revoke a PIN — each shows what it will do, in counts, before the confirm is enabled.
8. **The door is a different job.** Door surfaces are large-target, high-contrast, one-decision-per-screen, and usable one-handed on a phone at 1 a.m. Back-office surfaces are dense and keyboard-driven. They do not share a layout system beyond tokens.
9. **The dashboard does not go offline.** It is an online back-office surface that *reports* device offline state. Offline-first belongs to the scanner (RN §7). No surface here caches a write.
10. **Honest absence.** Where MVP lacks a capability an operator expects (scheduled on-sale, tier ladders, per-type purchase limits, table-spend tracking, bot defense), the surface says what MVP does instead. No disabled control that implies a coming feature without labeling it.

---

## 3. Platform decision and responsiveness contract

### 3.1 Surface split (adopted from RN §2, unchanged)

| Surface | Platform | Owner spec |
|---|---|---|
| Consumer (discovery, checkout, wallet, transfer) | React Native | RN spec §3–§6 |
| **Venue dashboard** (this file) | **Web, desktop-first** | this file |
| Door scanning | Dedicated mobile scanner mode | RN spec §7 |
| Platform internal admin | Separate internal plane | RN spec §8 |

**The venue dashboard is NOT duplicated inside the consumer React Native app.** No venue surface ships in the fan binary. A venue manager who is also a fan uses two products with one identity (domain §8.3).

### 3.2 Breakpoints

| Token | Width | Intent |
|---|---|---|
| `xl` | ≥ 1280 | Primary target. Persistent left nav, multi-column, dense tables, keyboard shortcuts. |
| `lg` | 1024–1279 | Nav collapses to icons; tables drop the least-load-bearing columns; side panels become drawers. |
| `md` | 768–1023 | Tablet. Nav becomes a top drawer. The **five mobile-critical surfaces** (§3.3) are fully functional; every other surface is **read-only** with an "Open on a larger screen to edit" banner. |
| `sm` | < 768 | Phone web. Only the five mobile-critical surfaces render as first-class. All others render a summary card plus the same banner. |

**Rule:** below `md`, no surface that can move money, change capacity, change price, change roles, or cancel an event is editable. Those are `lg`+ only. This is a deliberate blast-radius decision, not a layout limitation. `INFERENCE:` no spec mandates this; it follows from principle 7 plus the fact that every one of those actions is money-consequential or custody-consequential.

### 3.3 The five surfaces that must be genuinely usable on tablet and phone

These five are worked at the door, on the floor, or on the way to the venue. Each specifies what changes per breakpoint.

**1. Attendees (§9)**
- `xl`: full table — name · ticket type · qty · order status · check-in · source · promoter · refund state · order ref. Filter rail pinned left. Row click opens a right drawer.
- `lg`: drops `order ref` and `source` into the drawer. Filter rail collapses to a filter button with a count badge.
- `md`: table becomes a **card list**: line 1 name + check-in pill, line 2 ticket type · qty, line 3 order status · refund state. Search is the primary control and is sticky at the top. Filters in a bottom sheet, same closed enumerated set (Agent B).
- `sm`: same card list, single column, 56px minimum row height, search sticky. **Export is hidden below `lg`** — an export is a considered, audited act, not a thing you fire from a phone in a queue.

**2. Door operations (§12)**
- `xl`: three-pane — sessions list · live scan board (counters + stream) · device/PIN panel.
- `lg`: two-pane, device/PIN panel becomes a drawer.
- `md`/`sm`: **single-column, counter-first.** Top: one session, admitted / issued, big. Then per-device status rows (online, manifest age, queue depth). Then manual lookup as a full-width control. Then the flag queue as a count with a tap-through. Manifest open/close stays available at `md` and above; at `sm` it is **read-only status** (it freezes transfers for the whole session — not a phone-in-a-crowd action).

**3. Guest list (§11)**
- `xl`: table with inline check-in toggles and bulk add.
- `lg`: same, bulk add moves to a modal.
- `md`/`sm`: **check-in-optimized card list** — guest name large, party size as a chip, a single full-width Arrived / Not arrived toggle per card, search sticky, list default-filtered to "Not arrived". Add-guest stays available (single entry only; paste-many is `lg`+). Comp allocation is `lg`+ only (it draws capacity and carries a step-up seam, C39).

**4. Inventory status (§8)**
- `xl`: matrix — ticket types down, batches across, counters in cells, holds panel beside.
- `lg`: one table per ticket type.
- `md`/`sm`: **read-only status cards**, one per ticket type: name, price, and a capacity bar segmented `sold | held | remaining` with the three numbers written out. Warnings (low, sold out, door batch untouched, holds expiring) list beneath. **No capacity edits, no price edits, no batch creation below `lg`.** Releasing a specific expired hold IS allowed at `md` (it is a reversal, not a capacity change).

**5. Promoter performance (§10)**
- `xl`: promoter table with per-promoter sales, gross attributed, commission accrued/paid, plus the attribution detail drawer.
- `lg`: drops commission-paid into the drawer.
- `md`/`sm`: **read-only leaderboard cards** — promoter name, tickets attributed, gross attributed, commission accrued, status pill. Attribution detail opens full-screen and keeps `method`, `touch_corroborated`, `self_deal_flag` visible (Agent C requires the dispute-defence view to be complete wherever it renders). Issuing codes/links and the self-deal queue are `lg`+ only.

---

## 4. Information architecture

### 4.1 Navigation map

```mermaid
graph TD
  Root["Venue Dashboard (web, desktop-first)"]
  Root --> Ctx["Context bar<br/>Organization switcher · Venue switcher"]
  Ctx --> Home["A. Dashboard home<br/>Tonight · Upcoming · Sales · Attendance · Inventory warnings · Payouts · Activity"]

  Ctx --> Events["B. Events"]
  Events --> EvList["Events list"]
  Events --> EvNew["Create event (wizard)"]
  Events --> EvDetail["Event detail"]

  EvDetail --> Tabs["Event tabs"]
  Tabs --> TT["C. Ticket types & inventory"]
  Tabs --> Att["D. Attendees"]
  Tabs --> GL["F. Guest list & comps"]
  Tabs --> Door["G. Door operations"]
  Tabs --> Ref["H. Refunds"]
  Tabs --> Settle["I. Settlement"]
  Tabs --> Promo["E. Promoters (event scope)"]
  Tabs --> Act["L. Activity (event scope)"]

  Ctx --> PromoOrg["E. Promoters (org/venue scope)"]
  Ctx --> Finance["I. Settlement & payouts (org scope)"]
  Ctx --> Team["J. Staff & permissions"]
  Ctx --> Settings["K. Settings"]
  Ctx --> ActOrg["L. Activity (venue/org scope)"]

  Ext1["Promoter portal (separate surface)<br/>two-tier wall — domain §1.7"]
  Ext2["Scanner app (RN §7)"]
  Ext3["Platform internal admin (RN §8)"]

  classDef new fill:#2a1a1a,stroke:#FF1A1A,color:#fff;
  classDef ext fill:#1a1a1a,stroke:#666,color:#ccc;
  class Home,Events,EvList,EvNew,EvDetail,TT,Att,GL,Door,Ref,Settle,Promo,PromoOrg,Finance,Team,Settings,Act,ActOrg new;
  class Ext1,Ext2,Ext3 ext;
```

### 4.2 The two scope axes

Everything in this dashboard hangs off exactly one of two scopes, and the UI never blends them:

- **Organization scope** — money and people: settlement, payouts, payout destination, org members. Tested with `kernel.has_org_role(org_id, …)` (RLS §2.2).
- **Venue scope** — the room and the night: events, ticket types, inventory, guest lists, comps, door, venue staff. Tested with `kernel.has_venue_role(venue_id, …)`, or `kernel.has_event_role(event_id, …)` which resolves event → venue (RPC §1.1).

The org and venue **role label sets are disjoint by construction** (C36, RLS §2.1). The Staff section (§15) therefore renders **two separate rosters**, never one merged "Team" list — merging them is precisely the confusion C36 exists to make impossible.

`INFERENCE:` where an org role needs venue-grain authority (an `org_owner` editing an event), that inheritance lives inside the write RPCs (RLS §2.4), so the UI shows the control based on the same OR-predicate the RPC uses — it does not widen any read.

### 4.3 Context switching

The context bar's organization list is read from `kernel.org_member` for `auth.uid()` (RLS §7.3: "own org roster"); the venue list from `venue.staff_role` for `auth.uid()` (schema §3.9, index on `identity_id`, "my venues") **plus** venues of orgs where the user holds `org_owner`/`org_admin` (RLS §9.9: "venues of own org"). There is no "all organizations" or "all venues" read for any non-platform principal anywhere in this IA.

### 4.4 Why cross-organization access is impossible by construction

1. **No unscoped route exists.** Every dashboard route carries an org id, venue id, or event id, and every read behind it is a scoped read RPC or an RLS-filtered select. There is no route whose result set is "all".
2. **Scope ids are untrusted params.** RPC §0.1 makes every RPC re-check its scope predicate in-body against live tables. A tampered id in the URL returns `insufficient_privilege`, never another org's rows.
3. **No cross-org aggregate is ever computed.** A person operating three organizations sees three separate contexts and switches between them. There is deliberately **no "all my organizations" revenue tile, no combined attendee list, no combined payout view** — such a view would need a read that spans orgs, and no such read is specified or requested here.
4. **The switcher cannot enumerate what the user is not in.** Both switcher reads are keyed to `auth.uid()`.
5. **Deep links fail closed.** A pasted link to another org's event renders the standard permission-denied state (§18) with no partial content, no title, no count — a denial must not leak the existence or shape of the object.
6. **No impersonation.** This dashboard has no "view as venue" mode for platform staff. Platform roles reach venue data through the internal admin plane (RN §8) under `kernel.admin_audit`, not by borrowing a venue context here.

---

## 5. Role × surface access matrix

Consistent with **RLS §9.x** (venue schema), **§7.2/§7.3/§7.3b** (org tables), **§11** (EXEC authority), and — as of the Phase-2 consolidation — the **role-model spec §3/§5**, which is now co-binding with RLS on labels and capabilities. Columns are the RLS §1.1 principals that can reach this dashboard. `anon` and `fan` (no org/venue/platform role) have **no dashboard at all** — the route set is unreachable and returns the signed-out or denied state.

> **Label reconciliation applied (ratified O-2; role-model §3, §4.1, §4.5, and edit V-4).** The venue enum is now **six** labels, not four: `venue_manager` · `venue_finance` · `venue_box_office` · `venue_marketing` · `venue_promoter_manager` · `venue_scanner`. The org enum is now **six**: `org_owner` · `org_admin` · `org_finance` · `org_marketing` · `org_promoter_manager` · `org_member`. Two changes matter to every table below:
> - **`venue_door` → `venue_scanner` (rename).** Applied throughout; the `v_door` column is now `v_scan`. The rename is substantive, not cosmetic: O-4 separates *operating the door lifecycle* from *scanning against an already-open manifest*, and a label named `venue_door` asserted authority over the whole station. **The scanner may not create the security boundary it scans against.**
> - **`venue_promoter` is removed from the venue enum.** A promoter is a `promoter_link` row-ownership relationship, never a staff-role label. **The `promo` column below is retained and re-scoped: it denotes the promoter-portal principal, whose authority is `venue.promoter.identity_id = auth.uid()` on a live row — never `has_venue_role(...)`.** Note 14 already had this right; it is now true of the mechanism as well as the product. `venue_promoter` must not appear in any grant, picker, or predicate.
>
> The four new labels have no column in the 49-row matrix, which was written against the four-label enum. **Rather than rewrite a ratified, owner-approved table, their access is stated as an amendment in §5.1**, derived from role-model §5 and not extending it.

**Legend:** ● full (read + all writes the surface offers) · ◐ scoped subset (see note) · ○ read-only · — denied (surface not rendered; direct link → permission-denied state).

Platform columns record what RLS permits; **platform staff reach these objects through the internal admin plane (RN §8), not through this dashboard** — they are shown so the matrix is complete and so no one builds a venue-side control that platform is supposed to own.

| # | Surface | o_mbr | o_own | o_adm | o_fin | v_mgr | v_fin | v_scan | promo | p_sup | p_rsk | p_adm |
|---|---|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|
| 1 | A. Home — Tonight & upcoming | ◐¹ | ● | ● | ◐² | ● | ◐² | ◐³ | — | ○ | ○ | ● |
| 2 | A. Home — Sales & gross revenue | — | ● | ● | ● | ● | ○ | ◐³ | — | ○ | ○ | ● |
| 3 | A. Home — Attendance / check-in | — | ○ | ○ | — | ● | — | ◐³ | — | ○ | ● | ● |
| 4 | A. Home — Inventory warnings | ◐⁴ | ● | ● | ○ | ● | ○ | ◐³ | ◐⁴ | ○ | ○ | ● |
| 5 | A. Home — Payout status | — | ○⁵ | — | ● | — | — | — | — | ○ | ○ | ● |
| 6 | A. Home — Recent activity | — | ● | ● | ◐⁶ | ● | ◐⁶ | — | — | ○ | ○ | ● |
| 7 | B. Events — list & detail (read) | ○ | ● | ● | ○ | ● | ○ | ◐³ | ○⁷ | ○ | ○ | ● |
| 8 | B. Events — create / edit draft / add session | — | ● | ● | — | ● | — | — | — | — | — | ● |
| 9 | B. Events — publish / status change | — | ● | ● | — | ● | — | — | — | — | — | ● |
| 10 | B. Events — cancel event | — | ● | ● | — | ● | — | — | — | — | — | ● |
| 11 | B. Events — resale policy | — | ● | ● | ○ | ● | ○ | — | — | ○ | ○ | ● |
| 12 | C. Ticket types — read | ○ | ● | ● | ○ | ● | ○ | ◐⁸ | ○⁷ | ○ | ○ | ● |
| 13 | C. Ticket types — create | — | ● | ● | — | ● | — | — | — | — | — | ● |
| 14 | C. Ticket type — price / visibility change | — | ● | ● | — | ● | — | — | — | — | — | ● |
| 15 | C. Inventory — counters (full) | ◐⁴ | ● | ● | ○ | ● | ○ | ◐⁴ | ◐⁴ | ○ | ○ | ● |
| 16 | C. Inventory — create batch / capacity change | — | ● | ● | — | ● | — | — | — | — | — | ● |
| 17 | C. Holds — list & release | — | ◐⁹ | ◐⁹ | ○ | ● | ○ | ◐³ | — | ○ | ○ | ● |
| 18 | D. Attendees — list & detail | — | ● | ● | ◐¹⁰ | ● | ◐¹⁰ | —¹¹ | — | ○ | ○ | ● |
| 19 | D. Ticket holder mix (aggregate) | — | ○ | ○ | ○ | ○ | ○ | — | — | — | — | ○ |
| 20 | D. CRM export | —¹² | ● | ● | —¹² | ● | —¹² | —¹² | —¹² | —¹² | —¹³ | —¹³ |
| 21 | E. Promoters — list & manage | — | ● | ● | ○ | ● | ○ | — | ◐¹⁴ | ○ | ○ | ● |
| 22 | E. Promoter links & codes — issue / switch | — | ● | ● | — | ● | — | — | — | — | — | ● |
| 23 | E. Attribution & performance | — | ● | ● | ● | ● | ○ | — | ◐¹⁴ | ○ | ○ | ● |
| 24 | E. Self-deal flag queue — review | — | ● | ● | — | ● | — | — | — | — | ● | ● |
| 25 | F. Guest list — read | — | ● | ● | — | ● | — | ◐³ | — | ○ | ○ | ● |
| 26 | F. Guest list — manage entries | — | ● | ● | — | ● | — | — | — | — | — | ● |
| 27 | F. Guest list — door check-in | — | ● | ● | — | ● | — | ◐¹⁵ | — | — | — | ● |
| 28 | F. Comps — allocate / issue | — | ● | ● | ○ | ●¹⁶ | ○ | ◐³ | — | ○ | ○ | ● |
| 29 | G. Door PINs — issue / revoke | — | ● | ● | — | ● | — | ○¹⁷ | — | ○¹⁷ | ○¹⁷ | ● |
| 30 | G. Devices & manifest | — | ● | ● | — | ● | — | ◐¹⁸ | — | ○ | ○ | ● |
| 31 | G. Live scan board & totals | — | ○ | ○ | — | ● | — | ◐³ | — | ○ | ● | ● |
| 32 | G. Manual attendee lookup | — | ● | ● | — | ● | — | ●³ | — | ○ | ○ | ● |
| 33 | G. Flag / duplicate queue — view & escalate | — | ○ | ○ | — | ○ | — | ◐³ | — | ○ | ● | ● |
| 34 | G. Flag adjudication (resolve) | — | — | — | — | —¹⁹ | — | — | — | — | ● | ● |
| 35 | H. Refunds — order list | — | ● | ● | ● | ● | ○ | ◐³ | — | ○ | ○ | ● |
| 36 | H. Refund — initiate | — | —²⁰ | — | ● | —²⁰ | —²⁰ | — | — | ◐²¹ | ● | ● |
| 37 | I. Settlement — read header + lines | — | ● | ● | ● | ● | ● | — | — | ○ | ○ | ● |
| 38 | I. Settlement — open | — | ● | — | ● | ● | ● | — | — | — | — | ● |
| 39 | I. Settlement — close (→ payout) | — | — | — | ● | — | ● | — | — | — | — | ● |
| 40 | I. Payouts — status & history | — | ○⁵ | — | ● | — | — | — | — | ○ | ○ | ● |
| 41 | I. Payout — request disbursement | — | ● | — | ● | — | — | — | — | — | — | ● |
| 42 | J. Org members & invites — read | ○ | ● | ● | ○ | — | — | — | — | ○ | ○ | ● |
| 43 | J. Org invite / role change / remove | — | ● | ◐²² | — | — | — | — | — | — | — | ● |
| 44 | J. Venue staff roster — read | — | ● | ● | — | ● | ○²³ | ○²³ | ○²³ | ○ | ○ | ● |
| 45 | J. Venue staff — grant / revoke | — | ● | ● | — | ● | — | — | — | — | — | ● |
| 46 | K. Org & venue profile | ◐²⁴ | ● | ◐²⁴ | ◐²⁴ | ◐²⁵ | — | — | — | ○ | ○ | ● |
| 47 | K. Payout destination | — | ●²⁶ | — | ○ | — | — | — | — | ○ | ○ | ● |
| 48 | K. Notification preferences | ● | ● | ● | ● | ● | ● | ● | — | — | — | ● |
| 49 | L. Operational activity log | — | ● | ● | ◐⁶ | ● | ◐⁶ | — | — | ○ | ○ | ● |

**Notes**

1. `org_member` reads events/sessions (public-read, RLS §8.2/§8.3) and `remaining` only — it gets a catalogue view, not an operations view. `org_member` is deliberately the emptiest dashboard in the product.
2. `org_finance` / `venue_finance` are `D` on `venue.scan` (RLS §9.12) — their Tonight card shows sold and gross, **no attendance figures**.
3. `venue_scanner` is session-scoped and only for sessions its grant or PIN covers (RLS §1.1 row 9; §9.7 "own session orders", §9.12 "own session"). It sees no other session, no other event, no other venue.
4. Only the computed `remaining` projection is world-readable; raw `capacity`/`held`/`sold` are staff-scoped (RLS §9.2 note 23). `org_member` and `promoter` therefore see availability, never the counters.
5. **Flagged conflict (§22.3):** `kernel.request_org_payout` grants `org_owner` the request authority (RPC §10.3) but `kernel.payout`'s read authority names only "payee + org finance + platform" (schema §1.9). Shown as `○` on the read pending resolution.
6. Finance roles see the finance-relevant subset of the activity feed (settlement, payout, refund, price change) — see §17.3.
7. `promoter` reads public-visibility ticket types and `remaining` (RLS §9.1, §9.2) — but **inside the promoter portal, not this dashboard** (note 14).
8. `venue_scanner` reads `door_only` + `public` visibility ticket types for its own session (RLS §9.1).
9. `org_owner`/`org_admin` may `release_hold` for venue ops (RLS §9.5) but are `D` on `INSERT` there — they can release, not create, a hold from this surface.
10. Finance roles see money columns; **no contact PII** (domain §7.6 "View buyer PII: ◐(limited)"). See §9.3.
11. **Hard rule:** door staff never receive a bulk attendee list (domain §7.2, Door "Cannot list attendees in bulk"). Door gets single-record manual lookup only (row 32).
12. **CORRECTED (CRM K-2 / role-model V-5).** The export deny-list is `venue_scanner`, a door session, `venue_box_office`, `venue_promoter_manager`, `org_promoter_manager`, `venue_finance`, `org_finance`, promoters, `org_member`, `platform_support`, `fan`, `anon`. See §9.6.
13. **CORRECTED (CRM K-2 + K-3).** The allow-list now also carries `org_marketing` (org grain) and `venue_marketing` (venue grain), **audience columns only** — the money template stays `venue_manager` / `org_owner` / `org_admin`. `platform_risk` and `platform_admin` **read** the roster and **do not use the venue CRM export**; platform bulk extraction is not built in Phase 2. `platform_support` is narrower still: it reads, does not extract, and reaches a single record only through the lookup RPC. Full lists in §9.6. The former `UNVERIFIED:` is **discharged** — the CRM export spec supplies the job table, the lifecycle, the opt-in record and fifteen RPC contracts.
14. Promoters see only their own promoter row, own links, own attributions (RLS §9.17 note 40) — **in the separate promoter portal** (domain §1.7 two-tier wall). They never load this dashboard.
15. Door may update `status`/`checked_in_at` on guest entries for its session only (RLS §9.16 note 39).
16. Comp issuance beyond a per-staff threshold requires step-up + live grant re-check + reason code (C39; domain §7.5).
17. `pin_hash` is stripped from every client grant and is never returned to any client (RLS §9.10 note 32). Everyone's "read" excludes it.
18. Door updates only its own device's `last_sync_at`/`manifest_version` via the sync RPC (RLS §9.11 note 33).
19. `venue_manager` reads flagged scans (RLS §9.12 `A(own-venue)`) but has **no `INSERT`/EXEC for fraud-review actions** — only `platform_risk`/`platform_admin` do. The venue's action is *escalate*, not *resolve* (§12.7).
20. **Flagged conflict (§22.1):** RLS §11 grants `kernel.refund_primary_order` to `has_org_role([org_finance])` only among org roles; domain §7.2/§7.6 shows Org Owner with refund authority under dual control. This spec follows RLS (binding).
21. `platform_support` holds a *capped* refund authority whose ceiling is explicitly deferred to policy (RPC §16.3).
22. `org_admin` cannot invite or grant at `org_owner` tier (schema §1.3b; RLS §7.3b).
23. Venue staff see their own venue's roster (RLS §9.9 "own-venue roster") — read-only, no grants.
24. `org_member`/`org_admin` see `display_name` + `status` only; `legal_name`, Connect ref, and the payout lock are column-scoped to `org_owner`/`org_finance`/platform (RLS §7.2 note 4).
25. Venue profile (name, neighborhood, address, `capacity_hint`) is venue-manager editable via `catalog.update_venue` (RPC §3.3); `approval_status` is platform-set and read-only here.
26. `kernel.set_org_payout_destination` is `org_owner` only, dual-control seam, and triggers the `payout_destination_locked_until` cool-down (RLS §11; schema §1.2).

### 5.1 The four new labels — amendment, not extension (role-model §5)

`v_box` = `venue_box_office` · `v_mkt` = `venue_marketing` · `v_pmg` = `venue_promoter_manager` · `o_mkt` = `org_marketing` · `o_pmg` = `org_promoter_manager`. Cells use the §5 legend. **Nothing here widens any read; each cell is role-model §5's own value for that capability.**

| # | Surface | v_box | v_mkt | v_pmg | o_mkt | o_pmg |
|---|---|:--:|:--:|:--:|:--:|:--:|
| 1–6 | A. Home — all zones | ◐ᵃ | ◐ᵇ | ◐ᶜ | ◐ᵇ | ◐ᶜ |
| 7 | B. Events — read | ○ | ● | ○ | ● | ○ |
| 8–10 | B. Events — create / status / cancel | — | — | — | — | — |
| 11 | B. Resale policy | — | ○ | — | ○ | — |
| 12 | C. Ticket types — read | ○ | ○ | — | ○ | — |
| 13–14 | C. Ticket types — create / price | — | — | — | — | — |
| 15 | C. Inventory counters | ○ | — | — | — | — |
| 16 | C. Create batch / capacity | — | — | — | — | — |
| 17 | C. Holds — list & release | ◐ᵈ | — | — | — | — |
| 18 | D. Attendees — list & detail | —ᵉ | ●ᶠ | — | ●ᶠ | — |
| 19 | D. Ticket holder mix | — | ○ | ○ᵍ | ○ | ○ᵍ |
| 20 | D. CRM export | — | ●ʰ | — | ●ʰ | — |
| 21 | E. Promoters — list & manage | — | — | ● | — | ● |
| 22 | E. Links & codes — issue / switch | — | — | ● | — | ● |
| 23 | E. Attribution & performance | — | — | ● | — | ● |
| 24 | E. Self-deal queue — **review** | — | — | **—**ⁱ | — | **—**ⁱ |
| 25–27 | F. Guest list — read / manage / check-in | ◐ʲ | — | — | — | — |
| 28 | F. Comps — allocate / **issue** | ◐ᵏ | — | — | — | — |
| 29–31 | G. Door PINs / devices / scan board | — | — | — | — | — |
| 32 | G. Manual attendee lookup | ● | **—**ˡ | — | **—**ˡ | — |
| 33–34 | G. Flag queue / adjudication | — | — | — | — | — |
| 35–36 | H. Refunds — list / initiate | ○ / **—**ᵐ | — | — | — | — |
| 37–41 | I. Settlement & payouts | — | — | — | — | — |
| 42–45 | J. Staff & members | ○ᵛ | ○ᵛ | ○ᵛ | ○ | ○ |
| 46–47 | K. Org / venue profile · payout destination | — | ◐ⁿ | — | ◐ⁿ | — |
| 48 | K. Notification preferences | ● | ● | ● | ● | ● |
| 49 | L. Operational activity | — | — | — | — | — |

**Notes**
- ᵃ `venue_box_office` sells; its home is the sell-and-admit view — tonight's sessions, availability, its own holds. No gross revenue, no payout, no activity feed.
- ᵇ marketing sees the event/marketing surfaces and aggregate mix; **no money column anywhere**.
- ᶜ promoter-manager sees its promoters' attribution and commission; no money beyond that, no inventory, no door.
- ᵈ box office may **release** a hold it can reach (a reversal); it may not create capacity.
- ᵉ **`venue_box_office` gets no roster and no export — single-record lookup only** (CRM §3.1). Row 32 is its attendee read.
- ᶠ marketing's roster read is **audience columns only — IDENT + OPS + CONTACT, never MONEY.** `org_marketing` at org grain (all the org's venues); `venue_marketing` at venue grain only.
- ᵍ promoter-manager reads the holder-mix card at **event level only, with no promoter axis** — a promoter-attributed sub-population at a Miami club night is routinely 10–40 people, far below the k = 25 floor, and a promoter-scoped aggregate is exactly the second axis that would make the event aggregate differenceable.
- ʰ **audience template only.** The money template (`operations_v1`) stays `venue_manager` / `org_owner` / `org_admin`.
- ⁱ **Both promoter-manager labels are denied the self-deal release/deny decision** — separation of duties: the person who recruits the promoter does not adjudicate that promoter's flagged commission.
- ʲ box office may read the guest list and mark arrived for its session; it may not add, remove or rename.
- ᵏ box office may **issue** an individual comp against an already-allocated batch (an issuance operation, step-up-gated) but may **not allocate** comp capacity (an inventory decision).
- ˡ **both marketing labels are denied the single-record lookup.** Marketing gets the aggregate and the bulk audience export; it does not get a per-person service lookup. That asymmetry is deliberate.
- ᵐ **`venue_box_office` is not granted a cash-refund-at-door authority by this spec** (role-model OD-5). Refund initiation is §13.3's list.
- ⁿ marketing may edit event marketing fields and the event public page (role-model D3/H4). It touches no org money column and no payout setting.
- ᵛ every venue staff member reads their own venue's roster (RLS §9.9), read-only.

**The asymmetry worth stating on the Staff page (§15.4):** **finance sees money and never contact; marketing sees contact and never money. Neither sees both.** Only `venue_manager`, `org_owner` and `org_admin` hold the union — and that union is the single most consequential grant in this product.

**Not modelled, still:** `scan_scopes` (per-ticket-type door narrowing). A door PIN admits every ticket type for its session. **No surface may imply a VIP-only door.**

### 5.2 Corrected rows from the money-authority spec (§10.1)

These supersede the matrix cells above them. Only the four columns the money spec carried are changed; every other column in those rows is unchanged.

| # | Surface | o_own | o_adm | o_fin | v_fin | Change |
|---|---|:--:|:--:|:--:|:--:|---|
| 5 | A. Home — Payout status | **○** | — | ● | — | note 5's flagged conflict (§22.3) **resolved** by O-3; `○` is confirmed, not provisional |
| 36 | H. Refund — initiate | **●** | — | ● | — | **was `—`** with flagged-conflict note 20; **O-1 grants it.** Note 20 **resolved** |
| 40 | I. Payouts — status & history | **○** | — | ● | **◐** | `○` confirmed; `venue_finance` becomes `◐` — settlement-cause rows for its own venue only |
| 47 | K. Payout destination | **●**ˢᵒᵈ | — | **○** | — | `org_finance` is **read-only** here (it was implicitly writable only via domain prose) |
| **NEW** | H. Refund — approval queue | ● | — | ● | — | `NEW DASHBOARD SURFACE` — the second approver's inbox (§13.7) |
| **NEW** | K. Re-authenticate for a money action | ● | — | ● | — | `NEW DASHBOARD SURFACE` — the step-up flow (§16.9) |

**Legend addition:** **`ˢᵒᵈ` = SoD-constrained** — the grant is real, but the holder is structurally excluded from the paired act. `org_owner` may change the payout destination **and** may not then approve a payout to it. `INFERENCE:` the money spec introduces this superscript for the dashboard matrix without defining it (it defines the parallel `ᔆ` for the domain doc); the definition above is this spec's. → §22.10.

`INFERENCE:` the money spec's corrected table carries no row 38 and does not restate the cell legend. Rows 35, 37 and 39 are listed there as unchanged context and are **not** re-stated here.

> **⚠ ROW 35 IS CONTESTED — BLOCKING OWNER DECISION `D-8`. Added 2026-08-28 (reviewer condition 2).** Row 35
> (H. Refunds — order list) carries `org_admin` at `●` in §5 above, and the money spec's §10.1 carries the same
> `●` — **while that same money spec's §3.4 denies `org_admin` the refund ledger entirely and labels its own
> position `INFERENCE`.** Because §5.2 does **not** supersede row 35, this spec is faithfully inheriting a
> document that contradicts itself. **Silence defaults to GRANT** (RLS §9.7 and §9.13 both grant `org_admin`),
> and **over-provisioning is the unsafe direction**. See §22.13 for both positions in full, money spec §11.1
> for the registered decision, and `PHASE_2_RATIFICATION_RECORD.md` `O13`. **Do not render surface H's refund
> list for `org_admin` on the strength of this table until `D-8` is closed.**

---

## 6. (A) Dashboard home

**Route:** `/o/{org}/v/{venue}` · **Purpose:** answer "what do I need to do about tonight, and did I get paid?" in one screen, with nothing on it that a Phase-3 analytics product would own.

### 6.1 Zones (top to bottom, desktop)

**1 · Tonight**
One card per session whose `starts_at` is today or whose `status = 'live'` (schema §2.3 indexes `starts_at` for exactly this). Each card: event title · doors time · **sold / capacity** · **admitted count** · door manifest state (Closed / **Open — transfers frozen**) · devices online / registered · guest list arrived / total.
Empty: *"Nothing on tonight."* Never fabricate an empty card row.

**2 · Upcoming**
Next N sessions (default 10) by `starts_at`. Per row: event · date · status pill (`draft` · `announced` · `on_sale` · `live` · `completed` · `cancelled`, schema §2.2) · sold / capacity · days to doors · a warning chip if any inventory warning applies.
Empty: *"No upcoming events. Create one to start selling."* with the create action if the role has it.

**3 · Tickets sold**
Count and gross for the selected window (Today · 7 days · 30 days · This event). Source: `paid` `venue.order` + `venue.order_item`. One sparkline of sold-per-day for the current window — **this is the only chart on this page.**

**4 · Revenue (gross)**
Gross for the window, in USD from integer minor units (schema §0.3). Rendered with a permanent inline caption, not a tooltip:
> *"Gross, before fees and refunds. What you'll actually be paid is in Settlement."*
Hidden entirely for roles without order money read (matrix row 2).

**5 · Attendance / check-in**
For live and completed sessions: **admitted / issued**, percentage, last scan time, plus the non-admitted counts (`duplicate`, `invalid`, `frozen`, `fraud_review` — the `venue.scan.result` enum, schema §3.12). Hidden for `org_finance`/`venue_finance` (note 2 above).

**6 · Inventory warnings**
One row per condition, each naming the ticket type and the release:
- *Low* — `remaining` below the configured threshold for that batch.
- *Sold out* — `remaining = 0` **and** `sold` accounts for it.
- *All held, none sold* — `remaining = 0` because `held` consumed it. These two look identical to a fan and are completely different to an operator; never collapse them.
- *Door stock untouched* — a `door` release_kind batch with `sold = 0` while the session is live.
- *Holds expiring* — active `venue.inventory_hold` rows with `expires_at` inside the next hour.
**One row per (batch, threshold)** and it does not re-fire on the same pair — deliberately identical to Agent D's low-inventory notification rule, so the banner and the notification never disagree.

**7 · Payout status**
Latest settlement per recently-closed event with its payout state (`pending` · `submitted` · `paid` · `failed` · `reversed`, schema §1.9). **A `failed` payout pins to the top of the page and is not dismissible** for `org_finance` and `org_owner` — matching Agent D's non-opt-out routing for payout failure, so the alert channel and the dashboard agree.

**8 · Recent activity**
Last 20 rows of §17's operational feed, with a "See all" link. Never security events (§17.2).

### 6.2 What home deliberately does NOT have

No conversion rate, no funnel, no cohort, no repeat-buyer rate, no channel attribution beyond the promoter counts in §10, no forecast, no benchmark against other venues, no year-over-year, no heat map. If an operator asks, the answer is Phase 3. Shipping a hollow version of any of these is worse than not shipping it.

### 6.3 States

- **Loading:** zone-level skeletons; zones resolve independently (Tonight must not wait on Settlement).
- **Empty:** per zone, specific copy above. Never one page-level "no data".
- **Error:** per zone error card with retry; one zone failing never blanks the page.
- **Permission-denied:** zones the role cannot read are **absent**, not greyed. A role that can read no zone at all (e.g. `org_member` with no venue role) gets the catalogue-only home plus *"Your access covers event details only. Ask an organization owner or admin for more."*
- **Offline:** the browser-offline banner; the page is stale-labelled with last-loaded time. No writes queue.

**Reads:** §20 rows A1–A8.

---

## 7. (B) Events

### 7.1 Events list — `/o/{org}/v/{venue}/events`

Columns: title · venue · next session date · status pill · sold / capacity · resale mode · promoter count.
Filters (closed set): status, venue, date range. Search: title substring.
Sort: next session (default), title, sold.
**Reads:** `catalog.event` (RLS §8.2 — public-read for `announced`+, org/venue-scoped for `draft`), `catalog.event_session`, `venue.inventory_batch.remaining`, `catalog.resale_policy`.
States — loading: table skeleton · empty: *"No events yet."* + Create (role-gated) · error: retry · denied: standard denial.

### 7.2 Create event — 3-step wizard

Ends in `draft`. Steps:
1. **Basics** — title, venue (pre-filled from context), first session `starts_at`, optional `doors_at`, optional `session_label`. → `catalog.create_event` (RPC §4.1), which **auto-creates the implicit first session** (A1). Precondition surfaced by the UI: the venue must be `approved` (RPC §4.1) — if not, the wizard blocks at step 1 with *"This venue isn't approved to sell yet. Snatch It has to approve it first."*
2. **First ticket type** — kind (`admission` | `table`), name, price, visibility. → `venue.create_ticket_type` (RPC §5.1).
3. **First inventory release** — release kind, capacity, session. → `venue.create_inventory_batch` (RPC §5.2).

Step 2 and 3 are part of the wizard because **publishing requires at least one ticket type with a batch** (RPC §4.2 precondition, "no empty on-sale"). Doing it later is allowed; doing it never means the event can never go on sale, and the wizard should not let someone discover that a week later.

### 7.3 Edit draft

Editable while `draft`: title; session `starts_at`/`doors_at`/`ends_at`/`label`; ticket types; batches; resale policy.
Once `on_sale`, price and capacity edits become **confirmed operations** with an explicit warning (schema §3.1 "on-sale edits confirmed"; §2.3 "`starts_at` change on an on-sale session is a confirmed operation").

### 7.4 Publish / announce / status

One control: **Advance status**, offering only the next legal forward transition from `draft → announced → on_sale → live → completed` (RPC §4.2 validates the transition server-side; the UI must not offer a jump it will reject).
- `announced` — visible publicly, not buyable.
- `on_sale` — buyable. **Blocked** unless ≥1 ticket type with a batch exists; the UI pre-checks and, when blocked, names what's missing rather than showing a dead button.
- `live` — the night itself.
- `completed` — terminal for sales.
There is **no reverse transition** in the contract. The UI must say so before the confirm: *"You can't move an event backwards."*

**MVP on-sale configuration is manual.** There is no `announce_at`/`on_sale_at` column in `catalog.event` (schema §2.2) and no scheduler in the RPC contract. The surface states: *"On-sale starts when you set it to On sale. Scheduling isn't available yet."* → delta §21.6.

### 7.5 Event image, description, lineup

**Not modeled.** `catalog.event` has `event_id`, `venue_id`, `org_id`, `title`, `status`, timestamps — nothing else (schema §2.2). Domain §1.3 describes lineup/media/visibility as event attributes, but the *physical* Phase-2 schema does not carry them. MVP renders a venue-derived placeholder and does **not** ship an uploader against a column that does not exist. → delta §21.5.

### 7.6 Sessions

List of `catalog.event_session` for the event: label, `starts_at`, `doors_at`, `ends_at`, `status` (`scheduled` · `live` · `completed` · `cancelled`), and — read-only — **door manifest state** (`door_open_at`).
Add session → `catalog.create_event_session` (RPC §4.3); label must be unique per event.
Capacity is **per session**, expressed through the batches attached to it (domain §1.3) — the UI must never show an event-level capacity number, because oversell is checked per session and an event-level figure is the exact lie that causes a residency to oversell one night.

### 7.7 Resale policy

Per event (or inherited from the venue-scope policy). Fields from `catalog.resale_policy` (schema §2.5): `mode` ∈ `off` · `transfers_only` · `fixed_cap` · `face_value_queue` · `buy_now` · `auction` · `offer`; `price_cap_bps` (for `fixed_cap`); `royalty_bps`.
**Default is `off`** (C11) and the UI says so: *"Resale is off unless you turn it on."*
Changing the policy **creates a new version, never an edit** (schema §2.5, AO per version). The surface shows the in-force version and `effective_from`, and warns: *"Tickets already listed keep the policy they were listed under."* (listings snapshot `policy_id` + `version`, schema §2.5).
Write: `catalog.set_resale_policy` (RPC/RLS §11) — `org_owner`/`org_admin`/`venue_manager`.

### 7.8 Cancel event

The most destructive control in the product. Route: event detail → danger zone.
Pre-confirm panel shows the **blast radius as counts**, read live: sessions to cancel · tickets to void · orders to refund · open listings and transfers to cancel. Reason code required (closed set).
Confirm requires typing the event title. Step-up applies (domain §7.5, ownership/refund class).
Write: `catalog.cancel_event` (RPC §4.4) — cascades sessions, cancels open native listings/auctions/p2p, voids every issued ticket, and records refund intents; Stripe refunds execute edge-side, so the result screen shows a **progress state**, not a completed one.
Copy rule: never say "delete". Nothing is deleted (GP-2, RLS §1.3).
States: loading blast radius · blast-radius-unavailable → **block the action** (never cancel blind) · in-progress · partial (some refunds still executing) · error.

### 7.9 Event detail

Header: title, venue, next session, status pill, quick counters (sold / capacity, gross, admitted when live).
Tabs: Overview · Ticket types · Attendees · Guest list · Promoters · Door · Refunds · Settlement · Activity. Tabs the role cannot read are absent (not disabled).

---

## 8. (C) Ticket types & inventory

### 8.1 Ticket types list

Per event. Columns: name · kind (`admission` | `table`) · price · visibility (`hidden` | `public` | `door_only`) · releases · sold / remaining.
**Reads:** `venue.ticket_type` (RLS §9.1), `venue.inventory_batch` (RLS §9.2).

### 8.2 Create ticket type

Fields: kind, name (unique per event, schema §3.1), price (minor units, > 0), visibility.
Write: `venue.create_ticket_type` (RPC §5.1).
Blocked when the event is `completed`/`cancelled` (RPC §5.1 precondition) — stated, not silently failed.

**What MVP does not have, said plainly on this surface:**
- **No tier ladder object.** Domain §1.4 describes `tier_group`/`tier_rank` and `sell_out_unlocks_next`; the physical schema has neither (schema §3.1). MVP expresses tiers as **separate ticket types** whose visibility the operator flips by hand. The surface says: *"Tiers are separate ticket types today. Turn the next one public when the first sells out."*
- **No bundles, no add-ons.** `kind` is `admission | table` only (C11).
- **No table spend tracking.** A `table` type records a price; the running minimum-spend balance and its at-the-room settlement are **not modeled** (C45, domain §1.4). No surface may imply the platform tracks table spend. Copy: *"Snatch It handles the deposit. The balance at the table settles with you, off-platform."*

### 8.3 Price / visibility change

Money-consequential → live-table recheck (C9, schema §3.1, RLS §9.1 note 22). The UI:
1. Shows current price and the new price.
2. Warns when the event is `on_sale` or `live`: *"This event is selling. The new price applies to purchases from now on. Tickets already sold keep the price they were sold at."* (order items snapshot price, schema §3.8.)
3. Requires confirm; the change is audited.
Write: `venue.set_ticket_type_price` (RPC §5.1 companion).

### 8.4 Inventory: releases (batches)

One batch per (ticket type × session × `release_kind`). `release_kind` ∈ `public_sale` · `promoter_hold` · `comp` · `door` · `presale` (schema §3.2), shown with operator names: **Public sale · Promoter hold · Comps · Door · Presale**.

Matrix cell per batch: `capacity` · `held` · `sold` · **`remaining` (computed, never editable)** · a segmented bar.
Create batch → `venue.create_inventory_batch` (RPC §5.2): capacity > 0, type and session in the same event. Shard count is an internal optimization — **do not expose it**; the create form has no shard field, and the operator never sees shard rows (RLS §9.3 note 25). `INFERENCE:` sharding is chosen by ops policy, not by the venue.
Capacity change: audited, guarded, and refused if it would drop capacity below `held + sold` (the CHECK, schema §3.2). The UI computes and shows the floor: *"You can't go below 240 — that's what's already held or sold."*

### 8.5 Door vs public inventory

The `door` release is stock deliberately withheld from online sale so the box office has something to sell at 1 a.m. (domain §1.5). The surface states it as one line per session:
> **Held back for the door: 40 of 500** — and, when the session is live and that batch has `sold = 0`, an inventory warning (§6.1 zone 6).

### 8.6 Sale windows and quantity limits

**Not modeled per ticket type.** `venue.ticket_type` carries no sale window and no per-order min/max (schema §3.1). The per-user cap is a **global platform value** read from `catalog.platform_config` inside `venue.reserve_primary_inventory` (RPC §5.3). The surface therefore shows the cap **read-only** with *"Purchase limit: N per person (set by Snatch It)."* and offers no per-type override. → delta §21.7.

### 8.7 Holds

List of `venue.inventory_hold` for the event: holder, quantity, kind, `status` (`active` · `converted` · `released` · `expired`), `expires_at` countdown.
Action: **Release** → `venue.release_inventory_hold` (RPC §5.5) — idempotent; double-release is a no-op, so the UI never needs a "did that work?" retry loop.
Copy for staff/promoter holds: *"Releasing this puts the tickets back on sale immediately."*

### 8.8 Sold out vs held out

Two distinct states, never merged:
- **Sold out** — `remaining = 0`, driven by `sold`. Copy: *"Sold out."*
- **All held** — `remaining = 0`, driven by `held`. Copy: *"Nothing available — everything is on hold. Release holds to put tickets back on sale."*

### 8.9 States (all inventory surfaces)

Loading: matrix skeleton · Empty: *"No ticket types yet"* / *"No releases yet — add one so this type can sell."* · Error: retry, and **counters never render stale-optimistic** (an inventory number the operator can't trust is worse than a spinner) · Denied: standard · Partial: a batch whose counters fail to load renders as *"Couldn't load"* — never as zero.

---

## 9. (D) Attendees

**Grain: the session.** Attendees are listed per `catalog.event_session`, because that is the admission grain (domain §1.3) and a residency's Friday list is not its Saturday list.

### 9.1 List — **holder-keyed** (`SPEC CORRECTION`, CRM K-1)

> **The defect this replaces.** This list was **purchaser-keyed** — *"Name — from the buyer's `public.profiles` record via `venue.order.buyer_id`"*. A six-ticket table therefore showed **one name and omitted the five people actually holding tickets and walking through the door.** For a product whose entire native-rail thesis is that custody is real and transferable, that is the wrong grain. **The roster is holder-keyed; the order surface is purchaser-keyed; and contactability follows neither — it follows consent.**

**The canonical grain** is `session_roster`: one row per non-voided `kernel.tickets` atom for the session, carrying both the atom's **current holder** and its **originating purchaser**, evaluated live at a named instant `as_of`. The atom is the grain because the atom is the only object with exactly one holder and exactly one purchaser. Two projections exist and no others:

- **Holder view (DEFAULT — this tab).** One row per distinct current holder, aggregating the atoms they hold. **This is "who is coming."**
- **Purchaser view.** One row per `venue.order`. **This is "who paid" — a money surface**, and it is the Refunds tab (§13.1), not this one.

**Columns (`xl`), holder view.** Classes: **IDENT** · **OPS** · **CONTACT** · **MONEY**. **A role holds a class, never an individual column** — a denied class is **absent from the result, not null** (§16.1's rule).

| # | Column | Class | Source |
|---|---|---|---|
| 1 | `customer_ref` | IDENT | a per-org pseudonym; **never a global identity id** |
| 2 | Name | IDENT | `public.profiles.display_name` — the public-safe set. **Pins §22.9.** |
| 3 | **`is_purchaser`** | IDENT | true iff this holder is the buyer of ≥1 of the atoms they hold — **retained, so "who paid" is still answerable from this view** |
| 4 | Tickets held | IDENT | count of non-voided atoms held for this session |
| 5 | Ticket types | OPS | distinct, sorted |
| 6 | Source | OPS | `venue.order.source` ∈ `app` · `web` · `door` · `promoter_link` |
| 7 | Acquired via | OPS | ownership-log head cause, mapped to a plain verb (bought · transferred to them · comp) |
| 8 | Check-in | OPS | latest scan: not scanned · admitted (+ time) · already used · other non-admit. **Finance roles are denied — they are `D` on `venue.scan`.** |
| 9 | Admitted at | OPS | the admitting scan's time |
| 10–11 | Promoter name / code | OPS | via `venue.attribution` → `promoter_link`; **gated on the promoter package** |
| 12 | Email | **CONTACT** | **audience roles only, and only where a per-order, per-org opt-in was given.** Blank otherwise, with the legend in §9.6. |

**Money columns (order ref, order status, order total, unit price, refund state, tickets purchased) belong to the purchaser view**, are MONEY class, and render for money roles only. Refund state stays derived from order status plus ticket `voided` (D2: a refunded ticket is `voided`, never "refunded").

**Never on this list, for any role including `org_owner` and `platform_admin`:** a global identity uuid · phone number · legal name · any payment identifier · credential or custody internals · door internals · the transfer counterparty · another org's data · **and every demographic object** — no demographic column, no answered/not-answered flag, and no sort or filter derived from either.

**What the correction changes operationally:** a table that used to read "Maya Torres — 6" now reads six rows, five of which are the people who will actually present a pass. The purchaser is still identifiable — that is what `is_purchaser` is for — and the money view still rolls up by order.

**Backed by** `venue.list_attendees(p_session_id, p_filters, p_cursor)` — a definer read, column-scoped by role, filters validated against the closed set, rate-limited, **audited on every page**. This satisfies §21 Δ3's attendee read.

### 9.2 Search and filters

- **Search:** name (substring), order ref (exact), email (**exact match only**). No email substring search — substring search over emails is a directory-harvesting affordance and this surface will not have one. `INFERENCE:` mirrors the consumer-side exact-match recipient lookup rule (RN §4.5.2).
- **Filters — a closed enumerated set** (Agent B): session · ticket type · order status · check-in status · source · promoter · refund state. **No SQL box, no arbitrary column picker, no free-form query builder** anywhere in this product.

### 9.3 What each role sees in this list

- `venue_manager`, `org_owner`, `org_admin` — the full holder view **plus** the purchaser/money view. **This union is the most consequential grant in the product.**
- `venue_marketing` (venue grain) / `org_marketing` (org grain) — **audience columns only: IDENT + OPS + CONTACT. No money column, and no single-record lookup** (§5.1 note ˡ).
- `org_finance`, `venue_finance` — **money columns and counts, never contact detail, and never check-in** (they are `D` on `venue.scan`).
- **`venue_box_office` — no roster.** Single-record lookup only (§12.6). It sells and it admits a named person at the desk; it does not receive the list.
- **`venue_scanner` and a door session — never.** Bulk attendee listing is denied to door staff. The door uses §12.6 manual lookup, one record at a time. A door principal hitting this route gets the permission-denied state, and the denial **names the alternative**.
- **`venue_promoter_manager` / `org_promoter_manager` — no roster, no export.** The promoter dimension never becomes a back door into the attendee list.
- `promoter` — never, from any surface (RLS §9.17 note 40; domain §1.7).
- **Platform (CRM K-3):** `platform_risk` and `platform_admin` **read** the roster. `platform_support` is narrower still — **it reads, and it does not extract**, reaching a single record only through the lookup RPC for a support ticket. **None of the three uses the venue CRM export** (§9.6).

**The rule underneath all of it: read ≠ export.** Support can look; it cannot extract.

### 9.4 Attendee detail drawer

Order timeline (created → paid → refunded), order lines with snapshot prices, the tickets in the order with their state, scan result and time, attribution (method + promoter), and role-gated refund actions (§13).
Ticket history uses **`kernel.get_ticket_custody_chain`** (RPC §1.3) — the staff read, with counterpart PII still redacted. It never reads `kernel.ticket_ownership_log` directly (deny-all to clients, RLS §7.6), and it is **not** `market.get_ticket_history`, which is owner-only (RPC §1.2).

### 9.5 Ticket holder mix — the aggregate breakdown card (Agent B, binding)

Placement: **Attendees tab, per event, below the list.** Not on Dashboard home. Never inside the table. Never in the detail drawer.

> **Rendered copy is only what appears in blockquotes and quoted strings below.** This section's own heading and prose are engineering description, not card text — do not lift them into the UI.

- **Card title is exactly "Ticket holder mix."** The words **"attendee", "audience", and "demographics" are banned from this card** — title, subtitle, axis labels, tooltips, legend, and empty state.
- **Aggregate only.** No individual's value is ever shown, and no value ever appears beside a name. There is no drill-down, no row-level join, no "show me who".
- **Suppression:** rendered only when **≥ 25 responses** for the event (k = 25), with a **per-bucket floor of 5** — buckets below 5 are merged into an "Other" bucket or the whole card suppresses if merging cannot preserve the floor.
- **One dimension at a time.** No crossing with ticket type, promoter, price, or time. The dimension selector offers one choice; there is no second axis control to build.
- **Subtitle — PUBLISHED STATE ONLY** (`SPEC CORRECTION`, demographics **J-10** / §4.3 correction 1):
  > *"Based on N of M ticket holders who shared this. One person can hold more than one ticket, so this counts people, not tickets. Counts people who bought a ticket to this event."*
- **Suppressed state copy (exact) — and NOTHING ELSE:**
  > *"Not enough responses to show a breakdown for this event. We show this only when at least 25 ticket holders have shared it."*
- **Footnote, always rendered:**
  > *"Snatch It never shows you who answered what."*
- **Export:** the mix is **not** an exportable object and does not appear in the CRM export (§9.6). It is a read on screen.

**The suppressed card renders NO NUMBERS OF ANY KIND (`SPEC CORRECTION`, demographics J-10 / R6).** Not a total, not a response count, **not a reason, and not an `as_of`**. `venue.get_holder_mix` returns the single boolean **`{ suppressed: true }`** and nothing else, so there is no denominator on the wire for the client to render even by accident.

> **Why the projection is a bare boolean and not `{suppressed, reason, holders_total, holders_responded}`.** The richer shape carried **no floor on its denominators**, so a one-person session answered the question *"did this person answer?"* — `M = 1, N = 1` versus `M = 1, N = 0` — which is the exact individual-level disclosure the k-floor exists to prevent. A `reason` is the same leak in words, and an `as_of` on a suppressed card confirms a snapshot ran. **The suppression state is therefore not a *degraded* card; it is a card that has nothing to say, and it says nothing.**

**"Based on N of M" is a published-state string.** It is not a template with empty slots and it is not rendered with zeroes, dashes, or "—". In the suppressed state the subtitle **does not render at all**.

**The denominator, pinned — and it is NOT the length of the list above it (`SPEC CORRECTION`, demographics R7).** `M` is **`holders_total` = the R7-**eligible** holders: distinct identities holding ≥1 non-voided ticket for this session at `as_of` **whose custody was acquired for consideration** — the ownership-log head cause is not `comp`, and the atom's issuance was not zero-price. **Comped and zero-price custody is excluded**, because a comp costs the venue nothing and the same `venue_manager` mints both the session and the comps; any *"an inferable group is at least 5 people"* bound assumes those five were not manufactured.

Therefore the earlier pinned equality — *"the number of rows in the list above this card is exactly the `M` the card is counting"* — **is false and is withdrawn.** The roster (§9.1) deliberately counts **all** holders, comps included, because the room has to be run. The binding identity is now:

> **`COUNT(§9.1 holder rows) ≡ holders_total + holders_excluded_ineligible`**

and **`holders_excluded_ineligible` exists as a stored number precisely so this surface can state the gap.** The original reasoning survives its own correction: an operator who counts the list and reads the card must not be left to discover a discrepancy and conclude one surface is broken — so the difference is **rendered**, not merely reconciled in a test. §9.1 still had to become holder-keyed; a purchaser-keyed roster would have made the two numbers differ for a *second*, unstated reason. A test pins the identity.

`N` is `holders_responded` — R7-eligible holders with a **substantive** answer. **`prefer_not_to_say` is never a published bucket**; a deliberate decline and a never-answered row both land in `M − N`, so declining is indistinguishable from silence.

Also render, beneath the subtitle, **in the published state only**:
> *"As of {as_of}. This is who holds tickets — not a door count."*

`INFERENCE:` **a genuinely free event never renders this card at all** — every holder is R7-ineligible, so `M = 0`. That is the correct outcome (at a free event the operator can mint the entire population, so no anonymity bound holds) and it is a real product loss. It is **owner decision D-12** in the demographics spec, not something this surface may soften with copy.

**Suppression is enforced in the database, not the UI.** The per-bucket floor of 5 is a `CHECK` constraint — **a sub-floor bucket cannot physically be stored**, not merely hidden. Buckets below the floor merge into "Other", smallest first, until "Other" clears the floor; if no such set exists, the whole snapshot is suppressed and **zero** bucket rows are written. The shown buckets always sum exactly to `N` — omitting a suppressed bucket instead would make the residual computable and hand over its exact count.

**There is no second axis, anywhere.** No crossing with ticket type, promoter, price, time window, or scan status — and not because the UI hides them, but because **no such aggregate exists in the database, in any view, cache, export, or parameter.** `venue.get_holder_mix` takes **exactly two parameters, and that is the contract**: adding a third is a design change requiring privacy re-review, not a routine enhancement.

> **Scope of that argument, narrowed (demographics `J-9(1)`).** The absent-operand argument defeats **slicing** — differencing along an *axis* that does not exist. It is **not** a general answer to differencing, and the general form of it (*"you cannot difference aggregates that do not exist"*) **was deleted from the demographics spec as false.** The `(session, dimension, bucket)` aggregate does exist, one per session, and an operator who **composes two populations** — by minting a session, by minting custody, or by choosing which two of their own sessions to compare — differences two aggregates that both exist. The population-side defences are R7 (eligibility), R8 (churn) and R9 (cross-session near-duplicate); **this axis argument covers none of them and must not be cited as if it did.**

The former `UNVERIFIED:` is **discharged** — the demographics spec supplies the storage (`kernel.identity_demographic`, package `077`), the collection surface (RN "About you (optional)", **profile enrichment only, never signup**), and the aggregation (`venue.holder_mix_snapshot` / `holder_mix_bucket` + `venue.get_holder_mix`, package `087`). This section still specifies only how the dashboard renders it.

### 9.6 CRM export (Agent B, binding)

**Asynchronous job**, never a synchronous download.

- **Lifecycle:** `queued → running → ready → failed`, plus `revoked`, `expired`, `purged`. The UI renders each as a distinct state with its own copy; `ready` is the only state with a download control.
- **Download:** a **300-second signed URL**, **re-authorized live at download time** — the click re-checks authority server-side before the URL is honoured. An export prepared while the user held `venue_manager` and downloaded after revocation must fail. **The re-check is over `(scope, template_id)`, not over the role set** (CRM K-15): a `marketing` role holds the job-list read, so a re-check that only asked *"do you still hold a role over this scope?"* let it download a colleague's **`operations_v1`** file — order refs, totals, unit prices, refund state — defeating *"Marketing sees contact and no money"* with no grant being wrong. The download predicate is **the same predicate a fresh request would face**.
- **Audit:** every **request, generate, download, revoke** is audited. The export history panel shows who requested, when, what filters, and what happened to it — and is itself part of the venue activity feed (§17).
- **Authorized — `SPEC CORRECTION` (CRM K-2, role-model V-5). Two templates, two allow-lists.** The former single list (`venue_manager`, `org_owner`, `org_admin`) predated the marketing role.

  | Template | Columns | Who |
  |---|---|---|
  | **`audience_v1`** | IDENT + OPS + **CONTACT** (org grain adds the org-CRM counts) | `org_owner` · `org_admin` · **`org_marketing`** *(org grain)* · `venue_manager` · **`venue_marketing`** *(venue grain)* |
  | **`operations_v1`** | `audience_v1` **+ MONEY**, with the purchaser view appended as a second section | `org_owner` · `org_admin` · `venue_manager` **only** |

  **Marketing gains the audience template and never the money one.** The plane of the grant is the export scope: `org_marketing` exports across all of the org's venues; `venue_marketing` exports its own venue only.

  **Explicitly denied, every one:** `venue_scanner` · a door session · **`venue_box_office`** · **`venue_promoter_manager`** · **`org_promoter_manager`** · `venue_finance` · `org_finance` · `org_member` · promoters · **`platform_support`** · `fan` · `anon`.

  **Platform roles (CRM K-3):** `platform_risk` and `platform_admin` **read** the roster (§9.3) but the venue export surface **does not render for them** — a platform bulk extraction has a different justification, a different retention and needs dual control, and running it through a venue's own surface would file a platform action in that venue's history and give a compromised platform account the *venue's* rate limits rather than a platform-grade one. **Platform bulk extraction is not built in Phase 2.**
- **Phone is never exportable.** Not as a column, not as a filter, not as a hash.
- **Email only where a per-order, per-org opt-in was given.** Non-opted rows export an empty email cell, and the UI **explains why** rather than leaving it blank: an inline legend — *"Email is blank when the buyer didn't agree to share it with this organization."* — plus a count of suppressed cells in the export summary.
- **The name column is gated on the SAME consent test as email (`SPEC CORRECTION`, CRM K-18 / §4.3).** In an **export**, `display_name` is emitted **only where a contact relationship exists** and is **blank otherwise**. The rule is one predicate — `emit_name := emit_email` — evaluated once per holder row and driving **both** cells, so the two can never disagree and nobody can gate one and forget the other.

  **The suppression legend must therefore cover the name column too**, and the export summary carries a second counter pair:
  > *"Name is blank for people who haven't agreed to share their details with this organization. They're still on your roster on screen."*

  **Why the name column, which the venue can already read on screen, is gated in a file.** `display_name` came from the one global `public.profiles.display_name` string — **the same value for the same person at every organization on the platform** — and it was emitted on every row of every export, ungated. It was **the join key**: two orgs union their CSVs on the name column in one step and corroborate with admission time, `first_seen_at`, ticket type and acquisition route. The `customer_ref` pseudonym removes the platform-supplied *stable* join key **and nothing else**, so gating email while shipping the name defeated the pseudonym on every row.

  **The gate is on the egress, not on the knowledge.** `display_name` stays **ungated on screen** (§9.1/§9.3), in the single-record lookup (§12.6), and in the door verification projection — after 068 it is one of the columns any authenticated principal may read, **and a screen cannot be unioned with another org's screen.** A CSV can. The room still gets run; what changes is what leaves in a file.

  **Operator cost, stated rather than hidden:** an `audience_v1` export over a heavily transferred session is mostly `customer_ref` and ops columns with **name and email blank on the same rows**, and an `operations_v1` file identifies rows by `customer_ref` + `order_ref` rather than by name. That is **owner decision D-13** in the CRM spec, recommended as written; it is not a setting this surface may soften.
- **Filters are the same closed enumerated set as §9.2.** No SQL box. No arbitrary column picker. The column set is fixed per export type.
- **Revoke** is available on any `ready` export and takes effect immediately.
- **Availability:** `lg`+ only (§3.3).

- **Never exportable, in addition to phone:** any global identity uuid · legal name · any payment identifier · credential/custody internals · door internals · the transfer counterparty · another org's data · **and every demographic object.** A demographic value may not even be an export **filter** — *"export attendees where gender = X"* is individual-level disclosure by construction even when the column is absent, because **the row set is the disclosure.** The closed filter set must never gain a demographic member, a proxy ("shared demographics: yes/no"), or a derived row order.
- **No third-party destination, ever.** No emailed CSV, no webhook, no CDP sync, no ESP property, no ad-platform audience upload, no pixel parameter, no warehouse sync. Composition informs creative; it does not move data.
- **Retention, and the honest limit of the signed URL.** The artifact is swept **24 hours** after `ready`, or immediately on revoke; the job row is kept 13 months and **contains no customer rows**; audit rows are permanent. Say this on the surface, because *a 300-second signed URL bounds the window in which the **link** is redeemable and buys nothing whatever about the **data**.* **Anyone who describes a signed URL as a privacy control for exported data is describing a promise as a control.** The real controls are the 24-hour sweep, the size cap, the per-actor daily cap, and revoke.
- **Audit — and the one number that proves the consent gate ran.** Every request, generate, download, revoke, expire, purge, fail **and denial** writes `kernel.admin_audit` in the same transaction. A **refused** export attempt is more interesting than a successful one; an audit that records only successes cannot show an attacker probing scopes. Each row carries scope, template + version, normalized filters, `as_of`, row and byte counts, the artifact hash, the constraint-set version, and **`contact_cells_emitted` / `contact_cells_suppressed`** **plus `name_cells_emitted` / `name_cells_suppressed`** (CRM K-18) — the only evidence the consent gate ran, on **both** gated columns. Four integers, and they are the whole audit trail of the gate. **Never in an audit row:** a customer row, a name, an email, a `customer_ref`, a probed email value, or any signed URL.
- **The audit lives where the venue cannot reach it.** `kernel.admin_audit` is platform-read-only, and that is the point: the actor most likely to want an export record gone is the venue.

The former `UNVERIFIED:` is **discharged** — the export job table, its lifecycle, the opt-in record, the `crm-export` edge function and fifteen RPC contracts are specified. **Package `087`.**

### 9.7 States

| State | Copy / behaviour |
|---|---|
| Loading | Table skeleton, filters interactive immediately. |
| Empty (no sales) | *"No tickets sold for this session yet."* |
| Empty (filtered) | *"No attendees match these filters."* + Clear filters. **Distinct from no-sales** — collapsing them makes an operator think the event failed. |
| Error | Retry; filters preserved. |
| Permission-denied | Standard denial; for `venue_scanner`, the denial names the alternative: *"Door access uses ticket lookup, not the attendee list."* with a link to §12.6. |
| Partial | Attribution or check-in column fails → that column shows *"—"* with a hover explanation; the list still renders. |

---

## 10. (E) Promoters

Scope: org and venue level, plus an event-scoped view inside the event tabs.

### 10.1 The two-tier wall (structural, not a toggle)

Promoters **do not use this dashboard.** They use a separate promoter portal showing their own links, codes, attributed sales, commission, and payout — and nothing else (domain §1.7; RLS §9.17 note 40). Promoters never see buyer PII, other promoters' data, the venue back office, or aggregate finance. This dashboard's promoter section is the **venue's view of promoters**; the portal is the promoter's view of themselves. Two surfaces, one attribution ledger.

### 10.2 Promoter list

Columns: name · status (`active` | `inactive`, schema §3.17) · commission_bps · terms_version · links · codes · tickets attributed · gross attributed · commission accrued.
Write authority: `org_owner`/`org_admin`/`venue_manager` (RLS §9.17).

### 10.3 Invite / assign a promoter

Creates a `venue.promoter` row for (identity, org, optional event) with `commission_bps` and `terms_version`. Commission terms are **versioned** — changing them creates a new terms version and the surface shows which version each attribution was earned under, because a commission dispute is always about which terms were in force.

### 10.4 Links

`venue.promoter_link`: `slug` is **globally unique** and the link row is **immutable once created** (schema §3.17). The UI therefore:
- Offers **create** and **status change**, never "edit slug".
- Runs a live availability check on the slug before enabling create.
- States the permanence before create: *"A link's address can't be changed once it exists. You can switch it off, but the address is permanent."*

### 10.5 Codes (Agent C, binding)

- **Globally unique; eligibility is event-scoped.** The issuing form checks availability **live** against the global namespace, and separately shows which events the code is eligible for.
- **Confusable warning.** Before issuing, the form warns on visually confusable strings — **`J0RDY` is the same code as `JORDY`** — and requires an explicit acknowledgement. The warning shows the colliding form, not a generic message.
- **No reassignment.** There is **no UI affordance anywhere** to move a code from one person to another. Not a disabled button, not a hidden menu item, not an admin escape hatch. The RPC rejects it, and this surface does not offer it. Where an operator asks for it, the answer on screen is: *"Codes belong to the person they were issued to. Switch this one off and issue a new one."*
- **Three independent switches, each preserving history:**
  1. **Promoter status** — `active` / `inactive` on the person.
  2. **Link status** — on the link.
  3. **Code status** — on the code.
  Turning any of the three off **never deletes attribution already earned** and never rewrites history. The UI states the scope of each switch before confirming, because "switch off the promoter" and "switch off one code" are different acts an operator will confuse.

- **Bulk issue** is supported (capped per call), and its download rides the **audited export path** — not a browser-side CSV.
- **Settlement close warning.** When flagged commissions are unreviewed, the close dialog says so:
  > *"N flagged commissions have not been reviewed. Closing now will not pay them; they will roll to the next settlement."*

The former `UNVERIFIED:` is **discharged** — `venue.promoter_code` and `venue.promoter_code_scope` are specified with a **globally unique normalized code** (a stored generated column folding the confusable alphabet), event-scoped eligibility, an immutability guard on promoter/code/kind, and status columns. **Package `090`.** The confusable warning is backed by a real collision list, not a heuristic in the client.

**Who may issue and manage codes:** `venue_manager`, `org_owner`, `org_admin` — **and now also `venue_promoter_manager` / `org_promoter_manager`**, which is the label the O-2 ruling created for exactly this job (§5.1). **Neither promoter-manager label may adjudicate a self-deal flag** (§10.7) — the person who recruits the promoter does not decide that promoter's disputed commission.

### 10.6 Attribution view (must be sufficient to defend a dispute without engineering)

One row per attributed order. Columns:
`when` · `order ref` · `ticket type` · `qty` · `gross attributed` · `commission` · **`method` (link | code)** · **`touch_corroborated`** · **`self_deal_flag`** · terms version.

Design requirement from Agent C: this view alone must settle a commission argument. That means:
- `method` is always shown, never inferred from context.
- `touch_corroborated` renders as an explicit yes/no with a one-line plain explanation on hover, not a raw boolean chip.
- `self_deal_flag` renders as a visible flag with its reason, and flagged rows remain in the list (never hidden).
- The row is exportable **only** through the audited export path (§9.6) and only for roles on that allow-list.
- **No buyer PII appears in this view** — the promoter dimension never becomes a back door into the attendee list.

`venue.attribution` is **append-only** with `UNIQUE(order_id)` (schema §3.17), so the view is a straight read; nothing here is editable.

`UNVERIFIED:` `touch_corroborated` and `self_deal_flag` are not columns in schema §3.17 as written — they are Agent C's delta.

### 10.7 Self-deal flag queue

Rows where `self_deal_flag` is set. Actions: **Release** (credit the commission) or **Deny** (do not credit), each requiring a reason code. Both outcomes stay visible in the queue's history — a denied flag is not removed, it is resolved.
Reviewers: `org_owner`, `org_admin`, `venue_manager` (and `platform_risk` from the internal admin plane).
Copy for the operator: *"A promoter buying for their own guests is normal. This flag is for you to look at, not an accusation."* (domain §1.7 — self-purchases are flagged to the venue, not silently blocked.)

**Reviewers — corrected.** `org_owner`, `org_admin`, `venue_manager` (and `platform_risk` from the internal admin plane). **`venue_promoter_manager` and `org_promoter_manager` are explicitly denied**, on separation-of-duties grounds: they create promoters, links and codes, so they must not adjudicate a flagged commission on one.

**§22.4 RESOLVED.** Attribution is append-only, so Release/Deny is **not** a mutation of the attribution row — it is an **append-only decision ledger alongside it** (`venue.attribution_review`, unique on `(attribution_id, seq)`, effective decision = the highest `seq`), written by `venue.review_attribution_flag`. **§21.4's Δ4 is satisfied.** A denied flag is resolved, never removed, and a decision can be superseded without rewriting history — which is what a commission dispute actually needs.

### 10.8 Performance

Per promoter, per event: tickets attributed · gross attributed · commission accrued · commission paid (from `kernel.payout` cause `promoter_commission`, schema §1.9). Ranked list, no charts beyond a bar per row.
**Not here:** click counts, link CTR, conversion rate, time-to-purchase. Those are Phase-3 analytics and none of them have a home in the frozen schema.

### 10.9 States

Loading: skeleton · Empty: *"No promoters yet."* / *"No attributed sales yet."* / *"No flags to review."* (three distinct empties) · Error: retry · Denied: standard · Partial: commission-paid column unavailable renders *"—"*, never zero (a zero here reads as "we didn't pay you").

---

## 11. (F) Guest list & comps

### 11.1 The distinction that must be on screen

A **guest-list entry is a name, not a ticket.** It has no Entry Pass until it is converted into a comp admission, which draws real capacity from a `comp` release (domain §1.6, A4). This is the single most common door confusion in nightlife, and the surface must state it, not assume it:
> *"A name on the guest list isn't a ticket. Give them a comp if they need one that scans."*

### 11.2 Guest lists

Per session. A list header (`venue.guest_list`: name, created_by) with entries (`venue.guest_entry`: `guest_name`, `party_size`, `status` ∈ `pending` · `arrived` · `no_show`, `checked_in_at`) — schema §3.16.
Actions: create list · add guest (single; paste-many at `lg`+) · remove entry (via the parent list RPC only — **no client delete anywhere**, GP-2) · mark arrived.
`INFERENCE:` "Maya's list" (domain §1.6, a promoter's list) is expressed in MVP through the list `name` plus `created_by`; there is no promoter FK on `venue.guest_list` (schema §3.16). → delta §21.9 (low priority).

### 11.3 Comp allocation

`venue.comp_allocation` (schema §3.15): granted to an identity or a name, quantity, `status` ∈ `allocated` · `issued` · `revoked`, `granted_by`.
Flow: **Allocate** (`venue.allocate_comp`) → **Issue** (`venue.issue_comp`, which routes through `kernel.issue_ticket_atoms` with cause `comp`).

**Hard requirements on this surface:**
- The comp batch's `remaining` is shown **before** the quantity field, and allocation is refused when the batch is exhausted. Comps never bypass capacity (A4) and the UI must never let an operator believe otherwise.
- Beyond a per-staff threshold, issuance requires **step-up + live grant re-check + reason code** (C39, domain §7.5). The UI presents the step-up as a normal part of the flow, not an error.
- Copy: *"Comps come out of your room's capacity. They're free to the guest, not free to the night."*

### 11.4 Comp accountability

Per event: comps by staff member (granted_by), quantity, status, and the running total against the comp release capacity. Per-staff totals are visible to `venue_manager` and above — this is the insider-fraud control surface, and hiding it defeats it.

### 11.5 Door state

Guest entries show live `status` and `checked_in_at`. Door staff (`venue_scanner`) may update **only** `status` and `checked_in_at`, and **only** for their session (RLS §9.16 note 39). They cannot add, remove, or rename a guest.

### 11.6 States

Loading: list skeleton · Empty (no list): *"No guest list for this session yet."* · Empty (list exists, no entries): *"No guests added yet."* · Empty (filtered to not-arrived, all arrived): *"Everyone on the list has arrived."* · Error: retry; check-in toggles disabled while the write path is unhealthy (never optimistic — a false "arrived" at the door is a real-world failure) · Denied: standard · Comp batch exhausted: allocation blocked with the remaining count named.

---

## 12. (G) Door operations

### 12.1 What this surface is and is not

This is the **venue's view of the door**, on the web. The scanning itself happens in the dedicated scanner surface (RN §7). This surface configures the door, watches it, and reconciles it. **It never goes offline** and never queues a write (§2.9).

### 12.2 Door staff and PINs

- **Staff:** who holds `venue_scanner` at this venue (`venue.staff_role`, schema §3.9).
- **PINs** (`venue.door_pin`, schema §3.10): label ("Main door iPad"), session, `expires_at`, `status` (`active` | `revoked`).
- **Issue** → `venue.create_door_pin` (RPC §9.1). The RPC stores only `pin_hash` and **never returns it** (RLS §9.10 note 32). Therefore the plaintext PIN is displayed **exactly once**, at creation, with:
  > *"Write this down now. We can't show it again — we don't keep a copy you can read."*
  A "resend PIN" affordance must not exist; it would be a lie.
- **Revoke** → `venue.revoke_door_pin` (RPC §9.2). One tap, confirm, immediate.
- PINs are event/session-scoped and expiring **by design** — that weakness is the security model (domain §1.8: blast radius = one event, one night). The surface says so rather than letting an operator ask for a permanent PIN.
- **A door PIN can never authorize a refund** (C46, domain §1.8). No refund control appears on any door surface, for any principal, ever.

### 12.3 Devices

`venue.scan_device` (schema §3.11): label, `manifest_version`, `last_sync_at`, `status` (`active` | `retired`).
Register → `venue.register_scan_device` (RLS §11). Door staff can sync their own device only (RLS §9.11 note 33).
Status board per device: **online / offline** · **manifest age** (from `last_sync_at`) · **offline queue depth** (device-reported) · last scan time.
Manifest staleness is rendered as a duration with a threshold chip, not a raw version number — *"Synced 4 minutes ago"* not *"manifest_version 17"*.

### 12.4 Manifest status — and the transfer freeze

The session's **door manifest open** state is `catalog.event_session.door_open_at` (schema §2.3), and it is the **canonical door-freeze signal**: once open, native transfers and resale for that session's tickets are frozen, enforced by `kernel.is_transfer_frozen` re-checked under lock in every custody RPC.

**Scope — say what the mechanism does (`SPEC CORRECTION`).** The freeze is **session-wide, monotone and terminal**. Once the first episode opens, **every** ticket of that session is frozen from that instant **forever**, and **closing an episode does not clear it**. There is also an **implicit backstop**: the freeze engages at doors time even if nobody ever opens a manifest — `effective_freeze_at = LEAST(door_open_at, COALESCE(doors_at, starts_at) + configured offset)`. **It is not "narrowed per-open-manifest-ticket per C43"** — that narrowing is `RATIFIED-MODELED-ONLY(GATE-M)`, not MVP, and door §16 OQ-4 records that four documents describe a narrowing nothing implements. This surface must not imply that opening the manifest freezes only the tickets inside it. → §22.11.

The dashboard must state the consequence **before** the operator opens it, in operator words:
> *"Opening the door manifest stops ticket holders sending or reselling tickets for this session. Do it when doors open."*

**Blast radius before the confirm enables** (principle 7): the real counts of pending transfers and active listings that will be cancelled by the drain. **`INFERENCE`/gap:** the open RPC returns the drained counts *after the fact*; **no dry-run read is specified**. Until one exists, this confirm shows the counts it can compute from what it can read and says so. → §21.11.

After opening, the session card everywhere in the dashboard shows **"Door open — transfers closed."** After closing: **"Doors closed — transfers remain closed."** — because they do, and an operator who reads "closed" as "reopened" will tell a fan the wrong thing.

**Freeze status card (NEW).** Shows `effective_freeze_at` **and which input produced it** — the explicit manifest open, or the implicit doors-time backstop. Without that second half, an operator whose transfers froze at 21:30 with no manifest open has no way to learn why.

**Episode history (NEW).** The session's manifest episodes: opened/closed times, who, reason code, entry count, admitted count. A re-open creates a **new episode and a fresh snapshot** and explicitly **does not move `door_open_at`** — the freeze is monotone precisely so that transfers cannot resume between episodes.

**GAP CLOSED — the manifest is now operable.** §21.1's Δ1 is satisfied: `venue.open_door_manifest` / `venue.close_door_manifest` are contracted (door §7.1/§7.2), audited, idempotent on the session's current state, and reason-coded on close.

**Authority — `SPEC CORRECTION` to Δ1, and §22.7 is now resolved.** Δ1 proposed `has_venue_role([venue_manager, venue_door])`. **Ruling O-4 removes the door principal.** The correct role set is:

> `has_venue_role(venue, [venue_manager])` **OR** `has_org_role_over_venue(venue, [org_owner, org_admin])` **OR** `is_platform([platform_admin])`.
> **`venue_scanner` and every `door_pin` principal are excluded.**

§22.7 inferred the door principal was the operationally correct actor and declined to settle it. **The ruling went the other way, and the reasoning is worth keeping:** opening the manifest freezes custody for the whole session, which is a security boundary, and **the scanner may not create the security boundary it scans against.** The operational objection — a manager is often not at the door at 11 p.m. — is real and is answered by **scheduling** (`door_open_at` is set in advance) plus **remote action** (this dashboard is an online surface reachable from anywhere), **not** by a weaker credential at the door. This is also why the label became `venue_scanner`: it now asserts authority over *scanning*, which is what O-4 grants, rather than over *the door*, which is what O-4 denies.

**Consequently there is no Open control in the scanner at all** — **absent, not disabled**, so a door operator never learns it exists (RN §7.3).

**Override is not on this surface.** Break-glass freeze overrides are `platform_admin`-only and live in the internal admin plane. No venue role may reach one, and no venue surface may hint that one exists.

**Residual over-provisioning, flagged.** O-4 says box office does not inherit manifest administration — but a box-office seller granted `venue_box_office` now has a real label, while any legacy box-office user still holding `venue_manager` **does** get manifest open/close. → §22.12.

### 12.5 Live scan board

Per live session, live counters from `venue.scan` (schema §3.12):
**Admitted** · **Duplicate** · **Invalid** · **Frozen** · **Fraud review** — the exact `result` enum, with operator labels: Admitted · Already used · Not recognised · Blocked (door manifest) · Needs review.
Plus: **admitted / issued**, arrivals per 5 minutes (a bar, the only chart here), last scan time, and per-device contribution.

**Door reject reasons (Agent A, binding)** — the **six** reasons a pass is refused, each with its operator copy. **`SPEC CORRECTION` (door §9.2): this table and its surrounding prose said *five*. `refund_hold` is the sixth.**

| Reason (Agent A) | Pre-check `reason` (RPC §9.3) | Recorded `result` (schema §3.12) | Operator copy |
|---|---|---|---|
| `version_stale` | `version_stale` | `invalid` | *"This pass is out of date. Ask them to open the Snatch It app."* |
| `voided` | `voided` | `invalid` | *"This ticket was refunded or cancelled."* |
| `listed_locked` | `listed_locked` | `invalid` | *"This ticket is listed for resale or mid-transfer."* |
| **`refund_hold`** | **`refund_hold`** — **owed by the RPC integrator; see below** | `invalid` | ***"A refund is being reviewed on this ticket, so it can't be used yet. If they don't want the refund, it has to be cancelled in the Snatch It app — then this ticket works again."*** |
| `duplicate` | `already_scanned` | `duplicate` | *"Already used"* + the first-admit time. |
| `wrong_session` | `wrong_session` | `invalid` | *"Right event, wrong night."* + the correct session. |

> **Why a sixth reason and not a reuse of `listed_locked` (door §9.2).** MONEY §12 ADDITIVE-2 added a **fourth** overlay label, `refund_hold` (schema §1.5). Under the offline predicate's five-conjunct 3b a `refund_hold` atom is correctly **rejected** — but it was rejected with **no reason arm at all**, so door staff saw an unmapped refusal of a paying customer and had nothing to say and nothing to offer. Folding it into `listed_locked` would tell the holder their ticket is *"listed for resale or mid-transfer"*, which is **false**, and would send door staff hunting a listing that does not exist. (§9.2's earlier ruling on DL-5 refused new vocabulary because the existing five already carried every *meaning*; that argument does not hold here.)
>
> **`SPEC CORRECTION` owed elsewhere, and it must ship with this one.** `venue.validate_ticket_online`'s `reason` enum (RPC §9.3) is `active|already_scanned|listed_locked|voided|wrong_session|version_stale` and **must gain `refund_hold`** — filed to the RPC-contract owner. **Until it does, the ONLINE door has exactly the unmapped-refusal problem the offline door just fixed:** it refuses a `refund_hold` atom with no reason to render.

**Wallet staleness (Agent A):** every door surface carries the standing note *"A pass shown from a wallet can be out of date. The Snatch It app screen is the one that counts."* — it appears on the manual-lookup result and beside the `version_stale` reason, not buried in help.

**Naming reconciliation (not a conflict):** `venue.validate_ticket_online` returns `already_scanned` as its pre-check reason (RPC §9.3) while the recorded `venue.scan.result` enum uses `duplicate` (schema §3.12). Agent A's vocabulary is `duplicate`. The dashboard uses `duplicate` in copy and maps both backend values to it. Flagged in §22.5 so the RPC and schema authors can align the label if they want to.

### 12.6 Manual lookup

Search by guest name, order ref, or ticket ref → **one record** with its admit/deny reason, ticket type, session, and check-in history.
This is **the door's only attendee read** (§9.3). It returns single records; it has no list mode, no pagination, no export, and no empty-query "show all".
Backed by `venue.validate_ticket_online` (RPC §9.3) for the admissibility answer — a read that does **not** record admission — plus the scoped attendee read for the identifying detail.

### 12.7 Reconciliation and the flag queue

- **Reconciliation:** offline batches ingested per device (`venue.reconcile_offline_scans`, RPC §9.5), with counts of `admitted` / `duplicates` / `conflicts`, plus scans still `offline_pending`.
- **Flag queue:** rows with `fraud_flag` or `result IN (duplicate, fraud_review)`.
- **The venue can see and escalate. The venue cannot resolve.** Only `platform_risk`/`platform_admin` hold the fraud-review write path on `venue.scan` (RLS §9.12). The surface says so:
  > *"Snatch It reviews these. Add what you saw at the door and we'll pick it up."*
  and offers **Escalate with a note**, not "Resolve". Building a Resolve button here would be a control the RLS spec will reject at runtime.

### 12.8 Offline

The dashboard reports device offline state; it is not itself offline-capable. When the *browser* is offline, the door page shows the standard offline banner and stamps the counters with their last-loaded time — because a stale admitted count read as live is an operational error.

### 12.9 States

| Surface | Loading | Empty | Error | Denied | Notable |
|---|---|---|---|---|---|
| PINs | skeleton | *"No PINs for this session."* | retry | standard | Plaintext shown once; no resend. |
| Devices | skeleton | *"No devices registered."* | retry | standard | Offline device ≠ error. |
| Manifest | skeleton | n/a | retry | standard | Read-only until §21.1 lands. |
| Scan board | skeleton | *"No scans yet — doors haven't opened."* | retry; counters marked stale, never zeroed | standard | Counters never optimistic. |
| Manual lookup | inline spinner | *"No ticket matches that."* | retry | standard | Single record only. |
| Flag queue | skeleton | *"Nothing flagged."* | retry | standard | Escalate, never Resolve. |

---

## 13. (H) Refunds

### 13.1 Orders list

Per event/session or venue-wide. Columns: buyer · total · status · items · refunded to date · payment ref.
**Reads:** `venue.order` (RLS §9.7), `venue.order_item` (RLS §9.8).

### 13.2 Eligibility

An order is refundable when `status ∈ {paid, partially_refunded}` and the requested amount keeps `sum(refunds) ≤ payment.total` — re-validated server-side under `FOR UPDATE` on the payment (RPC §11.4). The UI shows the **maximum refundable amount**, computed from what it can read, and treats the server as the authority: an amount the UI thinks is fine but the server rejects renders as a plain `precondition_failed` message, not a crash.

### 13.3 Authority — **RESOLVED by ruling O-1** (was §22.1)

**`org_owner` and `org_finance` may initiate a refund.** `venue_manager` and `venue_finance` still cannot.

> **Corrected copy (replaces the previous two sentences):**
> *"Refunds are initiated by your organization's owner or finance role. Venue managers can see orders and refunds but cannot issue them — ask your org owner or finance lead, or ask Snatch It support."*

The refund control keeps its **permission-explained** state for `venue_manager`/`venue_finance` rather than going invisible — this spec was right that invisibility here produces support tickets.

**How the conflict was resolved, because the mechanism matters more than the outcome.** §22.1 flagged that domain prose gave Org Owner refund authority while the RLS EXEC row named only `org_finance`, and followed RLS. **This spec was right about the mechanism and wrong about the outcome.** `kernel.org_member.role` is single-valued, so no `org_owner` row can ever satisfy `has_org_role([org_finance])` — *"Inherits: Org Finance"* was prose, not a predicate. **O-1's fix moves the authority explicitly and deletes the inheritance mechanism** rather than reinterpreting it: every money authority the owner holds is now granted to the `org_owner` label by name, never derived. **Nothing in this product should ever rely on role inheritance for a money action.**

**`org_admin` is denied the money plane.** `INFERENCE`, and flagged as such by the money spec: O-1 and O-3 name `org_owner` and `org_finance` and are **silent on `org_admin`**. → §22.13.

### 13.3a Authority is tiered, not blanket — and the operator must learn the tier from the product

There is **one** org-facing entry point and **more than one possible outcome, and the caller does not choose which**: within window and cap the refund executes; above it, a second approver from the org is required; beyond the org's ceiling it goes to platform review. **Therefore §13.4 must disclose the tier before the confirm** (below). An operator who discovers the threshold from a rejection has been taught it by failure.

### 13.4 Initiating a refund

Fields: amount (full or partial, pre-filled full) · **reason code** · confirmation.
Reason codes offered on this surface: **`buyer_request`** and **`oversell_correction`** only. `event_cancelled` is produced by `catalog.cancel_event` (§7.8); `dispute`, `admin_action`, and `auto_compensation` are platform/system causes (schema §1.10) and must not be selectable by a venue.
Above the configured threshold: **step-up + dual control** (domain §7.5). The UI presents dual control as a **pending-approval state**, not a failure: *"Sent for a second approval."*

**Tier disclosure, mandatory, before the confirm enables** (§13.3a). Exactly one of:
> *"This refund executes immediately."* / *"This needs a second approver from your team."* / *"This goes to Snatch It for review."*

**Pre-confirm, mandatory:**
> *"This will stop their ticket working at the door."*
Because a refund voids the covered tickets in the same transaction (`kernel.void_ticket_atom`, cause `refund_void` — RPC §11.4), and the Entry Pass stops working immediately.

**Second pre-confirm, mandatory, for a refund that will be parked rather than executed:**
> *"While this is waiting for approval, the ticket will not scan at the door."*

A parked request puts the ticket in a hold state, and that consequence must be stated **before** the operator parks it — not discovered at 11 p.m. by a fan at the door. The holder's app says the same thing on their ticket and their Entry Pass (RN §4.10), so the two sides of the conversation agree.

**Third case, previously unhandled: the ticket was already scanned.** As contracted before this integration, a refund touching a scanned atom raised `precondition_failed` and **failed the entire refund, including its money leg**, with no explanation anywhere and no warning on this surface. Corrected copy:
> *"This ticket was already scanned — we can refund the money, but the ticket stays used and the seat does not come back."*

### 13.5 Status and the void state

- **Refund status:** `pending` · `submitted` · `succeeded` · `failed` (schema §1.10). The Stripe reversal executes **edge-side** (RPC §13), so the UI polls and shows a progress state — it must never declare "Refunded" on RPC return.
- **Ticket state:** the covered tickets become **`voided`**. There is **no `refunded` ticket state** (D2). The attendee row's refund column therefore reads *"Refunded"* for the order and *"Voided"* for the ticket, and the two are not the same word by accident.
- **Inventory:** the void returns capacity to the batch (`void_return`, RPC §11.4) — the inventory surface reflects it without any operator action.

### 13.6 States

Loading · Empty: *"No orders yet."* / *"No refunds for this event."* · Error: retry; failed refund shows the failure with the reason and a re-initiate path · **Permission-explained** (§13.3) · Pending dual approval · **Parked (awaiting approval) — with the ticket-won't-scan consequence shown, not implied** · **Already-scanned** (money refundable, seat not returned) · Partial: an order whose payment link fails to resolve shows *"Couldn't load payment detail"* and disables refund rather than guessing.

### 13.7 Refund approval queue — `NEW DASHBOARD SURFACE` (money spec §10.1)

**The second approver's inbox.** Refunds above the immediate-execution tier are parked and must be approved by a **different** principal — separation of duties is enforced in the RPC (`approver ≠ requester`), not merely asked for in the UI.

- **Who:** `org_owner`, `org_finance`. Not `org_admin`, not any venue role.
- **Rows:** order, amount, reason code, requester, requested at, the ticket(s) held, and **how long the ticket has been unable to scan.** That last column is the one that makes the queue get worked.
- **Actions:** Approve · Deny (reason code required). Both audited; both leave the request visible in history.
- **The UI must not offer Approve on your own request.** The control is absent on a row you requested — the server refuses it either way, but discovering SoD from an error is a poor way to learn it.
- **Backed by** `kernel.list_approval_requests(p_org_id, p_filters)` (read) and `kernel.approve_refund_request` (write).
- **Empty:** *"Nothing waiting for approval."* **Never** collapse this with "no refunds".

---

## 14. (I) Settlement & payouts

**Scope: organization.** Settlement rolls up to the org because the org is the legal payee (domain §1.2). A venue-scoped settlement view exists for `venue_finance`/`venue_manager` (RLS §9.13 grants own-venue read), but the payout is the org's.

### 14.1 Settlement list

Per org: event or period · `status` (`open` · `closed` · `paid`) · gross · fees · refunds · net · currency.
**Reads:** `venue.settlement` (RLS §9.13).

### 14.2 Open a settlement

`venue.open_settlement` (RPC §10.1) — `org_owner`, `org_finance`, `venue_manager`, `venue_finance` (RLS §9.13 INS).
Fields: org, venue, event (optional), period start/end.

### 14.3 Settlement detail

Immutable lines (`venue.settlement_line`, AO — schema §3.14), one per cause, each linked to its source object. Causes come from the D3 registry (foundation §4): `primary_sale`, `market_sale`, `auction_sale`, `refund_void`, `promoter_commission`, `chargeback`, `settlement`, etc.
- **Resale royalty** appears as its own line, sourced from `market.market_sale` at close (RPC §10.2) — this is the "your sold-out event keeps earning" number (domain §1.9), and it is labelled as such.
- **The rounding-bearer line is marked** (`is_rounding_bearer`, schema §3.14, C31), because in a three-way split someone absorbs the residual cent and an operator reconciling to their bank needs to see which line it landed on.
- **Waterfall display:** gross → fees → refunds → royalties → commissions → **net**. Net is derived from lines, never typed.

### 14.4 Close a settlement

`kernel.close_settlement` (RPC §10.2) — **`org_finance` or `venue_finance` only** (RLS §9.13 UPD note 36; §11).
Close generates the payout(s), including the promoter-commission payout line. It is **irreversible** — lines are append-only and the header advances `open → closed`. The confirm dialog says so and shows the net figure that will be paid.
`org_owner` and `org_admin` can open and read but **not close**. Shown as permission-explained, not hidden.

### 14.5 Payouts

`kernel.payout` (schema §1.9): `status` ∈ `pending` · `submitted` · `paid` · `failed` · `reversed`; cause ∈ `settlement` · `promoter_commission` · `market_sale` · `refund_void`; `stripe_transfer_ref`.
- **Request disbursement** → `kernel.request_org_payout` (RPC §10.3) — `org_finance` or `org_owner`. Preconditions: settlement `closed`, payout `pending`, **destination not locked**.
- **Destination cool-down:** when `payout_destination_locked_until` is in the future (schema §1.2 — the cool-down after a bank change), the request is blocked. The UI **names the unlock time**: *"Payouts are paused until 14 Mar, 6:12 PM — that's the safety window after your bank details changed."* A greyed button with no explanation here is the difference between a calm operator and a support call.
- **Failed payout:** pinned, non-dismissible for `org_finance` and `org_owner` (Agent D routing), with the failure reason and the honest next step. `kernel.release_payout` is `platform_risk`/`platform_admin` only (RPC §11.3), so for a **held** payout the venue's action is *contact Snatch It*; for a **failed** payout the retry runs through the payout executor. The UI must distinguish held from failed — they look the same to an operator and have completely different remedies.
- **History:** all payouts for the org with cause, amount, status, and date.
- **Probation — the third hold state, and the reason it needs its own copy.** The first payout after a bank change is reviewed:
  > *"Your first payout after a bank change is reviewed by Snatch It. This usually takes under a business day."*

  Without this, a probation hold is **indistinguishable from a risk hold** and generates exactly the support call §14.5 exists to prevent. **Three states, three remedies: held (contact Snatch It) · failed (retry runs through the payout executor) · on probation (wait, nothing to do).** They must never render as one pill.
- **§22.3 RESOLVED (ruling O-3).** `org_owner` could previously fire a disbursement whose status it had no contracted path to read. **`kernel.list_org_payouts(p_org_id, p_filters)` is now contracted and names `org_owner`** — so rows 5 and 40's `○` is confirmed rather than provisional, and Δ3's payout read is satisfied. `venue_finance` gets a scoped `◐`: settlement-cause rows for its own venue only. The read returns **`stripe_transfer_ref` as a presence boolean, not the reference itself**, for org roles.
- **Separation of duties is structural, not advisory.** `kernel.request_org_payout` refuses when the caller is the principal who set the current payout destination — **permanently, for that destination.** The UI shows this as a named state ("someone else on your team needs to request this payout"), never as a generic failure. This is the canonical redirect-then-release fraud primitive, and the refusal is the control.

**No reserve, no clawback, no instant payout in MVP** (Gate M, C29/C31, schema §1.11). No surface may imply an instant-payout capability.

### 14.6 States

| State | Behaviour |
|---|---|
| Loading | Skeleton per section; lines load after header. |
| Empty | *"No settlements yet. Open one when an event is finished."* / *"No payouts yet."* |
| Error | Retry. A settlement whose lines fail to load shows the header and blocks Close — never close a settlement whose lines you cannot see. |
| Permission-denied | Standard; Close is permission-explained for `org_owner`/`org_admin`. |
| Blocked (cool-down) | Named unlock time (§14.5). |
| Failed payout | Pinned banner, non-dismissible for finance + owner. |
| Held payout | Distinct from failed; "contact Snatch It" path. |
| Partial | A missing royalty source renders the line as *"Couldn't load"* and blocks Close. |

---

## 15. (J) Staff & permissions

**Two rosters, never merged** (§4.2, C36).

### 15.1 Organization members

`kernel.org_member` (schema §1.3): role ∈ `org_owner` · `org_admin` · `org_finance` · `org_member`; `granted_by`.
- **Read:** any org member sees the roster (RLS §7.3).
- **Invite** → `kernel.invite_org_member` → `kernel.org_invite` (schema §1.3b): `invitee_ref`, role, `expires_at`. Statuses: `pending` · `accepted` · `declined` · `expired` · `revoked`. One open invite per invitee per org.
  - `org_admin` **cannot invite at `org_owner` tier** (RLS §7.3b) — the role selector omits it, and the server enforces it.
- **Change role** / **Remove** → `kernel.grant_org_role` / `kernel.revoke_org_role`.
- **Guards the UI must render, not just obey:**
  - **≥1 `org_owner` at all times** — removing the last owner is refused: *"An organization always needs at least one owner."*
  - **No self-grant** (I-11) — a person cannot raise their own tier. The control is absent on your own row.
  - Every grant/revoke is audited and appears in §17.

### 15.2 Venue staff

`venue.staff_role`: role ∈ **`venue_manager` · `venue_finance` · `venue_box_office` · `venue_marketing` · `venue_promoter_manager` · `venue_scanner`** — six labels as of ratified **O-2** (was four: `venue_door` renamed to `venue_scanner`, `venue_promoter` **removed**). PK `(venue_id, identity_id, role)` — **a person may hold several venue roles**, so the UI is a multi-select of roles per person, not a single-role dropdown. The six-label set makes that multi-select *more* right, not less: "sells at the box office and scans at the door" is now two real labels instead of one over-provisioned `venue_manager`.

**Org roles are likewise six:** `org_owner` · `org_admin` · `org_finance` · **`org_marketing`** · **`org_promoter_manager`** · `org_member`. The two rosters stay separate (§4.2); the pickers stay plane-specific; the tier guards are unchanged.

**`venue_promoter` must not appear in any picker, grant, or predicate.** A promoter is a `promoter_link` row-ownership relationship, not a staff role — the authority is `venue.promoter.identity_id = auth.uid()` on a live row, and it is exercised in the promoter portal, never here.
Grant/revoke → `venue.grant_staff_role` / `venue.revoke_staff_role` (RLS §9.9; §11): `venue_manager`, or `org_owner`/`org_admin` by inheritance. **No self-grant.**
Read: every venue staff member sees their own venue's roster (RLS §9.9).

### 15.3 Scope: what MVP does not have

Domain §7.3 requires **event-scoped grants that auto-expire** for temp staff hired at 9 p.m. The physical `venue.staff_role` has **no `event_id` and no `expires_at`** (schema §3.9). MVP's answer is the **door PIN** — session-scoped, expiring, revocable, loginless (domain §1.8) — which is the intended mechanism for exactly that person anyway. The Staff surface states it:
> *"For one-night door staff, issue a door PIN instead of a staff role. PINs expire on their own."*
→ delta §21.8 for the general case.

Likewise `scan_scopes` (per-ticket-type door narrowing, domain §7.3) is **not modeled** in schema §3.10/§3.11. A door PIN admits every ticket type for its session. No surface may imply a VIP-only door.

### 15.4 Finance permissions, written out

Because the finance split surprises people, the Staff page carries a short, factual capability panel:

| Capability | Who |
|---|---|
| Open a settlement | `org_owner`, `org_finance`, `venue_manager`, `venue_finance` |
| Close a settlement (creates the payout) | `org_finance`, `venue_finance` |
| Request a payout | `org_finance`, `org_owner` — **and never the person who set the current bank destination** |
| Change the payout bank destination | `org_owner` only (dual control + cool-down); `org_finance` **reads** it |
| **Initiate a refund** | **`org_owner`, `org_finance`** — corrected by ruling O-1 (§13.3) |
| **Approve a parked refund** | `org_owner`, `org_finance` — **and never the requester** (§13.7) |
| Change a ticket price | `venue_manager`, `org_owner`, `org_admin` |
| Allocate comp **capacity** | `venue_manager`, `org_owner`, `org_admin` (step-up above threshold) |
| Issue **one** comp against an allocated batch | the above **plus `venue_box_office`** (step-up above threshold) |
| Open / close the door manifest | `venue_manager`, `org_owner`, `org_admin` — **never `venue_scanner`, never a door PIN** (O-4, §12.4) |
| **Export the audience list** | `venue_manager`, `org_owner`, `org_admin`, `venue_marketing`, `org_marketing` |
| **Export the money list** | `venue_manager`, `org_owner`, `org_admin` **only** |

**Say the asymmetry out loud on this page, because it is the thing people get wrong:** **finance sees money and never contact; marketing sees contact and never money.** Only venue manager, org owner and org admin hold both.

### 15.5 States

Loading · Empty: *"You're the only member."* / *"No venue staff yet."* / *"No pending invites."* · Error: retry · Denied: standard · Guard-blocked: last-owner and self-grant refusals render as explanations, never as generic errors · Invite expired: shown in the list as `expired` with a re-invite action.

---

## 16. (K) Settings

### 16.1 Organization

`kernel.organization` (schema §1.2). Editable: `display_name` (and benign profile fields — `org_admin` per RLS §7.2). Read-only: `status` (`applied` · `approved` · `active` · `suspended` · `closed`, platform-set), `home_region`.
**Column-scoped:** `legal_name`, `stripe_connect_account_ref`, and the payout lock are visible only to `org_owner`/`org_finance`/platform (RLS §7.2 note 4). `org_member`/`org_admin` see `display_name` + `status` only — the UI must not render an empty field where the column is not granted; it renders **nothing**, because an empty box implies "unset" rather than "not yours to see".

### 16.2 Venue

`catalog.venue` (schema §2.1) via `catalog.update_venue` (RPC §3.3): `name`, `neighborhood`, `address`, `capacity_hint`.
`approval_status` (`draft` · `pending` · `approved` · `archived`) is **platform-set and read-only** here.
**`capacity_hint` must be labelled as informational**: *"Reference only — this doesn't limit sales. Sales capacity comes from each event's inventory."* (schema §2.1 says so explicitly, and an operator who thinks otherwise will oversell.)
Legal occupancy is a distinct attribute that MVP does **not** track (C46, domain §1.3) — no surface may present `capacity_hint` as a fire-code number.

### 16.3 Payout account

- Connect account shown **masked**.
- **Change destination** → `kernel.set_org_payout_destination` — **`org_owner` only**, step-up, dual-control seam (RLS §11).
- The consequence is stated **before** the change, not after:
  > *"Changing your bank details pauses payouts for a safety window. You'll see exactly when they resume."*
  (`payout_destination_locked_until`, schema §1.2; domain §7.4 SoD-1: the canonical fraud primitive is redirect-then-release.)
- SoD is visible: the same person cannot change the destination and approve a payout to it. The UI shows the pending-approval state rather than failing.

### 16.4 Branding

**Not in MVP.** No branding columns exist on `kernel.organization` or `catalog.venue` (schema §1.2, §2.1). The section renders a single honest line rather than a disabled uploader: *"Custom branding isn't available yet."* → optional delta §21.10.

### 16.5 Notification preferences (Agent D, binding)

- Conceptually per-`(user, venue)`. **MVP ships a single global toggle per user** — the surface says so: *"This applies to every venue you work at. Per-venue settings are coming."*
- **Never per-sale push to staff.** Sales arrive as a **daily digest**. The preferences copy states the cadence so nobody waits for a ping that will not come: *"Sales come as one daily summary, not one message per ticket."*
- **Low inventory fires once per (batch, threshold)** — matching the dashboard warning rule (§6.1 zone 6), so the banner and the alert never disagree.
- **Payout failure routes to finance and owner and is not opt-out.** It renders in the list as an always-on row with an explanation, not as a toggle that does nothing: *"Payout problems always reach your finance and owner contacts."*
- **Door anomaly goes to on-duty door staff only, and only while a session is live.** Shown as such.

- **Mandatory rows render as always-on with their reason as visible copy — never as a disabled switch.** A greyed toggle invites an operator to keep clicking it; a labelled always-on row explains itself once.

The former `UNVERIFIED:` is **discharged** — staff preferences are backed by `notify.get_preference_matrix()` / `notify.set_preference()`, owner-scoped, with the mandatory guard enforced in DDL rather than in a policy.

### 16.5a "Send an update" — the announcement composer — `NEW DASHBOARD SURFACE` (notifications §7)

The one place a venue can reach its ticket holders directly. It is deliberately hard to fire and impossible to unsend.

- **Who:** `venue_manager`, `org_owner`, `org_admin` (plus platform). Recipients never read the announcement object; they read their own notification row.
- **Blast radius before the confirm:** *a count only, never a recipient list.* The composer must not become a roster.
- **A hold window, and the copy that makes it usable:**
  > *"Once this sends, it can't be taken back from anyone's phone. You have 5 minutes to cancel."*
- **Cancel** during the hold window; **revoke** after (which removes it from the in-app centre and marks the row revoked — **never deleted**, with actor and reason). Neither un-rings a phone, and the copy must not pretend otherwise.
- Above a configured audience size, **dual control**.
- Recipients can **report** an announcement from their notification centre; the report count is visible here.
- **History** with state, actor, audience count, and reports.

### 16.6-pre. Escalation caveat

The composer is the highest-blast-radius non-money control in this product: it reaches every ticket holder for a session at once, and its blast radius is people, not rows.

### 16.6 CRM / export controls

Mirrors §9.6: who may export (the three-role allow-list), export history with status and audit trail, and **revoke** for any `ready` export. This is the only place an outstanding export can be killed, so it is not buried inside the attendee tab.

### 16.7 Venue-scope resale default

`catalog.set_resale_policy` with `scope_kind = 'venue'` (schema §2.5) — the default an event inherits. Same versioning rules as §7.7.

### 16.9 Re-authenticate for a money action — `NEW DASHBOARD SURFACE` (money spec §8.3)

Money-consequential actions (payout destination change, payout request, refund above the immediate tier, comp issuance above the per-staff threshold) require a **fresh** authentication assertion at the action boundary, not merely a live session.

- **Presented as a normal step in the flow, never as an error.** The operator clicks Change destination and is asked to re-authenticate; they do not click, fail, and then guess why.
- **The client cost is real and must not be planned as free:** satisfying it requires an actual re-authentication round trip and a retry of the original action. Budget it.
- **Denied money actions must leave a trace.** A failed predicate raises, which rolls back the transaction and takes any audit row with it — Postgres has no autonomous transactions. **Repeated failed attempts to change a payout destination or fire a payout are the single highest-value fraud signal in the system, and today they are invisible.** The denial is therefore recorded out-of-band, in a separate transaction. This surface does not show it (it is a platform risk signal), but no dashboard change may make it harder to capture.
- `UNVERIFIED:` the money spec flags that it has not confirmed this project's access tokens actually carry the per-factor claims its predicate reads. **That must be checked against a real token before this surface is built** — otherwise the step-up either never fires or always fires. → §22.14.

### 16.8 States

Loading · Empty: n/a (settings always have content) · Error: per-section retry · Denied: sections the role cannot read are absent; column-scoped fields are absent rather than blank (§16.1) · Blocked: destination change during an open dual-control request shows the pending state.

---

## 17. (L) Operational activity

### 17.1 What this is

A **venue/org-scoped operational history** — who did what to this venue's objects. It exists so a manager can answer "who changed that price?" and "who comped 40 people?" without asking Snatch It.

### 17.2 What this is explicitly NOT

**No raw security logs.** This surface never renders:
- `kernel.admin_audit` in raw form. That table is **readable only by `is_platform`** (schema §1.12; RLS §7.12) — a venue principal cannot read it and must not be given a view that pretends otherwise.
- Authentication events, session events, MFA/step-up events, RLS denials, rate-limit hits.
- Signing-key provisioning, rotation, or revocation (`kernel.signing_key`) — key state is a platform incident surface (RN §8).
- Platform overrides, fraud adjudications, or risk actions taken by Snatch It.
- Anything belonging to another org or venue, ever.
- `before`/`after` payload blobs. Rows render a plain sentence, not a diff of internal state.

### 17.3 What it shows

One row per operational act, each: **when · who (display name) · what (plain verb) · which object (deep link) · reason code, where the action carries one.**

Covered actions (each already writes `kernel.admin_audit` in-transaction per its RPC contract):
event created / status changed / cancelled · session created · ticket type created / price changed / visibility changed · inventory batch created / capacity changed · hold released · comp allocated / issued · guest list created / entry added / entry removed · door PIN issued / revoked · scan device registered · staff granted / revoked · org member invited / role changed / removed · settlement opened / closed · payout requested · refund issued · resale policy changed · promoter created · link created · code issued / switched · export requested / generated / downloaded / revoked.

Added by the delta specs, all of which already write `kernel.admin_audit` in-transaction per their contracts: **door manifest opened / closed** (with reason code) · **export requested / generated / downloaded / revoked / expired / purged / failed / denied** · **promoter code issued / status changed / scope changed** · **attribution flag released / denied** · **refund requested / approved / denied** · **announcement drafted / approved / cancelled / revoked** · **single-record attendee lookup** (recorded by **query kind only, never the query value** — logging a probed email address would build the harvest list inside our own audit).

Filters (closed set): object type · actor · date range. Search: object name. **No free-text query, no SQL.**

**Still excluded, and now more so** (§17.2): the export audit's payload fields — the artifact hash, the constraint-set version, the emitted/suppressed contact-cell counts — are **platform forensics**, not venue history. The venue sees *that* an export happened, by whom, with what filters, and what became of it. It does not get the forensic payload, and it can never reach the underlying audit table.

**Role scoping:** `org_finance`/`venue_finance` see the finance-relevant subset (settlement, payout, refund, price change, comp) — not the full operational feed.

### 17.4 Export

**Activity is viewable, not exportable, in MVP.** Keeping exactly one audited export path in the product (§9.6) is worth more than a second convenience. Stated on the surface.

### 17.5 Retention

The venue view is windowed (current + previous season by default) even though `kernel.admin_audit` is permanent and tamper-evident (schema §1.12). The window is a product choice, and the surface says so rather than implying history stops.

### 17.6 Reads

There is **no venue-readable path to this data today** — `kernel.admin_audit` is platform-only. This surface requires the delta RPC in §21.2 and cannot ship before it.

### 17.7 States

Loading: row skeletons · Empty: *"Nothing has happened here yet."* / filtered: *"No activity matches these filters."* (distinct) · Error: retry · Denied: standard · Partial: an actor whose profile can't resolve renders as *"A team member"*, never as a raw id.

---

## 18. Global state matrix

Every major surface declares **loading · empty · error · permission-denied · offline · partial/degraded**. Cells marked **[NO BACKEND PATH]** are surfaces whose read or write does not exist in the frozen specs — these are the §21 delta items and cannot ship before them.

| Surface | Loading | Empty | Error | Permission-denied | Offline (browser) | Partial / degraded |
|---|---|---|---|---|---|---|
| **A. Home** | Per-zone skeletons, independent | Per-zone specific copy | Per-zone card + retry | Unreadable zones absent; catalogue-only fallback for `org_member` | Stale banner + last-loaded time | One zone failing never blanks the page |
| **B. Events list** | Table skeleton | *"No events yet"* + Create (role-gated) | Retry | Standard denial | Stale banner, writes blocked | Sold/capacity unavailable → *"—"*, never 0 |
| **B. Create event** | Step spinner | n/a | Field-level + RPC error | Wizard not offered | Blocked with *"You need a connection to create an event"* | Venue-not-approved blocks step 1 with the reason |
| **B. Publish / status** | Inline | n/a | `precondition_failed` rendered as the missing requirement | Control absent | Blocked | Blocked when no ticket type + batch, with what's missing named |
| **B. Cancel event** | Blast-radius loading | n/a | Retry | Control absent | Blocked | **Blast radius unavailable → action blocked** (never cancel blind) |
| **C. Ticket types** | Table skeleton | *"No ticket types yet"* | Retry | Standard | Read-only | Price change blocked while price read is stale |
| **C. Inventory** | Matrix skeleton | *"No releases yet"* | Retry; counters marked stale | Staff-only counters absent; `remaining` still shown | Read-only, stale-stamped | A batch that fails to load renders *"Couldn't load"*, never 0 |
| **C. Holds** | Skeleton | *"No active holds"* | Retry | Release control absent | Blocked | Expired-during-view row updates in place |
| **D. Attendees** | Table skeleton, filters live | No-sales vs no-match are **distinct** | Retry, filters preserved | Standard; door and box-office denials name manual lookup | Read-only, stale-stamped | **Holder-keyed** (K-1); denied column classes are **absent, not null**; attribution/check-in *"—"* with explanation |
| **D. Ticket holder mix** | Card skeleton | n/a | Retry | Card absent | Read-only | **Suppressed** (k<25 or bucket<5) — the bucket floor is a DB `CHECK`, so a sub-floor bucket cannot be stored, only suppressed |
| **D. CRM export** | Job status polling | *"No exports yet"* | `failed` state with reason + re-request | Absent for denied roles (§5 note 12) | Request blocked | `expired` / `revoked` / `purged` each render distinctly |
| **E. Promoters** | Skeleton | *"No promoters yet"* | Retry | Standard | Read-only | Commission-paid *"—"*, never 0 · **[NO BACKEND PATH]** for promoter and link CRUD (U-3, U-4) |
| **E. Codes** | Availability spinner | n/a | Availability check failure blocks issue | Absent | Blocked | Confusable warning requires acknowledgement before issue · **BACKED** — code RPCs contracted (pkg `090`); the *slug*-availability read is not (U-4) |
| **E. Attribution** | Skeleton | *"No attributed sales yet"* | Retry | Standard | Read-only | Missing corroboration renders *"Unknown"*, never *"No"* |
| **E. Self-deal queue** | Skeleton | *"Nothing flagged"* | Retry | Absent | Blocked | **BACKED** — `venue.review_attribution_flag`; promoter-manager labels denied the decision |
| **F. Guest list** | Skeleton | 3 distinct empties (§11.6) | Retry; check-in disabled if write path unhealthy | Standard; door sees check-in only | Check-in **blocked, never optimistic** | Comp batch exhausted blocks allocation with the count · **[NO BACKEND PATH]** for create/add/remove (U-1) and mark-arrived (U-2) |
| **F. Comps** | Skeleton | *"No comps issued"* | Retry | Standard | Blocked | Step-up required renders as a normal step, not an error |
| **G. Door PINs** | Skeleton | *"No PINs for this session"* | Retry | Standard | Blocked | Plaintext once; **no resend affordance exists** |
| **G. Devices** | Skeleton | *"No devices registered"* | Retry | Standard | Read-only | Device offline is a **status**, not an error |
| **G. Manifest** | Skeleton | n/a | Retry | Standard | Read-only | **BACKED** — open/close contracted; **`venue_scanner` and door PINs excluded (O-4)**. Blast-radius counts **[NO BACKEND PATH]** → Δ11 |
| **G. Scan board** | Skeleton | *"No scans yet"* | Retry; counters stale-marked | Standard | Stale-stamped | Counters never optimistic, never zeroed on error |
| **G. Manual lookup** | Inline spinner | *"No ticket matches that"* | Retry | Standard | Blocked | Single record; wallet-staleness note always present |
| **G. Flag queue** | Skeleton | *"Nothing flagged"* | Retry | Standard | Read-only | **Escalate only** — no Resolve control for venue roles |
| **H. Orders** | Table skeleton | *"No orders yet"* | Retry | Standard | Read-only | Payment link unresolved → refund disabled, reason shown |
| **H. Refund** | Inline | n/a | `precondition_failed` shown plainly | **Permission-explained** for `venue_manager`/`venue_finance` (§13.3) | Blocked | Tier disclosed **before** confirm; parked → ticket-won't-scan warning; already-scanned → money-only refund |
| **I. Settlement** | Header then lines | *"No settlements yet"* | Retry; **Close blocked if lines unreadable** | Close permission-explained for owner/admin | Read-only | Missing royalty line → *"Couldn't load"* + Close blocked |
| **I. Payouts** | Skeleton | *"No payouts yet"* | Retry | Standard | Read-only | **Held ≠ failed ≠ on probation** — three states, three remedies, never one pill; cool-down names its unlock time |
| **J. Org members** | Skeleton | *"You're the only member"* | Retry | Standard | Read-only | Last-owner and self-grant refusals are explanations |
| **J. Venue staff** | Skeleton | *"No venue staff yet"* | Retry | Standard | Read-only | Multi-role person renders as multi-select, not one dropdown |
| **K. Settings** | Section skeletons | n/a | Per-section retry | Sections absent; **column-scoped fields absent, not blank** | Read-only | Destination change pending dual control shows pending |
| **K. Notifications** | Skeleton | n/a | Retry | n/a (self) | Read-only | Non-opt-out rows render as always-on with an explanation |
| **L. Activity** | Row skeletons | No-activity vs no-match distinct | Retry | Standard | Read-only | Unresolvable actor → *"A team member"*, never a raw id · **BACKED** — `venue.list_activity` |

**Standard permission-denied state (used everywhere):** the object's existence, name, and counts are **not** revealed. Copy: *"You don't have access to this."* plus, where a role-appropriate alternative exists, a link to it. Never a partial render, never a title with an empty body.

---

## 19. Cross-cutting UI rules

1. **Money.** All amounts are integer minor units server-side (schema §0.3), formatted client-side as USD. No client-side arithmetic on money except display formatting of a server-supplied total. No currency selector (C13).
2. **Time.** All timestamps are `timestamptz` (schema §0.4). The dashboard renders in the **venue's local time** with the zone named on any time an operator will act on (door times especially). Relative times ("4 minutes ago") only for freshness indicators, never for a door time.
3. **Idempotency.** Every write control generates a `command_idempotency_key` once per user intent and reuses it across retries (C16, RPC §0.2). A double-click, a flaky network retry, and a refresh-and-resubmit must not produce two orders, two comps, or two batches.
4. **Confirmations.** Money-consequential, capacity-consequential, and custody-consequential actions require an explicit confirm that names the effect in counts. Reversible operational actions do not.
5. **Audit visibility.** Any action that writes `kernel.admin_audit` shows a one-line "this will be recorded" note on its confirm — staff behave better when the audit is visible, and it is not a secret.
6. **Never optimistic where the physical world disagrees.** Check-ins, scan counters, inventory counters, and refund results are server-confirmed before render. Optimistic UI is fine for a filter chip; it is not fine for "admitted".
7. **Errors carry the server's reason.** `oversell_rejected`, `precondition_failed`, `insufficient_privilege`, `idempotency_replay` (RPC §0.5) each map to specific operator copy. No generic "Something went wrong" on any money or capacity path.
8. **No impersonation, anywhere** (§4.4 rule 6).

---

## 20. Read index — what each view reads

For Agent F to check the RPC surface covers the dashboard. **R** = read RPC · **T** = RLS-filtered table read · **W** = write RPC · **Δ** = requires a §21 delta.

| # | View | Reads | Writes |
|---|---|---|---|
| A1 | Home — Tonight | T `catalog.event_session` (idx `starts_at`), `catalog.event`, `venue.inventory_batch`, `venue.scan`, `venue.scan_device`, `venue.guest_entry` · **Δ§21.3** for a single-call summary | — |
| A2 | Home — Upcoming | T `catalog.event`, `catalog.event_session`, `venue.inventory_batch` | — |
| A3 | Home — Tickets sold | T `venue.order` (`paid`), `venue.order_item` | — |
| A4 | Home — Revenue (gross) | T `venue.order`, `venue.order_item` | — |
| A5 | Home — Attendance | T `venue.scan`, `kernel.tickets` (issued count via order items) | — |
| A6 | Home — Inventory warnings | T `venue.inventory_batch`, `venue.inventory_hold`; thresholds from `catalog.platform_config` | — |
| A7 | Home — Payout status | R `kernel.list_org_payouts` (money §6.4) — **Δ3 satisfied**, names `org_owner` | — |
| A8 | Home — Recent activity | R `venue.list_activity` — **Δ2 satisfied** | — |
| B1 | Events list | T `catalog.event`, `catalog.event_session`, `venue.inventory_batch`, `catalog.resale_policy` | — |
| B2 | Create event | T `catalog.venue` (approval) | W `catalog.create_event` (RPC §4.1) |
| B3 | Add session | T `catalog.event` | W `catalog.create_event_session` (§4.3) |
| B4 | Publish / status | T `catalog.event`, `venue.ticket_type`, `venue.inventory_batch` | W `catalog.publish_event` (§4.2) |
| B5 | Cancel event | T `catalog.event`, `catalog.event_session`, `kernel.tickets`, `market.listing_native` (blast radius) | W `catalog.cancel_event` (§4.4) |
| B6 | Resale policy | T `catalog.resale_policy` | W `catalog.set_resale_policy` (§11) |
| C1 | Ticket types | T `venue.ticket_type`, `venue.inventory_batch` | W `venue.create_ticket_type` (§5.1) |
| C2 | Price / visibility | T `venue.ticket_type` | W `venue.set_ticket_type_price` (§5.1) |
| C3 | Inventory matrix | T `venue.inventory_batch` (counters staff-scoped; `remaining` public) · **Δ§21.3** for the per-event roll-up | W `venue.create_inventory_batch` (§5.2) |
| C4 | Holds | T `venue.inventory_hold` | W `venue.release_inventory_hold` (§5.5) |
| D1 | Attendees list | R `venue.list_attendees(p_session_id, p_filters, p_cursor)` — **Δ3 satisfied; holder-keyed per K-1**, column-scoped, audited per page | — |
| D2 | Attendee detail | R `kernel.get_ticket_custody_chain` (§1.3); T `venue.order`, `venue.order_item` | (refund → H2) |
| D3 | Ticket holder mix | R `venue.get_holder_mix(p_event_session_id, p_dimension)` — **exactly two params, by contract** | — |
| D4 | CRM export | R `venue.list_export_jobs`; edge `crm-export /download` → `venue.authorize_export_download` (live re-check) | W `venue.request_export` · `venue.revoke_export` |
| E1 | Promoter list | T `venue.promoter`, `venue.promoter_link`, `venue.attribution` | W promoter CRUD (RLS §9.17) |
| E2 | Codes | T `venue.promoter_code`, `venue.promoter_code_scope` (RLS, promoter §8.1) | W `venue.create_promoter_code` · `create_promoter_codes_bulk` · `set_promoter_code_status` · `set_promoter_code_scope`/`_window` |
| E3 | Attribution | T `venue.attribution` (+ Agent C's `touch_corroborated` / `self_deal_flag`) | — |
| E4 | Self-deal queue | R `venue.list_promoter_attributions`; T `venue.attribution_review` | W `venue.review_attribution_flag` — **Δ4 satisfied** |
| E5 | Performance | R `venue.list_promoter_attributions`; `kernel.list_org_payouts` (cause `promoter_commission`) — **Δ3 satisfied** | — |
| F1 | Guest list | T `venue.guest_list`, `venue.guest_entry` | W guest-list RPCs (RLS §9.16) |
| F2 | Door check-in | T `venue.guest_entry` | W check-in RPC (`status→arrived`, RLS §9.16 note 39) |
| F3 | Comps | T `venue.comp_allocation`, `venue.inventory_batch` (comp batch remaining) | W `venue.allocate_comp` / `venue.issue_comp` (§11) |
| G1 | Door PINs | T `venue.door_pin` (**never** `pin_hash`) | W `venue.create_door_pin` / `venue.revoke_door_pin` (§9.1/§9.2) |
| G2 | Devices | T `venue.scan_device` | W `venue.register_scan_device`; manifest-sync RPC (RLS §11) |
| G3 | Manifest state | R `catalog.effective_freeze_at(p_session_id)`; T `catalog.event_session.door_open_at`, `venue.door_manifest` (episode history) | W `venue.open_door_manifest` · `venue.close_door_manifest` — **Δ1 satisfied; door principal excluded (O-4)**. Blast-radius dry-run: **Δ11** |
| G4 | Scan board | T `venue.scan` | — |
| G5 | Manual lookup | R `venue.validate_ticket_online` (§9.3) + `venue.lookup_attendee(p_session_id, p_query_kind, p_query_value)` — one record, audited by **query kind only** | — |
| G6 | Reconciliation | T `venue.scan`, `venue.scan_device` | W `venue.reconcile_offline_scans` (§9.5) — door/manager |
| G7 | Flag queue | T `venue.scan` (`fraud_flag`) | — (adjudication is `platform_risk`, RLS §9.12) |
| H1 | Orders list | T `venue.order`, `venue.order_item` | — |
| H2 | Refund | T `venue.order`, `kernel.payment_native`, `kernel.refund` | W `kernel.refund_primary_order` (§11.4) |
| I1 | Settlement list | T `venue.settlement` | W `venue.open_settlement` (§10.1) |
| I2 | Settlement detail | T `venue.settlement_line` | W `kernel.close_settlement` (§10.2) |
| I3 | Payouts | R `kernel.list_org_payouts` — **Δ3 satisfied**; `stripe_transfer_ref` as a presence boolean for org roles | W `kernel.request_org_payout` (§10.3) |
| J1 | Org members | T `kernel.org_member`, `kernel.org_invite` | W `kernel.invite_org_member` / `grant_org_role` / `revoke_org_role` |
| J2 | Venue staff | T `venue.staff_role` | W `venue.grant_staff_role` / `venue.revoke_staff_role` |
| K1 | Org settings | T `kernel.organization` (column-scoped) | W `kernel.set_org_payout_destination` (owner only) |
| K2 | Venue settings | T `catalog.venue` | W `catalog.update_venue` (§3.3) |
| K3 | Notifications | R `notify.get_preference_matrix()` | W `notify.set_preference(p_type_key, p_channel, p_enabled)` |
| L1 | Activity | R `venue.list_activity(p_scope_kind, p_scope_id, p_filters, p_cursor)` — **Δ2 satisfied** | — |
| **H3** | **Refund approval queue** (§13.7) | R `kernel.list_approval_requests(p_org_id, p_filters)` | W `kernel.approve_refund_request` (SoD: approver ≠ requester) |
| **H4** | **Refund initiate — tiered** (§13.3a) | T `venue.order`, `kernel.payment_native`, `kernel.refund` | W `kernel.request_order_refund` (one entry point, three outcomes) |
| **G8** | **Freeze status card** (§12.4) | R `catalog.effective_freeze_at`; which input produced it | — |
| **G9** | **Episode history** (§12.4) | T `venue.door_manifest` (venue-scoped read) | — |
| **K4** | **Announcement composer** (§16.5a) | R `notify.preview_announcement_audience` (**count only, never a recipient list**); T `notify.announcement` (venue-scoped) | W `notify.draft_announcement` · `approve_announcement` · `cancel_announcement` · `revoke_announcement` |
| **K5** | **Re-authenticate for a money action** (§16.9) | the in-function step-up predicate; config keys | — (a client flow, not a write) |

---

## 20A. Acceptance check — every control mapped to a named backend capability

> **The binding owner rule this section discharges:** *"Ensure every dashboard action maps to an actual RLS/RPC/backend capability. No fake UI controls with no backend contract."*
>
> Method: every **write** control in §6–§17 is listed with the named RPC that performs it, or an RLS §11 EXEC row where the RPC is authorized but unnamed. Read-only surfaces are covered by §20. A control with neither is **flagged**, not quietly shipped.

### 20A.1 Mapped — write controls with a named RPC

| Surface | Control | Backend capability |
|---|---|---|
| B (§7.2) | Create event · add session | `catalog.create_event` · `catalog.create_event_session` |
| B (§7.4) | Advance status | `catalog.publish_event` / `catalog.set_event_status` |
| B (§7.8) | Cancel event | `catalog.cancel_event` |
| B (§7.7) | Set resale policy | `catalog.set_resale_policy` |
| C (§8.2) | Create ticket type | `venue.create_ticket_type` |
| C (§8.3) | Price / visibility change | `venue.set_ticket_type_price` |
| C (§8.4) | Create batch / capacity change | `venue.create_inventory_batch` |
| C (§8.7) | Release hold | `venue.release_inventory_hold` |
| D (§9.6) | Request / revoke export; download | `venue.request_export` · `venue.revoke_export` · `venue.authorize_export_download` (+ edge `crm-export`) |
| E (§10.5) | Issue / bulk-issue / switch code; set scope, window | `venue.create_promoter_code` · `create_promoter_codes_bulk` · `set_promoter_code_status` · `set_promoter_code_scope` · `set_promoter_code_window` |
| E (§10.7) | Release / Deny a self-deal flag | `venue.review_attribution_flag` → `venue.attribution_review` — **the sole writer of that ledger; `venue.decide_flagged_attribution` is DELETED, not aliased (`AUTHZ-H10`)** |
| G (§12.2) | Issue / revoke door PIN | `venue.create_door_pin` · `venue.revoke_door_pin` |
| G (§12.4) | **Open / close door manifest** | `venue.open_door_manifest` · `venue.close_door_manifest` — **Δ1 closed** |
| G (§12.7) | Reconcile offline scans | `venue.reconcile_offline_scans` |
| H (§13.4) | Initiate refund | `kernel.request_order_refund` |
| H (§13.7) | Approve / deny a parked refund | `kernel.approve_refund_request` |
| I (§14.2/§14.4) | Open / close settlement | `venue.open_settlement` · `kernel.close_settlement` |
| I (§14.5) | Request disbursement | `kernel.request_org_payout` |
| J (§15.1) | Invite / grant / revoke org role | `kernel.invite_org_member` · `kernel.grant_org_role` · `kernel.revoke_org_role` |
| K (§16.2) | Edit venue profile | `catalog.update_venue` |
| K (§16.3) | Change payout destination | `kernel.set_org_payout_destination` |
| K (§16.5) | Set notification preference | `notify.set_preference` |
| K (§16.5a) | Draft / approve / cancel / revoke an announcement | `notify.draft_announcement` · `approve_announcement` · `cancel_announcement` · `revoke_announcement` |

### 20A.2 Mapped, but to an RLS EXEC row rather than a named RPC contract

These have an authorization row and no contract. **They are backed, but under-specified** — an implementer has authority without a signature.

| Surface | Control | Where it is authorized | What is missing |
|---|---|---|---|
| **F (§11.3)** | **Allocate comp · issue comp** | **RLS §11.1 `venue.allocate_comp` / `venue.issue_comp`** — a *fully argued split authority model* (R-15/E6/E7: who may allocate vs who may issue, the C39 step-up seam, the audit obligation) | **no RPC contract when §20A.1 claimed one.** Moved here by RPC §20.14 **`R-8`** (`G-4`) |
| G (§12.3) | Register scan device | RLS §11 `venue.register_scan_device` | no RPC contract (params, errors, idempotency) |
| G (§12.3) | Device manifest sync | RLS §11 "manifest-sync" | **unnamed** — the row says "`register_scan_device` / manifest-sync" without giving the second function a name |
| J (§15.2) | Grant / revoke venue staff role | RLS §11 `venue.grant_staff_role` / `revoke_staff_role` | no RPC contract; **and the role picker must now offer six labels** |
| K (§16.3) | (destination) | RLS §11 `kernel.set_org_payout_destination` | contracted by the money spec, not by the RPC spec |

> **`SPEC CORRECTION` — the comp rows moved, and why the move is recorded rather than silently made
> (RPC §20.14 `R-8`, gap `G-4`).** §20A.1 listed `venue.allocate_comp` and `venue.issue_comp` as *"mapped —
> write controls with a named RPC"*. **They had a name and no contract.** RLS §11.1 authorized them and argued
> the split in detail; no document gave either one a signature, an error set, or an idempotency key. A name
> carried in an authorization row is not a contract, and §20A exists precisely to refuse that substitution —
> so listing them under §20A.1 made this section assert the thing it was written to detect.
>
> **The rows may return to §20A.1 only when RPC §20.5.1 / §20.5.2 are merged**, and **the earlier §20A.1
> listing must never be cited as evidence that they were ever mapped.** Until then these two controls are
> governed by §20A.2's rule: backed, under-specified, and an implementer holds authority without a signature.
> Ownership of that merge sits with the RPC integrator, not with this document.

### 20A.3 **UNBACKED — controls I could not map to any named backend capability**

**These are the answer to the acceptance question, and none of them should be built until an owner closes them.**

| # | Surface | Control | What exists | What is missing |
|---|---|---|---|---|
| **U-1** | F (§11.2) | **Create guest list · add guest · remove entry** | RLS §9.16 says only *"guest-list CRUD RPCs"* | **No RPC is named anywhere.** Three distinct writes, zero signatures. §20 row F1 has always said "guest-list RPCs" and no spec ever named them. |
| **U-2** | F (§11.5) | **Mark a guest arrived** (`status` + `checked_in_at`) | RLS §9.16 note 39 grants the door principal exactly this narrow update | **No RPC is named.** This is the single most-used control at a door and it has no contract. |
| **U-3** | E (§10.2/§10.3) | **Create / edit a promoter; invite or assign; set commission terms and terms version** | RLS §9.17 says only *"promoter CRUD"* | **No RPC is named.** The promoter spec contracts *code* RPCs but not promoter-record RPCs. |
| **U-4** | E (§10.4) | **Create a promoter link; change link status; live slug-availability check** | RLS §9.17 (same unnamed "promoter CRUD") | **No RPC is named, and no availability-check read exists** — the UI is required to run a live global-namespace check before enabling create, against nothing. |
| **U-5** | G (§12.4) | **Blast-radius counts on the door-open confirm** | the open RPC returns drained counts **after** it commits | **No dry-run read.** Principle 7 requires the counts *before* the confirm enables. → Δ11. |
| **U-6** | G (§12.4) | **Live-device count** on the door surface | the door spec requires the operator to acknowledge this exact number for a break-glass override, and says the dashboard shows it | **Not in that spec's dashboard section; no read or view is named.** → Δ12. |
| **U-7** | A (§6.1) | **Every home tile in one round trip** | the underlying tables are readable | `venue.get_dashboard_summary` is still only an ask (Δ3's third RPC, the one no delta spec adopted). Home works without it, at N queries. |
| **U-8** | C (§8.4) | **Capacity change on an existing batch** | `venue.create_inventory_batch` creates | **No capacity-change RPC is named**, though §8.4 specifies the guarded behaviour and the refusal floor in detail. |
| **U-9** | B (§7.3) | **Edit a draft event** (title, session times, labels) | `create_*` RPCs exist; §7.3 specifies editability while `draft` | **No update RPC** for `catalog.event` or `catalog.event_session` is named. Creation is contracted; editing is not. |
| **U-10** | K (§16.1) | **Edit org display name / benign profile fields** | RLS §7.2 column-grants imply it | **No `kernel.update_organization` is named.** `catalog.update_venue` exists for the venue; the org has no counterpart. |

**Pattern worth naming for the RPC owner:** every gap above is a **create-but-never-update** or an **authorize-but-never-name**. The write paths that were contracted are the ones that create money or custody objects; the ones that were not are the everyday edits — rename a guest list, fix a typo in a draft, change a capacity, mark someone arrived. **Nine of the ten are `venue`/`catalog` operational writes, and U-2 is the one a door will hit a thousand times a night.**

**Until each is closed, this spec's rule holds: the control is read-only or it does not render.** §18's `[NO BACKEND PATH]` markers are updated accordingly.

---

## 21. Delta request

Only what the dashboard needs and no sibling architect (A–D) has asked for. Every item reuses an existing table or adds a column to one — **no new tables are proposed.** Ordered by whether a surface can ship without it.

> ### 21.0 Status after the delta-spec integration — read this before working any item below
>
> | Δ | Status | Closed by |
> |---|---|---|
> | **Δ1** door manifest open/close | **SATISFIED** | `venue.open_door_manifest` / `venue.close_door_manifest` (door §7.1/§7.2). **Role set corrected — the door principal is excluded by O-4** (§12.4). §22.7 resolved. |
> | **Δ2** `venue.list_activity` | **SATISFIED** | contracted as the dashboard's activity read; §17 can ship. |
> | **Δ3** three scoped venue reads | **SATISFIED, all three.** `venue.list_attendees` (CRM §11.4, **holder-keyed per K-1**) · `kernel.list_org_payouts` (money §6.4, **names `org_owner`**, closing §22.3) · `venue.get_dashboard_summary` remains this spec's ask. |
> | **Δ4** attribution flag decision | **SATISFIED** | `venue.review_attribution_flag` + the append-only `venue.attribution_review` ledger (§10.7). §22.4 resolved. |
> | **Δ5–Δ10** | **OPEN, unchanged.** No delta spec touched event description/hero, scheduled on-sale, per-type limits, event-scoped expiring staff grants, guest-list promoter FK, or branding. |
>
> **Δ11 — NEW ask: a door-open dry-run read.** §12.4's confirm must show the real counts of pending transfers and active listings the drain will cancel, **before** the confirm enables (principle 7). The open RPC returns those counts *after the fact*; no dry-run is contracted. Small, read-only, same role set as the open RPC. **Without it the most consequential door control in the product asks for a confirmation the operator cannot evaluate.**
>
> **Δ12 — NEW ask: a live-device count read.** The break-glass override path requires the operator to acknowledge the exact number of live devices, and the door spec says the dashboard shows the same count — **but it is not in that spec's dashboard section and no read is named.** Even though the override itself is platform-only, the count is a venue-visible number on the door surface.
>
> **Δ8 gains urgency, and its rationale changes.** MVP's answer to the 9 p.m. temp doorman was "issue a door PIN", and for a *scanner* that is still right. But **O-2 created `venue_box_office`**, and a one-night box-office lead needs an account, not a PIN — so `venue.staff_role`'s missing `event_id` / `expires_at` now over-provisions a role that exists precisely to be narrow. The delta is unchanged; the case for it is stronger.

**Δ1 — `NEW RPC: venue.open_door_manifest(p_session_id, p_command_key)` and `venue.close_door_manifest(p_session_id, p_command_key)`**
*Blocks §12.4.* `catalog.event_session.door_open_at` is the canonical door-freeze signal (schema §2.3; RPC §12.4, C43) and `kernel.is_transfer_frozen` reads it — but **no RPC in the frozen contract writes it**, and it appears in no EXEC row of RLS §11. Something must open the manifest at doors. Role, **as originally proposed**: `has_venue_role([venue_manager, venue_door])` OR `has_org_role([org_owner, org_admin])`. Audited (`session.door_open` / `session.door_close`). Idempotent on the session's current state. Without it, the freeze is unreachable from any operator surface.

> **SATISFIED, with the role set corrected.** The RPCs are contracted (door §7.1/§7.2). **Ruling O-4 removes the door principal**, so the role set is `has_venue_role(venue, [venue_manager])` OR `has_org_role_over_venue(venue, [org_owner, org_admin])` OR `is_platform([platform_admin])` — **`venue_scanner` and every `door_pin` principal are excluded.** See §12.4; §22.7 is resolved. **The one thing Δ1 asked for that is still missing is the blast-radius dry-run read** → Δ11.

**Δ2 — `NEW RPC: venue.list_activity(p_scope_kind, p_scope_id, p_filters, p_cursor)`**
*Blocks §17 entirely.* `kernel.admin_audit` is readable only by `is_platform` (schema §1.12; RLS §7.12), so a venue principal has **no** path to its own operational history. Needs a definer read that (a) restricts to audit rows whose subject resolves to the caller's venue/org, (b) **excludes the security plane** — key rotation, platform overrides, risk actions, auth events, RLS denials, (c) returns plain verbs with no `before`/`after` payloads, (d) scopes the finance subset for `org_finance`/`venue_finance`. Role: `has_venue_role([venue_manager])` OR `has_org_role([org_owner, org_admin, org_finance])`.

**Δ3 — `NEW RPC:` three scoped venue read RPCs (no new storage)**
*Blocks §6, §9.1, §12.6, §14.5.* Every write path is contracted; the **operator read paths are not.** Three definer reads, each taking its scope id as an untrusted param and re-checking the predicate in-body (RPC §0.1):
- `venue.get_dashboard_summary(p_venue_id, p_window)` → the §6 tiles in one round trip (sessions tonight/upcoming, sold/gross, admitted, inventory warnings, latest payout state), each field omitted for roles that cannot read its source.
- `venue.list_attendees(p_session_id, p_filters, p_cursor)` → the §9 join across `venue.order` + `order_item` + `kernel.tickets` + `venue.scan` + `venue.attribution`, **column-scoped by role** (finance roles get money columns without contact detail; `venue_scanner` is refused outright), filters restricted to the closed enumerated set.
- `kernel.list_org_payouts(p_org_id, p_filters)` → `kernel.payout` is money-custody-RPC-only and schema §1.9 names "payee reads own via scoped RPC", but **no such RPC is contracted** — §14.5 and the home payout tile have no read today.

**Δ4 — `NEW RPC: venue.review_attribution_flag(p_attribution_id, p_decision, p_reason_code, p_command_key)`**
*Blocks §10.7.* Agent C requires a Release/Deny queue for flagged self-deals, but `venue.attribution` is **append-only** (schema §3.17), so the decision cannot be a mutation of the attribution row. The dashboard needs a write path that records an attributable, reason-coded decision and leaves it visible in history. **The storage shape is Agent C's call** — this delta asks only that a decision RPC exist. Role: `has_venue_role([venue_manager])` OR `has_org_role([org_owner, org_admin])`; `platform_risk` from the admin plane.

**Δ5 — `NEW COLUMN: catalog.event.description`, `catalog.event.hero_image_ref`**
*Degrades §7.5.* `catalog.event` carries only `title` and `status` (schema §2.2), while domain §1.3 treats the event as the marketing object. Without these, a venue cannot describe or illustrate its own event and the consumer Event Page (RN §4.2) has no hero to render. `hero_image_ref` as an opaque storage reference, not a blob.

**Δ6 — `NEW COLUMN: catalog.event.announce_at`, `catalog.event.on_sale_at`**
*Degrades §7.4.* MVP on-sale is a manual status flip, so a midnight drop requires a human awake at midnight. Two nullable timestamps plus a sweep that advances `status` would make scheduled on-sale possible without changing the lifecycle enum. **Deliberately paired with the C44 caveat:** this schedules an on-sale; it does **not** provide a virtual queue or bot defence, and no surface may claim otherwise.

**Δ7 — `NEW COLUMN: venue.ticket_type.sales_start_at`, `sales_end_at`, `min_per_order`, `max_per_order`**
*Degrades §8.6.* Per-order limits are the type-level anti-scalping control every operator expects (domain §1.4), and the only cap MVP has is a **global** platform value read inside `venue.reserve_primary_inventory` (RPC §5.3). "Tables sell 1 per order" is currently unexpressible. Sale windows likewise have no home.

**Δ8 — `NEW COLUMN: venue.staff_role.event_id (nullable)`, `venue.staff_role.expires_at (nullable)`**
*Degrades §15.3.* Domain §7.3 requires event-scoped, auto-expiring grants for the 9 p.m. temp doorman; the physical table has neither (schema §3.9), so MVP's only answer is the door PIN. The PIN is right for a loginless scanner, but a temp box-office lead who does need an account currently gets a **permanent venue-wide grant** — the exact over-provisioning §7.3 warns against. `expires_at` also needs a sweep, and the PK becomes `(venue_id, identity_id, role, event_id)`.

**Δ9 — `NEW COLUMN: venue.guest_list.promoter_id (nullable, FK→venue.promoter)`**
*Low priority; degrades §11.2.* Domain §1.6's canonical case is "Maya's list". MVP expresses it through the list `name` and `created_by`, which works but makes per-promoter guest-list accountability a string-matching exercise.

**Δ10 — `NEW COLUMN: kernel.organization.brand_logo_ref`, `catalog.venue.brand_logo_ref`** *(optional)*
*Degrades §16.4.* Only if venue branding is a product commitment. Otherwise §16.4's honest "not available yet" is the correct MVP answer and this delta should be dropped.

**Domain events — deferred to Agent D, not requested here.** Agent D's notification rules imply emitters for *low inventory crossed a threshold for a (batch, threshold) pair*, *daily sales digest window closed*, *payout failed*, and *door anomaly during a live session*. Those emitters belong to Agent D's notification design, and the dashboard consumes the same conditions directly from `venue.inventory_batch`, `kernel.payout.status`, and `venue.scan`. **`NEW DOMAIN EVENT:` — none requested by this spec.** If Agent D did not request the four emitters above, they become deltas on that spec, not this one.

---

## 22. Unresolved, and where sibling constraints collide

> **Resolution status after the delta-spec integration.** Six of nine are closed. **Resolved:** §22.1 (O-1) · §22.2 (O-2, edit V-1) · §22.3 (O-3) · §22.4 (append-only decision ledger) · §22.6 (CRM K-3) · §22.7 (O-4, edit V-3) · §22.9 (CRM K-5). **Still open:** §22.5 (label reconciliation, cosmetic) · §22.8 (thresholds). **New:** §22.10–§22.14. Each item below keeps its original text so the record shows what was decided and against what.

**§22.1 — Refund authority: RLS contradicts the domain architecture. → RESOLVED (O-1).**
**`org_owner` and `org_finance` may initiate a refund; `org_admin` and every venue role may not.** This spec's *mechanism* argument was upheld and its *outcome* reversed: role inheritance genuinely cannot work for money (single-valued membership), so O-1 grants the authority to the `org_owner` label **explicitly** and deletes the inheritance prose rather than reinterpreting it. §5.2 row 36, §13.3, §15.4 updated. Original text below.
RLS §11 grants `kernel.refund_primary_order` to `has_org_role([org_finance])` only among org roles. Domain §7.2 says Organization Owner "inherits Org Admin, Org Finance", and the §7.6 matrix shows Org Owner with `✔ᴰ✱` on "Issue refund (> micro)". But C36 makes `kernel.org_member.role` **single-valued** (schema §1.3), so there is no mechanism by which an `org_owner` row satisfies `has_org_role([org_finance])` — the inheritance in domain §7.2 is prose, not a predicate. **This spec follows RLS** (binding) and renders refund as `org_finance`-only with a permission-explained state. **Needs a ruling:** either add `org_owner` to the refund EXEC row, or state in the domain doc that org-role inheritance is not implemented for money actions.

**§22.2 — Venue roles: the domain catalog is wider than the physical enum. → RESOLVED (O-2; role-model edit V-1).**
**This was this spec's own "Needs a ruling", and the ruling arrived.** The venue enum is now six labels and the org enum six: **box office is `venue_box_office`; marketing is `venue_marketing` / `org_marketing`; promoter manager is `venue_promoter_manager` / `org_promoter_manager`; door is `venue_scanner`.** Every consequence this paragraph said the product must accept is retracted: a box-office seller is no longer over-provisioned as `venue_manager`, there **is** a marketing role, and "Promoter Manager" is no longer a euphemism for `venue_manager`. `venue_promoter` is removed entirely. See §5's label note, §5.1, and §15.2. **`scan_scopes` remains unmodelled** — that part of the paragraph stands, and no surface may imply a VIP-only door. Original text below.

*Original:* Domain §7.2 defines Venue Staff — Box Office, Venue Staff — Marketing, and Promoter Manager. The C36 physical enum is exactly `venue_manager | venue_finance | venue_door | venue_promoter` (schema §3.9; foundation §4). This spec uses only the four physical labels. Consequences the product must accept: a box-office seller must be granted `venue_manager` (over-provisioned) or work from a door PIN (under-provisioned for selling); there is no marketing role, so event-page editing is bundled into `venue_manager`; and "Promoter Manager" is `venue_manager`. `scan_scopes` (per-ticket-type door narrowing, domain §7.3) is not modeled at all. **Needs a ruling** on whether MVP accepts the four-role model as-is — this spec assumes it does.

**§22.3 — `org_owner` can request a payout it cannot read. → RESOLVED (O-3).**
`kernel.list_org_payouts(p_org_id, p_filters)` is contracted and **names `org_owner`** in its role set, so rows 5 and 40's `○` is confirmed rather than provisional. `venue_finance` gets a scoped `◐` — settlement-cause rows for its own venue only — and the read returns `stripe_transfer_ref` as a **presence boolean, not the reference**, for org roles. Δ3's payout read is satisfied (§14.5).

**§22.4 — Agent C's self-deal queue vs. append-only attribution. → RESOLVED.**
The collision was real and the resolution keeps both constraints: `venue.attribution` stays append-only, and Release/Deny becomes an **append-only decision ledger alongside it** (`venue.attribution_review`, unique on `(attribution_id, seq)`, effective decision = highest `seq`), written by `venue.review_attribution_flag`. A denied flag is resolved, never removed, and a decision can be superseded without rewriting history. Δ4 satisfied (§10.7).

**§22.5 — Door reject vocabulary: three names for one thing.**
Agent A specifies `duplicate`; `venue.validate_ticket_online` returns `already_scanned` (RPC §9.3); `venue.scan.result` records `duplicate` (schema §3.12). The dashboard maps all three to **"Already used"** and uses `duplicate` internally (§12.5). Not a behavioural conflict — a label reconciliation for the RPC author.

**§22.6 — Agent B's export allow-list vs. `platform_support`'s read grants. → RESOLVED (CRM K-3), in this spec's favour.**
**Read ≠ export was the right call and is now the ruling.** `platform_support` reads and does not extract, reaching a single record only through the lookup RPC. `platform_risk` and `platform_admin` read the roster and **do not use the venue CRM export** — a platform extraction has different justification, retention and controls, and routing it through a venue's surface would file a platform action in that venue's history and give it the venue's rate limits. **Platform bulk extraction is not built in Phase 2.** §9.3/§9.6 updated; note 13 corrected. Original text below.

*Original:* RLS gives `platform_support` `V` (scoped read) on `venue.order` and related objects, but Agent B explicitly denies it CRM export. This spec treats **read ≠ export** and honours Agent B: support can look, not extract. Also noted: Agent B's allow-list does not include `platform_risk` or `platform_admin`, so the venue export surface renders for neither. If platform staff need bulk extraction it must be a separately audited platform path, not this one.

**§22.7 — Which principal opens the door manifest. → RESOLVED (O-4; role-model edit V-3), against this spec's inference.**
**The door principal is excluded.** The `INFERENCE` below reasoned that the door principal was operationally correct and the freeze a bounded, reversible act. **Both halves were wrong in the way that matters:** the freeze is *not* reversible — it is monotone and terminal, and closing an episode does not clear it (§12.4) — and opening it is therefore the creation of a security boundary, not an operational convenience. **The scanner may not create the security boundary it scans against.** The operational objection stands and is answered by scheduling plus remote action, not by a weaker credential at the door. This is also why the label became `venue_scanner`. Original text below.

*Original:* Δ1 asks for the RPC but does not settle the authority. A `venue_manager` is often not at the door at 11 p.m.; a `venue_scanner` PIN principal is, but it is a deliberately weak, loginless device identity (domain §1.8) and opening the manifest freezes custody platform-wide for that session. `INFERENCE:` the door principal is the operationally correct actor and the freeze is a bounded, reversible operational act — but this is a security decision I should not make alone.

**§22.8 — Unresolved: inventory warning thresholds.**
§6.1 and Agent D's low-inventory rule both need a threshold per (batch, threshold) pair. `catalog.platform_config` holds fee/window/policy values (schema §2.4) and is the obvious home, but no key is named and no per-venue override exists. Left unresolved rather than invented.

**§22.9 — Attendee display name source. → RESOLVED (CRM K-5).**
`venue.list_attendees` pins it to **`public.profiles.display_name`**, the public-safe column set. **And the row it names is now the holder's, not the buyer's** (K-1, §9.1) — which was the larger of the two defects in that line.

---

### New open items raised by the integration

**§22.10 — the `ˢᵒᵈ` legend symbol is undefined by its author.**
The money spec introduces `●ˢᵒᵈ` into this spec's §5 matrix (row 47) without defining it, while separately defining a parallel symbol for the domain doc as a tracked correction. §5.2 defines it here as *"the grant is real, but the holder is structurally excluded from the paired act."* **Money-spec owner to confirm** the reading, and to track the addition.

**§22.11 — four sibling documents still describe a freeze narrowing that nothing implements.**
The physical schema spec (§643), the RPC contracts (§748), the RLS spec (§1150) and the migration plan (§414) all say the freeze is *"narrowed per-open-manifest-ticket per C43"*. **It is not; the predicate is session-wide, and C43's narrowing is Gate-M.** The edge spec and the RN spec are corrected; this spec's §12.4 now states the mechanism. **Owners of those four to correct, and the owner to confirm the MVP predicate is session-wide.**

**§22.12 — a legacy `venue_manager` grant still carries manifest authority a box-office user should not have.**
O-2 created `venue_box_office`, and O-4 says box office does not inherit manifest administration — but anyone previously granted `venue_manager` *for box-office work* retains open/close. **This is a migration/grant-hygiene question, not a spec question**, and it needs an owner decision on whether existing grants are re-mapped when the six-label enum lands. Under-provisioning is safe here; over-provisioning is not.

**§22.13 — `org_admin` on the money plane is an inference, not a ruling. → BLOCKING OWNER DECISION `D-8` (money spec §11 / §11.1). UNRESOLVED. DO NOT BUILD SURFACE H FROM EITHER CELL.**
O-1 (refund authority) and O-3 (payout visibility/requests) name `org_owner` and `org_finance` and are **silent on `org_admin`**. Neither position below is a ruling; both are readings.

- **Position A — deny.** `PHASE_2_MONEY_AUTHORITY_SPEC.md` §3.4: `org_admin` holds **no** money authority of any kind, `D` on `kernel.payout` and `kernel.refund` SEL/EXEC. Corroborated by Domain §7.2's Org Admin *Cannot* column (*"Cannot view or initiate payouts/bank changes"*) and O-2's *"not unrestricted financial authority"*. **§3.4 labels its own position `INFERENCE`.**
- **Position B — grant.** Row 35 (H. Refunds — order list) shows `org_admin` at `●`, and **money spec §10.1 row 35 shows the same `●` and previously called it *"unchanged"***. **§5.2 does not supersede row 35**, so this spec is faithfully inheriting the money spec — **the contradiction is internal to the money spec, not between the two documents.**

**What silence defaults to — and it defaults to GRANT.** An implementer resolves silence by building what RLS says. **RLS §9.7** grants `org_owner/admin` `A(own-org orders)` SELECT on `venue.order` (this is what backs row 35), and **RLS §9.13** grants `org_admin` `A(own-org)` SELECT on `venue.settlement`, whose header carries gross / fees / refunds / net. **Both grant.** So leaving this open does not stall the build — it ships **Position B silently**, with a `D` sitting unread in money §3.4.

**Why that default is the unsafe direction.** `org_admin` is the role most likely to be handed out liberally (it manages venues, events, staff, promoters). **Over-provisioning is the unsafe direction here**, and the remedy costs are asymmetric: widening later is a one-line matrix change; **narrowing later is a migration plus removing a capability operators have been using.** Deny-by-default is the standing posture (RLS `GP-1`) and the default on silence runs against it.

**Neither this spec nor the money spec picks a side, deliberately.** Registered as **`D-8`** in the money spec's owner-decision register (§11) with the full statement at §11.1, and as **`O13`** in `PHASE_2_RATIFICATION_RECORD.md`. **`D-4` covers row 37 (settlement) only and does not cover row 35.**

**§22.14 — the step-up predicate rests on an unverified claim about this project's tokens.**
The money spec flags `UNVERIFIED:` that it has not confirmed the access tokens actually carry the per-factor claims its step-up predicate reads. **This must be checked against a real token before §16.9 is built** — if the claim is absent the step-up either never fires or always fires, and both failure modes are silent.

**§22.15 — cross-spec package-map conflict on settlement.**
The promoter spec maps `venue.settlement` / `settlement_line` to `086`; the demographics and CRM specs map it to `087`. **The canonical registry says `087`** — the promoter spec is stale. Several delta specs also re-derive a numbering "shift" rather than citing `PHASE_2_PACKAGE_REGISTRY.md`, which is exactly how four competing scales were produced last time. **Every spec should cite the registry.**

**§22.16 — the notification objects have no migration package at all.**
The notifications spec says only that its objects land at `076`+. Nine tables, 23 RPCs, two cron jobs and two edge functions need a package in `076`–`091` or a ratified amendment extending the registry.

---

*End of Phase 2 Venue Dashboard Product Spec. Desktop-first operational software; every surface names its backend object for the engineer and its permission for the reviewer; the role × surface matrix (§5) is derived from RLS §9.x and the role-model spec §5 and does not extend either; cross-organization access is impossible by construction (§4.4); every capability the dashboard needs and does not have is in §21 and §20A.3, never asserted as existing.*

**The rule this file is held to, and the section that discharges it:** *"Ensure every dashboard action maps to an actual RLS/RPC/backend capability. No fake UI controls with no backend contract."* — **§20A.** **Twenty-three** write controls map to a named RPC; **five** map to an RLS EXEC row without a contract; **ten map to nothing and are listed as U-1…U-10.** *(Was twenty-four and four: the two comp controls moved §20A.1 → §20A.2 under RPC `R-8` / `G-4` — they had a name and no contract.)* The ten are not hidden in prose: they are a table, with the missing signature named in each row. **Until an owner closes one, that control is read-only or it does not render.**
