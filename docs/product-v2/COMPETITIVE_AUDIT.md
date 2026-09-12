# Competitive audit: POSH, DICE, CrowdVolt, Snatch It

**Method.** Three independent agents read shipped code, not screenshots: compiled CSS, JavaScript
chunks, image CDN parameters, server-rendered payloads, structured data and public documentation.
The underlying research files tag every claim OBSERVED or INFERRED. Full evidence in
`_research/posh.md`, `_research/dice.md`, `_research/crowdvolt.md`.

> **Read this before citing anything here.** This synthesis document is **not** tagged line by line,
> and an adversarial review (finding J-6) found that flattening the tags let two inferences read as
> facts. Corrected here: CrowdVolt's take rate of roughly 4% per side is **inferred** from live
> price data, since the rate is never disclosed; and DICE's "all-in pricing" is **inferred** from the
> absence of any fee string in its shipped translation dictionary, which is strong evidence of a
> practice but is not the same as the practice being stated. Do not let either number reach a
> pricing decision without checking the tagged source file.

**Purpose.** Understand why these interfaces work, then reinterpret the principles through Snatch
It's own brand. Nothing here proposes copying markup, assets, type stacks or color.

---

## 1. Who these companies are, relative to us

| | Business | Content | Closest to Snatch It in |
|---|---|---|---|
| **POSH** | First-party nightlife ticketing | Portrait party flyers with type in them | **Content type.** Same artwork problem exactly. |
| **DICE** | First-party gig ticketing, mobile-first | Artist photography, label artwork | **Engineering discipline.** |
| **CrowdVolt** | Ticket resale marketplace | Artwork ingested from primary platforms | **Business model today.** |
| **Snatch It** | Resale today, venue-direct tomorrow | Seller screenshots today, venue artwork tomorrow | Becoming all three at once |

Snatch It is the only one of the four attempting first-party ticketing and resale in the same
product. That is the strategic opportunity and the design problem.

---

## 2. Imagery: three different solutions to one problem

Every platform faces the same thing: artwork arrives in inconsistent shapes and must fill consistent
boxes. Each solved it differently, and the differences are instructive.

**POSH locks the frame and gives the organizer a choice.** Every image sits in a 4:5 frame. The
organizer sets a flag per event: crop, or fit. When fit is chosen, the image is contained and the
leftover area is filled with a blurred, 1.2x-scaled copy of the same flyer, with the real image's
edges feathered into that backdrop by a gradient mask along whichever axis has slack. Real numbers:
card image 224x280 in a 240 slot, 4px radius, Cloudflare transforms at quality 75 with
`fit=scale-down` so nothing is ever upscaled. There are no black letterbox bars anywhere in the
product. This is the only system of the three that gets a uniform grid **and** never decapitates a
poster's typography.

**DICE normalizes mechanically and never trusts the upload.** Every source is centre-cropped to a
square master, the crop rectangle is stored, and exactly three canonical crops derive from it. The
CDN width is literally the same number as the CSS box, and quality halves as pixel density doubles,
holding bytes flat. Slots are pre-painted a flat colour with intrinsic dimensions declared, so
nothing flashes and nothing shifts. It looks art-directed precisely because it is not: consistent
errors beat occasionally brilliant crops at grid scale.

**CrowdVolt refuses to have the problem.** All 521 live events carry artwork, because it is
ingested from the primary platforms rather than uploaded by sellers. Every landscape master measures
exactly 5:3. Each event carries three image fields with cross-fallback, and missing squares are
machine-generated. A resale marketplace with no image problem, because it never let sellers supply
images.

**Snatch It has none of this.** One asset is poured into six container ratios across three surfaces,
discarding up to 58.5% of the image. There are zero transformations anywhere, a 6.3 MB original is
shipped into a 358x180 card, cache headers are wrong by four orders of magnitude, and the two upload
paths contradict each other. See `EVENT_MEDIA_SYSTEM.md`.

**What we take.** POSH's framing model, because our content is flyers and POSH is the only one
solving for flyers. DICE's delivery discipline, because it is simply correct engineering.
CrowdVolt's insight in an adapted form, below.

### The CrowdVolt insight, adapted

CrowdVolt solved artwork coverage by ingesting from the source rather than from sellers. Snatch It
gets the same result from its own architecture, for free, the moment venue-direct ticketing exists:
**a resale listing attached to a real event inherits that event's artwork.** The venue uploads one
good flyer, and every fan reselling a ticket to that night gets it automatically. Today a seller
uploads a screenshot and the marketplace looks like a classifieds board. This is the strongest
non-obvious argument for the unified event model, and it is why listing creation must make sellers
pick a real event rather than type venue text.

---

## 3. Typography: all three are quieter than we expect to be

| | Display face | Event title treatment |
|---|---|---|
| POSH | Neue Haas Grotesk Display | 48px, weight 600. Card titles **weight 400**, same as metadata. Hierarchy from size and colour, never weight. No CSS uppercase anywhere. |
| DICE | ABC Favorit | 35px at **normal weight**. Not bold, not uppercase. Price is the only bold element and is deliberately dimmed. |
| CrowdVolt | System-ish sans | Title below image, price `text-5xl` bold tabular. |
| Snatch It | Oswald 700 uppercase (marketing) | Mobile app loads **no font at all**. |

