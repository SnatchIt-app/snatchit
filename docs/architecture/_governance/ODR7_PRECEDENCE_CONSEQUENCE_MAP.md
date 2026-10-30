# `ODR-7` / `O11` — Precedence Ruling Consequence Map

**Owner ruling `OR-6`, 2026-08-28: HYBRID PRECEDENCE.** Mapping only — no contract was edited to
produce this.

## What the ruling changed, in one table

| form, as ratified `C75` stated it | before | **after `OR-6`** |
|---|---|---|
| **(a) recency** — the later ratified correction governs | one of three candidates | **REJECTED OUTRIGHT.** Never *newest commit / newest markdown / latest edited / higher correction number wins*, unless a ratified authority says so for that exact subject |
| **(b) subject-matter ownership** | *"correct but requiring an owner map the corpus does not yet have"* | **PRIMARY.** The map now exists: `PHASE_2_SUBJECT_MATTER_OWNER_MAP.md`, 39 subjects |
| **(c) remediation-tag precedence** | used once, for `C57`/`C58`, with the caveat that it *"is not ratified as a general rule and must not be cited as one"* | **DEMOTED to a tie-breaker.** Available only where the owner map is genuinely silent; may not override an assigned owner however new or however tagged |
| *(no form)* | an unresolved conflict left the implementer to pick | **RULE 4: FAIL CLOSED.** Registered, failing CI, resolved explicitly. The implementer does not choose |

**History is preserved, not rewritten.** The `D14` pass's single use of form (c) stands as recorded,
including its own caveat. `OR-6` supplies the general rule that pass declined to invent — and does so
with (c) subordinate, which is the opposite of generalising it.

## Where the ruling is recorded

| instrument | what it now says |
|---|---|
| `_governance/PHASE_2_RATIFICATION_RECORD.md` | new row **`OR-6`**, status `RATIFIED — OWNER`; row `C75`'s status cell moved `OPEN-GATED(O11)` → `CLOSED — OWNER RULING`, with its caveat intact |
| `_governance/PHASE_2_OWNER_DECISION_REGISTER.md` | `ODR-7` → `CLOSED — OWNER RULING`, original text retained under a `<details>` marked *do not delete*; status split recomputed to `116 + 4 + 3 + 1 + 3 + 1 = 128`, and the file's own check 5 reproduces it |
| `PHASE_2_SUBJECT_MATTER_OWNER_MAP.md` | **new** — the artifact `C75` said form (b) required |
| `_governance/ODR128_CONTRADICTION_RESOLUTION.md` | **new** — nine contradictions, six resolved, three failing closed |
| `_governance/PRECEDENCE_CI_GATE_SPEC.md` + `scripts/precedence_gate.py` + `ci.yml` | **new** — rule 4 made mechanical in a required check |

## Cascade: three more `OPEN-GATED` rows closed

Recording `ODR-7` surfaced that three ratification rows still carried `OPEN-GATED` status for
decisions the owner had already ruled — `O7` (`ODR-2`, ruled `OR-4`), `O8` (`ODR-3`, ruled `OR-5`) and
`O11` itself. All three status cells are now closed.

**The register's second self-check asserted *"must be 13"* distinct gated decisions. The derived
figure is now 9** — `O6 O9 O10 O12 O13 O14 O15 O16 O18`. The check has been recomputed **with its
derivation written beside it**, because `DF-35` records that this number has gone stale four times and
names the cause: *"no mechanism that fails when these numbers go stale."*

## What is now transcription rather than decision

`ODR-128` was `BLOCKED BY ANOTHER DECISION — ODR-7`. It is unblocked, and **larger than it was
filed**: nine contradictions, not six. One named item was two; two of the same class were missing
entirely. **28 edit sites across 8 files**, of which **17 are pure transcription**, **7 need a new
`C`-row or an explicit discharge**, and **4 are blocked** pending the fail-closed escalations.

**Four intra-document defects were separated out and are NOT `ODR-7`'s to settle** — the ruling's
scope limit is binding. They belong to their own document's owner.

## What the ruling did NOT resolve — and why that is the ruling working

**Three of nine contradictions fail closed**, on two distinct causes:

- **`X-1` and `X-6` — the subject `WRITER` has three declared owners and none defers.** RLS claims
  write authority in the first person; RLS's own binding-inputs section assigns it to the schema
  spec; RLS §11.0 assigns its EXEC rows to `ROLE_MODEL` §5.3. Both sides of the content dispute carry
  ratified tags. **Two independent reviewers disagreed about these two rows, and that disagreement is
  the ambiguity** — resolving it by preferring the more confident reviewer would be the silent pick
  the ruling forbids.
- **`X-8` — the owner map splits one indivisible call contract.** `record_money_denial`'s `EXECUTE`
  grant belongs to one owner and its actor derivation to another, and the two disagree. **Ratified
  `C93` already proved one side unbuildable**: on a `service_role` connection `auth.uid()` is NULL and
  the audit table's `NOT NULL FK` forbids a sentinel, so *"the INSERT cannot satisfy its own
  constraint."* An implementer following it ships a fraud-signal audit function that fails on its
  first call, on the fraud path, silently.

**Each needs one owner act, and neither is large:** for `WRITER`, one clause naming a single owner for
*"which functions write table T"* — or a statement that the schema spec's write-authority column
governs and RLS's lists are its roll-up, the shape `EXEC-DERIVED` already uses for grants. For `X-8`,
either a clause covering the case where a single RPC's grant class and actor derivation are
inseparable, or a record that `C106` binds the RLS and MONEY sites as a discharge.

## One thing the gate caught on its first run against real inputs

The contradiction pass resolved `X-4` by the **rule-2 fallback**, reasoning that the owner map was
*"silent on function return types"*. **The gate rejected it** — `RPC-SIG` covers return types with
`CORRECTION_FALLBACK=NO`, so the fallback was not available. The correct resolution is by **owner**
under a different subject: the object is a SEAM-2 hook, whose signature and return type are frozen at
the stub by ratified **SEAM-2a**, and `SEAM-RULE` has a designated owner.

**The result: zero uses of the rule-2 fallback across all nine contradictions.** The owner map covered
every subject that resolved — which is the outcome `C75` predicted a real map would produce, and
which nobody could have asserted before the map existed.

## Standing consequences

- **`ARCHITECTURE_FREEZE.md` Rule 3 is stale.** It still carries the pre-ruling text — *"until it is
  made, the standing obligation remains `SPEC_FOUNDATION` §0's: surface the conflict, do not pick a
  side."* That obligation has been superseded. Not corrected in this pass, because the freeze is a
  covered document and editing it is its own act.
- **`SPEC_FOUNDATION` §0's rule is not wrong, it is now insufficient.** *"Surface the conflict; do not
  silently pick a side"* remains true, and `OR-6` adds the missing half: what to do once it is
  surfaced.
- **`ODR-1` is unaffected by this ruling** and remains NOT READY for reasons of its own.
