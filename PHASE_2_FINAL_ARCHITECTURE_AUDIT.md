# Snatch It — Phase 2 Final Architecture Audit

**Final architectural due diligence before implementation. Design-validation only — no code, SQL, migrations, or UI produced or authorized by this document.** Its job was not to approve the architecture; it was to try to kill it.

**Artifacts under review (treated as frozen):** `SNATCH_IT_DOMAIN_ARCHITECTURE.md` (constitution; A1–A11, C1–C11), `SNATCH_IT_CANONICAL_DATA_MODEL.md` (data constitution; §0–§15, C12–C25), `PHASE_2_ARCHITECTURE_REVIEW.md` (prior multi-persona critique; risk register 15.A–15.F; O1–O5), `PHASE_2_IMPLEMENTATION_ROADMAP.md`.

**Method.** Ten principal mandates across a six-reviewer independent board, each reviewer working blind to the others, each instructed to find defects, not praise. Findings were then reconciled by the Chair (Staff Engineer), cross-checked against the frozen documents (claims verified against exact lines), and consolidated into the risk register and the readiness score. Companion deliverables: `IMPLEMENTATION_READINESS_SCORE.md`, `ARCHITECTURAL_RISK_REGISTER.md`, `CTO_DECISION_MEMO.md`.

---

## 0. Headline verdict

**READY WITH CONDITIONS.** The foundational architecture is ratified — no reviewer, on any of the ten mandates, found a defect requiring a paradigm change, and all six independently rejected every alternative architecture in favor of the current one. **The bet is right. The current *specification* is not yet buildable.** It carries a defined, entirely additive correction set (C26–C50, O6, D1–D3 below) that must land — in prose — before the relevant code is written. Several corrections block *any* native ticket issuance; native resale, multi-region, and multi-currency are gated further out. The live external-rail marketplace and the frozen money core are untouched by every finding and continue shipping throughout.

This is the exact success criterion the review was asked to test: **an engineering organization can begin implementation without expecting a fundamental redesign** — provided it treats the conditions below as hard gates, not backlog.

---

## 1. The board

| Reviewer (independent) | Mandate | Domain verdict |
|---|---|---|
| Principal Distributed Systems + Scalability + Infrastructure | correctness under concurrency/partition; SSCAS; events; read models/projections; scale; ops; DR; multi-region | **NOT READY** |
| Principal Database Architect | canonical model; aggregate boundaries; lifecycle; inventory; read models; projections; maintainability | **NOT READY** |
| Principal Security + Identity + Fraud | permission; identity; fraud; transfer/adapter security | **NOT READY** |
| Principal Payments + Settlement | settlement; marketplace money; multi-currency; reserve/clawback | **NOT READY** (native resale money rail) |
| Principal Ticketing Systems | ownership; lifecycle; transfer engine; primary ticketing | **READY WITH CONDITIONS** (Miami GA+tables); NOT READY as a general ticketing core |
| Principal Product + Venue Operations + Adapter | venue ops; marketplace product; adapters; maintainability | **READY WITH CONDITIONS** (fundraise demo) |
| Staff Engineer (Chair) | synthesis; alternative architectures; scale; regret; disagreement resolution | issues the consolidated verdict above |

**Unanimity that matters:** 6/6 "keep the architecture"; 6/6 "every blocker is a specification defect, not a paradigm error"; 6/6 rejected event-sourced-everything, microservices-now, and external-first/white-label as inferior for this problem. The split (4 NOT READY vs 2 READY-WITH-CONDITIONS) is a split on *how much spec must land before code*, not on the design.

---

## 2. Per-category verdicts (all 24)

Verdict ∈ {**YES**, **YES/COND** (yes with conditions), **NO**}. "NO" here means *not buildable as currently specified* — in every case remediable in prose; none implies redesign.

