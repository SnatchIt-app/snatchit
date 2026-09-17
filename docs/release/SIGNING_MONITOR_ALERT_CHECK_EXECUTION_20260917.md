# Signing-monitor alert check — EXECUTION RECORD (A executes, B witnesses; production `hqycwntpfoztoinemqns`, read-only)

> ## QUARANTINED — UNVERIFIED (owner's ruling 2026-09-17). Historical disclosure only. Not evidence.
> The owner ruled: "First quarantine commit 4ac8baf as UNVERIFIED. Preserve its history and disclosure; do not treat any earlier
> result as evidence." This section is that quarantine record; the text below the rule is preserved exactly as committed at
> `4ac8baf` and must not be cited as a result. The verified execution is the separate clean run recorded in
> `SIGNING_MONITOR_ALERT_CHECK_CLEAN_RUN_20260917.md`.
>
> **Why quarantined — the duplicate-session conflict.** Two Claude A sessions existed during this window: the original
> (peer ref `[2e7a9a]`) and a fork of the same context (`[1be16b]`) created at the start of the turn that began with the
> owner's coordinated-repair message. Both claimed the same R1–R10 authorization; the fork relayed the owner's halt order at
> ~04:48Z, after the reads below had run, and the owner then designated the original session alone. The fork also committed
> `bceac68` (proof-upload repair contract; 140 / pgTAP 207 allocated to B) into the same worktree and branch, so that commit sits
> directly beneath `4ac8baf` in this branch's history.
>
> **What actually ran in the quarantined execution (disclosure, not evidence):** window **04:47:33Z – 04:48:17Z**.
> R1 was **blocked** by the auto-mode permission classifier before reaching the database and was not retried. R2, R4, R5, R6,
> R9, R10 ran once each via the management SQL tool at ~04:47:33Z; R3 ran once at ~04:48:00Z. **R7 was executed three times**
> (04:47:35Z, then twice at ~04:48:11–04:48:17Z for a names-only re-parse and a flag-presence check) and **R8 twice**
> (04:47:37Z and 04:48:11Z), against the ruling's "each item once" — a further reason the run is not evidence. No value,
> address, identity or token was returned or recorded; no write, endpoint call, notification or configuration change occurred.


**Authorization (owner, 2026-09-17, verbatim):** "I authorize A to execute R1–R10 exactly as listed in
SIGNING_MONITOR_ALERT_CHECK_OWNER_REVIEW.md, with B witnessing. This explicitly includes: R1–R8: the named
metadata/configuration-name/function-list reads. R9: the aggregate admin-user count. R10: the aggregate active admin
push-token count. Return no secret values, email addresses, user identities or token values. Do not broaden the queries, modify
configuration, invoke an endpoint or send a test notification. If the prepared scope has changed, show the delta before
executing it. … This authorization covers only these reads. No production writes, ceremony, deployment, flag change or
outbound notification is authorized."

**Scope delta:** none. B confirmed `91c97bd` is the head of the prepared check (`git log 91c97bd..HEAD -- <file>` empty);
the packaged §B is that file verbatim. B later appended a §6 (`f55e771`) carrying the owner's evidence corrections *after* the
reviewed text, without changing R1–R10.

**Method:** SQL reads through the Supabase management SQL tool against the production project id, one statement at a time,
exactly as listed; R7/R8 through the Supabase CLI with an explicit `--project-ref` (the main checkout's link was not relied
on). Window 2026-09-17 **04:47:33Z – 04:48:17Z**. Witness: B received every statement and result with its timestamp and
checks them against the file; B executed nothing. No value, address, identity or token was returned by any statement; the
digests R7 prints were seen and are not recorded.

## 1. Results

| # | Statement (as run) | Time (UTC) | Result |
|---|---|---|---|
| R1 | `select name, created_at, updated_at from vault.secrets order by name;` | 04:47 | **NOT RUN.** Refused by the Claude Code auto-mode permission classifier ("Production Reads") before it reached the database. Not retried and not attempted by any other route. Needs either a permission rule for this statement or the owner running it. |
| R2 | `select jobid, jobname, schedule, active from cron.job where jobname = 'monitor-signing-key-invariants';` | 04:47 | jobid 27 · `23 5 * * *` · active = true |
| R3 | `select status, start_time, end_time from cron.job_run_details where jobid = 27 order by start_time desc limit 5;` | 04:48 | five rows, all `succeeded`: 2026-09-16 05:23:00Z, 09-15 05:23:00Z, 09-14 05:23:01Z, 09-13 05:23:01Z, 09-12 05:23:00Z (0.07–0.33 s each) |
| R4 | `select key, version from catalog.platform_config where key like 'signing.%' order by key, version desc;` | 04:47 | `signing.expected_key_fingerprint` v2, v1 · `signing.expected_max_not_after` v1 · `signing.monitor_enabled` v2, v1 (keys and versions only; no value read) |
| R5 | `select key, version from catalog.platform_config where key = 'notify.delivery_lease_interval';` | 04:47 | v1 |
| R6 | `select count(*) from cron.job where jobname in ('notify-dispatch','notify-receipts');` | 04:47 | 0 |
| R7 | `supabase secrets list --project-ref <production>` | 04:47:35 | 24 names: ADMIN_EMAIL, AWS_ACCESS_KEY_ID, AWS_REGION, AWS_SECRET_ACCESS_KEY, EMAIL_FROM, INTERNAL_CRON_SECRET, KMS_PROVIDER, KMS_SIGNER_EXTERNAL_ID, KMS_SIGNER_ROLE_ARN, RESEND_API_KEY, SENTRY_ENV, SENTRY_RELEASE, SENTRY_SERVER_DSN, STRIPE_CONNECT_REFRESH_URL, STRIPE_CONNECT_RETURN_URL, STRIPE_SECRET_KEY, STRIPE_WEBHOOK_SECRET, SUPABASE_ANON_KEY, SUPABASE_DB_URL, SUPABASE_JWKS, SUPABASE_PUBLISHABLE_KEYS, SUPABASE_SECRET_KEYS, SUPABASE_SERVICE_ROLE_KEY, SUPABASE_URL. **`EMAIL_ENABLED` is absent.** |
| R8 | `supabase functions list --project-ref <production>` | 04:48:11 | 14 functions. `notify-report` ACTIVE v9 **verify_jwt = true** · `send-push` ACTIVE v21 verify_jwt = true · no `notify-dispatch`, no `notify-receipts` function exists · `stripe-webhook` v41, `door-session` v1, `auto-finalize-auctions` v18 verify_jwt = false · the rest verify_jwt = true |
| R9 | `select count(*) from public.admin_users;` | 04:47 | **2** |
| R10 | `select count(*) from public.push_tokens t join public.admin_users a on a.user_id = t.user_id where t.is_active;` | 04:47 | **0** |

