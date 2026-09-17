# Consumer information architecture V2

**Status:** proposal, pending owner approval. Nothing here is built.

The central decision in this document is not the tab bar. It is that **Snatch It becomes
event-first**, with direct and marketplace inventory presented as two ways to get into the same
night rather than as two products.

---

## 1. What exists today, and why it does not work

Measured from `app/(tabs)/_layout.tsx`:

| Tab | Route | Assessment |
|---|---|---|
| Home | `home` | Keep as a destination, rebuild the content model. |
| Create | `create` | Wrong for a primary tab. Selling is a periodic act. |
| Bids | `bids` | A market mechanic, not a user goal. Only meaningful when you have live bids. |
| Profile | `profile` | Keep, but it is currently carrying jobs that deserve their own home. |
| Explore | `explore` | **Exists in the codebase and is hidden from the tab bar** (`href: null`). |

Five structural problems:

1. **There is no Tickets destination.** This is a ticketing app in which the most frequent
   recurring job, "get me into the venue tonight", has no home. That job is now urgent, physical,
   and time-boxed. It must be reachable in one tap from any screen.
2. **Selling occupies prime real estate.** Most sessions are buying sessions. A permanent Create
   tab spends the most valuable slot in the app on the rarer act.
3. **Discovery is hidden.** Explore is written and unreachable. Top of funnel is switched off.
4. **The app is listing-first while the brand is event-first.** snatchitapp.com leads with
   "UP NEXT IN MIAMI / WHERE THE CITY IS GOING" and shows an event, a venue and a date. The app
   leads with resale listings. Venue-native ticketing cannot be bolted onto a listing-first model.
5. **Bids compete with tickets for attention** even when the user has none.

## 2. The unified event model

This is the load-bearing idea.

Today a listing is the primary object: a user browses listings, each of which happens to belong to
an event. In V2 **the event is the primary object**, and every purchasable thing hangs off it:

```
EVENT (III Points Saturday, Wynwood, Sat Oct 17)
   ├── DIRECT FROM EVENT        official inventory, sold by the venue
   │      ├── General Admission        $60
   │      └── VIP Table                $400
   └── FROM FANS                 marketplace, sold by other people
          ├── Buy Now                  $85
          └── Auction, ends in 4h      current bid $52
```

Rules that keep this honest:

- **One event page, always.** A user never has to know whether an event is "a Snatch It event" or
  "a resale event". The page adapts to whatever inventory exists.
- **Direct inventory sorts above marketplace inventory** when both exist and direct is not sold
  out. It is the cheaper, safer, first-party option, and burying it would be dishonest.
- **Provenance is stated on every purchasable row**, in words: `DIRECT FROM EVENT` or
  `FROM A FAN`. Never color alone, never implied by position.
- **A resale ticket is never presented as venue inventory.** No shared "from $X" price that blends
  the two. If the direct price is sold out and fans are asking more, the page says so plainly.
- **Sold out is not the end of the page.** When direct inventory is gone, the marketplace section
  becomes the primary call to action. This is the brand's own line: "SOLD OUT? THE NIGHT ISN'T."
- Events with no direct inventory look exactly like today's product, so nothing regresses for the
  existing marketplace business.

## 3. Proposed consumer structure

Five destinations. Each maps to a real recurring job, not to a feature.

| Tab | Job | Contents |
|---|---|---|
| **Home** | "What should I do?" | City-scoped feed of upcoming events. Editorial rails: tonight, this weekend, selling fast, newly announced. A compact "your next ticket" strip when the user holds one for the next 48 hours. An "your active bids" strip only when bids exist. |
| **Explore** | "Find a specific thing" | Search over events, venues and artists. Filters: date, neighborhood, price, kind of inventory. This is the currently hidden route, promoted and rebuilt. |
| **Tickets** | "Get me in" | Upcoming and past. Upcoming shows the credential. Offline-tolerant, because venue doors have bad signal. |
| **Sell** | "Move a ticket I can't use" | Create a listing, manage listings, see offers and bids received, and payouts. Everything about being on the supply side, in one place. |
| **Profile** | "Me" | Account, payment methods, notifications, settings, deletion state, support, saved events. |

**Why not four tabs.** Folding Sell into Profile would bury the behavior Snatch It was built on and
that its marketing still leads with. Folding Tickets into Profile repeats today's mistake.

**Where bids go.** Bids are purchase attempts in flight, not tickets and not listings. They appear
as a Home strip while active, and in full under Sell for offers received and under Profile activity
for offers made. They no longer own a tab, because most users on most days have none.

**Deep-link and notification targets** map cleanly: a ticket notice opens Tickets, an outbid notice
opens the auction, a direct on-sale notice opens the event page, an account or security notice
opens Profile. This matches the frozen notification target set, which already includes ticket,
event, order, listing, payout and account targets.

## 4. Primary journeys

**Buy direct.** Home or Explore, event card, event page, choose tier, quantity, checkout with the
hold countdown visible, pay, confirmation, ticket appears in Tickets. Target: five taps from home
to payment sheet.

**Buy from a fan.** Same path to the event page, then the marketplace section, then buy now or bid.
Identical checkout chrome, different provenance badge and a clear explanation of protection.

**Sell a ticket.** Sell tab, pick the event, set price or auction, publish. The event is chosen
from the event catalog rather than typed as free text, which is what makes resale inventory attach
to the right event page.

**Night of.** Tickets, upcoming ticket, credential. Must work with poor connectivity and be
reachable from the lock screen through a notification.

## 5. What this requires that does not exist

- An event page. There is no event route in the app today, only `listing/[id]`.
- Event-first discovery data. Home and Explore currently query listings.
- A tickets surface reading owned tickets. The database supports this now: `kernel` is exposed in
  production and owner-scoped ticket reads are permitted, so this is a client build, not a schema
  change.
- Tier selection and a direct checkout flow.
- Provenance components, per the design system.

## 6. Sequencing note

The event page is the hinge. It is the first screen that has to understand both inventory kinds,
and it is where the venue-native product becomes visible to a customer. It should be built first
and built once, with the marketplace path wired through it before direct inventory is switched on,
so that the risky new rail is not also the first user of a brand new screen.
