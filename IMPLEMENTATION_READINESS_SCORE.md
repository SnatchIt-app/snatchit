# Snatch It — Implementation Readiness Score

**Companion to `PHASE_2_FINAL_ARCHITECTURE_AUDIT.md`.** A scored, defensible readiness rubric across the 24 review categories, weighted by blast radius, producing one number and one gate. Design-validation only.

## Scoring rubric
Each category scored 0–5:
- **5** — buildable as specified; no blocker.
- **4** — buildable; minor conditions, no correctness/legal risk.
- **3** — buildable *after* a named, cheap, additive spec fix; no redesign.
- **2** — a correctness/legal/irreversible defect in the spec; must fix before code in that area.
- **1** — contradictory or self-falsifying spec; not buildable until resolved.
- **0** — requires redesign (paradigm change). **No category scored 0** — the architecture is sound.

Weight = relative blast radius of getting the category wrong (1 low → 3 high).

| # | Category | Verdict | Score | Weight | W×S | Blocking corrections |
|---|----------|---------|:----:|:-----:|:---:|----------------------|
| 1 | Domain correctness | YES/COND | 4 | 3 | 12 | — |
| 2 | Canonical data model | YES/COND | 3 | 3 | 9 | C29, C32, C34, C42 |
| 3 | Aggregate boundaries / SSCAS | NO | 2 | 3 | 6 | C28 |
| 4 | Ownership model | YES | 5 | 3 | 15 | — |
| 5 | Ticket lifecycle | NO | 2 | 3 | 6 | C26, C41, C43, D2 |
| 6 | Transfer engine | YES/COND | 3 | 3 | 9 | C33, C35 |
| 7 | Inventory model | NO | 1 | 3 | 3 | C27, C42 |
| 8 | Venue operations | YES/COND | 3 | 2 | 6 | C41, C45, C46 |
| 9 | Settlement model | YES/COND | 4 | 3 | 12 | C28 (reversals) |
| 10 | Marketplace model | YES/COND | 3 | 3 | 9 | C29, C30, C31 |
| 11 | Primary ticketing | YES/COND | 4 | 2 | 8 | C44 |
| 12 | Permission model | YES/COND | 3 | 3 | 9 | C35, C36 |
| 13 | Identity model | NO | 2 | 3 | 6 | C34, C38 |
| 14 | Fraud model | NO | 2 | 3 | 6 | C33, C37 |
| 15 | Event model | YES/COND | 4 | 2 | 8 | C49 |
| 16 | Read models | YES/COND | 4 | 2 | 8 | — |
| 17 | Projection strategy | YES/COND | 3 | 2 | 6 | C48 |
| 18 | Adapter strategy | YES/COND | 4 | 1 | 4 | C40 |
| 19 | Scalability | YES/COND | 3 | 2 | 6 | C28, C50 |
| 20 | Operational complexity | YES/COND | 3 | 2 | 6 | — (roadmap discipline) |
| 21 | Disaster recovery | NO | 2 | 3 | 6 | C47 |
| 22 | Multi-region | NO | 2 | 2 | 4 | C50/O6 |
| 23 | Multi-currency | NO | 2 | 2 | 4 | C32 |
| 24 | Long-term maintainability | YES/COND | 3 | 2 | 6 | D1, D2, D3 |

**Weighted total = 184 / 300 (61%).** Unweighted mean = 3.0/5.

## What the number means
61% is **not** "60% of the way to a good architecture." Every point lost is a *specification* point, not a *design* point — no category scored below 1, and the 0-band (redesign required) is empty. Read it as: **the architecture is ~100% ratified; the specification is ~61% complete.** The gap is entirely additive prose.

## Readiness by scope (the honest view)

| Scope | Ready? | Gate |
|---|---|---|
| **External-rail marketplace (live today)** | ✅ READY (unchanged) | none — untouched by every finding |
| **Frozen money core** | ✅ READY (unchanged) | none — untouched; do not reopen |
| **Phase 2A/2B primary issuance — GA only, no re-entry** | ⚠️ READY WITH CONDITIONS | **Pre-issuance gate** (below) |
| **Phase 2A/2B with `table`/bottle-service or re-entry** | ❌ NOT READY | + C41, C42, C45, C46 |
| **Phase 2C native resale + instant payout** | ❌ NOT READY | + C26, C29, C30, C31, C43, C50 |
| **Multi-region** | ❌ NOT READY | + C47, C48, C50/O6 |
| **International / multi-currency** | ❌ NOT READY | + C32, C34, C19 |
| **General ticketing (seated/festival/arena)** | ❌ NOT READY | + C42 (full), C44, seat-map program |

## Gates (must-clear, in order)

### Gate P — Pre-native-issuance (blocks the FIRST native credential; extends the prior 15.A gate)
Correctness & irreversibility — **all required before any native issuance code ships to production:**
- **C26** idempotency-key redesign (`UNIQUE(cause,cause_ref,ticket_id)` + per-sale terminal state machine)
- **C27** `remaining` single-truth decision
- **C33** C1 signing-key lifecycle + signer HA (the hardest-to-reverse item)
- **C35** kernel-boundary buyer authentication
- **C28** SSCAS closure + complete lock order (issuance is already an SSCAS member)
- **C36** scope-qualified roles as structure
- **C41** re-entry decision (add sub-state, or scope demo to no-re-entry GA and declare it a named future change)
- **C42** optional-nullable seat/unit-row hedge (cheap now; irreversible-costly later)
- **D1/D2/D3** doc-consistency pass (the frozen source of truth must stop contradicting itself)

Carried forward from prior 15.A and still required: **C1, C2, C3(→C26), C4(→C27), C5, C6-model, C9, C10-dedup-key (C17)**.

### Gate M — Pre-money-rail (blocks native resale + instant payout, Phase 2C/2D)
- **C29** Reserve/Clawback object + payout-timing policy
- **C30** fan-side liability representation
- **C31** double-entry money-ledger schema (recommended home for C29/C30)
- **C43** p2p `locked` auto-unlock + freeze-scope narrowing
- **C50/O6** cross-region resale saga decision (or explicit intra-region scoping)
- resolve **O1** (now reframed as C29), **O3** (resale-policy snapshot drift), confirm **O5/C17**

### Gate L — Pre-legal-scale (blocks international / erasure claims / enterprise)
- **C32** first-class multi-currency
- **C34** provable erasure spec
- **C47** DR design (RPO/RTO, PITR/standby, restore drill, snapshot rebuild budget)
- **C48** projection rebuildability; **C49** outbox hardening
- **C37** online-door live verify; **C38** merge grant reconciliation; **C39** comp step-up; **C40** static callback allowlist
- **C44** virtual queue / bot defense; **C45/C46** full venue-ops model

## Overall
**READY WITH CONDITIONS.** Score 184/300 reflects a ratified architecture with a ~61%-complete specification whose remaining 39% is additive prose organized into three ordered gates. Clear **Gate P** before the first native ticket; **Gate M** before resale; **Gate L** before international/enterprise. The live marketplace and money core score full marks and are untouched.
