# Phase 2 — Canonical Role Model Specification

**Status:** DESIGN-ONLY DELTA SPEC. No SQL, no migrations, no implementation code. Illustrative predicate
snippets are conceptual pseudo-SQL, never shippable DDL.

**Purpose.** Resolve the role-set contradiction between `PHASE_2_RLS_PERMISSION_SPEC.md` and
`SNATCH_IT_DOMAIN_ARCHITECTURE.md`, and implement owner rulings **O-2** (canonical administrative role set)
and **O-4** (door-lifecycle authority) against the ratified constraint **C36** (three disjoint per-plane role
label sets). This file **supersedes** the role-set definitions in the RLS spec §1.1/§2.1 and the permission
matrix in Domain Architecture §7.6. It does **not** edit the frozen constitutions; §11 lists every edit an
integration pass must apply.

**Binding inputs (authority order):**
1. Owner rulings **O-2** and **O-4** (ratified) — the reason this file exists.
2. `docs/architecture/_governance/PHASE_2_RATIFICATION_RECORD.md` — **C36** (RATIFIED, Gate P, structural),
   C9, C35, C37 (Gate L), C39 (Gate L), C46 (Gate L).
3. `docs/architecture/PHASE_2_SPEC_FOUNDATION.md` §4 (C35/C36), §6, §8.
4. `docs/architecture/PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md` §1.3, §1.4, §3.9–§3.12.
5. `docs/architecture/PHASE_2_RLS_PERMISSION_SPEC.md` §1.1, §2, §7.x, §9.x, §11, §15.
6. `docs/architecture/SNATCH_IT_DOMAIN_ARCHITECTURE.md` §0.4 A9, §7.1–§7.6, §4 challenge resolution.
7. `docs/architecture/SNATCH_IT_CANONICAL_DATA_MODEL.md` §1.3, §8, §15 (C36/C39/C46).
8. `docs/architecture/PHASE_2_VENUE_DASHBOARD_PRODUCT_SPEC.md` §18 open deltas (Δ1, Δ7, Δ-role-set) — the
   surface that raised the ruling request O-2/O-4 answer.

**Evidence convention.** Every load-bearing claim is tagged `VERIFIED:` (read directly from a file in this
repo at `phase2/consolidation@11ea2eb`, with the location) or `INFERENCE:` (a design judgement I made, with
the reasoning). Owner-reserved questions are never silently resolved — they are listed in §13.

---

## 0. Executive summary — the five decisions

| # | Question | Decision | Where |
|---|---|---|---|
| **D-1** | Are O-2's role list and C36's disjointness compatible? | **YES, and the reconciliation is already sanctioned by the corpus.** O-2 enumerates *role concepts* (display names). C36 governs *stored enum labels*. Domain Architecture §7.1 already states the mapping rule verbatim. Every O-2 concept lands on exactly one plane-prefixed label; nothing is collapsed, nothing is silently renamed. | §2, §3, §4 |
| **D-2** | Which plane owns `marketing` and `promoter_manager`? | **Both planes, two labels each** — `org_marketing`/`venue_marketing` and `org_promoter_manager`/`venue_promoter_manager` — exactly the pattern already ratified for `org_finance`/`venue_finance`. The plane of the grant *is* the CRM-export scope. | §4.3, §4.4 |
| **D-3** | What is a scanner's session? | **Not an `authenticated` Supabase session.** The default door principal is a **device-bound door session** minted by a new `door-session` edge function from (registered `venue.scan_device` + `venue.door_pin` + `event_session_id`). `auth.uid()` is NULL on that path; the Postgres principal is `service_role` acting on a server-validated device assertion. A separate `venue_scanner` **staff grant** exists for a named human who must be individually attributable. `has_venue_role` **stops accepting door PINs**. | §7 |
| **D-4** | Does `venue_manager` scope to one venue or many? | **One venue per grant row** — `venue.staff_role` PK is `(venue_id, identity_id, role)` (VERIFIED). Multi-venue authority is either N grant rows or an **org-plane role inheriting down**. The predicate is a PK point-probe, so there is no N+1 and no recursion — **provided `FORCE ROW LEVEL SECURITY` is never set on the three authz tables** (new invariant **INV-NOFORCE**). | §6.4, §6.5 |
| **D-5** | Where do promoters and ambassadors live? | **Not in any role enum.** `venue_promoter` is **removed** from `venue.staff_role`; a promoter's authority derives wholly from `venue.promoter_link` row ownership. Ambassadors were already correctly modelled as a derived predicate. Escalation is impossible by construction because neither holds a row in any of the three authz tables. | §9 |

**Six defects found in the frozen corpus** (§14): a role predicate whose meaning depends on the caller; an
RLS recursion hazard on all three authz tables; an unattributable scan ledger; an enum-vs-CHECK contradiction
between two frozen specs; four un-migrated bare-label role lists still sitting inside the C36 constitution
itself; and a money-authority conflict (`set_org_payout_destination`) that is **not mine to resolve**.

---

## 1. The contradiction, measured

`VERIFIED:` the two constitutions do not use the same role set. Measured from the text at `11ea2eb`:

| Source | Location | Role set as written |
|---|---|---|
| RLS spec §2.1 | `PHASE_2_RLS_PERMISSION_SPEC.md:105-107` | org: `org_owner · org_admin · org_finance · org_member` · venue: `venue_manager · venue_finance · venue_door · venue_promoter` · platform: `platform_admin · platform_support · platform_risk` |
| Spec foundation §4 C36 | `PHASE_2_SPEC_FOUNDATION.md:51-53` | identical to the above |
| Physical schema §3.9 | `PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md:899` | `role` **enum**(`venue_manager` · `venue_finance` · `venue_door` · `venue_promoter`) |
| Migration plan | `PHASE_2_SUPABASE_MIGRATION_PLAN.md:363,496` | `role` **CHECK** in the same four/four labels |
| Domain Arch §7.2 catalog | `SNATCH_IT_DOMAIN_ARCHITECTURE.md:1671-1676` | display names: Venue Manager · **Venue Staff — Box Office** · **Venue Staff — Marketing** · **Door (scanner)** · **Promoter Manager** · Promoter |
| Domain Arch §7.6 matrix | `SNATCH_IT_DOMAIN_ARCHITECTURE.md:1756` | columns: Plat Admin · Support · Risk Ops · Org Owner · Org Admin · Org Finance · Venue Mgr · **Box Office** · **Marketing** · Door · **Promoter Mgr** · Promoter · Seller · Buyer · **Ambassador** |
| Domain Arch object catalog | `SNATCH_IT_DOMAIN_ARCHITECTURE.md:156, 761, 1546, 2235` | **bare, unprefixed**: `owner/manager/finance/marketing/door/promoter_manager` |

Three distinct role vocabularies coexist in the frozen corpus. `venue_manager` and `scanner` are not the same
role; `box_office`, `marketing`, `promoter_manager`, `seller`, `buyer`, `ambassador` appear in the Domain
Architecture with no counterpart in the RLS spec; and the Domain Architecture's own object catalog and ER
diagram still carry the pre-C36 bare labels that C36 was ratified to abolish.

`VERIFIED:` the downstream surface already blocked on this. `PHASE_2_VENUE_DASHBOARD_PRODUCT_SPEC.md:1162`
states: *"a box-office seller must be granted `venue_manager` (over-provisioned) or work from a door PIN
(under-provisioned for selling); there is no marketing role, so event-page editing is bundled into
`venue_manager`; and 'Promoter Manager' is `venue_manager`… **Needs a ruling**."* O-2 is that ruling.

`VERIFIED:` nothing is applied. `supabase/migrations/` ends at `075_replay_parity_storage_policies_and_cron.sql`
plus four dated website-form migrations; `grep -rn "staff_role\|org_member\|platform_role" supabase/migrations/`
returns nothing. **The enums are still editable. After the venue-staff-roles package ships they are not.**
That is the entire cost of getting this wrong, and it is why O-2 had to be ruled before that package.

---

## 2. C36 × O-2 — the compatibility argument

### 2.1 The apparent conflict

C36 (RATIFIED, Gate P) — `_governance/PHASE_2_RATIFICATION_RECORD.md:28`:

> *"Scope-qualified roles are structural: three disjoint per-plane label sets (org/venue/platform enums share
> no label), not a lint convention."*

O-2's canonical list, as ruled: `org_owner` · `org_admin` · `org_finance` · `venue_manager` · `box_office` ·
`marketing` · `promoter_manager` · `scanner`.

Read as a flat list of **stored labels**, O-2 appears to violate C36: `box_office`, `marketing`,
`promoter_manager` and `scanner` carry no plane prefix, so a policy author could not tell from the label which
of the three enums a value came from — precisely the conflation C36 exists to make a type error.

### 2.2 The resolution — the corpus already contains it

`VERIFIED:` `SNATCH_IT_DOMAIN_ARCHITECTURE.md:1629` (§7.1), the section C36 itself cites as its own home:

> *"(The role names in §7.2's catalog are display names; the stored labels are the disjoint scope-prefixed
> sets.)"*

C36 therefore governs **one** namespace — the stored enum label — and explicitly permits a second, human
namespace of display names above it. O-2 is expressed in the second namespace. It is a ruling about **which
jobs exist and what each may do**, not a ruling about byte strings in a Postgres type.

Two independent confirmations that this is O-2's own reading, not a convenient one:

1. **O-2 is internally mixed.** It contains `org_owner` and `venue_manager` (already plane-prefixed) alongside
   `box_office` and `scanner` (not prefixed). A ruling intended as a literal enum-label list would not be
   half-prefixed. It is a capability list.
2. **O-2 names `venue_manager`, not `manager`.** The one venue-plane role O-2 spells out in full is spelled
   *with* the prefix — which is only meaningful if the prefix convention is presumed to apply to the rest.

**Conclusion: O-2 and C36 are compatible, and the mapping is mechanical.** Each O-2 concept is assigned to
exactly one plane; its stored label is the concept prefixed with that plane. Where a concept genuinely does
two different jobs in two planes, it becomes two labels — which is not a workaround but the *already-ratified*
pattern: `org_finance` and `venue_finance` are two labels for one concept today, and no one calls that a C36
violation.

### 2.3 What this does NOT license

- It does **not** license a bare label anywhere. `box_office` never appears as a stored value; only
  `venue_box_office` does. `SNATCH_IT_DOMAIN_ARCHITECTURE.md:156, 761, 1546, 2235` still store bare labels and
  are therefore **defects to be corrected** (§14.5), not precedent.
- It does **not** license the display name in a predicate. RLS spec §2.3 forbids bare comparison; that stands
  unchanged and now extends to display names: `has_venue_role(v, ['box_office'])` is as illegal as
  `role = 'finance'`, because `box_office` is not a member of any enum.
- It does **not** license collapsing O-2's roles. Every one of the eight named roles gets its own label and
  its own row in the master matrix. `box_office` is not "a narrow `venue_manager`"; `scanner` is not
  "`venue_door` renamed for taste" (§4.5 gives the substantive reason).

`INFERENCE:` the residual risk of the two-namespace model is that a reviewer reads a display name in a product
spec and a label in a policy and fails to connect them. §4 is the single normative concept→label table, and
§11 makes every downstream spec cite it.

---

## 3. Canonical enum membership — the three planes

### 3.1 Org plane — `kernel.org_member.role`

| Label | Concept (O-2 display name) | Origin |
|---|---|---|
| `org_owner` | org_owner | unchanged |
| `org_admin` | org_admin | unchanged |
| `org_finance` | org_finance | unchanged |
| `org_marketing` | marketing (org grain) | **NEW** — O-2 |
| `org_promoter_manager` | promoter_manager (org grain) | **NEW** — O-2 |
| `org_member` | base membership | unchanged (see §10) |

**6 labels.**

### 3.2 Venue plane — `venue.staff_role.role`

| Label | Concept (O-2 display name) | Origin |
|---|---|---|
| `venue_manager` | venue_manager | unchanged |
| `venue_finance` | *(not in O-2 — retained; see §13 OD-1)* | unchanged |
| `venue_box_office` | box_office | **NEW** — O-2 |
| `venue_marketing` | marketing (venue grain) | **NEW** — O-2 |
| `venue_promoter_manager` | promoter_manager (venue grain) | **NEW** — O-2 |
| `venue_scanner` | scanner | **RENAMED** from `venue_door` (§4.5) |
| ~~`venue_promoter`~~ | — | **REMOVED** (§9.1) |

**6 labels.**

### 3.3 Platform plane — `kernel.platform_role.role`

| Label | Concept | Origin |
|---|---|---|
| `platform_admin` | Platform Admin | unchanged |
| `platform_support` | Support | unchanged |
| `platform_risk` | Risk / Trust Ops | unchanged |

**3 labels.** O-2 does not touch the platform plane; it is carried forward verbatim.

### 3.4 Disjointness — proof by enumeration

All fifteen labels, sorted, with the plane each belongs to:

| # | Label | Plane |
|---|---|---|
| 1 | `org_admin` | org |
| 2 | `org_finance` | org |
| 3 | `org_marketing` | org |
| 4 | `org_member` | org |
| 5 | `org_owner` | org |
| 6 | `org_promoter_manager` | org |
| 7 | `platform_admin` | platform |
| 8 | `platform_risk` | platform |
| 9 | `platform_support` | platform |
| 10 | `venue_box_office` | venue |
| 11 | `venue_finance` | venue |
| 12 | `venue_manager` | venue |
| 13 | `venue_marketing` | venue |
| 14 | `venue_promoter_manager` | venue |
| 15 | `venue_scanner` | venue |

**Enumeration check.** The list is in strict lexicographic ascending order and every adjacent pair differs
(`org_admin` < `org_finance` < `org_marketing` < `org_member` < `org_owner` < `org_promoter_manager` <
`platform_admin` < `platform_risk` < `platform_support` < `venue_box_office` < `venue_finance` <
`venue_manager` < `venue_marketing` < `venue_promoter_manager` < `venue_scanner`). Fifteen labels, fifteen
distinct strings, therefore no label appears twice **anywhere**. Since the three plane sets partition the
fifteen (6 + 3 + 6 = 15, and every row is assigned exactly one plane), no label appears in two planes.
∴ **org ∩ venue = ∅, org ∩ platform = ∅, venue ∩ platform = ∅.** ∎

