# `X-8` — the minimum owner brief, after `A7`

> ## DISCHARGED 2026-08-29, later the same day — `P-6` LANDED AND `X-8` IS **RESOLVED**.
>
> This brief predicted zero remaining owner bits and one mechanical remediation; both held. The RPC
> owner deleted the two `EXEC: DEF` residues (§0.1a, §17.9 heading), invented no replacement value, and
> the `A7 → kernel.record_money_denial` entry in `ROLE_MODEL` §5.4 went live. Post-repair verification:
> thirteen transcribed §5.4 rows still hash-match §16.11a · both join directions resolve uniquely · the
> exclusion rule is byte-unedited · security posture unchanged (INDIRECT, two edge callers re-enumerated
> from HEAD, zero client routes, `SVC` denied) · the precedence gate's `X-8` failure cleared with the
> gate script byte-unchanged. **The declined option in §2 was not taken** — the rule was never rewritten.
> **`ID-6`** (`venue.assert_may_request`, §20.7.8 — the same defect class, second pre-existing instance,
> `T-RPC-GLOBAL-02` still fails on it corpus-wide) was found during verification, registered in
> `ODR128_CONTRADICTION_RESOLUTION.md`, and is **not** an `X-8` member. The appendix's `CM-1`/`CM-2`
> owner choices remain open and remain non-blocking. **The body below is preserved as written before
> `P-6` landed.**

**2026-08-29.** Written after owner ruling **`OR-9`** (`A7`). `A7` is closed and is not re-opened here.
Writer ownership is closed (`OR-7`) and is not re-opened here. `GRANTS` ownership is not re-opened,
because `ID-5` turns out not to be a `GRANTS` dispute.

> ## THE ANSWER THIS BRIEF EXISTS TO GIVE
>
> ```
> UNRESOLVED OWNER CHOICES REQUIRED TO CLOSE X-8 :  0
> ```
>
> **`X-8` is still `UNRESOLVED`, and no owner decision remains inside it.** Both surviving blockers were
> reconstructed from HEAD this pass. One is now closed by a mechanical housing act; the other is a
> mechanical repair owed by a named owner. **Neither is a choice.** Per the instruction not to
> manufacture an owner decision where none exists, this brief states the **mechanical remediation**
> instead, and its body is the derivation that no choice is hiding in it.
>
> An appendix records two genuine owner choices that housing the map **made visible**. They are
> **not** `X-8` blockers and must not be read as gating it.

---

## 1. `CAP-MAP` — **RESOLVED MECHANICALLY. No owner choice existed.**

### The question, and why it was never a choice

`OR-8` gave `PHASE_2_ROLE_MODEL_SPEC.md` the capability → RPC/function mapping. The owner map recorded
the state honestly: **`OWNED BUT UNHOUSED`** — the owner carried no such map in any form, and the only
map in the corpus was `PHASE_2_RLS_PERMISSION_SPEC.md` **§16.11a**, which `OR-8` makes **derived**.

Task instruction: *"If an existing subject-owner rule already determines its home: resolve
mechanically."* It does. **`CAP-MAP`'s owner was already determined and is not ambiguous:**

| classification | verdict |
|---|---|
| **A. part of `ROLE_MODEL`** | **YES — by ratified ruling `OR-8`.** |
| B. part of RPC contracts | no |
| C. part of RLS / authorization | **no — this is the reading `OR-8` overturned.** RLS holds the *`EXECUTE` posture*; the *mapping* is the role model's. |
| D. a derived cross-document registry | no — it is normative, and `T-RLS-EXEC-01` joins on it |
| E. genuinely ownerless | **no.** It was *unhoused*, which is a different condition and is the one that was fixed. |

### The one thing that could have been a choice — and was not

**Housing form: a mapping column on §5.3, or a new section?** Mechanically eliminated, not preferred:

- The map's rows are **grouped and many-to-many** — `A1 · A2 · A3 · A4` → four functions; `B2/B3` → one
  function; **`venue.review_attribution_flag` appears under both `F14` and `G5`**.
