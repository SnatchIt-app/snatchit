# Hybrid directions — second exploration (B, 2026-09-17)

**Owner's brief:** don't optimise only for calm; make it aesthetically strong and enjoyable, with layout, spacing,
hierarchy, transitions and feedback that feel intentional. Research DICE and Posh for discovery, CrowdVolt and StockX for
live-market signals, and Apple's current guidance. Borrow principles, never branding.

**Design only.** No product code, payment/auth/transfer rule, database file or active handset-test file is touched. No
sandbox, no production, no build. Branch `design/frontend-audit-20260917`. C's Home filter test is untouched — everything
here is a reconstruction with synthetic data.

**Prototype:** `docs/design-audit/prototypes/hybrids.html` — switcher across three hybrids × six screens (Home, Listing,
Bids, Send, Receive, Checkout) × normal and largest text, with per-screen states and a "Compare this screen" mode, plus a
live-bid treatment gallery. Verified in-browser: **75 of 75 direction/screen/state combinations render**, compare mode
returns three frames, and no frame scrolls horizontally.

## 1. The three hybrids
| | Idea | Home layout | Type | Live-bid layer | Nav |
|---|---|---|---|---|---|
| **A · Gallery Index** | flyer-led but scannable | date group headers, 3:2 flyer, compact metadata row under it | Inter content, Oswald only in the bar | quiet dot + time left in the metadata row | labelled dock |
| **B · Editorial Market** | art-directed, with the market visible | 4:5 hero + progress bar, "Ending soon" rail, then a thumbnail list | Oswald **mixed case** for names, Inter for everything else | explicit: hero progress bar, rail pills | labelled dock |
| **C · Premium Utility** | ledger-grade transactions, same voice | compact rows, 52 pt thumb, price right-aligned | Inter only, tabular figures | compact dot/pill in the price column | labelled dock |

All three share one transaction system — the Send/Receive/Checkout screens differ only in density, because that is where
research (§6) is unambiguous: money screens want alignment and one dominant number, not art direction.

## 2. Spacing and hierarchy rationale, screen by screen
The scale is the approved 4 pt base. What changes per direction is **rhythm**, not the unit.

| Screen | Rhythm | Card proportion / cropping | Metadata grouping | Price emphasis | Button placement | Scroll pacing |
|---|---|---|---|---|---|---|
| **Home A** | 34 between date groups, 24 between events, 9 inside a card | 3:2 — wide enough to read a flyer's type, short enough that three events fit a screen | one line for name+price, one for time·venue+live state | price at 20 pt beside the name, tabular | none on Home; the card is the target | a date header every 1–3 events gives the scroll structure |
| **Home B** | 36 between sections, 14 inside the hero stack | hero 4:5 (poster proportion), rail 1:1, list 4:5 at 76 pt | overlaid on the hero (scrim), beside the thumb in the list | hero price 20 pt on the scrim; rail price 15 pt | none | hero → rail → list is a deliberate deceleration |
| **Home C** | 16 between sections, 9 per row | 52 pt square thumb — recognition, not atmosphere | one line name, one line date·venue·bids | right column, 15 pt, tabular, with live state under it | none | uniform rows: fast scanning, no pacing tricks |
| **Listing** | 14 between blocks | A 3:2 · B 4:5 · C 16:9 (C demotes art deliberately) | date·time·venue above the name; facts as label/value rows | **current bid at 28 pt** — the largest number on the screen | sticky bar, two actions max | one panel, one fact table, then the commitment line |
| **Bids** | 8 between chips and list | 56 pt thumb | name, date·venue, then status + your-bid on one line | your bid 15 pt right, live state under | none | uniform rows |
| **Send / Receive** | 16–24 between blocks | no art | notice first, proof second, instructions third, facts last | n/a | sticky bar; the disabled reason rides on the button | notice → action → reference |
| **Checkout** | 16 | 48 pt item thumb | item, then order rows, then state notices | **total is the largest price on screen** (§6.3) | sticky bar | item → price → state → pay |

**Alignment rules that apply everywhere:** label column left, value column right, both baseline-aligned; every figure tabular
so columns line up; a section's eyebrow sits 8 pt above its first row; no nested boxes; a block gets a fill *or* a hairline.

