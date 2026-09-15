# Release sprint — deployment-ready marketplace candidate by Fri 18 Sept 2026

Owner directive 2026-09-14 (Mon, evening). Four sessions in parallel. **Supersedes
`RELEASE_COMPLETION_ESTIMATE_20260914.md`** (its serial-A staffing assumption no longer holds; kept for history).
Authorized: reassigned isolated development, local testing, review, release preparation. **Still requires its
own authorization:** hosted builds, shared-sandbox mutations, production deployment, credentials, feature activation.

## Scope (frozen)
IN: approved Premium batches 1–4 · required payment/hold (127 + L1 edge coupling), refund (126, F8 client state),
notification privacy (128 + client rebind), recovery/error-state corrections (CFT-607, D9-UX-1, F3) · integration +
verification · already-reviewed admin delivery on its own track.
OUT (backlog, preserved): C's remaining Premium P0/P1 (303, 405, 401r, 408, 409, 606, 503, 703, 507, 104, 501r)
and the 14 optional items; D-AN1/AN2/AN3; native signing/scanning activation (FL-3); L3/L4; F10; `auction-media`
remediation rides separately (P1). Build 16 stays the historical tested pin.

## Deadline-backward schedule
| Day | Must be true by end of day |
|---|---|
| **Mon 14** | Board published; B has the 126 package; C has scope + device-plan ask; D has reviews + rehearsal ask; A's 128 fold-ins committed and sent to D for review |
| **Tue 15** | 128 review returned; A corrects; **contract v2 frozen and sent to C** (slips to Wed AM if the review finds a blocker). B: 126 parts 2–3 + 193 written. C: device test plan + build config drafted; C-2 recovery work started. D: 128 review done; 126 acceptance cases drafted; D-INT0 timing known. A: D-AR1 admin review; owner decision batch sent |
| **Wed 16** | **126 review-ready** (B) → D reviews same day → A merges 126 onto the release branch. B starts L1 edge work. C: 128 rebind done (C-1), C-2 done, unit/SC green. A: integrates 121 (PR #58) → 123 → 124 → 125 (PR #62) onto the release branch; CI green. **SBX-1 window** if the owner opens it (124, venue kit, previews) |
| **Thu 17** | B: L1 edge + deno tests + review done → A merges. C: batches 1–4 + C-1/C-2 rebased; gated-surface diff reviewed. **A cuts the candidate snapshot (pin) by midday.** D: full integrated-chain rehearsal + regression on the snapshot (D-INT1); A resolves findings. **SBX-2** (apply 125→128, deploy the two edges, DV-611) if authorized. Owner authorizes the hosted build |
| **Fri 18** | Build cut from the pin (EAS preview, sandbox). Cold-launch gate; targeted handset plan (C + owner). Fixes only if blocking; re-pin only if code changes. **Release packet**: deployment order, compatibility checks, rollback/recovery, observation plan, remaining owner authorizations |

**Reserve:** Thu PM + Fri are verification and packet, not coding. Anything not merged by Thu midday is cut from
the candidate, not squeezed in.

## Task board
`Acceptance` is what closes the task; `Dep` names the exact upstream. One writer per file.

| ID | Owner | Deliverable | Dep | Due | Acceptance |
|---|---|---|---|---|---|
| A-1 | A | 128 fold-ins: column-scoped SELECT on `push_tokens` (hash unreadable); epoch no-advance guard | — | Mon | 195 +assertions with negative controls; CI table gate green; commit sent to D |
| A-2 | A | 128 independent review cycle with D; corrections | A-1, D-3 | Tue | D reports no blocking finding; 195 green; whole suite ran |
| A-3 | A | **Freeze 128 contract v2**, one versioned document to C (incl. every-cold-launch clause, sunset, error map, `contract_version`) | A-2, decision **O-3** | Tue EOD / Wed AM | contract file in `docs/release`; C ack |
| A-4 | A | Owner decision batch (below), one message | — | Mon | sent |
| A-5 | A | D-AR1: review `admin/analytics-redesign @ 64f26f9` (separate track) | — | Tue | approval recorded; no marketplace coupling |
| A-6 | A | Integrate 121 → 123 → 124 → 125 onto `release/convergence-135`; registry rows; CI green | PR #58, PR #62 as-is | Wed | CI id; guard passes; registry updated |
| A-7 | A | Merge B-1 (126) after D-4 review; then B-2 (L1 edge) after review | B-1/D-4, B-2 | Wed / Thu | merged on the release branch; CI green |
| A-8 | A | Merge C-4 (client) with line-level review of C-1/C-2 changes; gated surface otherwise byte-identical | C-4 | Thu AM | diff evidence recorded |
| A-9 | A | **Candidate snapshot (pin)** + registry/manifest updated; hand to D-5 | A-6, A-7, A-8 | Thu midday | one commit id; CI green at head |
| A-10 | A | SBX-1 and SBX-2 hosted phases, serialized (A → D → C); ledger/census before/after | owner **O-1**; A-9 for SBX-2 | Wed / Thu | manifest §7 state; sandbox tip 128 in order; edge parity |
| A-11 | A | **Release packet**: deployment order (migrate → 11 edges → mobile), compatibility, rollback/recovery, observation plan, remaining authorizations | A-9, D-5, C-6 | Fri | packet section in the release package |
| B-1 | B | 126 parts 2–3 (rewire `build_daily_summary`, `money_overview`, `latest_summary`/`normalize_summary_body` onto `refund_facts`) + rollback restoring the applied bodies + pgTAP 193 A1–A8 | 048eeb1 cherry-picked | **Wed** review-ready | fixtures via `record_payment_refund`; A6 both directions; negative controls fail against 120's bodies; plan() stated; whole suite ran |
| B-2 | B | L1 edge coupling: webhook claim predicate → `pending/processing`; RPC → `release_reservation_for_payment(listing, buyer, payment.id)`; `create-payment-intent` inserts P2 before cancelling P1; deno tests for concurrency, delayed and duplicate events, rollback | B-1 review-ready | Thu | tests that fail against `df9e0d3`; reviewed by A; any 127 contract change requested from A, not made |
| C-1 | C | 128 client rebind to frozen v2 (error map, `contract_version` pin, sunset branch, every-cold-launch registration) | A-3 | Wed | unit green; DV-611 rows on the build |
| C-2 | C | Recovery/error-state: CFT-607; D9-UX-1 closed or CFT-301; F3 labels; F8 partial-refund state | — | Wed | unit + SC; each maps to a DV row |
| C-3 | C | Targeted device test plan + candidate build config (EAS preview, sandbox) | — | Tue | plan in C's checklist doc; config diff reviewed |
| C-4 | C | Batches 1–4 + C-1/C-2 rebased onto the release branch | A-6 | Thu AM | gated-surface diff empty except C-1/C-2 |
| C-5 | C | Handset verification on the build (with owner) | build authorized **O-2**, C-3 | Fri | DV rows PASS with server read-backs; open items explicit |
| D-1 | D | Automated sandbox acceptance + cleanup on kit `62ec887`; optional phase-2 steps in the runner | — | Tue | dry run locally; runbook current |
| D-2 | D | D-INT0 pre-snapshot rehearsal on A's head | — | Mon/Tue | timing + breakage report |
| D-3 | D | 128 authorization-boundary review (cold read, own negative-control probes, then diff vs A's rounds) | A-1 | Tue | written findings with probe output |
| D-4 | D | 126 independent money-semantics review vs A1–A8 (cases drafted before B's tests) | B-1 | Wed | findings; every case traced to the contract text |
| D-5 | D | Full integrated-chain rehearsal + regression on the snapshot (fresh + production order, rollback battery, full pgTAP, Gate-2, manifests, `expected_grants`) | A-9 | Thu | counts per check; A witnesses |
| D-6 | D | Admin delivery closes on its track after A-5; no new scope | A-5 | Wed | recorded |

## Critical path
Two chains, both must land by Thu midday:
- **Money chain:** B-1 (Tue–Wed) → D-4 (Wed) → A-7 (Wed) → B-2 (Wed–Thu) → A-7 (Thu AM) → A-9.
- **Notification chain:** A-1 (Mon) → D-3 (Tue) → A-2/A-3 (Tue) → C-1 (Wed) → C-4 (Thu AM) → A-9.
Then serial: A-9 → D-5 + SBX-2 (Thu) → build (Thu PM/Fri AM) → C-5 (Fri) → A-11 (Fri).
Parallel throughout: C-2/C-3, D-1/D-2, A-5/A-6, B-1 while A-1..A-3 run.
**Longest pole is B-2 landing Thu AM** — it depends on B-1 being clean on first review. If B-1 needs a second review round, B-2 slips to Thu PM and the candidate pins Thu EOD with edge tests reviewed Fri AM.

## Is Friday achievable — honest answer
**Deployment-ready as defined (pinned commit + artifact, checks passed, no unresolved blocking review findings,
targeted sandbox + device acceptance, deployment plan, authorizations listed): achievable Friday, conditional on
three things outside the sessions' control:**
1. **O-1** the sandbox window (SBX-1 by Wed, SBX-2 Thu) and **O-2** the hosted build authorization by Thu — without
   them the candidate exists but "sandbox and device acceptance completed" is not met.
2. No review round finds a blocking defect that needs a design change (three of three prior rounds found defects;
   the fold-ins are small, but that history is the main risk to Tue/Wed).
3. Handset verification fits Friday: C's plan is targeted, but a failing DV row Friday afternoon means a Monday
   re-pin, not a Friday one.
Most likely slip if any condition fails: **1–2 working days**, landing Mon 21 / Tue 22, with the pin and packet
done Friday and device acceptance the open item. **FL-2 (authorized production release)** is not on this
sprint's clock: it needs the P0 gates (apply/deploy authorization, `AUTODEPLOY-VERIFIED-OFF` + empty
`git_branch`, deploy-window schedule with payout-cron pause + orphan reconciliation, Stripe
`payment_intent.canceled` subscription, PFA-32) and is listed in the packet, not scheduled here.
**Safe scope cut if the money chain slips:** ship 127 (L2) + 126 + 128 and defer B-2 (L1 closure) to the next
candidate with L1 recorded as an open, disclosed defect — never the reverse (no waiving a security or money
defect to hit the date).

## Owner decisions (batched; one message)
| | Decision | Recommendation | Consequence of no answer by |
|---|---|---|---|
| O-1 | Authorize the shared-sandbox window: SBX-1 (124, venue kit + your MFA step, checkout previews) **and** SBX-2 (apply 125→126→127→128, deploy `stripe-webhook` + `create-payment-intent` to sandbox, DV-611) | Yes, one authorization covering both phases, serialized through A | Wed: sandbox acceptance cannot complete Friday |
| O-2 | Authorize the hosted candidate build (EAS preview profile, sandbox) from A's Thursday pin | Yes | Thu AM: no device verification Friday |
| O-3 | 128: accept the transitional plant-then-claim risk on legacy hash-less rows, bounded by the every-cold-launch clause + NULL-hash monitoring | Accept | Tue EOD: contract cannot freeze; C-1 slips a day |
| O-4 | C-2 scope as listed (607, D9-UX-1, F3, F8) — confirm or amend | Confirm | Proceeding as listed unless amended |
Already decided, not re-asked: 126 stays 126 (129 withdrawn); 121 → 123 → 124 → 125 order; Build 16 pinned; D9c closed.
