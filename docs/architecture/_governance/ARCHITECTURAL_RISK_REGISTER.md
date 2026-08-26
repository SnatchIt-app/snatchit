# Snatch It — Architectural Risk Register

**Companion to `docs/architecture/_superseded/PHASE_2_FINAL_ARCHITECTURE_AUDIT.md`.** The consolidated, ranked register of every architectural risk the Phase 2C board surfaced, merged with the still-open items from the prior review (O1–O5, 15.A–15.D). Each row: severity, the defect, the source, the proposed additive remedy (correction ID), the gate that blocks on it, reversibility, and owner. Design-validation only — remedies are proposed for a later, separately-approved ratification pass; nothing here is applied to the frozen constitution.

Severity: 🛑 Critical (correctness / irreversible / legal) · 🔴 High · 🟠 Medium · 🟡 Low.
Gate: **P** pre-native-issuance · **M** pre-money-rail (resale) · **L** pre-legal-scale (international/enterprise) · **—** documentation/ongoing.
Reversible: **N** = irreversible once shipped/minted · **Y** = additive fix possible later (but cheaper now).

## Tier 1 — 🛑 Critical (block code now)

| ID | Risk | Source | Remedy | Gate | Rev |
|----|------|--------|--------|:---:|:--:|
| R1 | `UNIQUE(cause,cause_ref)` breaks on one-cause→many-tickets (issuance K atoms; refund-void K tickets) and doesn't block cross-object re-void → "double-transfer impossible" (C3) is unproven | DB, Payments | **C26** key `(cause,cause_ref,ticket_id)` + per-`market_sale` terminal state machine (compensate-XOR-complete under one lock) | P | Y |
| R2 | `remaining` defined as BOTH ledger-derived head and locked mutable counter → oversell or on-sale collapse | DB | **C27** pick one authoritative, the other derived | P | Y |
| R3 | C1 signing-key lifecycle unspecified; likely one global key = existential compromise (forge all tickets, accepted offline); signer is an unmodeled HA/throughput single point | Security, Ticketing, Product | **C33** per-event/venue-scoped keys + KMS/HSM + rotation/compromise runbook + signer HA + door key distribution | P | **N** |
| R4 | No Reserve/Clawback object; instant payout + O1 cancellation + C25 auto-refund have no funding source | Payments, DB, Product | **C29** reserve object + payout-timing policy (ideally via **C31** double-entry ledger) | M | Y (losses accrue if late) |
| R5 | Fan-side chargeback/clawback liability unrepresentable (no negative-balance home; Wallet deferred) | Payments | **C30** fan liability object / Wallet-MVP | M | Y |
| R6 | C15 crypto-shred erasure unsound: no DEK lifecycle, backups retain ciphertext, PII sinks + re-identifiable event graph uncovered → GDPR/CCPA erasure not provable | Security, DB | **C34** DEK lifecycle incl. backups + PII-sink inventory/purge + retained-graph mitigation + 7-yr-retention reconciliation | L (claim); spec at P | Y (spec) |
| R7 | Kernel trusts market-supplied buyer id at C8 seam (buyer ∉ owner/p2p/admin, so C2 doesn't cover it) — `p_user_id`-trust anti-pattern at the boundary | Security, DS, Payments | **C35** kernel authorizes the buyer principal itself | P | Y |

## Tier 2 — 🔴 High (block the named phase)

| ID | Risk | Source | Remedy | Gate | Rev |
|----|------|--------|--------|:---:|:--:|
| R8 | SSCAS "closed set of 9" is not closed — omits event-cancellation cascade, dispute-resolution reversal, C25 compensation, auction deposit-release, group-buy, wallet checkout | Payments, DS, DB | **C28** enumerate all; declare genuinely closed | P | Y |
| R9 | Lock-ordering constitution incomplete — Settlement/Attribution/Dispute/Refund/Wallet/Auction/sub-counters unplaced → no deadlock-freedom proof; multi-batch on-sale not ordered | DS, DB | **C28** place every locked class + ascending-batch-id | P | Y |
| R10 | C8 (single-DB sale) × C14 (home-region log) mutually exclusive → cross-region native resale undefined | DS (highest-value new) | **C50 / O6** saga/escrow, or explicit intra-region scoping | M/region | Y |
| R11 | Terminal `scanned` + A3 forecloses re-entry/pass-outs — core to nightlife, traded away unflagged; A3-level latent redesign | Ticketing, Product | **C41** re-entry sub-state, or scope demo to no-re-entry GA + name it a future change | P | N-ish (like H6) |
| R12 | Seat atom shipped as `table` on scalar capacity in 2A; unit-rows (C4/C22) already ARE the seat atom H6 forbids | DB, Ticketing, Product | **C42** optional-nullable seat/unit-row layer now; reconcile C4/C22 | P (hedge) | N if skipped |
| R13 | DR asserted not designed — no RPO/RTO; ledger + derived head share one failure domain; "replayable = recoverable" is a category error | DS | **C47** RPO/RTO + PITR/standby + restore drill + snapshot rebuild budget | L | Y |
| R14 | Multi-currency not first-class at frozen USD-cents money-in boundary; FX timing / per-country payout / rounding bearer unmodeled | Payments | **C32** currency on every money object + FX + rounding-bearer | L | Y (costly late) |
| R15 | Scope-qualified roles (A9) are lint convention, not structure → org/venue BFLA-by-naming | Security | **C36** typed scope / distinct labels | P | Y |
| R16 | Table minimum-spend balance + at-the-room settlement unmodeled → majority bottle-service revenue off-platform | Product | **C45** model balance + settlement, or explicit concession | 2A-tables | Y |
| R17 | §12 "one seam resists sharding" contradicts C12's nine; Event-aggregate boundary contradicts C4/C22 sharding | DS, DB | **C28** reconcile scalability prose to C12 | — | Y |

## Tier 3 — 🟠 Medium

| ID | Risk | Source | Remedy | Gate | Rev |
|----|------|--------|--------|:---:|:--:|
| R18 | p2p `locked` overlay unbounded + deadlocks C6 freeze → owner locked out of own valid ticket | Ticketing | **C43** C25-style auto-unlock + exempt cancel-to-self + narrow freeze scope | M | Y |
| R19 | Online-door credential-invalidation freshness ambiguous (cron-drain vs "strong online") → resurrection window even with connectivity | Security | **C37** live per-scan kernel read; drop "dispute-free by construction" claim | M | Y |
| R20 | Identity-merge grant reconciliation unspecified; attacker-influenceable trigger not dual-controlled → privilege-merge | Security | **C38** grant-union rules + dual-control on trigger | L | Y |
| R21 | Ephemeral-event projections (risk/notify/social) not rebuildable after outbox compaction | DS | **C48** retention floor + mark non-rebuildable | L | Y |
| R22 | Outbox+cron single drainer SPOF + per-aggregate head-of-line blocking; region hand-off is a hidden 2PC | DS | **C49** poison-quarantine + partitioned drainer + hand-off protocol | L | Y |
| R23 | Comp/guest-list issuance un-stepped-up insider fraud (money-adjacent) | Security | **C39** add to C9 live-recheck + step-up | M | Y |
| R24 | `validation_callback` allowlist owner unspecified → SSRF if provider-supplied | Security, Product | **C40** static platform-controlled allowlist + CI-assert adapter REVOKE | L (adapters) | Y |
| R25 | Settlement "carry to next payout" strands for dormant orgs; 3-way-split rounding residual unassigned; royalty is a one-sided (unbalanced) credit | Payments | **C31** double-entry ledger balances splits + rounding | M | Y |
| R26 | No virtual-queue / bot-defense primitive for competitive on-sales | Ticketing | **C44** waiting-room + bot-defense primitive | general | Y |
| R27 | Fire-code/legal occupancy ≠ sold capacity; door count admits-only | Product | **C46** occupancy attribute | 2B | Y |
| R28 | `credential_version` modeled as independent head but must be derived-from-log (else a second undetectable custody truth) | DB | **C27**-adjacent: pin credential_version to the log | P | Y |
| R29 | Verify-trigger recompute is O(custody-chain length) per write, K× per lot → write amplification on hot resale tickets | DB | checkpoint the head (C21-style) for this trigger too | M | Y |
| R30 | Adapter reach collapses to manual against rotating-credential incumbents (TM SafeTix / AXS Mobile ID) | Product, Ticketing | correct the adapter narrative; scope adapter value to open-credential providers | L (adapters) | Y |

## Tier 4 — 🟡 Low / documentation (cheap, do in the ratification pass)

| ID | Risk | Source | Remedy | Gate | Rev |
|----|------|--------|--------|:---:|:--:|
| R31 | CDM §2 line 262 "the one sanctioned cross-aggregate transaction" contradicts line 251 + C12 (verified) | DB | **D1** rewrite to SSCAS | — | Y |
| R32 | DA §3.1 diagrams still draw `active → refunded` despite A5 (verified) | DB | **D2** redraw to `voided(refund_void)` | — | Y |
| R33 | Cause-code enum diverges between CDM §481 and DA (verified) | DB | **D3** one canonical cause-code list | — | Y |
| R34 | `resale_state` (a market/Listing fact) physically on the kernel atom — dependency smell | DB | review placement in ratification pass | — | Y |
| R35 | Cash box-office + auto-gratuity/tip-out settlement causes; refund-at-door vs loginless door_pin authz contradiction | Product | **C46** settlement causes + reconcile door refund authz | 2B | Y |
| R36 | Constitution readability drift — C1…C50 precedence stack over a body that still says the opposite | Chair/regret | schedule a consolidation pass folding ratified corrections into the body | — | Y |

## Carried-forward open questions (from prior review; still open or reframed)

| Prior | Status now |
|---|---|
| O1 cancellation refund liability + reserve | **Reframed as R4/C29** — it is a missing object + payout-timing policy, not merely a question |
| O2 offline first-admit-wins consensus under skew/partition | **Still OPEN** — arbitration + fraud queue design before offline at scale |
| O3 resale-policy snapshot drift | **Still OPEN** — decide before native resale |
| O4 per-event identity-verification strength | **Still OPEN** — name-match vs custody-follows-credential |
| O5 cross-rail seat-identity dedup key | **Reframed as C17** (external-seat-reference) — confirm enforced before native issuance for events with external inventory |
| O6 (new) cross-region native-resale saga vs intra-region-only | **New OPEN** — joint commercial + technical decision (R10) |

## Register summary
- 🛑 Critical: 7 · 🔴 High: 10 · 🟠 Medium: 13 · 🟡 Low/doc: 6 · Open questions: 6 (2 reframed, 3 open, 1 new).
- **Every Tier-1 and Tier-2 risk is remediable in prose and is cheaper now than after code.** Three are irreversible-if-shipped (R3 key, R11 re-entry, R12 seat) — these are the highest-priority "get right while still prose" items.
- No risk in any tier requires a redesign.
