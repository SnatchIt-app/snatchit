# `ODR-1` RE-RATIFICATION — EIGHTH AMENDMENT (DRAFT for owner signature)

**Status: DRAFT — NOTHING HERE IS RATIFIED.** Prepared 2026-08-29 by AGENT 7 (read-only) against
`snatchit-consol` @ `92f529b`. Every count below is re-derived at HEAD by enumeration, not carried from
a prior report. This document is the complete amendment text the owner would sign; per registry §6.5
(*"this registry is updated only by ratified amendment"*), **numbering `092` is itself the owner's
ratification act** — the sixth limb of `B-1`/`B-2` that no mechanical pass may take.

Two sections are deliberately incomplete and say so where they stand:
- **§3 (`B-3`)** incorporates the `crm_export_builder` revert unit **by reference** — its site
  enumeration (~45 sites, 6 documents) is another agent's deliverable and is not restated here.
- **§6 (`B-7`)** carries **labeled unresolved slots** (⛔ `UNRESOLVED-PENDING`) for `092`'s
  non-derivable in-edges and `notify.emit_event`'s home. **No value is guessed for any of them.**

**NO GLOBAL EDGE COUNT IS ASSERTED.** The post-amendment declared edge count is
**`47 + |in(092)|` where `in(092) ⊇ {077, 078, 079, 082, 085, 090}`** — the final number is published
by the four-surface parser after the amendment lands and `092`'s in-edge derivation completes. `47` is
the verified pre-`092` set (enumerated in §5); `53` is a floor, not an answer.

---

## 0. PREAMBLE — what is being ratified, and under which rulings

This amendment re-puts `ODR-1`. The prior `ODR-1` signature was falsified by four owner rulings made
2026-08-28 (`ODR1_RERATIFICATION_READINESS.md`: signing the registry as it stood would have ratified
three things the owner had already settled the other way). This amendment carries those rulings into
the three DDL-authoritative documents so that the signature ratifies what the owner has ruled:

| Ruling | What it settled | What this amendment does with it |
|---|---|---|
| **`OR-1`** (`O17`/`MD-2`/`ODR-23`) | The CRM export function stays `postgres`-owned; **`crm_export_builder` is NOT created**; the Layer-0 dedicated-role design is REJECTED for Phase 2. `X-6` stands, replaced by the structural/catalog assurance plan. | **§3** — the revert unit (role, 13 grants, 12 policies, the seventh amendment's `C115` appendix) is stripped, by reference to the enumerating agent's map. |
| **`OR-3`** (`G-25` four events) | `#31 AttributionRecorded` and `#32 PromoterCommissionAccrued` are **KEEP**; `#2`/`#5` REMOVE. Two promoter events are carrier-relevant; the *"promoter codes unaffected / no async at all"* prose is falsified. | **§4** — `B-5` recorded closed, with the two residues found at HEAD enumerated for cleanup. **Guard (§2):** `OR-3` changes the carrier status of the **notice**, never the transactionality of the **money** (`D7`). |
| **`OR-4`** (`ODR-2`/`O7`/`C51`/`COND-A`) — corpus option **[A] BUILD** | One transactional outbox table, written in the SAME transaction as the authoritative state change; one drainer; idempotent consumers; existing cron. | **§2** — the outbox is **scheduled**: table `notify.outbox` in **`076`**; drainer `notify.drain_outbox` in **`092`**; `COND-A` retired and split into its two objects. |
| **`OR-5`** (`ODR-3`/`C7`/`COND-B`/`MD-10`) — corpus option **[C] GATE P, REDUCED** | The `notify` plane is built at Gate P with the reduced scope (21 mandatory + 2 non-mandatory *(pre-N3/OR-15 recitation — the ruled set is 29; F-P2-5)* types; announcements, `notify.schedule`, SMS, campaign machinery explicitly NOT built). Three pre-authoring blockers `N1`/`N2`/`N3`. | **§6** — package **`092`** is numbered and its row drafted; `COND-B` retired. **`N1`/`N2`/`N3` gate AUTHORING, not numbering** (§7). |
| **The band** (consequence of `OR-4` + `OR-5`, derived independently by `ODR-2` §4 and `ODR-3` §5) | The drainer's SEAM-1 floor holds at `090` (`#32`'s notice is IN, so `venue.promoter_link` stays in its read set); `091` is a protected writer-less shape (rule §6.7). Both consequence maps reach **one** new package. | **§1** — the band is restated as **`076`–`092`, 17 packages**, at every site (site-by-site map below). This is the structural change the corpus itself calls *"requiring re-ratification."* |

The signature additionally ratifies the seven prior pending amendments **as amended here** — the
seventh's `C115`/`crm_export_builder` appendix does not survive (§3); everything else in them stands
as written.

---

## 1. `B-1` — THE BAND: `076`–`092`, 17 packages — site-by-site edit map

**Base:** the sprint record's site map (agent E), **re-verified line-by-line at HEAD `92f529b`** — every
site below was grepped this pass; line anchors are HEAD line numbers and drift with edits above them.
The readiness doc's tally ("11 registry + 9 plan + 6 schema") reconciles with this map.

