# PHASE-2 ARCHITECTURE FREEZE — THE CANONICAL FREEZE RECORD

**OWNER:** Phase-2 architecture freeze
**SIGNED:** 2026-08-30
**BASELINE SHA:** `06fd5ecccc405f416e8f27591ccbbf709771f8ef`
**TAG:** `phase2-architecture-v2` (annotated, points at the baseline SHA)

> **This record refers TO the frozen SHA. It is committed AFTER it, and is not itself part of the frozen
> architecture baseline.** The frozen corpus is exactly the tree at
> `06fd5ecccc405f416e8f27591ccbbf709771f8ef` — nothing in this file, and no later commit, changes that.

---

## 1. THE OWNER SIGNATURE

> "FREEZE APPROVED — I ratify the Phase-2 architecture corpus at commit
> 06fd5ecccc405f416e8f27591ccbbf709771f8ef
> as the implementation baseline. No normative Phase-2 architecture change may
> occur after this freeze without an explicit post-freeze amendment."

---

## 2. WHAT THE FREEZE MEANS

1. **The architecture investigation phase is CLOSED.** OR-1–OR-25, C26–C137 (gap C119), D1–D35,
   O6–O18, O-1–O-5, RET-1–RET-6 — 184 ratification rows — are the complete decision record. No open
   owner architecture decision remains (`PHASE_2_RATIFICATION_RECORD.md` at the baseline SHA is the
   ledger of record).
2. **Packages `076`–`092` are the frozen Phase-2 implementation sequence.** Package count **17**.
3. **The frozen dependency-edge count is 66**, identical on all four declared surfaces (registry JSON
   `depends_on` · registry §2.1 · plan §2 mermaid · plan §3), acyclic, verified at the baseline SHA with
   zero file modifications during verification.
4. **Normative architecture changes after this freeze require a formal POST-FREEZE AMENDMENT** (§4
   below) carrying an owner signature. No pass, agent, or implementer may make, reopen, or soften a
   normative decision without one.
5. **Implementation fixes that do NOT change normative behavior do not reopen the architecture.**
   Typos in non-normative prose, build tooling, test scaffolding, CI wiring (e.g. the filed four-surface
   DAG parser), and engineering choices the corpus already uniquely determines are implementation work.
6. **Implementation discoveries that contradict the corpus MUST STOP and file a POST-FREEZE
   AMENDMENT.** Building around the contradiction, or building the contradiction, are both defects.
7. **Implementers may not silently reinterpret ambiguity.** If the corpus admits two readings of a
   normative question, that is a discovered defect: stop, file the amendment, cite both readings. The
   corpus's own precedence machinery (`PHASE_2_SUBJECT_MATTER_OWNER_MAP.md`, OR-6/OR-7) resolves
   document conflicts; what it cannot resolve goes to the owner.

## 3. THE VERIFIED BASELINE STATE (re-derived at freeze time, zero edits)

| Surface | State at `06fd5ec` |
|---|---|
| Precedence gate A–H | GREEN (81 writer tables · 290 entries · 175 distinct writers) |
| Writer fence | 81 rows, 81 OK — DIVERGENT 0 · MISSING_CONTRACT 0 · NOT_BUILT 0 |
| Package object parity O0–O5 | GREEN (bootstrap scope; 265 declared objects) |
| Four-surface DAG | 66/66/66/66 identical · acyclic |
| Ratification record | 184 rows, zero duplicate ids (C 111 · D 29 · O 8 · O- 5 · RET 6 · OR 25) |
| Notification family | catalogue 48 · reduced IN set 31 · orphans 0 |
| R2 emitter classification | 34 rows — REQUIRED 6 · BEST-EFFORT 28 · UNCLASSIFIED 0 |
| Deletion machine | BP-1..BP-12 closed over the 57-row inventory; eleven SEAM-2 stubs; cutover ≤ `077` |
| Dispute surface (`R-40`/OR-24) | `kernel.dispute_native` + §20.7.13–§20.7.15 in `088`; SSCAS 15 with rows 9/11 real |
| Cron register | 21 rows, closed both directions |
| OFFLINE-VERIFY-v1 | 4 blocks · 1 distinct body · sha256 `afb5184d58b62da5cb03cb8c4c7923953b4206c52f8afa23dee6403069fe6344` |
| Owner-map | DELETION + DISPUTE subjects registered; 43 subjects |

Accepted residuals (recorded IN the frozen corpus, with their controls named — they are part of the
baseline, not exceptions to it): the mid-episode offline-door dispute window (door §9.2); the exit-less
`pending` refund on a lost dispute (schema §1.10.1); void-path overlay residue (stated non-goal, RPC
§20.7.13 preamble); the direct-PostgREST reservation cap (filed engineering, RPC §20.8.8).

Post-freeze operational gates (by their own ratified text, NOT architecture decisions): N1/N2 gate
go-live; D-6's `BACKUP_RETENTION_VALUE` (OPS VERIFICATION REQUIRED) gates the reaper build; Gate-M
gates native-resale activation, seller disbursement, clawback and the ledger family; the 15.A flag gate
(incl. its `088`-applied + dispute-branch-deployed condition) gates `feature.native_issuance_enabled`.

## 4. POST-FREEZE AMENDMENT PROCEDURE

Any implementation finding requiring a normative change is filed in
`docs/architecture/_governance/POST_FREEZE_AMENDMENTS.md` (created empty by this record; one section
per amendment, ids `PFA-1`, `PFA-2`, …) carrying ALL of:

```
ID:                          PFA-<n>
FROZEN RULE:                 <the exact frozen text, file + §, at 06fd5ec>
IMPLEMENTATION CONFLICT:     <what was discovered>
WHY IMPLEMENTATION CANNOT CONFORM: <the proof, not the preference>
OPTIONS:                     <the admissible resolutions, honestly priced>
RECOMMENDATION:              <one>
PACKAGE IMPACT:              <which of 076–092; scope/object deltas>
DAG IMPACT:                  <edges added/removed; four surfaces re-verified>
SECURITY/MONEY IMPACT:       <RLS/grants/writer-fence/money-path consequences>
OWNER SIGNATURE REQUIRED:    YES/NO  (YES for any normative change; NO only for
                             corrections the frozen corpus already uniquely determines)
```

A signed amendment is then: recorded as a new `OR-`/`C-` row in the ratification record, applied to the
affected documents with the `PFA-` id cited inline, re-verified by the full gate suite, and committed —
the freeze baseline SHA never moves; the amendment trail is the delta. **No architecture file may be
silently edited around a conflict.**

## 5. TAG NOTE (reported, per the freeze instruction's STOP rule)

`phase2-architecture-v1` already existed as a **lightweight** tag at `cc3edba` — the 2026-08-24
pre-implementation closeout of the prior epoch ("BASELINE READY, AUTHORIZE 071"), already pushed to
origin. It was **not moved and not overwritten**. It establishes the versioned
`phase2-architecture-vN` convention; this freeze is tagged as its successor, **`phase2-architecture-v2`**
(annotated, at the baseline SHA).