**Structural check (the stronger property).** Every org label matches `^org_`, every platform label matches
`^platform_`, every venue label matches `^venue_`. The three prefixes are pairwise non-prefix-comparable
(`org_`, `platform_`, `venue_` — no one is a prefix of another), so a label's plane is decidable from its
first token alone, without consulting the enum. This is what makes cross-scope confusion a *type* error rather
than a lookup error: a reviewer reading a policy line can see the plane in the literal. ∎

`INFERENCE:` the prefix property is strictly stronger than C36 requires (C36 asks only for disjointness) and
costs nothing. It is worth stating as a standing rule so future labels cannot erode it: **RM-1 — every role
label MUST begin with its plane token; a proposed label that does not is rejected at review.**

### 3.5 Physical form — enum type vs CHECK constraint

`VERIFIED:` the frozen corpus contradicts itself. `PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md:899` says
`role` **enum**(…); `PHASE_2_SUPABASE_MIGRATION_PLAN.md:363,496` says `role` **CHECK** in (…). These are not
interchangeable for the property that motivated this whole exercise:

| | native `CREATE TYPE … AS ENUM` | `text` + `CHECK (role IN (…))` |
|---|---|---|
| Add a label later | `ALTER TYPE … ADD VALUE` — additive, but **cannot be run inside a transaction block with immediate use** in older PG, and the value is permanent | `ALTER TABLE … DROP CONSTRAINT … ADD CONSTRAINT` — fully reversible |
| Remove a label later | **impossible** without recreating the type and rewriting every dependent column | trivial, subject to no rows holding it |
| Rename a label | `ALTER TYPE … RENAME VALUE` | data update + constraint swap |
| Storage / comparison | 4 bytes, fast | text, negligible at this cardinality |

`INFERENCE:` **recommend `text` + `CHECK`.** The stated risk in the ruling request is *"an applied-migration
commitment that cannot be edited afterwards."* A CHECK constraint makes that statement false — the commitment
becomes editable while empty and correctable while nearly empty. At fifteen labels and three tiny tables the
performance argument for a native enum is nil. This is a **SPEC CORRECTION** to the physical schema spec, and
it is the single cheapest insurance policy available against getting §3 wrong. Flagged for the owner as
**OD-6** (§13) because it edits a frozen physical-schema statement.

---

## 4. Concept → label map, with every rename declared

### 4.1 The normative map

| O-2 concept | Stored label(s) | Plane(s) | Change vs frozen corpus |
|---|---|---|---|
| `org_owner` | `org_owner` | org | none |
| `org_admin` | `org_admin` | org | none |
| `org_finance` | `org_finance` | org | none |
| `venue_manager` | `venue_manager` | venue | none |
| `box_office` | `venue_box_office` | venue | **new label** |
| `marketing` | `org_marketing`, `venue_marketing` | org **and** venue | **two new labels** |
| `promoter_manager` | `org_promoter_manager`, `venue_promoter_manager` | org **and** venue | **two new labels** |
| `scanner` | `venue_scanner` | venue | **rename** of `venue_door` |
| *(base membership)* | `org_member` | org | none — but see §10 |
| *(retained, not in O-2)* | `venue_finance` | venue | none — **OD-1** |
| *(retained, not in O-2)* | `platform_admin/support/risk` | platform | none |
| *(removed)* | ~~`venue_promoter`~~ | — | **deleted** — §9.1 |

### 4.2 Why `marketing` is two labels, not one — and what it does to CRM export

`VERIFIED:` the tenant is the **Organization**. `SNATCH_IT_CANONICAL_DATA_MODEL.md` §8: *"Tenant =
Organization (and the Venues it operates)"* and *"an org/venue reads only its own operational and financial
data, and only the customers who transacted with it (its CRM slice)."* The CRM slice is therefore defined at
**org grain**, with a venue sub-slice underneath it.

`VERIFIED:` Domain Architecture §7.2 places Marketing in the venue plane (*"Venue Staff — Marketing | venue or
event"*). `VERIFIED:` the venue dashboard's CRM-export allow-list is
`venue_manager`, `org_owner`, `org_admin` (`PHASE_2_VENUE_DASHBOARD_PRODUCT_SPEC.md:545`) with an explicit
deny-list of `venue_door`, `venue_finance`, `org_finance`, `promoter`, `org_member`, `platform_support`
(`:546`) — marketing appears on neither list because the role did not exist.

`INFERENCE:` a single label cannot express both real jobs.

- A **venue's** in-house marketer must reach that venue's audience and **must not** see the sibling venues'
  customers. A single org-grain label over-exposes them.
- An **org's** marketing team runs one campaign across forty venues. Forcing forty venue grants is exactly the
  antipattern Domain Architecture §7.3 names: *"Org-wide operational authority is `org_member`, not a venue
  role sprayed across every venue."* A single venue-grain label under-serves them, and the only escape is to
  grant `org_admin` — general administration — which O-2 expressly says marketing must not have.

So: **the plane of the grant is the export scope.**

| Grant | Export scope | Predicate |
|---|---|---|
| `org_marketing` on org O | every customer in O's CRM slice, across all O's venues | `has_org_role(O, ['org_marketing'])` |
| `venue_marketing` on venue V | only customers who transacted at V | `has_venue_role(V, ['venue_marketing'])` |

**Money boundary (O-2: "no custody or money authority").** Marketing's export is a **contactable-audience**
export, not a finance export. It is column-restricted to identity + contact + event-attendance facts and
**excludes** order totals, fee splits, payment references, refund state, and payout data. `venue_manager`,
`org_owner` and `org_admin` keep the fuller export they have today. This is a distinct column projection of
the same underlying read, not a second export surface.

`INFERENCE:` this reading resolves a conflict. Domain Architecture §7.2 says Marketing *"Cannot touch …
PII beyond aggregates"*; O-2 says marketing gets *"CRM/export … as authorized"*. O-2 is later and ratified, so
O-2 governs — marketing **does** get row-level contact PII. The `as authorized` qualifier is honoured by the
column restriction above plus the export controls that already apply to everyone
(`PHASE_2_VENUE_DASHBOARD_PRODUCT_SPEC.md:543`: 300-second signed URL, **re-authorized live at download
time**, so an export prepared before a revocation fails after it).

### 4.3 Why `promoter_manager` is also two labels

`VERIFIED:` Domain Architecture §7.2 scopes Promoter Manager to *"venue or event"* and gives it: create/manage
promoters and `promoter_links`, view attribution/commission reporting for their venue/events, set commission
terms within policy; explicitly **not** ticket prices/inventory, **not** payout initiation, **not** full buyer
PII.

`INFERENCE:` the same two-jobs argument applies unchanged. An org that runs one promoter program across its
venues needs an org-grain promoter manager; a single venue that runs its own street team needs a venue-grain
one; and the only way to express the org case with a venue-only label is to grant `org_admin`, which O-2
forbids for the same reason it forbids it for marketing. Symmetry with `marketing` is also worth something on
its own: a role model whose plane rules have exceptions is a role model that gets misapplied.

Scope of the attribution/commission read follows the plane, identically to §4.2.

**One deliberate asymmetry, stated so it is not read as an oversight:** promoter managers are **denied** the
flagged-self-deal release/deny decision (venue dashboard Δ7), which stays with `venue_manager` /
`org_owner` / `org_admin` / `platform_risk`. `INFERENCE:` a promoter manager adjudicating a flag against a
promoter they recruited and are measured on is the fox at the henhouse; this is the same separation-of-duties
principle as Domain Architecture §7.4 rule 4 (propose vs approve is a real boundary).

### 4.4 Why `box_office` is venue-plane only

`INFERENCE:` box office is a **station**, not a policy function. It exists where the door is. There is no
coherent "org-wide box office" job that is not simply `org_admin` or a set of venue grants, and inventing
`org_box_office` would create a label with no distinct capability set — which is how role models rot. Venue
plane only.

### 4.5 Why `venue_door` becomes `venue_scanner` — a substantive rename, not a cosmetic one

O-2 ratifies the role name `scanner`. Renaming toward the ruling is the default, but there is a stronger
reason, and it is O-4:

O-4 draws a hard line between **operating the door lifecycle** (open/close the manifest, move the door-freeze
time, change event security configuration — `org_owner`/`org_admin`/`venue_manager` only) and **scanning
against an already-open manifest** (the scanner). A label named `venue_door` asserts authority over *the
door* — the entire station, lifecycle included — which is exactly what O-4 denies. A label named
`venue_scanner` asserts authority over *scanning*, which is exactly what O-4 grants. **The rename makes the
label agree with the ruling.**

`VERIFIED:` the corpus's door vocabulary (`venue.door_pin`, `catalog.event_session.door_open_at`,
`ticket_type.visibility='door_only'`, `venue.record_scan`) is untouched by this rename — those name the
*place* and the *artifact*, which is correct. Only the *role* changes, because only the role was claiming
authority the ruling withholds.

`VERIFIED:` blast radius — `venue_door` appears on 60 lines across six specs
(RLS 34, venue dashboard 13, RPC contracts 8, physical schema 2, migration plan 2, spec foundation 1).
Full edit list in §11.

**This rename is declared, not silent.** It is listed for the owner as **OD-2** (§13) in case the ruling's
word `scanner` was descriptive rather than nominative.

---

## 5. Master role × capability matrix

**This matrix supersedes** `PHASE_2_RLS_PERMISSION_SPEC.md` §7.x/§9.x role rows and
`SNATCH_IT_DOMAIN_ARCHITECTURE.md` §7.6 in their entirety. Every capability appearing in either source appears
here, reconciled. Where the two sources disagreed, the disagreement is named in the Notes column.

### 5.1 Column key (20 principals)

| Code | Principal | Tested by |
|---|---|---|
| `ANO` | `anon` | unauthenticated |
| `FAN` | authenticated fan / row owner | `auth.uid()` present; `auth.uid() = <owner col>` |
| `OMB` | `org_member` | `has_org_role(org,['org_member'])` |
| `OOW` | `org_owner` | `has_org_role(org,['org_owner'])` |
| `OAD` | `org_admin` | `has_org_role(org,['org_admin'])` |
| `OFI` | `org_finance` | `has_org_role(org,['org_finance'])` |
| `OMK` | `org_marketing` | `has_org_role(org,['org_marketing'])` |
| `OPM` | `org_promoter_manager` | `has_org_role(org,['org_promoter_manager'])` |
| `VMG` | `venue_manager` | `has_venue_role(venue,['venue_manager'])` |
| `VFI` | `venue_finance` | `has_venue_role(venue,['venue_finance'])` |
| `VBO` | `venue_box_office` | `has_venue_role(venue,['venue_box_office'])` |
| `VMK` | `venue_marketing` | `has_venue_role(venue,['venue_marketing'])` |
| `VPM` | `venue_promoter_manager` | `has_venue_role(venue,['venue_promoter_manager'])` |
| `VSC` | `venue_scanner` (authenticated staff grant) | `has_venue_role(venue,['venue_scanner'])` |
| `DOO` | **door session** (PIN + device; `auth.uid()` IS NULL) | `assert_door_session(device,session)` — §7 |
| `PRO` | promoter (**relationship, not a role**) | `promoter_link.identity_id = auth.uid()` — §9 |
| `PSU` | `platform_support` | `is_platform(['platform_support'])` |
| `PRI` | `platform_risk` | `is_platform(['platform_risk'])` |
| `PAD` | `platform_admin` | `is_platform(['platform_admin'])` |
| `SVC` | `service_role` | machine identity only — never a human path |

### 5.2 Cell vocabulary

| Cell | Meaning |
|---|---|
| `·` | **DENY** — no path. Deny-by-default; absence of a policy. |
| `A` | **ALLOW** — direct read via an RLS policy + column GRANT. (Per RLS GP-1 there is **no `A` write cell anywhere**.) |
| `V` | **VIEW-ONLY** — read exclusively through a scoped/redacted read RPC or bridge view; no direct table SELECT. |
| `R` | **RPC** — the action is permitted, exclusively inside a `SECURITY DEFINER` RPC. |
| `◐` | **SCOPED** — a strict subset (own rows / own session / own venue / aggregate only). Always combined: `R◐`, `A◐`, `V◐`. |
| `✱` | requires **fresh step-up** (`aal2` re-assertion at the action boundary). |
| `ᴰ` | requires **dual control** (two distinct approvers, SoD-satisfied). |
| `ᴾ` | **propose only** — creates a pending item another principal must approve. |

### 5.3 The matrix

#### A. Platform governance

| Capability | ANO | FAN | OMB | OOW | OAD | OFI | OMK | OPM | VMG | VFI | VBO | VMK | VPM | VSC | DOO | PRO | PSU | PRI | PAD | SVC |
|---|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|
| A1 Approve venue/org onboarding | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · | Rᴾ | · | R✱ | R |
| A2 Configure feature flags / `platform_config` | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · | R✱ | R |
| A3 Platform moderation / bans | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · | Rᴾ | R | R | R |
| A4 Grant/revoke platform role | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · | R✱ᴰ | R |
| A5 Read `kernel.admin_audit` (security plane) | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · | V | V | A | A |
| A6 Read own venue/org operational audit | · | · | · | R◐ | R◐ | R◐ | · | · | R◐ | R◐ | · | · | · | · | · | · | V | V | A | A |

> A6 is venue dashboard Δ2 (`:1123`) — a definer read restricted to the caller's org/venue subject, **excluding
> the security plane**, plain verbs, no before/after payloads. `NEW RPC`.

#### B. Money, custody & settlement

