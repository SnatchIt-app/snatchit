# Snatch It V3 — creative direction and implementation baseline (B, 2026-09-21)

**Phase:** reconnaissance and written baseline only. No production code, no HTML, no prototype, nothing committed,
built or deployed. This file is written but **deliberately left uncommitted**.

**Everything below labelled "source" was read today at the baseline commit.** Reference observations were taken from
live pages with computed styles, not from memory. Where a reference could not be inspected, that is stated.

---

## A · Verified product baseline

**Code reference.** Repository `snatchit`, branch **`release/candidate-20260918`**, commit **`ee4cc12c`**
(2026-09-21 22:50 −0400), read in A's integration worktree `/Users/josetascon/snatchit-converge`.
**`origin/main` is `eadd456a` (2026-09-01) and is *not* the baseline** — the candidate branch is three weeks ahead.

### Routes — 36 files under `app/`

| Group | Routes |
|---|---|
| Tabs (visible) | `home`, `create`, `bids`, `tickets`, `profile` |
| Tabs (hidden, `href: null`) | `index`, `explore` |
| Auth | `(auth)/login`, `signup`, `reset-password` |
| Listing & market | `listing/[id]`, `listing/edit/[id]`, `my-listings` |
| Money | `checkout/index`, `checkout/[id]`, `bid/[id]` |
| Transfers | `transfer/send/[id]`, `transfer/receive/[id]` |
| Account | `settings/{index,edit-profile,notifications,preferences,privacy,legal,support,blocked-users,verify-phone,payout-setup}`, `profile/[id]`, `payout-return`, `payout-refresh` |
| Other | `report/[type]/[id]`, `_dev/foundation` |

**Navigation truth.** The default tab bar is **already replaced** by `src/components/nav/AdaptiveDock.tsx` — a
floating, rounded, dark-translucent pill well above the bottom edge, with the active destination in a lighter inner
capsule, a global left-anchored collapse on scroll (220 ms, instant under reduce-motion), and a keyboard retreat.
Its own header records that *"true frosted BlurView needs expo-blur (not installed, deliberately not)"*, so the
shipped material is `rgba(18,18,20,0.72)`. Per-route collapse state lives in `dockContext.tsx` / `lib/nav/dockMachine`.

**A floating smoked dock is therefore not a V3 proposal — it is the shipping baseline.** V3 inherits it.

**Search** has no tab. `explore` is reachable only from Home's header button (`home.tsx:386` →
`router.push('/(tabs)/explore')`).

### The two data planes — the single most important structural fact

| | Live marketplace | Native plane |
|---|---|---|
| Tables | `public.listings`, `public.bids`, `public.transfers`, `public.payments`, `public.saved_listings` | `catalog.event`, `catalog.event_session`, `catalog.venue`, `catalog.resale_policy`, `catalog.platform_config`, `market.{auction,listing_native,market_sale,offer}`, `kernel.{tickets,ticket_ownership_log,wallet_pass,…}` |
| Event identity | **None.** A listing carries free-text `event_name`, `venue`, `event_date` (`000_baseline_schema.sql`) | Real `event_id` / `event_session_id` / `venue_id` with artwork refs |
| Reachable from the app | Yes — the client reads `public.*` and RPCs **only** (verified: zero `from('catalog.`/`market.`/`kernel.` in `src`/`app`) | Only through `public.get_my_tickets()` |
| State | Live | **Dark.** `catalog.platform_config` seeds `feature.native_issuance_enabled`, `native_scanning_enabled`, `native_resale_enabled`, `wallet.apple.enabled` all **`false`** (`078:1522`) |

### Ownership destinations — verified

- **Tickets tab = native ownership only.** It reads `public.get_my_tickets()` (owner-scoped, no arguments), grouped
  Upcoming / Past from the server's own `time_class`. Its header states: *"This is ownership, not marketplace
  activity: it is deliberately separate from Bids and never shows bid history"* and *"No Ticket Detail, no
  QR/barcode, no Apple Wallet, no price — none of those contracts exist yet."* The RPC returns columns for
  `event_id, event_session_id, event_title, session_label, starts_at, ends_at, doors_at, venue_id, venue_name,
  artwork_ref, ticket_type_id/name/kind, quantity, ownership_status, fulfillment_status, time_class`
  (`20260909000000:90-107`). **In production it returns the empty set** because issuance is off
  (`20260909000000:72-78`). A `__DEV__`-only fixture toggle exists for device review.
