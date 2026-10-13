# Consumer web redesign — route checklist (branch `web/consumer-redesign-20261013`)

Base: live web `0b389584` (= RC2 `web/`, 0 files differ). Native reference: frozen candidate
`e2b9498b` (source + the committed captures listed below). System: [`design-system.md`](design-system.md).
Presentation and interactions only — no backend, schema, payment-logic or wording change except
where listed under "Copy and behaviour changes".

Status legend: **Done** = redesigned and inspected rendered (phone 390, tablet 820, desktop 1440;
light + dark) on the local harness with synthetic data. **Source-only** = redesigned and
type/lint/test-checked, but a state could not be rendered locally (reason given).

## Verification summary (local harness, synthetic data, final commits)
- Unit: 17 files / 242 tests (vitest). Typecheck clean. Lint 0 errors (3 pre-existing warnings in untouched `lib/format.ts`).
- Production build (`next build`) exit 0; `scripts/smoke.mjs` 11/11 (incl. the real 404 for a missing listing).
- Rendered sweep: 572 page checks over 49 routes — phone 390, tablet 820, desktop 1440 in light and dark,
  plus 320px, 200% browser zoom and reduced motion + reduced transparency. 0 horizontal overflow, an h1 on
  every page, no unexpected sign-in redirect; contrast probe 21,521 text elements with its positive and
  negative controls passing — the only flags (a screen-reader-only label) were fixed.
- Real-input interaction checks on the production build: 24/24 (filter sheet Apply / Clear / Escape with
  focus return, quick chips, search, back chip keeping filters, skip link, dock collapse and expand, save,
  bid stepper and place bid, Buy Now → checkout, Appearance switch persisting across server renders).
- Mutation check: 6/6 mutants of the new presentation logic fail the tests (Miami day/time, urgent
  threshold, this-week window, sold amount, back-stack pop, theme cookie validation).
- Native-vs-web sheets for 7 screens (Home, listing breakdown, sold listing, settings hub light/dark,
  Appearance, payout setup) are kept privately on the SSD with the captures.

## Routes
| Route | Native reference | Status | States rendered (all sizes, light + dark) | Not rendered locally |
|---|---|---|---|---|
| `/` Home | `app/(tabs)/home.tsx` · capture `3d4d6a4a` | Done | Tonight / This week / Later, feature, rows, phone dock | empty state (data always present) — source + type check |
| `/browse` | `app/(tabs)/explore.tsx`, FilterSheet | Done | results, search results, no match, filtered, quick chips, filter sheet + rail | loading / error boundary (fast local data) |
| `/listing/[id]` | `ListingDetailScreen.tsx` · captures `2ada44bd`, `7d957100` | Done | live hybrid, live auction, ending soon, on hold (holder / other buyer), sold, ended without bids, cancelled, won-unpaid, owner view, 404 | live bid updates (realtime not emulated) |
| `/checkout/[id]` | CheckoutNative / CheckoutView | Done* | summary, auction-win and Buy Now modes, Already sold / Auction ended / Reservation expired, payment set-up error | *Stripe Payment Element and its success path — Stripe is not emulated (appearance set, unverified) |
| `/checkout/[id]/complete` | checkout result screen | Done* | payment failed | processing / success / unverified — need a real Stripe redirect |
| `/transfer/receive/[id]` | "Your order" | Done | needs delivery details, marked sent + proof, complete, disputed, expired | pending with delivery saved (no synthetic row) |
| `/transfer/send/[id]` | "Send transfer" | Done | pending awaiting buyer details, marked sent, complete / released, disputed | pending with buyer details present (no synthetic row) |
| `/sell` | `CreateListingScreen.tsx` | Done | gate (phone verified, payouts missing), gate (both missing), form | risk-blocked screen |
| `/account` (hub) | profile tab + settings hub · `9bbeaec6` | Done | buyer, seller, new account | — |
| `/account/purchases` · `/sales` · `/listings` · `/saved` · `/notifications` | Bids/My listings/settings rows | Done | filled (Ava, Sam) and empty (Nia) | load-error states (no fault injection) |
| `/account/profile` · `/account/settings` | edit profile, settings, Appearance, payout setup · `64e2212f` | Done | payouts not connected / connected, Appearance System / Light / Dark | Stripe onboarding hand-off |
| `/account/verify-phone` | `settings/verify-phone` | Done | number entry | code step (SMS not emulated) |
| `/account/listings/[id]/edit` | `listing/edit/[id]` | Done | editable, locked (has bids) | — |
| `/login` · `/signup` · `/forgot-password` · `/reset-password` · `/auth/confirm` | `(auth)` screens | Done | forms, field errors, `next` carried, expired reset link, link expired | email delivery, signup success after confirmation |
| 404 · error · global error | StateView | Done | 404 (h1), global error standalone | runtime error boundary (no fault injected) |

## Copy and behaviour changes
- Headings and labels only (no payment, refund, transfer or payout wording): Home section labels, Browse
  "Browse", listing "On hold" / "Held for you / another buyer" / "From a fan" / "Your winning bid", filter
  labels and chips, feed caption "all-in", sell hints "Buyers pay from $X" / "Buyers pay $X", account groups
  and Appearance, arrows replaced by chevron icons, "Get the app" moved to the footer.
- Behaviour: an on-hold listing no longer says "This listing has ended" (holder gets "Finish checkout");
  the back chip returns through history when an in-app page is behind it; the owner no longer sees an
  active "Buy now" on their own listing; error boundaries use `retry()`.


## Native reference captures used (all CURRENT at `e2b9498b`)
| Screen | Capture | Why current |
|---|---|---|
| Home | `native/3d4d6a4a/home-price-default-light` | no later change to the depicted Home price rows |
| Listing breakdown | `native/2ada44bd/listing-breakdown-default-light` | only `caa3fa03` since (navigation param) |
| Sold listing | `native/7d957100/listing-sold-default-light` | sold panel unchanged since |
| Settings hub, Appearance | `native/9bbeaec6/*-default-{light,dark}` | captured 2026-10-11, unchanged |
| Payout setup (not connected) | `native/64e2212f/payout-setup-default-light` | unchanged since |
Stale captures (profile, older listing frames) and the July App Store screenshots were not used.
Screens without a current capture were matched to the native source (`app/`, `src/screens/`).

## Missing native-equivalent flows (not built — no web backend path today)
- **Bids tab** ("Your bids", Active / Past with Won / Winning / Outbid cards) — the web has no
  read of a user's bids across listings.
- **Tickets tab** (owned tickets with Valid / Used / … badges) — native notes production returns
  no tickets; the web's equivalent is Purchases.
- **Public seller profile** (`/profile/[id]`: trust panel, rates, active listings, Report / Block).
- **Report a listing or user**, **Block user**, **Blocked users** settings.
- **Notification preferences** (six toggles), **Your scene** (neighborhoods), **Sign out of all devices**.
- **Phone-number sign-in** and the 4-step sign-up (the web signs in by email).
- **Payout return/refresh screens** — web payout onboarding returns to `snatchitapp.com/payout-return`
  (existing behaviour, unchanged).
The web keeps flows the native app lacks: notifications inbox, saved listings, inline bidding.
