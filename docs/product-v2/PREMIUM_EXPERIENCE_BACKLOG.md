# Consumer Frontend & Tickets backlog — Snatch It Premium Experience

**Owner:** Claude C (Consumer Frontend & Tickets). **Opened:** 2026-09-14.
**Source:** `SNATCH_IT_PREMIUM_EXPERIENCE_CHECKLIST.md` (54 items), treated as the
complete source. **Baseline audited:** Build 16 source `df9e0d3`, plus the
unmerged branches listed under Existing work.

**Scope.** Post–Build 16 workstream. Build 16 (`df9e0d3`) stays pinned. This
backlog authorises backlog integration and isolated frontend branches only — no
deployment, no production change, and no change to shared transaction behaviour.
Transaction correctness, backend contracts, migration allocation and release
integration go to **A**; vendor/admin dashboard work goes to **D**. Native
ticketing capabilities stay distinct from marketplace purchases.

**Non-negotiable guardrails for every task.**
1. Never show a successful bid, reservation, payment, receipt confirmation or
   payout before authoritative server confirmation.
2. Reconcile an uncertain payment outcome before offering another payment.
3. Cached availability never authorises a transaction; refresh before a bid or
   purchase.
4. Cache by account; clear private cached data on sign-out and account change;
   a cached order card must never resemble an admission credential.
5. Known misleading checkout and recovery behaviour ranks ahead of decorative
   polish.

**Status:** implemented · partial · missing · blocked (needs a dependency before
frontend work can be correct) · deferred (not applicable to the current
product). No item is fully implemented today.

**Evidence level.** **[C]** re-verified by C in `df9e0d3`; **[audit]** from the
2026-09-14 read-only audit, to be re-verified when the task starts.

**Priority.** P0 misleading or privacy-affecting · P1 core clarity and
responsiveness · P2 completeness · P3 refinement.

---

## Existing work extended (not duplicated)

| ID | Work | Where | State | Extended by |
|---|---|---|---|---|
| CFT-E1 | Transfer UI V2 (buyer receive, seller send) | `frontend/transfer-ui-v2` (`401e0aa`, `ddaf20d`, `cabc232`) | reviewed by A; **visual acceptance blocked** on a device/simulator render | CFT-401, 402, 403, 405 |
| CFT-E2 | Transfer load-error handling (not found / offline / unavailable) | `frontend/d7-transfer-load-errors` (`5569385`, `59a413f`) | reviewed by A | CFT-401, 607 |
| CFT-E3 | F1 checkout summary/countdown (dead `cover_image_url` select) | `frontend/f1-checkout-summary-query` (`2ba5281`) | **approved by A** | CFT-302 |
| CFT-E4 | D9-UX-1 released hold reported as "expired"; "Try again" cannot re-reserve | defect record, doc 18; no branch | open, out of Build 16 | CFT-301 |
| CFT-E5 | F3 deletion sheet shows raw tokens for 3 blocker kinds | doc 18 | open | CFT-703 |
| CFT-E6 | F6 stale "deletion pending" notification, future integration risk | doc 18 | retained risk | CFT-606 |
| CFT-E7 | Populated native Tickets state untested (0 native tickets; issuance disabled) | matrix | deferred | CFT-801 |

---

## Batch 1 — Immediate content, skeletons, stable images, background refresh, preserved navigation

| ID | Item | Pri | Status | Screens | Evidence | Acceptance (observable) | Deps | Owner |
|---|---|---|---|---|---|---|---|---|
| CFT-101 | 1 | P1 | missing | `home.tsx`, `explore.tsx`, `ListingDetailScreen.tsx` | [audit] cards push only `/listing/${id}` (home.tsx:436, explore.tsx:177); detail shows a full-screen spinner until the row arrives (ListingDetailScreen.tsx:948-952) | Tapping a card shows its artwork, event name, date and displayed price on the first frame of detail; no full-screen spinner | — | C |
| CFT-102 | 2 | P2 | partial | Home/Explore, Bids, My Listings, Tickets, listing detail | [audit] grid skeleton does not match the real card's text block (DiscoveryGridSkeleton.tsx:19-23 vs DiscoveryCard.tsx:105-140); Tickets uses a spinner (tickets.tsx:105-106) | Each screen's skeleton has the final layout's dimensions; no layout shift when content arrives | — | C |
| CFT-103 | 3 | P1 | partial | Tickets, Explore, Home, Bids | [C] Tickets sets `loading` on every focus and swaps content for a spinner (tickets.tsx:56, :68, :105); [audit] Explore clears results on a failed search (explore.tsx:106, :141) | Returning to a populated screen keeps it visible and refreshes quietly; a failed refresh shows an inline notice over the existing content | — | C |
| CFT-104 | 4 | P1 | partial | listing detail | [audit] seller → transfer → `finalize_auction` run in sequence (ListingDetailScreen.tsx:326-361); a failed seller section disappears with no retry (:1151) | Event info and purchase controls render without waiting on the seller profile; a failed secondary section shows its own retry | **A-13** (reorders the client-triggered `finalize_auction`) | C, A review |
| CFT-105 | 5 | P3 | missing | Home, Tickets, EventMedia | [audit] no prefetch or connection-type logic found (useNetworkStatus.ts:18-24 reads `isConnected` only) | Visible listings' detail and artwork prefetched on Wi-Fi within a memory cap; nothing prefetched on an expensive connection | — | C |
| CFT-106 | 6 | P1 | partial | EventMedia (all), `SellerListingCard.tsx` | [audit] frame reserved and branded fallback when there's no path (EventMedia.tsx:120-141, :174-185); no `onError` fallback when a URL fails; SellerListingCard bypasses EventMedia (:66) | A failing image URL shows the designed fallback in the reserved frame; no white flash; every card uses EventMedia | — | C |
| CFT-107 | 7 | P1 | partial | Home, Explore, Bids, Tickets | [audit] filters and query held only in component state (home.tsx:152, explore.tsx:63); Tickets unmounts its list on refocus (tickets.tsx:105-115); no anchoring on realtime inserts (home.tsx:265) | Scroll position, search text, filters and tab survive opening a listing and returning; a realtime insert does not move what the user is looking at | — | C |

## Batch 2 — Responsive controls, local pending states, press feedback, haptics, accessibility

| ID | Item | Pri | Status | Screens | Evidence | Acceptance (observable) | Deps | Owner |
|---|---|---|---|---|---|---|---|---|
| CFT-201 | 8 | P2 | partial | PlaceBid, SellerListingCard, CreateListing | [audit] shared 0.98 press scale (ui/press.ts:26-45); bid stepper and quick-add chips use plain Pressable (PlaceBidScreen.tsx:196-230) | Every tappable control shows the shared press response | — | C |
| CFT-202 | 9 | P3 | partial | AdaptiveDock, filter chips, bid, checkout | [audit] haptic on every tab tap (AdaptiveDock.tsx:117); none on filter chips, accepted bids or completed purchases | Tab taps silent; light tick on filter selection; confirmation and success haptics fire **only after** authoritative confirmation | **A-17** (confirmation source) | C |
| CFT-203 | 10 | P1 | partial | PlaceBid, listing detail, checkout, transfer receive | [audit] Button hides its label while loading (Button.tsx:111); the "Processing" label is written but hidden (payControl.ts:36); bid success is a "Bid placed" alert (PlaceBidScreen.tsx:132-145) | Visible "Submitting bid…" / "Reserving…" / "Confirming receipt…" while pending; "You're leading" / "Tickets received" only after server confirmation | **A-17** | C |
| CFT-204 | 11 | P3 | partial | notification settings, preferences | [audit] notification toggles are instant with rollback (settings/notifications.tsx:80-94); neighbourhood preferences use a blocking Save (preferences.tsx:61, :93); **save event does not exist** | Preferences update instantly and roll back with a brief explanation on failure. Save event is **blocked** | **A-15** (save-event table/API) | C |
| CFT-205 | 12 | P1 | partial | PlaceBid, listing reserve, transfer confirm/dispute | [audit] payment has a single-flight lock (CheckoutNative.tsx:121); bid and reserve are guarded by React state only (PlaceBidScreen.tsx:99; ListingDetailScreen.tsx:715-729) | A double tap cannot submit twice; progress stays in the control; back navigation remains usable | **A-06** (server-side duplicate protection) | C, A review |
| CFT-206 | 14 | P2 | partial | Sheet, stack transitions, haptics | [audit] `useReducedMotion` used by press, Skeleton, Spinner, OutbidToast (useReducedMotion.ts:16-25); sheets assume the platform respects it (Sheet.tsx:69-71); no haptics setting | With Reduce Motion on, every state change is still shown with simpler transitions; every haptic has a visible equivalent | — | C |
| CFT-207 | 50 | P2 | partial | detail, PlaceBid, checkout, bids, transfer, profile | [audit] price style uses tabular digits (typography.ts:91-94); reservation countdown does not (ListingStatusBanner.tsx:43); three local currency formatters (PlaceBidScreen.tsx:42, SellerListingCard.tsx:43, profile.tsx:59) | Countdown digits don't shift width; every amount formats through `formatCents`; quantity appears wherever a price does | CFT-303 (quantity semantics) | C |
| CFT-208 | 52 | P2 | partial | CreateListing, listing edit, report, delivery form | [audit] text capped at 1.3x (typography.ts:123); forms avoid the keyboard (CreateListingScreen.tsx:565); nothing guards unsaved work on back navigation | Back navigation from a form with unsaved changes asks first; long event names and 1.3x text fit without clipping primary actions | — | C |

## Batch 3 — Purchase and transfer clarity, checkout recovery (misleading behaviour first)

| ID | Item | Pri | Status | Screens | Evidence | Acceptance (observable) | Deps | Owner |
|---|---|---|---|---|---|---|---|---|
| CFT-301 | 24, 27 (extends CFT-E4) | **P0** | partial | checkout | [C] every not-held listing becomes `reservation_expired` (setupDecision.ts:87) → "Your reservation has expired…" (CheckoutNative.tsx:228); "Try again" only re-runs setup (:517) | A hold released after cancel or failure says it was **released**, not expired; when no hold exists the action is **Back to listing**, never a dead "Try again". No re-reserve call from checkout | — (presentation and navigation only) | C |
| CFT-302 | 24 (extends CFT-E3) | **P0** | partial | checkout | [C] F1 fixed on its branch (2ba5281); [audit] the countdown shows relative m:ss only (detailState.ts:211-213), and Pay stays live after the countdown reaches zero (CheckoutNative.tsx:520, :559) | Summary and countdown load; "Held for you until 21:14" shows the actual expiry time; at zero the hold state is re-checked with the server before Pay is offered again | **A-04** (Pay gating at expiry) | C, A |
| CFT-303 | 22 | **P0** | **blocked** | card, detail, checkout, create listing | [C] the charge uses `buy_now_price` and never references quantity (create-payment-intent); the seller sees "You receive $X per ticket" (CreateListingScreen.tsx:807) | "2 tickets · $180 total" on card, detail and checkout, and says when tickets must be bought together — **after** the per-ticket vs whole-listing meaning is decided | **A-01** + owner decision | Owner, A, then C |
| CFT-304 | 23 | **P0** | partial | checkout | [C] the server returns "Price changed. Please review the updated total and try again." (create-payment-intent :533, :640); no client pattern handles it (payments.ts EXPECTED_ERROR_PATTERNS); [audit] a retry resends the stale total (CheckoutNative.tsx:213) | A price change shows the old and new totals and requires a fresh acceptance; a retry never repeats a stale total | **A-02** | C, A |
| CFT-305 | 25 | **P0** | partial | checkout | [audit] the Cancel path checks the server before releasing (CheckoutNative.tsx:368-370); a network error from the sheet shows "Payment connection timed out. Try again." with no check (:424); no AppState or network listener | After an interruption or an uncertain result, "Checking your payment…" reconciles with the server before Pay is offered again | **A-04** | C, A |
| CFT-306 | 26 | P2 | partial | checkout | [audit] one "Processing" label covers confirm and settlement (payControl.ts:36-38); "Finalizing your order" only when pending (CheckoutNative.tsx:669) | "Confirming payment" during confirm and "Finalizing your order" during settlement, each tied to the real step; no percentages | A-04 (step signals) | C |
| CFT-307 | 27 | P1 | partial | checkout, listing detail | [audit] lost hold and sold are plain error text or alerts (CheckoutNative.tsx:228, :384; ListingDetailScreen.tsx:709, :723) | A lost hold or sold listing shows a designed outcome screen with the event still visible, what happened, and a way onward | **A-11** (event key for alternatives) | C |
| CFT-308 | 28 | **P0** | partial | checkout confirmation | [C] `SETTLED_STATUSES = ['succeeded', 'refunded']` (setupDecision.ts:52), so a refunded payment reaches the success screen ("You're in."); "tickets are ready" appears nowhere | A refunded payment never shows a purchase celebration; "Purchase confirmed" only for a completed order; no "tickets ready" wording before the transfer says so | **A-03** (transaction decision) | A, then C |
| CFT-401 | 29 (extends E1, E2) | P1 | partial | transfer receive/send | [audit] buyer screen renders pending, seller_sent, confirmed, disputed only (receive/[id].tsx:257-302); no body for auto_released, expired, reversed | One order status screen shows every state including exceptions, with a "Who acts next" line on each | **A-09**, **A-14** | C |
| CFT-402 | 30 | P1 | partial | transferState, bidState, TransferStatusBadge | [audit] "Sent" / "Tickets sent" / "Transfer Sent" state the seller's claim as fact (transferState.ts:42, bidState.ts:153, TransferStatusBadge.tsx:7) | "Seller marked tickets as sent" until the buyer confirms; "Tickets received" only after confirmation, on every surface | — | C |
| CFT-403 | 31 (extends E1) | P2 | partial | receive, DeliveryInfoForm | [audit] V2 surfaces delivery details at the top; no verify or edit step (receive/[id].tsx:221-233) | Buyer confirms delivery details before the seller sends and can correct them while allowed | **A-12** | C |
| CFT-404 | 32 | P2 | missing | receive, PlatformInstructions | [audit] no provider link; fetch on mount only (receive/[id].tsx:94) | Returning from the provider lands on the order with "Did the tickets arrive?" and a report option; status refreshed on return | — | C |
| CFT-405 | 33 (extends E1) | P1 | partial | receive | [audit] V2 adds "Only confirm once you have the tickets"; confirm calls the release with no second confirmation (receive/[id].tsx:127-131) | "Confirm receipt" explains what to check and that it releases payment, and asks once more before calling | **A-17** (money-release flow review) | C, A review |
| CFT-406 | 34 | P2 | partial | receive, support | [audit] dispute sends only the id (receive/[id].tsx:167); support is a plain mailto (support.tsx:21, :36) | "I haven't received my tickets" carries the order and status into support from any transfer state | **A-09**, **D-01** | C, A, D |
| CFT-407 | 35 | P2 | missing (native part deferred) | new event-day view, Bids, receive | [audit] no event-day view; event date/time exist in data (types/index.ts:104-105) | The next event shows time, venue directions, transfer status and provider link; the card is visibly an order, never credential-like | CFT-801 stays separate | C |
| CFT-408 | 39 | P1 | partial | My Listings, SellerListingCard, detail, profile | [audit] "Action needed — send the tickets" with no deadline (SellerListingCard.tsx:98); payout setup enforced only at publish (CreateListingScreen.tsx:453-470) | Each seller card shows one next action with its deadline ("Transfer these tickets by 21:14", "Finish payout setup") | — | C |
| CFT-409 | 40 | P1 | partial | send, payout setup, badges | [audit] "Your payout has been released" (send/[id].tsx:272, :281); "Payouts deposit automatically when your listings sell" (payout-setup.tsx:153) | Distinguishes awaiting release, sent to payout account, and bank deposit (when known); no bare "Paid" | **A-10** | C, A |

## Batch 4 — Auction states and reconnection

| ID | Item | Pri | Status | Screens | Evidence | Acceptance (observable) | Deps | Owner |
|---|---|---|---|---|---|---|---|---|
| CFT-501 | 15, 17 | P1 | partial (server time: blocked) | detail, Bids, PlaceBid | [audit] position states exist on detail (detailState.ts:195-230); between clock zero and finalisation a possible winner sees "Auction ended" (:206); clocks use device time (ListingDetailScreen.tsx:95-97); no resume correction | At zero, "Confirming result…" until the winner is authoritative; position visible on Place Bid; countdown corrected on resume | **A-05** | C, A |
| CFT-502 | 16 | P2 | partial | detail, TransactionPanel | [audit] bids update in place (useListingRealtime.ts:176-179); a non-silent refetch replaces the screen (ListingDetailScreen.tsx:727) | A new bid animates the changed amount and updates the minimum without a spinner or scroll loss | — | C |
| CFT-503 | 18 | P1 | partial | PlaceBid | [audit] floor fetched once (PlaceBidScreen.tsx:56-69); raw DB error in an alert (:134-135); client increment vs server rule may differ (bidEntry.ts:23-25) | If outbid while entering, the amount is kept, the new minimum is explained, and a fresh tap is required | **A-06** | C, A |
| CFT-504 | 19 | P1 | missing | detail, useListingRealtime | [audit] CHANNEL_ERROR / TIMED_OUT only logged (useListingRealtime.ts:210-217) | Interrupted live updates show "Reconnecting — bid status may be delayed" and mark price and countdown as not live | — | C |
| CFT-505 | 20 | P1 | partial | Bids | [audit] active sorted by priority (bids.tsx:268-269); no ending-soon rank; an unfinalised clock-out drops into Past as lost (bidState.ts:72, :86-89); no live updates on Bids | Outbid, ending soon and won-unpaid first; an ended but unfinalised auction stays in Active until authoritative | A-05 | C |
| CFT-506 | 21 | P3 | missing | detail, Bids | [audit] "You did not win this one." with no follow-up (detailState.ts:201) | A loss offers same-event listings first, keeping date, quantity and budget preferences | **A-11** | C |
| CFT-507 | 43 | P1 | partial | Home, Bids, Tickets, transfer | [audit] quiet catch-up only on listing detail (ListingDetailScreen.tsx:505-508); no foreground refresh on data screens | On reconnect or return to foreground, visible data refreshes quietly without navigation reset or notification bursts | — | C |

## Batch 5 — Offline order access, seller drafts, notification links, event day

| ID | Item | Pri | Status | Screens | Evidence | Acceptance (observable) | Deps | Owner |
|---|---|---|---|---|---|---|---|---|
| CFT-601 | 41 | P2 | missing | orders, transfer, venue | [audit] only the encrypted session is persisted (secureStorage.ts:35-40); offline transfer shows an error (receive/[id].tsx:86); no data cache library | Upcoming orders, venue info and transfer instructions are readable offline with "Updated 14:02"; cache keyed by account and cleared on sign-out; availability always refreshed before bid or purchase | A-17 (never authorise from cache) | C |
| CFT-602 | 42 | P2 | partial | PlaceBid, CreateListing, receive | [audit] bids and confirmations are live-only (PlaceBidScreen.tsx:126-135; receive/[id].tsx:131); no draft queue | Offline, drafts and preference changes are kept for later; bids, purchases, confirmations and payout actions say "Not placed — you're offline" | — | C |
| CFT-603 | 44 | P2 | missing | auth, root route | [audit] every sign-in goes to Home (rootRoute.ts:72); no return-to parameter | Signing in from a listing or a notification returns to that screen and intended action | — | C |
| CFT-604 | 45 | P2 | partial | Home, Bids, Explore, Tickets, My Listings | [audit] loading, error and empty are mostly separate (home.tsx:376-380); filtered empty is generic "No matches"; a failed refresh over data shows no notice; [C] price filter compares `current_bid` (home.tsx:333-334) | Empty, failed and filtered screens have distinct copy and actions ("No matches under $99"); the price filter's basis matches the price the card shows | — | C |
| CFT-605 | 46 | P2 | partial | detail | [audit] ended or sold shows a status label; "Listing not found" offers only "Go back", which fails on a cold start (ListingDetailScreen.tsx:966-973) | An old link to an ended or sold listing opens an outcome screen with a Browse path, never a dead end | A-11 | C |
| CFT-606 | 47 (extends CFT-E6) | P1 | partial | NativeAppShell, detail | [C] the outbid push body has only user_id, title and body (054 migration); [audit] every notification shown in foreground (NativeAppShell.native.tsx:47-50) | An outbid push opens its auction and a transfer update opens its order; alerts for the screen already open are suppressed; any future inbox on `notify.*` supersedes stale deletion notices | **A-07** | C, A |
| CFT-607 | 48 (extends E2) | P1 | partial | useAuth, transfer, Bids, profile | [audit] expired session signs out silently (useAuth.ts:52-63); expired and refunded transfers filtered out of Bids (bids.tsx:201) | Session expiry, cancelled events, late transfers, refunds and unavailable profiles each show a status and a next step | **A-09** | C, A |
| CFT-608 | 36 | P2 | missing | CreateListing | [audit] form state in memory only (CreateListingScreen.tsx:283-318) | Leaving and returning offers "Continue your listing" with fields and picked images restored; drafts cleared per account on sign-out | — | C |
| CFT-609 | 37 | P1 | partial | CreateListing | [audit] "You get $X" per ticket (CreateListingScreen.tsx:690-692, :721-723) | Net shown per ticket and for the whole listing beside the price input, with auction proceeds marked as depending on the final bid | CFT-303 / **A-01** | C |
| CFT-610 | 38 | P2 | partial | CreateListing, useImageUpload, MediaUpload | [audit] status only, no progress (useImageUpload.ts:42); re-uploads to new paths (:140-162); sequential with stop at first failure (CreateListingScreen.tsx:480-495) | Per-image progress; successful uploads kept; a failed image retries on its own; no orphaned files | — | C |
| CFT-611 | 41 (privacy finding) | **P0** | missing | sign-out paths | [C] the privacy page says tokens are marked inactive at sign-out (privacy.tsx:109), but no client code revokes one; the `notify` schema is not API-exposed | Signing out stops push notifications to that device for that account, matching the privacy page | **A-08** | A, then C |

## Batch 6 — Visual refinement and device verification

| ID | Item | Pri | Status | Screens | Evidence | Acceptance (observable) | Deps | Owner |
|---|---|---|---|---|---|---|---|---|
| CFT-701 | 13 | P3 | partial | stack, sheets, checkout | [audit] default stack animation (app/_layout.tsx:123); sheets slide (Sheet.tsx:71); purchase complete is static text (CheckoutNative.tsx:672) | Card artwork transitions into detail; one celebration reserved for confirmed milestones, respecting Reduce Motion | CFT-206 | C |
| CFT-702 | 49 | P3 | partial | ListingHero, EventMedia | [audit] blurred art backdrop only in fit mode (EventMedia.tsx:18-23) | Event header carries a restrained artwork-derived tint; price and controls pass contrast in both themes | — | C |
| CFT-703 | 51 (extends CFT-E5) | P1 | partial | transfer, PlaceBid, deletion sheet | [audit] raw server text under a bare "Error" title (send/[id].tsx:136; PlaceBidScreen.tsx:134); F3 raw tokens in the deletion sheet | No raw server messages anywhere; payment, transfer and refund failures use calm, exact copy; every deletion blocker kind has a sentence | — | C |
| CFT-704 | 53 | P2 | partial | Home, Bids, Explore, detail, receive | [audit] no shared store; each screen fetches on focus; Explore not on focus (explore.tsx:71); receive updates locally only (receive/[id].tsx:148) | A bid, sale or order update changes on every screen that shows it without a manual refresh | CFT-507 | C |
| CFT-705 | 54 | P2 | partial | test suite, device procedure | [audit] re-entry and 3DS return tests exist (checkout-setup-reentry.test.ts; checkout-3ds-return-and-session.test.ts); no tests for notification open, provider switch, auction-end reconnect or unfinished listing; no blank-screen or tap-feedback metrics | Automated and device checks cover the five interruption paths; blank-screen time and tap-to-feedback are measured | device/simulator access (owner) | C |
| CFT-801 | (native Tickets, not a checklist item) | P3 | deferred | Tickets | [C] 0 native tickets; issuance disabled; fixtures `__DEV__`-only | Populated Tickets state verified once native issuance exists; kept distinct from marketplace orders | native issuance (owner) | C |

---

## Coverage index — every checklist item

| Item | Task | Item | Task | Item | Task |
|---|---|---|---|---|---|
| 1 | CFT-101 | 19 | CFT-504 | 37 | CFT-609 |
| 2 | CFT-102 | 20 | CFT-505 | 38 | CFT-610 |
| 3 | CFT-103 | 21 | CFT-506 | 39 | CFT-408 |
| 4 | CFT-104 | 22 | CFT-303 | 40 | CFT-409 |
| 5 | CFT-105 | 23 | CFT-304 | 41 | CFT-601, CFT-611 |
| 6 | CFT-106 | 24 | CFT-301, CFT-302 | 42 | CFT-602 |
| 7 | CFT-107 | 25 | CFT-305 | 43 | CFT-507 |
| 8 | CFT-201 | 26 | CFT-306 | 44 | CFT-603 |
| 9 | CFT-202 | 27 | CFT-307, CFT-301 | 45 | CFT-604 |
| 10 | CFT-203 | 28 | CFT-308 | 46 | CFT-605 |
| 11 | CFT-204 | 29 | CFT-401 | 47 | CFT-606 |
| 12 | CFT-205 | 30 | CFT-402 | 48 | CFT-607 |
| 13 | CFT-701 | 31 | CFT-403 | 49 | CFT-702 |
| 14 | CFT-206 | 32 | CFT-404 | 50 | CFT-207 |
| 15 | CFT-501 | 33 | CFT-405 | 51 | CFT-703 |
| 16 | CFT-502 | 34 | CFT-406 | 52 | CFT-208 |
| 17 | CFT-501 | 35 | CFT-407 | 53 | CFT-704 |
| 18 | CFT-503 | 36 | CFT-608 | 54 | CFT-705 |

**Status totals (54 items):** implemented 0 · partial 43 · missing 9
(items 1, 5, 19, 21, 32, 35, 36, 41, 44) · blocked 2 (17, 22) · deferred 0 (the
native Tickets part of item 35 is deferred under CFT-801). Item 17's client-side
"Confirming result…" state can start; only its server-time correction is blocked.

---

## Dependencies on A (transaction correctness, contracts, migrations, release)

| ID | Exact dependency | Tasks |
|---|---|---|
| A-01 | **Quantity semantics.** The charge is `buy_now_price` with no quantity factor, while the seller is told "per ticket". Decide per-ticket vs whole-listing, then the contract | CFT-303, 609, 207 |
| A-02 | **Price-change contract.** Server returns "Price changed…"; define how the client gets the new total and re-accepts without resending a stale total | CFT-304 |
| A-03 | **Refunded counted as settled** in checkout setup (`SETTLED_STATUSES`). Correct the success semantics without re-enabling purchase of a refunded listing | CFT-308 |
| A-04 | **Uncertain-payment reconciliation and Pay gating**: when Pay may be offered again after an interruption, an unreachable check, or hold expiry | CFT-302, 305, 306 |
| A-05 | **Auction result authority and server time**: client-triggered `finalize_auction`, the source for "Confirming result…", clock correction | CFT-501, 505 |
| A-06 | **Bid rules**: client minimum increment vs server rule; server-side duplicate-bid protection | CFT-503, 205 |
| A-07 | **Notification payloads**: outbid push has no `data`; expiry, refund and auto-release pushes carry `listingId` only | CFT-606 |
| A-08 | **Push-token revocation on sign-out** (privacy page claim; `notify` not API-exposed) | CFT-611 |
| A-09 | **Transfer exception states and disputes**: expired and reversed states, dispute outside `seller_sent`, dispute reason | CFT-401, 406, 607 |
| A-10 | **Payout status contract**: awaiting release vs sent vs bank deposit | CFT-409 |
| A-11 | **Event key for alternatives** (same-event listings) | CFT-307, 506, 605 |
| A-12 | **Delivery-details edits**: confirm the RPC's allowed states for editing after save | CFT-403 |
| A-13 | **Listing detail read order**: parallelising reads reorders the client-triggered `finalize_auction` | CFT-104 |
| A-14 | **`auto_release_at` in the buyer transfer query** (owner decision already pending) | CFT-401 |
| A-15 | **Save event** needs a table and API | CFT-204 |
| A-16 | **Migration allocation**: any contract above needing DDL takes its number from A's registry | all backend-dependent tasks |
| A-17 | **Review of confirmation sources** for pending/success states, haptics, receipt confirmation and cache rules — frontend must not alter transaction semantics | CFT-202, 203, 205, 405, 601 |

## Routed to D (vendor/admin dashboard)

| ID | Work | Tasks |
|---|---|---|
| D-01 | Admin support intake that receives the order, its status and the dispute reason | CFT-406 |
| D-02 | Admin view of payout release/sent/deposit states consistent with the consumer wording | CFT-409 |

No D session is identifiable from C's session; the owner routes these.

## Owner decisions needed

1. Quantity meaning (per ticket or whole listing) — gates CFT-303, 609.
2. `auto_release_at` in the buyer transfer query — gates CFT-401's countdown.
3. Device or simulator access for visual acceptance (Transfer UI V2) and CFT-705.

## Recommended first implementation batch

Isolated branch `frontend/premium-batch-1`, cut from `df9e0d3` with the approved
F1 commit. No transaction behaviour change.

1. **CFT-301** — D9-UX-1: released vs expired wording, and **Back to listing**
   instead of the dead "Try again". P0; presentation and navigation only.
2. **CFT-302 (frontend part)** — carry F1, and show the hold's actual expiry
   time. Pay gating at zero waits for A-04.
3. **CFT-103** — quiet refresh with no full-screen spinner over populated
   content, starting with Tickets.
4. **CFT-106** — image `onError` fallback, and SellerListingCard on EventMedia.
5. **CFT-101** — listing detail opens with the tapped card's content.
6. **CFT-107 (first slice)** — Tickets keeps its scroll; Home anchors against
   realtime inserts.

Held for A before any frontend work: **CFT-303, 304, 305, 308, 611** (all P0).

---

## Rulings from A on the P0 holds and the first batch (2026-09-14)

A re-read `df9e0d3` and the sandbox read-only. **Three holds are released with
frontend-only contracts (A-02, A-03, A-04); two need the owner (A-01, part of
A-08). No frontend task needs a server change.** A reviews every PR touching
`payments.ts`, `setupDecision.ts`, `payControl.ts` or the sign-out helper.

