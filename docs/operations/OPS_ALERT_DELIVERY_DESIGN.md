# ops.alert delivery and acknowledgement: what existed, what 146 builds, and what is still missing (D)

**Owner's item 4 (2026-09-19):** "Verify what a p1 alert actually does. Identify the delivery path, recipient
configuration, failure handling and acknowledgement. A database alert row is not proof a person was notified.
Implement the missing application delivery capability if needed, using existing approved infrastructure; do not
activate a hosted channel or send real notifications under this instruction."

**Numbers:** migration **146** / pgTAP **213** (A's registry).
**Status (2026-09-20):** built, reviewed by A, reviewed independently, two defects found and fixed. Nothing is
applied, scheduled, switched on or deployed. Branch `admin/146-alert-delivery`, draft PR #86, do-not-merge.

## 1. What a p1 alert did before 146: nothing reached a person

Read at the gate `e191cbfa` plus `origin/main`'s edge functions.

| Question | Answer |
|---|---|
| Who reads `ops.alert`? | `ops.job_health()` (the full firing set), `ops.today()` (a count), `ops.refresh_metrics()` and `ops.build_daily_summary()` (counts into a snapshot/summary). The admin console's `/system` and `/` pages render them **on request**; there is no polling. Nothing else. |
| Does anything go out? | **No.** No trigger on `ops.alert`; no `pg_net`/`net.http_post` anywhere in 115–126's ops files; no edge function references `ops.alert`; no `notify.*` enqueue from `ops.*`; the daily summary is written `delivery_state = 'portal_only'`. |
| Acknowledgement? | **None.** `ops.alert` had `state` in ('firing','recovered'), `first_fired_at`, `last_fired_at`, `recovered_at`, `fire_count`, and nothing else. No assignee, no acknowledged_at, no escalation, no notified_at. Recovery was machine-only; no action type could touch an alert. |
| Failure handling? | Not applicable: nothing was attempted, so nothing could fail or be retried. |
| Recipients configured? | None for alerts. `public.admin_users` is the recipient list the working path already uses; `ADMIN_EMAIL` is its single email address. |
| The repo's own words | `docs/admin-console/DESIGN_AND_EXECUTION_PLAN.md`: "**Not built (honest labels):** … email/SMS alerts (no adapter)". |

**So a p1 alert on a refund-resolution or job case was a row an operator saw only if they opened the console.**

### The one working DB → human path (what this builds on)
`net.http_post` → `/functions/v1/notify-report` (migration 133's pattern, Vault `project_url` + `service_role_key`),
which fans out a push to every `public.admin_users` row, sends one `ADMIN_EMAIL` message and reports to Sentry. The
signing monitor uses it (`099`), gated by `catalog.platform_config` `signing.monitor_enabled`, seeded **false**.
`notify.*` is the other infrastructure, and its dispatch adapter is **parked**: `notify.claim_deliveries` fails closed
because `notify.delivery_lease_interval` is unset by owner policy, and no `notify-dispatch` function exists. So
`notify-report` is the only path that can carry an alert today.

## 2. What 146 actually built

Everything **in 146** is inert until an owner turns it on, and nothing is scheduled by the migration. That is a
statement about 146 only — 145 has no switch and is live on apply by design. The full per-migration picture, and the
eight conjunctive prerequisites before an alert reaches a person, are in `OPS_ALERT_ROLLOUT_PREREQUISITES.md`.

1. **`ops.alert` gains nine columns:** `queued_at`, `notify_request_id`, `delivered_at`, `delivery_status`,
   `notify_attempts`, `last_notify_error`, `acknowledged_at`, `acknowledged_by`, `incident_seq`. An alert nobody was
   told about is now visibly *undelivered*, which previously could not be said at all.
2. **`ops.alert_post(jsonb)` and `ops.alert_response(bigint)`** — the only two places in `ops` that touch pg_net and
   Vault. One auditable egress point, and the seam the tests substitute (CI's `postgres` is not superuser and may not
   create or write in `net`/`vault`; the local harness may, which is exactly how a test passes locally and fails in CI).
3. **`ops.dispatch_alerts(p_limit)`** — reconciles what earlier calls queued, then posts eligible alerts:
   - **off** while `ops.setting` `alert_delivery_enabled` (seeded **false**) is off, for every caller;
   - **queued ≠ delivered**: `net.http_post` returns a request id immediately, so `queued_at` + `notify_request_id`
     mean only that pg_net accepted the post. `delivered_at` is set only when the response is **2xx AND** the handler
     reports `delivered >= 1`. A status alone is not enough — `notify-report` answers 200 for an event it does not
     know and for its own internal errors, so before the `ops_alert` branch is deployed every post would otherwise
     look delivered. A 401 is a perfectly successful *queue*.
   - **allow-listed body**: alert key, kind, counts, timestamps, incident number, and `case_id` / `case_type` /
     `jobname` when the payload has them. `ops.alert.payload` is free-form and is **never** passed through.
   - **bounded**: five attempts, then the alert is counted as given up — it stays firing and keeps its last error,
     but it no longer occupies a delivery slot (see §4.1).
   - **never raises**, so a delivery problem cannot fail a detector tick. **Not scheduled by 146.**
4. **`ops.alert_ack(alert_key, note)`** — operator-only (`ops.assert_reader()`, aal2), writes `acknowledged_at`/`by`
   and an `ops.audit` row. Acknowledging is **not** recovery: the alert stays firing until the condition clears.
5. **`ops.alert_fire` (117) replaced** so a recurrence is a new incident — see §4.2.
6. **`notify-report` gains an `ops_alert` branch** (repository only). No existing branch or payload changes; B owns
   the signing monitor's use of that function and has no live session, so this file and this note are the record.
7. **What 146 does NOT do:** no channel activated, no cron schedule, no production send, no change to `notify.*`'s
   parked adapter, no change to who is an admin.

**Turning the setting on still delivers nothing by itself.** 146 schedules nothing and no detector calls
`dispatch_alerts`. Flipping `alert_delivery_enabled` only makes a *call* able to send. Scheduling a caller is the act
that would first send anything to a person, and it is a separate owner decision.

## 3. Tests (pgTAP 213, 36 assertions)
Sections O (the switch), Q (queued is not delivered: confirmation, the pre-deploy 200, a 401, staleness, the cap, a
raising sender, no base URL), L (the allow-list, with a witness so it cannot pass on an empty body), A
(acknowledgement), S and R (§4). The two egress seams are substituted inside the transaction, so nothing leaves the
database and nothing in `net`/`vault` is created or written.

## 4. The independent review's two findings (2026-09-20), reproduced and fixed

Both were reproduced by tests written before any fix: 213 failed **8 of 36** against the previous head
(`a9bf6423`) — S1, S2, R1, R2, R4, R5, R6, R7 — on exactly the assertions below.

### 4.1 Queue starvation (finding 1)
`dispatch_alerts` selected its batch and *only then* skipped alerts that had used up their attempts. With `p_limit`
exhausted alerts older than a live one, the batch was filled entirely by the dead ones and the live alert was never
posted — not delayed, never. The cap is now part of the batch predicate, and exhausted alerts are counted by a
separate aggregate and reported as `given_up`: still firing, still carrying their last error, still visible to an
operator, but no longer occupying a delivery slot.
**Test S1–S3:** 25 exhausted alerts, every one older than the new ones, still leave both new alerts queued; none of
the 25 is posted, reset, or has its error cleared.

### 4.2 Incident recurrence (finding 2)
`ops.alert_fire` reused the row without clearing the closed incident's delivery and acknowledgement state. Because
`delivered_at` and `acknowledged_at` are exclusion criteria for dispatch, a recurrence was **ineligible for
notification**; it also inherited an acknowledgement given for a different incident, kept spending the previous
incident's attempts, and could be marked delivered by a **late response to the previous incident's request**.

146 now replaces 117's `alert_fire`: the `recovered → firing` transition — and **only** that transition — opens a new
incident (`incident_seq + 1`) and clears `queued_at`, `notify_request_id`, `delivered_at`, `delivery_status`,
`notify_attempts`, `last_notify_error`, `acknowledged_at`, `acknowledged_by`. A repeat fire of an alert that is still
firing resets nothing, so a detector tick is not a fresh notification. `notify-report` names the incident, so a
recurrence is not read as a duplicate of one already dealt with.
**Test R1–R7:** fire → deliver → acknowledge → recover → fire again; the new incident is eligible, needs its own
acknowledgement (a second `ops.audit` row), carries incident 2, resets nothing on a same-incident re-fire, does not
hold the old request, and is **not** marked delivered by a late 2xx belonging to the closed incident.

**What a new incident discards** is the previous incident's delivery bookkeeping. What survives is the `ops.audit`
row every `ops.alert_ack` writes — that, not the alert row, is the durable record that a person saw it. A durable
per-incident delivery history would need its own table and is **not** built here.

### 4.3 A standing rule for whoever writes migration 147 or later (A, 2026-09-20)
146 is now the last definer of `ops.alert_fire`. **Any future migration that redefines it must carry 146's body
forward** — the recurrence branch that opens a new incident and clears the delivery bookkeeping — or a recurrence
silently becomes unnotifiable again, which is defect 4.2 reinstated. For the same reason 146's rollback is correct
only while 146 remains the last definer: it restores 117's body, so running it after a later migration has
redefined the function would undo that one instead. A holds this in the migration-number registry; it is repeated
here because this file is what a future author reads.

### 4.4 Found while fixing those
The rollback did not drop `ops.alert_post` / `ops.alert_response` (added late, in the CI-portability commit) and did
not restore 117's `alert_fire`. It now does both, in an order that never leaves `alert_fire` writing columns that
have been dropped.

## 5. Evidence (local, 2026-09-20)
- `213`: **36/36**; **28/36** against the pre-fix head, failing S1, S2, R1, R2, R4, R5, R6, R7 — reproduced
  independently by A, and re-measured by D after A found the error described below.
  **A correction, recorded rather than quietly fixed:** D first reported this as 7 failures / 29 passing. That number
  was measured against the 35-assertion version of the file, before the R5 "same incident, no storm" test was added,
  and D kept quoting it after the file became 36 assertions — while listing eight failing test names beside it, an
  inconsistency D should have caught. A re-ran the pre-fix control and got 8; D then re-ran it and got 8. A measured
  number belongs to the exact version of the artefact it was measured on.
- Full pgTAP on a **fresh replay of the whole chain** (162 migrations): **5455/5455** all-pass, which is A's
  independent number exactly. Per file at this head: 210 = 25, 211 = 61, 212 = 25, 213 = 36, 182 = 45, every other
  file equal to the gate's 5308. CI at this head is **5461** (the fixed +6 local↔CI delta).
  D first reported 5454. That was the same stale artefact as the failure-count error below: the full-suite replay
  had been run while 213 still had 35 assertions, so 5454 = 5455 − 1. A predicted the cause from the arithmetic
  alone and told D to read the per-file line before recording it as unexplained; the line said `plan=36` on a
  re-run and the total said 5455. **One stale artefact, two stale numbers, one fix.**
- Rollback: restores 117's `alert_fire` to md5 `dfcb1956d3bf6bedb7b3359b80122c0d` exactly (the value on a build
  without 146), `ops.alert` 17 → 8 columns, 0 of the four new functions left.
- **14 negative controls**, every kill set predicted in advance and matched on the first run, each failing a
  different set: the switch, the no-base-URL path, delivered-at-queue-time, any-2xx-confirms, the cap in the batch
  predicate, the payload allow-list, ack-also-recovers, anyone-may-ack, the exhausted count, the recurrence branch
  removed, the recurrence branch always taken (the storm), the acknowledgement inherited, the request id retained,
  and the incident counter frozen.

## 6. Evidence limits
- Production's `notify-report` (v41 era) is **not byte-read**; the branch shape here is from the repository.
- Whether the deployed function's push/email actually reach anyone is **not verified** and cannot be without a real
  send, which this instruction forbids. 146 makes delivery *attemptable, confirmable and recorded*, not *proven*.
- A confirmed delivery means the edge function accepted the event and reported that it delivered something. It is
  not proof a human read a push or an email. Only `alert_ack` records that, and only when someone presses it —
  **and there is no console control that presses it today (see `OPS_CONSOLE_OPERATOR_GAPS.md`).**
