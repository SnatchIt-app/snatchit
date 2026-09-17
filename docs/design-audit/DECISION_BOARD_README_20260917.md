# Visual decision board — README (B, 2026-09-17)

**File:** `docs/design-audit/prototypes/decision-board.html` — one self-contained HTML file, synthetic data,
no build step, no network dependency. Open it directly in a browser.

It replaces opening five prototypes side by side: eleven directions × nine screens = **99 screen compositions**
in one file, with a section nav, a direction selector, a screen selector and a compare view.

---

## 1 · What is in it

| Section | Contents |
|---|---|
| **Overview & legend** | How to read the board, the rules it follows, and a live fit report |
| **1 · The original five** | Gallery · Index · Charcoal · Liquid · Utility — in the order they were created |
| **2 · The hybrids** | A Gallery Index · B Editorial Market · C Premium Utility |
| **3 · Recommended** | **R · Gallery / Ledger** |
| **4 · New concepts** | **N1 · Ticket Stub** · **N2 · Night Index** — two directions that are not recombinations |
| **5 · Compare one screen** | The same screen across all eleven directions at once |
| **6 · Decision note** | Recommendation, tradeoffs, ordered implementation, and what is still the owner's call |

**Screens:** Home · Listing Detail · Bids · Tickets · Send Transfer · Receive Transfer · Checkout · Profile · Settings.

**Controls:** section tabs · screen tabs · zoom (100 / 80 / 62%) · *Outline preserved / proposed*, which marks
inside every frame what exists in the app today versus what is proposal only.

**Constraints followed:** populated success states only · regular text size only · Reduce Motion treated as on
(every indicator is static) · content at ~80% of the previous prototypes' scale.

---

## 2 · The recommendation

**Gallery / Ledger.** Image-led discovery with date structure, ledger-grade transaction screens, one shared type
scale, one filled red action per screen, advisory in a muted blue.

- **Discovery** — Gallery Index's Home: date header, 3:2 flyer, name and price on one baseline, one metadata line
  carrying time, venue, bid count and live state.
- **Transactions** — Premium Utility's density: label left, value right, tabular figures, the total larger than its
  line items, exactly one filled action with its consequence on its own sub-line.
- **From Editorial Market**, two ideas only: the hero progress bar inside the final six hours, and an "Ending soon"
  rail populated strictly by real remaining time.
- **From Charcoal**, one token: a muted blue for advisory, so information stops borrowing the action colour.
- **From Liquid**, one idea: text over artwork sits on a dimming scrim, not a glass panel — Apple's own guidance,
  and the thing the app can already render.

**No new dependency, no new font, no new native module.** It is layout, tokens and copy.

### The two new concepts

- **N1 · Ticket Stub** — the card takes the shape of the object being bought: art, a perforation, then a price
  column. The perforation is CSS, radius stays 0. My assessment: a strong *card* idea and a weak *system* idea. If
  you like it, take the stub card into Gallery / Ledger's discovery and leave the transaction screens alone.
- **N2 · Night Index** — time as the organising axis, and the same rail becomes the transfer's status timeline:
  paid → sent → confirmed → released, with real timestamps and the money at the end. **The timeline is the one idea
  I would take whatever you choose** — today that state is spread across sentences in three places.

---

## 3 · Key tradeoffs

| Choice | Gain | Cost |
|---|---|---|
| Gallery Index over Gallery | Structure in a long scroll, ~2× the events per screen | The single-poster drama |
| Ledger over card transactions | Aligned figures, dominant total, less travel before the action | Transaction screens look plainer than discovery — deliberately |
| Scrim over glass | Ships today, one visual system to maintain | Not the current-iOS look until a build is authorised |
| Advisory blue | Advisory stops reading as danger | A second accent in a system deliberately narrowed to one |
| Radius 0 kept | Identity intact, no token fight | Charcoal's softness, which reads better on sight to many people |

---

## 4 · What follows, in order

