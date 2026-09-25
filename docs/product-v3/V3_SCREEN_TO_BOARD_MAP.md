# V3 authoritative screen-to-board map

**B owns this map and the visual review; C owns the phone checklist and implementation** (owner, 2026-09-24).

**How to read a row.** Owner approval attaches only to the `midnight-*` set. Later packages carry
**delegated authority for their stated scope only** — pkg7 = copy/hierarchy (owner reopened the freeze),
pkg8 = appearance tokens (*"Same layout, same words, same hierarchy; only token values differ"*). A later
package overrides an earlier board **only inside its scope**. **An owner ruling in prose overrides every
board, including a newer one.**

**Owner approval event — 2026-09-22, the only one:** *"I approve neutral decorative hairlines, mixed-case
sentence headings, and the rounded controls shown in the approved V3 designs"*, with radii applied by
component role (A-1/A-2/A-3); and the four `midnight-*-clean` screens plus the "You" dock item.

---

## Confirmed mappings

| Screen | Composition (governs layout/geometry) | Copy | Dark tokens | Light tokens | Later ruling that overrides the board |
|---|---|---|---|---|---|
| **Home** | **`midnight-home-clean.png`** — owner-approved + `V3_DESIGN_PACKAGE_FOR_C_20260922.md` §3 geometry | pkg7 changed **nothing** | `pkg8-home-dark.png` | `pkg8-home-light.png` | Dock label **Create → "Sell"** |
| **Search** | **`midnight-search-clean.png`**; empty `midnight-search-empty.png` | `pkg7-search-after.png` — **one sentence** ("Try the venue name, or a shorter word.") | `pkg8-search-dark.png` | `pkg8-search-light.png` | No filter-excluded count — *"a new capability, not a copy change"* |
| **Listing detail** | **`midnight-listing-clean.png`**; failed read `midnight-listing-error.png` | **`pkg7-listing-after.png`** — removed the duplicated total/breakdown **and added `BidActivity`** (a coverage gap, not decoration) | `pkg8-listing-dark.png` | `pkg8-listing-light.png` | ⚠ **Buy now is PRIMARY** (owner, 2026-09-23). **No listing board has been redrawn. The ruling governs; the boards are wrong here.** Also quantity-aware verb |
| **Order** | **`midnight-order-clean.png`**; unreachable `midnight-order-unreachable.png` | `pkg7-order-after-ready.png`, `pkg7-order-after-unreachable.png` | `pkg8-order-dark.png` | `pkg8-order-light.png` | **Live data only** — no persistent cached-order presentation. The **auto-release sentence is NOT approved** (O-1) and is printed on the approved board |
| **Bid entry** | **No board approval.** Owner **direction** 2026-09-23 → **`pkg7-bid-after-raised.png`** (+ `-after`, `-after-annotated`) | same | `pkg8-bid-dark.png` | `pkg8-bid-light.png` | **O-2 withdrawn** — the CTA is plain `Place bid`. `pkg2-bid-entry-*.png` are **superseded and still draw the forbidden label** |
| **Checkout** | **No owner approval at all.** `pkg7-checkout-after.png`; state inventory `pkg2-checkout-states.png` (all 10 payControl states) | same | `pkg8-checkout-dark.png` | `pkg8-checkout-light.png` | `pkg8-checkout-amount-source.png` was **a proposal, now dead** — A and C resolved it by deletion. "Paying with" row **not authorised** |
| **Dock / "You" item** | **`compare-profile-nav.png`** — owner-approved (A2). **Dark only; no light variant of this sheet** | — | in context `pkg8-home-dark.png` | in context `pkg8-home-light.png` | **Create → "Sell"**; "Profile" → "You" changes the accessible name |
| **Profile screens** | `pkg8-account-tickets-dark.png` (own + public profile) | — | same | `pkg8-account-tickets-light.png` | — |
| **Settings / notifications / security** | `pkg8-account-settings-dark.png` | — | same | `pkg8-account-settings-light.png` | 2026-09-24: persistent visible label on the code field; do **not** differentiate critical-risk from listing-blocked; provide a working support route |
| **Auth** | `pkg8-account-auth-dark.png` | — | same | `pkg8-account-auth-light.png` | — |
| **Create / Sell** | `pkg7-create-after.png`; validation `pkg3-create-invalid.png` | same | `pkg8-create-dark.png` | `pkg8-create-light.png` | 2026-09-24: **readable colours for required-field prompts** |
| **My listings** | `pkg3-my-listings-clean.png`, `-empty.png` | `pkg7-selling-comparison.png` | `pkg8-mylistings-dark.png` | `pkg8-mylistings-light.png` | De-duplication direction applies |
| **Send transfer** | `pkg4-send-{clean,pending,seller_sent,expired}.png` | `pkg7-send-after.png` | `pkg8-send-dark.png` | `pkg8-send-light.png` | — |
| **Foundations / components** | **`pkg1-foundations.png`**, `pkg1-components.png` — **A-1/A-2/A-3 owner-approved** | — | `pkg8-appearance-tokens.png` | same | Canvas is **`#000000`**; pressed primary is **`#FF5353`** (pkg1-components still says `#CC0000` — stale) |
| **Listing dialogs** | `pkg6-listing-dialogs.png`, `pkg6-listing-action-matrix.png` (re-rendered `77a122b4`) — 23 call sites / 24 variants | same | dark only | **none** | *"Red marks the buying path… not a claim that money moves when you tap it."* F-29 recovery copy **withdrawn** |
| **Bids tab · selling dialogs · system surfaces · state screens** | `pkg6-bids-*.png`, `pkg3-selling-dialogs.png`, `pkg6-system-surfaces.png`, `pkg1-states.png` | — | dark only | **none drawn** | De-duplication applies as each slice lands |
| **Receive transfer (buyer)** | `pkg4-transfer-matrix.png`, `pkg4-dispute-support.png` | — | dark only | **none** | ⚠ **`expired`/`reversed` buyer cells are BLOCKED — explicitly not approved.** *"any refund is handled automatically"* withdrawn |

