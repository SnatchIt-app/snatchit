# CTO Decision Memo — Snatch It Phase 2 Architecture

**From:** Acting CTO / Staff Engineer (Chair), Phase 2C independent architecture review board
**Re:** Go/no-go on beginning Phase 2 implementation
**Basis:** six independent principal reviewers (ten mandates), 24 categories, all findings verified against the frozen documents. Full detail in `PHASE_2_FINAL_ARCHITECTURE_AUDIT.md`, `IMPLEMENTATION_READINESS_SCORE.md`, `ARCHITECTURAL_RISK_REGISTER.md`.

---

## VERDICT

# READY WITH CONDITIONS

The architecture is ratified. Begin implementation. Do not begin native ticket issuance until **Gate P** below is closed; do not begin native resale until **Gate M**; do not go international/enterprise until **Gate L**. The live external-rail marketplace and the frozen money core are untouched and keep shipping.

Every blocking condition is an **additive prose correction** to the design documents — not a redesign, not code. No reviewer, on any mandate, found a defect requiring a paradigm change, and all six independently rejected event-sourced-everything, microservices-now, and external-first/white-label in favor of the current design. The one load-bearing uncertainty is commercial (will Miami venues cede primary issuance), not architectural.

---

## Blocking conditions

### Gate P — before the FIRST native ticket is issued (correctness + irreversible)
1. **C26** — Redesign the double-write guard: `UNIQUE(cause, cause_ref, ticket_id)` **plus** a per-`market_sale` terminal state machine enforcing compensate-XOR-complete under one lock. *(The current `UNIQUE(cause,cause_ref)` is provably wrong for one-cause→many-ticket flows; the "double-transfer impossible" guarantee does not hold as written.)*
2. **C27** — Decide the single source of truth for `remaining` (locked counter authoritative, ledger derived — or vice versa). *(Currently defined both ways; mutually exclusive.)*
3. **C33** — Specify C1 signing-key lifecycle: per-event/venue scope, KMS/HSM custody, rotation, compromise runbook, signer HA/throughput, door public-key distribution. *(Hardest-to-reverse decision in the system; a global key is an existential single point.)*
4. **C35** — Kernel authorizes the buyer principal itself at the market→kernel seam; never trust a market-supplied id.
5. **C28** — Close the SSCAS (add cancellation cascade, dispute reversal, C25 compensation, auction deposit-release, group-buy, wallet checkout) and complete the lock order over every locked class + ascending-batch-id. *(Issuance is already an SSCAS member.)*
6. **C36** — Make scope-qualified roles structural (typed scope/distinct labels), not a lint convention.
7. **C41** — Resolve terminal `scanned` vs re-entry: add a re-entry sub-state, or explicitly scope the first venue to no-re-entry GA and declare re-entry a named future change.
8. **C42** — Add the optional-nullable seat/unit-row hedge now (cheap while prose; the unit-rows in C4/C22 already are seat atoms). Prevents the seat-atom rework from becoming a platform-wide migration.
9. **D1/D2/D3** — Doc-consistency pass so the frozen source of truth stops contradicting itself (stale `refunded` diagrams, "one cross-aggregate transaction" line, divergent cause-code enum).
   *(Plus the prior 15.A items still standing: C1, C2, C5, C6-model, C9, C17.)*

### Gate M — before native resale + instant payout (Phase 2C/2D)
10. **C29** — First-class Reserve/Clawback object + payout-timing policy (this is what O1 actually is).
11. **C30** — Represent fan-side chargeback/clawback liability.
12. **C31** — Adopt an additive **double-entry money-ledger schema** beside the frozen Stripe core (the recommended home for C29/C30 and the fix for unbalanced royalty/rounding). Keep the ownership log for custody.
13. **C43** — Hard auto-unlock on p2p `locked` + exempt cancel-to-self from the C6 freeze + narrow the freeze to per-open-manifest-ticket.
14. **C50 / O6** — Decide cross-region native resale: saga/escrow, or explicitly intra-region only. *(C8×C14 leave it undefined today.)*
15. Resolve **O3** (resale-policy snapshot drift); confirm **C17/O5** (cross-rail dedup) enforced.

### Gate L — before international / erasure claims / enterprise
16. **C32** first-class multi-currency · **C34** provable erasure spec · **C47** DR design (RPO/RTO, PITR/standby, restore drill, snapshot rebuild budget) · **C48** projection rebuildability · **C49** outbox hardening · **C37** online-door live verify · **C38** merge grant reconciliation · **C39** comp step-up · **C40** static callback allowlist · **C44** virtual queue/bot defense · **C45/C46** full venue-ops model.

---

## Why READY WITH CONDITIONS and not NOT READY
NOT READY would mean "expect a fundamental redesign." Six independent reviewers concluded the opposite: the ticket-atom, append-only ownership log, single transfer engine, credential-as-delivery, two-rail honesty, modular monolith, and frozen money core all survived every attack; the ownership model earned an outright YES. The failures are specification completeness in five clusters — money-reversal, key lifecycle, erasure, SSCAS closure, and region/DR/nightlife-ops — every one fixable in prose, most of them cheaper now than at any later point, and three (key, re-entry, seat) irreversible if shipped wrong. That is the textbook definition of READY WITH CONDITIONS.

## Why not READY (unconditional)
Because Gate P contains genuine correctness defects (R1 the double-write guard, R2 the `remaining` contradiction) and one irreversible security decision (R3 the signing key) that must not reach production unresolved. Shipping native issuance on today's spec would bake in a wrong idempotency guarantee and an unscoped key — the two most expensive mistakes to unwind.

## Recommended first action
Convene a short **ratification pass** that folds C26–C50 / O6 / D1–D3 into the two constitution documents as additive corrections (design-only, no code), then start Phase 2.0 foundation work in parallel. Gate P is the critical path to the fundraise demo; it is weeks of prose and hardening, not a quarter of rearchitecture — but C33 (key management) and C42 (seat hedge) should start immediately because they are the irreversible ones.

**Decision: proceed to implementation under the three gates above.**
