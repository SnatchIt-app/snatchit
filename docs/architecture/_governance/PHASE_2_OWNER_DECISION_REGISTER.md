# Phase 2 — Owner Decision Register

**Status:** INSTRUMENT, not authority. This file **decides nothing** and **changes nothing**. It is a reading
aid: one place where every open owner decision in the Phase 2 design corpus is stated once, in the form a
decision needs to be decidable — a question with named options, the failure under each option, the direction
silence falls, and what is blocked until it is answered.

**Built:** 2026-08-28, against branch `phase2/consolidation` at `32249f2`.
**Corpus scanned:** `docs/architecture/**` (33 files) and `ARCHITECTURE_FREEZE.md`.

---

## How to read this file

**Nothing here is a ruling and nothing here is new.** Every entry is assembled from text that already exists
in the corpus. Where the corpus carries a recommendation it is **quoted**, with its source named; where it
carries none — several deliberately carry none — the entry says so. Where two documents disagree, both
positions are stated and neither is preferred.

**One decision, one entry, one id.** The corpus files the same decision in as many as five places under as
many as three different ids. This register merges those into one entry and lists every filing site, with the
evidence for the merge.

**The `Silence` column is the one to read first.** Several of these decisions have a default that ships
automatically if nobody answers, and for several of those the default is the **unsafe** direction: the
permissive grant, the missing floor, the unbounded value. Those are marked `SILENCE → UNSAFE`. A decision
whose silent default is safe can wait; one whose silent default is unsafe cannot, because *not deciding* is
already a decision and it has already been taken.

**Ordering.** Entries are ordered by what they block, most blocking first, then by blast radius:

| Band | Meaning |
|---|---|
| **Band 1 — blocks the start** | Must be answered before the first Phase-2 migration (`076`) or before the package DAG can be re-ratified at all. Nothing downstream is safe to begin. |
| **Band 2 — blocks a named package** | Implementation can start; one identified package (`077`, `082`, `086`, `087`, …) or one identified surface cannot be built until this closes. |
| **Band 3 — blocks a flag or a value** | The build proceeds; a feature flag cannot be turned on, or a config key ships with no number in it. |
| **Band 4 — blocks nothing today** | Real and unanswered, but nothing in the current scope waits on it. |

---

## The new id namespace, and the proof it is unused

Ids in this file are **`ODR-1` … `ODR-n`** (*Owner Decision Register*). They are **additive**. They rename
nothing, renumber nothing, and replace no existing id anywhere in the corpus: every entry keeps and lists its
original ids, and those ids remain the ones to cite in their own documents.

**Why a new namespace was needed.** Open owner decisions are currently filed under at least eight
mutually-colliding series, and three of the collisions are documented hazards in the corpus itself:

| Series | Where | Collision |
|---|---|---|
| `O6` … `O16` | `_governance/PHASE_2_RATIFICATION_RECORD.md` | `O6`–`O8` unhyphenated also read as DA §0.4 architecture open questions; `O-1`…`O-5` hyphenated are owner *rulings*. Filed as record row `D4`. |
| `D-n` | `PHASE_2_MONEY_AUTHORITY_SPEC.md` §11 | Three unrelated `D-n` series exist (money, CRM, demographics), **and** the record's own `D1`–`D21` rows collide with all three. |
| `D-n` | `PHASE_2_CRM_EXPORT_SPEC.md` §14 | as above |
| `D-n` | `PHASE_2_DEMOGRAPHICS_PRIVACY_SPEC.md` §16 | as above |
| `S-n` | `PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md` §13.7 | Collides with a different `S-n` series in `PHASE_2_ROLE_MODEL_SPEC.md`. Filed as a known hazard by record row `D17` (*"the `S-`/`D-` edit-id namespace collisions"*). |
| `S-n` | `PHASE_2_ROLE_MODEL_SPEC.md` §11.7 | as above |
| `R-n` | `PHASE_2_RPC_FUNCTION_CONTRACTS.md` §20.14 | Three unrelated `R` series (RPC requests, role-model RLS edits, risk register `R1`–`R36`); the record avoided a fourth by minting `RET-`. |
| `X-n` | `PHASE_2_RLS_PERMISSION_SPEC.md` §17 | — |
| `OD-n` | `PHASE_2_ROLE_MODEL_SPEC.md` §13 | — |
| `OQ-n` / `OQ-Wn` | `PHASE_2_DOOR_LIFECYCLE_SPEC.md` §16 / `PHASE_2_APPLE_WALLET_SPEC.md` §15 | — |
| `COND-A/B/C` | `PHASE_2_SCOPE_AMENDMENT_2026_08.md` | — |
| `Δn` / `U-n` | `PHASE_2_VENUE_DASHBOARD_PRODUCT_SPEC.md` | — |

**Proof `ODR-` is unused.** Two checks, run against the whole repository at `32249f2`:

```
$ grep -rIoE '\bODR-[0-9]+' . --exclude-dir=.git | wc -l
0

$ grep -rIin 'odr' . --exclude-dir=.git
.git:1:gitdir: .../worktrees/wt-odr
package-lock.json:65,735,2679,4807     (npm integrity sha512- hashes)
web/package-lock.json:2397             (npm integrity sha512- hash)
```

The only case-insensitive occurrences of the three letters anywhere in the repository are inside base64
npm integrity digests and this worktree's own path. A third check enumerated **every** id-shaped token
(`^[A-Z]{1,8}-?[0-9]{1,3}[a-z]?$`) across `docs/architecture/**` and `ARCHITECTURE_FREEZE.md` — 118 distinct
prefixes, listed below — and `ODR-` is in none of them:

```
A A- ADDITIVE- API APPR- ATTR- AUDIT- AUTHZ- B B- BCP- C C- CAT- CFG CFG- COL- COMP- CONFLICT- CONNECT-
CRM CRM- CUSTODY- D D- DAG- DASH- DAY DB- DEFAULT- DEL- DEM DEMO- DEV- DL- DOOR- DRIFT- DS- E E- EA- EDGE-
EX- EXEC- EXPIRY- F F- FORCE- FR- G G- GATE- GLOBAL- GP- GUEST- H H- HG- I I- INV- J J- JORDY K K- KEY- L
L- M M- MARKET- MB- MD- MN- MONEY- MP- N NEW- NOTIFY- O O- OBS- OD- OFFER- OPEN- OQ- ORG- P P- PAYOUT-
PG PKG PL- POL- PROJ- PROMO- PSD PURGE- Q R R- REPLAY- RET- RM- ROLE- RV- S S- SEAM- SEC- SENTINEL- SET-
SETTLE- SF- SHA SHA- STAFF- SUBJ- T T- TM U- V V- W W- WALLET- X X- XO-
```

---

## How the corpus was searched, and why one pattern was not enough

The corpus does not mark open owner decisions consistently — that inconsistency **is** the problem this file
exists to solve, so the search could not assume any single marker. Every file listed above was read in full,
and the following independent sweeps were run across `docs/architecture/**` and `ARCHITECTURE_FREEZE.md`:

1. **The register tables**, each under its own local id scheme — money §11, CRM §14, demographics §16,
   schema §13.7, RPC §20.14, RLS §17, role model §13, door §16, Wallet §15, registry §7 and §7.1,
   dashboard's `Δ`/`U` lists, and the ratification record's `OPEN-GATED` rows.
2. **Status-word markers:** `OPEN-GATED`, `OPEN — owner`, `OPEN — recorded, not applied`.
3. **Prose markers:** `OWNER DECISION`, `OWNER-DECISION`, `owner ruling`, `the owner's`, `owed to the owner`,
   `owner must`, `awaiting owner`, `requires owner`, `owner ratification`, `owner sign-off`,
   `not decided here`, `recorded, not made`, `recorded rather than taken`, `left with its owner`.
4. **Negative-space markers** — the phrases the corpus uses when it declines to decide:
   `NO RECOMMENDATION IS OFFERED`, `Not made here`, `NO SIDE IS TAKEN`, `the choice is the owner's`,
   `a decision I declined to make alone`, `open question`, `must be chosen`, `not chosen`.
5. **The "what this pass deliberately did NOT do" paragraphs**, which every remediation pass in the record
   writes and which are where several decisions are named and nowhere else indexed.

