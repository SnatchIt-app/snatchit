# Notification System Audit — End to End

**Date:** 2026-06-12 · **Type:** read-only · **Project:** `hqycwntpfoztoinemqns` · **Function:** `notify-report` v4 (deployed, ACTIVE, `verify_jwt:true`) · **Migration 033:** applied (verified: `category`, `proof_status`, `admin_users`, `is_admin()`, `notify_moderation_event()`, both triggers, `proof-docs` bucket all present live).

## Overall verdict

**CONDITIONAL FAIL — one blocking defect (N1).** The code paths are correct and migration 033 is live, but the notification delivery hop has the **same edge-function auth trap that already broke `enforce-transfer-expiry` once**: `notify-report` runs with `verify_jwt:true` *and* does its own bearer check against `SUPABASE_SERVICE_ROLE_KEY`/`INTERNAL_CRON_SECRET`, while the DB trigger calls it with the 219-char Vault JWT. Unless `INTERNAL_CRON_SECRET` was set for this function to that exact JWT, every trigger call returns 401 and is silently swallowed (fire-and-forget). No report/dispute notification has fired since deploy (0 rows in `net._http_response` for the function), so this is unproven in production and must be verified before relying on it.

---

## 1. notify-report edge function — PASS (code) / see N1 (delivery)

Source: `supabase/functions/notify-report/index.ts`.

| Check | Result | Evidence |
|---|---|---|
| Uses Resend | **PASS** | `fetch('https://api.resend.com/emails', …)` lines 60-73 |
| RESEND_API_KEY required for email | **PASS** | `if (!RESEND_API_KEY) { …skip }` line 56-59; read line 27 |
| EMAIL_FROM used | **PASS** | `from: EMAIL_FROM` in Resend body, line 70; default `Snatch It <no-reply@snatchitapp.com>` line 30 |
| ADMIN_EMAIL used | **PASS** | `sendEmail(ADMIN_EMAIL, …)` report path line ~150, dispute path line ~178; default `support@snatchitapp.com` line 31 |
| EMAIL_ENABLED gates delivery | **PASS** | `if (!EMAIL_ENABLED) { …skip }` line 50-53; parsed `=== 'true'`, default OFF, line 28 |

**N1 (FAIL, HIGH):** function-side auth (`constantTimeEqual(token, SUPABASE_SERVICE_ROLE_KEY)` / `INTERNAL_CRON_SECRET`, lines ~95-104) will reject the trigger's Vault-sourced 219-char JWT if the runtime `SUPABASE_SERVICE_ROLE_KEY` env is the 41-char secret-format key (the documented mismatch in `enforce-transfer-expiry/index.ts:21-24`). Fix = set `INTERNAL_CRON_SECRET` for `notify-report` to the same legacy service-role JWT stored in Vault (`supabase secrets set INTERNAL_CRON_SECRET=<jwt> --project-ref hqycwntpfoztoinemqns`), then invoke once and confirm 200. **Until verified: treat all email + push delivery as unconfirmed.**

