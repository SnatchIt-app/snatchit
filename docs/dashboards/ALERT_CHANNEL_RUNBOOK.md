# Alert channel runbook: ops alerts by email to the owner (prepared, not activated)

**No step here is authorised; owner actions only.** This runbook prepares the channel and orders the owner's steps. It activates nothing. Each step needs the owner's own go when it runs. The recipient is **the owner's verified account email**. Never write that address into this repository, a ticket, a PR or a chat message. Enter it only in the Supabase secret field in step 2.

Prepared 2026-10-21 from read-only evidence: git objects and written records. No database or hosted read was made. Citation key: paths without a directory are in `supabase/migrations/` at the production gate @ `6f982f36`. `notify-report` = `supabase/functions/notify-report/index.ts` @ `6f982f36`, deployed as v10 (see §0). `send-push` = `supabase/functions/send-push/index.ts` @ `6f982f36`. Records: `docs/release/...` @ `14f3e8ec`. Admin v2: `fec26b41`. Live console: `07100a35`.

## 0. Current state (from the records)

| Fact | Value | Source |
|---|---|---|
| Delivery switch | `alert_delivery_enabled = false` (seeded false) | `146:97`; D's read-only production triage, 2026-10-13 21:1xZ (private evidence store) |
| Dispatcher | `ops.dispatch_alerts` is called by nothing: no cron job, no function. EXECUTE is revoked from `public`, `anon`, `authenticated` **and `service_role`**, so only the database owner, or a pg_cron job it owns, can run it | `146:47-50`, `146:326`; `docs/release/SPRINT_STATUS_20260917.md:1422-1424` (2026-09-23); D 2026-10-13 |
| What counts as delivered | Only a 2xx from `notify-report` whose body reports `delivered >= 1` for that request | `146:232-235`; `notify-report:315` |
| Edge function | `notify-report` v10, deployed 2026-09-23 from gate `5b255838`, carries the `ops_alert` branch | `SPRINT_STATUS_20260917.md:1422` |
| Admin push tokens | **0.** `public.admin_users` has 2 rows; the project's 2 active tokens belong to non-admin users | D 2026-10-13; also 0 of 2 on 2026-09-22 (`docs/release/POLICY_PROMISES_DECISION_LIST_20260924.md:79`) |
| Email | `EMAIL_ENABLED` is absent, so email is off (`notify-report:39`). The secret **names** `RESEND_API_KEY`, `ADMIN_EMAIL` and `EMAIL_FROM` exist; their values are unknown (only names were read) | `docs/release/PRODUCTION_APPLY_MANIFEST_20260922.md:126`; `docs/release/SIGNING_MONITOR_ALERT_CHECK_CLEAN_RUN_20260917.md:36` |
| Backlog | **17 alerts undelivered**: 15 `p1_case` firing, 1 `p1_case` recovered, 1 `job_failure` recovered. None queued, attempted or acknowledged | D 2026-10-13; the same 17 (15 firing, 2 recovered) on 2026-09-23 (`SPRINT_STATUS_20260917.md:1423`) |
| Acknowledging | `ops.alert_ack` needs an operator session at aal2 (`146:336`), so the SQL editor cannot call it. Only admin v2 has the control (`admin/src/components/system/AlertAckForm.tsx`); the live console `07100a35` has none | `146:329-359` |

## 1. Blockers in the code (fix before any owner step; these are not owner actions)