### A-01 Quantity — HELD FOR THE OWNER (CFT-303, CFT-609)
The money path prices the **whole listing**: `create-payment-intent` charges
`buy_now_price` once (:477), or `winning_bid`/`current_bid` for an auction
(:499), and fees and payout come off that single base (:514-518). Buyer detail
shows "Quantity: N tickets" with one price (ListingDetailScreen.tsx:1041). Only
two seller strings say per ticket: "You receive $X per ticket"
(CreateListingScreen.tsx:807) and the sticky "$X / ticket" when quantity > 1
(:846). The sandbox has 0 listings with quantity > 1; production was not read.
**A recommends the owner ratify whole-listing pricing** — what the server already
does — and fix the two strings (frontend only). Per-ticket pricing would change
amount, fees, payout, refunds and partial purchase: a transaction change with
migration and edge work, outside Premium scope.

### A-02 Price change — RELEASED (CFT-304)
**Worse than the audit said — a dead loop, verified by A.**
`expected_total_cents` comes from the route param (CheckoutNative.tsx:87, sent at
:213). "Try again" (:517) re-runs setup with the same stale param, so the server
returns 409 on every retry. The message is not in `EXPECTED_ERROR_PATTERNS`
(payments.ts:37-53), so the buyer sees the generic safe error and it is reported
as a failure, contradicting the comment at :333. No new server contract is
needed: both 409 paths already return `server_total_cents` (CPI :532-535 fresh;
:640-647 reuse, which also cancels the stale PaymentIntent at :633).
**Contract.**
1. Add `/price changed/i` to `EXPECTED_ERROR_PATTERNS`.
2. On that 409, re-read the listing and compute the all-in total with
   `allInFromDollars`. It must equal `server_total_cents`; if not, show the safe
   error and offer no Pay.
3. Show the new total; Pay requires a fresh explicit tap on it.
4. Hold the accepted total in state, not the route param, and send it as
   `expected_total_cents`; the server re-verifies.

Never auto-accept, and never send a total the buyer has not seen.

### A-03 Refunded — RELEASED, copy needs the owner's wording (CFT-308)
Confirmed: `SETTLED_STATUSES = ['succeeded','refunded']` (setupDecision.ts:52)
leads to `already_settled`, then `setSettlement('completed')` (:218-221), then
"You're in." (:672). **Second defect:** `fetchSettledPayment` uses
`.in(status, both).limit(1).maybeSingle()` with no ordering (:188-195), so a buyer
holding both a refunded and a succeeded row gets an arbitrary one.
**Contract.** Keep `refunded` in the no-setup set, so this route never creates or
presents an intent. Add a decision kind `refunded` with its own non-success state
and Back to listing; `already_settled` covers succeeded only. Check succeeded
first, then refunded. Pure tests go in setupDecision. Whether a refunded buyer
may buy a relisted listing is a product question outside scope; today's block is
the safe default.