- Flattening to one function-list per capability requires **decomposing groupings the corpus decomposes
  nowhere**. That is inventing data, not transcribing it.
- A column also cannot carry the **reverse direction** (`function → capability`) that
  `T-RLS-EXEC-01` asserts *"in both directions."*

**A separate section is the only form that preserves the map exactly as ratified.** Hence
`ROLE_MODEL` **§5.4**, created this pass: the thirteen rows of §16.11a transcribed **unchanged**, the
exclusion rule carried **verbatim**, and §5.4.1 enumerating the gaps. RLS §16.11a becomes the roll-up —
filed as `ROLE_MODEL` §11.2 **`R-19`**, **not applied**, because the RLS spec belongs to its own owner.

### Corpus reconstruction, for the record

| | |
|---|---|
| documents **defining** a capability → function mapping | **one** — `PHASE_2_RLS_PERMISSION_SPEC.md` §16.11a (13 rows). Now also `ROLE_MODEL` §5.4, created this pass. |
| documents defining a **function → capability** mapping | **none.** The reverse direction the join asserts has never existed anywhere. |
| validations / joins **consuming** it | **one** — `T-RLS-EXEC-01`. Restated in `PHASE_2_IMPLEMENTATION_TRACEABILITY_MATRIX.md` §8 and RLS §16.11 / §3392; governed by RLS §11.0's `EXEC-DERIVED` rule. |
| documents **referencing** it without defining it | `ROLE_MODEL` §5 supersession clause and the §5.3 preamble; the traceability matrix. |

⚠ **A namespace hazard found while reconstructing, reported and not fixed.** `A7` is now a §5.3
capability id — and `A7` already means **three other things** in this corpus: package group *"Credential
infrastructure (C33)"* (traceability matrix), architecture assertion *"venues and events are kernel-owned
reference data"* (`SNATCH_IT_DOMAIN_ARCHITECTURE.md` §53), and venue-dashboard screen row *"Home — Payout
status"*. The traceability matrix's §9.3 **"Capability"** column carries **package** ids (`A8`, `A2`, …),
not §5.3 capability ids — so a mechanical join across columns both labelled *"Capability"* would silently
mis-associate. **No collision exists inside §5.3**, which is what `OR-9` ruled on; this is a corpus-wide
id-prefix defect of the same class the role model already files at §11.7.

---

## 2. `ID-5` — **MECHANICAL REMEDIATION, owed by the RPC owner. Still open.**

### Located exactly

`ID-5` is defined in one place: `_governance/ODR128_CONTRADICTION_RESOLUTION.md`, added to the
**intra-document** defect list when a pass found that *"RPC §0.1a and the §17.9 heading say `EXEC: DEF`;
the §17.9 body says `EXECUTE` to `authenticated` only."*

**Its owner is `PHASE_2_RPC_FUNCTION_CONTRACTS.md`** — its own document. `OR-6`'s scope limit is binding
and says so: *"Two sections of the SAME normative document contradicting each other is a mechanical
intra-document defect, and this row may not be cited to settle one."*

### The two disputed sites, quoted

| site | text at HEAD |
|---|---|
| **RPC §0.1a**, closing sentence | *"…calls `kernel.record_money_denial` (§17.9) — **`EXEC: DEF`, no human path**."* |
| **RPC §17.9**, heading | *"`kernel.record_money_denial(…)` — **DB-RPC** · **`EXEC: DEF`** · `NEW RPC`"* |
| **RPC §17.9**, body (contradicting both) | *"**`SECURITY DEFINER`, `EXECUTE` to `authenticated` ONLY — never `anon`, never `service_role`** — and it is **BOUND BY EDGE-CALLER-JWT**… It RAISES when `auth.uid()` IS NULL"* — marked `SPEC CORRECTION (S-17)`, ratified `C93` + `C106`. |

The document therefore **fails its own global assertion `T-RPC-GLOBAL-02`** — *"every `EXEC: DEF` function
has no grant to `anon`/`authenticated`."*

