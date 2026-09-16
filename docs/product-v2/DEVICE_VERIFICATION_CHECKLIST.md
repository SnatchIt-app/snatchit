# Premium Experience — targeted device-verification checklist for the next candidate build

Status: prepared 2026-09-14 by C for the next authorised candidate. Not a
test report. Nothing here has been run; every row is UNVERIFIED until a
build carrying batches 1–4 runs on a physical device. Static previews are
supporting evidence only. Build 16's closed record is unchanged.

## Preconditions

- A candidate built from the integration of `frontend/premium-batch-1`
  (43e3a97), `-2` (73a5f19), `-3` (d48c290) and `-4` (this branch), on the
  sandbox project (`ofaidukbieeekqaboscm`), EAS profile per A's release
  package. Build 16 stays pinned for the closed QA record.
- One physical iPhone, one sandbox buyer account, one sandbox seller
  account; A available for read-only server read-backs.
- Writes to the shared sandbox (a hold, a bid, a transfer) happen only inside
  the explicitly scheduled window; every row below that needs one says so.
- Migration 128 is applied nowhere. Rows marked **128-RPC** cannot be run
  on this candidate unless the owner authorises applying 128 to the sandbox
  first; the legacy path rows can.

Evidence per row: what appeared on screen (text, not a screenshot unless the
owner asks), the server read-back A performs, and PASS / FAIL / UNTESTED.

## Batch 1 — content first, hold and refund truth

| ID | Check | Steps | Expected | Needs |
|---|---|---|---|---|
| DV-101 | Card → detail handoff | Home, tap a card | Title, venue, date and price painted before the spinner would have; Buy now / Bid disabled until the fresh row lands | device |
| DV-103 | Quiet refresh (T re-run) | Tickets tab, leave and return; Explore, search then refresh | Previous content stays; no full-page spinner; the T procedure from the Build 16 matrix re-run on this build | device |
| DV-106 | Image fallback | Open a listing whose fixture image 400s (P1/D7/D8) | Branded fallback in the reserved frame, no white flash | device, fixtures |
| DV-107 | Preserved place | Scroll Home, open a listing, back | Same scroll position, same filters | device |
| DV-302 | Hold row | Buy Now → checkout | "Held for you · m:ss left · until h:mm" with tabular digits; Pay withdrawn inside the last 15 s ("Checking your hold") | **window** |
| DV-301 | Hold lost copy | Let a hold run out on the checkout | "Your hold ran out" body, "Back to listing" is a normal back (listing exit path runs) | **window** |
| DV-304 | Price change | A-staged price change on a held listing | "The total changed … Accept $X"; Pay only after Accept | **window**, A |
| DV-305 | Interruption | Background during the payment sheet, return | "Checking your payment" then the server's verdict; no second Pay before reconciliation. D9c stays UNTESTED; no new attempt at that case | **window** |
| DV-308 | Refund faces | A-staged refunded / pending / partial payment rows | "Payment refunded" / "Refund in progress" / "Partial refund issued"; never "You're in." | **window**, A, owner wording |
| DV-609 | Seller proceeds | Create listing, quantity 2 | "$X for all 2 tickets", no "per ticket" | device |
| DV-611 | Sign-out revoke | Sign out on the device | Read-back: this device's token row is_active=false, revoked_reason='signed_out' (A); on the candidate the revoke goes through `public.revoke_push_token` (129) — a PGRST202 on a server without 129 is swallowed and the row stays active: record which | device, A (+129 on the sandbox) |

## Batch 2 — controls, pending states, haptics, accessibility

