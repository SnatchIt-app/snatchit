# Venue dashboard demo — walkthrough and pitch

Verified against the live preview's deployed commit `512e01e3a4f2eebdb8446c2f0c6e278fa8304e06`
by rendering every route below. The copy fixes described in
`DEMO_COPY_PASS_2026-10-06.md` are **not** on that commit yet — see that file for the
proposed commit.

Base URL: **https://snatchit-venue-demo.vercel.app** (sign in to Vercel as the account owner;
see `DEPLOYMENT.md`). Every link below is a working path on the live preview.

---

## 1. The 60-second pitch

> **Who it's for.** The person who runs a music venue — and the staff on the door with them.
>
> **The problem.** A venue sells tickets through someone else's box office, then spends the
> night half-blind. The promoter has a spreadsheet, the door has a clipboard or a borrowed
> scanner, and nobody can answer the questions that actually matter at 9pm on a show night:
> is anything about to sell out, has a scanner dropped off the network, how many people are
> actually inside, who is standing outside with a ticket we just refused. The answers exist
> in four places and arrive the next morning.
>
> **What Snatch It does about it.** One screen that opens on what needs you — ordered by how
> bad it is, each item saying what happens if you ignore it, each with one button to the place
> you fix it. Underneath, the night itself: people inside, still to arrive, scanners online.
> Tickets stay in the fan's app rather than a PDF, so a venue can see who is actually holding
> each one, let people pass tickets on under rules the venue sets, and stop all of that the
> moment doors open.
>
> **Why a venue would switch.** Not better reporting — fewer unpleasant surprises. The
> dashboard is built to never report success it hasn't been told about, and to name the
> consequence before you do something you can't undo.

**What the live demo actually demonstrates:** the screens, the role model, and the judgement —
what gets surfaced, in what order, in what words. All of it runs on invented data.

**What is the intended product, not the demo:** selling tickets, taking money, paying venues
out, refunds, and real scanning at a real door. None of that is connected to anything in this
preview. The demo contains no payment integration, no scanner, and no database — it cannot
transact, and a button that looks like it would says so when you press it.

**One sentence not to say in a pitch:** that it is processing sales or admitting people today.
It is not. It shows what that would look like.

---

## 2. Click-by-click tour

Four audiences, in the order a venue meets them.

### A. The venue manager arriving mid-shift — "what needs me?"