| # | Category | Verdict | Why (grounded) |
|---|----------|---------|----------------|
| 1 | Domain correctness | YES/COND | Online single-object invariants are money-grade; partition-time (offline door, cross-region) is reconcile-not-prevent and depends on C6/C23 shipping *with* scanning. |
| 2 | Canonical data model | YES/COND | Right objects, genuinely technology-agnostic — but the "additive-forever" claim is self-falsified (seat atom ships as `table` in 2A) and Reserve/FX/PII-vault objects are missing. |
| 3 | Aggregate boundaries / SSCAS | **NO** | The "closed set of 9" is not closed (omits event-cancellation, dispute-reversal, C25 compensation, auction deposit-release, group-buy, wallet checkout); lock order covers 5 tiers but not all locked classes → no deadlock-freedom proof; §12 "one seam" contradicts C12's nine. |
| 4 | Ownership model | **YES** | Ledger-as-truth + single-writer + derived-head is correct and complete; no two online owners possible; lot lock-order defined. The strongest part of the system. (2 minor conditions: O(1) tail read; p2p-`locked` overlay bound — see cat 5/6.) |
| 5 | Ticket lifecycle | **NO** | Abolished `refunded` terminal still drawn in DA §3.1 diagrams; `locked`-from-pending-p2p has no hard auto-unlock and deadlocks with the C6 freeze; terminal `scanned` forecloses re-entry; C25 auto-refund has no funding object. |
| 6 | Transfer engine | YES/COND | Single-writer is a correctness win and *not* an issuance-spike ceiling (per-atom locks parallelize). Real single points: the credential **signer** (unmodeled HA/throughput) and kernel-boundary buyer auth. |
| 7 | Inventory model | **NO** | Guard beats the old tautology online, but `remaining` is defined two mutually-exclusive ways (ledger-head vs mutable counter); sharded counter doesn't reconcile (tail-stranding); unit-rows ARE the forbidden seat atom. |
| 8 | Venue operations | YES/COND | Sell-and-scan spine is real (sessions, tiers, batches, comps, PINs, promoter holds, door-batch). Missing: re-entry/occupancy, table minimum *balance*, fire-code occupancy, cash box-office. NO for a bottle-service-driven room on night one. |
| 9 | Settlement model | YES/COND | Ticket-history firewall structurally enforced; forward close→payout idempotent. Conditions: "carry to next payout" strands for dormant orgs; compensating/dispute money flows not enumerated; 3-way-split rounding residual unassigned. |
| 10 | Marketplace model | YES/COND | Two-rail honesty and A10 mode-set are genuine; C8 atomicity is unbreakable. But resale money **economics** are NOT READY: instant payout + no reserve = unrecoverable clawback; royalty is a one-sided (unbalanced) credit. |
| 11 | Primary ticketing | YES/COND | Competitive-to-superior for GA nightlife; structurally behind for seated/festival/arena/bot-contested on-sales (no virtual queue). |
| 12 | Permission model | YES/COND | Capability-from-relationships, C2/C9, audited admin plane are right. But scope-qualified roles are enforced by lint convention, not structure; stale-JWT recheck is a hand-curated allowlist; kernel buyer-auth at the seam is unpinned. |
| 13 | Identity model | **NO** | Crypto-shred erasure (C15) is a slogan, not a spec (no key lifecycle; backups defeat it; PII sinks uncovered) → erasure not provable; merge grant-reconciliation unspecified = privilege-merge vector. |
| 14 | Fraud model | **NO** | C1 correctly kills the door forgery oracle, but the *signing key* is unspecified (likely one global key = existential compromise); offline window honestly *shrunk, not closed*; "dispute-free by construction" overstated. |
| 15 | Event model | YES/COND | Envelope (C12 seq/causation/correlation + set-based consumers) is future-proof; single outbox+cron drainer is a SPOF with head-of-line blocking. |
| 16 | Read models | YES/COND | Strong-at-decision-point rule is the right call; C14 cross-region "my tickets" scatter-gather is an availability cliff; async money projections diverge with no reconciler. |
| 17 | Projection strategy | YES/COND | Custody log is a true SSOT; but cross-aggregate settlement rebuild is non-deterministic (per-aggregate sequence only); `credential_version` not pinned to the log; ephemeral-event projections not rebuildable post-compaction. |
| 18 | Adapter strategy | YES/COND | ACL boundary is genuine and kernel-pure. Usefulness oversold: against TM SafeTix / AXS Mobile ID the transfer/validation ports degrade to today's manual flow; `validation_callback` allowlist owner unspecified. |
| 19 | Scalability | YES/COND | Honest hot-row analysis; single-writer is per-ticket (not a global ceiling); residual: outbox/cron, sharded-counter reconciliation, 8/9 SSCAS members without a sharding story. |
| 20 | Operational complexity | YES/COND (borderline NO) | Buildable via MVP-first roadmap, but ~9 reconciliation loops over money + custody + PII with bus-factor 1. |
| 21 | Disaster recovery | **NO** | No RPO/RTO anywhere; "replayable from logs" is intra-DB integrity, not substrate recovery (ledger + derived head share one failure domain). Asserted, not designed. |
| 22 | Multi-region | **NO** | C14 honest on reads but hand-waves write-locality on the custody/money path; C8×C14 make cross-region native resale undefined. |
| 23 | Multi-currency | **NO** | C13 types new objects, but the frozen USD-integer-cents money-in boundary has no currency home; FX timing, per-country payout currency, rounding bearer unmodeled. "Additive not redesign" is false at the frozen boundary. |
| 24 | Long-term maintainability | YES/COND | Genuine guardrail, honest on order — but additive/deprecate discipline is *already failing inside one review cycle*: body contradicts amendments (D2), enums diverge across docs (D3), and CDM §2 line 262 contradicts line 251 (D1). |