- **Marketplace purchases live on Bids.** `(tabs)/bids.tsx` merges `bids` with `transfers` where the user is the
  buyer — Buy Now purchases and completed auction wins — and purchase rows route to `/transfer/receive/[id]`
  (`:121, :186, :339`).
- So today: **a marketplace buyer's order is reachable only through Bids → Receive transfer.** Tickets cannot display
  it, and must not be made the destination for it.

### Design system in force

- **Tokens:** `src/theme/v2.ts` — canvas `#000000`, text primary `#FFFFFF`, `brand.red #FF1A1A`,
  `redPressed #CC0000`, `redSoft rgba(255,26,26,0.10)`, `warning #FFB020`, `error #FF4D4D` (deliberately a
  different red from brand), `radius { none: 0, pill: 9999 }`, 4 pt space scale, motion `instant 90 / swift 180 /
  settle 280`. Two notes matter: *"Black on red is a Snatch It signature"* and *"Radius 0 is the brand… every
  measured element on snatchitapp.com returned border-radius: 0px."*
- **Adoption:** 69 files import `theme/v2`; 9 still import the legacy theme. The app is mid-migration, screen by
  screen — V3 must be a **continuation of v2, not a third system.**
- **Typography:** `src/theme/typography.ts` — **display tokens are uppercase-only Oswald**, sub-1.0 designed leading
  with a `MIN_LINE_HEIGHT_RATIO 1.25` floor; body is Inter. Prices already use tabular figures (`:91-94`).
- **Fonts:** Oswald 700 + Inter 400/500/600/700, loaded from `@expo-google-fonts/*` subpath imports (deliberate — root
  imports would pull ~9 MB). Both **SIL Open Font License**, bundled locally, no network at runtime.
- **Logo — the real asset exists.** `brand/sn-logo-white.png` (used today by `AuthBrandMark.tsx` at ratio 1024/371
  through `expo-image`), plus `sn-logo-black.png`, `sn-logo-on-red.png`, 512 variants, `sn-app-icon-1024.png`, and
  vector `brand/sn-logo.svg` / `sn-logo-white.svg` (viewBox 1557×564, traced paths). **`react-native-svg` is not
  installed**, so the app consumes the PNG. Nothing needs to be redrawn.
- **Installed and usable:** `expo-image` 3.0.11, `expo-haptics` 15.0.8, `expo-font`, `react-native-safe-area-context`.
- **Installed but inert:** `react-native-reanimated` ~4.1.1 and `react-native-gesture-handler` ~2.28.0 — there is
  **no `babel.config.js` and no `metro.config.js`** in the repo, so no worklet has ever run. Current motion is RN
  `Animated`.
- **Not installed:** `expo-blur`, `expo-glass-effect`, `expo-linear-gradient`, `react-native-svg`.

### Status classification

| Class | Contents |
|---|---|
| **Implemented and merged** (on `ee4cc12c`) | AdaptiveDock + per-route collapse · Tickets on `get_my_tickets` with quiet refresh · Bids merging bids + purchases · C's Premium batches: pending labels, single-flight locks, meaningful haptics, reduce-motion, tabular countdowns, one dollar formatter (CFT-201–208) · checkout honest hold loss, Pay gating, payment reconciliation, price-change acceptance, refund states, two-step progress copy (CFT-202/203/306) · transfer wording separating the seller's claim from the buyer's possession (CFT-402/404) · listing opens with the tapped card's content already on screen (CFT-101) · content kept on screen through refresh and realtime inserts (CFT-103/107) · branded plate fallback for failed images (CFT-106) · back gestures that ask before discarding work (CFT-204/208) · seller proceeds labelled for the whole listing (CFT-609, owner ruling) |
| **Reviewed, pending integration** | **#84** transfer screens: neutral deadline copy, no "not found" from a failed read, no payout claim without a payout (`transfer/*`, `transferState.ts`, 4 test files) · **#81** checkout escrow line hidden while payment or reservation status is unknown (`holdState.ts`, `CheckoutNative.tsx`) · #70 pre-mint checkout group claim · #64 webhook/checkout edge coupling · #63 refund exactness · #83/#87 payout fairness · #82/#85/#86 ops. **All are marked review/CI-only.** |
| **Deployed / phone-verified** | Not established by me. Production was last recorded at ledger 135 (2026-09-12); the native plane is flag-dark. **I did no production read and no device check.** Anything below that depends on deployed or handset state is marked as such. |
| **Proposed or unsupported** | Canonical marketplace events · market statistics · friends / attendance / social proof · ticket detail, QR, Wallet · Make an Offer on the live plane · blur materials · worklet-driven motion |