Sweep 4 is the one that matters: the decisions with the most careful reasoning behind them are precisely the
ones whose authors refused to write a recommendation, and those rows contain none of the words in sweep 3.

---

## What this file deliberately did NOT do

- It **decided nothing.** No option is chosen, no default is endorsed, no recommendation is authored. Where a
  recommendation appears it is quoted from the corpus and attributed.
- It **closed nothing.** The "appears open, is in fact settled" section names decisions a later ratified row
  or spec already answered, with the evidence — it does **not** close them. Closing them is a bookkeeping act
  in the ratification record, and that is an owner act under Rule 1.
- It **renumbered nothing.** Every `ODR-n` is additive and lives only in this file.
- It edited **no** other document, **no** `OFFLINE-VERIFY-v1` fenced block, nothing under `.github/`,
  `supabase/` or any migration.

---

# BAND 1 — blocks the start of implementation

Seven decisions. **Nothing downstream is safe to begin until these are answered**, and two of them
(`ODR-1`, `ODR-5`) block work that has not started rather than work in progress, which is the cheapest
moment they will ever be answered at.

---

## ODR-1 — Re-ratify the amended package registry

**The question.** Does the owner ratify the **six amendments the package registry has already written into
itself**, or send one or more of them back?

**The six, as the registry states them:** (1) `kernel.approval_request` placed in `077` + two packages renamed
(`083_kernel_signing_key` → `083_kernel_credential_infrastructure`, `087_venue_settlement` →
`087_venue_settlement_and_export`) + seven dependency edges; (2) the schema-security remediation (additive to
`077`/`078`/`086`/`090`, adding `venue.door_session` and recommending edge `086 → 087`); (3) the
`crm-export-worker` amendment; (4) the `K-2`/`K-3` missing-object repair (`kernel.identity_contact_pref_event`
→ `077`, `kernel.org_contact_consent_event` → `082`, the `087` purge substrate, edges `077 → 082` and
`078 → 082`); (5) `AUTHZ-PKG1` — four venue-plane read policies move `078`/`079` → `080`, edge `079 → 080`;
(6) the `MB-2`…`MB-5` unwritable-control pass.

**What breaks under each option.** *Ratify* — nothing; the registry's stated content is what every other
document already builds against. *Do not ratify (or leave it open)* — registry rule §6.5 says *"this registry
is updated **only** by ratified amendment."* Every package authored against the current text is therefore
authored against unauthorized content, and the sixteen-package band `076`–`091` has no ratified statement
behind it. This is not a documentation nicety: `SEAM-1` placement, the 38-edge dependency graph and the
rollback ordering all derive from the registry.

**Which way silence falls.** The registry stays `PENDING RE-RATIFICATION` and **no package may be authored at
all.** The default is **safe but total** — it is the one open decision whose silent default stops work rather
than shipping a defect.

**Blocks.** **Authoring any package.** Every migration in `076`–`091`.

