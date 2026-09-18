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
- **DV-N-1 expected text (A, read-only ≈16:38Z; a correction to the plan above):** get_inbox renders the highest
  template version for the reader's locale (en-US), and 136's v2 in_app template has NO {{device_name}}, so "iPhone
  (DV staged)" is NOT shown. **Title:** "A device stopped receiving your notifications". **Body:** "A device that was
  getting notifications for this account is now registered to a different account. If that was you signing in to
  another account, there's nothing to do. If not, sign out of all devices." Buttons: "Sign out of all devices" +
  "Dismiss". Seeing the device name would mean v1 rendered, which would be a finding. A has added F-NOTICE-1 to the
  sprint table for the owner's scope decision. Still waiting on the owner's "buyer ready".
- **Staged notice, owner READY (2026-09-17):** "I'm ready as the DV buyer on Build 19 for the staged security-notice
  test. The existing 'Account deletion requested' notice is visible and must remain untouched. … I will not tap
  'Sign out of all devices' or dismiss the existing deletion notice." C sent A "buyer ready" and cc'd D.
  Sequence: A pre-counts → D pre-read → A's ONE write → A "written" → C GO → DV-N-1..3 → A deletes → D after-read.
- **Staged notice WRITTEN (A, 2026-09-17T16:42:48Z):** notification_id fb23b20a-72fa-4fa7-968c-3a4191136a3d,
  security_device_rebound / account_security, read_at null, dismissed_at null, dedupe dv-notice:140fcb44:2026-09-17.
  Pre-counts matched exactly (so exactly one write). Post: 0 delivery rows for it; the buyer now has 2 rows;
  notification total 10; delivery 18; queue 0; f3abe550 unchanged. **Stop rule (A + owner):** if the banner shown
  does not exactly match the staged title and the two-button layout, the owner taps nothing and C stops. C sent the
  owner GO for DV-N-1.
- **DV-N-1: PASS (owner-reported, Build 19, DV buyer, 2026-09-17 12:44 EDT).** After backgrounding and reopening, the
  staged notice showed exactly A's expected v2 text: title "A device stopped receiving your notifications"; message
  "A device that was getting notifications for this account is now registered to a different account. If that was
  you signing in to another account, there's nothing to do. If not, sign out of all devices."; buttons "SIGN OUT OF
  ALL DEVICES" and "DISMISS" (uppercase button styling). **No device name** (v2, not v1). The owner tapped nothing and
  did not mistake the deletion notice for it. D's read at 16:43:21Z agreed with A's write. Next: DV-N-2.
- **DV-N-2 (owner-reported, 2026-09-17 12:46 EDT):** tapped Dismiss once on the staged banner. It disappeared with no
  error shown; nothing else was tapped (not "Sign out of all devices"). Per source, the banner hides until the next
  load, so the deletion notice is not expected back until a refocus or relaunch. **Result pending A's read-back:**
  read_at on fb23b20a only, f3abe550 unchanged. DV-N-3 waits for it.
- **DV-N-2: PASS (owner tap + A's read-back at 2026-09-17T16:47:20Z).**
  - fb23b20a read_at **16:46:11.195Z**, matching the 12:46 EDT tap; dismissed_at null (Dismiss calls
    mark_security_notices_read, which sets read_at).
  - **f3abe550 (deletion notice) unchanged** (read_at null, dismissed_at null).
  - Buyer rows 2; notification total 10; delivery 18; 0 delivery rows for the staged id; queue 0; 2xx 0.
  - **No sign-out or session change from the tap:**
    - the buyer's newest session is 16:32:39Z (the owner's Build 19 sign-in); the other session is A's Line 1
      password-grant sign-in at 16:16Z;
    - push row 140fcb44 active and session-bound;
    - push_binding_epoch still 16:12:37Z, with no bump.
  - Next: DV-N-3 (relaunch).
- **DV-N-3: PASS (owner-reported + the owner's screenshot, Build 19, DV buyer, 2026-09-17 12:48 EDT).** After a force-quit
  and reopen, the staged notice "A device stopped receiving your notifications" did NOT reappear. Only the existing
  "Account deletion requested" notice shows (expected; F-NOTICE-1 unchanged). Nothing tapped. **DV-N-1..3 on Build
  19: PASS.** The owner asked A to delete ONLY fb23b20a and verify cleanup (buyer rows = f3abe550 only, unchanged;
  notification total 9; delivery 18; queue 0), then D's cleanup read.
- **Staged notice cleanup (A, 2026-09-17):**
  - Pre-check 16:49:11Z: the row matched exactly, with 0 delivery rows.
  - Delete 16:49:12Z, on notification_id AND the dedupe key: exactly one id returned.
  - Verify 16:49:13Z: buyer rows = f3abe550 only (unchanged: read_at null, dismissed_at null); staged rows 0;
    notification total 9; delivery 18; queue 0; 2xx 0. **This equals the pre-write state.**

  Step 3 closes on D's cleanup read (pending at this entry). Line 3 (Step 4) does not start without the owner's
  separate readiness through C, and it begins with A's PC1–PC8.
- **Step 3 (staged notice) CLOSED (D's cleanup read 2026-09-17T16:58:13Z agrees with A):** the buyer is back to only
  the deletion notice (unchanged); notification total 9, delivery 18, queue 0, 2xx 0; every non-timestamp line
  identical to D's pre-read; there was never a delivery row or queued request for the staged notice. **Summary:**
  DV-N-1..3 PASS on Build 19; sandbox restored to its pre-write state; F-NOTICE-1 open for the owner's scope
  decision. Next: the owner chooses Line 3 (needs their separate readiness) or Step 0 rows.
- **Owner (2026-09-17, after Step 3): run the remaining Step 0 Build 19 checks before Line 3, each recorded separately;
  Larger Text and Reduce Motion stay ON; no transfer or proof-upload screens.**
  1. Header spacing at the largest text size across the affected screens (F-SELL-2).
  2. Report form: Keep writing preserves the form and unsaved text (DV-NAV-2a).
  3. Settings › Preferences: the pending "Still saving" state and Wait (DV-NAV-2b).

  D's Step 3 cleanup confirmation arrived (16:58:13Z, recorded above). The owner decides the Line 3 start afterwards.
  **F-SELL-2 screen plan (as the buyer; no sandbox writes):**
  - H1: My listings, Settings, Settings › Notifications (shared settings header), a listing detail's top controls.
  - Sign-in screen: at the next account switch.
  - NOT in this pass:
    - Transfer send/receive: restricted until Line 3.
    - Place bid and Checkout: opening them risks a bid or a reservation on sandbox fixtures.
    - Outbid toast: needs a real outbid event.

    These stay UNTESTED with those reasons.
- **Build 19 check 1a, F-SELL-2 header spacing at the largest text (owner-reported, DV buyer, 2026-09-17; time not
  captured, after 16:58Z): PASS on four screens.**
  - My listings (Build 18 failed here): heading clears the SANDBOX badge; no clipping, no unusual gap.
  - Settings: the same.
  - Settings › Notifications (shared settings header): the same.
  - Listing detail top controls: the back arrow and More actions clear the badge; no clipping, no unusual gap.

  Still UNTESTED for F-SELL-2: transfer send/receive (restricted until Line 3), Place bid and Checkout (risk of a bid
  or reservation), the outbid toast (needs an event), and the sign-in screen (at the next account switch).
- **F-NOTICE-1 (recorded separately from the header test, per the owner):** the "Account deletion requested" banner is
  still present on the buyer's tab screens during check 1a; not interacted with.
- **Build 19 check 2, DV-NAV-2a report form (owner-reported, DV buyer, 2026-09-17; time and prompt wording not
  captured): Keep writing PASS.** After both navigation attempts (swipe back, then the Back arrow) the report screen,
  the selected "Other" reason and the notes "test note abc" remained. Discard returned to the listing.
  **SIDE EFFECT (owner-disclosed): the owner then accidentally tapped "Submit report", so a real sandbox report was
  probably created. This check is NOT a no-write test.** Report target not confirmed (a listing; probably Device D8).
  - *Source:* a reports insert fires the notify-report path (pg_net; the URL comes from Vault `project_url` since
    133). notify-report v4 (sandbox, from f412d10) claims delivery (139), calls send-push for admins (refused under
    option b) and sends Resend email only if a key is set and EMAIL_ENABLED=true.
  - **C asked A (read-only) to** identify the report row(s) and any moderation, queue or notification rows; confirm
    the trigger posted to the SANDBOX URL; and confirm whether any email or push actually left. If anything left
    the system, that breaches "no outbound notification" and the owner is told at once.
  - **Cleanup:** not covered by the four approved actions. A prepares an exact scoped plan without executing; the
    owner gives an explicit go. Line 3 unstarted.
- **Sequencing, relayed by D (a restriction, not an authorization; not yet confirmed to C directly):** the owner told D
  "Continue the Build 19 handset checks and the already-approved sandbox work independently. DV-ST2b may run before
  Line 3, but Line 3 remains a separate irreversible authorization and must not start until I explicitly say 'ready
  for Line 3.'" D is ready to witness DV-ST2b (tag st2b) on C's trigger. **DV-ST2b still needs the owner's "ready" +
  window approval directly to C**, and it does not overlap the open report-submission trace or any cleanup.
- **Accidental report, A's read-only findings (2026-09-17):**
  - **NO outbound email or push left the system; nothing was changed.**
  - **The row:** public.reports 265b0041-88a0-4294-b0b1-699811bfe6d1 (the only report on the sandbox): reporter = DV
    buyer; target_type listing, target **"Device D7"** (b1c3c478…; seller 2f5844b4; listing active; NOT D8); reason
    other; notes "Test note abc" (the keyboard capitalized the T); status pending; created 17:31:05.486Z.
  - **No other writes:** no moderation or queue rows (no ops schema on the sandbox), and the scan since 17:30Z finds
    only this row.
  - **Why nothing was sent:** `public.notify_moderation_event` posts only when both the Vault service_role_key and
    project_url exist, and the sandbox holds project_url only. So no HTTP request was made to any URL, notify-report
    was never invoked, report_delivery_claim=0, and there are no notify rows. The function has no RESEND_API_KEY or
    EMAIL_ENABLED, so email would have been skipped anyway. A did not read the edge logs.
  - **Standing D7 rule:** the report does not retry or modify Device D7's payment state, and the cleanup would not
    touch D7.
  - **Cleanup plan (A; NOT executed; needs the owner's explicit go):**
    - Pre-reads by A and D must match: reports total 1 / pending 1, fields as above; claim 0; queue 0; D7 active; the
      since-17:30Z scan shows only that row.
    - One transaction deletes exactly that id with all its field predicates and raises unless exactly 1 row.
    - Nothing cascades: there are no FKs to reports, and its only trigger is AFTER INSERT.
    - Post-reads: reports 0; claim 0; queue 0; D7 unchanged; the scan empty.
    - Stop, with no write, on any pre-read difference.
    - Left untouched: D7, its seller, the buyer's account and inbox (including F-NOTICE-1), and the pg_net cron rows.
  - The Preferences check is held until the cleanup is decided, so its preference write cannot confound the scans.
- **Owner AUTHORIZED the report cleanup (direct to C, 2026-09-17):** "I authorize A to delete sandbox report 265b0041 per
  the scoped cleanup plan, with A and D pre- and post-reads. Delete only that exact pending report for Device D7,
  reason 'Other,' notes 'Test note abc.' Stop if the pre-check does not find exactly one matching report, any other
  report created since 1:30 PM, or any change to D7. Confirm afterward that no reports remain and D7, the buyer
  account, notices and background jobs are unchanged." Relayed to A (cc D) for execution. The handset is held.
- **Report cleanup: A's pre-read PASSED every stop condition (2026-09-17T17:40:50Z); the WRITE IS HELD by A's rule that a
  relayed permission is not authorization.** A asked the owner in A's own conversation to say: "A: go — delete
  sandbox report 265b0041 per the scoped cleanup plan."
  - **Pre-read:**
    - reports total 1 / pending 1 / since 17:30Z 1 / others 0;
    - keyed match 1 (row md5 b733b1aa…);
    - D7 active, unchanged (row md5 f7d130c3…);
    - buyer ACTIVE, 0 deletions, 2 sessions (newest 16:32:39Z), push row 140fcb44 active;
    - f3abe550 unread and undismissed; notify.notification 9, delivery 18;
    - claim 0, queue 0; cron 22/22 active (list md5 c2c5c079…); pg_net on its 2-minute cadence.
  - **Write design:** one transaction re-checks, and raises on any difference: no other report since 17:30Z, D7 md5,
    report md5. It then runs the keyed delete, raising unless exactly 1 row. D's independent pre-read requested. The
    report stays inert (no outbound path).
- **Accidental report DELETED (A, 2026-09-17), on the owner's go given directly in A's session, with D holding the same
  authorization directly.** A's pre-read 18:07:06.405Z and D's 18:06:33.290Z were identical (keyed match 1, report md5
  b733b1aa…, D7 md5 f7d130c3…, cron md5 c2c5c079…). The guarded delete at 18:07:08Z removed exactly 1 row
  ("deleted 1 row 265b0041 at 18:07:09.332Z"). A's post-read 18:07:15.755Z: reports total 0; D7 unchanged and active;
  buyer account unchanged (ACTIVE, 0 account_deletions, 2 sessions, push row active); notices unchanged (f3abe550
  still unread and undismissed; 9 / 18 / 104); jobs unchanged (claim 0, queue 0, 22 cron, same list md5, pg_net on
  cadence). No HTTP request before or after. D's post-read closes the incident in A's manifest §14. **Handset work may
  resume.** Line 3 unstarted (needs "ready for Line 3"); DV-ST2b may run first on the owner's word.
- **Build 19 check 3, DV-NAV-2b Settings › Your scene "Still saving" (owner-reported, DV buyer, 2026-09-17): PASS.**
  Very Bad Network on 14:23 EDT, off 14:24 EDT. The owner changed the Miami Beach preference once, swiped back
  immediately, **the "Still saving" prompt appeared**, tapped **Wait**, stayed on Your scene, and the save completed.
  The preference was restored to its original position (the owner's own reversible write, as scoped in Step 0).
  **Evidence limitation:** the exact prompt title, message and button labels were not captured.
  **Step 0 status on Build 19:** DV-NAV-1 swipe PASS, Back arrow + repeat PASS; DV-NAV-2a report form Keep writing
  PASS (with the disclosed accidental submission, since deleted); DV-NAV-2b PASS; F-SELL-2 header spacing PASS on
  four screens; DV-N-1..3 PASS; DV-611C-2 launch outcomes PASS 2/2 with Try again UNTESTED; DV-ST1 and DV-ST3 per
  check; DV-ST2a PASS.
  **Still open:** DV-ST2b (needs the owner's ready + window approval); Line 3 (needs "ready for Line 3", and its own
  order starts with the picker-only rows on the Transfer send screen); F-SELL-2 on the sign-in screen (next account
  switch), Place bid and Checkout (bid/reservation risk) and the outbid toast (needs an event); DV-IMG-7 Sell-form
  picker parity (seller, picker only, no upload); F-DT-1 device row; DV-ST4's VoiceOver half (owner's skip).
- **Line 3 / DV-ST2b sequencing, relayed by D (2026-09-17):** D reports the owner authorized Line 3 directly to D, and
  D's pre-check read matches the approved post-W-C3 baseline (md5 f66988…). The owner's sequence: A and D complete
  matching pre-checks, then C gives the first handset instruction. D also relays the owner's scope (the exact approved
  permanent transfer-test scope; synthetic images with location off; all seller/buyer/U2/anonymous checks; disposition
  safeguards and stopping conditions; no replacing or deleting attached proof; no push key; no payout or executor flag
  changes; no outbound notifications) and **"Keep DV-ST2b paused unless I authorize it separately"**.
  **C's position:** the DV-ST2b pause is a restriction and is honoured now. **Line 3 does not start until the owner
  says "ready for Line 3" to C**, which has not happened; a relay is not that. The handset is also still signed in as
  the BUYER, and Line 3's first rows are seller rows, so a switch is needed first.
- **DV-ST2b AUTHORIZED by the owner directly to C (2026-09-17):** "I authorize the DV-ST2b window: A may temporarily
  remove read access to bids for signed-in sandbox users for up to six minutes; D takes matching before and after
  readings; A performs one read-only API-log check at least ten minutes after the window. Use the existing purchase
  rows, do not create a bid fixture, and restore access immediately after the refresh." And: "C: wait for A and D to
  confirm their pre-checks, then give me GO. I will pull to refresh Bids once, without tapping Retry. Stop on any
  mismatch and keep Line 3 paused until this window is fully closed."
  Relayed to A and D; D's own rule may need the owner's words in D's session. Handset step now: preload Bids as the
  buyer and hold (Build 19 lacks the F-BIDS-1 fix, so the empty message may flash before the purchases arrive).
  PASS also requires A's later API-log check showing a denied GET /rest/v1/bids inside the window; otherwise
  INCONCLUSIVE. Line 3 stays paused until the window is fully closed.
- **Sequencing conflict resolved in favour of the owner's latest direct order (2026-09-17):** A reported Line 3
  authorized with A's PC1–PC8 (18:30:38Z) and D's pre-check both PASS and matching, and asked C to give the first
  Line 3 handset instruction. **C held it.** The owner's direct instruction to C is DV-ST2b first, with "Line 3 paused
  until this window is fully closed" — which includes A's API-log check at least 10 minutes after the window. A was
  told to run the DV-ST2b capture/before-read/revoke now and to re-verify the Line 3 pre-checks afterwards, since a
  revoke and restore touch grants. Line 3 step 0's constraints are recorded for when it starts: picker-only rows on
  3118bd30 (DV-IMG-1, -2, -3a, -6, -7); synthetic images only; Camera location off before DV-IMG-9; the no-image Mark
  as sent must stop at "Evidence required" before any network call; 83b83858 untouched; nothing on the buyer's side;
  A releases each row only after D's witness read of the previous one.
- **DV-ST2b blocked on A's side (2026-09-17):** A cannot open the window on C's relay. A quotes the owner's message to A:
  "DV-ST2b remains optional and must use the existing purchase rows. Do not open another restriction window unless I
  authorize it directly." A has asked the owner for one line in A's conversation ("A: go — run the DV-ST2b window as C
  described"). A honours the relayed sequencing restriction, so A is ALSO holding Line 3, step 0 included. A's window
  limit is 6 minutes with a watchdog; A's sequence and the INCONCLUSIVE-without-log-check rule are agreed. D similarly
  needs the owner's word in D's session for DV-ST2b. **Nothing is running; the handset has nothing to do.** The owner
  chooses: send A and D the DV-ST2b line, or run Line 3 first (which needs "ready for Line 3" to C) and DV-ST2b after.
  The two must not overlap.
- **Order resolved by the owner (2026-09-17): DV-ST2b FIRST, then Line 3**, confirming the owner's instruction to C.
  D reported the conflict (the owner had told D that Line 3 was authorized and DV-ST2b paused) and holds all witness
  reads for both windows until the owner writes to D. A likewise holds both, quoting the owner's line to A: "Do not
  open another restriction window unless I authorize it directly." Both honour the relayed sequencing but not the
  relayed permission. **Both windows idle; the two must never be live at once, since a bids revoke makes any Line 3
  reading unattributable.** A is staged to open the window within a minute of the owner's line, with the 6-minute
  watchdog, immediate restore-and-verify, and the API-log check. A will re-read PC3 bodies and ACLs after the window,
  before any Line 3 P row. A is meanwhile scoping F-NOTICE-1 (server-side, nothing on the sandbox).
  Handset: the owner reported Bids preloaded with rows showing; they hold or re-preload just before GO.
- **DV-ST2b window (2026-09-17):** D's before-read 18:35:23Z (md5 466fd2d8…, byte-identical to the ST2a baseline) and
  A's capture agree. **Revoke 18:36:23Z** (authenticated SELECT on public.bids false; insert/update/delete unchanged;
  anon SELECT untouched), hard stop 18:42:23Z. **A's disclosure:** A's first watchdog call failed (the script was
  invoked by bare name), so for ≈28 s after the revoke there was no automatic restore; A fixed and re-armed it
  against the original timestamp, and the 6-minute limit is unchanged.
  **Observation (owner, 14:38 EDT ≈18:38Z, one pull-to-refresh, no Retry / tab switch / background / force-quit):
  the purchase rows REMAINED VISIBLE.** Per the owner's instruction, whether any message or banner appeared, and
  whether the screen changed to an error or empty state, is recorded as **NOT EXPLICITLY CAPTURED** — not inferred as
  "none". So the "cached rows stay" half is observed; the "no message on Build 19" expectation is not evidenced by
  this run. C sent RESTORE NOW on receipt.
  **Row result pending:** A's restore and byte-for-byte ACL verify, whether the watchdog fired, D's after-read
  reproducing md5 466fd2d8…, and A's API-log check ≥10 min after the window (a denied GET /rest/v1/bids inside the
  window). Without that check the row is INCONCLUSIVE, not PASS. Line 3 stays paused until all of it is closed.
