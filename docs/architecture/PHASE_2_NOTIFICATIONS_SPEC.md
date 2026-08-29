# Phase 2 — Notifications & Event-Lifecycle Specification

**Status:** BUILD-READY DESIGN SPEC. **Design-only — no SQL, no migrations, no client code.** Illustrative
fragments inside this file are prose examples, never files to apply.
**Branch:** `design/feature-notifications` off `phase2/consolidation` @ `11ea2eb`.

**Binding inputs (authority order):**
1. `docs/architecture/SNATCH_IT_CANONICAL_DATA_MODEL.md` — §1.6 (`notify` context), §15 **C12** (event envelope,
   SSCAS), **C18** (versioned registry-governed vocabularies), §15 **C48/C49**.
2. `docs/architecture/SNATCH_IT_DOMAIN_ARCHITECTURE.md` — §0.5 **C7** (leaf-service eviction), §6.1 (business-event
   catalog), §6.2 (transactional spine), §6.3 (outbox → cron drainer).
3. `docs/architecture/_governance/PHASE_2_RATIFICATION_RECORD.md` — C28, C36, C48, C49.
4. `docs/architecture/PHASE_2_SPEC_FOUNDATION.md`, `PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md`,
   `PHASE_2_RLS_PERMISSION_SPEC.md`, `PHASE_2_RPC_FUNCTION_CONTRACTS.md`, `PHASE_2_EDGE_FUNCTION_SPEC.md`,
   `PHASE_2_REACT_NATIVE_PRODUCT_SPEC.md`, `PHASE_2_VENUE_DASHBOARD_PRODUCT_SPEC.md` §16.5 (**binding delegation
   to this spec**), `PHASE_2_SUPABASE_MIGRATION_PLAN.md`.
5. The **live production system** as traced in `supabase/migrations/`, `supabase/functions/`, `src/`, `app/`, `web/`.

**This spec EXTENDS the notification system that already runs in production. It does not replace it.** §1 states
exactly what is reused, what is extended, and what is new.

---

## §0 — How to read this document

### 0.1 Classification legend (every element carries one)

| Tag | Meaning |
|---|---|
| `NO SCHEMA CHANGE` | uses an object that exists today, unchanged |
| `ADDITIVE SCHEMA CHANGE` | new table/column/index/constraint; nothing dropped, nothing re-typed |
| `SPEC CORRECTION` | a frozen Phase-2 spec says something that is wrong or unbuildable as written |
| `NEW RPC` | a new `SECURITY DEFINER` Postgres function |
| `NEW EDGE FUNCTION` | a new Supabase Edge Function |
| `NEW RN SURFACE` | a new React Native screen/behaviour |
| `NEW DASHBOARD SURFACE` | a new `web/` venue-dashboard screen/behaviour |

### 0.2 Evidence convention

- **`VERIFIED:`** read directly from repository source at the cited `file:line` on this branch.
- **`INFERENCE:`** a design conclusion drawn from verified facts. Not observed; may be wrong.
- **`UNVERIFIED:`** asserted by another document and not independently confirmed here.
- **`CONFLICT-n:`** a ratified invariant and a requirement collide. **Reported, never silently resolved** —
  every one is repeated in §10 as an owner decision.

### 0.3 Two rules that govern every line below

1. **A notification may never abort the transaction that caused it.** Every existing producer already enforces
   this two ways: `enqueue_notification` never raises (`057_notifications_dedupe_and_enqueue_helper.sql:83-86`)
   and every trigger body wraps a second `EXCEPTION WHEN OTHERS` (`058_notification_producers.sql:95-97, 117-119,
   152-154, 230-232`). Phase 2 keeps both layers.
2. **Write the durable record first, attempt transports second.** Inverting this is the single biggest defect in
   the system today: the push-only paths (033/034/035) leave *no trace at all* when delivery fails silently (§1.5
   D-1).

---

## §1 — What exists today (traced) vs what Phase 2 adds

### 1.1 The headline: two parallel notification systems that share nothing

`VERIFIED.` Production runs **two independent notification systems with two disjoint address spaces**, and the
migrations say so in their own headers:

- **Push rail** — Postgres trigger → `pg_net` → Edge Function → Expo. Addressed by a `data.type` string plus
  `listingId`/`transferId`. Leaves **no durable row anywhere**.
- **Inbox rail** — Postgres trigger → `public.enqueue_notification()` → `public.notifications`. Addressed by a
  **web-relative path string** in `link`. Rendered **only by `web/`**; the mobile app cannot see it.

> "Push and inbox are separate channels with separate address spaces."
> — `058_notification_producers.sql:6` (repeated at `:56`)

`057_notifications_dedupe_and_enqueue_helper.sql:17-20` states the boundary explicitly: `link` must be a
**web-relative path** consumed by `safeInternalPath`, and *"Mobile routes off the push `data` payload instead —
a separate address space."*

**Nothing maps between them.** `VERIFIED`: the web inbox reads `link` (`web/src/components/account/
NotificationsList.tsx:80`); the mobile router reads only `data.type` / `data.listingId` / `data.transferId` /
`data.role` (`src/providers/NativeAppShell.native.tsx:228-230, 251`). There is no shared key, no shared vocabulary,
and no code path that writes both.

**Phase 2 unifies them behind one record with a structured target** (§4, §6). It does **not** delete either rail.

### 1.2 Storage inventory (`NO SCHEMA CHANGE` — all of this is reused)

| Object | Definition | Shape / posture |
|---|---|---|
| `public.notifications` | `040_web_accounts_foundation.sql:65-76` | `id · user_id → auth.users · type(≤50) · title(≤140) · body(≤1000) · link(≤2048) · metadata jsonb · read_at · created_at` |
| `public.notifications.dedupe_key` | `057_...:44-52` | added later; `≤200` chars; **partial UNIQUE index** `notifications_dedupe_key_uidx ... WHERE dedupe_key IS NOT NULL` |
| RLS / grants on it | `040:88-108` | `REVOKE ALL FROM PUBLIC, anon, authenticated` → `GRANT SELECT` + `GRANT UPDATE (read_at)` to `authenticated`; owner-select + owner-update-read-state policies; **no INSERT policy at all** |
| Indexes | `040:81-86` | `(user_id, created_at DESC)` and a partial `WHERE read_at IS NULL` |
| `public.enqueue_notification(uuid,text,text,text,text,text,jsonb)` | `057:66-88` | `SECURITY DEFINER`, `SET search_path TO 'public'`, **never raises**, `ON CONFLICT (dedupe_key) DO NOTHING`, `left(title,140)`/`left(body,1000)`; `REVOKE ... FROM PUBLIC, anon, authenticated` + `GRANT ... TO service_role` (`057:90-91`) |
| `public.notification_preferences` | `000_baseline_schema.sql:920-929` | 6 booleans, PK `user_id`; owner-manage RLS (`:935-938`); auto-created by `trg_new_user_notification_prefs` on `profiles` insert (`:941-959`) + one-time backfill (`:962-964`) |
| `public.push_tokens` | `000_baseline_schema.sql:879-888` | `id · user_id · token UNIQUE · platform('ios'\|'android') · device_name · created_at · last_used · is_active` + owner CRUD policies (`:902-916`) |
| `public.transfer_notifications` | `034_transfer_notifications.sql:25-37` | **the existing idempotency ledger.** `PRIMARY KEY (transfer_id, event_type)`; 6-value CHECK; RLS on, `REVOKE ALL`, service-role only (`:39-41`) |
| `public.auth_audit_sweep_state` | `0600_...:83-92` | watermark-sweep state: `sweep_name PK · floor_at · watermark · last_run_at · last_error · sent_count`; RLS on with **zero policies** |
| `public.rate_limits` + `check_rate_limit(uuid,text,int,int)` | `005_rate_limits.sql`, replaced by `021_rate_limits_fail_closed.sql:22-68` | **fail-CLOSED** (`021:60-64`), `service_role`-only EXECUTE |

### 1.3 Every notification type emitted today — the complete enumeration

#### (a) Durable inbox types — 12 (`public.notifications.type`)

`VERIFIED` at `058_notification_producers.sql` and `0600/0601`.

| # | `type` | Recipient | Dedupe key | `link` | Producer |
|---|---|---|---|---|---|
| 1 | `bid_received` | listing seller | `bid_received:<bid_id>` | `/listing/<id>` | `notify_bid_inbox()` `058:63-103` |
| 2 | `outbid` | previous high bidder (self-outbid skipped `058:87`) | `outbid:<new_bid_id>` | `/listing/<id>` | `058:88-93` |
| 3 | `auction_won` | `listings.winner_user_id` | `auction_won:<listing_id>` | `/checkout/<id>` | `notify_auction_won_inbox()` `058:106-126` |
| 4 | `listing_sold` | seller | `listing_sold:<transfer_id>` | `/transfer/send/<id>` | `notify_transfer_created_inbox()` `058:139-144` |
| 5 | `buyer_info_needed` | buyer | `buyer_info_needed:<transfer_id>` | `/transfer/receive/<id>` | `058:146-151` |
| 6 | `buyer_confirmation_needed` | buyer | `buyer_confirmation_needed:<transfer_id>` | `/transfer/receive/<id>` | `notify_transfer_state_inbox()` `058:171-178` |
| 7 | `transfer_viewed` | seller | `transfer_viewed:<transfer_id>` | `/transfer/send/<id>` | `058:180-187` |
| 8 | `transfer_confirmed` | seller | `transfer_confirmed:<transfer_id>` | `/transfer/send/<id>` | `058:189-196` |
| 9 | `transfer_disputed` | **seller AND buyer** (2 rows) | `transfer_disputed:<transfer_id>:seller` / `:buyer` | send / receive | `058:198-211` |
| 10 | `payout_released` | seller | `payout_released:<transfer_id>` | `/account/sales` | `058:216-222` |
| 11 | `order_complete` | buyer | `order_complete:<transfer_id>` | `/account/purchases` | `058:223-228` |
| 12 | `security_password_changed` | the account holder | `auth_pwd:<audit_log_entry_id>` | `/account/security` | `sweep_auth_password_changes()` `0600:140-155`, fixed `0601:52-65` |

Two design decisions worth carrying forward verbatim:
- **One seller row on sale, not two.** `058:129-130`: *"'listing sold' and 'seller action required' are the same
  instant; two rows a second apart reads as a bug."*
- **The payout predicate is `payout_released_at NULL → NOT NULL`, never `status`** (`058:213-215`), because the
  auto-release path never changes `status`. Phase 2 inherits this rule for `kernel.payout`.

#### (b) Push `data.type` values — 15 distinct (no durable row for any of them)

| `data.type` | `data` keys | Emitter | Routes to |
|---|---|---|---|
| `bid_received` | `listingId` | `notify-transfer/index.ts:102-107` | `/listing/…` (via the `listingId` fallback) |
| `seller_action` | `transferId` | `notify-transfer:139-144`; **reused** by the reminder sweep `enforce-transfer-expiry:864-869` | `/transfer/send/…` |
| `buyer_info_needed` | `transferId` | `notify-transfer:152-157` | `/transfer/receive/…` |
| `buyer_confirm` | `transferId` | `notify-transfer:162-167`; reused `enforce-transfer-expiry:884-889` | `/transfer/receive/…` |
| `payment_succeeded` | `listingId`, `transferId?` | `stripe-webhook:483-488` | `/transfer/receive/…` |
| `ticket_sold` | `listingId`, `transferId?` | `stripe-webhook:490-495` | `/transfer/send/…` |
| `transfer_expired_refund` | `listingId` | `enforce-transfer-expiry:310-315` | `/listing/…` |
| `transfer_expired_seller` | `listingId` | `enforce-transfer-expiry:318-323` | `/listing/…` |
| `auto_release_seller` | `listingId` | `enforce-transfer-expiry:707-712` | `/listing/…` |
| `auto_release_buyer` | `listingId` | `enforce-transfer-expiry:713-718` | `/listing/…` |
| `dispute_review` | `transferId`, `role` | `notify-report:170-172` | send/receive by `role` |
| `admin_report` | `reportId` | `notify-report:129-131` | **nothing — orphan** |
| `report_ack` | *(none)* | `notify-report:138-140` | **nothing — orphan** |
| `under_review` | *(none)* | `notify-report:149-151` | **nothing — orphan** |
| `admin_dispute` | `transferId` | `notify-report:161-163` | **nothing — orphan** (not in either whitelist) |

The router: `src/providers/NativeAppShell.native.tsx:239-257`. `SELLER_TRANSFER = ['seller_action','ticket_sold']`
(`:239`), `BUYER_TRANSFER = ['buyer_confirm','buyer_info_needed','payment_succeeded']` (`:242`), then
`dispute_review` by `role` (`:248`), then a bare `listingId` fallback. **There is no `else` branch** — an
unrecognised payload is silently dropped.

#### (c) Client-local notifications — 4 (never leave the device)

`src/utils/notifications.ts:10` (`scheduleNotificationAsync`, `trigger: null`), called only from
`src/screens/ListingDetailScreen.tsx`: `outbid` (`:521`), `auction_ending_soon` (`:635`, `:647`), `auction_won`
(`:692`), `auction_lost` (`:712`). **They fire only while that screen is mounted.**

#### (d) The claim vocabulary — 6 declared, 5 used

`public.transfer_notifications.event_type` CHECK (`034:27-34`): `seller_action_required` (claimed at
`notify-transfer:138`), `buyer_transfer_info_needed` (`:151`), `buyer_confirmation_needed` (`:161`),
`transfer_reminder_seller` (`enforce-transfer-expiry:863`), `transfer_reminder_buyer` (`:883`).
**`tickets_marked_sent` is a payload event name (`notify-transfer:159`), never a claim key** — the CHECK carries
one unused value.

### 1.4 Transport inventory

| Hop | Implementation | Auth |
|---|---|---|
| Trigger → edge | `pg_net` + `vault.decrypted_secrets` where `name='service_role_key'` — `034:68-84`, `035:20-41`, `033:209` | Vault JWT bearer |
| `notify-transfer` | `supabase/functions/notify-transfer/index.ts` | `INTERNAL_CRON_SECRET` **or** service-role, constant-time (`:70-80`) |
| `notify-report` | `supabase/functions/notify-report/index.ts` | same dual check (`:93-103`) |
| `send-push` | `supabase/functions/send-push/index.ts` | **service-role ONLY** (`:14-25`) — does *not* accept `INTERNAL_CRON_SECRET` |
| Expo | `EXPO_PUSH_URL` default `https://exp.host/--/api/v2/push/send` (`send-push:7`), single `fetch` (`:88`) | — |
| Email | `fetch('https://api.resend.com/emails')` — `notify-report:67` only | `RESEND_API_KEY`; gated by `EMAIL_ENABLED`, **default `'false'`** (`:31`) |
| Token read | `.from('push_tokens').select('token').eq('user_id',…).eq('is_active',true)` (`send-push:66-71`) | service-role |

**pg_cron jobs (4 defined, 3 live):**

| Job | Schedule | Command | Defined |
|---|---|---|---|
| `auto-finalize-auctions` | `*/2 * * * *` | `select public.auto_finalize_expired_auctions();` (SQL only) | `014_frequent_cron_schedules.sql:15-19` |
| `enforce-transfer-expiry` v1 | `*/2 * * * *` | `net.http_post(current_setting('app.settings.supabase_url')…)` — **GUCs never set, superseded** | `014:26-38` |
| `enforce-transfer-expiry` v2 | `*/2 * * * *` | `net.http_post('https://…/functions/v1/enforce-transfer-expiry')`, bearer from Vault | `032_pre_testflight_blocker_fixes.sql:97-117` |
| `sweep-auth-password-changes` | `*/5 * * * *` | `select public.sweep_auth_password_changes();` (SQL only) | scheduled by the converge block `075_replay_parity_storage_policies_and_cron.sql:355-389` |

**`notify-transfer`, `notify-report` and `send-push` are never cron-driven.** They are exclusively
trigger-driven. `VERIFIED.`

### 1.5 The watermark-sweep pattern (the model Phase 2 generalises)

`sweep_auth_password_changes()` — `0600_auth_password_change_notifications.sql:100-173`, corrected by
`0601_fix_sweep_query_destination.sql`. Five properties Phase 2 copies **verbatim**:

1. **`pg_try_advisory_xact_lock(hashtext(...))` with an early `RETURN`** (`0600:115-117`) — *"a slow run must never
   pile up behind itself."*
2. **A `floor_at` no-backfill barrier seeded to `now()` in the same statement that creates the row**
   (`0600:96-98`), with `v_lower := greatest(v_wm - c_lookback, v_floor)` (`:124`) — *"the first run cannot reach a
   historical row. No backfill, by construction."*