| Capability | ANO | FAN | OMB | OOW | OAD | OFI | OMK | OPM | VMG | VFI | VBO | VMK | VPM | VSC | DOO | PRO | PSU | PRI | PAD | SVC |
|---|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|
| B1 Change org payout destination | · | · | · | R✱ᴰ | · | **⚠** | · | · | · | · | · | · | · | · | · | · | · | · | · | R |
| B2 Initiate payout ≤ threshold | · | · | · | R✱ | · | R✱ | · | · | · | · | · | · | · | · | · | · | · | · | · | R |
| B3 Initiate/approve payout > threshold | · | · | · | R✱ᴰ | · | R✱ᴰ | · | · | · | · | · | · | · | · | · | · | · | · | R✱ᴰ | R |
| B4 Freeze account / payouts (risk) | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · | R | R | R |
| B5 Release held funds | · | · | · | · | · | R✱ᴰ | · | · | · | · | · | · | · | · | · | · | · | · | R✱ᴰ | R |
| B6 Issue refund > micro-threshold | · | R◐ | · | R✱ᴰ | · | R✱ᴰ | · | · | · | · | · | · | · | · | · | · | Rᴾ | Rᴾ | R✱ᴰ | R |
| B7 Resolve dispute (escrow) | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · | Rᴾ | Rᴾ | R✱ᴰ | R |
| B8 Ownership override (manual custody) | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · | R✱ᴰ | R |
| B9 Open settlement | · | · | · | R | · | R | · | · | R | R | · | · | · | · | · | · | · | · | R | R |
| B10 Close settlement (→ payout) | · | · | · | · | · | R✱ | · | · | · | **⚠** | · | · | · | · | · | · | · | · | R | R |
| B11 Read org finance reports | · | · | · | A◐ | · | A◐ | · | · | A◐ᵛ | A◐ᵛ | · | · | · | · | · | · | V | A | A | A |
| B12 Read own commission / attributed revenue | · | · | · | A◐ | A◐ | A◐ | · | A◐ | A◐ | A◐ | · | · | A◐ | · | · | A◐ | V | A | A | A |

> **⚠ B1** — `VERIFIED` **CONFLICT, NOT MINE TO RESOLVE.** `PHASE_2_RLS_PERMISSION_SPEC.md:1076` restricts
> `kernel.set_org_payout_destination` to `has_org_role([org_owner])` under dual control;
> `SNATCH_IT_DOMAIN_ARCHITECTURE.md:1765` (§7.6 "Change payout/bank account") grants it to **both** Org Owner
> and Org Finance. This is money authority — owner ruling **O-1/O-3** territory, branch
> `design/o1-o3-money-authority`. The cell is left `⚠` deliberately. **OD-3.**
>
> **⚠ B10** — `VERIFIED` **OPEN in the frozen spec.** `PHASE_2_RLS_PERMISSION_SPEC.md:1219` §15 item 3 flags
> `org_finance` vs `venue_finance` for settlement close as undecided, while §9.13 and §11 both list
> `venue_finance` as authorized. Settlement close drives payout, so this is money authority. **OD-4.**
>
> ᵛ B11 venue-plane finance reads are venue-scoped rollups only, never the org payout view
> (`PHASE_2_VENUE_DASHBOARD_PRODUCT_SPEC.md:806`).
>
> B6: `VERIFIED` `PHASE_2_RLS_PERMISSION_SPEC.md:1082` — among venue-side principals **only `org_finance`
> initiates a refund**; `venue_manager` and `venue_finance` cannot. O-2 changes nothing here.
> `venue_box_office` is **NOT** granted a cash-refund-at-door authority by this spec even though C46 requires
> refund-at-door to run through an authenticated staff principal and `venue_box_office` is the natural
> candidate — that grant is money authority. **OD-5.**

#### C. Organization administration

| Capability | ANO | FAN | OMB | OOW | OAD | OFI | OMK | OPM | VMG | VFI | VBO | VMK | VPM | VSC | DOO | PRO | PSU | PRI | PAD | SVC |
|---|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|
| C1 Read own org roster | · | · | A◐ | A | A | A | A | A | · | · | · | · | · | · | · | · | A | A | A | A |
| C2 Grant/revoke org role | · | · | · | R✱ | R✱ᵗ | · | · | · | · | · | · | · | · | · | · | · | · | · | R | R |
| C3 Invite org member | · | · | · | R | Rᵗ | · | · | · | · | · | · | · | · | · | · | · | · | · | R | R |
| C4 Accept own org invite | · | R◐ | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · | R |
| C5 Edit org profile (benign columns) | · | · | · | R | R | · | · | · | · | · | · | · | · | · | · | · | · | · | R | R |
| C6 Read org legal/Connect columns | · | · | · | A | · | A | · | · | · | · | · | · | · | · | · | · | V | A | A | A |
| C7 Create venue | · | · | · | R | R | · | · | · | · | · | · | · | · | · | · | · | · | · | R | R |

> ᵗ **tier guard** — `VERIFIED` `PHASE_2_RLS_PERMISSION_SPEC.md:305,319`: `org_admin` may not grant or invite
> at `org_owner` tier. **No self-grant** (I-11) applies to C2/C3 for every principal.
> C6: `VERIFIED` `:294` — `legal_name`, `stripe_connect_account_ref` and the payout lock are column-scoped to
> `org_owner`/`org_finance`/platform; `org_admin` and `org_member` see `display_name` + `status` only.

#### D. Venue & event operations

| Capability | ANO | FAN | OMB | OOW | OAD | OFI | OMK | OPM | VMG | VFI | VBO | VMK | VPM | VSC | DOO | PRO | PSU | PRI | PAD | SVC |
|---|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|
| D1 Create/edit event & sessions | · | · | · | R | R | · | · | · | R | · | · | · | · | · | · | · | · | · | R | R |
| D2 Set event status / cancel event | · | · | · | R | R | · | · | · | R | · | · | · | · | · | · | · | · | · | R | R |
| D3 Edit event **marketing** fields (description, hero, media, tags) | · | · | · | R | R | · | R | · | R | · | · | R | · | · | · | · | · | · | R | R |
| D4 Create/edit ticket type | · | · | · | R | R | · | · | · | R | · | · | · | · | · | · | · | · | · | R | R |
| D5 Set ticket-type **price** | · | · | · | R | R | · | · | · | R | · | · | · | · | · | · | · | · | · | R | R |
| D6 Set/edit resale policy | · | · | · | R | R | · | · | · | R◐ | · | · | · | · | · | · | · | · | · | R | R |
| D7 Grant/revoke venue staff role | · | · | · | Rⁱ | Rⁱ | · | · | · | R | · | · | · | · | · | · | · | · | · | R | R |
| D8 Read venue staff roster | · | · | · | A◐ | A◐ | · | · | · | A | A | A | A | A | A | · | · | A | A | A | A |
| D9 Manage promo codes | · | · | · | R | R | · | R | · | R | · | · | R | · | · | · | · | · | · | R | R |

> ⁱ **org→venue inheritance** — `VERIFIED` `PHASE_2_RLS_PERMISSION_SPEC.md:147` — expressed **inside the write
> RPC** as `has_venue_role(v,[venue_manager]) OR has_org_role(org_of_venue,[org_owner,org_admin])`, never by
> widening venue RLS. **No self-grant** (I-11).
> D3/D9: new capability rows. `VERIFIED` venue dashboard Δ5 (`:1135`) — `catalog.event` carries only `title`
> and `status`; the marketing fields do not exist yet. **ADDITIVE SCHEMA CHANGE**, §12.
> D5: pricing is money-**adjacent** configuration, not custody. Retained with `org_admin` under C9 live-table
> re-check. `INFERENCE:` this is my reading of O-2's *"org_admin — general administration but not
> unrestricted financial authority"*: no custody, no payout, no bank change, no refund, no settlement close —
> but revenue configuration stays, because removing it would leave `org_admin` unable to run an org.

#### E. Inventory, orders & comps

| Capability | ANO | FAN | OMB | OOW | OAD | OFI | OMK | OPM | VMG | VFI | VBO | VMK | VPM | VSC | DOO | PRO | PSU | PRI | PAD | SVC |
|---|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|
| E1 Create inventory batch / set capacity | · | · | · | R | R | · | · | · | R | · | · | · | · | · | · | · | · | · | R | R |
| E2 Reserve inventory (buyer hold) | · | R◐ | · | · | · | · | · | · | R | · | R | · | · | · | · | · | · | · | R | R |
| E3 Create staff/comp/promoter hold | · | · | · | R | R | · | · | · | R | · | · | · | · | · | · | · | · | · | R | R |
| E4 Release hold | · | R◐ | · | R | R | · | · | · | R | · | R◐ | · | · | · | · | · | · | · | R | R |
| E5 Create primary checkout / order | · | R◐ | · | · | · | · | · | · | R | · | R | · | · | · | · | · | · | · | R | R |
| E6 **Allocate** comp release (capacity) | · | · | · | R✱ | R✱ | · | · | · | R✱ | · | · | · | · | · | · | · | · | · | R | R |
| E7 **Issue** individual comp / guest entry | · | · | · | R✱ | R✱ | · | · | · | R✱ | · | R✱ | · | · | · | · | · | · | · | R | R |
| E8 Read own-venue orders | · | · | · | A◐ | A◐ | A◐ | · | · | A | A | A◐ | · | · | · | A◐ | · | V | A | A | A |

> **E6/E7 split — new.** `VERIFIED` `PHASE_2_RLS_PERMISSION_SPEC.md:1101` lists `venue.allocate_comp` and
> `venue.issue_comp` together under one authority (`venue_manager` OR org_owner/admin).
> `INFERENCE:` O-2 gives `venue_box_office` *"ticket issuance / permitted inventory-sale operations only."*
> Allocating comp **capacity** is an inventory decision; issuing **one** comp against an already-allocated
> batch is an issuance operation. Splitting the authority at that seam gives box office exactly what O-2
> describes and nothing more. Both remain C39-gated (step-up + live-grant re-check above the per-staff
> threshold), and the per-staff comp totals stay visible to `venue_manager` and above — `VERIFIED`
> `PHASE_2_VENUE_DASHBOARD_PRODUCT_SPEC.md:665`: *"this is the insider-fraud control surface, and hiding it
> defeats it."*
>
> This also resolves a contradiction **inside** the Domain Architecture: §7.2 prose says Box Office may
> *"Sell/comp at the door"*, while the §7.6 matrix row "Manage inventory / holds / comps" gives Box Office only
> `◐(door sell)`. The E6/E7 split makes both statements true at once.
>
> E8 `DOO` = orders for **its own session only** (`VERIFIED` `PHASE_2_VENUE_DASHBOARD_PRODUCT_SPEC.md:275`).

#### F. Door, admission & attendee data

| Capability | ANO | FAN | OMB | OOW | OAD | OFI | OMK | OPM | VMG | VFI | VBO | VMK | VPM | VSC | DOO | PRO | PSU | PRI | PAD | SVC |
|---|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|
| F1 **Open/close door manifest** (O-4) | · | · | · | R | R | · | · | · | R | · | · | · | · | · | · | · | · | · | R | R |
| F2 **Move door-freeze time** (O-4) | · | · | · | R | R | · | · | · | R | · | · | · | · | · | · | · | · | · | R | R |
| F3 **Disable transfer freeze** (O-4) | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · | R✱ | R |
| F4 **Change event security configuration** (O-4) | · | · | · | R | R | · | · | · | R | · | · | · | · | · | · | · | · | · | R | R |
| F5 Issue / revoke door PIN | · | · | · | R | R | · | · | · | R | · | · | · | · | · | · | · | · | · | R | R |
| F6 Register / retire scan device | · | · | · | R | R | · | · | · | R | · | · | · | · | · | · | · | · | · | R | R |
| F7 Sync manifest to device | · | · | · | · | · | · | · | · | R | · | · | · | · | R◐ | R◐ | · | · | · | R | R |
| F8 **Scan / admit** against an open manifest | · | · | · | · | · | · | · | · | R | · | · | · | · | R | R | · | · | · | R | R |
| F9 Submit offline scan batch | · | · | · | · | · | · | · | · | R | · | · | · | · | R◐ | R◐ | · | · | · | R | R |
| F10 Guest-list check-in (status + `checked_in_at` only) | · | · | · | · | · | · | · | · | R | · | R | · | · | R◐ | R◐ | · | · | · | R | R |
| F11 Single-record attendee/ticket lookup (service) | · | · | · | A◐ | A◐ | · | · | · | A | · | A | · | · | A◐ᵐ | A◐ᵐ | · | V | A | A | A |
| F12 **Bulk** attendee list / export | · | · | · | A | A | · | Aᶜ | · | A | · | · | Aᶜ | · | **·** | **·** | · | · | A | A | A |
| F13 Read venue scan ledger | · | · | · | A◐ | A◐ | · | · | · | A | · | · | · | · | A◐ | A◐ | · | V | A | A | A |
| F14 Fraud-review action on a flagged scan | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · | R | R | R |

> **F1–F4 are the O-4 authority rows.** See §8 for the full derivation. `venue_scanner` and the door session
> are `·` on all four by ruling; `venue_box_office` is `·` by explicit ruling text.
> F3 `INFERENCE:` O-4 says scanner may not disable the transfer freeze but does not say who may. The freeze is
> platform-wide custody state (`kernel.is_transfer_frozen`), so I place it at `platform_admin` under step-up
> and flag it — **OD-7**.
> ᵐ F11 door principals get the **minimal verification projection** only (name + validity), never contact
> detail — `VERIFIED` `SNATCH_IT_DOMAIN_ARCHITECTURE.md:1674`.
> ᶜ F12 marketing's export is the **contactable-audience** column projection, money columns excluded (§4.2).
> **F12 denies both door principals outright** — `VERIFIED` `PHASE_2_VENUE_DASHBOARD_PRODUCT_SPEC.md:510`:
> *"Bulk attendee listing is denied to door staff… A door principal hitting this route gets the
> permission-denied state"*, with the denial naming the alternative (F11).
> F14 `VERIFIED` `:291` — the venue's action on a flagged scan is *escalate*, not *resolve*.

#### G. Promoter engine & attribution

