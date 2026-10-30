# Refund-resolution detector: design (D, 2026-09-19); built locally as 144 / pgTAP 211, nothing pushed or applied

**Brief:** A's `docs/release/REFUND_RESOLUTION_PLAN_20260919.md` §4 (on `release/candidate-20260918`), written on the owner's instruction to A.
- **Rules:** DB reads only, no Stripe call. No due time. Closure only by a support action. No live alert, schedule or apply. A reviews.
- **Base:** everything below was read at the gate `e191cbfa` (the replayed chain) plus `origin/main`'s edge functions:
  - `enforce-transfer-expiry` = deployed v38, per A;
  - `stripe-webhook` = repository only (deployed v41 has not been byte-read).
- **Status:** design A-PASS; built locally as migration 144 / pgTAP 211 (allocated by A); see §10. No PR, apply or setting flip without the owner.

## 1. What already exists (so nothing is duplicated)

| Need | Existing machinery (gate) | Consequence for this design |
|---|---|---|
| One case per subject | `ops.case_upsert` keys on `case_type:subject_id` and keeps at most one **open** case per key (`case_open_dedupe_uidx`). After a case closes, the next call **opens a new one** | We get one open case per transfer for free. For permanent states, the detector must decide itself whether to reopen after closure (§4) |
| Closing a case | `execute_action('case_status', …)` → `action_dispatch`. Any case type can be resolved or dismissed with only a reason (roles: admin, risk, support) | To force a classification, the `case_status` branch must require one for this case type (§5) |
| Silent closure risks | `detect_sweep` (per type) and `case_auto_resolve_subject` (only `dispute_open`, `payout_review`, `report_review`) | The new type is resolved by neither: the detector never sweeps it |
| **R4** (payout made + payment `refunded`, transfer not `reversed`) | `detect_reconciliation` already opens a **p1 `reconciliation_mismatch`** case on exactly this condition. It clears only when the transfer is recorded `reversed` or the payment stops being `refunded`: real changes, not a time window | **R4 is not duplicated.** It stays with `reconciliation_mismatch`. A refund-resolution case whose transfer reaches R4 records the transition and points to that case (§3) |
| **R3** overlap | `detect_release_stuck` (p2) already covers `buyer_confirmed` / `auto_released` without a payout, **including refunded payments**, with a misleading "awaiting release" summary. It does not cover `seller_sent` | R3 is detected here. `release_stuck` is **unchanged in v1**, so both cases can be open for the same transfer; the R3 summary says so. Excluding refunded payments from `release_stuck` would change its alert meaning, so that is a separate decision for A/the owner |
| Feature flags | `ops.setting` + `ops.setting_bool`; flags are seeded off (CLAUDE.md) | New setting `refund_resolution_detector_enabled`, seeded **false**. Applying the migration makes nothing live; turning it on is an audited `setting_set` (§6) |

## 2. The states, as DB predicates (payment = the transfer's `payment_id` row)

- **R1:** `t.status = 'pending'` and `p.status = 'refunded'`.
- **R2:** `t.status = 'expired'` and `p.status = 'refunded'` and **not `expiry_refunded(t, p)`**. The rule is in §2.1.
- **R3:** `t.status in ('seller_sent','buyer_confirmed','auto_released')` and `p.status = 'refunded'` and `t.stripe_transfer_id is null` and `t.payout_released_at is null`.
  - Deviation from the plan's wording: the plan says "payment not succeeded" and does not list `buyer_confirmed`. I use `refunded`, because other non-succeeded statuses are not refund cases. I add `buyer_confirmed`, because `confirm-and-release` is blocked by the same guard. Please confirm both.
- **R4:** left to `reconciliation_mismatch` (see §1).
- **Excluded:** `disputed` and `reversed` transfers. The dispute flow and its cases own them.

### 2.1 R2: the expiry job's own refund is never assumed (owner, 2026-09-19)

**Every expired + refunded order opens a case. Nothing is suppressed.** A refund id plus a timestamp within ten minutes
of expiry does **not** prove the expiry job issued a **full** refund: the database records no refund source and no
amount, and `status = 'refunded'` is written for a partial refund too.