### A-04 Pay gating and reconciliation — RELEASED (CFT-302, CFT-305); server gap L4 is A's
Confirmed: `payControl` has no expiry input (payControl.ts; CheckoutNative.tsx:507-514),
and `reservationExpired` (:520) drives display only, so Pay stays live at 0:00.
**Server gap, L4 (A's item):** nothing cancels a PaymentIntent at hold expiry.
The sheet can still confirm, and if another buyer took the listing, settlement is
`unfulfillable` and the sweep refunds (20260906110000 :72-79) — no double sale,
but charge-then-refund is possible.
**Contract.**
1. Take Pay out of `pay` when `reservationMsLeft` ≤ **15 s**. The margin absorbs
   device-vs-server clock skew; A owns the number.
2. At that point, re-check with existing dependencies: `fetchSettledPayment`
   first, then the hold via `holdIsMine`. Succeeded → completed; still held
   (clock skew) → re-offer Pay; otherwise → a no-longer-held state with Back to
   listing.
3. After **any non-Canceled** sheet error, call
   `confirmPaymentSuccess(paymentIntentId)` (the check `releaseAbandonedHold`
   uses, :368) before re-offering Pay. Verified → settlement path; reachable and
   not verified → Pay only while the hold is live; **unreachable → a calm
   "checking" state and no Pay.** The webhook, the sweep and the 10-minute hold
   expiry are the backstop.

Never re-offer Pay after an unreachable check.

### A-08 Privacy — PARTLY HELD FOR THE OWNER (CFT-611)
- **(a) The privacy page is currently untrue.** It says tokens are "automatically
  marked inactive when you sign out"; none of the 5 sign-out sites touches
  `push_tokens` (reset-password.tsx:34, profile.tsx:209, settings/index.tsx:126
  and :197, useAuth.ts:62). **Correcting the copy is an owner/legal decision.**
- **(b) Cross-account token binding, reproduced by A and verified by C.** The
  sandbox holds exactly **one** `push_tokens` row, owned by the other test
  account (`1fcd0c69`): iOS, active, last used 2026-09-10 17:33Z, never revoked.
  Buyer `919d511e` has **none**, and `UNIQUE(token)` exists. SnatchIt/16's
  registration reads the table and then gets **409 on insert** at both of today's
  sign-ins (04:25:50.931Z and 04:41:20.813Z). Mechanism (A): `usePushToken`
  selects by token, RLS hides the other user's row, the insert conflicts. Effect:
  this phone would receive the other account's pushes and none of the buyer's
  (`send-push` filters `is_active=true`, :70). **Same token, deduced (A; verified by C):** PostgREST returns 409 for SQLSTATE 23505 (unique violation; an RLS failure would be 403); the table's only unique indexes are `push_tokens_pkey(id)` and `push_tokens_token_key(token)`; `id` defaults to `gen_random_uuid()` and the app's insert sends only `user_id`, `token`, `platform`, `is_active` (usePushToken.ts:85) — so the conflict can only be on `token`, with one row present. Remaining assumption: no other row existed at 04:25/04:41Z and was deleted since. Token values not printed or compared.
  **Production exposure unknown** (no production read).
- **(c) Frontend part — RELEASED.** One sign-out helper for all 5 sites: before
  `signOut`, while the JWT is still valid, set `is_active=false`,
  `revoked_at=now()`, `revoked_reason='sign_out'` on this device's
  `public.push_tokens` row. Sandbox RLS allows it (owner UPDATE policy,
  authenticated UPDATE grant). Best-effort with a short timeout; never block
  sign-out.
- **(d) Server part — HELD FOR THE OWNER, A's.** Sign-out revocation cannot fix a
  token already stuck on another account (reinstall, expired session, deleted
  account). `notify.register_push_token` already rebinds on token conflict to
  `auth.uid()`, but `notify` is not API-exposed. The fix is a narrow `public`
  wrapper RPC with a registry number (A-16), not exposing `notify`. A will not
  prepare it without the owner.

### Conditions on the first batch (A)
- **CFT-301.** "Back to listing" must be a normal back navigation
  (`router.back`), so ListingDetail's `beforeRemove` / `reservationExit` path
  still runs — no replace that skips it, and no reserve or release call added in
  checkout. Say **"released"** only when this screen's own `release_reservation`
  call succeeded (:372-384); the server cannot tell released from expired (both
  leave the listing active with the hold fields null). Otherwise use neutral
  wording such as "no longer held for you". Keep "Try again" for transient or
  unverifiable setup errors (sheet init failure, 503, `reservation_unverifiable`),
  where the hold may still be live.
- **CFT-302.** F1 (`2ba5281`) already approved; an absolute "until 21:14" from
  the server's `reserved_until` is fine; gating per A-04.
- **CFT-103.** Fine. It changes the loading flash T recorded, so **re-run T on the
  next build**. Keep it off checkout.
- **CFT-106.** Fine. **Live reproduction:** the handset's
  `GET /storage/v1/render/image/public/auction-media/fixtures/{P1,D7,D8}.jpg`
  returns **400** (04:25:51Z and 04:41:21Z today, UA SnatchIt/1.0.0; verified by
  C).
- **CFT-101.** A-17 applies: card content is display-only; Buy now and Bid stay
  disabled until the fresh listing row arrives (status, hold, `buy_now_enabled`,
  price, `ends_at`); the `totalCents` param sent to checkout comes from the fresh
  row, never the card snapshot, because checkout sends it as
  `expected_total_cents` (A-02).
- **CFT-107.** Fine. Anchoring must not suppress realtime removals
  (home.tsx:268-287 drops sold or non-active listings).

**Holds now:** CFT-303 and CFT-609 (owner: quantity); CFT-611 server part and the
privacy copy (owner). **Released to C with contracts:** CFT-304, CFT-308 (owner
copy), CFT-302/CFT-305 (A-04), CFT-611 frontend helper.

---

## Batch 1 — status (2026-09-14, C)

Owner's go received 2026-09-14 with product direction: preserve whole-listing
pricing and label the total for the listed quantity; remove the seller
"per ticket" copy; make the privacy wording match implemented behaviour without
claiming deactivation works until verified; "Payment refunded" only for a
confirmed refund, a distinct pending state, no bank-arrival promise, no
purchase success; coordinate notification rebinding with A. Authorised:
isolated development and local verification only.

Branch **`frontend/premium-batch-1`** (worktree `snatchit-batch1`), cut from
the approved F1 commit `2ba5281`. Build 16 untouched. Nothing deployed.

| Commit | Tasks | Contract | State |
|---|---|---|---|
| `bcbb106` | CFT-301, 302, 304, 305, 308, 303 (label) | A-02, A-03, A-04; owner ruling on quantity | **landed; with A for review** |
| `5cb53f3` | CFT-609 | owner ruling | landed |
| `72ec91d` | CFT-611 (frontend), privacy copy | A-08(c) | **landed; with A for review** |
| — | CFT-103, 106, 101, 107 | A's batch conditions | in progress on the same branch |

**How the direction landed.**
- *Whole-listing pricing:* unchanged calculation; checkout shows the ticket
  count beside the total ("2 tickets" row, "covers all 2 tickets"); the seller
  sees "$X for all 2 tickets" / "You get for 2 tickets" — no "per ticket".
- *Refunds:* `refunded` = `refunded_at` set and `amount_refunded_cents ≥ total`
  → "Payment refunded"; anything else with status refunded → "Refund in
  progress". Neither promises bank timing or shows success; both offer Back to
  listing. (`payment_refunds` is not readable by the client, so the payments row
  is the only source.)
- *Privacy copy:* now describes an attempt and its failure mode. It does not
  claim deactivation works; that stays **unverified** until a build carrying the
  helper runs on a physical device.
- *Rebinding:* not attempted client-side. A token bound to another account is
  invisible under RLS (`no_match`); A-08(d) remains A's, on the owner's word.

**Gates at `72ec91d`:** tsc clean; vitest 1677 passed (71 files); expo lint 0
errors, 29 warnings (baseline).

**Previews.** A simulator build is feasible locally (Xcode 26.6, iPhone 17 Pro,
sandbox-only build script with pairing guards; native project generated in the
batch worktree). **Limit flagged:** checkout states (hold loss, Pay gating,
price change, refund screens) need a live reservation, which is a write to the
shared sandbox; not done without an explicitly scheduled window. Read-only
screens (Home with image fallback, listing detail handoff, Tickets, filter
sheet, create-listing proceeds copy, privacy page) can be previewed.

**Deferred inside this batch.** CFT-306 (split "Processing" into confirming vs
finalizing) waits on A-04's step signals; CFT-307's alternatives wait on A-11.

### Batch 1 — review round 1 closed (A, 2026-09-14)

**A approved all four payment/sign-out commits**, verified in the source:
`bcbb106`, `5cb53f3`, `72ec91d` and **`31b264c`** (the review changes). The
payment and sign-out half of batch 1 is cleared from A's side; nothing merges
or deploys, and the review gate still applies to any later change to
`payments.ts`, `setupDecision.ts`, `payControl.ts`, the sign-out helper or an
authoritative-state read.

| Review item | Disposition |
|---|---|
| Required 1 — auction price column | fixed: `winning_bid_amount ?? current_bid`, mirroring `create-payment-intent:499` |
| Required 2 — Pay re-offer from the device clock | fixed: one `revalidateAgainstServer()` (settled first, then the hold via a fresh listing read) serves the margin effect and the manual re-check; Pay returns only on `held` |
| Q1 unreachable → reachable re-offer | C's reading confirmed; built to it |
| Q2 `ran_out` from the displayed deadline | accepted as implemented |
| Q3 refund-confirmed rule | server's writer stamps status, amount and date together; `refund_pending` kept as documented, unreachable insurance |
| **F8 (new)** partial refund on a `succeeded` row reached the success screen | fixed in-batch: `partially_refunded` kind with the amount; "Your order stands…", Back to home; still blocks a new intent |
| Nit — revoke timer | cleared |

**Consequence carried into the Build 16 verdict:** CFT-103 changes the Tickets
loading behaviour that test T recorded, so **T is re-run on the next build**.

**Window:** the `reserve_buy_now` write needed to preview the held-checkout
states is in the shared-sandbox window scope A has put to the owner, with an
explicit `release_reservation` after each preview. Not run until scheduled.

### Batch 1 — complete on the branch (2026-09-14, C)

All batch-1 items are committed on `frontend/premium-batch-1` (HEAD
**`43e3a97`**). Local only; nothing merged, applied or deployed; Build 16
unchanged.

| Commit | Task | What landed |
|---|---|---|
| `bcbb106` + `31b264c` | CFT-301/302/304/305/308, 303 label | approved by A |
| `5cb53f3` | CFT-609 | approved by A |
| `72ec91d` | CFT-611 (frontend), privacy copy | approved by A |
| `88bd09e` | CFT-103 | pure `refreshPolicy` (shouldShowLoading / phaseAfterError / failureSurface); Tickets refreshes quietly over rows or a settled empty state; Search keeps prior results with an inline notice and Retry, no server text; copy, queries and the `__DEV__` toggle untouched |
| `6bca7ac` | CFT-106 | EventMedia `onError` takes the existing branded fallback in the same frame (keyed by URI so recycled rows start clean); SellerListingCard renders through EventMedia; queries unchanged |
| `26c0f4e` | CFT-101 | bounded in-memory card handoff (`cardHandoff.ts`, tolerant parser); Home/Search stage cover, name, venue, date/time, price label, then push the unchanged route; detail paints them immediately with no transactional control until the fetched row arrives; both `totalCents` computations still read the fetched row (pinned by test) |
| `43e3a97` | CFT-107 (first slice) | `maintainVisibleContentPosition` on the Home feed with realtime handlers pinned verbatim; Tickets list stays mounted across focus |

**Gates at `43e3a97`:** tsc clean; vitest **1730 passed (74 files)**, +53 over
the batch baseline; expo lint 0 errors / 29 warnings (baseline). CFT-103/106/
101/107 fall outside A's review gate and were not sent for review.

**Deviations recorded.** CFT-101 uses an in-memory handoff rather than route
params (existing guards pin the literal `/listing/${id}` push; no route file
edit). CFT-106 has no behavioural failed-URL test because image failure is a
runtime load event, not a resolver path; the component's handling is guarded
from source. No blur placeholder was added (it would cost a request per image).

**Previews — BLOCKED on this machine; owner access needed.** A sandbox-only
Release build was attempted twice. The native project generates and CocoaPods
installs, but `xcodebuild` lists **no iOS Simulator destination**: Xcode 26.6
carries the iphonesimulator 26.5 SDK, only the iOS 26.2 simulator runtime is
installed, and Xcode reports "iOS 26.5 is not installed". The documented
remedy (`xcodebuild -downloadPlatform iOS`, ~9 GB, needs ~20 GB free) is not
possible with **2.8 GB free**. Nothing was downloaded or changed in Xcode.
Options for the owner: free disk and install the iOS 26.5 platform here; or a
device/EAS build under a sandbox profile at a scheduled window (a hosted build,
so it needs explicit authorisation); or accept static previews for now. The
held-checkout states additionally need the scheduled sandbox window.

**Follow-ups already recorded:** T re-run on the next build (CFT-103 changed
the loading behaviour); A-08(d) rebinding; owner wording for the refund copy.

**Preview attempt 3 (explicit destination, A's suggestion) — failed the same
way.** `-destination "platform=iOS Simulator,id=<iPhone 17 Pro>"` against the
booted iOS 26.2 runtime: xcodebuild still lists no eligible simulator
destination and reports "iOS 26.5 is not installed". So the blocker is the
missing iOS 26.5 simulator platform, not the destination syntax. Nothing was
downloaded or changed in Xcode; the temporary Metro config and build directory
are removed. The options recorded above stand, and the decision is the owner's.

**Preview blocker closed as settled (A + C, 2026-09-14).** A checked the one
remaining hypothesis — the deployment target is 15.1 (`ios/Podfile:19` and
`project.pbxproj`), far below the installed 26.2 runtime — so an
ineligible-by-target explanation is dead. Cause: Xcode 26.6 will not pair its
26.5 SDK with the 26.2 simulator runtime for this scheme. Not fixable for
free; recorded in A's release package with the evidence so it is not
re-investigated. **A's recommendation to the owner: defer previews** to the
next build authorised for another reason, on the grounds that visual preview
is not a correctness gate for batch 1 (1730 tests, source contracts, A's
line-level review of every gated file), the disk cost is real, a hosted build
adds a non–Build 16 artefact to the record, and the held-checkout previews need
the sandbox window regardless. C concurs. Static previews of the read-only
screens remain the zero-cost middle path if the owner wants visual acceptance
sooner.

---

## Batch 2 — status (2026-09-14, C)

Branch `frontend/premium-batch-2` in `/Users/josetascon/snatchit-batch1`, from
batch 1's approved head `43e3a97`. Seven commits, oldest first:

| Commit | Scope | Tasks |
|---|---|---|
| `53d3fbf` | Button `pendingLabel` (visible label + spinner, width held, read by VoiceOver); `Tappable`; `src/lib/feedback/haptics.ts` (select / confirm / success / warning); dock silent; Chip ticks; `createSingleFlight` / `useSingleFlight`; Sheet and root Stack cross-fade under Reduce Motion | 201, 202, 203, 205, 206 |
| `de6dc09` | Place bid: "Submitting bid…", lock, outcome from a fresh `current_bid` read after the insert ("You're leading" / "Bid placed, but outbid" / "Bid placed"); confirm haptic after acceptance; `formatDollars` | 201, 203, 205, 207 |
| `7f6284e` | Buy Now "Reserving…" behind a lock; receive splits `submitting` into `confirming` / `disputing`, "Confirming receipt…" / "Reporting…", one lock over confirm-and-release and dispute, success haptic after the edge function succeeds; delivery form on the shared Button ("Saving…") | 201, 203, 205 |
| `4b705c4` | **Checkout, display only, for A's review**: Pay button passes payControl's label as `pendingLabel` while loading; one success haptic keyed on the `completed` outcome; tabular digits on the hold row | 202, 203, 207 |
| `ed0adcf` | `formatDollars` replaces the seller-card and profile formatters; tabular digits on the listing banner detail and the receive countdown; seller row + Edit/Delete/Cancel are `Tappable`; sticky price beside Place bid capped like the CTA | 201, 207, 208 |
| `afa2967` | Your scene: instant chips, latest-wins background save (`createCoalescedSaver`), rollback + inline notice + VoiceOver announcement, "Done" waits for settle; Notifications: inline revert notice instead of a modal alert; unsaved-changes guard (`useUnsavedChangesGuard`, `shouldAskBeforeLeaving`, `UNSAVED_COPY`) on Edit listing, Report and Your scene-while-saving; "Saving…" / "Sending report…" | 204, 208 |
| `3c78382` | `docs/product-v2/previews/premium-static-previews.html` — STATIC previews of the batch 1 + 2 screens, every string pinned to its source module by `tests/premium-static-previews.test.ts` | previews |

**Gates.** `tsc --noEmit` clean; vitest 1795 tests / 79 files (batch 1 was
1730 / 74); `expo lint` 0 errors / 29 warnings (batch 1's baseline); the
touched files carry 0 lint errors. Payment/sign-out gated files
(`payments.ts`, `setupDecision.ts`, `payControl.ts`, `signOut.ts`) untouched.

**Per task.**
- CFT-201 — done for every non-primitive control the batch touched (stepper,
  quick-add, seller row and its actions, delivery submit). Remaining: the raw
  pressables inside CreateListing's pickers (SelectRow) — batch 6 polish.
- CFT-202 — done. Tab taps silent; Chip = light tick; confirm = after the bids
  insert returned without error; success = after confirm-and-release success
  and on checkout's `completed` outcome; warning = the existing outbid path.
  No in-app haptics switch: iOS applies the system setting; an app-level
  toggle needs a preference column (adjacent to A-15).
- CFT-203 — done. Pending labels everywhere a submission runs; no success
  copy before the server's answer. "You're leading" comes from a fresh read
  with the Bids tab's own rule (`bidStatusOf`: amount ≥ current_bid), so the
  two screens tell one truth (item 53). Receipt success wording ("Transfer
  complete") is unchanged; CFT-402/405 own that copy.
- CFT-204 — done for Your scene and Notifications. **Save event stays blocked
  on A-15** (no table or API).
- CFT-205 — client half done: ref-held single-flight on bid, reserve, confirm,
  dispute; back navigation never disabled. Server duplicate protection is A-06.
- CFT-206 — done. Sheet and Stack cross-fade under Reduce Motion (the Modal
  slide was never swapped by the platform); every haptic pairs with a visible
  state; Spinner's static mark already existed.
- CFT-207 — done except the quantity half, which is **held with CFT-303**.
- CFT-208 — partial: guards on Edit listing and Report; Your scene asks while a
  save is in flight; sticky price cap beside Place bid. Not done: the delivery
  form's own typed-but-unsaved state (needs a state lift out of the
  component), CreateListing (a tab — state survives tab switches, no removal
  event), and the long-name / 1.3× audit, which needs a device.

**A-17 confirmation sources as implemented (for A's ruling).** Bid accepted =
`bids` insert without error (migration 047's trigger rejects anything not
above `current_bid`, so a successful insert was leading at that instant);
position = a fresh `listings.current_bid` read after the insert; receipt =
`confirm-and-release` returned success; purchase = settlement outcome
`completed` (unchanged from batch 1). Nothing is shown from the tap.

**For A's review.** `4b705c4` (CheckoutNative, display only). For awareness:
`7f6284e` (the lock now sits around `confirm-and-release` and the dispute RPC;
the two calls are made exactly as before) and `de6dc09` (post-bid re-read).

**Previews.** Static page sent to the owner and committed with its pin test.
Native visual/runtime acceptance is still outstanding for the next authorised
candidate build. Not previewable statically: haptics, press motion, Reduce
Motion transitions, the double-tap guard, Dynamic Type, VoiceOver.

**Next deliverable (proposed, on the owner's go).** The batch 3 slice that needs
no A contract: CFT-402 (seller claim vs buyer possession wording across
`transferState`, `bidState`, `TransferStatusBadge`) and CFT-404 (return from
the provider lands on the order with "Did the tickets arrive?" and a status
refresh), then CFT-306 (real-state progress copy), which touches
`payControl.ts` and goes to A first. CFT-401/403/405/406/408/409 wait on
A-09, A-12, A-17, A-14 and A-10 respectively.

### Batch 2 — A's review (2026-09-14)

- **`4b705c4` APPROVED.** A verified the stronger claim: across all of batch 2
  (`43e3a97..3c78382`) the diff over `payControl.ts`, `setupDecision.ts`,
  `holdState.ts`, `payments.ts` and `signOut.ts` is empty — byte-identical.
  One cosmetic nit: the `completed` effect re-fired on a remount (a 3-D
  Secure return landing on a settled checkout), so a buyer could feel the
  success haptic twice. **Fixed in `73a5f19`** with a module-level latch keyed
  by the listing; sent to A for a re-check. Batch 2 head is now `73a5f19`.
- **A-17 — all four confirmation sources APPROVED as implemented.** A checked
  the load-bearing claim: migration 047 line 80 raises on
  `NEW.amount <= v_current_bid`, so the rule is strictly greater and a
  successful insert really was leading at that instant. The "Bid placed"
  fallback when the re-read is unavailable is singled out as exactly A-17:
  assert the placement the server confirmed, never a position we cannot know.
  Do not "improve" it into a guess later.
- **A-06 — duplicate half CLOSED.** 047 also carries a per-(listing, bidder)
  3-second cooldown ("Please wait before bidding again."). Inside 3 s the
  cooldown rejects a duplicate; outside it the first bid has already raised
  `current_bid` so strictly-greater rejects it. The client lock is the UX
  half, not the only guard.
- **F10 (A's finding, owner decision).** The server enforces only "greater
  than `current_bid`" — no minimum increment. `MIN_BID_INCREMENT` is a client
  convention; a crafted request can bid one cent above the floor. If the
  increment is meant to be a rule, that is a server change and a new migration
  number from A. Changes nothing built here.
- **A-08(d).** Migration 128 is written and rehearsed on A's side (pgTAP 195,
  25/25). Client contract when the owner authorises it:
  `public.register_push_token(token, platform, device_secret, device_name)`
  with a random secret in SecureStore; rebinding requires the secret, never
  the token alone. **Not built against yet.**
- **Batch 3.** A agrees with the slice split and CFT-306 going to A first; the
  go is the owner's. A-15 unchanged (blocked). Native acceptance still rides
  the next authorised build.
- **`73a5f19` APPROVED (A, 2026-09-14). Batch 2 fully cleared; nothing
  outstanding.** Gated surface re-verified across `43e3a97..73a5f19`: empty.
  Two observations, no action: the latch Set grows one short string per
  completed purchase for the life of the process (irrelevant at mobile
  scale); and it is keyed by listing, which is correct only because a listing
  sells once — **if a future surface allows repeat purchases of the same id,
  the key must become the payment.**

---

## 54-item coverage — implemented / tested / still unverified (2026-09-14, after batch 3)

"Implemented" names the batch on which the client work landed (B1 =
`frontend/premium-batch-1` @43e3a97, B2 = `frontend/premium-batch-2` @73a5f19,
B3 = `frontend/premium-batch-3`). "Tested" is what vitest proves: unit tests
for pure modules, source contracts (SC) for screens that cannot render under
vitest. "Still unverified" is what only a device, a build or a server contract
can settle. **Nothing on this list has native visual/runtime acceptance yet;
that is pending the next authorised candidate build and applies to every row
marked B1/B2/B3.**

| Item | Task | Implemented | Tested | Still unverified |
|---|---|---|---|---|
| 1 | CFT-101 | B1 — card content painted on detail; Buy/Bid gated on the fresh row | unit + SC (listing-handoff) | device paint timing |
| 2 | CFT-102 | not yet (skeleton shapes) | — | — |
| 3 | CFT-103 | B1 — quiet refresh on Tickets/Explore | unit + SC (quiet-refresh) | T re-run on next build |
| 4 | CFT-104 | not yet (independent sections) — A-13 | — | — |
| 5 | CFT-105 | not yet (prefetch) | — | — |
| 6 | CFT-106 | B1 — onError fallback; every card via EventMedia | SC (event-media-fallback) | render on device; 400 on fixture images |
| 7 | CFT-107 | B1 — place preserved across refresh and realtime inserts (first slice) | unit + SC (preserve-place) | filters/search persistence across navigation |
| 8 | CFT-201 | B2 — Tappable on stepper, quick-add, seller card + actions, delivery submit | SC (premium-controls, -reversible) | press motion on device; CreateListing pickers remain |
| 9 | CFT-202 | B2 — four meanings; dock silent; confirm/success only after server | unit + SC | haptic feel on device |
| 10 | CFT-203 | B2 — pending labels everywhere; "You're leading" from a fresh read | unit + SC (bid-outcome, pending-states) | VoiceOver announcement on device |
| 11 | CFT-204 | B2 — Your scene autosave + rollback; toggles explain inline. **Save event blocked (A-15)** | unit (coalescedSave) + SC | rollback timing on device |
| 12 | CFT-205 | B2 — single-flight on bid/reserve/confirm/dispute. Server half closed by A (047 cooldown) | unit (singleFlight) + SC | double-tap on device |
| 13 | CFT-701 | not yet (art transition, one celebration) | — | — |
| 14 | CFT-206 | B2 — sheet + stack cross-fade under Reduce Motion; haptics paired | SC | Reduce Motion on device |
| 15 | CFT-501 | not yet (position states beyond Bids tab) | — | — |
| 16 | CFT-502 | B4 — current bid dips and returns in place; next bid follows the live bid | unit + SC (premium-auction-live) | motion on device |
| 17 | CFT-501 | B4 client side — "Confirming result" at zero, bounded SELECT poll until the server speaks. **Server-time correction still blocked** | unit + SC | at-zero behaviour on device; A read-back that no extra finalize call is made |
| 18 | CFT-503 | not yet (competing bids) — A-06 increment finding F10 with owner | — | — |
| 19 | CFT-504 | B4 — realtime connection health; "Reconnecting — bid status may be delayed" on a live auction | unit + SC | airplane-mode drop and catch-up on device |
| 20 | CFT-505 | B4 — urgency order, then the auction closing soonest; "Ends in Nm" within the hour | unit + SC | ordering with real rows on device |
| 21 | CFT-506 | not yet — A-11 | — | — |
| 22 | CFT-303 | B1 label only ("2 tickets" beside the total). **Quantity semantics held (owner)** | SC | — |
| 23 | CFT-304 | B1 — explicit price-change acceptance | unit + SC (refund-and-hold) | needs a live hold (sandbox window) |
| 24 | CFT-301, 302 | B1 — "Held for you · until 9:14 PM"; not-held reasons; Back to listing | unit + SC | needs a live hold (sandbox window) |
| 25 | CFT-305 | B1 — reconciliation before any Pay; "Checking your payment" | unit + SC | interruption cases on device (D9c stays UNTESTED) |
| 26 | CFT-306 | **B4 — "Confirming payment" / "Finalizing your order" from the two real steps; payControl change with A for review** | unit + SC (checkout-pay-control, premium-auction-live) | needs a live charge (sandbox window) |
| 27 | CFT-307, 301 | B1 partial (hold-loss copy); designed outcome screen with alternatives not yet — A-11 | SC | — |
| 28 | CFT-308 | B1 — refunded / refund pending / partial refund; never "You're in." | unit + SC | owner's refund wording decision |
| 29 | CFT-401 | B3 partial — auto_released now shown on the buyer screen; expired/reversed wait on A-09 | SC | — |
| 30 | CFT-402 | **B3 — "Marked sent" vs "Received" everywhere; role copy** | unit + SC (premium-transfer-wording) | — |
| 31 | CFT-403 | not yet — A-12 | — | — |
| 32 | CFT-404 | **B3 — Open {provider}; return re-reads and asks "Did the tickets arrive?" only on fresh seller_sent** | unit + SC (premium-provider-handoff) | app-switch return on device |
| 33 | CFT-405 | not yet (second confirmation) — A-17 money-release review | — | — |
| 34 | CFT-406 | not yet — D-01 | — | — |
| 35 | CFT-407 | not yet (event-day view); native part deferred (CFT-801) | — | — |
| 36 | CFT-608 | not yet (drafts) | — | — |
| 37 | CFT-609 | B1 — "$90 for all 2 tickets", no per-ticket copy | unit + SC (sell-state) | — |
| 38 | CFT-610 | not yet | — | — |
| 39 | CFT-408 | not yet — A-14 | — | — |
| 40 | CFT-409 | not yet — A-10 / D-02 | — | — |
| 41 | CFT-601, 611 | 611: B1 sign-out revoke (unchanged by 128) + **B3 128 client: device secret, registration machine, non-takeover legacy fallback, remedy in Settings**. 601 offline cache not yet | unit + SC (auth-sign-out, push-registration) | revoke and rebind on a physical device; 128 applied nowhere; A's adversarial review may amend the contract |
| 42 | CFT-602 | not yet | — | — |
| 43 | CFT-507 | not yet | — | — |
| 44 | CFT-603 | not yet | — | — |
| 45 | CFT-604 | not yet | — | — |
| 46 | CFT-605 | not yet | — | — |
| 47 | CFT-606 | not yet — A-07 | — | — |
| 48 | CFT-607 | not yet | — | — |
| 49 | CFT-702 | not yet | — | — |
| 50 | CFT-207 | B2 — one formatter; tabular countdowns. Quantity half held with item 22 | unit + SC | — |
| 51 | CFT-703 | not yet (calm language audit beyond checkout/refund/transfer copy) | — | — |
| 52 | CFT-208 | B2 partial — guards on Edit listing, Report, Your scene-while-saving; sticky price cap | unit + SC | 1.3× text and long names on device; delivery form dirty state; CreateListing (tab) |
| 53 | CFT-704 | B3/B4 partial — one transfer vocabulary shared by Bids, detail, receive, send; one auction result vocabulary ("Confirming result") on detail | unit + SC | — |
| 54 | CFT-705 | not yet (interruption test procedure) | — | — |

**Totals (after batch 4):** implemented in full or in part on a branch: 26
items (1, 3, 6, 7, 8–12, 14, 16, 17 client, 19, 20, 22–30, 32, 37, 41, 50,
52, 53); blocked/held: 3 (17 server time; 22 quantity, owner; item 11's
save-event half, A-15); not yet started: 26. Native acceptance outstanding
for all 26; see DEVICE_VERIFICATION_CHECKLIST.md.

---

## Batch 3 — status (2026-09-14, C)

Owner's go: the proposed isolated slice (seller-marked-sent vs
buyer-confirmed-possession wording; returning from the external provider to
the correct order), plus client integration with A's reviewed migration 128
contract once A supplied it. Returning from another app must not itself imply
receipt or payment success; order context preserved; authoritative state
fetched. Local only; 128 not applied; no hosted data changed.

Branch `frontend/premium-batch-3` in `/Users/josetascon/snatchit-batch1`, from
batch 2's cleared head `73a5f19`:

| Commit | Scope | Tasks |
|---|---|---|
| `09838fe` | One transfer vocabulary: `seller_sent` = "Marked sent", `buyer_confirmed` = "Received", `auto_released` = "Released"; `transferStatusCopy(status, role)`; Bids tab, listing banner, send screen and the legacy badge reworded | 402 (+704 slice) |
| `06fa842` | Receive: "Open {provider}" (official entry points only, none for `other`); on return a QUIET re-read, then "Did the tickets arrive?" only when the fresh state is still `seller_sent`; "They're here" dismisses and highlights the explaining control, never confirms; "Report a problem" is the existing dispute flow; auto_released block added; all states via the vocabulary | 404, 402, 401 (partial) |
| `d3a9856` | **128 client, for A's review**: `deviceSecret.ts` (32 CSPRNG bytes → base64url, once per install, Keychain, per device, never rotated or cleared by the client), `registration.ts` (decision machine + contract error classification + backoff + terminal 42501 branch + remedy copy), `registerToken.ts` (RPC with `p_` names; legacy select-then-insert-only, non-takeover), `registrationStore.ts` (record/failure on device, no secret), `registrationStatus.ts`, `usePushToken.ts` rewritten; Settings › Notifications shows the remedy | 611 / A-08(d) |
| `98cbf4a` | Static previews extended with the batch 3 screens, pinned to source | previews |

**Gates.** `tsc --noEmit` clean; vitest 1836 tests / 82 files (batch 2:
1795 / 79); `expo lint` 0 errors (baseline warnings); gated files
(`payControl.ts`, `setupDecision.ts`, `holdState.ts`, `payments.ts`,
`signOut.ts`) byte-identical across `43e3a97..HEAD`. No progress-copy or
payment-control change was needed for this slice.

**Contract as built (A's text of 2026-09-14, 128 @4e29fde; A's adversarial
review is still running and may amend it).** `register_push_token(p_token,
p_platform, p_device_secret, p_device_name)` → `{ token_id, outcome:
registered|refreshed|rebound|rebound_legacy, platform }`; 42501
`not_authenticated` → auth; 42501 "token is bound to another account" → the
ONE terminal branch (bound / wrong secret / active legacy row of another
account are deliberately indistinguishable) → wait until account, token or
method changes; P0001 `precondition_failed` → back off; same token+secret+user
→ `refreshed` (idempotent retries); PGRST202 → legacy path (live today
everywhere). Secret per device; sign-out unchanged (batch 1's direct UPDATE by
token AND user_id — the revoke that makes an active legacy row claimable);
account switch = rebind by design; never `notify.register_push_token`; the
fallback stays insert-only. My question on recovery exposed a defect in 128
(hash never replaceable for the owner) which A fixed at `4e29fde`.

**Lifecycle covered.** Device secret: create on first use, reuse forever,
regenerate only if the Keychain loses it (owner's next registration replaces
the server hash). Account switching: `account_changed` → register → server
rebinds. Sign-out: untouched. Legacy tokens: own legacy row → `refreshed`
(first-time hash); another account's active legacy row → terminal until they
sign out on the device (`rebound_legacy` after). Failed registration: backoff
30 s doubling to 6 h, retry on foreground/sign-in, terminal branch surfaces
the remedy in Settings.

**Still unverified.** Everything native: the app-switch return, the Keychain,
push registration against a database that has 128 (none does), the revoke and
rebind on a physical device. F10 (no server-side minimum increment) is with
the owner. CFT-405 (second confirmation before release) untouched pending
A-17's money-release review; CFT-401's expired/reversed states wait on A-09.

**Next deliverable (proposed, on the owner's go).** CFT-306 (progress copy
from real states) to A first since it touches `payControl.ts`; then batch 4's
client-side auction states that need no server time: CFT-502 (in-place bid
updates), CFT-505 (My Bids ordering), CFT-504 (connection-health notice).

### Batch 3 — 128 contract amended after A's adversarial review; client re-bound (2026-09-14)

A's `4e29fde` (unconditional hash replacement for the owner) was a
HIGH-severity regression — momentary session access could plant a secret and
capture the device permanently — and is reverted at `f7b31ad`. The lockout it
"fixed" was already recoverable because the owner holds RLS DELETE on their
own row. **Client re-bound at `d48c290`:**
- The stored hash is never replaced; the client never rotates. A mismatched
  secret still returns `refreshed`, so the reply cannot reveal a mismatch and
  `refreshed` is recorded as-is, never as proof the secret matches.
- Recovery = delete the row this device owns, then register with the fresh
  secret → `registered`. Gated three ways, never speculative: the secret was
  generated on this attempt (the only lost-secret signal), this device's own
  record says it registered THIS token for THIS user through the RPC, and the
  RLS-scoped select finds a row we own. **C's gate is stricter than A's
  two-way gate** (no stored secret AND row is mine): it adds "previously
  RPC-registered", so the day 128 lands, every device with a legacy row and no
  secret binds its secret to that row (`refreshed`) instead of deleting and
  re-inserting fleet-wide. Cost: the rare case of AsyncStorage AND Keychain
  lost while the token survives leaves a stale hash; A already noted a
  reinstall issues a new token, so that strands nothing real. Offered to A to
  accept or reject.
- P0001 precondition refusals are terminal until the inputs change (A's
  ruling on my question), not timed.
- `notify.register_push_token` is now revoked server-side too; the client pin
  stands. NULL platform → P0001 → the precondition branch.
- **Not frozen.** Four findings open (legacy/no-secret path as steady state,
  token squatting, client-writable proof column, rollback downgrading proven
  rows); a second delta is expected and may change sign-out / account-switch
  behaviour. Nothing here ships; 128 applied nowhere; the insert-only legacy
  fallback remains the live path.
- Gates at `d48c290`: tsc clean; vitest 1843 / 82; expo lint 0 errors.

A confirmed on their side that the gated files are byte-identical across
batch 3 and that the receive/vocabulary commits are right on the money-adjacent
surface (A-17 applied to transfers).
- **Three-way gate ACCEPTED by A (2026-09-14)** as the correct scope, not an
  optimisation: rule 2 adopts a hash when the column is NULL, so a legacy row
  binds its secret by simply registering (`refreshed`, nothing destroyed);
  recovery-by-deletion exists for exactly one case — a device that bound
  THROUGH the RPC and then lost its secret — which is what the third condition
  names. Correction to C's earlier reasoning: **nothing references
  `push_tokens` by foreign key** (zero inbound FKs; no `push_token_id` /
  `token_id` column in `notify`, `public` or `kernel`), so "an FK would
  surface" was speculative and is withdrawn. Residual case (AsyncStorage and
  Keychain both lost, same token surviving) fails safe: notifications keep
  working, only a later cross-account handover on that device is refused.
  Storing `refreshed` as-is, never as proof the secret matched, confirmed as
  the honest reading. Nothing further from A until the second 128 delta; the
  legacy/no-secret path around sign-out is the area most likely to move, so
  it is kept easy to re-bind (one wrapper, one decision function).


---

## Batch 4 — status (2026-09-14, C)

Owner's go: truthful progress copy and client-side auction presentation within
existing backend rules; payment-control changes to A; no change to bid
increments or auction timing while F10 is undecided; 128 client isolated and
provisional pending A's final contract; batch 3 preserved; coverage and the
next candidate's device checklist kept current.

Branch `frontend/premium-batch-4` in `/Users/josetascon/snatchit-batch1`, from
batch 3's head `d48c290`:

| Commit | Scope | Tasks |
|---|---|---|
| `ac31172` | **payControl.ts (gated) + CheckoutNative, for A's review**: `finalizing` input; "Confirming payment" while the sheet confirms, "Finalizing your order" while finalizePurchase records; set only around the two finalizePurchase calls; no decision or handler changed | 306 |
| `513adb0` | detailState: "Confirming result" at zero (kind `confirming_result`; the existing client finalize also reads as confirming); liveState: bounded SELECT poll schedule (3 s, then 10 s, ≤16 attempts) and the connection notice; useListingRealtime exposes `connection`; usePulseOnChange + TransactionPanel in-place amount change; bidState `endingSoon`, `compareBidRows`, `endingSoonLabel`, injectable clock; BidCard urgency line; Bids tab order | 501 (client), 502, 504, 505 |
| `59fb928` | Static previews follow the split progress copy | previews |

**Gates at `9e671db`.** tsc clean; vitest 1861 / 83;
`expo lint` 0 errors (baseline 29 warnings). Gated files: only
`payControl.ts` differs from batch 1 (the CFT-306 change, with A);
`setupDecision.ts`, `holdState.ts`, `payments.ts`, `signOut.ts` byte-identical.

**Semantics untouched, by construction.** No new `finalize_auction` call (the
poll is a SELECT; the screen's one existing call stays one); `MIN_BID_INCREMENT`
unchanged and read only where it was; no `ends_at` written or extended;
`bidStatusOf`'s rules unchanged (only its clock became injectable). Pinned by
`tests/premium-auction-live.test.ts`.

**128 client.** Untouched this batch; still marked provisional against
`f7b31ad`; awaiting A's final independently reviewed contract before
notification integration is called complete.

**Device checklist.** `DEVICE_VERIFICATION_CHECKLIST.md` (DV-101 … DV-505)
prepared for the next authorised candidate; rows needing the sandbox window,
A read-backs, or 128 on the sandbox are marked.

**Next deliverable (proposed).** CFT-503 (competing bids: keep the entered
amount, explain the new minimum, require a fresh tap) is the natural next
auction item, but it touches the increment rule's presentation and waits for
F10. Without F10: CFT-604 (empty / failed / filtered states distinguished on
Home, Bids, Explore, Tickets) and CFT-605 (ended or sold listing opened from
an old link shows an outcome, not an error).

### Batch 4 — A's review (2026-09-14)

- **`ac31172` APPROVED.** A verified: across batch 4 the only gated file that
  changed is `payControl.ts` (+13/−1); `setupDecision.ts`, `holdState.ts`,
  `payments.ts`, `signOut.ts` byte-identical to batch 1. Precedence (finalizing
  before confirming) confirmed right.
- **Owner copy decision raised by A (pending-face kicker).** The button's
  "Finalizing your order" means "work is happening now, wait a moment"; the
  confirmation screen's `pending` face means "we do not know yet, nothing is
  lost, the webhook and sweep settle it, you do not need to wait". They must
  not share the words. The button stays; the pending kicker (SETTLEMENT_COPY
  in `payments.ts`, gated + owner's settlement copy) is the one to change. A
  recommends wording that conveys "landed or not, this resolves without you".
  **C does not change it without the owner's word.**
- Batch 4 awareness items accepted; A names "Confirming result" as A-17
  applied to the auction clock, and the SELECT-only bounded poll with the
  single finalize call as the right shape.
- **128 — do not re-bind yet.** Contract version 2 is written (every reply
  will carry `contract_version`, so the client can pin it) and is under
  independent re-review; A sends it only once that clears. Material for the
  client: rule 5 (the no-secret path the fallback relies on) becomes gated
  four ways; both sign-out spellings are accepted because the client helper
  writes `revoked_reason='sign_out'` while the server writes `signed_out`
  (no client change needed; noted for the day the contract is pinned).
- Device checklist: A will act on the A-marked rows only when an authorised
  candidate build exists; no pre-approved read-backs.
- **`9091397` — `revoked_reason` spelling aligned at A's request (gated file,
  for A's confirmation).** 128's legacy path keys on the single value the
  server's only writer (`notify.revoke_push_token`) uses, `signed_out`; the
  batch 1 helper wrote `sign_out`, which would have left a signed-out device
  unrecognised as a genuine handover and refused the next account silently.
  One string changed; pinned by `tests/auth-sign-out.test.ts`. signOut.ts now
  differs from batch 1 by that string and its comment only.
- Coming in contract v2 (A, not yet released): the legacy path gets a 90-day
  sunset from the migration's apply time (previously re-armed by every
  sign-out, so it would have stayed open forever); the table holding that
  epoch was created by A in `public` with no RLS and no REVOKE — writable by
  anon and authenticated under production's default grants — and was **found
  by the independent review of A's migration**, not by A (A's correction to
  this record; the project's CI gate would also have caught it, and the
  migration was simply not CI-clean). Fixed; CI gate passes. The same
  attribution applies to the 0590 identity hardening reverted in 127: A's,
  found by review. A's stated lesson: every defect sat in code with passing
  tests written from the same assumptions as the code — green tests were not
  the evidence they appeared to be. Client unchanged until the versioned text.
- **`9091397` CONFIRMED by A** (2026-09-14): diff over signOut.ts since batch 1
  is the string and its header comment only; token AND user_id match, timeout
  and never-blocks untouched. Gated surface since batch 1: that string and the
  approved payControl.ts change, nothing else. Third review round running;
  versioned text follows when it clears.

---

## Release sprint (owner directive 2026-09-14; target Fri 2026-09-18) — C's track

Scope frozen to the focused candidate: batches 1–4 as approved; required
recovery/error-state corrections; 128 client finalised on A's frozen v2
contract; targeted device plan and candidate build configuration. No new
Premium batch. Deferred items keep their rows above.

A's assignment to C: C-1 128 rebind (Wed, after freeze); C-2 recovery/error
states (CFT-607, D9-UX-1, F3, F8); C-3 device plan + build config (Tue);
C-4 rebase batches 1→4→recovery onto A's integrated pin (Thu). Branch:
`frontend/candidate-recovery` from batch 4's head `9091397` (A accepted the
stack over a cut from `release/convergence-135`).

| Deliverable | State | Where |
|---|---|---|
| C-3 device plan + build config | done | `CANDIDATE_BUILD_AND_DEVICE_PLAN.md` (7a5e225); `DEVICE_VERIFICATION_CHECKLIST.md` sprint rows DV-L1, DV-L2, DV-607a–d, DV-605, DV-F8, DV-611C, DV-T (8a009f3) |
| C-2 CFT-607 cancelled bid state, session-expiry notice; CFT-605 not-found outcome; CFT-604 pinned; F3 all ten labels | done | `3a43ca8` (+ gated `6659ed9`: one line in signOut.ts, with A) |
| C-2 D9-UX-1 | closed in batch 1 (holdState + Back to listing) | DV-301 |
| C-2 F8 partial refund | closed in batch 1 (`partially_refunded` kind) | DV-F8 |
| C-1 prep: cold-launch registration, `contract_version` pin (provisional, v2 = 2) | done | `d90db6b` |
| C-1 rebind to frozen v2 | waiting on A (Tue EOD / Wed AM) | needs: sunset SQLSTATE/message, rule-5 message texts |
| C-4 rebase onto the integrated pin | Thu, when A publishes | gated-diff proof per commit |

Gates at `d90db6b`: tsc clean; vitest 1877 / 84; expo lint 0 errors / 29
warnings. Regression tests for the cancelled state and F3 verified RED against
the previous files. Gated surface vs batch 4: `signOut.ts` +3 only.

**Owner decisions carried to A's board (with C's recommendation):** pending-face
kicker wording (A's recommendation stands); F10 → defer past the candidate;
CFT-303 quantity → defer (label-only shipped); A-15 → defer; refund wording →
ship current REFUND_COPY unless objected; A-08(d) + 128-on-sandbox for
DV-611R; hosted candidate build, handset install, sandbox window.

**Still unverified:** everything native (the plan's Blocks 0–3) until the
authorised candidate build; 128 RPC path until 128 exists on the sandbox.
- **C-4 rehearsal (2026-09-14):** the integration stack is **F1 (`2ba5281`) +
  batches 1–4 + recovery = 30 commits**; `release/convergence-135` @ `c55ea50`
  lacks F1, so a replay of batches alone conflicts at `bcbb106` on F1's files.
  With F1 included the replay onto `c55ea50` is clean (throwaway worktree, not
  kept): tsc clean, vitest 1877 / 84 on the replayed head; gated diff vs the base
  = batch 1's approved surface + `ac31172` + `9091397`/`6659ed9`, nothing
  unreviewed. Release-packet C section skeleton: `RELEASE_PACKET_C_SECTION.md`.
- **Schedule (A, 2026-09-14 late):** 128 contract freeze moves to **Wed 09-16 AM**
  (D's cold read found a HIGH functional regression in 128 — the new verb did
  not heal `notify.identity_channel_state`, so one DeviceNotRegistered silenced
  a user permanently; A fixing, back through D). C-1 rebind follows the freeze
  the same day. C's carried owner decisions are in A's batch with C's
  recommendations; A-08(d) is already the authorised 128 work; 128-on-sandbox
  for DV-611R rides the window authorisation.
- **Owner corrections to the sprint board (2026-09-15):** (1) deferring L1 is
  not a "safe scope cut" — L1 stays required unless an independent review
  demonstrates an effective mitigation or the owner explicitly accepts a clearly
  explained release risk; a pin and a packet alone do not make the candidate
  deployment-ready. (2) Sandbox/build authorisation (O-1/O-2) is separate from
  production acceptance of 128's residual risk (O-3): testing 128 accepts
  nothing. The board is A's file; the corrected wording went to A.
- **O-3 brief (C, 2026-09-15):** `O3_128_RESIDUAL_BRIEF_C.md` — verifies A's
  `docs/release/O3_128_RESIDUAL_DECISION_BRIEF.md` against 128 @ `cf73d7b`,
  pgTAP 195 and the client at `d90db6b`; differs on "adds no capability" (the
  plant is a deferred, signal-less trigger); proposes a `mismatch` outcome on
  rule 2 so the cold-launch clause actually undoes a plant. D's independent
  disposition requested. Monitoring detects exposure; it prevents nothing.
- **G-2 (A's column-scoped UPDATE on `push_tokens`, in flight):** the client
  updates `last_used`/`is_active` (`registerToken.ts:174`) and, on sign-out,
  `is_active`/`revoked_at`/`revoked_reason` (`signOut.ts:92-94`). The last two
  are outside the proposed scope and `notify.revoke_push_token` is unexposed, so
  as stated G-2 would make every sign-out revoke fail silently (`failed`) and
  rule 5's `signed_out` precondition unreachable from the client. Sent to A:
  scope in those two columns or expose a public revoke verb; C-1 follows the
  freeze text.
- **Sunset branch (A, 2026-09-15; frozen unless the freeze text differs):** past
  the sunset a hash-less legacy row raises the rule-4 error verbatim (42501,
  "insufficient_privilege: token is bound to another account"); no distinct
  sunset error by design. The client's single terminal branch already covers it
  — no code change; DV-611R wording stands.
- **Schedule (owner, 2026-09-15):** hosted build submitted **Thu** after the
  candidate checks; **Fri = handset verification and corrections only**. Plan §3
  updated. The EAS submission is ready to fire on A's pin + O-2 (profile
  `preview`, commit = A's pin, expected build 17); C continues against the
  reviewed v2 interface with provisional markers and takes the final delta at
  the freeze. B-2 starts when 126 is review-ready, in parallel with D-4.
- **Sandbox sequencing dependency (flagged):** SBX-2 (apply through 128, deploy
  `stripe-webhook` + `create-payment-intent`, DV-611) needs 124 applied first
  only because the ledger is linear; it does not need the venue-kit acceptance,
  the MFA step or the checkout previews. Those ride D's track and are not on the
  money/notification path.
- **Contract v2 FROZEN (A, 2026-09-15; `docs/release/PUSH_TOKEN_CONTRACT_V2.md`,
  server `f22c1a3`, D pass 3 clean).** C-1 final delta done at **`656b3ee`** on
  `frontend/candidate-recovery`: sign-out revokes only through the server verb
  (§2.4) — no direct write of `revoked_*` remains anywhere in app/ or src/ (the
  d90db6b direct write was a freeze blocker, found by A's G-2 question); the
  registration record is cleared at sign-out so a same-process re-login
  registers again; `too many registration attempts` is `rate_limited` (600 s
  wait, then retry) instead of terminal; the sunset refusal is the rule-4 branch
  (no change). Gates: tsc clean; vitest 1883 / 84; lint 0 errors / 29 warnings.
  Gated diff vs d90db6b: `signOut.ts` +60/−17 (to A, A-8).
  **Open (A):** §2.4 names `notify.revoke_push_token`, but `notify` is not in
  PostgREST's exposed schemas on the sandbox — A is choosing between a `public`
  wrapper (one-line client change, likely migration 129) and exposing `notify`
  per environment; 656b3ee holds until the addendum. DV-611 depends on it.
- **Rehearsal on A's snapshot `release/candidate-20260918 @ cd1f03c`:** the
  32-commit stack (F1 + batches 1–4 + recovery through 656b3ee) replays with no
  conflicts (`--onto cd1f03c 2ba5281^`, throwaway worktree, removed); tsc
  clean, vitest 1883 / 84 on the replayed head. Nothing under app/ or src/
  changed between c55ea50 and cd1f03c.
- **Origin push refused:** `git push origin frontend/*` was denied by this
  session's permission classifier; the branches are on this machine only
  (`snatchit-batch1`, `snatchit-premium`, `snatchit-129`). Reported to the
  owner as their action; A reads the stack from the local path for A-8.
- **O-3 decided by the owner (2026-09-15): option (b), session-bound push
  bindings, a PRODUCTION gate.** Not accepted for production; sandbox
  acceptance and the candidate build do not waive it. A's design:
  `docs/release/SESSION_BOUND_PUSH_BINDINGS_129_DESIGN.md` (number moving to
  131 per A). **C's provisional client delta: `627ee62` on
  `frontend/session-bound-129`** (worktree `snatchit-129`; NOT in the candidate
  stack): `session_stale` terminal kind + forced local re-auth
  (`src/lib/push/sessionStale.ts`), ordinary sign-out → scope 'local',
  `signOutAllDevices()` (revoke_all_push_bindings → global sign-out) + Settings
  row "Sign out of all devices", reset-password → global sign-out with a
  'password_changed' notice, two new login notices. Gates: tsc clean; vitest
  1893 / 85; lint 0 errors / 29 warnings. **Product change put to the owner
  (A concurs):** the app's ordinary sign-out was global-scope (auth-js
  default) and left other devices with live push rows and no session; P6
  requires local scope + a distinct all-devices act. No reclaim UX (D's R1–R3).
  D reviewing the client side against S13–S16.
- **Effect on dates (C's view):** Friday candidate unchanged (Thu build after
  the candidate checks; Fri handset Blocks 0–3). Production readiness waits
  on 131 + its client delta in a later build: earliest the week of 21 Sept.
- **Wrapper decided (A, 2026-09-15): migration 129 = `public.revoke_push_token(text)`**
  (SECURITY DEFINER over notify's writer, authenticated only; contract v2 §2.4
  erratum, version stays 2). Recovery head is now **`db5bddf`**: one call-site
  change to `supabase.rpc('revoke_push_token', { p_token })`; gates tsc clean,
  vitest 1883 / 84, lint 0 errors / 29 warnings; gated diff vs d90db6b
  `signOut.ts` +59/−17 (A's A-8 line review covers the file end to end). A:
  nothing else outstanding from C for the candidate. Session-bound bindings
  renumbered **131** (pgTAP 198).
- **131 provisional client delta at `b538f1d` on `frontend/session-bound-131`**
  (worktree `snatchit-131`, rebased onto db5bddf, not in the candidate stack)
  after D's read-only review of 627ee62: K-1 account deletion → all-devices
  sign-out; K-3 two named acts `signOutThisDevice` / `signOutAllDevices` (old
  name removed on that branch); K-4 neutral stale-session copy (no cause
  named). **K-2 is the owner's decision:** ordinary "Sign out" becomes this
  device only, so a user who suspects misuse must use "Sign out of all devices";
  A and D both want it recorded as a product decision. D confirms S15/S16
  handled on the client; no reclaim UX exists (D's R1–R3 against A's tombstone
  reclaim). Gates: tsc clean; vitest 1893 / 85; lint 0 errors / 29 warnings.
- **D verified K-1/K-3/K-4 at `b538f1d`** (read and run locally, 2026-09-15):
  deletion and the row call `signOutAllDevices`; no `signOutEverywhere` left in
  app/ or src/; one `supabase.auth.signOut({ scope })` call site; neither
  stale-session string names a password; D's own run: the four touched suites
  63 / 63, tsc exit 0. K-2 stays with the owner. D's note to A for the 131 SQL:
  reset-password calls `revoke_all_push_bindings` from the device's OLD session
  (pre-epoch), so the verb must not apply the session-age check; the client
  already treats a refusal there as non-blocking (logged), so no client change
  either way.
- **A-8 approved (A, 2026-09-15):** `signOut.ts` d90db6b..db5bddf (+59/−17) approved
  for the candidate; the four money files untouched since d90db6b. **C-4 done
  early at A's request:** `frontend/candidate-recovery` rebased onto
  `release/candidate-20260918 @ 57b3a00` (121→129 + #64; no app/ or src/
  change on it) — head **`231f120`**, 33 commits, no conflicts; `git diff
  db5bddf..231f120 -- app src` is empty (every client file byte-identical to
  the approved head). Gates on 231f120: tsc clean; vitest 1896 / 85 (the extra
  file and 13 tests come from 57b3a00); lint 0 errors / 29 warnings. Gated diff
  vs 57b3a00: 5 files, +461/−18 (batch 1's approved surface + ac31172 +
  signOut.ts). Pre-rebase head kept locally as
  `frontend/candidate-recovery-pre-rebase` (db5bddf). A integrates from the
  local worktree as A-8's merge; only B's 130 (supabase/ only) can still land
  before the pin. `frontend/session-bound-131` stays on db5bddf (provisional).
- **Merged (A, 2026-09-15): `release/candidate-20260918 @ 37213e7` on origin**
  contains 231f120 (verified by C: fetch, ancestor check, `app src` diff vs the
  approved db5bddf empty). A's gates on the merged tree: vitest 1896 / 1896,
  tsc 0, lint 0 errors / 29 warnings. C's candidate work is therefore on
  origin through the candidate branch; still local only: the backlog docs
  branch and `frontend/session-bound-131` (kept provisional on db5bddf until
  the 131 SQL exists). Next for C: Thursday build (the owner authorised the
  candidate build in this session, conditional on D's 128 review passing —
  D pass 3 was clean) and the device plan Blocks 0–3 on Friday.
- **Pin (A, 2026-09-15): tag `candidate/2026-09-18-pin` = `4b012fd`.** Verified by C
  (fetch; 231f120 is an ancestor; `app src` identical to db5bddf; `eas.json`
  identical to Build 16). **Build HELD:** CI at the pin has not passed (docs-tip
  run failed, pin runs cancelled by later pushes); O-2's "after required
  checks pass" is unmet, so no EAS submission until A reports CI green at the
  pin. Pre-flight and the one-command submission are in the plan §1a; if the
  pin moves, the pre-flight is re-run against the new tag.
- **CI failure at the pin explained (A, 2026-09-15):** one server test file
  (pgTAP 193) sets a superuser-only parameter that passes on the local harness
  and fails on Supabase's CI stack; nothing in app/ or src/ is involved, so C's
  stack does not move. B is fixing 193; the pin moves to that merge commit and
  A sends the new tag with a green migrations job (expected Wed 09-16). C
  re-runs plan §1a's pre-flight against the new tag before any submission.
- **Intended pin `aabe029` (A, 2026-09-15): CI green, all five jobs.** C's pre-flight
  against it passed (231f120 ancestor; app/src identical to db5bddf; eas.json
  identical to Build 16; delta since 4b012fd = docs, the rehearsal tripwire and
  the 193 fixture only). Tag moves after D's re-run; build HELD until A sends
  the moved tag and states CI green at it. Plan §1a updated.
- **PIN DECLARED (A, 2026-09-15): `candidate/2026-09-18-pin` → `aabe029`** (tag
  force-moved and pushed; verified by C from origin). CI green at exactly that
  commit: run 34932209458, five jobs, migrations job pgTAP Files=80 Tests=4980
  PASS on the real stack. D re-pinned there (incremental D-5 PASS 22/0, 193
  fixture re-review OK). C's pre-flight at aabe029 stands. **Submission:
  Thursday morning after SBX-2, not before** — the owner authorised ONE build,
  and a Wednesday sandbox finding needing a code change would waste it; A
  says when SBX-2 is clean, then C submits first thing Thursday with
  `--message` naming aabe029. Nothing else from C until then.
- **Sandbox state (A, 2026-09-15 evening):** 124, 125 applied; 126 stopped (no `ops`
  schema on the sandbox; admin-only); 127/128 not applied; 129/130 wait on the
  owner's window extension. Blocked DV rows: DV-L1/L2 (127 + edges), DV-611
  L/S/R/C (128 + 129). Pin and Thursday submission unchanged. Owner action:
  rule on the extension (apply 127–130 + deploy the two edges) so those rows
  can run Friday; otherwise they are reported UNTESTED with the reason. Plan
  updated (§2, before Block 3).
- **Owner sprint direction (2026-09-15, evening) — C's items done:**
  (4) **K-2 APPROVED** and implemented as its own client branch cut from the
  pin: `frontend/logout-scope @ ba9cf6c` (signOutThisDevice = revoke own token
  via 129 then local sign-out; signOutAllDevices = revoke_all_push_bindings
  (131; PGRST202 swallowed elsewhere) then global sign-out; Settings row "Sign
  out of all devices"; deletion and password change use the all-devices act;
  gates tsc clean / vitest 1915 / 86 / lint 0 errors). **NOT in the pinned
  build (aabe029): shipping it needs a new pin and its own build
  authorisation.** The 131-only client parts are rebuilt on top of it as
  `frontend/session-bound-131-r2 @ f2c1a1c` (session_stale, forced this-device
  re-auth, neutral notices; gates tsc clean / vitest 1922 / 87 / lint 0
  errors). `frontend/session-bound-131 @ b538f1d` stays on origin as history
  (no force pushes). (5) **Pushes done, non-force:** f1, premium-batch-1..4,
  candidate-recovery @ 231f120, session-bound-131 @ b538f1d,
  session-bound-131-r2 @ f2c1a1c, logout-scope @ ba9cf6c, and this backlog
  branch. (1) Sandbox path (b): 127→130 + the two edges tonight via A; 126
  deferred on the sandbox (DV rows needing `ops` are not-run-on-sandbox, not
  failed). (2) Migration 132 (B): pending-record-before-intent; client
  unaffected unless the create-payment-intent contract changes — A owns any
  companion edge change and tells C. (3) O-3 b1/b2/b3: A and D. Device
  checklist: DV-611 spelling corrected to `signed_out` (+129 dependency);
  production-gate rows DV-P1..P4 added (not Thursday). Checkpoint sent
  through A.
- **A verified C's two outcome expectations against the 131 verb body (@ f102ce2):**
  re-login after "Sign out of all devices" or a password change → `refreshed`
  (row kept on the same user, hash cleared then re-adopted); re-login after a
  this-device sign-out → `refreshed` (hash kept; a different account on the
  same install → `rebound`). DV-P1/P2 set accordingly. **Shared-install edge
  (expected behaviour):** after a global sign-out a different account on the
  same install gets 42501 "bound to another account"; recovery = original
  account signs in then signs out this-device, or support unbind, or reinstall.
  DV-P5 added. The candidate's remedy copy ("sign out here first") is false
  advice in that edge, so the production-gate branch refines it:
  `frontend/session-bound-131-r2 @ dece6cf` ("…needs to sign in here and then
  sign out from this device, or contact support"); candidate copy untouched.
  **Process slip, disclosed:** 1b42e49 on that branch was committed and pushed
  with two failing pins (push-registration, premium-static-previews) because
  the commit was chained after the run without checking it; corrected in
  dece6cf, full suite 1923 / 87 green. No candidate branch was affected.
- **BUILD SUBMITTED (2026-09-15, on A's call after SBX-2 verified):** EAS preview build
  `53e5e98b-dbe9-405d-a7c8-159375c3fbc6` from tag `candidate/2026-09-18-pin` =
  `aabe029`, clean worktree (`npm ci`, 0 dirty files), `--no-wait`; the one
  build the owner authorised. Build number and the compiled env are read from
  EAS / the bundle when it finishes; packet §"Pinned source and artifact"
  filled. **A's F-K2-1** (all-devices revoke unbounded): fixed —
  `frontend/logout-scope @ 066625e` (revokeAllBindings raced against the 3 s
  sign-out budget; hang → null, logged; test: never-resolving rpc completes
  within budget; gates tsc clean / vitest 1916 / 86 / lint 0 errors) and
  cherry-picked as `frontend/session-bound-131-r2 @ 269aabe` (gates tsc clean /
  vitest 1924 / 87 / lint 0 errors). Both on origin, non-force.
- **BUILD 17 FINISHED (2026-09-15 14:05Z):** EAS `53e5e98b-…`, gitCommitHash `aabe029`,
  profile `preview` / INTERNAL, appVersion 1.0.0, SDK 54; artifact retained to
  2026-09-29. Compiled-env verification pending (bundle inspection needs the
  owner's permission to download the artifact; otherwise proven on the handset
  at Block 0 by `envGuard` + A's sign-in read-back, and the functions URL by the
  first edge call in Block 2). Packet updated. **A approved
  `frontend/logout-scope @ 066625e`** (gated signOut.ts); nit F-K2-2 (orphaned
  raced promise) fixed at `74b9c48` and cherry-picked as
  `frontend/session-bound-131-r2 @ 74881f5` (gates: tsc clean; vitest 1917 / 86
  and 1925 / 87; lint 0 errors). A's server-side note: the sessions trigger
  fires only when the LAST live session goes, so a failed/timed-out this-device
  revoke leaves that binding deliverable while other sessions live — A fixes
  on 131 (session-stamped bindings); no client change, copy unchanged.
- **D's K-2 contract review → two client findings (A-verified against auth-js):**
  **F-K2-3 (MEDIUM)** — the SDK keeps the session on a network error (drops it
  only on 401/403/404); the helper ignored the error, so an offline "Sign out"
  silently did nothing after the record was cleared, and an offline "Sign out
  of all devices" left a device signed in after the server had bumped the
  epoch. Fixed on `frontend/logout-scope @ 7dbe940` (result carries
  `signedOut`; record cleared only after success; session-end mark reset on
  failure; Settings/profile keep the user in place with "Couldn't sign out —
  check your connection and try again."; reset-password offers Try again) and
  carried to `frontend/session-bound-131-r2 @ b48f4e9` (a failed forced
  stale-session sign-out may retry). **S-13 copy (LOW)** — bound-to-another-
  account remedy now uses D's wording ("This device is still linked to another
  account. Sign in to that account and sign out of this device, or reinstall.
  If that isn't possible, contact support.") on the 131 branch. Gates:
  logout-scope tsc clean / vitest 1919 / 86; 131-r2 tsc clean / vitest 1928 /
  87; lint 0 errors on both. D's verdicts on record: all-devices and password
  change HOLD; this-device sign-out has the server gap A fixes (A-131-K2);
  scope 'others' deliberately not offered. Candidate (build 17) carries the
  pre-existing offline sign-out behaviour — recorded in the packet as a known
  limitation, with a DV-204 offline tap to observe it.
- **Compiled-env evidence decided (A, 2026-09-15): no artifact download.** On record:
  envGuard at Block 0 + A's sign-in read-back (URL + anon key) + the first
  create-payment-intent call in the sandbox edge logs (functions URL); bundle
  inspection is the stronger check, pending the owner's permission (owner item
  in A's checkpoint). A approved `logout-scope @ 74b9c48` (F-K2-2 closed);
  F-K2-3 and S-13 already carried (7dbe940 / b48f4e9), awaiting A's review of
  7dbe940.
- **A approved `frontend/logout-scope @ 7dbe940`** (gated signOut.ts, +120/−13 vs the
  pin): discriminated result, clear-after-success order, `consumeSessionEnd()`
  on error. **Documented consequence (no change asked), kept next to F-K2-3:**
  on "Sign out of all devices", `revoke_all_push_bindings` bumps the epoch
  before the global sign-out, so if that sign-out then fails offline this
  device is pre-epoch until the retry succeeds — its next registration is
  refused with the 42501 `session predates a credential change`, which the 131
  branch handles with the neutral notice and a retry (on the K-2 branch alone
  it would read as bound-to-another-account; the two ship together in the
  production-gate candidate). Nothing else pending from A; DV rows on build 17
  are C's from here.
- **132 (B, PR #70 @ ebbd1c0; D's battery pending) — no client delta:**
  `create-payment-intent` reuses the existing 409 body ("checkout is being
  updated") for two more situations. The client never enumerates 409 reasons:
  `src/lib/payments.ts` surfaces the function's `{ error }` / `{ message }`
  body generically (only the price-change case is special-cased into
  `PriceChangedError`), and the only tests asserting 409 bodies are the
  edge-function tests (A/B's). Same body, same handling; nothing to do on any
  branch. Not in build 17's server (sandbox at 130).
- **Resumption (owner, 2026-09-15 late):** disk freed (12 GiB available, measured);
  no cleanup by C. Install link and Handset session 1 (Block 0 + Block 1, 18
  ordered rows with evidence and A's read-backs) sent to the owner and written
  to the plan. Sandbox now carries 127–130 + both edges, so DV-L1/L2 and
  DV-611 L/S/R/C are runnable on build 17; `ops`-dependent rows are
  not-run-on-sandbox. Production gates unchanged (notification-redirection
  decision still open with A/D; 131/132 pre-production).
- **Handset session 1 on build 17 (2026-09-15 evening, owner + A read-backs):**
  Block 0 step 2 — the sign-in was a Keychain-restored session (created 09-14;
  refreshed 21:19 EDT by build 17's user-agent; URL + anon key proven).
  **Step 3 / DV-611L NOT MET AS WRITTEN:** zero push_tokens rows for the buyer.
  Root cause (A, sandbox logs, read-only): at 21:19:06 EDT build 17 called
  `register_push_token` → 403, postgres `insufficient_privilege: token is
  bound to another account` (128 rule 4) — the handset's token is still bound,
  ACTIVE and hash-less, to the owner's staff account from Build 16 testing on
  the same handset (row 140fcb44…, created 09-08); rule 5 needs
  `signed_out`, which Build 16 never wrote. The refusal is the F7 protection
  working (the buyer did not take over the staff account's token). The 21:26
  cold launch made no register call: the client's terminal state wins over the
  cold-launch clause (registration.ts:139-143); it is cleared by sign-out
  (656b3ee clears the record on every sign-out), a different account, a new
  token or a method change — no "Try again" exists. The remedy banner should
  be visible in Settings › Notifications ('waiting' + bound_to_other);
  owner asked to report its text. **F-611-1 (product/support-load, to D; not
  a server defect; not a candidate blocker on its own):** no automatic retry
  while terminal even after the cause is gone, and the candidate's copy says
  "sign out here first" where the exact remedy is sign in then sign out on
  this device (S-13 wording on the 131 branch already says so). Recovery
  paths offered to the owner: B (recommended, no mutation: buyer signs out →
  staff signs in on the handset → `refreshed` + hash → staff signs out →
  `signed_out` → buyer signs in → `rebound`), or A (A runs
  `unbind_push_token` as service_role, recorded). Decision pending. DV-611L
  to be recorded as NOT APPLICABLE as written (install not fresh); DV-106
  fixture = Build 16 listings "Phone P1" / "Device D7" / "Device D8"; DV-605 id
  `00000000-0000-4000-8000-000000000605`; two device-session writes (report
  row, quantity-2 listing) logged by A in manifest §10.
- **Session 1, Block 0 step 3 observed (owner, 21:33 EDT, screenshot by the owner):**
  Settings › Notifications shows the green "Notifications are enabled" and the
  yellow remedy banner verbatim: "Notifications aren't set up for this account
  on this device yet. The account that used this device before needs to sign
  out here first." Registration blocked (rule 4 terminal). Findings kept:
  initial 403; no retry while terminal; recovery wording (F-611-1). **Owner
  chose path B**; C guides one step at a time, A reads after each step and
  reports to C (single voice at the handset). Further rows paused until the
  recovery is verified.
- **Path B, S1 (A read, ≈22:0x EDT):** buyer sessions 0; staff row 140fcb44… unchanged
  (active, reason null, hash NULL); one push token on the sandbox. Extra
  on-device evidence for F-611-1 (A, from the logs): at 21:33:37 EDT the
  buyer's sign-out issued `revoke_push_token` (200, nothing to revoke) then
  logout 204; the buyer signed back in at 21:33:49 and registration was
  refused 403 again at 21:33:56 — sign-out clears the terminal state, the app
  retries on the next sign-in, and rule 4 repeats while the staff row is
  active. S2 (staff sign-in) issued by A.
- **Path B, S2 (A read, 21:40 EDT):** row 140fcb44… still the staff account's,
  active, last_used advanced (09-10 → 09-16 01:40:48Z), revoked_* null, hash
  now PRESENT — the contract's `refreshed`: rule 2 planted the real device's
  proof on the legacy row. Staff sessions 2, buyer 0; one push token; no
  channel-state row to heal. S3 (staff sign-out) issued by A.
- **Path B, S3 (A read, 21:41 EDT):** row 140fcb44… still the staff account's,
  active=false, revoked_at 01:41:51Z, revoked_reason `signed_out`, hash
  RETAINED, last_used unchanged — the 129 revoke on the verb path, i.e. the
  DV-611 shape, proven on build 17 (for the staff account; the buyer's own
  DV-611 run remains row 16). Sessions: staff 0 (the candidate's global-scope
  sign-out removed both staff sessions — K-2 context), buyer 0; one push token.
  S4 (buyer sign-in) issued by A.
- **Path B, S4 (A read, 21:42 EDT) — RECOVERY COMPLETE, no server mutation:** row
  `140fcb44-4920-4c32-8333-1a551879d36b` now user = DV buyer, active, last_used
  01:42:41Z, revoked_* null, hash RETAINED = the contract's `rebound` (rule 3:
  same device proof, new account). Buyer sessions 1, staff 0; one push token;
  no channel-state row. This row is the baseline for DV-611C (row 15) and
  DV-611S (row 18). DV-611L: not applicable as written (Build 16 residue);
  the 403 = F7 protection working; F-611-1 stays with D. Designed handover
  exercised end to end on build 17: rule 2 (`refreshed`, proof planted) →
  129 revoke (`signed_out`, proof kept) → rule 3 (`rebound`).
- **Banner gone on device after S4 (owner via A):** Settings › Notifications shows only
  "Notifications are enabled". Recovery verified server-side and on-device.
  Owner running rows 1–14 at their pace; rows 15–18 on C's triggers with
  140fcb44… as baseline. **132 passed D's review @ 9d82247**; A integrating
  131 + 132 + 133 onto the production-gate stack — no client change.
- **Session 1, Block 1 rows 1–8 (owner, 22:01 EDT): reported PASSED** "from Listing
  opens through Unsaved edits"; unsaved-edit protection works. Exact labels and
  timings were NOT captured for every row (owner's words) — recorded as such,
  nothing inferred: row 3 Tickets empty-state text, row 6/7 notice texts and
  timings, row 7 offline sign-out behaviour, and the DV-609 proceeds line are
  "not captured". Block 0 step 4 not reported. **NEW DEFECT (owner, screenshot):
  Sell your ticket form — while typing, the sticky "List Ticket" action bar
  sits far above the keyboard with a large blank gap; the heading crowds the
  SANDBOX banner.** Owner's acceptance: no artificial gap between keyboard and
  action bar; focused inputs visible, form scrollable; header spacing correct;
  open/dismiss/reopen keyboard restores layout reliably; unsaved-edit protection
  and entered values intact; verify create AND edit, incl. large text. Fix in
  the next candidate's frontend workstream (branch cut from the pin; A
  integrates); Build 17 stays the tested artifact; no new build from this.
  Tracked as **F-SELL-1**; a DV row is added for the next candidate.
- **Session 1 status (owner, 2026-09-16 early):** row 3 (notification registration)
  fully closed incl. A's and D's server verification — wording per the owner:
  registration "recovered through normal app-driven sandbox writes, without a
  manual support override"; rows 1–8 owner-reported PASS; **row 9 Reduce Motion
  PASS; row 11 large accessibility text PASS**; labels/timings not captured for
  every row (not inferred). DV-609 evidence (quantity-2 listing created during
  rows 1–8; proceeds line not captured) is reused — no second listing.
  Remaining: row 10, 13, 14, then 15–18 on C's triggers.
- **F-SELL-1 fix review-ready: `frontend/sell-form-keyboard @ 465dc32`** (cut from
  the pin; 8 files, +169/−17; no gated file): pure helpers `keyboardLift.ts`
  (stickyBottomPadding, ctaLift, topInset, SANDBOX_BADGE_EXTRA) + `useKeyboardUp`
  + `useTopInset`; StickyBar keyboard-aware; CreateListingScreen lifts only
  while the dock is visible and pads its heading under the badge; edit screen
  heading likewise; the badge sizes from the real top inset (was a hardcoded
  52 pt). RED-first test `tests/sell-form-keyboard.test.ts` (7). Gates: tsc
  clean; vitest 1918 / 86 green; lint 0 errors / 29 warnings. **Process slip,
  disclosed:** 10d917d was pushed with two stale adaptive-nav pins failing
  (chained commit without checking the run); fixed in 465dc32 with a guarded
  commit. One unrelated flake seen once (`tests/credential-sign.test.ts`
  token-length boundary, 6.6 s), green on three reruns of the file. Device
  rows DV-S1/S2 added (create + edit, large text, open/dismiss/reopen) — the
  fix is unverified on a device until the combined build.
- **O-3 decided (owner, 2026-09-16): b2, build shape (i)** — ONE additional sandbox
  preview build = backend 131–135 + K-2/131 client + client v3 (b2) + F-SELL-1,
  after combined review and CI; no independent build, no deployment; sandbox
  migrations/edge deploys only after the owner approves an exact package.
  Merge order (A): 135 → send-push (B) → client v3 (C); D reviews each and the
  stack. C's branches review-ready now: `frontend/logout-scope @ 7dbe940` (A
  approved), `frontend/session-bound-131-r2 @ b48f4e9`, `frontend/sell-form-
  keyboard @ 465dc32`. Client v3 branch: `frontend/push-proof-v3` from the
  131-r2 line, against `docs/release/PUSH_TOKEN_CONTRACT_V3.md` (A, draft
  within the hour). **C's paper estimate for client v3:** registration.ts —
  `challenge_required` outcome (challenge_id), `contract_version` pin → 3,
  new error kinds/copy (~1 h); challenge state machine as pure logic
  (requested → silent push received → confirmed; 60 s without push →
  visible-code fallback → 6-digit entry → confirmed; error/expiry paths) with
  unit tests (~2 h); foreground/background notification handler for the
  silent push `{type:'push_token_challenge', challenge_id, nonce}` →
  `confirm_push_token_challenge` (~1.5 h; needs `UIBackgroundModes:
  remote-notification` in app.json if silent pushes must arrive while
  backgrounded — a config change, build-affecting, to confirm with A);
  Settings › Notifications pending state + code-entry sheet with "never share
  this code" + old-build refusal copy (~2 h); source pins, previews, DV rows
  (~1 h). ≈ 7–8 h of C after the v3 draft, plus D's review; device
  verification only on the combined build with 135 on the sandbox.
- **Session 1 (owner, 22:20 EDT): row 14 offline portion PASS** (screenshots by the
  owner): Home, Bids and Profile show "You're offline / Check your internet
  connection and try again." with Retry; **Tickets shows "Something went wrong /
  We couldn't load this right now. Please try again."** — wording difference
  recorded for review as **F-OFF-1 (LOW):** the Tickets screen's error state is
  not network-aware (does not classify the offline failure as offline). Not
  established by this report: row 14's filtered/no-match and genuinely-empty
  portions, and row 13. **Row 10 VoiceOver: SKIPPED / UNTESTED at the owner's
  request** (worked on some tabs; navigation difficulty could not be told from
  an app issue) — neither a pass nor a confirmed defect; **accessibility
  follow-up A11Y-1** retained for a later dedicated VoiceOver pass; the owner
  is not asked to repeat it now.
- **D's review of the three integrated branches (2026-09-16):** all hold (K-2
  semantics match 131 @ f3963a3; F-K2-3 correct; K-1/K-3/K-4; handleSessionStale
  retry; F-SELL-1 mechanism sound). Three findings, none build-blocking, all
  fixed: **K-5** deletion navigated to login even when the sign-out failed →
  now stays with SIGN_OUT_FAILED_COPY; **K-6** stale-refresh sign-out now marked
  'expired' so the login screen says why — both `frontend/logout-scope @
  27c0b7d`; **S-1** sandbox badge text scaled with accessibility text size and
  would crowd the heading again → `allowFontScaling={false}`, `frontend/sell-
  form-keyboard @ 2b9559e`. Evidence limit (D): StickyBar and the badge have
  no rendering test — keyboard geometry and badge height are verified only on
  the combined build (DV-S1/S2 + a large-text pass). A integrated the earlier
  heads onto `release/production-gate-20260918 @ bf36928` (89 files / 1984
  tests, lint 0); the follow-ups go to A for re-integration.
- **Client v3 (b2) review-ready: `frontend/push-proof-v3 @ b098a46`** (from 131-r2;
  9 files, +610/−14; built against contract v3 @ candidate 53c95db incl. D's
  two changes: plain outcomes accept contract_version 2 or 3, a challenge and
  confirm require 3; the visible-code verb carries the device secret; the
  code IS a re-issued 6-digit nonce; 5 attempts then the challenge is consumed
  and Try again requests a new one). Pure state machine
  `src/lib/push/challenge.ts`; foreground-only silent push (no
  UIBackgroundModes); 60 s foreground fallback; Settings › Notifications
  pending / code entry ("Never share this code") / failed + Try again;
  contract_mismatch refusal copy. RED-first tests (13). Gates: tsc clean;
  vitest 1941 / 88; lint 0 errors / 29 warnings. Unverified on a device until
  the combined build with 135 on the sandbox.
- **Session 1 (owner, 22:3x EDT): row 13 owner-reported — "Browse live listings" took
  them to Home** (the not-found title text was not quoted; not inferred). **Row 4
  image placeholder PASS** (owner-reported). Remaining: row 14 filtered/no-match
  and genuinely-empty checks, then rows 15–18.
- **D's review of client v3 @ b098a46 (C1–C6 client share): all four probes clean**
  (foreign challenge id / wrong type ignored; expired code refused client-side
  before any call; backgrounding stops the clock and foreground re-requests the
  same challenge; no log carries the nonce, code, payload or secret — the nonce
  lives only in a local between arrival and echo). Findings: **P3-1 (MEDIUM,
  A's 135):** after five wrong codes the re-request re-dispatches the SAME
  exhausted challenge until it expires — D asks A to make a re-request on an
  exhausted challenge consume it and issue a new one; C's copy unchanged until
  A rules. **P3-2 (LOW):** rename `EXPECTED_128_CONTRACT_VERSION` →
  `EXPECTED_CHALLENGE_CONTRACT_VERSION` (done). **P3-3 (LOW):** iOS `inactive`
  (shade, prompts, calls) was treated as background and every resume reset the
  60 s clock — now only `background` pauses, and the fallback counts
  cumulative foreground time (done). **P3-4 (LOW, evidence):** four of the
  thirteen tests are source-text guards; the hook's wiring is verified only by
  DV-V1..V3 on the combined build (checklist says so). Device-row notes from
  D: the visible-code push shows the code in its alert text — the owner
  confirms the lock-screen preview is acceptable; a silent push arriving while
  the user is on the code screen is ignored by design.
- **State-views refresh (owner request, 2026-09-16) review-ready:
  `frontend/state-views-refresh @ 71eaef0`** (from sell-form-keyboard @ 2b9559e;
  17 files, +389/−157; no gated file). One Premium `StateView`
  (`src/components/ui/StateView.tsx`): display-face title, one sentence, one
  56 pt glyph treatment via IconSymbol (wifi.slash / exclamationmark.triangle
  / magnifyingglass; none for empty), the app Button as Retry (44 pt, busy),
  alert region + VoiceOver announcement, nothing animated; `ScreenState` and
  `EmptyState` are thin wrappers so Home/Explore, Bids, Tickets and Profile
  share it; Explore's no-match is its own state; pure
  `src/lib/ui/loadState.ts` (classifyLoadFailure: offline when the OS says so
  or the error is a connectivity failure; STATE_COPY) used by all five loads —
  **F-OFF-1 root cause:** Tickets passed a generic error state regardless of
  the failure (`state={'error'}`), now classified like the other tabs; cached
  content kept on failed refreshes (unchanged); the five headings use
  `useTopInset`. Static preview `docs/product-v2/previews/state-views-
  preview.html` (sent to the owner) pinned by `tests/state-views.test.ts`
  (RED first, 9). Three pre-existing pins updated (quiet-refresh, hardening,
  discovery-card-state). Gates: tsc clean; vitest 1927 / 87; lint 0 errors /
  29 warnings. Device rows DV-ST1..ST4 added. Not in build 17; A integrates
  into the combined candidate.
- **Client v3 @ `969ff20`:** per D's heads-up on A's 135 shape (confirm RETURNS
  `nonce_mismatch` + `attempts_left` and `challenge_consumed` instead of
  raising), a 200 binds only on `rebound`; mismatch uses the server's
  `attempts_left`; consumed is terminal; anything else never confirms and never
  writes a record. Open with A: stale nonce after a re-issue (D asks A to
  accept the previous nonce for one generation or not rotate within a
  challenge) and P3-1. Gates: tsc clean; vitest 1944 / 88 (guarded green run
  after one unrelated timing flake); lint 0 errors.
- **D's review of state-views-refresh @ 71eaef0 (2026-09-16): approved with three
  small findings; fixed at `frontend/state-views-refresh @ bf8b9ba`** (supersedes
  71eaef0 for A's integration; gated surface 0 lines). **SV-1 (LOW–MED, honesty):**
  `isNetworkError` treated `abort` as a connectivity failure, so an aborted or
  timed-out request would have said "You're offline" on an online device
  (regex from 9a0ecaf, pre-branch; nothing in the app aborts its own
  requests, so the branch was latent) — abort/timeout now fall to the
  server-error state (tests RED first, then green; also narrows the older
  ListingDetail / my-listings / transfer callers consistently). **SV-3 (LOW,
  copy):** the error sentence claimed a timeout; now "Something went wrong on
  our side. Try again in a moment." (title unchanged: "Couldn't load this");
  preview mirrored; test pins the body away from timeout wording. **SV-2
  (LOW, device):** the view carries both `accessibilityRole="alert"` and an
  explicit announcement; a double read is possible on Android TalkBack — kept
  both (iOS handset; the explicit call is what speaks there) and added the
  "announced exactly once" check to DV-ST4 with the drop-the-role remedy.
  D's proposed reconnect row already exists in DV-ST1 ("airplane mode off →
  the screen retries by itself"). Gates at bf8b9ba: tsc clean; vitest 1928 /
  87; lint 0 errors / 29 warnings. D also verified 969ff20 (H-135-1 closed
  client-side; push-proof-v3 16/16).
- **Open (v3, waits on A's stale-nonce ruling; flagged by D 2026-09-16):** on
  the PUSH path `prior` is null, so a `nonce_mismatch` is terminal `failed`
  with the code-flavoured "That code didn't match." If A rotates the nonce on
  re-issue, a stale silent echo lands there — a user who typed nothing is told
  their code was wrong and the challenge ends. Preferred: A's 135 does not
  charge an attempt for a stale-generation echo (D asked). Fallback if A keeps
  rotation: the push-path mismatch becomes neutral and recoverable (stay in
  `awaiting_push`, no attempt counted client-side, fallback timer continues).
  No client change until A rules; must not ship as it reads today.
  **Ruled by A 2026-09-16 (135 @ candidate ac716da) and applied at
  `frontend/push-proof-v3 @ 0eea9c3`:** (a) a re-issue rotates the nonce and
  keeps the previous hash one generation; an echo of the superseded nonce
  answers `{outcome:'stale_nonce'}` at no cost → client neutral: back to the
  exact prior state (push clock keeps its start, fallback re-armed; code entry
  keeps its attempts and says "That code was replaced by a newer one…"), never
  a bind or a record. **P3-1 yes:** a re-request on an exhausted/expired
  challenge consumes it and issues a fresh one → "Try again" from a dead
  challenge (exhausted/expired/consumed) requests a visible code directly; a
  reply carrying `challenge {id, mode, expires_in_s}` replaces id and expiry
  (A pinned the shape 2026-09-16: `request_push_token_challenge` returns
  exactly `{token_id, outcome:'challenge_required', contract_version:3,
  challenge:{id, mode, expires_in_s}}`, identical to the register verb's
  challenge reply, and 135 does issue a NEW id after P3-1 — pgTAP 202 F1),
  otherwise the same row switches to code entry; other failures register
  again. `challenge_consumed` after a typed code = fifth wrong code
  (exhausted copy); on the push path = "no longer valid". Final error list:
  `challenge not found` → consumed; `binding no longer exists` / `no binding to
  challenge — register instead` / `the caller already owns this binding —
  register instead` → `register_instead` ("This device needs to be set up
  again. Tap Try again." → register). Previous-owner notice is in-app: no
  client change. **Known limit (recorded on DV-V4):** a current push arriving
  while a stale echo is in flight is dropped (the nonce is never buffered) and
  the client waits for the 60 s fallback. Contract erratum §5 fixed by A the same
  day: a foreground re-request re-issues the same row with a ROTATED
  nonce/code, previous hash kept one generation → `stale_nonce`; the DV-V4
  limit is accepted by A as a device-row evidence limit and A stages the
  re-issue in the combined-build session. Tests RED first (10) then push-proof-v3 21/21; gates: tsc clean;
  vitest 1949 / 88; lint 0 errors / 29 warnings; gated surface
  `git diff --stat b48f4e9..HEAD` = 0 lines. Device rows DV-V2/V3 updated,
  DV-V4 added. To D for re-review; A integrates 0eea9c3 (supersedes 969ff20) after 135 and
  send-push. State-views `bf8b9ba` is on A's production-gate stack at
  `06d414f` (A: typecheck 0, vitest 1996/1996).
- **D's review of client v3 @ 0eea9c3 (2026-09-16): PASS.** D read 135's
  confirm verb at A's head and replayed it: `stale_nonce` is returned before
  any attempt is counted (row `attempts` still 0), so "free" is real and
  `onStaleNonce` returning the exact prior state is right; the null-prior
  terminal branch is unreachable (every confirm gets its prior); the re-arm
  resumes rather than restarts. D's mutants: 5 of 6 die; **survivor:** a flat
  60 s re-arm passed 21/21 (coverage gap). **CV-1 (LOW):**
  `classifyChallengeError` still sent timeout/abort to 'network' ("check your
  connection") — SV-1 again. **CV-2 (LOW):** `too many registration attempts`
  (register's 20/10 min) fell to unknown instead of rate_limited. All strings
  the classifier keys on verified by D against the verb bodies; `/nonce
  mismatch/` is a dead, harmless branch. **Fixed at `frontend/push-proof-v3 @
  e8114df`** (supersedes 0eea9c3): timeout/abort → unknown; rate-limit regex
  covers both texts; the re-arm is the pure `fallbackDelayMs` (60 s minus
  cumulative foreground time) with a test (45 s elapsed → 15 s; banked time
  counts) and a pin that the hook never does its own 60 s arithmetic — the
  survivor dies. RED first (3) → push-proof-v3 22/22; tsc clean; vitest 1950
  / 88; lint 0 errors / 29 warnings; gated surface 0 lines vs b48f4e9. Noted,
  not changed: `src/lib/push/registration.ts` line ~209 has the same
  timeout/abort → 'network' regex, but there the kind only schedules a retry
  and carries no connection claim to the user (follow-up, not a defect).
- **Client v3 CLEAR from D at `e8114df` (2026-09-16).** D killed each fix with
  a regression mutant: timeout/abort back in the network branch → 1 fails;
  `registration attempts` dropped → 1 fails; `fallbackDelayMs` ignoring
  elapsed foreground time → 1 fails; the hook bypassing the helper with a
  bare `60_000` → 1 fails (the pin catches the missing helper call
  `const delay = fallbackDelayMs(st, Date.now());`, not only the identifier —
  stronger than C first described). D confirmed `REGISTRATION_REMEDY` has no
  `network` entry, so registration.ts's timeout→network stays a scheduling
  kind; align it whenever that file is next open (not a finding). A's merge
  order 135 → send-push → client v3: the first two are cleared, so the client
  is the last gate before the combined stack. **Follow-ups:** (1) D re-runs
  the client tests against the stack commit because the `precondition_failed`
  texts the classifier keys on live in A's migration — a reword would degrade
  the classifier silently to `unknown`; (2) C adds a guard test on the stack
  (where `135_push_token_proof_of_possession.sql` exists) that asserts every
  keyed string appears in the migration body, so the coupling fails loudly in
  CI rather than only in D's run — not on the branch, which has no 135.
  **Done 2026-09-16: `frontend/classifier-migration-guard @ d9eb102`** (test-only,
  cut from the combined stack `0e8de77` = 131–135 + send-push + client v3
  e8114df + K-2/131 + F-SELL-1 + state-views; A's gates there typecheck 0 /
  vitest 2044 / lint 0; CI 35053233744; D has it for Gate 3).
  `tests/push-classifier-migration-guard.test.ts` reads 135 and asserts every
  keyed raise verbatim with its errcode, every 200 literal the client
  branches on, the challenge_required shape and contract_version 3, and that
  each string still classifies to the expected kind in both classifiers; dead
  v2 branches documented as not asserted. Negative control: a reworded raise
  fails by name. Gates: tsc clean; lint 0 errors / 29 warnings; vitest 2061 /
  93. Sent to A to integrate before the pin; D informed. **Integrated by A:
  stack tip `9bef640`** (guard 17/17, vitest 2061/2061, typecheck 0; CI
  queued; D confirms Gate 3 on this tip; then the pin). Nothing further from C
  before the pin; rows 15–18 on C's triggers after the owner's row 14 checks.
  **D, Gate 3 PASS at `9bef640`** (2026-09-16): D broke 135 three ways and each
  failed the guard by name (reworded `challenge attempts exhausted`; renamed
  the 200 outcome `stale_nonce`; changed the session refusal's errcode 42501 →
  P0001 with the text intact — the errcode assertion is what catches that
  last one). D independently parsed the stack's `raise exception` sites with
  comments stripped: all twelve keyed strings are genuinely raised; `nonce
  mismatch` is never raised (a 200 outcome) — documented as a dead v2 branch,
  correctly not asserted. Client work clear from D at e8114df. D's remaining
  risk is device behaviour only: push/foreground/background timing (DV-V1..V4),
  two accounts on one install (DV-V1), plant-then-claim from a second handset
  and completed-redirect recovery without support (DV-S1/S2) — the one
  combined build the owner authorises. Device-session note (already on DV-V2):
  the visible code arrives in a notification the lock screen previews, so the
  owner sees the code before unlocking — inherent to a visible-mode
  challenge, for the owner to see on the handset.
- **Pin named by A (2026-09-16): `candidate/2026-09-18-pin-b2` =
  `release/production-gate-20260918 @ 9bef640`** (tip = classifier guard
  d9eb102; CI 35053607616 green 5/5; D Gate 3 PASS). **Build NOT cut.** A is
  presenting the sandbox application package (131–135 + send-push) and the pin
  to the owner, recommending the build is cut from the tag only after the
  sandbox application completes (client v3 needs 135 on the sandbox to
  exercise anything), unless the owner says otherwise; when cut, from the tag,
  not the branch head, with the tag's commit quoted in the EAS record. The
  owner's one-build authorization is unchanged. Handset session 1 stays open on
  Build 17: rows 15–18 on C's "row N ready" triggers after the owner's two row
  14 checks; A's read-backs use the buyer row 140fcb44… baseline (last_used
  01:42:41Z, hash prefix 4b8628e7); row 17 (DV-607a) is A's documented
  server-side session delete, on the owner's readiness.
- **Session 1 (owner, 2026-09-16): row 14 closed.** No-match: **PASS** — the owner
  reports a filter result showing **"NO MATCHES / Try fewer filters."** (their
  note names "Your Bids → filter result"; on the Build 17 source that string is
  Home's active-filter no-match, `home.tsx:380`, and no Bids source carries it —
  recorded as reported, screen not inferred). Genuinely empty: **PASS** — Your
  Bids → Past showed **"NOTHING HERE YET / Ended auctions and completed
  purchases show up here."** (matches `bids.tsx:324/328`; the display face
  renders titles in capitals). Offline portion stays owner-reported PASS with
  **F-OFF-1** kept as a review item (Tickets: "Something went wrong / We
  couldn't load this right now. Please try again."; fixed in the state-views
  refresh on the combined stack, re-observed on the combined build). Rows 13
  and 4: PASS as recorded at 8e593ab. **Row 10 VoiceOver: SKIPPED / UNTESTED**
  (accessibility follow-up retained, DV-A11Y-1; neither passed nor failed). Both
  Build 17 strings are unchanged by the refresh (grep on bf8b9ba) and are to be
  re-observed on the combined build (DV-ST3). Labels and timings not captured
  are not recorded. **Next: row 15 (DV-611C)** — "row 15 ready" to A on the
  owner's relaunch time. **A's note (2026-09-16):** row 140fcb44…'s `last_used`
  already reads 04:00:03Z from the owner's row-14 relaunches, so A compares
  against a value captured immediately BEFORE the row-15 relaunch, not the
  01:42:41Z baseline — the owner holds the relaunch until A confirms the
  capture and C says go. Row 17's session delete waits for the owner's "ready".
  **Row 15 action (owner, 2026-09-16 00:12 EDT ≈ 04:12Z):** force-quit, reopened,
  10 s on Home, Settings not opened; performed before A's capture confirmation
  reached C, so A compares against its capture if taken before 04:12Z, else
  against the 04:00:03Z residue. "row 15 ready + time" sent to A.
  **A read-back (04:14:53Z, 04:15:32Z): NOT refreshed** — capture before the
  action at 04:10:50Z: user 919d511e…, active, last_used 04:00:03Z, revoked_*
  null, hash 4b8628e7; identical after the 04:12Z relaunch; no new token rows;
  one session (created 01:42:30, SnatchIt/17). **C root cause on Build 17
  (aabe029), before any repeat:** hook mounted at the root shell
  (`NativeAppShell.native.tsx:158`); `attempt()` returns early while userId is
  null without consuming the cold-launch flag; the flag is consumed only after
  `obtainToken()` and `decideRegistration`, where cold launch + same
  token/user record < 24 h ⇒ `register` (cold_launch) — no throttle, no screen
  gate, no token-changed wait; an RPC error would back off 30 s and retry;
  the sandbox-era verb (128:289) stamps `last_used = now()` on refreshed ⇒ the
  client never reached the verb at 04:12Z. Only silent path:
  `getExpoPushTokenAsync` threw (caught, console only, cold flag retained) or
  never resolved (APNs device token not delivered in that process). **Owner
  relaunched again at 00:16 EDT ≈ 04:16Z (own initiative), stopped;** sent to A
  as the discriminating data point; if unstamped too, A checks the sandbox API
  logs for a register call 04:11–04:18Z; next owner step would be a
  background→foreground transition, not another cold relaunch.
  **A read-back 04:19:28Z: PASS on the second attempt** — last_used advanced
  04:00:03 → 04:16:34Z, same user 919d511e…, proof unchanged (4b8628e7), no new
  row, one session = the contract's `refreshed`. The 04:12Z relaunch left no
  stamp; the 04:16Z one did. **Row 15: PASS on the second attempt; the 04:12Z
  relaunch is UNEXPLAINED pending A's sandbox API-log read** (D, 2026-09-16:
  an attribution to a token-fetch failure is a hypothesis that needs no
  further work; hold it open). What the Build 17 code rules out: (1) a verb
  refusal is persisted as a failure record, published to Settings and logged,
  and shapes the next launch — terminal kinds make every later attempt
  `wait`, rate_limited waits 10 min (until 04:22Z), transient kinds auto-retry
  after 30 s (would have stamped by ~04:13Z) — inconsistent with A's
  04:14:53/04:15:32 reads and the normal 04:16Z register; 131 is not on the
  sandbox, so the epoch refusal cannot have been raised; (3) a different row —
  A saw no other row for the buyer and the token string is unique to the row.
  Live hypothesis (2): the launch never reached the verb — the only
  launch-variant steps are `getExpoPushTokenAsync` and `loadRegistrationState()`,
  both caught by `attempt()` → `console.warn` only, nothing persisted, no status.
  A's log read decides: one call at 04:16 ⇒ (2) and the row closes; a call at
  04:12 ⇒ C's reading is wrong and the row stays open. **Finding F-611C-1 (C,
  LOW–MED, broadened per D):** the pre-register path fails invisibly — a
  refused register is persisted and shown, but a failed or hanging token fetch
  or storage read leaves no persisted state and no status, so nothing
  distinguishes it from "registered"; the next candidate should publish a
  "waiting for push token" status, bound the fetch with a timeout, and persist
  the failure kind (not Build 17). A concurs (2026-09-16): PASS on the second
  attempt, 04:12Z non-stamp UNEXPLAINED with the two timestamps; the device
  console (`[usePushToken] Error:`) is reachable only with the handset cabled
  to a Mac in Console.app, retention uncertain — offered to the owner as
  optional, not asked. **Row 16 action (owner, 00:21 EDT ≈ 04:21Z):** signed
  out online; login screen showed no message (client half PASS, owner-
  reported); stopped at login. **A read-back 04:23:49Z: server half PASS** —
  active=false, revoked_at 04:21:09Z, reason signed_out, proof kept, last_used
  unchanged 04:16:34, buyer sessions 0 (129 wrapper path). **Row 16: PASS.**
  **Row 15 SETTLED by A's edge log (with the positive control present):**
  exactly one register_push_token call, 04:16:34.448Z status 200 UA
  SnatchIt/17; none at 04:12Z. At 04:12:31–36Z the app was online and
  authenticated (GET auth/v1/user 200, user_blocks, get_my_profile ×2,
  listings ×2) and never sent register — the miss is client-side between
  userId-known and RPC-sent (`obtainToken()` / storage read), not network, not
  auth, not the verb. **Row 15: PASS on the second attempt; F-611C-1 CONFIRMED
  with evidence.** Detail: the 04:12 launch issued the auth/user +
  get_my_profile pair twice within five seconds (once at 04:16) — consistent
  with the root shell mounting twice; C checks the double-mount path with the
  fix. Dwell-time question withdrawn (the log answers it).
- **Owner decision (2026-09-16): sandbox push service key DEFERRED.** "b2 real
  push-delivery verification" is **BLOCKED until the key is deliberately
  approved** (DV-V1..V4 and every push-arrival row: deferred, not attempted,
  not failed). Coding, contract work, tests and local review continue.
- **F-611C-1 fix in progress:** `frontend/push-token-fetch-visibility` (from
  the stack tip 9bef640): bounded token fetch, persisted pre-register failure
  (kind + timestamp + attempts), published to Settings › Notifications with
  Retry, cold flag kept pending, in-process backoff retry. If the owner
  includes it in the combined candidate it is **a new pin + CI + D's gate,
  still one build**; otherwise it waits for the next candidate.
  **Delivered: `frontend/push-token-fetch-visibility @ ce310ef`** (from
  9bef640; 6 files, +281/−7; no gated file, no `supabase/`). Both mechanisms
  D named are closed: `src/lib/push/runGate.ts` (generation-scoped gate —
  cleanup cancels, a dead run never blocks the live effect, late completion
  ignored, rerun honoured; `withTimeout` 20 s; PreRegisterFailure {token_fetch
  | token_timeout, at, attempts}, backoff 30 s → 10 min; remedy copy);
  usePushToken gated on `beginRun`, `isLive` after every await, `endRun` in
  finally, a token-fetch failure persisted beside the record, published to
  Settings (Try again added to the failed banner), retried in-process, cold
  flag kept; `runningRef` removed. Tests RED first → 9/9 (D's exact sequence,
  fake-timer timeout, store round-trip, pins). Evidence limit recorded: the
  pins prove wiring, not order — **DV-611C-2** added. Gates: tsc clean; vitest
  2070 / 94; lint 0 errors / 29 warnings. To D for review; a proposal for the
  owner (new tag if included), not integrated. **D's review of ce310ef: gate
  correct, one change requested** — no liveness check between the register
  call returning and the first persist, so a run torn down mid-RPC could
  persist a stale record/failure over the live run's (a terminal stale
  failure would make `decideRegistration` `wait` on the next launch: the
  original defect's shape through the RPC window). **Fixed at `a609cbc`:**
  `isLive` check immediately after the register call block (covers the
  legacy fallback re-call), test-first (D's second sequence at gate level +
  a placement pin, count ≥ 3), push-token-fetch-visibility 10/10, vitest
  2071 / 94, tsc clean. **D: PASS at a609cbc** — verified the new `isLive`
  is the last position before all three `saveRegistrationState` sites with
  no await between, so no check is needed before the failure-path save;
  placement-pin mutants: check moved above the call → 1 fails; check deleted →
  1 fails (the pin asserts ORDER, not presence — pattern to carry into other
  pins). The session-stale handler stays ungated by design: clearing state on
  a confirmed stale session is idempotent and equally right for a dead run.
  DV-611C-2 reworded: silence is a FAIL, not inconclusive. Both proposal heads
  (8dc4cec, a609cbc) wait only on the owner's word in A's session.
- **My Tickets readiness map delivered (owner assignment relayed by A):**
  `docs/product-v2/MY_TICKETS_READINESS_20260916.md @ ecc58a0`, report only.
  Sandbox: the tab can be populated today only with an owner-authorised
  fixture row in `kernel.tickets` (+ joined catalog/venue rows), excluded by
  the acceptance-window ruling; production: `20260909000000` absent, so the
  tab shows the error state until the owner-gated apply, and the only
  legitimate row producer is the dark native issuance chain (flag, four null
  config stops, ceremony NO-GO, `primary-checkout` never deployed, no client).
  Offline cached tickets (spec) not implemented anywhere. New client work
  listed as CFT-801, 811–816, each needing a contract from A. Sent to A for
  the consolidated readiness report.
- **B2 window server phase CLOSED (A, 2026-09-16 04:57Z; D's closing read
  PASS):** sandbox ledger 141 (131, 132, 133, 135, 20260916000000; each md5 =
  the pinned bytes at 9bef640); census 32|106|37|37; create-payment-intent v5,
  send-push v4, enforce-transfer-expiry v4 deployed with byte parity;
  stripe-webhook unchanged; Vault holds `project_url` only; five refused 401
  ticks, zero drift; nothing reached the owner's handset. Under option (b)
  every b2 delivery row (challenge, echo, rebind, two accounts, plant-then-
  claim, recovery) is **deferred, not attempted, not passed** — on every build.
  Row 17 scripted for the owner with the post-131 expectation — **corrected by
  A (D caught it; verified from 131 at the pin): the sessions-gone trigger has
  two mutually exclusive branches per user.** (1) NO live session remains →
  `kernel.invalidate_push_bindings_for(user, 'signed_out_everywhere')`: every
  binding is_active=false, revoked_reason='signed_out_everywhere',
  device_secret_hash CLEARED, epoch MOVED; (2) another live session remains →
  only the deleted sessions' own bindings: revoked_reason='session_ended',
  proof KEPT, no epoch move. "session_ended + proof kept + epoch moved" cannot
  occur. With one iPhone the owner's buyer sign-in is the only live session →
  branch (1) is expected; the next sign-in on that device registers fresh (no
  proof) and re-plants. Branch (2) — the K-2 "this device only" case the
  amendment exists for — has only run in D's harness; it needs a second live
  sandbox session (Build 17 on a second iPhone): if the owner has one, that is
  the more valuable row 17; otherwise branch (2) is recorded untested outside
  the harness and proposed for the combined-build session. A reads
  auth.sessions immediately before the delete and states the branch. The
  buyer's own re-registration returns contract_version 2, which Build 17
  handles; row 18 deferred to the combined build.
  **Row 17 server half PASS (A, 02:38:30Z, branch (1)):** the buyer's only live
  session d947bef4… deleted by id (one row); row 140fcb44… active=false,
  revoked_reason='signed_out_everywhere', revoked_at 02:38:30Z,
  device_secret_hash NULL, session_id retained; `identity_ext.push_binding_epoch`
  null → 02:38:32Z (later than the deleted session's creation, so no
  pre-existing session can re-register); zero drift elsewhere; D taking the
  after-read. Client half pending the owner's foreground: expected the
  expiry notice on the login screen (CFT-607), not a silent failure. Next
  buyer sign-in on this device registers fresh with no proof → expected
  `registered` + a new plant (A reads after). Row 18 stays deferred.
  **Row 17 client half PASS (owner, 2026-09-16):** on reopening the app the
  login screen showed exactly "Your session expired. Sign in to pick up where
  you left off." **Row 17: PASS** — single-session global invalidation
  (branch (1)) verified server-side by A and D, client reaction owner-
  reported. **The two-session case (branch (2), K-2 "this device only") remains
  UNTESTED outside D's harness** — proposed for the combined-build session
  with a second iPhone. **Row 18 stays deferred** to the combined build.
  Session 1 on Build 17 is complete except the deferred rows (18, DV-A11Y-1
  VoiceOver at the owner's request, and every push-delivery row). Build: not cut until the owner says so
  in A's session; inclusion of 8dc4cec / ce310ef (new tag) is the owner's word.
- **Owner request (2026-09-16): exhaustive notification inventory + gap
  matrix from source and migrations** (not memory); no notifications added,
  no delivery behaviour changed. In progress: two read-only source sweeps of
  9bef640 (server: migrations, notify schema, edge functions, pgTAP; client:
  expo-notifications handlers, registration, preferences, inbox, copy, tests)
  → `docs/product-v2/NOTIFICATION_INVENTORY_AND_GAPS.md`.
- **Sandbox push delivery is impossible today (A, 2026-09-16):** the sandbox
  Vault holds no service_role_key, the only routine posting to send-push
  (notify_outbid) is guarded on it, and `net._http_response` has 0 rows in 24 h
  — nothing has ever posted from this sandbox through pg_net. Any row that
  expects a push to ARRIVE cannot pass on the sandbox as it stands (on the
  combined build: DV-V1..V4 and every "push received" row); registration and
  sign-out rows never leave the database and are unaffected — session 1's
  rows 16–18 as scripted are read-back/client-local rows and can run. A has put
  the fix to the owner as a decision beside the apply order: add the
  service_role_key to the sandbox Vault as a second named secret exception (A
  inserts from the environment value without printing it; D witnesses names
  only), or accept that b2 device verification of delivery is deferred. C runs
  no delivery row until the owner decides; if declined, delivery rows are
  recorded **deferred, not attempted, not failed** (D). If allowed, real
  pushes from the sandbox reach the Build 17 handset, visually identical to
  production ones.

## Profile gender — owner request 2026-09-16 (PROPOSAL only; nothing implemented)

Owner: gender is a key analytics dimension; collect it at signup **required to be
answered, with "Prefer not to say"**, inclusive predefined options plus an optional
self-described value, an explanation, **explicit consent for analytics use**, later
edit or clear, private by default, never inferred, aggregated analytics with
small-group suppression, RLS/retention/deletion/export/account-deletion defined
**with A before schema work**, and no use in discovery, bidding, checkout, transfers
or seller decisions unless separately approved. (Supersedes the interrupted draft of
the same day that had the field optional and never at signup.) **No migration or
production change is authorized.** C's proposal — UI, exact copy, accessibility
behaviour, A's data-contract questions, D's analytics questions —
`docs/product-v2/GENDER_PROFILE_DATA_PROPOSAL_C.md`. A: review the data contract,
privacy, schema, RLS and analytics implications. D: define the analytics dimensions
and dashboard treatment (suppression, consent filter, opt-out). Concerns flagged in
the proposal §3: App Store Review Guideline 5.1.1 (data minimisation — mitigated by an
equal-weight "Prefer not to say" and an honest "why"; A to confirm), signup friction
(placed with Name, after account creation), and self-described free text never
reaching analytics.

| ID | Item | Pri | Status | Screens | Owner | Blocked by |
|---|---|---|---|---|---|---|
| CFT-901 | Data contract: shape, RLS, retention, deletion, export, account deletion, consent semantics. **A's early positions (2026-09-16, full doc to follow on the converge branch):** separate owner-only table — yes; no admin row-level read — yes; one aggregate function with small-group suppression — yes; write path via a SECURITY DEFINER RPC (not RLS table writes) so consent and timestamps are set server-side; "cleared" and "undisclosed" distinguishable in the row, identical in every aggregate | P1 | proposed (A reviewing) | — | A (C supplies §7) | owner approval of the contract |
| CFT-902 | Signup step 2: Gender radio group, self-describe reveal, validation, Continue never disabled | P1 | proposed | `app/(auth)/signup.tsx` | C | CFT-901 |
| CFT-903 | Settings › Edit profile: Gender row, selector, Clear gender (consent off), consent toggle, revert on failed save | P1 | proposed | `app/settings/edit-profile.tsx` | C | CFT-901 |
| CFT-904 | Copy and the "Why we ask" sheet; strings in a module. Consent sub-line pinned to D's k: "Only in groups of at least 20 people, never on its own." — true only with D's complementary suppression and fixed buckets; if either is cut, the copy changes | P2 | proposed (text reviewable now) | signup, edit profile | C | CFT-906's suppression rules surviving review |
| CFT-905 | Accessibility: radiogroup/radio semantics, focus moves, announcements, polite live region, Dynamic Type, no animation | P1 | proposed | signup, edit profile | C | CFT-902, 903 |
| CFT-906 | Analytics dimension, suppression threshold, consent filter, opt-out, dashboard treatment. **Answered by D 2026-09-16** (`docs/review/d-release-sprint/GENDER_ANALYTICS_TREATMENT_D.md` @ 1698926): k = 20 with complementary suppression, fixed period buckets and a 250 denominator floor; `not_disclosed` absorbs undisclosed + cleared + consent-off; free text unreachable by the aggregate layer (derived column, no privilege — for CFT-901); every figure "of respondents who consented (n = N)"; per-request computation, exports timestamped point-in-time; one SECURITY DEFINER `search_path=''` function returning suppressed rows; bars not pie, fixed order, "—" never 0, no time series in v1, no pink/blue. **Open for the owner (D §0):** which decision the dimension informs — name one or two questions, build only those cuts | P1 | answered by D; blocked on CFT-901 | admin dashboards | D | CFT-901 |
| CFT-907 | Tests: validation, source pins (the field is read only in signup, edit profile, read model), static preview | P1 | proposed | tests, preview | C | CFT-902–905 |
| CFT-908 | Device rows DV-G1…G4 (each answer, large text, VoiceOver, edit, clear, consent off→on) + App Store 5.1.1 note in the release packet | P1 | proposed | device | C / owner | a build after CFT-902–907 |

- **BLOCKING Build 17 finding (owner, 2026-09-16): sign out online → sign back in
  → Home and Profile load forever until a force-quit.** Sign-in flow NOT passed
  while open. Investigation (C, before any change): auth event sequence on the
  broken path is SIGNED_IN → SIGNED_OUT → SIGNED_IN on one process; the working
  path (force-quit → relaunch) is INITIAL_SESSION on a fresh process and never
  runs the SIGNED_OUT callback. Root cause, confirmed in the installed
  `@supabase/auth-js` 2.98.0 (`GoTrueClient.js`): `signOut()` runs inside
  `_acquireLock` and, via `_removeSession` → `_notifyAllSubscribers`, AWAITS
  every onAuthStateChange callback before the lock is released
  (`_acquireLock` drains `pendingInLock`; `_notifyAllSubscribers` awaits
  `x.callback`). `useAuth.ts`'s callback was `async` and awaited
  `supabase.auth.getSession()` (the stale-token diagnostic), which queues
  behind the very sign-out that is waiting on it → circular wait,
  `lockAcquired` never resets. `signInWithPassword` does not take the lock, so
  sign-in "succeeds", but every data request awaits
  `SupabaseClient._getAccessToken → auth.getSession()` → chained on the hung
  tail → Home, Profile (and the push registration RPC) hang for the life of the
  process. Not a stale loading flag (Home/Profile `finally` paths are intact),
  not a missed event, not navigation timing, not the verb. Reproduced
  deterministically in `tests/auth-signout-deadlock.test.ts` against the REAL
  supabase-js client (in-memory storage, fake fetch): sign-out hangs, a data
  request after sign-out → sign-in hangs, account switch hangs; the restored
  session (cold launch) passes — 5 RED / 1 green before the fix. Fix
  (`frontend/auth-signout-deadlock`, from the stack tip 9bef640): the callback
  is a synchronous pure handler (`src/lib/auth/authStateHandler.ts`) that sets
  the session and the expiry mark and DEFERS the stale diagnostic past the
  lock (`setTimeout(fn, 0)`, the pattern Supabase documents); nothing in the
  callback awaits an auth call. Logout/session-security behaviour unchanged
  (revoke → sign-out order, K-2 scope, K-6 expiry mark, 131 stale handling).
  Device row DV-AUTH-1 (iOS, sandbox banner, large text): sign out online →
  sign in → Home and Profile load without a force-quit; no permanent spinner.
  **Delivered: `frontend/auth-signout-deadlock @ a046568`** (pushed; +235/−29:
  useAuth.ts, authStateHandler.ts, the test, one moved pin in
  candidate-recovery). Gates: tsc clean; vitest 2067 / 94; lint 0 errors / 29
  warnings; gated surface and `supabase/` 0 lines vs 9bef640. To A (integrate
  into the combined candidate after review; no build/deploy until CI) and D
  (review, mutants suggested). Evidence limit: the real-client test proves the
  lock semantics; the handset proves the screens (DV-AUTH-1).
  **D: PASS at a046568** (2026-09-16), root cause verified independently in
  the installed auth-js 2.98.0 (`signOut()` = `_acquireLock(... _signOut)`;
  `_notifyAllSubscribers` awaits every callback; the re-entrant branch chains
  on `pendingInLock`). Mutants: AM1 async handler awaiting inline → 4 fail,
  run time 0.35 s → 4.88 s (real hangs); AM2 defer dropped → 1 fails; **AM3
  hook swallows the handler's promise with `void` → SURVIVES** (equivalent
  mutant: the handler is synchronous, nothing to swallow) — C's claim that the
  source pin catches it was wrong; **AM4 = AM1 + AM3 → 4 fail** (the
  real-client tests catch the regression pair; no blind spot). Header note
  added at C's head **`8dc4cec`** (comment-only, +9) so the next reader keeps
  the handler synchronous and the hook returning its value. Integration
  waits on the owner's instruction given in A's session (it moves the build
  source); D and C have nothing pending.
- **Rows 17/18 restated by A (2026-09-16; 131 now applied on the sandbox,
  ledger 137, verified by A and D):** row 17 (DV-607a) after the window's
  server phase, expectation post-131 — on A's delete of the buyer's single
  live session the trigger revokes that session's binding: is_active=false,
  revoked_reason='session_ended', revoked_at set, device_secret_hash kept,
  rebind epoch moves; client half: expiry notice on foreground. **Row 18
  (DV-611S) deferred to the combined build, not attempted on Build 17:** once
  135 lands, a different account claiming the same token gets
  `challenge_required` with contract_version 3, which Build 17's v2 client
  rejects. A signals when the server phase is closed.

## Two-second registration rejection window — client assessment (C, 2026-09-17; owner assignment via A; D co-assessing)

**Server fact (131 at the pin):** `kernel.push_session_predates_epoch` refuses when the
caller's session `created_at < push_binding_epoch`, and every invalidation sets the epoch to
`greatest(prior, clock_timestamp()) + interval '2 seconds'` (`131:86-88`, `131:198-219`). A
session created inside that two-second margin — or one whose `auth.sessions` row is gone —
is refused with 42501 `insufficient_privilege: session predates a credential change` on
`register_push_token` (`131:266`, `135:190-193`) and on the 135 challenge verbs. The
session's `created_at` never changes, so **that session can never register**; the only
remedy is a new session. The migration's own comment ("a legitimate re-login inside the
margin retries") can only mean re-login, not a later retry with the same session.

**Client path 1 — register (the common case): NOT silent, recovery works.** The refusal
classifies as `session_stale` (`registration.ts`), the hook calls `handleSessionStale`
(`usePushToken.ts:221-227`): the registration record is cleared, the session end is
marked `credential_change`, and THIS device is signed out locally (`sessionStale.ts`). The
login screen then shows **"You were signed out on this device. Sign in again to keep
notifications on."** (`sessionEnd.ts:48`, neutral by design, K-4). The user signs in
again; by then well over two seconds have passed since the invalidation, the new session's
`created_at` is after the epoch, and registration succeeds. If the sign-out itself fails
offline the latch resets and the next refusal retries (F-K2-3). If Settings › Notifications
is open at that moment it shows "You were signed out on this device. Sign in again to turn
notifications back on." (`registration.ts:237-238`). Reachable on one device by "Sign out
of all devices" followed by an immediate sign-in within two seconds: the user is bounced
once with the notice, then succeeds. Understandable, one extra sign-in, no dead end.
Evidence: unit tests `tests/session-bound-131.test.ts` (classification, once-per-process,
F-K2-3 retry, the login sentence); **device-untested** — staging it needs A to bump the
epoch within two seconds of a sign-in on the combined build (proposed DV-131-1).

**Client path 2 — a challenge open across an invalidation: FINDING F-2S-1 (LOW, copy).**
If a 135 challenge is open (silent or visible code) and the epoch moves during its window
(password change or sign-out-everywhere from another device), `confirm_push_token_challenge`
/ `request_push_token_challenge` refuse with the same text; the client classifies it
`session_stale` and lands in the challenge **failed** banner with
**"You were signed out on this device. Sign in again to keep notifications on."**
(`challenge.ts:255`) — while the user is still signed in: the sentence is false for as long
as the banner stands. Recovery still works: Try again → `retryPlan` → register →
refused → `handleSessionStale` → forced local sign-out → the same sentence on the login
screen, now true → sign in again → registers. Not silent, but one screen states a sign-out
that has not happened. Proposed fix (follow-up, owner's call whether it joins a tag): route
the challenge path's `session_stale` into `handleSessionStale` exactly as the register path
does, so the sign-out happens first and the sentence is true when shown (one branch in
`usePushToken.ts` + a test); until then, the challenge copy could read "This device needs
to sign in again to keep notifications on. Tap Try again." Reachability is narrow (an
invalidation inside a ≤5-minute challenge window).

**Verdict:** no silent failure on either path; the affected user gets a neutral explanation
and a working one-step recovery (sign in again). One LOW copy finding on the challenge
path. Device rows proposed: DV-131-1 (register path, A stages the epoch bump) and
DV-131-2 (challenge path; needs push delivery → deferred with the key).
- **Owner ruling 2026-09-17 (in A's session): both fixes included.** A merged 8dc4cec and
  a609cbc --no-ff onto `release/production-gate-20260918` → `aad5f75`; TAG
  `candidate/2026-09-18-build-b2` = aad5f75; CI 35175523163 green; 9bef640 stays the
  sandbox application pin. **C cut the single authorised combined sandbox preview build
  from the tag: EAS `dcbf20e0-76dd-4b18-a48a-20c203ba0175`** (see the plan's build
  record) — **FINISHED as Build 18** (SDK 54, commit aad5f75, started 02:48:54Z); link to
  A → owner. Handset session 2 script ready (plan). **CFT-801 correction (A):** `kernel.tickets`
  requires `signing_key_id NOT NULL` → `kernel.signing_key` (084) and a custody-log tail,
  so a populated-Tickets fixture is not one row and touches the excluded trust-root
  table; the single-row assumption in the readiness map §2.1.3 and the estimates is
  withdrawn — A puts the real shape to the owner. Estimates for CFT-801/811–816 and the
  session-2 matrix sent to A for the critical path.
- **Populated Tickets: joint A+D recommendation (2026-09-17) — option D:** the existing
  `__DEV__` fixture toggle in `app/(tabs)/tickets.tsx` on a dev client, for layout
  evidence only, with D's requirement adopted: fixture rows render behind a VISIBLE
  "fixture mode / no server data" label on the Tickets screen (the venue dashboard's
  NotWiredState precedent), so a screenshot carries its own caveat and a populated list
  can never circulate as issuance working. Client-only commit from the build tag, D
  reviews, never in a preview build's default path; **not built until the owner picks
  D.** Option A (server-side fixture) not recommended by either: eight rows incl. a fake
  global ES256 signing key, permanent under the append-only ownership ledger, and it
  would spend the sandbox's ability to rehearse trust-root monitoring honestly.
- **Session 2 (owner, 2026-09-17): Build 18 installed; SANDBOX badge visible; signed in
  as the sandbox buyer; Home loaded normally without a force-quit or reopen**
  (owner-reported; this is the first sign-in on the device after row 17's global
  invalidation, so A's read-back should show a fresh `registered` with a new proof).
  Next single step: open Profile (S2-1 continues: then sign out → sign in same account →
  Home → Profile, then the seller).
  **A read-back 03:08:22Z (first sign-in on Build 18):** buyer session ff1f1494… created
  03:05:06Z (UA SnatchIt/18), after the epoch 02:38:32Z → registration permitted; row
  140fcb44… active, revoked_* null, session_id = the new session, last_used 03:05:08Z,
  same row re-activated. **Observed, recorded neither pass nor fail:** device_secret_hash
  is set with the SAME prefix as before the invalidation (4b8628e7) — Build 18 re-planted
  the secret it already held in SecureStore rather than generating a new one. C's reading
  of the client design (128): the device secret is created once per install and survives
  sign-out and account switch by design (pinned in `tests/push-registration.test.ts`); the
  server's global path clears the ROW's proof so that only a device holding the secret can
  re-plant it, and the 131 session binding (session_id + epoch) is what changes per
  session. Rotation on a server-side proof clear is not a contract requirement C knows of;
  **D confirmed: CONFORMANT** — `PUSH_TOKEN_CONTRACT_V2.md:41` "Generate the device secret
  once per install", `:62` "rotation does not exist"; V3 silent so V2's rule stands; under
  v3 the secret is no longer a takeover credential (cross-account register is
  challenge_required regardless of hash) and forcing rotation would break an in-flight
  challenge's captured secret_hash. D asked A to carry "rotation does not exist" into V3.
  Challenges 0.
- **Populated Tickets, labelled fixture preview delivered (owner ruling via A):**
  `frontend/tickets-sample-label @ 068843f` (from the build tag; +60/−1; no gated file,
  no `supabase/`): `SAMPLE_TICKETS_LABEL = 'Sample tickets — no server data'` and a
  full-width, high-contrast, non-dismissable alert banner above the list whenever the
  `__DEV__` fixture toggle swaps in the fixture rows; toggle unchanged, off by default,
  compiled out of preview/release builds; fixtures still written nowhere. Tests RED first
  → `tests/tickets-sample-label.test.ts` green; tsc clean; vitest 2079 / 96; lint 0
  errors. **Which client shows it:** a development build only (Expo Go / dev client /
  simulator); the recorded local-simulator blocker stands, so verification here is
  source-pinned tests; native rendering needs a dev client. Recorded as **layout
  evidence, fixture mode, no server data** — never beside CFT-801's server rows.
  **D: PASS at 068843f** (rows and label cannot appear apart; one caller of the toggle,
  inside `__DEV__`; banner keyed on `devFixtures` only — the stronger arrangement, kept
  and commented); D's non-blocking point taken: label text raised from `micro` to
  `bodySm` so a screenshot cannot miss it — head now **`ac70643`**; changes no pin.
- **Session 2 (owner, 2026-09-17): Profile loads normally on Build 18, no persistent
  spinner; Home loaded without a force-quit** (owner-reported; fresh-install sign-in,
  buyer). S2-1 (DV-AUTH-1, the sign-out → sign-in regression) starts next.
- **S2-1 step 1 (owner, 2026-09-17 23:33 EDT ≈ 03:33Z): sign out online → sign back in
  as the buyer on Build 18, no force-quit → Home and Profile both loaded** (owner-
  reported; the Build 17 blocker sequence). **A read-back 03:35:03Z: server half PASS**
  — one session f0118de8… created 03:32:43Z, the previous gone; row 140fcb44… active,
  revoked_* cleared by the re-registration, session_id = the new session, last_used
  03:32:44Z, same proof (conformant). API log: sign-out 03:32:30Z = revoke_push_token
  200 then auth/logout 204 (order preserved); sign-in 03:32:42Z; data requests flowed
  immediately with no relaunch — **the hang is NOT reproduced (DV-AUTH-1 core PASS,
  buyer).** **Finding F-AUTH-2 (C, LOW–MED, observation):** the acceptance line "no
  duplicate data requests" is NOT met — get_my_profile ×2 and listings ×2 within a
  second on both Home and Profile, user_blocks ×3 — the same doubled pattern as the
  04:12Z Build 17 launch (likely a double mount / duplicated effects on sign-in). Not a
  server finding; C to root-cause on the client (next candidate), not in Build 18.
  Step 2 = the seller account, same sequence.
- **Notification batch 1 (owner ruling 2026-09-17 via A; local implementation + tests,
  D reviewing; no dispatcher, no outbound, no build; Build 18 pin preserved):** C's items
  — (1) Settings › Notifications keeps only "Listing sold" live and HIDES the five
  unwired switches, preserving stored preferences (no write on hide); (2) a security-
  notice surface on the first signed-in screen for an unread `security_device_rebound`
  from A's 136 `public.get_my_security_notices()` / `mark_security_notices_read(uuid[])`,
  rendering {title, body} exactly as returned (A's correction: the server template
  carries the corrected meaning — a device that was receiving THIS account's
  notifications is now registered to ANOTHER account; the only client copy is the two
  action labels "Sign out of all devices" (K-2) and "Dismiss"); never on the login
  screen; (3) F-2S-1 neutral challenge copy, no auth change. **(3) delivered:
  `frontend/challenge-copy-neutral @ a3b67eb`** — `CHALLENGE_COPY.failed.session_stale`
  = "This device couldn't confirm notifications for this account. Try again from
  Settings › Notifications."; RED first; push-proof-v3 + session-bound-131 green; tsc
  clean; vitest 2077 / 95; lint 0 errors. DV rows for the next build to be prepared,
  not run.
- **Batch 1 item (1) delivered: `frontend/prefs-hide-unwired @ cf94311`** — only
  "Listing sold" shown; the five unwired switches hidden with their definitions and
  stored values preserved (one write site, no upsert/insert/delete, no default reset);
  RED first → tests/prefs-hide-unwired.test.ts; tsc clean; vitest 2080 / 96; lint 0
  errors; client-only from the build tag, no gated file. To D for review.
- **Batch 1 status (2026-09-17):** (3) `frontend/challenge-copy-neutral @ 577ec40` — D
  PASS on a3b67eb with one objection (Try again cannot succeed for a session that
  predates the epoch; the banner sits beside that button) → D's sentence adopted by A:
  "This device needs you to sign in again before it can confirm notifications for this
  account." (pin /sign in again/, not "signed out"); D's disclosure: a first mutant
  matched nothing and was redone with an asserted substitution count. (1)
  `frontend/prefs-hide-unwired @ cf94311` — D PASS (one write site, no upsert/insert/
  delete, four mutants die); **observation (D):** `fetchPrefs` uses `.single()`, so a
  user with no `notification_preferences` row (profile predating the baseline trigger)
  gets "Unable to load preferences" and now loses 6/6 switches instead of 1/6 — visible,
  non-writing; follow-up candidate. `notify_listing_sold` default true in the baseline
  matches the webhook's absent-row behaviour. (2) **`frontend/security-notice @
  e3ef6d3` delivered** — no client title/body (A's template v2 is the source: no
  {{device_name}} — attacker-chosen text —, no "sign in on that phone", no "change your
  password"); only the two action labels; get_my_security_notices / mark_
  security_notices_read({ p_ids }) per A's pin; PGRST202 = no notices; fetched on
  sign-in + foreground; mounted above the tabs only; K-2 action via signOutAllDevices
  (auth.uid()-scoped, cannot disturb the rebound token; does not undo the rebind). RED
  first → 6/6; tsc clean; vitest 2083 / 96; lint 0 errors. With D. Nothing integrates
  until D's PASS and the owner's word (new pin).
- **S2-1 step 2 (seller), step A (owner, 2026-09-17 23:49 EDT ≈ 03:49Z): signed out of
  Build 18 online** (owner-reported). Step B = sign in as the seller → Home.
- **S2-1 step 2 (seller), step B (owner, 2026-09-17 23:51 EDT ≈ 03:51Z): signed in as the
  sandbox seller on the same handset; Home loaded** (owner-reported: "home loaded 11:51"; no
  spinner or force-quit reported). Step C = open Profile. A's read-back requested for the
  03:49Z sign-out → 03:51Z seller sign-in window (expected: revoke → logout → token → then
  either `register` 200 or, because the token was bound to the buyer, `challenge_required`
  v3 — a pending challenge that Build 18 cannot complete without push delivery is DEFERRED,
  not a failure).
- **S2-1 step 2 (seller), step C (owner, ≈ 2026-09-17 23:52 EDT): Profile loaded** (owner-reported);
  then, unscripted, the owner force-quit and relaunched at 23:54 EDT — "it loaded again"
  (owner-reported; a cold relaunch on the seller session, not part of the script). **S2-1 step 2
  client half: PASS** — Home and Profile loaded after the buyer→seller switch, the Build 17 hang
  did not reproduce.
- **S2-1 step 2 server half (A, read-back 2026-09-17 03:54:43Z, edge_logs 03:47–03:56Z,
  UA SnatchIt/18): PASS on the sign-out/sign-in ordering.** (1) buyer sign-out 03:49:34Z:
  revoke_push_token 200 → auth/logout 204, order preserved; (2) buyer after: sessions 0, token row
  active=false, revoked 03:49:34Z, reason `signed_out_everywhere`, hash NULL — 131's sessions
  trigger, not a 129 defect: on a single-session account every "sign out this device" ends in the
  global branch (row 17 showed the same); buyer epoch moved again; (3) seller session created
  03:50:51Z; register_push_token 200 at 03:50:52 → `challenge_required` (challenge row, mode silent,
  requesting_user = seller, attempts 0, prev_nonce_hash present, expires 03:56:42Z); push_tokens
  still one row (the buyer's, inactive); send-push posted three times, all 401 (option (b), no
  service key) → **DEFERRED, not a failure**. F-AUTH-2 reappeared on the seller (get_my_profile ×3,
  user_blocks ×4, listings HEAD ×2 + GET ×3 at sign-in; Profile ×2/×2/×2; another burst 03:52:20–22).
  A's log shows a Settings › Notifications read at 03:54:33Z (notification_preferences) — owner to
  confirm whether they opened it and what it showed. Nothing written by A.
- **F-611C-2 (NEW, from the same read-back; MEDIUM; fixed locally, awaiting D review + A
  integration; no build):** Build 18 called register_push_token four times in 75 s as the seller
  (03:50:52 200, 03:50:57 200, 03:51:41 200, 03:52:07 **400** `too many challenge requests`), never
  called request_push_token_challenge, and made no register call on the 03:54 relaunch. Three client
  root causes, all from source (Build 18 = aad5f75):
  RC1 the AppState 'active' handler ignored `onForeground().reRequest` and ran `attempt()` on every
  'active' event, iOS inactive→active included (shade, keychain save-password sheet, Face ID); with a
  challenge open nothing is persisted, so each event re-registered, and 135 re-issues a live
  challenge in place (fresh nonce, same row — the prev_nonce_hash) and counts each against
  push_challenge_token 3/600 s and push_challenge_user 5/600 s, the budget the visible-code fallback
  also needs. RC2 `classifyRegistrationError` knew only 'too many registration attempts'; 135's
  rebind path raises 'precondition_failed: too many challenge requests' → 'precondition' =
  decideRegistration's never-retried refusal, with no remedy copy → silent and permanent for this
  signed-in session (the store is cleared by a sign-out on this device, so a later sign-in starts
  fresh). RC3 every `challenge_required` reply ran `beginChallenge()` (elapsedMs 0), restarting the
  cumulative 60 s visible-code budget that `fallbackDelayMs` is specified to resume.
  **Fix: `frontend/challenge-foreground-rerequest` @ 296439c** (from aad5f75, client only; gated
  surface and supabase/ diff empty): `isChallengeOpen`, `shouldReattemptOnForeground` (reRequest ||
  no open challenge) gating `attempt()` after the fallback re-arm; `resumeChallenge` (same id +
  silent → keep elapsed/startedAt, refresh expiry); classifier `/too many (registration
  attempts|challenge requests)/` → rate_limited + `REGISTRATION_REMEDY.rate_limited`. Evidence:
  `tests/push-challenge-foreground-rerequest.test.ts` 13 tests, RED 11/13 before the fix; six
  negative controls each fail 1–2; push-proof-v3 22/22, push-token-fetch-visibility 10/10,
  push-registration 30/30, classifier-migration-guard 17/17; full suite 96 files / 2090; tsc 0; lint
  0/29. From source: the visible code is requested at most once per challenge (the fallback is
  one-shot and only armed in awaiting_push; awaiting_code never re-registers on foreground). What
  only a device proves (needs push delivery → deferred with DV-131): inactive→active during an open
  challenge → no second register call; real background→foreground → exactly one re-issue.
  Session-2 consequence (A): the seller cannot register push on Build 18 while this sign-in lasts;
  rows that need no registration proceed as the seller; S2-2 runs as the buyer.
- **Batch 1 review heads (D, 2026-09-17):** 577ec40 PASS (comment nit fixed → `frontend/
  challenge-copy-neutral` @ df5127c, comment-only, 22/22, tsc 0); e3ef6d3 CHANGES REQUESTED → fixed
  at **`frontend/security-notice` @ da1d11d**: ① banner pays the top inset (`useTopInset()`;
  otherwise the title sat under the SANDBOX badge, F-SELL-1 again — interim double gap, overlay is
  the follow-up), ② newest unread notice of ANY type renders (A's ruling: 136 rev2 derives the set
  from the registry; the client never narrows it; unknown types get Dismiss only; fixture pin
  replaced), ③ a failed Dismiss puts `DISMISS_FAILED_COPY` on the screen and each action clears the
  previous error. 6/6, tsc 0, lint 0/29. Also from A: 136 rev3 returns unread-undismissed only.
- **D review (2026-09-17): 296439c PASS, da1d11d PASS, df5127c confirmed comment-only.** D
  re-ran 13/13, tsc 0, full suite 2090/96 on 296439c and killed four mutants: (a) isChallengeOpen
  without 'confirming' → 2 failed (D: confirming is exactly when Face ID or the keyboard raises
  inactive→active — the common path, not an edge); (b) resumeChallenge ignoring mode → 1 failed (a
  visible re-issue resumed as awaiting_push would be a silent dead end); (c) gate moved before
  armFallback → 1 failed; (d) `reRequest && !open` → 2 failed. D's note on (c), recorded as an
  evidence limit: the pin is a source-position pin (re-arm before gate); it does not prove a held
  challenge keeps its timer — that property lives on the device row DV-611C-3a, now extended with
  "and the visible-code fallback still appears after 60 s". da1d11d: three mutants (drop paddingTop;
  restore the type filter; delete setError(DISMISS_FAILED_COPY)) each 1 failed; ① style-array order
  verified (inline paddingTop wins over paddingVertical). Open on all three = the same four device
  rows: banner under the SANDBOX badge, K-2 ending sessions, inactive→active → no second register
  call, 60 s fallback on a held challenge — one build, and for the notification half the deferred
  push key. **D-cleared and awaiting the owner's word for A's integration:** cf94311, df5127c,
  da1d11d (batch 1), ac70643 (Tickets sample label), 296439c (F-611C-2). No build requested.
- **F-611C-2 handset half (owner, Build 18, 2026-09-17 ≈ 00:0x EDT report): Settings ›
  Notifications shows NO banner as the seller** after the 03:52:07Z 400 — the silence RC2 predicts
  ('precondition' has no remedy copy; the wait is invisible). Owner confirms the 03:54:33Z Settings ›
  Notifications read in A's log was their own open at ≈ 23:54 EDT. Owner-reported; no text captured
  because none was shown. This is the device-side confirmation of RC2's visibility defect; the
  fixed client (296439c) would show REGISTRATION_REMEDY.rate_limited here — device row for the
  next candidate (needs the 400 to be provoked, so it sits with DV-611C-3).
- **S2-3 started (seller signed in): DV-S1 (F-SELL-1, create) given as single steps; no listing is
  submitted from the handset** (sandbox writes belong to A).
- **Owner rulings via A (2026-09-17, converge bc72b92: critical path 1.2b, batch plan, manifest
  §13):** (1) the no-banner observation is recorded as the owner's observation consistent with RC2,
  NOT a PASS — matched to the F-611C-2 handset row above; (2) "Include all five reviewed C heads in
  the next candidate, including F-611C-2 at 296439c and the development-only Tickets label at
  ac70643. Preserve the label's exclusion from preview and production builds." A verified the
  exclusion from source: label and fixture rows render only when `devFixtures` is true, its only
  setter is the toggle inside the `__DEV__` branch, initial state false. **Invariant carried through
  any rebase: anything that sets `devFixtures` outside `__DEV__` is candidate-blocking.** (3) the
  D-reviewed device-rebound wording (136 template v2) and the neutral challenge-banner sentence
  (df5127c) are approved and final — no further copy work; (4) integration happens after D clears
  B's remaining head (139 residual); "No additional build, sandbox application, production change or
  outbound notification is authorized here." Build 18 stays the handset build, 9bef640 the sandbox
  pin. C continues guiding the seller-side tests; S2-3 (DV-S1/DV-S2) has no server half — A's next
  read-back is at S2-2 (buyer cold launches) and S2-5 (DV-ST2 staged read).
- **DV-S1 step 1 (owner, Build 18, seller, time not captured): PASS on the three checks** — no
  excessive keyboard gap above the List ticket bar, Event name stays visible, heading clears the
  SANDBOX badge. Steps 2 (scroll / dismiss / reopen / dock) and 3 (long name, largest text) still
  open; DV-S1 NOT complete (owner's instruction). No listing submitted.
- **NEW (owner, 2026-09-17) — F-IMG-1, PRIORITY functional defect:** on a listing that needs action,
  the buttons for adding ticket-proof images get stuck and do not behave like the Sell form's image
  controls. Owner's brief: trace and reproduce before changing; audit every image attachment entry
  point (selling, listing edits, proof submission, action-required screens) with the Sell form as
  the quality baseline; exercise permission granted/denied, picker cancel, select/replace, removal,
  upload failure, offline/reconnection, retry, repeated taps, navigate away/back, submission
  failure; iOS and Android where tooling exists (Xcode is deleted on the owner's Mac — no iOS
  simulator; no Android emulator recorded — so device rows stay UNTESTED and are labelled); fix what
  is reproduced with regression coverage; every operation finishes or shows an actionable error —
  no stuck controls, lost selections, duplicate submissions, or success before server confirmation;
  A owns storage / permissions / submission contracts; evidence and transaction behaviour
  preserved. Sub-findings F-IMG-1a… as traced. Owner: first report = defect IDs, reproduction
  findings, affected screens, owners; "Do not claim an exhaustive pass from source inspection alone."
- **NEW (owner, 2026-09-17) — ML-1, My Listings visual redesign:** the screen feels crowded and
  overwhelming; propose stronger grouping, clearer status and action hierarchy, consistent images
  and spacing, fewer competing controls; "needs action" stays easy to find; nothing important
  hidden. **Preview before implementing**, covering long lists, long titles, large text,
  empty/loading/error states, small screens. D reviews independently. Both initiatives: Build 18's
  pin unchanged; fixes go to the next candidate with an explicit device checklist; **no new build,
  deployment or production change is authorized.**
- **F-IMG-1 first report (C, 2026-09-17, source trace at aad5f75; NOT a device reproduction — no
  Xcode, no emulator; nothing exercised on iOS or Android):**
  *Entry points (exhaustive by grep of expo-image-picker and storage uploads; no camera path
  exists; the edit-listing screen has no image control; buyer dispute has no attachment):*
  (1) Sell form cover — `src/screens/CreateListingScreen.tsx` `useImageUpload({folder:'covers',
  aspect:[16,9]})` → `auction-media`; (2) Sell form proof of ownership — same screen,
  `folder:'proofs'`, bucket `proof-docs`; (3) **transfer send = the "needs action" screen** —
  `app/transfer/send/[id].tsx` (My Listings › Send tickets → `/transfer/send/<transferId>`),
  `folder:'transfer-evidence'`, bucket `proof-docs`, then `rpc('mark_transfer_sent')`; (4) profile
  avatar — `src/lib/avatarImage.ts` (separate implementation, bucket `avatars`), used by
  `app/(tabs)/profile.tsx` and `app/settings/edit-profile.tsx`. (1)–(3) share
  `src/hooks/useImageUpload.ts` + `src/components/ui/MediaUpload.tsx`; the Sell form is the baseline
  and the defects below exist there too, but the compact control on the transfer-send screen makes
  them visible: it has no picking feedback at all.
  *Sub-findings (source-provable):*
  **F-IMG-1a (HIGH) no in-flight guard and no feedback while the picker is opening.** `pickImage`
  sets status 'picking', but `MediaUpload` renders nothing for 'picking' (spinner only for
  'uploading') and both screens compute `disabled` from `status === 'uploading'` (the hook's own
  `busy` is unused by every consumer). During the 0.5–2 s the OS takes to present the photo sheet
  (longer on first use, with the permission prompt) the Add/Replace text looks inert; a second tap
  calls `launchImageLibraryAsync` again while the first is presenting — expo-image-picker rejects
  that ("different image picking in progress") — and the rejection is unhandled.
  **F-IMG-1b (HIGH) a thrown picker or permission error leaves the control in 'picking' with no
  message.** `pickImage` has no try/catch/finally; any rejection from
  `requestMediaLibraryPermissionsAsync` or `launchImageLibraryAsync` (the concurrent-launch case in
  1a; on Android the known "activity no longer available" rejection after a process restart) never
  resets status and never tells the user. Today that is invisible only because 'picking' does not
  disable the control — once 1a is fixed, 1b must be fixed with it or the button really locks.
  **F-IMG-1c (MED) retry after a failed verb re-uploads and re-submits.** On transfer send a
  successful upload followed by a failed `mark_transfer_sent` (or a lost response) leaves status
  'done' with `storagePath` set; the next "Mark as sent" runs `uploadImage()` again — a second
  object under a new `Date.now()` path (orphans in proof-docs) and a second verb call. Whether the
  second call is idempotent, and whether the client should read an outcome instead of inferring
  seller_sent from "no error", are A's contract questions (sent).
  **F-IMG-1d (MED) no double-tap guard on "Mark as sent".** `submitting` is React state; the
  receive screen uses `useSingleFlight` (CFT-205), the send screen and the Sell form do not.
  **F-IMG-1e (MED) network failure during upload shows the raw fetch message** ("Network request
  failed") in the control's helper line, not the product's offline wording, and nothing retries on
  reconnection; recovery is tapping the CTA again, which nothing says.
  **F-IMG-1f (LOW) navigating away mid-flow loses the selection**; the upload, if in flight,
  continues on an unmounted screen and its object is orphaned. **F-IMG-1g (LOW)** the
  permission-denied alert says "Enable it in Settings" without an Open Settings action.
  *Owners:* C — hook/control/screens (1a, 1b, 1c client half, 1d, 1e, 1f, 1g); A — proof-docs
  policies and paths, `mark_transfer_sent` idempotency, client-supplied `p_user_id` validation,
  server-side orphan cleanup (questions sent 2026-09-17); D — independent review of the fix and the
  device rows. *Fix plan (next turn, after A's contract answers):* single-flight `pickImage` with
  try/finally and a visible picking state; consumers gate on the hook's `busy`; reuse the uploaded
  path on retry of the same local file; single-flight the submit; network errors → offline copy +
  explicit retry; regression tests on an extracted pure flow module with fake picker/upload deps
  plus source pins; Sell form behaviour preserved by the same tests. *Evidence limit:* every device
  behaviour (picker sheet timing, permission prompts, iOS limited access, Android process restart,
  HEIC/iCloud assets, offline/reconnect) is UNTESTED until a candidate and a device — rows
  DV-IMG-1..8 in the checklist.
- **ML-1 preview v1 (C, 2026-09-17): https://claude.ai/artifact/32jnCwJv4yw58twpJPapk9** — four
  boards: Current (Build 18 structure), Proposed (needs-action rows pinned first with one primary
  "Send tickets" control; Live / Sold / Ended sections with headers and counts; one status line per
  row; Edit/Delete/Cancel behind a single More control; four-segment filter All · Live · Sold ·
  Ended replacing five chips), Proposed at 320×568 with the largest text and long titles (two-line
  clamp), and empty / loading / error (existing copy). Sample rows are illustrative; status words,
  time-left format, empty/error copy and the action line are the app's own strings. Awaiting the
  owner's approval before any implementation; no read or contract changes expected.
- **F-IMG-1 repair (owner, 2026-09-17: proceed under the frontend-fix scope; one coordinated repair
  — A owns the server contract and migration number, B implements server/upload changes, C owns
  picker, retry and submission UX, D reviews combined behaviour; no build, deployment or production
  change).** Evidence kept in three separate classes:
  *Source findings (traced, not device-reproduced):* 1a–1g as recorded above, plus **1h** proof picks
  were validated against the auction-media rules and the stored type came from the file name; and
  **1i (from expo-image-picker 17.0.10 source)** — the proof path (PHPicker, no editing) hands over a
  public.heic photo's raw bytes as .heic under the default `.current` representation, so Build 18
  stores iPhone proof photos as HEIC, which browser viewers (operator console, web receive page)
  cannot display; the cover path (editing) already re-encodes to JPEG. B's findings (lost response →
  false failure; seller_sent without evidence stranded permanently; filename-derived type; bucket
  missing from deps; no upload timeout) were measured by B on a local replay; A: `mark_transfer_sent`
  is not idempotent, returns void, raises "...current status: seller_sent." on a second call.
  *Automated results, `frontend/proof-image-flow`:* 3ca84a6 (first head) → **c0281aa** (after A, B and
  D review; D PASS on c0281aa, re-running D's own three mutants). Client only; supabase/ and gated
  surface diff empty. Pure modules `src/lib/media/uploadFlow.ts` (one picker at a time, gate released
  on every exit; byte sniff decides type and extension, no file-name input; object name fixed at pick
  time; after any upload error — a timeout included — `storage.exists` decides; reuse only for the
  same account/bucket/folder/transfer/file; selection kept across a remount and never swapped over a
  fresh pick; a cancelled pick restores the prior state) and `src/lib/transfer/markSent.ts` (status
  read → upload → verb → read back; success only on a sent read-back; the already-sent raise never
  shown as failure; a thrown/timed-out verb is uncertain → "Pull down to refresh"). Hook: iOS
  Compatible representation, Open Settings on a final denial, failure keeps the selection. Control:
  "Opening your photos…" state. Send tickets: single-flight, Try again after a failed/unconfirmed
  attempt. Sell form: picking included in busy, publish single-flight. 33 tests; harness asserts a
  clean baseline, each mutant applied and changed the file, digest-verified restore; RED on Build 18
  files 5; 21 mutants killed; full suite 96 files / 2110; tsc 0; lint 0/29. Disclosure: one earlier
  mutant run was VOID (zsh word-splitting made restores no-ops); rebuilt and re-run.
  *Device reproduction:* NONE. DV-IMG-1..9 pending; outcome 3 (HEIC → JPEG) does NOT pass until
  DV-IMG-9 observes it. The MIME display failure itself is not reproduced. Not done: converted_from
  metadata (PHPicker does not report the original type); existing HEIC evidence cannot be replaced
  (053) — viewer-side question with A; null-proof recovery UI waits for A's contract (140:
  transitioned / already_sent, attach → attached / already_attached). A session designation: the
  owner named the original A [2e7a9a] as the only A; the fork stood down.
- **ML-1 preview v2, calmer (owner, 2026-09-17: keep grouping, Needs action priority and simplified
  controls; calmer treatment; this approves the layout direction, not implementation):** same
  artifact, version 3 — boards: Current; Proposed v2 All; Live filter with a "2 listings need action"
  row and the More sheet open; largest text with long titles; 320-wide small screen at largest text;
  empty / loading / error. Charcoal rows without outlines, a small amber dot for Needs action,
  compact Send tickets buttons at 44 pt (52 pt at largest text), sentence case except the page title,
  red only for Send tickets and ending-soon time. **Cancel check (source):** Cancel exists only for a
  live listing with bids (`canCancelListing`), voids all bids behind a confirmation, and is also on
  the listing detail's seller menu; nothing in the app flags a listing as needing cancellation, so it
  is never a needs-action recovery — it goes behind More with a helper line. **Open for the owner:**
  the calmer empty/error type belongs to the shared state component, used app-wide; it needs its own
  approval or ML-1 keeps the shared look. New proposed copy is listed on the canvas.
- **DV-ST2:** held until the owner designated a single A session (now [2e7a9a]); owner still on
  DV-S1 step 2. **DV-S1 step 2** given to the owner as the next single step; not complete.
- **DV-S1 step 2 (owner, Build 18, seller, 2026-09-17 01:10 EDT ≈ 05:10Z): PASS** (owner-reported) —
  scrolling with the keyboard open, dismiss, reopen, typed text preserved, List ticket bar positioned
  correctly with the keyboard down. No listing submitted. DV-S1 still open: step 3a long event name at
  the current text size; step 3b largest accessibility text size (S2-4 row 11 residue runs at the same
  setting before it is turned back).
- **DV-S1 step 3a (owner, Build 18, seller, 2026-09-17 01:14 EDT ≈ 05:14Z): PASS** (owner-reported; the
  owner's first message said 01:17, the resent report says 01:14 — recorded as 01:14, the later report),
  long event name at the current text size. Observed behaviour, recorded exactly: Event name is a
  single-line field — unfocused it shows only the portion of the name that fits; focused it scrolls
  horizontally through the name; it does NOT wrap and the whole name is never visible at once. The
  owner considers single-line scrolling expected. Text intact after dismiss/reopen; field stays above
  the keyboard; no extra gap above the List ticket bar. No listing submitted. Also recorded: the
  heading-vs-SANDBOX-badge check passed at step 1 (time not captured); D's contrary wording was
  retracted by D. Next: step 3b at the largest accessibility text size.
- **Open product question (from DV-S1 step 3a; not a device defect; C to propose, owner decides):** a
  seller typing a long event name cannot see all of it at once, because Event name is a single-line
  field that scrolls sideways. Options: a multi-line Event name that grows to 2–3 lines; or keep
  single-line and show the full name under the field once it is typed. Recorded so it is not
  rediscovered as a bug (D, 2026-09-17). No change until the owner chooses.
- **DV-ST2 readiness (2026-09-17):** D reports the witness role authorized and live, kit paused,
  nothing running; A holds the revoke/restore with a watchdog. Trigger still waits for the owner to
  reach S2-5; A and D both carried step 3a as 01:17 — corrected to them as 01:14 per the owner's
  later report.
- **DV-S1 step 3b (owner, Build 18, seller, 2026-09-17 01:18 EDT ≈ 05:18Z): PASS** (owner-reported), at
  the largest accessibility text size: heading clears the SANDBOX badge; Event name stays visible;
  List ticket bar correctly positioned with the keyboard up and down; text intact; nothing cut off or
  overlapping. **DV-S1 (F-SELL-1, create) complete on Build 18: steps 1, 2, 3a, 3b PASS**, all
  owner-reported, no listing submitted. Larger text left ON for S2-4. Still open in S2-3: DV-S2 (edit
  listing with the keyboard), to run after S2-4 while larger text is still on.
- **S2-4 (owner, Build 18, seller, largest accessibility text ON, 2026-09-17, time not captured) — two
  observations recorded separately; S2-4 NOT passed:**
  *(1) SANDBOX badge:* stayed unchanged in size (owner-reported) — matches the design
  (`allowFontScaling={false}` in the root layout).
  *(2) Text scaling:* no apparent text-size increase on Home, Bids, Your Tickets or Profile; text did
  grow in Settings and on Sell your ticket; Explore not confirmed (owner-reported). Because text did
  not grow on those four tabs, **heading clearance at the largest size was not evaluated there** —
  that criterion stays open, not passed.
  **F-DT-1 (NEW, severity pending cause) — text on four tabs did not scale at the largest
  accessibility size.** Source check (Build 18 = aad5f75), not a device result: nothing in source
  fixes text on those screens. The only opt-out is the SANDBOX badge. `Chip`, `Button`, `Badge` and
  two Place bid elements cap scaling at `MAX_DISPLAY_FONT_SCALE` = 1.3× (intentional; the largest iOS
  setting is 3.571×, so those controls grow only 30% there). `textStyle()` sets fixed sizes that React
  Native scales by default; no global Text override, no `fontScale` reads, no caps in navigation or card
  components. Build 18 runs the new architecture (`newArchEnabled: true`, RN 0.81.5); its surface
  re-applies the font multiplier on a Dynamic Type change, but whether already-mounted tab screens
  re-measure is not provable from source. Working hypothesis, untested: screens mounted before the
  setting changed kept their old size. Discriminating check given to the owner: force-quit, relaunch
  with the setting on, look at Home.
- **S2-4 fresh launch (owner, Build 18, seller, largest text ON, 2026-09-17 01:27 EDT ≈ 05:27Z): PASS**
  (owner-reported) — after force-quit and reopen, all screens the owner tested showed large text; their
  headings clear the SANDBOX badge with no clipping or overlap; badge unchanged. The owner did not list
  the tested screens individually; not expanded here.
  **F-DT-1 stays open, recorded separately from that PASS:** screens already open when the text-size
  setting changed did not visibly update until the app was relaunched (owner-observed). Underlying
  cause NOT confirmed — the new-architecture re-measure hypothesis is untested. Severity to set with the
  owner: users who change Dynamic Type while the app is running keep old sizes until relaunch.
- **DV-S2 (F-SELL-1, edit) started (larger text still ON):** step 1 = Edit listing with the keyboard
  on a seller listing that shows Edit (no bids); Save changes is never tapped; step 2 = swipe back with
  an unsaved change → "Discard changes?" / "Your edits to this listing haven't been saved." with Keep
  editing / Discard (source: `UNSAVED_COPY.listingEdit`). No write in either step.
- **DV-S2 step 1 (owner, Build 18, seller, largest text ON; the observations carry no time, the owner's
  message is stamped 1:32 AM EDT) — mixed, recorded per check:**
  *PASS:* Save changes bar sits correctly with the keyboard up and down; the three added letters remain
  after dismiss and reopen; no other clipping or overlap noticed (owner-reported).
  *UNCONFIRMED (not passed):* Event name "mostly visible" above the keyboard — the owner cannot confirm
  it is fully visible; not inferred either way.
  *FAIL:* the SANDBOX badge does not clear the "My Listings" header (owner-observed).
  *Not reported:* whether the Edit listing screen's own heading clears the badge — open.
  Changes not saved (owner).
- **F-SELL-2 (NEW; investigated from source at Build 18 = aad5f75; fix not applied, awaiting the
  owner) — screen headers that ignore the SANDBOX badge.** Owner of the observed header:
  **`app/my-listings.tsx:189`** pays `insets.top + v2.space.sm` straight from the safe area instead of
  `useTopInset()`, which adds the badge's 20 pt (`SANDBOX_BADGE_EXTRA`). The Edit listing screen
  (`app/listing/edit/[id].tsx:143`, heading "Edit listing") already uses `useTopInset()`, so the header
  seen was My listings, not the edit screen. Mechanism: the badge overlays the top of every screen on
  sandbox builds only (`pointerEvents="none"`, so taps pass through); F-SELL-1's fix moved the tabs, Home
  header, Sell form and Edit listing to `useTopInset()`, but not the other stack screens. From source the
  My listings overlap exists at every text size and grows at large sizes; only the largest size is
  device-observed. **Production impact: none** — production builds render no badge. Impact is on
  sandbox testing: headings and back buttons sit under the badge. **Same pattern, source-only candidates,
  not device-observed:** `app/settings/index.tsx:286`, `app/transfer/send/[id].tsx:152`,
  `app/transfer/receive/[id].tsx:275`, `src/screens/PlaceBidScreen.tsx:192`,
  `src/screens/checkout/CheckoutNative.tsx:764/924/1002`, `src/components/auth/AuthScreen.tsx:34`,
  `src/components/listing/ListingHero.tsx:63` (back/share controls over the image), and
  `src/components/account/SettingsHeader.tsx:26` (shared by the settings sub-screens). Proposed fix,
  not applied: switch each to `useTopInset()` with a source pin that no screen header pays `insets.top`
  directly; C, client-only, next candidate; device rows per screen.
- **DV-S2 step 2 (owner, Build 18, seller, largest text ON, 2026-09-17 01:40 EDT ≈ 05:40Z)** (owner-reported):
  *PASS:* the Edit listing heading clears the SANDBOX badge; swiping back with an unsaved change
  brought up a prompt; the owner tapped Keep editing. *Not reported:* the prompt's exact title, message
  and button labels, and whether the screen and the three letters remained after Keep editing — open,
  asked in step 3. Event name full visibility stays UNRESOLVED until directly confirmed (owner).
- **Execution sprint (owner via A, 2026-09-17):** F-SELL-2 implemented — **`frontend/sandbox-header-inset`
  @ 9d01bad** (from aad5f75; client only; supabase/ and gated payment files unchanged): `useTopInset()` on
  My listings, Settings, Transfer send/receive, Place bid, Checkout (top bar + both confirmation bodies),
  the auth shell, the shared settings header, the listing hero controls and the outbid toast; spacing
  tokens kept, production spacing identical, no doubled insets. 19 tests; RED 11 on Build 18 files; 9
  mutants killed; stated survivor: an aliased import of the helper in a host. Full 2096/96, tsc 0, lint
  0/29. D reviewing. Rendering unverified — device rows for the next candidate at normal and largest text.
  **Sprint fields sent to A:** F-AUTH-2 — severity LOW; next action: trace repeated loader effects
  (auth events or double mount) with a request-count test, device re-check by edge-log count; blocks
  this candidate: NO (load, not correctness). F-DT-1 — severity LOW–MED (accessibility); next action:
  upstream React Native record for live Dynamic Type under the new architecture, plus a next-candidate
  device row; mitigation only with the owner's decision; blocks this candidate: NO (relaunch recovers,
  no data loss). **140 client adaptation** (outcome codes transitioned/already_sent, attach →
  attached/already_attached, attach entry point for a sent transfer with no proof): separate client head
  from the stack tip 4331ea4 after D closes F-SELL-2; exact raise texts requested from A.
- **F-SELL-2: D PASS on 9d01bad; A integrated at stack head e9413d8** (release/production-gate-20260918).
  D's independent sweep found only the badge and the helper reading the raw inset. D's intention for the
  security-notice banner's DV-N row: render it as an overlay like SandboxBadge rather than the interim
  paddingTop, since every other surface now pays its own inset — later, not this candidate.
- **140 client adaptation — `frontend/proof-outcome-attach` @ 5e9c80b** (from e9413d8; client only; supabase/
  and gated payment files unchanged; D reviewing). *Automated results only:* Mark as sent reads transitioned /
  already_sent with a sent read-back (the reply counts only when the read fails; a contradicted reply is
  unconfirmed); a transfer sent without a screenshot routes to an explicit **Add proof** section on transfer
  send (seller_sent with no stored proof only) calling `attach_transfer_evidence` (attached /
  already_attached); append-only refusal → has proof; raw `precondition_failed:` text never shown. Found and
  fixed on the way: c0281aa's "Pull down to refresh" copy had no pull-to-refresh on that screen. 27 new tests
  + 33 converted; literal guard pinned to 140 and the append-only guard; RED 30 on e9413d8's files; 15 mutants
  killed; full 2202/104; tsc 0; lint 0/29. *Evidence line (owner):* server outcomes 1–2 passed on the
  database side (A/B/D); conversion and buyer display unverified until a real iPhone round trip; device
  behaviour needs a build; the image issue is NOT described as fixed. DV-IMG rows wait for A's transfer ids.
  **D review → 5e14a68 → D PASS (2026-09-17):** D found refresh and submit could overlap (a late
  pre-submit read showing a confirmed proof vanish) → buttons wait for a refresh, a refresh waits for a
  submit (single-flight ref); a reply outcome without a sent status pinned as unconfirmed. Four mutants,
  each killed, re-run by D. Full 2204/104, tsc 0, lint 0/29. Head ready for A's integration; rendering,
  sandbox round trip and DV-IMG rows unverified.
  **Integrated by A: candidate head db16e1a** (tree aa93c03b; supabase/ and gated surface unchanged at
  merge), named in the owner's tag line subject to CI on that head and D's merge gate. No build yet.
  **CI on db16e1a: green** (run 35188006272, workflow CI, conclusion success, headSha db16e1a — read by C
  with `gh run view`); **D's merge gate: PASS, no open review item** (per A). **Build HOLD (owner + A,
  2026-09-17): db16e1a is not to be built until F-NAV-1 is resolved** — see below.
- **DV-S2 step 3 (owner, Build 18, seller, largest text ON; time not captured)** (owner-reported):
  *PASS — Discard path.* **FAIL — separate navigation defect F-NAV-1:** tapping **Keep editing** also took
  the owner back to My Listings instead of keeping the listing being edited open. **DV-S2 is NOT a full
  pass.** Whether the unsaved text survived Keep editing was NOT observed — the owner was taken off the edit
  screen, and asked that it not be inferred. The prompt's exact wording was not reported in this step.
  Event name full visibility stays UNRESOLVED (owner). The step-2 Keep editing outcome was not reported at
  the time; nothing is inferred about it.
- **F-NAV-1 (NEW, owner-reported, Build 18; C; repair scope; blocks building the candidate — owner + A HOLD).**
  *Source finding (C, read from the installed libraries):* `useUnsavedChangesGuard` held removal with a bare
  `beforeRemove` listener + `preventDefault()`, which holds navigation state only. native-stack 7.14.4 sets
  iOS `preventNativeDismiss` only from `usePreventRemove` registrations, so a swipe back completed in UIKit
  first (react-native-screens 4.16.0 `viewDidDisappear` → `onDismissed`); the pop that followed was refused
  and the prompt showed over My Listings. Discard replayed the pop so state caught up (looked right); Keep
  editing left the edit route in state but off screen. native-stack's own `useDismissedRouteError` names
  this case. The in-screen Back arrow (`router.back()` → GO_BACK) starts in JS and is held before anything
  moves — source predicts it already held on Build 18; **not device-checked.** Same hook: Report form
  ("Keep writing") and Settings → Preferences ("Still saving") — same swipe defect expected from source,
  not device-observed.
  *Fix:* **`frontend/unsaved-guard-native-dismiss` @ 2ba9e3a** (from db16e1a; client only; supabase/ and the
  gated payment/auth files: 0 lines) — the guard uses `usePreventRemove(when, …)`; Discard replays the
  action once. *Automated results only:* `tests/unsaved-guard-native-dismiss.test.ts` (17) renders the real
  Edit listing screen and the real hook with React Navigation core + StackRouter over a native-stack /
  react-native-screens iOS model pinned to installed source and exact versions
  (`tests/helpers/nav-stack-harness.ts`); per path (swipe back, Back button): the prompt does not navigate;
  Keep editing keeps the screen mounted with the typed Event name (read from the screen's own field); asks
  again; Discard leaves without saving after one prompt; clean and undone edits leave without asking. RED on
  db16e1a's hook: 3 swipe tests fail (native shows only My Listings); swipe-Discard and all Back-button tests
  pass there. 6 mutants killed as predicted (harness: clean baseline, anchor once, digest restore); no
  dedicated mutant for the typed-text assertion at first; **M7 added at A's request (no test change):** the screen
  resets its fields on a leave attempt while staying mounted → 4 killed as predicted before the run: both
  Keep editing tests at the Event name text assertion (route, native screen, same mounted instance all held),
  both "asks again" tests at the prompt count (the edits are gone, so the guard stands down — downstream of
  the lost text). Harness limit: routes added after start are not mounted, so a re-key mutant would read as
  "no screen", not a fresh mount; no test adds routes. CFT-208 pin updated. Full vitest 2221/105, tsc 0, lint
  0/29. Not modelled: Android back, animation, keyboard. **D reviewing; A integrates after D.** Device rows
  DV-NAV-1/2 (checklist) on the next build.
- **Owner ruling on F-NAV-1 (2026-09-17):** 2ba9e3a continues through D's review and A's integration. The M7
  text-loss check addresses the evidence gap. **Remaining limit, recorded:** the iOS layer in the tests is a
  model (native-stack / react-native-screens pinned to source and versions), not UIKit, and the harness does
  not mount routes added after start. Native navigation is verified only by DV-NAV-1/2 on the next build.
  **The fix is NOT device-verified until then.** DV-S2 on Build 18 stays **Discard PASS / Keep editing FAIL**;
  Event name full visibility UNRESOLVED.
- **S2-2 (DV-611C-2) started (owner, Build 18, Larger Text ON).** Step 1, on the normal network: seller sign-out
  (Profile › Sign out) → buyer sign-in (Use email instead → Sign in) → Home; the owner also checks whether
  Settings › Developer exists. Throttling from step 2: Network Link Conditioner if that menu exists; otherwise
  weak Wi-Fi, recorded as unmeasured. This Mac has only Command Line Tools (no Xcode), so Developer Mode cannot
  be enabled from here. A was notified for the expected registration outcome and the baseline read-back.
- **S2-2 step 1 (owner, Build 18, normal network, Larger Text ON):** Settings › Developer IS present on the
  iPhone. Seller signed out (Profile › Sign out) at 10:55 handset time; buyer signed in (Use email instead);
  Home loaded at 10:55. Network unchanged. A's expectation (135 `register_push_token`, looked up by token):
  `refreshed` (buyer-owned row); `challenge_required` would block, not fail (push delivery deferred). Limits:
  fewer than 20 register calls per 10 min; no DV-131-1 epoch bump during S2-2. A reads the baseline before the
  throttled launches. *Date check:* resolved below (A: server now() anchors today as 2026-09-17).
- **F-NAV-1: D PASS on the product change (2ba9e3a)**, with two test-only additions required and applied at
  **76b8622**. (1) Typed text is read after pending work settles: D's M8 (form reset one microtask later)
  survived 2ba9e3a's tests (0/17, confirmed by C). (2) Repeated attempts in all four orders (swipe/Back ×
  swipe/Back): Keep editing twice, and Keep editing → Discard. Plus a pin that expo-router's Stack fork renders
  upstream NativeStackView. 25 tests; db16e1a's hook fails 7; mutants M1–M8 and M11 each fail exactly the
  predicted set; full 2229/105, tsc 0, lint 0/29; delta test-only. D re-checks the head, then A integrates.
  D's residual, recorded: on a device `preventNativeDismiss` reaches native one commit after the keystroke,
  and the harness applies it in the same step. A swipe begun inside that frame would behave like Build 18.
  Negligible; only a device can show it.
- **Triage row (NEW, source-only, pre-existing on db16e1a, severity unset; D's observation, not run):** while a
  listing save is in flight the unsaved-changes guard is off by design (`submitting`). A swipe during the
  save leaves Edit listing, and the "Saved" alert's OK then calls `router.back()` from My Listings, which
  could pop one screen further. Not in F-NAV-1's scope; C to triage.

- **Date correction (A, server now() 2026-09-17T14:57:39Z = 10:57:39 EDT):** session 2 runs on **2026-09-17**,
  not 09-18. Every session-2 event dated 2026-09-18 in this file (from the S2-1 step 2 read-back onward), in
  the candidate plan's session-2 notes and in the checklist's DV-IMG fixture line is corrected to 2026-09-17
  (e.g. DV-S2 step 2 = 2026-09-17 01:40 EDT = 05:40Z; A's fixture read 2026-09-17T05:55:58Z). The sprint target
  (Fri 2026-09-18) and the tag names `candidate/2026-09-18-*` are names, and stay unchanged.
- **S2-2 baseline read (A, 2026-09-17T14:57:39Z; state, not the reply):** the buyer has exactly one push_tokens
  row, 140fcb44… (created 2026-09-08): is_active true, revoked null, **last_used 14:55:17.174Z** (one second after
  the buyer's only auth session, created 14:55:16Z), session_id live, device hash present, no provider error.
  That is consistent only with **`refreshed`** (not `registered`: the row predates today; not
  `challenge_required`: the buyer requested 0 challenges). The seller owns 0 rows (1 challenge, requested
  03:50:52Z at session 2's seller sign-in). Rebind epoch 2026-09-15, before the buyer session: no 42501 risk.
  Throttled launches are judged by last_used, is_active and session_id on 140fcb44; A reads after the step
  from the relaunch times.- **F-NAV-1: D PASS on 76b8622 (gate given to A).** D reproduced on the head: test-only delta (+60; 0 lines outside
  tests/, the gated surface, supabase/, scripts/ and .github/ since db16e1a); R0 / M7 / M8 fail 8 (7 + the CFT-208
  pin) / 12 / 12 of 46 across the two files; suite 2229/105 alone; tsc 0; lint 0/29. **Head ready for A's
  integration → new candidate head; the db16e1a build HOLD stays until A integrates.** Evidence class: source
  + tests only. **Device rows DV-NAV-1/2 are still owed on the next build**; nothing here stands in for them.
- **F-NAV-1 integrated by A: candidate head `f412d10`** (release/production-gate-20260918; --no-ff merge of
  db16e1a + 76b8622; tree 0409138f identical to 76b8622's — parents and tree verified by C). A's reruns on
  f412d10, alone: vitest 2229/105, tsc 0, lint 0/29; gated surface, supabase/, scripts/, .github/ vs db16e1a:
  0 files, so replay, pgTAP, census and sandbox pins carry over. **The hold's condition (reviewed by D,
  integrated) is met.** CI 35237352892 on f412d10: **in progress** (C read `gh run view`), then D's
  merge-preservation gate; the tag line names f412d10 only after both are green. No build yet. Evidence class:
  source + tests; DV-NAV-1/2 owed on the next build; phone-only residual: a swipe begun within one frame of the
  first keystroke.
- **f412d10 cleared for the owner's decision:** CI 35237352892 **success on all five jobs** (Admin console, Migrations
  apply cleanly, Typecheck/Lint/Unit tests, Web build, Deno type-check; C read `gh run view`); D's
  merge-preservation gate PASS (per A). Package issued for approval at converge ab64f1e. **Line 1 (awaiting the
  owner, not authorized yet):** "Create candidate/2026-09-18-build-c3 at f412d10 and have C submit one sandbox
  preview build." Nothing is tagged or built until the owner speaks that line. Limits stand: no phone has run
  F-NAV-1 or the image flow.
- **S2-2 step 2 (owner, Build 18, buyer, Larger Text ON):** Settings › Developer › Network Link Conditioner:
  profile **Very Bad Network** selected and **Enable ON** (the owner confirmed on their own screenshot). Enabled
  11:01 EDT; profile confirmed 11:03 EDT (2026-09-17). Snatch It not reopened since the buyer sign-in (10:55).
  Next: throttled cold launch 1; C asked A for a read after EACH launch, so each outcome can be attributed.
- **S2-2 launch 1 (owner, Build 18, buyer, Very Bad Network + Larger Text ON, 2026-09-17):** force-quit →
  reopened **11:06 EDT** (≈15:06Z, minutes only). Home loaded after "a couple of seconds". Settings ›
  Notifications: **no banner**; Try again not tapped. **Result pending A's read.** The owner's rule: no banner
  alone does not confirm registration. PASS for this launch needs A's read to show it registered (last_used on
  140fcb44 advanced to ≈15:06Z with the counter incremented). No banner and no registration is silence = FAIL
  (D's rule). Launch 2 waits for the read.
- **S2-2 launch 1 → registered (A's read, server now 2026-09-17T15:07:51Z).** 140fcb44 last_used 14:55:17.174Z →
  **15:06:09.326Z** (11:06:09 EDT, matching the 11:06 reopen); active, no revoke, no provider error; one buyer
  row. Rate-limit counter **1** in a **new window** (window_start 15:06:09Z; the 14:55:17Z window had expired),
  so exactly one register call reached the verb, and it moved last_used. Same single live buyer session (no
  re-sign-in); 0 buyer challenges; consistent with `refreshed`. **Launch 1: PASS**: a visible outcome (the
  registration, confirmed server-side, with no failure banner) under Very Bad Network. The reply's arrival
  in the app is not observable server-side. Launch 2 before ≈15:16:09Z should read counter 2.
- **S2-2 launch 2 (owner, Build 18, buyer, Very Bad Network + Larger Text ON, 2026-09-17):** force-quit →
  reopened **11:08 EDT** (≈15:08Z). **Home finished loading 11:09 EDT, roughly one minute; exact duration not
  measured.** Launch 1's Home loaded in a couple of seconds. Settings › Notifications: **no banner**; Try again
  not tapped. **Registration result pending A's separate read** (PASS needs last_used past 15:06:09.326Z with
  counter 2 in the 15:06:09Z window; otherwise silence = FAIL). The slow Home load is recorded with the result
  as an observation, not a pass criterion; whether it is only Very Bad Network or a finding is open until the
  read.
- **S2-2 launch 2 → registered (A's separate read, server now 2026-09-17T15:11:01Z).** 140fcb44 last_used
  **15:09:06.746Z** (11:09:06 EDT; 2 min 57 s after launch 1's); active, no revoke, no provider error; one row.
  Counter **2** in the same 15:06:09Z window, so exactly one more call reached the verb. Same single live buyer
  session; 0 challenges. No auth refresh gated either launch (refreshed_at null; the only rotation is the
  14:55:16Z sign-in). **Launch 2: PASS** (registered, server-confirmed; no banner). **Recorded with it:** Home
  finished loading ≈1 min after reopen (11:08 → 11:09, not measured), and the verb ran at 11:09:06, close to when
  Home finished. *Source (C, Build 18 aad5f75):* registration starts from the app shell
  (`useNativeEffects` → `usePushToken(userId)`) once the signed-in user is known. It does not wait for Home's data.
  It needs the Expo token fetch (bounded at 20 s) and then the RPC, over the same throttled link. The timing is
  consistent with network delay, but the server records only when the verb ran (A), so the cause is not proven.
  The ≈1 min Home load is an observation under Very Bad Network, not a finding unless it recurs on a normal network.
- **DV-611C-2 on Build 18: launch outcomes PASS 2/2** (both throttled cold launches registered and were
  confirmed server-side; no silence). **"Try again registers": UNTESTED.** No failure banner appeared on either
  launch, so Try again was never offered. Forcing a failure on Build 18 is confounded: Build 18 re-attempts
  registration on foreground (296439c is not in it), and under full loss Profile shows its load state without
  the Settings link. Not claimed as a full row pass.
- **S2-2 closed (owner):** Network Link Conditioner **Enable OFF at 11:14 EDT** (2026-09-17); profile selection left
  as it was; Larger Text ON. A recorded S2-2 in manifest §13 at converge 65f4e75 (launch outcomes PASS 2/2, Try
  again UNTESTED, push half DEFERRED).
- **S2-5 (DV-ST1..ST4) started as the buyer.** Step 1 = DV-ST1: airplane mode on, force-quit and reopen, then
  Home, Explore (Home's "Search events" icon, then type at least two letters — Explore only searches then),
  Bids, Tickets, Profile, each reached fresh. Build 18 copy (`src/lib/ui/loadState.ts`): "You're offline" /
  "Check your internet connection and try again." / Retry. Retry not tapped in this step. DV-ST2 stays gated:
  the trigger goes to A only after D confirms the witness is live and the kit is idle.
- **DV-ST1 step 1 (owner, Build 18, buyer, Larger Text ON, 2026-09-17): Airplane Mode ON at 11:17 EDT;** app
  force-quit and reopened offline. **Owner-reported for all five screens (Home, Explore, Bids, Tickets, Profile):**
  the same updated styling and message: "YOU'RE OFFLINE" / "Check your internet connection and try again." /
  "RETRY" (black text on a red button). Tickets therefore shows offline too (F-OFF-1). **Screenshot evidence
  (the owner's own, Home only, 11:18):** airplane icon; the SANDBOX — TEST MONEY ONLY badge; the SN header, MIAMI,
  the search icon and the YOUR SCENE / PRICE / FILTERS controls sit below the badge (clear, no overlap); a
  wifi-off glyph in a ringed disc; the three strings above; a red RETRY button with dark text; the tab dock below.
  *Evidence class:* Home by screenshot; the other four by the owner's observation only. **Heading clearance on
  the offline state is reported for Home only, not for the other four.** Profile's offline branch renders the
  state view without its header, so it stays unconfirmed there. Retry not tapped. Airplane Mode left ON.
  Remaining DV-ST1: Airplane Mode off → the screen retries by itself.
- **DV-ST2 readiness (D, 2026-09-17, before C's trigger):** witness live (d_st2_witness.sh md5 acd1d6d1…,
  read-only; target checked without connecting: sandbox ref present, production ref absent; refuses phases
  other than before/after; never overwrites an earlier file; no ST2 witness file yet; the sandbox NOT read before
  the trigger). D's acceptance kit idle; nothing of D's running against the sandbox; no other D window open. D's
  sequence for A: trigger → A's fresh capture → D's before-read (UTC + md5) → A revokes → owner observes → A
  restores + verifies → D's after-read. The window closes only when the after-read matches the before-read; a
  mismatch stops everything until A investigates. A to confirm nothing of A's or B's is running at the trigger.
  **Trigger not sent.** It goes to A when the owner reaches DV-ST2 (after DV-ST1 step 2).
- **DV-ST1 step 2 (owner, Build 18, buyer, Larger Text ON, 2026-09-17): Home recovered by itself.** Home changed
  from the offline screen to loaded content around **11:20 EDT**, without Retry and without touching Home.
  *Sequence, as the owner clarified:* Airplane Mode had already been turned off to send the screenshots, and the
  owner watched Home recover during that reconnection instead of repeating the toggle. **The time Airplane Mode
  went off and the recovery duration were not captured: both UNKNOWN.** Source (Build 18): `ScreenState` retries
  when the network changes from offline to online while the offline state is showing.
  **DV-ST1 per check:**
  - offline copy and Retry on all five screens: observed (Home by the owner's screenshot, the other four by the
    owner's observation);
  - self-recovery: observed on Home, timing unknown;
  - heading clearance on the offline state: confirmed on Home only.
- **S2-5 → DV-ST2 reached. Trigger sent to A (C, 2026-09-17).** Sequence (D's ask): A's fresh capture → D's
  before-read → **A holds the revoke until C relays that the owner is ready** → revoke (the T+360 s watchdog
  starts) → the owner's no-preload observation (ST2a: force-quit, reopen, Bids) → A restores + verifies → D's
  after-read must match the before-read. ST2b (cached rows stay) UNTESTED: the buyer has 0 bid rows [SUPERSEDED reason: Bids also shows the buyer's purchases, so rows exist and no fixture is needed — see the reconciliation entry below].
- **DV-ST2 window (2026-09-17).** A's fresh capture 15:24:39Z (md5 5365050…, identical to 04:41:57Z; B and A
  confirmed quiet); D's before-read 15:25:09Z agrees; the owner said ready; **revoke 15:26:11Z** (`revoke select on
  table public.bids from authenticated`; authenticated select=false, insert/update/delete unchanged; watchdog
  armed for ≈15:32:11Z). C told the owner GO.
  **Observation (the owner's screenshot, handset 11:26, no text sent):** online (Wi-Fi and cellular, no airplane
  icon); the "YOUR BIDS" heading clear below the SANDBOX badge; an amber warning glyph in a ringed disc;
  **"COULDN'T LOAD THIS" / "Something went wrong on our side. Try again in a moment."** with a red RETRY; the dock
  with Bids selected. **Not the offline copy.** Matches Build 18 `loadState.ts` error copy. *Not stated by the
  owner, asked:* whether the app was force-quit and reopened first (ST2a no-preload) and whether Retry was
  tapped. The screenshot alone shows neither. C sent A RESTORE NOW on receipt; restore, verify and D's
  after-read pending.
- **DV-ST2 restored (A): 2026-09-17T15:27:32Z; verified 15:27:35Z.** relacl matches the 15:24:39Z capture exactly;
  authenticated select/insert/update/delete true; anon select unchanged; revoked flag cleared. The revoke lasted
  15:26:11Z → 15:27:32Z (81 s), inside the watchdog window; the watchdog will log idle at ≈15:32:12Z without
  acting. **Window still open until D's after-read equals D's 15:25:09Z before-read.** The ST2a classification is
  held until the owner answers (force-quit/reopen first? Retry tapped?). ST2b UNTESTED (the buyer has 0 bids) [SUPERSEDED reason: Bids also shows the buyer's purchases, so rows exist and no fixture is needed — see the reconciliation entry below].
- **DV-ST2a: PASS (owner-reported + owner screenshot, Build 18, buyer, online, 2026-09-17 handset 11:26).** The owner
  confirmed they force-quit and reopened Snatch It before tapping Bids (no preload) and did NOT tap Retry. With
  the bids SELECT revoked, Bids showed the server-error state ("COULDN'T LOAD THIS" / "Something went wrong on our
  side. Try again in a moment." + RETRY), never the offline copy. Heading clear of the SANDBOX badge
  (screenshot). **DV-ST2b (cached rows stay): UNTESTED**, the buyer has 0 bid rows [SUPERSEDED reason: Bids also shows the buyer's purchases, so rows exist and no fixture is needed — see the reconciliation entry below]. Retry behaviour under the error
  not exercised. The window closes on D's after-read matching the before-read (pending at this entry).
- **DV-ST2 window CLOSED (D, 2026-09-17T15:29:36Z):** D's after-read is byte-identical to the 15:25:09Z before-read
  (md5 466fd2d8… both): relacl, authenticated S/I/U/D, anon select, RLS and 3 policies back to pre-revoke. D
  witnessed the before and after states only, not the revoked state or the observation. ST2a PASS is C's and the
  owner's record; ST2b UNTESTED. Sandbox access returns to normal (B's hold ends on A's announcement).
- **S2-5 → DV-ST3 next (buyer, online, Larger Text ON):** Explore no-match, then the Bids empty states (the buyer
  has 0 bids), then Tickets. Build 18 source copy for reference only; the owner reads what is shown:
  - no-match: "Nothing matches" / "Try the venue name, or a shorter word.";
  - Bids: "No active bids" (Active) and "Nothing here yet" (Past);
  - Tickets: "No tickets yet", only if truly empty.
- **DV-ST3 (owner, Build 18, buyer, online, Larger Text ON, ≈11:31 EDT 2026-09-17; the owner reports taking
  screenshots, which were not attached in C's session, so this is owner-reported):**
  - Explore "zqxv": "NOTHING MATCHES" / "Try the venue name, or a shorter word." with a magnifying-glass icon and no
    Retry: matches the no-match spec.
  - Bids › Past: "NOTHING HERE YET" / "Ended auctions and completed purchases show up here.", no icon, no Retry.
  - Tickets: "NO TICKETS YET" / "Tickets you own will show up here.", no icon, no Retry.
  - Both empty states match "title + sentence, no glyph, no Retry" (and the Build 18 source copy).
  - Bids › Active is populated, so its empty state was not observed: the chip reads "ACTIVE 21" (per source the
    chip's number is the needs-action count, not the total); disputed "Sandbox L6" entries show "Paid $110 all
    in" and "VIEW DISPUTE".
  - Visible headings clear the SANDBOX badge.
  - **"Neither shows while a load is in flight": NOT established** (the owner).
- **Reconciliation, the buyer's "0 bids" vs a populated Bids tab (owner's request; source, Build 18
  `app/(tabs)/bids.tsx`):** the Bids tab is "Bids and purchases". It reads `public.bids` for the user (A's read: 0
  rows, correct), then MERGES the buyer's `transfers` (pending / seller_sent / disputed / buyer_confirmed /
  auto_released). **The 21 visible Active rows are disputed purchases (transfers), not bid records.**
  Consequences for DV-ST2:
  - **ST2a mechanism:** the bids query runs first; on its error the load returns BEFORE the transfers merge, so on
    a fresh launch nothing was on screen and the full error state showed. The disputed purchases were hidden while
    the bids read failed. That is correct for the row, and recorded as a source observation (a bids-only failure
    hides purchases), severity unset, not a defect claim.
  - **ST2b's recorded reason is corrected:** "0 bid rows" did not mean an empty tab. With the tab preloaded (21
    purchase rows), `loadError && bids.length === 0` keeps the rows on an error, so ST2b WAS testable with this
    buyer. It stays **UNTESTED** because this window ran no-preload (ST2a) only.

- **Owner rulings (2026-09-17, after DV-ST3):**
  - **DV-ST4 VoiceOver half: UNTESTED, the owner's skip** (standing). Its Reduce Motion and largest-text halves
    run as two separate handset checks.
  - **DV-ST2b: prepare a short repeat window using the existing 21 purchase rows; no bid fixture.** Coordinate A
    and D first; ask the owner "ready" before any access removal; the window is **NOT started**.
  - **The test plan was updated** so "no rows available" no longer generates fixture requests: checklist DV-ST2
    and plan S2-5 now say ST2b uses the buyer's existing purchase rows. The earlier "0 bid rows" reasons are marked
    superseded in place. A has withdrawn the cached-bids fixture (Line 2) at converge 558a58f, with the
    premise-error note on A's side.
  - **ST2b design (C, from Build 18 source):** the owner opens Bids online and sees the rows (preload) → A revokes
    bids SELECT (D's before-read first; watchdog) → owner GO: pull down to refresh on Bids once (`onRefresh` →
    `fetchMyBids(true)`), then wait a few seconds → note whether the rows stay and whether any message appears →
    no Retry → A restores → D's after-read. *Expected from source:* the rows stay (the error returns before the
    merge; the state keeps the prior rows) and **no error message is shown while rows exist**. `loadError` is used
    only for the full-screen state, so an error with cached rows is silent. That would be a source observation for
    the owner to judge, not assumed to be a defect.
- **Build c3, relayed by A (2026-09-17):** A reports the owner's authorization in A's session to create
  `candidate/2026-09-18-build-c3` at f412d10 and for C to submit ONE sandbox preview build from that exact commit
  (Build 18 and the sandbox application pin preserved; W-C3, the staged notice, the storage round trip and
  permanent transfer writes excluded). The tag exists (C verified: annotated, → f412d10a1131, tree 0409138f;
  build-b2 → aad5f75 and pin-b2 → 9bef640 unchanged). **C has NOT submitted.** A relayed permission is not
  authority, so C asked the owner to confirm directly. Build checks after confirmation: the source commit equals
  the tag, the dev-only Tickets label is absent, and the build number and installation link go to the owner and A.
- **DV-ST2b plan amended (A):** single pull-to-refresh on preloaded Bids; the owner must not switch tabs, background
  or force-quit; watchdog 360 s. **Discrimination:** "rows stay, no message" looks the same whether the refresh
  failed or never ran, so PASS also needs a read-only API-log read (≥10 min after the window, for ingestion lag)
  showing ≥1 denied GET /rest/v1/bids between the revoke and the restore near the owner's refresh time (path,
  status and time only). Without it ST2b is INCONCLUSIVE. The owner's window authorization must name that log
  read. Not started.
- **DV-ST4 Reduce Motion: recorded check by check, NOT a full Reduce Motion pass (owner, Build 18, buyer, Larger
  Text ON, Very Bad Network ON 11:37–11:39 EDT, 2026-09-17).**
  1. Reduce Motion enabled 11:37 EDT.
  2. Bids loading placeholders: **no placeholder animation seen; static placeholders NOT confirmed** (the owner saw
     an empty "no bids" message during loading instead; see F-BIDS-1).
  3. Profile loading indicator: **NOT observed** (already loaded).
  4. Home: **three dots until loading finished; whether they moved NOT confirmed.** Source (Build 18): the only
     "• • •" in the app is `Spinner`'s Reduce Motion branch; the normal branch is a spinning wheel. The full-screen
     launch overlay (`app/_layout.tsx`, "Loading Snatch It") uses it, and Home's own feed placeholder is a skeleton
     grid. So the dots imply the Reduce Motion branch rendered (probably the launch overlay). Inference, not
     observed.
  5. Network Link Conditioner disabled 11:39 EDT.
  - The largest-text half of DV-ST4 is already covered by DV-ST1's 11:18 Home offline screenshot at the largest
    size: heading clear of the badge, badge not scaled, title and body unclipped, Retry visible without scrolling.
    Other tabs not re-checked.
  - VoiceOver half UNTESTED (owner skip).
- **F-BIDS-1 (NEW, potential premature empty state; owner-observed on Build 18 under Very Bad Network; cause under
  investigation, not yet claimed as a defect):** Bids showed a "no bids" empty message while loading, on an account
  that shows 21 purchases. Exact wording not captured.
- **F-BIDS-1: cause established (source + reproduction tests; the device observation is the owner's).** Build 18 and
  c3 carry identical code (`app/(tabs)/bids.tsx`, `src/lib/bids`, EmptyState unchanged aad5f75..f412d10).
  `fetchMyBids` reads `public.bids`, then the buyer's `transfers`, then `setBids(merge)`, but:
  - **(A)** `setLoading(false)` runs right after the BIDS read, before the purchases read. For a buyer with 0 bids,
    the screen has loading=false and rows=[] for as long as the purchases read takes, so the empty message ("No
    active bids" in source) shows until the purchases arrive. Very Bad Network stretched that window.
  - **(B)** the purchases read's error is ignored (`const { data: txData } = …`, no error check). If it fails, the
    merge proceeds with nothing, so the empty message shows as if the buyer had no purchases. A silent refresh
    whose purchases read fails would also replace rows already on screen with bids-only rows (source reading; no
    test for this third path yet).
  - **Evidence:** local branch `investigate/bids-empty-while-loading` @ f412d10 (not pushed, not for integration),
    `tests/bids-empty-while-loading.test.ts` renders the real Bids screen with both reads controlled. Control
    (both reads finish → 21 purchase rows) passes. R1 (empty while the purchases read is in flight) and R2 (empty
    after a failed purchases read) FAIL on f412d10.
  - **Causal probes** (temporary source edits, digest-verified restore): moving `setLoading(false)` to after the
    merge makes R1 pass (R2 still fails); also surfacing the purchases-read error makes both pass.
  - **Classification:** a presentation defect that misstates purchase state: a disputed purchase briefly, or on a
    read failure indefinitely, looks absent. No money action. Pre-existing (the data layer predates V2). DV-ST3's
    "not shown while a load is in flight" sub-check: observed failing on Bids (owner) and reproduced (tests).
  - **Release readiness (C's recommendation to A and the owner):** does NOT block the c3 preview build (identical
    code, no regression; c3 verifies F-NAV-1 and F-IMG-1). SHOULD be fixed before production release. Severity
    MEDIUM (misleading state on a purchase with an open dispute). No fix without the owner's scope decision; the
    fix shape is the two probes plus tests for R1, R2 and the refresh path.
- **Owner decisions (direct, C's session, 2026-09-17):**
  1. **"I confirm authorization to submit ONE sandbox preview build from candidate/2026-09-18-build-c3 at f412d10…
     same single build, not authorization for a duplicate."**
  2. **Implement F-BIDS-1 now on a separate branch for the next candidate:** both premature empty states and
     purchase-load failures; loading accounts for both requests; failed requests never look like genuine
     emptiness; previously loaded purchases stay visible on a failed refresh, with a clear failure indication;
     behavioural tests; D review; reviewed head to A; **c3 unchanged; no other build or deployment.**
  3. **Test results preserved:** Bids FAILS DV-ST3's no-empty-message-during-loading check; Reduce Motion stays
     recorded per observation; VoiceOver stays skipped. DV-ST2b is not started (the owner sends "ready" and the
     window approval separately).
- **Build c3 submitted by C (2026-09-17 ≈15:5xZ): EAS build `8ebf4d81-2938-41d9-9bfd-6d20e8645325`**
  (https://expo.dev/accounts/jdt_inc/projects/snatchit/builds/8ebf4d81-2938-41d9-9bfd-6d20e8645325), message
  "candidate 2026-09-18 build-c3 f412d10".
  - **Duplicate check before submitting (two independent reads):** C `eas build:list` (all platforms and iOS) and
    A's own list at ≈15:50Z showed no build for f412d10 or newer than Build 18 in any state; A: A, B and D have
    never run eas. C re-checked immediately before submitting (latest = 18 / aad5f75).
  - **Worktree:** clean worktree `/Users/josetascon/snatchit-c3` detached at tag c3 (HEAD f412d10a1131…, 0
    dirty files after `npm ci`).
  - **Config:** eas.json, app.json, envGuard, package.json and package-lock identical to Build 18 (aad5f75).
  - **Dev-only Tickets label:** the only `setDevFixtures` call is inside the `__DEV__` branch
    (`app/(tabs)/tickets.tsx:118–121`), so a release build cannot turn fixtures or their label on (ac70643
    rule).
  - **Pending:** build completion, the build record's commit = f412d10, build number, installation link → owner
    and A. Build 18 and the sandbox pins untouched.
- **F-BIDS-1 fix — `frontend/bids-load-states` @ 1ad216f** (from f412d10; for the NEXT candidate; c3 unchanged;
  client only; gated surface, supabase/, scripts/, .github/: 0 lines). **Automated results only.**
  - **Behaviour:** a load is both reads, and loading lasts until both answer. Either read failing fails the load
    and replaces nothing: with no rows the full error state; with rows they stay under an inline notice ("Couldn't
    refresh your bids and purchases. Showing what loaded earlier." / offline wording) with Retry. Success clears
    it. A genuinely empty account still shows the empty copy.
  - **Third path reproduced by the tests:** a refresh whose purchases read failed wiped the 21 rows on f412d10.
  - **Evidence:** 13 behavioural tests render the real Bids screen with both reads controlled; RED 9/13 on
    f412d10; mutants M1–M8 each fail exactly the predicted set; full 2242/106, tsc 0, lint 0/29.
  - **D reviewing; A integrates into a later candidate after D.**
  - **Behaviour change to note:** on a failed refresh with rows, a notice now shows where Build 18 and c3 are
    silent. A future ST2b on a build with this fix expects the notice; on c3 it does not.
  - **Test results preserved:** Bids FAILS DV-ST3's loading clause on Build 18 (and on c3, which carries the same
    code).
- **c3 build 8ebf4d81 status (C, `eas build:view`):** IN_PROGRESS, build number **19**, commit
  f412d10a11310167fc0227fe58ea189822bec625 (= the tag), profile preview.
- **Build c3 FINISHED: Build 19** (EAS `8ebf4d81-2938-41d9-9bfd-6d20e8645325`; installation link
  https://expo.dev/accounts/jdt_inc/projects/snatchit/builds/8ebf4d81-2938-41d9-9bfd-6d20e8645325). iOS, profile
  preview, app 1.0.0, SDK 54.0.0.
  - **Commit f412d10a11310167fc0227fe58ea189822bec625, which matches tag `candidate/2026-09-18-build-c3`.**
  - Started 15:48:20Z, completed 15:55:30Z (2026-09-17); artifact
    https://expo.dev/artifacts/eas/ZRK55cDy9yKaWJACZepCxj60KaDVRTqWTnYll9IPaGg.ipa.
  - **Exactly one c3 build:** the all-platform list reads 19 (f412d10) → 18 (aad5f75) → 17 (aabe029). The c3
    worktree still has 0 dirty files.
  - Sandbox configuration: eas.json, app.json and envGuard are identical to Build 18. The dev-only Tickets
    label is not reachable in a release build.
  - Build 18 and the sandbox pins are untouched. Link sent to the owner and A.
  - **Device evidence: none yet.** The F-NAV-1 rows (DV-NAV-1/2) and the F-IMG-1 rows (DV-IMG-*) are owed on
    Build 19. F-BIDS-1 is NOT in Build 19 (the fix is on 1ad216f, for a later candidate).
- **F-BIDS-1: D PASS on the 1ad216f product change**, with one required test and the generation guard preferred in
  this head (after A pointed out that the false notice over fresh rows is new with this fix).
  - **Head 5da8a75** (on 1ad216f):
    - a02c824, test-only: an offline purchases-read failure keeps the rows with the offline wording, killing D's
      surviving mutant D8; a genuinely empty account whose refresh fails shows the error state.
    - 5da8a75: only the latest load may change rows, error or loading (a `loadGen` ref, checked after each read).
      The latest load always ends loading.
  - **D's overlap findings on 1ad216f, reproduced:**
    - an older load failing after a newer one succeeded showed "Couldn't refresh…" over fresh rows (new with the
      notice);
    - an older success after a newer failure replaced the screen with an older snapshot and cleared the failure
      (already on f412d10).
  - **Evidence (automated only):** 19 tests; RED 4/19 on 1ad216f and 14/19 on f412d10; 16 mutants each fail
    exactly their predicted sets. Disclosure: in the first pass G2 survived (the fixture never reached the
    purchases-read guard, so O4 was added), and three predictions written before O4 existed were corrected and
    re-run. Full 2248/106, tsc 0, lint 0/29. Gated surface 0.
  - D re-reviews; A integrates into a later candidate. **Not in Build 19; not device-verified.**
  - **Per-build expectation for a future DV-ST2b:** on c3/Build 19 and Build 18, a failed refresh keeps rows with
    NO notice; on a build with this fix, it keeps rows WITH the notice.
- **F-BIDS-1: D PASS on 5da8a75 (the guard included), with two test-only pins required → accb40c.** O5 and O6: a
  quiet refresh that overtakes a full-screen Retry and then fails (at its bids read / its purchases read) shows the
  error state, never stuck placeholders. These kill D's surviving GD4 and GD5. 21 tests; 19 mutants each fail
  exactly the predicted set on the first run (predictions written before); full 2250/106, tsc 0, lint 0/29;
  delta test-only; gated surface 0. D's userId note (the generation bump happens after the `!userId` return) is
  left as a follow-up: the root layout redirects on auth change, so the tabs unmount. Awaiting D's gate on
  accb40c, then A (next candidate).

## Handset session 3 — Build 19 (c3 = f412d10; owner installed 2026-09-17)
Scope (owner): all later results are recorded against **Build 19**. The **Bids fix (F-BIDS-1) is NOT in Build 19**.
The image rows (DV-IMG-*) wait for the sandbox window. Order: step 1 the sandbox badge and the signed-in account;
then Keep editing (DV-NAV-1/2); then header spacing (the F-SELL-2 device rows). Carried settings at the start:
Larger Text at the largest size ON; Reduce Motion ON (since 11:37); Network Link Conditioner OFF (since 11:39).
- **F-BIDS-1: D PASS at accb40c** (reproduced: test-only delta, 21/21, GD4 {O5}, GD5 {O6}, D8 {R5}, guard removed =
  {O1, O2, O4, O5, O6}, suite 2250/106, tsc 0, lint 0/29). The userId follow-up is accepted as a follow-up. **Sent
  to A for the NEXT candidate** (never Build 19). Branch frontend/bids-load-states: 1ad216f, a02c824, 5da8a75, accb40c on
  f412d10. **Device row still owed on a build that carries it.**
- **Build 19 step 1 (owner, 2026-09-17 12:10 EDT):** opened on Home, still signed in after the install; the SANDBOX
  badge is visible (exact wording not transcribed); Profile shows the sandbox **buyer**. Next: switch to the seller
  for DV-NAV-1. Buyer sign-out → `signed_out` on the buyer's token row. A was told that the seller's sign-in on this
  install may request a proof-of-possession challenge (the token row is buyer-owned; push delivery is deferred,
  so it cannot confirm). That is expected and does not block the Keep editing rows.
- **Build 19 step 2 (owner, 12:12 EDT):** signed out of the buyer, signed in as the seller; Home loaded; Profile shows
  the seller. Separate sign-out and Home-load times not captured. No notice reported. Next: DV-NAV-1, swipe path.
- **Sandbox approval relayed by A (2026-09-17):** the owner approved the four actions in A's
  `docs/release/SANDBOX_APPROVAL_REQUEST_C3_20260917.md` (converge; sandbox only, in order):
  1. Line 1 storage round trip (API only);
  2. W-C3 (136 → 139 → 140 + stripe-webhook and notify-report from f412d10);
  3. staged security notice (DV-N-1..3, C guides);
  4. Line 3 permanent transfer-test writes (DV-IMG-4/-5/-9+3b/-10, C guides).

  **Not yet confirmed to C directly**; C asked the owner. The handset restrictions A asked for are followed now,
  because they only narrow what the handset does:
  - no proof upload and no Transfer send screen until A closes Step 1;
  - the owner is paused at a safe point before W-C3's S1, with no handset test during W-C3;
  - no transfer or notice screen until A announces W-C3 closed;
  - no DV-ST2b during any of it.

  Keep editing and header rows continue (Step 0). Steps 3–4 guidance starts only after the owner's direct
  confirmation and A's go.
- **Build 19 DV-NAV-1 swipe path (owner, seller, Larger Text + Reduce Motion ON, 2026-09-17 12:14 EDT): Keep editing
  PASS and Discard PASS (owner-reported, the owner's handset test).** Details not captured: the exact prompt wording
  and the swipe animation. **NOT covered by this report:** the in-screen Back arrow path, repeated attempts (Keep
  editing twice, or Keep editing then Discard on a second attempt), the report form and Preferences rows
  (DV-NAV-2), and D's one-frame residual. The unsaved edit was discarded, so nothing is held. Build 18's F-NAV-1
  failure is not re-described; this is the Build 19 result.
- **Owner's DIRECT confirmation to C (2026-09-17):** "I directly confirm the four sandbox actions I approved with A:
  temporary storage round trip; W-C3 migrations 136 → 139 → 140 and the two scoped edge updates; the temporary buyer
  security notice; and the permanent photo-proof tests on the four named sandbox transfers. Follow the exact package
  scope, order, safeguards and stopping conditions. No production changes, push key, payouts or additional builds."
  C guides the notice and the permanent transfer tests **only after A and D confirm their prerequisites and the
  owner says they are ready**. The screen restrictions stand, with no overlapping DV-ST2b.
  The swipe-back result (12:14 EDT, Keep editing + Discard PASS, owner-reported) is already recorded above and is
  not repeated. The Back-arrow and repeated-attempt checks are separate and still unconfirmed.
- **Build 19 DV-NAV-1 in-screen Back arrow with a repeat (owner, seller, 2026-09-17 12:18 EDT): PASS (owner-reported).**
  First Back arrow → Keep editing: stayed on Edit listing, three letters remained. Second Back arrow → Keep editing:
  the same. Third Back arrow → Discard: back on My Listings, listing name unchanged. Each attempt showed one prompt.
  Exact prompt wording not captured. Nothing saved. **DV-NAV-1 on Build 19:** swipe path (Keep editing + Discard,
  12:14) and Back-arrow path with a repeat (12:18), both owner-reported PASS. Not covered: a repeated attempt on the
  swipe path, and D's one-frame residual. DV-NAV-2 (report form, Preferences) not run yet.
- **A: Step 1 (Line 1 storage round trip) CLOSED** (D's post-read = pre-read; all rt objects deleted; no
  application-table writes). **W-C3 next: handset PAUSED** (C to A at ≈12:2x EDT: the owner idle at a safe point on
  My Listings with no unsaved edit). No handset test and no transfer, proof or notice screen until A announces W-C3
  closed.
- **A: W-C3 CLOSED (2026-09-17), D's closing read agrees:** 136/139/140 applied and verified; census 32|109|37|37 exactly;
  stripe-webhook v5 and notify-report v4 byte-identical to f412d10; zero drift; the five transfers unchanged.
  **Handset may resume Step 0 rows**; transfer and proof screens stay reserved for Line 3's sequence.
  **Step 3 (staged notice) available:** A takes pre-counts and D a pre-read, then A writes ONE
  `security_device_rebound` row for the DV buyer (device_name "iPhone (DV staged)", dedupe
  dv-notice:140fcb44:2026-09-17) and verifies 0 delivery rows, **only after C's "buyer ready"**. C guides DV-N-1..3; A
  reads back read_at after Dismiss, then deletes the row and verifies cleanup. Per the owner, C asks whether they
  are ready before starting.
- **Build 19 step 5 (owner, 2026-09-17; screenshots 12:32 Home and 12:33 Profile): signed in as the sandbox buyer**
  (Profile "sandbox-buyer", 0 active, 0 sold, My listings 0 total). **A notice was already showing, NOT the
  staged test notice:** "Account deletion requested" / "Your account deletion request was received. You can
  withdraw it from Settings while it is pending." / DISMISS, on both Home and Profile. **The owner did not dismiss
  it.** C did NOT send "buyer ready", so A has written nothing. A asked (read-only) to confirm no staged row
  exists, list the buyer's notice rows (type, created, read), and say whether a deletion request is actually
  pending for the buyer.
  - *Source (Build 19):* the banner shows the NEWEST unread notice of any mandatory account_security type. A staged
    rebound row would show first, then this deletion notice would reappear after Dismiss, which would confound
    DV-N-3 unless DV-N-3 is defined against the staged row.
  - *Screenshot observations (not assessed):* while the banner shows, Home has a large gap between the banner and
    the SN header (the "interim double gap" D noted at da1d11d; the overlay is the follow-up). On Profile the tab
    dock sits over the SIGN OUT button at that scroll position.
  - No notice touched; the owner waits on Home.
- **A's read-only answers (2026-09-17T16:35Z):** no staged row exists. The buyer's only security-set notice is
  f3abe550…, `account_deletion_pending`, created 2026-09-14T04:28:00Z, unread and undismissed, with 2 pre-existing
  delivery rows. **No deletion is pending:** deletion_state ACTIVE, deletion_requested_at null, 0 account_deletions
  rows. Line 3/RT6 is unaffected. A disclosed one statement that errored on a column name and was re-run corrected.
- **F-NOTICE-1 (NEW; A's finding, C triage; server-side): a stale "Account deletion requested" notice on an ACTIVE
  account.** The notice says "…You can withdraw it from Settings while it is pending" while no request is pending;
  withdrawal apparently does not retire the pending notice. Proposed severity MEDIUM (misleading account-security
  statement). Fix lane: A/B (server). Does not block Build 19's client rows. The owner decides scope. Not touched.
- **C correction (to A):** an earlier C line said Dismiss shows only for non-rebound types, which was wrong. Build
  19 `actionsFor`: the rebound type gets "Sign out of all devices" + "Dismiss"; other types get "Dismiss" only.
  `dismiss` marks only the displayed notice (`mark_security_notices_read`, `p_ids = [notice.id]`).
- **DV-N plan (restated from Build 19 source; not started):**
  - DV-N-1: after A's write, background and return (or relaunch). The staged rebound notice shows (newest unread),
    matching A's expected rendered text, with both buttons. **Never tap "Sign out of all devices".**
  - DV-N-2: Dismiss on the staged notice. The banner hides. A reads read_at set on the staged row; f3abe550
    unchanged.
  - DV-N-3: relaunch. The staged notice is not shown; the deletion notice showing again is expected (not a fail)
    and is not touched.
  - A deletes the staged row whatever the outcome.
  - "buyer ready" goes to A only after the owner confirms.