### The five verification asks — answered

1. **Does Tickets include marketplace purchases, native tickets, or both?** **Native only**, and empty in production.
   Marketplace purchases are on Bids.
2. **How does Bids expose purchases and transfer states?** It merges `transfers` (as buyer) into the bid list; the
   transfer's lifecycle drives the badge; purchase rows route to Receive transfer.
3. **Does a canonical event group multiple listings?** **No, not on the live plane.** `catalog.event` exists but is
   dark and unreferenced by `public.listings`. Event-level grouping is a new capability.
4. **Do friends / attendance / saves / social visibility have working contracts?** **Saves:** `public.saved_listings`
   exists but has **no mobile UI** (zero references in `src`/`app`). **Friends, attendance, follows, RSVP:** no tables
   at all. Social proof cannot be shown truthfully today.
5. **Are lowest ask, highest bid, last sale and inventory counts available?** **Per listing, yes:** `ticket_type`
   (GA/VIP), `quantity`, `starting_bid`, `buy_now_price`, `current_bid`, `bid_count`. **Across an event, no** — there
   is no event to aggregate over. Lowest ask, last sale and inventory count are new capabilities.

### Two corrections to my own earlier records

1. **`catalog.platform_config` is a real versioned config table** (key, version, value, visibility; `078:1520+`). My
   delivery-preferences handoff (§7) said no runtime-config mechanism exists in the chain. **That was wrong** and
   should be amended: staged enforcement can key off `catalog.platform_config` rather than shipping a migration per
   stage. I have not edited that file in this phase.
2. The same handoff described the dock and materials as proposals. The dock ships today; the translucent fallback is
   already the shipped material.

---

## B · Preservation matrix

For each surface: what must survive a presentation change, and where it lives.

| Surface | Must survive | Reference |
|---|---|---|
| **Dock / navigation** | Routing through the `tabBar` render prop; per-route collapse; keyboard retreat; reduce-motion instant; the active capsule is never a red frame | `AdaptiveDock.tsx`, `dockContext.tsx` |
| **Home / discovery** | Filter sheet behaviour and error handling; realtime inserts without losing scroll position; branded plate on image failure; quiet refresh | `home.tsx`, `FilterSheet`, CFT-103/106/107 |
| **Search (`explore`)** | Content stays on screen while refreshing; existing filter semantics; the Home-header entry point | CFT-103, `home.tsx:386` |
| **Listing detail** | Opens with the tapped card's content already on screen; server-mirrored auction price; live auction presentation within existing backend rules; per-ticket vs whole-listing price labels | CFT-101, CFT-501/502/504/505, CFT-609 |
| **Place bid** | "Submitting bid…", single-flight lock, "You're leading" **only after a fresh read**, bid increments, commitment copy | CFT-201/203/205/207, `PlaceBidScreen` |
| **Checkout** | All-in fee-inclusive pricing; honest hold loss; Pay gating and restoration only after server re-validation; payment reconciliation on unreachable; price-change acceptance; refund states incl. partial (F8); two named progress steps; one success haptic per purchase; tabular hold digits; **#81's hidden escrow line while status is unknown** | `CheckoutNative.tsx`, `checkout/*`, CFT-202/203/306, PR #81 |
| **Sell / create** | Every required field and guard; verified-phone gate (`038` + client); whole-listing proceeds label; draft-loss protection on back gestures | `CreateListingScreen.tsx:418`, CFT-204/609 |
| **Transfers** | The seller's claim and the buyer's possession never share a word; provider hand-off returns without implying anything; distinct `pending / seller_sent / buyer_confirmed / disputed / expired / auto_released / reversed`; **#84's neutral deadline copy, no "not found" from a failed read, no payout claim without a payout** | CFT-402/404, `transferState.ts`, `types/index.ts:223-230`, PR #84 |
| **Tickets / ownership** | Empty `[]` is success, not an error; auth failures route to sign-in, others retry; quiet reload keeps rows; server ordering and `time_class` grouping; **no fabricated QR, barcode, price or Wallet** | `tickets.tsx` header, `fetchMyTickets`, `ticketState.ts` |
| **Settings / account** | Every reachable function: profile, notifications, preferences (instant with rollback), privacy, legal, support, blocked users, verify phone, payout setup, report | `settings/*`, CFT-204 |
| **Cross-cutting** | Safe areas and dock clearance (`navInsets`); ≥44 pt targets; accessibility labels/roles/states; Dynamic Type with the display-scale cap; non-colour status cues; reduce-motion; disabled/pending/retry | `navInsets.ts`, `typography.ts`, CFT-206 |

