# Screen redesign matrix

**Status:** proposal, pending owner approval. Nothing here is built.
**Inputs:** `CURRENT_PRODUCT_AUDIT.md` (screen-by-screen evidence),
`PRODUCT_INFORMATION_ARCHITECTURE.md` (target structure), `DESIGN_SYSTEM_V2.md` (tokens and
components), `EVENT_MEDIA_SYSTEM.md` (image slots).

Classification vocabulary: **KEEP** (no visual work), **REFINE** (token migration and spacing only),
**REDESIGN** (same job, new layout and hierarchy), **REBUILD** (the current structure is wrong),
**REMOVE**, **NEW**.

---

## 1. Consumer, mobile

| Screen | Class | V2 direction | Tier |
|---|---|---|---|
| Home feed | **REDESIGN** | Event-first feed. 4:5 discovery cards, two-up. Editorial rails: tonight, this weekend, selling fast. "Your next ticket" strip when one is within 48 hours. Search entry in the header. Direct and marketplace events sit in one feed, each row carrying provenance. | 1 |
| Explore / search | **REBUILD** | Currently a dead route. Becomes the real search surface over events, venues and artists, with date, neighborhood and price filters as square chips. | 1 |
| **Event page** | **NEW** | The hinge screen. Hero artwork, Oswald title, venue and date, then the unified inventory block: direct tiers first, marketplace below, each with a provenance badge. Sticky action bar carrying price and the primary action. | 1 |
| Listing detail | **REBUILD** | Becomes a *view within* the event page rather than a top-level destination. The current screen stacks up to five banner rows above the content and presents four identical grey specification cards. Its real job, "should I buy this specific ticket from this specific person", is a sheet on the event page. | 1 |
| Tier selection | **NEW** | Quantity per tier, live availability band (available, low, sold out), never an exact remaining count. Hold countdown starts here and stays visible. | 1 |
| Primary checkout | **NEW** | Direct purchase. Event artwork present, order summary, honest fee breakdown, hold timer, payment sheet. | 1 |
| Marketplace checkout | **REDESIGN** | Existing `CheckoutNative` retains its money math, which is correct and well factored. It gains the event image, which it currently shows at no point, and the shared checkout chrome. | 1 |
| Purchase confirmation | **REDESIGN** | One screen for both provenances. Confirms what was bought, when the ticket arrives, and routes to Tickets. | 1 |
| **Tickets** | **NEW** | Upcoming and past. Upcoming shows the credential. Offline tolerant. This destination does not exist today; purchased tickets currently appear only as a transfer status badge inside the Bids tab. | 1 |
| Bid entry | **REDESIGN** | Free-text amount entry, which the current stepper-only design lacks. Clear maximum-bid semantics and honest outbid messaging. | 3 |
| Bids list | **REDESIGN** | Loses its tab. Becomes "offers made" under Profile activity, plus a Home strip while bids are live. | 3 |
| Create listing | **REBUILD** | A 1,139-line single form with roughly fifteen required fields becomes a short stepped flow: pick the event from the catalog, set price or auction, confirm. Choosing a real event rather than typing venue text is what attaches resale inventory to the correct event page. | 3 |
| My listings | **REFINE** | Token migration. Fix the green ACTIVE badge, which is the only green in the product. | 3 |
| Transfer send | **REDESIGN** | The moment the promise is kept. Deserves state clarity and reassurance, not a form. | 3 |
| Transfer receive | **REDESIGN** | Currently the only `contain` image in the app, letterboxed. Becomes a confident hand-off confirmation. | 3 |
| Profile | **REFINE** | Splits buyer and seller identity. Replaces emoji with the icon system that is already installed and barely used. | 4 |
| Public seller profile | **REFINE** | Token migration. Five hardcoded reputation hexes fold into the palette. | 4 |
| Login / signup | **REDESIGN** | The first screen a user sees has no imagery and no value proposition. Becomes brand-led, and moves the account wall to *after* a user has seen events. | 2 |
| Settings hub and children | **REFINE** | Token migration. The deletion-pending banner recently added stays, restyled to the system. | 4 |
| Legal, privacy, support, blocked users, reports, payout redirects | **KEEP** | Correctly plain. Token migration only. | 4 |
| `(tabs)/index` redirect shim | **KEEP** | Correct and minimal. | — |

## 2. Venue and organizer, web

Every row is **NEW**. No organizer surface exists in the product.

| Screen | Tier | Note |
|---|---|---|
| Venue overview | 2 | Tonight and upcoming, sold counts, what needs attention. |
| Event list | 2 | Create, edit, publish, cancel. |
| Event editor: details | 2 | Title, sessions, doors. |
| Event editor: artwork | 2 | Single 4:5 upload with a focal-point picker. Optional landscape hero. |
| Event editor: tickets and pricing | 2 | Tiers, prices, visibility. |
| Event editor: inventory | 2 | Capacity, releases, presale windows. |
| Orders | 2 | Per event and venue-wide. |
| Attendees | Deferred | Parked behind the buyer-privacy gate; the RPCs raise unconditionally today. |
| Team | 2 | Grant and revoke the six venue roles. |
| Venue settings | 2 | Profile, address, payout destination. |
| Settlements | Deferred | Rail is dark and structurally empty. Hiding beats an empty page. |
| Promoter tools | Deferred | Rail is dark. |
| Door / scan | Deferred | Separate mobile surface, dark rail. |

## 3. Cross-cutting work

| Item | Class | Note |
|---|---|---|
| Token migration, all screens | **REFINE** | Black canvas, brand red, radius 0, red hairlines. Mechanical but touches everything. |
| Font loading | **NEW** | Oswald and Inter must actually load. Today the app loads none. |
| Icon system adoption | **REFINE** | The icon component exists and is bypassed in favor of emoji. |
| Image components | **NEW** | One `EventImage` with slot, focal point, scrim, skeleton, fallback and recycling key. |
| Empty, loading, error states | **REFINE** | More complete than typical already; needs system styling. |
| Provenance components | **NEW** | The direct and marketplace badges, used everywhere inventory appears. |

## 4. Counts

| Class | Count |
|---|---|
| KEEP | 9 |
| REFINE | 11 |
| REDESIGN | 10 |
| REBUILD | 4 |
| REMOVE | 1 |
| NEW (consumer) | 6 |
| NEW (venue) | 10 |
| NEW (cross-cutting) | 3 |

## 5. Sequencing rule

Nothing in Tier 3 or 4 should be rebuilt before the Tier 1 purchase journey is on the new system.
The marketplace screens work today; they are unattractive, not broken. The event page, tickets
surface and checkout are where the product either becomes venue-native or does not.