3. **A deliberate overlap window** (60 min, `:109`) because the source's `created_at` is an application clock, not
   commit time — a row stamped `T` can become visible later.
4. **Correctness does not depend on the lock.** `0600:27-29`: the dedupe key is the immutable source-row uuid, so
   *"the 60-minute overlap re-presents the same key every run and `notifications_dedupe_key_uidx` absorbs it."*
   **This is the single most important pattern in the existing system** and it is the answer to "what if the job
   runs twice" (§7.5 / Appendix A5).
5. **The watermark advances only on the success path** (`0600:159-169` success vs `:164-170` failure) — *"a failure
   retries the window rather than dropping events."*

Also load-bearing: `0600:9-20` documents a **refusal to ship** `email_changed` because every candidate
discriminator had a 100% false-positive rate — *"A false security alert is worse than none."* Phase 2 inherits
that standard for every `security_*` type.

### 1.6 Defects inherited (each is a Phase-2 requirement, not a bug report)

| # | Defect | Evidence | Phase-2 response |
|---|---|---|---|
| **D-1** | **`notification_preferences` is inert.** No sender anywhere reads it. `send-push` reads only `push_tokens` (`send-push:66-71`); `notify-transfer`/`notify-report` delegate to it. The 6 toggles in `app/settings/notifications.tsx:41-72` change nothing. | `VERIFIED` (repo-wide: the table is referenced only by `000_baseline_schema.sql:920-964` and the settings UI at `:103, :142`) | §3 — the resolver is consulted **inside the dispatcher**, and a pgTAP assertion proves no channel adapter can bypass it |
| **D-2** | **No Expo receipt polling, ever.** `send-push` never checks `pushRes.ok`, echoes Expo's body verbatim as a 200 (`:96-99`), and no code anywhere calls `getReceipts`. | `VERIFIED` | §4.6 — `notify-receipts` edge fn + `notify.delivery.provider_receipt_id` |
| **D-3** | **`push_tokens.is_active` is write-`true`-only.** Nothing in the repo ever writes `false`. The `.eq('is_active',true)` filter and `idx_push_tokens_active` are therefore no-ops; dead tokens accumulate forever. | `VERIFIED` (`src/hooks/usePushToken.ts:78, :85`) | §6.2 — `revoked_at` + `DeviceNotRegistered` reaping + logout revoke |
| **D-4** | **A device changing hands keeps the old owner's `user_id`.** `usePushToken.ts:71-86` selects by `token` (UNIQUE) and, on hit, updates only `last_used`/`is_active` — it never rebinds `user_id`. User A keeps receiving pushes on User B's phone. | `VERIFIED` | §6.4 `notify.register_push_token()` sets `user_id = auth.uid()` unconditionally |
| **D-5** | **`last_used` is NULL for every device until its second launch** — the insert branch (`:82-86`) omits it. | `VERIFIED` | folded into D-4's RPC |
| **D-6** | **No logout revocation.** Four sign-out call sites (`app/settings/index.tsx:122, :165`, `app/(tabs)/profile.tsx:275`, `src/hooks/useAuth.ts:62`) and none touches `push_tokens`. | `VERIFIED` | §6.4 `notify.revoke_push_token()` |
| **D-7** | **The outbid push path is dead code.** `notify_outbid()` calls `send-push` with `current_setting('app.settings.service_role_key')`, a GUC `054_fix_notify_outbid_aborts_bids.sql:12-16` documents as never set — and `send-push` accepts only the service-role key, not `INTERNAL_CRON_SECRET` (`send-push:14-25`), unlike its two siblings. | `VERIFIED` | §6.5 — every new internal edge accepts **both** secrets; asserted in CI |
| **D-8** | **`notify-report` has no idempotency table at all.** A re-fired moderation trigger re-sends everything. | `VERIFIED` | §4 — every hop keyed |
| **D-9** | **The notification path has zero Sentry coverage.** None of `notify-transfer`, `notify-report`, `send-push` imports `_shared/sentry.ts`. | `VERIFIED` | §4.7 |
| **D-10** | **No batching.** `send-push` POSTs one array per user, no 100-message chunking, no `Retry-After` handling, no backoff. | `VERIFIED` (`send-push:80-94`) | §4.6 |
| **D-11** | **Four copy-pasted `sendPush` helpers and five copy-pasted `constantTimeEqual` implementations**; three different `supabase-js` pins across functions; no `_shared/cors.ts`, no `_shared/auth.ts`, no shared client factory. | `VERIFIED` | §6.5 — `_shared/notify.ts`, `_shared/notify-auth.ts` |
| **D-12** | **The mobile app has no inbox.** No mobile file reads `public.notifications`; `shouldSetBadge: false` (`NativeAppShell.native.tsx:48`); no `addNotificationReceivedListener` anywhere; no unread count; no mark-as-read. **A push a mobile user swipes away is gone permanently.** | `VERIFIED` | §6.6 `NEW RN SURFACE` |
| **D-13** | **Four push types are unroutable orphans** (`admin_report`, `report_ack`, `under_review`, `admin_dispute`) — tapping them does nothing. | `VERIFIED` | §4.4 structured targets |
| **D-14** | **Custom scheme only.** `scheme: "snatchit"` (`app.json:8`); no `associatedDomains`, no `web/public/.well-known/`, so no AASA and no `assetlinks.json`. `NativeAppShell.native.tsx:158-165` documents that a co-installed app can claim the scheme. | `VERIFIED` | §4.4 invariant N-DL-4: **a notification link may never carry a secret, token, or one-time action** |
| **D-15** | **Cold-start taps on an unauthenticated launch are dropped.** `getLastNotificationResponseAsync()` (`:264-270`) routes through a `setTimeout(…,0)` (`:233-236`) with no session gate and no pending-intent store. | `VERIFIED` | §6.6 |
| **D-16** | **No transactional email capability.** Exactly one call site (`notify-report:67`), flag-gated off by default (`:31`), with a locally-defined helper and no SDK. `web/` sends none. Auth mail runs on a personal Gmail SMTP relay (`AGENTS.md`, "Known environment gotchas"). | `VERIFIED` | O-N3 — **email is an owner decision, not a design assumption** |
| **D-17** | **No localization of any kind.** No `expo-localization`, `i18n-js`, `react-i18next`, `next-intl`, `react-intl`; no `locales/`; not even `Intl.NumberFormat`. Every string is a hardcoded English literal; `timeAgo` is hand-rolled (`web/src/components/account/NotificationsList.tsx:13-22`). | `VERIFIED` | §5 — DB structure must not assume any client library |
| **D-18** | **`notify-report`'s trigger→function auth is unproven in production.** `docs/security/NOTIFICATION_SYSTEM_AUDIT.md` finding N1: the Vault JWT is 219 chars while runtime `SUPABASE_SERVICE_ROLE_KEY` may be the 41-char secret-format key; zero rows in `net._http_response` for the function at audit time. | `UNVERIFIED` (audit dated 2026-06-12; not re-tested here — **no production access used**) | §4.7 — dispatch must record a delivery outcome, so a 401 becomes visible instead of silent |

### 1.7 Reuse / extend / new — the explicit ledger

**REUSED UNCHANGED (`NO SCHEMA CHANGE`)**
`public.notifications` and its RLS/grant posture (`040:88-108`) · `public.enqueue_notification` for the 12 legacy
types · `public.transfer_notifications` for the external rail · `public.rate_limits` + `check_rate_limit`
(fail-closed) · the `pg_net`+Vault trigger transport · the `pg_cron` heartbeat · `send-push` (kept for the legacy
push types; **not extended**) · `safeInternalPath` (`web/src/lib/auth/redirect.ts:9-21`) as defence-in-depth ·
the `AFTER`-trigger + double-`EXCEPTION` non-raising discipline · the `webhook_retries`/claim-lease pattern
(`064`, `069`).

**EXTENDED (`ADDITIVE SCHEMA CHANGE`)**
`public.push_tokens` gains `revoked_at`, `revoked_reason`, `provider_receipt_checked_at`, `last_provider_error`
(§6.2) · the watermark-sweep pattern generalises from one hard-coded sweep to a `notify.schedule` table (§4.5) ·
the dedupe-key mechanism generalises from one partial unique index to a three-layer keyed pipeline (§4.2).

**NEW**
The `notify` schema (9 tables) · a type registry (C18) · a resolved preference model with a **DDL-enforced**
mandatory class · the C12 event envelope as a physical outbox · per-channel delivery rows with retry and
dead-letter · a template/localization structure · organizer announcements with abuse controls · a mobile
notification centre · a venue-staff notification surface · 40 Phase-2 type keys (§2).

### 1.8 Conflicts found — reported, not resolved

**`CONFLICT-1` — the `notify` schema's gate. BLOCKING.**
- **C7 is `RATIFIED · Gate P · MVP`** and states leaf services *"(notifications, push_tokens, reports,
  risk_scores) are **evicted** from the kernel into their own schema"*
  (`SNATCH_IT_DOMAIN_ARCHITECTURE.md:79`; index row `:2722`; CDM header `:9` names `notify` among the C7 contexts;
  CDM §1.6 `:252` defines the Notification object as `notify`).
- **All four Phase-2 implementation specs defer `notify` to Gate L / DO-NOT-BUILD:**
  `PHASE_2_SPEC_FOUNDATION.md:17` · `PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md:1461-1462` (§11 Gate L) ·
  `PHASE_2_RLS_PERMISSION_SPEC.md:21` ("out of scope") · `PHASE_2_SUPABASE_MIGRATION_PLAN.md:199, 857`
  ("documented extension points, NOT scheduled").
- **Two readings, both defensible.** (a) C7's eviction is already satisfied *vacuously* — the leaves live in
  `public.*` and were never in the kernel, so nothing must move at Gate P. (b) C7 names `notify` as an MVP context
  and the specs contradict it.
- **`INFERENCE`:** reading (a) is what the spec authors intended. But it does not dispose of `CONFLICT-2`.

**`CONFLICT-2` — the outbox. BLOCKING.**
`SNATCH_IT_DOMAIN_ARCHITECTURE.md:1253` states the anti-over-engineering guarantee as
*"the only new infrastructure Phase 2 introduces is **one outbox table and a drainer on the cron that already
runs**"*, and §6.1 classifies **every notification as Async/outbox** (`:1164`, `:1240`).
**No Phase-2 spec defines an outbox table.** A full-text search of `PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md`
finds "outbox" exactly once — at `:1474`, inside the **Gate-L** deferral list. The migration plan's 43-object
inventory contains no outbox. So the one piece of infrastructure the constitution promises Phase 2 would build is
the one piece no implementation spec schedules.

**`CONFLICT-3` — migration numbering. `SPEC CORRECTION`.**
Three specs disagree with each other *and* with the repository:
`PHASE_2_SPEC_FOUNDATION.md:27` says begin at **071** · `PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md:129` says
**071** · `PHASE_2_SUPABASE_MIGRATION_PLAN.md:90` says **073**. On this branch `071`, `072`, `073`, `074` and
`075` are all **applied production migrations** (`071_fix_guard_proof_status.sql` …
`075_replay_parity_storage_policies_and_cron.sql`). Per the plan's own rule
(`PHASE_2_SUPABASE_MIGRATION_PLAN.md:102`) an applied `071+` migration may never be renumbered.
**Phase 2 must begin at `076`.** The plan's internal package map is also inconsistent with itself: §1 assigns
Phase K to `087` (`:199`) while §5's header is `088_kernel_reserve_stub` with a `087_*` rollback (`:830, :840`).

**`CONFLICT-4` — role vocabulary. Non-blocking; treated as pending per this agent's brief.**
The owner-ratified O-2 role set (`org_owner · org_admin · org_finance · venue_manager · box_office · marketing ·
promoter_manager · scanner`) and the ratified C36 enums (`PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md:86-88`:
org = `org_owner|org_admin|org_finance|org_member`; venue = `venue_manager|venue_finance|venue_door|venue_promoter`;
platform = `platform_admin|platform_support|platform_risk`) **share only `org_owner`, `org_admin`, `org_finance`
and `venue_manager`.** `box_office`, `marketing`, `promoter_manager` and `scanner` have no enum label; `org_member`,
`venue_finance`, `venue_door` and `venue_promoter` have no O-2 concept. This spec authorises against **role
concepts** and gives the mapping in §2.4; the concrete enum labels are the other agent's deliverable.

**`CONFLICT-5` — org-role inheritance for money notices.** Already flagged by the venue-dashboard spec
(`PHASE_2_VENUE_DASHBOARD_PRODUCT_SPEC.md:1158-1159`): C36 makes `kernel.org_member.role` single-valued, so an
`org_owner` row does **not** satisfy `has_org_role([org_finance])`. §16.5 (`:938`) nonetheless requires payout
failure to reach *"finance **and** owner"*. Recipient derivation for `staff_payout_failed` must therefore be an
explicit **role-set union** (`[org_finance, org_owner]`), never inheritance. §2.3 does this; the underlying
authority question stays open.

---

## §2 — Notification-type catalogue

### 2.1 Reading the catalogue

- **Type key** — the immutable registry key (`notify.notification_type.type_key`). Governed by **C18**: new values
  are added by a registry migration, never by overloading an existing key.
- **Trigger event** — the `SNATCH_IT_DOMAIN_ARCHITECTURE.md` §6.1 business event (by number) that produces it, or
  the sweep that does.
- **Ch.** — `I` in-app centre (always present, never suppressible) · `P` push · `E` email.
  Lower-case = default off for that channel. **Every `E` is conditional on O-N3**; until email exists those rows
  dispatch `I`+`P` and leave the `E` delivery row `suppressed`, reason `channel_unavailable`.
- **Class** — `MANDATORY` (structurally undisableable, §3.3) · `ON` (default on, user-disableable) ·
  `OFF` (default off, user-enableable).
- **Dedupe key** — the value of `notify.notification.dedupe_key`. **This is the user-visible idempotency
  boundary** (§4.2). `:<role>` suffixes follow the existing precedent `transfer_disputed:<id>:seller|buyer`
  (`058_notification_producers.sql:203, :209`).
- **Target** — `notify.notification.target_kind`; the client resolves it to a route. **Never a URL** (§4.4).

Every row is an `ADDITIVE SCHEMA CHANGE` (a registry row), except the four marked *extends*, which are
`NO SCHEMA CHANGE` on the type key itself.

### 2.2 The catalogue — 40 Phase-2 types

#### Group P — Purchase (4)

| Key | Trigger event | Ch. | Class | Dedupe key | Target | Params | Recipient derivation | Authority to emit |
|---|---|---|---|---|---|---|---|---|
| `purchase_confirmed` | #9 PaymentCaptured (native primary) | I P E | **MANDATORY** | `purchase_confirmed:<order_id>` | `order` | `order_id, event_title, venue_name, session_start_at, qty, total_minor, currency` | `venue.order.buyer_id` | kernel, inside issuance SSCAS member #1 |
| `ticket_ready` | #10 TicketIssued | I P | **MANDATORY** | `ticket_ready:<order_id>` | `order` (multi) / `ticket` (single) | `order_id, ticket_count, event_title` | order buyer | kernel, same tx as issuance |
| `wallet_pass_available` | first successful `credential-sign` for an atom | I p | ON | `wallet_pass:<ticket_id>:<credential_version>` | `ticket_pass` | `ticket_id, credential_version, event_title` | `kernel.tickets.current_owner` | `credential-sign` edge fn |
| `purchase_failed` *(beyond the brief — the honest counterpart)* | `payment_intent.payment_failed` | I P | **MANDATORY** | `purchase_failed:<order_id>:<attempt_no>` | `order` | `order_id, reason_code, retryable` | order buyer | `stripe-webhook` |

`INFERENCE:` `wallet_pass_available` is `ON` not `MANDATORY` because the pass is always reachable from the ticket;
suppressing the ping costs the user nothing they cannot recover in one tap.

#### Group T — Transfer (6) — native Rail A (`market.p2p_transfer`)