---

## C · Recommended visual system

### Palette — with measured contrast

Canvas `#000000` stays. Graphite surface `#1A1A1C`. Off-white text `#F4F4F2`. Titanium `#C7C9CC`.

| Pair | Ratio |
|---|---|
| Off-white `#F4F4F2` on `#000000` | **19.07** |
| Titanium `#C7C9CC` on `#000000` | **12.66** |
| Secondary `#8A8D92` on `#000000` | **6.31** |
| Off-white on graphite `#1A1A1C` | **15.78** |
| Amber `#FFB020` on `#000000` | **11.48** |

**Red candidates** (all vs `#000000`, and as a fill carrying text):

| Candidate | On black | Black text on it | White text on it | Verdict |
|---|---|---|---|---|
| **`#FF1A1A` — current brand red** | 5.41 | **5.41 ✓** | 3.88 ✗ | **Recommended: keep** |
| `#FF3B30` iOS systemRed | 5.92 | 5.92 ✓ | 3.55 ✗ | Rejected — reads as a system default, costs identity |
| `#F5251C` | 5.16 | 5.16 ✓ | 4.07 ✗ | Viable alternative, marginally deeper |
| `#E4221A` | 4.54 | 4.54 ✓ | 4.62 ✓ | The crossover point — below this, black-on-red fails |
| `#D91F14` | 4.16 | 4.16 ✗ | 5.05 ✓ | Rejected — forces white text, loses the signature |

**Finding:** any red dark enough to carry white text is too dark to carry black text, and **black-on-red is the
recorded Snatch It signature**. So the red should not change. **My recommendation is to keep `#FF1A1A` and change
only where it is allowed to appear** — that is the actual problem, not the hue.

### Typography — evaluate before replacing

- **Keep Inter** as the utility voice. It is bundled, OFL, and already carries tabular figures.
- **The change I propose is to Oswald's role, not its presence.** Today every display token is **uppercase-only**,
  which produces the shouting the brief wants gone. Proposal: Oswald stays for the wordmark, section eyebrows and
  numeric emphasis, at **mixed case** and small sizes; it stops being the voice of every title.
- **Cultural/display voice — the one genuine typographic question.** All three references use a distinctive display
  face (Rumor: the serif `romie`; DICE: `Favorit`; POSH: `Haas Grotesk`). Snatch It has no equivalent. A licensed
  display face is the single highest-impact change available and the only one with a real cost. **Decision D-3.**
- **Numbers.** Rumor's own stack includes `DM Mono` and `diaSemiMono` — observed. I propose a **semi-mono numeric
  treatment** for prices, countdowns and dates: tabular Inter today (free, already there), with an optional mono face
  later. Countdowns are still not tabular everywhere (CFT-207 is `partial`).

### Geometry by role — a four-step scale

| Role | Radius | Why |
|---|---|---|
| Content, rows, price tables, sheets' content | **0** | The brand rule, and it is what POSH does (567 nodes at 0) |
| Media | **8** | DICE's exact value on square artwork; enough to read as a photograph, not a card |
| Floating chrome — dock, on-art controls, overlay sheets | **20–24** | Matches the shipping dock and Rumor's selective 24 px |
| Pills — avatars, status, filter chips | **9999** | Existing token |

This replaces "0 or pill only" with **0, 8, 20–24, pill**. It is a departure and needs approval (D-2).

### Materials and the shipping fallback

Glass is an **accent on chrome only**: the dock, on-art controls, the filter/search overlay, sheets. Content,
prices, breakdowns and long text sit on **opaque graphite**. No content-layer material treatment is proposed.