**P-1. A push to an admin with no device is counted as delivered.** `sendPush` returns true whenever `send-push` answers 2xx (`notify-report:62-63`). `send-push` answers **200 `{"sent":0,"reason":"No push tokens found"}`** for a user with no token (`send-push:272-276`). It also answers 200 without checking Expo's reply (`send-push:285-297`). With today's 2 admin rows and 0 tokens, every `ops_alert` post would report `delivered: 2`. `dispatch_alerts` would then set `delivered_at` (`146:232-235`), never post that alert again, and the console would show it as delivered **although nobody was told**. This defeats the "queued is not delivered" design of 146. The same false positive keeps report and dispute delivery claims from being released (`notify-report:337`), and it affects B's signing alert, which shares `sendPush`.
- Fix (A writes it, D reviews as 146's author, B is informed): `sendPush` returns true only when the JSON reply has `sent >= 1`, and `send-push` counts Expo tickets whose status is `ok`.
- Test: a notify-report unit test in which `send-push` replies `{"sent":0}` must give `delivered: 0`.

**P-2. `EMAIL_ENABLED` switches on email for every event.** It is one flag for the whole function (`notify-report:39`, `:72`). Setting it to true would also send email to:
- the reporter and the reported user on every new report (`notify-report:205-233`);
- the buyer and the seller on every dispute (`notify-report:235-254`).

Those are customer emails that promise "Snatch It support is reviewing this". They are not part of the alert channel and their recipients were never checked.
- Fix: a per-event allow-list, for example a secret `EMAIL_EVENTS` (comma-separated, default empty), checked inside `mail()`, and set to `ops_alert` only. Turning customer emails on is a separate product decision for the owner, outside this runbook.

**One deploy.** P-1 and P-2 ship together in **one** reviewed `notify-report` deploy (plus `send-push`, if it changes), each through the normal path under its own owner go. That is one production deploy, not two.

**P-3. Dependency.** Step 5 needs admin v2 live (O-1), because it is the only console that can acknowledge an alert.

**Observation on case dismissal.** D's triage expects that dismissing the 15 test-mode cases would also recover their alerts. The code says otherwise:
- A detector re-opens a dismissed case on the next 5-minute tick while its condition persists (`115:445-470`). `117:175-219` has no test-mode or dismissed exclusion.
- The alert recovers only when the condition stops being detected (`117:143-152`).

So dismissal is not a way to clear the backlog. Quieting test-mode records needs a detector change (A's call), and it is not part of this runbook.

## 2. Owner steps, in this order

The brief listed backlog acknowledgement last. It must run **before** the switch is turned on, so it is step 5 below.

### Step 1. Confirm the recipients (read-only)
- **Do.**
  - Supabase dashboard → Authentication → Users → the owner's account: "Email confirmed" is set. That confirmed address is the one step 2 uses.
  - In the SQL editor, run this read-only query. It deliberately selects no email column:
    ```sql
    select au.user_id, au.label,
           u.email_confirmed_at is not null as email_verified,
           (select count(*) from public.push_tokens t
             where t.user_id = au.user_id and t.is_active and t.token is not null) as active_push_tokens
      from public.admin_users au
      join auth.users u on u.id = au.user_id
     order by au.created_at;
    ```
- **Who receives what.**
  - Email goes **only** to the value of the `ADMIN_EMAIL` secret (`notify-report:300`). It is never sent to `admin_users` addresses.
  - Push goes to every `admin_users` row that has an active token (`notify-report:189-190`, `:296-299`). With 0 tokens it reaches nobody.
  - Every `ops_alert` is also sent to Sentry (`notify-report:306`). Check the Sentry project's members and alert rules, so that only people the owner chooses are notified.
- **Verify.** 2 rows, both `email_verified = true`, both `active_push_tokens = 0`.
- **Stop if** there is a third row, an unverified account, or any admin token. A token on the second founder's device makes them a push recipient; the owner decides about that before step 6.
- **Rollback.** None needed (read-only).

### Step 2. Provider and secrets (owner; only after the P-1/P-2 deploy)
- **Provider.** Resend is the only provider in the code (`notify-report:81-88`). Choosing another provider is a code change; this runbook assumes Resend. No paid plan is bought here: the volume is a handful of alerts a day.
- **Do, read-only first.** In the Resend dashboard, confirm that the key behind `RESEND_API_KEY` belongs to the company account, and that the sending domain of `EMAIL_FROM` (default `no-reply@snatchitapp.com`, `notify-report:40`) shows Verified. If it does not, its DNS records go into Cloudflare (X-1), as a separate owner change.
- **Then set the secrets, in this order** (Supabase → Edge Functions → Secrets):
  1. `ADMIN_EMAIL` = the owner's verified account email, from step 1.
  2. `EMAIL_EVENTS` = `ops_alert`.
  3. `EMAIL_ENABLED` = `true`, last.
- **Why `ADMIN_EMAIL` must be set explicitly.** Its current value is unknown, and its fallback is `support@snatchitapp.com` (`notify-report:41`), a mailbox nobody has confirmed a human reads (`docs/release/SIGNING_MONITOR_ALERT_CHECK_OWNER_REVIEW.md:92`).
- **Verify.** The secret list shows the names; values cannot be read back. The real check is step 4's test email.
- **Rollback.** Delete `EMAIL_ENABLED` first (absent means off, `notify-report:39`). The other two can stay.
- **Stop if** P-2 is not deployed. `EMAIL_ENABLED=true` would then email customers on the next report or dispute.

### Step 3. Schedule the dispatcher (A's migration; A numbers it)
- **What A writes.** One migration in the 117 idiom (`117:1122-1123`): `select cron.unschedule(jobname) from cron.job where jobname = 'ops-dispatch-alerts';` then `select cron.schedule('ops-dispatch-alerts', '*/5 * * * *', $$select ops.dispatch_alerts(20);$$);`.
  - Number: A allocates it (the registry at `14f3e8ec` shows 179+ as next free). Nothing is allocated here.
  - A rehearses it on the local replay. It is applied in production only on the owner's authorisation, as one targeted file plus its ledger row.
- **Inert by construction.** While the switch is false, every call returns `{"skipped":"alert_delivery_disabled"}` before it reads any alert (`146:209-213`).
- **Verify** (read-only):
  - `cron.job` has one `ops-dispatch-alerts` row, owned by `postgres`, because `service_role` cannot execute the function (`146:326`).
  - `cron.job_run_details` shows succeeded runs.
  - In `ops.alert`, every `notify_attempts` is still 0 and every `queued_at` is null.
  - 145's job monitor records the new job as first seen (`145:58`, `:242`).
- **Rollback.** `select cron.unschedule('ops-dispatch-alerts');` plus A's rollback file and ledger row.

### Step 4. Test the channel, reaching only the owner (no database change, no switch)
- **Before.** Re-run step 1's query: `active_push_tokens` must be 0 for every admin, or the test also pushes them.
- **Do.** Supabase → Edge Functions → `notify-report` → test invoke with the service-role authorisation (the function refuses anything else, `notify-report:111-119`), with this body:
  ```json
  {"event":"ops_alert","alert_key":"test:owner-channel-check","kind":"test","fire_count":1,"incident_seq":1}
  ```
- **Verify.**
  - The reply is `{"ok":true,"event":"ops_alert","attempted":3,"delivered":1}`: 2 push attempts to admins with no device, both undelivered once P-1 is fixed, and 1 email. Before the P-1 fix it would wrongly say `delivered: 3`.
  - Exactly one email arrives at the owner's account, subject "[Snatch It] Operating Console alert", naming `test:owner-channel-check`.
  - Sentry shows one `ops-alert` event, and nobody else was notified.
- **What it does not touch.** No `ops.alert` row, no switch, no schedule, and no other event (`ops_alert` takes no delivery claim, `notify-report:280`).
- **Rollback.** None needed.
- **Stop if** `delivered` is not 1, if the email does not arrive (read Resend's logs), or if anyone else was notified.

### Step 5. Clear the backlog before the first delivery (owner, in admin v2)
- **Why.** The first enabled tick posts every alert that is firing, unacknowledged, undelivered and not in flight (`146:275-284`), up to 20 per call. Today that is 15 emails at once.
- **Read** (exactly the dispatcher's eligibility rule; expect 15 before and 0 after):
  ```sql
  select count(*) as would_post
    from ops.alert a
   where a.state = 'firing' and a.acknowledged_at is null and a.delivered_at is null
     and a.notify_request_id is null and a.notify_attempts < 5;
  ```
- **Do.** Admin v2 → `/system` → Alerts → acknowledge each firing alert with a note such as "backlog before first delivery, reviewed <date>". Each acknowledgement writes an `alert.acknowledged` audit row (`146:348-351`).
- **Do not:**
  - rely on dismissing the cases (see §1);
  - update `ops.alert` by SQL, which skips the audit row.
- **Note.** Acknowledging is not fixing: the 15 cases stay open for their own per-case decisions.
- **Rollback.** None needed. An acknowledgement covers the current incident only; a recurrence opens a new incident (`146:121-129`).

### Step 6. Turn delivery on, with a canary (owner; two founders once the money-switch proposal ships)
- **6a. Optional canary.** In the SQL editor, as the database owner, run `select ops.alert_fire('test:delivery-canary', 'test', '{}'::jsonb);`. `would_post` becomes 1. (`alert_fire` is revoked from `service_role`, `146:140`.)
- **6b. The switch.** Console → `/system` → Settings → `alert_delivery_enabled` → `true`, with the reason "O-2 go <date>". Today one founder can do this. Under `TWO_PERSON_MONEY_SWITCHES_PROPOSAL.md` it parks until the second founder approves it on System → Approvals.
- **Verify.**
  - Within about 5 minutes the canary has `queued_at` and `notify_request_id`.
  - Within about 10 minutes it has `delivered_at`, `delivery_status = 200` and no `last_notify_error`.
  - The owner receives one email for `test:delivery-canary`, and `ops.audit` has the `action.setting_set` row.
  - Then acknowledge the canary in v2 and run `select ops.alert_recover('test:delivery-canary');`.
- **Rollback.** Set `alert_delivery_enabled` back to `false` (one founder, as a brake, under the proposal). Posting stops on the next tick, and the schedule can stay.
- **Stop if** `delivered_at` is still null after 3 ticks (read `last_notify_error`), or if `delivered_at` is set but no email arrived (P-1 again).

## 3. Out of scope

- The push channel. It needs an admin device registered from a production build (`POLICY_PROMISES_DECISION_LIST_20260924.md:67`).
- Customer emails for reports and disputes. SMS (none is configured, `notify-report:24-25`).
- Any change to the alert content. The body is an allow-list (alert key, kind, counts, times, case and job identifiers) and never carries customer details (`146:287-300`).
