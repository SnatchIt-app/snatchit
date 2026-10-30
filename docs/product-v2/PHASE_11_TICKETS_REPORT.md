# Phase 11 — Tickets ownership UI

**Session:** Front End · **Date:** 2026-09-04
**Branch:** `frontend/v2-phase11-tickets` (from the V2 closeout).
**Status: OWNER-APPROVED on physical iPhone (2026-09-04) and checkpointed.** No push, no PR.
Frontend-only; no Core-owned file touched.

## 1. Frontend base SHA
`5df53768637bfb161b531d69664fc95c1c8df083` — `chore(frontend-v2): close out mobile redesign`
(branch `frontend/v2-closeout`).

## 2. Core Tickets handoff reference
`docs/product-v2/TICKETS_FRONTEND_CONTRACT_HANDOFF.md`, Core branch `core/tickets-owner-read` @
`6dc3ee0` (migration 110, `public.get_my_tickets()`). Treated as authoritative.

## 3. Branch
`frontend/v2-phase11-tickets`, cut from `5df5376`. No rebase, no force-push, uncommitted.

## 4. Files changed
New:
- `app/(tabs)/tickets.tsx` — the Your Tickets screen.
- `src/components/tickets/TicketEventGroup.tsx` — the event-first card (upcoming hero / past row).
- `src/lib/tickets/types.ts` — the contract types (mirror of the handoff).
- `src/lib/tickets/ticketState.ts` — pure mappers (vocab, quantity, date, sectioning, error class).
- `src/lib/tickets/api.ts` — the single typed RPC wrapper.
- `src/lib/tickets/fixtures.ts` — `__DEV__`-only sample data for device review.
- `tests/tickets.test.ts` — 18 assertions (mappers + shipped-source guards).

Modified (minimal nav activation + test truth):
- `app/(tabs)/_layout.tsx` — register `Tabs.Screen name="tickets"` between Bids and Profile.
- `src/components/nav/AdaptiveDock.tsx` — `navItems({ tickets: true })` (data flip only).
- `src/lib/nav/navItems.ts` — add `tickets` to `COLLAPSING_ROUTES`.
- `tests/adaptive-nav.test.ts` — 3 assertions updated from the deliberately-held four-item state to
  the now-approved five-item state (still guarding: no coming-soon, no `kernel.tickets`, Search not
  primary, ownership icon).

## 5. RPC integration
`src/lib/tickets/api.ts` → `supabase.rpc('get_my_tickets')`. No arguments, no `.select()`, no filters.
`[]` returns as a success. Errors are normalized to `{ code, message }` and never shown raw.

## 6. Local TypeScript shape
`MyTicketGroup` in `src/lib/tickets/types.ts` mirrors the handoff exactly (event-first group row;
`ownership_status`, `fulfillment_status`, `time_class` unions). The supabase client is not
parameterized with generated Database types (repo convention), so the SETOF result is cast locally to
`MyTicketGroup[]` in the wrapper — no Core/schema type file is regenerated or touched.

## 7. Authorization / error handling
The RPC is owner-scoped on the server (no user argument). Client-side, `classifyTicketsError` maps
SQLSTATE `42501` (anon) and `28000` (`tickets_unauthenticated`) to an **auth** failure →
`router.replace('/(auth)/login')`; any other error is a **retry** state. The raw SQLSTATE / token is
never rendered.

## 8. Empty behaviour
A successful `[]` renders the `EmptyState`: "No tickets yet" / "Tickets you own will show up here." It
is never treated as an error, and never mentions backend flags or issuance.

## 9. Information architecture
Two sections from the server's own `time_class`: **Upcoming** then **Past**, in a single `SectionList`.
Bids and Tickets stay separate: no bid data, no transfer state machine, no marketplace activity here —
only owned tickets.

## 10. Upcoming treatment
The loud, ownership-forward state: an artwork-led card (`EventMedia` `TICKET_ART`, full-bleed), event
title (`title` token — user-generated names are never uppercased), date+venue, then the distinct
ticket rows (type × quantity + status badges).

## 11. Past treatment
A quieter row layout: a small `SEARCH_RESULT` thumbnail, muted text, reduced emphasis. Includes
`used` / `expired` / `void` — none hidden; the ownership badge tells the truth. No attendance or
social/memory language is invented.

## 12. Grouping behaviour
`groupByEvent` collapses the flat contract rows into per-session cards **without destroying any state
distinction**: a "2 held + 1 listed" holding shows two clear rows under one event, never a merged
number. First-appearance order is preserved, so the server's Upcoming-soonest / Past-most-recent
ordering is untouched.

## 13. Ownership state treatment
Exact Core vocabulary → labels/tones: `valid`→"Valid"/success, `used`→"Used"/neutral,
`void`→"Void"/danger, `expired`→"Expired"/neutral. Every state carries a word (never color-only).

## 14. Fulfillment treatment
`held`→"Owned" (no badge — it is the ordinary owned state), `listed`→"Listed for resale"/neutral,
`in_transfer`→"Transfer in progress"/neutral, `payment_hold`→"Payment hold"/warning,
`disputed`→"Disputed"/danger. Projected overlay only — `public.transfers` is never reverse-engineered.

## 15. Artwork / media handling
`artwork_ref` (opaque storage path) is passed to `EventMedia` as
`{ path, bucket: 'event-media', contract: 'v2' }` (the `TICKET_ART` / `SEARCH_RESULT` slots). No URL is
ever built by hand; `null` renders the standard branded fallback plate.

