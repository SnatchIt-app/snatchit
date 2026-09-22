# Refund detection and operator alerts: what must be true before any of it works (D, 2026-09-21)

**Status, stated once and plainly: none of this is operational.** Migrations 143–146 are applied to no database.
The console controls are on an unmerged branch. `notify-report`'s `ops_alert` branch is not deployed. Alert delivery
is seeded off and nothing is scheduled to call it. Every claim below is about what *would* happen after specific,
named acts, none of which have been performed.

Scope: migrations 143, 144, 145, 146 @ `70a4f613` (PR #86), console branch `admin/refund-classification-console`
@ `3dab1614`, edge function `supabase/functions/notify-report/index.ts` at the same head.

---

## 1. What changes the moment each migration is applied

This is the part most easily got wrong, because the four migrations do **not** behave alike on apply.

| Migration | On apply, before anyone changes a setting |
|---|---|
| **143** | Nothing observable. `job_health` / `detect_jobs` read cron history through bounded queries instead of full scans. Same monitoring coverage, same alert meaning. |
| **144** | **No cases appear.** The detector is seeded `refund_resolution_detector_enabled = false` and refuses for every caller, manual included. Witnessed, not assumed: pgTAP 211 G4 holds a fixture that *would* open a case and asserts none is opened; G2/G3 assert the detector reports `skipped / refund_resolution_disabled`. |
| **145** | **Cases DO appear, by design.** `detect_jobs` has no switch of its own and runs from the existing detector tick (`run_all_detectors` → `ops.run_job('jobs','cron')`). The whole point is that a job which stopped running stays visible, so the first tick after apply can open `job_not_running` cases for anything genuinely not running. Apply it when somebody can act on what it finds. |
| **146** | **Nothing is sent.** `alert_delivery_enabled` is seeded false and checked for every caller, and the migration schedules nothing. The new columns exist and read as empty, which is itself the honest new fact: an alert nobody was told about is now visibly undelivered. |

---

## 2. The prerequisites for one alert to reach one person

These are **conjunctive**. Every one must hold; any single failure means nobody is told. They are listed in the
order the data travels, with what happens when each is missing — each behaviour taken from the source or pinned by
a test, not assumed.

| # | Prerequisite | If it is missing |
|---|---|---|
| 1 | **146 applied** | No delivery machinery exists at all. |
| 2 | **`notify-report` deployed *with* the `ops_alert` branch** | The deployed function answers **200 for an event it does not know**, with no delivery accounting. 146 records that as `"notify-report answered 200 but reported no delivery"` — correctly **not** delivered — and the alert stays eligible until its five attempts are spent. Pinned by 213 Q7b. |
| 3 | **Vault `project_url`** | `ops.alert_post` returns null: nothing is posted, and **no attempt is burned**. The row records `functions base URL (Vault project_url) is not configured`. Pinned by 213 Q13. |
| 4 | **Vault `service_role_key`** | The post carries an empty bearer token and comes back **401** — which is a perfectly successful *queue* and not a delivery. Recorded as `HTTP 401 from notify-report`, attempt burned. Pinned by 213 Q8/Q9. |
| 5 | **`alert_delivery_enabled = true`**, set by an audited `setting_set` | `dispatch_alerts` returns `{skipped: alert_delivery_disabled}` and touches nothing. Pinned by 213 O2/O3. |
| 6 | **A scheduled caller of `ops.dispatch_alerts`** | Nothing ever calls it. 146 schedules nothing and no detector calls it. **Flipping the switch alone delivers nothing.** |
| 7 | **At least one channel that can actually deliver** — see §3 | The handler answers 200 with `delivered: 0`, 146 refuses to call that a delivery, and after five attempts the alert is given up. Nobody is told, and nothing is retried. |
| 8 | **A person, and a way for them to acknowledge** | Delivery is not reading. Only `ops.alert_ack` records that someone saw it, and today the only UI for it is on the unmerged console branch. |

**Scheduling is therefore necessary but not sufficient** — prerequisites 2, 3, 4 and 7 are each independently
capable of making a fully switched-on, fully scheduled system deliver nothing.

---

## 3. Recipients: the trap worth reading twice

`delivered` is incremented by the handler in exactly two places, and the database confirms a delivery only when that
count is at least 1:

- **a push that succeeded** — `attempted++; if (await sendPush(...)) delivered++`. Needs a row in
  `public.admin_users`, a registered push token for that user, and the push service accepting it. A non-OK response
  counts as a failure, deliberately.
- **an email that was sent** — `if (r !== null) { attempted++; if (r) delivered++; }`. `sendEmail` returns **null**
  when email is switched off or has no key, and the comment is explicit that this is *not* a failed attempt: it does
  not increment `attempted` **or** `delivered`.

`EMAIL_ENABLED` defaults to **`'false'`** (`Deno.env.get('EMAIL_ENABLED') ?? 'false'`), and email also needs
`RESEND_API_KEY` and a correct `ADMIN_EMAIL`.

**The consequence:** with email off (the default) and no working admin push token, `delivered` is **0 forever**.
The system behaves correctly and honestly — it refuses to claim a delivery it cannot evidence — but the observable
result is that each alert burns five attempts and then goes quiet. It will *look* configured. Nobody will be told.

So before switching delivery on, confirm **at least one** of:
- `public.admin_users` has rows whose users have working push tokens; or
- `EMAIL_ENABLED='true'`, `RESEND_API_KEY` set, `ADMIN_EMAIL` correct.

---

## 4. Where a failed delivery is visible

Per alert, once 146 is applied: `queued_at`, `notify_request_id`, `delivered_at`, `delivery_status`,
`notify_attempts`, `last_notify_error`, `acknowledged_at`, `acknowledged_by`, `incident_seq`. `ops.dispatch_alerts`
returns counts per call: `queued`, `confirmed`, `failed`, `given_up`, `max_attempts`.

In the console — **only on the unmerged branch `admin/refund-classification-console`** — the System page shows, per
alert: acknowledged (by whom, when) · delivered (with HTTP status) · queued but not confirmed · not delivered after
N attempts with the last error · or "nobody has been notified". On the current production console **none of these
columns are displayed at all**: `job_health` already emits them, and the parser drops them.

Two visibility gaps that no amount of console code fixes, both recorded in
`admin/docs/OPS_CONSOLE_OPERATOR_GAPS.md`:
- **Recovered alerts vanish.** `ops.job_health` selects only `state = 'firing'`. Once a condition clears, the
  incident leaves the console. The acknowledgement survives in `ops.audit`; the delivery record does not survive a
  recurrence at all, because 146 clears it when a new incident opens.
- **No aggregate.** Nothing says "N firing alerts have never been delivered". That is a tile and a `job_health`
  field away, and is not built.

---

## 5. Acknowledgement: what it does and does not mean

`ops.alert_ack(key, note)` is operator-only (`ops.assert_reader()`, role + aal2), writes `acknowledged_at` /
`acknowledged_by` and an `ops.audit` row, and is the **only** record in the system that a person saw an alert.

It does **not** recover the alert — the condition still has to clear on its own — and it is **not** a delivery
confirmation. It covers **one incident**: if the condition clears and returns, 146 opens a new incident with its own
number and the earlier acknowledgement does not carry over. The notification says so in its own text.

Nobody is assigned to alerts by the system. Acknowledgement is a human responsibility that has to be given to a
named person as part of turning this on; there is no rota, no escalation and no re-notification if an acknowledged
alert is then ignored.

---

## 6. Rollout sequence, and the disable path

The sequence is A's (`docs/release/ROLLOUT_PLAN_REFUND_PAYOUT_20260920.md`); what this file adds is the per-step
consequence and the verified way back.

1. **Apply 143–146**, both switches off. Expect: no refund cases; **`job_not_running` cases may appear on the first
   detector tick** (§1); nothing sent.
2. **Deploy the edge functions**, including `notify-report` with the `ops_alert` branch. Until this, prerequisite 2
   fails silently-but-recorded.
3. **Merge and deploy the console**, so an operator can classify, settle obligations and acknowledge. Note the
   ordering hazard: **144 applied without the console leaves refund-resolution cases that nobody can close** — the
   database refuses the close until a classification and every obligation are recorded, and there is no UI for
   either. Do step 3 with, or before, exercising step 1's detector.
4. **Verification window** — read the cases and the delivery columns; change nothing.
5. **Separately authorised:** flip `refund_resolution_detector_enabled`, with a named assignee for the cases.
6. **Separately authorised, and last:** confirm §3, flip `alert_delivery_enabled`, then schedule
   `ops.dispatch_alerts`. **Scheduling is the act that first sends anything to a person.**

**Disable path, verified 2026-09-21** by `scripts/local/rollback_battery_143_146.sh` (20 assertions, all pass, on a
fresh replay of all 162 migrations):

| To undo | Effect | Evidence |
|---|---|---|
| Switch off | `setting_set` to false — instant, audited, reversible, keeps every row | the switch tests |
| **144 rollback, after operators have used it** | **DISABLES rather than reverses.** The case, every `case_event`, every note and the readable classification all survive; the vocabulary is kept so existing rows stay legal; the switch is left off. **Re-applying 144 restores the detector with history intact.** | B2.1–B2.10 |
| 144 rollback, before anyone used it | Full reversal: detector and setting row gone | B1.1–B1.3 |
| 145 rollback | `detect_jobs` returns to 143's exact body (`9e932d28…`, measured from the file, not quoted from notes); the gap helper is dropped | B3.1–B3.3 |
| 146 rollback | 117's `alert_fire` restored and still working; `ops.alert` back to 8 columns; **alert rows survive**; all four new functions dropped | B4.1–B4.5 |

**Recovery never requires deleting case history.** That was the owner's explicit requirement and B2 is the proof.

### Two things about stopping 145 that are easy to get wrong

Both verified on a fresh replay, 2026-09-21.

1. **The global detector switch is not a full stop for 145.** `detectors_enabled = false` halts the *scheduled*
   path — `ops.run_job('jobs','cron')` returns `skipped / detectors_disabled` — but a **manual** trigger still
   runs it: `ops.run_job('jobs','manual')` succeeds and scans. The console exposes exactly that, because 144's
   `job_retry` arm executes `ops.run_job(name, 'manual')` and the System page has the control. So one "Run job
   now" click reopens job-not-running cases on a system an owner believes is stopped. Contrast 144's dedicated
   switch, which refuses manual as well (`run_job('refund_resolution','manual')` → `refund_resolution_disabled`,
   pinned by 211 G3). **To stop 145 completely, roll it back; there is no switch that does it.**
2. **After a 145 rollback its open cases auto-resolve, and the history reads misleadingly.** 143's restored body
   no longer detects a stalled job, so the sweep closes the case with `auto: condition no longer detected`. The
   row and its events survive — history, not deletion, and it works only because 145 reuses the `job_failure`
   case type rather than inventing one. But the closed case **keeps its "…is not running" title**, so a later
   reader sees job-not-running cases resolving themselves and can easily conclude the jobs recovered. They did
   not; the detector stopped looking.

---

## 7. Corrections to claims made earlier in this programme

1. **The ten-minute refund-origin window is triage-only.** It labels a case ("recorded within 10 minutes of expiry,
   so the expiry job probably issued it") and **never suppresses one**. Verified in source rather than asserted: in
   migration 144 the window appears only in the `CASE` expression that builds the `provenance` summary text and in
   no predicate anywhere, so it can mislabel a case but cannot hide one. Any earlier statement that it excludes
   cases is wrong.
2. **Applying a *disabled* detector does not create cases.** 144 applied with its switch off opens nothing — see §1,
   witnessed by 211 G4. This does **not** generalise to 145, which has no switch and is live on apply.
3. **Scheduling is not the only prerequisite for delivery.** §2 lists eight; scheduling is one. An earlier summary of
   mine reduced "what is left" to the schedule, which understated it.
4. **An earlier claim that `detect_refunds` would catch the missed-refund case after 60 minutes was removed** as
   untrue; 211 section M drives the actual sequence and shows the remainder stays detectable.

---

## 8. Migration 138 — explicitly separate, and not silently present

138 (`ops/138-operator-onboarding`) is **not** in this release chain and must not be introduced by it. Verified on
A's integration head `e6ebd800`: no 137- or 138-numbered migration exists among its 162 migrations, and the
`ops.action_dispatch` / `ops.execute_action` bodies on a fresh replay of that chain hash identically to those on my
own verified replay of 143–146 — so the action-handling function the chain ships is the one 144 defines, not a
138-influenced variant. 138's own integration is a separate piece of work: per A's correction of my earlier wrong
report, its real residue is **two assertions**, not the 20 failures I first reported.

The standing rule that protects this (A, registry + `OPS_ALERT_DELIVERY_DESIGN.md` §4.3): 146 is the last definer of
`ops.alert_fire`; any migration ≥147 that redefines it must carry 146's recurrence branch forward, and 146's
rollback is valid only while 146 remains the last definer.

---

## 9. What is NOT verified

- **No environment has any of this applied.** Every behavioural statement is from a local replay or a test, never
  from a running system with real data.
- **The console controls have never been exercised against a live database** — typecheck, lint, 109 unit tests and a
  production build, but no click-through, because nothing has 144/146 applied.
- **The deployed `notify-report` is not byte-read**, and whether its push/email actually reach a human has never been
  observed. It cannot be without a real send, which is not authorised.
- **The console project's Vercel settings are unread by me** — the API refuses my token for that scope (403). Whether
  preview deployments are access-protected, and whether preview env vars point write-capable credentials at
  production, is an open owner item. Inferring it from observed preview behaviour is exactly what AUTODEPLOY-1
  forbids.
- **A confirmed delivery is still not proof a person read it.** Only an acknowledgement is, and only because someone
  pressed the button.