**N2 (verify, MEDIUM):** `RESEND_API_KEY`, `EMAIL_ENABLED`, `EMAIL_FROM`, `ADMIN_EMAIL` secrets are read from env but could not be confirmed set (secret values aren't readable via SQL). With `EMAIL_ENABLED` unset/false, **all email is correctly skipped** (safe default) but no email will ever send in production until `EMAIL_ENABLED=true` is set.

---

## 2. Report workflow

Trigger: `trg_notify_report_created AFTER INSERT ON public.reports` → `notify_moderation_event()` → pg_net POST `event='report_created'`. Live-verified present. `reports` columns confirmed: `reporter_id, target_id, target_type, reason, notes, status` — matches the payload built in `notify_moderation_event` (migration 033) and consumed by the function.

**Report a LISTING** (`target_type='listing'`): function resolves `reportedUserId` = `listings.seller_id` for `target_id`. Recipients:

| Recipient | Email | DB/push notification | Result |
|---|---|---|---|
| Admin (every `admin_users` row → currently 1) | ADMIN_EMAIL | push per admin | PASS* |
| Reporter | their auth email | "Report received" push | PASS* |
| Reported seller (if ≠ reporter) | their auth email | "One of your listings is under review" push | PASS* |

**Report a USER** (`target_type='user'`): `reportedUserId = target_id` directly. Same three-way fan-out; reported party copy = "Your profile is under review". PASS*.

\* PASS on logic/wiring; gated by N1 (delivery) and N2 (email enabled). **Note:** "DB notifications" are delivered as **Expo push via `send-push`**, not rows in a notifications table — there is **no in-app notification-center table** (N3, LOW). Admins receive push + email but there is **no admin dashboard UI** (migration 033 only added the `is_admin()` hook), so admin "DB notification" = push + email only (N4, MEDIUM — matches the documented "future dashboard" decision).

---

## 3. Dispute workflow

Trigger: `trg_notify_dispute_opened AFTER UPDATE OF status ON public.transfers WHEN (NEW.status='disputed' AND OLD.status IS DISTINCT FROM 'disputed')` → `event='dispute_opened'`. Live-verified present.

| Recipient | Push | Email | Result |
|---|---|---|---|
| Buyer (`transfers.buyer_id`) | "Transaction under review" | auth email | PASS* |
| Seller (`transfers.seller_id`) | "Transaction under review" | auth email | PASS* |
| Admin (`admin_users`) | "Dispute opened" | ADMIN_EMAIL | PASS* |

\* Gated by N1/N2. **N5 (MEDIUM, coverage gap):** the trigger fires on `status → 'disputed'`. The in-app dispute path (`buyer_dispute_transfer`) sets that status, so it's covered. But a **post-payout Stripe chargeback** that lands while a transfer is already `auto_released` never transitions to `disputed` (per the earlier trust audit), so it raises a `disputes` row **without firing this trigger** — those disputes generate no buyer/seller/admin notification. Off-platform "under review" messaging therefore won't reach users on post-payout chargebacks.

---

## 4. SMS — FAIL (does not exist) / correctly omitted

No SMS implementation anywhere: no Twilio/Vonage/MessageBird/SNS provider, no `sendSms`, no `phone`-based send in `notify-report`, `send-push`, or any migration. The function header explicitly documents SMS as not implemented because no provider is configured. **This is the intended state** (per prior instruction "do not invent SMS"), so it is a correct omission, not a regression. **Missing implementation, if ever wanted:** (1) an SMS provider account + secret, (2) a `sendSms()` helper in `notify-report`, (3) a consented phone column + opt-in (most users have no phone on file — `profiles` has no verified phone for notifications). Until all three exist, SMS must stay off.

---

## 5. Admin account — PASS

| Check | Result | Evidence (live) |
|---|---|---|
| Only Snatch It admin is admin | **PASS** | `admin_users` = exactly 1 row: `SNATCH IT APP ADMIN` / `2b117757-f4e3-41c1-b7df-68a4502d0fba` |
| No other account can gain admin | **PASS** | `admin_users` RLS enabled, **0 policies** → no anon/authenticated read or write; only service_role (RLS bypass) can insert. No app code path writes the table. |
| `is_admin()` not abusable | **PASS** | SECURITY DEFINER, evaluates `auth.uid()` only (can't probe other users); EXECUTE = `authenticated, service_role`; **anon revoked** (`anon_is_admin=false`, `auth_is_admin=true` verified) |
| No client self-promotion | **PASS** | no INSERT/UPDATE grant to client roles on `admin_users`; `proof_status` self-set also blocked by `trg_guard_proof_status` |

---

## 6. Email sender identity — recommendation

Use **`no-reply@snatchitapp.com`** as the `EMAIL_FROM` sender (already the function default) for all automated report/dispute mail — these are one-way system notifications, and a no-reply From discourages users replying into an unmonitored box. Keep **`support@snatchitapp.com`** as the `ADMIN_EMAIL` destination (the monitored inbox where admin alerts land) and as the human reply-to/contact surfaced in-app (Settings → Support, already `support@snatchitapp.com`; legal `legal@snatchitapp.com`). **Required before production:** verify the `snatchitapp.com` domain in Resend and publish SPF + DKIM (and ideally DMARC) DNS records, or mail will land in spam / be rejected — **N6 (verify, HIGH for deliverability).** Optionally set `Reply-To: support@snatchitapp.com` on user-facing mail so replies reach support despite the no-reply From (not currently set — N7, LOW).

---

## PASS / FAIL summary

| # | Path | Status |
|---|---|---|
| 1 | notify-report uses Resend | PASS |
| 1 | RESEND_API_KEY required | PASS |
| 1 | EMAIL_FROM used | PASS |
| 1 | ADMIN_EMAIL used | PASS |
| 1 | EMAIL_ENABLED gates email | PASS |
| 1 | **Trigger→function delivery auth** | **FAIL (N1)** |
| 2 | Report listing → admin/reporter/seller | PASS* (logic) / blocked by N1 |
| 2 | Report user → admin/reporter/reported | PASS* / blocked by N1 |
| 2 | DB notification recipients | PASS (push); no notif table (N3) / no admin UI (N4) |
| 3 | Dispute → buyer | PASS* / blocked by N1 |
| 3 | Dispute → seller | PASS* / blocked by N1 |
| 3 | Dispute → admin | PASS* / blocked by N1 |
| 3 | Post-payout chargeback coverage | FAIL (N5) |
| 4 | SMS exists | N/A — does not exist (intended) |
| 5 | Only Snatch It admin is admin | PASS |
| 5 | No self-promotion | PASS |
| 6 | Sender identity | no-reply@ (from) + support@ (admin/reply); domain unverified (N6) |

## Exact missing implementations / locations

- **N1 (HIGH, blocking):** set `INTERNAL_CRON_SECRET` for `notify-report` to the Vault legacy service-role JWT; auth check at `supabase/functions/notify-report/index.ts:~95-104`. Verify with one manual POST → expect HTTP 200.
- **N2 (MEDIUM):** set `RESEND_API_KEY` and `EMAIL_ENABLED=true` (prod only) via `supabase secrets set`; read at `notify-report/index.ts:27-28`.
- **N5 (MEDIUM):** post-payout chargebacks don't hit `trg_notify_dispute_opened`. Add an AFTER INSERT trigger on `public.disputes` → `notify_moderation_event` (extend the function with a `disputes`-table branch). Locations: trigger absent on `public.disputes`; `notify_moderation_event` migration 033 handles only `reports`/`transfers`.
- **N3 (LOW):** no `notifications` table / in-app notification center — delivery is push + email only.
- **N4 (MEDIUM):** no admin dashboard UI; only `is_admin()` exists. Admin alerts are push + email.
- **N6 (HIGH for deliverability):** verify `snatchitapp.com` in Resend + SPF/DKIM/DMARC DNS before enabling email.
- **N7 (LOW):** add `Reply-To: support@snatchitapp.com` on user-facing mail; `notify-report/index.ts:70` Resend body.