**Shipping fallback, honestly:** `expo-blur` is not installed and no build is authorised, so every "glass" surface
renders as the dock already does — `rgba(18,18,20,0.72)` over the canvas, with a 1 px light top edge. Real blur is a
build dependency, not a design decision, and nothing in V3 depends on it.

### Imagery, icons, motion

- **Imagery is the colour.** Artwork is cropped, never letterboxed. Two proportions only: **1:1** for compact rows
  and rails (DICE's discipline) and **4:5** for features (POSH's). One scrim ramp; the existing branded plate remains
  the failure state.
- **Icons:** keep the current set. No icon library is installed and none is needed.
- **Motion:** RN `Animated` with the existing `v2.motion` tokens — **not Reanimated**, which cannot run without a
  babel config. The shared-content listing open already exists (CFT-101) and is the one transition worth extending.
  Everything collapses under reduce-motion. Nothing animates a warning, a price, or a per-second tick.

### Departures from the locked direction — each needs approval

| # | Locked rule | V3 proposal | Rationale |
|---|---|---|---|
| **1** | Display type is uppercase-only Oswald | Mixed case; Oswald demoted to eyebrows, wordmark and numerals | The references are almost entirely mixed case (POSH: zero uppercase; Rumor: 3 of 482 nodes). All-caps at title size is the "loud" quality already objected to |
| **2** | `radius: 0 or pill only` | Add **8** for media and **20–24** for floating chrome | Already true in practice — the shipping dock uses a large radius. The rule and the code disagree |
| **3** | Red for primary actions, destructive actions and the brand mark | **Unchanged in meaning**, but stated per mode: red appears in TRANSACTION and destructive only; DISCOVERY and MARKET carry none | Consistent with the 18 Sep ruling; narrows by mode rather than by element |
| **4** | Green only for confirmed payment or completed money states | Unchanged | — |
| **5** | Selected tab indicator is chrome | Unchanged — the dock's lighter capsule already implements it | — |

---

## D · Screen architecture — four modes

**DISCOVERY** (Home, Search) — *Do I want to go?* Artwork leads. The unit is **artwork → title → date · venue →
price**, in DICE's order, mixed case, price present but never the largest element. Varied density: one 4:5 feature,
then 1:1 compact rows. **No invented curation** — sections may only be things the data can prove (date groups,
"ending soon" by real end time, price bands from the filter). No trending, no personalisation, no social proof.

