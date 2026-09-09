# Venue dashboard preview — design (2026-09-09)

**Status:** implemented on branch `venue/dashboard-preview` as `venue/`. Product preview only — not a deployment.

## Purpose

Give the owner a reviewable, clickable vertical slice of the Phase-2 venue dashboard
(`docs/architecture/PHASE_2_VENUE_DASHBOARD_PRODUCT_SPEC.md`) before any backend for it
exists. Production has no `catalog.*` / `venue.*` objects (spec §0.1), so the preview renders
sample fixtures only and performs no writes.

## Scope — the smallest complete slice

Five surfaces, one sample organization and venue, one fully populated live event:

| # | Surface | Spec | Route |
|---|---|---|---|
| 1 | Events list | §7.1 | `/o/{org}/v/{venue}/events` |
| 2 | Event setup (detail + 3-step create wizard) | §7.2–§7.9 | `…/events/{event}`, `…/events/new` |
| 3 | Inventory overview | §8 | `…/events/{event}/inventory` |
| 4 | Orders / attendees (holder view + purchaser view) | §9.1–§9.3, §13.1 | `…/events/{event}/attendees` |
| 5 | Door status | §12 | `…/events/{event}/door` |

Out of scope, on purpose: dashboard home, promoters, guest list/comps, refund initiation,
settlement/payouts, staff, settings, activity log, ticket-holder mix, CRM export jobs.

## Approaches considered

1. **Separate Next.js app `venue/` mirroring `admin/` tooling (chosen).** Same Next 16 /
   React 19 / Tailwind 4 / Vitest toolchain and brand tokens as the founder console, but a
   separate package, separate routes, separate CI job, no Supabase dependency at all. Keeps
   the venue product physically separate from both the consumer app (`web/`) and the founder
   console (`admin/`), as the brief requires.
2. Route group inside `admin/`. Rejected: mixes venue and platform planes the spec keeps apart
   (§3.1, §4.4 rule 6) and would inherit the founder auth/MFA proxy.
3. Static HTML mockups. Rejected: cannot show state matrices, role scoping or responsive rules
   faithfully, and would not be reusable when wiring begins.

## Architecture

- **Pages** (`src/app/o/[org]/v/[venue]/…`) are thin server components: parse `?role=` and
  `?state=`, fail closed on any org/venue id other than the sample (spec §4.4 rule 5), read
  fixtures through `lib/data.ts`, and pick one of loading / denied / error / surface.
- **`lib/data.ts`** is the only data access layer. Every function is annotated with the spec
  §20 read it stands in for (`T catalog.event`, `R venue.list_attendees`, …). Swapping it for
  RPC calls later is a substitution, not a redesign. `?state=error` throws a
  `PreviewReadError` naming that read, so error cards carry the server's reason (§19.7).
- **`lib/roles.ts`** projects the §5 / §5.1 / §9.3 / §12.4 matrix rows this slice needs into
  show-or-hide predicates. It only ever hides; it never widens a grant. Column classes
  (IDENT · OPS · CONTACT · MONEY) are held per role; a denied class is absent, not null.
- **Presentational components** take plain props and are rendered with
  `react-dom/server` in tests, so the spec's copy and state rules are asserted verbatim.
- **Actions** are GET forms carrying `did=<named RPC>`; the page re-renders with a
  "Preview only — would call X, nothing saved" banner. No control exists for a write the spec
  lists as unbacked (§20A.3): capacity change, draft edit, guest-list writes, blast-radius
  dry-run.
- **Responsive rules** follow §3.2/§3.3: xl persistent nav, lg icon nav, md/sm top drawer;
  attendees and inventory become card lists below md; door is counter-first single column
  with the manifest control read-only at sm; export hidden below lg; every money/capacity
  control hidden below lg with the "Open on a larger screen to edit" banner.
- **Preview indicator**: a sticky striped strip on every page with the role/state switchers.

## Data flow

fixtures (`src/fixtures/venue.ts`, frozen clock `PREVIEW_NOW`) → `lib/data.ts` (state gate)
→ page → component. No network, no environment variables, no storage.

## Error handling / states

Every surface renders loading (skeleton), empty (surface-specific copy), no-match (distinct
from empty), error (named read + retry), unauthorized (standard denial, alternative named
for door/box office), partial ("—" with a reason). Driven by `?state=` and by the role.

## Testing

Vitest: capacity math and warning rules, forward-only lifecycle and publish blockers, door
reject vocabulary and freeze semantics, role projections, preview context parsing, and SSR
smoke renders of each surface per role and state asserting the spec's copy.
CI: `venue` job (typecheck · lint · tests · build), not a required check, same posture as
`admin`.

## What is still missing for live wiring

See `docs/venue-dashboard/PREVIEW.md` §"Backend capabilities still missing".
