# Venue dashboard — owner-review PREVIEW

**This is a product preview over sample data.** It does not connect to Supabase, reads no
environment variables, performs no writes, and cannot be mistaken for live venue operations:
every page carries a striped "Preview data" strip that cannot be dismissed. Nothing in
production changed to produce it.

## Run it

```bash
cd venue && npm ci && npm run dev
```

Open <http://localhost:3300> — it redirects to the sample venue's events list:

`/o/smp_org_wynwood/v/smp_ven_room/events`

Two query parameters drive every page and are kept across links and forms:

| Param | Values | Effect |
|---|---|---|
| `role` | `venue_manager` (default) · `venue_finance` · `venue_box_office` · `venue_marketing` · `venue_promoter_manager` · `venue_scanner` · `org_owner` · `org_admin` · `org_finance` · `org_marketing` · `org_promoter_manager` · `org_member` · `fan` | Who is looking. Surfaces and columns follow spec §5/§5.1/§9.3; hiding only, never widening. |
| `state` | `live` (default) · `loading` · `empty` · `nodata` · `error` · `denied` | Forces the surface state. `nodata` = filtered to nothing, distinct from `empty` = nothing sold yet. |

Both are also switchable from the strip at the top of every page.

## Screens included

| Screen | Route | What to look at |
|---|---|---|
| Events list | `/events` | Status pills, next session, sold / capacity (counters for staff, availability for `org_member`), resale mode, inventory-warning chip, status/title filters, "No events yet" vs "No events match". |
| Event setup | `/events/smp_evt_sat_music` (live), `/events/smp_evt_reggaeton` (announced, blocked from on-sale), `/events/smp_evt_draft`, `/events/new` (3-step wizard) | Only the next forward status is offered; the missing requirement is named instead of a dead button; capacity per session; "Held back for the door: 40 of 520"; manifest consequence copy; honest-absence copy for tiers, tables, purchase limits, scheduling. |
| Inventory overview | `/events/smp_evt_sat_music/inventory` | Matrix at ≥1280px, one table per type at 1024–1279, status cards below; sold-out vs all-held kept distinct; low / door-untouched / holds-expiring warnings; capacity floor named; holds panel with Release (reversal) only. |
| Orders / attendees | `/events/smp_evt_sat_music/attendees` (+ `?view=purchasers`) | Holder-keyed roster (a six-ticket table order shows six people, one marked purchaser); column classes per role (finance: money, no check-in/email; marketing: contact, no money; scanner/box office: denied with the lookup alternative); export hidden below 1024px; purchaser view says "voided", never "refunded", for tickets. |
| Door status | `/events/smp_evt_sat_music/door` | Counter-first (291 / 411), five scan results, arrivals bar, devices with sync age and queue depth, PINs (no resend, never a hash), manifest + freeze-status card + episode history, manual single-record lookup with the wallet-staleness note, flag queue with Escalate only. Manifest control is read-only on a phone; never offered to a scanner. |

Suggested walk-through: events → Saturday Music Night → inventory → attendees (try
`role=venue_finance`, `role=venue_marketing`, `role=venue_scanner`) → door (try
`role=venue_scanner`, then `state=error`) → create event wizard (`role=org_member` shows the
denial). Resize to 375px for the mobile-critical surfaces (attendees, inventory, door).

## Sample-data source

`venue/src/fixtures/venue.ts` — invented names, ids prefixed `smp_`, clock frozen at
2026-09-12 22:30 Miami so "tonight", countdowns and staleness are stable. The only data the
app ever renders. `venue/src/lib/data.ts` maps each fixture read to the spec §20 read it
stands in for.

## Checks run

`cd venue && npm run typecheck && npm run lint && npm test && npm run build` — all green
(50 Vitest cases incl. SSR renders of every surface). CI job `venue` mirrors this.

## Backend capabilities still missing for live wiring

From the product spec's own read index (§20) and acceptance check (§20A), for these five
surfaces only:

| Need | Status in the specs |
|---|---|
| Every `catalog.*` / `venue.*` table these pages read | Specification-only; production runs the 27 `public.*` tables (spec §0.1). Migrations 076–092 first. |
| `venue.list_attendees(p_session_id, p_filters, p_cursor)` — holder-keyed, column-scoped, audited | Contracted (CRM §11.4); not implemented. |
| `venue.get_dashboard_summary` (one round trip for counters) | Still only an ask (Δ3). Preview computes from fixtures. |
| `venue.validate_ticket_online` + `venue.lookup_attendee` for the door lookup | Contracted; `reason` enum must gain `refund_hold` (§12.5 correction). |
| `venue.open_door_manifest` / `close_door_manifest` | Contracted (door §7.1/§7.2), role set per O-4. **Blast-radius dry-run read (Δ11) does not exist** — the preview says so on the confirm. |
| Live-device count read (Δ12) | Not named anywhere. |
| Capacity change on an existing batch (U-8), edit a draft event (U-9) | No RPC named; the preview offers no control. |
| Inventory low-threshold source (§22.8) | Unresolved; fixture-supplied per batch here. |
| `org_admin` on the refund/orders list (D-8) | Contested; the preview follows the spec and does not render orders for `org_admin`. |
| Role predicates (`kernel.has_venue_role` etc.) and the six-label enums | Role-model spec; not migrated. |

The preview's role switch is a **display projection** of the matrix. Real authority is
re-checked inside each RPC (spec §2.2); no UI decision here is a permission.

## Statement

No production data was read or written and no production setting changed to build or run this
preview. It has no Supabase client, no credentials and no environment.
