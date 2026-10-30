# Phase 2 — Final Pre-Implementation Consolidation Report

**Branch:** `phase2/consolidation` @ `8c06c60` · **Date:** 2026-08-28
**Verdict:** **NOT READY TO BUILD** (Agent L, independent readiness review)
**Consequence:** the architecture freeze (Task 14) is **NOT written**. It was conditioned on READY.

---

## 1. What was authorised and what was done

Two owner-issued programmes ran in this session.

**(a) Migration `075` to production** — applied 2026-08-27 21:39:49 UTC, ledger 88 → 89, all seven pre-apply
gates and all 24 post-apply verification items passed, twelve catalog content digests byte-identical before and
after. Delivered as `075_PRODUCTION_VERIFICATION_REPORT.md`. AUTODEPLOY-1 confirmed OFF against a real
migration-bearing merge — the positive control the earlier docs-only test could not provide.

**(b) Final pre-Phase-2 consolidation + architecture freeze** — 14 tasks. Thirteen completed; **Task 14 (the
freeze) is not written, because Task 13 returned NOT READY.**

## 2. Production state — unchanged

**Zero diff under `supabase/migrations/` since the consolidation baseline.** The production ledger is 89 rows,
highest sequential `075`. No RLS change, no Edge Function deployment, no Stripe change, no schema mutation.
Every prohibition in the brief held.

## 3. Repository tasks — closed

