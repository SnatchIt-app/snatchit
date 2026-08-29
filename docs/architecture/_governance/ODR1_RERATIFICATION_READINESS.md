# `ODR-1` — Re-ratification Readiness

> ## RECOMPUTED 2026-08-28 AFTER THE `WRITER` OWNER RULING — **VERDICT UNCHANGED: NOT READY**
>
> The `WRITER` ruling and the `X-1`/`X-6` repairs are **writer-membership** changes. They touch no
> package number, no dependency edge, no `CREATE ROLE`, and no band statement — so **none of the six
> blockers below moves**, and I re-derived the structural facts rather than assuming that.
>
> Independently re-derived from the registry JSON at HEAD, this pass:
> ```
> PACKAGES     076 077 078 079 080 081 082 083 084 085 086 087 088 089 090 091
> COUNT 16 · BAND 076-091 · EDGES 45 · GAPS none · DUPLICATES none
> ALL FORWARD true · ACYCLIC yes (every edge source<target, so a cycle needs a<a)
> 092 in packages[] : FALSE  (it appears only as `package_if_gate_p` in a conditional)
> ```
> And the four items the ruling set specifically requires be checked, all still failing:
> ```
> crm_export_builder in registry        12 occurrences, incl. 2 x CREATE ROLE   REJECTED BY OR-1
> "CONTINGENT ON RLS MD-2 ... NOT taken"  still present                          STALE CONDITIONAL
> 16-package / 076-091 claims             12 sites in the registry alone          FALSIFIED BY OR-5
> COND-A owner_ruling_required: true      3 sites                                 FALSIFIED BY OR-4
> ```
> **No migration file `092` was created, and none should be** — `092` is a *design-registry* placement,
> not an implementation artifact, and authoring it is separately blocked by `OR-5`'s three
> pre-authoring blockers.

**2026-08-28.** Every number below is derived by a parser over the artifacts, not read from a stated
figure. **Nothing was ratified.**

> ## READY FOR OWNER RULING: **NO**
>
> ```
> PACKAGE BAND   : 076–091   (required: 076–092)
> PACKAGE COUNT  : 16        (required: 17)
> EDGE COUNT     : 45        (owed: +2 declaration-only, + at least 090→092)
> ```
>
> **`ODR-1` is a ratification of a WRITTEN registry** — the registry's own §6.5 says it *"is updated
> only by ratified amendment."* Signing it today would ratify **three things the owner has already
> settled the other way**:
>
> 1. a **16-package `076`–`091`** band, falsified by `OR-5`;
> 2. **no outbox and no drainer scheduled**, falsified by `OR-4`;
> 3. a **`CREATE ROLE crm_export_builder` in `076`** with thirteen grants and twelve policies —
>    **refused by `OR-1`/`O17` = B.**
>
> **The registry cannot be made ready by a ruling. It must be amended to carry the rulings, then
> re-put.**

## The check table

| # | check | required | **derived** | verdict |
|:--|---|---|---|:--|
| 1 | package count | 17 | **16** | **FAIL** |
| 2 | package enumeration | `076`…`092` | `076`…`091` — **`092` absent** | **FAIL** |
| 3 | start / end | `076` / **`092`** | `076` / `091` | **FAIL** |
| 4 | gaps | none | **none** in `076`–`091` | PASS *(terminus wrong — see 3)* |
| 5 | duplicates | none | **0** — 16 numbers, 16 distinct | **PASS** |
| 6 | edge count | ≥45 +2 owed +`092` | **45**, and the declared count agrees | PASS *as declared* / INCOMPLETE vs corpus |
| 7 | edge enumeration | full list | **45, enumerated below** | **PASS** |
| 8 | four-surface parity | identical | **all four enumerate the identical 45-edge set** | **PASS** |
| 9 | acyclic DAG | proven | **proven** — see below | **PASS** |
| 10 | every edge forward | 45/45 | **45/45 strictly forward, 0 backward** | **PASS** |
| 11 | every amendment represented | 7 | **7 blocks present** | PASS structurally / **content of #7 falsified** |
| 12 | `notify` at `092` | scheduled | **conditional only** (`COND-B`, `SPECIFIED_NOT_SCHEDULED`) | **FAIL** |
| 13 | outbox in `076`, drainer separate | both scheduled | **neither**; one scalar for two objects; drainer has **no number anywhere** | **FAIL** |
| 14 | no `crm_export_builder` | 0 | **12 in the registry**, 33 across the three DDL-authoritative docs | **FAIL** |
| 15 | no 16-package claim | 0 | **11 sites in the registry alone**, ~40 corpus-wide | **FAIL** |

