# Venue and organizer information architecture V2

**Status:** proposal, pending owner approval. Nothing here is built. No venue surface exists in the
product today.

This structure is derived from two things only: the roles that actually exist in the deployed
schema, and the operations that actually exist as callable verbs. It is not copied from another
platform's dashboard.

---

## 1. The role model this must serve

Venue roles (migration 080). These six are canonical and closed:

| Role | What it is for |
|---|---|
| `venue_manager` | Runs the venue. Broadest operational authority. |
| `venue_finance` | Money: settlements, payouts, refund approvals. |
| `venue_box_office` | Day to day selling, orders, comps, guest list. |
| `venue_marketing` | Event presentation, listings, promotion. |
| `venue_promoter_manager` | Promoter program, codes, attribution. |
| `venue_scanner` | Door only. Scans tickets. Nothing else. |

Organization roles sit above venues: `org_owner`, `org_admin`, `org_finance`, `org_marketing`,
`org_promoter_manager`, `org_member`. An organization can own several venues, so the product has
two levels and the navigation must express that without making a single-venue operator feel like
they are managing an enterprise.

There is no `venue_door` and no `venue_promoter`. If either name appears in a design, it is wrong.

## 2. Where this lives: web, not mobile

**The venue dashboard is a web product.** Venue staff build events at a desk, on a keyboard, with a
spreadsheet open. Event setup involves long text, pricing tables, capacity numbers and image
uploads. That is a desktop job, and `web/` already exists with the brand-correct token system.

**One exception: the door.** `venue_scanner` is a phone job, standing at an entrance, often with
bad signal. Scanning belongs in a mobile surface and should be a separate, stripped-down mode, not
a tab inside the consumer app. That rail is dark and out of scope for the first train.

## 3. Proposed structure

Two levels. An operator with one venue never sees the organization level; they land directly in
their venue.

```
ORGANIZATION (only when more than one venue, or for org-level roles)
  Overview · Venues · Team · Billing and payouts · Settings

VENUE
  Overview
  Events
    └── EVENT
          Details · Tickets and pricing · Inventory · Orders · Attendees · Promotion
  Orders
  Attendees
  Settlements
  Team
  Settings
```

### Destinations, and what each is for

| Destination | Job | Backed by | Visible to |
|---|---|---|---|
| **Overview** | "How is tonight looking?" Sold today, upcoming events, what needs attention. | Reads over orders and inventory | All venue roles except scanner |
| **Events** | The list. Create, edit, publish, cancel. | `catalog.create_event`, `update_event_session`, `publish_event` | manager, marketing, box_office (read) |
| **Event: Details** | Title, session times, doors, venue, artwork. | `catalog.update_event_session` | manager, marketing |
| **Event: Tickets and pricing** | Define tiers, set prices, visibility. | `venue.create_ticket_type`, `set_ticket_type_price` | manager, box_office |
| **Event: Inventory** | Capacity, releases, presales, holds. | `venue.create_inventory_batch`, `set_batch_capacity` | manager, box_office |
| **Event: Orders** | Orders for this event, refund requests. | `venue."order"` reads | manager, box_office, finance |
| **Event: Attendees** | Who is coming, check-in state. | order and ticket reads, gated by the privacy rules | manager, box_office |
| **Event: Promotion** | Promoter codes and attribution. Dark today. | migration 090 verbs | promoter_manager, manager |
| **Orders** (venue level) | Across events. Search, refund, resend. | order reads | manager, box_office, finance |
| **Attendees** (venue level) | Audience across events. Export. Parked behind the CRM gate. | 087 export verbs, currently fail-closed | manager, marketing (consent-gated) |
| **Settlements** | What the venue is owed and paid. Dark today. | 087 settlement tables | finance, org_finance, manager (read) |
| **Team** | Grant and revoke staff roles. | `venue.grant_staff_role`, `revoke_staff_role` | manager, org_owner, org_admin |
| **Settings** | Venue profile, address, neighborhood, payout destination. | `catalog.create_venue` fields, Connect onboarding | manager, finance |

### Navigation shape

Left sidebar for venue destinations, because there are more than five and they are visited
non-linearly. Event-scoped work is a second level inside an event, with tabs across the top, so a
user editing an event never loses their place. Square edges, red hairline dividers, Oswald section
heads. No cards with shadows, no rounded panels, no dashboard chrome.

## 4. What each role sees on landing

- `venue_scanner` never sees this product at all. They get the door app.
- `venue_box_office` lands on today's orders and door list, not on analytics.
- `venue_finance` lands on settlements and payouts.
- `venue_marketing` lands on the event list with presentation state.
- `venue_manager` and `org_owner` land on Overview.

A role that cannot act on a destination does not see the destination. Hiding is not the security
boundary, the database is, but showing a person a page they cannot use is a defect.

## 5. The event creation flow

This is the highest-value screen in the venue product and the one that decides whether venues
adopt Snatch It. It should be a short, forgiving, resumable sequence, not a wizard with ten steps.

1. **Event basics.** Title, date and time, doors. Creates the event and its first session.
2. **Artwork.** Upload once, and the system derives every placement from it. The media system
   document specifies how, and this is where the current product fails hardest.
3. **Tickets.** Add tiers with name and price. Most venues have one to three.
4. **Inventory.** Capacity per tier. Optional presale window.
5. **Review and publish.** Draft until explicitly published. Publishing is a deliberate act with a
   confirmation, because it exposes the event publicly.

Everything after step 1 must be editable later. An event should be saveable as a draft at any
point, because a venue rarely has all the details in one sitting.

## 6. What does not exist yet

Every screen above. There is no venue surface in the product today. What does exist is the entire
database layer behind it: roles, predicates, events, sessions, ticket types, inventory batches,
holds, orders and checkout are all deployed and callable. The venue product is a client build on
top of a finished spine, plus the two missing payment edge artifacts.

## 7. Deliberately excluded from the first train

Settlements, payouts, promoter tools, CRM export, analytics dashboards and door scanning are all
either dark rails or parked behind owner decisions. Showing a venue an empty Settlements page is
worse than not showing it, so those destinations stay hidden until their rails are activated. The
first train is: create an event, sell tickets for it, see the orders.
