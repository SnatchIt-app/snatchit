# Snatch It — Phase 2 Architecture Review

> ## ⛔ SUPERSEDED — this document is NOT current design. Banner added 2026-08-28 (`R4-8`; ratification rows `C127` / `D34`).
>
> **Why this banner exists.** This file sits under `docs/architecture/_superseded/` and **carried no
> supersession notice at all**, while the one `_governance/` document that was salvaged the same way
> (`PHASE_2_FINAL_PREIMPLEMENTATION_GATE.md`) does carry one. A directory name is not a banner: a reader who
> opens the file directly, follows a cross-reference into it, or reads a printed copy sees only live-sounding
> present-tense prose. **Nothing below is deleted** — these documents are the provenance of ratified
> decisions and are still cited by name — but nothing below may be implemented from.
>
> **Superseded by:** the **consolidated constitutions** — `docs/architecture/SNATCH_IT_DOMAIN_ARCHITECTURE.md`
> and `docs/architecture/SNATCH_IT_CANONICAL_DATA_MODEL.md` — into whose bodies this review's findings were
> folded, and `docs/architecture/_governance/PHASE_2_RATIFICATION_RECORD.md`, which records each as a row.
> Its **Part 15 risk register** is superseded by
> `docs/architecture/_governance/ARCHITECTURAL_RISK_REGISTER.md` (R1–R36), which merges it forward. The
> five-persona **YES-IF** verdict below is a 2026-08 verdict on a document the record has since corrected
> 114 times; the live readiness verdict is
> `docs/architecture/_governance/IMPLEMENTATION_READINESS_SCORE.md`.
>
> **Still cited, legitimately:** `SNATCH_IT_DOMAIN_ARCHITECTURE.md` names this file as a companion for the
> multi-persona critique, and that citation is to the critique, not to its conclusions about current design.
>
> **Reading rule.** Cite this file for **provenance** — what was found, by whom, and why a decision was
> taken. **Never for current design, current numbers, or current scope.** Where it disagrees with the
> superseding document named above, **the superseding document governs**, and that determination needs no
> precedence rule: this one is dated and closed.


**Companion to `docs/architecture/SNATCH_IT_DOMAIN_ARCHITECTURE.md`.** Design-only. This is the adversarial stress-test of the domain constitution: Part 17 (five independent principal-level critiques), the resolution of their disagreements, and Part 15 (the consolidated, ranked risk register with the must-fix gate). Every ratified fix appears in the constitution's §0.5 as C1–C11.

---

## 0. Verdict

**YES-IF — unanimous (5/5 reviewers).**

The foundational bet is right and is a stronger decade-scale foundation than any single competitor's core: **the ticket as the single atom, ownership as an append-only log mutated only by one transfer engine, credential-as-delivery, the two-rail "claim vs. issued-ticket" honesty, and a modular monolith with DB-enforced boundaries** over microservices for a two-engineer team. The money-invariant discipline is excellent and the design is genuinely additive — the frozen marketplace money core is not reopened.

**The "IF" is a specific, mostly-additive set of corrections that must land before the first native ticket is issued** (§4 gate). None requires re-architecting; all are captured as C1–C11. Left unfixed, the native rail's "guaranteed, atomic, dispute-free" promise is false in exactly the offline, mid-event, and compromised-key conditions an attacker will choose.

---

## Part 17 — Multi-persona self-critique

Five reviewers, each with a distinct mandate, reviewed the full constitution independently and were told to find what is wrong, not to praise.

### 17.1 Principal Product Manager — *does it serve the business?*
**Verdict: YES-IF.** The primary-ticketing-and-door core models real nightlife (sessions, door batch for 1 a.m. walk-ups, loginless PINs, tables-with-minimums, comps, promoter holds) and can put one approved Miami venue live — issue, scan, get paid — on a 2-engineer timeline **without touching the marketplace**. The danger is not the design but the absence of a sequencing layer on top of it: a 37k-word constitution handed to two engineers reads as a build backlog, and native resale is architected as a full platform (auctions, six resale modes, credential rotation, royalty-through-settlement) **before a single primary ticket exists to resell.** Biggest IF: treat the document as guardrails around a ~12-object MVP; ship *issue → buy → scan → venue paid* for the raise; make native resale the visible fast-follow. → drives the **roadmap** and C11.

### 17.2 Principal Staff Engineer — *is it buildable; will five engineers converge?*
**Verdict: YES-IF.** The core bet is sound and additive. But the review found the constitution **contradicted itself** in three ratified places (the §0.4 amendments were not propagated into the body): `event_session`'s schema home, the abolished `refunded` terminal, and multi-session cardinality — the exact load-bearing, near-irreversible decisions. Biggest IF: reconcile the amendments into the body and **freeze `event_session`'s placement before any code.** → fixed by the §0.4 precedence clause and **C7**. Also flagged dual-control as an operational deadlock for a 2-person team → **C11**.