**MARKET** (listing detail's inventory region) — *Which ticket do I want?* Ticket type, quantity, per-ticket vs
total, seller context, bid count and real remaining time. Denser rows, tabular figures, aligned price column. **No
market statistics** — no lowest ask, no last sale, no "N listings" until an event entity exists.

**TRANSACTION** (checkout, place bid) — *What am I agreeing to?* One item block, quantity, itemised fees, the total
as the most prominent price, payment or bid terms, then one filled red action with its consequence on its own line.
Restrained: no artwork competing with the total. Every guard from §B intact.

**OWNERSHIP** (Tickets, transfers, order view) — *What do I have, and what happens next?* Three distinct objects,
never merged:
1. **A paid marketplace order** — lives on Bids → Receive transfer. Shows payment state, the seller's claim, proof,
   review window, and what happens next. Never implies admission.
2. **A received transfer** — the buyer has confirmed; payment released. Still not a credential.
3. **A native credential** — Tickets tab only, from `get_my_tickets`, empty in production. No QR, no Wallet, no price
   until those contracts exist.

---

## E · Component families

Separate families where the job differs; shared primitives underneath.

| Family | Used by | Primitives shared |
|---|---|---|
| **Discovery feature** (4:5 artwork, overlay title, date · venue, price) | Home | `Artwork`, `TitleBlock`, `PriceText` |
| **Compact result row** (1:1 @8, four lines, price right) | Home rows, Search results, saved | `Artwork`, `TitleBlock`, `PriceText`, `Row` |
| **Market row** (type · quantity · seller · per-ticket vs total · bid count) | Listing detail inventory | `Row`, `PriceTable`, `LiveState` |
| **Ownership object** (event facts, fulfilment state, permitted actions) | Tickets, Receive/Send transfer | `FactRows`, `StatusPill`, `StatusRail` |
| **Transaction summary** (item, quantity, fees, dominant total, terms) | Checkout, Place bid, confirm sheets | `PriceTable`, `Notice`, `StickyBar` |
| **Chrome** (dock, on-art control, overlay sheet) | global | existing `AdaptiveDock`, `FilterSheet` |

There is deliberately **no universal EventCard**. `PriceText` and `PriceTable` must be the only places an amount is
formatted — CFT-207 records three local currency formatters still in the tree.

---

## F · Capability and dependency matrix

| Capability | Status | Owner |
|---|---|---|
| Discovery composition, artwork proportions, type, geometry, dock reuse | **Available and verified** | B design · C implements |
| Per-listing market facts (type, quantity, prices, bid count, real end time) | **Available and verified** | C |
| Transaction surfaces with all existing guards | **Available and verified** | C, reviewed by A |
| Marketplace order view (via Bids → Receive) | **Available with limitations** — it is a transfer screen, not an order screen | C |
| Native ticket presentation | **Available with limitations** — contract exists, returns empty; `__DEV__` fixtures only | A/B (flag) · C (UI) |
| Saves / wishlist | **Available with limitations** — table exists, no mobile UI, RLS unverified by me | C (UI) · A (contract review) |
| Tabular countdowns everywhere, single formatter | **Available with limitations** — CFT-207 `partial` | C |
| **Canonical marketplace event** (group listings, event-level destination) | **Requires new product/data capability** | A (schema) + owner (product) |
| **Market statistics** (lowest ask, last sale, inventory count) | **Requires new capability** — depends on the event entity | A |
| **Friends / attendance / social proof** | **Requires new capability** — no tables, plus a privacy model | owner first, then A |
| **Ticket detail, QR, Apple Wallet** | **Requires new capability** — `wallet.apple.enabled` false; issuance dark | A/B |
| **Make an Offer** | **Requires new capability on the live plane** — `market.offer` exists but is dark | A |
| Real blur materials | **Requires a dependency and a build** — `expo-blur` absent | owner authorises |
| Worklet motion / gestures | **Requires a build config** — no `babel.config.js` | C, with A's review |
| Licensed display typeface | **Requires a licence and a decision** | owner (D-3) |

**Nothing in the recommended direction sits on the critical path behind a new capability.** The presentation refresh
uses only rows 1–3.

---

## G · Phased handoff

| Phase | Contents | Review | Evidence of no regression |
|---|---|---|---|
| **V3-0 · Language** | Tokens only: graphite surface, titanium neutral, geometry scale, mixed-case display, red-by-mode. No layout moves | A (token parity) | `tests/product-v2-foundation.test.ts` parity green; existing suites unchanged |
| **V3-1 · Discovery** | Home and Search composition, artwork proportions, compact rows | C | Filter behaviour, realtime insert position, image-failure plate, quiet refresh all unchanged on device |
| **V3-2 · Listing + market** | Detail composition and the inventory region | C, then A for price semantics | Server-mirrored price, per-ticket vs whole-listing labels, live auction states |
| **V3-3 · Transaction** | Checkout and Place bid presentation only — **no monetary logic, no guard, no retry semantics** | **A required** | Every checkout test green, incl. #81's escrow-unknown case; no change to `payments.ts`, `checkout/*` |
| **V3-4 · Ownership** | Tickets and transfer composition | C, then A for transfer states | #84's copy preserved; the seven states still distinct; `[]` still success |
| **V3-5 · Optional** | Saves UI, event aggregation, social — each behind its own capability | owner decides order | — |

Interaction changes (navigation, back gestures, deep links, reservation cleanup) are **C's to review** and are not
part of V3-0 to V3-2.

---

## Recommended direction, and two alternatives

**Recommended — "Editorial Black."** Keep the black canvas, the shipping dock and `#FF1A1A`. Change three things:
type goes mixed-case with Oswald demoted to eyebrows and numerals; artwork becomes the only source of colour at two
fixed proportions; geometry gains two roles (8 for media, 20–24 for floating chrome). Red retreats to transaction and
destructive use only. This is a presentation change that needs no new capability, no dependency and no build.

**Alternative A — "Editorial Black + licensed display face."** The same, with a purchased display typeface replacing
Oswald's title role. This is the version that would feel closest to Rumor. Cost: a licence, a bundle-size increase,
and a re-measure of every display token against `MIN_LINE_HEIGHT_RATIO`.

**Alternative B — "Warm editorial."** Rumor's actual palette is **light** (page white, near-black text, warm sand
`#E8E0DB`). A light or warm-neutral Snatch It is the most differentiated option in a category where DICE and POSH are
both black. It is also the largest change: every screen, every token, and the "black on red" signature would need
re-testing. I do not recommend it now, but it is the only proposal here that would not read as "another dark ticket
app".