**The missed refund this fixes** (pgTAP 211, section M drives exactly this):
1. expiry's own refund **fails** (a Stripe error, or a non-live row), so the payment stays `succeeded`;
2. `detect_refunds` opens its p1 `refund_pending` case after 60 minutes;
3. an external **partial** refund is recorded within ten minutes of expiry, **carrying a refund id**;
4. `payments.status` becomes `refunded`, so `detect_refunds`' own sweep **auto-resolves** `refund_pending` — its query
   only looks at payments that are not refunded;
5. under the earlier rule the refund-resolution case was suppressed as well, so **a remainder owed to the buyer was
   invisible**. The earlier claim that `detect_refunds` "opens after 60 minutes anyway" was wrong: that case does not
   survive step 4.

**What the database still says** is carried as **triage text** in the summary, never as grounds to hide a case:

| What the row shows | Summary text |
|---|---|
| a console `refund_execute` action exists | "…so the refund did not come from the expiry job" |
| no `stripe_refund_id` | "no refund id is recorded, which the expiry job always writes, so the refund did not come from it" |
| no `refunded_at` | "no refund timestamp is recorded" |
| `refunded_at` < expiry | "the refund was recorded BEFORE expiry, so the expiry job skipped its own refund" |
| `refunded_at` within 10 min of expiry | "consistent with an expiry-issued refund, but UNCONFIRMED: the database records no refund source and no amount" |
| later than that | "recorded more than 10 minutes after expiry…" |

**Consequence, stated plainly:** with the detector on, the ordinary expiry path opens a case too. The switch is seeded
off, so the volume can be judged before it is turned on. **Safe exclusion becomes possible only with reliable
provenance** — the refund's source and amount recorded where the refund is made. That is a server change, and the
owner's decision.

**Re-review trigger (A, 2026-09-19):** the provenance text is read from the **deployed** writers —
`enforce-transfer-expiry` v38 and `stripe-webhook` as in the repository. Before any edge deploy that changes how a
refund is recorded (the release candidate's Phase 0 / `record_payment_refund` / `amount_refunded_cents`,
`20260906110000` / `20260906120000`), this section and 144 must be re-reviewed.

## 3. The case

- `case_type = 'refund_resolution'` (added to `case_case_type_check`); `subject_kind = 'transfer'`; `subject_id` = the transfer. So one open case per transfer.
- **Priority p2.** p1 would fire a `case:` alert on every opening (`detect_case`). Alerting is the owner's decision, not a detector default.
- **`due_at` null, always.** No promise.
- **Title:** "Refund recorded — support action needed".
- **Summary:** the state code and its meaning; payment and transfer ids and the amounts the DB has (`total`, seller net), each labelled **"amount refunded unknown (DB)"**; and the resolution steps for the state, from the plan's §3 table. Customer contact details are never in the text.
- **State history:** a new `case_event` kind `state_changed` (added to `case_event_kind_check`), with data `{from, to}`.
  - One event is written when the case opens (`from: null`), and one per later transition while it is open.
  - The case's **current state** = the newest `state_changed` event.
  - When the transfer reaches R4, the event is `{to: 'R4', see: 'reconciliation_mismatch'}` and the summary points there.
- **The detector never resolves or sweeps this type.** If the state disappears (e.g. the transfer becomes `disputed`), the case stays open with its last state until support closes it.

## 4. Reopening after closure (A's classification-keyed rule)

For each transfer currently in R1, R2 or R3, per run:
1. **An open case exists:** if its current state ≠ the DB state, write `state_changed` and refresh the summary. Never resolve.
2. **No open case, and none ever closed:** open one.
3. **No open case; the newest closed case had state Sc and classification K:**