**Convention adopted for historical text (owner ratifies it as part of this amendment):**
- **Restate** — sites stating the band/count as a *present* fact are rewritten to `076`–`092` / 17.
- **Annotate** — the seven amendment banners and §4's decode records are **history**: each was true at
  its writing. They receive a one-line dated annotation pointing at this amendment, and are not
  rewritten. (This is the annotate-vs-delete convention `B-3`'s residue #2 poses; it is settled here
  for band sites and applies identically to the revert unit's HISTORY class in §3.)

### 1.1 Registry — `PHASE_2_PACKAGE_REGISTRY.md` (11 prose sites + JSON)

| # | Site (HEAD anchor) | Today | Edit |
|---|---|---|---|
| R1 | First-amendment banner, ~L35–42: *"COUNT UNCHANGED at 16 — conditionally … If `notify` is ruled Gate P, the count becomes 17 (`076`–`092`)"* | conditional | **Restate** — the condition fired: `OR-5` ruled Gate P. Annotate the banner; the count IS 17. This site also carries strike #1 of §2.3. |
| R2 | Third-amendment banner ~L91 *"the count stays 16 (`076`–`091`)"* | history | **Annotate** |
| R3 | Fourth-amendment banner ~L130 (same phrase) | history | **Annotate** |
| R4 | Fifth-amendment banner ~L211 (same phrase) | history | **Annotate** |
| R5 | Sixth-amendment banner ~L224–225 (*"the count stays 16"*) | history | **Annotate** |
| R6 | Seventh-amendment banner ~L234–235 (*"the band stays `076`–`091`, sixteen, each number used once; the count stays 16"*) | history | **Annotate** — and its `C115` appendix is stripped per §3, which the annotation must say. |
| R7 | §1 band table ~L367: *"`076`–`091` … Sixteen packages"* | present-fact | **Restate:** `076`–`092` · Seventeen packages |
| R8 | §2 heading ~L383: *"Phase-2 package registry `076`–`091`"* | present-fact | **Restate:** `076`–`092` |
| R9 | §2 count line ~L409: *"Count: 16 packages, `076`–`091` inclusive, no gaps, no duplicates — subject to §7 COND-B"* | present-fact | **Restate:** *"Count: 17 packages, `076`–`092` inclusive, no gaps, no duplicates."* The COND-B subjection clause is deleted (COND-B is retired, §6). |
| R10 | §4 scale table ~L683: CANONICAL row *"`076`–`091` · everywhere, after 2026-08-27"* | decode record | **Restate the CANONICAL row** to `076`–`092` with this amendment's date; the S0/S1/S2 rows and §4.1's defect records ("Both now read `076`–`091`", ~L697) are history — **Annotate** only. |
| R11 | §6 rules ~L717–725: rule 2 *"Phase-2 packages occupy `076`–`091`"*; rule 3 *"new security hotfixes go above `091`"* | present-fact | **Restate:** occupy `076`–`092`; hotfixes above `092`. |
| R12 | §7 ~L752: heading *"NOT counted in the 16"* + the COND-A / COND-B rows | present-fact | **Rewrite §7**: COND-A and COND-B leave the conditionals table (ruled — §2 and §6 record where each object landed); **COND-C remains the sole conditional** and the heading becomes *"…NOT counted in the 17."* |
| R13 | §2 table | — | **Add the `092` row** (content: §6.2). |
| R14 | §2.1 table + edge-rationale table | — | **Add seq 17 / `092`** with the six derived in-edges and the labeled unresolved slots (§6.3); add a rationale row per derived edge. |
| R15 | ~L464 (`†077 → 078` rationale: *"the canonical band stays `076`–`091`"*) and ~L472 (MP-1 note: *"the `076`–`091` band is untouched"*) | history (each true at its writing) | **Annotate** |

**Registry JSON (§3) — five edits:**

| # | Field | Edit |
|---|---|---|
| J1 | `phase2_range` | `{ "first": "076", "last": "092", "count": 17 }` |
| J2 | `packages[]` | **Gains the `092` row** — draft object in §6.4, with ⛔ slots carried as explicit `"UNRESOLVED-PENDING"` markers, never as guessed values. |
| J3 | `conditionals[]` | **COND-A**: replaced by the two-object scheduled record (§2.2). **COND-B**: retired — replaced by a resolution stub pointing at `OR-5` and the `092` row. **COND-C**: unchanged. |
| J4 | `amendment_count` / `amendment_summary` | `7 → 8`; summary gains the eighth entry (band `076`–`092`/17 · outbox split `076`+`092` · `B-3` revert per `OR-1` · `092` numbered under `OR-5` REDUCED · `declared_edge_count` republished by parser after `in(092)` derivation). |
| J5 | `declared_edge_count` + `edge_set_parity_verified` | **Found at HEAD (this pass):** `declared_edge_count` is `47` but the parity string still attests *"all four surfaces enumerate the same **45** edges"* — a `B-4` residue. The string is refreshed **by the parser run** (§7 step), not by hand, and after `092`'s in-edges land the count field is republished the same way. Until then the count field must not be hand-set to any post-`092` number. |

### 1.2 Migration plan — `PHASE_2_SUPABASE_MIGRATION_PLAN.md` (11 sites)

| # | Site (HEAD anchor) | Edit |
|---|---|---|
| P1 | §0.5 ~L234 *"all MVP packages (`076`–`091`)"* | **Restate** `076`–`092` |
| P2 | §1 heading ~L273 *"Phase → package map (`076`–`091`)"* | **Restate** — and §1's table gains a row for `092` (Phase: Gate P notify, REDUCED — §6.2's one-line scope). |
| P3 | §1 K row ~L292 *"`notify` is no longer simply deferred — it is a marked conditional, §8 COND-B"* | **Restate:** `notify` is **ruled** Gate P REDUCED (`OR-5`) and scheduled as `092`. |
| P4 | §2 mermaid | **Add node `N092`** and its in-edges — the six derived edges as one arrow per line (the chain form is legal but the readiness doc's "mermaid chain trap" is real; single arrows keep the surface parser-trivial), plus **NO arrows for the ⛔ slots** until derived. |
| P5 | §2 edge note ~L395–396 *"Still 16 packages, still `076`–`091` …"* | **Annotate** (history of that pass) + append the present-fact sentence: 17 packages, `076`–`092`. |
| P6 | §3 rollout table + ~L442 *"NO for all 16 / YES for all 16"* | **Add seq 17 row `092`** (Depends on: the six derived + ⛔ slots; Additive Y; Mkt change N; flag-gated per `OR-5`); restate both "all 16" phrases as "all 17". |
| P7 | §5 heading ~L464 *"(076–091)"* + ~L471 *"these sixteen packages"* | **Restate** (§5 remains the pre-delta record; its heading is a present-fact band claim). |
| P8 | §6 ~L1123 *"every one of `076`–`091`"* | **Restate** |
| P9 | §8 heading ~L1150 *"THE FINAL PACKAGE TABLE — `076`–`091`"* | **Restate** `076`–`092` |
| P10 | §8 `076` row (~L1259–1276) | **Tables row edit (§2.2):** gains `notify.outbox`; the parenthetical *"(COND-A: the event outbox lands here if ratified)"* becomes the scheduled fact. Also carries §3's strip of the `C115` material in this row (the role/GRANT prose — see §3's DELETE class). |
| P11 | §8 gains the **`092` row** (full draft: §6.2) and §8's **COND-A / COND-B blocks** (~L1530–1566) convert per §2.2 / §6.1. | — |

