# Snatch It — V2 Navigation & Tickets Direction

**Status:** APPROVED DIRECTION — not yet implemented. Recorded 2026-09-03 after the owner
reviewed DICE and Posh native references. This is a design north star for future batches; **no
adaptive-navigation or Tickets code ships until its own dedicated batch.**

> These findings take **behavioral and structural lessons** from DICE and Posh. They are **not** a
> license to copy either product. Snatch It keeps its own approved V2 identity: black / white /
> `#FF1A1A`, radius 0, Oswald display + Inter body, restrained red, sharper than both references.

---

## 1. Primary navigation north star

Future primary destinations:

```
HOME · CREATE · BIDS · TICKETS · PROFILE
```

- **Search is not a primary tab.** It lives inside Home / discovery as a discovery utility.
- **TICKETS becomes a primary destination** once Core exposes the canonical ticket contract
  (see §4). Until then it is not built.
- BIDS and TICKETS are **distinct products** (see §3).

This replaces today's `Home · Create · Bids · Profile`. The redesign is deferred to its own batch;
every screen built now is designed to slot into this five-destination model.

## 2. Adaptive Home navigation (Snatch It's own version)

The behavioral lesson from DICE is *navigation gets out of the way while browsing*. Snatch It will
build its **own** version, **Home-only**:

- **Resting / top of Home:** the full floating dock is shown (`Home · Create · Bids · Tickets · Profile`).
- **On intentional scroll DOWN** past a threshold (~70–100pt, tune on device), the full dock
  **compresses** into a much smaller floating control showing only the active **Home** icon — to
  maximize event-artwork and discovery canvas.
- **Restore the full dock** when the user scrolls up, nears the top, or taps the collapsed control.
- The trigger is **scrolling down**, never merely "Home is open."

**Collapse is Home-only.** Create, Bids, Checkout, Profile, Settings, Transfer and Tickets keep
predictable, always-visible navigation — they are transactional / utility contexts.

### Dock visual direction

Floating, compact, black, sharp, mostly iconographic, restrained, intentionally separated from the
device bottom edge. **Not** the DICE pill, **not** the Posh tab bar, **not** a full-width Expo tab
bar, no giant red selected background, no glassmorphism, no blur-for-its-own-sake, minimal labels.
Motion: fast, mechanical, controlled (~180–240ms), no spring/bounce/morph.

## 3. BIDS vs TICKETS

| BIDS (exists today) | TICKETS (future, blocked) |
| --- | --- |
| Auctions I'm bidding on | Tickets I actually own |
| winning / outbid / ended | official-event issued tickets |
| my participation in auctions | fulfilled resale purchases |
| — | upcoming + past owned tickets |

Potential Tickets hierarchy: **UPCOMING** / **PAST** — *only if the canonical data supports it.*

## 4. Tickets contract — HARD BLOCK

`kernel.tickets` authenticated SELECT is **ABSENT** unless Core explicitly changes it. Therefore,
until Core delivers the canonical ticket contract, do **not**:

- build a Tickets tab or call purchase history "Tickets";
- build QR / barcode / Apple Wallet / ticket-wallet placeholders;
- invent official ticket objects or fake past attendance;
- query `kernel.tickets`.

Ownership today is expressed **only** through the transfer state machine (Phase 4 Bids + Phase 7
Transfer), never as a ticket object.

### Future Tickets visual direction (once real data exists)

Event-first: artwork, event name, date, venue, ticket type, quantity, ownership/fulfillment state —
**not** order IDs or payment IDs. Past tickets read as an **event-history / memories** layer, not an
accounting log. Never claim attendance the data does not support.

## 5. Profile north star

Direction: **DICE-level cleanliness + Snatch It transaction / ownership relevance.** Not a
social-media dashboard. Do **not** invent followers, following, views, ratings, verification or
promoter stats unless Snatch It genuinely ships those contracts.

Profile answers: **who is this account? · what's relevant to their Snatch It activity? · what can
they do next?** Structure: identity → compact relevant activity → actions → event history / owned
activity when authoritative. Real metrics only where supported (Sold, Bought, trust/rating if
canonical). The Phase 6 Profile is directionally aligned; lower-profile content can become more
event-visual over time. Settings stays separate.

## 6. What stays different about Snatch It

Sharper, less rounded, more transactional, more black/white, restrained red, more price-aware, more
bid-aware, more ownership-aware than either reference. Oswald 700 = Snatch It display voice; Inter =
events, people, prices, forms, transaction data. The approved native Oswald line-height correction
stays.

---

**Implementation note:** this document is direction only. The adaptive dock, the Tickets surface,
and the five-tab navigation are each their own future batch, gated on owner approval and (for
Tickets) on the Core ticket contract.
