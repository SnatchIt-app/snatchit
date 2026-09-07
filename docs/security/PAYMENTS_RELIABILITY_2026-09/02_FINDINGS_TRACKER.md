# Findings tracker — audit 2026-09-05 → program disposition

Status vocabulary: **CONFIRMED** (reproduced against `eadd456` source; see `investigation/`), **PARTIAL** (true with a
narrower reach than stated), **NOT REPRODUCED**, **FIXED-IN-BRANCH** (implemented + tested in this program; not
deployed), **DEFERRED** (out of this program's scope; reason given), **OWNER DECISION**.
Deployed-state caveat: production edge code is ahead of `main` for three functions (`00_BASELINE.md`); source
verification is not production verification.

| # | Finding | Verification | Reach correction | Package | Status |
|---|---|---|---|---|---|
| F01 | Intent for another buyer's reservation; stale intents; multiplicity | CONFIRMED (A §1) | multiplicity is cross-buyer/cross-mode (per-buyer pending PI is reused); auction branch does reject sold/cancelled — the gap is a live foreign reservation | 1 | FIXED-IN-BRANCH (P1 rev2; pgTAP 120 58/58, checkout-intent 23/23; reviewed) |
| F02 | Webhook retry completes without settling the sale | CONFIRMED (B §1, real handler: 500 → 200, RPC called once, listing unsold) | practical trigger = client died ∧ webhook RPC failed, but the consequence is worse than stated: the reservation cleanup cron re-lists the paid listing and a second buyer's promotion 500-loops on the partial unique index | 2 | FIXED-IN-BRANCH (P2 rev2; settle_verified_payment; audit reproduction turned green; reviewed) |
| F03 | Sale-marking RPCs need no payment | CONFIRMED (A §1) | blast radius is stranded inventory + seller lock-out, not unpaid transfers (061/confirm-payment/webhook all gate transfers on `succeeded`) | 1 | FIXED-IN-BRANCH (P1; wrappers require bound succeeded payment) |
| F04 | Reservation duration/extension unbounded | CONFIRMED (A §1) | bounded by `ends_at`, not "indefinite"; `p_minutes NULL` ⇒ never-swept reservation | 1 | FIXED-IN-BRANCH (P1; server-fixed 10-min window) |
| F05 | Refunded → succeeded regression | CONFIRMED (B §1, C §1) | webhook writer leaves a contradictory row (`refunded_at` survives); the dangerous case is dispute-lost (charge not refunded at Stripe ⇒ payout probe passes) | 2 (writers) + 3 (DB guard) | FIXED-IN-BRANCH (P2 writers via contract + P3 `guard_payment_transitions`; 123 51/51) |
| F06 | Refund/dispute failures acknowledged | CONFIRMED and broader (B §1, §4) | freeze failure and dispute-lost mark failure complete the event as SUCCESS (no error recorded); `webhook_retries` has no writer | 2 (ack semantics) + 3 (branches) | FIXED-IN-BRANCH (P2 ack semantics + P3 branches; refund-dispute-webhook non-2xx on DB failure) |
| F07 | Dispute between check and payout loses the mapping | CONFIRMED (C §1) | window includes two Stripe GETs; status stays `disputed`, audit insert skipped, `tr_` id nowhere in DB; sweep excludes disputed rows so F08 recovery never sees it | 3 | FIXED-IN-BRANCH (P3; `tr_` always recorded, `reversal_required` + PAID_DURING_DISPUTE) |
| F08 | Payout recovery leans on 24h idempotency | CONFIRMED (C §1, §2) | >24h double-pay happens with an unchanged destination too; concurrent releasers are NOT a double-pay today | 3 | FIXED-IN-BRANCH (P3; per-attempt ledger, reconcile-before-POST; payout-races) |
| F09 | Evidence path string satisfies risk signal | PARTIAL (C §1) | downgrades one HIGH signal; cannot move money alone | — | DEFERRED to a risk-policy slice (one-line storage.objects check in the RPC) |
| F10 | Deletion severs unsettled obligations | CONFIRMED on `main`; PARTIAL on deployed code | deployed tombstone sweep (Phase-2 `078`) already blocks BP-6..BP-11; remaining gaps: paid-with-no-transfer, expired-unrefunded, deferred seller payouts without review status; `payout_decisions`/`disputes` not anonymized | 3 | FIXED-IN-BRANCH on main-based code (P3 rev2; `account_deletion_blockers` fail-closed, 124 40/40); RELEASE DEPENDENCY: deployed tombstone sweep must call the predicate (04 §0) |
| F11 | $0.90 fee rollout hazards | not in scope | — | — | OWNER DECISION: not implemented (10%+10% preserved) |
| F12 | Lot vs unit price semantics | not in scope | — | — | OWNER DECISION required before any fee change |
| F13 | Dev/preview builds share prod backend | acknowledged | — | — | DEFERRED (infra; this program never used production as staging) |
| F14 | Connect onboarding readiness/idempotency | not verified here | — | — | DEFERRED |
| F15 | Partial refunds/disputes ledger | partially addressed | `payment_refunds` + `amount_refunded_cents` (P3) record amounts going forward; no full ledger | 3 | partial |
| F16 | Recovery throughput/fairness | not verified here | — | — | DEFERRED |
| F17 | Pagination | not in scope | — | — | DEFERRED |
| F18 | CI lacks web tests / parity / edge checks | CONFIRMED (`ci.yml` `web` job builds only) | — | lead | FIXED-IN-BRANCH (jobs added; see `03_CI.md`) |
| F19 | Deployment parity/manifest | acknowledged | deployed-state deltas recorded in `00_BASELINE.md` | — | DEFERRED |
| F20 | Notification loss | not in scope | — | — | DEFERRED |
| F21 | Mobile proceeds math | not in scope | — | — | DEFERRED |
| F22 | Dependency advisories | not in scope | — | — | DEFERRED |
| F23 | Secure-storage crash gap | not in scope | — | — | DEFERRED |

New findings from this program's investigation (not in the audit):

| # | Finding | Source | Package |
|---|---|---|---|
| N1 (fixed P2) | `cleanup_expired_reservations` re-lists a listing that already holds a `succeeded` payment | B §2 | 2 |
| N2 (fixed P2: unfulfillable → sweep refund) | Second buyer's capture after a partial-unique collision has no refund path (row stays `pending`, webhook loops) | A §5, B §4 | 2 (unfulfillable → compensation) |
| N3 (fixed P1) | `mark_listing_sold` on webhook retry releases the reservation as a side effect ("expired" branch) | B §4 | 1 |
| N4 (fixed P1: Buy-Now hold priority) | `finalize_auction` is EXECUTE `authenticated` and does not consider a live Buy-Now reservation (dual eligibility) | A §3(e) | 1 (priority rule) — `finalize_auction` grant itself out of scope |
| N5 (docs update = launch blocker P3-e) | `DAY5_MANUAL_REFUND_PLAYBOOK.md` Part 2 direct `UPDATE transfers` is blocked by the 0562 guard; its manual dashboard transfer is the double-pay path | C §7 | docs (P3 report) |
| N6 (launch blocker, owner decision) | Production edge code ahead of `main` (deletion guards, tombstone delete-account) — release dependency | baseline | lead |


## Round 2 (converged RC, 2026-09-06) — independent review findings and dispositions

| Id | Finding | Source | Status |
|---|---|---|---|
| R2-M1 | Production `payments` shape (093: `native_primary`, NULL listing/seller) breaks the transition guard, blockers and contract | R2 §1 | FIXED-IN-RC (NULL-safe guard; `not_external_rail`; external-rail-only predicates; confirm-payment 409) |
| R2-M2 | Full/partial refund after payout never flags a reversal | R2 §2 | FIXED-IN-RC (`REFUNDED_AFTER_PAYOUT` / `PARTIAL_REFUND_AFTER_PAYOUT`) |
| R2-m3 | Payout amount ignores partial refunds | R2 §3 | FIXED-IN-RC (`PAYMENT_PARTIALLY_REFUNDED`, operator decision) |
| R2-m4 | Cumulative refund ledgered under one id | R2 §4 | FIXED-IN-RC (increment) |
| R2-m5 | Dispute freeze failure ACKed; no last-moment payout re-check | R2 §5 | FIXED-IN-RC |
| R2-m6 | Late captures (>2 h) outside `pending_stale` | R2 §6 | OPEN follow-up (04 §6) |
| R3-2.2 | Legacy orphan double-pay (no `transfer_group` on pre-ledger transfers) | R3 §2 | FIXED-IN-RC (legacy-aware pre-flight) + release step P3-b3 |
| R3-3.2 | Open attempt at rollback ⇒ old edge re-POST | R3 §3 | PROCEDURE (04 §3, rehearsed) |
| R3-1 | 132 env-dependent expectation; CI green explained | R3 §1 | FIXED-IN-RC |
| R1 | Production-only edge behaviours must survive convergence | R1 | FIXED-IN-RC (09 §2) |
| R1-policy | Request-time 409 vs always-accept | R1 / lead | OWNER DECISION — (B) implemented, (A) documented (09 §3) |


## Round 3 (2026-09-06) — sandbox readiness (R4), rollback integrity (R5), mixed versions (R6)

| Id | Finding | Status |
|---|---|---|
| R4-G1 | money-out gates refuse test-mode rows → sandbox cannot prove payouts | FIXED-IN-RC (sandbox-only switch, default off) |
| R4-G2/G8/G9/G12 | cron host hard-coded; Connect endpoint typing; no grace window; build 13 not re-pointable | DOCUMENTED (11 §1a) + harness handles G2 |
| R4-G14 | later recorder overwrote attempt evidence | FIXED-IN-RC (append under `subsequent`; succeeded→succeeded is a no-op) |
| R5-1 | rollback → old code pays full net on partially refunded orders | FIXED-IN-RC (gate D2 + archive/restore) |
| R5-2 | dropped attempt ledger → old sweep re-POSTs | FIXED-IN-RC (gate D1; drain procedure) |
| R5-5 | 130000 rollback tombstones BP-13-only identities; out-of-order rollbacks | FIXED-IN-RC (gates D6, O1, O2) |
| R5-6/7 | archive design; point of no return; forward-fix per class | IMPLEMENTED + DOCUMENTED (14) |
| R5-8 | §F gaps | FIXED (63/63) |
| R6-2 | confirm-and-release NEW + expiry OLD with cron live = double payout | FIXED-IN-PLAN (order + pause; 13 §2–§3) |
| R6-6 | first new sweep moves money on legacy rows | DOCUMENTED (13 §6; Q1–Q15 triage mandatory) |
| R6-4/5 | old webhook 500-loops until new webhook; resend cannot re-drive completed events | DOCUMENTED (13 §5) |
