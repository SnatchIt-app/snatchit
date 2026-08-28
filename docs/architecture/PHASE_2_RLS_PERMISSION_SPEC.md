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

**Coverage:** all **43** original MVP objects (kernel 12 · catalog 5 · venue 20 · market 6-incl.-bridge-view). EXT
tables (`kernel.reserve`, `venue.inventory_unit`) are specified with their MVP deny-all posture and marked
DO-NOT-BUILD. Deferred schemas (`social`/`analytics`/`adapter`, money-ledger) are out of scope. **`notify` is
DISPUTED, not settled** — C7 is `RATIFIED · Gate P · MVP` and names it, while this spec and three others
defer it to Gate L. §16.9 records its authority model **conditionally**; see **MD-10**, §15.7. §16 adds the
matrices for the objects the eight Phase-2 delta specs introduce.

---

## 1. How to read this document

### 1.1 Roles (the 20 principals) and how each is tested

Human "roles" here are **application roles**, not Postgres roles. The only Postgres roles are `anon`,
`authenticated`, and `service_role`. Every app-role test is a **scope-qualified predicate** (C36, §2) run
inside an RLS policy or RPC — never a bare string comparison.

> **AUTHORITY NOTE (O-2 / O-4).** The canonical role set is defined by
> `docs/architecture/PHASE_2_ROLE_MODEL_SPEC.md` §3 (fifteen stored enum labels across three planes) and its
> §5.1 twenty-principal column key. That spec **supersedes** the four-label venue set this document previously
> carried. `venue_door` is renamed **`venue_scanner`**; `venue_promoter` is **removed** from the venue enum;
> five labels are added. This section is the reconciled form. Edits R-1 … R-4 of ROLE_MODEL §11.2 are applied
> here.

| # | Code | Role (matrix label) | Postgres role | How the policy tests it | Scope |
|---|---|---|---|---|---|
| 1 | `ANO` | `anon` | `anon` | unauthenticated request | none |
| 2 | `FAN` | `fan` (authenticated fan) | `authenticated` | `auth.uid()` present, no org/venue/platform role | self |
| 2b | `FAN◐` | `owner` (row owner) | `authenticated` | `auth.uid() = <row owner col>` (buyer/seller/current_owner/identity/from/to) | row |
| 3 | `OMB` | `org_member` | `authenticated` | `has_org_role(org_id,[org_member])` | org |
| 4 | `OOW` | `org_owner` | `authenticated` | `has_org_role(org_id,[org_owner])` | org |
| 5 | `OAD` | `org_admin` | `authenticated` | `has_org_role(org_id,[org_admin])` | org |
| 6 | `OFI` | `org_finance` | `authenticated` | `has_org_role(org_id,[org_finance])` | org |
| 7 | `OMK` | `org_marketing` | `authenticated` | `has_org_role(org_id,[org_marketing])` | org |
| 8 | `OPM` | `org_promoter_manager` | `authenticated` | `has_org_role(org_id,[org_promoter_manager])` | org |
| 9 | `VMG` | `venue_manager` | `authenticated` | `has_venue_role(venue_id,[venue_manager])` | venue |
| 10 | `VFI` | `venue_finance` | `authenticated` | `has_venue_role(venue_id,[venue_finance])` | venue |
| 11 | `VBO` | `venue_box_office` | `authenticated` | `has_venue_role(venue_id,[venue_box_office])` | venue |
| 12 | `VMK` | `venue_marketing` | `authenticated` | `has_venue_role(venue_id,[venue_marketing])` | venue |
| 13 | `VPM` | `venue_promoter_manager` | `authenticated` | `has_venue_role(venue_id,[venue_promoter_manager])` | venue |
| 14 | `VSC` | `venue_scanner` (authenticated staff scanner) | `authenticated` | `has_venue_role(venue_id,[venue_scanner])` | venue |
| 15 | `DOO` | **door session** (device + PIN) | **none** — `service_role` edge path; `auth.uid()` IS **NULL** | `kernel.assert_door_session(device_id, session_id)` **inside the RPC**; **NEVER an RLS predicate** (RM-5) | device + event_session |
| 16 | `PRO` | `promoter` (**a relationship, not a role**) | `authenticated` | `kernel.is_promoter_for_event(event_id)` / `promoter_link.identity_id = auth.uid()`; holds **NO row** in `venue.staff_role` | event / row |
| 17 | `PSU` | `platform_support` | `authenticated` | `is_platform([platform_support])` | platform |
| 18 | `PRI` | `platform_risk` | `authenticated` | `is_platform([platform_risk])` | platform |
| 19 | `PAD` | `platform_admin` | `authenticated` | `is_platform([platform_admin])` | platform |
| 20 | `SVC` | `service_role` | `service_role` | machine identity (Supabase service key / definer context) | machine only |

> **`promo` is NOT a role (R-3).** `venue_promoter` was removed from the venue enum (ROLE_MODEL §9.1). A
> promoter's authority is **row ownership** over `venue.promoter_link` / `venue.attribution`, tested by
> `kernel.is_promoter_for_event` — never by `has_venue_role`, which returns **false for every promoter**. Its
> data visibility is deliberately narrow (own links/attributions/commission only — CDM §8; never the back
> office). Every former `promoter` *matrix row* below is retained **only** as an own-row scope statement; it
> confers no venue-plane authority.

> **`DOO` (door session) is not an RLS principal (R-1, RM-5).** The scanner device never reaches PostgREST.
> It calls the `door-session` edge function, which holds `service_role` and invokes the definer RPC with a
> server-derived `p_actor_device_id`. Inside the RPC, `kernel.assert_door_session(device_id, session_id)`
> re-checks the binding against `venue.scan_device` + `venue.door_pin` live and raises on failure. Because the
> Postgres principal on that path is `service_role`, **RLS is bypassed entirely for the door**, and
> `assert_door_session` is the *single* gate — a deliberate concentration of the door's whole authorization
> surface into one auditable, security-critical function. It appears in a `DOO` matrix cell only to say *what
> the RPC will permit*, never to describe a policy. `DOO` holds exactly four capabilities (ROLE_MODEL §5.3
> F7–F10) and is `D` everywhere else, including the entire consumer plane — it has no `auth.uid()`, therefore
> no owned rows.

> **`service_role` is a machine identity, NEVER a human authority path** (Phase-0 056b/063, SPEC_FOUNDATION
> §8). It bypasses RLS by Postgres design, so it appears as `A` on reads — but the discipline is: no human
> ever authenticates as `service_role`; it is used only by edge functions and as the effective privilege the
> `postgres`-owned `SECURITY DEFINER` RPCs run with. A `svc` write cell is always **the definer path**, never
> a UI path. **See §3.1 (rule EDGE-CALLER-JWT): holding the service-role key does not license invoking a money
> or custody RPC with it.**

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

**GP-3 — every policy has a name, and the naming convention is normative (NEW).** Across the eight Phase-2
delta specs, authority is expressed only as matrix cells and predicate shapes; **not one RLS policy is named
anywhere**. That is a real gap: an implementer cannot diff, drop, replace, or test an anonymous policy, and CI
cannot assert that a required policy exists. This section states the convention and §16 applies it to every
object in this document.

> **Policy name = `<schema>_<table>_<verb>_<principal-class>`**, lower snake case, no spaces, ≤ 63 bytes
> (Postgres identifier limit — truncate the *principal-class* token, never the table token).
>
> | Token | Domain |
> |---|---|
> | `<schema>` | `kernel` · `catalog` · `venue` · `market` · `notify` |
> | `<table>` | the physical table name **without** its schema, verbatim |
> | `<verb>` | `sel` · `ins` · `upd` · `del` (a policy is written **`FOR SELECT`** etc., never `FOR ALL`) |
> | `<principal-class>` | the *predicate family*, not the individual role: `anon` · `public` (any authenticated) · `owner` · `org` · `venue` · `event` · `platform` · `svc` |
>
> Examples: `catalog_event_sel_anon` · `venue_order_sel_owner` · `venue_staff_role_sel_venue` ·
> `kernel_org_member_sel_org` · `market_listing_native_sel_public`.
>
> **Rules.**
> 1. **One policy per (table, verb, principal-class).** Never one policy per role — five venue labels sharing
>    one predicate share one policy, with the label array inside `has_venue_role(...)`. This keeps the policy
>    count proportional to *predicate families* (≈ 3–4 per table), not to the 20 principals.
> 2. **`FOR SELECT` only, in this document.** GP-1 means there is no `A` write cell anywhere, so **no Phase-2
>    table carries an INSERT, UPDATE or DELETE policy at all** — writes are `REVOKE`d, not policy-gated. A
>    write policy in a Phase-2 migration is a defect: it implies a client write path that must not exist.
> 3. **Deny-all tables carry zero policies** and are named in §5; `ALTER TABLE … ENABLE ROW LEVEL SECURITY`
>    with no policy *is* the deny. Do not write a `USING (false)` policy — it is noise that reads like a
>    grant.
> 4. Every policy name is asserted by pgTAP (`policies_are(schema, table, ARRAY[...])`), so an added,
>    renamed, or dropped policy fails CI rather than silently widening or narrowing authority.
>
> **GP-3a — the money plane deliberately has no policies, and that must be STATED, not left implicit.**
> Every money and custody mutation is `EXECUTE` on a `postgres`-owned `SECURITY DEFINER` function (GP-1). A
> definer function runs as its owner, so **a table policy on `kernel.payout` / `kernel.refund` /
> `kernel.tickets` / `kernel.ticket_ownership_log` / `market.market_sale` never runs on the write path.**
> Authority on that plane is expressed **only** as: (a) `REVOKE EXECUTE … FROM anon, authenticated, public`
> then a narrow `GRANT EXECUTE`, and (b) the in-body predicate re-check (§11). An implementer who writes RLS
> policies for these tables will produce policies that are never evaluated **and believe they are protected**.
> That is the single most likely way to build this wrong. The money-authority spec reaches the same conclusion
> from the other direction for step-up (§3.1): *"any design that says 'enforce step-up in RLS' is describing a
> policy that will never be evaluated on the path that matters."* The only policies these tables carry are
> **read** policies where the matrix shows `A` for a platform role; every `V` cell is a scoped read RPC, not a
> policy.

---

## 2. C36 — the scope-qualified role model, made STRUCTURAL

C36's mandate: roles are **never bare strings**; scope is always in the predicate; the enum label sets are
**disjoint** so cross-scope confusion is structurally impossible. This is the backbone of every matrix below.

### 2.1 Three disjoint enum label sets (no overlap by construction)

| Scope | Physical table | enum labels (DISJOINT) |
|---|---|---|
| **org** (6) | `kernel.org_member.role` | `org_owner` · `org_admin` · `org_finance` · `org_marketing` · `org_promoter_manager` · `org_member` |
| **venue** (6) | `venue.staff_role.role` | `venue_manager` · `venue_finance` · `venue_box_office` · `venue_marketing` · `venue_promoter_manager` · `venue_scanner` |
| **platform** (3) | `kernel.platform_role.role` | `platform_admin` · `platform_support` · `platform_risk` |

The label sets share **no common string**. There is no bare `finance`, `admin`, or `manager` — only
`org_finance`, `venue_finance`, `platform_admin`, etc. Consequence: a policy can never accidentally accept a
venue-finance staffer where org-finance is required, because the *strings never match* and the *predicate
carries the scope id*. A leaked/confused `role` value cannot cross a scope boundary — it fails the label check
and the scope-id check simultaneously.

**Proof by enumeration (C36, adopted from ROLE_MODEL §3.4).** All fifteen labels, in strict lexicographic
ascending order, each with its plane:

`org_admin`(org) < `org_finance`(org) < `org_marketing`(org) < `org_member`(org) < `org_owner`(org) <
`org_promoter_manager`(org) < `platform_admin`(plat) < `platform_risk`(plat) < `platform_support`(plat) <
`venue_box_office`(venue) < `venue_finance`(venue) < `venue_manager`(venue) < `venue_marketing`(venue) <
`venue_promoter_manager`(venue) < `venue_scanner`(venue).

Fifteen labels, fifteen distinct strings (every adjacent pair differs), and the three plane sets partition them
6 + 3 + 6 = 15 with every label assigned exactly one plane. ∴ **org ∩ venue = ∅, org ∩ platform = ∅,
venue ∩ platform = ∅.** ∎ **Ratified row C36 is satisfied structurally, not by convention.**

**Structural check (stronger than C36 requires).** Every org label matches `^org_`, every platform label
`^platform_`, every venue label `^venue_`; the three prefixes are pairwise non-prefix-comparable, so a label's
plane is decidable from its first token alone, without consulting the enum. A reviewer reading a policy line
sees the plane in the literal.

> **RM-1 (standing rule).** Every role label MUST begin with its plane token (`org_` / `platform_` /
> `venue_`). A proposed label that does not is rejected at review.

**Renames and removals in this set (declared, not silent):** `venue_door` → **`venue_scanner`** (ROLE_MODEL
§4.5 — the rename makes the label agree with O-4: authority over *scanning*, not over *the door*);
`venue_promoter` **removed** (ROLE_MODEL §9.1 — a promoter holds no administrative grant; its authority is row
ownership). Five labels added: `org_marketing`, `org_promoter_manager`, `venue_box_office`, `venue_marketing`,
`venue_promoter_manager`.

**Physical form.** ROLE_MODEL §3.5 recommends `text` + `CHECK` rather than a native enum for all three role
columns, so the label commitment stays correctable while the tables are empty (**OD-6**, owner-reserved). This
document is agnostic: every predicate below is a set-membership test either way.

### 2.2 The nine predicate helpers (the ONLY sanctioned way to test a role)

Conceptual behavior (defined as SECURITY DEFINER helpers in the RPC spec, `search_path` pinned, owned by
`postgres`, `STABLE`; **live-table reads, never JWT claims** — C9/§3). Adopted verbatim from ROLE_MODEL §6.2.

- **`kernel.has_org_role(org_id, role[])`** *(existing, unchanged)* → reads `kernel.org_member` for
  `(org_id, auth.uid())` and returns true iff the stored `role` ∈ the requested set. Reads the **live**
  membership row (a demotion/revoke takes effect immediately; a stale JWT cannot re-grant).
- **`kernel.has_venue_role(venue_id, role[])`** *(**CHANGED** — R-8)* → reads `venue.staff_role` for
  `(venue_id, auth.uid(), role)` live. **It reads no other table.** The former door-PIN branch
  (*"Door path also accepts a valid non-expired `venue.door_pin` … as a `venue_door` device principal"*) is
  **REMOVED**. Door principals never satisfy this predicate. See §2.5 for why this matters.
- **`kernel.has_event_role(event_id, role[])`** *(existing, unchanged)* → **resolves event → venue via
  `catalog`** (`catalog.event.venue_id`), then delegates to `has_venue_role(venue_id, role[])`. This is the
  single place event-grain authorization is turned into venue-grain authority; no table stores an "event
  role" — it is always derived, so there is no second source of venue authority to drift.
- **`kernel.is_platform(role[])`** *(existing, unchanged)* → reads `kernel.platform_role` for `auth.uid()`
  live, extending the existing `public.admin_users` bootstrap. Platform authority is global (no scope id).