## 16. Five-item nav activation
`navItems({ tickets: true })` returns the approved order **Home · Create · Bids · Tickets · Profile**;
the tab route is registered in `(tabs)/_layout.tsx`. Search stays inside Home (never a primary tab).
The reserved ownership icon `ticket.fill` is used — no scanner/QR glyph.

## 17. Adaptive dock integration
No dock geometry changed — only the data set was flipped to five items (the dock was always built for
five). Tickets joins the shared `COLLAPSING_ROUTES` and wires the standard `useDockScroll('tickets')` +
`useDockClearance()`; there is no bespoke Tickets dock code. Dock size, vertical position, radius,
glass, animation, thresholds, selected capsule, and safe-area geometry are byte-for-byte unchanged.

## 18. Accessibility
Each card exposes a combined screen-reader label (event title, date, venue, then each row's type ×
quantity + ownership + fulfillment). Section headers carry `accessibilityRole="header"`; the screen
title too. State is always a word, never color-only. Tab semantics come from the existing dock
(`accessibilityState={{ selected }}`).

## 19. Dev fixtures used
`src/lib/tickets/fixtures.ts` (`DEV_TICKET_FIXTURES`) covers every ownership × fulfillment × time_class
combination plus a long title and null artwork. Gated behind `__DEV__` and an in-screen "DEV" toggle
that is **off by default**; real RPC data always takes precedence, and nothing is ever written to any
server. The toggle is not rendered in production builds.

## 20. Tests
`tests/tickets.test.ts` (18) — exhaustive ownership/fulfillment vocab, quantity singular/plural, error
classification (42501/28000 → auth, else retry), `splitByTimeClass`, `groupByEvent` (distinct states
stay distinct; server order preserved), date label; shipped-source guards (exact RPC, no owner
argument, no `.select` chaining, no `kernel.tickets`, no price, no QR/barcode/Wallet, no Ticket-Detail
navigation, no hand-built URL, five-item nav, Search absent, ownership icon). `tests/adaptive-nav.test.ts`
updated to the five-item truth. **Full suite: 586 passed / 24 files** (was 568 / 23).

## 21. Typecheck
`tsc --noEmit` clean (exit 0).

## 22. Lint
`expo lint`: 27 problems, 0 errors, **27 warnings** — identical to baseline. **No new warnings.**

## 23. Native iOS bundle
`platform=ios` bundle: **HTTP 200, ~14.6 MB**, contains `get_my_tickets`, `TicketEventGroup`, and the
"Your tickets" title; no unresolved-import/error banner.

## 24. Physical-device status
**Physical iPhone runtime verified: YES. Owner visual review: APPROVED (2026-09-04). Phase 11 status:
APPROVED.** Jose reviewed the Tickets tab on a physical iPhone — five-item dock and Tickets selected
state, adaptive collapse on Tickets, the real empty state, and the Upcoming / Past populated fixtures
(including multi-state single event, long title, no artwork, quantity 1 vs many, and the full status
set) — and approved the implementation.

## 25. QR / barcode intentionally absent
None built (Core status BLOCKED). No QR, barcode, scanner, show-code, entry pass, rotating code, or
offline credential exists anywhere in the Tickets surface (guarded by test).

## 26. Apple Wallet intentionally absent
None built (Core status BLOCKED). No "Add to Wallet", PassKit button, or pass placeholder (guarded by
test).

## 27. Ticket Detail intentionally absent
No detail route. Cards do **not** navigate — there is no truthful next action yet (per Core, per-atom
Ticket Detail needs a future contract). No `ticket_id` is invented; `event_session_id` +
`ticket_type_id` are treated as implementation keys only and never shown.

## 28. Core deploy / data-population caveat
`public.get_my_tickets()` is authored but **not deployed** (production is through 092; 093–110 are
DARK), and native issuance is disabled, so the connected RPC legitimately returns `[]` for every user
today. The UI is built correctly against the live contract and shows the empty state until Core
deploys the train and enables issuance/mint. Populating data is a Core activation, not a frontend task.

## 29. Remaining blocker
- **Core:** deploy 093–110 and enable native issuance + mint so the RPC returns rows.
- **Future frontend (blocked on Core contracts):** Ticket Detail, QR/barcode, Apple Wallet — none in
  scope until Core ships their respective contracts.

## 30. Checkpoint record (owner-approved)
- **Owner approval:** APPROVED on physical iPhone, 2026-09-04.
- **Physical iPhone runtime verified:** YES.
- **Final verification at checkpoint:** 586 tests / 24 files passed; `tsc --noEmit` clean; `expo lint`
  27 problems / 0 errors / 27 warnings (no new warnings, identical to baseline); native iOS bundle
  HTTP 200.
- **Frozen (owner-approved):** five-item nav order and Tickets placement; Tickets selected state and
  dock integration; Tickets visual direction; Upcoming artwork-led and Past quieter presentations;
  event-first grouping; quantity presentation; ownership and fulfillment badges; empty and
  loading/error treatments; artwork fallback; no Ticket Detail / QR / Wallet; no price reconstruction.
  The AdaptiveDock geometry remains frozen.
- **Scope:** frontend only — no Core-owned file, no `kernel.tickets` client query, DEV fixtures
  `__DEV__`-only. Checkpoint commit SHA is recorded in the session completion response; the worktree
  is clean afterward except two pre-existing unrelated stray docs
  (`FRONTEND_V2_CHECKPOINT_REPORT.md`, `PHASE_3_CHECKPOINT_REPORT.md`) carried over from earlier
  phases, deliberately excluded.
