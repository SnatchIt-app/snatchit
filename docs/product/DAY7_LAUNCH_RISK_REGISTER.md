# Day 7 — Launch Risk Register

**Version:** 1.0
**Date:** 2026-04-02
**Scope:** Top 10 risks for SnatchIt private beta launch

---

## Risk Severity Scale

| Level | Definition |
|-------|-----------|
| **Critical** | Could cause financial loss, legal exposure, or total service outage |
| **High** | Major feature broken or significant user trust impact |
| **Medium** | Degraded experience but workaround exists |
| **Low** | Minor inconvenience, cosmetic, or unlikely to occur |

## Risk Likelihood Scale

| Level | Definition |
|-------|-----------|
| **Very Likely** | Expected to happen during beta (>70%) |
| **Likely** | Probable during beta (40–70%) |
| **Possible** | Could happen under certain conditions (10–40%) |
| **Unlikely** | Rare but not impossible (<10%) |

---

## Top 10 Launch Risks

### RISK 1 — Orphaned Payment (Payment Succeeds, No Transfer Row Created)

| Field | Value |
|-------|-------|
| **Severity** | Critical |
| **Likelihood** | Possible |
| **Description** | Stripe `payment_intent.succeeded` webhook fires but `stripe-webhook` edge function fails to create a `transfers` row. Buyer is charged, but no transfer exists — the system doesn't know about the sale. |
| **Mitigation** | (1) Stripe webhook retries (up to 3 attempts over 24h). (2) Daily monitoring query to find payments without matching transfers (see docs/product/DAY7_DAILY_MONITORING_CHECKLIST.md). (3) Manual recovery: admin creates transfer row via SQL using docs/operations/DAY5_ADMIN_SQL_PACK.sql. |
| **Owner** | Lead Developer |

---

### RISK 2 — Cron Job Stops Running (Expiry or Auto-Release Fails)

| Field | Value |
|-------|-------|
| **Severity** | Critical |
| **Likelihood** | Possible |
| **Description** | `enforce-transfer-expiry` or `auto-release-funds` cron stops firing due to Supabase edge function deployment issue, secret rotation, or platform outage. Expired transfers are never refunded; auto-releases never pay sellers. |
| **Mitigation** | (1) Daily check of cron execution logs. (2) If cron is down >1 hour, manually run the edge function via `curl`. (3) Set up Supabase/Sentry alert on edge function failure. |
| **Owner** | Lead Developer |

---

### RISK 3 — Seller Stripe Connect Account Not Properly Onboarded

| Field | Value |
|-------|-------|
| **Severity** | High |
| **Likelihood** | Likely |
| **Description** | Seller connects Stripe but account is in `restricted` or `pending` state. When `confirm-and-release` tries to create a Transfer to their Connect account, Stripe rejects it. Buyer has confirmed receipt, but seller can't get paid. |
| **Mitigation** | (1) App checks `charges_enabled` on seller's Connect account before allowing listing creation. (2) Admin monitors for failed transfer attempts in Stripe logs. (3) Admin contacts seller to complete Stripe onboarding. (4) Payout retried once seller account is active. |
| **Owner** | Admin / Ops |

---

### RISK 4 — Duplicate Webhook Delivery Creates Double Transfer

| Field | Value |
|-------|-------|
| **Severity** | High |
| **Likelihood** | Possible |
| **Description** | Stripe sends `payment_intent.succeeded` twice (retry or network glitch). If the idempotency check in `stripe-webhook` fails, two transfer rows are created for one payment, potentially leading to a double payout. |
| **Mitigation** | (1) `stripe-webhook` has idempotency guard checking for existing transfer by `payment_id`. (2) Database unique constraint on `transfers.payment_id` prevents duplicate rows. (3) Daily monitoring query checks for duplicate transfers. |
| **Owner** | Lead Developer |

---

### RISK 5 — Push Notifications Not Delivered

| Field | Value |
|-------|-------|
| **Severity** | Medium |
| **Likelihood** | Very Likely |
| **Description** | Expo push tokens expire, users deny notification permissions, or Expo push service has intermittent failures. Users miss critical alerts (tickets sent, payout released, refund issued). |
| **Mitigation** | (1) Critical state changes are always visible in-app (not just via push). (2) Tester onboarding doc instructs users to enable notifications. (3) Admin checks Expo push receipts for failures. (4) Consider adding email fallback post-beta. |
| **Owner** | Lead Developer |