### Why it currently bars `A7 → record_money_denial`

The bar has two limbs, and only one of them is real:

1. **§5.4's exclusion rule** (carried verbatim from §16.11a): *"Every `DEF` RPC is deliberately absent
   from this map: a definer-only primitive implements no principal's capability, and mapping one to a
   §5.3 cell would reintroduce the human grant the `DEF` class exists to deny."*
2. **`ID-5`'s two stale labels** make the function *read* as `DEF`.

Limb 1 is sound and stands. Limb 2 is residue. **The rule fires lexically, not on the merits.**

### Classification — **`C`**

**`C` — a later ratified correction supersedes the relevant portion**, where *the relevant portion* is
**the `EXEC: DEF` classification of this one function**, and explicitly **not** the exclusion rule, which
is unweakened and carried into §5.4 verbatim.

- **Not `A`** (*correctly applied, would violate a ratified invariant*). The rule's own rationale is
  false here: there is no human grant to *reintroduce* — `GRANT EXECUTE … TO authenticated` is ratified
  **twice** (`C93`, `C106`) and already written into the canonical contract — and the row's `SVC` `·` is
  the **first denial of `service_role` in the matrix**, a narrowing.
- **Not `B`** (*governs a different concept, over-applied*). Close, and it is the second-best reading:
  `ID-5` proper governs the RPC document's internal consistency, not the map. But the labels genuinely do
  make the rule fire, so the rule is not merely being mis-cited.
- **Not `D`** (*needs decomposition: capability relationship without EXECUTE*). `OR-8` already performed
  exactly that decomposition, and `OR-9`'s `A7` row is written under it.
- **Not `E`.** See below.

### Why this is **not** an owner decision

| | |
|---|---|
| **Is another value admissible?** | **No.** `C93` proved the `DEF` configuration **unbuildable**: on a `service_role` connection `auth.uid()` is NULL, `kernel.admin_audit.actor_identity` is `NOT NULL FK→auth.users`, and the FK forbids a sentinel — *"the INSERT cannot satisfy its own constraint."* A `DEF` `record_money_denial` fails on **every** call. |
| **Does the repair need new vocabulary?** | **No.** §0.1a defines exactly two grant classes and the other one — *caller-authorized (default)* — **carries no tag.** The repair is `delete "EXEC: DEF"` at two sites, plus the *"no human path"* clause that travels with it. |
| **Does it change authorization?** | **No.** It makes a **label** agree with a grant that is already ratified and already contracted. |
| **Does any precedence rule need to be invoked?** | **No — and none may be.** `OR-6` cannot reach an intra-document defect. This is an **unpropagated correction**, which is `R-28`'s own class, not an arbitration between authorities. |

**Filed as `ROLE_MODEL` §11.4 `P-6`.** `PHASE_2_RPC_FUNCTION_CONTRACTS.md` was **not** edited by this pass.

### The option that was available and was declined — recorded because declining it was a choice

**Restate §5.4's exclusion rule substantively rather than lexically** — *exclude functions with no human
`EXECUTE` grant*, instead of *exclude functions tagged `DEF`*. Under that wording the rule stops reaching
`record_money_denial` immediately and the `A7` entry could be written today, with `ID-5` still open.

- **Security consequence:** none directly — the substantive test is the rule's own stated rationale, and
  the function's `authenticated` grant is ratified twice. **But** the lexical test is *mechanically
  checkable* and the substantive one is not, so the rule would become weaker as an assertion while
  reading stronger as prose.
- **Architecture consequence:** it is a **rule edit made by the editor to unblock the editor's own row**,
  and it would leave `T-RPC-GLOBAL-02` failing in the RPC document indefinitely, since nothing would then
  depend on the labels being right.
- **Verdict: declined**, under *"do not weaken `ID-5` merely to close `X-8`."* Repairing two stale labels
  costs less and fixes the actual defect. **It is recorded here so the owner can overrule if desired; it
  is not recommended.**