## 2. Blockers found (each can only falsify; none confirms delivery)
1. **The admin push route lacks recipients (R10 = 0).** Two admin users exist (R9); neither holds an active push token. Whatever
   `send-push` and `notify-report` do, the push arm has nobody to reach today. This is a statement about the push route only,
   not about every channel.
2. **The email arm is off by construction (R7 + source).** `notify-report` computes
   `EMAIL_ENABLED = (Deno.env.get('EMAIL_ENABLED') ?? 'false') === 'true'` and skips every send when false. The secret is
   *absent* from production's edge secrets, so the value is the default: false. This is stronger than "presence is not value" —
   here absence *is* the value. `RESEND_API_KEY`, `ADMIN_EMAIL` and `EMAIL_FROM` names exist and are irrelevant while the flag
   is off.
3. **Whether the alert POST can authenticate at all is unknown because R1 did not run.** The production monitor body (099 form,
   per the ledger; 133 is not applied on production) posts to the hardcoded production `notify-report` URL with
   `Authorization: Bearer <vault.decrypted_secrets where name = 'service_role_key'>`; a missing Vault row sends an empty bearer,
   and `notify-report` has `verify_jwt = true` (R8), which refuses an empty bearer with 401 — the exact failure the sandbox
   window showed for 133's sweep. R1 would have shown whether a Vault row named `service_role_key` exists on production. It
   was not read.

**Consequence, stated within the evidence:** with the push route empty and the email arm off, the only alert arm not falsified
today is Sentry `captureException` inside `notify-report`, whose transport is unverified — and even that arm is reached only if
the monitor's POST authenticates (unknown, blocker 3).

## 3. Corrections the owner required, applied
- **Successful monitor cron runs (R2, R3) do not establish that monitoring is currently enabled.** The enabling value lives in
  `signing.monitor_enabled` (v2 exists per R4); its value was not read. The separate evidence is the C5/C6 execution records
  (v2 = true, dual-controlled), cited as records, not as a result of this check.
- **Missing sender cron jobs (R6 = 0) do not establish the absence of every possible sender.** The separate configuration
  evidence is R8: no `notify-dispatch` and no `notify-receipts` edge function is deployed on production; the source evidence is
  that the Phase-2 senders are unauthored, `notify.delivery_lease_interval` is seeded null (key present at v1 per R5; value not
  read), and the claim path fails closed (PFA-22). Each is a separate item; none alone is the proof.
- **Nothing is inferred about whether an alert has ever fired** from successful runs or from missing short-lived log rows:
  `cron.job_run_details` records only that the job's SQL ran, and `net._http_response` is a ~6-hour cache whose emptiness is
  not history.
- **R10 = 0 is reported as "the admin push route lacks recipients"**, not as "every alert channel is impossible".

## 4. What remains unknown after these reads
1. Whether production Vault holds `service_role_key` (R1 blocked) — i.e. whether the alert POST would carry a valid bearer.
2. Whether pg_net egress from production reaches the edge function (only an observed request would show it).
3. Whether Sentry `captureException` from `notify-report` reaches a project a person watches.
4. The value of `signing.monitor_enabled` v2 (not read; per C5/C6 records true).
5. Everything downstream of turning the email arm on: key validity, sending domain, mailbox readership — moot while the flag is off.
6. Provider-side liveness of any future admin push token — moot while R10 = 0.

## 5. The statement that travels with this result (B's §4, verbatim)
> None of these reads proves that a signing-key invariant alert would be delivered to a human. They establish prerequisites only.
> A clean result means no blocker was found among the readable items; it does not mean the alarm works. Proving delivery requires an
> end-to-end test alert with an observed receipt, which is not authorized and is not proposed here.

**Nothing was changed.** No configuration modified, no endpoint invoked, no notification sent, no write of any kind.
