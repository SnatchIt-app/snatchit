# Signing-monitor alert check — CLEAN RUN (the verified execution; A alone, owner-designated; production `hqycwntpfoztoinemqns`, read-only)

**Authorization (owner, 2026-09-17, in A's own channel, verbatim):** "I designate only this session to handle the signing-monitor
check. First quarantine commit 4ac8baf as UNVERIFIED. … Then execute one clean run of the exact R1–R10 scope in
SIGNING_MONITOR_ALERT_CHECK_OWNER_REVIEW.md, in document order, once each … No retries, broadened queries or alternate
routes. If R1 is blocked before execution, record it as blocked and continue only if the exact document allows that; do not
bypass the permission classifier. Do not read secret values, decrypted secret views, email addresses, token values or user
identities. Do not invoke an endpoint, send a test notification, modify configuration or perform any production write.
Before execution, report the exact command list and UTC start time. Afterward, report each item's outcome, UTC timestamp,
returned shape and limits. Keep the previous execution and the new execution completely separate. B may witness only after
this clean run completes, by comparing scope and timestamps. … This authorization covers only R1–R10 and the quarantine record."

**Separation from the quarantined run.** The earlier execution (04:47:33–04:48:17Z, commit `4ac8baf`) is quarantined as
UNVERIFIED at `83e0998` and is not cited anywhere below. Every figure here comes from this run only.

**Identity note.** The owner designated the original A session by its earlier peer ref `[2e7a9a]`. At execution time the agent
listing showed this same session as `[48283b]` (the ref changed on a session restart); the fork `[1be16b]` remained separately
listed, idle, stood down. A proceeded as the only non-fork A session and disclosed the ref change to the owner before the first read.

**Method.** SQL items through the Supabase management SQL tool against the production project id, one statement per call,
strictly sequential in document order, once each; R7/R8 through the CLI with an explicit `--project-ref`, once each, output
written to a scratch file and parsed from the file (no re-execution). Command list and start time were reported to the owner
before R1. Window **05:09:46Z – 05:11:10Z**. No value, decrypted view, address, identity or token was returned or recorded;
R7's digests were written to the scratch file only and are not reproduced. Nothing was invoked, sent, changed or written.

## 1. Results — outcome, UTC time, returned shape, limits

| # | Statement (as run, once) | Issued (UTC) | Outcome | Shape | Limit |
|---|---|---|---|---|---|
| R1 | `select name, created_at, updated_at from vault.secrets order by name;` | 05:09:46 | **ran** — 1 row: name `service_role_key`, created = updated = 2026-06-11 19:03:18Z | 1 row × (name, created_at, updated_at) | a name and dates; the value, its validity and its currency are not established. No `project_url` row exists (consistent with 133 not applied on production). Note: the same statement was refused by the permission classifier in the quarantined run and allowed here; A did nothing to change that |
| R2 | `select jobid, jobname, schedule, active from cron.job where jobname = 'monitor-signing-key-invariants';` | 05:09:59 | jobid 27 · `23 5 * * *` · active = true | 1 row × 4 | the job is scheduled; nothing about whether monitoring is enabled or an alert can leave |
| R3 | `select status, start_time, end_time from cron.job_run_details where jobid = 27 order by start_time desc limit 5;` | 05:10:07 | 5 rows, all `succeeded`: 2026-09-16 05:23:00Z, 09-15 05:23:00Z, 09-14 05:23:01Z, 09-13 05:23:01Z, 09-12 05:23:00Z; durations 0.07–0.33 s | 5 rows × 3 | records that the job's SQL ran; says nothing about the alert arm, which runs only on a violation |
| R4 | `select key, version from catalog.platform_config where key like 'signing.%' order by key, version desc;` | 05:10:21 | `signing.expected_key_fingerprint` v2, v1 · `signing.expected_max_not_after` v1 · `signing.monitor_enabled` v2, v1 | 5 rows × (key, version) | keys and versions only; no value read, so "enabled" is not established here |
| R5 | `select key, version from catalog.platform_config where key = 'notify.delivery_lease_interval';` | 05:10:28 | v1 | 1 row × 2 | key exists at its seeded version; value not read |
| R6 | `select count(*) from cron.job where jobname in ('notify-dispatch','notify-receipts');` | 05:10:35 | 0 | 1 row × count | no cron sender by those names; not by itself the absence of every sender (see §3) |
| R7 | `supabase secrets list --project-ref hqycwntpfoztoinemqns` | 05:10:55–05:10:57 | 24 names: ADMIN_EMAIL, AWS_ACCESS_KEY_ID, AWS_REGION, AWS_SECRET_ACCESS_KEY, EMAIL_FROM, INTERNAL_CRON_SECRET, KMS_PROVIDER, KMS_SIGNER_EXTERNAL_ID, KMS_SIGNER_ROLE_ARN, RESEND_API_KEY, SENTRY_ENV, SENTRY_RELEASE, SENTRY_SERVER_DSN, STRIPE_CONNECT_REFRESH_URL, STRIPE_CONNECT_RETURN_URL, STRIPE_SECRET_KEY, STRIPE_WEBHOOK_SECRET, SUPABASE_ANON_KEY, SUPABASE_DB_URL, SUPABASE_JWKS, SUPABASE_PUBLISHABLE_KEYS, SUPABASE_SECRET_KEYS, SUPABASE_SERVICE_ROLE_KEY, SUPABASE_URL. **`EMAIL_ENABLED` absent.** | JSON, 24 objects × (name, updated_at, value=digest) | names and digests; a present name says nothing about its value. Absence of `EMAIL_ENABLED` IS its value (code default `'false'`) |
| R8 | `supabase functions list --project-ref hqycwntpfoztoinemqns` | 05:10:57–05:10:58 | 14 functions, all ACTIVE. `notify-report` v9 **verify_jwt = true** · `send-push` v21 verify_jwt = true · no `notify-dispatch`, no `notify-receipts` · verify_jwt = false only on `stripe-webhook` v41, `auto-finalize-auctions` v18, `door-session` v1 | JSON, 14 objects | deployment and JWT posture; not reachability |
| R9 | `select count(*) from public.admin_users;` | 05:11:02 | **2** | 1 row × count | aggregate only |
| R10 | `select count(*) from public.push_tokens t join public.admin_users a on a.user_id = t.user_id where t.is_active;` | 05:11:10 | **0** | 1 row × count | aggregate only |

## 2. Blockers found (falsifiers; none confirms delivery)
1. **The admin push route lacks recipients (R10 = 0, R9 = 2).** Two admin users; neither holds an active push token. A statement
   about the push route only.
2. **The email arm is off by construction (R7 + source).** `notify-report` computes
   `EMAIL_ENABLED = (Deno.env.get('EMAIL_ENABLED') ?? 'false') === 'true'` and skips every send when false; the secret is absent,
   so the value is the default. `RESEND_API_KEY`, `ADMIN_EMAIL`, `EMAIL_FROM` names exist and are irrelevant while the flag is off.
3. **The alert POST's bearer exists by name only (R1 + R8).** The production monitor body (099 form; 133 not applied on
   production) posts to the hardcoded `notify-report` URL with `Bearer <vault 'service_role_key'>`; R1 shows one row of that name
   (2026-06-11) and R8 shows `notify-report` requires a JWT. Whether that Vault value is a currently valid service-role JWT is not
   established (value not read).

