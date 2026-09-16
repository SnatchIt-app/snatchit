# Notification inventory and gap matrix (C, 2026-09-16)

**Source of truth:** the combined stack commit `9bef640` (`release/production-gate-20260918`; migrations 000–135 plus the timestamped 2026-09 files, `supabase/functions/**`, `app/**`, `src/**`, `tests/**`, `supabase/tests/**`). Every claim below was read from that source in two sweeps on 2026-09-16, not from memory; file:line citations are relative to the repo root. "Not found in source" means exactly that. **Nothing in this document adds a notification or changes delivery behaviour; it inventories and proposes.**

**Environment facts that colour "can it deliver":** production carries the ledger through 135's predecessors (A's release records); the sandbox now carries 131 (ledger 137) with 132–135 applying in the B2 window; the sandbox Vault holds **no `service_role_key`**, and the owner deferred adding one (2026-09-16), so **no database-triggered push can leave the sandbox** and b2 push-delivery verification is recorded as blocked until the key is deliberately approved.

---

## 0. How to read this

There are **four independent notification planes plus an ops-detection plane**, with no shared tables, dedupe keys, templates or preferences (stated in source: `supabase/migrations/058_notification_producers.sql:3-6`):

| Plane | Storage | Transport | Reaches a device today? |
|---|---|---|---|
| **A** legacy push | `public.transfer_notifications` (dedupe only) | DB trigger → pg_net → edge (`notify-transfer`, `notify-report`, `enforce-transfer-expiry`, `stripe-webhook`) → `send-push` → Expo | **Yes** — the only plane that does (where Vault `service_role_key` + `project_url` exist) |
| **B** legacy in-app inbox | `public.notifications` | none; read by the web inbox (`057:60-64`) — **no mobile inbox screen exists** | in-app only |
| **C** Phase-2 notify plane | `notify.outbox` → `notify.notification` / `notify.delivery` | **parked**: no caller for `notify.claim_deliveries` / `record_delivery_result` anywhere; lease config seeded `null` so the claim verb fails closed (`092:780-785`, `092:1187-1194`) | **No** — every push delivery row stays `pending` |
| **D** device possession (128/131/135) | `notify.push_token_challenges`, `public.push_tokens` | `notify.issue_push_token_challenge` → pg_net → `send-push` (token-addressed) | Yes where Vault `project_url` + service key exist |
| **E** ops console | `ops.case`, `ops.alert`, `ops.daily_summary` | `portal_only` | internal only |

**Client-side, the mobile app:** presents every titled notification as a banner + list entry + sound, foreground and background, with no category filter (`src/providers/NativeAppShell.native.tsx:47-55`); routes taps by `data.type`/`transferId`/`listingId` (`:223-252`); fires **four local notifications** from the listing screen (§2); has one `addNotificationReceivedListener`, used only for the possession challenge (`src/hooks/usePushToken.ts:370-372`); and has **no inbox, no badge, no unread count** (not found in client source).

Field key used in every entry: **Trigger · Channel · Sender/table · Recipient · Preference · Copy · Sandbox key · Offline/denied/expired/dup/retry · Lock screen · Tests · Gaps.**

---

## 1. Event inventory

### 1.1 Outbid

**A2 — push `notify_outbid` (server): INERT.**
- Trigger: `on_new_bid_notify AFTER INSERT ON public.bids` → `public.notify_outbid()` (`070:77-78`; body `054:59-117`).
- Channel: push only. Sender: posts to `<app.settings.supabase_url>/functions/v1/send-push` (`054:98-109`); writes no rows.
- Recipient: previous top bidder by `ORDER BY amount DESC LIMIT 1`, self skipped (`054:90-97`).
- Preference: none honoured.
- Copy: title `You've been outbid!`; body `Someone placed a higher bid on <listing title|a listing>. Bid again now!` (`054:106-107`).
- Sandbox key: reads GUCs `app.settings.supabase_url` / `service_role_key`, both recorded unset (`054:12-15`); 133 did **not** convert this trigger to Vault (`133:10-12`). **Permanently a no-op in every environment.**
- Behaviour: wrapped `EXCEPTION WHEN OTHERS → RAISE WARNING` so a bid is never aborted (`054:111-112`, the reason the migration exists). No dedupe, no retry.
- Lock screen: would be visible.
- Tests: none reference `notify_outbid`.
- Gaps: dead path; equal-amount mis-attribution noted in its own header (`054:41`).

