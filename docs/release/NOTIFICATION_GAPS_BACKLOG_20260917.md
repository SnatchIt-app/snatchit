# Notification gaps — prioritized backlog with owners (A, 2026-09-17; owner request)

Source: C's `docs/product-v2/NOTIFICATION_INVENTORY_AND_GAPS.md` (2026-09-16, `frontend/premium-experience-backlog`), gap
matrix G1–G27, cross-cutting facts §2. **This backlog authorizes no additional outbound notification**; every "new
notification" row is a proposal that needs the owner's approval as its own task. Owners: **A** = notify plane, contracts,
producers in SQL; **B** = edges (`send-push`, `notify-*`), crons and drain arms; **C** = client (screens, routing, preferences
UI); **D** = ops detection and the web notification centre. Priority: **P0** = a user is misled or a security/money signal
is lost with no new notification needed; **P1** = correctness of what already sends; **P2** = new notifications, proposals
only; **P3** = decisions to take before any work.

## P0 — fix without adding notifications

| # | Gap (C's id) | What is wrong today | Work | Owner | Effort | Depends on |
|---|---|---|---|---|---|---|
| 1 | **G25 ignored preferences** | `public.notification_preferences` has six client-writable toggles that **no server path reads** (`000:920-940`); `notify.preference` is honoured only by Plane C, where 28 of 32 types are mandatory. A user who turns a toggle off keeps receiving the push. | **Decision first (P3-1)**, then either: (a) honour the six toggles in the A producers (`notify-transfer`, `notify-report`, `enforce-transfer-expiry` Phases 1/3, the webhook's push) by reading `notification_preferences` before each send — B for the edges, A for any SQL producer; or (b) replace the Settings screen with the Plane-C matrix (`notify.preference`) — C. | A + B (a) / C (b) | (a) 2–3 d incl. edge tests; (b) 2 d client + 0.5 d A | P3-1 |
| 2 | **G20 device-rebound notice invisible on mobile** | `security_device_rebound` is enqueued in-app only (`allowed_channels '{}'`); there is no mobile inbox, so the previous owner sees it only in the web notification centre. Under option (b) no email; the owner kept it in-app only. | Surface it **on the affected account's next sign-in** as a login-screen or first-screen notice read from `notify.notification` (owner-scoped RLS exists) — C for the screen, A for a read contract (`get_my_security_notices()` or reuse of the notification read) with pgTAP; no new outbound channel. Alternative: the mobile notification centre (G27). | C + A | 2 d C + 1 d A | none (server rows already exist) |
| 3 | **G21 payout-destination-changed never drained** | `C13` is emitted (`093:4601-4603`, the separation-of-duties substitute) but **no drain arm delivers it**, so an org owner is never told their payout destination changed. Money/security signal lost. | Add the drain arm for `security_payout_destination_changed` in the Plane-C dispatcher path B owns, with a pgTAP that fails RED without it; channel per the type row (no new channel). | B (edge/cron) + A (pgTAP) | 1–2 d | the Plane-C dispatcher being un-parked for this one type (P3-2) |
| 4 | **G18 registration failure invisible** | token-fetch failure was console-only. | **DONE on the build tag** (`a609cbc`, F-611C-1): persisted, published, Retry. Device check DV-611C-2 on the combined build. | C | done | build |
| 5 | **G16 session expiry** | login-screen notice exists; must never name the cause on the shared login screen (K-2). | Keep; covered by row 17 PASS. The **two-second registration rejection window** (131 epoch margin) is under C+D assessment: an affected user must get an understandable explanation and a working recovery path; silent failure = finding. | C + D | 0.5 d assessment | 131 on the sandbox (done) |

## P1 — correctness of what already sends

| # | Gap | Work | Owner | Effort |
|---|---|---|---|---|
| 6 | **G26 tap routing** — nine server push types unrouted (`report_*`, `admin_*`, `auto_release_*`, `transfer_expired_*`, `signing_invariant_alert`) | route each to its screen; client test per type | C | 1 d |
| 7 | **G22 reports/disputes idempotency** — `notify-report` can double-send | claim row before send (the `transfer_notifications` pattern) + edge test | B | 1 d |
| 8 | **G9 / G13 dedupe** — expiry refund and payout-released pushes have no dedupe row | add `transfer_notifications (transfer_id, 'refund_notified' / 'payout_released')` claims + tests | B | 1 d |
| 9 | **G6 / G13 wording** — three wordings for "sold" and for "payout released" | one wording each; copy test | C (copy) + B (edge) | 0.5 d |
| 10 | **G24 detector cannot fire** — `ops.detect_notifications()` opens cases only for Plane-C deliveries, which never claim | note in the ops runbook now; it becomes live with P3-2 | D | 0.25 d |
| 11 | **G11/G12 tests** — edge tests for the transfer claim path and reminder copy | add | B | 1 d |

## P2 — new notifications (proposals only; each needs the owner's approval; none authorized here)

| # | Gap | Proposal | Owner | Effort |
|---|---|---|---|---|
| 12 | G1 outbid | server push via the tracked producer, honouring `notify_outbid` | A (producer) + B (edge) + C (routing) | 2 d |
| 13 | G2 auction ending soon | server-scheduled push at T-5 min, honouring `notify_auction_ending` | A + B | 2 d |
| 14 | G3 auction won / G4 lost | push + inbox; lost default off | A + B + C | 2 d |
| 15 | G5 reservation expiry | push at T-2 min, honouring `notify_reservation_exp` | A + B | 1 d |
| 16 | G8 payment failed / canceled | in-app state + push `purchase_failed` (template exists) | A + C | 1 d |
| 17 | G17 password changed | push `security_password_changed` to every other live device (template exists) | A + B | 1 d |
| 18 | G27 mobile inbox | a mobile notification centre reading `public.notifications` + `notify.notification` (owner-scoped RLS exists) | C + A | 4–5 d |

## P3 — decisions the owner takes before any P0/P2 work starts

| # | Decision | Options | Recommendation |
|---|---|---|---|
| P3-1 | Preferences: honour the six legacy toggles in the A producers, or replace the screen with the Plane-C matrix? | (a) honour; (b) replace | (a) now (it fixes a misleading screen without new UI), (b) when the mobile inbox lands |
| P3-2 | Plane C: keep parked (32 types, 0 deliverable) or un-park the dispatcher for a named subset (payout-destination-changed first)? | park / subset / all | subset: G21 only, as a security signal |
| P3-3 | Device-rebound surfacing: next-sign-in notice (no new channel) vs email (an N1 exception the owner declined 2026-09-16) vs mobile inbox | notice / email / inbox | next-sign-in notice now; inbox later |
| P3-4 | Which P2 proposals, if any, are approved; each is its own task and its own outbound authorization | per row | none until the marketplace release is out |

## Evidence limits
The inventory was written from files, not from delivery logs; whether a given A-plane push reaches devices in production is
"exists and reaches devices" per the shipped behaviour, not re-measured here. On the sandbox no push can leave (no service
key, option (b)), so none of this is testable there until that deferral is lifted; nothing in this backlog is described as
verified.