**Tally:** YES 1 · YES/COND 15 · NO 8. Every NO is a prose-remediable specification defect.

---

## 3. What the board would refuse to build until fixed (ranked, cross-reviewer consolidation)

Severity: 🛑 Critical (correctness/irreversible/legal) · 🔴 High · 🟠 Medium.

1. 🛑 **C3 `UNIQUE(cause,cause_ref)` is wrong as written** (F1/NEW-3). Issuance mints *K atoms* under one cause_ref and refund-void voids *K tickets* under one cause_ref → the literal constraint rejects rows 2..K; scoped per-ticket it then fails to block re-void across two refund objects. The flagship "double-transfer physically impossible" guarantee is unproven. **Refuse all issuance/transfer code until the idempotency key is redesigned** (→ C26).
2. 🛑 **`remaining` has two contradictory definitions** (F2): ledger-derived head (CDM §1.3) vs locked mutable CHECK counter (C4). One must be authoritative, the other derived. **Refuse inventory code until decided** (→ C27).
3. 🛑 **C1 signing-key lifecycle is unspecified and irreversible once minted** (F16): no custody/KMS/HSM, scope, rotation, or compromise runbook; a global key compromise forges the entire population and offline doors accept it. The signer is also an unmodeled HA/throughput single point on the credential hot path. **Refuse the first native credential until keyed** (→ C33). *This is the single hardest-to-reverse decision in the system.*
4. 🛑 **No Reserve/Clawback object; fan-side liability unrepresentable** (F11/F12): instant payout + O1 cancellation + C25 auto-refund have no funding source, and a withdrawn fan-seller's chargeback has no ledger home. **Refuse native resale + instant payout until modeled** (→ C29/C30, ideally via C31).
5. 🛑 **C15 crypto-shred erasure is unsound as specified** (F17): no per-identity DEK lifecycle, backups retain decryptable ciphertext, PII sinks (search, notifications, name-on-ticket, ID media, Stripe) and the re-identifiable retained event graph are uncovered. **Legal exposure. Refuse to claim GDPR/CCPA erasure until spec'd** (→ C34).
6. 🔴 **SSCAS is not closed and the lock order is incomplete** (F4/F5): omits event-cancellation, dispute-reversal, C25 compensation, auction deposit-release, group-buy, wallet checkout; unplaced locked classes mean no deadlock-freedom proof. **Refuse multi-aggregate flows until enumerated + fully ordered** (→ C28).
7. 🔴 **C8 × C14 make cross-region native resale undefined** (F7): the differentiator rail has no cross-region custody transaction. **Refuse multi-region native resale until modeled as a saga/escrow, or scope native resale intra-region explicitly** (→ C50/O6).
8. 🔴 **Kernel trusts market-supplied buyer id at the C8 seam** (F18): the market_sale buyer is not owner/p2p-recipient/admin, so C2 doesn't cover it — the `p_user_id`-trust anti-pattern at the context boundary. **Refuse the native-sale path until the kernel authorizes the buyer itself** (→ C35).
9. 🔴 **DR is asserted, not designed** (F8): no RPO/RTO; ledger + head share one failure domain. **Refuse to call the system "recoverable" until PITR/standby/restore-drill + snapshot rebuild budget exist** (→ C47).
10. 🔴 **Terminal `scanned` + A3 forecloses re-entry** (F24): core to nightlife, traded away without flagging; an A3-level latent redesign. **Decide now** (→ C41).
11. 🔴 **Seat atom (`table`) is assigned seating on scalar capacity on the 2A critical path** (F25): and unit-row materialization (C4/C22) already *is* the seat atom H6 forbids. **Hedge with an optional-nullable seat/unit-row layer now** (→ C42).
12. 🔴 **Multi-currency has no home at the frozen money-in boundary** (F13). **Refuse international until currency is first-class on every money object** (→ C32).
13. 🟠 **p2p `locked` overlay deadlocks with the C6 freeze** (F26); **table minimum-balance settles off-platform** (F29); **online-door invalidation freshness ambiguous** (F20); **role scope is convention not structure** (F19); plus the doc-consistency defects D1–D3.