**Filing sites.** `PHASE_2_PACKAGE_REGISTRY.md` header (six `⚠ AMENDMENT PENDING RE-RATIFICATION` blocks) ·
`PHASE_2_SCOPE_AMENDMENT_2026_08.md` §14.2-K `OD-79` · `_governance/PHASE_2_RATIFICATION_RECORD.md` rows
`C72` / **`O10`** and `C73`/`C74` (`RATIFIED-PENDING-REGISTRY-RE-RATIFICATION`) ·
`PHASE_2_ROLE_MODEL_SPEC.md` §13 `OD-10` · `PHASE_2_PROMOTER_CODES_SPEC.md` §14.1 ·
`PHASE_2_NOTIFICATIONS_SPEC.md` §10 `O-N7` · `PHASE_2_VENUE_DASHBOARD_PRODUCT_SPEC.md` §22.15 ·
`PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md` §1.13 header and §3.10a header (both *"requires
re-ratification"*).

**Does the corpus recommend?** **Yes.** `PHASE_2_SCOPE_AMENDMENT_2026_08.md` §14.2-K, the scope amendment's
own consolidated index: *"Ratify as amended; the count changes to 17 only if OD-14 is Gate P."* The registry
itself declines to recommend on its own amendments, noting only *"No change here is an owner **decision**"* —
i.e. it claims the amendments are mechanical, not that they are ratified.

**Note.** `ODR-3`'s answer changes this one's arithmetic: `notify` at Gate P makes the band `076`–`092` and
seventeen packages, which falsifies the registry §2 assertion of *"16 packages … no gaps, no duplicates"*.
Answer `ODR-3` in the same sitting or ratify conditionally.

---

## ODR-2 — Is the event outbox in Phase 2?

**The question.** Build the event outbox table and drainer in Phase 2 as the constitution promises **(a)**, or
amend the constitution to withdraw the promise and re-scope Wallet push, door events and notifications **(b)**?

**The two forms, as the corpus states them.** **(a) the constitution is right** — an outbox package is
Gate-P/MVP work missing from the plan; placement is **`076`** (*"the table has zero FK dependencies, so no
producer package gains an edge"*), drainer on the existing 2-minute `pg_cron` heartbeat, schema
`notify.outbox` if `ODR-3` is Gate P and `kernel.event_outbox` otherwise. **(b) the implementation specs are
right** — DA §6.2/§6.3 must stop claiming an outbox exists in Phase 2, `C12`'s event-envelope guarantees have
**no carrier** at MVP, and every design that emits an envelope message needs a stated alternative transport.
The schema spec puts it plainly: *"There is no third option in which DA:1253 stands and nothing implements
it."*

**What breaks under (b), priced.** From `PHASE_2_PACKAGE_REGISTRY.md` §7: *"the entire Apple Wallet push path
(pass supersession runs in the outbox consumer specifically so Wallet can never block or roll back a custody
transfer — the two alternatives, moving it into the custody transaction or leaving a superseded pass live, are
both prohibited by ratified invariants); the door-manifest open transaction as specified (its steps are
all-or-nothing and the last one writes the envelopes); scanner push-to-sync; every notification.
**Unaffected:** CRM export …, demographics, promoter codes, and money authority — each carries its own
scheduler."* **What breaks under (a):** one table and one RPC on a cron that already runs — the constitution's
own anti-over-engineering budget, per the notifications spec.

**Which way silence falls.** No outbox is built, because no implementation spec schedules one. **UNSAFE.** The
traceability matrix states the consequence: four capabilities become *"unimplementable **as designed**, not
merely degraded"*, and the Wallet push path has *"**no admissible alternative design**"*.

**Blocks.** Package **`076`**. Hard gate `HG-2` (*"No Wallet push path, no door-manifest open transaction as
specified, no scanner push-to-sync and no notification may ship before the outbox ruling is made"*). The
traceability matrix adds a deadline: *"Neither ruling can be deferred past `083`."*

**Filing sites.** `_governance/PHASE_2_RATIFICATION_RECORD.md` row `C51` / **`O7`** (`OPEN-GATED`) ·
`PHASE_2_PACKAGE_REGISTRY.md` §7 **`COND-A`** + the registry JSON `conditionals[0]` ·
`PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md` §13.3 **CONDITIONAL A** · `PHASE_2_SUPABASE_MIGRATION_PLAN.md` §8
`COND-A` · `PHASE_2_SCOPE_AMENDMENT_2026_08.md` §13.1 and §14.2-B `OD-13` ·
`PHASE_2_NOTIFICATIONS_SPEC.md` §10 `O-N2` and §1.8 `CONFLICT-2` · `PHASE_2_RLS_PERMISSION_SPEC.md` §15.7
`MD-11` · `PHASE_2_IMPLEMENTATION_TRACEABILITY_MATRIX.md` `G-1` / `D4` · `SNATCH_IT_DOMAIN_ARCHITECTURE.md`
§0.4 and the §6.3 boxed note · `SNATCH_IT_CANONICAL_DATA_MODEL.md` §15 `C51/O7`.

**Does the corpus recommend?** **Split, and the split is recorded.** `PHASE_2_NOTIFICATIONS_SPEC.md` §10:
*"Build it. It is one table plus one RPC on a cron that already runs — the constitution's own
anti-over-engineering budget."* The scope amendment records the disagreement rather than resolving it:
*"`NOTIF` §10 recommends **build it** … **`REGISTRY` and `SCHEMA` decline to recommend.** Not decided here."*
The schema spec's own words: *"**This is a conditional package element and this integration does NOT decide
it.** It is specified here so that a YES ruling is an apply, not a design exercise."*

---

## ODR-3 — What gate is the `notify` schema at?

**The question.** Is `notify` a **Gate-P MVP context**, as ratified row `C7` says, or **Gate L /
do-not-build**, as all four implementation specs say?

**What breaks under each.** *Gate L* — the venue dashboard's §16.5 carries a **binding** dependency on the
notification plane, and RLS `MD-10` rules that no Gate-L object may carry one; every notification stays on the
frozen `public.notifications` path, which the schema spec describes as having *"**no preference matrix, no
mandatory-type guard, no delivery-state ledger, no dedupe key and no locale**"*, leaving the money spec's seven
money emitters, the door's events #37–#44 and Wallet's holder-facing updates with **no carrier**; and the
traceability matrix records `G-19` — preference toggles *"that gate nothing"*, which replicates a named live
production defect. *Gate P* — nine `notify.*` tables land as package **`092`** (floored there by `SEAM-1`
because `notify.drain_outbox` reads `venue.promoter_link` at `090`), **the count becomes 17 and the range
`076`–`092`**, which falsifies registry §2's *"no gaps, no duplicates"* assertion and requires the
re-ratification of `ODR-1`.

**Which way silence falls.** The four implementation specs win by weight of numbers, `notify` is never
scheduled, and the dashboard surface ships against nothing. **UNSAFE.**

**Blocks.** Package **`092`**'s existence; the package count and range; everything in RLS §16.9 and dashboard
§16.5; and — because `notify.outbox` versus `kernel.event_outbox` is decided here — the schema home of
`ODR-2`'s table.

**Coupling — this is binding on how the two are asked.** `COND-D`, stated in `PHASE_2_PACKAGE_REGISTRY.md` §7
and `PHASE_2_SCOPE_AMENDMENT_2026_08.md` §13.3: outbox-in with `notify`-out is coherent; outbox-out with
`notify`-out is coherent; both in is coherent; **`notify`-in with outbox-out is not**, because *"the
notifications design **is** the outbox pipeline."* **Rule `ODR-2` first, then `ODR-3`, in one sitting.**

**Filing sites.** `_governance/PHASE_2_RATIFICATION_RECORD.md` row `C52` / **`O8`** ·
`PHASE_2_PACKAGE_REGISTRY.md` §7 **`COND-B`** + JSON · `PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md` §13.4
**CONDITIONAL B** · `PHASE_2_SUPABASE_MIGRATION_PLAN.md` §8 `COND-B` ·
`PHASE_2_SCOPE_AMENDMENT_2026_08.md` §13.2, §8, §14.2-B `OD-14` · `PHASE_2_NOTIFICATIONS_SPEC.md` §10 `O-N1`
and §1.8 `CONFLICT-1` · `PHASE_2_RLS_PERMISSION_SPEC.md` §15.7 `MD-10` ·
`PHASE_2_VENUE_DASHBOARD_PRODUCT_SPEC.md` §22.16 · `PHASE_2_IMPLEMENTATION_TRACEABILITY_MATRIX.md` `G-2` /
`G-19` · `SNATCH_IT_CANONICAL_DATA_MODEL.md` §1.6 and §15 `C7`.

**Does the corpus recommend?** **Split.** `PHASE_2_NOTIFICATIONS_SPEC.md` §10: *"Ratify the reading that C7's
*eviction* is satisfied vacuously (the leaves were never in the kernel), **and separately** authorise `notify`
at Gate P on its own merits — because the venue dashboard already has a binding dependency on it (`§16.5`),
which no Gate-L object may have."* `PHASE_2_RLS_PERMISSION_SPEC.md` §15.7 `MD-10` refuses: *"**Not resolved
here** — it is a stop-and-ask. §16.9's matrices are conditional."*

---

## ODR-4 — Acknowledge the two global-posture exceptions, and bind whoever next edits migration `020`

**The question.** Accept, as named exceptions to two standing corpus rules, that (i) `kernel.identity_demographic`
carries a **definer-scoped `DELETE`** — the single `GP-2` exception in the whole model — and (ii) the
demographic and contact/consent relations carry **`ON DELETE CASCADE` from `auth.users`** against the corpus
`ON DELETE RESTRICT` default; **and** bind whoever next edits migration `020` never to repoint those rows to
the `019` anonymization sentinel?

**What breaks under each.** *No `DELETE`* — *"keeping a withdrawn gender answer as a tombstoned row would
defeat the withdrawal."* *`RESTRICT` instead of `CASCADE`* — account deletion **fails outright** on the log of
a permission the account already withdrew; the demographics spec calls an orphaned answer *"the worst possible
residue"*, and the registry adds that `RESTRICT` *"needs an erasure path designed, and none exists."*
*Sentinel repoint (the live `019`/`020` house pattern)* — *"a sentinel row holding 'consent granted to 40
orgs' would be an accumulating grant belonging to nobody, and the gate in §5.1 would evaluate it"*, and on the
demographics side it would *"pile every deleted user's gender answer onto a single identity and create a
'sentinel demographics' row."*

**Which way silence falls.** **UNSAFE, and specifically so.** The exceptions ship unacknowledged inside `077`
and are **not reversible once data exists** (`HG-8`) — and the third limb has no enforcement at all:
repointing to the sentinel **is** what `019`/`020` already do, so silence plus one routine edit to `020`
reintroduces the defect.

**Scope has changed since the sign-off was first requested.** `PHASE_2_PACKAGE_REGISTRY.md` §7.1
`OWNER-DECISION-K2-D3`: *"**`D-3`'s outstanding sign-off now covers SIX relations, not four.**"* The two
`_event` consent ledgers inherit the cascade mechanically — *"but `D-3` is an unresolved sign-off, and
silently widening its scope from four relations to six is exactly the shape of change rule §6.5 exists to
stop."*

**Blocks.** Package **`077`** (hard gate `HG-8`), and packages `077`/`082` for the two `_event` ledgers.

**Filing sites.** `PHASE_2_SCOPE_AMENDMENT_2026_08.md` §14.2-C `OD-19` and §11 `HG-8` ·
`PHASE_2_DEMOGRAPHICS_PRIVACY_SPEC.md` §14 `D-9` and `D-11` (and §10.2, §8.2) ·
`PHASE_2_CRM_EXPORT_SPEC.md` §13 `D-3`, §11.2 and §9.5 (correction `K-6`) ·
`PHASE_2_RLS_PERMISSION_SPEC.md` §15.7 `MD-9` · `PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md` §1.15.2 (its
**own** `D-3`, a different id from the money spec's) · `PHASE_2_PACKAGE_REGISTRY.md` §7.1
`OWNER-DECISION-K2-D3` · `_governance/PHASE_2_RATIFICATION_RECORD.md` row `D13`.

**Does the corpus recommend?** **Yes, on both limbs.** `PHASE_2_SCOPE_AMENDMENT_2026_08.md` §14.2-C: *"Accept
as the single GP-2 exception in the model; a second must not be granted by analogy."*
`PHASE_2_PACKAGE_REGISTRY.md` §7.1: *"**CASCADE (recommended, and what §1.15 specifies):** deletion is clean;
the fan's evidence dies with the account, consistent with `§9.2`."*

---

## ODR-5 — Execute the migration-history repair, and authorize it

**The question.** Execute the migration-history repair event now under owner authorization, or continue to
hold every Phase-2 migration?

**What breaks under each.** *Execute* — a one-time, authorized repair event with a documented procedure.
*Don't* — `ARCHITECTURE_FREEZE.md` rule 5 and the pre-implementation closeout both state the repair is
**required before any Phase-2 migration is applied to any real database**; the engineering execution protocol
strengthens rule 5 into an **unconditional** prohibition on Supabase automatic production deployment until the
owner has *visually* confirmed the dashboard control is off (`AUTODEPLOY-1`, step 10a). Applying `076` without
it puts an unrepaired history under a sixteen-package chain.

**Which way silence falls.** Nothing is applied — **safe**, and it is the second of the two decisions here
whose silent default stops work rather than shipping a defect.

**Blocks.** **Applying any Phase-2 migration to any real database.** Not authoring — applying.

**Filing sites.** `ARCHITECTURE_FREEZE.md` rule 5 · `_governance/PHASE_2_PREIMPLEMENTATION_CLOSEOUT.md` §9
item 1 · `_governance/PHASE_2_ENGINEERING_EXECUTION_PROTOCOL.md` §1 (`AUTODEPLOY-1`).

**Does the corpus recommend?** **It recommends the sequence, not a choice** — the repair is described as owed
and its execution as requiring owner authorization; no document argues for deferring it.

---

## ODR-6 — What happens to the untracked `043_profiles_select_column_restriction.sql`

**The question.** Renumber the untracked migration file on `mobile/profile-rpc-compat` above the applied
maximum `075` **without** colliding with the reserved `076`–`091` Phase-2 band, fold it into another
migration, or delete it?

**What breaks under each.** *Renumber into the band* — it consumes a number the registry has reserved and
falsifies the sixteen-package assertion `ODR-1` is being asked to ratify. *Leave it as `043`* — the closeout
calls it a **back-dated-version hazard**: a migration numbered below the applied maximum, sitting in a tree
whose migrations guard asserts monotonic ordering. *Fold or delete* — the column restriction it carries has to
go somewhere or be abandoned.

**Which way silence falls.** The file sits untracked at `043` and the hazard stands. **UNSAFE** in the narrow
sense that the next person to run the migration tooling meets a numbering conflict rather than a decision.

**Blocks.** Nothing numbered; it collides with the `076`–`091` reservation that `ODR-1` ratifies.

**Filing sites.** `_governance/PHASE_2_PREIMPLEMENTATION_CLOSEOUT.md` §9 item 2.

**Does the corpus recommend?** **No.** The closeout states the three options and the hazard and stops.

---

## ODR-7 — Precedence between delta specifications

**The question.** When two documents in the **same tier** — two delta specs, or a delta spec and an
implementation spec — state contradictory authority for the same object, which governs: **(a) recency**,
**(b) subject-matter ownership**, or **(c) remediation-tag precedence**?

**The three forms, verbatim from record row `C75`.** *"**(a) recency** — the later ratified correction
governs, mechanical but blind to whether the later document is the right owner of the section; **(b)
subject-matter ownership** — a named owner per subject (authority branches → RPC; predicates/grants → RLS;
physical columns → schema; the money-authority *model* → the money spec), correct but requiring an owner map
the corpus does not yet have; **(c) remediation-tag precedence** — where two documents state the same rule and
one carries a ratified correction tag (`AUTHZ-*`, `J-*`, `K-*`, `S-*`, `H-*`) and the other carries none, the
tagged text governs and the untagged is presumed pre-remediation."*

**What breaks with no rule — this already happened.** `PHASE_2_MONEY_AUTHORITY_SPEC.md` §6.2 and
`PHASE_2_RPC_FUNCTION_CONTRACTS.md` §17.2 both carried a **build-ready** authority branch for
`kernel.approve_refund_request` and they contradicted each other, with the money spec's branch keyed on two
strings that are stored nowhere — *"an implementer following it routes every parked refund to the org arm,
above-ceiling and consumed-atom cases included."* Nothing in the corpus ranked them: `PHASE_2_SPEC_FOUNDATION.md`
§0 says *"if a source document conflicts with this file, surface the conflict; **do not silently pick a
side**"* — correct, and silent on which side wins — and `ARCHITECTURE_FREEZE.md` Rule 3 ranks **tiers**, placing
every delta spec in one. **The only available action was *surface it*, and that is exactly what nobody did.**

**Which way silence falls.** The standing obligation stays `SPEC_FOUNDATION` §0's *surface, do not pick a
side* — **safe in principle, and demonstrably not what happens in practice**: the defect above stood as a
build-ready contract for a full remediation cycle. The `D14` pass resolved that one instance using form (c) and
recorded that its reasoning *"is not ratified as a general rule and must not be cited as one"* and **does not
generalize to a conflict where neither side carries a ratified row**.

**Blocks.** No package. It blocks **the next delta-vs-delta conflict**, which has no stated resolution — and
this register documents several places where two documents already disagree (`ODR-23`, `ODR-39`, and the
`resale_state` writer question at `ODR-80`).

**Filing sites.** `_governance/PHASE_2_RATIFICATION_RECORD.md` row `C75` / **`O11`** (`OPEN-GATED`) ·
`ARCHITECTURE_FREEZE.md` Rule 3 boxed note · `PHASE_2_SPEC_FOUNDATION.md` §0 ·
`PHASE_2_MONEY_AUTHORITY_SPEC.md` §13.2 and its header banner.

**Does the corpus recommend?** **No, explicitly.** Record row `C75`: *"**Ranking delta specs against each
other decides which document's authority statement binds an implementer, which is an OWNER decision. It is NOT
made here.**"*

---

# BAND 2 — blocks a named migration package

Twenty-seven decisions, ordered by the package they gate. Implementation can begin once Band 1 closes; each
of these stops one identified package from being authored correctly.

Each entry states: the question as a choice · what breaks under each option · **which way silence falls, and
whether that direction is safe** · the package · every filing site · the corpus recommendation, quoted.

---

### ODR-8 — Per-org refund/payout thresholds at launch? · `077`
**Choice.** One platform-wide threshold set (build nothing), **or** build `kernel.org_money_policy` — `org_id`
PK, override columns, org-scoped read, platform-only write, versioned, audited.
**Breaks.** *Build it* — *"it doubles the resolution logic (per-org → fall back to platform) at every decision
point"*, `077` gains a table, every threshold read becomes two-step, and `kernel.approval_request`'s
`config_versions` must pin the **org** policy version as well as the platform pair. *Don't* — every org shares
one ceiling.
**Silence.** Never built. **SAFE.**
**Blocks.** `077` scope — a conditional package element marked *"DO NOT BUILD WITHOUT AN OWNER RULING."*
**Filed at.** MONEY §11 `D-2` + §7.4 · REGISTRY §7 `COND-C` · SCHEMA §1.14 + §13.1 (`cond.` row) · AMEND
§14.2-A `OD-02`.
**Recommendation — yes, and it has been withdrawn from under itself.** MONEY §11: *"**No** — **but the stated
basis has since become false and the recommendation must be re-derived before it is acted on.** This row
argues from *"`platform_config` is world-readable"*. **It is not**: RLS §8.4 is a two-class model on
`visibility` (`AUTHZ-CFG1` / ratification **C71**), and money keys are `restricted`. A non-public home for
per-org limits may therefore already exist. **Recorded, not re-decided**."* The traceability matrix flags the
same premise as needing re-derivation (`TM-X2`). **Re-pose the question before answering it.**

### ODR-9 — Were `org_marketing` and `org_promoter_manager` intended to be storable at the org grain? · `077`
**Choice.** Confirm the six-label org set (what the schema pass restored), **or** rule marketing/promoter
venue-grain only — in which case *"the fix is the opposite one — remove them from §0.6."*
**Breaks.** Before the fix, `077` enumerated only four org labels, so the two labels were **unstorable** —
*"`23514` at write time on both the grant and the invite path, with no workaround short of a migration."*
Confirming the wrong reading entrenches it in a CHECK constraint.
**Silence.** Six labels ship. **SAFE while the tables are empty; unsafe after `077` applies** — the role model
warns *"the enums are still editable. After the venue-staff-roles package ships they are not."*
**Blocks.** `077` — `kernel.org_member.role` and `kernel.org_invite.role` CHECK sets.
**Filed at.** SCHEMA §13.7 `S-8` + §1.3.1 (defect `M-5`) · ROLE_MODEL §3.1–§3.4.
**Recommendation.** **None explicit.** The schema pass acted *"on the strength of §0.6's own canonical table;
the role model is the document that ratified the six"* and calls the correction *"mechanical **if** the
six-label set is right."*

### ODR-10 — Is `kernel.approval_request` an aggregate class or an intent record? · `077`
**Choice.** **Aggregate class** ⇒ a sixteenth SSCAS member ⇒ `C28`'s closure needs a formal amendment; **or
intent record** ⇒ `SSCAS: n/a`.
**Breaks.** Neither breaks anything at runtime — *"It is lock-ordered either way."* What changes is whether
`C28`'s ratified fifteen-member closure is still true.
**Silence.** Intent record; `C28`'s fifteen stands. **SAFE.**
**Blocks.** The parked refund branch (MONEY §6.1); the placement of the table in `077`.
**Filed at.** MONEY §11 `D-1` + §7.5 · RLS §17 `X-8` + §15.7 `MD-1` · RPC §16 item 8 + §17.1 · SCHEMA §0.9 +
§1.13 · AMEND §14.2-A `OD-01`.
**Recommendation — yes, three documents agree.** MONEY §11: *"Intent record — argued in §7.4; it is
lock-ordered either way, so an amendment is a one-line ratification"*. RLS §15.7 `MD-1`: *"Intent record — the
parked branch takes `FOR UPDATE` on exactly one pre-existing class (Ticket Atom); the approval row is a fresh
INSERT that contends on nothing."*
**Citation defect to be aware of.** Every citation points at MONEY **§7.4** (*"Per-org override"*); the SSCAS
argument is in **§7.5**.

### ODR-11 — The six threshold values · `078` seeds
**Choice.** The numbers for `refund.org_auto_execute_max_minor`, `refund.org_dual_control_max_minor`,
`refund.platform_support_max_minor`, `payout.request_auto_max_minor`, `payout.dual_control_min_minor`,
`refund.request_ttl_hours`.
**Breaks.** The operand changed under these numbers: *"**AMENDED (`MB-1`): the refund keys now denominate a
CUMULATIVE ceiling per payment (§6.1a), not a per-call one.**"* — *"A per-call £50 and a cumulative £50 are
different products"*, and *"an owner who sets the numbers against the old reading sets them against a control
that no longer exists."* Absent `refund.request_ttl_hours`: *"**A hold with no sweep is a bricked ticket**."*
**Silence.** Keys ship unset. For `refund.platform_support_max_minor` the fail-to-safe rule makes absent =
*"support may approve nothing"* — **safe and loud**. For `refund.org_auto_execute_max_minor`,
`refund.org_dual_control_max_minor` and `refund.request_ttl_hours` **no absent-key rule is stated anywhere** —
see the defect list, item **DF-7**.
**Blocks.** Tier behaviour. Values are runtime (`set_platform_config`); seeds consolidate into `078`.
**Filed at.** MONEY §11 `D-3` + §7.2 + §6.1a · RLS §15.7 `MD-3` + §15 item 4 · RPC §16.3 + §17.1a · AMEND
§14.2-A `OD-03`.
**Recommendation — none on the numbers.** MONEY §11: *"commercial + risk call; the keys ship, the values are
set by an audited `set_platform_config`. **No number is chosen by the `MB-1` pass**"*.

### ODR-12 — The money-role grant-maturity window · `078` seed
**Choice.** How many hours a money-role grant must be old before its holder may act as the second half of a
dual-control pair. The admissible range on record is **24–72 hours**.
**Breaks.** *Too short* — *"The attack becomes 'mint the counterparty, wait until tomorrow' … The control
degrades toward the cool-down it was designed to outrank, which stops nobody willing to wait."* *Too long* —
*"A genuine new hire cannot be the second half of a dual-control pair for their whole first week, so the org
is a **single-money-principal org** for that window and every refund and payout escalates to platform review …
The cost is real, it is operational, and it is paid by the honest case."*
**Silence.** The key ships regardless and fails to *no grant is mature* ⇒ nobody can approve anything.
**SAFE, but it presents as an outage** rather than a missing decision — the RPC spec's interim guidance is to
*"seed the key at the **restrictive** end of the range and record the seed as provisional."*
**Blocks.** The `SoD-1`/`SoD-2` guarantee — the control that makes `O-3`'s ratified SoD collapse survivable.
**Filed at.** RPC §1.1e (`AUTHZ-C1C`, *"THE WINDOW ITSELF IS AN OWNER DECISION, RECORDED HERE AND NOT MADE
HERE (`MD-14`)"*) · RLS §15.7 `MD-14` · record row `C58`.
**Recommendation — yes.** RLS §15.7 `MD-14`: *"**24–72 hours.** Long enough that minting a counterparty cannot
be same-session, short enough that a genuine hire is not blocked past their first day. The **key** ships
regardless and fails to *no grant is mature*; only the **number** is this decision."*

### ODR-13 — `door.*` config visibility: `restricted` or `public`? · `078` seed row
**Choice.** Leave the `door.*` `catalog.platform_config` namespace `restricted`, or move it to `public`.
**Breaks.** *Public* publishes `door.manifest_ttl_interval` and `door.implicit_freeze_offset_interval`, which
*"state **how long a door may operate on stale data** — which is the width of the window in which an offline
duplicate admission is possible"*, and since `AUTHZ-H3` also bounds the life of a bearer door-session token:
*"how long a stolen tablet keeps working"*, readable by a signed-out browser. *Restricted* costs nothing the
corpus can name — *"A client never needs it; the scanner receives its effective window inside the manifest it
is issued."*
**Silence.** `restricted` — the column `DEFAULT` is `restricted`, so the safe class is structural, not
remembered. **SAFE.**
**Blocks.** One seed row in `078`. *"It is isolated — moving it changes nothing else."*
**Filed at.** SCHEMA §13.7 `S-9` + §2.4.1 · RLS §17 `X-17` + §15.7 `MD-17`.
**Recommendation — yes, keep it restricted, with the reversal path named.** SCHEMA §2.4.1: *"**`door.*` is
classified `restricted`, and that is the one genuinely arguable line.** … **If the owner disagrees, this is
the row to move, and moving it changes nothing else."* §2.4.1 also frames its own status: *"**This is an
owner-facing ruling, and it is stated as a recommendation with its reasoning, because it narrows a property
(`public-read`) that RLS §8.4 already asserts.** It is filed for ratification, not applied unilaterally."*

### ODR-14 — Confirm k = 25 and cell floor = 5, and where the constants live · `077` CHECK
**Choice.** Keep 25/5 or raise them (lowering is asked against); **and separately** put them in
`catalog.platform_config` (tunable) or hard-code them in the `CHECK` constraint (rigid).
**Breaks.** *Tunable* — *"a tunable privacy floor is a floor that gets tuned"*, and it dissolves **R2**, the
only rule in the whole privacy set that is an actual database constraint (*"A sub-floor bucket is not merely
hidden — it **cannot physically be stored**"*). *Rigid* — any future change needs a migration.
**Silence.** 25/5, CHECK-enforced. **SAFE.**
**Blocks.** The `CHECK` constant in `077`.
**Filed at.** DEMOG §14 `D-5` + §5.2 + §5.4 · AMEND §14.2-C `OD-17`.
**Recommendation — yes.** DEMOG §5.2: *"**This spec recommends the CHECK constraint** — a tunable privacy
floor is a floor that gets tuned."* AMEND adds *"may be raised, never lowered."*

### ODR-15 — `notify.push_token` as a new table, or additive columns on `public.push_tokens`?
**Choice.** New `notify.push_token` table, or extend the existing `public.push_tokens`.
**Breaks.** *New table* — *"a second token table creates a split-brain during migration."* *Extend* — `C7`
*"literally says 'into their own schema'"*, so extending is a deliberate, recorded deviation from a ratified
correction.
**Silence.** Unresolved; the four token fixes (`revoked_at`, `revoked_reason`,
`provider_receipt_checked_at`, `last_provider_error`) have no home. **UNSAFE** — a revoked push token is the
mechanism by which a mandatory money notice becomes silently undeliverable.
**Blocks.** The token model; `notify.register_push_token` / `revoke_push_token`. Rides `ODR-3`.
**Filed at.** NOTIF §10 `O-N11` + §6.1 extensions table · SCHEMA §13.4 · AMEND §14.2-H `OD-55`.
**Recommendation — yes, and it is the one sub-decision the schema pass did take.** NOTIF §10: *"**Extend
`public.push_tokens`.** A second token table creates a split-brain during migration and C7's eviction is
satisfied either way. Flagged because C7 literally says 'into their own schema'."*

### ODR-16 — How account deletion behaves for an identity holding custody · `079`
**Choice.** **(a) tombstone** — retain the `auth.users` row marked erased, revoke credentials, crypto-shred
PII, keep an opaque dereferenceable uuid; **(b) refuse while custody is live** — deletion is refused, with a
named reason, until every held atom is terminal or transferred; **(c) forced hand-off** — deletion voids or
transfers the remaining atoms through the custody engine first.
**Breaks.** *(a)* *"the row survives deletion. The honest description is 'we keep an opaque identifier, and
nothing else'."* *(b)* *"a fan holding a ticket to next month's show cannot delete today"* — and must be told
why **inside the deletion flow, before the confirm step**. *(c)* *"a privacy action destroys or moves something
the person paid for."* **Inadmissible under all three:** reusing the `019` anonymization sentinel as the new
`current_owner_id` — it would render on the dispute surface as *"Deleted User"* (record `C96`).
**Silence.** **UNSAFE, and total:** every identity column is `ON DELETE RESTRICT` to `auth.users`, so
*"**account deletion as a whole stops working for anyone who has ever held a ticket, the day `079` lands.**"*
**Blocks.** Package `079` — not its authoring, its product behaviour, from the day it applies.
**Filed at.** Record row **`O15`** / `C95` · SCHEMA §5.1 `CUSTODY-DEL-1` + §13.7 `S-19` · CRM §9.2 · DEMOG
§8.2 · DOOR §7.6.
**Recommendation.** **None.** Three forms are stated with their costs; none is preferred.

### ODR-17 — `kernel.door_freeze_override`: move the table to `079`, or take a `SEAM-2` hook? · `079`/`086`
**Choice.** Move the table into `079` (what the schema pass did), or leave it at `086` and have `079` stub
`door_freeze_override_active()` returning false.
**Breaks.** The hook *"does fail safe — a `false` stub means 'no override', so `is_transfer_frozen` returns
**true** and transfers stay blocked — but it buys nothing."* Not moving it leaves forward reference `FR-7`,
because `kernel.lock_ticket` (`079`) rechecks `is_transfer_frozen` under the atom lock.
**Silence.** The table moves to `079`. **SAFE.**
**Blocks.** `079` / `086`.
**Filed at.** SCHEMA §13.5-B.
**Recommendation — yes.** *"moving the table removes the seam instead of papering it. **Recorded so the owner
can take the hook instead if `079`'s blast radius is judged too precious to touch.**"*

### ODR-18 — Does disbursement auto-fire on `close_settlement`, or require an explicit human request? · `085`
**Choice.** `payout-execute` fires from the scheduler on settlement close, **or** money moves only on an
explicit `kernel.request_org_payout` by a human.
**Breaks.** *Auto-fire* — money leaves on a schedule with no human in the loop, and the step-up predicates
(`aal`/`amr`, MONEY §8.3a) **cannot fire for a machine identity**, so the entire money-plane step-up control
is bypassed on the disbursement path. *Human step* — settlement close does not disburse; every payout carries
a manual step.
**Silence.** **UNSAFE ambiguity on a money-out path.** Edge §3.4 supports both readings in one sentence
(*"invoked by an authenticated finance user OR by a scheduler/service principal"*), so an implementer picks.
**Blocks.** `payout-execute`'s auth model (Class A versus a machine-identity path), package `085`; RPC §16.4.
**Filed at.** EDGE §9 reconciliation item 5 + §3.4 · RPC §16.4 · MONEY §8.3(c)/§8.3a.
**Recommendation.** **None** — it is filed as a confirmation request. **Not indexed in the scope amendment's
`OD-` series at all.**

### ODR-19 — What `kernel.payout.status='paid'` asserts · `085`/`087`
**Choice.** `paid` means *"the transfer succeeded and was not reversed"*, written synchronously by the payout
executor; **or** *"the funds reached the payee's bank"*, a `balance_transaction` fan-out from `payout.paid`.
**Breaks.** *"the two differ in what the venue is being told, and one of them is a promise about a bank we do
not observe."* Only `transfer.created` supplies the `stripe_transfer_ref` join key; `payout.paid`/`payout.failed`
describe the **connected account's own bank payout** (`po_…`), which aggregates many transfers and *"is **not
joinable to a single `kernel.payout` row**."*
**Silence.** Three of five `status` labels and `stripe_transfer_ref` have no writer at all: *"A failed transfer
therefore leaves the row reading `submitted` **forever** — nobody retries, nobody is alerted, and dashboard
§14.5's 'Failed payout: pinned, non-dismissible' banner can never fire."* **UNSAFE.**
**Blocks.** `kernel.mark_payout_transfer_state` (`085`) and `venue.on_payout_settled` (stub `085`, body
`087`); the edge spec §4 placeholder.
**Filed at.** Record row **`O16`** / `C92` · SCHEMA §1.9.2 + §13.7 `S-16` · EDGE §4 · VD §14.5.
**Recommendation.** **None on the meaning.** The writers are named either way — *"Both forms are served by the
single RPC above; only the caller and the triggering event change."*

### ODR-20 — Does `venue.set_event_security_config` exist at all? · `078` + `086`
**Choice.** **(a) schedule `catalog.event_security_config`** into `078` — `(event_id, key, value, version,
effective_from)`, append-only per version, `restricted` visibility since it overrides `door.*` — and the
ratified `O4-4` authority stands; **or (b) rule the function out**, as `venue.set_door_open_at` was
(`AUTHZ-R1`), in which case RLS §11.4's `O4-4` EXEC row goes with it and `086` never names it.
**Breaks.** *(a)* one additive table in an already-scheduled package. *(b)* **a ratified `O-4` authority row
keeps its authority and loses its object.** Doing neither and building anyway is what the schema pass refuses:
*"a function scheduled in `086` with nowhere to write is unbuildable regardless of which keys it accepts"*, and
*"inventing the table at build time is exactly what `S-13` refuses."*
**Silence.** `⛔ BLOCKED` — *"`086` must not schedule it while this stands"*, no EXEC row may be written, and
test `T-RPC-DOOR-24` is held. **SAFE (fails closed) and genuinely blocking.**
**Blocks.** `078` (the table), `086` (the function), RLS §11.4's `O4-4` EXEC row, ROLE_MODEL `R-16`.
**Filed at.** SCHEMA §13.7 `S-13` · RPC §20.14 `R-21` + §20.6.6 · RLS §15.7 `MD-18` · ROLE_MODEL §13 `OD-11` +
§11.2 `R-16` + §12 row 15 · record row `D17` · TRACE `G-14`.
**Recommendation.** **None — every document refuses.** ROLE_MODEL `OD-11`: *"**None — recorded, not
decided.**"* SCHEMA: *"the function's existence is not this spec's to decide."*
**Do not conflate with `ODR-81`**, which asks about the *key set*: *"answering `R-11` does not answer this."*

### ODR-21 — The door-session selector: `door_session_id` or `session_ref`? · `086`
**Choice.** The lookup handle is the uuid PK `door_session_id` (the schema's spelling), or a new
`session_ref text UNIQUE NOT NULL` column (the edge spec's spelling).
**Breaks.** Edge §3.9a *"is unimplementable as written: it selects rows by a column the schema does not define
… an implementer following §3.9a writes a `session_ref` that nothing stores."* Adopting `session_ref` costs
one schema column.
**Silence.** Two documents disagree and one is unimplementable. **UNSAFE.**
**Blocks.** Edge §3.9a and package `086`.
**Filed at.** RPC §20.14 `R-19` + §1.1d (`AUTHZ-H3a`) · RLS §17 `X-18` + §15.7 `MD-19` · EDGE §3.9a.
**Recommendation — yes.** RLS §15.7 `MD-19`: *"**`door_session_id`.** The schema owns the table and defines no
`session_ref`; the two designs are otherwise identical, so this is a spelling decision with a one-column
alternative. It is listed because **edge §3.9a is currently written against the other spelling** and one of
the two documents must move."*
**Note.** `R-19`'s second half — the PIN-free `/refresh` route — is **not** part of this choice; it is a
settled safety property (schema §3.10a.4 *"deliberately refused"* it). See defect **DF-12**.

### ODR-22 — `record_scan` under `FOR SHARE`, and whether M2 is signed · `086`
**Choice.** Two coupled door-transaction questions the scope amendment files as one. (i) Must
`venue.record_scan` take the rank-1 session `FOR SHARE` lock? (ii) Build the optional `door-manifest` edge
function that KMS-signs the M2 manifest, or accept TLS-only?
**Breaks.** *(i) no lock* — a scan's recorded `manifest_id` may be a racing one; *"Not needed for the theorem
(scans do not move custody)"*, so this degrades reconciliation evidence, not correctness. *(i) lock* — *"scans
briefly block during open/close (milliseconds, twice a night)."* *(ii) TLS-only* — *"M2's *integrity* then
rests on transport alone while M1's does not."*
**Silence.** No lock; TLS-only. **SAFE for correctness, weaker for evidence and integrity.**
**Blocks.** The door transaction shape; an optional element of `086`. Coupled to `ODR-51` (budget).
**Filed at.** DOOR §16 `OQ-6` and `OQ-7` part (a) · EDGE §3.9b + §5.4.2 · AMEND §14.2-I `OD-60`.
**Recommendation — split.** DOOR `OQ-6`: *"Recommend yes. **Implementer/owner preference.**"* DOOR `OQ-7`:
*"**Recommend building it**; the TLS-only fallback is acceptable for MVP if KMS budget is constrained."* The
scope amendment's `OD-60` records **no** recommendation.

### ODR-23 — Adopt the Layer-0 privilege wall for the export builder? · before `087`
**Choice.** Own `venue.build_export_rows` with a dedicated `crm_export_builder` definer role holding **zero**
grants on the four demographic objects, so an `X-6` violation is a runtime permission error rather than a CI
finding — **or** reject it and let layers 1–3 stand alone. Named non-option: *"`BYPASSRLS` on the role is
**not** an acceptable shortcut — it would restore access to everything and delete the entire benefit."*
**Breaks.** *Adopting without the complete enumerated grant set and the blank-column canary* produces *"a
builder that runs, raises nothing, and emits a **blank contact column on every row** — which reads, to the
operator and to the audit counters alike, as 'nobody consented'. A silent wrong answer, in the one column the
whole document is about."* *Rejecting* leaves `X-6` resting on grep, catalog checks and pgTAP, and *"§10.2's
empty-file-set guard becomes load-bearing rather than merely important."* Adopting also deviates from the
frozen RPC §0 global (`SECURITY DEFINER` owned by `postgres`).
**Silence.** Ambiguous and **UNSAFE** — element 23 sits inside `087`, and a half-adoption is the zero-rows
failure.
**Blocks.** `087`, and hard gate `HG-4`: *"It changes **who owns** `venue.build_export_rows`. Deciding after
authoring means rewriting the function's ownership and its policy set, in the package that also creates the
bucket."*
**Filed at.** CRM §13 `D-2` + §10.1 + §11.3 · RLS §15.7 `MD-2` + §16.10 · AMEND §11 `HG-4`. **It has no
`OD-` id in the scope amendment's index, which the amendment itself notes.**
**Recommendation — yes, conditionally.** CRM §10.1: *"**Recommendation: adopt Layer 0.**"* — qualified: *"**This
cost is part of D-2**, and the zero-rows failure mode is the reason D-2 cannot be answered 'adopt it' without
also adopting the enumeration and the canary."* RLS `MD-2`: *"**Adopt.** The alternative is a `postgres`-owned
function with reach over everything. `BYPASSRLS` is not an acceptable substitute."*

### ODR-24 — Operatorship change: the new operator's CRM starts empty, and who tells them · `087`
**Choice.** Confirm `XO-1a` — a venue changing hands transfers no customer list, no consent and no
`first_seen_at` history — **and decide who tells the incoming operator.**
**Breaks.** *Without `XO-1a`* — *"**Org 2 receives Org 1's customer list**, complete with consent-gated email
for everyone who consented *to Org 1*"*, plus identical `customer_ref` values across the two orgs, which is
*"the defence inverted."* *With it* — *"Org 2 loses the venue's history for its own venue. A new operator sees
an empty CRM on day one and will ask why."* The only alternative named is out of scope: a private commercial
arrangement between two orgs, *"**not** a platform feature, and this spec builds nothing for it."*
**Silence.** `XO-1a` ships; **the "who tells them" limb has no default at all** — the incoming operator
discovers it at go-live.
**Blocks.** `087`.
**Filed at.** CRM §13 `D-12` + §4.4 case (e) + §5.1 (correction `K-14`, `XO-1a`/`XO-2`).
**Recommendation — yes, on the rule; none on the second limb.** CRM: *"That is the correct answer — the
audience belongs to the organization the person transacted with, not to the building — and it is a real
product consequence the incoming operator will contest. **Confirm, and decide who tells them.**"*

### ODR-25 — Export artifact retention: 24 hours or 7 days? · `087` sweep constant
**Choice.** 24 h or 7 d in the `crm-exports` bucket after `ready`.
**Breaks.** *7 days* *"is an operator convenience that multiplies the standing exposure sevenfold"* — the
bucket becomes a week of every venue's customer lists, and the *"the lake is bounded by a 24-hour sweep"*
defence weakens accordingly. *24 h* costs an operator a re-request.
**Silence.** **No default exists** — the sweep needs a literal constant (`expires_at`, `purge_after`, a
`platform_config` seed).
**Blocks.** The sweep constant; `087` element 20.
**Filed at.** CRM §13 `D-6` + §6.6 + §9.2/§9.3 · AMEND §14.2-G `OD-46`.
**Recommendation — yes.** CRM §13: *"**Recommend 24 h.**"* §6.6: *"Extending to 7 days is **owner decision
D-6**, with this document recommending against."*

### ODR-26 — Settlement close: `org_finance`, `venue_finance`, or both? · `087`
**Choice.** Which role may call `kernel.close_settlement`.
**Breaks.** Settlement close **drives payout**, so a venue-grain grant puts payout-triggering authority at
venue level. RLS flags it undecided at §15 item 3 while §9.13 **and** §11 already list `venue_finance` — *"the
spec contradicts itself."*
**Silence.** **UNSAFE.** Both are granted today (§11.1's `kernel.close_settlement` row grants org **and**
venue finance), so silence ratifies the permissive reading of an explicitly open question.
**Blocks.** `close_settlement`'s authority; the settlement package `087`.
**Filed at.** ROLE_MODEL §13 `OD-4` + §5.3 cell `B10` (left `⚠`) · RLS §15 item 3 + §9.13 + §11 · RPC §16 item
4 · AMEND §14.2-A `OD-11`.
**Recommendation.** **None, from any document.** ROLE_MODEL: *"None. Cell B10 left `⚠`."* AMEND: *"none —
O-1/O-3 do not reach it."*

### ODR-27 — Where does the bid ledger live? · `088`
**Choice.** Accept *"native-only auctions are not offered in MVP"* — `create_auction` requires a listing that
mirrors to `public.listings`, and a native-only attempt raises
`precondition_failed('native_only_auction_unsupported')` **at create time, not at bid time** — **or** schedule
the EXT `market.bid` ledger into `088`.
**Breaks.** *Refuse* — a product capability is not offered. *Schedule* — a package change to `088`.
**Silence.** **UNSAFE, and named as such:** *"§16.5, schema §4.2 and schema §4.9 leave it open in three
different words. An implementer facing that silence creates a table no package specifies — and **a bid ledger
invented at build time is a money surface with no review**."*
**Blocks.** `088`. *"**Either way it must be decided before `088` is written.**"*
**Filed at.** RPC §20.14 `R-9` + §20.8.4 (`OPEN DECISION`) + §16.5 + §19 item 16 · SCHEMA §4.2/§4.9 · PLAN §8
`088` · RLS §15 item 6 · TRACE `G-5`. **Not indexed in the scope amendment's `OD-` series.**
**Recommendation — a proposal, explicitly not a ruling.** RPC §19 item 16: *"**The MVP position on the bid
ledger** (§20.8.4 `OPEN DECISION`) is a **proposal, not a ruling** — §16.5, schema §4.2 and schema §4.9 leave
it open in three different words."*

### ODR-28 — `venue.promoter_link.status`, or promoter-grain deactivation only? · `090`
**Choice.** Add `venue.promoter_link.status` (+ `status_changed_at`, `status_changed_by`, CHECK, partial
index, the `PL-1` immutability trigger) — **or** remove the dashboard's per-link status control and rely on
deactivating the whole promoter.
**Breaks.** *No column* — `venue.set_promoter_link_status` (RPC §20.9.4, marked **BLOCKED**), dashboard control
`U-4` and RLS §9.17's grant are *"expressible against nothing"*, and all three workarounds are closed (DELETE
blocked by `ON DELETE RESTRICT` plus the append-only attribution; slug rename blocked by immutability and by
flyers already printed). *Promoter-grain only* — *"it kills every link that promoter holds. 'Retire this one QR
code' and 'stand this promoter down' are not the same operational act."*
**Silence.** The column is added — *"but that is a ruling, not a default."* **SAFE** (a dead UI control is the
worst case in the other direction).
**Blocks.** `090`; dashboard control `U-4`.
**Filed at.** SCHEMA §13.7 `S-10` + §3.17.2 · RPC §20.14 `R-5` + §20.9.4 · RLS §17 `X-13` (schema half) · VD
`U-4`.
**Recommendation — yes, with the reversal stated.** SCHEMA §3.17.2: *"**This pass adds the column**, because
the alternative silently deletes a contracted RPC (§20.9.4) and a dashboard control (`U-4`) that RLS §9.17
already grants authority for … **If the owner prefers the promoter-grain control, the column comes back out
and §20.9.4 plus `U-4` are removed with it** — but that is a ruling, not a default."*

### ODR-29 — Does a typed code beat a link when they name different promoters? · `090`
**Choice.** **Code wins**, with the link recorded in `displaced_promoter_id` — or **link wins** and the code is
a fallback.
**Breaks.** *Link wins* — *"a code would be dead on every device that had ever touched any link — which is
most of them — and the code feature would silently not work in exactly the cases anyone would notice"*, and it
contradicts the owner's own stated requirement *"do not depend on links."* *Code wins* — *"promoter B can farm
promoter A's traffic by broadcasting B's code"*, mitigated by `touch_corroborated=false`,
`displaced_promoter_id` and eligibility rules `E4`–`E6` into *"a **venue policy** problem with full evidence,
not a silent money leak."*
**Silence.** Code wins. **SAFE, and irreversible:** *"Reversing it later is a **breaking change** to
already-frozen attributions."*
**Blocks.** The §2.3 precedence table (`P1`–`P10`), `venue.resolve_order_attribution`, pgTAP group D — package
`090`.
**Filed at.** PROMO §13 `OWNER DECISION 1` + §2.4 + §2.3 row `P2` · AMEND §14.2-F `OD-33`.
**Recommendation — yes.** AMEND `OD-33`: *"**Code wins**, link recorded in `displaced_promoter_id`. Reversing
later is a **breaking change** to frozen attributions."*

### ODR-30 — Commission basis: face subtotal, or gross including fees? · `090`
**Choice.** `basis_minor` = the order's surviving items at `unit_price_minor × quantity` (excluding platform
fees, buyer fees, taxes and tips), or gross-of-fees.
**Breaks.** *Gross* — *"fees are not the org's revenue, and paying a percentage of the platform's own fee would
make the promoter's commission move when the platform reprices."*
**Silence.** Face subtotal. **SAFE — but time-sensitive:** *"**It changes every promoter's effective rate;
deciding it after codes are live means renegotiating terms.**"*
**Blocks.** Terms; `venue.attribution.basis_minor` in `090`.
**Filed at.** PROMO §13 `OWNER DECISION 4` + §6.1/§6.2 · AMEND §14.2-F `OD-36`.
**Recommendation — yes.** AMEND `OD-36`: *"**Face subtotal.** Deciding after codes are live means
renegotiating every promoter's terms."*

### ODR-31 — Do codes need redemption caps or expiry by default? · `090`
**Choice.** No cap with opt-in expiry (`valid_from`/`valid_until` nullable), or a per-code `max_redemptions`
plus expiry-by-default.
**Breaks.** *Cap* — *"A per-code cap is a hot mutable counter on the checkout path"*, and it duplicates
`inventory_batch.release_kind = 'promoter_hold'`: *"two answers in the system for one question — the failure
**C27** exists to prevent."* *Expiry by default* — *"Codes are printed on flyers and live in Instagram bios;
auto-expiry would silently kill live campaigns."*
**Silence.** No cap, opt-in expiry. **SAFE.**
**The trigger that flips the answer, stated by the spec:** *"If 'Jordy has 60 tickets' must be enforced by the
*code*, this file's answer changes and a hot counter enters the checkout path."*
**Blocks.** The `venue.promoter_code` column set — `090`.
**Filed at.** PROMO §13 `OWNER DECISION 5` + §1.1 + §9.6 + §10.6 · AMEND §14.2-F `OD-37`.
**Recommendation — yes.** AMEND `OD-37`: *"No cap, opt-in expiry. Enforcing 'Jordy has 60' via the code puts a
hot counter in the checkout path."*

### ODR-32 — Who bears a post-settlement chargeback on a commissioned sale? · gates the promoter program
**Choice.** **The org**, via a negative `venue.settlement_line` in the next open settlement — or **the
promoter**.
**Breaks.** *Promoter bears it* is **not buildable in Phase 2**: it needs `C29` reserve and `C30` fan-side
liability, both Gate-M. *"Choosing 'promoter bears it' is therefore a decision to **gate the promoter program
on Gate M**, which is a schedule decision."* *Org bears it* — a named, bounded exposure: *"**exposure ≤ Σ
commission on charged-back attributed orders whose settlement closed before the dispute arrived**. At a
nightlife commission of 5–15% of face, that is 5–15% of the org's chargeback rate … It is not zero and this
file does not claim it is."*
**Silence.** The org absorbs. **SAFE and honest; the residual is named.**
**Blocks.** The promoter program's gate. If answered "promoter", it blocks the **entire** program on Gate M.
**Filed at.** PROMO §13 `OWNER DECISION 3` + §5.3 + §5.1 · AMEND §14.2-F `OD-35` · records `C29`/`C30`/`C31`.
**Recommendation — yes.** AMEND `OD-35`: *"**The org**, via a negative settlement line. 'Promoter bears it'
needs C29+C30 and is therefore a decision to **gate the program on Gate M**."* The spec adds a request: that
*"the instant-payout switch be *gated on C29 landing*, not on a feature flag someone can flip."*

### ODR-33 — Promoter portal: web, or in the RN app? · `090` classification
**Choice.** Web, mobile-first responsive, or a new RN surface.
**Breaks.** *RN* — three reasons on record: *"it is a money surface with an audit table; shipping it inside the
consumer app couples promoter releases to App Store review; and promoters are not a subset of app users (an
off-platform affiliate has no app)."* And *"If it becomes RN, it is a new §4 section, not an extension of any
existing one."*
**Silence.** Web. **SAFE.** It also decides reach: *"whether an off-platform affiliate (no app account) can be
served at all."*
**Blocks.** The §15 classification row for `090`; a new RN §4 section if reversed.
**Filed at.** PROMO §13 `OWNER DECISION 7` + §11.1 + §15 · RN §12 item 13 · AMEND §14.2-F `OD-39`.
**Recommendation — yes.** PROMO §11.1: *"`INFERENCE:` **recommend web, mobile-first responsive** — not an RN
surface."*

### ODR-34 — May the subject read their own consent *history*? · `082` (additive)
**Choice.** Current state only (today's `kernel.list_my_org_contact_consents`), or add one definer RPC that
returns the append-only history — *"you allowed this venue on 3 March and withdrew on 9 May."*
**Breaks.** *No* — *"the §5.3 evidence argument stands unimplemented"*, and CRM §5.3 argues at length that *"a
consent record is the person's own evidence in the dispute they are most likely to have."* *Yes* — *"one new
definer RPC, own-`identity_id` only, on `082` … and the `_event` tables' grant set stays empty because the RPC
is a definer — **no RLS posture changes either way.** The cost is one function, not a permission model."*
**Silence.** Deny-all with an empty grant set — the strictest posture. **SAFE**, *"but it is a default this
repair chose by inheritance, not a ruling."*
**Blocks.** Nothing. Would attach to `082`.
**Filed at.** `PHASE_2_PACKAGE_REGISTRY.md` §7.1 `OWNER-DECISION-K2-READ` · CRM §5.3 · record row `D13`.
**Recommendation.** **None.** Both outcomes are costed and neither is preferred.