| Capability | ANO | FAN | OMB | OOW | OAD | OFI | OMK | OPM | VMG | VFI | VBO | VMK | VPM | VSC | DOO | PRO | PSU | PRI | PAD | SVC |
|---|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|
| G1 Create/manage promoter record | · | · | · | R | R | · | · | R | R | · | · | · | R | · | · | · | · | · | R | R |
| G2 Create/manage promoter link | · | · | · | R | R | · | · | R | R | · | · | · | R | · | · | R◐ˢ | · | · | R | R |
| G3 Set commission terms (within policy) | · | · | · | R | R | · | · | R | R | · | · | · | R | · | · | · | · | · | R | R |
| G4 Read attribution / promoter performance | · | · | · | A◐ | A◐ | A◐ | · | A◐ | A◐ | A◐ | · | · | A◐ | · | · | A◐ | V | A | A | A |
| G5 Release/deny a flagged self-deal attribution | · | · | · | R | R | · | · | **·** | R | · | · | · | **·** | · | · | · | · | R | R | R |

> ˢ G2 `PRO` = **sub-links only, where policy allows** — `VERIFIED` `SNATCH_IT_DOMAIN_ARCHITECTURE.md:1676`.
> **G5 denies both promoter-manager labels** — §4.3 SoD reasoning. `VERIFIED` this is venue dashboard Δ7
> (`:1132`); the storage shape is not mine, only the authority.

#### H. Marketing, CRM & analytics

| Capability | ANO | FAN | OMB | OOW | OAD | OFI | OMK | OPM | VMG | VFI | VBO | VMK | VPM | VSC | DOO | PRO | PSU | PRI | PAD | SVC |
|---|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|
| H1 Read event/marketing analytics (aggregate) | · | · | · | A◐ | A◐ | · | A◐ | A◐ | A◐ | · | · | A◐ | A◐ | · | · | A◐ | V | A | A | A |
| H2 CRM export — **audience columns** | · | · | · | A | A | · | Aᵒ | · | A | · | · | Aᵛ | · | · | · | · | · | A | A | A |
| H3 CRM export — **money columns** | · | · | · | A | A | · | **·** | · | A | · | · | **·** | · | · | · | · | · | A | A | A |
| H4 Manage event public page / media | · | · | · | R | R | · | R | · | R | · | · | R | · | · | · | · | · | · | R | R |