---

### RISK 6 — Refund Fails on Expired Transfer

| Field | Value |
|-------|-------|
| **Severity** | Critical |
| **Likelihood** | Unlikely |
| **Description** | `enforce-transfer-expiry` cron marks transfer as `expired` but the Stripe refund API call fails (network error, insufficient balance on platform account, or PaymentIntent already refunded). Buyer doesn't get money back. |
| **Mitigation** | (1) Edge function logs refund failures with full error details. (2) Daily monitoring query checks for expired transfers without a corresponding Stripe refund. (3) Admin uses docs/operations/DAY5_MANUAL_REFUND_PLAYBOOK.md to issue manual refund via Stripe Dashboard. |
| **Owner** | Admin / Ops |

---

### RISK 7 — Supabase Outage or Rate Limiting

| Field | Value |
|-------|-------|
| **Severity** | High |
| **Likelihood** | Unlikely |
| **Description** | Supabase platform outage or connection pool exhaustion makes the app unusable. All reads and writes fail. Webhook processing stops. |
| **Mitigation** | (1) Supabase status page monitoring (status.supabase.com). (2) App shows friendly error screen when API is unreachable. (3) Beta scale (~20 users) is well within free/pro tier limits. (4) Database backups enable recovery if data is corrupted. |
| **Owner** | Lead Developer |

---

### RISK 8 — Stripe API Key Leak or Secret Rotation Breaks Webhooks

| Field | Value |
|-------|-------|
| **Severity** | Critical |
| **Likelihood** | Unlikely |
| **Description** | Stripe secret key is exposed (committed to repo, visible in logs) or rotated without updating Supabase edge function secrets. All payment processing and webhook verification breaks silently. |
| **Mitigation** | (1) Stripe key stored only in Supabase Edge Function secrets — never in app code or git. (2) `.gitignore` includes all `.env` files. (3) If key is rotated, update Supabase secrets immediately and redeploy edge functions. (4) Sentry alerts on 401/403 errors from Stripe. |
| **Owner** | Lead Developer |

---

### RISK 9 — User Sells Real Tickets During Beta and Transaction Fails

| Field | Value |
|-------|-------|
| **Severity** | High |
| **Likelihood** | Possible |
| **Description** | A tester ignores beta rules and lists real, valuable event tickets. The transaction encounters a bug (failed payout, orphaned payment, stuck transfer) and real money is at stake. |
| **Mitigation** | (1) Tester onboarding doc explicitly states "do not list real tickets you intend to sell to real buyers." (2) Beta uses live Stripe (required for real testing) so money IS real — admin must monitor closely. (3) Admin has manual refund and manual payout playbooks ready. (4) Keep beta group small and trusted. |
| **Owner** | Admin / Ops |

---

### RISK 10 — App Store / Play Store Rejection on Next Update

| Field | Value |
|-------|-------|
| **Severity** | Medium |
| **Likelihood** | Possible |
| **Description** | Apple or Google rejects an app update due to missing privacy labels, incomplete metadata, or policy violation (e.g., ticket resale restrictions in certain jurisdictions). Beta is paused until resolved. |
| **Mitigation** | (1) TestFlight and internal track don't require full review — lower risk for beta. (2) Ensure privacy manifest is complete before public launch. (3) Review Apple's guidelines on ticket resale apps before submitting to public App Store. (4) Keep an older passing build as fallback. |
| **Owner** | Lead Developer |

---

## Risk Summary Matrix

| # | Risk | Severity | Likelihood | Priority |
|---|------|----------|------------|----------|
| 1 | Orphaned payment | Critical | Possible | **P1** |
| 2 | Cron stops running | Critical | Possible | **P1** |
| 3 | Seller Connect not onboarded | High | Likely | **P1** |
| 4 | Duplicate webhook / double transfer | High | Possible | **P2** |
| 5 | Push notifications not delivered | Medium | Very Likely | **P2** |
| 6 | Refund fails on expired transfer | Critical | Unlikely | **P2** |
| 7 | Supabase outage | High | Unlikely | **P3** |
| 8 | Stripe key leak / rotation | Critical | Unlikely | **P3** |
| 9 | Real tickets sold during beta | High | Possible | **P2** |
| 10 | App Store rejection | Medium | Possible | **P3** |

---

*Review weekly during beta. Promote or demote risks as evidence accumulates.*