### 1.3 Schema spec — `PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md` (6 sites — filed to the schema-spec owner)

The schema spec is **not** one of the four parity surfaces; these are filed, not silently applied, per
its ownership (`OR-6` subject-matter ownership).

| # | Site (HEAD anchor) | Edit |
|---|---|---|
| S1 | ~L227 *"`076`–`091` (canonical map: …)"* | **Restate** `076`–`092` |
| S2 | ~L1777 *"the whole `076`–`091` chain replays green"* | **Restate** |
| S3 | ~L3988 *"inside the `076`–`091` band"* | **Restate** |
| S4 | §13.3 (~L4093–4162) | **Convert** from *"SPECIFIED, NOT SCHEDULED"* to the scheduled record (§2.2): strike #4 of the scheduled-by-nothing set; the header comment *"schema home depends on the notify ruling"* resolves to **`notify.outbox`**; **and the un-struck `B-5` site ~L4157** *"promoter codes (no async at all)"* is struck (§4.2 residue b). |
| S5 | §13.4 (~L4164–4201) | **Convert** to a ruling record: `OR-5` = Gate P REDUCED; the Gate-P consequence row's *"makes the registry 17 packages"* becomes the present fact; the Gate-L row is retained as the rejected branch, marked so. |
| S6 | §13.6 (~L4266–4331) | **Full refresh — the `B-6` deliverable. New content drafted in §5 below.** |

*(~L1266 quotes registry §2's old count inside an argument — a quotation of then-true text: **Annotate**.)*

---

## 2. `B-2` — THE OUTBOX: `notify.outbox` in `076`, drainer in `092` (`OR-4` applied)

### 2.1 The two-object split (the defect being repaired)

`COND-A`'s label — **"event outbox + drainer"** — named **two objects** against a **single scalar**
`package_if_ratified: "076"`, giving any machine reader one number for two objects (`ODR-2` §4 calls
this *"the more dangerous kind"* of latent defect). The split, both placements already derived by the
consequence maps and re-verified here:

| Object | Package | Why (derived, not chosen) |
|---|:--:|---|
| **`notify.outbox`** (the table — schema home per `OR-5` Gate P; the `kernel.event_outbox` alternative dies with COND-B) | **`076`** | Zero FK dependencies (`aggregate_kind`/`aggregate_id` polymorphic by design) — born with the schemas; **no producer package gains a dependency edge**. Column list, the two UNIQUEs, and the partial index: schema §13.3, adopted as drafted. |
| **`notify.drain_outbox`** (the drainer) | **`092`** | SEAM-1 `max()` over its reach **includes `venue.promoter_link` (`090`)** — the floor holds because `#32`'s notice is IN under `OR-5` (`ODR-3` §5, falsification 1) — and `091` is a protected writer-less shape (rule §6.7; `ODR-3` §5, falsification 2). Before this amendment the drainer had **no package number in any DDL document.** |

### 2.2 Edits

1. **Registry §2 `076` row + JSON `076` `scope`** — gain `notify.outbox` (table) with a pointer to
   schema §13.3's physical definition. *(Note: after §3's revert, the `076` scope row no longer names
   `CREATE ROLE crm_export_builder` — the two edits touch the same cell and must land together.)*
