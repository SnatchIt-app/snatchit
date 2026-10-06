# Venue dashboard — demonstration preview

A working venue dashboard you can click through, running entirely on **invented sample
data**. It is for showing people what operating a venue on Snatch It looks like. It is not
connected to Snatch It's database, it holds no credentials, and nothing in it can sell,
refund, pay out, transfer or scan a real ticket.

Every page carries a striped amber strip that cannot be dismissed:

> ◆ Demo — sample data · Invented venue and events. Nothing here sells, refunds, pays out or
> scans a real ticket.

Any button that would change something answers: **"Nothing was saved. This is the demo: no
ticket moved, no money moved, nobody was emailed."**

## Deployment

| | |
|---|---|
| Vercel project | `snatchit-venue-demo` (separate project; `snatchit-web` and `snatchit-admin` untouched) |
| Project root | `venue/` |
| Branch | `venue/demo-integration` |
| Data source | `NEXT_PUBLIC_VENUE_DATA_SOURCE=fixtures`, set explicitly on every environment |
| Supabase variables | **none set** — the project has no `NEXT_PUBLIC_SUPABASE_URL` and no key of any kind |
| URL and deployed commit | recorded in `DEPLOYMENT.md` beside this file |

The build carries a self-only Content-Security-Policy with no `connect-src` entry for
Supabase or Stripe, and `X-Robots-Tag: noindex, nofollow`. There is no Supabase client in the
package in fixtures mode, so there is no credential for one to use.

## Walkthrough — the five minutes to show someone

1. **Open the URL.** You land on **Tonight**, not a table. The top section is *What needs
   you*, worst first: a scanner that stopped syncing, flagged scans nobody has reviewed,
   holds about to expire. Each one says what it is, **what happens if it is ignored**, and
   has exactly one button to the screen where you fix it. Underneath, *N other checks are
   clear* — so an empty list means the dashboard looked, not that nothing ran.
2. **Read the door numbers.** *Happening tonight* shows **291 people inside**, **120 still to
   arrive**, **1 of 3 scanners online** — each with the sentence that defines it. No number
   on this product appears without its definition.
3. **Follow a signal.** Click *Open the door screen*. Counter first, then the five scan
   results, the arrivals bar, each device with how long ago it synced and how many scans are
   queued on it, the door PINs, and the manifest with its freeze status and history.
4. **Open inventory.** `Events → Saturday Music Night → Inventory`. Sold / held / remaining
   per release, sold-out kept distinct from all-held, the capacity floor named, and a holds
   panel where the only action is *Release* — a reversal, never a deletion.
5. **Look at the guest list.** `Attendees`. It is keyed by the **person holding the ticket**,
   not the buyer: a six-ticket table booking shows six people with one marked as purchaser.
6. **Change who is looking.** Open *Demo controls* in the strip and set **Viewing as →
   Venue finance**. The guest list keeps the money columns and loses contact details and
   check-in, and says so: *"Your role sees money and counts, never contact detail or
   check-in."* Try **Venue scanner**: the whole list closes, and the page explains that door
   roles check one ticket at a time and links you to the single-ticket lookup instead.
7. **Hit a wall on purpose.** Set *Viewing as → Organization member* and open *Create event*.
   The denial names the screen, says your role doesn't include it, says who can grant it, and
   gives you a link to somewhere you can go.
8. **Force a bad day.** *Demo controls → Screen state*: `loading`, `empty`, `no matches`,
   `error`, `denied`. `no matches` is deliberately different from `empty` — filtering to
   nothing says *"No events match these filters. Your 6 events are still here."*, never "you
   have no events" beside a button that would create a duplicate.
9. **Create an event.** `Events → Create event` walks three steps. Only the next legal status
   is ever offered; when an event can't go on sale the dashboard names the missing
   requirement instead of showing a dead button.

Everything in that walk is linkable: the role and screen state stay in the URL, so you can
send someone a link that opens in the persona you want them to see.

## What is functional, simulated, or waiting on the backend

**Functional** — real logic, real computation, over sample rows:

| | |
|---|---|
| Permissions | 13 principals; every surface and column class is decided by the role matrix. Hiding only — it never widens anything. |
| The Tonight signals | Computed from the sample reads: scanner sync age, unreviewed flags, holds expiring within the hour, sold-out and low releases, untouched door stock, events blocked from on sale, drafts. Severity-ordered. |
| Inventory arithmetic | Sold / held / remaining, capacity floor, availability, door hold-back, low-stock and expiry warnings. |
| Door logic | Manifest open/closed/closed-after-open, freeze time with its backstop, device sync age and staleness, the six refusal reasons. |
| Screen states | Loading, empty, filtered-to-nothing, error, permission-denied — all reachable and all distinct. |
| Navigation and filters | Status and title filters, role/state persistence across every link and form. |
| Accessibility | Measured, not asserted — see below. |