The lesson is not "be neutral". It is that **type gets out of the artwork's way**. Both first-party
platforms deliberately avoid heavy display type next to a poster, because the poster already
contains display type, and two competing headlines look like a mistake.

This constrains our brand translation. Oswald uppercase is right for screen titles and section
heads, which are our voice. It is wrong for an event title sitting under someone else's flyer. There
it must be Inter, sentence case, because the event name is user-generated content that arrives in
mixed case and often runs long.

---

## 4. Fees and price honesty: the clearest differentiator

**DICE deleted the concept.** Searching roughly 1,328 shipped translation keys for "fee" returns
zero booking or service fee strings. Prices are all-in, which is why they are not round: "From
£39.22". The odd number is the proof. They did not disclose the fee well, they removed the
disclosure step, and their vocabulary consequently has no word for it.

**CrowdVolt is all-in where it matters**, with a three-state price ladder that is never blank:
lowest all-in ask, else last sale, else "Be the first to sell". The seller composer shows both sides
live: what you get, what buyers pay. The fee rate itself is never disclosed and reads about 4% per
side.

**POSH promises transparency and breaks it.** Cards show $25.00 while the event carries a
`minPriceWithFees` of $29.24, a 17% gap, and the "show fees in price" control is a per-event toggle
that the ticket component then hard-codes to true anyway.

**Snatch It already ships all-in pricing**, which is the right side of this and is currently
under-communicated. Two consequences: make all-in an invariant rather than a setting, and show the
all-in number on the card, not just at checkout. Given a resale heritage, price honesty is the
cheapest credibility Snatch It can buy.

---

## 5. Trust and provenance

**CrowdVolt is the most instructive**, because it sells other people's tickets, as we do today.

- The guarantee is stated three times at tightening altitudes: legal terms, help centre, product
  line. It is never given a brand name.
- It is funded by a **seller clawback**, not an insurance pool: a delivery SLA keyed to time to
  event, tightening from 24 hours down to 15 minutes after doors, with a dropped-order penalty
  stated as up to or greater than 200% of the sale price, agreed at listing time in one sentence.
- Seller trust is reputation-forward and identity-light: first name, avatar, transaction count,
  review count, join date. Across 42 live rows, a verified badge appeared once.
- Three help articles pre-answer the fears that make a legitimate ticket look fake: someone else's
  name on the ticket, seat numbers on a general admission ticket, the ticket living in another app.

**DICE takes the opposite route**: it eliminates resale entirely, markets that to organizers as
yield recovery, and replaces the secondary market with a wait list.

**Snatch It's position is different from both** and better than either for its own strategy: it will
have first-party inventory and a marketplace in one product. That means it can show something
neither can, an unbroken chain from issue to transfer, and face value shown beside a resale ask.
That is a stronger claim than any guarantee, and the custody ledger to back it is already deployed.

The obligation that comes with it: **never present a resale ticket as venue inventory**. Provenance
in words, on every purchasable row.

---

## 6. What Snatch It should take, and what it must avoid

**Take**

1. POSH's locked frame with an organizer-chosen crop or fit, and a blurred self-backdrop rather than
   letterbox bars.
2. POSH's ambient theming: derive the event page's background from the event's own artwork. It makes
   third-party venue art look art-directed with zero venue effort, which is exactly the problem
   venue-native ticketing creates.
3. DICE's delivery discipline: CDN width equals layout token, quality inversely proportional to
   density, pre-painted slots, intrinsic dimensions, no layout shift.
4. DICE's fee posture: all-in as an invariant, no toggle, no disclosure step.
5. CrowdVolt's three-state price ladder, so a card is never blank.
6. CrowdVolt's habit of pre-answering the fears that make a real ticket look fake.
7. The artwork-inheritance idea, adapted: resale listings inherit the venue's event artwork.

**Avoid**

1. **POSH's fee inconsistency.** Transparency cannot be a per-event setting.
2. **DICE's app-only ticket gating.** DICE has the demand to absorb the friction; we do not. Take
   the activation idea, not the distribution lock.
3. **POSH's thin mobile web.** A venue's shared link must work fully for someone who has not
   installed the app, or venue-direct ticketing cannot spread.
4. **CrowdVolt's small contradictions**: an IP-guessed city fighting the filter chip in the same
   paint, pre-fee prices in structured data while cards show all-in, a 404ing fallback image, avatar
   thumbnails requested at full resolution.
5. **Adopting anyone's typographic neutrality wholesale.** POSH is neutral because it has no
   identity by design. Snatch It has one. Be neutral next to artwork, not everywhere.
6. **Letting brand red own ambient colour.** If red tints every event page, every event looks like
   Snatch It instead of itself. Red is for what the user can tap.

---

## 7. Where Snatch It can be better than all three

1. **One event, both kinds of inventory, honestly labelled.** None of the three does this. CrowdVolt
   has no first-party inventory, DICE forbids resale, POSH does not run a marketplace.
2. **Provenance backed by a real custody ledger**, already deployed, rather than by a policy promise.
3. **Face value beside the resale ask**, which is only possible when you issued the original ticket.
4. **Price history**, which CrowdVolt models and does not ship.
5. **A brand with an actual point of view.** All three are visually careful and largely
   interchangeable. Snatch It's marketing site is not interchangeable with anything. The
   opportunity is to carry that into the product without letting it fight the artwork.