## The enumerations, so the counts are checkable

**Packages (16):** `076 077 078 079 080 081 082 083 084 085 086 087 088 089 090 091`.
`092` occurs in the registry **only** as a conditional field and a `COND-B` row — in neither §2's table
nor the JSON `packages[]`.

**Edges (45), by target:**
`077`←076 (1) · `078`←077 (1) · `079`←077,078 (2) · `080`←077,078,079 (3) · `081`←078,080 (2) ·
`082`←077,078,081 (3) · `083`←078,079,081 (3) · `084`←079,081,083 (3) ·
`085`←077,078,079,081,082,083 (6) · `086`←079,080,081,083 (4) · `087`←077,081,085,086 (4) ·
`088`←078,079,081,085,086,087 (6) · `089`←085,088 (2) · `090`←078,082,085,087 (4) · `091`←077 (1).
**Total 45.**

> **The mermaid chain trap, and it is real.** The plan's DAG contains `P0 --> A076 --> B077 --> C078`
> — a three-edge chain, two of them package→package. **Parsed as a chain it yields 45 and parity
> holds; parsed naively as one arrow per line it yields 44 and manufactures a phantom mismatch
> against the JSON.** There is no such mismatch. (An earlier pass of mine reported exactly this
> phantom; it was my regex, not the document.)

**Acyclicity, proven without a cycle search.** All 45 edges satisfy `int(source) < int(target)`,
verified mechanically with zero exceptions. The edge relation is therefore a subrelation of the strict
total order `<` on the integers, which is irreflexive and transitive; a cycle would require `a < a`.
**Acyclicity is a corollary of check 10**, and ascending package number is simultaneously a valid
topological order.

**Four-surface parity — and the four are not what one might assume.** The corpus defines them as: the
plan's §2 mermaid · the plan's §3 rollout table · the registry §2.1 · the registry JSON `depends_on`.
All four are set-equal, verified four ways. **The schema spec is NOT one of the four** — it is a
fifth, partial, five-amendments-stale surface still stating *"Edge count 36 → 38"* and *"the count
stays 16"*. Parity is not broken by it, but **any reader treating it as the DAG of record reads a
38-edge, 16-package graph.**

## The seven blockers

> **Corrected 2026-08-29 — this heading said *"six"* while the section enumerated seven.** `B-7` was
> added 2026-08-28 and the heading was not recounted; `B-6` also sits **after** `B-7` in reading order.
> Enumerated at HEAD: `B-1` `B-2` `B-3` `B-4` `B-5` `B-7` `B-6` — **seven.** This is the
> count-without-enumeration drift the register warns about, in the document that carries the readiness
> verdict. Recounted, not carried.
>
> **`ODR-1` was NOT touched by the `OR-9` / `A7` pass (2026-08-29) beyond this heading correction.** All
> seven blockers stand exactly as written, `B-7` included: **`092`'s dependency set is derived nowhere,
> so the required final edge count remains NOT DERIVABLE and `47` is a floor, not an answer.**

**B-1 — `OR-5` is unrepresented, and the sentence `ODR-1` would sign is the one it falsifies.**
The registry states *"Count: 16 packages, 076–091 inclusive, no gaps, no duplicates"*. `092` is
required because the drainer's `SEAM-1` floor holds at `090` (`#32`'s notice is IN, so
`venue.promoter_link` stays in its read set) and `091` is a protected, writer-less shape that may not
absorb it. **11 registry sites + 9 plan sites + 6 schema-spec sites restate the old band**, including
one that self-describes its own falsification: *"COUNT UNCHANGED at 16 — conditionally."*

**B-2 — `OR-4` is unrepresented, and the drainer has no package anywhere in any DDL document.**
`076`'s scope row contains no outbox object, in prose or JSON. `COND-A` remains
`SPECIFIED_NOT_SCHEDULED` with `owner_ruling_required: true`, names the item **`"event outbox +
drainer"`** — two objects — against a **single scalar** `package_if_ratified: "076"`. Three sites
still assert *"no implementation spec schedules one"* / *"scheduled by nothing"*, now false. The
drainer's derived package is `092`; it appears in no DDL-authoritative document.

