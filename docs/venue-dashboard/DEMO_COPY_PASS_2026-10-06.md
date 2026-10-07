# Venue demo — plain-language and dead-end pass (2026-10-06)

Scope: copy and navigation only, inside the existing screens. No new features, no redesign,
no backend work. The persistent sample-data strip and the "nothing was saved" feedback are
unchanged except to be stated more plainly.

**This is not yet on the live preview.** The live preview remains
`512e01e3a4f2eebdb8446c2f0c6e278fa8304e06`. This pass is offered for approval before another
deployment.

## What was wrong

The earlier §P3 fix moved backend identifiers out of panel *eyebrows*. It did not touch body
copy, so a first-time reader still met these on screen:

- `Add session → catalog.create_event_session`
- `Change → catalog.set_resale_policy (creates a new version, never an edit)`
- `Preview: would call catalog.set_event_status; nothing is saved here.` (and the same for
  `catalog.create_event`, `venue.close_door_manifest`, `venue.open_door_manifest`,
  `venue.release_inventory_hold`)
- `Not offered in this preview: no capacity-change RPC is contracted (spec §20A.3 U-8).
  Creating a release is (venue.create_inventory_batch).`
- `Blast-radius counts … no dry-run read is contracted (spec Δ11).`
- Panel headings in internal language: **"What MVP has, said plainly"**, **"Per event ·
  versioned"**, **"Guarded"**, **"Advance status"**, **"Danger zone"**, **"Escalate, never
  resolve"**, **"One row per release and condition"**
- Two measures under one slash header: **"Sold / capacity"**, **"Admitted / issued"**,
  **"Sold / remaining"**
- **"Gross $12,900.00 — … What you'll be paid is in Settlement."** pointing at a screen that
  does not exist
- Non-descriptive link text: **"this view"**
- Raw enum names as the door's refusal reference: `version_stale`, `voided`, `listed_locked`…
- **"Export · money list"**

Two real defects, not just wording:

1. **A dead end.** The create-event wizard had no visible way out — no cancel, no back. The
   only route was the nav, which is a drawer on a phone.
2. **A contradiction.** The completed sample event shows **231 sold**, and its attendee list
   said **"No tickets sold for this session yet."** The demo invents ticket holders for one
   night only; the page reported that absence as a fact about the event. That is precisely the
   class of thing this demo must not do.

## What changed

| Area | Change |
|---|---|
| Audited-action note | *"In the real dashboard this is recorded in your venue's activity, with your name on it. **In this demo nothing is saved.**"* The backend call moves to the element's `title`. |
| Event setup | Plain headings; *Ticket sales* replaces *Gross* and says the payout screen **is not built yet**; the cancel panel explains in plain words what it would show you and why it is withheld. |
| Inventory | *Needs attention*; *Changing capacity · Checked before it is allowed*; *Sold, then remaining*; the capacity-change note explains the gap without naming an RPC; the read-only link is described. |
| Door | *Admitted, of tickets issued*; *Flagged at the door · You pass these on; you don't decide them*; the manifest warning says you cannot see the count before confirming because the read does not exist yet; the six refusals get plain titles with the reason code in `title`. |
| Attendees | *Download the list your role can see* / *Download the contact list*. |
| Wizard | **Cancel and go back to events** on every step, plus a line saying it ends as a draft that is not public. |
| Attendees, no sample roster | A distinct, truthful state: *"The sample data doesn't include a guest list for this night… It is not telling you that nobody bought."* |

## Verification at the proposed commit

- `typecheck` clean, `lint` clean, **vitest 121/121** (110 before + 11 new).
- `next build` green.
- **New regression guard**: every surface is rendered and its *visible* text — with
  `title=` and `data-read=` stripped — is scanned for `catalog.|venue.|kernel.|ops.|public.`
  identifiers. It carries a positive control in the same test: the guard is fed an identifier
  and must find it, and fed one inside a `title` attribute and must not. **The guard caught
  one I had missed** (`venue.create_inventory_batch` on inventory), which is why it exists.
- A second guard asserts no surface promises a record without the "in this demo nothing is
  saved" caveat; a third asserts the wizard's way out on all three steps; a fourth asserts the
  guest-list states discriminate — a session with no sample roster says so, and a session that
  genuinely sold nothing still says *that*.
- One pre-existing assertion was **repaired, not deleted**: a test asserted the *absence* of
  "Inventory warnings" for a scanner. Renaming that panel made the assertion unfalsifiable —
  it would pass whatever the component did. It now asserts the manager sees the panel and the
  scanner does not, in the same test.
- Re-measured in a browser at 375×812, all seven routes, at 1×/1.5×/2× text: **0 px
  horizontal overflow, 0 controls under 24×24**, positive control 2625 px. The longer copy did
  not reintroduce the overflow fixed in the previous pass.
- Walked all ten routes and confirmed: **0 backend identifiers in visible text**, none of the
  jargon strings above, and the **"Demo — sample data" strip present on every page**.
