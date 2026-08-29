# Writer Parity — Remediation Report (Phase C/D of the convergence pass, 2026-08-29)

Every repair below passed the mechanical-repair rule: one normative owner · exactly one admissible value
from ratified architecture · no product/security behavior chosen · no Phase-2 SQL · no new package · no
production change. **Everything that failed any limb was FILED, not repaired.**

## Repaired — 29 sites/groups across 7 files

**Canonical (`PHASE_2_RPC_FUNCTION_CONTRACTS.md`), 8:** `R-24` TEN→ELEVEN (both sites, plus the missing
sweep added to its own missing-list) · §0.7a six→seven + the `sweep_expired_ticket_atoms` row + the closure
restated over the corrected enumeration · §7 preamble "No other code writes custody"→the enumerated form ·
§8.2 Writes→delegation form (closes X-1's "2 or 3" at **2**) · §17.10 Writes re-routed through
`market.on_door_freeze_engaged` · **§17.10a added** — the two `C110` hooks contracted (transcription of the
ratified row, signatures SEAM-2a-frozen) · §20.0a trigger-exclusion prose repaired to `OR-7` · `R-34`/`R-35`
filed and indexed.

**RLS (`PHASE_2_RLS_PERMISSION_SPEC.md`), 16 Write-RPCs lines + §5 ×13 rows + §7.5 footnote ⁹ + §16.5
closure set + `R-28` (§3.1 exclusion-list removal + §11.3 row) + `R-19` (§16.11a roll-up + `A7` row;
the thirteen original rows still hash-match `dbfe3069…`).**

**Schema (`PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md`), 6:** §1.5 `current_owner_id` "only the transfer
engine"→the three custody paths · §1.5.1's four-writer premise→the eleven · §1.8 owner/writers→the `R-34`
pair · §1.9 payout placeholder annotated as a MISSING CONTRACT, not a writer · §3.12 "+ door_pin path"
removed ×2 and `reconcile_offline_scans` named.

**Door (`PHASE_2_DOOR_LIFECYCLE_SPEC.md`), 1:** the manifest Write-RPCs line gains
`append_door_manifest_delta`. *(The second candidate site re-derived as already correct — counted out.)*

**MONEY ×3 + traceability ×2 (`R-28` completion):** §2.3 row · §8.4 Control 6 · §12 item 8 · the two
`(DEF)` tags. **R-28 and R-19 are now CLOSED.**

**Registry/gate:** fence rewritten to 6 fields (BUILT witness), 82 rows, `kernel.tickets` (the canonical
eleven, `OK`) and `kernel.payment_native` (`MISSING_CONTRACT`) added, `admin_refund` removed from
`venue.order` (`F-3`); checks `H`+`H2` extended; **25/25 negative fixtures** (16 preserved + 9 new).

## D1 — `kernel.sweep_expired_ticket_atoms` / the `kernel.tickets` count

```
CANONICAL COUNT                 11   (re-derived: §0.7a's seven + §17.1–§17.4's four; §12.5 is member 11)
LIVE STALE CLAIMS BEFORE         5   R-24 "CONTRACTS TEN" · R-24 "Six are missing" · §20.14 "10 are
                                     contracted" · §0.7a "six kernel functions" · §0.7a "nothing is added"
                                     (+ the RLS/schema four-writer lists, repaired under RC-2)
LIVE STALE CLAIMS AFTER          0
HISTORICAL RECITATIONS PRESERVED 9+  ODR128 ×3 · owner register ×2 · consequence map ×2 · final report ·
                                     ratification rows (D20/OR-7) — history describing the dispute's terms,
                                     not asserting a live count; untouched by design
```
*The previously reported "18 stale TEN claims / 13 correctable" did not survive re-derivation — most hits
were the unrelated (and correct) "ten predicate helpers". Counted from enumeration, not carried.*

## D2 — `kernel.set_updated_at`

Intended: every MUT table (schema global conventions: *"maintained by the existing `set_updated_at` helper
trigger pattern"*). Scheduled: plan §8 Triggers rows `077 078 081 082 085 087 088 091` ("on the MUT
tables"; `086` builds guards only). Canonical contract: **NONE** — §20.0a's repaired text now requires
registry membership; the contract itself is owed (**class C + B**, filed `R-35`). Registry: carried as a
CATEGORY writer + missing-contract entry. **Attachment uniquely required and not chosen here; nothing built.**

## D3 — `kernel.tickets.updated_at`

**STATUS: MECHANICAL CONTRACT/PLACEMENT OMISSION — not an owner decision.** (A) removal — contradicted by
the schema's own convention and the column's presence; (B) trigger required — **this is the ratified
answer**: schema global conventions require the maintainer wherever `updated_at` exists, and `079` attaches
*"raise_append_only … and nothing else"*; (C) another writer — no contract names `updated_at` as its write;
(D) undecided — no: the rule decides it. **Filed as `R-35`; the plan edit and the trigger are the plan
owner's and Phase-2's respectively. Nothing attached, nothing built.**

## D4 — demographic erasure tombstone (`J-12`)

```
FUNCTION CONTRACT    MISSING — the trigger is required by DEMOGRAPHICS §8.2/§8.5/§10.2/§13 (BEFORE DELETE
                     FOR EACH ROW, SECURITY DEFINER, pinned search_path, value-free upsert, body references
                     no gender column) and has NO NAME and NO contract in the owner document
TRIGGER ATTACHMENT   CONTRADICTED — plan §8 `077`: "identity_demographic carries exactly one trigger — the
                     updated_at maintainer — and nothing else"; demographics §8.2 requires exactly two
PACKAGE PLACEMENT    NOWHERE — the erasure TABLE is 077; the trigger is scheduled by no package
TEST COVERAGE        ABSENT — T-RPC-DEMO-01/-02 cover the demographic table's writer set; NO scheduled test
                     asserts any deletion path yields a tombstone; the two-trigger assertion exists only as
                     requested text inside the demographics spec
```
As written: `clear_my_demographics` succeeds, the account-deletion CASCADE succeeds, **no removal path
writes any tombstone**, and the §8.5 `purge_after` control is dead. **Nothing implemented (hard stop);
`J-12` remains the defect of record, now with all four faces separated.**

## D5 — `kernel.payment_native`

**Why it was outside the gate count:** `RC-1` — derived in `WRITER_OWNER_RULING_CONSEQUENCE_MAP.md`, never
a fence row, so its parity never reached check `H`. **Gate coverage defect: CLOSED** (row present,
`MISSING_CONTRACT`; `H2` guards recurrence). **Architecture defect: OPEN** —
`instrument_fingerprint` has ZERO contracted writers while being the sole mechanism of the promoter
self-deal detector; it fails OPEN, silently, on the fraud path. The writer pair itself is settled at 2
(`R-34`). **No behavior added.**

## Filed, deliberately NOT repaired

The 16 missing contracts (engineering) · the 4 not-built writers (`S-24` + holder-mix pair + the tombstone
trigger) · `E-1` session_version and `E-2` `market.bid` (owner) · `ID-6` (owner — see its analysis) ·
`R-25`/`ODR-38` (resale_state one-writer-pair question, open owner decision, untouched).
