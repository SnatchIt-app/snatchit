# Owner-ruling ratification + economic-consistency + final pre-activation backend report

**Train:** owner-ruling ratification · economic consistency · final pre-activation backend. **Date:** 2026-09-03.
**Scope:** backend / architecture / money / production-readiness only. No UI work. **Nothing was applied, deployed, configured, activated, signed, or moved in production.**

This report answers the 28 required questions after the section summaries. Evidence lives in `docs/phase2/_impl/K*.md` (KINV, KADV, KM5, KT2, KRECON2) and the ruling/matrix/PFA files; every verdict below was executed against a local rehearsal replay, not inherited.

---

## 0. STATE VERIFICATION (read-only)

| | |
|---|---|
| **Branch** | `feature/venue-native-and-product-v2` |
| **HEAD (entry)** | `cf9b780`; this train's commit is authored on top |
| **PR / CI** | [#52](https://github.com/SnatchIt-app/snatchit/pull/52) open, base `phase2/consolidation`; CI green on `cf9b780` |
| **Migration range at tip** | `000`–`092` (live) + 5 timestamped + **`093`–`101`** authored/unapplied |
| **Production ledger (READ-ONLY)** | **107 rows**, max `20260902003623`, ends at `092_notify_reduced` + the 5 website migrations |
| **Production 093–101** | **NOT APPLIED** (no `kernel.organization_obligation`/`payout_reversal`/recovery tables present) |
| **Production flags/config** | only `feature.native_issuance_enabled=false`; the 093/099 keys absent (unapplied) |
| **Production signing keys** | **0** |
| **Production edges** | native primary edges **NOT DEPLOYED**; `stripe-webhook` at the pre-native build |
| **Production cron** | 19 (none of this train's) |

Reality matches the expected baseline exactly. No discrepancy. **Production was inspected read-only only.**

---

## 1. WHAT THIS TRAIN CHANGED (all authored, DARK, unapplied)

- **Migration 100** `venue_obligation_excludes_held_commission` (md5 `58402dbfec629abaa10b6866ec8abf29`) — the G4 economic-consistency fix. **Seams-only:** re-creates `kernel.settlement_primary_lines` and `kernel.settlement_royalty_lines` so a post-payout reversal (chargeback or refund_void) debit is capped at what the venue **received** = `face − refund_exposure − prior_cb − held_commission_for_order`. No new object, no new column, no close_settlement change, census unchanged (kernel functions stay 146).
- **Migration 101** `recovery_venue_scope` (md5 `8d79dbc7663ebe9caa94271034f9de7e`) — closes the adversarial **P0**: a `transfer_reversal` recovery now must match the obligation's **originating venue**, not just its org (`kernel.organization_obligation_recovery_guard` body-only re-create). No census change.
- Tests: `166` (rewritten, obligation-fix + conservation, 39/39), `167` (new, cross-venue recovery refusal, 24/24), `153` H58 regex fix.
- Docs: G1–G5 + Gate-M ratification text (`FINAL_ACTIVATION_BLOCKER_RULINGS.md`), the four rulings, the activation matrix (fourth revision, with the CODE-COMPLETE→ACTIVATED legend), `PFA-PT-5`, and the evidence reports.
- **093 is byte-identical** (`0e6729d72cf3f61b0a00c2683962d400`); assembler G-4 PASS.

**Verification (final, independent):** full `000`–`101` replay **116/116**; Gate-2 `tables=27 functions=70 policies=37 triggers=26` unchanged; pgTAP **plan=3549 ok=3545 not_ok=4** = only the 4 documented local deltas (`060`×2 TODO, `132`×2 db-name), "matches the expected local baseline"; assembler G-4 PASS; vitest **489**; typecheck/lint clean; `100`+`101` rollback battery clean (kernel functions → 146).

---

## 2. THE G4 ECONOMIC FIX, IN FULL

Canonical fixture (executed, test 166 §A): face **10000**, funded held commission **1000** (bps 1000), venue paid **9000**, **full** post-payout chargeback **10000**.
- Before: chargeback line −10000 → net −10000 → obligation **10000** (overstated by the held commission the venue never received).
- After 100: chargeback line **−9000** → net −9000 → obligation **9000**. Conservation from ledger rows only: `face 10000 = venue-paid 9000 + held-commission 1000`; `dispute 10000 = obligation 9000 + held-commission 1000`. The held commission **payout** is **untouched** (1000/pending/held/unfunded_settlement) — no promoter payout ever leaves pending/held.

**Why the held-commission PAYOUT is not converged here (specified, deferred).** The venue's *obligation* is the owner's hard requirement and is now correct standalone. Converging the held *payout* down to its surviving amount is a separate concern that is **not needed for launch** (promoter payout is DARK) and that G4 itself defers ("before the FIRST future promoter commission payout, a separate owner ruling and architecture for paid-commission recovery/receivable is required"). An earlier draft void-and-re-minted the held payout inside `close_settlement`; that created a **second** `promoter_commission` row per attribution and (a) broke the single-minter fence, (b) broke single-row `cause_ref` lookups, and (c) made every "latest payout by `created_at`" reader — including the **production** promoter-status projection at `090:1325` — nondeterministic (two rows share the transaction-frozen `now()`). It was removed; the obligation fix needs none of it. The payout convergence is specified for the future ruling in **PFA-PT-5**.

**Partial-reversal open question (PFA-PT-5).** A partial post-payout reversal has two defensible models — proportional (obligation = reversed × venue-share) vs window/FIFO (obligation = reversed, capped at venue-received). **Both satisfy "obligation ≤ venue-received" for the canonical full case.** Migration 100 ships the window/FIFO model (matching the ratified cumulative-cap mechanism); a 4000 partial on a 10000/1000 order books 4000, where proportional would book 3600 (a 400 difference). This is a narrow owner choice, not a silent defect, and is filed as PFA-PT-5 item.

---

## 3. THE ANSWERS

1. **Branch / HEAD / PR / CI.** `feature/venue-native-and-product-v2`; entry `cf9b780`; PR #52 open (base `phase2/consolidation`); CI green.
2. **Migration range at repo tip.** `000`–`101`; **`093`–`101` unreleased/unapplied**.
3. **Production ledger.** 107 rows, ends at `092_notify_reduced` + 5 timestamped website migrations. Unchanged.
4. **G1 internally consistent and ratifiable? YES.** The stale claim that the unguarded backdating defect "still exists" is struck — `093 catalog.update_event_session` refuses a backward `ends_at` once economic weight exists (issued atom / paid|partially_refunded|refunded order / door scan / any settlement), refuses newly setting an already-elapsed `ends_at`, permits safe `starts_at`/`doors_at` moves and future postponement, `platform_admin`-only bypass. Value `"72 hours"` (JSON string; number forms forbidden; interval-type guard; dual control). Ratifiable; not set in production.
5. **G2 internally consistent and ratifiable? YES.** Value `"7 days"`, anchor `max(event_session.ends_at)` over covered lines. The conjunction is **nine** fail-closed predicates enumerated from live SQL: `unbounded_refund_exposure, maturity_policy_invalid, covered_set_unresolvable, event_cancelled, maturity_instant_unknown, maturity_not_elapsed, refund_in_flight, dispute_open, dispute_unabsorbed` (+ execution-time `refund_exposure_stale`). No single predicate releases; re-evaluated at close, request, execution.
6. **G4 pro-rata surviving-revenue economics correctly implemented? YES** for funding (098, PFA-PT-4) and for the venue obligation (100, full reversal). The partial-reversal obligation model is an explicit owner choice (PFA-PT-5). Held-commission **payout** convergence is specified/deferred (§2).
7. **Do venue obligations exclude held promoter money the venue never received? YES** (full reversal: obligation 9000, not 10000). The held commission is a separate dark accrual (payout untouched), not part of the venue's debt.
8. **Does G5 organization-obligation + recovery architecture conserve money? YES.** Conservation closes from ledger rows only (KADV five no-commission cases + KM5 commission full-reversal). Recovery facts (096) are append-only, Σ-capped, and now venue-scoped (101).
9. **Is cross-venue leakage impossible by construction? YES.** 097 ring-fences the chargeback arm to the originating venue (test 163); 101 closes the recovery-facts hole so a `transfer_reversal` recovery must match the obligation's venue (test 167). Cross-org isolation also holds.
10. **Can Gate-M C29/C30/C31 honestly remain deferred for launch?** **C29 (reserve/clawback): NOT REQUIRED. C30 (fan-side chargeback debt): NOT REQUIRED. C31 (full double-entry): DEFERRED, conditionally met** — conservation was proven to close without any hand-derived quantity for the no-commission chain (5 cases) and the commission full-reversal case. Gate-M remains a REQUIRED gate before **payout** activation; the re-attestation block is drafted, PENDING signature.
11. **Is deletion event-anchored? YES.** `kernel.deletion_blockers_money` anchors on `max(coalesce(event_session.ends_at, starts_at))` over the buyer's paid orders; the old `deletion.refund_possible_window_hours` is orphaned (read by no logic). No payment-time path remains.
12. **Candidate deletion hold durations (not chosen).** 72h / 120h / 180h / 720h (30d) / 2880h (120d). Tradeoff: the Stripe dispute window runs ~120 days after the event, so anything below ~2880h leaves a tail of post-hold disputes that must be caught by the obligation/recovery path rather than by blocking deletion; longer holds delay legitimate erasure. **Owner-unset; do not choose.**
13. **Is A9 refund executability engineering-ready?** **YES — ENGINEERING READY, DARK/UNDEPLOYED.** Executor + `claim_refunds_for_execution` + `get_refund_execution_context` exist; the dark cron invoker is authored (099, `refund.executor_enabled=false`); PFA-23 direct arm reachable via `request_order_refund`. Missing only: deploy + arm.
14. **Do native dispute writers have real safe callers? YES.** The webhook native branch calls `record_dispute_native`/`mark_dispute_state`; authority + idempotency + out-of-order handling re-attacked clean (KADV). The 097 rail guard accepts a native (order- or sale-linked, or `native_primary`-mode) payment and rejects a genuinely legacy one.
15. **Is `transfer.reversed` safely wired? YES.** Native routing → `record_payout_reversal` (facts, `trr_` idempotent); full drives `paid→reversed` via the existing edge; partial stays `paid` with a reversed-minor projection.
16. **Is failed-payout reconciliation safe? YES.** `claim_failed_payouts_for_reconcile` + `reconcile_payout_transfer` + the executor's reconcile pass; never invents an outcome (404/mismatch/ambiguous stay `failed` + page); amount server-derived.
17. **Is the payout executor engineering-ready but dark? YES.** Claim-lease, server-derived amount/destination, destination immutability, maturity re-eval, exposure guards, reversal facts, failed-reconcile — all present; DARK (undeployed, `payout.executor_enabled=false`).
18. **Payout-destination replacement — Day-2 or launch-blocking?** **Day-2.** `set_org_payout_destination` has no staging producer for a bound org; the `connect-onboarding mode:'replace'` flow is specified (KINV). The edge must stop advertising the non-working `409 destination_unusable` recovery. Not launch-blocking (a first onboarding binds once).
19. **Does an actual credential signer exist? NO — HARD ACTIVATION BLOCKER.** No `credential-sign` component produces a ticket signature; `kernel.issue_ticket_atoms` only pins `signing_key_id`; **`kernel.tickets` has no signature/token column at all**. A signing *key* existing ≠ tickets can be signed.
20. **Is G3/KMS the next signing blocker?** The KMS ceremony (G3, approved in principle, not executed) produces the *key*; the actual blocker is the **signer/verifier component + signature storage** (question 19). Order: build the signer (+ a signature column) → KMS ceremony provides the key → issuance can sign. Both precede native issuance activation.
21. **Does on_sale vs SALEABLE require another owner ruling? YES.** A8 is ambiguous; code implements "A" (`publish_event(...,'on_sale')` gates on nothing SALEABLE; only checkout does). Two texts drafted — **A8a** (on_sale = commercially published, checkout may be unavailable; current) vs **A8a′** (transition must satisfy SALEABLE). Owner picks.
22. **Is tax an activation blocker?** **OWNER/LEGAL decision, not an engineering gate.** Zero tax model (0 keys/functions/columns). Launch can architecturally run with tax = not-applicable only if the ratified product scope/jurisdiction confirms it; that confirmation is not in the corpus. Do not silently charge zero.
23. **Remaining P0 / P1.** **P0: 0 open** (the adversarial cross-venue-recovery P0 is fixed by 101). **P1 (owner decisions, non-blocking as code):** `signing.%` config keys not dual-controlled (a single admin can arm the monitor / pin the fingerprint); the pre-transfer native-resale dispute gap (fail-closed, retried, alerted — resale rail dark); the partial-reversal obligation model (PFA-PT-5). **Hard activation blocker (not a code defect):** the credential signer (Q19).
24. **Remaining owner decisions.** Sign G1, G2, G3, G4, G5; Gate-M re-attestation; ratify `kernel.claim_refunds_for_execution`; sign PFA-PT-4 (promoter basis) and PFA-PT-5 (obligation cap + partial-reversal model + deferred payout convergence); on_sale ruling (A8a/A8a′); tax (legal); deletion hold duration; `signing.%` dual-control; written-off-late-receipt policy; 093-forward-only acknowledgement or a 093 rollback.
25. **Remaining production operations.** Apply `093`–`101`; expose `catalog`+`venue`; deploy connect-onboarding / stripe-webhook (native) / refund-execute / notify-report / primary-checkout / payout-execute; **build + deploy the credential signer**; run the KMS ceremony; arm the KMS monitor + the refund/payout invokers (config, quorum); set owner config values; onboard one org; flip `feature.native_issuance_enabled`.
26. **Recommended sequence to FIRST SAFE VENUE-DIRECT SALE.** (a) owner signatures (G1/G2/G3, refund-claim ratification, Gate-M) + 093-forward-only ack; (b) apply 093→101 (ledger 107→116); (c) build + deploy the credential signer and add the ticket signature column (new migration) — **hard blocker**; (d) KMS ceremony (key); (e) deploy connect-onboarding → stripe-webhook → refund-execute → notify-report; (f) onboard one org; (g) owner config (inventory → ticket.expiry_grace → payout.settlement_maturity_interval → deletion.post_event_hold_hours after the refund tick is proven → fee.buyer_service_bps); (h) expose catalog+venue (late); (i) deploy primary-checkout; (j) resolve on_sale/SALEABLE (A8a/A8a′) and tax; (k) flip native_issuance_enabled; (l) first controlled quote → payment → mint → refund proof.
27. **Recommended sequence to FIRST SAFE VENUE PAYOUT.** (a) **G5 signed** + Gate-M attested; (b) a matured settlement (`maturity_not_elapsed` the only remaining hold); (c) deploy payout-execute; (d) human `request_org_payout` (aal2, destination pinned); (e) ONE manual single execution under two-person watch; (f) arm the payout invoker (`payout.executor_enabled=true`, quorum) only after (e); (g) threshold keys. Promoter payout is in neither sequence (A4/G4; dark).
28. **Production not mutated.** Confirmed — read-only inspection only; nothing applied, deployed, configured, flipped, signed, or moved.

---

## 4. SUCCESS-CONDITION LEDGER

| Condition | Status |
|---|---|
| Promoter economics conserve correctly | **YES** (098 funding + 100 obligation; conservation ledger-derived) |
| Venue debt never includes money the venue never received | **YES** for full reversal (100); partial model is an owner choice, both variants ≤ venue-received |
| Post-payout debt durable and auditable | **YES** (094 obligation + 096 recovery facts) |
| Cross-venue leakage impossible by default | **YES** (097 arm + 101 recovery, tests 163/167) |
| Refund execution mechanically safe | **YES** (dark) |
| Dispute writers actually wired | **YES** |
| Payout execution mechanically safe but DARK | **YES** |
| Deletion not on an unsafe payment-time clock | **YES** (event-anchored) |
| Migration chain replays clean | **YES** (116/116, Gate-2 unchanged) |
| No hidden money path | **YES** (assembler G-4 PASS; append-only guards hold vs table owner) |
| Remaining owner decisions narrow and explicit | **YES** (§3 Q24) |
| Remaining production operations enumerated | **YES** (§3 Q25) |
| Nothing deployed or activated | **YES** |

**Optimised for proving what is and is not safe, not for "READY."** The backend is economically consistent and mechanically safe in the dark; the gates to activation are owner signatures, the credential signer, and the enumerated deploy/config steps — not unproven engineering.

STOP. No production mutation, no deploy, no Stripe, no KMS, no secret, no signature.