**Simulated** — looks like the real thing, changes nothing:

| | |
|---|---|
| Every write | Publish, go on sale, release a hold, escalate a flag, open or close the manifest, create an event. Each posts back and renders "Nothing was saved", naming the backend call it stands in for. |
| Sales, refunds, payouts, transfers | No money exists in this demo. Figures shown are fixture values. |
| Scanning | No scanner connects to it. The counters and devices are sample rows with a clock frozen at 2026-09-12 22:30 Miami, so "19 minutes ago" stays 19 minutes ago. |
| Sign-in | Fixtures mode has no accounts. The role switch is a display projection, never an authorization. |
| Exports | The button is present and scoped per role; it produces nothing. |

**Still needs backend integration** before a real venue could use this:

| Need | State today |
|---|---|
| `venue_api` read views (migration `20260910120000`) | Written, pgTAP 47/47 locally, **applied nowhere**. Owner-gated. |
| `venue.list_attendees` — holder-keyed, column-scoped, audited | Contracted (CRM §11.4), not implemented. |
| `venue.get_dashboard_summary` — counters in one round trip | Still an ask (Δ3). The demo computes from fixtures. |
| A signals read for the Tonight page | **Does not exist in any spec.** The page is fixtures-only and says "not wired" in database mode rather than mixing sample numbers with real ones. This is the main new backend dependency this demo creates. |
| `venue.validate_ticket_online` + `venue.lookup_attendee` | Contracted; the `reason` enum needs `refund_hold` (§12.5). |
| `venue.open_door_manifest` / `close_door_manifest` | Contracted. The blast-radius dry-run read (Δ11) does not exist; the confirm screen says so. |
| Live device count (Δ12) | Not named anywhere. |
| Capacity change on an existing batch (U-8), edit a draft (U-9) | No RPC named; the demo offers no control. |
| Inventory low-threshold source (§22.8) | Unresolved; fixture-supplied per batch here. |
| Staff invites and role management | Migration 138 written and unapplied; no UI on any branch. |
| Payouts, settlement, disputes, audit history | No venue surface exists. Out of slice 1. |
| Role predicates and the six-label enums | Specified, not migrated. |

## Usability work in this demo

Against `DASHBOARD_USABILITY_AUDIT_D_20260917.md`, venue items only:

| Audit item | Done |
|---|---|
| **X0** type scale | Every size in `rem` from four named tokens; no px font-size left in the package. Grids collapse on text size, not viewport width. |
| **X2** empty vs filtered-to-nothing | Branches ordered by cause; the filtered message keeps the count and offers *Clear filters*, never *Create event*. |
| **W1** "what needs me now?" | New **Tonight** overview as the landing page. |
| **W2** denial | One component: screen, reason, who can grant it, a route out. All 10 call sites. |
| **P3** raw table names as headings | Gone from every visible heading; the read name moved to `data-read` and the heading tooltip. |
| **P4** error copy | Leads with what you lost and what to do; the read name is support detail. |
| **P5** one header over two measures | Header follows the measure: *Sold of capacity* or *Still available*. |
| **P10** all-caps | Removed — converges venue with the console's owner-approved direction. |
| **P11** two sticky bars on a phone | One. Sticky chrome 90px, was 223px of an 812px viewport. |

**Measured in a browser, 375×812 and 1024×900, at 1×, 1.5× and 2× text**, over all seven
routes:

| Check | Result |
|---|---|
| Text elements that fail to grow | **0 of 235** on the door page (audit measured 78 of 212) |
| Horizontal overflow | **0 px** on every route, both widths, all three text scales |
| Controls under 24×24 (excluding inline links in prose) | **0** |
| Overflow probe positive control | 2625 px at 375, 1976 px at 1024 — the probe detects overflow when it exists, and returns to 0 |

Not claimed: this is not a full WCAG conformance review. Contrast was not re-measured in this
pass — the Light theme's own token-contrast test still covers it. No native or device
evidence; this is a web app.

## Sample data

`venue/src/fixtures/venue.ts`. Invented names, every id prefixed `smp_`, clock frozen at
2026-09-12 22:30 Miami. `venue/src/lib/data.ts` maps each fixture read to the real read it
stands in for. It is the only data the app can reach in this mode.

## Running it locally

```bash
cd venue && npm ci && echo "NEXT_PUBLIC_VENUE_DATA_SOURCE=fixtures" > .env.local && npm run dev
```

http://localhost:3300 — redirects to the sample venue's Tonight page.