---

## 4. Consolidated new findings (not already in C1–C25 / O1–O5)

These are the review's yield — defects the existing corrections do **not** cover. Each is proposed as an additive correction (C26+) or open question (O6), to be ratified in a subsequent, separately-approved editing pass (this document does not modify the frozen constitution).

| New ID | Finding | Source(s) | Proposed remedy |
|--------|---------|-----------|-----------------|
| **C26** | `UNIQUE(cause,cause_ref)` breaks on one-cause→many-tickets and doesn't block cross-object re-void | DB #1, Payments NEW-3 | Idempotency key `= UNIQUE(cause, cause_ref, ticket_id)` **plus** a per-`market_sale` terminal state machine enforcing compensate-XOR-complete under one lock |
| **C27** | `remaining` defined as both ledger-head and mutable counter | DB #2 | Pick the locked counter as authoritative operational truth; ledger movements are audit/reconcile only (or the reverse) — one is explicitly derived |
| **C28** | SSCAS not closed; lock order incomplete; §12 contradicts C12 | Payments NEW-1/2, DS N1/N2/N6, DB | Enumerate all synchronous multi-aggregate flows incl. reversals + cancellation cascade; place every locked class in the order; add ascending-batch-id; reconcile §12 prose to C12 |
| **C29** | Reserve/Clawback is named nowhere as an object; O1 is a missing object, not a question | Payments #1, DB #5, Product #4 | First-class Reserve/receivable object + payout-timing policy gating instant payout |
| **C30** | Fan-side chargeback/clawback liability unrepresentable | Payments #2 | Model fan liability (receivable, or Wallet-MVP negative balance) |
| **C31** | (Strong rec) money plane lacks a balancing structure | Payments alt-arch, DB alt-arch | Additive **double-entry money-ledger schema** beside the frozen Stripe core — resolves C29, C30, and split/rounding balancing structurally; keep the custody log separate (custody is not a balance problem) |
| **C32** | Multi-currency not first-class at the frozen money-in boundary | Payments #5 | Currency attribute on every money object; FX capture-vs-payout timing; per-country payout currency; named rounding bearer |
| **C33** | C1 signing-key lifecycle + signer HA unspecified | Security #1, Ticketing signer, Product | Per-event/venue-scoped keys; KMS/HSM custody; rotation + compromise runbook; signer throughput/HA + public-key distribution to doors |
| **C34** | C15 erasure unsound/unprovable | Security #2, DB #6 | Per-identity DEK lifecycle incl. backup destruction; PII-sink inventory + purge; retained-graph re-identification mitigation; reconcile with 7-yr financial retention |
| **C35** | Kernel trusts market-supplied buyer id at C8 seam | Security NEW-1 | Kernel authorizes the buyer principal itself; never trust a context-supplied identity |
| **C36** | Scope-qualified roles are lint convention, not structure | Security #3 | Typed scope / distinct labels so org≠venue role is structurally impossible |
| **C37** | Online-door invalidation freshness ambiguous | Security NEW-2 | Live per-scan kernel read for online doors; drop "dispute-free by construction" claim |
| **C38** | Identity-merge grant reconciliation unspecified; trigger not dual-controlled | Security NEW-3 | Define grant union rules; put the merge trigger under dual-control |
| **C39** | Comp/guest-list issuance un-stepped-up insider fraud | Security | Add to C9 live-recheck + §7.5 step-up |
| **C40** | `validation_callback` allowlist owner unspecified | Security, Product | Static platform-controlled allowlist; CI-assert the adapter REVOKE |
| **C41** | Terminal `scanned` + A3 forecloses re-entry | Ticketing #1, Product #1 | Add a re-entry sub-state, or explicitly scope the demo to no-re-entry GA and declare re-entry a named future change (like H6) |
| **C42** | Seat-atom un-hedged; unit-rows already are the seat atom; `table` is seated-on-scalar in 2A | Ticketing #2/#4, DB #3/#4, Product | Introduce an optional-nullable seat/unit-row layer now (additive), reconciled with C4/C22, hedging H6 as currency/region were hedged |
| **C43** | p2p `locked` overlay unbounded + deadlocks C6 freeze; freeze scope too coarse | Ticketing #3/#6 | C25-style hard auto-unlock on `locked`; exempt cancel-to-self from the freeze; narrow freeze to per-open-manifest-ticket |
| **C44** | No virtual-queue / bot-defense primitive | Ticketing #5 | Waiting-room + bot-defense primitive before competitive on-sales |
| **C45** | Table minimum-spend balance + at-the-room settlement unmodeled | Product #2 | Model the balance + at-the-room settlement, or explicitly concede Snatch It is not the bottle-service system of record |
| **C46** | Fire-code occupancy vs sold capacity; cash box-office; auto-grat/tip-out; refund-at-door vs door_pin authz | Product #5/#6 | Occupancy attribute; cash + gratuity settlement causes; reconcile door refund authz |
| **C47** | DR asserted not designed | DS N4 | RPO/RTO targets; PITR/standby; restore drills; snapshot-based projection-rebuild budget at 500M; separate projection-replay from substrate-DR |
| **C48** | Ephemeral-event projections not rebuildable post-compaction | DS N5 | Retention floor for canonical inputs before outbox compaction; mark non-rebuildable projections |
| **C49** | Outbox drainer SPOF + head-of-line blocking; region hand-off is a hidden 2PC | DS N7/N8 | Poison-quarantine; partitioned/multi-drainer outbox; specify the region hand-off protocol |
| **C50 / O6** | C8×C14 cross-region native-resale collision | DS N3 (highest-value) | **O6 (open):** native-resale saga/escrow vs intra-region-only — a joint commercial+technical decision before multi-region resale |
| **D1** | CDM §2 line 262 "the one sanctioned cross-aggregate transaction" contradicts line 251 + C12 | DB #8 (verified) | Doc-consistency: rewrite to SSCAS |
| **D2** | DA §3.1 diagrams still draw `active → refunded` despite A5 | DB #8 (verified) | Doc-consistency: redraw to `voided(refund_void)` |
| **D3** | Cause-code enum diverges between CDM §481 and DA | DB #8 (verified) | Doc-consistency: one canonical cause-code list |

