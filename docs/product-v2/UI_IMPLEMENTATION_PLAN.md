# UI implementation plan

**Status:** proposal, pending owner approval. No UI work has been started.

This plan sequences the V2 redesign against the venue-native backend work. The ordering is derived
from three constraints, not from a preferred aesthetic:

1. **The foundation must land before any screen.** Migrating a screen to a token system that does
   not exist yet means doing it twice.
2. **The event page is the hinge.** It is the first screen that must understand both direct and
   marketplace inventory, and it is where venue-native ticketing becomes visible to a customer.
3. **Do not rebuild working marketplace screens first.** They are unattractive, not broken. The
   business runs on them today.

---

## Tier 0 — Foundation (blocks everything)

Nothing user-visible ships in this tier, and everything after it depends on it.

| Work | Why it is first |
|---|---|
| Invert the token package | `packages/design-tokens` currently generates from the non-brand mobile theme, so the wrong palette is upstream of the right one. Until this flips, every migrated screen inherits the fork. |
| Load Oswald and Inter in mobile | `expo-font` is installed and never called. The brand's entire typographic identity is missing from the product. |
| Build the UI primitives | Button, Input, Chip, Badge, Sheet, Skeleton, EmptyState, StickyBar. |
| Build `EventImage` | One component, ten slot configurations, with focal point, fit mode, scrim, skeleton, fallback and recycling key. |
| Turn on image transformations and fix cache headers | No migration required. Immediate bandwidth and quality win across every existing screen. |
| Add the style lint guard | Fails the build on a raw hex or a non-zero radius outside token files, so the system cannot fork again. |

**Exit criterion:** a single screen can be built entirely from tokens and primitives, with no local
styles.

## Tier 1 — The purchase journey

The critical path. This is what a customer touches and what venue-native ticketing needs.

| Order | Screen | Depends on |
|---|---|---|
| 1 | **Event page** | Tier 0. Built with the marketplace path wired first, so the new screen is proven before the new rail uses it. |
| 2 | Home feed, event-first | Event page, `EventImage` |
| 3 | Explore and search | Home |
| 4 | **Tickets** | Tier 0. Reads owned tickets. No schema change needed; the database already permits owner-scoped reads and `kernel` is exposed. |
| 5 | Tier selection and hold countdown | Event page, and the two unseeded inventory config rows |
| 6 | Primary checkout | Tier selection, the `primary-checkout` edge function, the payments shape migration |
| 7 | Marketplace checkout refresh | Shares the checkout chrome from 6 |
| 8 | Purchase confirmation | 6 and 7 |

**Note on ordering 4 before 6.** Tickets can be built and shipped before any payment work, because
tickets issued by any path land in the same place. It is the cheapest way to make the app feel like
a ticketing product rather than a resale board.

## Tier 2 — Venue product, web

Begins in parallel with Tier 1 once Tier 0 lands, because it is a different codebase and a different
audience.

| Order | Screen |
|---|---|
| 1 | Venue shell, navigation, role-gated routing |
| 2 | Event list and event creation |
| 3 | Event editor: details, artwork with focal-point picker, tickets and pricing |
| 4 | Inventory: capacity and releases |
| 5 | Orders |
| 6 | Team management |
| 7 | Venue settings |

Deferred until their rails are activated: attendees, settlements, promoter tools, analytics, door
scanning. An empty Settlements page is worse than no Settlements page.

## Tier 3 — Marketplace refresh

Only after Tier 1 is on the new system.

Bid entry with free-text amounts, the bids surface moved out of the tab bar, the listing creation
rebuild with event selection from the catalog, transfer send and receive, my listings.

The listing creation rebuild carries hidden strategic weight: making sellers pick a real event from
the catalog, rather than typing venue text, is what attaches resale inventory to the correct event
page. Without it the unified event model has holes.

## Tier 4 — Supporting

Profile split, settings token migration, notification preferences, empty and error state polish,
public seller profile.

---

## What gates what

| UI work | Backend gate |
|---|---|
| Event page showing direct inventory | `venue` and `catalog` exposed through PostgREST |
| Tier availability | Two inventory config rows that do not exist and cannot be created without a migration |
| Primary checkout | `primary-checkout` edge function; the `public.payments` native shape migration |
| Ticket appears after purchase | The webhook native branch; a provisionable signing key |
| Venue event artwork | The event media schema and bucket, which do not exist |
| Native events visible in discovery | The discovery projection's native arm, which hard-codes a null cover |

Every one of these is tracked with evidence in `PHASE2_PRIMARY_ACTIVATION_GAP_MATRIX.md`.

## Risk notes

- **Do not build Tier 1 screens against the old design system.** That is the explicit instruction
  and it is also correct: six of the eight Tier 1 screens are new or rebuilt, so there is nothing to
  preserve.
- **The event page will be built twice if the media system is not settled first.** Its entire layout
  depends on the frame ratio and the fit-mode decision.
- **Tier 2 can stall on owner decisions** (attendee privacy, settlement activation). Scope it to
  create, sell, and see orders, and let the rest wait.
