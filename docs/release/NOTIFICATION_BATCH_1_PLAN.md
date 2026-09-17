# Notification batch 1 — honour the existing preferences; surface the device-rebound notice on mobile (A, 2026-09-17) — **APPROVED for implementation and local verification 2026-09-17 (owner)**

**Owner's frame (2026-09-17):** "prepare the next development batch around honouring the existing preferences and surfacing
the device-rebound notice on mobile without a new outbound channel. Name the exact preference-to-event mapping, mandatory
security exceptions, scope and owners before implementation. Keep the dispatcher activation and new outbound notifications
pending separate approval."

**Owner's choices (2026-09-17):** (1) honour the existing "Listing sold" preference; **hide** the other five inactive switches
until their paths are implemented; **preserve stored preferences**. (2) implement the authenticated, owner-scoped
security-notice read and acknowledgement path. (3) the rebound copy's meaning, corrected before implementation: **the event
means a device previously receiving THIS account's notifications was registered to ANOTHER account; it does not mean another
device was linked to this account** — D verifies the message and the recovery actions against the actual contract. (4)
include the neutral wording fix for F-2S-1 without changing authentication behaviour. The staged-notice device test is
prepared in §3b and **not executed**. Dispatcher activation, new outbound notifications and another hosted build remain
separate decisions. Status: implementation and local verification in progress across A/B/C, D reviewing.

**Copy source, settled:** the server template already carries the corrected meaning — 135's `notify.template` en-US in_app
v1 for `security_device_rebound`: subject "A device was re-registered to another account"; body "A device that was receiving
your notifications ({{device_name}}) was just registered to another account. If that was you switching accounts on your own
phone, nothing to do. If not, sign in on that phone to take it back, then change your password." The 136 wrapper returns it
rendered through `notify.get_inbox`, so the mobile notice and the web notification centre say the same thing from one source;
the client renders `{title, body}` and owns only its two action labels. A's first client draft ("another device was linked")
was wrong in exactly the way the owner corrected and is withdrawn. Any change to the wording is a new template version in
136, reviewed by D, never a client string.

## 1. The six preferences, exactly, and what each governs today (source at the build tag)

`public.notification_preferences` (`000_baseline_schema.sql`), client-writable from `app/settings/notifications.tsx`, **read by no
server path today** (C's inventory G25; the only server references are the table's own DDL in 000 and 040).