### 17.3 Principal Architect — *are the boundaries and seams right?*
**Verdict: YES-IF.** Two structural corrections: (R1) the flagship native-sale transaction is specified two incompatible ways — either the kernel writes a `market` table (dependency inversion) or the sale spans two schemas co-transacting (fine now, un-extractable later); it must be **pinned** → **C8**. (R3/R5) `core` is a god-schema fusing identity + money + custody + high-churn venue/event data + leaf tables, and `event_session` is ratified into two schemas at once; **split into `kernel` + `catalog` + evict leaves** → **C7**. Also: reserved/assigned **seated inventory is foreclosed** (scalar capacity, no `seat` atom) — a future non-additive change → **C11**; and the two-rail discriminator has no home for a "verified external" (adapter-delivered) claim → **C10**.

### 17.4 Principal Security Engineer — *attack the new surface.*
**Verdict: YES-IF.** The single most important finding of the review: **the credential is a symmetric HMAC whose secret must be shipped to offline doors to verify — making every scanner a forgery oracle**, and the secret sits on a readable ticket row (re-leaking Phase-0's column-exposure). Must become an **asymmetric signature** → **C1**. The transfer engine authorizes `service_role`, not the owner (BFLA), and the dual-control threshold itself is single-admin-editable → **C2/C11**. The relationship model re-opens H-2/H-3 self-grant/mass-assignment across ~12 new authz/money-config tables, and money-config writes ride stale JWT claims → **C9**. Cross-rail double-sell, adapter-write-by-convention, `validation_callback` SSRF, and a non-private `attendance_visibility` default → **C10**. Must-fix-before-issuance: **C1**; must-fix-before-first-transfer: **C2**.

### 17.5 Principal Database Engineer — *does it hold under concurrency and crash?*
**Verdict: YES-IF.** The ledger→derived-head + single-writer + `FOR UPDATE` pattern is money-grade **for online single-hot-object paths**, but the document repeatedly implies the row lock's guarantee extends to multi-row and offline cases where it does not. (R1) offline door demotes *every* resale-safety invariant, not just duplicate-scan → **C6**. (R2) per-user caps are write-skew a trigger cannot hold → **C5**. (R3) the `sum=capacity` trigger is a **tautology**; real oversell guard is `remaining≥0` + a locked decrement, and that counter is the **hottest row** (shard or unit-rows) → **C4**. (R4) `paid_pending_transfer` recovery can double-transfer without `UNIQUE(cause,cause_ref)` → **C3**. (R5/R6) issuance welds `core`↔`venue`; the "partial-unique on live custody" is unimplementable on a pure append-only log — enforcement is really `FOR UPDATE` + single writer → reconciled in **C2/C3/C7**.

---

## Part 17.6 — Resolution of disagreements

The reviewers largely converged; where they differed or where a choice was forced, the panel resolved as follows:

1. **`event_session` schema home (core vs venue).** Staff Engineer wanted it frozen; Architect proved *both* placements were ratified and that `venue` creates an outward-kernel FK while `core` deepens the god-schema. **Resolution:** neither — introduce a `catalog` reference-data schema and place it there (C7). This satisfies both objections and is strictly better than the original A1.
2. **Dual-control: mandatory (security ideal) vs impossible for a 2-person team (staff/product reality).** **Resolution (C11):** config-gated seam — single-operator orgs use single-approver-with-mandatory-audit, but the *threshold itself* is under dual-control so a lone admin cannot raise it to self-clear a large move (Security R2). Preserves the control's intent without deadlocking the team.
3. **Credential: keep HMAC (simpler) vs asymmetric (secure).** No real disagreement once stated — HMAC is unsound for offline verification. **Resolution (C1):** asymmetric, non-negotiable, before issuance.
4. **Native resale now vs later.** Product/Staff say defer; the design specifies it in full. **Resolution:** the *architecture* stays (it is the differentiator and cheap to leave in the constitution), but the *build* is deferred to the fast-follow (roadmap Phase 2c), shipped as a stubbed `resale_policy='off'` object. No conflict between a complete constitution and a lean build order.
5. **Event-driven catalog (36 events).** Architect/Staff call most of it premature. **Resolution (C11):** keep the naming discipline for the ~10 invariant-bearing synchronous calls + ~6 genuinely-async outbox events; drop the speculative Phase-3/4 events and the consumer matrices for unbuilt contexts. Transport stays a single outbox table on the existing cron.

No reviewer dissented from the core architecture. All disagreements were about *scope and enforcement mechanism*, not the domain model.

---

## Part 15 — Risk register (ranked; every architectural decision that is expensive to change, and every material risk)

Severity = blast radius × likelihood. Status: **RATIFIED-FIX (C-n)** = corrected in §0.5 · **OPEN** = deferred, needs a decision before the relevant phase · **ACCEPTED** = a deliberate, documented tradeoff.

### 15.A — Must-fix before the FIRST NATIVE TICKET IS ISSUED (the gate)
| # | Risk | Sev | Status | Reversible? |
|---|------|-----|--------|-------------|
| G1 | Symmetric-HMAC credential = offline forgery oracle + row-secret leak | 🛑 Critical | **C1** | **No** once minted — hardest-to-reverse in the system |
| G2 | Transfer/issuance engine authorizes `service_role`, not the owner (BFLA / custody theft) | 🛑 Critical | **C2** | Yes (pre-launch) |
| G3 | Double-transfer possible on `paid_pending_transfer` recovery (no `UNIQUE(cause,cause_ref)`) | 🔴 High | **C3** | Yes (additive constraint) |
| G4 | Oversell: `sum=capacity` trigger is a tautology; unguarded counter | 🔴 High | **C4** | Yes (additive CHECK + lock) |
| G5 | Cross-rail same-seat double-sell (no shared dedup key) | 🔴 High | **C10** | Yes, if keyed before native issuance |
| G6 | H-2/H-3 self-grant/mass-assignment re-opened on ~12 new authz/money-config tables | 🔴 High | **C9** | Yes (grant discipline) |

### 15.B — Must-fix before NATIVE RESALE / OFFLINE SCANNING ships
| # | Risk | Sev | Status |
|---|------|-----|--------|
| B1 | Offline door demotes credential-invalidation to reconcile-after-the-fact (resold-credential resurrection, double-admit) | 🔴 High | **C6** + offline-transfer freeze |
| B2 | Per-user caps are write-skew (trigger cannot hold) | 🟠 Med-High | **C5** |
| B3 | `locked` not stated to block scans; version-bump ordering undefined | 🟠 Med-High | **C3** clause |
| B4 | Inventory `batch` counter is the hottest row; single-counter fails instant sellout | 🟠 Med-High | **C4** (shard/unit-rows) |
| B5 | Native-sale tx boundary ambiguous (kernel writes `market`?) | 🟠 Med | **C8** |
| B6 | Lot / multi-session transfers deadlock without a mandated lock order | 🟠 Med | ascending-`ticket_id` lock order (roadmap) |

### 15.C — Hardest-to-reverse decisions (change-control-critical — get right while still prose)
| # | Decision | If wrong | Hedged? |
|---|----------|----------|---------|
| H1 | Credential scheme (asymmetric, C1) | Re-issue entire population | Now yes (C1) |
| H2 | Schema boundaries: `kernel`/`catalog`/leaf/`venue`/`market`/`social`/`analytics` (C7) | Re-home = rewrite RLS/grants/functions/views | Improved by C7 |
| H3 | Ticket-atom + ownership-log-as-truth + single transfer engine | Total — but replayable & additive | Yes (ledger replay) |
| H4 | Two-rail discriminator (`inventory_kind` + nullable `ticket_id`) | Pervasive branch; no "verified external" home | Partly; C10 adds the third state |
| H5 | Event/session grain (C7 places session in `catalog`) | Scans/capacity re-home | Now yes |
| H6 | No `seat` atom (scalar capacity) | Seated/sports = non-additive core rework | **ACCEPTED** (Miami GA+tables); C11 |
| H7 | Modular-monolith-as-future-services | Extraction may never pay off; discipline tax | Yes (deferred) |

### 15.D — Open questions (no reviewer fully closed; decide before the named phase)
| # | Question | Blocks |
|---|----------|--------|
| O1 | Native-resale event-cancellation refund liability: full-chain clawback vs face refund, and the **reserve** that funds it (instant payout makes clawback harder) | native resale + instant payout |
| O2 | Offline first-admit-wins consensus under clock skew / partition (arbitration + fraud queue) | offline scanning at scale |
| O3 | Resale-policy snapshot drift (a native listing outliving a mid-sale policy change) | native resale |
| O4 | Per-event identity-verification strength (name-match vs custody-follows-credential; corporate/renamed holders) | high-risk events |
| O5 | Cross-rail seat-identity dedup key design (what canonical key identifies "the same physical seat" across an external claim and a native ticket) | native issuance for events with external inventory |

### 15.E — Deferred / over-built (cut from Phase 2 build; keep in the constitution)
`social` schema, `analytics` schema, the 36-event catalog (trim to ~16), promoter/affiliate engine, native auctions/offers, six resale modes (ship `off`/`transfers_only`), adapter ports (documented only), demand-pricing, waitlist/bundles/tiered ladders/segment-visibility. All are fast-follow or later; none blocks the first venue.

---

## Part 15.F — What the review did NOT find (to keep proportion)
No reviewer found a flaw in the frozen money core, the append-only-ledger principle, the single-writer choke point, the two-rail honesty, or the modular-monolith choice. The identity model (one login, capability-from-relationships) and the audited admin plane were endorsed. The corrections are concentrated in **cryptographic credential design (C1), authorization-vs-machine-identity (C2), multi-row/offline concurrency (C3–C6), and schema shape (C7–C8)** — not in the domain model itself.

**Bottom line:** the constitution is sound; build it in the order the roadmap prescribes, clear the 15.A gate before minting a native credential, and resolve O1–O5 before the resale fast-follow.
