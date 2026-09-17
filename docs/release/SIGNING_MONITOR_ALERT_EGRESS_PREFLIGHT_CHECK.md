# Signing-monitor alert egress — the read-only production check (B, 2026-09-17)

**Status: DRAFT FOR THE OWNER'S AUTHORIZATION. No production read is authorized by this document, and B has made none.**
A packages it into the production preflight; the owner authorizes the reads **by name** or not at all.

## 0. The question, and the shape of the answer
`kernel.check_signing_key_invariants` (migration 099, cron `monitor-signing-key-invariants`, `23 5 * * *`) is the only continuous
check that production's ES256 trust root has not changed. It reports clean today. **What is unverified is not the check — it is the
alarm.** Its alert path is the `notify-report` edge function, gated by `EMAIL_ENABLED` (default `false`) and `RESEND_API_KEY`, and
the Phase-2 notify rail behind it has no sender at all (senders parked and unauthored, `notify.delivery_lease_interval` seeded
null, claim fails closed by PFA-22).

**The asymmetry that governs this whole document: these reads can only FALSIFY delivery, never confirm it.** Every item below can
show that an alert *cannot* arrive. None of them, alone or together, shows that one *would*. A clean result means "no blocker was
found among the things that can be read without secret values" — it does not mean the alarm works. Only an end-to-end test alert
with an observed receipt would show that, and **a test alert is not proposed here and is not authorized.**

## 1. The reads, exactly as they would run
Each is read-only. **No statement returns a secret value.** Two are production *data* reads (counts) and are marked, because the
standing rule is that even an aggregate count on production needs the owner's authorization for that specific read.

| # | Statement / command | Kind |
|---|---|---|
| R1 | `select name, created_at, updated_at from vault.secrets order by name;` | metadata. **`vault.secrets`, never `vault.decrypted_secrets`** — the decrypted view is not touched by this check at all. |
| R2 | `select jobid, jobname, schedule, active from cron.job where jobname = 'monitor-signing-key-invariants';` | metadata |
| R3 | `select status, start_time, end_time from cron.job_run_details where jobid = <R2.jobid> order by start_time desc limit 5;` | metadata |
| R4 | `select key, version from catalog.platform_config where key like 'signing.%' order by key, version desc;` | metadata. Keys and versions only — **no `value` column**, so the expected fingerprint is never read. |
| R5 | `select key, version from catalog.platform_config where key = 'notify.delivery_lease_interval';` | metadata |
| R6 | `select count(*) from cron.job where jobname in ('notify-dispatch','notify-receipts');` | metadata (expected: 0) |
| R7 | `supabase secrets list --project-ref <production>` | metadata. Returns **NAME and DIGEST only**; digests are not reversible and no value is printed, quoted or recorded. |
| R8 | `supabase functions list --project-ref <production>` | metadata. `notify-report` version, status, `verify_jwt`. |
| R9 | `select count(*) from public.admin_users;` | **production data read (count only)** |
| R10 | `select count(*) from public.push_tokens t join public.admin_users a on a.user_id = t.user_id where t.is_active;` | **production data read (count only)** |

## 2. What each establishes — as a prerequisite, not as proof
- **R1, R7 — the secret NAMES exist.** Establishes only that a name is present. A present name says nothing about whether the value
  is correct, current, or accepted by the provider.
- **R2, R3 — the monitor runs.** Establishes that the job is active and its recent runs succeeded. It does **not** establish that an
  alert would leave the database: the runs succeed precisely because there is nothing to alert on, so the egress arm has never
  executed in production.
- **R4 — the monitor's configuration keys exist at the expected versions.** Whether the monitor is *enabled* is already established
  by the C5 and C6 execution records (`signing.monitor_enabled` v2 = true, dual-controlled) and corroborated by R2/R3 — so its value
  does not need reading here.
- **R5, R6 — the notify rail's sender really is absent by construction**, not by a local misconfiguration: the lease key exists at
  its seeded version and neither sender job is scheduled. This is what makes any notify-rail route unusable for the alarm today.
- **R8 — `notify-report` is deployed** and its JWT posture is known, so the alert POST has a live endpoint to reach.
- **R9, R10 — the push arm has, or does not have, a possible recipient.** This is the most decisive item in the list and the one
  most likely to falsify: **if R10 is 0, the admin push fan-out cannot deliver to anyone, whatever the email path does.**

## 3. What remains UNKNOWN after all ten reads
Without reading secret values, and without sending a test alert, none of the following is answerable:
1. **Whether `EMAIL_ENABLED` is actually on.** The code requires the exact string `'true'` and defaults to `false`. R7 shows the name
   is set; a name that is set to `"false"` looks identical. **Presence is not the value** — this is the single most misleading item
   in the check, and it must not be reported as "email is enabled".
2. **Whether `RESEND_API_KEY` is valid**, unexpired, and bound to a verified sending domain.
3. **Whether `ADMIN_EMAIL` resolves to a mailbox a human reads.** A deliverable address nobody opens is indistinguishable here from
   a working alarm.
4. **Whether pg_net egress from production actually reaches the edge function.** The sandbox window is a live reminder that a post
   can be *made* and *refused* while the cron still records success: five ticks, all 401, and `cron.job_run_details` recorded only
   that the queuing SQL ran. Worse for forensics, `net._http_response` is a ~6-hour TTL cache, so the absence of rows proves nothing
   after six hours.
5. **Whether the alert POST is attempted at all with the current URL configuration.** The 099 monitor body is one of the four
   rewritten by migration 133 to read the base URL from Vault `project_url` — and 133 is **not applied on production**, where the
   host is still the hardcoded form. Any conclusion drawn before 133 does not carry across it.
6. **Whether an admin's registered push token is still live at the provider.** A token can be present, active in our table, and dead
   at APNs/FCM.
7. **Whether the Sentry arm works** — the alert also calls `captureException`, whose transport is unverified here.

## 4. The statement that must travel with any result
> None of these reads proves that a signing-key invariant alert would be delivered to a human. They establish prerequisites only.
> A clean result means no blocker was found among the readable items; it does not mean the alarm works. Proving delivery requires an
> end-to-end test alert with an observed receipt, which is not authorized and is not proposed here.

## 5. If the owner authorizes only part of it
The cheapest falsifying subset is **R10 with R9** (does any admin device exist to receive the push?) and **R7** (are the email
secrets set at all?). Those three can show the alarm is impossible today. They cannot show it is possible.