| ID | Check | Steps | Expected | Needs |
|---|---|---|---|---|
| DV-201 | Press response | Tap stepper keys, quick-add, seller row | 0.98 compress on every control | device |
| DV-202 | Haptics by meaning | Tap a tab; select a filter chip; place a bid; complete a purchase (window); confirm receipt (window) | Tab: none. Chip: light tick. Bid: restrained tick AFTER the alert appears. Purchase/receipt: distinctive success AFTER the success screen | device (+window for the last two) |
| DV-203 | Pending labels | Place bid; Buy now; confirm receipt; save Your scene; submit report | "Submitting bid…", "Reserving…", "Confirming receipt…", "Saving…", "Sending report…" visible beside a spinner; button width does not jump | device (+window) |
| DV-203b | Bid outcome | Place a bid, then have the seller account outbid before the alert (A stages) | "You're leading" only when the fresh read agrees; otherwise "Bid placed, but outbid ($Y)" | **window**, A |
| DV-204 | Reversible actions | Toggle a notification preference offline; pick an area in Your scene offline | Flip reverts with the inline notice; chips roll back with the notice; Done waits ("Saving…") and does not leave on failure | device, airplane mode |
| DV-205 | Double tap | Double-tap Place bid, Buy now, I got my tickets | One request each (A read-back: one bid row, one reserve call, one confirm) | **window**, A |
| DV-206 | Reduce Motion | Settings › Accessibility › Reduce Motion on | Sheets cross-fade, stack cross-fades, spinner is the static mark, every state change still visible | device |
| DV-206b | VoiceOver | VoiceOver on, run DV-203 | Pending label read; rollback notices announced; "Did the tickets arrive?" read as a region | device |
| DV-208 | Dynamic Type | Largest accessibility text size | CTAs remain reachable; sticky prices and buttons do not clip; long event names wrap, not overflow | device |
| DV-208b | Unsaved work | Edit listing, change a field, swipe back; Report, choose a reason, swipe back | "Discard changes?" / "Discard this report?"; Keep stays, Discard leaves | device |

## Batch 3 — transfer wording, provider return, 128 client

| ID | Check | Steps | Expected | Needs |
|---|---|---|---|---|
| DV-402 | Claim vs possession | Seller marks sent; buyer views Bids, listing, receive; buyer confirms | "Marked sent" everywhere until the buyer confirms; then "Received" / "Tickets received"; auto-release reads as payment, never as receipt | **window** |
| DV-404 | Provider return | On receive (seller_sent), tap "Open {provider}", return | Order still on screen; quiet refresh; "Did the tickets arrive?" shown; "They're here" only dismisses and thickens the confirm border; "Report a problem" asks first; nothing confirmed or released (A read-back: no confirm-and-release call) | **window**, A |
| DV-404b | Return after state moved | While away, A moves the transfer to disputed/auto_released | On return the new state shows; no question asked | **window**, A |
| DV-611L | Registration, legacy path (live today) | Fresh install, sign in as buyer | Read-back: one push_tokens row, is_active=true (A); Settings › Notifications shows no remedy banner | device, A |
| DV-611S | Account switch, legacy path | Sign out (DV-611), sign in as seller on the same device | Read-back: the buyer's row revoked; seller's attempt: insert conflicts (23505) → **no takeover**, remedy banner "…needs to sign out here first" is NOT shown for a revoked row — record the exact outcome observed | device, A |
| DV-611R | Registration, RPC path | **128-RPC** — only if the owner authorises applying 128 to the sandbox | Outcomes `registered` → `refreshed` (relaunch) → `rebound` (account switch, same device) per A's contract; a lost secret (A clears the Keychain value under supervision) recovers by delete-then-register → `registered` | **owner authorisation**, A |

## Sprint additions (A's C-3, 2026-09-14) — changed behaviour and integration risks