2. **Registry JSON `conditionals[]`** — `COND-A`'s single object is **replaced by two scheduled
   objects** (no longer conditionals; recorded as a resolution block or moved into the package rows):
   `{ "object": "notify.outbox", "kind": "table", "package": "076", "ruled_by": "OR-4 [A]" }` and
   `{ "object": "notify.drain_outbox", "kind": "drainer RPC", "package": "092", "ruled_by": "OR-4 [A] + OR-5 [C]", "seam1_floor": "090 (venue.promoter_link; #32 IN)" }`.
3. **Plan §8 `076` Tables row** — *"none. (COND-A: …)"* becomes *"`notify.outbox` (schema §13.3;
   scheduled by `OR-4`)"*; plan §8's COND-A block converts from conditional to the scheduled record.
4. **Schema §13.3 conversion** (S4 above) — header and body converted to scheduled; schema-home
   comment resolved to `notify.outbox`.

### 2.3 The four "scheduled-by-nothing" strikes

All four assert what `OR-4` + this amendment make false, and each is struck (replaced by the
scheduled fact) at its site:

| # | Site | The now-false text |
|---|---|---|
| 1 | Registry, first-amendment banner ~L38 | *"no implementation spec schedules one"* |
| 2 | Registry §7 COND-A row ~L761 | *"**No implementation spec schedules one.**"* |
| 3 | Plan §8 COND-A ~L1534 | *"**No implementation spec schedules one.**"* |
| 4 | Schema §13.3 ~L4101–4104 | *"No Phase-2 implementation spec schedules one … the one piece of infrastructure the constitution promises Phase 2 will build is the one piece nothing schedules."* |

*(B-2's readiness text also counts the drainer's "no number anywhere" — closed by §2.1 row 2.)*

### 2.4 Two guards carried INTO the schedule (normative clauses of this amendment)

- **`ODR-2` §6's money guard — `#31` money stays same-transaction.** Ratified `D7` pins the
  attribution row in the transaction that marks the order paid, and the commission line is written
  inside `close_settlement` via the SEAM-2 hook. **`OR-3` changed the carrier status of the notice,
  not the transactionality of the money. No correction under this amendment may move promoter money
  onto the outbox** — a correction that does contradicts `D7` and is the defect.
- **`ODR-3` §3.2's expansion-cursor consequence — carried onto `drain_outbox` chunking.** Dropping
  `notify.schedule` removes the expansion cursor, but four IN MANDATORY types (`event_cancelled`,
  `event_time_changed`, `event_venue_changed`, `event_postponed`) use custody-expansion recipient
  derivation across every active atom of a session, and `drain_outbox` is specified as one set-based
  INSERT…SELECT **with no bound** — a 50 000-holder cancellation is one unbounded transaction holding
  one long lock. **The reduced build must carry the cursor on `notify.outbox`, or `drain_outbox` must
  chunk internally.** Engineering, not an owner decision — written into the `092` row (§6.2) so it
  cannot be lost with the dropped table.

---

## 3. `B-3` — THE `crm_export_builder` REVERT UNIT (`OR-1` applied) — INCORPORATED BY REFERENCE

`OR-1` (verbatim consequence set): *"no `CREATE ROLE` in `076`; the thirteen grants across
`076`/`077`/`078`/`079`/`082`/`087` are not authored; ZERO `_sel_svc_export` policies exist … `C115`
reverts as one unit."* The full site enumeration (~45 sites across 6 documents, per the sprint record)
is **another agent's deliverable and is incorporated here by reference as Annex A**. This amendment
authorizes the revert as one unit; the classes and the two residues it must resolve are fixed here so
the annex slots into a settled frame:

| Class | Placeholder — what Annex A enumerates |
|---|---|
| **DELETE** | Sites that exist only to state the role/grants/policies and carry nothing else: the registry JSON `seam_rules.grants.crm_export_builder` object; the `076` scope-row `CREATE ROLE` clause (prose + JSON); plan §8 `076`'s `C115` enumeration rows and `T-SCHEMA-GRANT-01/-02/-03`; the per-package `GRANT … TO crm_export_builder` lines (`077`/`078`/`079`/`082`/`087`); the `_sel_svc_export` policy statements. *(Annex A: exact list.)* |
| **REWRITE** | Sites where the role is one clause of a larger, surviving statement: package Grants rows, RLS-row references, the SEAM-4 exposition (the **rule** SEAM-4 survives — its motivating example does not). *(Annex A: exact list + replacement text per site.)* |
| **HISTORY** | The seventh amendment's `R2B`-9 narrative and its `C115` appendix; the sprint/defect records that describe the defect and its repair. Treated under §1's annotate convention: annotated as reverted by `OR-1`, not silently deleted. *(Annex A: exact list.)* |
| **OWNER-DEPENDENT** | Sites whose disposition turns on a call this amendment's signature makes rather than the enumeration: see the two residues. *(Annex A: exact list.)* |