> ᵒ `org_marketing` exports at **org grain** (all the org's venues). ᵛ `venue_marketing` exports at **venue
> grain** only. §4.2.
> **H3 is the O-2 "no custody or money authority" line, made concrete.** Both marketing labels are `·`.
> `VERIFIED` the existing deny-list stands unchanged (`PHASE_2_VENUE_DASHBOARD_PRODUCT_SPEC.md:546`):
> `venue_finance`, `org_finance`, `org_member`, `platform_support`, and promoters are denied CRM export
> entirely — finance roles are denied because CRM export is a *contact* surface, not a money surface, and
> least privilege runs in both directions.
> All exports remain under the 300-second signed URL **re-authorized live at download time** (`:543`).

#### I. Consumer plane (derived, not stored roles)

| Capability | ANO | FAN | OMB | OOW | OAD | OFI | OMK | OPM | VMG | VFI | VBO | VMK | VPM | VSC | DOO | PRO | PSU | PRI | PAD | SVC |
|---|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|
| I1 Browse public catalog / listings | A | A | A | A | A | A | A | A | A | A | A | A | A | A | · | A | A | A | A | A |
| I2 Buy / bid / hold / p2p transfer | · | R◐ | R◐ | R◐ | R◐ | R◐ | R◐ | R◐ | R◐ | R◐ | R◐ | R◐ | R◐ | R◐ | · | R◐ | R◐ | R◐ | R◐ | R |
| I3 Create listing / run auction (seller) | · | R◐ᵏ | R◐ᵏ | R◐ᵏ | R◐ᵏ | R◐ᵏ | R◐ᵏ | R◐ᵏ | R◐ᵏ | R◐ᵏ | R◐ᵏ | R◐ᵏ | R◐ᵏ | R◐ᵏ | · | R◐ᵏ | R◐ᵏ | R◐ᵏ | R◐ᵏ | R |
| I4 Referral / ambassador program | · | R◐ | R◐ | R◐ | R◐ | R◐ | R◐ | R◐ | R◐ | R◐ | R◐ | R◐ | R◐ | R◐ | · | R◐ | R◐ | R◐ | R◐ | R |

> **The consumer plane is orthogonal to every role.** Buyer, Seller, Attendee and Ambassador are **derived
> predicates over the acting identity**, not grants — `VERIFIED` `SNATCH_IT_DOMAIN_ARCHITECTURE.md:1678-1685`.
> Holding `venue_manager` neither adds nor removes consumer capability; a venue manager buying a ticket at
> another venue is acting as `FAN`, and every consumer row is `◐` = own rows via `auth.uid()`.
> ᵏ **Seller is gated, never self-granted** — requires completed `market.seller_onboarding` (+ KYC per risk
> tier); `VERIFIED` `:1683` (the H-2 fix).
> **`DOO` is `·` on the entire consumer plane** — a door session has no `auth.uid()`, therefore no owned rows,
> therefore no consumer capability. That is not a policy choice; it falls out of §7's credential model.

---

## 6. Scope objects and predicate shapes

### 6.1 The grant objects — one per plane

| Plane | Grant table | Grant key | The scope object |
|---|---|---|---|
| org | `kernel.org_member` | `(org_id, identity_id)` — `VERIFIED` `PHASE_2_SUPABASE_MIGRATION_PLAN.md:363` | an **organization** |
| venue | `venue.staff_role` | `(venue_id, identity_id, role)` — `VERIFIED` `PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md:897-900` | a **venue** |
| platform | `kernel.platform_role` | `(identity_id, role)` — `VERIFIED` `PHASE_2_SPEC_FOUNDATION.md:97` | **global** (no scope id) |

Note the asymmetry, which is deliberate and worth stating: the org grant key does **not** include `role` (one
role per person per org), while the venue grant key **does** (a person may hold several roles at one venue —
`VERIFIED` `PHASE_2_VENUE_DASHBOARD_PRODUCT_SPEC.md:874`: *"a person may hold several venue roles, so the UI
is a multi-select of roles per person, not a single-role dropdown"*).

`INFERENCE:` this asymmetry becomes more load-bearing under O-2, not less. A small venue's one operations
person plausibly holds `venue_manager` + `venue_box_office` + `venue_scanner` simultaneously; a person's
relationship to an *organization* is singular. Keep both keys as they are.

### 6.2 The predicate helpers — complete set

> **`SPEC CORRECTION F-4` (`AUTHZ-C1C`, 2026-08-28) — THIS TABLE WAS THE DERIVATION SOURCE FOR THE WHOLE
> CORPUS AND IT WAS THREE RATIFIED CORRECTIONS STALE.**
> RLS §2.2 says it adopts this table *"verbatim"*, and this table calls itself *"complete set"* — so a
> reader who trusted both would have silently reverted **`C58`/`AUTHZ-C1B`** (which adds a **tenth** helper),
> **`C54`/`AUTHZ-H3`** (which changes `assert_door_session`'s **signature** — it takes a token and returns
> the bound pair) and **`AUTHZ-M10`** (which corrects `is_promoter_for_event`, whose old definition compared
> a `promoter_id` to an `auth.uid()` and was therefore **false for every row that will ever exist**). The
> prose above the table said *"Four exist. Three are new. One changes meaning"* — **seven** — while the table
> listed **nine**, so this section did not agree with itself either.
> **Re-derived below under RLS §2.2's `HELPER-DERIVED` rule**, whose clause 3 is written for exactly this
> case: a stale derivation source is brought into line with a ratified correction, never cited over the top
> of one. ROLE_MODEL filed `F-1`…`F-3` and no `F-4`; this is `F-4`.

**Ten helpers. Four pre-existed. Six are new. Three changed meaning or signature after they were first
written here.** The defining contracts are `PHASE_2_RPC_FUNCTION_CONTRACTS.md` **§1.1–§1.1e**; membership is
fixed by the ratification record (`HELPER-DERIVED` clauses 1–2) and asserted by `T-RLS-ROLE-06` /
`T-RPC-AUTHZ-17`.

| Helper | Status | Reads | Returns true iff | Contract |
|---|---|---|---|---|
| `kernel.has_org_role(p_org_id, p_roles[])` | existing, unchanged | `kernel.org_member` | a live row exists for `(p_org_id, auth.uid())` with `role ∈ p_roles` | §1.1 |
| `kernel.has_venue_role(p_venue_id, p_roles[])` | **CHANGED** — §7.5 | `venue.staff_role` **only** | a live row exists for `(p_venue_id, auth.uid(), role ∈ p_roles)` | §1.1 |
| `kernel.has_event_role(p_event_id, p_roles[])` | existing, unchanged | `catalog.event` → `venue.staff_role` | `has_venue_role(catalog.event.venue_id, p_roles)` | §1.1 |
| `kernel.is_platform(p_roles[])` | existing, unchanged | `kernel.platform_role` (+ `public.admin_users` bootstrap) | a live row exists for `auth.uid()` with `role ∈ p_roles` | §1.1 |
| `kernel.has_org_role_over_venue(p_venue_id, p_roles[])` | **NEW** | `catalog.venue` → `kernel.org_member` | `has_org_role(catalog.venue.org_id, p_roles)` | §1.1a |
| `kernel.has_org_role_over_event(p_event_id, p_roles[])` | **NEW** | `catalog.event` → `kernel.org_member` | `has_org_role(catalog.event.org_id, p_roles)` | §1.1a |
| `kernel.is_org_affiliate(p_org_id)` | **NEW** | `kernel.org_member` | **any** row exists for `(p_org_id, auth.uid())`, regardless of role — §10. **Scoping only, never authorizing** (RM-6) | §1.1b |
| `kernel.is_promoter_for_event(p_event_id)` | **NEW** (Phase 2D) — **CORRECTED, `AUTHZ-M10`** | `venue.promoter` **→** `venue.promoter_link` **and** `venue.promoter_code`(+`_scope`) | the caller is a live promoter of that event **by either route, link or CODE**: `venue.promoter.identity_id = auth.uid() AND status='active'`, then out to links **or** code scopes by `promoter_id` — §9. **The old row said `venue.promoter_link` and *"a live link exists for `(p_event_id, auth.uid())`"*: `promoter_link` has no identity column, so that predicate is false for every row forever, and link-only excludes the code-only promoter the feature actually creates** | §1.1c |
| `kernel.assert_door_session(p_device_id, p_session_id, p_door_session_id, p_session_token)` | **NEW** — **SIGNATURE CHANGED, `AUTHZ-H3`/`C54`** | `venue.door_session` (by PK) · `venue.scan_device` · `venue.door_pin` | a valid, unexpired, unrevoked door session **whose token the caller holds** binds that device to that session — §7. **Returns the bound `(device_id, event_session_id)`, NOT a boolean**, and raises rather than returning false. **The old two-argument row proved provisioning, not possession.** `EXEC: DEF` — `service_role` only; **never an RLS predicate** (RM-5) | §1.1d |
| **`kernel.money_role_grant_matured(p_org_id)`** | **NEW** — **`AUTHZ-C1B` / `C58`; absent from this table entirely until `F-4`** | `kernel.org_member` (`role`, `granted_at`) · `catalog.platform_config` (`authn.money_role_maturity_hours`) | the caller holds an **org-plane money role** (`org_owner` · `org_finance`) in `p_org_id` whose `granted_at` is at least `authn.money_role_maturity_hours` old. **An absent, NULL or unparseable key means NO grant is mature.** The only member of this set that is a function of **time** as well as role — it exists because every other money SoD test compares two `auth.uid()`s that one `org_owner` can mint. **Conjunct only, never a sole gate; binds both halves of both money SoD primitives; never applied to a deny or a cancel** | §1.1e |

All are `SECURITY DEFINER`, owned by `postgres`, `search_path` pinned (066/067), `STABLE`, and read **live
tables, never JWT claims** (C9 / RLS I-5). All take their actor from **`auth.uid()` inside the body and never
as a parameter** (**C35**) — every argument above is a **scope**, and a scope argument that does not bind to
the subject the operation acts on is the same defect wearing the other parameter (RPC §10.3, `AUTHZ-C1C`).
`EXEC: authenticated` for nine of them; `assert_door_session` alone is `DEF`.

`INFERENCE:` `has_org_role_over_venue` and `has_org_role_over_event` are new because the corpus **describes**
org→venue inheritance in prose but never names a helper for it. `VERIFIED`
`PHASE_2_RLS_PERMISSION_SPEC.md:147` says inheritance lives *"inside the write RPCs… not by widening venue
RLS"* — yet `:760` grants `org_owner/admin` a direct venue-table **read** (`A(venues of own org)`), which is a
read-path inheritance the prose says does not exist. Naming the helper closes that gap and stops every policy
from re-inlining the same two-table join, which is the *"hundreds of policy clauses"* failure mode Domain
Architecture §7.1 explicitly designs against.

### 6.3 Predicate shape per role — conceptual, not shippable SQL

```text
-- ORG PLANE (scope object = organization)
--   any org-scoped table carrying org_id
USING ( kernel.has_org_role(org_id, ARRAY['org_owner','org_admin']) )

-- VENUE PLANE (scope object = venue)
--   any venue-scoped table carrying venue_id
USING ( kernel.has_venue_role(venue_id, ARRAY['venue_manager','venue_box_office']) )

-- VENUE PLANE, with the ratified org→venue inheritance on the READ path
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
-- Asserted inside a SECURITY DEFINER RPC, reachable only from the service_role edge path:
--   PERFORM kernel.assert_door_session(p_device_id, p_session_id);   -- raises on failure
```

### 6.4 Multi-venue `venue_manager` — the answer, and why there is no N+1

**A `venue_manager` grant scopes to exactly one venue.** `VERIFIED:` the PK is `(venue_id, identity_id, role)`,
so a person managing five venues holds five rows. There is no wildcard, no `venue_id IS NULL` grant, and no
"all venues of org X" row. Multi-venue authority has exactly two sanctioned expressions:

1. **N venue grants** — right for a person who manages three of an org's forty venues.
2. **An org-plane role that inherits down** — right for a person who manages all of them. `VERIFIED`
   `SNATCH_IT_CANONICAL_DATA_MODEL.md` §8: *"Org-level roles inherit down to the org's venues… venue/event
   roles do not inherit up."* This is what O-2's `org_admin` is for.

**No N+1, and here is the argument.** The predicate takes the scope id as a *parameter*, so it is evaluated
against each row's own `venue_id` during the scan:

```text
SELECT … FROM venue.order WHERE event_session_id = $1
  -- policy: kernel.has_venue_role(venue_id, ARRAY['venue_manager'])
```

`has_venue_role` is a single **primary-key point probe** on `venue.staff_role` — an index-only lookup on
`(venue_id, identity_id, role)`. It is declared `STABLE`, so within one statement Postgres may cache the result
per distinct argument pair; and in practice a query filtered to one session touches one venue, so the helper
resolves once. The cost is O(distinct venues in the result set), not O(rows). It never degrades into a join
against the caller's full venue list, because **the caller's venue list is never materialized** — the question
asked is always "does this specific venue grant me this role?", never "which venues grant me roles?".

The one place the reverse question *is* asked — the dashboard's venue switcher — is a deliberate,
separate, indexed read: `VERIFIED` `PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md:904` provides an index on
`identity_id` for exactly this ("my venues"), and `PHASE_2_VENUE_DASHBOARD_PRODUCT_SPEC.md:198` confirms it is
one bounded read at context-bar load, *"plus venues of orgs where the user holds `org_owner`/`org_admin`"*, and
that *"there is no 'all organizations' or 'all venues' read for any non-platform principal anywhere in this
IA."* That read is a **projection for navigation**, never an authorization input.

### 6.5 INV-NOFORCE — the recursion invariant (new, and load-bearing)

`VERIFIED:` `PHASE_2_RLS_PERMISSION_SPEC.md:760-763` grants venue principals `A(own-venue roster)` on
`venue.staff_role` itself. A naïve implementation of that policy calls `has_venue_role`, which `SELECT`s
`venue.staff_role`, which fires the policy again — **infinite recursion, and Postgres reports it as a policy
error at query time, not at migration time.** The same trap exists on `kernel.org_member` (RLS §7.3 grants
`org_member` `A(own org roster)`) and on `kernel.platform_role` (§7.4).

The model does not recurse **only because** the helpers are `SECURITY DEFINER` owned by `postgres`, and the
table owner bypasses row-level security. That bypass disappears the moment anyone sets `FORCE ROW LEVEL
SECURITY` — a one-line change an engineer will plausibly make "for safety" during a hardening pass, at which
point all three authz tables become unqueryable and, worse, every policy that depends on them fails closed
platform-wide.

> **INV-NOFORCE (new invariant).** `kernel.org_member`, `venue.staff_role` and `kernel.platform_role` MUST NOT
> carry `FORCE ROW LEVEL SECURITY`. The predicate helpers depend on owner-bypass to terminate. Any migration
> or hardening pass that proposes `FORCE` on these three tables is rejected. The three tables are the
> **only** ones in the model with this exemption, and it must be asserted in the staging verification of the
> package that creates them, not merely documented.

`INFERENCE:` this belongs in the migration package's verification step as a positive assertion (query
`pg_class.relforcerowsecurity = false` for the three relations), because a documented rule that nothing checks
is a rule that lasts until the first hardening sprint.

### 6.6 Standing rules

> **RM-1** — Every role label begins with its plane token (`org_` / `platform_` / `venue_`). §3.4.
> **RM-2** — No RLS policy or RPC compares a bare role string, a display name, or a JWT claim. Only the
> **ten** helpers **enumerated by name** in §6.2, always with an explicit scope argument. (Extends RLS §2.3
> to display names.) **The count read "nine" here and in RLS `RM-2`, "eleven" in RLS §2.2's heading and in
> `T-RLS-ROLE-02` — six statements, three numbers. Under `HELPER-DERIVED` clause 4 no statement of this set
> may be a bare count**, because a count assertion passes on the wrong set of the right size, and that is
> precisely how `money_role_grant_matured` reached four money call sites with no defining contract
> (`AUTHZ-C1C`). Asserted by `T-RLS-ROLE-06` / `T-RPC-AUTHZ-17`.
> **RM-3** — Org→venue and org→event inheritance is expressed **only** through `has_org_role_over_venue` /
> `has_org_role_over_event`. No policy re-inlines the `catalog.venue → kernel.org_member` join.
> **RM-4** — Venue and event roles never inherit **up**. There is no venue→org path, in any helper.
> **RM-5** — A door session is never an RLS predicate. §7.
> **INV-NOFORCE** — §6.5.

---

## 7. The scanner credential model — decided and defended

### 7.1 The question, stated exactly

O-2: *"Do not give `scanner` a broad authenticated dashboard session if a narrower door-specific credential
model exists."*

A narrower model **does** exist and is already ratified. `VERIFIED:`

- `venue.door_pin` (`PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md:910-926`) — loginless, `event_session_id`-scoped,
  `expires_at`-bounded, `status ∈ active|revoked`, `pin_hash` **never client-readable**, constant-time
  compared inside the door-auth RPC (I-9).
- `venue.scan_device` (`:927-940`) — hardware identity, `manifest_version`, `last_sync_at`, `device_boot_id`
  for C23 offline ordering, `status ∈ active|retired`.
- `SNATCH_IT_CANONICAL_DATA_MODEL.md` §1.3: *"PINs are device identities, not users."*
- `SNATCH_IT_DOMAIN_ARCHITECTURE.md` §7.3: *"Temp door staff who shouldn't get an account at all get a PIN,
  not a `staff_role`."*

But the frozen spec **also** gives the door an authenticated session. `VERIFIED:`
`PHASE_2_RLS_PERMISSION_SPEC.md:43`:

> `| 9 | `v_door` (venue_door) | `authenticated`/door_pin device principal | `has_venue_role(venue_id,[venue_door])` or valid `venue.door_pin` for the session | venue/session |`

That single row is the whole ambiguity: the door is *both* an authenticated user *and* a PIN device, and
`has_venue_role` — the predicate every venue policy in the corpus depends on — **changes what it reads
depending on who is calling it**. That is a predicate whose meaning is caller-dependent, which is the property
C36 was ratified to eliminate one level up.

### 7.2 The decision

**A scanner's session is a device-bound door session, not a Supabase `authenticated` session.**

Three artifacts, and the session is the product of all three:

| Artifact | What it establishes | Issued by |
|---|---|---|
| `venue.scan_device` row | **which hardware** may present a PIN at this venue | `venue_manager` / `org_owner` / `org_admin` (F6) |
| `venue.door_pin` row | **the session secret**, bound to one `event_session_id`, expiring, revocable | `venue_manager` / `org_owner` / `org_admin` (F5) |
| **door session token** | the bearer artifact the device actually holds | the new `door-session` edge function |

The door session token:

- is minted **only** by a `door-session` edge function that validates `(device_id, pin_plain, event_session_id)`
  server-side, constant-time-compares against `pin_hash`, and checks `status='active' AND expires_at > now()`
  and `scan_device.status='active'`;
- is bound to `(device_id, event_session_id, pin_id)` and carries a TTL that is **`min(configured TTL,
  door_pin.expires_at)`** — a door session can never outlive its PIN;
- carries **no** Supabase `authenticated` role and **no** `auth.uid()`;
- authorizes exactly four capabilities and nothing else: **F8** scan/admit for that session, **F9** offline
  batch for that device, **F7** manifest sync for that device, **F10** guest-entry check-in
  (`status` + `checked_in_at` only) for that session. That is the complete list. It is `·` on every other row
  of §5, including the entire consumer plane.

**How it reaches the database.** The door client never talks to PostgREST. It calls the door edge function,
which holds `service_role` and invokes the definer RPC with an explicit, server-derived
`p_actor_device_id` — so the Postgres principal is `service_role` (a machine identity, exactly as
`PHASE_2_RLS_PERMISSION_SPEC.md:52` requires) acting on a **server-validated** device assertion, never on a
client claim. Inside the RPC, `kernel.assert_door_session(p_device_id, p_session_id)` re-checks the binding
against the live tables and raises on failure.

### 7.3 The alternative I rejected, and why

**Rejected: mint a Supabase JWT for the door with `role=authenticated` and a device claim.**

1. It re-creates the broad authenticated session O-2 forbids. Once the door holds an `authenticated` JWT with
   a real `auth.uid()`, every `USING (auth.uid() = …)` policy in the model becomes reachable from a device
   sitting on a bar. The blast radius of a stolen door tablet becomes "everything a fan can do", not "scan
   this room tonight".
2. It puts authority in a JWT claim, which C9 / RLS I-5 forbid for anything money-consequential — and
   admission **is** custody-consequential: it drives `kernel.tickets.state → scanned` through
   `kernel.mark_ticket_scanned` (`VERIFIED` `PHASE_2_RPC_FUNCTION_CONTRACTS.md:600`).
3. A JWT survives a revoke for up to its TTL. A door PIN is revoked *now*, and the next scan fails. That
   difference is the entire point of a door credential.

### 7.4 Why the authenticated `venue_scanner` grant still exists

It is not redundant. It is for a **named human** who scans and must be individually attributable — a door
lead, a supervisor doing spot checks. The distinction matters because of an attribution gap I found:

`VERIFIED:` `venue.scan` (`PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md:941-968`) has columns `scan_id`,
`ticket_atom_id`, `event_session_id`, `device_id`, `direction`, `scan_type`, `result`, `offline_pending`,
`device_boot_id`, `scan_sequence`, `fraud_flag`, `manifest_version`, `server_receipt_at`, `occurred_at`,
`created_at` — and **no actor column**. On the device path, `device_id` carries the identity. On the
authenticated-staff path, `device_id` is NULL (`VERIFIED` `:948`: *"null for online/web admits"*) and the row
records **who admitted nobody at all**.

> **`ADDITIVE SCHEMA CHANGE`** — add `venue.scan.actor_identity_id uuid NULL` (FK → `auth.users`, ON DELETE
> RESTRICT), set when the caller is an authenticated staff principal, NULL on the device path. Plus a CHECK
> that at least one of `device_id` / `actor_identity_id` is non-null, so no admission is anonymous. Without
> it, a `venue_scanner` grant is indistinguishable from a `venue_manager` grant in the ledger, and the door's
> insider-fraud trail has a hole in exactly the place O-2 asks for least privilege.

### 7.5 Consequence — `has_venue_role` stops reading door PINs

> **CHANGE.** `kernel.has_venue_role(p_venue_id, p_roles[])` reads `venue.staff_role` **only**. The clause
> *"Door path also accepts a valid non-expired `venue.door_pin` bound to the session as a `venue_door` device
> principal"* (`PHASE_2_RLS_PERMISSION_SPEC.md:123-125`) is **removed**.

`INFERENCE:` this is the most important structural consequence of the decision, and it is a strict
improvement independent of O-2. A predicate that reads a different table depending on the caller cannot be
reasoned about in a policy review: a reviewer looking at
`USING (kernel.has_venue_role(venue_id, ARRAY['venue_manager']))` has to know whether a PIN could ever satisfy
it. After the change, the answer is always no, for every policy in the corpus, without reading the helper.

**And a warning for the implementing engineer.** `auth.uid()` is **NULL** on the door path. Every policy and
RPC that assumes a non-null `auth.uid()` must be re-read against the door flow — but because the door reaches
the database only via `service_role`, RLS is bypassed on that path entirely and the *only* gate is
`assert_door_session` inside the RPC. That is a deliberate concentration of the door's entire authorization
surface into one auditable function, which is the point; it is also a single point of failure, so
`assert_door_session` must be treated as a security-critical function: pinned `search_path`, `postgres`-owned,
`EXECUTE` revoked from `anon`/`authenticated`, and covered by the package's adversarial verification.

### 7.6 Reconciliation with C46 and C37

**C46** (*"door refunds require an authenticated staff principal, never a door PIN"*) — `VERIFIED`
`_governance/PHASE_2_RATIFICATION_RECORD.md:38`.

**C46 binds refunds only. It does not constrain admission.** The reasoning: C46's integration points are
CDM §1.3's *"a door PIN can never authorize a refund"* and DA §5 ¶1.3/¶1.6/¶1.8 — all money statements. The
PIN-as-admission-principal model is the *ratified* §1.3 model that C46 was written on top of; had C46 intended
to abolish loginless admission it would have contradicted its own base text. C46 is satisfied here because the
door session is `·` on B6 (refund) and on every money row of §5, and because refund authority sits with
`org_finance` — an authenticated principal by construction. `venue_box_office` is the natural candidate for a
capped cash-refund-at-door authority and is **not granted one by this spec** (OD-5, §13).

**C37** (*"online door performs a live authoritative per-scan kernel read at the decision point"*) — `VERIFIED`
`:29`. **Orthogonal, and unweakened.** C37 constrains what `record_scan` *does*; the credential model
constrains who may *call* it. Both the door-session path and the `venue_scanner` path enter the same definer
RPC, which performs the same live kernel read under the same atom lock. Nothing about a device credential
makes the read less authoritative — if anything the concentration of the door path into one server-side
function makes C37's guarantee easier to certify, since there is exactly one call site to audit.

**C23/C6 offline reconciliation** — the door session is bound to `(device_id, event_session_id)`, which is
precisely the key `device_boot_id` + `scan_sequence` ordering needs. `INFERENCE:` binding the credential to
the device rather than to a person makes the offline first-admit-wins reconciliation *more* sound, because the
ordering key and the authorization key are the same key.

---

## 8. O-4 — door-lifecycle authority rows

**Scope note.** This section specifies **authority only**. The door state machine — states, transitions,
idempotency, what "open" means to the manifest, how the freeze interacts with in-flight transfers — is owned
by a separate agent (`design/o5-door-lifecycle`). Nothing here designs the lifecycle.

### 8.1 The authority rows

| Row | Action | Authorized | Denied (explicitly) | Predicate |
|---|---|---|---|---|
| **O4-1** | **Open** the door manifest for a session | `org_owner`, `org_admin`, `venue_manager` | `venue_box_office`, `venue_scanner`, **door session**, all finance, all marketing, all promoter roles | `has_venue_role(v,['venue_manager']) OR has_org_role_over_venue(v,['org_owner','org_admin'])` |
| **O4-2** | **Close** the door manifest | same as O4-1 | same as O4-1 | same as O4-1 |
| **O4-3** | **Move** the door-freeze time (`event_session.door_open_at`) | same as O4-1 | same as O4-1 | same as O4-1 |
| **O4-4** | **Change event security configuration** | same as O4-1 | same as O4-1 | same as O4-1 |
| **O4-5** | **Disable** a transfer freeze | `platform_admin` (step-up) — **OD-7** | everyone below platform, incl. all three O4-1 roles | `is_platform(['platform_admin'])` |
| **O4-6** | **Scan / admit** against an already-open manifest | `venue_scanner`, **door session**, `venue_manager` | everyone else | `has_venue_role(v,['venue_scanner','venue_manager'])` OR `assert_door_session(d,s)` |
| **O4-7** | Sync the manifest to a device | `venue_manager` (any device), `venue_scanner` / door session (**own device only**) | everyone else | as O4-6, plus `device_id` binding |

**Every one of O4-1 … O4-5 is privileged, audited, and server-side.** Each writes `kernel.admin_audit` in the
same transaction with actor, reason code and before/after, and each is idempotent on the session's current
state. None is reachable by direct client DML (GP-1).

### 8.2 What changes versus the frozen corpus

`VERIFIED:` `PHASE_2_VENUE_DASHBOARD_PRODUCT_SPEC.md:1120` (delta Δ1) proposed:

> *"Role: `has_venue_role([venue_manager, venue_door])` OR `has_org_role([org_owner, org_admin])`."*

and at `:1177` explicitly declined to settle it:

> *"A `venue_manager` is often not at the door at 11 p.m.; a `venue_door` PIN principal is, but it is a
> deliberately weak, loginless device identity… `INFERENCE:` the door principal is the operationally correct
> actor… but this is a security decision I should not make alone."*

**O-4 settles it: the door principal is removed from that authority list.** The operational objection is real
and remains real — a manager may not be at the door — but O-4's answer is that opening the manifest freezes
custody platform-wide for that session, which is a security boundary, and *"scanner may not create the
security boundary."* The operational answer is scheduling (`door_open_at` is set in advance by a manager) plus
remote action (the dashboard is an online surface; a manager can open the manifest from anywhere), not a
weaker credential at the door.

`INFERENCE:` there is a real operational risk here that the owner should see rather than discover at 11 p.m.:
if `door_open_at` was mis-set and no `venue_manager` is reachable, the door cannot open. The mitigation is
scheduling plus the org-plane fallback (`org_owner`/`org_admin` can act remotely), and — if that proves
insufficient in practice — a **time-boxed, audited, break-glass** grant, which is a product decision, not a
role-model one. Noted as **OD-8**.

### 8.3 The three-way separation this produces

| | Configure the door | Open/close the boundary | Admit people |
|---|:-:|:-:|:-:|
| `org_owner` / `org_admin` | ✔ | ✔ | ✔ (via venue_manager path) |
| `venue_manager` | ✔ | ✔ | ✔ |
| `venue_box_office` | · | · | · (sells; does not admit) |
| `venue_scanner` | · | · | ✔ |
| **door session** | · | · | ✔ |
| `platform_admin` | ✔ | ✔ | ✔ (override, audited) |

`INFERENCE:` the shape worth noticing is that **admission is the widest capability and configuration is the
narrowest** — the opposite of how door roles are usually built, and exactly what least privilege demands: the
principal standing in the doorway all night holds the *fewest* powers, and the power that is hardest to
misuse (scanning a valid ticket) is the one distributed most widely.

---

## 9. Promoters and ambassadors — non-admin attribution identities

O-2: *"Promoters and ambassadors are NOT automatically organization administrators. They remain
attribution/distribution identities unless explicitly invited into an organization with an administrative
role."*

### 9.1 `venue_promoter` is removed from the venue enum

`VERIFIED:` today `venue_promoter` is a label in `venue.staff_role`
(`PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md:899`), tested by `has_venue_role`
(`PHASE_2_RLS_PERMISSION_SPEC.md:45`), and the spec itself notes its visibility is *"deliberately narrow (own
links/attributions/commission only… never the back office)"* (`:52-54`).