| Toggle | Default | Event it is meant to govern | What actually sends today | Batch 1 action |
|---|---|---|---|---|
| `notify_listing_sold` | true | seller: "Your ticket sold!" | **A9 push from `stripe-webhook` on `payment_intent.succeeded`** (seller side) — the **only** toggle whose event reaches devices today | **honour it**: the webhook reads the seller's row before the A9 seller push; buyer-side "Payment Confirmed!" is not governed (it is the buyer's own money event — mandatory) |
| `notify_outbid` | true | previous top bidder: outbid | server push **inert** (`notify_outbid` returns early when the legacy GUCs are null — B's N-6; 133 did not migrate it); web inbox row B2 only | **no honouring possible without re-enabling a dead producer**, which is a new outbound (pending separate approval; critical path 1.9 is the 133 follow-up migration) — batch 1 only makes the screen truthful (see §3) |
| `notify_auction_ending` | true | bidders: ending soon | nothing server-side (client timer on screen) | screen truth only |
| `notify_auction_won` | true | winner | web inbox row B3 only | screen truth only |
| `notify_auction_lost` | false | losing bidders | nothing | screen truth only |
| `notify_reservation_exp` | true | buyer with a hold | nothing server-side (in-screen countdown) | screen truth only |

**Finding to state plainly:** five of the six toggles govern events that no server path sends; the screen implies they do.
Honouring them means, for five toggles, nothing can be honoured until their producers exist — and each producer is a **new
outbound notification** (backlog P2, pending the owner's separate approval). Batch 1 therefore (a) honours the one toggle with
a live event and (b) makes the screen tell the truth about the other five, with no new channel.

## 2. Mandatory — never governed by a toggle (security and money-flow), unchanged by this batch

Buyer "Payment Confirmed!" (A9 buyer side) · transfer created / tickets marked sent / confirm reminders (A3–A6) · transfer
expiry refund (A7) · payout released / order complete (A8) · reports and disputes to admins and parties (A10/A11) · signing
invariant alert to admins (A12) · account deletion (C10/C11, Plane C, parked) · session expiry / signed-out-elsewhere
(client notice, K-2) · **device-possession challenge (D1/D2, 135)** · **device rebound (D3, `security_device_rebound`,
mandatory type, in-app only by the owner's ruling)** · password changed (B12, web inbox). A preference toggle never suppresses
any of these; the batch adds no new toggle.

## 3. Scope of batch 1 (two items, both without a new outbound channel)

### Item 1 — honour `notify_listing_sold`; make the Settings screen truthful
- **Server (B, edge):** `stripe-webhook` reads `public.notification_preferences.notify_listing_sold` for the seller before the
  A9 seller push; absent row ⇒ default true; edge test RED without the read (a seller with the toggle off still receives the
  push) then GREEN. No SQL change. **Effort 0.5 d B + 0.25 d D review.**
- **Client (C), per the owner's choice:** the five toggles with no sending event are **hidden** until their paths exist;
  stored preferences are **preserved** (no write on hide, no default reset; the rows keep their values and will govern the
  P2 producers when approved). Tests: the five rows absent from the tree; stored values untouched; `notify_listing_sold`
  still writes. **Effort 0.5 d C.**
- **Not in scope:** re-enabling the outbid producer (N-6 / critical path 1.9) — a new outbound in effect; the Plane-C
  `notify.preference` matrix (pending the dispatcher decision P3-2).

### Item 2 — surface the device-rebound notice on mobile, from rows that already exist
- **Why server work is needed at all:** `security_device_rebound` rows are enqueued by 135 into `notify.notification` for the
  previous owner (in-app, no delivery rows), and `notify.get_inbox / get_unread_count / mark_read / mark_all_read / dismiss`
  exist with `authenticated` EXECUTE (092) — but **the `notify` schema is not PostgREST-exposed** (`public, graphql_public,
  kernel`), so the mobile client cannot call them. The 129 pattern applies: a `public` wrapper that delegates.
- **Server (A):** migration **136** (`public_security_notices_read`): `public.get_my_security_notices()` — `security definer`,
  `search_path=''`, `authenticated` EXECUTE only, delegates to `notify.get_inbox` for `auth.uid()` and returns only rows whose
  type is in the mandatory security set (`security_device_rebound` now; `security_password_changed` when produced) with
  `id, type_key, title, body, created_at, read_at`; `public.mark_security_notices_read(uuid[])` delegating to `notify.mark_read`
  scoped to the caller's own ids. Rollback; pgTAP (owner-scoped: another user's rows never returned; anon 42501; ids not
  owned ignored); grant-decision manifest +2 rows; Gate-2 census +2 functions; `expected_grants.txt`; contract note in
  `PUSH_TOKEN_CONTRACT_V3.md` §"previous owner". **Effort 1 d A + 0.5 d D review.** No new channel: it reads rows 135 already writes.
- **Client (C):** on sign-in and on foreground, call `get_my_security_notices()`; if an unread `security_device_rebound` exists,
  show a full-width notice on the first signed-in screen rendering the **server's** `{title, body}` exactly as returned (the
  corrected meaning lives in the template, see "Copy source, settled"); the client owns only two action labels — "Sign out
  of all devices" (K-2) and "Dismiss" (→ `mark_security_notices_read`); never on the shared login screen (K-2 rule); tests
  RED-first for: shown when unread, not shown when read, action routes to K-2, never rendered on the login screen. D
  verifies the recovery actions against the contract (the template's own remedy is "sign in on that phone to take it back,
  then change your password"; whether "Sign out of all devices" is also right for the previous owner is D's call).
  **Effort 1.5 d C.**
- **Evidence limits:** the rebound event itself needs push delivery (challenge → echo → rebind), deferred with the sandbox key,
  so the notice is exercised on a handset only by **staging one `security_device_rebound` row for the DV buyer** via
  `notify.enqueue` in an authorized sandbox window (a write; cleanable: `dismiss` marks it, and the row can be deleted by id),
  or by pgTAP alone. That staging is its own authorization line, not assumed.

### Item 3 — F-2S-1 neutral copy (owner's choice 4)
The challenge-failed banner's sentence "You were signed out on this device …" is replaced by neutral copy on the challenge
path only — e.g. "This device couldn't confirm notifications for this account. Try again from Settings › Notifications." —
with **no change to authentication behaviour** (no forced sign-out from a push flow; the register path's stale handling is
untouched). D verifies. **Effort 0.25 d C.**

## 3b. The staged-notice device test — prepared, NOT executed (its own authorization line)

**Purpose:** exercise the mobile notice end to end on the next build without push delivery (deferred with the sandbox key):
the rebound event's *server row* is what the notice reads, so one row staged for the DV buyer is sufficient and sends nothing.

| Step | Exact action | Evidence |
|---|---|---|
| Pre | read-only: `notify.notification` rows for the buyer (`919d511e-c4e6-4422-a71d-e2bc0139de65`) = 1 today (type recorded at execution); `notify.delivery` total = 18; `net.http_request_queue` = 0; type row `security_device_rebound` `allowed_channels = {}` (read 2026-09-17) | A + D before-reads |
| Write (one statement, as `postgres`, sandbox only, inside an owner-authorized window) | `select notify.enqueue('919d511e-c4e6-4422-a71d-e2bc0139de65', 'security_device_rebound', 'account_security', '140fcb44-4920-4c32-8333-1a551879d36b', '{"device_name":"iPhone (DV staged)"}'::jsonb, 'dv-notice:140fcb44:<YYYY-MM-DD>');` → returns the notification id (recorded) | the returned id |
| Delivery suppression (the test's whole safety argument, verified, not assumed) | `select count(*) from notify.delivery where notification_id = <id>` = **0** (allowed_channels `{}` ⇒ enqueue creates no delivery row); `net.http_request_queue` unchanged; no new `net._http_response` row attributable to it; `notify.delivery` total still 18 | A read, D read |
| Device | owner signs in as the buyer on the next build (or foregrounds): the notice renders the server title/body with "iPhone (DV staged)"; "Dismiss" → `mark_security_notices_read` → `read_at` set; relaunch → not shown | C guide, A read-back of `read_at`, D witness |
| Cleanup (verified) | `notify.notification` carries no trigger and no append-only guard (092; checked 2026-09-17), so: `delete from notify.notification where notification_id = '<id>'` as `postgres`; verify buyer rows back to the pre-count and `notify.delivery` total unchanged at 18 | A + D read-backs; recorded in the manifest |
| Excluded | no push, no email, no dispatcher, no change to any type row or template, no second row | — |

## 4. Owners, sequence, and what it does not include

| Step | Owner | Effort | Depends on |
|---|---|---|---|
| Owner approves batch 1 scope as written (items 1–2), the Settings copy choice (label vs hide), and whether a staged notice row on the sandbox is authorized for the device check | Owner | — | — |
| 136 + pgTAP + manifests + rollback + contract note | A | 1 d | approval |
| Webhook preference read + edge test | B | 0.5 d | approval |
| Settings truth label + copy test; security notice screen + tests | C | 2 d | 136's contract (can start on the contract text) |
| Reviews (RED evidence, negative controls, grants) | D | 1 d | the three heads |
| Integration onto the stack → **new pin** (server + client) → CI → D gate | A | 0.5 d | reviews |
| Device checks on the next build: notice shown/dismissed (staged row, if authorized); Settings truth label; `notify_listing_sold` honoured is **test-only** until push delivery is testable (deferred) | C guide, Owner handset, A read-backs, D witness | 1 h owner | the build ruling |

**Explicitly not in batch 1, pending separate approval:** dispatcher activation (`notify.delivery_lease_interval`, PFA-22;
`notify-dispatch` / `notify-receipts`), any new outbound notification (the five no-producer toggles' producers, password-changed
push, payment-failed push, auction pushes), the outbid producer repair as an outbound (1.9 is filed as a 133 correctness
follow-up; enabling its push is a separate approval), email for the rebound notice (declined 2026-09-16), and a mobile
notification centre (backlog row 18).
