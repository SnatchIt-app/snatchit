# Refund-resolution detector: design (D, 2026-09-19); local proposal, nothing built or applied

**Brief:** A's `docs/release/REFUND_RESOLUTION_PLAN_20260919.md` §4 (on `release/candidate-20260918`), written on the owner's instruction to A.
- **Rules:** DB reads only, no Stripe call. No due time. Closure only by a support action. No live alert, schedule or apply. A reviews.
- **Base:** everything below was read at the gate `e191cbfa` (the replayed chain) plus `origin/main`'s edge functions:
  - `enforce-transfer-expiry` = deployed v38, per A;
  - `stripe-webhook` = repository only (deployed v41 has not been byte-read).
- **Status:** no migration number is claimed yet; A allocates one when this design is agreed.

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

### 2.1 R2: can "the expiry job refunded it" be told apart from "refunded outside expiry" in the DB alone?

**Not exactly. The rule below errs towards opening a case.** What each writer leaves on `payments` (source read 2026-09-19):

| Writer | `status` | `refunded_at` | `stripe_refund_id` |
|---|---|---|---|
| Expiry main path (v38, deployed) | `refunded` | seconds after the run's `expired_at` (the RPC sets `expired_at = now()`, then refunds per transfer) | **always** its own `re_…` (unconditional update) |
| Expiry self-heal (Phase 1b), after a failed main refund | `refunded` | minutes to hours after `expired_at` | always |
| `charge.refunded` webhook (repository) | `refunded`, **only if not already `refunded`** (`.neq`) | the time of the webhook | only if the payload carries `charge.refunds.data[0].id`. The source notes recent API versions omit it, so usually **none** |
| `charge.dispute.closed` lost (repository) | `refunded` (only if not already) | the time of the webhook | none |
| Console `refund_execute` action | via the webhook, as above | as above | as above; plus an `ops.action` row (`refund_execute`, subject = the payment) |

**Rule:**
```
expiry_refunded(t, p) :=
      p.stripe_refund_id is not null
  and p.refunded_at >= coalesce(t.expired_at, t.expires_at)
  and p.refunded_at <  coalesce(t.expired_at, t.expires_at) + interval '10 minutes'
  and not exists (select 1 from ops.action a
                   where a.action_type = 'refund_execute' and a.subject_id = p.id)
```
Everything else that is expired + refunded is R2. The rule is therefore:
- **exact** for refunds recorded before expiry, which expiry skips (`refunded_at < expired_at`);
- **exact** for webhook refunds without an id, dispute losses and console refunds.

Residual misclassification, stated at its real strength:
- **False R2 (safe; costs one support check):**
  - a self-heal refund more than 10 minutes after expiry;
  - an expiry refund whose DB update failed, then marked by an id-less webhook.

  Support sees the Stripe refund's metadata (`reason = transfer_expired`, `source = enforce-transfer-expiry…`) and closes as A.
- **Missed R2 (possible only if all three hold):**
  1. expiry did **not** refund a succeeded payment (a non-live row, or a failed Stripe call);
  2. someone refunded it outside the console within 10 minutes of `expired_at`;
  3. the webhook payload carried a refund id.

  I know of no path that produces this routinely, but the DB cannot exclude it. If expiry's Stripe call failed, `detect_refunds`' p1 `refund_pending` case opens after 60 minutes anyway.
- **What would make it exact:** expiry recording its own refund's source on the payment. That is a payment-path server change, and outside this proposal (owner decision).
- **The 10-minute window is an assumption.** It covers a run of many transfers at about 1 Stripe call each. It is not measured in production: the run duration is visible in `cron.job_run_details`, and reading it needs the owner's authorisation.

## 3. The case

- `case_type = 'refund_resolution'` (added to `case_case_type_check`); `subject_kind = 'transfer'`; `subject_id` = the transfer. So one open case per transfer.
- **Priority p2.** p1 would fire a `case:` alert on every opening (`detect_case`). Alerting is the owner's decision, not a detector default.
- **`due_at` null, always.** No promise.
- **Title:** "Refund recorded: support action needed".
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

## 5. Closure by support

- The existing `execute_action('case_status', subject = the case, params {status, classification}, reason)` is used, with one addition in `action_dispatch`'s `case_status` branch:
  - for a `refund_resolution` case moving to `resolved` or `dismissed`, it **requires** `params.classification ∈ {'A','B','C'}`; otherwise it is rejected `precondition`. There is no "D/unresolved" closing value (A).
  - The value is stored in the `status_changed` event's data, and prefixed to `resolution_note`, e.g. `[C] remainder refunded in Stripe`.
- Other case types are unchanged, and a regression test pins that.
- Reopening a closed case (`case_status` → `open`) stays as today. A reopened case's next closure needs a classification again.
- **The console must send the classification** before support can close these cases there: a select control on refund-resolution cases, in a separate D console change after the database part. Until then these cases can only be closed through the action RPC.
  - This is the safe direction: no silent closure.
  - It is also a real usability gap if the detector is turned on first. **Turn it on only after the console change.**

## 6. What the migration would contain (on A's number; four-files rule)
- Two check-constraint widenings: `case_type` and `case_event.kind`.
- New function `ops.detect_refund_resolution()` (`SECURITY DEFINER`, `search_path = ''`, revoked from `public`, `anon`, `authenticated`, `service_role`, like the other detectors). This needs a manifest row, `EXPECT_FUNCS` + 1 and an `expected_grants` row.
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
5. The 10-minute window for expiry's own refund, and whether a production read of expiry run durations is wanted (the owner).
6. Turn-on order: the migration (setting off) → the console classification control → the owner turns the setting on.

## 9. Evidence limits
- Deployed `stripe-webhook` (v41) and `confirm-and-release` (v36) are not byte-read; their writes above come from repository source.
- No production rows were read. How many transfers are in R1–R3 today is unknown; counting them is a customer-data aggregate that needs its own authorisation.
- As the plan says, the DB cannot tell a partial refund from a full one. Classification is support's, from the Stripe Dashboard.