**Meta-observation (three independent hits each — highest confidence):** the **market↔kernel buyer-auth seam** (Payments, DS, Security), **SSCAS incompleteness** (Payments, DS, DB), **the reserve/clawback gap** (Payments, DB, Product), **re-entry** (Ticketing, Product), and **the credential key/signer** (Security, Ticketing, Product) were each surfaced by multiple blind reviewers. These are not stylistic quibbles; they are the load-bearing gaps.

---

## 5. Alternative architectures — designed, then defeated (or conceded)

The board designed three materially different architectures and pressure-tested the current one against each. **All six reviewers independently concluded: keep the current architecture.** It is the deliberate intersection of *event-sourced where truth must replay* ∩ *modular monolith with service seams* ∩ *external-first now, native-issuer later*.

### Alt-1 — Event-sourced everything (CQRS, event store as system of record)
- **Wins:** uniform audit/replay/temporal queries; royalty/commission/chargeback become natural folds.
- **Loses (decisive):** it pushes the *cheap, provably-correct* invariants (oversell, one-owner, no-double-transfer) — which the current design nails with a synchronous `FOR UPDATE` + a UNIQUE constraint in one Postgres transaction — onto eventually-consistent projection reads on the hottest path. Inventory oversell becomes a slow synchronous projection read. And it implies reopening the frozen Stripe core. **Current wins.** The current design already takes the 20% of ES that pays (append-only logs where truth must reconstruct) and rejects the 80% that taxes a two-engineer team. The SSCAS + event envelope keep it *ES-ready at the seams* — optionality to bank, not spend.

### Alt-2 — Microservices from day one
- **Wins:** independent scaling; team isolation at org scale (irrelevant at 2 engineers).
- **Loses (decisive):** every SSCAS transaction becomes a distributed saga with compensations *now*, for zero current scaling need. The modular monolith **is** Alt-2 minus the premature operational cost, and its schema seams preserve the extraction exit. **Current wins.** Honest caveat: the "extract later" exit is only real if the GRANT/function boundaries are CI-enforced and never bypassed (H7/F-X9).

