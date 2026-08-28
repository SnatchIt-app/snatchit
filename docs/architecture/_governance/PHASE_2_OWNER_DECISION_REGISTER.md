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
