# Release completion estimate — A/B/C/D (2026-09-14, A)

> **SUPERSEDED the same day by `SPRINT_PLAN_20260918.md`** (owner sprint directive: four-session parallel
> allocation, scope freeze, Fri 18 Sept target). This file's serial-A staffing assumption no longer holds; kept
> for history, not for planning.

Owner-requested. Inputs: the release package (through `1b3e603`), the registry, the sandbox manifest, and status
messages from B, C and D on 2026-09-14/15 (each from their own records; their estimates are labelled theirs).
**Nothing here is authorized; no production change.** Ranges, not percentages. `wd` = elapsed working days;
`h` = active hours. Elapsed ranges assume ≤2 wd owner latency per gate — every owner-paced item can stretch them.

## Reconciled state (outdated blockers cleared)

| Item | Now |
|---|---|
| C's Premium batch 4 | **complete** — head `9091397`, all four batches approved by A |
| D's admin visual direction | **approved** — handed to A at `admin/analytics-redesign @ 64f26f9` (supersedes light-theme/f9/a11y); admin-only, own deploy path, **not marketplace** |
| B's assignment | **closed** — 0 marketplace hours; 121 (PR #58) and 125 (PR #62) ride A's chain; native activation is a separate finish line |
| Migration 126 | **part 1 of 3 written** (`048eeb1`); the `129` renumber is an **unapproved proposal**, kept separate in the registry (`1b3e603`); number stays 126, order 126 → 127 → 128 |
| 127 / 128 | 30/30 and 41/41 after three review rounds; **not integration-ready** until a round returns clean; 128 has three residual findings dispositioned (package, last section) |

## Completion table — must-finish for the marketplace release (16 deliverables)

Row 9 is one bundled deliverable of C's 12 Premium P0/P1 items; **scope decision D1** moves it to optional.