**Remove it.** Three reasons:

1. **O-2 says promoters are not administrators.** `venue.staff_role` is the administrative grant table; every
   other label in it confers operational authority over the venue. A promoter in that table is an
   administrator with an empty capability set — the category error O-2 names.
2. **It shrinks the blast radius of `grant_staff_role`.** `VERIFIED` `:753`: `venue.grant_staff_role` is
   authorized to `venue_manager` and org owner/admin. Today that RPC's input domain includes a label that is
   not an operational grant, so "may this caller grant a venue role?" has to be answered per-label. After
   removal, every label in the enum is an operational grant and the question is uniform — which is what makes
   a tier guard reviewable.
3. **It is row-ownership wearing a role costume.** A promoter's entire authority is "my own links, my own
   attributions, my own commission" — that is `auth.uid()` row ownership, which the model already expresses
   everywhere else without a role label.

**Where promoter authority lives instead:** `venue.promoter`, `venue.promoter_link`, `venue.attribution`
(`VERIFIED` schema §3.17; migration package `venue_promoter_engine`, roadmap Phase 2D). The predicate is
`kernel.is_promoter_for_event(p_event_id)` plus plain row ownership
(`promoter_link.identity_id = auth.uid()`).

### 9.2 Ambassadors — already correct, confirmed

`VERIFIED:` `SNATCH_IT_DOMAIN_ARCHITECTURE.md:1678, 1685` places Ambassador in the *"Consumer & growth plane
(derived predicates, **not stored account types**)"* with basis *"affiliate relationship (derived)"*, and
`SNATCH_IT_DOMAIN_ARCHITECTURE.md:2306` keeps the referral edge *"distinct from the commercial promoter
engine."* `VERIFIED:` the only applied ambassador artifact is
`supabase/migrations/20260730212326_ambassador_applications_website_form.sql` — an **application** form, not a
grant.

**No change. Ambassador appears in none of the three enums, and must not be added to any of them.**

### 9.3 Escalation proof

**Claim.** Neither a promoter nor an ambassador can reach any administrative capability without an explicit
org or venue grant.

*Proof.*
1. After §9.1, a promoter holds **no row** in `venue.staff_role`, and an ambassador never did. Neither holds a
   row in `kernel.org_member` or `kernel.platform_role` by virtue of being a promoter or ambassador.
2. By **RM-2**, every administrative capability in §5 is gated by `has_org_role`, `has_venue_role`,
   `has_event_role`, `has_org_role_over_venue`, `has_org_role_over_event`, or `is_platform`. Each of those
   returns true only if a live row exists in one of those three tables for `auth.uid()`.
3. By (1) and (2), every such predicate returns **false** for a promoter or ambassador acting as such.
   Deny-by-default (I-1) then denies the capability — no policy is required to say so.
4. The only writers of the three grant tables are `grant_org_role` / `invite_org_member` + `accept_org_invite`
   / `grant_staff_role` / `grant_platform_role` (`VERIFIED` RLS §11). **None takes a `promoter_id`,
   `promoter_link_id`, `attribution_id`, or referral id as input**, so no promoter or referral artifact can
   appear on the write path to a grant.
5. Therefore the only path from promoter/ambassador to administrator is an explicit invitation or grant by an
   already-authorized principal — which is exactly O-2's *"unless explicitly invited into an organization with
   an administrative role."* ∎

**Residual surface, stated honestly.** The proof holds for *authority*. It does not by itself bound *data
exposure*: a promoter who is separately granted, say, `venue_marketing` at one venue holds the union of both,
and the union of "sees own attributed sales" and "exports the venue's contactable audience" is a person who can
correlate their own attribution against the venue's customer list. `INFERENCE:` that is an acceptable union
(both grants are deliberate acts by a venue manager), but the CRM export's live re-authorization at download
(`VERIFIED` `PHASE_2_VENUE_DASHBOARD_PRODUCT_SPEC.md:543`) and the money-column exclusion (H3) are what keep it
bounded, and they are load-bearing for that reason.

---

## 10. `org_member` — role label vs membership fact

**Both concepts survive, and they are named differently.**

| Concept | Name | Realized as | Predicate |
|---|---|---|---|
| **Org affiliation** — this person is connected to this org **at all** | *affiliation* | the **existence** of a `kernel.org_member` row for `(org_id, auth.uid())`, at any role | `kernel.is_org_affiliate(p_org_id)` |
| **Base membership role** — connected, with **no** operational authority | `org_member` | the enum **label** `org_member` in that row's `role` column | `has_org_role(p_org_id, ['org_member'])` |

`INFERENCE:` I keep the label `org_member` rather than renaming it. O-2 says it *"may remain"*; it appears in
every downstream spec; and the ambiguity the ruling request identifies is real but is fully resolved by naming
the *other* concept. Renaming the label would ripple through six specs to fix a problem that a new predicate
name fixes at the source. The residual oddity — that the table `kernel.org_member` and one of its enum labels
are the same string — is cosmetic once the two predicates are distinct, and is called out here so a reviewer
is never guessing which is meant. (Alternative, if the owner prefers: rename the label to `org_affiliate` and
leave the table alone. **OD-9**, low stakes.)

**The hard rule that makes this safe:**

> **RM-6** — Affiliation is a **scoping** input, never an **authorizing** one. `is_org_affiliate` may
> determine *which* orgs appear in a context switcher or *which* rows a roster read returns. It may **never**
> appear as the sole gate on any capability in §5. Every capability requires a named role.

`VERIFIED:` this matches what `org_member` already gets and nothing more — RLS §7.3 grants it `A(own org
roster)`, and §7.2 note 4 restricts it to `display_name` + `status` on the org record. `VERIFIED:` it also
matches Domain Architecture §7.3's *"Org-wide operational authority is `org_member`, not a venue role sprayed
across every venue"* — read correctly, that sentence says org-wide *scoping* rides on membership, and the
authority still comes from the role.

---

## 11. Required edits to every other spec — file · section · old · new

Format: exact old text where a single edit suffices; a mechanical rewrite rule where the same substitution
recurs. Line numbers are at `phase2/consolidation@11ea2eb`.

### 11.1 `docs/architecture/PHASE_2_SPEC_FOUNDATION.md`

| # | Section | Old | New |
|---|---|---|---|
| F-1 | §4 C36, line 51 | ``- `kernel.org_member(org_id, identity_id, role)` where role ∈ `org_owner|org_admin|org_finance|org_member` (org scope).`` | ``- `kernel.org_member(org_id, identity_id, role)` where role ∈ `org_owner|org_admin|org_finance|org_marketing|org_promoter_manager|org_member` (org scope).`` |
| F-2 | §4 C36, line 52 | ``- `venue.staff_role(venue_id, identity_id, role)` where role ∈ `venue_manager|venue_finance|venue_door|venue_promoter` (venue scope).`` | ``- `venue.staff_role(venue_id, identity_id, role)` where role ∈ `venue_manager|venue_finance|venue_box_office|venue_marketing|venue_promoter_manager|venue_scanner` (venue scope).`` |
| F-3 | §4 C36, line 54 | `Predicate helpers: … `kernel.is_platform(role[])`.` | append: `` · `kernel.has_org_role_over_venue(venue_id, role[])` · `kernel.has_org_role_over_event(event_id, role[])` · `kernel.is_org_affiliate(org_id)`. Door principals are NOT tested by `has_venue_role` — see PHASE_2_ROLE_MODEL_SPEC §7. `` |
| **F-4** | §4 C36, the Predicate-helpers line | the eight-name list left by `F-3` **as extended by the authz pass** — `has_org_role` · `has_venue_role` · `has_event_role` · `is_platform` · `has_org_role_over_venue` · `has_org_role_over_event` · `is_org_affiliate` · `money_role_grant_matured` | **complete it to the canonical TEN and enumerate, never count** — the list is missing **`kernel.assert_door_session(device_id, session_id, door_session_id, token)`** and **`kernel.is_promoter_for_event(event_id)`**, both of which are helpers in §6.2, in RLS §2.2 and in RPC §1.1c/§1.1d, and neither of which any `F-n` row ever asked for. **`SPEC_FOUNDATION` §4 is the file every implementation spec is told to take its names from**, so a short list there is a helper an implementer never learns exists. **Filed here because `SPEC_FOUNDATION` line 58 records that `F-3` was the last `F-n` and that `money_role_grant_matured` was therefore added *on the authz pass's own authority* with the omission reported back — this row is that report answered** (`AUTHZ-C1C`; ratification **C76**). |

### 11.2 `docs/architecture/PHASE_2_RLS_PERMISSION_SPEC.md`