1. **[Tonight](https://snatchit-venue-demo.vercel.app/o/smp_org_wynwood/v/smp_ven_room)**
   — the landing page. Top section, worst first:
   - *Needs you now*: two scanners out of sync (longest 19 minutes), one flagged scan nobody
     has reviewed, holds on General admission expiring within the hour.
   - *Before doors*: Early bird sold out, General admission down to 12, Reggaeton Sundays
     can't go on sale yet (and why).
   - *Worth knowing*: door stock untouched, one event still a draft.

   Each card says what happens if it's ignored. The scanner one, for instance: *"It still
   admits people from the list it already has, but tickets sold or refunded since then are not
   on that list. Anyone holding one gets turned away."*

2. **Happening tonight**, on the same page: **291 people inside**, **120 still to arrive**,
   **1 of 3 scanners online** — each with the sentence that defines it. No number in this
   product appears without its definition.

3. The **Demo controls** disclosure in the amber strip changes who is looking and lets you
   force a `loading` / `empty` / `no matches` / `error` / `denied` screen. It is a demo
   instrument, not a product control, which is why it sits behind a disclosure.

### B. Before doors — check the night will hold

4. **[Inventory for Saturday Music Night](https://snatchit-venue-demo.vercel.app/o/smp_org_wynwood/v/smp_ven_room/events/smp_evt_sat_music/inventory)**
   — *Needs attention* at the top, then a release-by-release matrix: sold, held, remaining,
   against capacity. Two states a spreadsheet collapses are kept apart: **"Sold out."** and
   **"Nothing available — everything is on hold. Release holds to put tickets back on sale."**
   - *Holds* panel: the only action is **Release** — a reversal, never a deletion.
   - **Simulated.** Press Release and you get: *"Nothing was saved. This is the demo: no
     ticket moved, no money moved, nobody was emailed."*
   - **Unavailable, and it says so:** changing the capacity of a release that is already
     selling. The demo explains there is no safe path for it yet and that adding a new release
     is the way to sell more.

5. **[Event setup](https://snatchit-venue-demo.vercel.app/o/smp_org_wynwood/v/smp_ven_room/events/smp_evt_sat_music)**
   — status, sessions, ticket types, resale rules. Only the next legal status is ever offered
   and you can't move an event backwards. **Ticket sales $12,900.00** is labelled as face
   value before fees and refunds, and says plainly that the payout screen showing what you'd
   actually be paid **is not built yet**.
   - **[Reggaeton Sundays](https://snatchit-venue-demo.vercel.app/o/smp_org_wynwood/v/smp_ven_room/events/smp_evt_reggaeton)**
     is the better one to show: it's announced but can't go on sale, and instead of a dead
     greyed-out button it names the requirement — *"Add a ticket type before going on sale."*
   - **Unavailable:** *Cancelling this event*. The panel explains it would show you the exact
     counts it would affect before enabling the confirm, and that the control is withheld
     here because the read that produces those counts doesn't exist yet.

### C. Door staff, during the show

6. **[Door status](https://snatchit-venue-demo.vercel.app/o/smp_org_wynwood/v/smp_ven_room/events/smp_evt_sat_music/door)**
   — counter first: **291 / 411 admitted, 71%, last scan 1 min ago**, then the five scan
   outcomes (admitted, already used, not recognised, blocked, needs review) and an arrivals
   bar.
   - **Devices**: *Main door iPad — online, synced 2 min ago, queue 0*. *Patio scanner —
     offline, synced 19 min ago, stale, queue 7.* The copy that makes the point: *"Offline is
     a status, not an error."*
   - **Door PINs** for staff scanning without a device. The PIN is shown; its hash never is.
   - **Door manifest** — the list the scanners work from, with its freeze status: *"Transfers
     frozen since 8:55 PM — because the door manifest was opened."* Opening it stops ticket
     holders passing tickets on for the session, so it is read-only on a phone: *"not a
     phone-in-a-crowd action."*
   - **What to say when a pass is refused** — six plain reasons with the words to use at the
     rope, including the awkward one: a refund under review means the ticket can't be used
     until the holder cancels the refund in the app.
   - **Flagged at the door** — you escalate with a note; you never adjudicate. *"Snatch It
     reviews these."*
   - **Simulated:** every button here — Close manifest, Escalate, Revoke a PIN, Issue a PIN,
     and the single-guest lookup. No scanner is connected to this preview.

7. **Door staff see less, on purpose.** Open the same event's
   **[attendee list as a scanner](https://snatchit-venue-demo.vercel.app/o/smp_org_wynwood/v/smp_ven_room/events/smp_evt_sat_music/attendees?role=venue_scanner)**:
   the whole guest list closes, and the page explains that door roles check one ticket at a
   time and links to the single-ticket lookup instead. That is the pattern worth showing — a
   boundary that teaches, not a wall.

### D. Who's coming, and reviewing it afterwards

8. **[Who is coming](https://snatchit-venue-demo.vercel.app/o/smp_org_wynwood/v/smp_ven_room/events/smp_evt_sat_music/attendees)**
   — keyed by the **person holding the ticket**, not the buyer. The six-ticket VIP table
   shows six people with one marked as purchaser. That is the thing a PDF box office cannot
   do.
   - **[The same list as finance](https://snatchit-venue-demo.vercel.app/o/smp_org_wynwood/v/smp_ven_room/events/smp_evt_sat_music/attendees?role=venue_finance)**
     keeps the money and loses contact details and check-in, and says so: *"Your role sees
     money and counts, never contact detail or check-in."*
   - **[Purchasers view](https://snatchit-venue-demo.vercel.app/o/smp_org_wynwood/v/smp_ven_room/events/smp_evt_sat_music/attendees?view=purchasers)**
     is the order side. It says **voided**, never "refunded", for a ticket — those are
     different things and the demo keeps them apart.
   - **Simulated:** the download button produces nothing.

9. **After the show.**
   **[Labor Day Rooftop](https://snatchit-venue-demo.vercel.app/o/smp_org_wynwood/v/smp_ven_room/events/smp_evt_done)**
   is a completed event: sales closed, final numbers, and its
   **[door record](https://snatchit-venue-demo.vercel.app/o/smp_org_wynwood/v/smp_ven_room/events/smp_evt_done/door)**
   showing transfers frozen by the doors-time backstop because no manifest was ever opened —
   which is exactly the kind of thing you want to find out afterwards.
   - **Honest gap:** its **[attendee list](https://snatchit-venue-demo.vercel.app/o/smp_org_wynwood/v/smp_ven_room/events/smp_evt_done/attendees)**
     says the sample data has no guest list for that night. The demo invents people for one
     night only. *(On the deployed commit this page currently says "No tickets sold for this
     session yet" beside the event's own "231 sold" — a contradiction fixed in the proposed
     commit.)*
   - **Not built at all:** settlement, payouts, disputes, staff management, and an activity
     log you can read. Several screens promise "this is recorded in your venue's activity";
     there is nowhere yet to read it.

### E. Two more worth showing

10. **[Create an event](https://snatchit-venue-demo.vercel.app/o/smp_org_wynwood/v/smp_ven_room/events/new)**
    — three steps, ends as a draft: visible to your staff only, not announced, not selling.
    **Simulated** — it creates nothing.
11. **[Filter to nothing](https://snatchit-venue-demo.vercel.app/o/smp_org_wynwood/v/smp_ven_room/events?state=nodata)**
    — *"No events match these filters. Your 6 events are still here."* with *Clear filters*.
    Worth 10 seconds in a pitch, because the obvious alternative is a product that tells a
    venue their events are gone and offers to create a duplicate.

---

## 3. Everything simulated or unavailable, in one list

| On screen | Reality |
|---|---|
| Release a hold, Close/Open manifest, Escalate, Revoke PIN, Issue PIN, Set status, Create event, single-guest lookup | **Simulated.** Each answers "Nothing was saved… no ticket moved, no money moved, nobody was emailed." |
| Every figure — sold, remaining, $12,900, 291 admitted, device sync ages | **Sample data.** Clock frozen at 2026-09-12 22:30 Miami, so "19 minutes ago" stays 19 minutes ago. |
| Scanning | **No scanner connects to this.** Devices and counters are invented rows. |
| Download / export | **Simulated.** Button is role-scoped; it produces no file. |
| Sign-in | **Not used.** Fixtures mode has no accounts; the role switch is display only and never an authorization. |
| Changing capacity on a live release | **Unavailable, stated on screen.** No safe path built. |
| Cancelling an event | **Unavailable, stated on screen.** Withheld until it can show what it would affect first. |
| Settlement / payouts | **Not built.** Named on the event page as not built. |
| Staff invites, roles, disputes, readable activity log | **No screen exists.** |
| Guest list for any night but Saturday Music Night | **Not in the sample data**, and the page says so. |