- **`kernel.has_org_role_over_venue(venue_id, role[])`** *(**NEW** — R-9)* → resolves `catalog.venue.org_id`,
  then delegates to `has_org_role`. The **only** sanctioned expression of org→venue inheritance on the read
  path (RM-3). No policy re-inlines the `catalog.venue → kernel.org_member` join.
- **`kernel.has_org_role_over_event(event_id, role[])`** *(**NEW** — R-9)* → resolves `catalog.event.org_id`,
  then delegates to `has_org_role`. Same rule at event grain.
- **`kernel.is_org_affiliate(org_id)`** *(**NEW** — R-9)* → true iff **any** `kernel.org_member` row exists
  for `(org_id, auth.uid())`, regardless of role. **Scoping only, never authorizing** (RM-6): it may decide
  *which* orgs appear in a context switcher or *which* rows a roster read returns; it may **never** be the
  sole gate on a capability.
- **`kernel.assert_door_session(device_id, session_id)`** *(**NEW**)* → reads `venue.scan_device` +
  `venue.door_pin`; raises unless a valid, unexpired, unrevoked door session binds that device to that
  session. **NEVER appears in a `USING` clause** (RM-5) — it is asserted inside a definer RPC reachable only
  from the `service_role` edge path. Security-critical: `postgres`-owned, pinned `search_path`, `EXECUTE`
  revoked from `anon`/`authenticated`, covered by the package's adversarial verification.
- **`kernel.is_promoter_for_event(event_id)`** *(**NEW**, Phase 2D)* → true iff a live `venue.promoter_link`
  exists for `(event_id, auth.uid())`. Replaces the deleted `has_venue_role(…,[venue_promoter])` test
  everywhere.

**Predicate shapes (conceptual, not shippable SQL — ROLE_MODEL §6.3):**

```text
-- ORG PLANE (scope object = organization)
USING ( kernel.has_org_role(org_id, ARRAY['org_owner','org_admin']) )

-- VENUE PLANE (scope object = venue)
USING ( kernel.has_venue_role(venue_id, ARRAY['venue_manager','venue_box_office']) )

-- VENUE PLANE, with the ratified org→venue inheritance on the READ path (RM-3)
USING (
      kernel.has_venue_role(venue_id, ARRAY['venue_manager'])
   OR kernel.has_org_role_over_venue(venue_id, ARRAY['org_owner','org_admin'])
)

-- EVENT GRAIN (no event-grain grant exists; always resolved to venue or org)
USING (
      kernel.has_event_role(event_id, ARRAY['venue_manager','venue_marketing'])
   OR kernel.has_org_role_over_event(event_id, ARRAY['org_owner','org_admin','org_marketing'])
)

-- PLATFORM PLANE (no scope id)
USING ( kernel.is_platform(ARRAY['platform_risk','platform_admin']) )

-- DOOR SESSION — NOT an RLS predicate. Never appears in a USING clause.
--   PERFORM kernel.assert_door_session(p_device_id, p_session_id);   -- raises on failure
```

### 2.2b Standing rules carried into this document (ROLE_MODEL §6.6)

> **RM-1** — Every role label begins with its plane token. §2.1.
> **RM-2** — No RLS policy or RPC compares a bare role string, a **display name**, or a JWT claim. Only the
> nine helpers of §2.2, always with an explicit scope argument. (This extends §2.3 to display names:
> `has_venue_role(v,['box_office'])` is as illegal as `role = 'finance'`, because `box_office` is not a member
> of any enum.)
> **RM-3** — Org→venue and org→event inheritance is expressed **only** through `has_org_role_over_venue` /
> `has_org_role_over_event`.
> **RM-4** — Venue and event roles never inherit **up**. There is no venue→org path in any helper.
> **RM-5** — A door session is never an RLS predicate.
> **RM-6** — Affiliation (`is_org_affiliate`) is a *scoping* input, never an *authorizing* one.
> **INV-NOFORCE** — §3, invariant **I-12**.

### 2.2c Multi-venue authority — one venue per grant row, and why there is no N+1

A `venue_manager` grant scopes to exactly **one** venue: `venue.staff_role`'s key is
`(venue_id, identity_id, role)`. There is no wildcard, no `venue_id IS NULL` grant, and no "all venues of org
X" row. Multi-venue authority has exactly two sanctioned expressions: **N grant rows** (a person managing three
of forty venues) or **an org-plane role that inherits down** via `has_org_role_over_venue` (a person managing
all of them). `has_venue_role` is a **primary-key point probe**, declared `STABLE`, evaluated against each
row's own `venue_id`; the cost is O(distinct venues in the result set), not O(rows), because **the caller's
venue list is never materialized** — the question asked is always *"does this specific venue grant me this
role?"*, never *"which venues grant me roles?"*. The one place the reverse question is asked (the dashboard's
venue switcher) is a separate indexed read on `identity_id`, and it is **a projection for navigation, never an
authorization input**.

Note the deliberate key asymmetry: the **org** grant key omits `role` (one role per person per org) while the
**venue** grant key includes it (a person may hold several roles at one venue — a small venue's one operations
person plausibly holds `venue_manager` + `venue_box_office` + `venue_scanner` at once).

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

**On the READ path the inheritance is expressed by `kernel.has_org_role_over_venue` /
`kernel.has_org_role_over_event`, never by re-inlining the `catalog.venue → kernel.org_member` join (RM-3).**
This closes a real contradiction in the previous text (ROLE_MODEL defect 14.6): this paragraph said read-path
inheritance *does not exist*, while §9.9 grants `org_owner`/`org_admin` `A(venues of own org)` — which is
read-path inheritance. Naming the helper makes the grant honest and stops every policy from re-inlining the
same two-table join, which is the *"hundreds of policy clauses"* failure mode the domain architecture designs
against.

### 2.5 The caller-dependent predicate, closed (ROLE_MODEL defect 14.1 — HIGH)

`has_venue_role` previously read **`venue.staff_role` on the staff path and `venue.door_pin` on the door
path** — a predicate whose *meaning depended on who called it*. A reviewer looking at
`USING (kernel.has_venue_role(venue_id, ARRAY['venue_manager']))` had to know whether a loginless, shared,
deliberately weak device PIN could ever satisfy it. That is precisely the class of confusion C36 was ratified
to eliminate one level up, reintroduced one level down.

**Closed by R-8 + RM-5.** `has_venue_role` reads `venue.staff_role` **only**; the door is authorized by
`kernel.assert_door_session` **inside a definer RPC**, never in a policy. After the change the answer is
always *no*, for every policy in the corpus, without reading the helper.

**Warning for the implementing engineer:** `auth.uid()` is **NULL** on the door path. Every policy and RPC that
assumes a non-null `auth.uid()` must be re-read against the door flow — but because the door reaches the
database only via `service_role`, RLS is bypassed on that path entirely and the *only* gate is
`assert_door_session`. That is a deliberate concentration of the door's whole authorization surface into one
auditable function; it is also a single point of failure, and must be treated as security-critical.

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
| **I-12** | **INV-NOFORCE — the three authz tables MUST NOT carry `FORCE ROW LEVEL SECURITY`** (NEW; ROLE_MODEL §6.5 / defect 14.2) | `kernel.org_member`, `venue.staff_role`, `kernel.platform_role` each grant a **role-gated read of themselves** (§7.3, §9.9, §7.4). A naïve policy calls `has_*_role`, which `SELECT`s that same table, which fires the policy again. The model does **not** recurse only because the helpers are `SECURITY DEFINER` owned by `postgres` and **the table owner bypasses row-level security**. `FORCE` removes that bypass. See §3.2. |

### 3.1 EDGE-CALLER-JWT — the binding rule for every edge function on a money or custody path (NEW)

> **An edge function holding `SUPABASE_SERVICE_ROLE_KEY` MUST NOT invoke a money or custody RPC with a
> service-role client.** For any RPC that authorizes on **caller identity**, the edge function MUST construct
> its Supabase client from the **caller's own `Authorization` header**, so that `auth.uid()` and `auth.jwt()`
> resolve to the human *inside the transaction*. The service-role key may be used for that function's other
> work — Stripe calls, KMS calls, webhook callbacks, denial logging, push fan-out — but **never** to invoke a
> money or custody RPC on a human's behalf.

**Why this is not a style preference.** On a service-role client, inside the RPC:

- `auth.uid()` is **NULL**, so **every** `has_org_role` / `has_venue_role` / `is_platform` check
  **silently degrades** — the predicate does not error, it returns false, or worse, an implementer "fixes" it
  by passing the actor in as a parameter;
- `auth.jwt()` is the service token: **no `uid`, no `aal`, no `amr`**, so step-up freshness
  (`authn.money_action_required_aal` / `authn.money_action_max_age_seconds`) is unenforceable and the
  destination-change control set collapses to the cool-down alone;