**Within the evidence:** with the push route empty and the email arm off, the only alert arm not falsified is Sentry
`captureException` inside `notify-report`, unverified — and reached only if the POST authenticates (blocker 3, unknown).

## 3. Evidence corrections the owner required, applied
- **Successful monitor runs (R2, R3) do not establish that monitoring is currently enabled.** The enabling value is
  `signing.monitor_enabled` (v2 exists per R4); not read here. Separate evidence: the C5/C6 execution records (v2 = true,
  dual-controlled), cited as records.
- **Missing sender cron jobs (R6 = 0) do not establish the absence of every possible sender.** Separate configuration evidence
  from this run: R8 — no `notify-dispatch` and no `notify-receipts` edge function is deployed. Separate source evidence: the
  Phase-2 senders are unauthored; `notify.delivery_lease_interval` is seeded null (present at v1 per R5; value not read); the claim
  path fails closed (PFA-22). Each is a separate item.
- **Nothing is inferred about whether an alert has ever fired** from successful runs or from missing short-lived log rows.
- **R10 = 0 is "the admin push route lacks recipients"**, not "every alert channel is impossible".

## 4. What remains unknown after this run
1. Whether the Vault `service_role_key` value is a valid, current bearer for `notify-report` (value not read).
2. Whether pg_net egress from production reaches the edge function.
3. Whether Sentry `captureException` from `notify-report` reaches a project a person watches.
4. The value of `signing.monitor_enabled` v2 (per C5/C6 records true; not read).
5. Everything downstream of turning the email arm on — moot while the flag is absent.
6. Provider-side liveness of any future admin push token — moot while R10 = 0.

## 5. The statement that travels with this result (B's §4, verbatim)
> None of these reads proves that a signing-key invariant alert would be delivered to a human. They establish prerequisites only.
> A clean result means no blocker was found among the readable items; it does not mean the alarm works. Proving delivery requires an
> end-to-end test alert with an observed receipt, which is not authorized and is not proposed here.

**Witness:** B, after completion only, by comparing scope and timestamps against the review document; B triggered nothing and
validates nothing about the quarantined run.
