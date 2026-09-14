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