**B2 — inbox `outbid`.** Trigger `trg_notify_bid_inbox` on bid insert (`058:101-103`); recipient previous top bidder; dedupe `outbid:<bid_id>`; title `You have been outbid`; body `Your bid on <title|a listing> was beaten. Current bid is $<amount>.`; link `/listing/<id>` (`058:83-93`). Web-only visibility. No preference. No test.

**Client-local — `outbid`.** `src/screens/ListingDetailScreen.tsx:511-521`: fires only on a winning→outbid transition observed **while the listing screen is mounted**, with a Warning haptic and a 4 s in-screen banner. Title `You've been outbid!`; body `Someone bid higher on <event_name|this listing>. Tap to bid again.`; data `{listingId, type:'outbid'}`. Ignores `notify_outbid`; ignores permission state (failure swallowed `src/utils/notifications.ts:25-27`). Tap → `/listing/<id>`.
- Preference toggle **exists but is read by nobody**: `notification_preferences.notify_outbid` default true (`000:920-928`; only `app/settings/notifications.tsx:84,113` touches the table).
- Tests: `tests/listing-detail-state.test.ts:361-386` pins the handler survives; no copy/condition test.

### 1.2 Auction ending soon

- Server: **not found in source** on any plane (no producer, no template).
- Client-local: `ListingDetailScreen.tsx:610-647` — a JS `setTimeout` to the 5-minute mark, **only while the screen is mounted and only if the user has bid**; once per mount. Title `⏰ Auction Ending Soon`; body `<event_name> ends in less than 5 minutes!`; type `auction_ending_soon`. Not an OS-scheduled notification (`scheduleNotificationAsync` with a time trigger: not found).
- Preference `notify_auction_ending` (default true) exists and is read by nobody.
- Lock screen: only if the app is foregrounded on that screen at that moment.
- Tests: none. Gap: the toggle names a notification that does not exist server-side.

### 1.3 Auction won / lost

**B3 — inbox `auction_won`.** `trg_notify_auction_won_inbox AFTER UPDATE OF winner_user_id ON listings` (`058:123-126`), set by `auto_finalize_expired_auctions` (cron `014`) or `finalize_auction`. Recipient winner; dedupe `auction_won:<listing_id>`; title `You won!`; body `You won <event_name|the auction>. Complete checkout to secure your tickets.`; link `/checkout/<id>` (`058:111-116`). No push on any plane.
**Auction lost:** **not found in source** on any plane, though `notify_auction_lost` (default false) exists (`000:925`).
**Client-local:** won `ListingDetailScreen.tsx:654-689` (`You Snatched It 🎉` / `You won <event>. Complete checkout to claim your ticket.`), lost `:694-709` (`Auction Ended` / `The auction for <event> has ended. Better luck next time!`), both once per mount, only while the screen is open. Tests: none for copy/conditions.

### 1.4 Reservation / hold expiry

- Server: **not found in source** on any plane. Preference `notify_reservation_exp` (default true) exists and is read by nobody.
- Client: in-screen copy only — `Finish checkout before the hold expires.` (`src/lib/listing/detailState.ts:220`) and the checkout hold countdown (`src/screens/checkout/CheckoutNative.tsx:794`). No notification, no tap route.

### 1.5 Listing sold / payment / checkout

**A9 — push `payment_intent.succeeded`.** `supabase/functions/stripe-webhook/index.ts:329-352`, after `settled.outcome === 'settled'`; idempotent via the webhook-event lease (`claim_stripe_webhook_event`, `064`) so it fires once per event. Buyer: `Payment Confirmed!` / `Your payment for <title> was successful. Waiting for seller to transfer the ticket.` data `{listingId, type:'payment_succeeded', transferId?}`. Seller: `Your ticket sold!` / `Send the transfer now for <title>.` data `{type:'ticket_sold'}`. Bearer for `send-push` is the **edge runtime** `SUPABASE_SERVICE_ROLE_KEY` (`:126`), not Vault — the one Plane-A path that does not depend on the sandbox Vault key. Not awaited; no retry. Lock screen: visible; no amount. Tap: buyer → `/transfer/receive/<id>`, seller → `/transfer/send/<id>`. Tests: `tests/settlement-webhook.test.ts:92-182` (two pushes only on `settled`; none on refund-before-success / unknown / mismatch); no copy assertion. **Gap:** `payment_failed` / `canceled` send nothing (only two `sendPush(` sites in the file).

**B4 — inbox `listing_sold`** (`058:139-144`): on transfer insert, seller, dedupe `listing_sold:<transfer_id>`, `Your tickets sold - send them now` / `<title|Your listing> sold. Send the tickets within 24 hours.`, link `/transfer/send/<id>`. **B5 `buyer_info_needed`** (`058:146-151`).