| From Sc (at closure) | To (now) | K = A (full) | K = B (partial, continue) | K = C (partial, cancel, remainder refunded) |
|---|---|---|---|---|
| same state | same state | suppressed | suppressed | suppressed |
| R1 | R2 (expired) | suppressed | **open** (fulfilment did not continue; a remainder may be owed) | suppressed |
| R1 | R3 (sent, payout blocked) | **open** (tickets sent for a refunded order) | **open** (payout escalation; no tool exists) | **open** |
| any | R4 | handled by `reconciliation_mismatch`, which always opens: new money exposure | same | same |
| any other pair | | **open** (conservative default) | same | same |

- R2 → R3, R3 → R2 and any return to R1 are impossible by the transfer's rules: an expired transfer cannot be sent, and a sent one cannot expire. They fall under the default.
- **A simpler fallback** (A's): one case per transfer, reopened only on R4. It is not recommended, because after a B closure support would have to notice an R1→R2 or R1→R3 change themselves.

## 5. Classification is not closure (owner, 2026-09-19; A's corrections)

Selecting A, B or C must never silently close a refund or payout that is still owed. Three separate steps:

1. **`case_refund_classify`** `{classification, assignee?}` + a reason. Records a `classified` event. **It never changes
   the case's status.** It raises the obligation the classification implies:
   - **B** (partial, fulfilment continues) → `payout_owed`. Nothing releases it today (F-PAYOUT-PARTIAL-1), so **B can
     never close on its own**.
   - **C** (partial, order cancelled) → `remainder_refund_owed`.
   - **A** (full refund) → `reversal_decision`, **only** when the transfer was already paid out; otherwise none.
   - When an obligation is raised the case must have an **assignee** (given here or already set): money that is owed is
     never merely open and ownerless.
   - Re-classification is allowed: a new event, last one wins, with its own reason. Never silent.
2. **`case_refund_obligation`** `{kind, settled, note}` records what happened to an obligation that was raised. Kinds:
   `payout_owed`, `remainder_refund_owed`, `reversal_decision`. Settling one is its own human record, with a note.
3. **`case_status` → resolved/dismissed** is refused unless a classification is recorded (for `resolved`) **and every
   obligation raised for the case is recorded settled**. Dismissal does not bypass an outstanding obligation; a case
   with nothing outstanding can still be dismissed as a false positive.

Both actions are named `case_*` deliberately: `action_dispatch`'s `case_%` preamble then loads the case and enforces the
caller's expected version, and `action_allowed_roles` gives admin / risk / support. Every other case type dispatches
exactly as before (211 C15–C17, and control M9b).

## 6. What the migration would contain (on A's number; four-files rule)
- Two check-constraint widenings: `case_type` and `case_event.kind`.
- New function `ops.detect_refund_resolution()` (`SECURITY DEFINER`, `search_path = ''`, revoked from `public`, `anon`, `authenticated`, `service_role`, like the other detectors). **No** grant-manifest row, `EXPECT_FUNCS` change or `expected_grants` row: those CI checks cover the `public` schema only (`ci.yml` counts `nspname='public'`; neither manifest has `ops` lines), so an `ops` function correctly needs none of them (corrected 2026-09-19 after A's review; do not add them).
- `ops.run_job`: one `when` arm. `ops.run_all_detectors`: `'refund_resolution'` in `c_order`. The arm returns `skipped: refund_resolution_disabled` while the setting is false, so the 5-minute tick applies nothing live. Both functions are redefined, so the rollback must restore the **applied** bodies at the time of apply.
- `ops.action_dispatch`: the §5 check. It is redefined, with the same rollback rule.
- The setting row, seeded `false`.
- **No new table, no index**; the candidates are refunded payments only. No schedule change.

## 7. Tests (pgTAP number from A; through the front door)
- **One fixture per state,** run through `ops.run_job('refund_resolution', 'manual')` with the setting on:
  - R1, R2, R3;
  - **R2 with expiry's own refund → no case**;
  - R2 cases: refunded before expiry, webhook without an id after expiry, dispute lost, a console `refund_execute` row, and a self-heal refund at 11 minutes (the documented false R2);
  - R3 with `buyer_confirmed`;
  - a disputed transfer (excluded);
  - payout made + refunded (no refund-resolution case, while `reconciliation_mismatch` opens).
- **Setting off:** `run_job` returns skipped and opens no case. The `run_all_detectors` order includes it.
- **Never auto-resolved:** after the state disappears or changes, the case stays open. There are `state_changed` events, and two runs write no duplicates.
- **Transitions after closure:** each suppressed and each opening cell in §4 is its own fixture, with closures made through `execute_action('case_status', …)` as a platform-support user.
- **Closure:** without a classification → rejected. `'D'` → rejected. A, B and C → resolved, with the classification in the event and the note. A `job_failure` case still resolves with a reason only (regression).
- **Negative controls (predictions written first):**
  - remove the classification check in the reopen rule → the A→R2 fixture reopens and its test fails;
  - remove the same-state guard → a reopen on every run;
  - call `detect_sweep` for the type → the never-auto-resolved test fails;
  - drop the `refund_execute` clause → the console-refund fixture is missed;
  - widen the window to 30 minutes → the 11-minute self-heal fixture flips;
  - remove the setting gate → the off test fails;
  - remove the `case_status` requirement → the rejection tests fail.
- **Full suite:** all other pgTAP files run, because other suites pin schema counts.

## 8. Decisions this design needs (A, or the owner through A)
1. R3's predicate: `refunded` rather than "not succeeded", plus `buyer_confirmed`.
2. R4 not duplicated (left to `reconciliation_mismatch`).
3. `release_stuck` unchanged in v1: overlapping cases for refunded, confirmed or released transfers.
4. p2 with no alert, versus p1 with an alert (the owner).
5. ~~The 10-minute window for expiry's own refund~~ — **settled by the owner, 2026-09-20: the ten-minute
   attribution heuristic is TRIAGE-ONLY. It may label a case ("recorded within 10 minutes of expiry, so the expiry
   job probably issued it"), and it must NEVER suppress one.** An uncertain refund is surfaced for support, always.
   That is what 144 does and what 211 section M pins; the window is a wording threshold in the summary, not a
   detection threshold, so getting it wrong can only mis-label a case, never hide one. A production read of expiry
   run durations would only sharpen the label, and is therefore no longer needed for correctness — it stays
   available to the owner as a refinement, not a dependency.
6. Turn-on order: the migration (setting off) → the console classification control → the owner turns the setting on.

## 9. Evidence limits
- Deployed `stripe-webhook` (v41) and `confirm-and-release` (v36) are not byte-read; their writes above come from repository source.
- No production rows were read. How many transfers are in R1–R3 today is unknown; counting them is a customer-data aggregate that needs its own authorisation.
- As the plan says, the DB cannot tell a partial refund from a full one. Classification is support's, from the Stripe Dashboard.

## 10. Build (2026-09-19, local only): migration 144 / pgTAP 211, allocated by A
- **A's review:** PASS on the design, with two required changes, both done:
  - **(1) The collision with 138.** `ops/138-operator-onboarding` also redefines `ops.action_dispatch`. 144 sorts after it, so on replay 144's body replaces 138's.
    - 144 is built on 118's body (the gate). Before any PR, it must be rebased onto the body that lands immediately before it, and its rollback must restore that body.
    - This is noted in the header. 211's C7–C9 pin pre-existing case actions still dispatching unchanged.
  - **(2) The R2 re-review trigger** (§2.1, and the migration header).
- **§8 decisions:**
  - A agreed 1–3: R3 = `refunded` + `buyer_confirmed`; R4 left to `reconciliation_mismatch`; `release_stuck` unchanged.
  - 4 and 6 are owner items: p2 vs p1, and the turn-on order. The build uses p2. Item 5 was settled on
    2026-09-20: the ten-minute window is triage-only and never suppresses (see §8.5) — it is no longer a decision
    the build is waiting on.
- **Build details:**
  - The owner's switch gates `run_job` for every trigger, manual included.
  - The detector is in `run_all_detectors`' order, and reports "skipped" while the switch is off.
  - `job_state` gets its row on the first (skipped) run.
  - Tests 182 B31 (settings count 9 → 10) and 183 N1 / N5 / N10 (job count, `detect_*` count, `job_state` rows) are amended in place, with dated notes.