## 3. Live-bid indicator — the mini-gallery, and the rule behind it
Six states, all derived from the auction's real `ends_at` and real bid count. Rendered in the prototype under
**Screen → Live-bid gallery**.

| # | Treatment | Appears | After expiry | Reduce Motion |
|---|---|---|---|---|
| 1 | Quiet time stamp — "Ends Fri 22:00" | more than 6 h out | replaced by the ended row | identical (no motion) |
| 2 | Live dot + time left | 6 h → 15 min, only while open | dot removed in the same render as the status change | dot static at full opacity |
| 3 | Time-progress bar (elapsed share of the final 6 h) | same window, where a second line fits | bar completes and is replaced, never left full | width set without transition |
| 4 | "Ending in 11m" pill | under 15 min — **the only red pill in discovery** | becomes "Ended" | static, no pulse |
| 5 | "Ended · won at $52" | after the real end time | terminal | identical |
| 6 | Your status: leading / outbid / won | on Bids and on a listing you bid on | "Outbid" → "Ended — not won" | value pulse skipped |

**What makes it truthful:** escalation is a function of real remaining time only. No "hot", no "almost gone", no countdown
on an auction that is not open, and every treatment disappears at expiry rather than lingering. This is the one place the
research was decisive — see §6.2.

## 4. Motion specification
On RN `Animated` with the existing `v2.motion` tokens (`instant 90 / swift 180 / settle 280`, easing
`cubic-bezier(0.22,1,0.36,1)`). Reanimated 4.1.6 is installed but there is **no `babel.config.js`**, so no worklet has ever
run in this build; nothing below needs one. Every row collapses through the existing `useReducedMotion()`.

| Trigger | Communicates | Motion | Duration / easing | Reduce Motion |
|---|---|---|---|---|
| Tab change | which section you are in | content opacity 0→1, 2 pt rise | 180 ms `swift`, brand easing | instant, no rise |
| Image load / replace | the new file replaced the old | crossfade (`expo-image` `transition`) | 180 ms | instant swap |
| Bid update arrives | the number changed, and which one | value opacity dip to 0.35 → 1 (`usePulseOnChange`) | 350 ms | no pulse; number simply updates |
| Countdown tick | — | **nothing.** Text updates silently | — | identical |
| Progress bar advance | time is moving | width transition | 600 ms, ease-out | width set instantly |
| Pull-to-refresh | the list is re-reading | existing `RefreshControl`; changed rows pulse once | 350 ms | spinner only, no pulse |
| Notice appears / clears | the screen changed its mind about whether you can act | height + opacity | 280 ms `settle` | instant |
| Failed action | nothing was lost | notice reveal only — **no shake, no bounce, no colour flash** | 280 ms | instant |
| Success on a task screen | it is done | state block fades in while the action row fades out | 280 / 180 ms | both instant; haptic unchanged |
| Sheet open/close | where it came from | RN `Modal` slide (existing) | system | existing fade |

**Two prohibitions, from the research:** never animate a warning or a price into view in a way that draws a second look
(§6.6), and never animate on a per-second tick — a countdown that pulses every second is decoration pretending to be
information.

## 5. Visual distinction between the three classes of surface
The owner asked for a clear line between discovery, marketplace activity and irreversible action. The system:

| Class | Surfaces | Signature |
|---|---|---|
| **Discovery** | Home, Listing, search | art-led, no filled red anywhere, live state is informational, actions are navigational |
| **Marketplace activity** | Bids, Tickets, payout status | no art beyond a 56 pt thumb, status words carry colour (green leading, amber outbid), one filled action at most |
| **Irreversible action** | Place bid, Buy now, Mark as sent, Confirm receipt, Pay | sticky bar, exactly one filled red action, its consequence on the button's own sub-line ("this releases payment to the seller"), and a fact table above it that never scrolls away without the user having passed it |

## 6. Research notes — observations, then what I took from them
Apple's material is in `FIVE_DIRECTIONS_20260917.md` §11a (iOS 26/27 Liquid Glass, typography floors, tab-bar labels,
sheets, motion) and is not repeated. Below is the product research. **Observations are the cited products' behaviour; the
"taken" column is mine.** Where a product could not be verified it says so — no gaps were filled from category knowledge.