**The two named residues (per the sprint record / Q-5), both settled BY this signature:**
1. **The `T-SCHEMA-GRANT` test disposition disjunction** — `OR-1` says the tests are *"retargeted or
   retired"*; which of the two, per test, is a disposition the annex proposes and this signature
   adopts. (The replacement assurance surface is `X6_POSTGRES_OWNED_ASSURANCE_PLAN.md`'s
   structural/catalog assertions — a retarget must point there, not at the dead role.)
2. **The annotate-vs-delete convention** — settled in §1.0 above (restate present-fact sites; annotate
   history), applied by the annex uniformly.

---

## 4. `B-4` / `B-5` — ALREADY APPLIED — recorded as CLOSED

Closed mechanically in the 2026-08-29 parallel-convergence sprint; commits **`ca94e05`**
(*"sprint C2 — package/registry mechanical convergence (B-4, B-5, C112 move, R-35 attachments,
R-7a)"*) and **`762fd63`** (*"sprint C4/C5 — owner queue consolidated, ODR-1/register/reports
re-derived"* — records the closures and corrects the readiness doc's own false *"recorded nowhere"*
clause about `077 → 090`). Re-verified independently at HEAD `92f529b` by this pass:

### 4.1 `B-4` — the two owed declaration-only edges: **APPLIED on all four surfaces**

