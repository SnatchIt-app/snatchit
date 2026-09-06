# Findings tracker — audit 2026-09-05 → program disposition

Status vocabulary: **CONFIRMED** (reproduced against `eadd456` source; see `investigation/`), **PARTIAL** (true with a
narrower reach than stated), **NOT REPRODUCED**, **FIXED-IN-BRANCH** (implemented + tested in this program; not
deployed), **DEFERRED** (out of this program's scope; reason given), **OWNER DECISION**.
Deployed-state caveat: production edge code is ahead of `main` for three functions (`00_BASELINE.md`); source
verification is not production verification.

| # | Finding | Verification | Reach correction | Package | Status |
|---|---|---|---|---|---|
| F01 | Intent for another buyer's reservation; stale intents; multiplicity | CONFIRMED (A §1) | multiplicity is cross-buyer/cross-mode (per-buyer pending PI is reused); auction branch does reject sold/cancelled — the gap is a live foreign reservation | 1 | in progress |
| F02 | Webhook retry completes without settling the sale | CONFIRMED (B §1, real handler: 500 → 200, RPC called once, listing unsold) | practical trigger = client died ∧ webhook RPC failed, but the consequence is worse than stated: the reservation cleanup cron re-lists the paid listing and a second buyer's promotion 500-loops on the partial unique index | 2 | pending P1 core |
| F03 | Sale-marking RPCs need no payment | CONFIRMED (A §1) | blast radius is stranded inventory + seller lock-out, not unpaid transfers (061/confirm-payment/webhook all gate transfers on `succeeded`) | 1 | in progress |
| F04 | Reservation duration/extension unbounded | CONFIRMED (A §1) | bounded by `ends_at`, not "indefinite"; `p_minutes NULL` ⇒ never-swept reservation | 1 | in progress |
| F05 | Refunded → succeeded regression | CONFIRMED (B §1, C §1) | webhook writer leaves a contradictory row (`refunded_at` survives); the dangerous case is dispute-lost (charge not refunded at Stripe ⇒ payout probe passes) | 2 (writers) + 3 (DB guard) | in progress |
| F06 | Refund/dispute failures acknowledged | CONFIRMED and broader (B §1, §4) | freeze failure and dispute-lost mark failure complete the event as SUCCESS (no error recorded); `webhook_retries` has no writer | 2 (ack semantics) + 3 (branches) | in progress |
| F07 | Dispute between check and payout loses the mapping | CONFIRMED (C §1) | window includes two Stripe GETs; status stays `disputed`, audit insert skipped, `tr_` id nowhere in DB; sweep excludes disputed rows so F08 recovery never sees it | 3 | in progress |
| F08 | Payout recovery leans on 24h idempotency | CONFIRMED (C §1, §2) | >24h double-pay happens with an unchanged destination too; concurrent releasers are NOT a double-pay today | 3 | in progress |
| F09 | Evidence path string satisfies risk signal | PARTIAL (C §1) | downgrades one HIGH signal; cannot move money alone | — | DEFERRED to a risk-policy slice (one-line storage.objects check in the RPC) |
| F10 | Deletion severs unsettled obligations | CONFIRMED on `main`; PARTIAL on deployed code | deployed tombstone sweep (Phase-2 `078`) already blocks BP-6..BP-11; remaining gaps: paid-with-no-transfer, expired-unrefunded, deferred seller payouts without review status; `payout_decisions`/`disputes` not anonymized | 3 | in progress; integration dependency: deployed sweep must call the new predicate |
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
| N1 | `cleanup_expired_reservations` re-lists a listing that already holds a `succeeded` payment | B §2 | 2 |
| N2 | Second buyer's capture after a partial-unique collision has no refund path (row stays `pending`, webhook loops) | A §5, B §4 | 2 (unfulfillable → compensation) |
| N3 | `mark_listing_sold` on webhook retry releases the reservation as a side effect ("expired" branch) | B §4 | 1 |
| N4 | `finalize_auction` is EXECUTE `authenticated` and does not consider a live Buy-Now reservation (dual eligibility) | A §3(e) | 1 (priority rule) — `finalize_auction` grant itself out of scope |
| N5 | `DAY5_MANUAL_REFUND_PLAYBOOK.md` Part 2 direct `UPDATE transfers` is blocked by the 0562 guard; its manual dashboard transfer is the double-pay path | C §7 | docs (P3 report) |
| N6 | Production edge code ahead of `main` (deletion guards, tombstone delete-account) — release dependency | baseline | lead |
