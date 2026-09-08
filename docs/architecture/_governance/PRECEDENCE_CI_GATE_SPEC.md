# Precedence CI Gate — specification

**Enforces owner ruling `OR-6` (`ODR-7` / `O11`).** Rule 4 is not advice: *"the contradiction must
**fail CI / readiness**, be registered, and be resolved explicitly."* A rule that lives only in prose
is the defect class this corpus keeps re-discovering — ratified `C53` records four editable copies of
one predicate, one corrected and three not, with the stale copy being the one a scanner SDK
implements. So the rule gets a gate.

## Deliberately small

**One parseable map, one script, one existing required CI job.** No new workflow, no new required
check, no governance framework. It verifies six mechanical properties plus a propagation check, and
**refuses to guess about anything else** — a gate that reasons about prose would be a gate nobody
could trust.

| | |
|---|---|
| map | `docs/architecture/PHASE_2_SUBJECT_MATTER_OWNER_MAP.md` — fenced ` ```owner-map ` block |
| contradictions | `_governance/ODR128_CONTRADICTION_RESOLUTION.md` — fenced ` ```contradictions ` block |
| propagation | `_governance/PHASE_2_RATIFICATION_RECORD.md` — optional fenced ` ```propagation ` block |
| script | `scripts/precedence_gate.py` |
| host | `ci.yml` job **`quality`** (`Typecheck / Lint / Unit tests`) — already a **required** check, already the host of the `OFFLINE-VERIFY-v1` byte-identity gate, and it runs **before `npm ci`** so a broken lockfile cannot take the governance gates down with it |

## The seven checks

| | check | what it catches |
|---|---|---|
| **A** | every registered subject has exactly one normative owner | a duplicated `SUBJECT_ID`; an owner or derived path that does not exist (a typo fails CI) |
| **B** | every contradiction row names a subject that exists in the map | a contradiction resolved against a subject nobody registered |
| **C** | no restatement document also claims ownership of the same subject | a document listed as both owner and derived — the shape that makes precedence circular |
| **D** | the ratified-correction fallback is cited ONLY where the map says the owner is silent | **`OR-6` rule 2**: a correction may not override an assigned owner however new or however tagged |
| **E** | recency is never used as a resolver, anywhere in the corpus | **`OR-6` rule 3.** Greps every `docs/architecture/**` markdown for resolver phrasings — *"newest commit wins"*, *"newest markdown wins"*, *"latest edited … wins"*, *"most recently edited wins"*, *"higher correction number wins"*, *"the later document wins"*, *"recency governs"* — with an allowlist only for the documents that **prohibit** them |
| **F** | ambiguous or unresolved contradictions fail closed | **`OR-6` rule 4.** `UNRESOLVED` fails; an `OWNER` resolution on an `AMBIGUOUS` subject fails; a resolved row naming no transcription site fails; a site path that does not exist fails |
| **G** | a ratified correction declaring N propagation sites is detectable in all N | the correction-propagation check: *"if a ratified correction row names N affected documents, the correction must be detectable in all N or the gate fails"* |

**E is the one worth dwelling on.** Rule 3 is the easiest of the four to violate by accident, because
"the newer document is probably right" is a reasonable-sounding instinct. It is now a build failure.

## Anti-vacuity — the control that keeps the gate honest

`--selftest` runs **first**, before the real check. It drives **seven deliberately-broken fixtures**
through the checkers and **fails the build if any of them PASSES**:

```
precedence gate selftest OK: 7/7 negative fixtures correctly failed
```

duplicate subject id · contradiction naming an unregistered subject · owner also listed as
restatement · fallback used where an owner exists · unresolved contradiction · `OWNER` resolution on
an `AMBIGUOUS` subject · correction not detectable at a declared site.

**A parser that silently matches nothing cannot go green.** That is exactly how a gate like this
normally dies — the fenced block gets renamed, the regex stops matching, and the check reports
success forever. The selftest makes that failure loud.

## Exit codes — it fails closed on its own inputs too

| code | meaning |
|---|---|
| `0` | all seven hold |
| `1` | a violation of `OR-6` |
| `2` | **the gate could not run** — map missing, block missing, unparseable row, bad field count. **Also a failure, on purpose.** A governance gate that passes when it cannot read its own input is worse than no gate. |

## Current state, and why it is red

```
subjects registered : 39
ambiguous subjects  :  4   (WRITER, PAY-STATE, RESALE-WRITER, EDGE-PKG)
contradiction rows  :  9

PRECEDENCE GATE FAILED — 3 violation(s):
  X-1 is UNRESOLVED  ·  X-6 is UNRESOLVED  ·  X-8 is UNRESOLVED
```

**This is the gate working, not the gate broken.** `OR-6` rule 4 requires an unresolved same-tier
contradiction to fail CI until it is resolved explicitly. Three are unresolved: `X-1` and `X-6`
because `WRITER` has three declared owners and none defers, and `X-8` because the owner map splits one
indivisible call contract across two owners who disagree.

**The gate will stay red until the owner acts.** That is the ruling, and the red is the mechanism by
which "the implementer does not choose" becomes true rather than merely stated. It must not be
silenced by editing a row to `OWNER` against an owner the corpus has not designated.

## What the gate deliberately does NOT check

- **Whether a restatement's prose actually agrees with its owner's prose.** That is a semantic
  judgement; a script that claimed to do it would be lying. What it checks is the structural
  precondition — that the ownership relation is well-formed, acyclic in the owner/derived sense, and
  that no contradiction is resolved against a subject with no owner.
- **Intra-document contradictions.** `OR-6`'s scope limit is binding: two sections of the same
  normative document contradicting each other is a mechanical defect, not a precedence question. Four
  are recorded in `ODR128_CONTRADICTION_RESOLUTION.md` and belong to their own document's owner.