Stage 0 is not mine and comes first: the release-critical state fixes from the first audit — the bid form's `0`
floor, the re-entrant destructive actions, Home's in-flight empty state, the avatar spinner. Those are C's.

| Stage | Work | Files |
|---|---|---|
| 1 | Live-bid state machine, pure logic, unit-tested against a real end time | new `src/lib/listing/liveBid.ts` |
| 2 | `Notice` primitive, three ranks; replaces hand-rolled boxes | new `src/components/ui/Notice.tsx`; both transfer screens, `settings/index`, `CreateListingScreen` |
| 3 | Live-bid rendering in discovery and Bids | `DiscoveryCard.tsx`, `bids/BidCard.tsx`, `listing/TransactionPanel.tsx` |
| 4 | Home layout — SectionList with date headers, 3:2 media slot, ending-soon rail | `app/(tabs)/home.tsx`, `src/lib/media/slots.ts` |
| 5 | Transaction density + status timeline | `app/transfer/send/[id].tsx`, `app/transfer/receive/[id].tsx`, `CheckoutNative.tsx`, `ui/StickyBar.tsx` |
| 6 | Motion — every row collapses through `useReducedMotion()` | `usePulseOnChange`, `MediaUpload`, `Notice` |

**Components that fall out of this:** `Notice`, `StickyBar`, `PriceTable`, `LiveState`, `StatusTimeline`,
`FactRows`, `SectionHeader`. Three are already wanted by C's ML-1 work and by the calm pass — the ownership
conflict C has put to the owner as one decision.

---

## 5 · Verification — measured in the browser, not asserted

Run against the board itself (Chromium, 2026-09-17). Each number is a measurement, not an estimate.

| Check | Result |
|---|---|
| Frames rendered | **99** (11 directions × 9 screens) |
| Frames fitting 360 × 800 with no internal scrolling | **93 of 99** |
| Frames overflowing | **6**, all image-led: Home g1 305 px · h2 136 px · r1 165 px; Listing g1 161 px · h2 145 px; Receive n2 57 px — each stated in its own caption |
| Essential transaction content present in every transaction frame (recipient, delivery method, proof, payout/breakdown figures, deadline, primary action) | **0 missing** across 33 frames |
| Checkout total is the most prominent price in its frame (FTC junk-fees rule) | **0 violations** in 11 directions |
| Filled red actions on discovery and account screens | **0** |
| Filled red actions on transaction screens | **exactly 1** per frame |
| Destructive action rendered filled | **0** |
| CSS animations or transitions anywhere | **0** — the Reduce Motion claim is literal, not a label |
| Live treatment rendered beside an ended auction | **0** |
| "Ending soon" pill outside the under-15-minute window | **0** |
| Focusable elements inside a phone frame | **0** — nothing pretends to be a working control |
| Board structure | one `<main>`, one level-1 heading, all controls are real `<button>`s with `aria-pressed` |
| Console errors | none |

### What is *not* verified

- **No device check.** These are local renderings in a desktop browser at a phone-shaped frame — not screenshots of
  the app, and no frame here has been rendered on a handset by me. Type, spacing and proportion will differ on a
  real device; only C's handset pass on an authorised build closes that.
- **The display face is optional.** Oswald loads from Google Fonts if reachable; if it is not, the board falls back
  to a condensed system stack and no layout depends on it.
- Nothing was applied, built, deployed or tagged. No sandbox or production access.

---

## 6 · Still the owner's decision

1. **Red** — whether destructive actions get their own colour. The board draws them outlined in a dashed error tone
   and never filled, which is my recommendation, but it reverses the direction approved on the 14th. D is carrying
   it as an A-or-B.
2. **Which direction to build**, if any.
3. **Charcoal's radius** — included unchanged so it can be seen, but it breaks an approved token.
4. **Liquid** — needs `expo-glass-effect` and a new build; nothing about it can start without authorisation.