| Key | Trigger event | Ch. | Class | Dedupe key | Target | Params | Recipient derivation | Authority to emit |
|---|---|---|---|---|---|---|---|---|
| `transfer_sent` | #18 TransferStarted | I p | ON | `transfer_sent:<p2p_transfer_id>` | `p2p_transfer_out` | `transfer_id, event_title, recipient_display_name, expires_at` | `market.p2p_transfer.from_identity` | `market.create_p2p_transfer` (SSCAS #7) |
| `transfer_received` | #18 TransferStarted | I P E | **MANDATORY** | `transfer_received:<p2p_transfer_id>` | `p2p_transfer_in` | `transfer_id, event_title, venue_name, session_start_at, sender_display_name, expires_at` | `market.p2p_transfer.to_identity` | same RPC |
| `transfer_accepted` | #19 TransferAccepted | I P | **MANDATORY** | `transfer_accepted:<p2p_transfer_id>:sender` | `ticket` *(sender no longer holds it → fail-safe state, §4.4)* | `transfer_id, event_title, recipient_display_name` | sender | `market.accept_p2p_transfer` (SSCAS #8) |
| `transfer_declined` | p2p → `declined` | I p | ON | `transfer_declined:<p2p_transfer_id>` | `ticket` | `transfer_id, event_title` — **no reason text** | sender | `market.decline_p2p_transfer` |
| `transfer_cancelled` | p2p → `cancelled` | I p | ON | `transfer_cancelled:<p2p_transfer_id>:recipient` | `none` | `transfer_id, event_title` | recipient | `market.cancel_p2p_transfer` |
| `transfer_expired` | #20 TransferExpired (TTL sweep, C43) | I P | ON | `transfer_expired:<p2p_transfer_id>:<sender\|recipient>` | `ticket` / `none` | `transfer_id, event_title` | **both** parties, 2 rows | `market.sweep_expired_p2p_transfers` (RPC §12.2) |

`transfer_received` is MANDATORY: it is the only signal that an asset has been put in the recipient's name with an
expiry clock running — missing it costs them the ticket. `transfer_accepted` is MANDATORY because it is a
**custody-loss** notice for the sender, the exact mirror of a `security_*` event.

#### Group R — Resale & payout (8)

| Key | Trigger event | Ch. | Class | Dedupe key | Target | Params | Recipient derivation | Authority to emit |
|---|---|---|---|---|---|---|---|---|
| `listing_created` | #12 ListingCreated (native) | I | OFF | `listing_created:<listing_native_id>` | `listing_native` | `listing_id, event_title, ask_minor, currency` | `market.listing_native.seller_id` | `market.create_listing_native` (SSCAS #6) |
| `listing_bid_received` *(extends legacy `bid_received`)* | #13 BidPlaced | I P | ON | `bid_received:<bid_id>` | `listing_native` | `listing_id, bid_id, amount_minor, currency` | seller; **skip self-bid** | native auction engine |
| `listing_outbid` *(extends legacy `outbid`)* | #13 BidPlaced | I P | ON | `outbid:<new_bid_id>` | `listing_native` | `listing_id, bid_id, current_minor` | previous high bidder; **skip self-outbid** (the `058:87` rule) | native auction engine |
| `listing_sold` *(extends legacy)* | #15/#16 AuctionWon / ListingSold | I P E | **MANDATORY** | `listing_sold:<market_sale_id>` | `listing_native` | `sale_id, listing_id, event_title, gross_minor, net_minor, currency` | seller | native-sale SSCAS member #2 |
| `ownership_changed` | #17 OwnershipTransferred | I P | **MANDATORY** | `ownership_changed:<ownership_log_id>` | `ticket` | `ticket_id, event_title, direction ∈ {acquired, released}, cause_label` | the losing owner and the gaining owner — 2 rows, distinct `ownership_log_id`s | `kernel.transfer_ticket_ownership` (the single custody writer) |
| `payout_released` *(extends legacy)* | #25 PayoutReleased | I P E | **MANDATORY** | `payout_released:<payout_id>` | `payout` | `payout_id, amount_minor, currency, destination_last4, expected_arrival` | `kernel.payout.payee_identity` | `payout-execute` → `kernel.release_payout` |
| `payout_failed` | #26 PayoutFailed | I P E | **MANDATORY** | `payout_failed:<payout_id>:<attempt>` | `payout` | `payout_id, amount_minor, currency, failure_class, action_required` | payee, **and** for org payouts the `[org_finance, org_owner]` union (`CONFLICT-5`) | `payout-execute` failure path |
| `payout_on_hold` | #29 DisputeOpened → payout freeze (SSCAS #9) | I P | **MANDATORY** | `payout_on_hold:<payout_id>:<hold_cause_ref>` *(re-keyed + re-triggered 2026-08-29, N3: the Control-4 probation hold has NO dispute — `hold_cause_ref` is the dispute id on the #29 arm and the probation `hold_reason_code`-bearing audit ref on the risk arm; trigger set = #29 DisputeOpened OR the probation-hold write)* | `payout` | `payout_id, reason_class, dispute_id` | payee | dispute-freeze RPC |

`INFERENCE:` `ownership_changed` keys on `ownership_log_id`, not `ticket_id`. That is deliberate — **C26** makes
`UNIQUE(cause, cause_ref, ticket_atom_id)` the log's own idempotency key, so one log row is exactly one custody
fact, and keying the notification to it inherits C26's double-transfer-impossible proof for free.

The legacy inbox rule that the payout predicate is **`payout_released_at NULL → NOT NULL`, never `status`**
(`058:213-215`, because the auto-release path never changes `status`) carries forward unchanged to
`kernel.payout`: use the one column that transitions exactly once on both release paths.

#### Group E — Event lifecycle (7)

| Key | Trigger event | Ch. | Class | Dedupe key | Target | Params | Recipient derivation | Authority to emit |
|---|---|---|---|---|---|---|---|---|
| `event_reminder_24h` | scheduled fan-out (§4.5) | I P | ON | `event_reminder_24h:<event_session_id>:<ticket_id>` | `ticket` | `ticket_id, event_title, venue_name, session_start_at, door_open_at` | current holder of each `active` atom for the session, **at expansion time** | `notify.sweep_scheduled()` |
| `event_door_open` | scheduled fan-out at `door_open_at` | I P | ON | `event_door_open:<event_session_id>:<ticket_id>` | `ticket_pass` | `ticket_id, door_open_at, venue_name` | same | `notify.sweep_scheduled()` |
| `event_time_changed` | `catalog.event_session.starts_at` / `door_open_at` change | I P E | **MANDATORY** | `event_time_changed:<event_session_id>:<session_version>:<ticket_id>` | `event_session` | `session_id, old_start_at, new_start_at, old_door_at, new_door_at` | same | `catalog.update_event_session` |
| `event_venue_changed` | `catalog.event_session` venue change | I P E | **MANDATORY** | `event_venue_changed:<event_session_id>:<session_version>:<ticket_id>` | `event_session` | `session_id, old_venue_name, new_venue_name, new_address` | same | `catalog.update_event_session` |
| `event_cancelled` | SSCAS #10 event-cancellation cascade | I P E | **MANDATORY** | `event_cancelled:<event_session_id>:<ticket_id>` | `event_session` | `session_id, event_title, refund_expected, refund_eta_note` | holder of each atom voided by the cascade | `catalog.cancel_event` |
| `event_postponed` | session status → postponed with a new date | I P E | **MANDATORY** | `event_postponed:<event_session_id>:<session_version>:<ticket_id>` | `event_session` | `session_id, old_start_at, new_start_at, tickets_remain_valid` | same | `catalog.update_event_session` |
| `organizer_announcement` | `notify.announcement` released (§7) | I P | ON | `announcement:<announcement_id>:<ticket_id>` | `announcement` | `announcement_id, venue_name, organizer_body` | holders of `active` atoms for `subject_id`, at expansion time | `notify.approve_announcement` — **never** a raw insert |

**`session_version`.** A monotonic counter bumped by `catalog.update_event_session`.
`INFERENCE / delta:` `catalog.event_session` carries no such column
(`PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md:627-653`). **Without it a venue that moves the door time twice cannot
notify twice** — the second change collides with the first row's dedupe key and is silently swallowed by
`ON CONFLICT DO NOTHING`. That is a correctness requirement, not a nicety. See §6.1 Δ-N1.

`organizer_announcement` is `ON`, not MANDATORY, precisely because §7 shows this channel is attacker-reachable —
so it must be one the user can switch off. Time / venue / cancellation changes are **separate, MANDATORY,
platform-authored** types, so that a venue can neither smuggle an operational notice through the free-text path
nor have one silenced by a user's announcement opt-out.

#### Group F — Refund (4)