**B-3 — the refused `crm_export_builder` role survives in full, and this is the most serious one.**
`OR-1` states plainly: *"no `CREATE ROLE` in `076`; the thirteen grants … are not authored; ZERO
`_sel_svc_export` policies exist."* Yet the registry still carries `CREATE ROLE crm_export_builder
NOLOGIN` in `076`'s scope row **and** in the JSON, a `seam_rules.grants` map with
`role_created_in: "076"`, 6 packages, 13 grants, 12 relations and the twelve-policy half, and an
`owner_decision: "CONTINGENT ON RLS MD-2, recorded and NOT taken"` — **a contingency the owner has
since closed the other way.** The impact map already says it: *"`ODR-1` MUST NOT be signed against the
registry as it stands … Signing today ratifies a `CREATE ROLE` the owner has just refused."*

**B-4 — two declaration-only edges are owed and appear in no surface.** `078 → 086` is recorded and
explicitly *not applied* (§13.6 asserts *"`086` already declares `078`"* — **it does not**; `086`'s set
is `{079,080,081,083}` in all four surfaces). `077 → 090` is recorded nowhere in the three
DDL-authoritative documents. Both are strictly forward. `ODR-1`'s own brief proposes absorbing them in
the same signature (`45 → 47`); `092` adds at least `090 → 092` on top.

**B-5 — prose falsified by `OR-3` that a ratification would ratify.** The registry's *"Unaffected: …
promoter codes"* line and the JSON array element, plus the schema spec's *"promoter codes (no async at
all)"*. Note this contradicts the registry's own line **sixteen lines above**, which classifies
commission accrual as Async/outbox.

**B-7 — THE REQUIRED FINAL EDGE COUNT IS NOT DERIVABLE FROM THE CORPUS. (New, 2026-08-28.)**
The required band and count ARE derivable: the drainer and the `notify` plane land in the **same**
package `092` — both consequence maps reach it independently, and the reduced scope holds the
`SEAM-1` floor at `090` because `#32`'s notice is IN — so it is **one** new package: **`076`–`092`,
17 packages**. That much is settled.

**The edge count is not.** It is 45 today, plus the two declaration-only edges owed (`078 → 086`,
`077 → 090`), plus `092`'s in-edges — **and no document anywhere derives `092`'s dependency set.**
Under `OR-5`'s *reduced* scope four of the drainer's reads drop away, so the set cannot simply be
copied from the full platform's read list either. A grep for a derived edge set for `092` across
`docs/architecture/**` returns nothing.

**So a specific number must not be asserted.** `47` (45 + 2) is the floor, not the answer, and any
figure quoted for the post-`092` DAG today is manufactured. Deriving `092`'s edge set is a
prerequisite to `ODR-1`, and it is work no pass has done.

**B-6 — the schema spec's DAG section is five amendments stale.** Not one of the four ratified
surfaces, so parity holds — but it is the placement record `ODR-1` cites.

## The minimum sequence to readiness — all mechanical, none of it an owner decision

1. Execute the `O17` remediation: strip the role, the 13 grants, the 12 policies and the seventh
   amendment's appendix from the registry and the plan.
2. Schedule the outbox table in `076` as **`notify.outbox`** — `OR-5` collapses the conditional schema
   home — and **split `COND-A`'s single scalar into two objects**.
3. Add package **`092`** (`notify`, reduced: 7 tables, 16 RPCs, 2 edge functions, 2 cron) with the
   drainer, and re-derive its edge set (`090 → 092` at minimum) across all four surfaces.
4. Restate the band as **`076`–`092`, 17** in all 26 sites.
5. Declare `078 → 086` and `077 → 090`; refresh schema §13.6 to the current graph.
6. Re-run the four-surface parser and publish the new declared edge count.

**Note on sequencing that matters:** `OR-5`'s three pre-authoring blockers (`N1` email, `N2` escalation
authority, `N3` money-emitter map) gate **authoring** `092`, not **numbering** it. Numbering can
proceed; authoring cannot.

## NO OPTION BLOCK — NOT READY

Per the task's own instruction, no lettered owner-choice block is drafted, because the artifact is not
in a state that can be signed.