---

## 3. `X-8` status, recomputed from HEAD

```
CAPABILITY (A7)         WRITTEN     ROLE_MODEL §5.3 block A, 70 rows
CAP-MAP HOME            HOUSED      ROLE_MODEL §5.4, created this pass
A7 MAPPING ENTRY        ⛔ BLOCKED  by ID-5 — written as a blocked row, not as a mapping
ID-5                    OPEN        mechanical, RPC owner, ROLE_MODEL §11.4 P-6
RLS §16.11a ROLL-UP     OWED        ROLE_MODEL §11.2 R-19, filed not applied

X-8                     UNRESOLVED
REMAINING OWNER BITS    0
```

**Next mechanical remediation, smallest first:**

1. **`P-6`** — RPC owner deletes `EXEC: DEF` at RPC §0.1a and the §17.9 heading. **This alone closes
   `X-8`**: the exclusion rule stops reaching the function, §5.4's `⛔ A7` row becomes the mapping entry,
   `T-RLS-EXEC-01`'s join gains its missing entry in both directions, and `T-RPC-GLOBAL-02` passes.
2. **`R-19`** — RLS owner restates §16.11a as the roll-up of §5.4. Independent of (1); until it lands the
   two are byte-identical in their thirteen rows, so nothing is ambiguous in the interim.

---

## APPENDIX — two genuine owner choices, **NOT `X-8` blockers**

Housing the map made these visible; it did not create them. **`X-8` closes without either.** Both are
capability-**existence** questions, which `OR-8` assigns to `PHASE_2_ROLE_MODEL_SPEC.md` — but the corpus
supplies no derivation either way, so they are registered (`CM-1`, `CM-2` at §5.4.1) and **not decided**.

### `CM-1` — **`B7` "Resolve dispute (escrow)" is implemented by nothing**

- **Disputed contract:** §5.3 grants `B7` **`R✱ᴰ`** to `platform_admin` — RPC-only, **fresh step-up**,
  **dual control** — and `Rᴾ` (propose-only) to `platform_support` and `platform_risk`. **No RPC in the
  corpus implements it.** The map's money rows jump `B6 → B8`.
- **Owner:** `PHASE_2_ROLE_MODEL_SPEC.md` (`CAPABILITY`).
- **Options:** **(a)** contract the RPC — a money-authority function needing dual control, step-up and an
  approval-request row; **(b)** retract `B7` as a capability Phase 2 does not carry.
- **Security consequence:** (a) adds a money-moving surface that must satisfy SoD and step-up. (b) removes
  none — **nothing implements it today, so no authority is being exercised either way.** The live risk is
  the third state: a ratified capability with real security machinery that an implementer may read as a
  requirement and build **without** the machinery.
- **Architecture consequence:** (a) is a new `085`-band function and a new package edge. (b) is a row
  deletion plus a §5.4 gap-row removal.
- **Recommendation:** **decide it before `085` is authored, not after.** No recommendation between (a) and
  (b) — dispute resolution is a product-scope question, and `PHASE_2_SCOPE_AMENDMENT_2026_08.md` is where
  its scope would be settled, not here.

### `CM-2` — **`I4` "Referral / ambassador program" is implemented by nothing**

Same shape without the security machinery. Options and consequences as above, lower stakes.

### Three further map defects, carried and **not** owner decisions

`CM-3` duplicate semantic mappings (`update_event` in three cells) · `CM-4` uncontracted or aliased
targets (`admin_refund`, `update_organization`, `set_org_status`, `grant_platform_role`; and
`venue.record_scan`, which `X-6` established is a **delegating wrapper, not the writer** — ruled to the
RPC owner by `OR-7` and **never re-derived here**) · `CM-5` the read boundary is inconsistent (the map's
scope is EXEC rows, yet it maps `A6`'s read RPC and omits `venue.list_attendees` and
`kernel.list_org_payouts`). All three are enumerated at `ROLE_MODEL` §5.4.1.