- **DV-ST2b restored (A, 2026-09-17T18:38:56Z) and verified clean; the watchdog did NOT fire** (A restored on C's word,
  2m33s into the 6-minute bound). Permissions are byte-for-byte back to the capture: authenticated
  select/insert/update/delete true, anon SELECT untouched throughout, 3 policies, RLS on. The revoke was in place
  18:36:23Z → 18:38:56Z.
  **A's second disclosure, same root cause as the watchdog failure:** the automatic verify step also failed to run
  (bare-name self-invocation). A ran it explicitly 11 s later and it passed. Both are recorded as one defect in A's
  script; it now has no bare self-invocations and refuses to hold a window whose automatic restore isn't confirmed
  running. Window bounds and evidence are unaffected.
  **Row still INCONCLUSIVE** until A's API-log check, no earlier than 18:48:56Z, finds a denied GET /rest/v1/bids
  inside 18:36:23Z–18:38:56Z; D's after-read must also reproduce md5 466fd2d8…. Then A re-verifies PC2/PC3 and the
  bids ACL before Line 3 resumes at step 0 (the picker-only rows on 3118bd30), which needs the owner's go through C.
- **DV-ST2b CLOSED (owner's ruling, 2026-09-17).** A's API-log check found **six denied bids requests inside the
  window**, and D's before/after permission reads match. **Narrow recorded result: on Build 19, the buyer's existing
  purchase rows stayed visible during a failed bids refresh.** Banner and error-message behaviour was NOT captured
  and is not claimed either way. The owner directs: do not repeat this test and do not wait for another log check.
  The window is fully closed (revoke 18:36:23Z → restore 18:38:56Z, verified; watchdog never fired; A's two
  tooling-failure disclosures recorded as one defect, since fixed).
- **Line 3 is next (owner, 2026-09-17).** Coordination: A re-verifies PC2/PC3 and the bids ACL after the window; D
  confirms its pre-check still matches; then C gives the first handset row. **C must wait for the owner's
  confirmation that they are available with the phone before any permanent write.** Setup first, which writes
  nothing: switch to the DV seller (this also gives the F-SELL-2 sign-in screen check), prepare synthetic ticket
  images with no real codes or personal information, and turn Camera location off before the DV-IMG-9 photo. This is
  the single next handset sequence.
- **Line 3 readiness confirmed by A (read-only re-verify 2026-09-17T20:17:58.915Z), identical to A's 18:30:38Z pre-check
  and to the 18:50:58Z read taken after the window:** PC1 identity PASS (sandbox markers, no ops schema, ledger 144);
  PC2 vault = project_url only; PC3 all seven function bodies unchanged (attach_transfer_evidence 67615b89/2690,
  enqueue_notification 1e11b92d/518, guard_transfer_state_columns c423ef62/1951, mark_transfer_sent(uuid,uuid,text)
  17453329/2560, mark_transfer_sent(uuid,uuid) d816c53e/86, notify_transfer_event 49146f9f/1361,
  notify_transfer_state_inbox 203f7c7d/3442); **bids ACL restored and unchanged** (authenticated and anon SELECT
  true); PC4 seven triggers enabled; PC5 five proof-docs policies, same qual md5s; PC6 bucket private, 10 MiB, six
  types; PC7 the five transfers unchanged; PC8 folder 0, rt 0; executors false; net queue 0, 2xx 0; buyer inbox 41.
  Nothing of A's runs against the sandbox; A relays that B reports local work only.
  **Gate restated by A and matching the owner's instruction to C: step 0 begins only when the owner confirms they are
  back and available with the phone — not on read-backs.** D takes no Line 3 witness read until then either. Order
  when it starts: step 0 (picker-only on 3118bd30, the one Mark as sent tap being the no-image case that must stop at
  "Evidence required" before any network call) → DV-IMG-4 on 92ee5156 → N1, N2 → DV-IMG-5 → DV-IMG-9 + 3b → N3 →
  DV-IMG-10 → N4 → RT6 → U1 → RT5-P → close. A releases each row only after D's witness read of the previous one.
- **Line 3 setup complete (owner, 2026-09-17 16:20 EDT):** signed in as the DV seller; **the sign-in screen heading
  clears the SANDBOX badge (F-SELL-2's last outstanding screen: PASS, owner-reported)**; Camera location set to Never;
  synthetic ticket images ready. The owner confirms they are with the phone and ready for Line 3 under the approved
  scope, and asked for the picker-only step first, then the permanent tests one at a time.
  C is waiting only on D's post-window confirmation, and has asked A for the listing event name and venue behind
  3118bd30, 92ee5156, bce07eef and 8f59d37e, the Send tickets entry point on Build 19, and the listing behind
  83b83858 so the owner can avoid it.
  **F-SELL-2 device status:** PASS on My listings, Settings, Settings › Notifications, listing top controls and the
  sign-in screen. UNTESTED: transfer send/receive (covered incidentally during Line 3 if the headers are observed),
  Place bid, Checkout, the outbid toast.
- **D's post-window re-check MATCHES (read-only, 18:5xZ; output md5 0c26b6d3…), identical to D's pre-check and to the
  approved post-W-C3 baseline** across the five transfers, dedupe 0/1/1/0/0, buyer inbox 41, the seven function
  bodies, the seven triggers, the empty evidence folder, executors false, net queue 0 / 2xx 0 and vault names. D's
  "owner away" note crossed with C's message: the owner confirmed presence at 16:20 EDT. **D asks to repeat this read
  immediately before the first PERMANENT row rather than relying on this one**, which C will request at that moment.
  D's DV-ST2b record: docs/venue-dashboard/DV_ST2B_WITNESS_RECORD_D_20260917.md, noting the buyer has no bids at all,
  so the list survived because purchases populate it.
- **Line 3 step 0 begins with DV-IMG-7 (Sell form parity), which needs no transfer and no mapping**, while A's
  listing-name mapping for 3118bd30 / 92ee5156 / bce07eef / 8f59d37e (and the listing behind 83b83858 to avoid) is
  outstanding. Build 19 Sell form: Photos section with "Cover image" and "Proof of ownership" pickers; a selected
  image shows Replace and Remove. Nothing is uploaded until the listing is published, and the owner will not publish.
- **Line 3 navigation map (A, read from Build 19 source + the sandbox, read-only):**
  - 3118bd30 (pending; step 0 + DV-IMG-9/3b) → listing 086dd027 **"Device D1"**, venue "Club Device".
  - 92ee5156 (pending; DV-IMG-4) → 96799125 **"Device D6"**, "Club Device".
  - bce07eef (pending; DV-IMG-5) → 9c6eecd4 **"Device D2"**, "Club Device".
  - 8f59d37e (seller_sent, no proof; DV-IMG-10) → 92f8effe **"Sandbox S8only"**, venue "Club".
  - **AVOID: 83b83858 → c0dd0706 "Sandbox L7"**, venue "Club" — the same venue label as S8only, so the EVENT NAME is
    the only separator. The owner reads the event name before every tap in that pair.
  - **Entry points:** pending transfers → My listings → the **"Send tickets"** tab → tap the CARD BODY (routes to
    `/transfer/send/<transferId>`); the pencil is Edit (the F-NAV-1 screen) and there is also a delete action, neither
    part of Line 3.
  - **Trap, recorded as a device-row detail:** DV-IMG-10 is NOT reachable from "Send tickets", because
    `needsTicketSend` requires the transfer to be pending, and 8f59d37e is already seller_sent. Route that works:
    My listings → Sold (or All) → "Sandbox S8only" → the listing detail's primary button reads **"View transfer"** →
    `/transfer/send/8f59d37e`, where the Add proof section renders (seller_sent with no path).
  - **A's caution:** DV-IMG-7 on the Sell form is picker-only with nothing submitted; creating or saving a listing is
    a write outside Line 3's scope (which covers the four named transfers and their objects only). C's step 0a
    instruction already forbids publishing.
  - Both prerequisites satisfied: A's re-verify (20:17:58Z) and D's fresh read (20:22:33Z, md5 9113aeb2…) match their
    baselines. A takes a read-back after step 0; D reads after step 0 and after every permanent row; A releases each
    row only after D's read lands, with a fresh D read immediately before DV-IMG-4 if a gap opens.
- **Line 3 step 0a, Sell form picker parity (DV-IMG-7; owner-reported, DV seller, Build 19; time and exit-prompt
  wording not captured): PASS, no writes.** Cover image opened and cancelled normally; three quick taps opened only
  ONE picker with nothing stuck; synthetic "blue 01" previewed, Replace swapped it to "orange 02", Remove cleared it;
  Proof of ownership previewed synthetic "purple 03". The owner left without publishing and never tapped List ticket,
  so no listing was created. A's read-back and D's post-step read requested; D's must match its 20:22:33Z read.
- **D's step 0a read (20:30:02Z, md5 77841c46…): NOTHING WAS WRITTEN** — every non-timestamp line identical to D's
  20:22:33Z read: five transfers by row md5, dedupe 0/1/1/0/0, inbox 41, seven bodies and seven triggers, evidence
  folder 0 and rt 0 with no referenced paths (so the picker work created no object), executors false, net queue 0,
  2xx 0, vault project_url only, and no listing row. D's notes, recorded: step 0a's missing time stays "not captured"
  and is bounded by the read (before 20:30:02Z, database identical to 20:22:33Z); and D's read proves only the
  database state, not what the owner saw on screen — the picker behaviour is the owner's and C's evidence.
  Step 0b waits for A's read-back.
- **A's step 0a read-back (20:30:22.970Z): step 0a wrote nothing.** Listings 49, none created since 18:00Z (nothing
  published); no object created in any bucket since 18:00Z and proof-docs still 0; the five tracked transfers
  unchanged by row md5 (all 33 hash b2547604…); executors false; vault project_url only; net queue 0; 2xx 0;
  notify.notification 9, delivery 18, buyer inbox 41.
  **One new row, identified and NOT ours:** public.notifications went 104 → 105. The extra row 9c2ea626 is to the
  SELLER, type `transfer_viewed` ("Buyer viewed your transfer"), for transfer 9869cb08 — a disputed transfer on
  "Sandbox L6", not one of the five tracked — created 18:32:31.953Z, while the owner was preloading Bids as the buyer,
  four minutes before the DV-ST2b window. It is the owner's own buyer-side viewing, not step 0a and not any session.
  **Accounting change A is applying: the closing equation keys on the tracked dedupe keys, never on gross
  notification totals**, since the seller's inbox moves with ordinary buyer-side viewing; the three existing
  `transfer_viewed` rows for tracked transfers are baseline.
  **Owner note (not blocking):** while signed in as the seller this cannot recur, but if they switch to the buyer and
  open any purchase, each first view writes another `transfer_viewed` row to the seller; C tells A at once if it
  happens mid-sequence.
  Step 0b is clear: DV-IMG-1, -2, -3a, -6 on 3118bd30 / "Device D1"; nothing on "Sandbox L7".
- **Line 3 step 0b BLOCKED on 3118bd30 / "Device D1" (owner-reported + owner screenshot, Build 19, 2026-09-17 16:34
  EDT).** The Send tickets screen shows "Transfer window expired"; Buyer "Unknown"; "Buyer must provide delivery info
  before you can send tickets."; **Mark as sent disabled**; the synthetic "orange 02" selected with its preview
  visible. The owner stopped and asked that nothing be bypassed.
  - **Source (Build 19):** the disable is `busy || refreshing || buyerDeliveryMissing`, and `sellerDeliveryMissing` is
    `!delivery_email && !delivery_phone`, so the blocker is the missing delivery info. The expiry line is display
    only and disables nothing. "Buyer: Unknown" comes from `transfer.buyer?.display_name || 'Unknown'` via the embed
    `buyer:profiles!buyer_id(display_name)`; the buyer's own Profile showed "sandbox-buyer", so either that
    display_name is null or the seller's embed is filtered by RLS — A to read which. (The "no separate queries for
    profile embeds" ruling stands; this is only a finding if the embed is filtered.)
  - **NOT recorded as passed:** DV-IMG-3a's no-image "Evidence required" check never ran. The picker observations are
    recorded separately.
  - **A asked (read-only) for all four transfers:** delivery_email/phone, expires_at and whether passed,
    transfer_method, and the buyer display_name as the seller's embed sees it; then to separate missing TEST DATA from
    app defects. **Any corrective write — the buyer supplying delivery info in the app, a DB write of delivery
    fields, or extending expires_at — is outside the approved Line 3 scope; A sends options, executes nothing, and the
    owner decides.**
- **A's read-only prerequisite answers (2026-09-17):** `delivery_email` and `delivery_phone` are NULL on all four
  transfers and on **all 33 transfers (0 with delivery info)** — so the block is MISSING TEST DATA, and the client's
  disable is the product rule working. `expires_at` is past on all four (3118bd30 09-12T01:05Z, 92ee5156
  09-12T01:19Z, bce07eef 09-11T20:58Z, 8f59d37e 09-09T01:20Z) but **neither the client gate nor
  `mark_transfer_sent` / `attach_transfer_evidence` reads it**, so extending it would change nothing.
  `transfer_method` is mobile_transfer on all four. `profiles.display_name` is NULL for both DV accounts and
  `authenticated` holds column SELECT, so **"Buyer: Unknown" is the app's null fallback, not RLS**.
- **Minor consistency finding (C, source-confirmed, not a defect):** Profile renders
  `profile?.display_name ?? user?.email?.split('@')[0] ?? 'User'`, so the owner saw "sandbox-buyer" from their email,
  while the Send screen has only the embedded `display_name` and falls back to "Unknown". Two surfaces, two
  fallbacks. For the owner's scope list.
- **OWNER DECISION (2026-09-17): fix the fixtures FIRST and then run Line 3 in the originally approved order** (so
  A's Option 4, running the attach subset first, is declined as a reordering), **and take Option 2: A writes the two
  delivery fields directly** on 3118bd30, 92ee5156 and bce07eef (Option 1, the owner entering them as the buyer, is
  declined; Option 3, extending expiry, is declined as pointless).
  This is a NEW authorization outside the approved Line 3 scope. It reached A through C, so A must get the owner's
  line in A's own session. C asked A to send the exact statement first — rows, columns, proposed synthetic values
  (C prefers one column, `delivery_email` = the DV buyer's sandbox email), what it does not touch, pre/post reads by
  A and D, and stop conditions — so the owner's line can be precise. **Nothing runs until then.** The no-image
  "Evidence required" check stays NOT PASSED.
## Owner's testing direction for the rest of the sprint (2026-09-17)
Most of the app is already tested; close the remaining gaps efficiently.
- Before proposing a test, check the device records and name the specific change or unresolved behaviour it covers.
- **Reuse prior evidence when the relevant code and conditions are unchanged**; never repeat a whole flow to verify one
  changed part.
- Line 3: use the approved direct delivery fixture update (no buyer data entry); **check ALL remaining transfers for
  blockers together before the owner taps**; preserve completed picker results and run only what remains; **combine
  compatible observations into one handset pass**; keep the necessary server verification but coordinate it without
  asking the owner repeatedly for the same readiness or approval.
- Results stay precise: PASSED / FAILED / BLOCKED / UNTESTED. A missing detail becomes neither a pass nor an automatic
  demand to repeat: first decide whether it matters to release readiness.
- Roles: C is the sole handset guide; A coordinates execution and records; D verifies independently; B continues the
  frontend audit. **Only genuinely new scope decisions go to the owner, with one consolidated recommendation.**
- **C's application to the open rows:** DV-IMG-1 and DV-IMG-3's picker behaviour are already evidenced on the Sell
  form (step 0a) through the SAME components (`MediaUpload` + `useImageUpload`), so they are not re-run on the
  transfer screen; what remains there is what differs — the permission rows (DV-IMG-2, run once), leave-and-return
  (DV-IMG-6), the no-image gate (DV-IMG-3a) and the submitting rows (DV-IMG-4, -5, -9+3b, -10).
- **Delivery fixture write DONE (A, 2026-09-17T20:44:31Z), under the owner's own line to A.** `update public.transfers
  set delivery_email = <DV buyer's sandbox email> where id in (3118bd30, 92ee5156, bce07eef) and status='pending' and
  delivery_email is null and delivery_phone is null`, in a transaction raising unless exactly 3 rows changed.
  `delivery_phone` left NULL. A diffed each row's full JSON in the same transaction: **changed keys = delivery_email on
  the three; "(none)" on 8f59d37e and 83b83858.** No status, expiry, payment state or evidence path. No side effects
  (notifications 105, inbox 41, queue 0, 2xx 0); the state-column guard protects status/expiry/payout, not delivery;
  `notify-transfer` isn't deployed and the trigger can't call out without the Vault service key.
- **Consolidated blocker sweep: ALL FOUR CLEAR (A).** 92ee5156 "Device D6" pending, delivery SET; bce07eef "Device D2"
  pending, SET; 3118bd30 "Device D1" pending, SET; 8f59d37e "Sandbox S8only" seller_sent, delivery NULL but it does not
  matter — the Add proof button is `disabled={busy || refreshing}` and the delivery warning gates only the Send
  section. Storage INSERT policy requires the object under the seller's own uid folder (what the client builds); party
  read requires the object to be referenced, which is what makes RT6 work and U1/RT5-P deny. Bucket private, 10 MiB,
  allows jpeg/png/webp/heic/heif/pdf, so DV-IMG-9 passes either way. The append-only guard is harmless with NULL paths.
  Expiry gates nothing.
- **Probe sequencing (A, with one stated deviation):** N3 runs BEFORE the pass (it must precede DV-IMG-10, since
  attaching proof changes the precondition); N1, N2 and N4 run AFTER the pass in one batch, which deviates from the
  approved interleaving so the owner taps continuously — recorded as a deliberate deviation, with the reason, not as
  the approved order. RT6, U1 and RT5-P follow once all four objects exist.
- **Reuse recorded as C's judgement:** DV-IMG-1 and DV-IMG-3's replace/remove half are **PASSED on step 0a's evidence**
  (same components), not re-tested on the transfer screen. DV-IMG-3a's no-image gate stays **UNTESTED** until the pass.
- **Owner's three tightenings for the combined pass (2026-09-17), applied:**
  1. Offline test: the owner confirms **Wi-Fi off as well as Airplane Mode on**, so the failure is a real network failure.
  2. **HEIC:** a camera photo alone does not establish HEIC coverage. The owner reports the iPhone's Camera › Formats
     setting ("High Efficiency" = HEIC, "Most Compatible" = JPEG), and **A verifies the STORED object's actual format
     from its bytes** (magic bytes, extension, Content-Type, size, sha256) and states whether the row proves
     HEIC→JPEG conversion, a JPEG that was never HEIC, or a stored HEIC. If the device never produced HEIC,
     DV-IMG-9's conversion half is **UNTESTED**, not passed.
  3. **Stop conditions are phone-observable**, replacing "success before the server confirms": a success message while
     Airplane Mode is on; two success messages for one transfer; the transfer showing as sent without the button ever
     showing its spinner; the no-image tap showing a spinner or delay instead of an instant alert; landing on
     "Sandbox L7". **A verifies server-side timing afterwards** (each success followed a confirmed verb call; no
     transfer took two calls).
  Order preserved; A's post-checks batched. Shared picker coverage is REUSED EVIDENCE from step 0a, not a new
  transfer-screen pass; DV-IMG-3a stays UNTESTED until performed.
- **Sent to B for the frontend audit (owner's instruction):** the expired-window warning that gates nothing
  (display-only at send/[id].tsx:309 beside a button disabled for a different reason) and the inconsistent "Unknown"
  buyer label (the Send screen's embed fallback versus Profile's email fallback at profile.tsx:229).
- **N3 PASS (A, 2026-09-17T20:50:53Z), seller JWT over the API:** `mark_transfer_sent(8f59d37e, <seller>, <a path that
  does not exist>)` → **HTTP 400, P0001, exactly `precondition_failed: transfer already sent without evidence — use
  attach_transfer_evidence`**. Row identical before and after (md5 c74e9fd0…, still seller_sent, no path,
  seller_sent_at unchanged); notifications 105 → 105. **A's disclosure:** a first attempt used the wrong parameter
  names and PostgREST answered 404 PGRST202, so nothing ran; A read the live signature and re-ran. Both attempts are
  logged — useful for anyone scripting these verbs.
- **HEIC decision rule, fixed BEFORE the row (A):** stored `ftypheic/heix/mif1` + .heic + image/heic → a stored HEIC,
  conversion half **UNTESTED** (but the bucket accepting HEIC is worth having); `ffd8ff` + .jpg + image/jpeg **with
  Camera › Formats = High Efficiency** → **HEIC→JPEG conversion PROVED**; `ffd8ff` with **Most Compatible** → a JPEG
  that was never HEIC, conversion half **UNTESTED**; **no Formats setting reported → UNTESTED, never inferred**. The
  setting must be captured before the row; it is unrecoverable from the bytes afterwards.
- **What A can and cannot prove after the pass:** CAN prove exactly one pending → seller_sent transition per transfer
  (`seller_sent_at` set once, append-only guard), exactly one object per transfer, the path set once and never
  replaced, and `buyer_confirmation_needed:<id>` at 1. **CANNOT prove how many client calls were made** — the verb is
  idempotent, so a retry answers `already_sent` and writes nothing; counting calls needs an API-log read, which
  **Line 3's approved scope excludes**. So "no transfer took two calls" is recorded as **NOT ESTABLISHED** unless the
  owner authorizes that read, which is not being asked for now. If the double-success stop condition fires on the
  phone, it becomes a real question and goes to the owner once, with everything else.
- **Owner narrows the pass (2026-09-17).** Clarification: the transfer flow worked in EARLIER app versions; the remark
  is not a statement about today's state, and **A confirms current transfer states from the planned pre-checks, never
  from that comment**. Scope: only the proof-repair changes and their direct regression risks — upload failure and
  retry, duplicate submission, selecting the correct replacement image, HEIC handling and buyer display, and attaching
  proof after marking sent. Generic navigation and permission checks are dropped unless tied to a code change or an
  unresolved release requirement. Transfer assignments and approved writes unchanged.
  **Shortened sequence (C), approved transfer order kept:** DV-IMG-4 on D6 (offline then retry) → DV-IMG-5 on D2
  (double tap) → D1: permission-denied alert with Open Settings, selection preserved across leaving the screen, then
  screenshot → Replace with the camera photo → Mark as sent (DV-IMG-9 + 3b) → DV-IMG-10 on S8only → buyer display:
  the owner switches to the buyer and confirms the stored proof renders on the receive screen (expect one
  `transfer_viewed` row per transfer opened; C tells A which).
  **Kept, with C's justification:** the Open Settings denial path and selection preservation are NEW code from the
  F-IMG-1 repair (`useImageUpload`'s final-denial Alert with `Linking.openSettings()`;
  `rememberSelection`/`recallSelection`/`selectionToRecall`) and are explicit items on the owner's own acceptance list.
  **Dropped:** the limited-access row (no changed code behind it) and **DV-IMG-3a's no-image gate** — that early
  return pre-dates the repair and is unchanged, so it stays **UNTESTED** with that reason, not called a pass.
- **B's frontend design audit delivered (read-only): `design/frontend-audit-20260917 @ 79a7b6b`,
  `docs/design-audit/FRONTEND_DESIGN_AUDIT_20260917.md` + two HTML prototypes.** It reads 6561d1f (which INCLUDES
  F-BIDS-1), while the handset runs f412d10 (which does not) — B labels each Bids finding with its tree. C's two
  device findings appear in §5b attributed to C and the owner, and B derived the expiry finding independently from
  source. B's §10 protects C's F-SELL-2 insets, the 20 pt badge, MAX_DISPLAY_FONT_SCALE, the line-height floor,
  loadState copy, F-BIDS-1's states, the haptics and AdaptiveDock; B proposes nothing visual for My Listings while
  ML-1 is open.
  **Six release-critical items B hands to C's lane, no patches proposed:** (1) PlaceBidScreen builds its form on a
  `?? 0` floor after a failed read, and a thrown read leaves the spinner up; (2) CheckoutNative has no offline state,
  so a dead connection reads as a decline at payment time; (3) Send Transfer layout, the action far below the fold and
  the blocker stated three times; (4) Unblock, delete listing and cancel listing have no busy state and re-fire on
  repeat taps; (5) Home's lazy filter fetches show EmptyState while in flight and log errors to console, so a failed
  filter reads as an empty marketplace; (6) the avatar spinner clears before the profile write completes. Smaller:
  synthetic-bold layering on the notice banner, ProofImageViewer's raw Modal/ActivityIndicator with no Reduce Motion
  path, and no shared display-name resolver.
  **C's handling, per the owner's direction:** the handset pass first; then C verifies each finding in source before
  it reaches the owner; then ONE consolidated recommendation with severity, what each fix touches and what device
  evidence it needs. Nothing is written without the owner's scope decision.
- **B's negative-control notes for its release-weight items (kept for if/when the owner authorizes the work):**
  - **Place bid is two defects with two controls.** Resolved-with-error: mock `{data: null, error}` and assert the
    screen renders NO bid amount at all; asserting "the minimum is not 0" passes vacuously as soon as MIN_INCREMENT is
    added to zero. The control must fail by showing a figure DERIVED from zero, not by showing 0. Rejected promise:
    mock a throw and assert loading resolves, with an explicit assertion rather than leaning on the runner's timeout,
    since the current code's failure mode is a spinner that never clears.
  - **Checkout offline:** the discriminating fixture is a network failure that is NOT a Stripe decline; a generic
    failure passes either way. Assert the copy DIFFERS by cause, and confirm that assertion fails on the current tree,
    where both land on SAFE_PAYMENT_ERROR.
  - **Repeat-fire actions:** assert the second tap produces NO SECOND REQUEST, not merely that the button is disabled;
    disabled-in-render and guarded-in-handler fail differently under a fast double tap.
  These match C's mutation discipline and will be used if the owner authorizes any of it. B will not touch a screen
  the handset pass is on, and asks to be given the item and constraints rather than guessing scope.
- **A's boundary read before the pass (2026-09-17T20:55:11.785Z), from A's own query, not from the owner's remark:**
  92ee5156 "Device D6" pending, delivery set, no evidence (md5 198c9918…); bce07eef "Device D2" pending, set, none
  (4116ee1a…); 3118bd30 "Device D1" pending, set, none (17a9dddb…); 8f59d37e "Sandbox S8only" seller_sent, delivery
  NULL (irrelevant to Add proof), none (c74e9fd0…); 83b83858 "Sandbox L7" untouched, seller_sent, none (d1b36045…).
  Three transfers carry delivery info and **0 remain eligible for the fixture, so it cannot fire twice**;
  notifications 105; queue 0; 2xx 0.
- **Step 5's expected write, agreed in advance:** when the owner switches to the buyer and opens the D1 transfer, that
  writes a `transfer_viewed` notification to the seller. It is recorded now as an EXPECTED and ACCEPTED consequence of
  a step the owner put in scope ("HEIC handling and buyer display"), so it won't read as an unexplained increment.
  C tells A exactly which transfers the owner opens; **a `transfer_viewed` for a transfer they did NOT open remains a
  stop condition.**
- **A's per-row boundary reads:** the row's full state and md5, the object's name and metadata (size, mimetype, eTag),
  the `buyer_confirmation_needed:<id>` dedupe count, notifications, queue and 2xx. For DV-IMG-9, A additionally pulls
  the stored bytes and applies the fixed decision rule — and needs the owner's **Camera › Formats** setting BEFORE
  that row, or the conversion half is UNTESTED by rule.
  A has nothing pending: N3 done, fixture written, boundary read taken. **Only D's post-read is outstanding.**
- **Owner's refinements (2026-09-17), applied:**
  - **"Spinner not seen" is REMOVED as a stop condition.** A fast operation can finish before the owner notices, so it
    is recorded as an observation and the server evidence establishes the result. Remaining stop conditions: a success
    message while Airplane Mode is on; two success messages for one transfer; landing on "Sandbox L7".
  - **After the handset pass:** C validates B's findings and gives A and the owner **one ranked implementation batch**,
    separating CONFIRMED DEFECTS from DESIGN PROPOSALS and saying which genuinely block release.
  - **Checkout framing required by the owner:** distinguish (a) offline BEFORE the request, (b) a confirmed decline,
    and (c) an UNKNOWN outcome after a lost response — and never imply a retry is safe without reconciling payment
    state. (c) is the dangerous one: the charge may have succeeded.
  - **Preserve:** existing accessibility scaling and completed test evidence. **No global text-size caps, no broad
    redesign, no repeated full handset flows.** Verification focuses on changed behaviour.
- **D's post-fixture read landed and PASSES (md5 5cbd7dbc…):** diffed against D's pre-fixture read, **exactly three
  lines differ — the three pending rows**; 8f59d37e and 83b83858 byte-identical; inbox 41; folder 0/0; executors false;
  queue 0; 2xx 0; the seven bodies and seven triggers unchanged. D independently confirmed the blast radius, that the
  state-column guard doesn't name the delivery fields, and that the Vault has no service key. **C gave the owner GO.**
- **F-CHK-1 (B's checkout finding) — A's correction, to be verified by C before it reaches the owner.** A reports the
  file is identical in both trees and that CheckoutNative already implements the three-way distinction: a sheet error
  is not proof of failure (`reconcileAfterSheetError()` at :513, A-04); the helper returns **verified** → settle,
  **not_verified** → failure line, **unreachable** → `setPaymentReady(false)` so Pay is WITHDRAWN, with the copy "We
  couldn't confirm your payment yet — Your last attempt may or may not have gone through. Please don't pay again.
  We'll keep checking; you can also check now." plus a Check status button (:851-858). `revalidateAgainstServer()` is
  settled-first; the copy layer separates transport from decline; `payments.ts` routes network/timeout to the pending
  path rather than a failure claim. **A reclassifies F-CHK-1 as not release-critical rather than leaving a false
  blocker in front of the owner.** What may remain, narrower and C's to confirm: whether anything guards the
  PRE-REQUEST case (starting checkout with no connectivity) and whether the initial screen fetches show content-free
  states while in flight. Any test here must drive a network failure that is NOT a Stripe decline; a generic-failure
  test passes on the current tree and proves nothing.
- **D's independent blocker survey (all five transfers): NOTHING BLOCKS THE PASS.** D1, D6 and D2 are pending, each
  carrying its own buyer's delivery email and no phone, so the client's gate is satisfied with no buyer typing; no
  evidence attached, not disputed, not released. S8only is seller_sent since 2026-09-08 with no proof, reachable only
  via the listing detail's "View transfer". "Sandbox L7" is out of scope and sits beside S8only under the same venue
  name, so **the event name is the only on-screen discriminator**.
  **Run-sheet note from D:** both seller_sent rows are 6.8 days past auto-release, and the release job runs every 2
  minutes but fails 401 because this project has no service key — so **nothing moves on its own during the pass,
  provided no service key or push key is added while Line 3 is open.** D has sent A the same with evidence, and D's
  witness of step 0a stands (it wrote nothing; nothing to repeat).
- **B's "calm pass" draft (artifacts only): `design/frontend-audit-20260917 @ 457f8fe`,
  `docs/design-audit/CALM_VISUAL_DIRECTION_20260917.md` + `prototypes/calm-pass.html`** (Home, Send Transfer, Checkout
  at normal and largest text). No product code, no tests, nothing on C's branches; Send Transfer's re-order is parked
  until the handset pass is off that screen.
  **Touching C's surfaces if approved:** `ui/StateView.tsx`, `ui/Sheet.tsx`, `ui/EmptyState.tsx` (in-content titles
  move from Oswald caps to Inter 600 sentence case, copy verbatim); `ui/Chip.tsx` and `ui/Badge.tsx` (selection and
  count stop using brand red); `ui/Button.tsx` (secondary's border red-tinted → white 20%, primary unchanged); a new
  `ui/Notice.tsx` with three ranks absorbing the hand-rolled warning boxes on the transfer screens, settings index and
  the create-listing risk banner. One new type token `eyebrow` replacing `micro` caps as section labels.
  **Owner's decision, not B's or C's:** whether `border.default` stops being red-tinted (rgba(255,26,26,0.15) → white
  10%, red kept for selection/focus) — one token, whole-app effect.
  **Named as preserved:** `loadState.ts` copy verbatim, F-SELL-2's `useTopInset()`, the 20 pt badge,
  MAX_DISPLAY_FONT_SCALE, the 1.25 line-height floor, `useReducedMotion()` and its nine sites, AdaptiveDock's
  geometry, the four haptic meanings, F-BIDS-1's Bids states. Motion limited to four transitions on existing
  `v2.motion` tokens, all collapsing through `useReducedMotion()`.
  **Overlap C must manage:** these primitives are the same ones ML-1 proposes to calm on My Listings, so if the owner
  approves both, one of them owns the shared components. C raises that when the ML-1 decision returns.
- **F-CHK-1 WITHDRAWN by B**, which verified A's disproof: the reachable / not_verified / unreachable path is
  implemented, Pay is withdrawn when the server can't be reached, and the copy already says the attempt may or may not
  have gone through and not to pay again. **C does not build a batch on B's original framing.** What survives is a
  setup-path copy gap, polish-level, routed through A. C still owns verifying the narrower pre-request question.

## PRIVACY INCIDENT — Line 3 STOPPED (owner, 2026-09-17)
**Owner's declaration:** "Stop Line 3. I completed the visible steps, but the selected/uploaded images may include real
personal photos rather than only synthetic ticket images… Have A identify exactly which files were stored, their
transfer IDs, timestamps, metadata and access records; have D independently verify. Quarantine this Line 3 result and
determine the safest authorized handling for any real personal images before continuing." The owner also instructed:
do not ask them to upload anything else, delete or overwrite proof, or open another transfer.
**C's observation from the owner's screenshots (evidence, attributed to the owner):** the D6 proof thumbnail is a
photograph of a person's face; the buyer's view of the D1 transfer renders a photograph of a car in a car park with a
number plate visible; the S8only thumbnail is a room interior. These are personal photographs, not synthetic tickets.
**Owner-reported screen outcomes (17:08–17:13 EDT):** D6 "Couldn't upload the transfer proof / You're offline. Check
your internet connection and try again." with the selection kept and a TRY AGAIN control; D2 "Marked as sent / You've
marked this transfer as sent. The buyer still needs to confirm they received the tickets."; D1 the same dialog;
S8only the Add proof section with an image selected ("Image added"); the buyer's Receive transfer screen showing the
seller's proof for D1.
**A's state read (21:13:59–21:15Z), no boundary reported to A, D witnessed neither row:**
- bce07eef "Device D2" marked sent 21:09:22Z, evidence `…/transfer-evidence/1789679356721.png`, 210,364 bytes,
  image/png, object created 21:09:21Z, one `buyer_confirmation_needed` at 21:09:22Z, row md5 57c2d304….
- 3118bd30 "Device D1" marked sent 21:11:36Z, evidence `…/transfer-evidence/1789679485922.jpg`, **5,829,677 bytes**,
  image/jpeg, object created 21:11:36Z, one notification, row md5 89080d2c….
- 92ee5156 "Device D6" still pending and untouched, so DV-IMG-4 never completed; 8f59d37e unchanged (no evidence);
  83b83858 unchanged (md5 d1b36045…). Folder: 2 objects, both referenced, no orphans; 2xx 0 of 191; executors false.
**Process deviations recorded plainly:** the approved order was D6 → D2 → D1; what ran was D2 → D1 with D6 pending. No
row boundary reached A and D witnessed neither row, so the state BETWEEN the two rows is unreconstructable. Neither is
a reason to re-run: the writes are permanent and the data is consistent.
**C's immediate holds:** A was about to download both objects to verify bytes — C stopped that, since byte
verification (sha256, EXIF, magic bytes) requires reading content that is likely photographs of a person and of
identifiable property. A asked to report what, if anything, it already fetched and to delete local copies. RT6, U1,
RT5-P, N1, N2, N4 and every further handset row are HELD. Nothing is deleted, overwritten or moved by anyone.
**Asked of A and D (read-only, no bytes):** object paths, owning uid folder, size, mimetype, eTag, created_at, the
referencing transfer, the transfers' exact `transfer_evidence_path` values, **access records** for those objects (the
owner's instruction authorizes that log read for this purpose), and who could read them under current policy.
**Standing constraint that shapes the options:** `transfer_evidence_path` is append-only, and deleting or overwriting
attached proof was explicitly excluded from the approved scope. Any handling option therefore needs a NEW owner
authorization, and C will bring ONE consolidated recommendation once A and D report.
- **A's metadata-and-access report (no bytes read; A confirms it downloaded nothing, and has never fetched a Line 3
  object):**
  - **Exactly two objects exist**, both in the seller's own folder: `2f5844b4…/transfer-evidence/1789679356721.png`
    (210,364 B, image/png, eTag 2e8bb290…, created 21:09:21.894Z) referenced by **bce07eef (D2)**; and
    `…/1789679485922.jpg` (5,829,677 B, image/jpeg, eTag 9fd322bc…, created 21:11:36.269Z) referenced by
    **3118bd30 (D1)**. Referenced 2, orphans 0, nothing created in any other bucket since 20:55Z.
  - **Two of the three photographs the owner saw were never stored.** The FACE was the D6 thumbnail: D6 is still
    pending with a NULL path and no object — the offline attempt failed before upload, so that image never left the
    phone. The CHAIR was S8only: selected but never attached, no object. **Stored exposure is one confirmed personal
    photograph (the D1 JPEG) and one image of unknown content (the D2 PNG).**
  - **Access records:** the D2 PNG — one seller upload (21:09:21.587Z, 200) and **no read of any kind, ever**. The D1
    JPEG — one seller upload (21:11:35.628Z, 200), then the BUYER minted a signed URL at 21:13:40.493Z and it was
    fetched three times (21:13:40.697Z, 21:14:33.950Z, 21:14:40.320Z), all 200, all `SnatchIt/19` from the same
    device: the owner's own buyer-side view. **No other identity ever accessed either object** — no service_role, no
    U2, no anonymous, nothing from A's or D's sessions.
  - **Who could read them:** only the two `authenticated` policies — owner-folder read (the seller) and transfer-party
    read (buyer or seller). **Both accounts are the owner's own.** No operator or admin read policy exists here.
  - **One time-limited residual:** `receive/[id].tsx:105` mints a ONE-HOUR signed URL, so a bearer link to the D1
    JPEG exists until ~22:13:40Z (18:13 EDT). Unguessable, only ever used by the owner's own device, and it lapses on
    its own.
  - **Completion from state:** D2 and D1 completed (each seller_sent + one object + one `buyer_confirmation_needed`);
    **D6 did NOT complete**; **S8only did NOT complete**; 83b83858 unchanged; 2xx 0 of 191 — nothing outbound.
  - A argues no content read is needed for the owner's decision, and the eTags already distinguish the files. C agrees.
- **C's source check for the options:** if a stored object is deleted, the buyer's receive screen degrades cleanly —
  `createSignedUrl` on a missing path yields no URL, `proofUrl` stays null and the proof section is simply not
  rendered. The seller's send screen keeps its Add-proof section hidden, since the path is still set.
- **OWNER AUTHORIZATION for the privacy cleanup (direct to C, 2026-09-17):** "After D confirms A's metadata and access
  findings, I authorize deleting exactly the two stored proof objects for Device D1 and Device D2, using their exact
  recorded paths and sizes. Leave all transfer references, statuses, payment state, notices, logs and Sandbox L7
  unchanged. A and D must perform matching pre- and post-checks, and nobody may open, download, overwrite or clear the
  files' contents or database references."
  Relayed to A and D with the sequence: **D's confirmation of A's findings → matching pre-checks → A deletes exactly
  those two objects (keyed on path and size, eTag where possible) → matching post-checks.** Scope held narrow:
  `transfer_evidence_path` on bce07eef and 3118bd30 is NOT touched, so the append-only guard stays untested and the
  references remain; no status, payment, notice, notification or log changes; L7 untouched; **no opening, downloading,
  hashing or EXIF at any point, including as delete "verification"** — existence, path, size and eTag are the
  comparison. Stop with no write if the pre-check finds anything other than those two objects at those paths and
  sizes. Expected post-state: proof-docs 0 objects; both transfers still seller_sent with paths intact; no orphans;
  notifications, queue and 2xx unchanged. C confirmed from source that the buyer's screen degrades cleanly afterwards
  (no signed URL → `proofUrl` null → the proof section is not rendered). A and D may each ask the owner for the line in
  their own sessions; the owner is expecting that.
- **DV-IMG-9 (HEIC → JPEG conversion): UNTESTED on this device, by A's pre-fixed decision rule.** The owner reports
  **Camera › Formats = "Most Compatible"**, so the iPhone produced a JPEG in the first place; the stored D1 object is
  `image/jpeg` with a `.jpg` name (5,829,677 B). Under the rule written before the row, a JPEG from a "Most
  Compatible" phone is **a file that was never HEIC**, so the conversion half is UNTESTED, not passed — and the bytes
  could not settle it afterwards even if anyone were allowed to read them.
  **What the row DOES evidence, from metadata only:** a camera photograph went through the repaired picker and upload
  path, and the stored object's type and extension match what the client's byte-sniff decided (`image/jpeg` / `.jpg`),
  which is the sniff-over-filename behaviour the F-IMG-1 repair introduced.
  **To test the conversion half later** the device must be set to "High Efficiency" before the photo is taken, on a
  transfer with a synthetic image, and it needs a fresh owner authorization since Line 3 is stopped.
- **The authorized deletion cannot be executed by A, and C verified why in the repo.**
  `supabase/migrations/049_proof_docs_owner_delete_unreferenced.sql:37-52` — policy "proof-docs owner delete
  unreferenced" (DELETE, `authenticated`) requires the object to be in proof-docs, in the caller's own uid folder,
  **AND not referenced by any `listings.proof_of_ownership_path` AND not referenced by any
  `transfers.transfer_evidence_path`.** Both objects ARE referenced, and the owner's instruction is that the
  references stay, so the seller-JWT path — the only client path — is refused by design. The policy is doing exactly
  what it exists to do.
  **A's three alternatives, with C's agreement on the ranking:**
  1. **service_role via the storage API** — needs a service key in this project's Vault, the deferral held all sprint.
     D's hazard makes the cost concrete: `enforce-transfer-expiry` runs every 2 minutes and fails only for want of that
     key, with two transfers already 6.8 days past `auto_release_at`, one of them **Sandbox L7**. Adding the key to
     delete two files would arm an automatic payout release on rows nobody may touch, within two minutes. **Advise
     against.**
     **→ WRONG PREMISE in the OPTION, not in D's hazard — corrected below ("A's correction to option 1"). A storage
     delete does not need a Vault key: the API takes one as a request header, which arms nothing. D's hazard itself
     stands — a key placed in this project's Vault DOES arm the cron. Carry the Vault-scoped rule, not the option.**
  2. **postgres deleting the `storage.objects` row** — removes the row but **leaves the bytes in the storage
     backend**, so the owner would be told the photograph is gone when it is not. **A refuses; C agrees nobody does
     this.**
  3. **The owner deletes both objects in the Supabase Storage dashboard** — removes row and bytes, needs no key in
     the Vault, arms nothing, touches no reference. **A's and C's recommendation.**
  A and D then do the matching pre- and post-checks the owner specified: existence, path, size and eTag only, never
  content. Everything else unchanged: references, statuses, payment state, notices, logs, Sandbox L7, and the
  append-only guard left untested.
  **Visible consequence to state in advance:** after deletion the buyer's receive screen renders no proof section
  (no signed URL → `proofUrl` null), which is a change the owner should not meet by surprise.
  **The one-hour signed link** minted for the D1 image at 21:13:40Z lapses by itself at ~22:13:40Z; deleting the
  object kills it immediately.
- **D's independent verification (21:23Z, metadata only — no bytes, no download, no hash, no EXIF) MATCHES A's report.**
  - The same two objects, both owned by the seller: the 210,364 B PNG (created 21:09:21.894868Z, referenced by D2) and
    the 5,829,677 B JPEG (21:11:36.269845Z, referenced by D1), with the stored eTags 2e8bb290… and 9fd322bc… — stored
    by storage at upload, not computed by D. Orphans 0; nothing created anywhere else since 20:00Z.
  - Transfers: D2 seller_sent 21:09:22Z and D1 seller_sent 21:11:36Z, each with its path and auto_release 2026-09-20,
    buyer not confirmed, not released; **D6 pending, never sent; S8only unchanged with evidence still null** ("selection
    is not attachment"); **L7 untouched**, md5 identical to D's pre-pass read.
  - Readers: the bucket is private and the public-read policy covers only auction-media and avatars; owner read (the
    seller) and transfer-party read (the buyer, for its own transfer's object) are the whole RLS surface — no
    anonymous, no other signed-in user, no cross-transfer access. **Two caveats outside RLS:** a service-role key
    bypasses RLS entirely, including the Supabase dashboard (the Vault has none, which is why the cron 401s, but the
    project's key exists wherever it is held); and a signed URL bypasses sign-in for its lifetime — the buyer's
    1-hour link for the D1 JPEG lapses ~22:13:40Z. D cannot see signed-URL issuance; that is A's evidence.
  - Totals moved by exactly the two writes: notifications 105 → 107, buyer inbox 41 → 43, both `buyer_confirmation_needed`;
    queue 0; **2xx 0 of 191 — no outbound call has ever succeeded on this project.**
  - **What D's evidence cannot settle, stated by D:** what any image depicts (D has not looked and will not without the
    owner's instruction); which photograph was which on screen — "the face was D6" is the owner's identification, not
    D's read, though it follows from D6 and S8only having no object. D's row md5s are not comparable with A's
    (different projections); compare field by field across sessions.
  - D independently names the same delete mechanics: the policy refuses a seller delete while a transfer references
    the object, so deleting as the seller would need the reference cleared first, or a service-role delete — the
    owner's call, and D proposes nothing.
  **Both reports agree, so the owner's condition ("after D confirms") is satisfied.** The recommendation stands:
  the owner deletes the two objects in the Supabase Storage dashboard, which uses the project's own key without
  putting one in the Vault, so the expiry cron stays inert.
- **OWNER RULING on the privacy cleanup (2026-09-17): LEAVE the two stored proof files in place.** "No deletion,
  overwrite, reference clearing, service key or further storage access." So: no dashboard deletion, no service key in
  the Vault (the expiry cron stays inert), no reference clearing, and no further storage access by anyone.
  **Line 3 RESULT: QUARANTINED, with the two objects RETAINED** — the D2 PNG (210,364 B) and the D1 JPEG (5,829,677 B),
  both in the seller's folder, both still referenced by their transfers. Reachable only by the owner's own two
  accounts; nothing else has ever accessed them; the buyer's 1-hour signed link lapsed at ~22:13:40Z.
  **DV-IMG-9's HEIC conversion check: UNTESTED**, because Camera › Formats was "Most Compatible", so the phone
  produced a JPEG and no conversion could occur.
  **Line 3 rows as they stand:** D2 and D1 wrote (marked sent with proof); **D6 not performed**; **S8only not
  performed**; L7 untouched; RT6, U1, RT5-P, N1, N2 and N4 all held, unrun.
- **A's correction to option 1 (2026-09-17, after the ruling): "a service-role delete would arm the payout timer" was
  FALSE, and C verified the mechanics in the repo before recording it.** A's retraction: the Vault holds `project_url`
  only, the **Vault is what the cron and the DB triggers read**, the sandbox service-role key already exists in the
  owner's local env file (named only, never printed), and the **storage API takes that key as a request header** — so
  using it writes nothing to the Vault and `enforce-transfer-expiry` keeps failing 401 exactly as it has 191 times.
  *C's check:* `supabase/migrations/032_pre_testflight_blocker_fixes.sql:36,125` and `033_marketplace_expansion.sql:19`
  show the cron/trigger auth is the **Vault secret `service_role_key`**, which a header-supplied key never creates.
  Consistent with the standing record that this project's Vault has `project_url` only. So option 1's real cost was
  narrow — lifting the owner's standing deferral on *using* the sandbox service key for one action — not arming payouts.
  **Nothing to act on:** the owner's ruling forbids deletion by any route, so options 1 and 2 are both moot; this entry
  exists so the false cost is not carried into a later decision. A recommended option 2 for the smaller reason (no
  standing constraint lifted) before the ruling superseded it. D independently reached the same delete mechanics.
  **C's misattribution, corrected the same day: D's hazard was never the false half, and C wrongly told both D and the
  owner that it was.** The two halves must stay apart, and C verified the surviving one in the repo rather than on D's
  word: `032_pre_testflight_blocker_fixes.sql:98-114` — the `enforce-transfer-expiry` cron entry runs `*/2 * * * *` and
  builds its `Authorization: Bearer` from `SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name =
  'service_role_key'`.
  - **TRUE, D's original wording, still the standing instruction:** a `service_role_key` placed in THIS PROJECT'S Vault
    arms that cron within two minutes. **Do not put a service key in this project's Vault while the 72-hour
    auto-release deadlines are live.** That is why all 191 responses are 401 and none is a 2xx.
  - **FALSE, A's generalization, retracted:** that service-role use *as such* — e.g. a storage API call — would arm it.
    A request header never writes to the Vault, so it arms nothing.
  The narrow instruction survives; only the broadened version is dead. Recorded in these words at D's request after D
  pushed back on C's framing, and confirmed by C against the migration rather than accepted as asserted.
- **Next handset check chosen by C (non-destructive; Home and its filter sheet only; no transfer, proof, payment or
  L7 screens): Home's lazy filter datasets — a failed or slow filter load reading as an empty marketplace.**
  *Verified in Build 19 source before proposing (C):* `fetchSoldListings` and `fetchEndedListings`
  (`app/(tabs)/home.tsx:204-240`) have **no loading flag** and swallow failures with `console.warn` + `return`, while
  the chip flips immediately. So while the dataset is in flight — or when its fetch FAILS — the feed renders the
  settled empty copy ("Nothing sold yet / Completed sales show up here."; "No ended auctions / Auctions that closed
  without a sale show up here."). The screen-level offline state cannot mask it, because `loadError` belongs to the
  main listings fetch, not to these two. **Same defect class as F-BIDS-1, unverified on a device** — this is B's audit
  item 5, now confirmed in source by C.
- **B's five-direction exploration (prototypes only): `design/frontend-audit-20260917 @ c41e597`,
  `docs/design-audit/FIVE_DIRECTIONS_20260917.md` + `prototypes/five-directions.html`** (five directions × Home,
  Listing detail, Send, Receive, Checkout × normal and largest text, with a Reduce Motion toggle). No product code, no
  tests, no sandbox, no build; the Line 3 screens are reconstructions.
  **If the owner picks B's recommendation ("Gallery / Ledger"), what would land in C's code:** a new full-bleed 4:5
  Home media slot in `src/lib/media/slots.ts` consumed through the existing `EventMedia` (a slot, not a component
  rewrite); Home gains date section headers, i.e. `SectionList` on Home, the pattern `app/(tabs)/tickets.tsx` already
  uses; a frosted-panel treatment built on `experimental_backgroundImage` (expo-blur is NOT installed, and B checked);
  and **one token change — a muted non-red advisory accent** so advisory notices stop using the action colour, which is
  the three-file token shape (v2 + the design-tokens mirror + the parity test) and therefore an owner decision.
  **B's rule across all five:** nothing transactional is removed to make a screen calmer — the delivery blocker, the
  expiry consequence, the proof requirement, the payment-state notice and the full price breakdown stay visible.
  **B rejected two ideas specifically to protect C's work:** a bottom sheet as the primary checkout surface (a sheet
  implies dismissibility; a payment in flight is not, and `Sheet` has no drag-dismiss guard), and collapsing the
  delivery blocker or expiry line into an icon.
  **C's note for the eventual consolidated recommendation:** this overlaps ML-1 and the calm pass on the same shared
  primitives and tokens; whichever the owner approves, ONE of them must own those files.
- **F-HOME-1 — Home's "Recently sold" and "Ended" filters report an EMPTY MARKETPLACE when their fetch FAILS.
  CONFIRMED ON DEVICE, Build 19, 2026-09-17 5:57 PM Eastern (owner-reported).** Same defect class as F-BIDS-1:
  a failed load is indistinguishable from genuine emptiness.
  - **Owner's observation, offline (Airplane Mode ON *and* Wi-Fi off — both confirmed by the owner):**
    Recently sold → "NOTHING SOLD YET" / "Completed sales show up here."; Ended → "NO ENDED AUCTIONS" /
    "Auctions that closed without a sale show up here." **No connection error, no offline banner, no Retry, no loading
    indicator in either state.** The filter control showed one active filter; Home stayed in place and no other screen
    opened (screenshots, owner's).
  - **Cause, read at the built commit f412d10 (not the worktree):** `app/(tabs)/home.tsx` — the main listings fetch
    classifies failures (`:191-197`, `setLoadError(classifyLoadFailure(...))`), but the two filter datasets do not:
    `:213` `if (error) { console.warn('[HomeScreen] sold fetch error:', …); return; }` and `:233` the same for ended.
    No loading flag, no error state, no row preservation — the chip has already flipped, so the list renders its
    settled empty copy. The screen-level offline state cannot mask it because `loadError` belongs to the main fetch.
    Device wording matches the source copy exactly, so observation and cause are the same defect, not two.
  - **Sibling screens are NOT affected — checked at f412d10 before widening scope:** `explore.tsx` classifies and
    renders `ScreenState`/`SearchFailureNotice` (`:131-188`), `tickets.tsx` keeps current rows on a failed refresh
    (`:79-84,143`), `profile.tsx` keeps current on catch (`:163`) and shows `ScreenState` (`:221-224`). **Home's two
    filter datasets are the outlier in Build 19**; Bids was the other and is fixed on `frontend/bids-load-states`
    @ accb40c, which is NOT in Build 19.
  - **Status: FAILED (failure path).** Two halves remain **UNTESTED** and must not be inferred from this run:
    (a) the *slow-network* premature-empty path (same missing loading flag, never observed on a device);
    (b) **online recovery — the owner did not observe it and explicitly said not to infer it.** Whether the false
    empty state is sticky after connectivity returns decides severity, and is the next handset check C proposed.
  - **Release readiness:** C's assessment to A — same class as F-BIDS-1, consumer-visible, states a falsehood about
    the marketplace, but confined to two optional Home filters on a screen whose main feed does classify failures.
    Fix belongs with F-BIDS-1's pattern (latest-load guard + failure notice that preserves rows), NOT in Build 19.
- **F-HOME-1 stickiness — C's PREDICTION, written and committed BEFORE the owner's observation** (so the result tests
  the reading rather than being fitted to it). Read at f412d10, `app/(tabs)/home.tsx`:
  - `soldLoadedOnce.current = true` / `endedLoadedOnce.current = true` are set **only on success** (`:218`, `:238`),
    after the early `return` on error. A failed load therefore leaves the once-flag FALSE — the flag is not poisoned.
  - `onChipTap` (`:345-351`) and `onFiltersApply` (`:353-360`) re-fire the fetch only `if (!soldLoadedOnce.current)`.
    Because the flag stayed false, **re-selecting the filter retries the read**.
  - Nothing else refreshes these two datasets: `useFocusEffect` (`:246-252`) re-runs `fetchListings()` only — the main
    feed — and the realtime channel appends to `allListings`, not to sold/ended.
  - **Therefore predicted:** (a) staying on Recently sold after reconnection → the false empty PERSISTS indefinitely,
    no self-recovery, no spinner, no retry; (b) switching to All and back → refetches and populates.
  - **Severity if that holds:** sticky until the user acts, but self-clearing on any re-selection, and the main feed
    still classifies its own failures — so a user who leaves the filter sees the earlier-loaded feed rather than a
    claim of emptiness. Note the honest limit: that feed is the last successful read, not a fresh one.
  - **Not yet observed. Nothing here is a result**; the owner's report supersedes it either way, and a mismatch means
    the source reading is wrong, not the device.
- **F-HOME-1 prediction REFINED before observation — a second recovery path, found by A and verified by C at f412d10.**
  `app/(tabs)/home.tsx:365-371` — `onRefresh()` calls `fetchSoldListings()` / `fetchEndedListings()` for the active
  chip **unconditionally**, with no once-flag gate. So pull-to-refresh clears the false empty as well as re-selection.
  - **Revised prediction:** the false empty is sticky against *time* and against leaving and returning to Home, and
    clears on **either** user action — a pull-to-refresh or a re-selection of the filter.
  - **Test-design consequence, which is why this mattered before the run, not after:** C's original sequence
    ("flip to All and back") exercises only one of the two paths. A pull-to-refresh during the passive-watch step would
    have looked like self-recovery when it is not. The owner's sequence was corrected to watch without pulling, then
    pull deliberately as its own step.
  - **Failure is still silent on that path:** `onRefresh` sets `refreshing` true/false around the call, so the gesture
    shows a spinner, but a failed read still returns early and leaves the settled empty copy with no error. A user who
    pulls while offline sees a spinner and then the same false "nothing sold yet".
  - **Severity language agreed with A, replacing "sees real state":** the main feed *never claims emptiness, may be
    stale, and says so when it cannot read* (`:191-197` classifies its own failures).
- **F-HOME-1 stickiness run, 2026-09-17 — TWO CONFIRMED SCREEN STATES, RECOVERY PATH UNCAPTURED.** Owner-reported with
  two screenshots, Build 19, sandbox buyer, Larger Text on.
  - **6:46 PM Eastern, Airplane Mode on (status bar shows the airplane glyph, no Wi-Fi or cellular):** Home with
    FILTERS 1 active, Recently sold → "NOTHING SOLD YET" / "Completed sales show up here." Empty body, no error text,
    no banner, no Retry, no spinner. **Confirms the 5:57 PM observation a second time.**
  - **6:47 PM Eastern, connectivity restored (status bar shows cellular bars and Wi-Fi):** the same screen, same
    FILTERS 1, now populated with sold listings — Device D6 and Device D1 visible ("SOLD", "Club Device", "SOLD FOR
    $110 all in"), D2 and D3 below.
  - **UNCAPTURED, and NOT to be inferred — the owner said so explicitly and C is recording it that way:** whether the
    screen recovered on its own, after a pull-to-refresh, or after switching filters; and the exact recovery moment.
    The screenshots establish two end states one minute apart, nothing about the transition between them.
  - **C's committed prediction (7dcdf22, refined e9dd55f) is therefore NEITHER CONFIRMED NOR REFUTED.** It predicted
    no self-recovery while the filter stays applied, with recovery on a pull or a re-selection. This run cannot
    distinguish those, because the interaction sequence was not captured. **The prediction stands UNTESTED.** It is
    not evidence, and must not be quoted later as though the 6:47 screenshot supported it.
  - **A's severity claim "lowers severity a notch" is WITHDRAWN** (A, cc409b6), with C's inversion as the reading that
    stands: a pull-to-refresh while still offline ends its spinner on the same settled empty copy, so the gesture a
    user reaches for when a list looks wrong is the one that most convincingly confirms the lie. A's earlier "sees real
    state" was also withdrawn, replaced by: the main feed never claims emptiness, may be stale, and says so when it
    cannot read.
  - **What this run settles:** the defect itself, twice observed. **What it leaves open:** stickiness and the
    slow-network premature-empty path, both UNTESTED.
  - **C's recommendation: do not spend another handset run on the stickiness half.** The fix is identical either way —
    the two filter datasets need a loading state, a classified failure state and row preservation, exactly F-BIDS-1's
    pattern — so the answer would change the urgency ranking, not the code. Behavioural tests can pin both recovery
    paths off-device, since `onChipTap`, `onFiltersApply` and `onRefresh` are all reachable in the existing harness.

## Consolidated recommendation on B's frontend audit (C, 2026-09-17)
Owner's instruction: "After the handset pass, validate B's findings and give A and me one ranked implementation batch,
separating CONFIRMED DEFECTS from DESIGN PROPOSALS and saying which genuinely block release." Handset work is finished
or quarantined, so this is that batch. **B's audit: `design/frontend-audit-20260917 @ ea8a9a2`,
`docs/design-audit/FRONTEND_DESIGN_AUDIT_20260917.md`.** B read at `6561d1f` (= Build 19's `f412d10` + F-BIDS-1);
**C re-verified every confirmed defect below at `f412d10`, the tree the owner's phone actually runs.**

### CONFIRMED DEFECTS — each verified by C in Build 19 source, not accepted on B's report
| # | Defect | C's verification at f412d10 | Blocks release? |
|---|---|---|---|
| **1** | **F-BID-1 (B's P1) — Place bid builds its form on a $0 floor after a failed read.** `.then(({ data }) => …)` never destructures `error` and has no `.catch`; a resolved-with-error read leaves `listing` null, `loading` false, and `minNextBid(listing?.current_bid ?? 0, …)` offers a minimum derived from nothing, with no event name (`:200` renders it conditionally). A *rejected* read never runs the handler, so the spinner never clears. | `src/screens/PlaceBidScreen.tsx:70-85,180-201` — read directly; no null-listing guard exists between the loading branch and the form | **YES.** The app states a price it does not know on a screen where a user commits money, and the second path is a permanent stall. Smallest fix in the batch |
| **2** | **F-HOME-1 (B's P5) — Home's filters report an empty marketplace when their fetch fails.** | `app/(tabs)/home.tsx:213,233` warn-and-return, no loading flag, no error state. **Confirmed on device twice** (5:57 PM and 6:46 PM, owner) | **YES**, with the same pattern as F-BIDS-1 |
| **3** | **F-SEND-1 (B's P3, device-corroborated) — "Transfer window expired" is a device-clock claim the button contradicts.** The chip is `formatCountdown(transfer.expires_at)` on a 60-second interval, computed on the device; the CTA is `disabled={busy \|\| refreshing \|\| buyerDeliveryMissing}` with **no expiry term**, and `mark_transfer_sent` has no `expires_at` check, so sending still succeeds until the sweep flips the row. | `app/transfer/send/[id].tsx:110-115,306-313,347` | **YES for the contradiction**, which also violates the standing truth that *the device clock is not an authority*. The re-order and notice redesign around it do NOT block release |
| **4** | **F-DESTRUCT-1 (B's P4) — destructive listing actions are re-entrant.** `performDelete` and `performCancel` carry no busy flag and nothing disables the row while the request is in flight. | `app/my-listings.tsx:105-130` | **No** — each sits behind a confirm dialog, so it needs a deliberate second confirmation. Include in the batch, not as a gate |
| **5** | **F-AVATAR-1 (B's P6) — the busy flag clears before the write.** `setAvatarUploading(false)` (`:193`) runs *before* `profiles.update()` (`:199`), and `setAvatarUrl` only after it. | `app/(tabs)/profile.tsx:189-203` | **No.** *C corrects B's framing:* the user does not see "done" — they see the spinner stop with the **old avatar still showing**, so it reads as a no-op, and the guard is already false, so a second tap can race the first write |
| **6** | **F-BIDS-1 — already fixed**, reviewed by D, integrated at `6561d1f`. Not in Build 19. | — | Carried by whatever candidate ships next |
Also confirmed earlier and unchanged: **F-NOTICE-1** (stale deletion notice, server-side, A's lane) and **"Buyer: Unknown"**
(B's P12 — three surfaces, three fallbacks, no shared resolver; `personLabel()` is the right fix, polish rank).

### DESIGN PROPOSALS — the owner's call, none of them defects
B's P7–P16 (ErrorBoundary→StateView, retiring the five live legacy components and two dead ones, legal/privacy onto
`textStyle()`, one `ScreenHeader` for eleven hand-rolled bars, `personLabel()`, the `Notice` primitive with three ranks,
the lint guard, doc hygiene, the setup-path transport copy), the Send Transfer re-order (§2a/2f), ML-1 v2, B's calm pass,
and B's five directions. **Two are token decisions with whole-app effect and are the owner's alone:** whether
`border.default` stops being red-tinted, and whether advisory notices get a muted non-red accent.

### THE ONE DECISION C IS BRINGING — who owns the shared primitives
ML-1, the calm pass and the five directions all edit the same files: `ui/StateView.tsx`, `ui/Chip.tsx`, `ui/Badge.tsx`,
`ui/Button.tsx`, `ui/EmptyState.tsx`, a new `ui/Notice.tsx`, and the v2 tokens. Approving more than one without naming an
owner means they overwrite each other. **C's recommendation: the calm pass owns the primitives and tokens; ML-1 ships as
My Listings layout only, consuming whatever the primitives become; the five directions inform the token choices and ship
nothing on their own.** Rationale: the calm pass is already scoped exactly at that layer, ML-1's value is its grouping and
Needs-action priority rather than its styling, and the directions are exploratory by B's own labelling.

### SEQUENCE C RECOMMENDS
- **Batch 1 (next candidate, correctness only, zero token or layout change):** defects 1, 2, 3's contradiction, 4, 5,
  riding with the already-integrated 6. Each gets a behavioural test with a negative control, per B's S0 acceptance bar.
  Provable locally; no handset time required to build, and the device rows can be claimed on the next candidate.
- **Batch 2 (after the ownership decision):** the primitives, the notice ranks, the Send Transfer re-order, the legacy
  retirement. Nothing here blocks a release.

- **F-HOME-1 stickiness — OWNER'S CORRECTION (2026-09-17), superseding the "uncaptured" record above.** The owner
  reported the interaction sequence they had not captured at the time: **they pulled down to refresh while Recently sold
  was selected, and the sold listings appeared after that manual refresh. The screen did NOT recover by itself from
  reconnecting.** Recorded exactly as the owner framed it:
  - **Passive automatic recovery: NOT OBSERVED / did not occur during the watch** (watch duration approximate, not
    captured).
  - **Pull-to-refresh recovery: OBSERVED** — content returned after the manual refresh.
  - **The 6:47 PM screenshot is evidence of the POST-REFRESH populated state, not of automatic recovery.** The earlier
    entry recording the transition as uncaptured is superseded by this; A's record and the bar on quoting that
    screenshot were updated to match.
  - Timing stays approximate throughout: the moment of reconnection and the moment of the pull were not captured.
  - **C's committed prediction (7dcdf22, refined e9dd55f) is now CONFIRMED on both halves it can claim:** no
    self-recovery while the filter stays applied, and recovery on a pull-to-refresh. The **re-selection** path
    (`onChipTap` / `onFiltersApply` re-firing because the once-flag stayed false) remains **UNTESTED** — the owner
    recovered via the pull and never needed the filter switch. Behavioural tests will cover it off-device.
  - **Severity, now settled rather than inferred:** the false empty is sticky against time and against reconnection, and
    clears only when the user acts. Combined with the property that a failed pull is silent, the full shape is: offline,
    a pull ends its spinner on the same "NOTHING SOLD YET"; online, the same gesture fixes it. The user cannot tell those
    two apart from the screen.

## Batch 1 — state correctness (C, 2026-09-17). `frontend/batch1-state-correctness @ 812ec45`
Owner authorised the five items, one branch, tests with negative controls, D reviews the tests, A reviews
transfer/payment behaviour, no build, no sandbox, Build 19 and Line 3 evidence untouched. Cut from A's
integrated head **6561d1f** so F-BIDS-1's pattern is available. Worktree `/Users/josetascon/snatchit-b1state`.

| # | Commit | Fix | Tests | Negative controls |
|---|---|---|---|---|
| 1 | `ff8427c` | **F-BID-1** `PlaceBidScreen.tsx` — the read is awaited in one place; an error, a missing row or a thrown read classifies and ends loading, and no form renders without a listing. Retry re-reads. | 8 | full revert to shipped code kills 7/8 as predicted (B5, the happy path, survives by design); M2/M3/M5 kill their one test each; **M1/M4 survive — three layers hold independently** |
| 2 | `2745dc7` | **F-HOME-1** `home.tsx` + new `src/lib/home/filterLoad.ts` — each lazy dataset carries loading / classified error / settled; rows survive a failed refresh behind an alert-role notice with Retry; the settled empty copy needs a successful read. | 11 | 7/7 as predicted **after correcting the harness and three predictions** (below) |
| 3 | `75f6673` | **F-AVATAR-1** `profile.tsx` — busy spans upload *and* save, cleared in a `finally`. | 6 | 2/2 |
| 4 | `cc1c9c4` | **F-DESTRUCT-1** `my-listings.tsx` + `SellerListingCard.tsx` — per-listing ref lock, `busy` prop stands the row down, confirmation refuses to re-open. Rules, precondition and RPC arguments unchanged. | 7 | 6/6 after one correction; DM2 survives by design |
| 5 | `ffd0f06` | **F-XFER-1 (client half)** `transfer/send/[id].tsx` + `TRANSFER_EXPIRY_COPY` — the screen stops asserting an expiry nothing enforces. **CTA enablement deliberately unchanged.** | 6 | 5/5; XM2 (disabling the CTA on expiry) kills X2 *by design* — that would be a transfer-rule change, A's and the owner's, not this batch |
| 6 | `812ec45` | `tests/candidate-recovery.test.ts` — the CFT-604 Home pin follows the new shape and additionally asserts the settled empty copy is unreachable until the dataset returns. Intent widened, not weakened. | — | — |

**Gates, run fresh in the same session:** `npx vitest run` **2288 passed / 111 files**; `npx tsc --noEmit -p tsconfig.json` clean; `npm run lint` **0 errors, 29 warnings** (the recorded baseline — no new warnings).
**Gated surface:** `git diff --stat 6561d1f..HEAD -- src/lib/payments.ts src/lib/checkout/{setupDecision,payControl,holdState}.ts src/lib/auth/signOut.ts supabase/ scripts/ .github/` → **zero lines**.

**Method notes kept because they are the evidence, not decoration:**
- **A test weakness the mutants found, not the reviewer:** the Home `view()` helper read "nothing rendered" as
  loading, so HM1 (dropping the loading flag) survived. It is now a distinct `'blank'` verdict and HM1 kills H1.
- **Four predictions of C's were wrong and are corrected in place, with the tests vindicated each time:** HM2 also
  kills H10; HM6 spares H8 because a pull does not go through `retryDataset`; HM7 also kills H9; DM1 also kills D2.
- **Survivors recorded as defense in depth, with the combined control that does kill:** F-BID-1's M1/M4 (and M6,
  which also survived until the full revert — a null dereference throws into the catch, a third layer);
  F-DESTRUCT-1's DM2; F-XFER-1's XM4, whose combined XM5 removes both status gates and kills X5 as predicted.
- **Nothing here is device-verified.** No build, no sandbox, no handset time; device rows are owed on whatever
  candidate carries this.

- **F-XFER-2 (A's id, 20ef84a; C aligned to it) — the buyer's screen still makes the claim the seller's no
  longer makes.** Filed separately from F-XFER-1 on purpose, so the owner sees two separable decisions rather
  than one bundled ask: the client copy fix (this) and server-side enforcement (F-XFER-1's open half). Found by A reviewing the batch; **C verified it at the batch head and found the gate is looser than
  A reported.** `app/transfer/receive/[id].tsx`:
  - `:341` renders the literal `'Transfer window expired'` from the same device-clock `formatCountdown`.
  - `:338` the render condition is `transfer.status !== 'buyer_confirmed'` — wider than the send screen's
    `=== 'pending'`.
  - **`:166` the countdown effect has NO status gate at all** (`if (!transfer?.expires_at) return;`), where the
    send screen's effect also required `status === 'pending'`. So the buyer can be shown "Transfer window
    expired" on a **seller_sent** transfer — the tickets are already on their way, and the screen announces an
    expiry about a window that no longer matters, for an enforcement that does not exist.
  - Same false claim, counterparty's screen, and the same non-enforcement underneath: `mark_transfer_sent` (140)
    reads status only. **Fix is the same shape as the send half** — `TRANSFER_EXPIRY_COPY` plus a status gate —
    and it is a SIXTH item, on a screen the owner's Batch 1 scope did not name. **C is not expanding scope
    unasked: recorded and put to the owner with a recommendation.**
- **A's residual on the batch, accepted and recorded rather than argued:** the new send-screen copy still derives
  from the device clock, so a skewed clock says "has passed" early. Much weaker than the old chip — it gates
  nothing and invites the action rather than forbidding it — but under the standing truth that the device clock
  is not an authority, it is not nothing. Closing it properly means the server saying whether the window has
  passed, which is the same decision A has already put to the owner.
- **A's review outcome on Batch 1: transfer half PASSES.** A independently verified the zero-line gated surface
  rather than taking C's word, and endorsed leaving the CTA's `disabled` untouched with the expiry-term mutant
  killing X2 by design. **A's own push is blocked by a permission gate and A will not route a PR through C** —
  opening one is the owner's call, and A has put it to them. Branch holds at 812ec45; nothing owed by C meanwhile.

- **D's review of Batch 1: the five fixes PASS, the tests had four gaps — all closed at `2fe7abd`.** D re-ran
  the gates itself (2288/111, tsc 0, gated surface zero lines) rather than taking C's report, then read the
  helpers and the diff. **C verified every finding against the code before accepting it; all four reproduced.**
  - **(a)** place-bid `view()` returned `{form:true}` for anything that was not a state or a spinner, so an empty
    tree read as "the bid form is up" — the outcome the fix exists to prevent. **(b)** profile `busy()` returned
    `false` for "absent" and "idle" alike, because `findElement` yields undefined rather than throwing
    (`nav-stack-harness.ts:194`). **(c)** B2's `$0` pin sat behind `'texts' in shown`, false for every passing
    verdict, so it never executed. **(d)** X5 had two `not.toContain` and no positive anchor.
  - **The correction C accepted on its own commit message:** "three independent layers" was WRONG. The refusal
    lives in ONE place — the render guard, whose two terms are each sufficient — with the catch supplying
    classification, not refusal. D's real point: **no mutant removed that guard alone.** `M7` now does, and
    kills **7 of 8**, one more than C predicted (with the guard gone there is no `ScreenState` at all, so B3
    falls too); only B5, the happy path, survives.
  - **The general fix, not a fourth specific one:** `tests/helpers/screen-view.ts` — one reader, one rule: a
    verdict is reported only when something positively identifies it, and "nothing matched" is `'blank'`, which
    no assertion expects. D's framing, kept because it is the lesson: *four of six findings were the same defect
    C had already found and fixed once in the Home helper, and left standing in three others.*
  - **New controls:** `M7` (render guard alone) · `DM7` (id-keyed lock → global) kills the new **D8**, which taps
    a second row while the first is in flight — nothing in D1–D7 distinguished per-listing from global ·
    `AM3` (avatar control goes missing) kills all six, where the old boolean helper passed four.
  - **Gates after hardening:** vitest **2289 passed / 111 files**; tsc clean; lint 0 errors / 29 warnings.
  - Still true: no device verification, no build, no sandbox, Build 19 untouched. Branch head **2fe7abd**.

- **F-AVATAR-2 — the avatar defect is unfixed in a SECOND screen. Found by D while re-running C's controls;
  C verified it at the batch head.** `app/settings/edit-profile.tsx:65-82` is `setAvatarUploading(true)` →
  `await pickAndUploadAvatar` → **`setAvatarUploading(false)`** → `profiles.update({ avatar_path })` →
  `setAvatarUrl`. Byte-for-byte the shape C fixed on the profile tab: the ring goes idle while the write is
  still in flight, the old photo is still showing, and `if (avatarUploading) return` is already open.
  - **What C found on top of D's report: there are TWO controls, not one.** `:141` the avatar ring and `:149`
    the "Change photo" text both call `handleAvatarPress` with the same open guard, so either can start the
    second pick during the write window.
  - **Consequence (D's, and it holds):** two overlapping presses each write `avatar_path`; if the second
    upload's update lands first, the stored path points at the earlier object and the avatar silently reverts
    on next load. Worse than the profile tab, where the same race only re-renders.
  - **Untested:** the only test touching the file (`tests/settings-completion.test.ts:60-63`) asserts the source
    contains `avatar_path:` and would pass with the defect present or absent.
  - **Outside the five items the owner authorised. Batch 1 stays as reviewed; C is not widening a passed
    branch.** D offered to carry it; C keeps it — consumer screens are C's lane.
- **C's recommendation to the owner: one small follow-up batch, not two asks.** F-XFER-2 (the buyer's screen
  still claims an expiry nothing enforces) and F-AVATAR-2 are the same species — *a defect fixed in one screen
  and left standing in its twin* — each a few lines with the same test-and-control treatment, neither touching
  payment, auth, transfer rules or the server. Owner's call; nothing starts without it.
- **D's Batch 1 verdict: PASS.** D re-ran C's three new controls in its own detached worktree at `2fe7abd` and
  all three reproduce exactly — M7 7 failed / 1 passed with B5 the sole survivor; DM7 D8 alone; AM3 6 of 6.
  Gates on the pushed head, D's own run: vitest 2289 / 111, tsc 0. **AM3 is the one that earns the tri-state
  helper:** under the old boolean, A2/A4/A5/A6 would all have passed with the control absent from the screen.

## Batch 1b — the twin screens (C, 2026-09-17). `frontend/batch1b-twin-screens @ 3fc2acb`
Owner authorised exactly two items, client-only: F-XFER-2 and F-AVATAR-2. Cut from the **reviewed** Batch 1
head `2fe7abd`, which is untouched at 2fe7abd. D reviews the tests, A reviews the transfer wording.

| # | Commit | Fix | Tests | Negative controls |
|---|---|---|---|---|
| 1 | `f743d76` | **F-XFER-2** `app/transfer/receive/[id].tsx` — the countdown effect is gated on `pending` like the send screen's, the render gate matches, and the expired case reads `TRANSFER_EXPIRY_COPY`. **On `seller_sent` the window line is gone entirely, not softened** (A's position, independently reached; the send window stops meaning anything once the tickets are on their way). | 8 (R1–R8) | 5/5 after two corrections |
| 2 | `3fc2acb` | **F-AVATAR-2** `app/settings/edit-profile.tsx` — busy spans upload *and* save, cleared in a `finally`, across **both** controls (the ring and "Change photo" share one flag). | 8 (E1–E8) | 6/6 after two corrections |

**Gates, fresh:** vitest **2305 passed / 113 files**; tsc clean; lint **0 errors, 29 warnings** (baseline).
**Gated surface vs 2fe7abd: zero lines** (payments, the three checkout modules, signOut, `supabase/`, `scripts/`,
`.github/`). Diffstat: four files — two screens, two test files. No build, no sandbox, Build 19 and the retained
proof files untouched. **The server-side expiry decision stays separate and open; nothing here anticipates it.**

**Method notes — four predictions wrong, and what each taught:**
- **A line was DELETED because its mutant survived.** C added an explicit `setCountdown(null)` reset; RM5 showed the
  render gate already hides a stale value, so nothing could observe it. *A line no test can justify and no user can
  observe is worse than no line*, so it went rather than being kept as "defense in depth".
- **RM2 (wide render gate alone) KILLS R8**, where C predicted survival. That is what gives the render gate its own
  targeted control — via the one real in-screen transition: the buyer opens the ticket provider, returns after
  `MIN_AWAY_MS`, and the seller has sent meanwhile.
- **EM3/EM4 taught the layering on the avatar screen:** the `disabled` props are PRESENTATION (EM3 kills E2 alone,
  EM4 kills E1 alone) and the function's own `if (avatarUploading) return` is the LOCK — EM5 alone changes nothing,
  and only EM6 (guard plus both props) kills all four. Both layers now have their own control.
- Running total of C's prediction accuracy across Batch 1 and 1b: **eight corrections, every one of them C's
  prediction rather than a test defect**, plus two real test weaknesses the mutants exposed (the Home `view()`
  conflation, found by HM1, and D's four helper gaps).

- **Batch 1b closed out at `0ca71ff`** (from 3fc2acb → `fbe83a2` → `0ca71ff`). Three review findings landed after the
  first push, and **two of them were real defects in C's own fix, not test gaps**:
  - **F-XFER-2-A (A's wording review, `fbe83a2`).** Batch 1b gave both screens ONE string, and its second clause —
    "send now if you still can" — is addressed to the SELLER. The buyer read an instruction for an action they
    cannot take. *The old literal was wrong for asserting an unenforced rule; C's replacement was wrong for
    addressing the wrong party.* `TRANSFER_EXPIRY_COPY` now carries one string per role; the buyer's says what is
    true from their side ("the seller may still send"). **R9** pins that the buyer's screen renders neither the
    seller's string nor any instruction to send — matching the *shape* by regex, not the exact string — and **R10**
    that the roles differ and neither asserts a block. A's note, recorded: R7 guaranteed the two screens SHARE a
    constant and guaranteed nothing about its suitability, and a shared constant is exactly where an audience
    mismatch hides from a suite.
  - **D's finding 2 — the avatar re-entry guard DID NOT WORK (`0ca71ff`).** D removed it and all 8 tests passed; C
    wrote the press `disabled` cannot stop (the handler twice in one tick, before React re-renders) and **two
    uploads started**. The state guard read the same stale closure both times. E3/E4 only ever proved the controls
    were disabled. The lock is now a **ref**, the pattern F-DESTRUCT-1 already used for this race, with the state
    kept as what the controls SHOW. **E9** pins the same-tick press; **E10** pins the RELEASE, after a mutant that
    never cleared the ref passed everything else. *C's earlier claim that "the function's own guard is the actual
    lock" was contradicted by C's own suite.*
  - **D's finding 1 — the countdown effect's status gate was unpinned.** It is invisible in rendered output because
    what it stops is a `setInterval(…, 60_000)` firing `setCountdown` once a minute for as long as the screen is
    open. **R11/R12** pin it through the resource: one timer while pending, none once the window stops applying,
    and a live timer cleared across the transition.
  - **CAVEAT now recorded beside the code, at D's insistence:** *"a line no test can justify and no user can observe
    is worse than no line"* was right for the inert reset C deleted and would be WRONG for the effect gate.
    **Observable must include resource behaviour** — timers, subscriptions, re-render loops — or the rule eats a
    guard that does real work. Not a slogan; it is written next to both cases.
  - **Gates at `0ca71ff`:** vitest **2311 passed / 113 files**; tsc clean; lint 0 errors / 29 warnings; gated surface
    vs 2fe7abd **zero lines**. A: wording CLOSED (3413b6b) with A's own gate runs matching. D: mechanics PASS at
    3fc2acb, final verdict pending on the two closures.
- **F-AVATAR-3 (NEW, C, outside 1b's authorised items — recorded, not fixed).** `app/(tabs)/profile.tsx:190` still
  guards with `if (!user || avatarUploading) return;` — **state, not a ref** — so the profile tab carries the same
  same-tick double-press race that D's review exposed in Edit Profile, and its suite has no E9-equivalent. Batch 1
  is reviewed and passed; C is not amending it. Same one-line shape as the 1b fix (a ref lock plus two tests).
  **Owner's call.** This is the fourth time today the pattern has held: *the fix was right, and the search for where
  else the shape lives is what found the rest.*
  **CONFIRMED LIVE by two independent runs, not inferred from the code:** D appended a throwaway probe to the Batch 1
  profile suite (two presses in one tick, count uploads) and got `expected 2 to be 1`; **C ran the same probe
  separately and got the same result**, then removed it. So the profile tab starts two uploads on a same-tick double
  press. The race is in Build 19's code too — Batch 1 changed when the busy flag clears, not what guards re-entry.
  **When authorised the fix is the one already written in 1b:** the ref lock plus E9/E10 equivalents, because the
  release matters as much as the lock.
- **D's correction to its own Batch 1 verdict, recorded in D's words rather than C's:** D's PASS was a verdict on the
  tests and stands as that, but it did not catch a live defect sitting in the diff. D's diagnosis of how: *on F-BID-1
  it asked which line does the work and found the render guard was the only one; on F-AVATAR-1 it never asked the
  same question about `if (!user || avatarUploading) return;`* — the standard applied in one place and not the other.
  D also corrected its 1b disposition after C's evidence: it had written "the shipped behaviour is correct" about a
  guard it had not exercised, one message after saying a claim is not a fact until someone runs it.
- **D's instrument ruling on R11/R12, accepted:** keep the `setInterval` spy, do NOT add clock advancement. What the
  tests must prove is that no timer is created and that a live one is cleared; a spy observes exactly that, while
  advancing a clock would only show the consequence of a timer already proven not to exist and would couple the test
  to the 60-second period, an implementation detail.
- **D's final verdict: Batch 1b PASS at `0ca71ff`**, re-run at that head (vitest 2311 / 113, gated surface vs 2fe7abd
  zero lines), with all four new controls verified on D's own runs: remove the ref check → E9 alone; never release the
  ref → E10 alone; remove the effect status gate → R12 alone; buyer screen renders the seller string → R1 + R9.
  **A test verdict only — not a merge or deployment authorisation; sequencing is A's and the gate is the owner's.**

## Batch 1c — the profile-tab avatar race (C, 2026-09-17). `frontend/batch1c-profile-avatar @ 2567401`
Owner authorised F-AVATAR-3 with the four required tests named. Cut from the passed 1b head `0ca71ff`, so the
stack is linear: `6561d1f` → Batch 1 `2fe7abd` → 1b `0ca71ff` → 1c `2567401`. D reviews the implementation **and
the negative controls**. The server-side expiry decision stays separate and untouched.

**Fix** (`app/(tabs)/profile.tsx`): the lock is a **ref**; `avatarUploading` stays as what the control SHOWS.
The state guard it replaces was in Build 19 and survived F-AVATAR-1 — Batch 1 changed when the flag clears, not
what guards re-entry.

**Tests (6):** P1 same-tick double press → one upload and one `profiles.update`, **with the stored path asserted
rather than assumed** · P2 out-of-order completion cannot arise, checked against both the UI press and the raw
handler · P3 a later press succeeds once the prior save completed · P4 the control stays available and the busy
state cleared exactly once · P5 a failed save releases the lock · P6 a cancelled pick releases it.

**Controls 4/4**, after two corrected predictions that both show *the lock changed layer*: **PM1** restores the
state guard → P1, P2 · **PM2** never releases → P3, P5, P6 (D's E10 point: a guard that locks and never unlocks
bricks the control) · **PM3** clears busy before the save → A1, A2, P4 but **no longer A3**, because the ref
rather than the state is now what stops a second press · **PM4** removes the acquire → A3, P1, P2.

**Gates:** vitest **2317 passed / 114 files**; tsc clean; lint 0 errors / 29 warnings. **Gated surface across all
three batches vs `6561d1f`: zero lines** (payments, checkout, signOut, `supabase/`, `scripts/`, `.github/`,
app.json, package.json). No build, no sandbox, Build 19 and the retained proof files untouched.

**Two limits C stated to D rather than letting them read as coverage:**
- **P2 is an argument, not an observation.** C cannot observe an ordering the lock prevents from existing; it
  asserts no second save overlaps the first and that the stored path is the single upload's.
- **P4's "cleared exactly once"** actually asserts the observable consequence — one upload, one save, control
  re-enabled — because counting clears would mean reaching into React internals. Said so in the test.

**PR:** the owner authorised a review PR for 1/1b/1c so CI can run — **no merge, no deploy, no build**. **A owns
and opens it**; C declined to open a second one, since release integration is A's lane.

- **Correction to C's own Batch 1c report: the file count was 113, and it is 114.** A measured 114 at `2567401`
  and flagged the mismatch; C re-ran and confirmed A is right. 1b was 113 files; 1c adds
  `tests/profile-avatar-same-tick.test.ts`. The test TOTAL (2317) was correct throughout — C carried the file
  count forward from the 1b run instead of reading it off the 1c run, i.e. reported a number it had not looked at
  in a message whose whole point was verified evidence. **A's reason for not letting it go is the one worth
  keeping: a reported count that doesn't reconcile is the shape of the thing that is right until it isn't.**
- **Owner's ruling on server-side transfer expiry (via A): NO server-side enforcement this sprint; keep the honest
  client wording.** F-XFER-1's open half is therefore CLOSED by decision, not by code. The copy C and A landed was
  written to be true under either answer, so the ruling costs nothing to absorb — that is what the restraint bought.
  **If enforcement is ever added, `TRANSFER_EXPIRY_COPY`'s comment already says the copy must be revisited.**
- **F-AVATAR-3 is a STANDING defect, not a regression** (A's framing, accepted): the state guard is in `f412d10`,
  the build on the owner's phone. Batch 1 changed when the busy flag clears, not what guards re-entry.
- **Review PRs, owned by A, both draft, no merge / no deploy / no build:** #72 (Batch 1 + 1b) and **#73 (1c alone,
  stacked on #72)** — https://github.com/SnatchIt-app/snatchit/pull/73 — **all nine checks pass** at `2567401`.
  D's implementation and control review of 1c is still open; nothing integrates before it lands.

- **D's Batch 1c verdict: PASS at `2567401`** — implementation AND negative controls, as the owner required, on D's
  own runs (vitest 2317 / 114; gated surface zero across all three batches; PM1 → P1+P2, PM2 → P3+P5+P6).
  - **D's structural finding, stronger than C's claim:** the acquire sits before the first `await` and before
    `setAvatarUploading(true)`, and there is **exactly one** `avatarInFlight.current = false` in the file, in a
    `finally` — D counted rather than eyeballed. So a double clear is **impossible by construction**, which is a
    better guarantee than any assertion. P4 is renamed to what it observes; the structural argument lives in the
    commit, not in the test's name.
  - **D declined C's offer of an interleaving test for P2, and the reasoning is worth keeping:** P2 pins the
    invariant (no second operation starts while one is in flight) and out-of-order completion follows deductively;
    it already has a control that fires (PM1). A permanent test that removes the lock to demonstrate the reversion
    would pin *the behaviour of code that does not exist* — that is a mutant's job, transiently. The reversion has
    been demonstrated live twice (C's run and D's independent probe) and that evidence belongs in this record.
- **F-SEC-1 (NEW, C, from D's hand-over — a LEAD that C probed and CONFIRMED).** `src/hooks/useSecurityNotices.ts`
  guards `dismiss` (`:56`) and `signOutAll` (`:74`) with `if (busy) return;` — **state, not a ref**, the same shape
  as the three avatar/listing races.
  - **Probe result: the same handler reference called twice in one tick invokes `signOutAllDevices()` TWICE**, with
    one navigation. So the guard does not stop a real double-tap on a **security action**.
  - **C's first probe was INVALID and C caught it before reporting a result.** It re-read `api.signOutAll` for the
    second call, so the harness's synchronous re-render handed it a fresh closure with `busy` already true — it
    "passed" and proved nothing. Real React does not re-render between two presses in one event loop. Capturing the
    handler ONCE reproduces the real condition. *Suspect the harness when a result flatters the code.*
  - **What is NOT established:** whether the second `signOutAllDevices()` fails in production and therefore shows
    "sign out failed" after a successful sign-out. C's mock forced the second call to fail; the real return value
    after sessions are revoked is unverified. The confirmed part is that the second invocation happens at all.
  - **Outside every current authorisation, and it touches auth** — `src/lib/auth/signOut.ts` is on the gated
    surface, so any fix goes to A before merge. Recorded for the owner; nothing started. **Fifth instance of the
    same shape today**, and the first one C found by taking a hand-over rather than being handed the defect.

- **F-SEC-1 — D's independent confirmation, labelled as what it is.** D read the mechanism and **did not re-run
  C's probe**, saying so: `signOutAll` is `useCallback(…, [busy])` with `if (busy) return` over `useState`, so a
  captured reference carries `busy === false` and the second call walks through. `dismiss` (`:55-71`) has the
  identical shape with `[notice, busy]` — same defect, lower stakes. D is not treating it as a new hypothesis
  because the same mechanism was confirmed empirically twice today on the avatar screens. **There is no
  behavioural harness for this hook** — `tests/security-notice.test.ts` greps the source — so an independent
  empirical run means building one, which is the owner's call, not speculative work.
  - **D's framing of the claim, adopted: "a security action runs twice" is the headline and is enough to justify
    a fix.** The failure-copy consequence (whether the second call then shows "sign out failed" over a successful
    sign-out) stays a HYPOTHESIS — it would need a real double invocation against a real session, and C's mock
    forced that outcome rather than observing it. It must not become the headline when this reaches the owner.
- **Why C's invalid probe looked legitimate — D's diagnosis, and the reason the rule is now durable.** Re-reading
  `api.signOutAll` between the two calls does not hand back a stale reference; because the handler is memoized on
  `[busy]`, it hands back a genuinely DIFFERENT function whose closure already has `busy === true`. That is exactly
  what a real double tap cannot reach, since React does not re-render between two presses in one event loop. **A
  guard memoized on the state it guards is where the next person writes the same broken probe and believes it.**
  **Rule: capture the handler once and call that same reference twice.** Written into the durable memory
  `busy-window-is-not-a-lock` (which already covered the trap; C merged the handler inventory in rather than
  creating a second entry) and recorded here with C's case as the example.
  **C caught it because the pass felt too easy — there was no mechanism that would have caught it. The suspicion
  was the mechanism.** Kept in the record as-is, at D's suggestion.
- **1c stays PASS at the reviewed head.** `649248a` changes two test names and a commit message, not behaviour, so
  D's verdict carries — **but A pins whichever head actually goes into the PR.**

- **F-SEC-1 verified by A at `f412d10` — the INSTALLED build — not relayed from C.** `dismiss` (`:55`) and
  `signOutAll` (`:71`), both `busy` state, `signOutAll` closing over `[busy]`; two presses in one tick both read
  false and `signOutAllDevices()` runs twice. So the defect is on the owner's phone today, not only on a branch.
  A recorded C's boundary as not established and did not upgrade it. **A's statement of the stakes, worth putting
  to the owner as a potential and not a claim:** if the second call does render "sign out failed" after a
  successful sign-out, that is the worst truthfulness defect of the sprint — telling someone their
  sign-out-everywhere failed when it succeeded, on the screen whose whole job is to tell them their account
  security changed. **Unverified. Nothing authorised, nothing started.** Fix site is likely the hook, but
  `src/lib/auth/signOut.ts` is on the gated surface, so anything near it routes through A.
- **Count reconciliation (A says four, C said five — both right about different things).** The **state-guard
  shape** has **four** instances: F-DESTRUCT-1 (my-listings, fixed Batch 1), F-AVATAR-2 (edit-profile, 1b),
  F-AVATAR-3 (profile tab, 1c), F-SEC-1 (security notices, unfixed). The broader *"fixed here, still live in its
  twin"* pattern has **six**: F-BIDS-1 → F-HOME-1 · the Home `view()` conflation → three more helpers · F-AVATAR-1
  → F-AVATAR-2 · F-XFER-1 → F-XFER-2 · F-AVATAR-2 → F-AVATAR-3 · F-AVATAR-3 → F-SEC-1. Quoting one number for the
  other is how a tally stops meaning anything.
- **A's tally of harnesses flattering the code, all four in the SAFE-LOOKING direction:** Home's `view()` naming a
  state for an empty tree · place-bid's `view()` reporting the form for an empty tree · the press helpers honouring
  `disabled` and never reaching the guard · a re-render handing C's probe a fresh closure. **A's rule, matching
  C's and D's:** a same-tick probe calls the handler directly, twice, with no re-read between the calls, or it
  tests the harness. **"You caught it because it felt too easy; that instinct is the control that has no test."**
- **1c at `649248a`:** A's diff vs `2567401` is the one test file (11/5), no behaviour change; A's gates 114 / 2317,
  typecheck 0, lint 0 / 29. **PR #73 re-pointed, head `649248a`, all nine checks pass.**

## F-SEC-1 — security-notice action lock (C, 2026-09-17). `frontend/batch1d-security-notice-lock @ 39bc41c`
Owner authorised it as a security-focused follow-up with five evidence items named. **Cut onto the gate
`6561d1f`, NOT onto the 1c head** — A's correction, D's argument: a security fix should be takeable without the
three UI batches, in either order or ahead of them. Verified: `6561d1f` is an ancestor, `2fe7abd` is not.

**The defect in one line: the hook locked its read and left its writes open.** `load()` already guarded with a
`useRef` (`inFlight`, released in a `finally`); `dismiss` and `signOutAll` guarded with `if (busy) return;` over
React state, so two presses in one event loop both read false. A verified it in **`f412d10`, the installed build**.

**Fix:** one `actionInFlight` ref for BOTH actions, distinct from `inFlight`, with a **single acquire and single
release** — both actions run through one `runExclusive` helper, so there is one acquire site and one release site
for the pair, not one per handler. That is what makes "released exactly once" structural.
**ONE ref, not two — D's mechanism ruling, adopted over C's weaker preservation argument:** `busy` is a single
state driving both controls, so separate refs would let whichever action finished first clear it **while the other
was still running** — F-AVATAR-1 reintroduced inside the fix for its own descendant. Two refs would require
splitting `busy`, which is a UI change nobody authorised. **SM3 mutates to two refs and kills S8**, so the
decision has a control rather than only prose.

**Evidence, the owner's five:** S1/S4 capture one handler reference and call it twice with **no re-read between
calls** · S1 counts `signOutAllDevices` **invocations, not navigations** (A's point: the defect was two calls with
ONE navigation, so a navigation assertion passes on the bug) · S3 a failed sign-out releases the guard, reports it,
does not navigate, and a later press works · S5/S6 a completed and a failed dismiss both leave the control usable ·
**SM1 removes the lock and kills S1, S2, S4 and S8** — one more than C predicted, since without it dismiss can also
start during a sign-out. SM2 (never release) kills S3 and S6.

**Exact diff vs `6561d1f`: three files, +273/-17** — `src/hooks/useSecurityNotices.ts` (+43/-17), the new
behavioural suite (the hook had none; `tests/security-notice.test.ts` greps source), and that contract test, whose
`setError(null)` pin C **followed to its new single site inside `runExclusive`** rather than dropping, adding
assertions the old shape could not express (both actions go through `runExclusive`; the lock is `actionInFlight`).
**Zero lines on `src/lib/auth/signOut.ts`, payments, checkout, `supabase/`, `scripts/`, `.github/`.**
**Gates:** vitest **2258 passed / 107 files** (the gate base, not the batch base); tsc clean; lint 0 errors / 29
warnings. No production read, no deployment, no build; server behaviour, session policy, Build 19 and Line 3
untouched.

**REMAINING UNCERTAINTY, reported because the owner asked for it by name and because a fix must not imply an
answer it did not produce:** whether a second `signOutAllDevices()` would surface **"sign out failed" over a
successful sign-out** is **UNRESOLVED**. The probe that found the defect used a mock that forced the second call
to fail; that outcome was never observed against a real session. After this fix there is no second call, so the
question is moot in practice — **but it was never settled, and this fix does not settle it.**

- **D's F-SEC-1 verdict: PASS at `39bc41c`** — mechanism and controls, the half the owner assigned. D's own runs:
  vitest 2258 / 107, tsc 0, gated surface zero including `signOut.ts`; standalone confirmed (`2fe7abd` not an
  ancestor). D verified each of the owner's five requirements rather than reading them, and **wrote the two-refs
  mutant itself rather than taking C's**: SM3 kills S8 alone. D's note: *"one ref, not two" is now pinned by a test
  instead of resting on my argument in a commit message — I would not have insisted on it if it had stayed prose.*
  D also judged `runExclusive` better than what it specified (one release site **for the pair**, so the two-refs
  drift is impossible by shape rather than by convention) and confirmed the contract pin was **widened, not
  weakened**, by checking the two removed lines could no longer be true at the old site.
- **F-SEC-2 (NEW, PRE-EXISTING — D found it, C verified it; NOT introduced by F-SEC-1 and NOT in its scope).**
  Neither the old code nor `runExclusive` catches a **thrown** error — only the `error` field a call returns. C
  confirmed the consumer: `src/components/SecurityNoticeBanner.tsx:43,45` passes the async handlers straight to
  `onPress`, so a network throw from the RPC or the SDK becomes an unhandled rejection with **no message to the
  user** — the same "silent tap" class that DISMISS_FAILED_COPY was written to end. The `finally` still releases
  the lock and clears `busy`, so nothing jams. **Identical before and after the fix**, which is why D recorded it
  rather than folding it in: so it is not later mistaken for something this batch introduced. Owner's call.

- **A's gated auth review: PASS.** Tripwire clean — zero lines across `signOut.ts`, payments, checkout,
  `supabase/`, `scripts/`, `.github/`, `app.json`, `package.json`. A's gates at `39bc41c` match C's exactly
  (107 files / 2258 tests, tsc 0, lint 0/29; the lower totals are correct for a branch off the gate).
  **PR #74 open standalone against the gate, all nine checks green.** A confirmed the contract pin was followed
  to its new home rather than deleted, which is "the thing most people get wrong in a refactor".
- **F-SEC-1-A (A's finding) — CLOSED at `016d8e2`.** The suite pinned that the acquire and release *exist* inside
  `runExclusive`, not that the release is **unique** — and "released exactly once" is the property the owner's
  evidence list asks for. A counted and it held today, but a later edit adding a second release on a success path
  would have passed every assertion. The source contract now counts occurrences: exactly one acquire, one release,
  one `setBusy(true)`, one `setBusy(false)`. **Verified by mutant, not asserted:** C wrote A's exact scenario — a
  second release on the dismiss success path — and it was GREEN before the change and fails after. Gates after:
  2258 / 107, tsc clean, lint 0/29.
- **Credit correction C volunteered:** S1 counts invocations rather than navigations because C's own probe had
  already shown two calls with one navigation — the shape was in front of C, not deduced. The version of that trap
  C did *not* catch alone is the one D found twice, where the harness hides the layer.

- **D's retraction of its own 1c advice, in D's words, and the generalisable line from it.** In 1c D told C that a
  single release site made a double clear *"impossible by construction… a stronger guarantee than any assertion
  could give you"*, and told C not to chase it. D now withdraws that: **impossible-by-construction is true of the
  construction that exists; it is not a guarantee about the next edit.** D proved it by writing the mutant (a
  second release on the success path) and watching all 14 tests pass. **C's original instinct — that "cleared
  exactly once" was thin — was right, and D talked C out of it with a tidy-sounding argument.**
  *A structural guarantee and a pinned guarantee are different things, and "impossible by construction" is a
  statement in the present tense.*
  **Already closed in F-SEC-1 at `016d8e2` before D's message arrived — and the extension mattered.** D ran both
  mutants at the new head and reported the result against its own proposal: **SM4** (a second ref release) fails;
  **SM5** (a second `setBusy(false)`, ref untouched) **also fails — and D's proposed one-liner, which counted only
  the ref release, would have walked straight past SM5**, while the control opened mid-operation. D asked that the
  record say so rather than credit its line. Counting all four — both acquires, both releases — is what holds.
- **F-SEC-1-B (NEW, recorded, NOT fixed): the identical uniqueness gap exists in 1b and 1c.** C verified at
  `frontend/batch1c-profile-avatar`: `app/settings/edit-profile.tsx` and `app/(tabs)/profile.tsx` each have
  **exactly one** `…InFlight.current = false` — true today, and **pinned by nothing**; neither suite counts
  occurrences. `app/my-listings.tsx` needs a **different property, not just a different regex** — D's correction,
  and it matters more than the sweep miss: its lock is **keyed by listing id**, so `endDestructive` having two call
  sites (one per handler, both in `finally`) is **correct**, not a double release. A uniqueness count there reads
  zero (a false clean) and, if someone 'fixed' it, would enforce the wrong rule on a file that is already right.
  **The property for that file is "released on every path", not "the release is unique."** Written down now so
  whoever picks F-SEC-1-B up does not correct correct code.
  **Not being folded in.** 1b and 1c are passed with PRs open, and quietly widening a reviewed batch is what C and
  D have both refused to do all day — D recommended the same. **Owner's to schedule**, and it is a test-hardening
  item, not a defect: every one of those locks releases correctly today.

## F-SEC-2 — a thrown security action says so (C, 2026-09-18). `frontend/batch1e-security-notice-throws @ 3b9dc9d`
Owner authorised it as a standalone security-surface fix with five tests named. **Base: `016d8e2`, the F-SEC-1
head — not the gate.** C's scoping call, flagged to A rather than taken silently: the instruction is to *preserve*
the shared same-tick lock, and that lock exists only on the F-SEC-1 branch, so "standalone" can only mean
standalone from the UI batches. Verified independent of 1/1b/1c (`2fe7abd` not an ancestor). **1e requires 1d;
sequencing is A's.**

**The defect:** only the `error` field a call RETURNS was handled. A rejection — the session read or SecureStore
work under `performSignOut`, or the RPC — propagated out of a handler `SecurityNoticeBanner.tsx:43,45` passes
straight to `onPress`, so it became an unhandled rejection and the screen said nothing. The lock released and
`busy` cleared, so nothing jammed: the user tapped a security action and was told nothing — the silent tap
`DISMISS_FAILED_COPY` exists to prevent. **Pre-existing; identical before and after F-SEC-1**, which is why D
recorded it rather than folding it in.

**Fix:** `runExclusive` takes the caller's **existing** failure copy and catches, so the throw path joins the
returned-error path at the one site that already owns the lock. **No new strings**, no change to sign-out policy,
session semantics or `signOut.ts`. The lock still releases in the same single `finally` on every path.

**Tests (6) and controls (5/5 as predicted — the first clean sweep of the sequence):** T1 thrown sign-out shows
`SIGN_OUT_FAILED_COPY`, no navigation · T2 thrown dismiss shows `DISMISS_FAILED_COPY`, notice stays · T3 the lock
releases after each · T4 a retry works and clears the old message · T5 same-tick double invocation still one
action · T6 a throw in one action does not strand the other. **TM1** removes the catch (the shipped defect) ·
**TM2** catches silently · **TM3** rethrows after reporting so the rejection escapes again · **TM4** crosses the
two copies, kills T2 alone · **TM5** skips the release on the throw path.

**Exact diff vs `016d8e2`: two files, +221/−4** (hook +23/−4, new suite). **Zero lines** vs the gate on
`signOut.ts`, payments, checkout, `supabase/`, `scripts/`, `.github/`. **Gates:** vitest **2264 / 108**, tsc
clean, lint 0 errors / 29 warnings. No merge, deploy or build.

**Two limits C stated rather than let pass as coverage:**
- **The "no unhandled rejection" assertion is indirect.** The tests assert the handler's promise RESOLVES — the
  same property, stated so the suite can check it — not that nothing reaches the process's rejection handler.
- **The copy choice is a judgement, not a derivation. A throw is an UNKNOWN outcome, not a known failure.** If a
  rejection lands after the session actually ended, "Couldn't sign out" asserts a failure that did not happen. The
  returned-error path has always had that property, so reusing its copy keeps the two consistent instead of
  inventing a third state — but nothing here establishes which side of that line a real throw falls on. Same shape
  as F-SEC-1's open question, and kept out of the fix's claims.

- **F-SEC-2-A (A's finding, on C's own fix) — FIXED at `a6a8323`.** The catch C added in F-SEC-2 spanned the whole
  action, **including the `router.replace` that runs AFTER a successful sign-out**, so a throw there showed
  "Couldn't sign out" for an action that completed — every session and push binding really ended and the screen
  said the opposite about the user's account security. **C introduced it; the catch was right, its scope was not.**
  The navigation is now guarded separately and logged; C verified it is belt-and-braces anyway (the global auth
  listener in `app/_layout.tsx` + `useAuth` routes on sign-out).
  **The principle, the mirror of the one this sprint enforces everywhere:** *a throw is an unknown outcome only
  while the outcome is unknown; past the success line it is known, and no failure may be asserted over it* — the
  same rule as never asserting success before confirmation. **T7** pins it; **TM6** (navigation back inside the
  outer catch — A's exact scenario) kills T7. **TM7 survives and is recorded, not hidden:** an over-correcting nav
  guard that cleared a real failure passes, because that guard only ever runs after success, so no test can
  distinguish it. Gates at `a6a8323`: vitest **2265 / 108**, tsc clean, lint 0/29.
- **D's ruling on C's "indirect assertion" worry: it is NOT indirect, and D told C not to close the gap.**
  `onPress={handler}` discards the promise, so "an unhandled rejection" IS "that discarded promise rejected" —
  asserting it resolves asserts the cause, not a proxy. It holds because the action path is one fully-awaited
  chain with no floating promises, which D checked rather than assumed. D also advised AGAINST a
  `process.on('unhandledRejection')` spy in the suite: it couples to the runner, is order-dependent under parallel
  files, and cannot attribute a late rejection to the test that caused it.
- **F-SEC-3 (NEW — D's lead from the same file, and C PROBED it rather than leaving it unverified).**
  `useSecurityNotices.ts:50-51` calls `void load()` twice (mount and the AppState listener) and `load()` (`:29-43`)
  has `try`/`finally` with **no catch** — so a throwing `get_my_security_notices`, or a throw out of
  `parseSecurityNotices`/`selectActionableNotice` inside that try, rejects a discarded promise. **C's probe:
  exactly ONE unhandled rejection, observed.** *(The probe used the `process.on('unhandledRejection')` instrument
  D rejected for a permanent test — legitimate for a throwaway probe, not for a suite fixture.)*
  **Stakes, stated accurately rather than inflated:** the read path already intends to fail quietly (its own
  comment says so) and `finally` still clears `inFlight`, so the user-facing outcome is unchanged — no notice
  shown, nothing jams. What differs is mechanism: a handled quiet failure versus an unhandled rejection that
  surfaces as a warning or in crash reporting. **Outside F-SEC-2's authorisation; recorded, nothing started.**
  **Sixth time a fix's twin was sitting in the same file.**
- **D's ruling on the copy, adopted, with the part worth writing down:** keep the existing message, and record that
  **the fix changes the character of the over-claim rather than creating it** — *silent-and-possibly-wrong became
  visible-and-possibly-wrong.* Still the right trade, because a security action that says nothing is worse. If a
  third state is ever wanted ("we couldn't tell whether that worked"), it is a copy decision for the owner, not a
  bug fix.

- **F-SEC-2 CLOSED at `a6a8323`: A PASS (gated auth) and D PASS (mechanism/controls).** A verified C's
  belt-and-braces claim itself — `onAuthStateChange` at `app/_layout.tsx:86` and `src/hooks/useAuth.ts:127` — so
  swallowing the navigation throw *degrades to a log, not to a dead end*. A's gates match C's (108 / 2265, tsc 0,
  lint 0/29, gated surface zero). **TM7 stands in the record as a limit of the suite, not as coverage** — A: *a
  suite that cannot see something should say so in its own words rather than leave the gap for whoever edits next.*
- **The rule, now with both halves, stated once (A's formulation):** *no failure is asserted before confirmation,
  exactly as no success is.* This sprint enforced the second half everywhere — transfers, Home, Bids, checkout.
  **F-SEC-2-A was the first time the first half broke, and it broke inside a fix rather than in the original
  defect.** The boundary is the success line.
- **F-SEC-3 filed by A, credited as D's lead and C's probe**, with C's characterisation kept: lower stakes,
  because the read path fails quietly by design (a missing RPC reads as "no notices"; other failures retry on the
  next foreground), so the difference is **mechanism, not user-facing outcome**. Nothing started.

### Where the sprint stands (C, 2026-09-18) — five branches, all reviewed, none merged
| Branch | Head | Contents | Reviews | PR |
|---|---|---|---|---|
| `frontend/batch1-state-correctness` | `2fe7abd` | F-BID-1, F-HOME-1, F-AVATAR-1, F-DESTRUCT-1, F-XFER-1 client half | D PASS, A PASS | #72 (draft) |
| `frontend/batch1b-twin-screens` | `0ca71ff` | F-XFER-2 (+2-A), F-AVATAR-2 | D PASS, A PASS | #72 |
| `frontend/batch1c-profile-avatar` | `649248a` | F-AVATAR-3 | D PASS, A PASS | #73 (draft, 9/9 green) |
| `frontend/batch1d-security-notice-lock` | `016d8e2` | F-SEC-1 (+1-A) | D PASS, A PASS | #74 (standalone off the gate, 9/9 green) |
| `frontend/batch1e-security-notice-throws` | `f3cff27` | F-SEC-2 (+2-A) | D PASS, A PASS | **none — owner's PR authorisation named 1/1b/1c only** |
**Sequencing:** 1b requires 1, 1c requires 1b, 1e requires 1d; 1d is independent of all UI batches.
**Open for the owner:** F-SEC-1-B (test hardening, 1b/1c, with a different property needed for `my-listings`) ·
F-SEC-3 · the "third state" copy question on throw outcomes · **device verification — nothing in any of these five
branches has run on a handset** · B's design proposals and the shared-primitives ownership decision.

- **TM7 PROVED equivalent by D, not conceded — and the proof is now in the code (`f3cff27`, comment only, gates
  unchanged).** D wrote the mutant itself and showed no input can distinguish it: `runExclusive` clears `error`
  each cycle, and the only earlier `setError` in the sign-out action is on the `!out.signedOut` branch, which
  **returns** — so `error` is necessarily null when the nav guard runs and clearing it is a no-op. **D's note,
  worth keeping: this is the first "survives by design" claim of the sprint that held up to being attacked, and D
  is the one who insisted they all be attacked.**
  **The caveat is why it went into the source and not just here:** equivalence is a property of the code as it
  stands. If that failure branch ever falls through, or anything sets an error on the success path, the same line
  becomes an over-correcting guard that erases a genuine failure on a security surface — the present-tense trap D
  named in 1c, now applied to the thing D had just proved safe.
- **D withdrew the general form of its `unhandledRejection` objection**, keeping it scoped to a permanent suite
  fixture (runner coupling, ordering, attribution) and agreeing those costs do not apply to a one-file throwaway
  probe where the direct observation is the point. D: *"I'd rather be corrected on the scope of my own argument
  than have you work around it."*
- **The count as it ended: seven instances of the same shape, and the seventh came out of a correction rather than
  the original code.** A found a defect C's fix introduced (F-SEC-2-A); the fix for that carries a mutant that is
  provably harmless today and conditionally harmful later. Every layer of correction was its own surface. All
  seven were found — and it is the reason **none of these five branches should land before the device
  verification nobody has run.**

- **1e re-pinned: D PASS at `f3cff27`.** D verified the diff is comment-only (five added lines, no deletions, no
  code) and **deliberately did not re-run the suite**, saying so: *comments cannot change behaviour, so the diff
  is the verification, and "gates identical" should mean someone checked WHY they are identical rather than that
  they ran the numbers again out of ritual.*
- **THE CLOSING CAVEAT ON ALL FIVE BRANCHES, in D's words, and the most important sentence in this record:**
  *"My verdicts say the tests discriminate and the mechanisms are right; not one of them says the app behaves
  correctly on a handset. Those are different claims, and the distance between them is exactly what this sequence
  has been demonstrating."* Five branches of state-correctness work, **every one verified in tests and source
  only**. Seven instances of the same defect shape were found — the seventh produced by a correction rather than
  by the original code — which is not an argument against correcting, since all seven were found, but is the
  reason **nothing here should land without device verification that nobody has done.**