| Task | State |
|---|---|
| B-1 — pgTAP masking ratchet | **merged** (assertion-sum ratchet, after three rounds) |
| B-2 — MONEY-1 impersonation matrix (PR #19) | **merged** `7345f81`; floors ratcheted 16→17 files, 287→305 assertions |
| PR #21, #22, #23 (superseded) | **closed**; #22 salvaged as PR #27 (SEC-2 grant gate), merged |
| Phase 2 renumber 071–086 → **076–091** | **done**; four numbering scales reconciled |
| Five owner rulings O-1…O-5 propagated | **done**, each as a numbered ratification row |
| Six feature specs completed | **done** (Wallet, demographics, promoter codes, CRM export, notifications, dashboard) |

PR #19's reviewed content changed on inspection: PR #22's assertion 17 was not a superset but a **dominating
replacement** — #19's version aimed `mark_listing_sold` at an `active` listing, so the guard short-circuited on
its first disjunct and would have stayed green **even if the forged `p_user_id` were honoured**. The landed
version turns the outcome on identity alone.

## 4. Review history

| Pass | Result |
|---|---|
| Agent K round 1 | **REJECT** — 4 blockers |
| K's sub-attackers | 9 further blockers (money/custody authority, cross-file request tables) |
| Remediation wave 1 + 2 | 7 branches, all merged |
| Agent K round 2 | **REJECT** — 21 blockers |
| Remediation R1–R4 | 4 branches, all merged |
| Merge-integrity audit | **no content lost**; 15 mis-resolving citations (fixed) |
| Agent L | **NOT READY TO BUILD** |

## 5. Verified mechanically at head (not asserted)

- 16 packages, `076`–`091`, each number used once, no gaps.
- **45 dependency edges, exact parity across all four surfaces** (plan §2 mermaid, plan §3, registry §2.1,
  registry JSON `depends_on`); every dependency strictly precedes its dependent; DAG acyclic.
- `OFFLINE-VERIFY-v1`: the CI gate **executed from `ci.yml`**, exit 0 — 4 tagged blocks, 1 distinct body,
  2017 bytes, 10 clause anchors, 0 unfenced tags, 0 unterminated fences,
  sha256 `afb5184d58b62da5cb03cb8c4c7923953b4206c52f8afa23dee6403069fe6344`.
- pgTAP floors present and honest: 17 files, 305 planned assertions, `110_money_authz_matrix.sql` `plan(18)`.
- Ratification record: 159 rows, **zero duplicate ids**.

## 6. Why the verdict is NOT READY

**The blocking defects are not the open owner decisions.** Those are honestly registered and correctly banded —
Agent L tested the banding and found no decision blocking `076`–`078` mis-classified as blocking nothing.

The blockers are **unregistered contradictions created by the remediation itself**. The decisive measurement:

| Document | `R2B` correction-id occurrences |
|---|--:|
| migration plan | 54 |
| package registry | 52 |
| physical schema spec | **0** |
| RPC contracts | **0** |
| RLS permission spec | **0** |
| door spec / money spec | **0** |

The mirror image also holds: `kernel.mark_refund_state` — sole writer of three `kernel.refund` statuses and of
`stripe_refund_ref` — is contracted in the RPC spec and the schema spec and appears **zero** times in the plan,
the registry and the RLS spec. By the corpus's own rule, *a contracted function absent from plan §8 is a
function nobody builds.*

**Root cause, and it is mine.** I scoped the remediation agents by file ownership so the concurrent merges
would stay tractable. That produced document-local repairs — precisely the failure pattern Agent K round two
had already named: *a repair that lands in the document hosting the defect and not in the artifact an
implementer builds from.* The scoping that made the merges clean is what made the repairs incomplete.

## 7. Where an implementer first stops

- **Registered (acceptable):** package `076`, on `CREATE ROLE crm_export_builder` — gated on `MD-2`/`O17`,
  recorded, banded, with the failure mode stated (*shipping the role without the policies is the one
  combination that is silently wrong*).
- **Unregistered (a readiness failure):** package `083`, on `kernel.issue_ticket_atoms` — `p_ctx` has no SQL
  type, `serial_no` has no generator, `signing_key_id` has no resolver, and RPC §6.3 and §7.1 **both** claim
  the inventory write, so `sold` increments twice and a second `issue` row violates a stated unique. Nothing
  warns the engineer, and the SEAM-1 derivation for the `081→083` move rests on the duplicated write set.

## 8. Shortest path to READY (the work plan)

1. **Replay `R2B` into the five documents it skipped** — schema §13.1/§13.2, RPC §6.3/§7.1/§20.11, RLS §5/§7.5,
   door and money specs. Three hook signatures are still in their pre-freeze form; under `SEAM-2a` that is a
   `42P13` hard replay failure, or a silent overload leaving the C26 compensate arm dead in production.
2. **Rule seven cross-document contradictions** (decisions, not transcription): the §6.3/§7.1 inventory write;
   the writer of `kernel.payment_native`; `cause_ref` grain; `append_door_manifest_delta`'s return type;
   `assert_may_request`'s arity (three live forms); the `kernel.tickets` writer set (4 vs 10); `078` seed
   semantics.
3. **Create the missing objects** — `failure_code` on `kernel.payout` and `kernel.refund` (both contracted as
   written, neither declared); a writer for `inventory_hold.status='converted'`; `venue.scan.fraud_flag`'s
   writer and the `result`-label rule; the `door.session_touch_interval` seed.
4. **Apply the outstanding `R-` filings** (`R-24`, `R-25`, `R-27`, `R-29`…`R-33`, `DR-1`). Note §20.14's status
   column is unreliable in both directions.
5. **Take five rulings in one sitting** — `ODR-1` (registry re-ratification: *no package may be authored at
   all* until it closes), `ODR-2`+`ODR-3` (outbox + `notify`, which fix `076`'s contents), `O17`/`MD-2`,
   `R2B-1` (`p_cause`'s value set, frozen at `085`), `O11` (same-tier precedence — no longer theoretical).
6. **Refresh both instruments and add one gate** — recount `ARCHITECTURE_FREEZE.md` and rebuild the owner
   register at HEAD; add a CI check that fails when a correction id appears in fewer documents than its own
   filing table names. **The corpus has exactly one automated corpus-level gate today, and it guards one
   predicate.**

## 9. Owner decisions — 123 open, across 22 namespaces

`PHASE_2_OWNER_DECISION_REGISTER.md` (new, this session): `ODR-1`…`ODR-123`, deduplicated from ~170 filings
with evidence per merge. **7 block the start · 27 block a named package · 58 block a surface or flag · 31 block
nothing today. 25 default to the unsafe direction on silence.** Separately: 17 decisions already settled but
never marked closed, and 30 items that are defects rather than decisions.

Two structural findings: a consolidated index already existed (`PHASE_2_SCOPE_AMENDMENT_2026_08.md` §14,
`OD-01`…`OD-81`) and is stale, reaching none of `O11`–`O16`, and its `OD-nn` collides with the role model's
`OD-1`…`OD-11` by a leading zero. The richest register in the corpus — RLS §15.7's `MD-1`…`MD-19` — is
referenced by no other register.

## 10. What is genuinely sound

The physical layer. Every table traced is literal and buildable: columns with types, PK, FKs with delete rules,
CHECKs as SQL, uniques and partial uniques, indexes, immutability class, RLS class, write authority. Enum wire
form settled (`text` + CHECK, asserted). Money representation unambiguous (integer minor units). The global
lock order is concrete enough to write bodies against. `G-15` (the manifest two-shape defect) is closed
field-by-field. The door session/token lifecycle is closed across six documents. `kernel.payout`'s `status` and
`hold_state` machines are closed with a named writer per value.

## 11. Notable defects closed this session

The offline door predicate was byte-perfect across four CI-gated mirrors and **uncomputable** — no contract
delivered its fields, so the offline door admitted atoms the online door refuses. Refund tiers were per-call,
so one `org_finance` could drain any order in N sub-threshold calls. `kernel.payout.status` had no `held` label
while four documents and a ratified ruling stored `held`. Two contact-consent tables were contracted by four
documents and created by none, and would have produced exports reading *"nobody consented"* while balancing
perfectly. The role model still ordered three abolished functions built, one of which reinstates a closed
privilege escalation. Six routine-layer forward references would have replayed green and failed at runtime.

## 12. Process findings worth keeping

- **Six concurrent passes each claimed the same "next free" ratification ids.** Every collision was renumbered
  by hand. Two later passes fixed it by reading the maxima first and reserving disjoint blocks — the fix is
  practice, not a rule, and it should become a rule.
- **Count-without-enumeration drift bit this corpus five times**, including inside the register that tracks
  drift, and including twice in my own merges.
- **File-ownership scoping produces document-local repairs.** See §6.

## 13. Decision

```
PHASE 2 IMPLEMENTATION: NO-GO

REASON:   Agent L (independent) returns NOT READY TO BUILD.
          The last two remediation passes repaired only the documents they owned;
          five documents an implementer builds from still state the pre-repair design.
          First unregistered stop: package 083, kernel.issue_ticket_atoms.

FREEZE:   NOT WRITTEN. Task 14 was conditioned on READY.

NEXT:     §8 items 1-3 close the gap to READY. Items 5 and 9 are the owner's and
          cannot be delegated. No production change is required or authorised.

STATE:    production untouched (ledger 89, zero migration diff);
          phase2/consolidation @ 8c06c60 is the authoritative design corpus.
```
