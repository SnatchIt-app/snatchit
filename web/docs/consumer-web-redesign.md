# Consumer web redesign — route checklist (branch `web/consumer-redesign-20261013`)

Base: live web `0b389584` (= RC2 `web/`, 0 files differ). Native reference: frozen candidate
`e2b9498b` (source + the committed captures listed below). System: [`design-system.md`](design-system.md).
Presentation and interactions, plus the release-prep changes listed under "Release prep": no
backend, schema or payment-logic change.

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

## Release prep (owner direction 2026-10-13: visuals approved, stale claims not)
Verified at `50a928a7` on the same private harness, with migration 152 applied to the rehearsal
database (function digests match A's post-apply reference). 152 went live in production at
21:42Z (A's read-back and D's post-apply verdict).

**Changes**
- **152 refusals** (bid insert, `reserve_buy_now`, listing insert, listing update): the four hints
  map by exact match to POLICY_WORDING K2, as the app's `serverRefusal.ts` does; any other error
  keeps its previous copy (`lib/server-refusal.ts`).
- **FU-1:** the listing pre-check is the app's ten word-boundary patterns = 152's list, fields
  joined the server's way; its message is the server's own K2 sentence (`lib/content-moderation.ts`).
- **FU-4:** POLICY_WORDING §5 rows, confirmed by A, from one module (`lib/policy-wording.ts`):
  fee on the sale price, payout not unconditional, the 24-hour refund stated precisely, P4,
  the report confirmation and payout-setup sentence from the app. Dropped "funds held until
  your ticket is delivered" and a duplicate payout line; the listing links the Terms (G).
- `/sell`'s blocked state uses the app's sentence (a suspension has no end date) and links support.
- **Payment truth:** a processing return (`redirect_status=processing`) is pending, not failed
  (PaymentForm's own sentence, purchases only); a dropped confirm-receipt response no longer
  claims "nothing was charged or released".
- **Email links:** `/auth/confirm` accepts `?code=` (the web's PKCE requests). Before, a fresh
  reset link said "Link expired" right after the client had exchanged the code.
- Local-preview CSP allowance also covers `ws://` (inert in production; pinned test).

**Results at `50a928a7`**
- Unit 22 files / 279 tests (1 skipped by design: the migration-file parity row until 152's file
  is on this tree; the list is pinned to 152 as reviewed instead). Typecheck clean; lint 0 errors.
- Mutants killed: 11/11 (list parity, field join, the four call sites, exact-hint match, three
  wording reversions), plus the processing branch, the PKCE link reader and the CSP allowance.
- `next build` exit 0; smoke 11/11.
- Changed-route sweep: 152 page checks over 17 routes (phone, tablet, desktop × light, dark;
  320 px; 200% zoom): 0 overflow, an h1 everywhere, no console errors; contrast 7,644 elements,
  0 failures, controls passing.
- Interactions 24/24 (regression set). 152 refusals 13/13: blocked either way on bid and Buy Now,
  suspended seller's listing, suspended buyer, suspended seller's edit and `/sell`, pre-check,
  and a control bid that goes through; each refusal writes no row and holds nothing.
- Flows 16/16: reset link (PKCE) lands on Reset password, saves, and a reused link is refused;
  phone code (wrong refused, right verified, recorded); payment return processing / failed /
  unverifiable / settled (listing sold, one transfer, idempotent on return).
- Realtime 6/6 against a protocol stand-in: another buyer's bid appears live, the next-bid amount
  moves, an ended auction stops bidding live, and an event for another listing changes nothing.

**Still not verified (and why)**
- Stripe Payment Element, 3DS and a real PaymentIntent: the Stripe connector here reaches only the
  live account, and the test-mode sandbox needs a sign-in this lane may not perform. The return
  page was driven with stated confirm-payment answers; no payment existed.
- Supabase Realtime itself (WAL, RLS on channels): no Docker for a local stack. The web's client
  half was exercised against the stand-in only.
- Real email and SMS delivery, and which link format production's email templates use (Supabase
  Auth configuration, owner-only). Reset links came from a local outbox; the phone code from the
  stand-in. No message was sent.
- Spoken VoiceOver (owner waiver).

## Routes
| Route | Native reference | Status | States rendered (all sizes, light + dark) | Not rendered locally |
|---|---|---|---|---|
| `/` Home | `app/(tabs)/home.tsx` · capture `3d4d6a4a` | Done | Tonight / This week / Later, feature, rows, phone dock | empty state (data always present) — source + type check |
| `/browse` | `app/(tabs)/explore.tsx`, FilterSheet | Done | results, search results, no match, filtered, quick chips, filter sheet + rail | loading / error boundary (fast local data) |
| `/listing/[id]` | `ListingDetailScreen.tsx` · captures `2ada44bd`, `7d957100` | Done | live hybrid, live auction, ending soon, on hold (holder / other buyer), sold, ended without bids, cancelled, won-unpaid, owner view, 404; 152 refusals on bid and Buy Now; live bid and auction end (realtime stand-in) | Supabase Realtime itself |
| `/checkout/[id]` | CheckoutNative / CheckoutView | Done* | summary, auction-win and Buy Now modes, Already sold / Auction ended / Reservation expired, payment set-up error | *Stripe Payment Element and its success path — Stripe is not emulated (appearance set, unverified) |
| `/checkout/[id]/complete` | checkout result screen | Done* | processing (pending), failed, unverifiable, settled (sold + transfer) — confirm-payment answer stated by the harness | a real Stripe redirect |
| `/transfer/receive/[id]` | "Your order" | Done | needs delivery details, marked sent + proof, complete, disputed, expired | pending with delivery saved (no synthetic row) |
| `/transfer/send/[id]` | "Send transfer" | Done | pending awaiting buyer details, marked sent, complete / released, disputed | pending with buyer details present (no synthetic row) |
| `/sell` | `CreateListingScreen.tsx` | Done | gate (phone verified, payouts missing), gate (both missing), form, blocked (suspended) | — |
| `/account` (hub) | profile tab + settings hub · `9bbeaec6` | Done | buyer, seller, new account | — |
| `/account/purchases` · `/sales` · `/listings` · `/saved` · `/notifications` | Bids/My listings/settings rows | Done | filled (Ava, Sam) and empty (Nia) | load-error states (no fault injection) |
| `/account/profile` · `/account/settings` | edit profile, settings, Appearance, payout setup · `64e2212f` | Done | payouts not connected / connected, Appearance System / Light / Dark | Stripe onboarding hand-off |
| `/account/verify-phone` | `settings/verify-phone` | Done | number entry, code step (wrong / right), verified | real SMS delivery |
| `/account/listings/[id]/edit` | `listing/edit/[id]` | Done | editable, locked (has bids), pre-check refusal, suspended refusal | — |
| `/login` · `/signup` · `/forgot-password` · `/reset-password` · `/auth/confirm` | `(auth)` screens | Done | forms, field errors, `next` carried, reset link (PKCE) → reset → saved, reused link refused | email delivery, sign-up confirmation link, production template format |
| 404 · error · global error | StateView | Done | 404 (h1), global error standalone | runtime error boundary (no fault injected) |

## Copy and behaviour changes
- Policy and payment wording: see "Release prep" (POLICY_WORDING §5, K2).
- Headings and labels: Home section labels, Browse
  "Browse", listing "On hold" / "Held for you / another buyer" / "From a fan" / "Your winning bid", filter
  labels and chips, feed caption "all-in", sell hints "Buyers pay from $X" / "Buyers pay $X", account groups
  and Appearance, arrows replaced by chevron icons, "Get the app" moved to the footer.
- Behaviour: an on-hold listing no longer says "This listing has ended" (holder gets "Finish checkout");
  the back chip returns through history when an in-app page is behind it; the owner no longer sees an
  active "Buy now" on their own listing; error boundaries use `retry()`.


## Production release plan (A coordinates; each step is the owner's)
Web production is the Vercel project `snatchit-web`, built from `feature/web-accounts-foundation`
(live `0b389584`; a push to it deploys production). PR #102 targets that branch. Nothing here
touches the database, migrations, the native app, the console or the dashboards.

**Preconditions (all of them):**
1. **M-152 applied in production and read back** (A's message with the ledger row, after D's
   post-apply verdict). **Met: applied 2026-10-13 21:42Z, read back by A and D.** Why it
   gated: FU-1 replaces web's substring pre-check with the app's word-boundary list, which is
   looser for substrings ("alcoholic", "drugstore"); without 152 nothing checks listing text on
   the server. Without 152 the K2 refusal mapping is simply inert.
2. PR #102's CI green at the candidate sha (Typecheck / Lint / Unit, Web build, migration checks).
   CI's web job runs `next build` only; the web unit tests (FU-1 parity, refusals, wording) run
   with `cd web && npm test` — locally at the candidate, or in CI once a web test step exists.
3. Base unchanged: `origin/feature/web-accounts-foundation` = `0b389584`. If it moved, merge it
   into the branch, re-run the checks, and treat the result as a new candidate.
4. The owner approves the web production deploy (merging #102 is that deploy).

**Deploy:**
1. Mark #102 ready; merge into `feature/web-accounts-foundation` with a merge commit.
2. Vercel: the production deployment's commit is the merge commit and its state is Ready.
3. Read-only checks on production, no sign-in and no purchase: `/`, `/browse`, one live listing,
   a missing listing answers 404, `/login`, `/forgot-password`, `/auth/confirm` (renders
   "Link expired" with no link), `/account` redirects to `/login?next=%2Faccount`, and the
   Content-Security-Policy header has no `127.0.0.1` (the harness allowance is off on Vercel).
4. Record the deployment id. The gate's `web/` no longer equals live web from here on, so
   `rc3_verify`'s web reference has to move (A).

**Rollback (presentation and client logic only; no data to undo):**
- Fastest: Vercel Instant Rollback to the previous production deployment (built from
  `0b389584`). Then revert the merge commit on `feature/web-accounts-foundation`, so the
  branch matches what is served.
- What comes back with a rollback: the withdrawn wording (FU-4 rows), the substring pre-check,
  raw server sentences instead of the K2 mapping, "Link expired" on PKCE email links, and
  "did not complete" on a processing payment return.
- A 152 rollback needs no web change: the hints stop arriving and web falls back to its
  previous copy; the pre-check stays equal to the app's.

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
- **Report a listing or user**, **Block user**, **Blocked users** settings. (152's server refusals
  apply to web users regardless; the web only lacks the entry points.)
- **Notification preferences** (six toggles), **Your scene** (neighborhoods), **Sign out of all devices**.
- **Phone-number sign-in** and the 4-step sign-up (the web signs in by email).
- **Payout return/refresh screens** — web payout onboarding returns to `snatchitapp.com/payout-return`
  (existing behaviour, unchanged).
The web keeps flows the native app lacks: notifications inbox, saved listings, inline bidding.