### Alt-3 — External-first / integrate-don't-issue / white-label
- **Wins:** kills the entire 15.A gate (credential crypto, key mgmt, offline door, oversell concurrency); ships faster; lower liability.
- **Loses (decisive):** it structurally *forfeits the moat* — venue-governed royalty and dispute-free credential-as-delivery are impossible if you don't own the credential; you become a thinner StubHub / SeatGeek-secondary, blocked by the incumbents' rotating-barcode walls and hostile transfer ToS. **Current wins on the destination.** But Alt-3's *discipline* is already absorbed: the roadmap is external-first *today* and defers native issuance behind the gate; native resale is a `resale_policy='off'` stub until a venue commits. **The load-bearing uncertainty is therefore commercial — will Miami venues cede primary issuance — not architectural.**

### Where an alternative genuinely wins (conceded, and folded into the corrections)
- **Payments:** a formal **double-entry ledger *schema* inside the monolith** (not a service) beats the current payout+log model on the money plane — it turns the reserve gap, fan-clawback, split-balancing, and C25 compensation from silent leaks into constraint violations (→ **C31**). Keep the ownership log for custody; do not ledgerize custody.
- **Distributed Systems:** model **native resale as a saga/escrow from day one** rather than pinning C8 to a single DB transaction — the design is already 80% there via `paid_pending_transfer`+C25, and the pin is exactly what makes cross-region resale intractable (→ **C50/O6**).
- **Ticketing:** an **optional-nullable seat layer now** — C22's unit-rows already *are* seat atoms, so the atom is largely additive; only the seat-map/selection UX is the multi-month cost (→ **C42**).
- **Analytics/DB:** a **separate OLAP store** is a worthwhile *addition* (pull settlement/reporting rebuild out of OLTP), not a replacement (→ deferred, roadmap Phase 3).

None of these is a replacement; each is an additive refinement of the current design.

---

## 6. Expensive at 50M users / 20k venues / 500M tickets / global / multi-provider / enterprise

| Decision | Why expensive at scale | Op risk | Avoidable now? |
|---|---|---|---|
| C8 pinned to single-DB txn (no cross-region custody txn) | Differentiator rail is an undefined distributed transaction post-region-split | **High** | Yes — saga/escrow prose now (C50) |
| 8/9 SSCAS members with no sharding/saga story; §12 undercounts 9:1 | Every multi-aggregate flow becomes a cross-shard problem at once | **High** | Yes — sharding/saga story per member (C28) |
| Hot inventory counter, even sharded | Instant sellout = thousands of writers; tail-stranding + rebalance-lock; unit-rows = forbidden seat atom | **High** | Mitigated (C4/C22); reconcile (C27/C42) |
| No seat atom (`table` on scalar capacity) | First reserved-seat/sports/theater venue = platform-wide money-touching migration | **High** | Hedge cheaply now (C42) |
| Instant/fast payout with no reserve | Cancellation/chargeback clawback economically impossible; silent uncollectable losses | **High** | Yes — reserve object + double-entry (C29/C31) |
| Frozen USD-integer-cents money-in boundary | First non-US market = schema-wide retrofit under load | **High** | Yes — first-class currency now (C32) |
| "Replay from logs" as DR without snapshots | 500M-ticket rebuild blows any real RTO; ledger+head one failure domain | **High** | Yes — DR design + snapshots (C47) |
| Single outbox+cron drainer | Latency floor + throughput ceiling + head-of-line blocking | **Med-High** | Envelope already allows bus swap (C49) |
| C1 global signing key (if not scoped) | Compromise = re-issue entire population; offline doors accept forgeries | **High** (existential) | Yes — scope + KMS/HSM + rotation (C33) |
| Per-identity crypto-shred + KYC/OFAC/PSD2-SCA + 50-country VAT | An entire compliance program the docs don't yet contain | **High** | Partially — spec the erasure + tax hooks now (C34/C19) |
| Offline reconciliation fraud-ops across 20k venues | Uncosted human ops army; adjudication under clock-skew (O2) | **Med-High** | Model the queue (C6/C23); O2 still open |
| Modular-monolith boundary discipline over years | "Extract later" thesis dies if seams are bypassed under deadline | **Med-High** | Permanent CI enforcement only defense |
| Bottle-service balance off-platform | Cedes the money that matters in the target market to POS-fusion competitors | **High** (commercial) | Yes — model it (C45) |