| Key | Trigger event | Ch. | Class | Dedupe key | Target | Params | Recipient derivation | Authority to emit |
|---|---|---|---|---|---|---|---|---|
| `refund_requested` | refund intent recorded | I P E | **MANDATORY** | `refund_requested:<request_id>` *(re-keyed 2026-08-29, N3: the parked/pending tiers write NO `kernel.refund` row — R7: request objects never write money rows — so a `refund_id` key cannot emit on the request path; the key is the `kernel.approval_request` id)* | `refund` | `refund_id, order_id, amount_minor, currency, reason_class` | the payer (`venue.order.buyer_id` / `public.payments.buyer_id`) | `kernel.refund_primary_order` · `admin_refund` · `catalog.cancel_event` |
| `refund_submitted` *(SPLIT 2026-08-29, N3 — this row's former name `refund_approved` covered two different facts, two recipients, two producers)* | refund submitted to Stripe (`refund-execute`, payer) | I p E | **MANDATORY** | `refund_approved:<refund_id>` | `refund` | `refund_id, amount_minor, currency, expected_days` | payer | `refund-execute` edge fn |
| `refund_request_approved` *(NEW 2026-08-29, N3 split)* | refund request GRANTED (RPC `approve_refund_request`; both parties) | I P E | **MANDATORY** | `refund_request_approved:<request_id>` | `refund` | `request_id, order_id, amount_minor` |
| `refund_request_parked` *(NEW 2026-08-29, N3 orphan #1)* | refund request parked for dual control | I P | **MANDATORY** | `refund_request_parked:<request_id>` | `refund` | `request_id, org_id` — **recipients: the org approver set** (Group F's other rows address the payer; this one addresses the approvers, §2.4 form 3) |
| `refund_request_denied` *(NEW 2026-08-29, N3 orphan #2)* | refund request denied | I P E | **MANDATORY** | `refund_request_denied:<request_id>` | `refund` | `request_id, reason_code` — both parties |
| `refund_request_expired` *(NEW 2026-08-29, N3 orphan #3)* | refund request expired unactioned | I P | **MANDATORY** | `refund_request_expired:<request_id>` | `refund` | `request_id` — both parties (the producer sweep is contracted "not optional" and "emits a notification" — this is its key) |
| `refund_request_cancelled` *(NEW 2026-08-29, `OR-15` — the N3 ninth)* | refund request/hold cancelled or reverted | I P E | **MANDATORY** | `refund_request_cancelled:<request_id>` | `refund` | `request_id, reason_code` — the buyer (payer); producer `kernel.cancel_refund_request` (§17.3), best-effort class (`OR-14`) |
| `payout_request_pending_approval` *(NEW 2026-08-29, N3 orphan #4)* | payout parked for dual control | I P | **MANDATORY** | `payout_request_pending_approval:<request_id>` | `payout` | `request_id, org_id` — **the org approver set** ("a payout parked for dual control sits in a queue nobody is told about") |
| `refund_completed` | #27 RefundIssued (`charge.refunded` / `refund.updated → succeeded`) | I P E | **MANDATORY** | `refund_completed:<refund_id>` | `refund` | `refund_id, amount_minor, currency, destination_last4` | payer | `stripe-webhook`, under the 064 event lease |
| `refund_failed` | refund failed / requires review | I P E | **MANDATORY** | `refund_failed:<refund_id>:<attempt>` | `refund` | `refund_id, amount_minor, failure_class, next_step` | payer **and** `[org_finance, org_owner]` of the funding org | `refund-execute` failure path / webhook |

**Every refund type is MANDATORY.** These are notices about the user's own money returning to them; there is no
product argument for a switch that disables them and no user who genuinely wants one. §3.3 makes that structural
rather than a default.

Dedupe keys are the **kernel refund id**, never `stripe_refund_id` — so a Stripe-side retry (which reuses the
Stripe id) and a kernel-side replay collapse onto the same notification row. See Appendix A3.

#### Group S — Security (5)

| Key | Trigger event | Ch. | Class | Dedupe key | Target | Params | Recipient derivation | Authority to emit |
|---|---|---|---|---|---|---|---|---|
| `security_password_changed` *(EXISTS — `NO SCHEMA CHANGE`)* | `auth.audit_log_entries` action `user_updated_password` | I P E | **MANDATORY** | `auth_pwd:<audit_id>` *(unchanged)* | `account_security` | `occurred_at` | the actor, inner-joined to `auth.users`, excluding the zero-uuid actor and deleted/anonymous users (`0600:136-155`) | `sweep_auth_password_changes()` |
| `security_payout_destination_changed` | Connect external-account change / `payout_destination_locked_until` set | I P E | **MANDATORY** | `security_payout_dest:<org_id\|identity_id>:<change_id>` | `account_security` | `destination_last4, locked_until, actor_display_name` | the account holder; for an org, `[org_owner, org_finance]` | `connect-onboarding` + the `account.updated` webhook branch |
| `security_org_role_granted` | grant on `kernel.org_member` / `venue.staff_role` | I P E | **MANDATORY** | `security_role_grant:<grant_audit_id>` | `account_security` | `scope_kind, scope_name, role_label, actor_display_name` | **the subject of the grant** and `[org_owner]` | `kernel.grant_org_role` / `venue.grant_staff_role` |
| `security_org_role_revoked` | revoke | I P E | **MANDATORY** | `security_role_revoke:<revoke_audit_id>` | `account_security` | same | same | same |
| `security_payout_method_added` | a new payout destination is attached | I P E | **MANDATORY** | `security_payout_method:<method_ref_hash>` | `account_security` | `method_last4, actor_display_name` | account holder / `[org_owner, org_finance]` | `connect-onboarding` |

**Only *sensitive* role changes notify** — grants/revocations of roles carrying money authority (`org_owner`,
`org_admin`, `org_finance`, `venue_manager`) or custody authority (door / scanner). Adding someone to a
`marketing` concept is not a security event, and notifying it would train users to ignore the ones that are.
`INFERENCE:` the sensitivity flag belongs on the role registry, which is the O-2/O-4 agent's deliverable
(`CONFLICT-4`); this spec assumes a boolean `is_sensitive` per role label and does not define it.

**`security_email_changed` is deliberately NOT specified**, inheriting `0600:9-20` verbatim: no reliable
discriminator exists in `auth.audit_log_entries`, all three production `user_modified` rows were something else,
and *"a false 'your email was changed' security alert is worse than none."* The sound future path named there —
a `sha256(auth.users.email)` mirror sweep — is recorded as O-N13, not designed here.

#### Group M — Promoter / attribution (2)

| Key | Trigger event | Ch. | Class | Dedupe key | Target | Params | Recipient derivation | Authority to emit |
|---|---|---|---|---|---|---|---|---|
| `promoter_attribution_recorded` | #31 AttributionRecorded | I | OFF | `attribution:<order_id>:<promoter_link_id>` | `none` | `promoter_link_id, order_ref_short, commission_minor, currency` | the promoter identity behind `venue.promoter_link` | `venue.record_attribution`, same tx as OrderPaid |
| `promoter_commission_accrued` | #32 PromoterCommissionAccrued | I p E | ON | `commission:<attribution_id>` | `payout` | `attribution_id, commission_minor, currency, payout_id?` | same | kernel commission accrual |

`OFF` for per-order attribution is deliberate: a working promoter generates hundreds of these, and default-on
per-order pings are a self-inflicted spam incident. The right long-term shape is a digest, matching the staff
sales rule (`PHASE_2_VENUE_DASHBOARD_PRODUCT_SPEC.md:936`) — recorded as O-N14.

#### Group V — Venue staff (4) — **binding delegation from `PHASE_2_VENUE_DASHBOARD_PRODUCT_SPEC.md` §16.5**

| Key | Trigger event | Ch. | Class | Dedupe key | Target | Params | Recipient derivation | Authority to emit |
|---|---|---|---|---|---|---|---|---|
| `staff_low_inventory` | `venue.inventory_batch.remaining` crosses a configured threshold | I P | ON | `low_inventory:<batch_id>:<threshold>` | `event_session` | `batch_id, ticket_type_name, threshold, remaining, session_id` | `[venue_manager]` of the owning venue + `[org_owner, org_admin]` | `venue` reserve/issue RPCs, post-commit |
| `staff_sales_digest` | daily digest window closes | I p E | ON | `sales_digest:<venue_id>:<local_date>` | `event_session` | `venue_id, date, gross_minor, currency, tickets_sold, top_event` | `[venue_manager]`, `[org_owner, org_admin, org_finance]` | `notify.sweep_scheduled()` |
| `staff_payout_failed` | #26 PayoutFailed on an org payout | I P E | **MANDATORY** | `staff_payout_failed:<payout_id>:<attempt>` | `payout` | `payout_id, amount_minor, currency, failure_class, action_required` | **union** `[org_finance] ∪ [org_owner]` (`CONFLICT-5`) | `payout-execute` failure path |
| `staff_door_anomaly` | anomalous `venue.scan.result` rate **while a session is live** | I P | ON | `door_anomaly:<event_session_id>:<anomaly_window_start>` | `event_session` | `session_id, anomaly_class, count, window_minutes` | on-duty door staff for that session, **only while live** | `venue` scan path / live-window sweep |

These are **exactly** the four emitters the dashboard spec anticipated (`:1152`), honouring all four of its binding
rules: low-inventory fires **once per `(batch, threshold)`** so the banner and the alert can never disagree
(`:334`, `:937`); sales arrive as **one daily digest, never per sale** (`:936`); payout failure is
**non-opt-out** and reaches finance *and* owner (`:938`; it also pins undismissibly on the dashboard, `:337`);
door anomaly reaches on-duty door staff **only while a session is live** (`:939`).

MVP ships **one global preference per user, not per `(user, venue)`** — the dashboard copy already commits to
saying so (`:935`). `NEW DASHBOARD SURFACE`.

### 2.3 Class totals

| Class | Count | Types |
|---|---|---|
| **MANDATORY** | **24** | P: `purchase_confirmed`, `ticket_ready`, `purchase_failed` · T: `transfer_received`, `transfer_accepted` · R: `listing_sold`, `ownership_changed`, `payout_released`, `payout_failed`, `payout_on_hold` · E: `event_time_changed`, `event_venue_changed`, `event_cancelled`, `event_postponed` · F: all 4 · S: all 5 · V: `staff_payout_failed` |
| `ON` | 14 | `wallet_pass_available`, `transfer_sent`, `transfer_declined`, `transfer_cancelled`, `transfer_expired`, `listing_bid_received`, `listing_outbid`, `event_reminder_24h`, `event_door_open`, `organizer_announcement`, `promoter_commission_accrued`, `staff_low_inventory`, `staff_sales_digest`, `staff_door_anomaly` |
| `OFF` | 2 | `listing_created`, `promoter_attribution_recorded` |
| **Total new** | **40** | |

**Registry total after Phase 2: 40 new + 12 legacy inbox (§1.3a) + 15 legacy push (§1.3b) = 67 rows.**

### 2.4 Recipient derivation — the four legal forms, and the one that is illegal

Every recipient set above is produced by exactly one of these. **No other form is permitted.**

1. **Row-column** — a uuid column on the causing row (`venue.order.buyer_id`, `kernel.payout.payee_identity`,
   `market.p2p_transfer.to_identity`). Single recipient. Cheapest and safest; used wherever possible.
2. **Custody expansion** — `SELECT current_owner FROM kernel.tickets WHERE event_session_id = $1 AND state =
   'active'`, keyed per-ticket where the notice is per-ticket, deduplicated by owner where it is per-person. Used
   by every Group-E type. **Evaluated at expansion time, never at schedule time** — a ticket transferred away
   between scheduling and firing notifies the *new* holder, which is the only correct answer.
3. **Scope-role union** — `kernel.has_org_role(org_id, ARRAY[...])` / `kernel.has_venue_role(venue_id, ARRAY[...])`.
   Always an explicit array **union**, never inheritance (`CONFLICT-5`). Fail-closed: an unresolvable scope yields
   the empty set plus a `notify.outbox.last_error`, never a broadcast.
4. **Self** — `auth.uid()` of the actor, for `security_*`.

**Illegal:** a recipient list as an RPC parameter · a recipient list inside an outbox payload · any `SELECT` over
`auth.users` not constrained by one of the four forms. Asserted in §9 (N-A12).

### 2.5 Authority to emit — role concepts → predicates

`CONFLICT-4` is live; this table binds **concepts**. The enum labels belong to the O-2/O-4 agent.

| Concept (O-2) | Nearest ratified C36 label | May emit |
|---|---|---|
| `org_owner` | `org_owner` | approve announcements; all org staff types |
| `org_admin` | `org_admin` | approve announcements; all org staff types |
| `org_finance` | `org_finance` | **nothing** — receives money types, emits none |
| `venue_manager` | `venue_manager` | draft **and** approve announcements for its own venue |
| `box_office` | *(no label)* | none |
| `marketing` | *(no label)* | **draft announcements only** — never approve, never release (§7.3) |
| `promoter_manager` | *(no label)* | none |
| `scanner` | `venue_door` *(nearest)* | none |
| platform | `platform_admin` / `platform_support` | correction announcements; the global circuit breaker |
| machine | `service_role` | every system-produced type, via `SECURITY DEFINER` RPCs only |

**`marketing` has no custody or money authority (O-2), and an announcement reaches people *because of what they
hold* — it is custody-derived.** Marketing may therefore compose but may not release. §7.3.

### 2.6 Legacy types — retained, not migrated

The 12 legacy inbox types and 15 legacy push types keep working exactly as they do today. They are **registered**
in `notify.notification_type` with `legacy = true` so the preference surface can render them, but their producers
are untouched and they keep writing `public.notifications` through `public.enqueue_notification`.
`NO SCHEMA CHANGE`. Whether they are ever back-filled into `notify.notification` is **O-N10**.

---

## §3 — Preference model and the mandatory class

### 3.1 Why the current model cannot be extended

`public.notification_preferences` is **six boolean columns** (`000_baseline_schema.sql:920-929`). Three
consequences, all `VERIFIED`:

1. **Every new type costs a migration and a client release.** `PrefKey` on the client is
   `keyof Omit<NotificationPreferences,'user_id'|'updated_at'>` (`src/types/index.ts:174-183`,
   `app/settings/notifications.tsx:39`), so a 7th column changes a generated type and requires an explicit
   `TOGGLES` entry to render. 40 new types would mean 40 columns.
2. **There is no channel dimension.** A user who wants email but not push cannot express it.
3. **Nothing reads it (D-1).** The toggles are inert.

And structurally: a boolean column cannot express "this one may not be turned off." A default of `true` is not
enforcement — one `UPDATE` disables it.

### 3.2 The Phase-2 model — registry + sparse override + a resolver

`ADDITIVE SCHEMA CHANGE`. Three objects, one function.

**`notify.notification_type`** — the C18 registry. One row per type key.
`type_key PK · delivery_class ∈ ('mandatory','default_on','default_off') · allowed_channels text[] ·
default_channels text[] · target_kind · template_key · mandatory_reason text · legacy bool · active bool ·
registry_version int`.
Constraint that makes §3.3 possible: **`UNIQUE (type_key, delivery_class)`**.

**`notify.preference`** — a **sparse override** table. Absence means "the registry default."
`identity_id → auth.users · type_key · channel ∈ ('push','email') · enabled bool · delivery_class (denormalised) ·
updated_at`, `PRIMARY KEY (identity_id, type_key, channel)`.

**`notify.identity_channel_state`** — transport facts, not preferences.
`identity_id · channel · state ∈ ('ok','bounced','complained','unreachable') · since · reason`. An email hard
bounce or a spam complaint lands here. **This is not an opt-out** — see §3.5.

**`notify.channel_enabled(p_identity uuid, p_type_key text, p_channel text) RETURNS boolean`** — `NEW RPC`,
`SECURITY DEFINER`, `service_role`-only EXECUTE. The single resolver. Order of evaluation:

```
1. registry row absent OR active = false           -> false
2. channel not in allowed_channels                 -> false
3. delivery_class = 'mandatory'                    -> TRUE, and RETURN NOW.
                                                      The preference table is never read.
4. preference row exists                           -> its `enabled`
5. otherwise                                       -> channel ∈ default_channels
```

**Step 3 returns before step 4 is reachable.** Even a row that somehow existed for a mandatory type could not
suppress anything. That is the second of two independent guarantees; the first is §3.3.

### 3.3 The mandatory class — structurally impossible to disable

The enforcement is **declarative DDL, not a trigger, not application code, and not RLS.**

`notify.preference` carries a denormalised `delivery_class` column with:

```
FOREIGN KEY (type_key, delivery_class)
  REFERENCES notify.notification_type (type_key, delivery_class)
  ON UPDATE CASCADE
CHECK (delivery_class <> 'mandatory')
```

What this buys, in order of importance:

- **A preference row for a mandatory type cannot be inserted.** The composite FK forces `delivery_class` to equal
  the registry's value for that `type_key`; the CHECK then rejects `'mandatory'`. There is no value of the pair
  that satisfies both. No trigger to bypass, no `service_role` exemption, no RLS to misconfigure — `service_role`
  bypasses RLS but **cannot bypass a CHECK constraint**, which is exactly why the guarantee is put here and not in
  a policy.
- **Reclassifying a type to mandatory is a forced, visible migration.** `ON UPDATE CASCADE` propagates the new
  `delivery_class` into every existing preference row, where the CHECK then fires. The `UPDATE` on the registry
  **fails** until the author explicitly deletes the now-illegal overrides. Silent reclassification is impossible.
- **Downgrading mandatory → optional is safe and needs no cleanup** — the CHECK simply starts admitting rows.

`INFERENCE:` a `GENERATED ALWAYS AS ... STORED` column cannot be used here because it cannot read another table;
the denormalised column is written by `notify.set_preference()` and held true by the FK. That is the standard
Postgres idiom for "this column must agree with the parent," and it is the whole mechanism.

**The in-app centre is not a channel.** `notify.notification` rows are always written, for every type, before any
transport is attempted. `allowed_channels` covers only `push` and `email`. There is no preference, mandatory or
otherwise, that suppresses the durable record — so a user who has muted everything still has a complete,
auditable history in the app. This is what makes `ON`/`OFF` safe: turning a type off degrades *interruption*,
never *record*.

### 3.4 Why these 24 are mandatory

| Family | Types | Reason |
|---|---|---|
| **Money leaving or returning to the user's own funds** | all 4 refund types, `payout_released`, `payout_failed`, `payout_on_hold`, `staff_payout_failed`, `listing_sold` | A person must be told when their money moves. A silenced "refund failed" leaves someone waiting for funds that will never arrive, with no way to know. |
| **Account-security state change** | all 5 `security_*` | The entire value of a security alert is that an attacker cannot switch it off. A disableable security alert is worse than none, because it creates false confidence. |
| **Custody change on an asset the user holds** | `ownership_changed`, `transfer_received`, `transfer_accepted` | Losing or gaining a ticket without being told is indistinguishable from theft. |
| **Entitlement viability** | `event_cancelled`, `event_postponed`, `event_time_changed`, `event_venue_changed` | The user paid for admission at a time and place. If either changes, silence causes a missed event — a concrete, uncompensable loss. |
| **The transaction record** | `purchase_confirmed`, `ticket_ready`, `purchase_failed` | The receipt and the delivery confirmation are the record of the trade. |

**`INFERENCE`, and the honest limit of it:** this classification is a product-and-ethics judgement grounded in
what a reasonable person would consider unwaivable, not a legal opinion. Consumer-protection receipt rules,
payment-reversal disclosure expectations, card-network dispute-notice requirements, and app-store guidance
(transactional notices are not marketing, and must not be bundled with marketing consent) all bear on which of
these are *legally* compulsory in the operating jurisdictions. **That determination requires counsel and is
O-N4.** The design is deliberately built so the answer changes one registry column and nothing else.

### 3.5 Deliverability failure is not consent

A hard bounce, a spam complaint, or a revoked push permission writes `notify.identity_channel_state`. It **does
not** write `notify.preference`, and it **never** silences a mandatory type. Behaviour:

- Push permission denied / all tokens revoked → push deliveries go `suppressed` (reason `no_transport`), the
  in-app row is still written, and for a MANDATORY type the email adapter is attempted **even if email is `OFF`
  by preference** — because the preference governs *whether the user wants to be interrupted*, and the mandatory
  class governs *whether they must be reachable*. If no transport at all is available, the type is recorded
  `undelivered_mandatory` and surfaced in the in-app centre with an "we could not reach you" banner.
- Email hard-bounced → email suppressed, push attempted, in-app always written.
- **A mandatory notification is never dropped silently.** Every terminal failure of a mandatory type raises a
  Sentry event (§4.7) — the notification path has none today (D-9).

### 3.6 Quiet hours

`INFERENCE / proposed, needs a decision (O-N12).` A `notify.preference` row with `channel='push'` and a
`quiet_hours` window would suppress **non-mandatory push only**, deferring to the next open window rather than
dropping. Mandatory types ignore it entirely. Not built in MVP; the `notify.delivery.next_attempt_at` column
already carries the machinery, so adding it later is additive.

### 3.7 Client surfaces

`NEW RN SURFACE` and `NEW DASHBOARD SURFACE`. One RPC serves both: **`notify.get_preference_matrix()`** returns
the registry joined to the caller's overrides — `type_key, group_label, display_label, description,
delivery_class, channel, effective_enabled, mandatory_reason`. The UI renders:

- an optional type as a switch;
- a **mandatory type as an always-on row with its `mandatory_reason` as visible copy**, never a disabled switch.
  The dashboard spec already requires exactly this rendering (`:1038`: *"Non-opt-out rows render as always-on with
  an explanation"*) and supplies the copy for payout failure (`:938`).

`notify.set_preference(p_type_key, p_channel, p_enabled)` — `NEW RPC`, `authenticated`, `auth.uid()`-scoped. It
raises `40003 mandatory_type_not_configurable` before touching the table; the DDL of §3.3 makes the write
impossible anyway. **Both layers must hold** — the same "both layers" discipline the edge spec already mandates
for idempotency (`PHASE_2_EDGE_FUNCTION_SPEC.md:481-484`).

`public.notification_preferences` and `app/settings/notifications.tsx` are **left in place, untouched**. The six
legacy booleans are seeded as `notify.preference` rows on first read of the new matrix
(`INFERENCE:` a one-shot lazy migration, not a backfill, so nothing runs against the whole user table). O-N10.

---

## §4 — Delivery pipeline

### 4.1 The five hops

```
  (1) PRODUCER                (2) ENVELOPE            (3) FAN-OUT           (4) ADAPTER        (5) TRANSPORT
  RPC / trigger / sweep  ──►  notify.outbox      ──►  notify.notification ──► notify.delivery ──► Expo / Resend
  same transaction as         same transaction        one row per            one row per          external
  the state change            as the producer         (recipient, subject)   (notification,ch)

        │                          │                        │                      │
        │                          └── drained by pg_cron ──┘                      │
        │                              notify.drain_outbox()                       │
        └── never raises (two layers)                                              │
                                            notify-dispatch edge fn ───────────────┘
```

**Hop 1→2 is synchronous and transactional. Hops 2→5 are at-least-once.** That is C12's contract
(`SNATCH_IT_CANONICAL_DATA_MODEL.md:606`) and it is not negotiable — which is precisely why hop 3 carries the
user-visible dedupe key (§4.2).

`ADDITIVE SCHEMA CHANGE` throughout. **`CONFLICT-2` applies to the whole of this section**: the constitution
promises the outbox in Phase 2 (`SNATCH_IT_DOMAIN_ARCHITECTURE.md:1253`) and no implementation spec schedules it.

### 4.2 Idempotency at each hop — three keys, three layers

| Hop | Object | Key | Enforced by | What a replay does |
|---|---|---|---|---|
| **2** | `notify.outbox` | `event_key` = the §6.1 idempotency key of the business event (e.g. `payout_id`, `stripe_refund_id`, `ownership_log_id`, `market_sale_id`) **plus** `event_type` | `UNIQUE (event_type, event_key)` | a replayed producer writes **no second envelope** |
| **3** | `notify.notification` | `dedupe_key` — the §2.2 value | `UNIQUE` partial index, `WHERE dedupe_key IS NOT NULL` — **the exact `057:50-52` pattern**, reused | a re-drained envelope inserts **no second user-visible row** (`ON CONFLICT DO NOTHING`) |
| **4** | `notify.delivery` | `(notification_id, channel)` | `UNIQUE` | a re-fan-out creates **no second delivery row** |
| **5** | the wire | `notify.delivery.claimed_until` lease + terminal `sent_at` | `UPDATE ... WHERE state='pending' AND (claimed_until IS NULL OR claimed_until < now()) RETURNING` | a dispatcher that crashed after Expo returned 200 but before it wrote `sent_at` **can** re-post — see the honest limit below |

**The idempotency boundary that answers "why did the user see 'refund completed' twice" is hop 3 — the
notification row — keyed `refund_completed:<kernel_refund_id>`.**

Reasoning, stated as the design rejects the two alternatives:

- **Not hop 2 (the envelope).** C12 defines delivery as at-least-once and consumers as idempotent
  (`CDM:606`). A drainer that commits handler work and crashes before acking re-presents the same envelope. Making
  the envelope the boundary would require exactly-once delivery, which C12 explicitly refuses to promise
  (`SNATCH_IT_DOMAIN_ARCHITECTURE.md:1251`: *"'At-least-once + idempotent consumer,' never 'exactly-once'"*).
- **Not hop 4/5 (the delivery attempt).** A retried push after an Expo 5xx is a duplicate *attempt*, not a
  duplicate *notification*, and it must be allowed — otherwise a transient failure loses a mandatory notice. The
  delivery row is the right place to bound *attempts*; it is the wrong place to bound *facts*.
- **Hop 3 is where a fact becomes a thing the user can see.** One row, one unique key, `ON CONFLICT DO NOTHING`
  — the identical construction that already absorbs the password sweep's 60-minute overlap
  (`0600:27-29`).

**The honest limit.** Hop 3 guarantees the *in-app centre* shows one row. It does **not** guarantee the *device*
buzzes once: a dispatcher that dies in the ~200 ms window between Expo's 200 and the `sent_at` write will re-post
after the lease expires, and the user gets two banners for one row. Narrowing that window is the lease's job; it
cannot be closed without exactly-once semantics against a third party that does not offer them. **For MANDATORY
money types the design deliberately prefers a rare duplicate banner to a rare missing one.** The support-visible
consequence — "I got the refund notice twice" — is bounded by the fact that both banners open the *same* single
notification row, so the app never shows two refunds.

### 4.3 Hop 2 — the envelope (C12)

`notify.outbox` — `ADDITIVE SCHEMA CHANGE`.

`outbox_id uuid PK · event_type text · aggregate_kind text · aggregate_id uuid · sequence bigint ·
causation_id uuid · correlation_id uuid · event_key text · payload jsonb · occurred_at timestamptz ·
state ∈ ('pending','claimed','done','dead') · claimed_until timestamptz · attempt int · last_error text ·
created_at`.
`UNIQUE (event_type, event_key)` · `UNIQUE (aggregate_kind, aggregate_id, sequence)` ·
index `(state, occurred_at) WHERE state IN ('pending','claimed')`.

C12 requires *"a per-aggregate monotonic `sequence`, plus `causation_id` and `correlation_id`"* (`CDM:606`) —
all three are columns, not conventions. `sequence` is allocated per `(aggregate_kind, aggregate_id)` under the
aggregate's existing row lock, which every SSCAS member already holds in the global lock order
(`PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md:120-124`), so no new lock and no new deadlock class is introduced.
**The outbox row is written last within its transaction**, after every money/custody row, so it is strictly below
the money-plane rows in the lock order.

**`payload` never contains a recipient list** (§2.4) and never contains rendered copy (§5) — only ids and the
scalar facts a consumer needs.

**`notify.emit_event(...)`** — `NEW RPC`, `SECURITY DEFINER`, `service_role`-only, **non-raising**, same
`EXCEPTION WHEN OTHERS` subtransaction shape as `public.enqueue_notification` (`057:80-86`). A producer that
cannot emit its envelope logs a warning and commits its money/custody work regardless. §0.3 rule 1.

### 4.4 Hop 3 — fan-out, and the deep-link model

**`notify.drain_outbox(p_limit int)`** — `NEW RPC`, `service_role`, invoked by pg_cron.

```
pg_try_advisory_xact_lock(hashtext('notify_drain_outbox'))            -- 0600:115 pattern
SELECT ... FROM notify.outbox
 WHERE state = 'pending' AND occurred_at <= now()
 ORDER BY occurred_at, outbox_id
 FOR UPDATE SKIP LOCKED LIMIT p_limit                                  -- C49 down-payment
```

`SKIP LOCKED` is what makes the drainer safe to run in parallel later without redesign — C49's *"partitioned /
multi-drainer (no head-of-line blocking)"* is Gate L (`PHASE_2_RATIFICATION_RECORD.md:41`), and this is the MVP
shape that does not have to be undone to get there.

Per envelope: resolve recipients (§2.4), then **one set-based `INSERT ... SELECT ... ON CONFLICT (dedupe_key) DO
NOTHING`** into `notify.notification`. No row loop. C12 requires consumers be *"idempotent by a persisted dedup key
OR ... an upsert/set-operation (never a naked increment)"* (`CDM:606`) — this is both.

**Poison quarantine.** A handler that raises marks **that envelope** `dead` with `last_error` and continues. One
bad row can never block the batch. `INFERENCE:` this is the MVP-shaped down-payment on C49's quarantine
requirement; the full Gate-L form (a separate quarantine store with redrive) is not built.

#### The deep-link model — structurally open-redirect-proof

**`notify.notification` stores `target_kind` (a closed enum) + `target_id` (uuid). It never stores a URL.**

The closed set (MVP): `ticket · ticket_pass · event · event_session · listing · listing_native · p2p_transfer_in ·
p2p_transfer_out · external_transfer_send · external_transfer_receive · order · refund · payout ·
account_security · account_notifications · announcement · none`.

Four invariants:

- **N-DL-1 — there is no place to put a hostile URL.** The column admits only registry values; a CHECK against the
  closed set rejects everything else. This is stronger than sanitising a URL, because there is no URL.
  `safeInternalPath` (`web/src/lib/auth/redirect.ts:17-19`, regexes `/[ -]/` and
  `/^\/(?!\/)[^\s\\]*$/` plus the `/auth/` prefix ban) **stays in place as defence-in-depth** for the 12 legacy
  types that still write `link`. New types write `target_kind`/`target_id` and leave `link` NULL; a server-side
  `notify.resolve_web_link(target_kind, target_id)` composes the web path from the closed set.
  `SPEC CORRECTION:` the 058 producers build `link` by string-concatenating a uuid (`058:77, :91, :114, :142`).
  That is safe today only because the input is a uuid. **Phase 2 must not extend the pattern.**
- **N-DL-2 — fail safe, and fail *identically*.** A client never navigates on the strength of the notification.
  It opens the screen for `target_kind`, which then loads `target_id` **under RLS**. Because GP-2 makes row
  deletion impossible platform-wide (`PHASE_2_RLS_PERMISSION_SPEC.md:84-88`), "the target no longer exists" is
  almost always "the target is no longer visible to *you*". Distinguishing the two in copy would leak existence.
  **One terminal state, one string, for both:** *"This isn't available to you anymore."* Plus a type-appropriate
  next action — Tickets, the event page, the inbox. Never an error screen, never a redirect, never a loop.
  Concrete cases: ticket transferred away → the sender's `transfer_accepted` tap lands here by design; listing
  cancelled; transfer expired; announcement revoked (§7.5).
- **N-DL-3 — the target is derived from `subject_id`, never from content.** For `organizer_announcement` the
  target is computed as `('announcement', announcement_id)` from the row; **nothing in the organizer's free text
  can influence it** (§7.2).
- **N-DL-4 — a notification link may never carry a secret, a token, or a one-time action.** `VERIFIED` ground:
  the app has only the custom scheme `snatchit` (`app.json:8`); there is no `associatedDomains` and no
  `web/public/.well-known/`, so neither AASA nor `assetlinks.json` is hosted, and
  `src/providers/NativeAppShell.native.tsx:158-165` documents that a co-installed malicious app can claim the
  scheme. **Tapping a notification may only ever navigate.** Every action still requires the authenticated
  session. Universal links are O-N15.

**Cold-start ordering (`NEW RN SURFACE`).** Today `getLastNotificationResponseAsync()` routes through a bare
`setTimeout(...,0)` with no session gate (`NativeAppShell.native.tsx:233-236, :264-270`), so a tap on an
unauthenticated cold start is **dropped** (D-15). Phase 2: the tap writes a *pending target* to `expo-secure-store`,
auth resolves, and the router replays it once — or discards it if the session belongs to a different identity than
the notification's recipient.

### 4.5 Hop 3 at scale — the scheduled fan-out

One event, thousands of holders, one scheduled expansion. **The producer is a sweep, not a trigger** — there is no
per-ticket state change to hang a trigger on.

**`notify.schedule`** — `ADDITIVE SCHEMA CHANGE`.
`schedule_id uuid PK · schedule_kind ('event_reminder_24h','event_door_open','sales_digest') ·
subject_kind · subject_id · fire_at timestamptz · state ∈ ('queued','claimed','expanding','done','superseded',
'failed') · claimed_until · expand_cursor uuid · expanded_count int · attempt int · last_error ·
created_at`, `UNIQUE (schedule_kind, subject_id, fire_at)`.

**`notify.sweep_scheduled()`** — `NEW RPC`, `service_role`, on pg_cron `*/5 * * * *` (the cadence
`sweep-auth-password-changes` already proves at `075:358`).

1. `pg_try_advisory_xact_lock(hashtext('notify_sweep_scheduled'))`, early `RETURN` — **verbatim `0600:115-117`**:
   *"a slow run must never pile up behind itself."*
2. Claim a bounded batch: `WHERE fire_at <= now() AND state IN ('queued','expanding') AND (claimed_until IS NULL
   OR claimed_until < now()) ORDER BY fire_at FOR UPDATE SKIP LOCKED LIMIT N`.
3. Expand **set-wise, one statement, cursor-bounded**:
   `INSERT INTO notify.notification (...) SELECT ... FROM kernel.tickets WHERE event_session_id = $1 AND state =
   'active' AND ticket_id > expand_cursor ORDER BY ticket_id LIMIT 5000 ON CONFLICT (dedupe_key) DO NOTHING`,
   then advance `expand_cursor` to the max inserted id. A 50 000-holder event drains over ten ticks instead of
   holding one long transaction and one long lock.
4. `state = 'done'` only when the cursor is exhausted. **On failure the cursor and state are left unadvanced** —
   the identical rule as the password sweep (`0600:164-170`): *"a failure retries the window rather than dropping
   events."*

**If the job runs twice, three independent guards catch it, and only the third is load-bearing:**

1. the advisory lock (prevents overlap);
2. the claim lease `claimed_until` (prevents a crashed run wedging a row forever — after expiry another run
   reclaims it);
3. **`UNIQUE (dedupe_key)` on `notify.notification`**, key `event_reminder_24h:<event_session_id>:<ticket_id>`.

Guard 3 is the one correctness depends on, and this is deliberate — it is the same argument `0600:27-29` makes
about its own lock: *"Correctness does not depend on the advisory lock."* A double run re-presents identical keys
and the unique index absorbs them. A cursor that rewinds re-presents identical keys. A lease that expires
mid-expansion re-presents identical keys. **Every failure mode collapses to the same no-op.**

**Timezone and re-scheduling.** `fire_at` is computed **once**, at schedule creation, from
`catalog.event_session.starts_at` / `door_open_at`, and stored as `timestamptz`. It is never recomputed per
recipient. A time change does **not** mutate `fire_at`: the old rows go `state='superseded'` and new rows are
created — so the audit trail shows what was scheduled and what replaced it, and the already-sent reminders keep
their (now historical) meaning.

**Push fan-out is a separate hop**, so a 50 000-recipient expansion is 50 000 cheap `notify.delivery` rows drained
in chunks by §4.6 — never 50 000 synchronous HTTP calls inside a sweep.

### 4.6 Hops 4–5 — per-channel adapters, retry, dead-letter

**`notify.delivery`** — `ADDITIVE SCHEMA CHANGE`.
`delivery_id uuid PK · notification_id → notify.notification · channel ∈ ('push','email') ·
state ∈ ('pending','claimed','sent','failed','dead','suppressed') · suppress_reason ·
attempt int · next_attempt_at · claimed_until · provider_message_id · provider_receipt_id ·
provider_receipt_state · rendered_subject · rendered_body · last_error · sent_at · created_at`.
`UNIQUE (notification_id, channel)` · index `(state, next_attempt_at) WHERE state IN ('pending','claimed')`.

**`notify-dispatch`** — `NEW EDGE FUNCTION`. Cron-invoked, `verify_jwt = true`, plus a constant-time bearer check
accepting **either** `INTERNAL_CRON_SECRET` **or** the service-role key.
`SPEC CORRECTION:` `send-push` accepts only the service-role key (`send-push/index.ts:14-25`) while both its
callers accept both — and that inconsistency is exactly what killed the outbid path (D-7,
`054_fix_notify_outbid_aborts_bids.sql:12-16`). Every new internal function accepts both, and §9 N-A20 asserts it.

Push adapter, fixing D-2/D-3/D-10:
- claim `pending` deliveries with `next_attempt_at <= now()` under a lease;
- resolve tokens: `public.push_tokens WHERE user_id = $1 AND revoked_at IS NULL`;
- **chunk at 100 messages per Expo request** (there is no chunking at all today);
- honour `429` + `Retry-After` by setting `next_attempt_at`, never by spinning;
- **persist every Expo ticket id into `provider_receipt_id`** — today the response is echoed into a 200 and
  discarded (`send-push:96-99`);
- record the outcome on the delivery row so a 401 becomes *visible* rather than silent (D-18).

**`notify-receipts`** — `NEW EDGE FUNCTION`, cron `*/15`. Polls Expo's receipts endpoint for `provider_receipt_id`
values older than 15 minutes and:
- `DeviceNotRegistered` → set `push_tokens.revoked_at = now()`, `revoked_reason = 'device_not_registered'`.
  **This is the first code in the system's history that would ever mark a token inactive** (D-3).
- `MessageTooBig` / `InvalidCredentials` → `dead` + Sentry.
- transient → back to `pending` with backoff.

Email adapter — `_shared/email.ts` (`NEW`), promoting the private helper at `notify-report/index.ts:57-79` to a
shared module. **Conditional on O-N3**: today there is exactly one call site, gated by `EMAIL_ENABLED` defaulting
to `'false'` (`notify-report:31`), with no SDK, no shared helper, and auth mail on a personal Gmail relay (D-16).
Until SPF/DKIM/DMARC exist on `snatchitapp.com`, every `E` row dispatches to `suppressed` /
`channel_unavailable` — **which is why email is a channel row and not a hard dependency anywhere in this spec.**

**Retry schedule:** attempts at +1 m, +5 m, +25 m, +2 h, +12 h. Five attempts, then `dead`.
**Dead-letter:** `state='dead'` with `last_error`. There is no separate DLQ table — the delivery row *is* the
dead letter, which keeps the failure attached to the notification a support agent is already looking at.

### 4.7 Observability

- Every terminal `dead` on a **MANDATORY** type → `captureException` via `_shared/sentry.ts`. **The notification
  path has no Sentry coverage at all today** — none of `notify-transfer`, `notify-report`, `send-push` imports it
  (D-9).
- `notify.dead_letter_count` and `notify.oldest_pending_age` exposed to the platform admin plane; C12 requires a
  *"bounded dwell + max-age alarm"* for SSCAS members and the same discipline is cheap to apply here.
- Structured one-line-per-stage JSON logging, per `PHASE_2_EDGE_FUNCTION_SPEC.md:487-489`. **Never** log
  `rendered_body` for a `security_*` type, an announcement body, or any counterparty name.

---

## §5 — Templates and localization-ready structure

### 5.1 The rule that makes everything else possible

**A notification row stores a `template_key` and a `params jsonb`. It never stores a rendered string.**

Today it does the opposite: `058_notification_producers.sql` builds English copy by SQL string concatenation at
producer time — `'New bid: $' || NEW.amount` (`:75`), `'Someone bid $' || NEW.amount || ' on ' ||
coalesce(v_title,'your listing') || '.'` (`:76`). That copy is frozen into the row forever. Changing a typo means
a data migration; translating means an impossible one.

`ADDITIVE SCHEMA CHANGE`. `notify.notification` carries `template_key text NOT NULL` and `params jsonb NOT NULL
DEFAULT '{}'`. The 12 legacy types keep their pre-rendered `title`/`body` columns; new types leave them NULL and
carry params. Both shapes coexist because the renderer falls back to the stored strings when `template_key` is
NULL.

### 5.2 `notify.template`

`template_key · locale · channel · version · subject text · body text · created_at`,
`PRIMARY KEY (template_key, locale, channel, version)`.

- **Channel-specific by construction.** A push body must fit a lock screen (≈120 chars); an email body must not.
  They are different rows, not one string truncated twice.
- **Versioned** — C18 requires versioned vocabularies (`CDM:612`). A copy change is a new `version`, never an
  in-place edit, so a delivered notification can always be re-rendered exactly as it was sent.
- **Placeholders are named and closed**: `{{event_title}}`, `{{amount}}`, `{{venue_name}}`. A template referencing
  a placeholder absent from the type's declared param set fails the registry migration's CI check, not production.

### 5.3 Where rendering happens — deliberately two places

| Surface | Rendered | Why |
|---|---|---|
| In-app centre | **at read time**, from `template_key` + `params` + the reader's current locale | history re-renders when a user changes language; a copy fix improves the past |
| Push / email | **at send time**, and the result is frozen into `notify.delivery.rendered_subject` / `rendered_body` | the wire copy is what the user actually received; support and audit need the exact string, and it can never be retro-edited |

### 5.4 Locale resolution

```
kernel.identity_ext.locale        (Δ-N2 — the column does not exist yet)
  → device locale captured at push-token registration
  → 'en-US'
```

`notify.notification.locale_resolved` stores the answer at fan-out time so a re-render is reproducible.

**MVP ships `en-US` only.** What Phase 2 buys is the *structure*: adding `es-US` later is inserting
`notify.template` rows, not touching a single producer, notification row, or client string.

`VERIFIED`, and it is the constraint that shapes this section: **there is no localization framework anywhere** —
no `expo-localization`, `i18n-js`, `react-i18next`, `next-intl` or `react-intl` in either `package.json`; no
`locales/` directory; not one use of `Intl.NumberFormat` or `Intl.DateTimeFormat`; `timeAgo` is hand-rolled
English (`web/src/components/account/NotificationsList.tsx:13-22`) (D-17). So the DB structure **must not assume
any client library exists**, which is why rendering is a server capability reachable by RPC and not an ICU bundle
shipped to two clients that cannot parse it.

Money and dates: `params` carry `amount_minor` + `currency` and raw `timestamptz`, never pre-formatted strings —
formatting is a rendering concern, and C13 already requires money to travel as `(amount_minor, currency,
minor_unit)` rather than a scalar (`CDM:607`).

### 5.5 Copy governance

Every template is subject to the RN product-language rule (`PHASE_2_REACT_NATIVE_PRODUCT_SPEC.md:13`), which names
push copy explicitly. **Forbidden in any notification string:** `kernel · catalog · rail · ticket atom · SSCAS ·
credential_version · market_sale · ownership log · batch · shard · resale_state · cause-code`. Approved vocabulary
is the table at `:17-30` — *Official Ticket*, *Transfer*, *Entry Pass*, and so on. Template review is part of the
registry migration; §9 N-A18 asserts the forbidden-term ban mechanically over `notify.template`.

Additional rules specific to notifications, from §8:
- **No counterparty name and no money amount in a push `subject`/`body`** for custody or money types — those go in
  the in-app body only (§8.4).
- **No cause-codes.** `ownership_changed` renders `cause_label` ("Transferred to you", "Bought resale"), the
  plain-verb mapping the RN spec already requires for ticket history (`:205, :207`).

---

## §6 — Deltas: schema · RLS · RPC · Edge · clients

### 6.1 Schema delta — `ADDITIVE SCHEMA CHANGE` throughout

New schema **`notify`** — 9 tables. Nothing is dropped, nothing re-typed, no existing column changes meaning.

| # | Table | Purpose | RLS class (`PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md:94-104`) |
|---|---|---|---|
| 1 | `notify.notification_type` | the C18 registry; `UNIQUE(type_key, delivery_class)` | deny-all; read via RPC |
| 2 | `notify.notification` | the durable record; `UNIQUE(dedupe_key)` partial | **owner-scoped** |
| 3 | `notify.delivery` | per-`(notification, channel)` attempt state | deny-all (RPC-only) |
| 4 | `notify.preference` | sparse override + the §3.3 mandatory guard | **owner-scoped** |
| 5 | `notify.identity_channel_state` | transport facts (bounce/complaint/unreachable) | deny-all |
| 6 | `notify.outbox` | the C12 envelope | deny-all |
| 7 | `notify.schedule` | scheduled fan-out state | deny-all |
| 8 | `notify.announcement` | organizer announcements + their state machine | **venue-scoped** read for staff |
| 9 | `notify.template` | copy, per `(key, locale, channel, version)` | deny-all; rendered via RPC |

**Extensions to existing tables (additive columns only):**

| Object | Added | Why |
|---|---|---|
| `public.push_tokens` | `revoked_at timestamptz`, `revoked_reason text`, `provider_receipt_checked_at timestamptz`, `last_provider_error text` | D-3: nothing has ever marked a token inactive. `is_active` is left in place and untouched; `revoked_at IS NULL` becomes the authoritative predicate, so no backfill and no behaviour change for existing readers |
| `catalog.event_session` | `session_version int NOT NULL DEFAULT 1` | **Δ-N1**, and it is a correctness requirement: without it a second door-time change collides with the first notification's dedupe key and is silently swallowed (§2.2 Group E) |
| `kernel.identity_ext` | `locale text` | **Δ-N2**, §5.4 |
| `catalog.platform_config` | seeds `notify.announcements_enabled`, `notify.announcement_hold_seconds`, `notify.announcement_dual_control_threshold`, `notify.announcement_max_per_session`, `notify.announcement_min_interval_seconds` | §7; the config table is already versioned `(key, version)` (`schema §2.4`) |

**Migration numbering.** Per `CONFLICT-3`, these land at **`076_`+**, not `071`/`073`. Every package carries the
mandated header (purpose · forward behaviour · backwards-compat · expected locks/runtime · rollback location ·
verification query) per `PHASE_2_SUPABASE_MIGRATION_PLAN.md:178-179`, and every one is expand→verify→adopt with no
big-bang (`:126`).

**`public.notifications`, `public.notification_preferences`, `public.transfer_notifications`,
`public.enqueue_notification` and every existing trigger are untouched.** `NO SCHEMA CHANGE`.

### 6.2 RLS delta

**`notify.notification` reuses the `040` posture verbatim** — this is the single most valuable piece of reuse in
the spec, because that posture is already production-proven:

```
REVOKE ALL ON notify.notification FROM PUBLIC, anon, authenticated;   -- 040:97
GRANT SELECT ON notify.notification TO authenticated;                 -- 040:98
GRANT UPDATE (read_at) ON notify.notification TO authenticated;       -- 040:99
policy "owner select"        USING (recipient_id = auth.uid())        -- 040:101-103
policy "owner update read"   USING/WITH CHECK (recipient_id = auth.uid())  -- 040:105-108
-- NO INSERT policy, NO DELETE policy, for any client role.
```

Column-level `UPDATE (read_at)` matters and is not decoration: RLS restricts *rows*, not *columns*
(`040:90-96`), so without it a user could rewrite `title`/`body`/`params` on their own rows. The web mark-read
action already relies on this as defence-in-depth (`web/src/lib/notifications-actions.ts:9-12`).

| Table | Posture |
|---|---|
| `notify.notification` | owner-scoped, as above |
| `notify.preference` | owner-scoped full CRUD via `auth.uid()`; **the mandatory guard is DDL, never RLS** (§3.3) — a policy could be misconfigured, a CHECK cannot be |
| `notify.announcement` | venue-scoped read for `[venue_manager, org_owner, org_admin]` + platform; **writes RPC-only**; recipients never read this table, they read their own `notify.notification` row |
| `notify.notification_type`, `notify.template` | deny-all; surfaced only through `notify.get_preference_matrix()` / the renderer. Deny-all rather than public-read because the UI needs the *resolved* state, not the raw registry |
| `notify.delivery`, `notify.outbox`, `notify.schedule`, `notify.identity_channel_state` | RLS on, **zero policies**, `REVOKE ALL FROM anon, authenticated` — the `auth_audit_sweep_state` posture (`0600:91-92`) |

GP-1 and GP-2 hold throughout (`PHASE_2_RLS_PERMISSION_SPEC.md:76-88`): no client holds direct INSERT/UPDATE/DELETE
on any `notify` table beyond `UPDATE(read_at)`, and DELETE is denied everywhere — a "cleared" notification is a
`dismissed_at` column, never a row removal.

### 6.3 RPC contracts — `NEW RPC` (all `SECURITY DEFINER`, `SET search_path`, owned by `postgres`, explicit REVOKE-then-GRANT per `067`)

**Consumer-facing (`authenticated`):**

| RPC | Contract |
|---|---|
| `notify.get_inbox(p_cursor timestamptz, p_limit int ≤ 50)` | own rows, newest first, keyset-paginated. Returns `notification_id, type_key, group_label, rendered_title, rendered_body, target_kind, target_id, read_at, created_at`. Rendered server-side (§5.3). **Keyset, not `.limit(50)`** — the web inbox currently truncates at 50 with no pagination (`web/src/lib/notifications.ts:29`) |
| `notify.get_unread_count()` | `WHERE recipient_id = auth.uid() AND read_at IS NULL AND dismissed_at IS NULL`; served by the partial index (`040:84-86`). **Fails to `0`, never raises** — it renders in a global header (`web/src/lib/notifications.ts:52, :54`) |
| `notify.mark_read(p_ids uuid[])` · `notify.mark_all_read()` | writes `read_at` only, `auth.uid()`-scoped |
| `notify.dismiss(p_ids uuid[])` | writes `dismissed_at`; never deletes (GP-2) |
| `notify.get_preference_matrix()` | §3.7 |
| `notify.set_preference(p_type_key, p_channel, p_enabled)` | raises `40003 mandatory_type_not_configurable`; the DDL makes the write impossible regardless (§3.3) |
| `notify.register_push_token(p_token, p_platform, p_device_name, p_locale)` | upserts on `token` and **always sets `user_id = auth.uid()`** and `last_used = now()`. Fixes D-4 (a device changing hands keeps the previous owner's `user_id`) and D-5 (`last_used` NULL on first insert) |
| `notify.revoke_push_token(p_token)` | sets `revoked_at`; called on sign-out. Fixes D-6 |
| `notify.report_announcement(p_announcement_id, p_reason)` | §7.6 |

**Staff-facing (`authenticated`, role-gated):** `notify.draft_announcement` · `notify.preview_announcement_audience`
(returns **a count only**, never a recipient list) · `notify.approve_announcement` · `notify.cancel_announcement` ·
`notify.revoke_announcement` — all §7.

**Internal (`service_role` only; `REVOKE ... FROM PUBLIC, anon, authenticated` then `GRANT ... TO service_role`,
exactly `057:90-91`):** `notify.emit_event` · `notify.enqueue` · `notify.channel_enabled` · `notify.drain_outbox` ·
`notify.sweep_scheduled` · `notify.record_delivery_result` · `notify.claim_deliveries`.

`notify.enqueue` **supersedes-by-extension** `public.enqueue_notification`: the old function stays, unmodified,
serving the 12 legacy types; the new one takes `(recipient, type_key, subject_kind, subject_id, params,
dedupe_key)` and derives channels, template and target from the registry. Both are non-raising with the same
`EXCEPTION WHEN OTHERS` subtransaction shape (`057:80-86`).

### 6.4 Edge Function contracts

| Fn | Class | verify_jwt | Auth | Schedule | Contract |
|---|---|---|---|---|---|
| `notify-dispatch` | `NEW EDGE FUNCTION` | `true` | constant-time bearer: `INTERNAL_CRON_SECRET` **OR** service-role | pg_cron `* * * * *` | claim → render → Expo (chunk 100) / Resend → `notify.record_delivery_result` |
| `notify-receipts` | `NEW EDGE FUNCTION` | `true` | same | pg_cron `*/15 * * * *` | poll Expo receipts; revoke `DeviceNotRegistered` tokens |
| `_shared/notify-auth.ts` | `NEW` shared module | — | — | — | one `constantTimeEqual` + dual-secret check, replacing **five** copy-pasted implementations (D-11) |
| `_shared/email.ts` | `NEW` shared module | — | — | — | promotes `notify-report:57-79`; **conditional on O-N3** |
| `send-push` | `NO SCHEMA CHANGE` | unchanged | unchanged | — | kept for the 15 legacy push types; **not extended** |
| `notify-transfer`, `notify-report` | `NO SCHEMA CHANGE` | unchanged | unchanged | — | untouched |

Every new function inherits `PHASE_2_EDGE_FUNCTION_SPEC.md:470-497` unchanged: CORS whitelist +
`getSecurityHeaders()` on every response including errors and OPTIONS; secrets by name only; `check_rate_limit`
fail-closed; deterministic idempotency keys with **both** layers holding; RPC-first-then-side-effect ordering;
structured logging with no PII; deny-by-default failure mapping.

`SPEC CORRECTION` to `PHASE_2_EDGE_FUNCTION_SPEC.md:75`: the placement table rejects a new push function with
*"REJECTED → reuse `send-push` — already exists."* That verdict is correct about *transport* and wrong about
*pipeline*: `send-push` has no batching (D-10), no receipt loop (D-2), no retry, no idempotency, no preference
check (D-1), and rejects the very secret its own callers use (D-7). **Reusing it for 40 new types would propagate
seven verified defects.** `notify-dispatch` is a new function; `send-push` stays for the legacy paths.

### 6.5 Client surfaces

**`NEW RN SURFACE` — the mobile notification centre.** The largest single product gap: no mobile file reads
`public.notifications`, `shouldSetBadge` is `false` (`NativeAppShell.native.tsx:48`), there is no
`addNotificationReceivedListener` anywhere, no unread count, no mark-as-read — **a push a mobile user swipes away
is gone permanently** (D-12). Required:

1. A notification-centre screen reading `notify.get_inbox()`, grouped by day, with per-row `target_kind` routing.
2. An unread badge from `notify.get_unread_count()`; `shouldSetBadge: true`; `setBadgeCountAsync` on
   foreground/receipt.
3. `addNotificationReceivedListener` → refresh the unread count in the foreground.
4. Mark-read on open; mark-all-read affordance.
5. `notify.register_push_token()` replacing the manual select-then-branch in `src/hooks/usePushToken.ts:71-86`;
   `notify.revoke_push_token()` wired into all four sign-out sites (`app/settings/index.tsx:122, :165`,
   `app/(tabs)/profile.tsx:275`, `src/hooks/useAuth.ts:62`).
6. A `target_kind` router replacing the hardcoded whitelist at `NativeAppShell.native.tsx:239-257`, **with an
   `else` branch** — today an unrecognised payload is dropped silently and four push types are unroutable orphans
   (D-13).
7. Pending-target replay across a cold, unauthenticated start (§4.4, D-15).
8. A preference screen from `notify.get_preference_matrix()`, rendering mandatory rows as always-on with their
   `mandatory_reason` — extending `app/settings/notifications.tsx`, which today shows six inert booleans.

**`NEW DASHBOARD SURFACE` — venue staff.** §16.5 of the dashboard spec is binding and already writes the copy:
one global toggle per user with *"This applies to every venue you work at. Per-venue settings are coming."*
(`:935`); the digest cadence stated so nobody waits for a ping that will not come (`:936`); payout failure as an
always-on row (`:938`); door anomaly described as on-duty-and-live-only (`:939`). Plus a **Send an update**
composer (§7) with its blast-radius count, hold window and irrevocability warning.

**`web/` consumer inbox** — `NO SCHEMA CHANGE` to what exists; it migrates from a direct
`.from("notifications").limit(50)` (`web/src/lib/notifications.ts:29`) to `notify.get_inbox()` with keyset
pagination. `safeInternalPath` stays (§4.4 N-DL-1).

---

## §7 — Organizer announcements: the abuse controls

### 7.0 The premise, stated plainly

A venue employee types free text. That text is delivered as a push notification to every person holding a ticket
to their event. **This is the only place in the entire platform where attacker-influenced content is broadcast to
thousands of people who did not ask for it.** It deserves more design than the feature appears to warrant.

**No such feature exists today.** `VERIFIED`: a case-insensitive search for `announcement|broadcast` across `app/`,
`src/`, `components/`, `hooks/`, `web/src/`, `packages/` and `supabase/functions/` returns zero hits; there is no
admin send UI, no broadcast function, no announcements table, no Realtime broadcast channel, and no preference
column that could gate one.

### 7.1 Threat model

| # | Threat | Realistic? |
|---|---|---|
| T1 | Content injection — the text reaches an HTML email body, a URL, or a deep-link target | Yes. The email adapter (§4.6) is the obvious sink |
| T2 | Phishing — *"Your ticket needs re-validation, tap here"* with an attacker-chosen destination | Yes, and it is the highest-value attack: the message arrives with the platform's own trust |
| T3 | Impersonation — a title reading "Snatch It Security Alert" | Yes, if the title is author-supplied |
| T4 | Spam / harassment — repeated blasts to a captive audience who cannot unsubscribe from the venue | Yes |
| T5 | Wrong-audience blast — intended for one session, sent to every holder at the venue | Yes; ordinary human error, high blast radius |
| T6 | Compromised staff account — one credential equals a push to every holder | Yes |
| T7 | Irrevocability — **a delivered push cannot be recalled, ever** | Not a threat; a *fact*, and the one that shapes the design |

### 7.2 Structural controls — making injection impossible rather than filtered

**C-A1 — The sender never supplies a recipient list.** `notify.announcement` carries `subject_kind` (MVP: exactly
`'event_session'`) + `subject_id`. Recipients are derived server-side from live custody (§2.4 form 2). There is no
parameter through which an audience can be widened, and `notify.preview_announcement_audience()` returns **a count
only** — never an enumeration. This kills T5 as an addressing error and denies T6 an audience-harvesting
primitive.

**C-A2 — Plain text only, with no URLs at all.**
`body text NOT NULL`, and three CHECK constraints:
- `char_length(body) BETWEEN 10 AND 500`;
- no control characters — `body !~ '[ -]'`, matching the first guard `safeInternalPath` already
  applies to untrusted input (`web/src/lib/auth/redirect.ts:17`);
- **no URL-shaped substring** — `body !~* '(https?://|www\.|[a-z0-9-]+\.(com|net|org|io|co|link|xyz|app|me)\b)'`.

Not "sanitised URLs" — **no URLs**. A venue that needs to link something links its own event, and the platform
renders that from `catalog.event`, never from the text. This is what defeats T2: there is no destination the
author can choose. `INFERENCE:` the TLD list is deliberately over-broad and will reject some legitimate prose
("see you at 8pm.co-op"); a false rejection the author can rewrite is strictly better than a phishing link that
ships.

**C-A3 — The body is a bound parameter at every hop, never an interpolation.** It travels as a jsonb string in
`notify.outbox.payload`, as a `params` value on `notify.notification`, as a JSON field in the Expo payload, and —
if email ships — into a **`text/plain` part only**, or into a fixed HTML template with the body HTML-escaped.
**It is never concatenated into SQL, into a URL, or into a template that the author also controls.** This is a
direct correction of the existing producer style, which builds copy by `||` concatenation (`058:75-76`).

**C-A4 — The title is not author-supplied.** It is generated: *"Update from {{venue_name}}"*, using the approved
`catalog.venue.name`. T3 dies here — the author has no surface on which to write "Snatch It Security Alert".

**C-A5 — The deep-link target is derived from `subject_id`.** `target_kind='announcement'`,
`target_id=announcement_id`. §4.4 N-DL-3. Nothing in the text can influence where a tap lands.

**C-A6 — Sender identity is unremovable.** Every rendering prefixes the venue name. The copy cannot present itself
as coming from the platform.

**C-A7 — Announcements are `ON`, not MANDATORY (§2.2).** The one broadcast channel an attacker can reach is
precisely the one a user must be able to switch off. Operational notices that genuinely must reach everyone
(`event_time_changed`, `event_cancelled`, …) are **separate, MANDATORY, platform-authored** types with no
free-text field — so a venue can neither smuggle an operational notice through this path nor have a real one
silenced by an announcement opt-out.

### 7.3 Who may send

Two distinct authorities, deliberately split:

- **Draft** — `venue_manager`, `org_owner`, `org_admin`, **and `marketing`**.
- **Approve / release** — `venue_manager`, `org_owner`, `org_admin`. **Never `marketing`.**
- **Nobody else.** `box_office`, `scanner`, `org_finance`, `promoter_manager`: no.

**Why marketing may draft but not send.** O-2 gives `marketing` no custody or money authority. An announcement
reaches a person *because of a ticket they hold* — the audience is derived from the custody ledger. Releasing one
is therefore an exercise of custody-derived reach, which is exactly the authority marketing does not have. Writing
the words is not. (`CONFLICT-4`: `marketing` has no ratified enum label; this binds the concept.)

**Dual control above a blast-radius threshold.** If `recipient_count > notify.announcement_dual_control_threshold`
(seed 500), release requires a **second, distinct principal** holding an approve-authorised role. Same shape as
C39's comp step-up and C15's dual-controlled merge. **A single compromised credential then cannot blast a
stadium** — the direct mitigation for T6.

**Step-up re-authentication on release.** `INFERENCE / dependency:` the platform has no step-up primitive today;
this is a requirement on the O-2/O-4 role agent, recorded as O-N5.

### 7.4 Rate limiting — per subject, not just per user

| Limit | Value (seeded in `catalog.platform_config`) | Enforced |
|---|---|---|
| Per `(venue, event_session)`, lifetime | `notify.announcement_max_per_session` = **3** | counted over `notify.announcement` rows **inside the RPC** |
| Minimum interval for the same session | `notify.announcement_min_interval_seconds` = **1800** | same |
| Per venue per 24 h | **10** | `check_rate_limit(actor_uid, 'announcement_send', 10, 86400)` — **fail-closed** (`021:60-64`) |
| Global kill switch | `notify.announcements_enabled` | checked first; support can stop the world |

**The per-subject limits are counted over rows, not over `check_rate_limit`, and that matters:** `check_rate_limit`
is keyed `(user_id, action)` (`021:43-45`), so two managers at the same venue would each get a full quota and
together double the blast. The cap must live on the *subject*. `check_rate_limit` is the second layer, not the
first.

### 7.5 The hold window, and the truth about revocation

**A push notification cannot be recalled. Once Expo accepts the message it exists on the device permanently.
Deleting the row afterwards changes only the in-app copy.** This spec states it, the UI must state it, and the
design is built around it rather than pretending otherwise.

**Therefore: a mandatory hold.** `notify.announcement.send_after = now() + notify.announcement_hold_seconds`
(seed **300 s**, floor 120 s). The drainer will not expand a row before `send_after`. During the hold, the author
or any approve-authorised peer may **cancel** — `state='cancelled'` — and nothing leaves the database.
This converts *"cannot be recalled"* into *"can be recalled for five minutes"*, which is where nearly every real
mistake is caught. The composer shows a live countdown and a single prominent **Cancel** control.

**After the hold, revocation is partial, and the UI must say exactly which part.**
`notify.revoke_announcement()` sets `state='revoked'` and:

| Effect | Reality |
|---|---|
| in-app centre entries | replaced with *"This message was withdrawn by {{venue_name}}."* |
| `notify.delivery` rows still `pending` | → `suppressed`, reason `announcement_revoked` |
| **push notifications already delivered** | **cannot be removed. They stay on the device forever.** |
| the `notify.announcement` row | never deleted (GP-2); `state='revoked'` with actor and reason |

The composer states this **before the send control is enabled**, in product language:
*"Once this sends, it can't be taken back from anyone's phone. You have 5 minutes to cancel."*

The actual remedy after delivery is a **correction announcement**, which bypasses the per-session cap when
`is_correction = true` and the actor holds `platform_admin` / `platform_support`. That is the only cap exemption
in the design.

### 7.6 Detection and consequence

- Every recipient can **report** an announcement from the in-app centre — `notify.report_announcement()`, reusing
  the `public.reports` shape and the existing `notify_moderation_event` path (`033:161-219`).
- `notify.announcement.report_count` crossing a threshold **auto-suspends the venue's announcement privilege**
  pending platform review. Suspension is a state on the venue, not a deletion.
- Every announcement writes `kernel.admin_audit` with actor, approver, blast radius, and the body — so a
  post-incident question ("who sent this, who approved it, how many people got it") has a single answer.
- Send, cancel, revoke and suspend all raise Sentry breadcrumbs; a revoke on a delivered announcement raises a
  `captureMessage` — it is, by definition, an incident.

### 7.7 What is deliberately NOT built

No scheduling ("send at 6pm"), no audience segmentation beyond the session, no attachments, no images, no rich
text, no links, no per-recipient personalisation, no A/B testing, and **no email channel for announcements in
MVP** (push + in-app only). Each of these enlarges the attack surface of the one attacker-reachable broadcast
path, and none is required by any spec. `organizer_announcement` is `I P` in §2.2 for exactly this reason.

---

## §8 — Privacy analysis

### 8.1 Ownership change — what the sender learns

The sender initiated the transfer by **exact-match lookup** — *"find recipient by username/phone/email … Privacy:
no bulk directory browsing; exact-match lookup only"* (`PHASE_2_REACT_NATIVE_PRODUCT_SPEC.md:215`) — and confirmed
a recipient card before sending (`:216`). **The sender therefore already knows who the recipient is, and the
notification must reveal nothing beyond it.**

`transfer_accepted` params are exactly `transfer_id, event_title, recipient_display_name` — the same display name
the sender confirmed at send time. **Explicitly excluded:** the recipient's email, phone, legal name, avatar
beyond what the confirmation card already showed, their other tickets, their attendance at anything, whether they
are a new or existing user, and any timing signal about when they opened the app.

`transfer_declined` carries **no reason text** (§2.2). A free-text decline reason forwarded to the sender is a
harassment vector in the wrong direction and an information leak in the right one; the sender learns the outcome,
not the recipient's words.

### 8.2 Ownership change — what the recipient learns

The recipient learns the **sender's display name**, and that is necessary: an unexplained ticket appearing in a
stranger's account is worse than knowing, and Accept/Decline is not a decision anyone can make anonymously.

**Explicitly excluded:** what the sender paid, where the sender obtained the ticket, the sender's other holdings,
the sender's contact details, and the ticket's price history. This is consistent with the redaction the RN spec
already requires of ticket history — *"No prices of prior owners, no PII of prior owners"* (`:205`) — and with
`market.get_ticket_history` being *"the purpose-built owner-scoped redacted read"* while the raw ownership log is
deny-all to clients (`:391`, `PHASE_2_RLS_PERMISSION_SPEC.md:382-407`).

### 8.3 The leak that is easy to miss — the account-existence oracle

If a sender can address a transfer to an arbitrary email or phone and the resulting notifications differ depending
on whether that address resolves to an account, **the transfer flow becomes an account-existence oracle**: send,
observe, learn whether a given person has a Snatch It account. At scale that is an enumeration primitive against
the whole user base.

Mitigations, all required:
- `transfer_sent` copy and timing are **identical** whether or not the address resolves. No "we couldn't find that
  user" in the notification; any such feedback belongs in the synchronous RPC response, gated by the exact-match
  lookup that already exists.
- The pending state looks the same in both cases.
- `check_rate_limit(sender, 'p2p_transfer_create', …)`, fail-closed.

### 8.4 Lock-screen exposure — the third-party reader

A push notification is read by whoever is holding the phone. A body reading *"Alice Chen sent you 2 tickets to
Bad Bunny — Miami, Sat 9pm"* discloses an identity, an event, an attendance and a date to a shoulder-surfer, a
partner, or a thief.

**Rule N-P1 — the push body for custody and money types carries no counterparty name and no money amount.**
`ownership_changed`, `transfer_received`, `transfer_accepted`, `payout_released`, `payout_failed`,
`refund_completed`, `listing_sold` render on the wire as, e.g., *"You received a ticket"* / *"Your refund is
complete"*. The name and the amount live in the **in-app body**, behind device unlock and an authenticated
session. Because §5.2 makes push and in-app **different template rows**, this costs nothing structurally.

`INFERENCE:` iOS `interruptionLevel` and `relevanceScore` are presentation hints, not privacy controls, and are
not relied on anywhere in this design.

### 8.5 What a notification payload may never contain

| Never in `params`, `payload`, or any rendered string | Why |
|---|---|
| Email addresses, phone numbers, street addresses | not needed by any type in §2.2 |
| Full PAN, bank account numbers, full IBAN | only `destination_last4`, and only in-app |
| The signed credential, a QR token, `credential_version` as user-facing copy | N-DL-4: a notification link may never carry a secret |
| Any prior owner's identity, price, or acquisition route | RN `:205` |
| Cause-codes, `resale_state`, `market_sale` ids and the rest of the forbidden vocabulary | RN product-language rule `:13` |
| A recipient list | §2.4 |
| Another venue's or org's data in a staff notification | scope-role union only, fail-closed |

### 8.6 Staff notifications and attendee privacy

`staff_low_inventory`, `staff_sales_digest` and `staff_door_anomaly` carry **counts and aggregates only** — never
attendee identities. This matches the dashboard's own column-scoping rule, where the attendee read is
*"column-scoped by role (finance roles get money columns without contact detail; `venue_door` is refused
outright)"* (`PHASE_2_VENUE_DASHBOARD_PRODUCT_SPEC.md:1128`). A notification must never become the side channel
that hands a finance role the contact details the attendee list withholds.

### 8.7 External-rail asymmetry (existing, unchanged)

`VERIFIED`: on the external rail the buyer supplies `delivery_email` / `delivery_phone`
(`011_v1_transfer_enhancements.sql:71-72`, set by `set_transfer_delivery_info`, `:124-167`) and the seller reads
them — necessarily, because the seller performs the transfer off-platform. **Phase 2 does not widen this.** The
existing seller-facing notifications carry only `transfer_id` in metadata (`058:186, :195`), which is correct, and
no new type adds buyer identity to a payload. **The native rail needs none of it**, which is one of the quieter
privacy wins of Rail A and worth stating: a native transfer moves custody without either party learning a contact
detail.

### 8.8 Retention and erasure

`notify.notification` is a **derived projection**, not a source of truth — CDM §1.6: *"Derived from events; never a
source of truth"* (`:252`). Consequences:
- It carries `recipient_id` (an identity uuid) and ids; **PII lives in params only as display names**, which
  C15's crypto-shred model treats as vault-resident and re-renderable.
- A retention policy may compact it. C48 requires that *"outbox compaction respects a retention floor for
  canonical inputs"* and that a projection whose only inputs are ephemeral is either rebuildable or
  **explicitly marked non-rebuildable** (`SNATCH_IT_DOMAIN_ARCHITECTURE.md:1255`).
  **This spec marks `notify.notification` and `notify.delivery` NON-REBUILDABLE** once the outbox is compacted
  past their inputs, and excludes them from the "projections are disposable" claim. Retention values are O-N9.
- Account deletion already cascades `push_tokens` and `notification_preferences`
  (`supabase/functions/delete-account/index.ts:218`); `notify.notification.recipient_id → auth.users ON DELETE
  CASCADE` extends the same behaviour, matching `040:67`.

---

## §9 — pgTAP assertion list (described; **no SQL written by this spec**)

44 assertions in nine families. Each names what must be true and what failure it catches. Design-only: this is the
list an implementing engineer writes tests from.

### A. Mandatory-class enforcement (the §3.3 guarantee) — 6

| ID | Assertion | Catches |
|---|---|---|
| N-A1 | Inserting a `notify.preference` row for **any** type whose registry `delivery_class = 'mandatory'` **fails**, for every one of the 24 mandatory keys, as `service_role` | the whole §3.3 mechanism |
| N-A2 | The same insert fails as `postgres` (superuser) — a CHECK binds every role | a "just use service_role" workaround |
| N-A3 | `UPDATE notify.notification_type SET delivery_class='mandatory'` **fails** while any preference row exists for that key | silent reclassification |
| N-A4 | After deleting those preference rows the same `UPDATE` **succeeds**, and no orphan rows remain | the cascade path is usable |
| N-A5 | `notify.channel_enabled()` returns `true` for every mandatory `(type, channel)` **even when a preference row is force-inserted by disabling the constraint** | the resolver's step-3 early return |
| N-A6 | `notify.set_preference()` on a mandatory key raises `40003`, and the table is unchanged | the second of the two layers |

### B. Idempotency — the three keys (§4.2) — 7

| ID | Assertion | Catches |
|---|---|---|
| N-A7 | Two `notify.emit_event` calls with the same `(event_type, event_key)` yield **exactly one** `notify.outbox` row | producer replay |
| N-A8 | Draining the same envelope twice yields **exactly one** `notify.notification` row per recipient | the at-least-once contract, C12 |
| N-A9 | **`refund_completed` specifically:** replay the webhook branch 5× → `count(*) = 1` for `dedupe_key = 'refund_completed:<id>'` | the named support incident |
| N-A10 | Fanning out the same notification twice yields **exactly one** `notify.delivery` row per channel | hop-4 duplication |
| N-A11 | A claimed delivery whose lease has not expired is **not** re-claimable by a second dispatcher | double-send inside the lease |
| N-A12 | `notify.sweep_scheduled()` run twice over the same window produces **zero** additional notification rows, and the count matches the ticket count exactly once | the fan-out replay question (§4.5) |
| N-A13 | Running the sweep with the advisory lock **held by another session** is a clean no-op that leaves state untouched | the `0600:115-117` pile-up guard |

### C. Recipient derivation (§2.4) — 5

| ID | Assertion | Catches |
|---|---|---|
| N-A14 | No `notify.*` function's body contains a `SELECT` over `auth.users` outside the four sanctioned forms (`pg_get_functiondef` inspection) | ad-hoc audience widening |
| N-A15 | No `notify.*` RPC accepts an array-of-uuid recipient parameter (signature inspection over `pg_proc`) | a caller-supplied recipient list |
| N-A16 | An announcement expansion returns **only** current holders of `active` atoms for its `subject_id`; a ticket transferred between schedule and expansion notifies the **new** holder and not the old | stale audience |
| N-A17 | `staff_payout_failed` reaches the `[org_finance] ∪ [org_owner]` union, and an `org_owner`-only member **does** receive it | `CONFLICT-5` — inheritance is prose, not a predicate |
| N-A18 | An unresolvable org/venue scope yields **zero** recipients and a non-null `last_error`, never a broadcast | fail-open on scope resolution |

### D. RLS and grants (§6.2) — 7

| ID | Assertion | Catches |
|---|---|---|
| N-A19 | `authenticated` cannot `SELECT` another identity's `notify.notification` row | the core boundary |
| N-A20 | `authenticated` cannot `INSERT` into `notify.notification` under any policy | client-forged notifications |
| N-A21 | `authenticated` can `UPDATE (read_at)` and **cannot** update `title`, `body`, `params`, `type_key`, `target_kind` or `dedupe_key` on its own row | the `040:90-99` column-grant lesson |
| N-A22 | `anon` holds **zero** privileges on every `notify` table | default public-schema grants leaking in |
| N-A23 | `notify.outbox`, `notify.delivery`, `notify.schedule`, `notify.identity_channel_state`, `notify.template`, `notify.notification_type` each have RLS enabled and **zero** policies | the `0600:91-92` posture |
| N-A24 | `DELETE` is denied to `anon` and `authenticated` on every `notify` table (GP-2) | row removal instead of state transition |
| N-A25 | A `venue_manager` of venue A cannot read venue B's `notify.announcement` rows | cross-tenant leak |

### E. Function security posture — 5

| ID | Assertion | Catches |
|---|---|---|
| N-A26 | Every `notify.*` function is `SECURITY DEFINER` with a **pinned non-empty `search_path`** (the `0660` rule) | search-path hijack |
| N-A27 | Every internal `notify.*` function has `EXECUTE` revoked from `PUBLIC`, `anon`, `authenticated` and granted only to `service_role` (`057:90-91`, `067`) | privilege leak |
| N-A28 | Consumer RPCs are granted to `authenticated` and **not** to `anon` | `0552`-class regressions |
| N-A29 | `notify.enqueue` and `notify.emit_event` **never raise**: injecting a constraint violation leaves the caller's transaction committed and the parent row present | §0.3 rule 1, the `057:80-86` contract **AMENDED `OR-14` (R2, 2026-08-29): this assertion now binds `notify.enqueue` and the BEST-EFFORT `notify.emit_event` only; its counterpart for `notify.emit_event_required` asserts the OPPOSITE — a failed envelope RAISES and the producer transaction aborts.** |
| N-A30 | Every producer trigger body contains its own `EXCEPTION WHEN OTHERS` (the second layer, `058:95-97`) | single-layer regressions |

### F. The event envelope (C12) — 4

| ID | Assertion | Catches |
|---|---|---|
| N-A31 | Every `notify.outbox` row has non-null `sequence`, `causation_id`, `correlation_id` | C12's stated envelope guarantees (`CDM:606`) |
| N-A32 | `sequence` is strictly monotonic per `(aggregate_kind, aggregate_id)` with no gaps within a transaction | ordering claims |
| N-A33 | A handler that raises marks **only that envelope** `dead` and the rest of the batch still drains | poison-message head-of-line blocking (C49) |
| N-A34 | The outbox row is written **after** every money/custody row in the same transaction (lock-order conformance) | a new deadlock class |

### G. Deep links and targets (§4.4) — 4

| ID | Assertion | Catches |
|---|---|---|
| N-A35 | `target_kind` admits **only** the closed set; an arbitrary string is rejected by CHECK | N-DL-1 |
| N-A36 | No new (non-legacy) `notify.notification` row has a non-null `link` | the URL column creeping back |
| N-A37 | `notify.resolve_web_link()` output always satisfies `safeInternalPath`'s two regexes and never begins `/auth/` (`redirect.ts:17-19`) | open redirect on the web surface |
| N-A38 | Every registry row's `target_kind` is in the closed set and every type in §2.2 has one | orphan push types (D-13) |

### H. Announcements (§7) — 5

| ID | Assertion | Catches |
|---|---|---|
| N-A39 | A body containing `http://`, `https://`, `www.` or a bare domain is **rejected**; ≥30 adversarial samples incl. unicode-homograph and whitespace-split variants | T2 phishing |
| N-A40 | A body containing a control character or exceeding 500 chars is rejected | T1 injection |
| N-A41 | `notify.approve_announcement` **fails** for a marketing-concept principal and succeeds for `venue_manager` | §7.3 authority split |
| N-A42 | The 4th announcement for one session is rejected, and a 2nd within `min_interval_seconds` is rejected — **even from a different staff user of the same venue** | §7.4's per-subject-not-per-user rule |
| N-A43 | Expansion of an announcement before `send_after` produces zero notifications; cancelling during the hold leaves the count at zero permanently | §7.5 hold window |

### I. Copy and privacy — 1

| ID | Assertion | Catches |
|---|---|---|
| N-A44 | No `notify.template` subject or body contains any forbidden term from `PHASE_2_REACT_NATIVE_PRODUCT_SPEC.md:13`, and no `push`-channel template for a custody/money type references `{{counterparty_*}}` or `{{amount*}}` (§8.4 N-P1) | architecture terms and lock-screen leaks reaching users |

---

## §10 — Open questions — owner decisions required

**Blocking (Phase 2 cannot start the notification work without these):**

| ID | Question | Why it blocks | Recommendation |
|---|---|---|---|
| **O-N1** | **What gate is the `notify` schema at?** `CONFLICT-1`: C7 is `Ratified · Gate P · MVP` and names `notify`; all four implementation specs put it at Gate L / DO-NOT-BUILD. | Everything in §6 depends on the answer | Ratify the reading that C7's *eviction* is satisfied vacuously (the leaves were never in the kernel), **and separately** authorise `notify` at Gate P on its own merits — because the venue dashboard already has a binding dependency on it (`§16.5`), which no Gate-L object may have |
| **O-N2** | **Is the outbox in Phase 2 or not?** `CONFLICT-2`: `SNATCH_IT_DOMAIN_ARCHITECTURE.md:1253` promises exactly one outbox table and a drainer on the existing cron; no implementation spec schedules one. | §4 is unbuildable without it; so is every "Async" row in the §6.1 event catalog | Build it. It is one table plus one RPC on a cron that already runs — the constitution's own anti-over-engineering budget |
| **O-N3** | **Does transactional email exist in Phase 2?** D-16: one flag-gated Resend `fetch`, default off, no SDK, no shared helper, auth mail on a personal Gmail relay. Requires a provider account and SPF/DKIM/DMARC on `snatchitapp.com` (audit finding N6). | 19 of the 24 mandatory types name `E` | Decide before build. The design degrades safely (email rows go `suppressed`), but a mandatory money notice with **push as its only channel** is one revoked permission away from unreachable |
| **O-N4** | **Which of the 24 mandatory types are *legally* compulsory, in which jurisdictions?** §3.4 is a product-and-ethics judgement, not a legal opinion. | Determines whether the class is a policy choice or a compliance control | Counsel review. The design is built so the answer changes one registry column |
| **O-N7** | **Migration numbering.** `CONFLICT-3`: specs say 071/071/073; 071–075 are applied. | The first migration cannot be written | **076+.** Also fix the plan's internal 087-vs-088 inconsistency (`:199` vs `:830`) |

**Design decisions with a recommendation, needed before the relevant package:**

| ID | Question | Recommendation |
|---|---|---|
| **O-N5** | Announcement hold-window length, dual-control threshold, and whether a step-up primitive exists to gate release. | 300 s hold, 500-recipient threshold. Step-up is a dependency on the O-2/O-4 role agent |
| **O-N6** | May the `marketing` concept release announcements, or only draft? | **Draft only** (§7.3). Needs owner ratification because it is a product-authority call, not a technical one |
| **O-N8** | Do venue staff notifications share the consumer inbox table or get a separate surface? | One table, `org_id`/`venue_id` columns, one surface per client. Two tables would double every RLS and dedupe assertion |
| **O-N9** | Retention for `notify.notification` / `notify.delivery` / `notify.outbox`, and the C48 retention floor. | 24 months for notifications, 90 days for deliveries, 30 days for drained outbox rows — **and both projections marked NON-REBUILDABLE** (§8.8) |
| **O-N10** | Migrate the 12 legacy inbox types into the registry, or leave them alongside? | Leave them. Register them as `legacy=true` for the preference UI; do not touch working producers |
| **O-N11** | `notify.push_token` as a new table, or additive columns on `public.push_tokens`? | **Extend `public.push_tokens`.** A second token table creates a split-brain during migration and C7's eviction is satisfied either way. Flagged because C7 literally says "into their own schema" |
| **O-N12** | Quiet hours for non-mandatory push? | Not in MVP; the `next_attempt_at` machinery already supports adding it |
| **O-N13** | `security_email_changed` via a `sha256(auth.users.email)` mirror sweep? | Not in MVP. `0600:9-20` refused it on evidence; the sound path is named there and should be built deliberately, not assumed |
| **O-N14** | Promoter attribution as a digest rather than per-order? | Yes, matching the staff sales rule. Not in MVP |
| **O-N15** | Universal Links / App Links (AASA + `assetlinks.json`)? | Required before any notification target is more sensitive than navigation. Until then N-DL-4 binds |

**Cross-agent dependencies (not owner decisions, but blocking on another deliverable):**

- **`CONFLICT-4`** — the plane-scoped role enums. §2.5 binds concepts; `box_office`, `marketing`,
  `promoter_manager` and `scanner` have no ratified label, and `is_sensitive` per role label is assumed by
  §2.2 Group S.
- **`CONFLICT-5`** — org-role inheritance for money actions. Already flagged by the venue-dashboard spec
  (`:1158-1159`); §2.4 works around it with an explicit union, but the underlying authority question is open.
- **Δ-N1** — `catalog.event_session.session_version`. **Correctness-blocking** for repeated time/venue changes.
- **Δ-N2** — `kernel.identity_ext.locale`.

---

## Appendix A — The six hard questions, answered in one line each

| # | Question | Answer | Full treatment |
|---|---|---|---|
| A1 | Organizer announcement as an injection vector | The audience is derived from custody and never supplied; the title is generated, not authored; the body is plain text with **no URLs at all** and is a bound parameter at every hop; `marketing` may draft but not release; dual control above 500 recipients; 3 per session, 30 min apart, per-**subject** not per-user. **A delivered push cannot be recalled** — so a mandatory 5-minute hold window converts "cannot recall" into "can cancel", and post-delivery revocation is honestly described as partial (in-app text replaced, undelivered rows suppressed, delivered pushes permanent). | §7 |
| A2 | Mandatory vs preference | 24 of 40 types are MANDATORY: money moving to/from the user, account-security state, custody change, entitlement viability, the transaction record. Enforcement is **declarative DDL** — a composite FK `(type_key, delivery_class)` plus `CHECK (delivery_class <> 'mandatory')` makes the preference row *unrepresentable*, binds superusers and `service_role` alike, and turns reclassification into a forced, failing migration. The resolver's mandatory branch returns before the preference table is read. **Legal compulsion is O-N4** — §3.4 is an ethics judgement, not counsel. | §3.3, §3.4 |
| A3 | Duplicate financial notifications | Three keys, three layers. **The boundary is hop 3 — the notification row — keyed `refund_completed:<kernel_refund_id>`**, absorbed by a partial `UNIQUE(dedupe_key)` + `ON CONFLICT DO NOTHING` (the `057:50-52` construction). Not the envelope: C12 promises at-least-once and refuses exactly-once. Not the delivery attempt: a retry after a 5xx is a duplicate *attempt*, not a duplicate *fact*. Honest limit: a dispatcher dying between Expo's 200 and the `sent_at` write can re-buzz the device — both banners open the same single row, and for mandatory money types a rare duplicate beats a rare miss. | §4.2 |
| A4 | Ownership change and privacy | The sender learns **nothing new** — they chose the recipient by exact-match lookup and confirmed a card, so `transfer_accepted` echoes only that display name; declines carry no reason text. The recipient learns the sender's display name (necessary and unavoidable) and nothing about price, provenance or contact details. The leak that is easy to miss is the **account-existence oracle**: `transfer_sent` copy and timing must be identical whether or not the address resolves. Lock-screen rule N-P1: no counterparty name and no amount in any custody/money push body. | §8.1–§8.4 |
| A5 | Event reminder / door time at scale | A **sweep**, not a trigger — there is no per-ticket state change. `notify.schedule` + `notify.sweep_scheduled()` on the 5-minute cron, using the traced `0600` shape: `pg_try_advisory_xact_lock` early-return, `FOR UPDATE SKIP LOCKED` batch claim, a **set-based cursor-bounded `INSERT…SELECT…ON CONFLICT DO NOTHING`** capped at 5 000 per tick, and a watermark that advances only on success. **If it runs twice**, three guards catch it and only the third is load-bearing: `UNIQUE(dedupe_key)` on `event_reminder_24h:<session_id>:<ticket_id>` — the same argument `0600:27-29` makes about its own lock, *"correctness does not depend on the advisory lock."* Every failure mode collapses to the same no-op. | §4.5 |
| A6 | Deep links | **There is no URL to attack.** A closed `target_kind` enum + a uuid; the web path is composed server-side and `safeInternalPath` stays as defence-in-depth. Fail-safe: the client never navigates on the notification's word — it opens the screen, which loads the target under RLS. Because GP-2 forbids row deletion, "gone" is almost always "not visible to you", so both render **one identical string** rather than leaking existence. And because only a custom scheme is configured (no AASA, no `assetlinks.json`, and a documented co-install hijack risk), **N-DL-4: a notification link may never carry a secret, token, or one-time action** — tapping may only ever navigate. | §4.4 |

---

## Appendix B — Classification index

| Classification | Elements |
|---|---|
| `NO SCHEMA CHANGE` | `public.notifications` + its RLS/grant posture · `public.enqueue_notification` · `public.notification_preferences` · `public.transfer_notifications` · `public.rate_limits` / `check_rate_limit` · the `pg_net`+Vault trigger transport · the `pg_cron` heartbeat · `send-push`, `notify-transfer`, `notify-report` · `safeInternalPath` · all 12 legacy inbox types and 15 legacy push types · the 4 *extends* rows in §2.2 |
| `ADDITIVE SCHEMA CHANGE` | the `notify` schema (9 tables) · 67 registry rows · `public.push_tokens` +4 columns · `catalog.event_session.session_version` (Δ-N1) · `kernel.identity_ext.locale` (Δ-N2) · 5 `catalog.platform_config` seeds · 2 new pg_cron jobs |
| `SPEC CORRECTION` | `CONFLICT-1` `notify` gate · `CONFLICT-2` the missing outbox · `CONFLICT-3` migration numbering (076+, and 087-vs-088) · `CONFLICT-4` role vocabulary · `CONFLICT-5` org-role inheritance · Edge spec `:75` "reuse `send-push`" · `send-push`'s single-secret auth (D-7) · the `058` `link`-by-concatenation pattern |
| `NEW RPC` | `notify.emit_event` · `enqueue` · `channel_enabled` · `drain_outbox` · `sweep_scheduled` · `claim_deliveries` · `record_delivery_result` · `get_inbox` · `get_unread_count` · `mark_read` · `mark_all_read` · `dismiss` · `get_preference_matrix` · `set_preference` · `register_push_token` · `revoke_push_token` · `resolve_web_link` · `report_announcement` · `draft_announcement` · `preview_announcement_audience` · `approve_announcement` · `cancel_announcement` · `revoke_announcement` — **23** |
| `NEW EDGE FUNCTION` | `notify-dispatch` · `notify-receipts` (+ shared modules `_shared/notify-auth.ts`, `_shared/email.ts`) |
| `NEW RN SURFACE` | notification centre · unread badge · foreground receipt listener · `target_kind` router with an `else` branch · pending-target cold-start replay · token register/revoke via RPC · preference screen with always-on mandatory rows |
| `NEW DASHBOARD SURFACE` | staff preference surface (§16.5) · announcement composer with blast-radius count, hold countdown and irrevocability warning · announcement history/revoke |

---

*End of `docs/architecture/PHASE_2_NOTIFICATIONS_SPEC.md`. Design-only: no SQL, no migrations, no implementation
code. Every `CONFLICT-n` is reported, none is silently resolved; every one reappears in §10 as an owner decision.*