| # | Section | Old | New |
|---|---|---|---|
| R-1 | §1.1 table, line 43 | ``| 9 | `v_door` (venue_door) | `authenticated`/door_pin device principal | `has_venue_role(venue_id,[venue_door])` or valid `venue.door_pin` for the session | venue/session |`` | ``| 9 | `v_sca` (venue_scanner) | `authenticated` | `has_venue_role(venue_id,[venue_scanner])` | venue |`` **plus a new row** ``| 9b | `door` (door session) | **none** — `service_role` edge path, `auth.uid()` IS NULL | `kernel.assert_door_session(device_id, session_id)` inside the RPC; NEVER an RLS predicate | device+session |`` |
| R-2 | §1.1 table, line 45 | ``| 11 | `promo` (promoter) | `authenticated` | `has_venue_role(venue_id,[venue_promoter])` (enum label = `venue_promoter`) | venue |`` | ``| 11 | `promo` (promoter) | `authenticated` | `kernel.is_promoter_for_event(event_id)` / `promoter_link.identity_id = auth.uid()` — **a relationship, not a role**; holds NO row in `venue.staff_role` | event/row |`` |
| R-3 | §1.1, lines 52-54 (the `promo ↔ venue_promoter` note) | ``> **`promo` ↔ `venue_promoter`.** The prompt's `promoter` is the C36 **venue-scope** `venue_promoter` label, tested by `has_venue_role`. It is NOT an org or platform role. …`` | ``> **`promo` is NOT a role.** `venue_promoter` was removed from the venue enum (ROLE_MODEL §9.1). A promoter's authority is row ownership over `venue.promoter_link` / `venue.attribution`, tested by `kernel.is_promoter_for_event` — never by `has_venue_role`, which returns false for every promoter. …`` |
| R-4 | §1.1 table | **add 5 rows** | `org_marketing`, `org_promoter_manager`, `venue_box_office`, `venue_marketing`, `venue_promoter_manager`, each `authenticated`, each tested by the plane helper. Renumber. |
| R-5 | §2.1 table, line 105 | `` | **org** | `kernel.org_member.role` | `org_owner` · `org_admin` · `org_finance` · `org_member` | `` | `` | **org** | `kernel.org_member.role` | `org_owner` · `org_admin` · `org_finance` · `org_marketing` · `org_promoter_manager` · `org_member` | `` |
| R-6 | §2.1 table, line 106 | `` | **venue** | `venue.staff_role.role` | `venue_manager` · `venue_finance` · `venue_door` · `venue_promoter` | `` | `` | **venue** | `venue.staff_role.role` | `venue_manager` · `venue_finance` · `venue_box_office` · `venue_marketing` · `venue_promoter_manager` · `venue_scanner` | `` |
| R-7 | §2.1 prose after the table | `The label sets share **no common string**. …` | append the §3.4 proof-by-enumeration and rule **RM-1**. |
| R-8 | §2.2, lines 123-125 | ``- **`kernel.has_venue_role(venue_id, role[])`** → reads `venue.staff_role` for `(venue_id, auth.uid(), role)` live. Door path also accepts a valid non-expired `venue.door_pin` bound to the session as a `venue_door` device principal.`` | ``- **`kernel.has_venue_role(venue_id, role[])`** → reads `venue.staff_role` for `(venue_id, auth.uid(), role)` live. **It reads no other table.** The door-PIN branch is REMOVED (ROLE_MODEL §7.5); door principals never satisfy this predicate.`` |
| R-9 | §2.2 | **add 3 bullets** | `has_org_role_over_venue`, `has_org_role_over_event`, `is_org_affiliate` per §6.2. |
| R-10 | §2.4 | `An org's `org_owner`/`org_admin` implicitly has venue-management authority … **not** by widening venue RLS to org roles.` | append: `On the READ path the inheritance is expressed by `kernel.has_org_role_over_venue`, never by re-inlining the `catalog.venue → kernel.org_member` join (**RM-3**). This closes the gap between this paragraph and §9.9's `A(venues of own org)` read grant.` |
| R-11 | §3, invariant table | **add row** | `` | I-12 | **INV-NOFORCE** | `kernel.org_member`, `venue.staff_role`, `kernel.platform_role` MUST NOT carry `FORCE ROW LEVEL SECURITY`; the definer helpers rely on owner-bypass to terminate. Asserted in staging verification, not merely documented. | `` |
| R-12 | §7.x + §9.x matrices | **mechanical rewrite** — 34 lines contain `venue_door`; 3 contain `venue_promoter`; ~75 lines contain a bare `promoter` matrix label | (a) `venue_door` → `venue_scanner`, and **add a distinct `door session` row** wherever the old `venue_door` row carried a PIN-path capability (only F7–F10 of §5 keep it; everywhere else the door session is `D`). (b) Delete every `venue_promoter` / `promoter` **matrix row**; promoters are covered by the owner/row-ownership rows. (c) Add matrix rows for the five new labels per §5. |
| R-13 | §9.9 `venue.staff_role` | role list in the row labels | replace `venue_door/finance/promoter` with `venue_finance/box_office/marketing/promoter_manager/scanner`. |
| R-14 | §11 EXEC table, line 1094-1102 | every `[venue_door, venue_manager]` / `[venue_door,venue_manager]` | `[venue_scanner, venue_manager]`; and for `venue.record_scan` / `record_offline_scans` / manifest-sync, add `OR a valid door session (service_role edge path, `assert_door_session`)`. |
| R-15 | §11, line 1101 | `` | `venue.allocate_comp`/`issue_comp` | `has_venue_role([venue_manager])` OR org_owner/admin (step-up seam C39) | `` | **split into two rows**: `venue.allocate_comp` → `has_venue_role([venue_manager])` OR org_owner/admin; `venue.issue_comp` → `has_venue_role([venue_manager, venue_box_office])` OR org_owner/admin. Both C39-gated. |
| R-16 | §11 | **add rows** | `venue.open_door_manifest` / `close_door_manifest` / `set_door_open_at` / `set_event_security_config` (O4-1…O4-4 authority); `venue.decide_flagged_attribution` (G5); `venue.read_operational_audit` (A6); `venue.list_attendees` (F11/F12); the CRM-export authorization (H2/H3). |
| R-17 | §15 | **add** | items resolved by this spec (role-set, scanner credential, door authority) with a pointer; retain items 1, 3, 4 (still open — OD-3/OD-4). |

### 11.3 `docs/architecture/PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md`

| # | Section | Old | New |
|---|---|---|---|
| S-1 | §3.9, line 899 | ``role` enum(`venue_manager` · `venue_finance` · `venue_door` · `venue_promoter`) part of PK`` | ``role` **text + CHECK** in (`venue_manager` · `venue_finance` · `venue_box_office` · `venue_marketing` · `venue_promoter_manager` · `venue_scanner`) part of PK — CHECK not native enum, so the commitment stays correctable (ROLE_MODEL §3.5)`` |
| S-2 | §1.3 `kernel.org_member` | org role enum list | add `org_marketing`, `org_promoter_manager`; same text-plus-CHECK note. |
| S-3 | §3.9 | **add** | **INV-NOFORCE**: this table must never carry `FORCE ROW LEVEL SECURITY`. Same note on §1.3 `org_member` and §1.4 `platform_role`. |
| S-4 | §3.12 `venue.scan` columns | (no actor column) | **add** `actor_identity_id uuid NULL` FK→`auth.users` ON DELETE RESTRICT + CHECK `(device_id IS NOT NULL OR actor_identity_id IS NOT NULL)`. §7.4. |
| S-5 | §2.2 `catalog.event` | (only `title`, `status`) | **add** marketing fields per venue dashboard Δ5 — `description`, `hero_image_ref`, `category`, `genre_tags` (D3/H4 have no columns to write today). |
| S-6 | §3.9 | (venue-scoped grants only) | **document** the event-scoped-grant extension point: PK becomes `(venue_id, identity_id, role, event_id)` with `event_id` nullable + `expires_at` + a sweep. Deferred, pre-cleared as additive. Venue dashboard Δ8 (`:1144`). |

### 11.4 `docs/architecture/PHASE_2_RPC_FUNCTION_CONTRACTS.md`

| # | Section | Old | New |
|---|---|---|---|
| P-1 | §1.1, lines 109-111 | ``**Reads:** `kernel.org_member` / `venue.staff_role` (+ valid non-expired `venue.door_pin` for `venue_door`) / `kernel.platform_role` …`` | ``**Reads:** `kernel.org_member` / `venue.staff_role` / `kernel.platform_role` … `venue.door_pin` is NOT read by any role predicate; the door path is `kernel.assert_door_session` (ROLE_MODEL §7).`` |
| P-2 | §1.1 | **add contracts** | `has_org_role_over_venue`, `has_org_role_over_event`, `is_org_affiliate`, `assert_door_session`, `is_promoter_for_event`. |
| P-3 | lines 325, 352, 372, 507-508, 588, 600-601, 613-614 | every `venue_door` occurrence (8 lines) | `venue_scanner`; and for `record_scan` / `record_offline_scans` / manifest-sync, state the two entry paths (authenticated `venue_scanner` **or** `service_role` edge with `assert_door_session`). |
| P-4 | §comp | `venue.allocate_comp` / `issue_comp` shared authority | split per R-15. |
| P-5 | new §  | — | contracts for O4-1…O4-4 (door lifecycle **authority** rows only — the state machine belongs to `design/o5-door-lifecycle`), G5, A6, F11/F12. |

### 11.5 `docs/architecture/PHASE_2_SUPABASE_MIGRATION_PLAN.md`

| # | Section | Old | New |
|---|---|---|---|
| M-1 | line 363 | ``- `kernel.org_member` (PK `(org_id,identity_id)`; `role` CHECK in `org_owner/org_admin/org_finance/org_member`).`` | ``… `role` CHECK in `org_owner/org_admin/org_finance/org_marketing/org_promoter_manager/org_member`.`` |
| M-2 | line 496 | ``  `venue_manager/venue_finance/venue_door/venue_promoter` — **disjoint** from org/platform labels, C36;`` | ``  `venue_manager/venue_finance/venue_box_office/venue_marketing/venue_promoter_manager/venue_scanner` — **disjoint** from org/platform labels, C36;`` |
| M-3 | venue-staff-roles package, staging verification | `disjoint CHECK rejects an `org_*`/`platform_*` label` | append: `+ assert `pg_class.relforcerowsecurity = false` for `venue.staff_role`, `kernel.org_member`, `kernel.platform_role` (INV-NOFORCE) + assert the full 15-label enumeration matches ROLE_MODEL §3.4 exactly.` |
| M-4 | promoter-engine package | `venue.promoter`, `promoter_link`, `attribution` | append: `+ `kernel.is_promoter_for_event`; note that `venue_promoter` is NOT a staff_role label (ROLE_MODEL §9.1).` |
| M-5 | scan package | `venue.door_pin`, `scan_device`, `scan` | append `venue.scan.actor_identity_id` (S-4) and the `door-session` edge function dependency. |

### 11.6 `docs/architecture/PHASE_2_VENUE_DASHBOARD_PRODUCT_SPEC.md`

| # | Section | Old | New |
|---|---|---|---|
| V-1 | §18 role-set delta, line 1162 | the whole paragraph ending **"Needs a ruling** on whether MVP accepts the four-role model as-is — this spec assumes it does." | **RESOLVED by O-2.** Replace with a pointer to ROLE_MODEL §3/§4: box office is `venue_box_office`, marketing is `venue_marketing`/`org_marketing`, promoter manager is `venue_promoter_manager`/`org_promoter_manager`, door is `venue_scanner`. `scan_scopes` remains unmodelled (deferred, §12). |
| V-2 | §18 Δ1, line 1120 | ``Role: `has_venue_role([venue_manager, venue_door])` OR `has_org_role([org_owner, org_admin])`.`` | ``Role: `has_venue_role([venue_manager])` OR `has_org_role_over_venue([org_owner, org_admin])`. **Door principals are excluded by O-4** — see ROLE_MODEL §8.`` |
| V-3 | §18, line 1177 | the whole `INFERENCE:` paragraph declining to settle door authority | **RESOLVED by O-4.** Replace with ROLE_MODEL §8.2, including the operational-risk note and OD-8. |
| V-4 | line 874 | ``role ∈ `venue_manager` · `venue_finance` · `venue_door` · `venue_promoter``` | the six-label venue set; keep the multi-select UI note (it is now *more* right — §6.1). |
| V-5 | lines 545-546 | export allow-list / deny-list | allow-list gains `org_marketing` (org grain) and `venue_marketing` (venue grain), **audience columns only**; deny-list gains `venue_box_office`, `venue_scanner`, `venue_promoter_manager`, `org_promoter_manager`; `venue_door` → `venue_scanner`. |
| V-6 | lines 275, 280, 285, 291, 510, 563, 669, 685, 1128 | 13 lines carrying `venue_door` | `venue_scanner`, and distinguish the **door session** wherever the capability is the PIN path (F7–F10). |
| V-7 | §13.x role-management surfaces | single-plane role pickers | the role picker now offers six venue labels and six org labels; tier guards unchanged. |
| V-8 | §18 Δ7 (attribution decision, line 1132) | `Role: `has_venue_role([venue_manager])` OR `has_org_role([org_owner, org_admin])`; `platform_risk`…` | unchanged authority, **plus** an explicit denial of both promoter-manager labels (§4.3 SoD). |

### 11.7 Frozen constitutions — delta only, applied by a later integration pass

**These files are FROZEN. The edits below are recorded, not applied.**

| # | File · Section | Old | New |
|---|---|---|---|
| D-1 | `SNATCH_IT_DOMAIN_ARCHITECTURE.md:156` | ``role (owner/manager/finance/marketing/door/promoter_manager), per-event scan scopes.`` | the six plane-prefixed venue labels. **Pre-C36 bare labels — a defect, §14.5.** |
| D-2 | `SNATCH_IT_DOMAIN_ARCHITECTURE.md:761` | ``| **venue staff** (`manager` / `finance` / `marketing` / `door` / `promoter_manager`) | `venue.staff_roles` …`` | six plane-prefixed labels; also `staff_roles` → `staff_role` (physical name). |
| D-3 | `SNATCH_IT_DOMAIN_ARCHITECTURE.md:1546` (mermaid ER) | ``text role "owner|manager|finance|marketing|door|promoter_manager"`` | ``text role "venue_manager|venue_finance|venue_box_office|venue_marketing|venue_promoter_manager|venue_scanner"`` |
| D-4 | `SNATCH_IT_DOMAIN_ARCHITECTURE.md:2235` | ``role ∈ `owner`/`manager`/`finance`/`marketing`/`door`/`promoter_manager`, plus per-event `scan_scopes``` | six plane-prefixed labels; `scan_scopes` marked as a deferred extension point. |
| D-5 | `SNATCH_IT_DOMAIN_ARCHITECTURE.md` §7.2 catalog | display-name catalog | add the stored label beside each display name; mark Promoter and Ambassador **"not a role — derived"**. |
| D-6 | `SNATCH_IT_DOMAIN_ARCHITECTURE.md` §7.6 matrix (line 1756) | the 15-column matrix | **SUPERSEDED** by ROLE_MODEL §5. Replace the matrix with a pointer; keep the mermaid authorization-flow diagram (still correct). |
| D-7 | `SNATCH_IT_DOMAIN_ARCHITECTURE.md` §7.2 Marketing row | ``**Cannot** touch inventory pricing, orders, PII beyond aggregates, finance, or scanning.`` | ``**Cannot** touch inventory pricing, orders, finance, or scanning. **May** export the contactable-audience CRM slice at its plane's grain, money columns excluded (O-2; ROLE_MODEL §4.2).`` |
| D-8 | `SNATCH_IT_CANONICAL_DATA_MODEL.md` §1.3 Staff Role bullet | ``…scope-qualified **with structurally disjoint per-plane label sets** …`` | unchanged in principle; append the six-label venue set and the door-session model (§7); note `venue_promoter` removal. |
| D-9 | `SNATCH_IT_CANONICAL_DATA_MODEL.md` §15 C36 row (line 633) | `Integrated: §1.3 Staff Role, §8.` | append `; label sets finalized in PHASE_2_ROLE_MODEL_SPEC §3 (O-2).` |
| D-10 | `_governance/PHASE_2_RATIFICATION_RECORD.md` | — | **add rows O-2 and O-4** with this file as their integration point. |