- the only remaining way to name the actor is for the **edge to attest it as a parameter** — which is exactly
  the client-supplied-authority pattern **ratified row C35 forbids**, and which §0.1 of the RPC contracts
  forbids in the same words (*"the acting principal is always `p_actor := auth.uid()` — server-derived, never
  a client parameter"*).

This is what makes the edge spec's *"the edge passes ids; the RPC decides — no role logic in the edge"* true
rather than aspirational. The money-authority spec records it as **the single highest-severity correction in
its document**. The edge integrator states the mirror of this rule in `PHASE_2_EDGE_FUNCTION_SPEC.md`
§3.4/§3.5; both statements must exist, because either document alone can be read as describing the other's
job.

**Scope — which RPCs the rule binds.** Every RPC in §11 whose "may invoke" column names a *human* predicate:
all `request_*` / `approve_*` / `cancel_*` money RPCs, every refund and payout RPC, every custody RPC reachable
from a user action, every role-grant RPC, `set_org_payout_destination`, and the CRM-export authorization. It
does **not** bind the six **definer-only** RPCs (`catalog.engage_door_freeze`,
`venue.append_door_manifest_delta`, `kernel.record_money_denial`, `kernel.sweep_expired_refund_requests`,
`market.sweep_expired_p2p_transfers`, `market.sweep_paid_pending_sales`, `kernel.sweep_expired_door_overrides`,
`catalog.sweep_implicit_door_freezes`) — those have **no human actor by construction**, are `GRANT
EXECUTE`ed to `service_role` only, and are the *only* sanctioned use of a service-role client against this
schema.

**Consequence for the door.** The door path is the deliberate exception that proves the rule: it has no
`auth.uid()` *by design*, and therefore may not authorize on caller identity at all. Its authority comes from
`kernel.assert_door_session(device_id, session_id)` re-validating a **server-validated device assertion**
against live tables — not from an edge attestation of a human. A door RPC that accepted an edge-supplied
`p_actor_identity` would be the same C35 violation wearing a different hat.

### 3.2 I-12 in detail — why a one-line hardening change fails the whole authz model closed

`FORCE ROW LEVEL SECURITY` is a plausible, well-intentioned one-line change during any hardening sprint. On
these three tables it is catastrophic and **Postgres reports it as a policy error at query time, not at
migration time** — so it passes review, passes migration, and fails in production on the first authorized read.
When it fires, `has_org_role` / `has_venue_role` / `is_platform` all fail, and because every capability in
this document is gated by one of them, **the entire authorization model fails closed, platform-wide.**

> **INV-NOFORCE.** `kernel.org_member`, `venue.staff_role` and `kernel.platform_role` MUST NOT carry
> `FORCE ROW LEVEL SECURITY`. The predicate helpers depend on owner-bypass to terminate. Any migration or
> hardening pass proposing `FORCE` on these three tables is **rejected at review**. These three are the
> **only** tables in the model with this exemption.

**A documented rule that nothing checks is a rule that lasts until the first hardening sprint**, so I-12 is
discharged as a **positive assertion**, not prose:

- **Staging verification** of the package that creates each table asserts
  `pg_class.relforcerowsecurity = false` for `kernel.org_member`, `venue.staff_role`,
  `kernel.platform_role` — a *positive* equality on the catalog, not the absence of a `FORCE` statement in the
  migration text (which a later migration could add).
- **pgTAP, permanently:** three assertions in the standing suite, one per relation, so the check survives the
  package that introduced it and fails CI on any future migration that flips the flag.
- **The assertion is stated as an allow-list, not a scan:** exactly these three relations are exempt from
  `FORCE`; the same suite asserts that no *other* Phase-2 relation depends on owner-bypass to terminate a
  policy (i.e. no other table's policy calls a helper that reads that same table).

Migration-plan integration (`M-3`) is the schema/plan integrator's edit; recorded here so the assertion has an
owner. **See §16 for the policy and test names.**

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
| `venue.attribution` | promoter/org read; RPC-only (AO) | `venue.resolve_order_attribution`, in `finalize_primary_order` (§9.17) | commission basis |

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
| `kernel.identity_demographic` | **none — no client role holds any column grant** | entire table → `kernel.get_my_demographics()` (own row only); **never cross-identity, never platform** |
| `kernel.identity_demographic_erasure` | **none** | entire table → definer/`service_role` only; **no human role, including `platform_admin`** |
| `venue.holder_mix_snapshot` · `venue.holder_mix_bucket` | **none** | entire table → `venue.get_holder_mix()` (role- and scope-checked) |
| `kernel.identity_contact_pref` | **none** | entire table → `kernel.get_my_contact_prefs()` (own row) |
| `kernel.org_contact_consent` | **none** | entire table → `kernel.list_my_org_contact_consents()` (own rows); the export build-time gate is definer-internal |
| `kernel.org_customer_key` | **none** | definer / `service_role` only; **no human role, including `platform_admin`** |
| `venue.export_job` | **none** | entire table → `venue.list_export_jobs()` (role- and scope-checked) |
| `venue.promoter_code` · `promoter_code_scope` | **none** | org/venue back office reads own-org rows; **promoter reads own codes only** (§9.17) |
| `kernel.wallet_pass` | **none** | owner reads `{wallet_pass_id, ticket_atom_id, status, built_at, last_updated_at}` for **own** atoms via RPC; `auth_token_enc`, `auth_token_hash`, `serial_no_opaque` granted to **no role but `service_role`** and returned by no RPC |
| `kernel.pass_type_cert` | **none** | `certificate_pem`/`wwdr_cert_pem`/`not_after` → `is_platform`; `kms_handle_ref` → `is_platform` only. **Deliberate contrast with `kernel.signing_key`**, whose `public_key` *is* world-readable because doors need it — **doors never verify the Apple signature**, so this gets no public projection |
| `venue.door_manifest_entry` | **none** | the door's bulk read is `(ticket_atom_id, serial_no, credential_version, signing_key_id, ticket_state)` via `venue.get_door_manifest`. **The table carries no identity column by construction**, which is what keeps *"door staff never receive a bulk attendee list"* true even though the door now holds a legitimate bulk read |
| `notify.notification` | own row: `{type_key, group_label, rendered_title, rendered_body, target_kind, target_id, read_at, created_at}` | **`UPDATE (read_at)` only** — RLS restricts rows, not columns, so without the column grant a user could rewrite `title`/`body`/`params`/`type_key`/`dedupe_key` on their own rows |

> **The three tiers of column protection, and when each applies** (from the privacy spec's taxonomy, which
> governs every row above):
> 1. **Reduced public-safe subset** — the 068 pattern: grant `authenticated` a named safe column list. Valid
>    only where a genuinely public-safe subset exists (`display_name`, `avatar_url`).
> 2. **Empty grant set** — *not a reduced set, an empty set.* Used wherever **no column is public-safe**.
>    `INFERENCE:` this is the load-bearing rule and the reason the demographic and contact tables look
>    different from everything else: **column privileges in Postgres are per-role, not per-row**, so a column
>    granted to `authenticated` is readable on **any** row, not just the caller's own. A single column grant
>    on `kernel.org_contact_consent` would publish a map of who allows which venue to email them. **The
>    absence of a grant is the enforcement** — RLS is belt and braces behind it.
> 3. **Definer-only, no human role at all** — `kernel.identity_demographic_erasure`, `kernel.org_customer_key`.
>    Not even `platform_admin`.

---

## 7. Schema `kernel` — matrices

> Reminder (GP-1/GP-2): INS/UPD = `R` where EXEC authorizes, else `D`; **DEL = `D` for all roles, all tables**.
> `svc` = machine/definer path only (I-8).
>
> **Reading the matrices after the role-model integration (§1.1, §2).** Three mechanical rules apply to every
> matrix in §7–§10, so they are not repeated per table:
> 1. **`venue_door` is now `venue_scanner`** everywhere. Wherever the old `venue_door` cell described a
>    *PIN-path* capability (manifest sync · scan/admit · offline batch · guest-entry check-in — ROLE_MODEL §5.3
>    F7–F10), the **door session** (`DOO`) shares that cell; **everywhere else the door session is `D`.** A
>    `DOO` cell is always a statement about what the RPC permits, never about a policy (RM-5).
> 2. **`promoter` is a relationship, not a venue-plane role.** Every `promoter` cell below is an **own-row**
>    statement resolved by `kernel.is_promoter_for_event` / `promoter_link.identity_id = auth.uid()` /
>    `venue.promoter.identity_id = auth.uid()` on a **live** row — never by `has_venue_role`, which returns
>    false for every promoter. A `promoter` cell confers no authority over any venue object.
> 3. **The five new labels** (`org_marketing`, `org_promoter_manager`, `venue_box_office`, `venue_marketing`,
>    `venue_promoter_manager`) are `D` on every table in §7–§10 **except** where a matrix names them
>    explicitly. Deny-by-default (I-1) does the work; a new label does not inherit an old label's cells. Their
>    positive grants are exactly the cells of the master matrix (§4A) — marketing on the event/marketing and
>    CRM surfaces, promoter-manager on the promoter engine, box office on issuance and door-adjacent reads.

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

### 7.3b `kernel.org_invite` — org-scoped + addressed-invitee (ADDENDUM A1 — schema §1.3b, migration 077)
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
| venue_scanner | A⁸(scan cols, session) | R⁹ | R⁹ | D | `record_scan` (state→scanned) |
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
atom lock, and only for its session (door_pin/venue_scanner scope).

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
| venue_scanner | D | D | D | D | — |
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
| venue_scanner | A¹³ | D | D | D | — (verifies with public_key in manifest) |
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

> **REPLACED WHOLESALE** by `PHASE_2_MONEY_AUTHORITY_SPEC.md` §2.1 under ratified owner ruling **O-3**. The
> previous matrix **contradicted this document's own §11**, which granted `org_owner` `request_org_payout`
> while §7.9 denied `org_owner` the read — *an owner who could request a payout it could not see*. O-3 resolves
> it in favour of §11: `org_owner` reads the org payout ledger and requests payouts. **The old SELECT row was
> the text that was wrong.**

Write RPCs: `close_settlement`, native-sale payout path, `pay_promoter_commission`, `request_org_payout`
(state advance), `hold_payout`/`release_payout` (state advance). Idempotency-keyed (Phase-0 discipline).

| Role | SEL | INS | UPD | DEL | EXEC |
|---|---|---|---|---|---|
| anon | D | D | D | D | — |
| fan | D | D | D | D | — |
| owner (payee identity) | V(own payout)¹⁵ᵃ | D | D | D | — |
| org_member | D | D | D | D | — |
| **org_owner** | **V(own-org payouts)**¹⁵ᵇ | D | **R** | D | **`request_org_payout` (own org; ≤ threshold direct, > threshold via approval)** |
| **org_admin** | **D**¹⁵ᶜ | D | D | D | **—** |
| org_finance | V(own-org payouts)¹⁵ᵇ | D | R | D | `request_org_payout` (own org; same threshold rule) |
| venue_finance | **V(own-venue *settlement-caused* payouts only)**¹⁵ᵈ | D | D | D | — |
| venue_manager / venue_scanner / venue_box_office / venue_marketing / venue_promoter_manager / door session / promoter | D¹⁵ | D | D | D | — |
| org_marketing / org_promoter_manager | D | D | D | D | — |
| platform_support | V | D | D | D | — |
| platform_risk | A(money read) | D | R | D | `hold_payout` · `release_payout` (dual-control seam, SoD-3) |
| platform_admin | A | R | R | D | admin payout ops (audited) · `hold_payout` · `release_payout` |
| service_role | A(machine) | R(def) | R(def) | D | definer (settlement/native-sale/commission) |

¹⁵ `promoter` reads own `promoter_commission` payout **only** via `venue.get_my_promoter_summary` (§16.9),
whose filter is derived from `auth.uid()` and cannot be widened by a parameter — never the org payout ledger
(CDM §8).
¹⁵ᵃ payee-identity read is `payee_identity_id = auth.uid()`, one row set, no org context.
¹⁵ᵇ **the ONLY read path is `kernel.list_org_payouts(p_org_id, …)` (§16.5)** — a definer read RPC requiring
`has_org_role(p_org_id,[org_owner, org_finance])` and filtering `payee_org_id = p_org_id`. **There is no
direct table SELECT grant for any org role** (GP-3a: no policy runs here).
¹⁵ᶜ **`org_admin` is DENY on the whole money plane.** Domain §7.2 states Org Admin *"cannot view or initiate
payouts/bank changes (that's Finance/Owner)"*, and O-2 constrains `org_admin` to *"general administration but
not unrestricted financial authority."* Deny rather than a narrow read grant, because `org_admin` is the role
most likely to be handed out liberally, and the payout ledger plus the refund ledger together are the complete
financial picture of the business — **widening later is a one-line matrix change; narrowing later is a
migration plus an operator-facing removal.** (`INFERENCE` in the money spec §3.4; residual tension with
`org_admin`'s existing `A(own-org)` on `venue.settlement` (§9.13) is named, not smoothed — owner decision
**MD-4**, §15.7.)
¹⁵ᵈ **narrowed, and the narrowing is load-bearing.** `kernel.payout` has **no `venue_id`** (schema §1.9:
`payee_kind ∈ {organization, identity}`, `payee_org_id`/`payee_identity_id`, `cause`, `cause_ref`). A payout's
venue is derivable **only** for `cause='settlement'`, via `cause_ref → venue.settlement_line →
venue.settlement.venue_id`, and is **undefined** for `promoter_commission`, `market_sale`, and every
identity-payee payout. The previous unqualified *"V(own-venue payouts)"* was **not expressible against the
physical schema.** `venue_finance` reads settlement-caused payouts for its own venue and is `D` on every other
cause. Enforced **inside `kernel.list_org_payouts`, never as a table policy.**

### 7.10 `kernel.refund` — money-custody-RPC-only

> **REPLACED WHOLESALE** by `PHASE_2_MONEY_AUTHORITY_SPEC.md` §2.2 under ratified owner ruling **O-1**. The
> previous matrix denied every org role but `org_finance` any refund authority, while Domain §7.6 granted
> *Issue refund* to Org Owner. The "Org Owner **inherits** Org Finance" prose cannot bridge that:
> `kernel.org_member.role` is **single-valued** and C36 permits only a literal membership-row label test, so
> **no `org_owner` row can ever satisfy `has_org_role(org,[org_finance])`.** Inheritance is prose, not a
> predicate. O-1 moves the *authority*; the *inheritance mechanism* is deleted.

Write RPCs: `refund_primary_order`, `admin_refund`, C25 auto-compensation sweep. **Org and buyer authority
enters exclusively through `kernel.request_order_refund` (§16.1), which calls `refund_primary_order` as
definer** — the org never invokes the money writer directly.

| Role | SEL | INS | UPD | DEL | EXEC |
|---|---|---|---|---|---|
| anon | D | D | D | D | — |
| fan | D | D | D | D | — |
| owner (buyer) | V(own refund) | **R** | D | D | **`request_order_refund` (own order only; capped + windowed by config)** |
| org_member | D | D | D | D | — |
| **org_owner** | **V(own-org refunds)**²ᵃ | **R** | D | D | **`request_order_refund` · `approve_refund_request` (own org; SoD)** |
| **org_admin** | **D**²ᵇ | D | D | D | **—** |
| org_finance | V(own-org refunds)²ᵃ | R | D | D | `request_order_refund` · `approve_refund_request` (own org; SoD) |
| venue_finance | V(own-venue)²ᶜ | D | D | D | — |
| venue_manager / venue_scanner / venue_box_office / venue_marketing / venue_promoter_manager / door session / promoter | D | D | D | D | — |
| org_marketing / org_promoter_manager | D | D | D | D | — |
| platform_support | V | R | D | D | `refund_primary_order` (support-initiated, capped, audited) · `approve_refund_request` (platform-review tier) |
| platform_risk | A(money read) | R | D | D | `admin_refund` (dispute) · `approve_refund_request` (platform-review tier) |
| platform_admin | A | R | R | D | `admin_refund` · `refund_primary_order` · `approve_refund_request` |
| service_role | A(machine) | R(def) | R(def) | D | definer (incl. C25 sweep) |

²ᵃ **the ONLY read path is `kernel.list_org_refunds(p_org_id, …)` (§16.6).** `kernel.refund` carries no
`org_id` (schema §1.10 — `payment_id`, `reason_code`, `amount_minor`, `status`, refs). Org scope is resolved
`kernel.refund.payment_id → kernel.payment_native.payment_id → order_id → venue.order.org_id`
(`venue.order.org_id` is a real column — schema §3.7 — so this is a two-hop join, not a search). **The join
direction is part of the contract, not an implementation detail.** Refunds whose `payment_native` link is a
`sale_id` (native resale) resolve through `market.market_sale → listing → atom.org_id`; **in MVP native resale
is `resale_policy='off'` (Gate M), so that arm returns no rows and MUST fail closed rather than fall through.**
²ᵇ `org_admin` DENY on the money plane — see note ¹⁵ᶜ.
²ᶜ `venue_finance` own-venue read resolves through the same order join filtered on
`catalog.event_session → catalog.event.venue_id`; scope is venue, and it is a **read** only — **venue roles
hold no refund EXEC at any tier.**

> **Money-plane policy posture (GP-3a restated where it bites).** Neither §7.9 nor §7.10 carries an RLS policy
> admitting `authenticated`. Every `V` cell above is a **scoped read RPC**; every `R` cell is `EXECUTE` on a
> definer function. A policy written on these two tables would never be evaluated on the path that matters.
> The money-authority spec reaches the identical conclusion for step-up enforcement (§3.1).

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
| venue_scanner/finance/promoter | A(own venue) | D | D | D | — |
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
| venue_scanner/finance/promoter | A(own-venue announced+) | D | D | D | — |
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
| venue_scanner | A(own-venue, tonight) | D | D | D | — |
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
| venue_scanner/finance/promoter | A | D | D | D | — |
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
| venue_scanner | A(door_only + public, own session) | D | D | D | — |
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
| venue_scanner | A(remaining, own session) | R²⁴ | R²⁴ | D | door-sale reserve/issue path |
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
| venue_scanner | D²⁵ | R²⁴ | R²⁴ | D | via door reserve/issue |
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
| venue_scanner/promoter | D | D | D | D | — |
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
| venue_scanner | A(own session) | R | R | D | door reserve/release |
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
| venue_scanner | A(own session orders) | R²⁸ | D | D | door `create_order` |
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
| venue_scanner/finance/promoter | A(own-venue roster) | D | D | D | — |
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
| venue_scanner | A³²(own, no hash) | D | D | D | — (authenticates via the pin in the door RPC) |
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
| venue_scanner | A(own device) | D | R³³ | D | manifest-sync (own device) |
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
| venue_scanner | A(own session) | R | D³⁵ | D | `record_scan` |
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
| venue_scanner/promoter | D | D | D | D | — |
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
| venue_scanner/promoter | D | D | D | D | — |
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
| venue_scanner | A(own session) | D | D | D | — |
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
| venue_scanner | A(own session, check-in) | D | R³⁹ | D | check-in RPC (`status→arrived`) |
| venue_finance/promoter | D | D | D | D | — |
| platform_support/risk | A/V | D | D | D | — |
| platform_admin | A | R | R | D | override |
| service_role | A(machine) | R(def) | R(def) | D | definer |

³⁸ `guest_entry` rows are removed only via the parent guest-list RPC cascade, never client DELETE (GP-2).
³⁹ door updates only `status`/`checked_in_at` on entries for its session.

### 9.17 `venue.promoter` / `venue.promoter_link` / `venue.attribution` (Phase 2D)

> **`SPEC CORRECTION` — the attribution write moves from `create_order` to `finalize_primary_order`.**
> This section previously said *"attribution recorded in-txn by `create_order` (AO)"* and RPC §6.1 said the
> same. **Four documents disagreed with those two.** DA §1.7 says attribution is *"written when an attributed
> order is **paid**"*; CDM §1.3 defines it as *"an append-only record of a **sale**"*.
>
> The two were not merely inconsistent — the `create_order` placement is **unsatisfiable**. An append-only
> ledger row written for a **pending** order records a sale that has not happened and may never happen. Most
> abandoned carts never pay, so the ledger fills with rows every reader must then "ignore" — and an ignorable
> append-only ledger row is a contradiction in terms. It also makes the owner requirement *"immutable once
> economically committed"* impossible to satisfy, because the row would be frozen **before** the economic
> commitment, and it makes a promoter's dashboard show earnings that evaporate.
>
> **Resolution.** Attribution **freezes at the commit of the transaction that moves `venue.order.status` from
> `pending` to `paid`** — inside `venue.finalize_primary_order` (SSCAS member #1), in the same transaction that
> mints the atoms. Order-paid is the point where the platform first has irreversible economic consequence
> (money captured, tickets minted, capacity consumed); that is what *"economically committed"* means.
> (Ticket issuance is the same instant but the wrong **aggregate** — attribution is a property of the order,
> the money event, not of the ticket, the asset. Settlement close is far too late: the terms in force at
> settlement rather than at sale would govern the commission.)
>
> **Before the freeze the candidate is fully mutable**, held in two nullable columns on `venue.order` —
> `attribution_candidate_code_id`, `attribution_candidate_link_id` — writable **only while
> `order.status='pending'`** and frozen by a guard trigger the instant it leaves `pending`. The candidate is
> 1:1 with the order and dies with it, which is why it lives on the order row rather than in a second table
> the hottest write path would have to join.
>
> **After the freeze nothing can change who was credited** — not the promoter, not `venue_manager`, not
> `org_owner`, not `platform_admin`, not `service_role`. A rebind returns `attribution_frozen`; every UPDATE
> raises on the AO guard; DELETE is denied by GP-2; deactivating the code is **not retroactive** (eligibility
> is evaluated at freeze only); changing `commission_bps` binds new sales only, because the row snapshotted
> `terms_version` and the applied rate. **There is no "fix a wrong attribution" path by design** — the remedy
> is an off-ledger commercial settlement between the org and the promoter.
>
> **Second correction — the promoter's own-row predicate.** It must resolve
> `venue.attribution.promoter_id = auth.uid()`, **not** `attribution → link_id → promoter_link → promoter`.
> `link_id` is now nullable (a code-sourced attribution has no link), so the old join **silently returns zero
> rows for every code-sourced attribution** — a promoter would see none of their code earnings. This is the
> concrete reason `promoter_id` is denormalized onto the row, alongside `org_id`/`event_id`: an RLS predicate
> that joins two or three tables, evaluated per row on the largest table the promoter engine has, is the
> classic Postgres scale trap.
>
> **Third correction — promoter authority derivation.** Row 11 of §1.1 and §2.1 previously expressed
> "promoter" as `venue.staff_role.role = 'venue_promoter'`. After ROLE_MODEL §9.1 that label does not exist.
> Every promoter-facing read derives authority from **`venue.promoter.identity_id = auth.uid()` on a live
> row** (or `kernel.is_promoter_for_event`), never from `has_venue_role`.

Write RPCs: promoter CRUD; **attribution recorded in-txn by `venue.finalize_primary_order` via the internal
`venue.resolve_order_attribution` (AO)** — never by `create_order`. `promoter_link.slug` globally unique;
link IMM.

**`venue.promoter`** and **`venue.promoter_link`** (venue/org-scoped; promoter reads OWN):

| Role | SEL | INS | UPD | DEL | EXEC |
|---|---|---|---|---|---|
| anon / fan / owner | D | D | D | D | — |
| org_member | D | D | D | D | — |
| org_owner/admin | A(own-org) | R | R | D | manage promoters/links |
| org_finance | A(own-org) | D | D | D | — |
| venue_manager | A(own-venue) | R | R | D | manage promoters/links |
| venue_finance | A(own-venue) | D | D | D | — |
| venue_scanner | D | D | D | D | — |
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
| org_member/venue_scanner | D | D | D | D | — |
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
| venue_scanner/finance/promoter | A(active) | D | D | D | — |
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
| venue_scanner/promoter | D | D | D | D | — |
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

**Two grant classes, and the distinction is load-bearing.**

- **Caller-authorized** — `GRANT EXECUTE TO authenticated`, authority decided in-body from `auth.uid()`.
  **Every one of these is bound by EDGE-CALLER-JWT (§3.1):** an edge function fronting it MUST build its
  client from the caller's `Authorization` header. Invoking it with a service-role client makes `auth.uid()`
  NULL and silently degrades every predicate in the row.
- **Definer-only** — marked **`DEF`** below. `REVOKE EXECUTE FROM anon, authenticated, public`, `GRANT
  EXECUTE TO service_role` **only**. Never in a UI path, never reachable from PostgREST. These have **no
  human actor by construction** and are the only sanctioned use of a service-role client against this schema.
  A `DEF` row appearing with an `authenticated` grant in a migration is a defect.

**GP-3a reminder:** this table *is* the authority model for every money and custody write. There is no table
policy behind it — see §1.3.

### 11.1 Core (pre-existing surface, reconciled)

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
| `kernel.refund_primary_order` | **`DEF`** (from `request_order_refund` / `approve_refund_request` / `catalog.cancel_event` / C25 sweep) · `is_platform([platform_support (capped), platform_admin])` — **role NARROWED**; buyer, `org_finance` and `org_owner` reach it only via `request_order_refund` |
| `kernel.admin_refund` | `is_platform([platform_risk, platform_admin])` |
| `kernel.close_settlement` | `has_org_role([org_finance])` · `has_venue_role([venue_finance])` · platform — *unchanged; `org_owner` still cannot close (it opens and reads). §15.3 remains open.* |
| `kernel.pay_promoter_commission` | definer (settlement path) |
| `kernel.provision/rotate/revoke_signing_key` | `is_platform([platform_admin])` |
| `catalog.create_venue` | `has_org_role([org_owner,org_admin])` |
| `catalog.set_venue_approval` | `is_platform([platform_admin])` |
| `catalog.create_event`/`set_event_status`/`cancel_event` | `has_org_role([org_owner,org_admin])` OR `has_venue_role([venue_manager])` |
| `catalog.create_event_session` | as create_event |
| `catalog.set_platform_config` | `is_platform([platform_admin])` (dual-control) |
| `catalog.set_resale_policy` | `has_org_role([org_owner,org_admin])` OR `has_venue_role([venue_manager])` · platform |
| `venue.create_ticket_type`/`set_ticket_type_price` | `has_venue_role([venue_manager])` OR org_owner/admin (live-recheck, C9) |
| `venue.reserve_inventory`/`release_hold` | any `authenticated` (own hold) · `has_venue_role([venue_manager,venue_scanner])` |
| `venue.create_order` | any `authenticated` (own) · door/staff on-behalf (`has_venue_role([venue_scanner,venue_manager])`) |
| `venue.grant_staff_role`/`revoke_staff_role` | `has_venue_role([venue_manager])` OR org_owner/admin inheritance; no self-grant |
| `venue.issue_door_pin`/`revoke_door_pin` | `has_venue_role([venue_manager])` OR org_owner/admin |
| `venue.register_scan_device` / manifest-sync | `has_venue_role([venue_manager])`; sync also `venue_scanner` (own device) |
| `venue.record_scan` | **two entry paths, both landing in the same definer function:** (a) `has_venue_role(venue,[venue_scanner, venue_manager])` — an authenticated, individually attributable staff principal; (b) the `service_role` edge path with `kernel.assert_door_session(device_id, session_id)` asserted in-body. **Never a `door_pin` tested by `has_venue_role`** (R-8) |
| `venue.open_settlement`/`close_settlement` | `has_venue_role([venue_finance])` OR `has_org_role([org_finance])` · platform |
| **`venue.allocate_comp`** *(capacity — SPLIT per R-15/E6)* | `has_venue_role(venue,[venue_manager])` OR `has_org_role_over_venue(venue,[org_owner,org_admin])`. **C39-gated** (step-up + live-grant re-check above the per-staff threshold). **`venue_box_office` is DENIED** — allocating comp *capacity* is an inventory decision |
| **`venue.issue_comp`** *(issuance — SPLIT per R-15/E7)* | `has_venue_role(venue,[venue_manager, venue_box_office])` OR `has_org_role_over_venue(venue,[org_owner,org_admin])`. **C39-gated.** Issuing **one** comp against an already-allocated batch is an issuance operation, which is exactly what O-2 grants box office (*"ticket issuance / permitted inventory-sale operations only"*) and nothing more. Per-staff comp totals stay visible to `venue_manager` and above — this is the insider-fraud control surface and hiding it defeats it |
| `venue.record_offline_scans` | as `venue.record_scan` — `has_venue_role([venue_scanner, venue_manager])` OR the `service_role` edge path with `assert_door_session` (own device only) |
| `market.create_listing`/`cancel_listing` | owner of the atom · platform (cancel) |
| `market.create_auction` / bid RPC | listing seller (create) · any `authenticated` (bid) |
| `market.make_offer`/`respond_offer` | any `authenticated` (offer) · listing seller (respond) |
| `market.create_p2p_transfer`/`accept_p2p_transfer` | atom owner (create) · resolved recipient (accept) |
| **read RPCs** `get_ticket_custody_chain` · `get_ticket_history` · `get_market_sale_status` | scoped as §14 |

### 11.2 Predicate helpers and the door session

| RPC | May invoke |
|---|---|
| `kernel.has_org_role` · `has_venue_role` · `has_event_role` · `is_platform` | `authenticated` (pure predicates; `STABLE`, live reads) |
| `kernel.has_org_role_over_venue` · `has_org_role_over_event` · `is_org_affiliate` | `authenticated` |
| `kernel.is_promoter_for_event` | `authenticated` |
| **`kernel.assert_door_session(device_id, session_id)`** | **`DEF`** — `service_role` only. Security-critical: it is the *entire* authorization surface of the door path. Covered by the package's adversarial verification |

### 11.3 Money authority (money spec §2.3 — replaces the corresponding §11.1 rows)

| RPC | May invoke (predicate, live-rechecked) |
|---|---|
| **`kernel.request_order_refund`** *(NEW)* | owner-of-order (`venue.order.buyer_id = auth.uid()`, capped + windowed) · `has_org_role(order.org_id,[org_owner, org_finance])` · `is_platform([platform_support, platform_risk, platform_admin])`. **`org_admin` and every venue role are forbidden callers.** |
| **`kernel.approve_refund_request`** *(NEW)* | `has_org_role([org_owner, org_finance])` **AND `auth.uid() <> request.requested_by`** — SoD-2 enforced structurally, and **self-approval is its own named failure** so the UI can say *"a different person must approve this"* rather than a bare 403 · `is_platform([platform_support, platform_risk, platform_admin])` for the platform-review tier |
| **`kernel.cancel_refund_request`** *(NEW)* | the requester · `has_org_role([org_owner, org_finance])` · platform |
| **`kernel.sweep_expired_refund_requests`** *(NEW)* | **`DEF`** — scheduler only. **Not optional:** without it a parked request is an unbounded denial-of-admission on a paying customer's ticket |
| **`kernel.list_org_payouts`** *(NEW read)* | `has_org_role([org_owner, org_finance])` · `has_venue_role([venue_finance])` (settlement-cause rows, own venue only) · `is_platform` |
| **`kernel.list_org_refunds`** *(NEW read)* | `has_org_role([org_owner, org_finance])` · `has_venue_role([venue_finance])` (own venue) · `is_platform` |
| **`kernel.list_approval_requests`** *(NEW read)* | `has_org_role([org_owner, org_finance])` (own org) · platform — the approval queue |
| **`kernel.record_money_denial`** *(NEW)* | **`DEF`** — service_role only, **no human path**. Exists because a failed predicate `RAISE`s, which rolls back the transaction **and takes the audit row with it** (§0.3 writes audit in-txn; Postgres has no autonomous transactions). Repeated failed attempts to change a payout destination or fire a payout are the highest-value fraud signal in the system and are otherwise **invisible**. The edge catches `insufficient_privilege`/`sod_violation`/`step_up_required` and calls this **in a separate transaction** |
| `kernel.request_org_payout` | `has_org_role([org_finance, org_owner])` — *unchanged, now consistent with §7.9*. **Adds three preconditions:** the destination-probation hold, the **SoD-1 destination-setter exclusion** (rejects when `auth.uid() = organization.payout_destination_set_by`, **permanently for that destination**, with `sod_violation` — not merely during the cool-down), and the step-up predicate. Above `payout.dual_control_min_minor` it parks an approval instead of advancing |
| `kernel.set_org_payout_destination` | `has_org_role([org_owner])` **only** · **step-up + SoD + probation**. `org_finance` is **excluded entirely** — under O-3 it holds payout-request authority, and one identity may not hold both halves of the SoD-1 fraud primitive (*redirect the account, then release funds to it*) |
| `kernel.hold_payout` / `kernel.release_payout` | `is_platform([platform_risk, platform_admin])` — *unchanged; SoD-3, **no org role, ever***. (Domain §7.6 previously marked Org Finance ✔ on *Release held funds*; a risk-placed hold released by the org it was placed on is the control inverted. Corrected to blank.) |
| `catalog.set_platform_config` | `is_platform([platform_admin])`; **for keys in the `refund.*` / `payout.*` / `authn.*` namespaces dual control is MANDATORY, not a seam** — the call creates a `kernel.approval_request` a **second distinct `platform_admin`** must approve, and only the approval inserts the new `(key, version+1)` row. A threshold that gates money authority is exactly as money-consequential as the action it gates. **Direction asymmetry:** *lowering* a limit may execute directly; only *raising* one needs the second approver — a security control that is hard to tighten in an incident is a liability |

### 11.4 Door lifecycle (door spec §10A.7 — O-4 authority)

| RPC | May invoke (predicate, live-rechecked) |
|---|---|
| `venue.open_door_manifest` · `venue.close_door_manifest` | `has_venue_role(venue,[venue_manager])` OR `has_org_role_over_venue(venue,[org_owner, org_admin])` OR `is_platform([platform_admin])`. **`venue_scanner`, the door session, `venue_box_office`, every finance / marketing / promoter role, `platform_support` and `platform_risk` are explicitly excluded (O-4).** Opening the manifest freezes custody for the whole session — a scanner may not create the security boundary it works inside |
| `venue.set_door_open_at` (O4-3) · `venue.set_event_security_config` (O4-4) | as above |
| `venue.get_door_manifest` | `has_venue_role(venue,[venue_scanner, venue_manager])` OR the `service_role` edge path with `assert_door_session` bound to that session |
| **`catalog.engage_door_freeze`** | **`DEF`** — the **sole writer** of `catalog.event_session.door_open_at`. Never granted to `authenticated`, never a UI path, and **appears in no other EXEC row**. A trigger enforces this independently of grants |
| **`venue.append_door_manifest_delta`** | **`DEF`** — appends `add`/`revoke` deltas to the open episode |
| `catalog.effective_freeze_at` · `kernel.is_transfer_frozen` | `authenticated` (`STABLE` reads; `is_transfer_frozen` is already the RN eligibility boolean, §14.3) |
| `kernel.grant_door_freeze_override` | `is_platform([platform_admin])` **only** — an override defeats a safety property, so it requires authority strictly above the authority that engaged the freeze. Refused while any episode is `open` |
| `kernel.revoke_door_freeze_override` | `is_platform([platform_admin, platform_risk])` — risk may **tighten**, never **loosen** |
| `kernel.sweep_expired_door_overrides` · `catalog.sweep_implicit_door_freezes` | **`DEF`** — cron. **Neither is load-bearing for correctness**; the helper computes the boundary arithmetically whether or not either ever runs |

### 11.5 Promoter engine and codes (Phase 2D)

| RPC | May invoke (predicate, live-rechecked) |
|---|---|
| `venue.create_promoter_code` · `create_promoter_codes_bulk` · `set_promoter_code_status` · `set_promoter_code_scope` · `set_promoter_code_window` | `has_venue_role(venue,[venue_manager, venue_promoter_manager])` OR `has_org_role([org_owner, org_admin, org_promoter_manager])`, scoped to the promoter's org. **A promoter is explicitly forbidden from minting their own codes** — a self-minted code is a self-minted *distribution surface* over the org's global namespace, and codes are immutable, so a grab of `CLUBSPACE` or a rival's brand is permanent |
| `venue.preview_promoter_code` | `authenticated`; **also reachable unauthenticated only through the `promoter-code-preview` edge wrapper** — see §11.8 |
| `venue.bind_order_attribution` | the order's buyer (`auth.uid() = order.buyer_id`) OR a door/box-office principal for an on-behalf order. Rejects with `attribution_frozen` once `order.status <> 'pending'` |
| `venue.review_attribution_flag` | `has_venue_role(venue,[venue_manager, venue_promoter_manager])` OR `has_org_role([org_owner, org_admin])` · `is_platform([platform_risk])`. **`platform_admin` holds no EXEC here.** Rejects `attribution_settled` once a `promoter_commission` settlement line exists — the money and the decision freeze together |
| **`venue.resolve_order_attribution`** | **`DEF`** — the precedence engine, called only from `venue.finalize_primary_order` inside the paid transaction. **`REVOKE EXECUTE FROM anon, authenticated`.** It **never raises for an attribution problem**: a raise here would roll back the money and the tickets. A missing commission is a support ticket; a failed checkout on a sold-out Friday is a business incident |
| `venue.get_my_promoter_summary` · `venue.list_my_attributions` | authority derived from **`venue.promoter.identity_id = auth.uid()` on a live row** (C9), never from `has_venue_role`. The promoter id set is derived from `auth.uid()` and **is not accepted as input**, so the filter cannot be widened by a parameter |
| `venue.list_promoter_attributions` | `has_venue_role([venue_manager, venue_finance, venue_promoter_manager])` OR `has_org_role([org_owner, org_admin, org_finance, org_promoter_manager])`. **`venue_scanner`, the door session, `org_member` and `promoter` denied outright.** Returns an order *reference*, never an attendee — the promoter dimension is not a back door into the attendee list |
| **`venue.decide_flagged_attribution`** (G5, dashboard Δ7) | `has_venue_role(venue,[venue_manager])` OR `has_org_role_over_venue(venue,[org_owner, org_admin])` · `is_platform([platform_risk])`. **Both promoter-manager labels are DENIED** — a promoter manager adjudicating a flag against a promoter they recruited and are measured on is the fox at the henhouse (SoD; same principle as propose-vs-approve) |

### 11.6 CRM export and attendee reads

| RPC | May invoke (predicate, live-rechecked) |
|---|---|
| `venue.list_attendees` (F11/F12, dashboard Δ3) | `has_venue_role(venue,[venue_manager, venue_marketing])` OR `has_org_role_over_event(event,[org_owner, org_admin, org_marketing])` OR `has_venue_role([venue_finance])` / `has_org_role([org_finance])` **for the money-only projection** OR `is_platform([platform_support, platform_risk, platform_admin])`. **Column-scoped by role: denied classes are ABSENT from the result shape, not null.** Denied: `venue_box_office`, `venue_scanner`, the door session, `promoter`, both promoter-manager labels, `org_member`, `fan`, `anon` |
| `venue.lookup_attendee` (single record, service context) | `has_venue_role(venue,[venue_manager, venue_box_office])` OR `has_org_role_over_venue(venue,[org_owner, org_admin])` · `is_platform([platform_support])`. **Denied to both marketing labels.** Audited with the **query kind only, never the value** — logging a probed address would build the harvest list inside our own audit |
| `venue.request_export` — **audience** template | `has_org_role([org_owner, org_admin, org_marketing])` (org grain) · `has_venue_role([venue_manager, venue_marketing])` (venue grain). **The plane of the grant is the export scope.** `scope_kind='all'` is not a member of the CHECK set |
| `venue.request_export` — **operations** template (adds money columns) | `has_org_role([org_owner, org_admin])` · `has_venue_role([venue_manager])` **only** — the narrowest allow-list in this document. Finance sees money and no contact; marketing sees contact and no money; **only these three hold the union** |
| **`venue.build_export_rows`** | **`DEF`** — `REVOKE EXECUTE FROM anon, authenticated`, **no human path**. Re-derives authority from **the job row's recorded actor and scope**, not from the caller. Contains **no dynamic SQL** |
| **`venue.finalize_export`** | **`DEF`** |
| `venue.authorize_export_download` | the X8 set (`org_owner`, `org_admin`, `org_marketing`, `venue_manager`, `venue_marketing`), **re-checked live against the grant tables at this instant** — an export prepared before a revocation fails after it. 300-second signed URL |
| `venue.revoke_export` | the requester · `has_venue_role([venue_manager])` / `has_org_role([org_owner, org_admin])` over the job's scope · `is_platform([platform_admin])` (**the one export-lifecycle write a platform role holds — revoking is not extraction**) |
| `venue.list_export_jobs` | `has_org_role([org_owner, org_admin, org_marketing])` · `has_venue_role([venue_manager, venue_marketing])` · `is_platform([platform_support, platform_risk, platform_admin])`. **Job metadata only — never a row, never an object path, never a signed URL** |
| **`venue.sweep_expired_exports`** | **`DEF`** — `pg_cron` hourly |

> **PLATFORM ROLES READ THE ROSTER; THEY DO NOT USE THE VENUE CRM EXPORT.** This closes a live conflict:
> the role-model matrix (F12) marks `platform_risk`/`platform_admin` `A` on bulk attendee list/export, while
> the venue dashboard's allow-list omits them. **Both are right about different things.** Platform roles may
> **read** the roster (they hold `V`/`A` on the read rows, and F12's grant is a read grant). They may **not
> request a venue CRM export**. The venue export is scoped, templated and audited *as a venue action*: its
> audit row names a venue actor and lands in that venue's activity feed. A platform bulk extraction has a
> different justification, a different retention, and needs dual control; running it through the venue's own
> surface would file a platform action in a venue's history and would hand a compromised platform account the
> venue export's rate limits rather than a platform-grade one. **Platform bulk extraction is not built in
> Phase 2** (owner decision **MD-8**, §15.7).
>
> **Dashboard §9.6's export allow-list predates the `marketing` role.** It gains `org_marketing` (org grain)
> and `venue_marketing` (venue grain), **audience template only**; its deny-list gains `venue_box_office`,
> `venue_scanner`, `venue_promoter_manager`, `org_promoter_manager`, and `venue_door` → `venue_scanner`.

### 11.7 Demographics, wallet, notifications, and the remaining new surfaces

| RPC | May invoke (predicate, live-rechecked) |
|---|---|
| `kernel.get_my_demographics` · `set_my_demographics` · `clear_my_demographics` | `authenticated`, **own row only**. All three are **parameterless or carry no identity parameter of any type** — "read someone else's row" must be *inexpressible*, not merely denied. There is **no staff write path and no `admin_set_demographics`** |
| `venue.get_holder_mix` | `has_venue_role(venue,[venue_manager, venue_marketing, venue_promoter_manager])` OR `has_org_role_over_event(event,[org_owner, org_admin])` OR `is_platform([platform_admin])`. Denied: `org_finance`, `venue_finance`, `venue_box_office`, `venue_scanner`, the door session, `promoter`, `platform_support`, `platform_risk`, `fan`, `anon`. **Exactly two parameters — adding a third is a design change requiring privacy re-review, not a routine enhancement** (it is the differencing-attack contract) |
| **`venue.refresh_holder_mix`** · the nightly rollup-reconciliation job | **`DEF`** — `pg_cron`; `REVOKE EXECUTE FROM anon, authenticated` |
| `kernel.get_my_contact_prefs` · `set_my_contact_prefs` · `list_my_org_contact_consents` · `grant_org_contact_consent` · `withdraw_org_contact_consent` | `authenticated`, **own rows only**. **No `p_identity_id` parameter exists anywhere** — a venue can never record a contact consent on a fan's behalf |
| `kernel.mint_wallet_pass` | `authenticated`; authorizes `kernel.tickets.current_owner_id = auth.uid()` **in-body, live-read** (C35/I-5). Gated on `config('wallet.apple.enabled')`, and **the kill switch is not role-bypassable** — `platform_admin` also gets `wallet_disabled` |
| `kernel.revoke_wallet_pass` | `is_platform([platform_admin, platform_support])` |
| `kernel.provision_pass_type_cert` · `rotate_pass_type_cert` · `revoke_pass_type_cert` | `is_platform([platform_admin])` **only**, dual-controlled, audited |
| **`kernel.supersede_wallet_passes_for_atom`** · `touch_wallet_pass` · `get_wallet_pass_build_context` · `register_wallet_pass_device` · `unregister_wallet_pass_device` · `list_updated_wallet_passes` · `record_wallet_push_result` · `sweep_wallet_pass_lifecycle` | **`DEF`** — `REVOKE EXECUTE FROM anon, authenticated, public`. `supersede_…` is called **from the outbox consumer, not inside the custody transaction**, so a Wallet outage can never roll back or block a transfer |
| `notify.get_inbox` · `get_unread_count` · `mark_read` · `mark_all_read` · `dismiss` · `get_preference_matrix` · `set_preference` · `register_push_token` · `revoke_push_token` | `authenticated`, `auth.uid()`-scoped |
| `notify.draft_announcement` | `has_venue_role([venue_manager, venue_marketing])` OR `has_org_role([org_owner, org_admin])` |
| `notify.approve_announcement` · `cancel_announcement` · `revoke_announcement` | `has_venue_role([venue_manager])` OR `has_org_role([org_owner, org_admin])`. **Never a marketing label** — drafting and releasing are distinct acts (SoD). Above the blast-radius threshold, release requires a **second distinct approve-authorized principal**, so one compromised credential cannot blast a stadium |
| `notify.preview_announcement_audience` | as `draft_announcement`. **Returns a COUNT only, never an enumeration** — there is no parameter through which an audience can be widened, which denies an audience-harvesting primitive |
| `notify.report_announcement` | `authenticated` (any recipient) |
| **`notify.emit_event` · `enqueue` · `channel_enabled` · `drain_outbox` · `sweep_scheduled` · `claim_deliveries` · `record_delivery_result` · `resolve_web_link`** | **`DEF`** — `REVOKE ... FROM PUBLIC, anon, authenticated`, `GRANT ... TO service_role` |
| `venue.read_operational_audit` (A6, dashboard Δ2) | `has_org_role([org_owner, org_admin, org_finance])` OR `has_venue_role([venue_manager, venue_finance])`, **restricted to the caller's own org/venue subject and EXCLUDING the security plane**; plain verbs, no before/after payloads. Platform reads the security plane via the existing `is_platform` path |

### 11.8 The one rate-limit adaptation, recorded as an adaptation

`public.check_rate_limit(p_user_id **uuid**, p_action text, p_limit int, p_window int)` is a **frozen Phase-0
function** (migration `005`), `GRANT EXECUTE … TO service_role` **only**. Two consequences bind this document:

1. **A rate-limited RPC cannot be a plain PostgREST call** — the limiter is unreachable from `authenticated`.
   That is why `venue.preview_promoter_code` is fronted by the `promoter-code-preview` edge function rather
   than being called directly.
2. **Its first parameter is a `uuid`, so it cannot rate-limit an unauthenticated principal at all.** A buyer
   may type a promoter code before signing in, and that path has no user uuid to key on.

> **Recorded as an adaptation of a frozen function's contract, not a change to it.** The edge wrapper
> **derives** a principal — `uuidv5(NS_PROMOCODE, ip || ':' || sha256(user_agent))` — and passes it as
> `p_user_id`. The function is unmodified; a synthetic uuid is supplied where a real one does not exist.
> Limits: 10/min authenticated, **5/min anonymous per derived principal**, **fail-closed** (503 on limiter
> error, 429 over-limit). This is flagged so it is a reviewed decision rather than a clever workaround, and
> because **it will recur for every future anonymous-callable edge function.** Owner: the edge-spec author.
>
> `INFERENCE:` the derived principal is a *rate-limiting* key only. It is never persisted as an identity,
> never joined to a real `auth.users` row, and never used in an authorization predicate. An IP+UA hash is a
> weak, spoofable key; it is proportionate for an advisory preview whose every failure mode returns the same
> `not_applicable` payload, and it would **not** be proportionate for anything that writes.

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

### 14.3 Door-freeze signal (#3) — **CORRECTED (door lifecycle spec §3, §7.6, §13.1–§13.5)**

Transfer/Sell must disable once the event is underway (C6). The stored signal is
`catalog.event_session.door_open_at`; the ONLY authorization read is the derived helper
`kernel.is_transfer_frozen(ticket_atom_id)` — there is **no stored `kernel.tickets.transfer_frozen` column**.
This is a live-table recheck (I-5), never a client-trusted flag. The RN client reads the same helper
(owner-scoped boolean via the ticket read) to disable the buttons; the edge layer never independently decides
freeze. **`NO SCHEMA CHANGE` to the helper's signature or to any call site** — only its body and its recheck
set change.

#### 14.3.1 The corrected predicate — total, so the freeze can never silently fail to engage

The previous body was `door_open_at IS NOT NULL AND now() >= door_open_at`. That is **fail-open at NULL**: a
session whose manifest is never opened is never frozen. Replaced with:

```text
catalog.effective_freeze_at(p_session_id) -> timestamptz NOT NULL       -- NEW helper, STABLE
  := LEAST(
       door_open_at,                                           -- explicit: first manifest open (nullable)
       COALESCE(doors_at, starts_at) + config('door.implicit_freeze_offset_interval')
     )                                                         -- implicit backstop: NEVER null

kernel.is_transfer_frozen(p_ticket_atom_id) ->
       now() >= catalog.effective_freeze_at(session_of(atom))
   AND NOT EXISTS (active, unexpired kernel.door_freeze_override covering this atom)
```

`starts_at` is `NOT NULL` (schema §2.3), so **`effective_freeze_at` is total** — there is no input for which
it returns NULL, and therefore **no input for which the freeze silently never engages.** That is the
fail-closed property expressed as a type, not as a promise. `doors_at` rather than `starts_at` is the primary
backstop because `doors_at` is when humans physically arrive; `starts_at` is often an hour later, and freezing
there would leave an hour of live-door / open-transfer overlap — exactly the window C6 exists to close.

#### 14.3.2 **The narrowing four documents described and nothing implements — corrected**

Schema §2.3, RPC §12.4, **this section**, and the migration plan all previously said the freeze is *"narrowed
per-open-manifest-ticket, not blanket per-session, per C43."* **The specified predicate is session-wide.**
There is no per-ticket term in it, and none was ever specified. Worse, **C43 is
`RATIFIED-MODELED-ONLY(GATE-M)` — it is not MVP**, so the narrowing could not be implemented in Phase 2 even
if a predicate existed for it.

Four documents therefore described a mechanism that does not exist and cannot be built in this phase. **This
document now says what the mechanism does:**

> **MVP: the freeze is session-wide.** `is_transfer_frozen(atom)` is true for **every** atom of a session once
> `now() >= effective_freeze_at(session)`, subject only to an active override (§14.3.4). The
> per-open-manifest-ticket narrowing is a **purely additive conjunct** deferred to Gate M with C43; adding it
> later strictly *reduces* the frozen set and breaks nothing that depends on the MVP predicate.

`INFERENCE:` this is the reconciliation, not a new decision — the door spec keeps the session-wide predicate
for MVP and makes the narrowing additive. Restating it here removes an implementer's only reason to look for
a per-ticket term that was never written.

#### 14.3.3 The freeze recheck set — **CORRECTED; the old set is wrong in one direction and incomplete in three**

| RPC | Old §14.3 / RPC §12.4 | **This spec** | Why |
|---|:---:|:---:|---|
| `market.create_listing` | rechecks | **rechecks** | correct |
| `market.create_p2p_transfer` | rechecks | **rechecks** | correct |
| `kernel.lock_ticket` | rechecks | **rechecks** | correct — a choke-point |
| **`kernel.mark_ticket_scanned`** | **rechecks → rejects `frozen`** | **MUST NOT RECHECK** | **§14.3.5 — CRITICAL. As written, nobody gets in.** |
| **`kernel.transfer_ticket_ownership`** | absent | **rechecks — THE enforcement point** | the sole custody engine; enforcing here makes bypass structurally impossible |
| **`market.accept_p2p_transfer`** | absent | **rechecks** | the freeze gated transfer *start* but not *completion* — §14.3.6 |
| **`kernel.void_ticket_atom`** (routine refund path only) | absent | **rechecks** | C23 extends the freeze to refund-voids |
| `market.cancel_p2p_transfer` (cancel-to-self) | — | **exempt** | C43, ratified: owner and `credential_version` unchanged; nothing can strand |
| `market.cancel_listing` | — | **exempt** | delisting strands nothing |
| `catalog.cancel_event` | — | **exempt** | the session is being cancelled; no admission will occur |
| `kernel.force_void_ticket` · `kernel.admin_refund` | — | **exempt, audited** | platform break-glass; residual is the C6 reconcile window |
| `market.sweep_paid_pending_sales` — **complete** branch | — | **frozen** | it is a custody move |
| `market.sweep_paid_pending_sales` — **compensate** branch | — | **exempt** | §14.3.7 — otherwise the money is stranded forever |
| `kernel.issue_ticket_atoms` (door sale · comp · import) | — | **exempt — never frozen** | minting from ∅ is not a custody move; door-release inventory exists precisely to be sold after doors open |
| `kernel.request_order_refund` — **parked** branch only | — | **rechecks** | a parked refund places a custody hold; it must not be parked on a door-open session (money spec §5.5) |

**Every exempt path that voids an atom MUST write a `revoke` delta to the open manifest episode** (door spec
§7.7). Without it, the exemption re-opens the offline-revocation leak it was granted to avoid. This binds all
three voiding exemptions: `catalog.cancel_event`, `force_void_ticket`/`admin_refund`, and the C25 compensate
branch.

**Defense in depth, deliberately two-layered.** The **enforcement** points are
`kernel.transfer_ticket_ownership` and `kernel.lock_ticket` — the choke-points nothing bypasses. The
caller-level rechecks (`create_listing`, `create_p2p_transfer`, `accept_p2p_transfer`) exist for **error
quality**, so a fan sees *"Transfers are closed"* rather than a generic engine failure. Both layers must hold.

#### 14.3.4 The override, and what an RLS reader must know about it

`kernel.door_freeze_override` (audit-only class, §16.4) is an audited, TTL-bounded, reason-coded suspension of
the freeze's *effect*; it never alters the boundary, so `door_open_at` survives verbatim. Granting it is
`is_platform([platform_admin])` **only** — strictly above the authority that engaged the freeze — and it is
refused while any manifest episode is `open`, which is what preserves the Door Safety Theorem: **no custody
move can commit while an offline manifest is armed, override or not.** Revoking (tightening) additionally
allows `platform_risk`; the role that can *loosen* a safety property is strictly narrower than the role that
can *restore* it. Overrides expire arithmetically (`expires_at > now()` inside the helper) with **no sweep
required for correctness** — correctness that depends on a cron running is the failure class this whole area
exists to prevent.

#### 14.3.5 **CRITICAL — `mark_ticket_scanned` rejecting on `frozen` denies admission to every fan**

The previous text of this section, and RPC §12.4 verbatim, made `kernel.mark_ticket_scanned` re-check
`kernel.is_transfer_frozen` under the atom lock **and reject with `frozen`.**

**Trace it.** Opening the manifest sets `door_open_at`. `is_transfer_frozen` then returns **true for every atom
of the session** (§14.3.2 — the predicate is session-wide, and even after the corrected body it is true for
every atom past `effective_freeze_at`). `mark_ticket_scanned` is the custody-side transition
`active → scanned` that `venue.record_scan` invokes on the first valid admit. Therefore, **from the moment
doors open until the end of the night, every scan of every valid ticket is rejected. Nobody gets in.** This is
not a degraded mode or an edge case — it is the normal, intended operating sequence of every event, and it
fails 100% of admissions.

**Why the check was there, and why it is redundant.** The evident intent was that a mid-transfer atom must not
be scanned. **That is already fully enforced by the function's own precondition `resale_state = 'none'`** —
RPC §7.5, verbatim: *"a `listed`/`locked` atom cannot be scanned — 'delist first'"*. An atom in an open p2p or
an active listing carries `locked`/`listed` and is refused on that precondition alone, with a precise reason
(`listed_locked`), whether or not the door is open. The freeze adds nothing to it.

**Why the check is also categorically wrong.** The freeze is a **custody-move** guard. Scanning is **not a
custody move** — the same RPC document says so: *"an ownership-log entry is **not** appended (scan is not a
custody change)"*. Applying a custody-move guard to a non-custody-move is a category error, and the category
error is what produced the total-denial behaviour.

**Correction: `kernel.mark_ticket_scanned` is REMOVED from the recheck set and MUST NEVER consult
`kernel.is_transfer_frozen`.**

**Argument that admission works after door open** (the four conditions that gate an admit, none of which is
the freeze):
1. the session is `live` — `venue.record_scan`'s own precondition, and the *only* thing that stops admission;
2. the atom is `state='active'` and belongs to the session;
3. `resale_state='none'` — the delist-first rule, which independently covers every case the freeze check was
   reaching for;
4. `credential_version` is current (online live verify, C37) or matches the manifest entry (offline).
Opening the manifest changes **none** of these. It changes `door_open_at`, which drives `is_transfer_frozen`,
which after this correction has **no reader on the admission path at all.** The drain (§14.3.8) additionally
guarantees condition 3 is satisfiable: any atom left `listed`/`locked` when doors open is unlocked back to its
owner at open time, so a fan mid-transfer is not refused at the door with no remedy.

**Made structural, not merely documented.** A prose correction to a check that "seemed safer" will be
re-added by the next engineer who reads the freeze section. This document therefore adopts the door spec's
structural assertion as a **standing pgTAP test**, `T-RLS-DOOR-01` (§16.11):

> `pg_get_functiondef('kernel.mark_ticket_scanned')` **does not match** `is_transfer_frozen`.

plus the behavioural regressions `T-RLS-DOOR-02..04`: with an episode open and `is_transfer_frozen = true`,
`venue.record_scan` on an `active`, `resale_state='none'` atom returns `result='admitted'` and the atom moves
to `scanned`; a second scan returns `duplicate` with the atom still `scanned` (C41 first-in-wins holds under
freeze); and with the session `status='completed'`, `record_scan` returns `precondition_failed` — proving
admission is gated by **session status, not manifest state**.

#### 14.3.6 The freeze gated transfer *start* but not *completion*

`market.create_p2p_transfer` rechecked; **`market.accept_p2p_transfer` and
`kernel.transfer_ticket_ownership` did not appear in the recheck set at all.** A transfer initiated at 21:00
and accepted at 23:30, with doors open at 22:00, therefore **moved custody and bumped `credential_version`
after the manifest snapshot was taken** — precisely the credential-stranding C6 exists to prevent. C43's TTL
auto-unlock mitigates but does not close it; the TTL may be many hours. **Both are added, with
`transfer_ticket_ownership` as the enforcement point** (§14.3.3).

#### 14.3.7 Freezing both branches of the C25 sweep strands money forever

`market.sweep_paid_pending_sales` resolves a sale stuck in `paid_pending_transfer` by **either** completing the
transfer **or** auto-compensating (refund-void). If the freeze applied to both branches, a sale caught by
doors-open could do **neither**: complete is a custody move (frozen) and compensate is a refund-void (frozen
under C23). The buyer's money sits in `paid_pending_transfer` **forever** — the exact unbounded-dwell failure
C25 exists to forbid.

**Ruling: complete is frozen; compensate is EXEMPT.** A sale caught by doors-open resolves as `compensated` —
the buyer is refunded. That is not a compromise, it is the correct outcome: a buyer who cannot receive a
working credential before an offline door opens was never going to be admitted. The compensate branch is a
**refund-void, not a custody move**; exempting it moves no ticket to a new owner and strands nothing. (It
must still write its `revoke` delta — §14.3.3.)

#### 14.3.8 In-flight overlays would lock fans out — the drain

`mark_ticket_scanned` requires `resale_state='none'`. Once the freeze engages, `accept_p2p_transfer` is
rejected as `frozen` (§14.3.6), so a pending transfer's atom stays `locked` until its TTL expires — possibly
hours. A fan whose ticket is mid-transfer or listed arrives at the door and is refused, **with no action
available to them and none to the door.** On open, before the snapshot, `venue.open_door_manifest` therefore
**drains** the session's in-flight market overlays: `initiated` p2p transfers → `cancelled`
(`reason_code='door_freeze'`, atom unlocked back to the **sender**, which C43 exempts because owner and
`credential_version` do not change) and `active` listings → `cancelled`, atom unlocked. **Excluded:** any
listing whose sale is in `paid_pending_transfer` — money is already taken and the C25 sweep owns that row
(§14.3.7). The drain **moves no custody, appends no ownership-log row, and bumps no `credential_version`.**

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
   migration 078 — package C, catalog) + the `kernel.is_transfer_frozen(atom_id)` helper as the ONLY authorization read (§14.3
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

### 15.7 Status after the delta-spec integration

**CLOSED by this pass:**

- **The role set** (§1.1, §2.1) — O-2/O-4 ratified; fifteen labels, three disjoint planes, `venue_door` →
  `venue_scanner`, `venue_promoter` removed, five labels added.
- **The scanner credential model** (§2.5) — `has_venue_role` reads `venue.staff_role` only; the door is
  `assert_door_session` inside a definer RPC and is never an RLS predicate.
- **Door-lifecycle authority** (§11.4) — O-4: the door principal is removed from open/close.
- **Item 2 (door-freeze form)** — now §14.3, substantially corrected: the predicate is total, the recheck set
  is right in four places it was wrong, and the C43 narrowing is stated as deferred rather than described as
  implemented.
- **Refund authority** — O-1; §7.10 replaced.
- **Payout visibility** — O-3; §7.9 replaced, and the §11-vs-§7.9 self-contradiction is gone.
- **The attribution write point** — §9.17; moved to `finalize_primary_order`.
- **RLS policy naming** — GP-3 + the §16.10 register.
- **The recursion hazard** — I-12.

**STILL OPEN (items 1, 3, 4 of §15 stand):** the platform sub-role read boundary (item 1); org- vs
venue-level settlement close (item 3, = money spec's open reconciliation item — O-1/O-3 do not reach it); the
`platform_support` refund ceiling (item 4 — the **key** `refund.platform_support_max_minor` now has a config
home, but **the number does not**).

**Owner decisions this document surfaces or inherits.** None blocks writing the spec; each blocks
implementation of the item named.

| # | Decision | Recommendation | Blocks |
|---|---|---|---|
| **MD-1** | Is `kernel.approval_request` an *aggregate class* (⇒ a sixteenth SSCAS member ⇒ a C28 amendment) or an *intent record* (⇒ `SSCAS: n/a`)? | Intent record — the parked branch takes `FOR UPDATE` on exactly one pre-existing class (Ticket Atom); the approval row is a fresh INSERT that contends on nothing. It is lock-ordered either way, so an amendment would be a one-line ratification | the parked refund branch |
| **MD-2** | A second definer owner (`crm_export_builder`) for the export builder, deviating from the RPC spec's `postgres`-owned global | **Adopt.** The alternative is a `postgres`-owned function with reach over everything. `BYPASSRLS` is not an acceptable substitute. Needs the explicit `_sel_svc_export` policies of §16.10 | the export package |
| **MD-3** | The actual numbers: `refund.org_auto_execute_max_minor`, `refund.org_dual_control_max_minor`, `refund.platform_support_max_minor`, `payout.request_auto_max_minor`, `payout.dual_control_min_minor`, `refund.request_ttl_hours` | commercial + risk call; the keys ship, the values are set by an audited `set_platform_config` | tier behaviour |
| **MD-4** | `org_admin` reads `venue.settlement` (§9.13) while denied the payout and refund ledgers | Keep — settlement is operational reconciliation, payout is money-out. **The inconsistency is real and is named rather than smoothed** | consistency only |
| **MD-5** | A single-money-principal org is **blocked** from payouts after a destination change by SoD-1 | **Escalate** via the existing `release_payout` — the second human in the SoD pair becomes a platform operator. Relaxing reintroduces the exact named fraud primitive | §11.3 |
| **MD-6** | `refund.scanned_atom_policy` default: `refuse` or `platform_review` | `platform_review` — refunding an attendee who already walked in is legitimate, but it is **also** the insider-collusion shape (staff scans a friend in, then refunds), so it should be *seen*, not silently allowed or silently blocked | the consumed-atom refund path |
| **MD-7** | Ship step-up at `aal1` freshness now and flip to `aal2` on staff MFA enrollment? | Ship at `aal1` with the level in config, so `aal2` is a **config change, not a code change**. Blocking until MFA ships would ship a dashboard nobody can use. **`UNVERIFIED:` whether this project's tokens carry `amr` with per-factor timestamps was not checked — no production access. If absent, freshness degrades to token age (`iat`), which is weaker and must be labelled as such rather than described as "recent authentication"** | §11.3 step-up |
| **MD-8** | Is a platform-plane bulk extraction path wanted at all? | **Not built in Phase 2** (§11.6). If wanted, it needs dual control, its own retention and its own audit action — not the venue surface | platform export |
| **MD-9** | The GP-2 `DELETE` exception and the `ON DELETE CASCADE` on `kernel.identity_demographic` | **Accepted here** on the terms in §16.5, as the single GP-2 exception in the model. A second must not be granted by analogy | the demographics package |
| **MD-10** | **What gate is the `notify` schema at?** C7 is `RATIFIED · Gate P · MVP` and names `notify`; all four implementation specs, including this one, defer it to Gate L | **Not resolved here** — it is a stop-and-ask. §16.9's matrices are conditional. Note the load-bearing argument: the venue dashboard already carries a *binding* dependency on `notify`, which no Gate-L object may have. Its companion **MD-11** asks whether the event outbox — the constitution's *"only new infrastructure Phase 2 introduces"* — is scheduled anywhere, and it is not | everything in §16.9 |
| **MD-12** | Who may **disable** a transfer freeze? O-4 says not the scanner; it does not say who | `platform_admin` under step-up, placed there provisionally (§14.3.4) | the override RPC |
| **MD-13** | Break-glass for the door: if `door_open_at` is mis-set and no manager is reachable, the door cannot open under O-4 | Ship without it; scheduling plus remote org-plane action should cover it. **The operational risk is real and the owner should see it here rather than discover it at 11 p.m.** | nothing; ops risk |

Everything else has a determinate policy from the schema spec's stated read/write authority + the Phase-0
class defaults (§4).

---

## 16. Matrices for the objects the eight delta specs add

All inherit GP-1 (no client INSERT/UPDATE/DELETE on any Phase-2 table), GP-2 (DEL = `D` for every role on
every table), GP-3 (policy naming, §16.10) and I-7 (`REVOKE ALL` first, then the exact GRANT). The
twenty-principal key of §1.1 applies; roles not named in a matrix are `D` by deny-by-default (I-1), and a new
label never inherits an old label's cells.

### 16.1 `kernel.approval_request` — money-custody-RPC-only (the generic approval object)

One generic object serves org refund dual control, money-namespace `platform_config` dual control, and
payout-above-threshold dual control: one state machine, one SoD rule, one expiry sweep, one audit vocabulary.

| Role | SEL | INS | UPD | DEL | EXEC |
|---|---|---|---|---|---|
| anon / fan | D | D | D | D | — |
| owner (requester, own request) | V(own) | R | D | D | `cancel_refund_request` (own) |
| org_member / org_admin / org_marketing / org_promoter_manager | D | D | D | D | — |
| org_owner / org_finance | V(own-org, via `list_approval_requests`) | R | R | D | `request_order_refund` · `approve_refund_request` (**approver ≠ requester**) · `cancel_refund_request` |
| every venue role · door session · promoter | D | D | D | D | — |
| platform_support / platform_risk | V | R | R | D | `approve_refund_request` (platform-review tier) |
| platform_admin | A | R | R | D | all, incl. the money-config approval branch |
| service_role | A(machine) | R(def) | R(def) | D | definer (incl. the expiry sweep) |

**SoD is a table constraint, not a convention:** `CHECK (approved_by IS NULL OR approved_by <> requested_by)`.
**The payload footgun, named and mitigated:** a generic `payload jsonb` invites the approval to become a
client-supplied authority vector (*"approve this, amount = X"*). The payload is **server-computed at request
time and re-derived and re-compared at approval time**; the stored payload is *evidence for the approver's
UI*, and the executing code trusts nothing in it. A mismatch moves the request to `stale` — it is **never an
override**. Every threshold's `(key, version)` is pinned onto the row, so a config change mid-flight cannot
silently re-tier a parked request.

### 16.2 `venue.door_manifest` — venue-scoped

| Role | SEL | INS | UPD | DEL | EXEC |
|---|---|---|---|---|---|
| anon / fan / owner | **D** | D | D | D | — |
| org_member | D | D | D | D | — |
| org_owner / org_admin | A(own-org venues) | R | R | D | `open_door_manifest` · `close_door_manifest` |
| org_finance | A(own-org: `status`/`opened_at`/`closed_at` only — settlement timing context, **never `manifest_digest`**) | D | D | D | — |
| venue_manager | A(own-venue) | R | R | D | `open_door_manifest` · `close_door_manifest` |
| venue_scanner · door session | **A(own session only, and only via `venue.get_door_manifest` — never a table scan)** | **D** | **D** | D | **—** (O-4) |
| venue_finance / venue_box_office / venue_marketing / venue_promoter_manager / promoter | D | D | D | D | — |
| platform_support | V | D | D | D | — |
| platform_risk | A(all) | D | D | D | — |
| platform_admin | A(all) | R | R | D | override |
| service_role | A(machine) | R(def) | R(def) | D | definer |

**A fan cannot read this table at all.** The freeze reaches the client exclusively as the
`kernel.is_transfer_frozen` boolean (§14.3). Exposing episode timings to fans would leak venue operations and
invite gaming the boundary. The operator must be able to tell an explicit open from the implicit backstop; the
fan must not.

### 16.3 `venue.door_manifest_entry` · `venue.door_manifest_delta` — venue-scoped, AO

| Role | SEL | INS | UPD | DEL | EXEC |
|---|---|---|---|---|---|
| anon / fan / owner | D | D | D | D | — |
| org_owner / org_admin / venue_manager | A(own-venue) | R | D | D | — |
| venue_scanner · door session | **V** (own session, via `venue.get_door_manifest` only) | D | D | D | — |
| all other org/venue roles · promoter | D | D | D | D | — |
| platform_risk / platform_admin | A | R(def) | D | D | — |
| service_role | A(machine) | R(def) | D | D | definer (`append_door_manifest_delta`) |

**Column discipline (I-4).** These tables carry **no identity column by construction** — no
`current_owner_id`, no buyer reference, no name. See §6.

### 16.4 `kernel.door_freeze_override` — audit-only (RLS on, ZERO policies)

| Role | SEL | INS | UPD | DEL | EXEC |
|---|---|---|---|---|---|
| every role except platform + service_role | **D** | D | D | D | — |
| platform_support | V | D | D | D | — |
| platform_risk | V | D | R | D | `revoke_door_freeze_override` **only** (may tighten, never loosen — SoD) |
| platform_admin | V | R | R | D | `grant_…` · `revoke_…` |
| service_role | A(machine) | R(def) | R(def) | D | definer |

### 16.5 `kernel.identity_demographic` · `_erasure` · `venue.holder_mix_snapshot` · `_bucket`

**The grant set is EMPTY, not reduced** (§6 tier 2), and RLS is enabled with **no policy admitting `anon` or
`authenticated`** behind it.

| Role | SEL | INS | UPD | DEL | EXEC |
|---|---|---|---|---|---|
| owner (own row, `identity_demographic` only) | **V** (via `get_my_demographics()`) | **R** | **R** | **D**¹ | `get/set/clear_my_demographics` |
| every other principal on `identity_demographic` | D | D | D | D | — |
| every principal on `identity_demographic_erasure` | D | D | D | D | — (definer only; **no human role**) |
| org_owner / org_admin (holder mix) | V (via `get_holder_mix`, own-org sessions) | D | D | D | `get_holder_mix` |
| venue_manager / venue_marketing / venue_promoter_manager (holder mix) | V (own-venue sessions) | D | D | D | `get_holder_mix` |
| platform_admin (holder mix) | V (any session, audited) | D | D | D | `get_holder_mix` |
| org_finance / venue_finance / venue_box_office / venue_scanner / door session / promoter / platform_support / platform_risk / fan / anon | **D** | D | D | D | — |
| service_role | A(machine) | R(def) | R(def) | D | definer (`refresh_holder_mix`, reconciliation) |

¹ **Named GP-2 exception, requiring this document's acknowledgment (owner decision MD-9).** `DELETE` on
`kernel.identity_demographic` is permitted **inside the definer `clear_my_demographics` only**; clients hold
zero DELETE. Keeping a withdrawn gender answer as a tombstoned row would defeat the withdrawal, and this table
references no ledger. **Acknowledged and accepted here** as the single GP-2 exception in the model — it is
scoped to one table, one function, and a row that is not a ledger entry. A second such exception must not be
granted by analogy. The paired `ON DELETE CASCADE` from `auth.users` (against the corpus's `RESTRICT` default)
is accepted on the same terms: an orphaned demographic answer belonging to a deleted account is the worst
possible residue, and cascade-from-`auth.users` is already the house pattern. **The row must never be
repointed to the anonymized sentinel.**

> **The reader-enumeration rule this matrix depends on.** The set of functions, views and matviews whose
> definition references `kernel.identity_demographic` must be **exactly**
> `{get_my_demographics, set_my_demographics, clear_my_demographics, refresh_holder_mix}`, and the set
> referencing the holder-mix tables exactly `{refresh_holder_mix, get_holder_mix, <reconciliation job>}`.
> Any addition fails the suite. This is what makes "no export function can reach demographics" checkable
> rather than asserted — and the assertion must carry a **non-vacuity guard** (it must be able to see all
> nine export functions), or an empty match set would pass trivially.

### 16.6 `kernel.identity_contact_pref` · `kernel.org_contact_consent` · `kernel.org_customer_key` · `venue.export_job`

Same posture: **empty grant set**, RLS on, no policy admitting a client role.

| Role | SEL | INS | UPD | DEL | EXEC |
|---|---|---|---|---|---|
| owner (own rows, the two contact tables) | V (via the four own-row RPCs) | R | R | D | `get/set_my_contact_prefs` · `list/grant/withdraw_org_contact_consent` |
| every principal on `kernel.org_customer_key` | **D** | D | D | D | — (definer only; **no human role, including `platform_admin`**) |
| org_owner / org_admin / org_marketing (export_job) | V (own-org, via `list_export_jobs`) | R | R | D | `request_export` · `authorize_export_download` · `revoke_export` · `list_export_jobs` |
| venue_manager / venue_marketing (export_job) | V (own-venue) | R | R | D | as above at venue grain |
| org_finance / venue_finance / venue_box_office / venue_scanner / door session / promoter / promoter-manager labels / org_member | D | D | D | D | — |
| platform_support / platform_risk | V (history only) | D | D | D | `list_export_jobs` |
| platform_admin | V (history) | D | R | D | `list_export_jobs` · `revoke_export` (**revoking is not extraction**) |
| service_role | A(machine) | R(def) | R(def) | D | definer (`build_export_rows`, `finalize_export`, `sweep_expired_exports`) |

**Withdrawal is a state change, never a row deletion** (`state ∈ granted|withdrawn` with `granted_at` /
`withdrawn_at`); the row cascades away only with the account. **There is no staff-side consent write path** —
no `admin_set_contact_consent`, and **no `p_identity_id` parameter on any of the five contact RPCs**, so a
venue can never record a consent on a fan's behalf. Asserted structurally, not by inspection.

**Storage bucket `crm-exports`:** `public = false`, 32 MB size limit, `allowed_mime_types = {text/csv}`, object
path `{org_id}/{job_id}.csv` carrying **no venue name, no event title, no date, no filter, no segment**, and
**zero `storage.objects` policies for `anon` or `authenticated`** — not a reduced set, none. The only principal
that touches the bucket is `service_role` inside the edge function.

### 16.7 `venue.promoter_code` · `venue.promoter_code_scope` · `venue.attribution_review`

`promoter_code`/`_scope` mirror §9.17's promoter/link matrices exactly — **a code is a link's sibling and must
not acquire a wider grant by being newer**:

| Role | SEL | INS | UPD | DEL | EXEC |
|---|---|---|---|---|---|
| anon / fan / owner / org_member | D | D | D | D | — |
| org_owner / org_admin / org_promoter_manager | A(own-org) | R | R | D | create · bulk · status · scope · window |
| org_finance / venue_finance | A(own-org / own-venue) | D | D | D | — |
| venue_manager / venue_promoter_manager | A(own-venue's org) | R | R | D | create · bulk · status · scope · window |
| venue_scanner · door session · venue_box_office · venue_marketing | D | D | D | D | — |
| **promoter** | **A(own codes only)** | **D** | **D** | D | — |
| platform_support / platform_risk | A | D | D | D | — |
| platform_admin | A | R | R | D | override (audited) |
| service_role | A(machine) | R(def) | R(def) | D | definer |

`venue.attribution_review` is **AO**: `UPD` is `D` for **every** role including `platform_admin`; a wrong
decision is corrected by appending `seq+1`, never by an edit, and the **effective decision is `max(seq)`**.
`platform_risk` holds `INS`/EXEC; `platform_admin` does **not**. The promoter reads `decision` +
`reason_code` on their **own** attribution and **never** the reviewer's `note` (the venue's internal
deliberation) or `displaced_promoter_id` (another promoter's identity) — enforced by the read RPC's
projection, not by hoping the client omits columns. Supersession **closes at settlement**: once a
`promoter_commission` settlement line exists, review is rejected with `attribution_settled` — the money and
the decision freeze together.

### 16.8 `kernel.wallet_pass` · `wallet_pass_device` · `pass_type_cert` · `wallet_pass_push_log`

| Role | SEL | INS | UPD | DEL | EXEC |
|---|---|---|---|---|---|
| anon | D | D | D | D | — |
| **fan / current owner** | **V** — own atoms only, `{wallet_pass_id, ticket_atom_id, status, built_at, last_updated_at}`, **via RPC only** | R | D | D | `mint_wallet_pass` |
| **every org role and every venue role, including `venue_manager` and the door** | **D** | D | D | D | — |
| platform_support | V | D | R | D | `revoke_wallet_pass` |
| platform_risk | V | D | D | D | — |
| platform_admin | A | R | R | D | `revoke_wallet_pass` · cert lifecycle |
| service_role | A(machine) | R(def) | R(def) | D | definer |

**No venue or org role reads this table at all.** A pass registry is not venue-operations data; the door's
bulk read is the manifest and nothing else. `wallet_pass_device`, `wallet_pass_push_log` and `pass_type_cert`
are **audit-only**: RLS on, **zero policies**, `REVOKE ALL FROM anon, authenticated`, read only through an
`is_platform` RPC. **No client, no venue role and no org role ever reads a push token.**

### 16.9 `notify.*` — nine tables

| Table | Posture |
|---|---|
| `notify.notification` | **owner-scoped**, reusing the production-proven 040 posture verbatim: `GRANT SELECT`, `GRANT UPDATE (read_at)`, policies `notify_notification_sel_owner` / `notify_notification_upd_owner` on `recipient_id = auth.uid()`. **No INSERT policy, no DELETE policy, for any client role.** The column-level `UPDATE (read_at)` is not decoration — RLS restricts *rows*, not *columns* |
| `notify.preference` | owner-scoped CRUD via `auth.uid()`. **The mandatory-type guard is DDL, never RLS** — a composite FK to `(type_key, delivery_class)` plus `CHECK (delivery_class <> 'mandatory')`. *A policy could be misconfigured; a CHECK cannot.* |
| `notify.announcement` | venue-scoped read for `[venue_manager, org_owner, org_admin]` + platform; **writes RPC-only**. Recipients never read this table — they read their own `notify.notification` row |
| `notify.notification_type` · `notify.template` | deny-all; surfaced only through `get_preference_matrix()` / the renderer. Deny-all rather than public-read because the UI needs the **resolved** state, not the raw registry |
| `notify.delivery` · `outbox` · `schedule` · `identity_channel_state` | RLS on, **zero policies**, `REVOKE ALL FROM anon, authenticated` |

**A "cleared" notification is a `dismissed_at` column, never a row removal** (GP-2 holds).

> **SCOPE FLAG — `notify` is NOT settled, and this document does not settle it.** §0 of this spec lists
> `notify` among the deferred schemas. The notifications spec reports a **BLOCKING** conflict: C7 is
> `RATIFIED · Gate P · MVP` and names `notify`, while all four Phase-2 implementation specs (including this
> one) defer it to Gate L. It **explicitly declines to resolve it** and escalates it as owner decision
> **O-N1**, with the load-bearing argument that the venue dashboard already carries a *binding* dependency on
> it — which no Gate-L object may have. A companion blocker **O-N2** asks whether the event outbox is in
> Phase 2 at all: the domain architecture promises *"one outbox table and a drainer on the cron that already
> runs"* as Phase 2's only new infrastructure, and **no Phase-2 spec defines it.**
>
> **The matrices above are therefore CONDITIONAL.** They are recorded so that, if the owner ratifies `notify`
> at Gate P, the authority model is already written and nothing is invented under time pressure. **They are
> not authority to build.** Flipping this document's scope line requires an owner ratification entry, which
> is a stop-and-ask under the governance rules. Recorded as **MD-10**, §15.7.

### 16.10 Policy-name register (GP-3 applied)

Every policy this document requires, by name. **A migration that creates a policy not on this list, or omits
one that is, fails review.** Read with GP-3's rules: one policy per (table, verb, principal-class); `FOR
SELECT` only; deny-all tables carry **zero** policies.

| Object | Policy name(s) | Predicate family |
|---|---|---|
| `catalog.venue` | `catalog_venue_sel_anon` · `catalog_venue_sel_org` · `catalog_venue_sel_venue` | narrow `approval_status='approved'`; org draft; own-venue draft |
| `catalog.event` | `catalog_event_sel_anon` · `catalog_event_sel_org` · `catalog_event_sel_venue` | `status >= 'announced'`; org/venue draft |
| `catalog.event_session` | `catalog_event_session_sel_anon` · `catalog_event_session_sel_org` · `catalog_event_session_sel_venue` | sessions of visible events |
| `catalog.platform_config` | `catalog_platform_config_sel_public` | values are not secret |
| `catalog.resale_policy` | `catalog_resale_policy_sel_public` | policy in force |
| `kernel.identity_ext` | `kernel_identity_ext_sel_owner` | `identity_id = auth.uid()` |
| `kernel.organization` | `kernel_organization_sel_org` · `kernel_organization_sel_platform` | `is_org_affiliate` / `has_org_role`; `is_platform` |
| `kernel.org_member` | `kernel_org_member_sel_org` · `kernel_org_member_sel_platform` | **I-12 applies** |
| `kernel.org_invite` | `kernel_org_invite_sel_invitee` · `kernel_org_invite_sel_org` | addressed invitee; inviter tier |
| `kernel.platform_role` | `kernel_platform_role_sel_platform` | **I-12 applies** |
| `kernel.signing_key` | `kernel_signing_key_sel_public` | `public_key` + window columns only |
| `kernel.tickets` | `kernel_tickets_sel_owner` · `kernel_tickets_sel_venue` · `kernel_tickets_sel_platform` | `current_owner_id = auth.uid()`; issuing venue/org ops; platform |
| `venue.staff_role` | `venue_staff_role_sel_venue` · `venue_staff_role_sel_org` · `venue_staff_role_sel_platform` | **I-12 applies** |
| `venue.ticket_type` | `venue_ticket_type_sel_public` · `venue_ticket_type_sel_venue` | `visibility='public'`; venue-scoped incl. hidden/door_only |
| `venue.inventory_batch` | `venue_inventory_batch_sel_public` · `venue_inventory_batch_sel_venue` | `remaining` projection; full counters |
| `venue.inventory_hold` | `venue_inventory_hold_sel_owner` · `venue_inventory_hold_sel_venue` | holder; venue ops |
| `venue.order` · `venue.order_item` | `venue_order_sel_owner` · `venue_order_sel_org` · `venue_order_sel_venue` (and the `_item` triple) | buyer; org back office; venue ops |
| `venue.settlement` · `venue.settlement_line` | `venue_settlement_sel_org` · `venue_settlement_sel_venue` (and the `_line` pair) | org/venue finance |
| `venue.comp_allocation` · `venue.guest_list` · `venue.guest_entry` · `venue.scan_device` · `venue.scan` | `<table>_sel_venue` (+ `venue_scan_sel_platform`) | venue-scoped |
| `venue.door_manifest` · `venue.door_manifest_entry` · `venue.door_manifest_delta` | `<table>_sel_venue` · `venue_door_manifest_sel_platform` | §16.2–§16.3 |
| `venue.promoter` · `promoter_link` · `promoter_code` · `promoter_code_scope` · `attribution` · `attribution_review` | `<table>_sel_org` · `<table>_sel_venue` · `<table>_sel_promoter` | back office; **promoter own-row via `promoter_id = auth.uid()`**, never a join through `link_id` (§9.17) |
| `market.listing_native` | `market_listing_native_sel_public` · `market_listing_native_sel_owner` | `status='active'` discovery cols; seller full |
| `market.auction` · `market.offer` | `market_auction_sel_public` · `market_offer_sel_owner` | active auction; buyer/seller |
| `market.p2p_transfer` | `market_p2p_transfer_sel_owner` | `from_identity` or `to_identity` = `auth.uid()` |
| `market.listing_unified` (VIEW) | **none** — `security_invoker`, inherits base-table policies | §14.1 |
| `notify.notification` | `notify_notification_sel_owner` · `notify_notification_upd_owner` | `recipient_id = auth.uid()`. **The only UPDATE policy in this register**, and it is column-restricted to `read_at` |
| `notify.preference` | `notify_preference_sel_owner` · `notify_preference_ins_owner` · `notify_preference_upd_owner` | `identity_id = auth.uid()`; mandatory guard is DDL |
| `notify.announcement` | `notify_announcement_sel_venue` | venue-scoped staff read |

**Objects with ZERO policies, by design (RLS enabled, `REVOKE ALL`):** `kernel.ticket_ownership_log` ·
`kernel.payment_native` · `kernel.payout` · `kernel.refund` · `kernel.reserve` · `kernel.admin_audit` ·
`kernel.approval_request` · `kernel.door_freeze_override` · `kernel.identity_demographic` ·
`kernel.identity_demographic_erasure` · `kernel.identity_contact_pref` · `kernel.org_contact_consent` ·
`kernel.org_customer_key` · `kernel.wallet_pass` · `kernel.wallet_pass_device` · `kernel.pass_type_cert` ·
`kernel.wallet_pass_push_log` · `venue.inventory_batch_shard` · `venue.inventory_movement` ·
`venue.inventory_unit` · `venue.export_job` · `venue.holder_mix_snapshot` · `venue.holder_mix_bucket` ·
`market.market_sale` · `notify.notification_type` · `notify.template` · `notify.delivery` · `notify.outbox` ·
`notify.schedule` · `notify.identity_channel_state` · the `crm-exports` storage bucket.

**Layer-0 exception, named because it needs policies this register would otherwise forbid.** If the CRM export
builder runs as a narrow owner role (`crm_export_builder`) rather than `postgres` — the recommended
least-privilege shape — that role is **subject to** the roster tables' RLS and therefore needs an explicit
permissive policy naming it on exactly those relations, named `<schema>_<table>_sel_svc_export`. **`BYPASSRLS`
on that role is NOT an acceptable shortcut** — it would restore access to everything and delete the entire
benefit. This is a deviation from the RPC spec's *"definer owned by `postgres`"* global and is **owner
decision MD-2**, §15.7.

### 16.11 Test register — the assertions this document requires

Named so they can be written, run and cited. Grouped by the property each defends.

| ID | Assertion | Defends |
|---|---|---|
| `T-RLS-FORCE-01..03` | `pg_class.relforcerowsecurity = false` for `kernel.org_member`, `venue.staff_role`, `kernel.platform_role` — a **positive equality on the catalog**, not the absence of a `FORCE` statement in migration text | **I-12** |
| `T-RLS-FORCE-04` | No **other** Phase-2 relation has a policy whose predicate calls a helper that reads that same relation (no second table depends on owner-bypass to terminate) | I-12 (allow-list, not scan) |
| `T-RLS-DOOR-01` | `pg_get_functiondef('kernel.mark_ticket_scanned')` **does not match** `is_transfer_frozen` | **§14.3.5 — the CRITICAL regression** |
| `T-RLS-DOOR-02` | With an episode open and `is_transfer_frozen = true`, `record_scan` on an `active`, `resale_state='none'` atom ⇒ `result='admitted'`, atom `scanned` | §14.3.5 |
| `T-RLS-DOOR-03` | The same on a second scan ⇒ `result='duplicate'`, atom stays `scanned` (C41 first-in-wins holds under freeze) | §14.3.5 |
| `T-RLS-DOOR-04` | With session `status='completed'`, `record_scan` ⇒ `precondition_failed` — admission is gated by **session status, not manifest state** | §14.3.5 |
| `T-RLS-DOOR-05` | `transfer_ticket_ownership` and `accept_p2p_transfer` for an atom of a frozen session ⇒ `frozen` | §14.3.6 |
| `T-RLS-DOOR-06` | The routine `refund_primary_order → void_ticket_atom` path ⇒ `frozen`; `catalog.cancel_event` on the same session **succeeds** (exempt) | §14.3.3 |
| `T-RLS-DOOR-07` | `sweep_paid_pending_sales` **compensate** branch succeeds on a frozen session; the **complete** branch is refused | §14.3.7 |
| `T-RLS-DOOR-08` | `catalog.effective_freeze_at` returns **NOT NULL** for every row of a seeded fixture covering every status × nullability combination | §14.3.1 totality |
| `T-RLS-DOOR-09` | A drained atom (p2p cancelled at open) then scans successfully — the end-to-end lockout regression | §14.3.8 |
| `T-RLS-DOOR-10` | `venue_scanner`, a valid door session, `venue_box_office`, both finance labels, `platform_support` and `platform_risk` may not `open_door_manifest` ⇒ `42501`, and `door_open_at` is unchanged | O-4 |
| `T-RLS-EDGE-01` | Every RPC in §11 whose authority names a human predicate raises when invoked with `auth.uid()` NULL — i.e. a service-role invocation **fails loudly instead of degrading** | **§3.1 EDGE-CALLER-JWT** |
| `T-RLS-EDGE-02` | Every RPC marked `DEF` in §11 has **no** EXECUTE grant to `anon` or `authenticated` | §11 grant classes |
| `T-RLS-POL-01` | `policies_are(schema, table, ARRAY[...])` for every object in §16.10 — an added, renamed or dropped policy fails CI | **GP-3** |
| `T-RLS-POL-02` | The zero-policy list of §16.10 has RLS **enabled** and **zero** policies; no `USING (true)` exists anywhere in the Phase-2 schemas | GP-3a, I-1, I-2 |
| `T-RLS-POL-03` | **No Phase-2 table carries an INSERT, UPDATE or DELETE policy**, with the single named exception `notify_notification_upd_owner` | GP-1, GP-3 rule 2 |
| `T-RLS-COL-01` | `anon` holds **zero** rows in `information_schema.role_column_grants` for every empty-grant-set table of §6 | §6 tier 2 |
| `T-RLS-COL-02` | `authenticated` holds **zero** rows in `role_column_grants` for the same set — *the assertion that would have caught the pre-068 `public.profiles` exposure* | §6 tier 2 |
| `T-RLS-COL-03` | `authenticated` holds no SELECT on `kernel.wallet_pass.auth_token_enc` / `.auth_token_hash` / `.serial_no_opaque`; no `venue_*` or `org_*` role holds SELECT on any wallet table | §16.8 |
| `T-RLS-COL-04` | `venue.door_manifest_entry` exposes **no** owner/identity column | §16.3 |
| `T-RLS-ROLE-01` | The three role columns admit **exactly** the fifteen labels of §2.1, and reject every `org_*` label on the venue enum and vice-versa | C36 |
| `T-RLS-ROLE-02` | No policy body and no RPC body contains a bare role-string comparison or a display name (`box_office`, `marketing`, `scanner`, `promoter`) | RM-2 |
| `T-RLS-ROLE-03` | `kernel.assert_door_session` appears in **no** `pg_policy` expression | RM-5 |
| `T-RLS-ROLE-04` | `has_venue_role`'s definition does not reference `venue.door_pin` | R-8 |
| `T-RLS-ATTR-01` | No `venue.attribution` row exists while the order is `pending`, even with both candidates set | §9.17 |
| `T-RLS-ATTR-02` | A **code-sourced** attribution (`link_id IS NULL`) **is** visible to its own promoter | §9.17 predicate correction |
| `T-RLS-MONEY-01` | `org_admin` is denied SELECT and EXECUTE on every `kernel.payout` / `kernel.refund` path | §7.9/§7.10 |
| `T-RLS-MONEY-02` | `approve_refund_request` by the requester raises **`self_approval`**, distinctly from a generic `42501` | §11.3 SoD |
| `T-RLS-MONEY-03` | `request_org_payout` by `organization.payout_destination_set_by` raises `sod_violation` **after** the cool-down has elapsed | §11.3 SoD-1 |
| `T-RLS-MONEY-04` | `venue_finance` reads only `cause='settlement'` payouts for its own venue and zero rows of every other cause | §7.9 note 15ᵈ |
| `T-RLS-CRM-01` | No platform role can call `venue.request_export` | §11.6 |
| `T-RLS-CRM-02` | A `venue_marketing` at V1 of Org 1 is denied at V2 of the same org; `org_marketing` at Org 1 reaches all Org 1 venues and no Org 2 venue | §11.6 grain |

---

## 17. Requests to the other integrators (recorded, not applied here)

This document does not edit any file but its own. Each item below is a change another owner must make for the
authority model above to be implementable.

| # | To | Request |
|---|---|---|
| X-1 | **schema + migration plan** | `venue.order` gains `attribution_candidate_code_id` / `_link_id` (nullable, guard-triggered to `status='pending'`), and `venue.attribution` is written by `finalize_primary_order` — §9.17. Assert `pg_class.relforcerowsecurity = false` on the three authz tables in the venue-staff-roles package's staging verification (I-12). |
| X-2 | **schema** | `venue.scan.actor_identity_id uuid NULL` + `CHECK (device_id IS NOT NULL OR actor_identity_id IS NOT NULL)`. Without it a `venue_scanner` grant is indistinguishable from a `venue_manager` grant in the ledger — the insider-fraud trail has a hole exactly where O-2 asks for least privilege. |
| X-3 | **schema** | The three role columns as `text` + `CHECK`, not native enums, so the fifteen-label commitment stays correctable while the tables are empty (OD-6). |
| X-4 | **edge integrator** | State the mirror of **§3.1 EDGE-CALLER-JWT** in the edge spec §3.4/§3.5. Both statements must exist — either document alone reads as describing the other's job. Also: the `promoter-code-preview` wrapper and its derived `uuidv5` principal (§11.8), and `kernel.record_money_denial` called **in a separate transaction** on `insufficient_privilege` / `sod_violation` / `step_up_required`. |
| X-5 | **edge integrator** | The `door-session` edge function is the **only** way a scanner reaches the database. It must derive `p_actor_device_id` server-side and never accept an attested human actor. |
| X-6 | **dashboard/RN integrator** | The export allow-list gains both marketing labels (audience template only) and the deny-list gains the four new denied labels (§11.6). Δ1's door-manifest role list drops the door principal (O-4). |
| X-7 | **amendment owner** | C43's narrowing is `RATIFIED-MODELED-ONLY(GATE-M)`; four documents describe it as implemented. §14.3.2 states the MVP mechanism instead. If the board wants the narrowing in MVP it is a **new** ratification, not a clarification. |
| X-8 | **amendment owner** | `kernel.approval_request`'s placement between Ticket Atom and the money plane in the global lock order: if a reviewer judges it an **aggregate class** rather than an intent record, the parked refund branch is a **sixteenth SSCAS member** and C28's closure needs a formal amendment. It is lock-ordered either way, so the amendment is a one-line ratification, not a redesign. |
| X-9 | **traceability owner** | Every `T-RLS-*` id of §16.11 and every policy name of §16.10 needs a matrix row. |

---

*End of docs/architecture/PHASE_2_RLS_PERMISSION_SPEC.md. Design-only; no SQL. Companion to the physical schema spec
(deliverable #1) and the RPC contracts (deliverable #4), per SPEC_FOUNDATION §10.*