| # | Phase | Owner · ID | Exact unfinished work | Depends on / owner decision | Active | Elapsed | Conf. | Evidence that closes it |
|---|---|---|---|---|---|---|---|---|
| 1 | Impl | A · 126-p2/3 | rewire `ops.build_daily_summary` + `money_overview` onto `ops.refund_facts`; pgTAP 193 A1–A8 (A6 both directions); census/manifest rows | none · D2 (number stays 126) | 4–6 h | 1–2 wd | High | 193 green on rehearsal; A6 negative control; CI table gate green |
| 2 | Review | A · 126-rev | independent review of the final 126 (owner required) | row 1 | 2–3 h reviewer + 1–2 h fixes | 1 wd | Med-High | reviewer report, no open finding; fixes committed |
| 3 | Impl | A · 128-fold | column `REVOKE SELECT (device_secret_hash)`; epoch no-advance guard + assertion; rollback header | none | 1.5–2 h | 0.5 wd | High | 195 +2 assertions; negative control on the REVOKE |
| 4 | Review | A · 127/128-R4 | fourth adversarial round on the final versions; corrections | row 3 | 3–5 h reviewer + 0–4 h | 1–2 wd (+1–2 if a 5th round) | **Med** — 3 of 3 rounds found defects | no blocking finding; 194/195 green; CI gates green |
| 5 | Impl | A · 128-contract | send C one versioned contract (v2 + fold-ins, every-cold-launch clause) | row 4 | 1 h | same day | High | contract in `docs/release`; C ack |
| 6 | Impl | C · CFT-611s | rebind client to v2: error map, `contract_version` pin, sunset branch | row 5 | 2–4 h (C) | same day | High | unit tests; DV-611 on Build 17 with 128 on sandbox |
| 7 | Impl | A · 127-edge | webhook: claim only `pending/processing`, call `release_reservation_for_payment(listing, buyer, payment.id)`; `create-payment-intent`: insert P2 before cancelling P1; deno tests; review | **D3** (sandbox edge deploy is outside the manifest) | 3–5 h + 1–2 h review | 1–3 wd | Med | deno tests; sandbox: P1 cancel → `no_claimable_row` / `live_sibling_attempt`, hold intact (edge_logs, ≥10 min lag) |
| 8 | Impl | A · A-contracts | A-07, A-09, A-10, A-11, A-12, A-13, A-14, A-17(405) | none | 8–14 h | 2–3 wd | Med-High | each recorded in the Premium backlog "Dependencies on A"; C ack |
| 9 | Impl | C · Premium P0/P1 | 303, 405, 401r, 408, 409, 607, 606, 503, 703, 507, 104, 501r (C's classification) | row 8; owner: A-01/303 quantity, F10, A-14, A-15 | 50–75 h (C) | 8–12 wd **if row 8 lands in 2–3 wd** | Med | unit + SC per item; DV rows on Build 17. **D1** |
| 10 | Integration | A · INT | integrate on the release base: 121 (PR #58) → 123 → 124 → 125 (PR #62) → 126 → 127 → 128; edges (row 7); batches 1–4 (+ row 9); fresh `LC_ALL=C` replay + production-order replay + rollback battery + full pgTAP + Gate-2/manifests/`expected_grants`; CI green; new pin | rows 1–8 (9) | 6–10 h | 1–2 wd | High — harness exists, 144-file chain already rehearsed for 125 | CI run id at the new head; both-order replay hash-identical; rollback battery count |
| 11 | Sandbox | A+D+C+owner · SBX-1 | the manifested window: Phase A 124; Phase B venue (kit `62ec887`, owner MFA, E1/E2); Phase C checkout previews | **D4** | A 1–2 h, D 45–60 min, C 0.5–1 h, owner ~15 min | 0.5 wd | High | manifest §7 final state; evidence JSONs; ledger 132 |
| 12 | Sandbox | A+C+owner · SBX-2 | after integration: apply 125 → 126 → 127 → 128 (125 first for ledger order); deploy the two edges to sandbox; DV-611 L/S/R | row 10 · D3, D4 | A 2–3 h, C 2–3 h | 1–2 wd | Med | sandbox tip 128 in order; pgTAP on sandbox; edge_logs; DV-611 |
| 13 | Build | C+owner · B17 | cut the next candidate from the integrated pin; cold-launch gate; DV-101…505, T re-run, D9-UX-1, Transfer UI V2, B1–B4 native checks | rows 10–12; owner authorizes build + handset | C 4–8 h, owner 2–4 h handset | 2–4 wd | Med | DV rows PASS with server read-backs. **Stays open by ruling:** populated Tickets (CFT-801), D9c |
| 14 | Gates | Owner · P0-1…5 | apply/deploy authorization; `AUTODEPLOY-VERIFIED-OFF` + empty `git_branch`; deploy-window schedule with payout-cron pause + orphan reconciliation; Stripe `payment_intent.canceled` subscription; PFA-32 signature | owner | 2–4 h owner | 0–5 wd owner-paced | — | each gate row dated with evidence |
| 15 | Gates | Owner+A · P1 | `auction-media` 27-object remediation (separate change); sandbox-unprovable evidence (`notify-transfer`, `verify_jwt` parity, push routing) — parity env or accepted risk; Twilio SID rotation | owner scope decisions | A 4–8 h if the bucket move is approved | 1–3 wd | Med | private-policy-only reachability; paths repointed; rollback tested |
| 16 | Release | A+owner · REL | execute §3: migrations → 11 edges (9 + the 2 changed) → mobile; §4 validation per stage; 24 h observation | rows 13, 14 | A 3–5 h + observation | 1 wd + 1 wd | Med-High | §4 validations; ledger 135 → N; edge parity; build promoted |

**Optional Premium enhancements (not counted above):** 14 items — 102, 105, 701, 506, 403, 406, 407, 608, 610, 602,
603, 604, 605, 702 — plus backlog batches 5–6 (untouched planning tables). C's estimate: not sized.

**Adjacent tracks, parallel, not marketplace:** D-AR1 admin integration review (A 1.5–3 h); D-AN1 `money_timeseries`
+ three indexes (needs a number from A; D 5–8 h; before ~100k production payments — count unmeasured); D-AN2 after
126 freezes (D 1–3 h); D-AN3 (owner fee-attribution definition); venue `venue/light-theme @ 530d35d` review.

## Critical path and parallelism

- **A is the serial bottleneck before integration:** rows 1→2, 3→4→5, 7 and 8 are all A's; ≈ 20–36 h ≈ 3–5 wd
  of A's time. Reviewers (rows 2, 4) run in parallel with A's writing. Row 8 can be delegated to a reviewer-grade
  subagent under A's approval if the owner wants the client path started sooner.
- **Fully parallel with the server path:** row 9 (C), row 11 (any time the window opens), every D track, B's native
  gates (after 125 merges).
- **Trimmed scope (D1 = trim):** A serial (3–5) → INT (1–2) → SBX-2 (1–2) → B17 + device (2–4) → REL (2).
- **Full scope (D1 = full):** row 8 (2–3) → row 9 (8–12) → B17 (2–4) → REL (2). The client bundle *is* the path.
- Parallel work is not summed; the ranges below are path lengths.

## Two finish lines (and a third, separate)

| | Best | Likely | Conservative |
|---|---|---|---|
| **FL-1 development-complete, verified candidate** (through row 13) — trimmed | 7 wd | 9–12 wd | 15–17 wd |
| FL-1 — full scope (row 9 in) | 12 wd | 14–18 wd | 22–26 wd |
| **FL-2 authorized production release** (through row 16) — trimmed | 9 wd | 12–16 wd | 18–20 wd |
| FL-2 — full scope | 14 wd | 17–23 wd | 28–32 wd |
| **FL-3 native signing/scanning activation** (B: G2 M5 ruling, G3 Model A, G4 first production signature, G5 issuance flip, G6 = 125 applied, G7 scanning flip, G8 live commerce) — **not required for the marketplace release**; parallel after 125 merges | 5 wd | 7–9 wd | 11 wd + unestimated scanner SDK readiness and G8 |

Drivers of the width: (a) whether round 4 is clean — every round so far found defects; (b) owner latency on the
window and the P0 gates; (c) row 9 is conditional on row 8; (d) two things have **no** estimate in any record:
scanner SDK readiness and the production payment count (AN-1 trigger, not marketplace).

## Decisions needed now (smallest set)

| | Decision | A's recommendation |
|---|---|---|
| **D1** | Candidate scope: **trim** (batches 1–4 + 611 + the four no-dependency items 607/703/507/501r) or **full** (C's 12) | Trim. The 8 contract-gated items become the next candidate; it takes ~1.5–2 weeks off FL-1 |
| **D2** | 126 stays `126` and precedes 127/128 (your ruling) — confirm; the `129` proposal is withdrawn unless you want it | Confirm 126; parts 2–3 are ≤2 wd and the review overlaps 127/128's round |
| **D3** | Authorize the L1 edge change and its **sandbox** deploy (a new edge deploy, outside the current manifest) | Yes — 127 alone delivers only L2; this is what closes L1 |
| **D4** | Open the sandbox window as manifested, and accept that 125 is applied to the sandbox in the marketplace phase for ledger order | Yes |
| **D5** | 128: accept the transitional plant-then-claim risk on legacy hash-less rows, with the every-cold-launch contract clause and NULL-hash monitoring | Accept; the other two residuals fold into 128 (row 3) |

Later, already on the gate table: Build 17 authorization (row 13); P0-1…5 (row 14); `auction-media` scope and the
parity-environment question (row 15); optional read-only production payment count for AN-1.
