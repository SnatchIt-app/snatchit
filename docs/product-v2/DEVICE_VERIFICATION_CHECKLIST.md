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
| DV-ST2 | Server-error state, distinct from offline | A stages a failing read (or revokes a grant for the DV user) while online. **ST2a** fresh launch (no preload); **ST2b** with Bids already showing rows, then pull to refresh during the revoke | "Couldn't load this" / "Something went wrong on our side. Try again in a moment." with Retry — never the offline copy; cached rows stay if the tab had any. **ST2b needs NO bid fixture:** Bids is "bids + purchases" (it merges the buyer's transfers), so the DV buyer's existing purchase rows (21 disputed on 2026-09-17) are the cached rows; a bids-read error keeps rows on screen (`loadError && bids.length === 0`). Build 18: ST2a PASS 2026-09-17; ST2b UNTESTED (that window ran ST2a only) | device, A, D witness |
| DV-ST3 | Empty and no-match states, distinct from failures | Empty account tab (Tickets: "No tickets yet"); Explore with a query matching nothing | Empty: title + sentence, no glyph, no Retry; no-match: search glyph + "Nothing matches" + "Try the venue name, or a shorter word."; neither shows while a load is in flight. Build 17 observed (owner, 2026-09-16): filter no-match "NO MATCHES / Try fewer filters." and Bids › Past "NOTHING HERE YET / Ended auctions and completed purchases show up here." — both strings unchanged by the refresh; re-observe here | device |
| DV-611C-2 | Cold launch on a slow network, twice (F-611C-1, D 2026-09-16: the composition seam the unit pins cannot prove) | Throttle the network (Settings › Developer › Network Link Conditioner, or a weak Wi-Fi); force-quit and reopen twice, 30 s on Home each time; open Settings › Notifications | Each launch produces a VISIBLE outcome: either it registers (A read-back: last_used advanced) or Settings shows a failed banner with a specific reason and a Try again. **Silence — no stamp and no banner — is a FAIL, not inconclusive** (D 2026-09-16: that is the whole point of the change). Try again registers; A read-back after each launch | device, A |
| DV-N1 | Account-security notice (batch 1, item 2; prepared, NOT run) | A stages one unread `security_device_rebound` row for the DV buyer (A's write, not executed yet); owner signs in / foregrounds | Full-width notice above Home with the server title and body; "Sign out of all devices" → login screen; a second staged row → "Dismiss" → notice gone and stays gone on relaunch; never on the login screen; VoiceOver announces it once | device, A (staged row) |
| DV-N2 | Hidden notification switches (batch 1, item 1; prepared, NOT run) | Settings › Notifications; A reads the DV buyer's preferences row before and after | Only "Listing sold" shown; toggling it writes that column only; the five hidden columns keep their prior values (A read-back) | device, A |
| DV-N3 | F-2S-1 copy (batch 1, item 3; prepared, NOT run) | A bumps the buyer's epoch while a challenge is open (needs push delivery → deferred with the key); fallback: static review of the sentence | Challenge failed banner reads "This device needs you to sign in again before it can confirm notifications for this account."; no sign-out happens from that banner; signing out and in registers | device, A (deferred with the key) |
| DV-131-1 | Two-second registration window (prepared, NOT run) | A bumps the buyer's push-binding epoch within 2 s of the owner's sign-in | The app signs this device out with "You were signed out on this device. Sign in again to keep notifications on."; signing in again registers (A read-back); no silent state | device, A |
| DV-AUTH-1 | Sign out online → sign in → data loads (blocking Build 17 finding, owner 2026-09-16) | Online; Profile › Sign out; sign in as the same account; wait on Home; open Profile; then repeat with the OTHER DV account (account switch); large text on; sandbox banner visible | Home and Profile load without a force-quit; no permanent spinner; A read-back shows one listings read and one get_my_profile per screen (no duplicates); sign-out row state unchanged from row 16 (inactive/signed_out then re-registered on sign-in) | device, A |
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
| DV-NAV-1 | Keep editing keeps the edit screen (F-NAV-1; Build 18 FAILED: Keep editing landed on My Listings) | Edit listing → change a field → swipe back from the left edge → read the prompt → Keep editing; then the in-screen Back arrow → Keep editing; then leave again → Discard | Swipe: the screen does not slide away; "Discard changes?" / "Your edits to this listing haven't been saved." / Keep editing · Discard; after Keep editing still on Edit listing with the changed text present. Back arrow: same. Discard: on My Listings, listing unchanged, one prompt only | device |
| DV-NAV-2 | Same guard on the other two forms (F-NAV-1, same hook) | Report form: choose a reason → swipe back → Keep writing. Settings › Preferences: toggle and swipe back while it is still saving → Wait | Each stays on its screen with the entry intact; the leave button still leaves | device |
DV-IMG fixtures and ordering (A, sandbox read 2026-09-17 05:55:58Z; full ids in A's manifest before the window; no fixture write needed): DV seller 2f5844b4…, buyer 919d511e…. PENDING transfer 92ee5156… (alternates 3118bd30…, bce07eef…) for DV-IMG-1..8. SELLER_SENT with no stored proof 8f59d37e… (alternate 83b83858…) for the Add proof rows. All DV-IMG rows are next-build rows: Build 18 has neither the picker repair nor the 140 client, and the Add proof rows also need 140 applied on the sandbox in the owner's window.
| DV-IMG-10 | Add proof on a transfer sent without a screenshot (140) | Transfer send on 8f59d37e…: the Add proof section shows; pick a screenshot; Add proof; then tap Add proof again with the same photo | Section only on this transfer (not on one that has proof); success only after A's read-back shows the path; the repeat answers already attached with no second object; a different photo afterwards says it can't be replaced | UNTESTED — next build + 140 on sandbox |
| DV-IMG-1 | Proof picker feedback (F-IMG-1a) | Transfer send (needs action): tap Add on Transfer proof once; then tap it three times quickly | One photo sheet opens; the control shows a picking state and ignores the extra taps; no error alert; after cancel the control is idle again | UNTESTED — next candidate |
| DV-IMG-2 | Permission denied / limited (F-IMG-1b) | Photos permission off → tap Add; then Limited access → tap Add | Denied: the permission alert, control idle after OK; Limited: the sheet opens with the allowed photos; nothing stuck | UNTESTED — next candidate |
| DV-IMG-3 | Replace and remove (F-IMG-1) | Pick, Replace with another, Remove, pick again | Preview updates each time; Remove clears; no stale image sent | UNTESTED — next candidate |
| DV-IMG-4 | Upload failure and retry (F-IMG-1c/1e) | Airplane mode on after picking → Mark as sent; airplane off → Mark as sent | First: the offline wording on the control and a Retry, no success; second: one upload, one verb call (A read-back: one object, one mark), success only after the verb answers | UNTESTED — next candidate |
| DV-IMG-5 | Repeated taps on Mark as sent (F-IMG-1d) | Tap Mark as sent twice quickly | One upload, one verb call (A read-back); one success alert | UNTESTED — next candidate |
| DV-IMG-6 | Navigate away and back (F-IMG-1f) | Pick, leave the screen, return | Selection state as the fix defines (kept or cleared, stated); nothing stuck | UNTESTED — next candidate |
| DV-IMG-7 | Sell form parity | Same as DV-IMG-1..3 on Sell your ticket cover and proof | Same behaviour; the Sell form stays the baseline | UNTESTED — next candidate |
| DV-IMG-8 | Android | DV-IMG-1..5 on an Android device | Same, incl. the photo picker without a permission prompt on Android 13+ | UNTESTED — no device or emulator |
| DV-IMG-9 | iPhone HEIC proof → JPEG (F-IMG-1i, outcome 3) | Send tickets: attach a HEIC camera photo (not a screenshot) as transfer proof; A's read-back of the stored object; open it in the operator console and on the web receive page in Chrome | Stored object's bytes and label are JPEG with a .jpg name; it renders in Chrome and on the iPhone. If compatible mode does not transcode, the object must be labelled HEIC (never JPEG) and the row FAILS outcome 3 | UNTESTED — next candidate + sandbox round-trip |

## Out of scope for this candidate

- Anything routed to D (vendor/admin) or waiting on A contracts A-07, A-09,
  A-10, A-11, A-12, A-14, A-15.
- F10 (minimum increment as a server rule): owner decision, nothing to verify
  until decided.
- Native Tickets (CFT-801): issuance disabled; the populated state stays
  UNTESTED.

## Build 20 — `candidate/2026-09-18-build-d1` → `8da50c0` (EAS 2c423058-fd38-4680-bbf4-26360b188567)
Preview profile, `EXPO_PUBLIC_APP_ENV=sandbox`, test Stripe key. Submitted by A from a clean worktree at the tag.
**C verified independently, not relayed:** all five heads are ancestors of `8da50c0` (`2fe7abd`, `0ca71ff`,
`2567401`, `016d8e2`, `f3cff27`) **and each fix is present in the built tree** by source check — ancestry alone
would not have caught a later revert. *(C's first content check reported three misses; that was C's own shell
escaping of the `[id].tsx` paths, not the build. Re-checked correctly: present.)*
**Known gap, the owner's to close:** the tag is local to A's machine — A's pushes are permission-gated — so the
build's source cannot be resolved from the remote yet. Does not affect the build or the pass.

**Every row below is UNTESTED. Each has source-and-test evidence and none has device evidence.** A green suite
says the code does what we wrote; it cannot say the screen does what a person sees.

| # | Row | What must be true on the handset | Status |
|---|---|---|---|
| DV-20-1 | Home "Recently sold" offline | a classified failure, never "Nothing sold yet" | **PASSED** 11:34 (below) |
| DV-20-2 | Home "Ended" offline | same | **PASSED** 11:39 (below) |
| DV-20-3 | Home filter refresh fails over rows | rows stay, notice + Retry appear | **PASSED** 13:33 (below) |
| DV-20-4 | Place bid, connection off | error state with Retry; **no bid form, no $0 current bid** | **PASSED** on the final state, 11:43:47 — **one earlier screen unreported, see note** |
| DV-20-5 | Place bid, read rejects | no permanent spinner | UNTESTED |
| DV-20-6 | Delete / cancel a listing | one request; the row stands down while it runs | UNTESTED |
| DV-20-7 | Send Transfer past the window | "Send window has passed — send now if you still can"; **Mark as sent still enabled** | UNTESTED |
| DV-20-8 | Receive Transfer, `pending`, past the window | the buyer's wording, not the seller's; no instruction to send | **PASSED** 13:35 (below) — device evidence for F-XFER-2's pending branch |
| DV-20-9 | Receive Transfer, `seller_sent` | **no window line at all** | **PASSED** 11:58 on the observed screen (below); fix evidence condition MET on D's read (`expires_at` non-null); the open wrote one seller notification |
| DV-20-10 | Profile avatar, single press | spinner persists through the save; photo updates once | UNTESTED on its property — the save completed (14:09), spinner timing and a single change not captured (below) |
| DV-20-11 | Edit Profile avatar, single press | same, and both controls stand down | UNTESTED |
| DV-20-12 | Avatar, same-tick double press | one picker, one upload | **PASS (weak)** 14:09 — one picker (below) |
| DV-20-13 | Security notice actions | one sign-out per press; a thrown failure shows a message | UNTESTED, **needs a staged notice** |

**DV-20-12 is a weak-pass row by construction, and C is saying so before it is run.** The old state guard already
blocked a *slower* second tap; only a press landing inside the same event loop (~16 ms) got through. So a **FAIL
is conclusive** (two pickers = the lock is not holding) while a **PASS is ambiguous** — it is equally consistent
with "the fix works" and "the two taps did not land in the same frame". It must be recorded as PASS (weak) or
UNTESTED, never as proof the race is closed.
**DV-20-13 needs a staged security notice** — the buyer's existing "Account deletion requested" notice is a
different type and must stay untouched; a thrown-failure row additionally needs a network condition, so it may
end UNTESTED rather than be forced.

**Two operational facts about Build 20, verified by C and confirmed by A (whose earlier statement was wrong):**
1. **Builds 19 and 20 CANNOT coexist.** `app.json` declares one `bundleIdentifier` (`com.jdt-inc.snatchit`) and no
   `eas.json` profile overrides it — `preview` adds only `ios.autoIncrement`. **Installing 20 replaces 19**, and
   getting 19 back means reinstalling from its own build page. A's "both can sit on the phone" was a release-stack
   fact ("20 supersedes nothing") extended to the device, which is a different system.
2. **The app renders its build number nowhere.** `NativeAppShell.native.tsx:30` reads the version once and uses it
   only for the Sentry release tag. Both builds report 1.0.0 and show the same SANDBOX badge, so **the owner
   cannot confirm from inside the app which build is running.**

**Consequence for the pass, and the owner was told before starting:** the first row doubles as build
identification. DV-20-1 is the right one for it — the owner reproduced the Build 19 behaviour twice, so the old
result is known exactly. **If the old copy appears, that is AMBIGUOUS between a failed install and a failed fix:
reinstall, confirm the app reopened, and re-run before anything is recorded as FAIL.** Letting a first-row failure
land on the code by default would have been very hard to unwind afterwards.

### DV-20-1 — PASSED, Build 20, 2026-09-18 11:34 (owner-reported)
Airplane Mode **on** and Wi-Fi **off** (both confirmed by the owner). Home → FILTERS → **Recently sold** showed exactly:
**"YOU'RE OFFLINE"** / **"Check your internet connection and try again."** / a visible **"RETRY"** button.
**No "NOTHING SOLD YET", no spinner.**
- **This is the before/after the row was chosen for.** On Build 19 (`f412d10`) the owner saw, under the same
  conditions, twice: "NOTHING SOLD YET / Completed sales show up here.", no error, no Retry, no spinner. Build 20
  shows the offline state instead. The defect is not reproduced.
- **Build identification, settled by the same observation:** the old copy did not appear, so the ambiguity the
  owner was warned about (stale install vs failed fix) does not arise. Build 20 is what is installed.
- **What this does NOT establish, recorded rather than inferred:** which render branch produced the state — the
  filter's own classified failure or the main feed's `loadError`. Both are correct outcomes for this row (neither
  is the empty copy), and on screen they are the same component with the same copy, so the observation cannot tell
  them apart. Whether Home had loaded online before going offline was **not captured**.
- **Still UNTESTED on this row family:** DV-20-2 (Ended), DV-20-3 (a failed refresh over rows already shown), the
  slow-network premature-empty path, and whether the screen recovers without user action once the connection
  returns.

### DV-20-2 — PASSED, Build 20, 2026-09-18 11:39 (owner-reported)
Offline with Wi-Fi off (owner); Airplane Mode as set for DV-20-1, not separately restated. Home → FILTERS →
**Ended** showed exactly: **"YOU'RE OFFLINE"** / **"Check your internet connection and try again."** / a visible
**"RETRY"** button. **No "NO ENDED AUCTIONS", no spinner.**
- Build 19 carried this defect on BOTH lazy datasets; this row confirms the fix covers the second one rather than
  inferring it from the first.
- Same limit as DV-20-1, recorded rather than inferred: the screen cannot show whether the filter's own failure
  state or the main feed's rendered it. Both are correct for this row.

### DV-20-4 — PASSED on the final state, Build 20, 2026-09-18 11:43:47 (owner-reported, owner's ruling)
The owner's correction, recorded verbatim in substance: the correct post-action state was
**"YOU'RE OFFLINE"** / **"Check your internet connection and try again."** / a visible **"RETRY"** button, with
**no bid form and no $0 value present.** The owner directed that DV-20-4 be recorded as PASSED on this final state,
and that an earlier bid-form screenshot "was not the correct final output".
- **Before/after:** on Build 19 a failed listing read fell through to the full bid form on a floor derived from
  `?? 0`. The final state here is the offline state instead — the defect's outcome did not reproduce.
- **DISCLOSED, NOT INFERRED — an earlier screen in this attempt showed a bid form, and C never received that report
  or its screenshot.** Not captured: whether that form appeared **while still online** (a real read, real values —
  correct behaviour) or **after Airplane Mode was on**, and what current bid and minimum it showed. **That
  distinction is load-bearing:** a bid form rendered OFFLINE with "$0" would be the Build 19 defect itself, and a
  later correct screen would not cancel it out. Nothing in the source explains a form turning into the offline
  state on its own — the screen reads once when it opens — which fits a re-entry or a Retry in between, but that
  sequence was not reported either.
- **The row stands as PASSED because the owner ruled it so on their own observation.**
- **OWNER'S ANSWER (2026-09-18), recorded exactly:** the earlier screenshot shows **Airplane Mode on**, **current bid
  $100**, **proposed bid $105**, and an alert **"Bid failed" / "TypeError: Network request failed."** The later
  screenshot shows the offline state with Retry and no form. **No $0 is visible in either screenshot.** The sequence
  between them was **not captured**: *do not infer when the form loaded or which buttons were pressed* (owner's
  instruction). An earlier statement elsewhere that the owner had not tapped submit is **unsupported** and is not
  repeated here.
- **What this settles for DV-20-4's property:** the defect was a form built on a FAILED read — a $0 current bid and a
  floor from nothing. **Neither screenshot shows that.** $100/$105 are real values, i.e. a form from a read that
  succeeded. The earlier screenshot's context (when that read happened relative to Airplane Mode) stays
  **UNRESOLVED**, as the owner directed.
- **A fact about the build, stated as source rather than as a claim about the owner's actions:** in `8da50c0`, the
  alert "Bid failed" carrying an error message is emitted at `src/screens/PlaceBidScreen.tsx:176` —
  `Alert.alert('Bid failed', error.message)` — inside `submitBid`, after the `bids` insert returns an error. It is
  not emitted by the listing read. **Whether a bid row was written is NOT verified;** a request failing with
  "Network request failed" under Airplane Mode most likely never reached the server, but that is not evidence. A can
  check it read-only if the owner authorises that read.
- **F-BID-1 ITSELF STILL HAS NO DEVICE EVIDENCE (A's framing, adopted — stricter than C's first reading, and
  right).** The row PASSED on its final screen, as the owner ruled. But the fix's own signature is "a FAILED listing
  read on the bid screen renders the offline state instead of a form", and with the sequence uncaptured nobody can
  attribute the final offline screen to the bid screen's failed read rather than to some other screen or read. The
  final state is *consistent with* the fix; it is not *evidence of* it. The row's pass and the fix's evidence are
  recorded separately so the second is not quietly upgraded by the first.
- **The DV-20-4 listing is not identified in the record.** The step said "any live auction", so C does not know which
  listing was used and will not guess it. A bid-row check, if authorised, needs the owner to name it.
- **C's own framing error, corrected:** C's step told the owner "if a bid form does appear, that's the failure we're
  looking for". That was imprecise. A form with real values from a read that succeeded is correct behaviour; the
  failure is a form built on a read that FAILED.

### DV-20-9 fixture selection (C, 2026-09-18) — owner's constraints: no further access to the retained D1/D2 proof
### files; Sandbox L7 untouched. **Read from the repo's migrations and Build 20's source; not yet confirmed against
### the sandbox.**
- **D1 and D2 are ruled out entirely, not just "don't look at the image".** In `8da50c0`,
  `app/transfer/receive/[id].tsx:100-109` calls `supabase.storage.from('proof-docs').createSignedUrl(path, 3600)`
  whenever `transfer_evidence_path` is set and the status is `seller_sent` — merely opening either transfer mints a
  signed URL for a retained object. That is storage access, which the owner's ruling bars.
- **L7 is ruled out** by the standing restriction.
- **Candidate: `8f59d37e` "Sandbox S8only"** — last recorded as `seller_sent` with `transfer_evidence_path` NULL, so
  the proof-URL effect returns early and **no storage is touched**. Two cautions from the record: it sits beside
  L7 under the same venue name, so **the event name is the only on-screen discriminator**; and it is reachable only
  via the listing detail's "View transfer".
- **Opening the Receive screen is NOT read-only, and whether it writes depends on a fact C must not read itself.**
  On mount it calls `mark_transfer_viewed` (`0550_transfer_state_guard.sql`):
  `UPDATE transfers SET buyer_viewed_at = COALESCE(buyer_viewed_at, now()) WHERE id = … AND buyer_id = auth.uid()`.
  `trg_notify_transfer_state_inbox` (`058`) inserts a `transfer_viewed` notification to the seller **only when
  `buyer_viewed_at` goes NULL → NOT NULL**; every other branch is gated on a status transition, the status-only
  triggers (`033`, `034`) cannot fire because status is not in the SET list, and there is no `updated_at` trigger
  on `transfers`. So: **if S8only's `buyer_viewed_at` is already set, opening it writes nothing; if it is NULL, the
  first buyer view stamps it and writes one notification to the seller.**
- **Pre-check needed before the owner opens anything, and it is A's read, not C's:** for `8f59d37e` — `status`,
  `transfer_evidence_path IS NULL`, `buyer_viewed_at` (null or set), `buyer_id` (which account must be signed in),
  and the listing's event name. Sandbox state is not inferred from last night's record.

### DV-20-9 — PASSED on the observed screen, Build 20, 2026-09-18 11:58 (owner-reported)
Owner's report and 11:58 screenshot: **Receive Transfer** for **"Sandbox S8only"**, badge **MARKED SENT**, **no expiry
line visible**. The screen also showed the delivery-information prompt ("Please provide your delivery info so the
seller knows where to send your tickets.") and form (phone field, SAVE DELIVERY INFO). Transfer card: Event "Sandbox
S8only", Seller "Unknown", Method "mobile transfer". **Navigation sequence not supplied; no database outcome
confirmed** (owner's words) — neither is inferred below.
- **Fixture discriminator held:** the event name reads "Sandbox S8only", not "Sandbox L7". "MARKED SENT" is
  `seller_sent`'s label (`src/lib/transfer/transferState.ts:72`).
- **The row's property is met on what the screenshot shows.** In `8da50c0` the line would render at
  `app/transfer/receive/[id].tsx:343`, between the delivery form and the Transfer card — that region is on screen and
  empty.
- **Does this screen exercise the fix? Yes, conditionally.** Before F-XFER-2 (`2fe7abd`, `:338`) the countdown block
  rendered for every status except `buyer_confirmed` and was **not** inside the delivery-prompt gate, so a
  `seller_sent` transfer with a past `expires_at` showed "Transfer window expired" in that same region. The only change
  to this file between `2fe7abd` and Build 20 is F-XFER-2 (`git diff --stat`: 1 file, +10/−5). **The condition is
  `expires_at IS NOT NULL` — past or future (A's sharpening of C's first wording, "still past", verified by C):**
  `formatCountdown` (`transferState.ts:35-43` at `2fe7abd`) returns null only for a null timestamp — "Expired" if
  past, "…remaining" if future — so the pre-fix screen showed *a* window line on `seller_sent` for any non-null
  value. S8only's `expires_at` was non-null (09-09T01:20Z) in A's read of 2026-09-17, and 0550 guards the column, so
  it is very likely unchanged — but it was **not re-read**, so the fix evidence stays conditional. Only a NULL would
  make this screen uninformative about the fix. Row and fix evidence recorded separately, as for DV-20-4.
- **A's pre-check was not run before this open** (it was never authorised). So **whether this open stamped
  `buyer_viewed_at` and wrote one `transfer_viewed` notification to the seller is UNKNOWN** — it did so only if the
  column was NULL beforehand. A can settle it read-only if the owner authorises that read — and one row does it:
  `notifications.dedupe_key` has a unique index and `enqueue_notification` inserts `ON CONFLICT (dedupe_key) DO
  NOTHING` (`057:50,83`), and the key is `transfer_viewed:<id>` (`058:185`). So at most one such row exists, and its
  `created_at` answers the question: ≈15:57–15:59Z → today's open wrote it; earlier → a prior open did and today's
  wrote nothing; none → the trigger never fired. Prepared by A, not run.
- **Storage:** S8only is a different transfer from D1/D2, so opening it cannot reach their retained objects. Whether
  a signed URL was minted for S8only's *own* path depends on that path being NULL — last recorded NULL, not re-read.
  The absence of a proof section on screen is **not** evidence either way: the proof block sits inside the same
  `!needsDeliveryInfo` gate (`:372`).
- **"Seller: Unknown"** is the fallback at `:358` when `display_name` is empty; A recorded `display_name` NULL on both
  DV accounts (2026-09-17). Visible; not raised; not investigated.
- The delivery prompt on a sent transfer → **F-XFER-3** (backlog).

### 11:59 screenshot — a listing-detail screen, NOT Receive Transfer (owner's classification)
Recorded for one thing only, at the owner's direction and **without expanding this pass**: the sticky bottom bar
truncates the price label and amount to **"CURREN…"** and **"$…"** ("total" visible), beside PLACE BID and
BUY NOW · $110. → **F-LAYOUT-1** (backlog). Which listing this is, and how the owner reached it, were not reported and
are not inferred.

### Sandbox reads for DV-20-9 and DV-20-4 — run by D (2026-09-18), reported to C
D states the owner authorised D directly. All statements `begin read only` against `ofaidukbieeekqaboscm`; no
storage, no L7, no logs, no trigger read. D's output files: `d_owner_answer_a1.txt` (md5 `aa816aec…`), `…_a2.txt`
(md5 `35e8e3aa…`). Read time not reported.
- **S8only `8f59d37e`:** `seller_sent`; delivery email and phone both absent; evidence path absent;
  `seller_sent_at` 2026-09-08 01:20:24Z; **`expires_at` 2026-09-09 01:20:22Z (non-null)**; `auto_release_at`
  2026-09-11 01:20:24Z (passed, not auto-released — one of the transfers stranded by the auto-release hazard);
  **`buyer_viewed_at` 2026-09-18 15:58:05.544Z** = 11:58:05 ET, the owner's time — **the first view ever**.
- **So the 11:58 open WROTE to the sandbox:** it stamped `buyer_viewed_at` and produced **exactly one**
  `public.notifications` row (`1f50cfaa…`, `transfer_viewed`, to the **seller**, 15:58:05.544Z — same millisecond, same
  transaction; consistent with `058`'s `trg_notify_transfer_state_inbox` per C's fixture note, which D did not read).
  Nothing to the buyer on the 18th; no `notify.notification` row for this transfer ever; whether the legacy row caused a
  push was **not examined**. A sweep of every notification to either party on the 18th found only that row.
- **DV-20-9's fix evidence:** the condition was `expires_at IS NOT NULL`; D's read (after the open) shows it non-null,
  and nothing records a change to that guarded column. **DV-20-9 therefore stands as device evidence for F-XFER-2's
  `seller_sent` branch**, on that read.
- **Device D7 `b1c3c478` (DV-20-4):** `active`, `current_bid` **100**, `bid_count` 0, no highest bidder. **Bids on D7
  ever: 0. Bids of 105 on the 18th, anywhere: 0. Bids by anyone on the 18th: 0. Bids by buyer `919d511e` ever: 0.**
  **No bid was written.** Why the submit never reached the database (failed on device, refused, or not completed) is
  not established; the sandbox API log around 15:43Z would settle it and was not read (not authorised).
- **What this adds to DV-20-4, without inference about the sequence:** the earlier screenshot's "$100 current bid /
  $105 proposed" matches D7's real `current_bid` 100 and its +$5 minimum — i.e. that form was built from a read that
  **succeeded**, not the $0 defect. F-BID-1 itself still has no device evidence (unchanged).
- **Corroborated independently by A** (owner authorised A directly; one read-only transaction, `tx_read_only=on`,
  16:46:13Z; evidence path reported only as a boolean; recorded at A's `675628c8`): S8only exactly one row,
  `seller_sent`, buyer `919d511e…`, event "Sandbox S8only", `expires_at` 2026-09-09T01:20:22Z, `buyer_viewed_at`
  15:58:05.544Z, evidence path null = true, `transfer_viewed` rows = 1 at 15:58:05.544Z to the seller. Because
  `mark_transfer_viewed` updates only where `buyer_id = auth.uid()` and it did update, **the owner was signed in as
  `919d511e` at 11:58.** D7: exactly one listing, `current_bid` 100; bids 15:30–16:00Z by any account: **0** — so
  "no bid was saved" holds **whichever account was signed in at 11:43.** Two sessions' reads agree on every field.

### DV-20-3 — PASSED, Build 20, 2026-09-18 13:33 (owner-reported, screenshot)
Owner: after the offline refresh the listings **remained visible** (Device D6, Device D1 among them); exact notice
**"You're offline. Showing what loaded earlier."** with **RETRY** beside it. The screenshot shows Airplane Mode on,
FILTERS 1 active, SOLD cards with "SOLD FOR $110 all in", the notice above the grid. Matches F-HOME-1's inline branch
(`HOME_FILTER_REFRESH_FAILED_COPY.offline`; `failureSurface` → `inline` when rows are loaded). The pull-to-refresh
sequence is the owner's report; nothing further is inferred.
- **Layout, recorded without expanding the pass → F-LAYOUT-2:** the notice text sits flush against the screen's
  left edge and RETRY against the right, while the cards below are inset.

### DV-20-8 — PASSED, Build 20, 2026-09-18 13:35 (owner-reported, screenshot)
Device D6's Receive Transfer: badge **PENDING**; exact line **"Send window has passed — the seller may still send"**
(`TRANSFER_EXPIRY_COPY.buyer`); below it "The seller has not marked the tickets as sent yet." No "Transfer window
expired", no instruction to send. Screenshot also shows the generic "How to receive your tickets / Varies"
instructions, no "Open …" button, Event "Device D6", Seller "Unknown", Delivery email `sandbox-buyer@snatchit.test`.
- **This is device evidence for the fix, not just a pass:** the line renders only when the device-clock countdown is
  "Expired", so `expires_at` was non-null and past; on the pre-fix code that same state rendered the literal
  "Transfer window expired" (`2fe7abd:341`).
- **Write: UNKNOWN, not read.** If this was the buyer's first view of D6, it stamped `buyer_viewed_at` and wrote one
  `transfer_viewed` notification to the seller (the owner was told before opening and proceeded). Not verified.

### DV-20-12 — PASS (weak), and DV-20-10 partly observed — Build 20, 2026-09-18 14:09 (owner-reported, screenshot)
On the sandbox buyer's Profile tab, a quick double-tap on the photo **opened only one picker**, and the selected image
(a non-personal Snatch It promotional graphic) **appeared as the profile photo**.
- **DV-20-12 is PASS (weak), by construction, as recorded before the run:** one picker is equally consistent with "the
  lock held" and "the two taps did not land in the same frame". A FAIL (two pickers) would have been conclusive; this
  PASS is not proof the race is closed. The same-tick behaviour is pinned by P1–P6 in tests.
- **DV-20-10's own property was not captured** (owner): whether the spinner stayed until the save finished, and
  whether the photo changed exactly once. What was observed is only that the upload and save completed. Row stays
  UNTESTED on its property.
- **This wrote to the sandbox (owner accepted before running):** one object in the public `avatars` bucket under the
  buyer's folder, and `profiles.avatar_path` for the buyer. Not read back.