---

## The facts that constrain this

1. There is **no canonical event** on the live plane, so event pages, lowest ask and inventory counts cannot be built
   as presentation work.
2. **Tickets is empty in production** and marketplace orders live on Bids — ownership design must follow that, not fix it.
3. **No social data exists.** Any "people you know" surface would be fabricated.
4. **No blur, no SVG, no gradient, no worklets** without a dependency and a build.
5. The app is **mid-migration to v2** (69 files vs 9). V3 must extend v2 rather than become a third system.
6. Two consumer PRs (**#84**, **#81**) are reviewed but unintegrated; V3 must not conflict with them.
7. I performed **no production read and no device check**. Nothing here is phone-verified.

## Missing capabilities and their owners

| Missing | Owner |
|---|---|
| Canonical event + listing→event linkage | A (schema), owner (product decision) |
| Market statistics | A, after the event entity |
| Order-view destination for marketplace buyers | C (UI), A (contract) |
| Ticket detail / QR / Wallet, native issuance flag | A and B |
| Social graph + privacy model | owner, then A |
| `expo-blur` (or equivalent) and a build | owner authorises |
| `babel.config.js` for worklets | C, reviewed by A |
| Display typeface licence | owner |

## Decisions I need from you

- **D-1 · Direction.** Editorial Black, Alternative A (licensed face), or Alternative B (warm/light)?
- **D-2 · Geometry.** Approve the four-step scale (0 / 8 / 20–24 / pill), which formally departs from "0 or pill only"
  — a rule the shipping dock already breaks.
- **D-3 · Display typeface.** Keep Oswald in a demoted role, or licence a display face? This is the only proposal
  with a purchase attached.
- **D-4 · Ownership destination.** Marketplace orders currently live on Bids. Do we design a proper **order view**
  (new capability, C + A), or keep Bids as the destination and design it honestly?
- **D-5 · Cornerstone scope.** The brief's next stage names four surfaces. Given that Tickets is empty in production,
  I propose substituting **the marketplace order view** for "Tickets/ownership detail" — or keeping Tickets and
  designing against `__DEV__` fixtures. Your call.
- **D-6 · Deliverable format.** Since HTML is excluded: I propose **annotated written screen specifications** — per
  surface, a region-by-region composition table with exact tokens, type, spacing and states, plus a one-page ASCII
  wireframe per screen. No images, no code. Approve or name another format.

## Saved delivery preferences — separate deliverable, unchanged

**Status: complete and awaiting others. It is not part of V3 and is not folded into it.**

- **Where:** `docs/product/TICKET_DELIVERY_PREFERENCES_PLAN_20260919.md` on `design/frontend-audit-20260917` @
  **`7c7a07e7`** (clean tree).
- **Done:** the owner's eight approvals recorded and applied; flow, exact wording, edge cases, staged enforcement
  E0–E4, retention proposal, provider provenance separated into three layers (app-encoded / team research 12 Jun /
  independently verified — none), and the false "charged automatically" copy corrected in five prototypes at
  `c3aa96c4`.
- **Outstanding — A:** five items (A-1 reconcile the 24 h expiry and refund claims with deployed behaviour; A-2
  retention timing and exceptions; A-3 confirm the `mark_transfer_sent` refusal changes no payment/refund/expiry
  rule; A-4 how the store client renders a checkout error; A-5 confirm the settlement copy site and the table
  location). **These were never delivered to A — cross-session messaging is unavailable from my session.**
- **Outstanding — owner:** O-1 link providers (Fever, Shotgun), O-2 resale-sourced listings, O-3 the old-version
  enforcement threshold.
- **New, from today:** amend §7 — `catalog.platform_config` **does** exist, so staged enforcement can use it instead
  of one migration per stage. I have not edited the file in this phase.
