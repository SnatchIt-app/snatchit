# Venue dashboard demo — remaining work

Written 2026-10-06 against `venue/demo-integration`. **Reuse before building** is the rule
below: every item names the existing implementation it should start from, and nothing here
proposes a new product surface except where it says so explicitly.

## 1. Usability issues still in this demo

Ordered by how likely they are to confuse someone during a pitch.

| # | Issue | Reuse |
|---|---|---|
| U1 | A **completed** event still offers *Open the door manifest* and a confirm that talks about freezing transfers, for a night that already happened. Nothing in the role model is wrong; the control just isn't gated on the session being over. | `lib/door.ts` `manifestState()` already distinguishes `closed_after_open`; the session carries `status`. Gate the control on it in `DoorStatus.tsx` — no new logic needed. |
| U2 | Several screens promise *"this is recorded in your venue's activity"* and there is nowhere to read it. Truthful but it invites a question with no answer. | `lib/data.ts` already has `recentActivity()` reading `F.ACTIVITY`, unused by any surface. A read-only activity panel is a render, not a feature. |
| U3 | The **Tonight** page shows up to eight signals at once, which is honest but dense; the third sold-out release adds little. | `lib/signals.ts` already groups by severity. Collapse same-kind signals past the first into "and 2 more releases" using the existing `clear`-check disclosure pattern in `Tonight.tsx`. |
| U4 | **Event setup** is one long column of six panels on a phone; a manager hunting for status scrolls past it. | The panels are already independent; the ordering is in `EventSetup.tsx`. No new component. |
| U5 | The sample venue has **one organisation and one venue**, so the org/venue switchers in the top bar are inert dropdowns with a single option. In a pitch they read as broken. | `Shell.tsx` `FixtureSwitchers` — either render them as plain text when there is one option, or add a second sample venue to `fixtures/venue.ts`. |
| U6 | `?state=no matches` does nothing on inventory, door and the wizard, because those surfaces have no filter. The control implies it will. | `lib/preview.ts` owns `PREVIEW_STATES`; the honest fix is to offer only the states a surface supports. |
| U7 | Contrast was **not re-measured** after dropping all-caps and changing colour-free copy. Not known to be broken — the Light theme's `theme-contrast.test.ts` still passes — but it is an unmeasured claim. | `tests/theme-contrast.test.ts` plus the console's `scripts/ui-audit/audit.mjs`, which already measures contrast and could be pointed at `venue/`. |

## 2. Backend work needed before a real venue could use this

Nothing here is startable without owner authorisation, and none of it is in scope for this
demo. Listed so the dependency is visible rather than discovered later.

| # | Need | State today |
|---|---|---|
| B1 | `venue_api` read views — the whole read side | Migration `20260910120000` written, pgTAP 47/47 locally, **applied nowhere**. The app's database mode is already wired to it (`lib/db/adapters.ts`), so this is an apply, not a build. |
| B2 | A **signals read** behind the Tonight page | **Does not exist in any spec.** This is the one new dependency the demo creates. `lib/signals.ts` is the executable specification for it — the shape it needs is already written down and tested. |
| B3 | `venue.list_attendees` — holder-keyed, column-scoped, audited | Contracted (CRM §11.4), not implemented. `lib/roles.ts` `rosterClasses()` is the column policy it has to enforce server-side. |
| B4 | `venue.get_dashboard_summary` — counters in one round trip | An ask (Δ3). `lib/inventory.ts` `sessionTotals()`/`doorHoldback()` define the arithmetic. |
| B5 | `venue.validate_ticket_online` + `venue.lookup_attendee` | Contracted; the `reason` enum must gain `refund_hold` (§12.5). The six-reason copy is already frozen in `lib/door.ts` `REJECT_COPY`/`REJECT_TITLE`. |
| B6 | `venue.open_door_manifest` / `close_door_manifest`, **plus** the dry-run read (Δ11) | Contracted; the dry-run read is not. Until it exists, the demo withholds the cancel control and warns on the manifest confirm — that behaviour should survive into production. |
| B7 | Capacity change on a live release (U-8), edit a draft (U-9) | No RPC named. The demo offers no control and explains why. |
| B8 | Live device count (Δ12), inventory low-threshold source (§22.8) | Not named / unresolved. Both are fixture-supplied here. |
| B9 | Staff invites and role management | Migration **138 written and unapplied**; no UI on any branch. |
| B10 | Settlement, payouts, refunds, disputes | No venue surface, and money changes are owner-gated by the constitution. The **admin console** already implements the outcome-honesty pattern money needs (`admin/src/components/ui/ConfirmForm.tsx`) — reuse it rather than inventing one. |
| B11 | Readable activity / audit history | `ops.*` audit reads exist for the console; the venue plane has no equivalent read. |

## 3. Optional later improvements

Worth doing, nothing depends on them.

| # | Improvement | Reuse |
|---|---|---|
| O1 | Make the demo **self-explaining** — a one-screen "what you're looking at" card on first visit, dismissible, derived not stored | The audit's §7 onboarding proposal and prototype `docs/venue-dashboard/prototypes/p1-venue-tonight.html` already contain a derived first-run checklist. |
| O2 | A second sample venue and a second organisation, so the switchers and the cross-venue permission boundary are demonstrable | `fixtures/venue.ts`; the acceptance kit's rehearsal fixtures (`venue/scripts/rehearsal-fixtures.sql`) already model org A / org B. |
| O3 | Point the console's CDP **UI audit** at `venue/` so contrast, landmarks and small targets are measured by CI rather than by hand | `admin/scripts/ui-audit/audit.mjs` exists and already measures all three. This closes U7 permanently. |
| O4 | A shareable demo mode — a public, protection-free deployment with its own URL, separate from the protected one | Vercel project settings only. **Owner decision**, set out in `DEPLOYMENT.md`. |
| O5 | Git-connect the Vercel project so pushing the branch redeploys | Blocked today: the API token in-session cannot create or connect a project under the team scope. Dashboard action. |
| O6 | Metric definitions as a shared vocabulary between venue and console | `admin/docs/ANALYTICS_DATA_CONTRACT.md` is the existing definitions document; the venue figures should be added there rather than defined twice. |

## Not recommended

- **Don't** build a venue payouts screen before B10's money reads are owner-approved and the
  console's confirm pattern is reused. A payout screen over fixtures would be the one thing in
  this demo that could mislead someone about money.
- **Don't** connect database mode to the sandbox to make the demo "more real". It would trade
  a demo that cannot lie for one that can be half-wired, and the preview's whole value is that
  the labelling is unconditionally true.