| ID | Check | Steps | Expected | Needs |
|---|---|---|---|---|
| DV-L1 | Failed attempt then retry on the SAME listing | In the window: start Buy Now, fail the card (test decline), then pay again on the same listing | Second attempt creates a replacement intent before the old one is cancelled (B's L1 work); the hold stays the buyer's; one settled payment row at the end (A read-back) | **window**, A, B's L1 landed |
| DV-L2 | Leaving checkout after success | Complete a purchase, then navigate back to the listing and to Home | No release_reservation call is made for a paid order (L2 guard); the listing shows Sold; Bids shows the purchase (A read-back: no release event) | **window**, A |
| DV-607a | Session expiry | A invalidates the session server-side (or the refresh token is made stale) while the app is backgrounded; foreground | Login screen shows "Your session expired. Sign in to pick up where you left off."; a normal Sign out shows no such notice | device, A |
| DV-607b | Cancelled listing | A cancels a listing the buyer bid on (window) | Bids shows "Cancelled · Listing was cancelled" under Past, never "Winning"; the listing banner reads "Listing cancelled" | **window**, A |
| DV-607c | Delayed transfer | View a transfer past its window | "Transfer window expired" on the countdown; buyer states read from the shared vocabulary | **window** |
| DV-607d | Unavailable account | Request deletion (sandbox account), then attempt to bid | Settings shows the pending-deletion view; Place bid refuses with the deletion-pending alert; the blockers list names every kind with a label (F3) | **window**, A |
| DV-605 | Listing gone from a notification | Open a deleted listing's id from a cold start | "Listing not found" with "Browse live listings" that lands on Home (no dead Back) | device |
| DV-F8 | Partial refund | A stages a succeeded payment with amount_refunded_cents > 0 | Checkout re-entry shows "Partial refund issued" with the amount, never "You're in." | **window**, A |
| DV-611C | Cold-launch registration | Kill and relaunch the app while signed in | A read-back: register_push_token called on the relaunch (v2 clause), outcome refreshed; on a database without 128, the legacy touch updates last_used | device, A (+128 on the sandbox for the RPC path) |
| DV-T | T re-run | The Build 16 Tickets empty-state procedure, on this build | Same PASS criteria as the matrix; no full-page spinner on refocus | device |

## Batch 4 — progress copy, live auction presentation

| ID | Check | Steps | Expected | Needs |
|---|---|---|---|---|
| DV-306 | Real steps | Pay on checkout | "Confirming payment" while the sheet confirms, "Finalizing your order" after the charge; no "Processing" | **window** |
| DV-501 | At zero | Watch an auction end on the listing screen | "Confirming result" with detail until the row flips; then won/lost; no "Auction ended" before the server says so; A read-back: no extra finalize_auction call from the client during the poll | **window**, A |
| DV-502 | In-place bid | Seller account bids while buyer watches | Amount dips and returns; "Next bid from" updates; scroll position unchanged | **window** |
| DV-504 | Connection health | Toggle airplane mode on a live auction | "Reconnecting — bid status may be delayed" appears; disappears on reconnect; catch-up brings missed bids without a second outbid haptic | **window** |
| DV-505 | My Bids order | Two live auctions, one ending within the hour | Won unpaid first; within outbid/winning the sooner auction first; "Ends in Nm" line on the soon one | **window** |

## Production-gate rows (K-2 + 131; NOT Thursday's build — they need the production-gate candidate's own pin and build)
Server contract per A (131 @ f102ce2, verified by A and D): this device = `public.revoke_push_token(p_token)` then
`auth.signOut({ scope: 'local' })`, other devices untouched; all devices = `public.revoke_all_push_bindings()` then
`auth.signOut({ scope: 'global' })`, the sessions-gone trigger as the slow path. Client: `frontend/logout-scope @
ba9cf6c` (K-2) + `frontend/session-bound-131-r2 @ f2c1a1c` (131).

| ID | What | Steps | Evidence | Needs |
|---|---|---|---|---|
| DV-P1 | Sign out of all devices | Two devices signed in as the same buyer. On device A: Settings › "Sign out of all devices" → confirm | A read-back: every push_tokens row of the user is_active=false with reason `signed_out_everywhere`, hashes NULL, epoch set; device B receives **no** push on the next test send and is signed out on its next foreground (login shows no "expired" mis-statement — record the exact notice); device A signs in again → outcome **`refreshed`** (A verified against 131 @ f102ce2: the row keeps its user_id, is revoked `signed_out_everywhere` with the hash cleared, and rule 2 re-adopts whatever secret the device presents) | two devices, A, 131 on the sandbox |
| DV-P2 | Sign out (this device only) | Two devices signed in. On device A: Settings › "Sign out" → confirm | A read-back: only device A's row revoked (`signed_out`); device B keeps its session and still receives the next test send; device A signs in again → **`refreshed`** (A verified: hash kept, row re-activated; a *different* account on the same install would get `rebound` because the hash still matches) | two devices, A, 129 on the sandbox |
| DV-P3 | Password change ends every session | Two devices signed in. On device A: reset the password | A read-back: the trigger revoked every row (`password_changed`), hashes NULL; device A's login shows "Password updated. Sign in with your new password."; device B is signed out on next foreground; device A signs in with the new password → registers from the new session (no `session predates a credential change` on a fresh session) | two devices, A, 131 on the sandbox |
| DV-P5 | Shared install after "Sign out of all devices" (expected behaviour, not a defect — A, 131 @ f102ce2; D's S-scenario) | Device A: "Sign out of all devices"; then a *different* account signs in on the same install | Registration refused **42501 "insufficient_privilege: token is bound to another account"** (the hash was cleared, so nothing proves possession; the legacy rule covers pre-128 rows only). Settings › Notifications shows the remedy, which on the production-gate branch reads "…needs to sign in here and then sign out from this device, or contact support" (`frontend/session-bound-131-r2 @ dece6cf`; the candidate's copy still says "sign out here first"). Recovery, any one: the original account signs in (`refreshed`) then signs out this-device (hash kept → the other account gets `rebound`); support `unbind_push_token`; reinstall (new token → `registered`) | two devices, A, 131 on the sandbox |
| DV-ST1 | Offline state, refreshed (owner request 2026-09-16) | Airplane mode on; open Home, Explore, Bids, Tickets, Profile | Every tab shows the same Premium state: glyph disc, "You're offline", "Check your internet connection and try again.", a red Retry button; **Tickets now says offline too** (F-OFF-1); headings clear the SANDBOX badge; airplane mode off → the screen retries by itself | device |
| DV-ST2 | Server-error state, distinct from offline | A stages a failing read (or revokes a grant for the DV user) while online | "Couldn't load this" / "Something went wrong on our side. Try again in a moment." with Retry — never the offline copy; cached rows stay if the tab had any | device, A |
| DV-ST3 | Empty and no-match states, distinct from failures | Empty account tab (Tickets: "No tickets yet"); Explore with a query matching nothing | Empty: title + sentence, no glyph, no Retry; no-match: search glyph + "Nothing matches" + "Try the venue name, or a shorter word."; neither shows while a load is in flight | device |
| DV-ST4 | State views at large text, with VoiceOver and Reduce Motion | Largest accessibility text; VoiceOver on; Reduce Motion on; repeat DV-ST1 on one tab | Heading clears the badge (badge does not scale); VoiceOver announces the title and sentence **exactly once** (D review SV-2: the view carries both an alert role and an explicit announcement; if it is read twice, keep the explicit call and drop the role — Android TalkBack is untested this session) and reads Retry as a button (busy while retrying); nothing animates; Retry reachable without scrolling | device |
| DV-V1 | Proof of possession, silent path (client v3 + 135) | Token with history under another account: sign in as the other account on the same install | Settings › Notifications shows "Confirming this device for notifications…"; within seconds the silent push is echoed and the banner clears; A read-back: challenge confirmed, row `user_id` flipped, proof superseded = `rebound` from the confirm verb; the previous owner gets the in-app `security_device_rebound` notice, never a push | two accounts, A, 135 on the sandbox |
| DV-V2 | Proof of possession, visible-code fallback | Same as DV-V1 with the silent push withheld (A/B stage) | After 60 s foregrounded the app requests the visible code; the notification reads "Snatch It verification code: NNNNNN. Never share this code."; typing it confirms; a wrong code shows "That code didn't match. N attempts left."; the fifth wrong code shows "Too many wrong codes. Tap Try again to get a new code." and Try again requests a visible code straight away — a NEW challenge with a fresh code (A's P3-1 ruling, 135 @ ac716da; A read-back: the old row consumed, a new challenge id, attempts reset); typing the OLD code after that shows "That code was replaced by a newer one…" and costs no attempt (`stale_nonce`); the code appears in the notification's alert text — **owner confirms the lock-screen preview is acceptable**; a silent push arriving while on the code screen is ignored by design | two accounts, A/B, 135 on the sandbox |
| (evidence) | Client v3 wiring | — | Five of the twenty-one v3 unit tests are source-text guards (hook wiring, deps, Settings, no UIBackgroundModes); only DV-V1..V3 exercise the hook: a real silent push arriving, the 60 s fallback firing, a wrong code then a right one | — |
| DV-V3 | Challenge across background / expiry | Start DV-V1, background the app before the push, foreground after 30 s; then repeat and wait past 5 min | Backgrounding stops the fallback clock; foreground re-requests the same challenge and it completes; past expiry the app shows "The confirmation expired. Tap Try again to get a new code." and Try again requests a visible code directly (fresh challenge, P3-1). Note: a foreground re-request ROTATES the nonce (A's ruling (a)); if the first, late silent push then arrives its echo answers `stale_nonce` — see DV-V4 | A read-back, 135 |
| DV-V4 | Stale echo is neutral (A's ruling (a), client 0eea9c3) | A stages a re-issue (e.g. two requests for the same open challenge) and delivers the SUPERSEDED nonce to the device, then the current one | On the superseded push: the banner stays "Confirming this device for notifications…", no failure copy, A read-back shows no attempt charged and no bind; on the current push: `rebound`. **Known limit:** if the current push arrives while the stale echo is still in flight the client drops it and waits for the 60 s fallback (visible code) — record the time to completion | A, 135 |
| DV-A11Y-1 | VoiceOver pass (deferred from build 17 row 10) | Dedicated VoiceOver session on Settings › Your scene, Report, Notifications and the transfer prompt | Pending labels read; rollback and confirmation notices announced; "Did the tickets arrive?" read as a region; navigation order sensible — a later session, not asked of the owner now | device |
| DV-P4 | Stale session refused, then healed | Device B still holding an old session after DV-P3 (before it foregrounds): trigger a registration (relaunch) | Device B: register refused 42501 `session predates a credential change` → the app signs this device out with "You were signed out on this device. Sign in again to keep notifications on." (no password mentioned); after re-login it registers | two devices, A, 131 on the sandbox |

## Next-candidate rows from build 17 findings (combined build after 131–135 + client v3; NOT build 17)
| ID | What | Steps | Evidence | Needs |
|---|---|---|---|---|
| DV-S1 | Seller form with the keyboard (F-SELL-1, create) | Sell your ticket → tap Event name → type; scroll while the keyboard is up; dismiss; reopen; repeat with a long event name and the largest accessibility text size | No blank gap between the keyboard and the List ticket bar (only the bar's own padding); the focused input stays visible and the form scrolls; the heading clears the SANDBOX badge with normal spacing; open → dismiss → reopen lands in the same layout; entered values intact; when the keyboard is down the bar clears the floating dock as before | device |
| DV-S2 | Edit listing with the keyboard (F-SELL-1, edit) | Edit an owned listing → tap a field → type; dismiss; reopen; swipe back with a change | Same as DV-S1 for the Save changes bar and heading; "Discard changes?" still appears (unsaved-edit guard intact) | device |

## Out of scope for this candidate

- Anything routed to D (vendor/admin) or waiting on A contracts A-07, A-09,
  A-10, A-11, A-12, A-14, A-15.
- F10 (minimum increment as a server rule): owner decision, nothing to verify
  until decided.
- Native Tickets (CFT-801): issuance disabled; the populated state stays
  UNTESTED.