---

## 12. Classification of every element

| # | Element | Classification |
|---|---|---|
| 1 | Three enum memberships (§3.1–§3.3) | `SPEC CORRECTION` — nothing is applied; the enums are still editable (VERIFIED §1) |
| 2 | `venue_door` → `venue_scanner` rename | `SPEC CORRECTION` |
| 3 | `venue_promoter` removal from the venue enum | `SPEC CORRECTION` |
| 4 | 5 new labels (`org_marketing`, `org_promoter_manager`, `venue_box_office`, `venue_marketing`, `venue_promoter_manager`) | `SPEC CORRECTION` |
| 5 | `text` + CHECK instead of native enum (§3.5) | `SPEC CORRECTION` — **OD-6** |
| 6 | Master matrix §5 superseding RLS §7.x/§9.x and DA §7.6 | `SPEC CORRECTION` |
| 7 | `has_venue_role` drops the door-PIN branch (§7.5) | `SPEC CORRECTION` + `NEW RPC` (revised contract) |
| 8 | `kernel.has_org_role_over_venue` | `NEW RPC` |
| 9 | `kernel.has_org_role_over_event` | `NEW RPC` |
| 10 | `kernel.is_org_affiliate` | `NEW RPC` |
| 11 | `kernel.assert_door_session` | `NEW RPC` |
| 12 | `kernel.is_promoter_for_event` | `NEW RPC` (Phase 2D, with the promoter engine) |
| 13 | `venue.open_door_manifest` / `close_door_manifest` (O4-1/O4-2 **authority only**) | `NEW RPC` — state machine owned by `design/o5-door-lifecycle` |
| 14 | `venue.set_door_open_at` (O4-3) | `NEW RPC` — same boundary |
| 15 | `venue.set_event_security_config` (O4-4) | `NEW RPC` — same boundary |
| 16 | `venue.issue_comp` split from `allocate_comp` (E6/E7) | `NEW RPC` (split of an existing contract) |
| 17 | `venue.decide_flagged_attribution` (G5) | `NEW RPC` — venue dashboard Δ7; storage shape not mine |
| 18 | `venue.read_operational_audit` (A6) | `NEW RPC` — venue dashboard Δ2 |
| 19 | `venue.list_attendees` (F11/F12, column-scoped by role) | `NEW RPC` — venue dashboard Δ3 |
| 20 | CRM export authorization split (H2 audience / H3 money) | `NEW RPC` (column projection on the existing export) |
| 21 | `door-session` edge function (mint + validate the door session) | `NEW EDGE FUNCTION` |
| 22 | Door scan/sync/offline-batch relay via `service_role` | `NEW EDGE FUNCTION` (may be the same function; separate routes) |
| 23 | `venue.scan.actor_identity_id` + non-anonymous CHECK (§7.4) | `ADDITIVE SCHEMA CHANGE` |
| 24 | `catalog.event` marketing fields (D3/H4 have nothing to write) | `ADDITIVE SCHEMA CHANGE` — venue dashboard Δ5 |
| 25 | Event-scoped staff grants (`event_id` + `expires_at`, PK extension) | `ADDITIVE SCHEMA CHANGE` — **deferred**, pre-cleared; venue dashboard Δ8 |
| 26 | `scan_scopes` (per-ticket-type door narrowing, DA §7.3) | `ADDITIVE SCHEMA CHANGE` — **deferred**; the door-session token can carry the scope set since it is minted server-side |
| 27 | INV-NOFORCE (§6.5) | `NO SCHEMA CHANGE` — a prohibition + a verification assertion |
| 28 | RM-1 … RM-6 standing rules | `NO SCHEMA CHANGE` |
| 29 | Org affiliation vs `org_member` label (§10) | `NO SCHEMA CHANGE` — naming + one new predicate (#10) |
| 30 | Ambassador model | `NO SCHEMA CHANGE` — confirmed correct as-is |
| 31 | Multi-venue `venue_manager` (§6.4) | `NO SCHEMA CHANGE` — the existing PK already answers it |
| 32 | Role-management surface: six venue + six org labels, multi-select, tier guards | `NEW DASHBOARD SURFACE` (extension of the existing §13 surface) |
| 33 | Door-lifecycle open/close control (O4-1/O4-2) on the venue dashboard | `NEW DASHBOARD SURFACE` |
| 34 | Marketing surfaces: event page/media editor, promo codes, audience export (D3/D9/H2/H4) | `NEW DASHBOARD SURFACE` |
| 35 | Box-office surface: door sale, single-record lookup, guest check-in, comp issuance (E2/E5/E7/F10/F11) | `NEW DASHBOARD SURFACE` |
| 36 | Promoter-manager surface: promoter/link/terms management + attribution reporting (G1–G4) | `NEW DASHBOARD SURFACE` — Phase 2D |
| 37 | Scanner PIN + device login flow (replaces any assumption of an account login) | `NEW RN SURFACE` — RN spec §7; `VERIFIED` `PHASE_2_REACT_NATIVE_PRODUCT_SPEC.md:54` already assumes loginless PIN, so this **confirms** the existing plan rather than changing it |
| 38 | Scanner: authenticated `venue_scanner` staff mode alongside PIN mode | `NEW RN SURFACE` — small addition to RN §7 |

---

## 13. Owner decisions still required

| # | Decision | Why it is owner-reserved | My recommendation |
|---|---|---|---|
| **OD-1** | **`venue_finance` is retained though O-2 does not list it.** O-2 enumerates the canonical administrative roles; it does not say the list is exhaustive. | Deleting a role O-2 did not mention would be inventing a ruling. Retaining one it did not mention could equally be wrong. | **Retain.** `VERIFIED` RLS §9.13/§11 both depend on it, and RLS §15 item 3 has an open question about it — deleting it would silently close that question. |
| **OD-2** | **`venue_door` → `venue_scanner` rename.** Is O-2's word `scanner` nominative or descriptive? | It renames a label in a frozen spec across 60 lines. | **Rename.** §4.5 gives a substantive O-4 reason beyond matching the ruling's word. Cheap to reverse now, impossible after the package ships. |
| **OD-3** | **`set_org_payout_destination`: `org_owner` only, or owner + finance?** `VERIFIED` RLS §11:1076 says owner only; DA §7.6:1765 says both. | **Money authority — O-1/O-3, branch `design/o1-o3-money-authority`.** Not mine. | None. Cell B1 left `⚠`. Flag to the money-authority agent. |
| **OD-4** | **Settlement close: `org_finance`, `venue_finance`, or both?** `VERIFIED` RLS §15 item 3 flags it open; §9.13/§11 list both. | Money authority; close drives payout. | None. Cell B10 left `⚠`. |
| **OD-5** | **May `venue_box_office` refund cash at the door?** C46 requires refund-at-door to run through an authenticated staff principal; box office is the natural candidate and is authenticated. | Money authority. O-2 gives box office no money authority; C46 implies *someone* authenticated must exist at the door. | None granted here. If the answer is yes, it needs its own cap, step-up and reason code — money-authority agent's call. |
| **OD-6** | **`text` + CHECK instead of a native enum** for all three role columns. | Edits a frozen physical-schema statement, and the two frozen specs already contradict each other on it. | **Adopt CHECK.** It makes the "cannot be edited afterwards" risk false, at zero cost at this cardinality. §3.5. |
| **OD-7** | **Who may disable a transfer freeze?** O-4 says not the scanner; it does not say who may. | The freeze is platform-wide custody state. | `platform_admin` under step-up. Placed there provisionally (F3/O4-5). |
| **OD-8** | **Break-glass for the door.** If `door_open_at` is mis-set and no manager is reachable, the door cannot open under O-4. | A product/ops risk trade-off, not a role-model one. | Ship without it; scheduling + remote org-plane action should cover it. Revisit if it bites. §8.2. |
| **OD-9** | **Rename the label `org_member` → `org_affiliate`?** | Cosmetic; O-2 says `org_member` may remain. | **Do not rename.** §10 resolves the ambiguity by naming the *other* concept. Listed only so the alternative is on the record. |
| **OD-10** | **Phase-2 migration package numbering collides with the repo.** `VERIFIED`: `supabase/migrations/` already contains `073`, `074`, `075`, while `PHASE_2_SUPABASE_MIGRATION_PLAN.md` §1 allocates `073–088` to Phase 2. The plan is **also internally inconsistent**: §1's table says `076` creates `venue.staff_role`, but the package header at `:491` is `077_venue_staff_roles_and_predicates` with its rollback labelled `076_*`. The ruling request refers to yet a third mapping (`077` org roles, `080` venue staff roles). | Renumbering is a different agent's scope — branch `phase2/renumber` exists. | **Not resolved here.** This spec deliberately refers to packages **by name**, never by number, so it survives any renumbering. Flagged so it is not lost. |

---

## 14. Defects found in the frozen corpus

| # | Defect | Evidence | Severity | Fix |
|---|---|---|---|---|
| **14.1** | **A role predicate whose meaning depends on the caller.** `has_venue_role` reads `venue.staff_role` *or* `venue.door_pin` depending on who calls it, so no policy review can determine from a `USING` clause whether a loginless PIN satisfies it. | `PHASE_2_RLS_PERMISSION_SPEC.md:43, 124`; `PHASE_2_RPC_FUNCTION_CONTRACTS.md:109` | **High** — undermines the reviewability C36 exists to provide | §7.5 — remove the PIN branch; door authority moves to `assert_door_session` |
| **14.2** | **RLS recursion hazard on all three authz tables.** Each grants a role-gated read of itself; termination depends silently on `postgres` owner-bypass. A `FORCE ROW LEVEL SECURITY` added during any hardening pass breaks all three and fails the whole model closed. | `PHASE_2_RLS_PERMISSION_SPEC.md:300-303` (org_member), `:757-763` (staff_role), `:347-353` (platform_role) | **High** — latent, triggered by a plausible one-line change | §6.5 **INV-NOFORCE**, asserted in staging verification |
| **14.3** | **The scan ledger cannot attribute a staff scan to a person.** `venue.scan` has `device_id` but no actor column, and `device_id` is NULL on the authenticated path. | `PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md:941-968` | **Medium** — an insider-fraud trail with a hole | §7.4 — `ADDITIVE SCHEMA CHANGE` |
| **14.4** | **Enum vs CHECK contradiction between two frozen specs**, on the exact column whose editability is the stated risk. | schema `:899` (enum) vs migration plan `:363, 496` (CHECK) | **Medium** | §3.5 / **OD-6** |
| **14.5** | **The C36 constitution still contains four pre-C36 bare-label role lists.** The Domain Architecture's object catalog, principal table, mermaid ER diagram and relationship catalog all still say `owner/manager/finance/marketing/door/promoter_manager` — the exact strings C36 was ratified to abolish. The §4 challenge resolution was applied to §7.1 prose and never propagated. | `SNATCH_IT_DOMAIN_ARCHITECTURE.md:156, 761, 1546, 2235` vs `:55` (A9), `:1963` (C36 resolution) | **Medium** — an implementer reading the object catalog would build the footgun C36 forbids | §11.7 D-1 … D-4 |
| **14.6** | **Read-path org→venue inheritance is described as non-existent while being granted.** §2.4 says inheritance lives *only* inside write RPCs and *"not by widening venue RLS to org roles"*; §9.9 grants `org_owner/admin` `A(venues of own org)` — a read-path inheritance. | `PHASE_2_RLS_PERMISSION_SPEC.md:147` vs `:760` | **Low** — a doc contradiction that would produce an inlined join in every policy | §6.2 / **RM-3** — name the helper |
| **14.7** | **Money-authority conflict on `set_org_payout_destination`.** Two frozen specs disagree on whether `org_finance` may change the payout destination — the exact SoD primitive DA §7.4 rule 1 exists to prevent. | `PHASE_2_RLS_PERMISSION_SPEC.md:1076` vs `SNATCH_IT_DOMAIN_ARCHITECTURE.md:1765` | **High**, but **not mine** | **OD-3** → `design/o1-o3-money-authority` |

---

## 15. What this spec does not decide

- **The door state machine.** O-4 authority rows only. States, transitions, idempotency semantics, and the
  interaction between manifest-open and in-flight transfers belong to `design/o5-door-lifecycle`.
- **Any money authority.** B1, B10 and the door-refund question (OD-3/OD-4/OD-5) are left explicitly open for
  `design/o1-o3-money-authority`. Where this spec shows a money cell, it is transcribed from the frozen
  corpus, not decided here.
- **The storage shape of the flagged-attribution decision** (G5). Authority only; venue dashboard Δ7 says the
  shape is a separate call.
- **Migration package numbering.** OD-10. This spec names packages, never numbers.
- **Privacy/PII column-level policy** beyond the audience-vs-money split of §4.2/H2/H3 — `design/privacy`
  owns the column taxonomy.

---

*End of `docs/architecture/PHASE_2_ROLE_MODEL_SPEC.md`. Design-only; no SQL, no migrations, no implementation
code. Delta spec — the frozen constitutions are unedited; §11 is the integration instruction set.*