---

## 7. Regret analysis — return in 2036

Ranked by P(regret) × cost-of-regret:

1. **Seat atom shipped as `table` in 2A on scalar capacity.** The "out of scope" object shipped anyway, threaded through inventory/orders/settlement/projections; the non-additive rework becomes the seven-figure, money-touching migration the framing meant to avoid. **Avoidable now, cheaply** (C42) — the team hedged currency/region/tax/external-seat-ref with optional-nullable fields but did not hedge seating.
2. **Unscoped global signing key.** A 2033 compromise re-issues the entire population while offline doors accept forgeries. Highest blast radius; irreversible after mint. **Avoidable now** (C33).
3. **Instant payout with no reserve ledger.** Years of silently-absorbed chargebacks/clawbacks with no row naming the loss = an un-reconstructable hole in the books. **Avoidable now** (C29/C31).
4. **Frozen USD-scalar money-in.** Going multi-currency forces reopening the "never reopen" core — the exact redesign the freeze was meant to prevent. **Avoidable now** (C32).
5. **Terminal `scanned` baking re-entry out of the scan model.** Regretted the moment festivals/re-entry appear. **Decide now like seating** (C41).
6. **DR-by-assertion.** RPO/RTO defined retroactively in the first outage. **Avoidable now** (C47).
7. **The constitution becomes unreadable** — "deprecate don't delete" applied to the *document* yields a C1…C50 precedence stack over a body that still says the opposite (D1/D2/D3 already prove the drift). Regretted when the founders holding the precedence algorithm are gone. **Mitigate now** with a consolidation pass that folds ratified corrections into the body.

**Regret meta-point:** every top regret except the seat-map UX is avoidable *at prose cost today*. That is the entire value of running this review while the system is still prose. The corrections push these from "roadmap hopes" into ratified extension points and contracts before code.

---

## 8. Disagreement resolution (Chair)

The board largely converged; where verdicts differed, the split was about *scope*, not design:

1. **NOT READY (4) vs READY-WITH-CONDITIONS (2).** Resolved: both are true at different scopes. The Product/Ticketing "ready" is scoped to the *fundraise demo / Miami GA path*; the DB/DS/Security/Payments "not ready" is scoped to *native resale + scale + region + the money-reversal envelope*. The consolidated verdict encodes both as a **gated readiness** (§0, CTO memo): pre-issuance subset → GA path; fuller subset → resale/multi-region/multi-currency.
2. **Seat atom: "accepted deferral" (prior H6) vs "already shipped as `table`" (DB) vs "cheaply hedgeable" (Ticketing).** Resolved in favor of DB+Ticketing: the deferral is only safe if the extension point is reserved now (C42). H6's "non-additive" is downgraded to "non-additive *only if the unit-row/seat hedge is skipped*."
3. **Double-entry ledger: add now vs later.** Resolved: adopt the *schema* now as the home for the reserve/clawback/currency corrections (C31), since those are pre-resale blockers anyway; a dedicated ledger *service* remains overkill and deferred.
4. **C8 pin: keep (atomicity) vs saga (region).** Resolved: keep the single-DB path as the intra-region implementation *and* specify the saga/escrow as the cross-region form now (C50/O6) — they are the same money-safety window (`paid_pending_transfer`) at two scopes.

No reviewer dissented from the core: ticket-atom, append-only ownership log, single transfer engine, credential-as-delivery, two-rail honesty, modular monolith, frozen money core. **The corrections are concentrated in specification completeness — money-reversal, key lifecycle, erasure, SSCAS closure, region/DR, and nightlife-ops — not in the domain model.**

---

## 9. What the review did NOT find (to keep proportion)

No reviewer found a flaw requiring redesign. The frozen money core, the append-only-ledger principle, the single-writer choke point, the two-rail honesty, the modular-monolith choice, the asymmetric-credential decision (C1's *scheme*), and the identity model (one login, capability-from-relationships) all survived every attack. The ownership model earned an outright **YES**. The corrections make an already-right architecture *buildable*; they do not change what it is.

**Bottom line:** ratify the architecture; land C26–C50 / O6 / D1–D3 in the order the CTO memo prescribes; clear the pre-issuance subset before minting the first native credential; resolve the resale/region/currency subset before the fast-follows. Then build.
