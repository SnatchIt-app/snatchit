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