## Boards that are known-wrong — do not implement from them

1. **Every listing board draws bid-primary.** The owner ruled **Buy now primary** on 2026-09-23 and no board was redrawn.
2. **`pkg2-bid-entry-*.png`** still show `Place bid · $104.50 all-in` — **O-2, withdrawn**.
3. **`midnight-order-*.png` and `pkg7-order-after-ready.png`** print the **unapproved** auto-release sentence (O-1), and the unreachable boards depict **persistent order caching**, which is out of scope.
4. **Approved boards and pkg1–pkg7** were drawn on `#08090A`; the canvas is **`#000000`**. Only the `pkg8-*` dark boards were re-rendered.
5. **`pkg1-components.png`** and Package 1 §2 still say `brand.redPressed #CC0000`; the pinned value is **`#FF5353`**.
6. **`pkg8-home-{dark,light}.png` draw "Tonight" / "This week"**, but no package text defines the grouping rule. **The board is ahead of the spec** — see the review's H2.

## Genuinely unresolved — pending, and not blocking the rest

- **Listing:** the pkg7 removal ledger and the rendered `pkg7-listing-after.png` disagree about the commitment sentence and whether the "IF YOU BID THE MINIMUM" eyebrow survives. Both are in the record; I am not guessing which is final.
- **Search:** the **"Any date" chip** is drawn; its semantics are undefined.
- **Order:** whether the unreachable variant is a panel inside `pkg8-order-{dark,light}.png` is not stated anywhere.

---

## Consumer-screen rows added 2026-09-24 (B)

Reviewed-commit convention: every review names the commit it captured. **C's `app/_dev/v3-*` harness
screens take no board and are never consumer surfaces** — they are a review instrument only.

| Screen | Reference (dark / light) | Later ruling that governs |
|---|---|---|
| **Tickets** | `pkg8-account-tickets-dark.png` / `-light.png` | Populated/Past rendering is **not coverable** — `kernel.tickets` is 0 |
| **Appearance** (Settings → Appearance) | `pkg8-appearance-dark.png` / `-light.png` | System / Light / Dark, default System; selection carries four cues, not colour alone |
| **Edit listing** | `pkg3-create-*` geometry + `pkg8-create-dark/light` tokens | Required-field prompts must be readable (owner 2026-09-24) |
| **Payout setup** | `pkg6-settings-surfaces.png` (dark only) | **No light board exists** — light is derived from the palette, not from a board |
| **Report a listing / user** | `pkg4-dispute-support.png` (dark only) | **No light board.** The 0/1000 counter must not sit at `faint` |
| **Public profile** | `pkg8-account-tickets-light.png` (it draws own + public profile) | Trust row shows "unavailable" rather than inventing a figure |
| **Settings sub-screens** (notifications, security notice, blocked users, legal, privacy, preferences, support) | `pkg8-account-settings-dark.png` / `-light.png`; earlier `pkg6-settings-surfaces.png` | Persistent visible label on the 6-digit code field; a working support route; do not differentiate the two blocked reasons |
| **Checkout display page** (`app/_dev/v3-checkout.tsx`) | **none — harness only** | Review instrument. Never a consumer surface, never a board row |

---

## SETTLED — listing footer action presentation (owner, 2026-09-25)

**Approved from `comparisons/footer_arrangements_91062ab1.png`, Option B, in both appearances.**
**This supersedes the 2026-09-24 Buy-Now-first visual hierarchy ruling.**

When **bidding and Buy Now are both available** (`detailState` mode `auction_and_buy_now`, and
only that mode):

1. **Place a bid** — first, full-width, **red (filled)**. Its minimum all-in amount sits beneath
   the label **inside** the button.
2. **Buy Now** — second, full-width, **outlined**. Its quantity-aware label ("Buy both now",
   "Buy all N now"), its price and its sub-line are preserved exactly as rendered in Option B.

**Scope limits, as ruled.** This pair is **not** forced onto reserved, sold, ended, cancelled,
own-listing, won, not-found or any other state with different valid actions. Those keep the
single state control and the sentence outside the pill.

**Behavioural invariants, unchanged by the paint.** Opening bid entry submits no bid. Buy Now does
not establish a successful charge. Action **eligibility** is unchanged: which actions exist, and
which are disabled, is still the resolver's decision.

**The boards remain superseded here.** `pkg8-listing-dark` / `-light` draw the bid filled with Buy
Now beneath it; the 2026-09-24 ruling inverted that to Buy-Now-filled; this ruling returns the
fill to the bid while keeping Buy Now's V3 label, price and sub-line, which the boards predate.
The board rows in this map stay marked known-wrong for the footer, now against **this** ruling.

**Status:** C implements in the app's action-presentation logic (never as a harness patch) ·
B verifies the committed result · E updates the reference map and the acceptance record.
Verification owed on native: Dynamic Type, wrapping, safe areas, both appearances, with no
essential label or price truncated.