`078 → 086` (the `door_session` FKs → `event_session`/`venue`, both `078`; was recorded-not-declared)
and `077 → 090` (recorded in plan §8 `090`'s own Dependencies cell; declared nowhere) are present at
HEAD in: plan §2 mermaid (`C078 --> H086`, `B077 --> D090`) · plan §3 rows 11/15 · registry §2.1 rows
11/15 · registry JSON `depends_on` (`086`: includes `"078"`; `090`: includes `"077"`).
`declared_edge_count` 45 → **47**; the 47 verified by enumeration in §5. **One residue found at HEAD
(this pass): the JSON `edge_set_parity_verified` string still attests "the same 45 edges"** — cleared
by the parser run in §7's sequence (J5 above).

### 4.2 `B-5` — the five promoter "unaffected / no-async" strikes per `OR-3`: **APPLIED, two residues**

Struck at: registry §7 prose (annotation) · registry JSON `unaffected[]` (element removed +
`unaffected_note`) · plan §8 COND-A (annotation) · plus the `ODR-2` §6 sites. Residues found at HEAD
(this pass), folded into §1/§2's edit map:
- **(a)** Registry §7 ~L776–777: the strike **annotation** is present, but the enumeration itself
  still reads *"… demographics, **promoter codes**, and money authority"* — the phrase survives its
  own strike marker, leaving the sentence self-contradictory. Under §1.0's convention a falsified
  present-fact enumeration is **restated** (phrase removed, annotation kept).
- **(b)** Schema §13.3 ~L4157: *"promoter codes (no async at all)"* — **entirely un-struck** (`ODR-2`
  §6 row 3 calls it *"the sharpest error in the corpus on this point"*). Filed to the schema-spec
  owner with S4 (§1.3).

---

## 5. `B-6` — THE §13.6 REFRESH — replacement content, drafted from the CURRENT 47-edge declared set

**Verification, this pass:** all four surfaces at HEAD (plan §2 mermaid · plan §3 rollout · registry
§2.1 · registry JSON `depends_on`) enumerate the **identical 47-edge set** below. Count follows
enumeration: per-target in-degrees `1+1+2+3+2+3+3+3+6+5+4+6+2+5+1 = 47`. ✔
(The mermaid contains the `P0 --> A076 --> B077 --> C078` chain; parsed as a chain it yields 47 —
the readiness doc's "chain trap" note stands.)

> ### REPLACEMENT TEXT for schema spec §13.6 (filed to the schema-spec owner as part of this amendment)
>
> **§13.6 The declared dependency graph — current, post-eighth-amendment.**
>
> The graph below supersedes this section's prior delta-only table, whose framing (*"Edge count
> 36 → 38"*, *"the count stays 16"*) was five amendments stale — the amendments since are recorded in
> `PHASE_2_PACKAGE_REGISTRY.md`'s banners and this section no longer re-narrates them. This section is
> **not** one of the four parity surfaces (plan §2 mermaid · plan §3 · registry §2.1 · registry JSON);
> it is the placement record, and it now states the same set they do.
>
> **Band: `076`–`092`, 17 packages** (eighth amendment / `ODR-1` re-ratification; `092` per `OR-5`
> Gate P REDUCED). **Declared edges among `076`–`091`: 47**, enumerated by target:
>
> | Target | Depends on (declared) | In-degree |
> |---|---|:--:|
> | `077` | `076` | 1 |
> | `078` | `077` | 1 |
> | `079` | `077`, `078` | 2 |
> | `080` | `077`, `078`, `079` | 3 |
> | `081` | `078`, `080` | 2 |
> | `082` | `077`, `078`, `081` | 3 |
> | `083` | `078`, `079`, `081` | 3 |
> | `084` | `079`, `081`, `083` | 3 |
> | `085` | `077`, `078`, `079`, `081`, `082`, `083` | 6 |
> | `086` | `078`, `079`, `080`, `081`, `083` | 5 |
> | `087` | `077`, `081`, `085`, `086` | 4 |
> | `088` | `078`, `079`, `081`, `085`, `086`, `087` | 6 |
> | `089` | `085`, `088` | 2 |
> | `090` | `077`, `078`, `082`, `085`, `087` | 5 |
> | `091` | `077` | 1 |
> | **`092`** | `077`, `078`, `079`, `082`, `085`, `090` **+ ⛔ unresolved slots (see the registry's `092` row)** | ≥ 6 |
>
> **Total: `47 + |in(092)|`, where `in(092) ⊇ {077, 078, 079, 082, 085, 090}`. No final figure is
> stated here; the four-surface parser publishes it once `092`'s in-edge derivation completes.**
> Every declared edge strictly increases the package number, so acyclicity is a corollary and
> ascending number is a valid topological order.
>
> **The eight SEAM-2 hooks and their declared stub → replacement edges** (third acceptance property:
> every pair must be a DECLARED edge — verified, all eight present in all four surfaces):
> `venue.append_door_manifest_delta` `083 → 086` · `venue.on_payout_settled` `085 → 087` ·
> `market.on_atom_voided` `085 → 088` · `venue.resolve_order_attribution` `085 → 090` ·
> `market.on_door_freeze_engaged` + `market.door_freeze_drain_preview` `086 → 088` (×2) ·
> `kernel.settlement_royalty_lines` `087 → 088` · `kernel.settlement_commission_lines` `087 → 090`.
> The binding hook table (signatures frozen per SEAM-2a) is registry JSON `seam_rules.hooks`.
>
> Prior §13.6 content (`DAG-1`…`DAG-5`, the door_session correction note) is **history** — retained
> below this table under a dated "record of amendments" rubric, not restated as present fact.

*(The two crisp `B-6` corrections — the false "`086` already declares `078`" sentence and the stale
"SEAM-2 is used exactly three times" — were applied in the sprint and are re-verified standing at
HEAD; this refresh is the deferred third limb.)*

---

## 6. `B-7` — PACKAGE `092` — the row this signature numbers

### 6.1 What `092` is

The `OR-5` Gate-P REDUCED `notify` plane plus the `OR-4` drainer. Both consequence maps
(`ODR-2` §4, `ODR-3` §5) reach `092` independently; the two-package split was considered and rejected
(`ODR-3` §5). `COND-B` retires into this row.

**The 7-vs-6 table drafting inconsistency — flagged, and resolved by transcription discipline:**
`ODR-3` §3's reduced-scope table and the readiness doc's minimum-sequence step 3 both say **"7
tables"** — that seven is the reduced count of `notify.*` tables **including `notify.outbox`**, which
this amendment schedules in **`076`** (§2). A `092` row transcribed as "7 tables" would
double-schedule the outbox. **`092`'s own Tables row carries SIX.** Both statements are correct in
their own scope; the row below is the binding one.

### 6.2 The `092` row (registry §2 / plan §8 form) — DRAFT

| Field | Value |
|---|---|
| **New** | `092` *(no `old` — first number above the original band)* |
| **Name** | `092_notify_gate_p_reduced` *(draft name; final at authoring)* |
| **Phase** | Gate P — notify plane, REDUCED (`OR-5` `[C]`) |
| **Tables (6)** | `notify.notification` · `notify.notification_type` · `notify.delivery` · `notify.preference` · `notify.template` · `notify.identity_channel_state`. **NOT here:** `notify.outbox` (→ `076`, §2); `notify.schedule` and `notify.announcement` (dropped by `OR-5` — `schedule`'s CHECK enumerates exactly the three OUT types; both explicitly NOT built). Includes the mandatory-class DDL — the composite `FOREIGN KEY (type_key, delivery_class)` + `CHECK (delivery_class <> 'mandatory')` on `notify.preference` (`ODR-3` §4: protects 21 of 23 types *(pre-N3/OR-15 recitation — the ruled set is 29; F-P2-5)*, hardest control to retrofit). |
| **Functions** | `notify.drain_outbox` (the `OR-4` drainer — see the chunking clause) **+ the reduced RPC set: 16 per `ODR-3` §3 (23 − the six announcement RPCs − `sweep_scheduled`), minus adjustments** — the 16 is a scope count, not yet a name-by-name row; the authoring pass transcribes it from the notify spec's registry against `OR-5`'s IN set. **⛔ `notify.emit_event` is NOT placed here and NOT counted here — see 6.3.** |
| **Edge functions (2)** | `notify-dispatch` (cron-invoked, `verify_jwt: true` + constant-time bearer) · `notify-receipts` (`ODR-3`: *"NOT droppable — the reduction makes it MORE necessary"*) — plus the two shared modules `_shared/notify-auth.ts`, `_shared/email.ts` (not functions). |
| **Cron (2)** | `notify-dispatch` `* * * * *` · `notify-receipts` `*/15 * * * *`. (The drainer rides the **existing** 2-minute heartbeat per `OR-4` — not a new entry.) |
| **Normative note (from §2.4)** | `drain_outbox` must carry the expansion cursor on `notify.outbox` **or chunk internally** — the four custody-expansion MANDATORY types make the unbounded set-based form a one-transaction fan-out over every active atom of a session. |
| **Dependencies** | See 6.3. |
| **Rollback posture** | *(draft, authoring-gated)* CLEAN-WHILE-EMPTY; `notify.delivery`/`notify.notification` become forward-fix once they hold real delivery history. |
| **Authoring gate** | **⛔ NOT AUTHORABLE** while any of `N1`/`N2`/`N3` or the `R1`–`R5` choice is open (§7). Numbering ≠ authoring. *(Also on file for authoring, not numbering: the unseeded `notify.delivery_lease_interval` config read — sprint filing.)* |

### 6.3 `depends_on` — six derived, three labeled slots. **NOTHING IS GUESSED.**

**Derived (six), ratified by this signature:** `{ 077, 078, 079, 082, 085, 090 } → 092`
*(the sprint's B-7 sharpening, re-checked for plausibility this pass: identity/prefs (`077`), catalog
+ type seeds (`078`), tickets (`079`), orders (`082`), money events (`085`), `promoter_link` (`090`)
— the full SEAM-1 derivation is the deriving agent's artifact and is adopted by reference.)*

**⛔ UNRESOLVED-PENDING (labeled slots — another agent derives; a slot is filled only by that
derivation, never by this amendment):**

| Slot | What blocks it |
|---|---|
| **`076 → 092`** | The declaration-convention call: the corpus does not declare transitive edges (`085` does not declare `076` either), and `092` reaches `076` transitively through every derived in-edge. Whether the outbox-table read (`notify.outbox`, `076`) forces a **direct** declaration is a convention question, pending. |
| **`080 → 092`** | Pending **`CONFLICT-4`** (as referenced by the sprint record and Q-5; not characterized here). |
| **`notify.emit_event` placement** | Its own SEAM-1 says `076`; **19 call sites across six packages (`079` `083` `085` `086` `088` `090`) + two edge functions forbid `092`**; no document places it. Also pending: the `R1`–`R5` emit-semantics choice (`ODR-2` §8 — non-raising emit silently breaks the Wallet invariant; five options stated, none chosen) and `N3`'s re-keying (three of the fifteen facts have no `event_key`; DA §6.1 must number and key `U1`/`U2`/`U3` **before `076` can be authored**). Until placed, `emit_event` appears in **no** package row. |

**Consequently: the post-`092` edge count is `47 + |in(092)|`, `in(092) ⊇ {the six}`. The floor is
53. A floor, not an answer — no document may quote a final figure until the parser publishes it.**

---

## 7. SIGNATURE BLOCK

**By signing, the owner ratifies — exactly this list, nothing by implication:**

1. **The band: `076`–`092`, seventeen packages, no gaps, no duplicates** — restated at every §1 site
   per the §1.0 convention (restate present-fact; annotate history). **The act of numbering `092` is
   this signature** (registry §6.5) — it was deliberately taken by no mechanical pass.
2. **The seven prior pending amendments, as amended here** — the seventh's `C115`/`crm_export_builder`
   appendix stripped per item 3; all else standing as written.
3. **The `B-3` revert unit as one unit** (`OR-1` applied): role, thirteen grants, twelve policies,
   appendix — per Annex A's enumeration (incorporated by reference), under the DELETE / REWRITE /
   HISTORY / OWNER-DEPENDENT classes, with the two residues resolved as §3 states (test disposition
   per Annex A's proposal; annotate-vs-delete per §1.0).
4. **The outbox schedule** (`OR-4` applied): `notify.outbox` in `076`; `notify.drain_outbox` in
   `092`; `COND-A` retired and split into those two objects; the four scheduled-by-nothing strikes;
   **and the two carried guards** — `#31`/`D7` money stays same-transaction, and the expansion-cursor
   /chunking obligation on `drain_outbox`.
5. **The `092` row as drafted in §6** (`OR-5` applied): six tables + drainer + the reduced-16 RPC
   scope + 2 edge functions + 2 cron; `COND-B` retired; the six derived in-edges
   `{077, 078, 079, 082, 085, 090} → 092`; **the three ⛔ slots ratified AS unresolved** — filling
   any of them is a subsequent mechanical derivation (or the ruling it names), not a new owner act,
   unless the deriving pass escalates it.
6. **The `B-4`/`B-5` closures** as applied in `ca94e05`/`762fd63`, including cleanup of the three
   residues this pass found at HEAD (§4.1 J5; §4.2 a/b).
7. **The §13.6 refresh** as drafted in §5, filed to the schema-spec owner.
8. **Edge accounting:** the 47-edge declared set is ratified as the current four-surface graph
   (verified by enumeration, §5). **No post-`092` edge count is ratified, asserted, or implied** —
   the final count is `47 + |in(092)|` and is published by the four-surface parser run that follows
   the amendment landing and the `in(092)` derivation. The parser run also refreshes the JSON parity
   attestation (§1.1 J5).
9. **Recording:** this ruling is entered in `_governance/PHASE_2_RATIFICATION_RECORD.md` as a
   **RATIFIED — OWNER** row under the next free `OR` id (`OR-11` at HEAD), and the registry's
   `amendment_status` for amendments one through eight resolves to ratified.

**And the owner explicitly acknowledges:**

> **`N1` (transactional email — provider selection is an owner decision), `N2` (Control 5's
> escalation authority — `kernel.hold_payout` is barred to every principal Control 5 offers it to),
> `N3` (the money-emitter ↔ catalog map — eight emitters, four orphans, not ready), and the
> `R1`–`R5` emit-semantics choice GATE THE AUTHORING OF `092`, NOT ITS NUMBERING.** This signature
> numbers `092` and schedules its objects; **no SQL for `092` may be authored while any of the four
> is open**, and nothing in this amendment weakens `OR-5`'s pre-authoring blockers or the ratified
> deep-link prohibition.

| | |
|---|---|
| **Owner** | ________________________________ |
| **Date** | ____________ |
| **Ruling id** | `OR-__` *(next free at signing; `OR-11` at HEAD `92f529b`)* |

---

### Annex A *(placeholder — incorporated by reference)*

The `B-3` site enumeration: ~45 sites across 6 documents, classed DELETE / REWRITE / HISTORY /
OWNER-DEPENDENT, with per-site replacement text for the REWRITE class and the `T-SCHEMA-GRANT`
disposition proposal. Deliverable of the enumerating agent; this amendment adopts it wholesale on
signature.


---

## POST-DRAFT UPDATE — 2026-08-29 (sprint 2 lead; fills the §6 ⛔ slots and closes §3)

**§3 (B-3): EXECUTED** — commit `0188766`: 65 sites (26 DELETE · 34 REWRITE · 5 HISTORICAL-ANNOTATE ·
1 OWNER-DEPENDENT untouched), X-6's five properties verified with post-patch homes. Annex A is the patch's
own tuple list (sprint record). The two residues stand for this amendment's signature: the
`T-SCHEMA-GRANT-01/-02/-03` disposition (impact map recommends RETIRE with D-1 inverted to a
`pg_roles`-absence assertion) and the annotate-vs-delete convention.

**§6 (B-7): THE ⛔ SLOTS ARE FILLED — agent 4's derivation, adopted after lead verification:**

- **`emit_event` home = `076`** (outbox primitive; its own SEAM-1; reading B fails the ratified `C76`
  forward-reference test; reading C refuted by the contract's negative space — validation is contracted
  onto `enqueue`/`channel_enabled` and quarantine-at-drain). **The `076` row therefore also gains
  `CREATE SCHEMA notify` and `notify.emit_event`** beside `notify.outbox`.
- **`092.depends_on = {076, 077, 078, 079, 080, 082, 085, 090}` — EIGHT, fully derived.** `076` by
  `drain_outbox`'s direct `notify.outbox` read under the direct-declaration convention; `080` by the
  IN-and-MANDATORY security-role pair's `venue.staff_role` recipient derivation (§2.4 form 1;
  CONFLICT-4 cannot empty the venue arm, and the enqueue-direct alternative fails the same `C76` test).
  **Invariant across R1–R5** (R3 is buildable only with the classification store at `076` — no `092`
  edge either way).
- **Caller-side consequence:** the packages whose bodies call `emit_event` (`079 083 085 086 088 090`,
  plus `077`/`080` if the security producers' emit clauses are transcribed) each owe a declaration-only
  direct edge to `076` — part of this amendment's edge table, outside the `092` in-edge count.
- **Edge arithmetic at signature:** 47 declared + 8 in(092) + the caller→076 declaration set (6–8) —
  **published by the four-surface parser after the amendment applies; the derived floor is 61.**
- **Remaining genuinely-underivable:** the `is_sensitive` role-registry home (CONFLICT-4's substrate —
  wherever it lands, its reader gains one edge) — it does not affect the eight; and the stale "19 call
  sites" count (the `077`/`080` producers make it 21) — a count correction, not an edge question.


## FINAL ARITHMETIC — 2026-08-29 (post-OR-11, post-N3; signature-exact)

`OR-11` removed nothing scheduled (no dependency existed solely for bids) and `N3` moved no package.
**Parsed at HEAD: 16 packages, 47 declared edges (JSON `depends_on`, identical on all four surfaces).**
At signature: **17 packages · 62 edges** = 47 + 8 (`092` in-edges: `076 077 078 079 080 082 085 090`)
+ 7 new caller→`076` declaration edges (`079 080 083 085 086 088 090` — the `emit_event` callers not
already declaring `076`; `077` already does). Every edge is named; the four-surface parser verifies the
scalar the moment the amendment applies. The `notification_type` seeds are now writable (N3 closed;
28 IN types); authoring `092` still waits on the one R1–R5 contract choice and nothing else.