### 6.1 Discovery and card composition
| Observation | Source | Taken |
|---|---|---|
| DICE cards carry **exactly four fields in a fixed order** — title, date, venue, price — on 23/23 cards measured; price always present, "From" prefix for tiered events | [DICE browse](https://dice.fm/browse/london-54d8a23438fe5d27d500001c/music/gig) | Four is the floor. Our card adds a fifth — live state — because an auction's remaining time *is* decision information, unlike a fixed-price gig |
| Shotgun: 16:9 image cards, 6–7 fields, price always on the card, ~2.5 events per phone screen | [Shotgun NYC](https://shotgun.live/en/cities/new-york) | The density cost of image-led cards, measured. Hybrid A's 3:2 crop is the compromise |
| Resident Advisor: listing rows carry **no images at all** (verified by control test — the event page does load images) and **no price**; ~6–7 events per screen | [RA London](https://ra.co/events/uk/london) | Proof that density and beauty are a real trade, not a false one. Hybrid C is the RA end of that axis, and it is why C is recommended for transactions, not discovery |
| Eventbrite cards: three fields and **no price**; geography as **neighbourhood · venue** rather than an address; relative dates near-term | [Eventbrite NYC](https://www.eventbrite.com/d/ny--new-york/all-events/) | Adopted the neighbourhood·venue idea for orientation over precision, and relative dates inside the near window |
| Posh and Partiful both put the **social signal above the title** (organiser; attendee count) | [posh.vip/explore](https://posh.vip/explore), [Partiful explore](https://partiful.com/explore) | Not adopted: our seller identity is not the draw, and our own research says the price is. Recorded as considered-and-rejected |

### 6.2 Urgency — the decisive finding
| Observation | Source | Taken |
|---|---|---|
| **Zero** scarcity vocabulary on any discovery surface across DICE, Posh, Shotgun, RA and Eventbrite — five products, measured directly | the five links above | Our discovery grid carries no urgency decoration. The only red pill appears under 15 real minutes |
| DICE pushes **low stock as a notification to people who saved the event**, not as a grid badge; wait-list availability is shown on the ticket | [DICE help](https://dicefm.zendesk.com/hc/en-gb/articles/22365422759313-Getting-started-with-DICE) | Urgency is a message to someone who already expressed interest — which is our outbid/ending-soon push, not a permanent clock |
| Shotgun and Posh render **sold-out tiers in place**, muted, no badge; Shotgun uses ordinary metadata grey | [Shotgun event](https://shotgun.live/en/events/boof-folsom-2026), [Posh KB](https://support.posh.vip/en/articles/15075671-ticket-management-creating-ticket-tiers-groups-and-advanced-toggles) | Our "Ended" state is muted and in place, never red |
| StubHub's event page reportedly stacked **five urgency devices at once** and was sued by DC's AG over drip pricing and a countdown; the FTC sent a warning letter | [Hall of Shame](https://hallofshame.design/stubhub-dark-patterns-in-event-ticket-sales/), [OAG DC](https://oag.dc.gov/release/attorney-general-schwalb-sues-stubhub-deceptive), [FTC letter](https://search.ftc.gov/system/files/ftc_gov/pdf/stubhub-wl.pdf) | The anti-pattern, named in the doc so nobody re-proposes it |
| Shotgun's waiting list lets **auto-pay raise queue priority**; RA **randomises** pre-sale queue positions | [Shotgun help](https://support-pro.shotgun.live/hc/en-us/articles/17500892760978-Charge-Now-and-The-Waiting-List), [RA QueueIT](https://support.ra.co/article/49-queueit) | Rejected the first, noted the second: fairness is a design property, and randomisation defeats millisecond advantage |

### 6.3 Price hierarchy — and a rule with legal force
| Observation | Source | Taken |
|---|---|---|
| **FTC junk-fees rule, effective 2025-05-12:** the total must be **the most prominent price on the screen**; itemisation is permitted but not required; a later disclosure **does not cure** an early partial price | [FTC FAQs](https://www.ftc.gov/business-guidance/resources/rule-unfair-or-deceptive-fees-frequently-asked-questions), [Federal Register](https://www.federalregister.gov/documents/2025/01/10/2024-30293/trade-regulation-rule-on-unfair-or-deceptive-fees) | Made it a measured acceptance criterion, not an intention (§8). **It immediately caught a defect in my own prototype** — the checkout total rendered at the same 13 pt as its line items, because a row style out-specified the price class. Fixed, then re-measured |
| Posh's tier sheet: **one all-in price as the dominant numeral, with the fee named in a smaller line underneath** | [Posh KB](https://support.posh.vip/en/articles/15075671-ticket-management-creating-ticket-tiers-groups-and-advanced-toggles) | This is the shape our checkout uses |
| Partiful: **all-in headline at browse time, itemised at the moment of payment** | [Partiful help](https://help.partiful.com/hc/en-us/articles/50427922740763-What-fees-will-I-pay-for-a-ticket) | Same as ours, and it confirms the split is legitimate rather than a compromise |
| RA documents **advising promoters against** splitting the fee out of the display price | [RA adding tickets](https://support.ra.co/article/186-adding-tickets) | A platform arguing against its own itemisation option is the strongest available precedent for all-in display |
| Airbnb made total-price display default in 2022 and then **removed the toggle** in 2025 | [2022](https://news.airbnb.com/airbnb-is-introducing-total-price-display-and-updating-guest-checkout), [2025](https://news.airbnb.com/total-price-display-is-now-standard-globally) | **A toggle is a transition state, not a destination.** Offering a choice between two truths is itself a fee-hiding affordance — and StubHub's buried toggle is what a regulator attacked |
| Posh and Partiful independently converged on **dual price entry** for sellers (type either the buyer price or your payout; the other computes) | [Posh KB](https://support.posh.vip/en/articles/15075671-ticket-management-creating-ticket-tiers-groups-and-advanced-toggles), [Partiful help](https://help.partiful.com/en-us/articles/15525398-what-fees-does-partiful-charge) | Carried into the cross-product work as a seller-side pattern, not a consumer one |
| **Our app already displays all-in prices** — `allInFromDollars`, the "all in" suffix on cards, and a preformatted all-in listing price | verified by B in `src/components/discovery/DiscoveryCard.tsx:119`, `src/lib/listing/detailState.ts:106` | No finding. Recorded as a strength, and as the reason the rule above is an acceptance criterion rather than a repair |

### 6.4 Holds, and provisional versus authoritative state
| Observation | Source | Taken |
|---|---|---|
| Eventbrite's checkout hold is **20 minutes, organiser-adjustable, framed as the tickets being held unavailable to others** | [Eventbrite help](https://www.eventbrite.com/help/en-us/articles/435853/how-to-increase-or-decrease-the-amount-of-time-to-complete-an-order/) | Our hold notice says what is held and that nothing is charged — reservation framing, never a penalty clock |
| Monzo keeps **displayed balance and settled balance separate in the ledger**, so a pending transaction cannot read as settled | [Monzo](https://monzo.com/blog/2022/02/18/how-we-calculate-balances) | The clearest external statement of the rule our payments work already follows: a provisional figure must look different from an authoritative one. Applied to "leading bid" and to the unreachable-payment state |
| Stripe: an authorisation hold can surface in a bank app as a **pending charge alongside the final charge**, reading as two transactions | [Stripe](https://stripe.com/resources/more/authorization-holds-explained) | Our hold copy should say the hold is not a charge. Stripe describes the confusion; the disclosure is my inference |
| Partiful gives **waitlisted its own label**, not a variant of going | [Partiful help](https://help.partiful.com/en-us/articles/15525409-what-happens-if-the-waitlist-is-turned-off) | Same discipline as never showing "you're leading" for a bid the server has not accepted |

### 6.5 Irreversibility, and disabled capability
| Observation | Source | Taken |
|---|---|---|
| Posh transfers are **two-phase: pending until accepted, cancellable by the sender**, and the sender's old QR then reads **cancelled** rather than failing silently | [Posh KB](https://support.posh.vip/en/articles/10723763-how-to-transfer-tickets) | Our Send screen shows a terminal state after marking sent, and the Receive screen names what confirming releases |
| Where a tier has transfers disabled, Posh renders the action **greyed out rather than hidden** | same | Our disabled CTA carries its reason on its own sub-line — the capability's absence is explained, not invisible |
| DICE makes ticket activation a **one-way gate that removes transfer**, and says so on the ticket | [DICE help](https://dicefm.zendesk.com/hc/en-gb/articles/19413725197713-How-to-activate-your-tickets-on-the-day-of-the-event) | Irreversible steps state their consequence at the point of action, not in terms |
| Robinhood **removed its confetti** animation, and separately was fined over **misleading displayed financial state** (buying power, balances, margin) | [Robinhood newsroom](https://robinhood.com/us/en/newsroom/the-top-secret-robinhood-design-story/), [CNBC](https://www.cnbc.com/2021/06/30/robinhood-to-pay-70-million-for-misleading-customers-and-outages-the-largest-finra-penalty-ever.html) | No celebration on a transaction, and displayed state is a correctness surface, not a decoration surface |

### 6.6 Typography, motion budget and systems
| Observation | Source | Taken |
|---|---|---|
| DICE runs **one neutral grotesque at weight 400** for all product content, `h1` 25 px/400, with all-caps confined to 11–12 px chrome — while its **uppercase-only display face lives in marketing** | measured on dice.fm; [foundry](https://ohnotype.co/custom/dice) | The single most reassuring finding for the calm work: expressive type belongs to marketing. Oswald stays, at one place per screen |
| Posh: two cuts of one grotesque, `h1` 16 px/400, **zero uppercase on the whole discovery page**, five size/weight combos | measured on posh.vip | Hierarchy by weight and position, not by a size ramp |
| RA: three families, with **11 px monospace reserved for metadata** — venue, counts, chips | measured on ra.co | Considered, not adopted: a third family is a real cost, and our tabular Inter already does the "reference data" job |
| DICE's entire documented in-app motion budget: **eight Lottie illustrations, 1–3 s, on one upsell surface**, with the static image carrying the meaning | [Animade](https://archive.animade.tv/work/dice-extras) | The motion budget in §4 is deliberately smaller than what we could build |
| Posh spends its animation budget on **organiser-supplied flyers**, not chrome | [Posh University](https://posh.vip/university/post/designing-a-high-converting-event-page-visuals-strategy-best-practices) | Our motion stays out of the content the seller supplies |
| Eventbrite's design system: **400+ tokens, two brand themes, four colour modes, a responsive token dimension**, and a shift from colour-encoded button hierarchy to **shape and monochrome** | [Marmalade case study](https://www.tnflnt.co/work/eventbrite-marmalade) | The button-hierarchy shift is what our "one filled action per screen" rule already implies; the four colour modes are the model for an increased-contrast variant later |
| Things enforces restraint **by scaling** — vector icons and layouts retuned so type and chrome grow together under user text settings | [Cultured Code](https://culturedcode.com/things/blog/2023/09/things-big-and-small/) | Our largest-text frames grow icons and rows with the text rather than capping the layout |
| Partiful's RN contractor **substituted linear gradients for native blur** on Android after blur failed | [Software Mansion](https://swmansion.com/case-studies/partiful/) | Direct support for the no-new-dependency scrim over a blur dependency |
| Linear: opinionated defaults over configuration, and **don't invent vocabulary** | [The Linear Method](https://linear.app/method/introduction) | Our state words stay plain: sent, confirmed, held, ended, outbid |
| CrowdVolt and StockX | **not yet reported** — that agent is still running | The live-market half of §6.2/§6.3 rests on the five products above; CrowdVolt/StockX will be appended as §6.7 or recorded as a gap |

**Evidence quality, carried from the research:** no product **screenshot** was viewed anywhere — App Store images have no
alt text — so nothing here describes a native app screen. Claims marked "measured" were read from live official web pages;
help-centre text reached only through a search index is labelled in the research report. SeatGeek's and StubHub's live
surfaces were largely unreachable, and their entries are secondhand by necessity.

## 7. Comparison matrix
B's judgement, 1–5 (5 best); **implementation cost inverted** (5 = cheapest). Measured inputs in the row below.

| | Visual appeal | Usability | Discovery | Transaction clarity | Accessibility | Impl. cost |
|---|---|---|---|---|---|---|
| **A · Gallery Index** | 5 | 4 | **5** | 4 | 4 | **5** |
| **B · Editorial Market** | **5** | 3 | 4 | 3 | 3 | 4 |
| **C · Premium Utility** | 3 | **5** | 2 | **5** | **5** | **5** |

Measured: events visible per Home screenful — A 2–3, B 1 hero + 2 rail + 2 list, C 5+. Filled-red blocks per screen — one
at most in every direction, and zero on Home. Frames that fit their viewport at largest text without the action leaving the
screen — A and C on every screen; B's hero pushes the first list row below the fold.

## 8. Recommendation, and what to carry into the others
**Lead with A (Gallery Index) for discovery, C (Premium Utility) for the transaction and activity screens, and take two
details from B.** That is one product: A and C share the type scale, the notice ranks, the dock and the action rules — they
differ only in density, which is exactly how DICE and RA differ from each other while each staying coherent.

**Carry from B:** (1) the **hero progress bar** on a listing whose auction is inside its final six hours — B's one genuinely
new idea, and the honest version of urgency; (2) the **"Ending soon" rail** on Home, but populated strictly by real
remaining time and empty when nothing qualifies — an empty rail is the correct state, not a reason to loosen the rule.

**Do not carry from B:** the 4:5 hero as the default Home unit. It is beautiful and it costs the fold at largest text.

## 9. Implementation sequence
Every stage is reviewable on its own and reversible. Release-critical state fixes from the first audit (the `0`-floor bid
form, the re-entrant destructive actions, Home's in-flight empty state, the avatar spinner) **still come first and are C's**.

| Stage | Contents | Files / components | Dependencies | Device checks (C) | Acceptance criteria |
|---|---|---|---|---|---|
| **H0** | Live-bid state machine, pure logic | new `src/lib/listing/liveBid.ts`; unit tests | none | — | Given `ends_at` and now, returns exactly one of the six states; a mutant that widens a boundary fails a test; no state renders after expiry |
| **H1** | `Notice` primitive, three ranks | new `src/components/ui/Notice.tsx`, `ui/index.ts`; replaces hand-rolled boxes in both transfer screens, `settings/index`, `CreateListingScreen` | H0 for the ranks' colour roles | VoiceOver reads the blocking notice before the disabled CTA | At most one blocking notice per screen (assertable); the disabled CTA's reason comes from it |
| **H2** | Live-bid rendering in discovery and Bids | `DiscoveryCard.tsx`, `bids/BidCard.tsx`, `listing/TransactionPanel.tsx`, `src/lib/bids/bidState.ts` | H0 | dot and pill legible at largest text; Reduce Motion leaves a static dot | No treatment appears for an auction past `ends_at`; the pill appears only under 15 real minutes |
| **H3** | Home layout A | `app/(tabs)/home.tsx` (SectionList, as `tickets.tsx` already does), `discovery/DiscoveryCard.tsx`, a new 3:2 slot in `src/lib/media/slots.ts` | H2 | scroll pacing on device; date headers sticky or not, owner's eye | Four fields plus live state per card; total price dominant where a price appears; no card taller than 0.55 × viewport at largest text |
| **H4** | Transaction density C | `app/transfer/send/[id].tsx`, `app/transfer/receive/[id].tsx`, `src/screens/checkout/CheckoutNative.tsx`, `ui/StickyBar.tsx` | H1; **and C's handset pass finished** | the disabled reason readable at largest text; one-handed reach for the sticky action | **The total is the most prominent price on the screen, measured** (FTC §6.3); exactly one filled action; every blocker stated once |
| **H5** | Motion | `usePulseOnChange` (existing), `MediaUpload`, `Notice`, both transfer screens | H1–H4 | Reduce Motion on device for all ten rows in §4 | Every animation collapses through `useReducedMotion()`; no per-second animation; no motion on a warning |
| **H6** | Listing hero progress (from B) | `listing/TransactionPanel.tsx` | H2 | — | Bar derives from real remaining time; hidden outside the final 6 h; completes and is replaced at expiry |

**No new dependency at any stage.** Glass stays out: Apple's guidance keeps it on chrome, `expo-blur` is absent, and
Partiful's contractor published the same substitution we are making — a gradient where a blur is not affordable.

## 10. What B cannot verify
No device, no simulator, no screenshot of our app; "largest text" is simulated by scaling the type tokens with display
capped at 1.3× as the app does. Dynamic Type on device, iOS font metrics, one-handed reach and the live badge inset are
C's. Every product observation above is web-surface or documentation evidence — no competitor's native app was seen.

### 6.7 Live-market research (CrowdVolt, StockX, eBay, Sotheby's, Robinhood, Monzo) — and two changes it forces
| Observation | Source | Taken |
|---|---|---|
| **eBay publishes an accessibility pattern for clocks:** do not announce a countdown every second to a screen reader — space announcements **at least 15 s apart** and convey only meaningful thresholds | [eBay MIND — Time](https://ebay.gitbook.io/mindpatterns/messaging/time) | **Change 1 to §3:** the live-bid spec now carries a screen-reader cadence, not just a no-animation rule. A visual countdown may tick every second; the accessible announcement may not |
| CrowdVolt explains a bid as a **bank authorisation, not a charge**, names the release conditions (filled, cancelled, expired) and the real 3–5 business-day lag | [CrowdVolt](https://www.crowdvolt.com/help_center/question/made-bid-why-charged) | Our hold copy should say what the *bank* will show, not only what we mean. "Nothing has been charged" is necessary but not sufficient if a pending line appears on a statement |
| StockX **fixes the fee at the moment of bidding**; it cannot move afterwards | [StockX](https://stockx.com/help/en-GB/articles/what-are-stockx-fees-for-buyers) | A market number may move; a fee may not, once committed. Matches our accepted-total behaviour |
| Robinhood documents a **complete order state machine with fixed names** — placed, pending, filled, partially filled, cancelled, pending-cancel, rejected, failed — and pending is defined by what resolves it, never by a spinner | [Robinhood](https://robinhood.com/us/en/support/articles/event-contracts-order-fills/) | **Change 2 to §3:** treatment 6 becomes an enumerated vocabulary — *placed · leading · outbid · won · ended, not won · not placed (failed)* — with one fixed word per state and the ugly ones named, rather than three happy labels |
| RM Sotheby's puts bid state **on the lot page**, not only in the notification | [RM Sotheby's](https://rmsothebys.com/general-online-bidding-faqs/) | Already our shape: Bids and the listing both render status. Recorded as external confirmation |
| Sotheby's and eBay both **extend the clock on a late bid** (anti-snipe), and disclose that lots can then close out of order | [Sotheby's](https://help.sothebys.com/en/support/solutions/articles/44002518078-guide-for-buyers-global), [eBay](https://www.ebay.co.uk/help/buying/bidding/bidding-items?id=4003) | **Not mine to propose.** It changes auction mechanics and therefore transfer/payment rules, which this work must not touch. Recorded as a product question for the owner, with the precedent attached |
| Sotheby's keeps the **leading bid public and a bidder's maximum private** | same | Relevant only if proxy bidding is ever added; recorded, not designed |
| Robinhood **removed post-trade confetti** under regulatory pressure; the settlement included a commitment never to use it again | [CNBC](https://www.cnbc.com/2021/03/31/robinhood-gets-rid-of-confetti-feature-amid-scrutiny-over-gamification.html) | The strongest available argument for §4's no-celebration rule: on a financial commitment, celebratory motion is a regulatory question, not a taste one |
| The FTC's dark-patterns report names **baseless countdown timers and false low-stock messages** as deceptive design | [FTC report](https://www.ftc.gov/system/files/ftc_gov/pdf/P214800+Dark+Patterns+Report+9.14.2022+-+FINAL.pdf) | Every urgency signal in §3 renders a stored fact — a real `ends_at`, a real bid count — or it does not render |
| **StubHub refunded $10M** after the FTC charged that its first pricing display omitted mandatory fees | [FTC, Apr 2026](https://www.ftc.gov/news-events/news/press-releases/2026/04/stubhub-refunding-10-million-fees-consumers-after-deceptive-ticket-pricing) | Total-price prominence stays a measured acceptance criterion (§9 H4) |
| Monzo's writing system: short, **active voice naming who acted**, same word for the same state everywhere | [Monzo](https://monzo.com/blog/weve-made-our-writing-system-available-to-all) | Adopted as the rule behind the state vocabulary above, and in the dashboard work |
| CrowdVolt sends **success and failure through the same channel with the same payload** | [CrowdVolt](https://www.crowdvolt.com/help_center/general/order-go-through) | A failed action must be as loud as a successful one, and reach the user the same way |

**Not knowable from public material:** neither CrowdVolt nor StockX publishes a design system, type scale or numeric
alignment convention, and CrowdVolt's logged-in bid-status UI is behind authentication. Their contribution here is
mechanics and vocabulary, not visual reference. eBay and Monzo are the only subjects in either research pass that publish
accessibility or writing systems at all.