**C1 — Phase-2 `purchase_confirmed`** (native rail): `market.finalize_market_sale` → `notify.emit_event` (`088:1339-1342`); mandatory, channels `{push,email}`; in_app `Purchase confirmed` / `Your payment of {{amount}} for {{event_title}} was received.`; push body without amount (`092:288-289`). **Cannot deliver** (plane parked); email row born `suppressed/channel_unavailable`. Tests `157` E.

Preference: `notify_listing_sold` (default true) exists, read by nobody. Sandbox key: A9 no (runtime key); B4/B5 none; C1 n/a.

### 1.6 Refund

- **A7 — push, transfer expiry refund** (cron `enforce-transfer-expiry` every 2 min, Phase 1: `enforce-transfer-expiry/index.ts:638-662`). Buyer `Refund Processed` / `The seller didn't send the ticket for <title> in time. Your full refund has been issued.` `{type:'transfer_expired_refund'}`; seller `Transfer Expired` / `You didn't send the ticket for <title> in time. The buyer has been refunded.` `{type:'transfer_expired_seller'}`. Fire-and-forget, **no dedupe row** (the refund itself is idempotent). Cron requires Vault `project_url` (`133:362-383`); the edge calls `send-push` with the runtime key. Tap: **unrouted** (lands on the listing only if `listingId` is present, which it is). Tests: cron auth only.
- **C4 `refund_requested`** (REQUIRED, three producers in `catalog.cancel_event`'s cascade, `088:1670-1777`), **C5 `refund_request_expired`**, **C6 `refund_request_cancelled`**: mandatory; in_app copy carries the amount, push copy does not (`092:308-321`). **Cannot deliver** (plane parked). Registered but **no producer**: `refund_submitted`, `refund_request_approved`, `refund_request_parked`, `refund_request_denied`, `refund_completed`, `refund_failed` (`092:254-261`).
- Client: tap route for `transfer_expired_refund`: no dedicated branch. No preference for refunds anywhere.

### 1.7 Transfer / ticket delivery

- **A3 `transfer_created`** (`034:96-98`, body `133:106-162`) → edge `notify-transfer`: claims `public.transfer_notifications (transfer_id, event_type)` **before** sending; only a real insert authorises the push, and a claim error suppresses it (`notify-transfer/index.ts:54-68`). Seller `Action needed: send the tickets` / `You sold "<event>". Send the tickets now to complete the sale.` `{type:'seller_action'}`; buyer (only when no delivery email/phone yet) `Add your transfer info` / `Add your transfer info so the seller can send your "<event>" tickets.` `{type:'buyer_info_needed'}` (`:139-157`).
- **A4 `tickets_marked_sent`** (`034:101-105`): buyer `Tickets sent — confirm once received` / `The seller sent your "<event>" tickets. Confirm once you've received them.` `{type:'buyer_confirm'}` (`:162-167`).
- **A5/A6 reminders** (cron, `enforce-transfer-expiry` Phase 3): seller `Reminder: send the tickets to complete your sale` (`:1216-1221`); buyer `Reminder: confirm your tickets` / `Confirm your "<event>" tickets — or open a dispute if something is wrong.` (`:1233-1238`); one per transfer ever via the same dedupe table.
- **A8 auto-release**: seller `Payout released` / `Your payout for <title> has been released.` `{type:'auto_release_seller'}`; buyer `Order complete` / `Your order for <title> is complete. If anything is wrong with your tickets, contact support.` `{type:'auto_release_buyer'}` (`:906-922`); no dedupe row.
- **B6–B11 inbox rows** on transfer state changes (`058:171-228`): `buyer_confirmation_needed`, `transfer_viewed`, `transfer_confirmed`, `transfer_disputed` (seller and buyer rows), `payout_released` (`Your payout for <title> is on its way to your bank.`), `order_complete` (`… Enjoy the event!`).
- **C2 `ownership_changed`** (REQUIRED, `kernel.transfer_ticket_ownership`, `088:725-728`): two notifications (acquired / released) with plain-verb `cause_label`s (`092:557-573`); mandatory `{push}`; **cannot deliver**.
- Sandbox key: A3/A4 need Vault `service_role_key` + `project_url` (`133:145`); A5–A8 need Vault `project_url` for the cron. Tap: `seller_action`/`ticket_sold` → send; `buyer_confirm`/`buyer_info_needed`/`payment_succeeded` → receive; `auto_release_*` no branch (listing fallback). Preference: none. Tests: none for the edge copy; `docs/security/TRANSFER_NOTIFICATION_FINAL_AUDIT.md` is an audit.
- Gaps: three wordings for one moment (`payout_released` A8 vs B10 vs C's unproduced template); `transfer_notifications` never cleaned up.

### 1.8 Account deletion

- **C10 `account_deletion_pending`**: `kernel.request_account_deletion` → `emit_event` (`077:1807-1815`); recipient self; mandatory `{push,email}`; in_app `Your account deletion request was received. You can withdraw it from Settings while it is pending.` (`092:346-347`). **Cannot deliver.** Tests `157` J1–J10.
- **C11 `account_deletion_completed`**: `kernel.sweep_deletion_pending` (current definer `20260906130000_…:258-266`); mandatory `{email}` only → the single delivery row is always `suppressed/channel_unavailable` because email does not exist on this plane (`092:277`, `092:459`; asserted intended by `157:J16`). **Undeliverable by construction.**
- Client: the deletion request alert (`Deletion request accepted` + bodies, `app/settings/index.tsx:193-196`), then `signOutAllDevices`. No push, no inbox row on Plane B.

### 1.9 Session expiry / credential change

- Server: **no notification**; 131's triggers revoke push bindings on password change and on the last session ending (`131:128-195`); B12 `security_password_changed` is an inbox row from a 5-minute audit sweep (`075:355-390`, body `0601:18-79`): `Your password was changed` / `The password on your Snatch It account was changed. If this was not you, reset your password immediately and contact support.`, dedupe `auth_pwd:<audit_id>`, watermark + 60-min overlap, advisory lock, no backfill. **No push.** No test. Email change deliberately not shipped (`0600:9-20`).
- Client: login-screen notices, consumed once (`src/lib/auth/sessionEnd.ts:44-49`): expired `Your session expired. Sign in to pick up where you left off.`; password_changed `Password updated. Sign in with your new password.`; credential_change `You were signed out on this device. Sign in again to keep notifications on.` (neutral by design). Marked by the sign-out helper or by the unmarked SIGNED_OUT (CFT-607). **The sign-out → sign-in auth-lock deadlock found on Build 17 today lives on this path** (fixed on `frontend/auth-signout-deadlock @ a046568`; see the backlog).
- Tests: `tests/logout-scope.test.ts`, `tests/session-bound-131.test.ts`, `tests/candidate-recovery.test.ts` (CFT-607), `tests/auth-signout-deadlock.test.ts`.

### 1.10 Device registration

- Server: `public.register_push_token` (current definer `135:146-270`; rate limit 20/600 s; `refreshed`/`registered` stamp `contract_version 2`; cross-account → `challenge_required` v3); `public.revoke_push_token` (`129`); `revoke_all_push_bindings` (`131`); guards on secret hash, session, client delete (`128`, `131`, `135`). No user-facing notification.
- Client: registration decision/backoff/persistence (`src/lib/push/registration.ts`, `registrationStore.ts`), statuses (`registrationStatus.ts`), remedies for only four kinds (`REGISTRATION_REMEDY`, `registration.ts:223-238`); Settings › Notifications banner. **A thrown or hung `getExpoPushTokenAsync` is swallowed with `console.warn` only — no record, no status, no retry** (`usePushToken.ts:196-198`; F-611C-1, fix in progress on `frontend/push-token-fetch-visibility`). `network`, `rate_limited`, `precondition`, `auth`, `unknown` have no remedy copy.
- Sandbox key: none (database only). Tests: `push-registration`, `session-bound-131`, `auth-sign-out`, `logout-scope`, pgTAP `195/196/198/202`.

### 1.11 Device-possession challenge (135, contract v3)

- **D1 silent**: `register_push_token` cross-account branch → challenge row → `notify.issue_push_token_challenge` → pg_net → `send-push` (`135`); payload `{to, _contentAvailable:true, data:{type:'push_token_challenge', challenge_id, nonce}}` (`send-push/index.ts:177-182`); no title/body. 5-minute expiry, 5 attempts, rate limits 5/user and 3/(token,user) per 10 min (`135:249-250`, `135:306-307`; edge namespace `send-push/index.ts:135-159`). Nonce never logged (asserted). Client echoes in the foreground only (no `UIBackgroundModes`, pinned); 60 s cumulative-foreground fallback.
- **D2 visible**: `request_push_token_challenge(p_mode='visible')` → `{title:'Confirm this device', body:'Your Snatch It code is <6 digits>. Snatch It will never ask for this code. Never share this code.', data:{type, challenge_id}}` (`:169-176`); the code IS the nonce.
- Sandbox key: the issuing verb posts only when Vault `project_url` exists (`135:121-122`) and `send-push` checks the runtime key; A's read-back: nothing has ever posted from the sandbox through pg_net → **blocked until the key decision**.
- Behaviour: offline → no push arrives → visible fallback after 60 s foreground; denied permission → no token → no challenge; expired → `challenge expired` refusal, Try again issues a fresh challenge (P3-1); duplicate/replayed push → dropped by phase+id guard; stale nonce after re-issue → `stale_nonce`, free; retry → fresh challenge on Try again.
- **Lock screen: the visible code is shown on the lock screen** — the one secret on a lock screen in the product, mitigated by "never share" and the 5-minute / 5-attempt bound (`docs/release/O3_128_RESIDUAL_DECISION_BRIEF.md:202`; support must never relay a code, `docs/operations/SUPPORT_RUNBOOK_PUSH_TOKEN_UNBIND.md:43`).
- Tests: pgTAP `202` (57), `tests/send-push-challenge.test.ts` (23), `tests/push-proof-v3.test.ts` (22), `tests/push-classifier-migration-guard.test.ts` (17). Device rows DV-V1..V4 (deferred with the key).
- Gap: `PUSH_TOKEN_CONTRACT_V3.md` is cited by `135:4` but absent from the repo at this commit (it lives on A's candidate branch); to be carried onto the stack.

### 1.12 Device rebound / security notice

- **D3 `security_device_rebound`**: on `confirm_push_token_challenge` success with a different previous owner (`135:390-393`) → `notify.enqueue` directly; type has `allowed_channels '{}'` so **zero delivery rows — in-app notification centre only**, by design ("their push is exactly what moved", `135:389`). Subject `A device was re-registered to another account`; body `A device that was receiving your notifications ({{device_name}}) was just registered to another account. If that was you switching accounts on your own phone, nothing to do. If not, sign in on that phone to take it back, then change your password.` (`135:500-504`). Dedupe per token per day. Tests `202:A7, A7b, E3`.
- **Gap:** the previous owner has **no way to see it on mobile** — there is no mobile inbox; the row is visible only in the web notification centre. Contract v2/v3 text was corrected by A to "in-app, not email".
- Also registered with producers: C12 `security_org_role_granted/revoked` (mandatory, cannot deliver). Registered, emitted by three producers, **never drained**: C13 `security_payout_destination_changed` (`093:4437/4605/5187`; no `when` arm in `notify.drain_outbox`, `092:520-732`) — envelopes counted `unmapped` and marked done.

### 1.13 Reports and disputes

- **A10 `report_created`** (`033:227-229`, body `133:164-231`) → edge `notify-report`: push to every admin (`New report filed` / `<target_type> report — reason: <reason>. Review in the admin dashboard.`), to the reporter (`Report received` / `Thanks — our team is reviewing your report. <UNDER_REVIEW_COPY>`), to the reported party (`Under review` / `<One of your listings|Your profile> is being reviewed by Snatch It support. <UNDER_REVIEW_COPY>`); **email via Resend** gated on `EMAIL_ENABLED='true'` (default off) + `RESEND_API_KEY` (`notify-report/index.ts:34-69`, `:133-158`). `UNDER_REVIEW_COPY` = `Snatch It support is reviewing this. Please do not complete any arrangements outside the app — keep all communication and the transfer inside Snatch It so you stay covered.` **No idempotency of any kind; a re-POST re-notifies everyone.** No test. Tap: `admin_report`, `report_ack`, `under_review` **unrouted** on the client.
- **A11 `dispute_opened`** (`033:232-236`): admins `Dispute opened`; parties `Transaction under review` `{type:'dispute_review', transferId, role}` (`:161-180`); tap routed by role. B9 inbox rows for both parties. Gap N5 from the 2026-06 audit still true: a post-payout chargeback never sets `disputed`, so nothing fires (no trigger on `public.disputes`).
- Sandbox key: Vault `service_role_key` + `project_url` (`133:214`); email needs Resend env.

### 1.14 Administrative alerts

- **A12 `signing_invariant_alert`**: cron `monitor-signing-key-invariants` 05:23 → `kernel.check_signing_key_invariants()` (`133:233-356`) → audit row + `notify-report` → admin push `Signing-key invariant alert` / `KMS signing-key monitor: <summary>`, admin email, Sentry. 24-hour dedupe on the alerts array (`133:301-310`); content is words/counts only, never key material. Requires Vault `project_url`; bearer `coalesce(service_role_key,'')`. Tests pgTAP `165`, `200`. Tap: unrouted.
- **E ops console**: `ops.detect_notifications()` opens a `notification_failure` case per failed/dead `notify.delivery` (`117:668-703`); alerts `p1_case`, `webhook_backlog`, `job_failure:*`; `daily_summary` is `portal_only`. Since Plane C never claims, the detector can only fire on `template_missing` or lease exhaustion, neither reachable today. Tests `183` etc.

### 1.15 Registered on Plane C with no producer (17)
`ticket_ready`, `purchase_failed`, `wallet_pass_available`, `payout_released`, `payout_failed`, `staff_payout_failed`, `refund_submitted`, `refund_request_approved`, `refund_request_parked`, `refund_request_denied`, `refund_completed`, `refund_failed`, `event_time_changed`, `event_venue_changed`, `event_postponed`, `security_password_changed` (on this plane), `security_payout_method_added` (`092:240-270`). Templates exist for all (Appendix B of the server sweep); none can deliver.

---

## 2. Cross-cutting facts

| Topic | Fact | Source |
|---|---|---|
| Foreground presentation | banner + list + sound for everything with a title; `shouldSetBadge:false` | `NativeAppShell.native.tsx:47-55` |
| Permission prompt | at the first foreground after sign-in; denied → console only, later a Settings banner with `Open settings` | `usePushToken.ts:87-95`; `app/settings/notifications.tsx:150-164` |
| Android channel | one, `default`, importance MAX | `usePushToken.ts:98-104` |
| Tap routing | typed transfer routes; `listingId` fallback; nine server types unrouted | `NativeAppShell.native.tsx:223-252` |
| Preferences (A/B) | `public.notification_preferences` six toggles, client-writable, **read by no server path** | `000:920-940`; client `app/settings/notifications.tsx:34-41,83-115` |
| Preferences (C) | `notify.preference` honoured by `notify.enqueue`; 28 of 32 types are `mandatory` and not configurable | `092:389-406`, `092:1085-1087` |
| Dedupe | A: `transfer_notifications` on 4 of 12 events; B: `dedupe_key` unique; C: three keys (outbox, notification, delivery) | `034:25-37`; `057:42-51`; `076:186-187`, `092:114,138` |
| Retry | A: none (edges answer 200 on error); C: drain 5× on transient SQLSTATEs, delivery backoff 1m/5m/25m/2h/12h then dead; `device_not_registered` revokes the token | `notify-transfer/index.ts:177`; `092:733-739`, `092:861-924` |
| Email | Plane C: does not exist (zero templates); only `notify-report`'s hard-coded Resend emails, off by default | `092:281-282`, `157:K3`; `notify-report/index.ts:34-69` |
| Sandbox key | DB-trigger pushes (A1, A3–A6, A10–A12, D1/D2) need Vault `service_role_key` and/or `project_url`; A9 uses the edge runtime key; `send-push` itself checks the runtime key | `133:81,145,214,338`; `135:121-122`; `send-push/index.ts:14-25` |
| Liveness predicate | `send-push` filters `is_active = true`; 092 made `revoked_at IS NULL` authoritative — they agree today because every revoke sets both | `send-push/index.ts:269`; `092:184-189` |
| Lock screen | every titled push; the only secret is the visible challenge code | §1.11 |
| Mobile inbox | none; Plane B and D3 rows are web-only | not found in client source |

---

## 3. Gap matrix

Legend: **EXISTS** = in source at 9bef640 and reachable; **PARKED** = in source, cannot deliver; **NEW** = proposed, not in source; **CLIENT-ONLY** = local notification only. Retry/idempotency and acceptance tests are the rules a change would have to meet; none is implemented by this document.

| # | Scenario | Intended recipient | Channel today → proposed | Copy today → proposed | Privacy risk | Retry / idempotency rule | Acceptance test | Status |
|---|---|---|---|---|---|---|---|---|
| G1 | Outbid | previous top bidder | A2 push INERT; B2 inbox (web); client-local only while on the screen → **server push via the tracked producer, honouring `notify_outbid`** | server `You've been outbid!` (dead) / inbox `You have been outbid` / client `You've been outbid!` → one wording | low (listing title only) | dedupe `outbid:<bid_id>`; never abort the bid (054's rule) | pgTAP: one push row per bid, none to self, none when toggle off; device: push arrives off-screen | EXISTS (inbox) + CLIENT-ONLY; push **NEW** (replace 054's stopgap) |
| G2 | Auction ending soon | bidders on the listing | nothing server-side; client timer only while on the screen → **server-scheduled push at T-5 min, honouring `notify_auction_ending`** | `⏰ Auction Ending Soon` / `<event> ends in less than 5 minutes!` → keep, drop the emoji | low | dedupe `ending_soon:<listing>:<user>`; never re-send after the listing closes | pgTAP: one row per bidder per listing; device: arrives with the app closed | **NEW** (toggle exists, nothing behind it) |
| G3 | Auction won | winner | B3 inbox (web); client-local on screen → **push + inbox**, honouring `notify_auction_won` | `You won!` / `You won <event>. Complete checkout to secure your tickets.` | low | dedupe `auction_won:<listing>` (exists) | pgTAP: fires once on winner set; device: tap lands on checkout | EXISTS (inbox) + CLIENT-ONLY; push **NEW** |
| G4 | Auction lost | non-winning bidders | nothing server-side; client-local on screen → **push (default off, per `notify_auction_lost=false`)** | client `Auction Ended` / `… Better luck next time!` → keep | low | dedupe `auction_lost:<listing>:<user>` | pgTAP: default-off users get no row | **NEW** |
| G5 | Reservation / hold expiry | buyer holding a reservation | nothing; in-screen countdown only → **push at T-2 min, honouring `notify_reservation_exp`** | `Finish checkout before the hold expires.` → `Your hold on <event> ends in 2 minutes.` | low | dedupe `hold_expiry:<hold_id>`; suppressed if paid | pgTAP; device with the app backgrounded | **NEW** |
| G6 | Listing sold (seller) | seller | A9 push (`Your ticket sold!`) + B4 inbox + C1 (parked) → keep A9; retire the third wording | three wordings → one | low | webhook lease (exists) | `settlement-webhook.test.ts` (exists) + a copy pin | EXISTS |
| G7 | Payment succeeded (buyer) | buyer | A9 push + B (none) → keep | `Payment Confirmed!` | low; no amount in push | webhook lease | exists | EXISTS |
| G8 | Payment failed / canceled | buyer | nothing → **in-app state + push `purchase_failed` (template exists on C)** | C template `Purchase failed` / `Your payment did not go through.` | low | dedupe on payment intent id | `settlement-webhook.test.ts` negative outcomes → one notification | **NEW** (template PARKED) |
| G9 | Refund (transfer expiry) | buyer, seller | A7 push → keep; **add dedupe row** | `Refund Processed` / `Transfer Expired` | low | `transfer_notifications (transfer_id, 'refund_notified')` | pgTAP: re-running the phase sends nothing twice | EXISTS; dedupe **NEW** |
| G10 | Refund requested / approved / completed / failed (native rail) | buyer | C4–C6 emitted, PARKED; six types have no producer → **decision: park until the dispatcher is authorised, or bridge the three live ones to Plane A** | C templates (amount only in in-app copy) | medium: amounts must stay out of push copy (`157:F9`) | C's three keys + backoff (exists) | `157` E/F (exist) | PARKED |
| G11 | Transfer created / sent / confirm | seller, buyer | A3/A4 push + B4–B8 inbox → keep | as §1.7 | low | `transfer_notifications` (exists) | none today → **add an edge test for the claim-then-send order and copy** | EXISTS; test **NEW** |
| G12 | Transfer reminders | seller, buyer | A5/A6 → keep | as §1.7 | low | exists | cron-auth test exists; copy test **NEW** | EXISTS |
| G13 | Payout released / order complete | seller, buyer | A8 push + B10/B11 inbox (+ C template unproduced) → one wording | three wordings | low | **no dedupe today** → `transfer_notifications (transfer_id, 'released')` | pgTAP double-run sends once | EXISTS; dedupe **NEW** |
| G14 | Ownership changed (native) | new and previous holder | C2 REQUIRED, PARKED | `Ticket ownership changed` / `<cause>. Open the app for details.` | low | C keys | `157:E1-E9` | PARKED |
| G15 | Account deletion pending / completed | self | C10 PARKED; C11 undeliverable by construction; client alert exists → **decide whether completion needs any channel (source says no push for an account that cannot sign in)** | as §1.8 | low | `account_deletion_completed:<id>` once ever | `157:J13-J19` | PARKED / by design |
| G16 | Session expiry / signed out elsewhere | the user on the device | login-screen notice (client) → keep; **no push** | as §1.9 | medium: never name the cause on the shared login screen (K-4) | n/a | `candidate-recovery`, `logout-scope`, `auth-signout-deadlock` | EXISTS (+ deadlock fix pending integration) |
| G17 | Password changed | account owner | B12 inbox (web only) → **push `security_password_changed` (template exists on C)** to every other live device | `Your password was changed. If this was not you, secure your account now.` | medium: send to devices other than the one that changed it; never to a revoked binding | dedupe `auth_pwd:<audit_id>` (exists) | pgTAP on the sweep (none today) + device row | EXISTS (inbox) ; push **NEW** |
| G18 | Device registration failure | the user on the device | Settings remedy for 4 kinds; token-fetch failure invisible → **persist + show pre-register failures with Try again** (F-611C-1) | REGISTRATION_REMEDY → add `token_fetch`, `token_timeout`, `storage`, `network`, `rate_limited` | none | cold flag kept; in-process backoff | `push-token-fetch-visibility` tests + DV row | in progress |
| G19 | Possession challenge (silent / visible) | the device claiming a token | D1/D2 → keep | as §1.11 | **high on the visible path (code on the lock screen)** — bounded, "never share", support never relays | 5 attempts, 5 min, rate limits, stale-nonce free | `202`, `send-push-challenge`, `push-proof-v3`, guard; DV-V1..V4 (deferred with the key) | EXISTS |
| G20 | Device rebound notice | previous owner | D3 in-app (web) only → **mobile notification centre (none exists) or a login-screen notice on that account's next sign-in** | as §1.12 | medium: must not disclose the new owner | per token per day (exists) | `202:E3` + a client test for the surfacing | EXISTS (web only); mobile surfacing **NEW** |
| G21 | Payout destination changed | org owners/finance | C13 emitted, **never drained** → **add the drain arm** (a SoD substitute per `093:4601-4603`) | C templates (`… ending in {{destination_last4}}` in-app; no digits in push) | medium: last4 only, in-app only | per-recipient key (exists) | pgTAP: envelope → notification rows | **NEW** (bug, one `when` arm) |
| G22 | Reports / disputes | admins, reporter, reported party, parties | A10/A11 push + optional email → keep; **add idempotency** | as §1.13 | medium: emails include report id and target id (admin only); parties never see each other | **none today** → `transfer_notifications`-style claim per (report_id, recipient) | edge test (none today) | EXISTS; idempotency + test **NEW** |
| G23 | Admin: signing invariant | admins | A12 → keep | as §1.14 | low (words/counts only) | 24 h dedupe (exists) | `165`, `200` | EXISTS |
| G24 | Admin: delivery failures | operators | E ops cases → keep; **note the detector cannot fire until Plane C claims** | case title `Notification delivery <state>` | none | `detect_sweep` (exists) | `183` | EXISTS (latent) |
| G25 | Preferences | every user | six toggles saved, **honoured by nothing** → either honour them in the A producers or replace the screen with the C matrix | Settings labels as §1 | none | n/a | test: a toggled-off user receives no A push | **NEW** (decision) |
| G26 | Tap routing | every user | nine server types unrouted → **route `report_*`, `admin_*`, `auto_release_*`, `transfer_expired_*`, `signing_invariant_alert`** | n/a | none | n/a | client test of the routing table (none today) | **NEW** |
| G27 | Mobile inbox | every user | none → **decision**: a mobile notification centre reading `public.notifications` + `notify.notification` | n/a | medium: rows must stay owner-scoped (RLS exists) | read_at update only | client test + device row | **NEW** (decision) |

---

## 4. What already exists versus new work, in one line each

- **Exists and reaches devices:** A1 bid placed, A3/A4 transfer created/sent, A5/A6 reminders, A7 expiry refund, A8 auto-release, A9 payment succeeded/ticket sold, A10/A11 reports/disputes (+ optional email), A12 signing alert, D1/D2 challenge — all subject to the Vault key / `project_url` on the environment, which the sandbox lacks by the owner's deferral.
- **Exists, in-app only (web):** B1–B12 inbox rows, D3 device-rebound notice.
- **Exists, client-local only while on the listing screen:** outbid, ending soon, won, lost.
- **Exists, cannot deliver (parked by design):** every Plane-C type (32 registered, 13 with producers, 0 deliverable).
- **Bugs to fix without adding notifications:** the sign-out → sign-in auth-lock deadlock (fix delivered, `a046568`); invisible token-fetch failure (in progress); the missing drain arm for `security_payout_destination_changed`; the inert `notify_outbid` trigger (retire or convert); no idempotency on report/dispute/refund/release pushes.
- **New notifications proposed (need owner approval, each a separate task):** auction ending soon, auction lost, reservation expiry, payment failed, password-changed push, device-rebound surfacing on mobile, routing for unrouted types, honouring the six preferences, a mobile inbox.

## 5. Evidence limits
Source sweeps only; no environment was read for this document except A's recorded sandbox facts (no Vault key, ledger 137). Delivery behaviour on a device is verified only by the device rows named above, all of which need the combined build and, for anything that must arrive, the deferred sandbox key.
