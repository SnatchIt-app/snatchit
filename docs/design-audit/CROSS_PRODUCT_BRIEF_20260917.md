# Cross-product design brief — consumer app and manager dashboards (B, 2026-09-17)

**Ownership, stated first.** B proposes the shared visual and interaction direction. **D verifies operational
correctness** — every metric definition, permission and action consequence below is B's *proposal* until D confirms it.
Design only: no product code, payment/auth/transfer rule, database file or active handset-test file is touched; no
sandbox, no production, no deployment, no build. Nothing in `admin/` or `venue/` is modified.

**Prototype:** `docs/design-audit/prototypes/cross-product.html` — five screens (first-run onboarding · dashboard home ·
event management · transfer/dispute review · settings and permissions), each with loading, empty, error,
permission-limited and success states where they apply, at normal and largest text, with a Reduce Motion toggle.
Verified without a browser (the pane was unavailable): **20 of 20 screen/state combinations build**, all nine dashboard
tiles carry a definition, a comparison period and a next step, both destructive actions are role-gated and render disabled
in the permission-limited state, and the permissions table marks the two actions that always need a second approval.

**Grounded in the real console, not an invented one.** The admin console has 18 pages; its role model is
`platform_admin` / `platform_risk` / `platform_support` (`admin/src/lib/permissions.ts:8-17`), and **payout release and
refund execution both require a second person's approval** (`:30-32`). The metric keys on the Today page are real:
`open_cases`, `paid_unsettled`, `transfers_due_6h`, `transfers_overdue`, `refunds_pending`, `disputes_open`,
`stripe_disputes_open`, `evidence_due_72h`, `payout_review`, `reports_pending`, `jobs_failing`, `webhook_backlog`,
`approvals_pending`, `alerts_firing` (`admin/src/lib/routes.ts:59-86`). **The venue dashboard is not at this pin** — it
lives on D's branches — so every venue-specific claim here is explicitly unverified.

## 1. What should be shared
One product, two audiences. Shared, without exception:

| Layer | Shared |
|---|---|
| **Tokens** | The v2 set: black canvas, `#FF1A1A` reserved for action, `status.*` for state, square geometry, no shadows, red-tinted hairlines replaced by neutral ones (the calm pass's proposal), 4 pt spacing |
| **Type** | Inter for everything, Oswald once per screen at most. Tabular figures for every number that sits in a column |
| **Notice ranks** | Blocking (owns a disabled action's reason) · advisory (a state you cannot change) · ambient (metadata). At most one blocking notice per screen |
| **State vocabulary** | One word per state, the same word in both products: *sent, confirmed, held, ended, outbid, refunded, disputed*. A manager reading "held" and a seller reading "held" must mean the same thing |
| **Empty / loading / error / offline** | The same four-part shape: what this is, why it is empty or failed, what is unaffected, one action |
| **Money** | The total is the most prominent figure wherever a price appears — the FTC rule applies to any buyer-facing figure, including one shown to a manager |
| **Motion** | The same ten triggers and durations as the consumer spec, all collapsing through Reduce Motion. No celebration on a money action |

## 2. What must differ, and why
| | Consumer app | Manager dashboard |
|---|---|---|
| **Job** | discover, decide, buy | notice, understand, resolve |
| **Unit** | the event (art-led) | the exception (list-led) |
| **Density** | one decision per screen | many rows per screen, one action per row |
| **Navigation** | five-tab dock, bottom, thumb-reachable | six-section top nav with a breadcrumb — a manager arrives from a link or a notification, so *where am I* matters more than *where can I go* |
| **Imagery** | load-bearing | 52 pt recognition thumbnails at most |
| **Colour** | red = the one action | red = **danger only**. On a dashboard the primary action is white-on-black, because the operator's dangerous actions must own red exclusively |
| **Numbers** | one price, dominant | aligned columns, tabular, with definitions attached |
| **Success** | a state block and a haptic | a sentence naming what changed, who it told, and what is now logged |
| **Irreversibility** | disclosed on the button | disclosed on the button **and** gated by role **and** queued for a second approval |

That colour inversion is the single most important difference. In the app, red invites. In the console, red warns — so the
console's ordinary primary action is monochrome, and red is spent only on actions that move money or restrict a person.

## 3. The shared system, layer by layer
**Navigation.** Consumer: labelled dock (five). Console: top nav (six) + breadcrumb + page title; no nested sidebar. A
manager can always answer *what is this page, what needs me, what happens if I press this*.
**Page hierarchy.** Eyebrow (context) → H1 (what this is) → one-line summary of what needs attention → grouped content →
destructive zone last, visually separated.
**Tables.** Label column left, numbers right and tabular; status as a bordered chip, never a bare colour; the row's next
step as the last column in words, not an icon; "needs attention" sorts first by default and says so.
**Cards / tiles.** A metric tile is: number → plain label → definition → comparison → next step. A tile without all five is
not a tile; it is a number with a caption, which is the thing managers cannot act on.
**Filters.** Chips with counts, one row, horizontally scrollable, the active one carrying a neutral fill. The current
filter is always stated in words above the table ("Sorted by: needs attention first").
**Statuses.** Bordered chips: green confirmed/healthy, amber waiting-on-someone, red failed/disputed, grey terminal. Never
colour alone — every chip carries a word (Apple's Differentiate Without Color, and eBay's messaging patterns).
**Alerts.** The three notice ranks. A blocking notice on a dashboard always names who *can* act if the reader cannot.
**Empty states — and the distinction the consumer app already makes.** Four parts (§1), and **"no data" and "no match"
must never render the same**. The consumer app has this as a first-class distinction: `StateView` takes
`kind: 'offline' | 'error' | 'empty' | 'noMatch'`, and Explore renders `noMatch` with its own copy. The dashboards do not,
and it has already produced a defect **D found only by rendering**: in venue, `?state=nodata` and `?state=empty` render
identically as "No events yet." with a Create button, because `lib/data.ts:27` returns the empty set for both and
`EventsTable.tsx:64` tests the count before the filter — so **a manager who filtered to nothing is invited to create a
duplicate event**, and the app's own note says these must stay apart for exactly that reason. The other three venue
surfaces dodge it by passing `"live"` for nodata; the events list does not. **[measured, D]** The shared rule: *nothing
exists yet* offers creation; *your filter matched nothing* offers clearing the filter and never offers creation.
The console's most important empty state remains "nothing needs you", which must read as success rather than absence.
**Loading.** Skeletons that mirror the real layout, never a spinner over a whole page; a table keeps its header while its
rows load so the columns do not jump.
**Permissions.** Hidden is wrong; a named reason plus a route to the person is right. **The exemplar already exists in our
own product, and it is better than the pattern I invented:** venue's attendees page renders the roster *and* the sentence
"Your role sees money and counts, never contact detail or check-in." **[measured, D]** That teaches the boundary at the
moment it is hit, instead of explaining an absence — and it is the pattern to copy, not the console's info alert (which
names the role but offers no route) and not a hidden form (which teaches nothing). The consumer-side analogue is a disabled
action carrying its own reason; Posh does the same by greying a disabled transfer rather than hiding it.
**Destructive actions.** A distinct class: separated block with a red left edge, a required typed reason, the consequence
in the button's own sub-line, and — where the model demands it — "you are requesting, not executing; a second admin
approves before money moves." Never adjacent to a routine action, never the default focus.

## 4. Onboarding a first-time manager
Apple's guidance is flow-level and predates the current design language: teach through interactivity, prefer contextual
tips to one upfront flow, keep it skippable and don't repeat it, postpone nonessential setup, ask permissions at first use,
and **don't put licensing in onboarding**
([HIG Onboarding](https://developer.apple.com/design/human-interface-guidelines/onboarding)). Arc Search's first run
delivers value before asking for identity ([arc.net](https://arc.net/blog/arc-search)). The proposal follows both:

**Three steps, about four minutes, skippable at every step, and it lives in Settings › Getting started afterwards.**
1. **What you can do here — and what you can't.** Two columns: your capabilities, and the two actions that are deliberately
   not yours (payout release, refund) with *why* (they move real money and take two people) and *who to ask*. Ending on
   "nothing you do here is silent — every action is logged with your name and your reason" reframes the audit log as
   protection rather than surveillance.
2. **Clear one real item together.** A live item from their own venue, with one sensible next step, and an explicit note
   that the rest is automatic. Teaching by doing, on real data, once.
3. **How to read the numbers.** Two real tiles side by side — one that needs action, one that is information — and the rule:
   amber edge means you, quiet means information, nothing amber means nothing to do today.

**Not in onboarding:** terms, licensing, feature tours of pages they have no permission for, or any step that must be
completed before the dashboard is usable.

## 5. "Could a new manager figure this out?" — a walkthrough
Read as a first-time venue manager with no marketplace background, using the prototype.

| Moment | What they see | Do they know what to do? |
|---|---|---|
| First sign-in | "What you can do here", with the two forbidden actions named and explained | **Yes.** The most common new-manager fear — pressing something expensive — is answered before they can press anything |
| Dashboard, three items | "Three things need you", each tile with a definition and a next step | **Yes**, provided the labels are the plain ones in §6. With the current keys (`paid_unsettled`, `webhook_backlog`) — **no** |
| Dashboard, nothing to do | "Nothing needs you right now", plus what is being watched | **Yes**, and this is the state most dashboards get wrong |
| A seller is late | "Sellers who haven't sent tickets · 3 · Remind the seller" | **Yes.** One verb, one object |
| A payout is held | "Payouts waiting for review · 2 · Review them" | **Partly.** They will understand *what*; whether they can act depends on role, and the tile must say so rather than failing at the click |
| An event page | Needs-attention rows first, each with a next step in words | **Yes** |
| A dispute | Facts, then a timeline, then a separated decision block naming both outcomes as irreversible and requiring a typed reason | **Yes on comprehension; deliberately hesitant on action** — which is correct for a decision that moves $134 of someone else's money |
| Permission-limited | The action is visible, disabled, with the reason and who can | **Yes.** They learn the shape of their own role by reading the interface rather than by failing |
| Something breaks | "Couldn't load today's numbers… nothing has changed and no action you took has been lost" | **Yes.** The critical sentence is the second one |

**Where a new manager would still struggle, honestly:** the word "case" is our jargon (nobody outside support calls a
customer problem a case); "review window" needs a tooltip the first time; and the money tiles conflate *what buyers paid*
with *what sellers received* unless both are labelled, which is why the event page shows them as two adjacent figures.

## 6. Metrics — corrected by D, whose definitions are authoritative
**I had this wrong in the first draft and the error mattered.** I gave several metrics a comparison period. D's answer,
from `admin/analytics-redesign @ 64f26f9` and `admin/docs/ANALYTICS_DATA_CONTRACT.md` (which B then read directly):

> **All fourteen `ops.today()` counts are point-in-time. None of them has a comparison period.** Only the money measures
> from `ops.money_overview` are period aggregates with a change against the equal-length previous period — and one of
> *those*, seller funds pending release, is point-in-time too, deliberately excluded from comparisons and charts because it
> has no date predicate.

So a "vs yesterday" line on an open-work count is a number the data layer cannot produce. That is the same class of mistake
as my withdrawn checkout finding: **I designed a surface that implied data nobody had**. The prototype is corrected — open
work says *counted right now* and, where the rows support it, *oldest has waited 3h 40m*, which is derivable; only money
tiles carry a previous period.

**D's labels already exist and supersede mine.** `SHORT_LABEL` in
`admin/src/components/analytics/sections.tsx:67-82` and `METRIC_DEFINITIONS` in
`admin/src/app/(console)/page.tsx:25-40` were written for exactly this job. **Use those.** My three distrusted guesses were
wrong in instructive ways:

| Key | My guess | D's real definition | Why mine was harmful |
|---|---|---|---|
| `paid_unsettled` | "Sales stuck mid-payment" | **Paid orders without a transfer** — succeeded payments past the grace window with no transfer row yet; money at rest | Mine implied a broken payment. A manager would have escalated a payment incident that isn't one |
| `webhook_backlog` | "Payment messages waiting" | **Stripe webhooks stuck** — events received and unprocessed past the staleness threshold; not lost, not an outage | Mine lost "past a threshold", which is the whole signal |
| `payout_review` | "Payouts waiting for review" | **Payouts in manual review** — flagged by risk tiering, no Stripe transfer id yet | Closest of the three; "manual" and the missing transfer id both matter |

**Two landmines in the money set, from the contract, both now rendered in the prototype:**
1. **"Fully refunded payments" is not "refunds".** Status `refunded` is set only when the refund covers the whole total, so
   **partial refunds are absent from that count and still counted in full in captured sales**. The tile says so, and its
   amount is shown as *not known exactly · at most $268.00*, because the contract marks the value uncertain with an upper
   bound. A dashboard that printed a confident refund figure would be lying in a way nobody would catch.
2. **Platform fees are gross, never net revenue.** Net revenue does not exist yet (AN-3, undefined). The tile is labelled
   gross and says "this is not net revenue".
Two more contract rules the prototype now honours: **bank payouts are "not tracked" and never a number** — shown as a blank
with the reason rather than a zero — and **freshness is stated** ("figures computed 3 min ago"), because the contract
requires a stale badge past 15 minutes and "unknown", never "fresh", when `computed_at` is missing.

**The rule that survives:** a metric may appear on a dashboard only if it can say what it counts, over what basis, and what
to do about it. What changed is the middle term — for nine of fourteen the honest answer is "right now", not a period.

## 7. Where the dashboards make people hunt, guess, or hesitate
Two of my six first-draft findings were wrong about what is built. Corrected, with D's measured findings added and
attributed — D's are **[measured, D]**, mine are **[source, B]**.

**Corrections to my first draft:**
- **Permission-limited UI is neither hidden nor disabled — it already names who can act.** `admin/src/app/(console)/orders/[paymentId]/page.tsx:388` renders "Only founders and risk operators can record dispute outcomes."; `:415` "Only a founder can request a payout release."; `:423` "Only a founder can request a refund." **[measured, D]** My X4 was written against a hidden form that does not exist. **The real gap is narrower and better: the alert names the role but gives no route to the person.** The prototype now shows the named person and an "Ask them" affordance.
- **The destructive actions already say requesting, not executing.** The labels are "Request release" and "Request refund" (`:403`, `:440`), the body says nothing changes until the other founder approves (`:407`), and the outcome reads "Awaiting a second operator's approval. Nothing has changed yet." (`ConfirmForm.tsx:45-46`). **[measured, D]** My X5 drops to a wording note.

**The findings that stand, most valuable first:**
1. **Text does not scale. [measured, D]** `body { font-size: 14px }` in both apps (`admin/src/app/globals.css:86`, `venue/src/app/globals.css:79`), px sizes on every shared utility, and 260 `text-[Npx]` literals across 49 admin files. Rendered on the venue Door page at a 200% browser text-size setting: **78 of 212 text elements do not grow at all** while their neighbours double, and the page **overflows horizontally by 195 px at 1024 px**. Page zoom hides it; the text-size setting does not. **This is the highest-leverage item in the shared-direction lane and it is one rule in two files.** It is also the dashboards' version of what the consumer app solved with `textStyle()` and a scale cap.
2. **99 controls under 24×24 at 390 px** in the console's own audit (`admin/docs/ui-audit/ui-audit-combined-light-f9-a11y.md`, `smallTargetsAt390`) — /orders 27, /users/:id 18, /marketplace 16. The redesign's verification summary omits that metric and the redesign-head audit output was not committed, so **the current number is unknown rather than fixed**. **[measured, D]**
3. **Metric definitions are hover-only.** `admin/src/components/ui/MetricTile.tsx:33-38` puts the definition in an `<abbr title>` — unreachable on touch and by keyboard. The redesigned Today tiles print it inline (`sections.tsx:120`); the older tiles did not follow. **[measured, D]** Every tile in my prototype prints its definition inline, always.
4. **Six venue panel headings are raw database identifiers** — `venue.scan_device`, `venue.door_pin · never the hash`, `catalog.event_session.door_open_at`, `venue.inventory_hold`, `venue.scan`, `venue.validate_ticket_online` — rendered unconditionally, including in database mode. **[measured, D]** This is the jargon problem one level worse than a metric key: a schema name as a section heading.
5. **The two dashboards have visually diverged.** The console dropped all-caps per the owner-approved direction; the venue dashboard still renders table headers, buttons and badges in caps with letter-spacing. **[measured, D]** Exactly the drift a shared token layer exists to prevent.
6. **Two denial paths of very different quality in venue.** The entry denial explains the situation and offers a way out; the role-level denial is a bare "You don't have access to this." with no reason, no who-can-grant and no navigation — **and the nav item is hidden for that role, so a bookmark is a dead end**. **[measured, D]**
7. **Jargon at the top level, and no comparison anywhere.** Nine of fourteen metric keys are engineering vocabulary, and no tile shows a basis. **[source, B]**, now with D's split (§6) as the correct basis wording.
8. **Same-red destructive actions.** `ConfirmForm.tsx:15` renders the `danger` prop as `btn-primary` — **the same red as an ordinary primary action** — and the prop is applied inconsistently ("Relist" carries `danger`, "Deny" does not). **[measured, D]** See §8 X5 for why the defect and its remedy are separate decisions.

## 8. Ranked improvements
Re-ranked after D's verification. The console's correctness posture is **stronger than I assumed** — roles re-checked in the
database, second approval on money, requesting-not-executing copy already written, denial reasons already named. The
remaining problems are comprehension and scaling problems, and one of them is an accessibility defect.

| # | Improvement | Why now | Owner |
|---|---|---|---|
| **X0** | **One font-size rule in two files, and it is the root cause, not the literals.** `body { font-size: 14px }` (`admin/src/app/globals.css:86`, `venue/src/app/globals.css:79`) **overrides the user's own default size before any utility class applies** — so the 260 `text-[Npx]` literals are the symptom and this line is the disease. Replace with the rem scale in §11 | 78 of 212 elements on one page do not grow at a 200% browser text setting, and the page overflows horizontally by 195 px at 1024 px. An accessibility defect, not a preference — and the cheapest fix per affected user in either product | **D** (scale supplied in §11, as asked) |
| **X1** | Definitions **inline**, never in a `title` attribute, on every tile | Hover-only definitions are unreachable on touch and by keyboard — so the metric's meaning is inaccessible to exactly the operators most likely to misread it | **D** |
| **X2** | Basis on every tile: *counted right now* or *last N days* | Nine of fourteen are point-in-time and none says so; a manager cannot tell an open-work count from a trend | **D** (definitions), B (wording) |
| **X3** | A next step in words on every tile | Turns a dashboard into a work queue | **D** |
| **X4** | A **route to the person**, not just their role, in every permission notice | The reason is already named; the dead end is the remaining half. Include the role-level venue denial, which currently has no reason, no who-can-grant and no navigation | **D** |
| **X5** | **Separate the destructive-action defect from its remedy** | The defect is real and citable: `ConfirmForm.tsx:15` renders `danger` as the same red as an ordinary primary, and the prop is applied inconsistently. **The defect can be fixed inside the owner-approved direction** — give destructive actions their own treatment (error-coloured outline, separated block, typed reason) without changing what red means for primary actions. **The inversion I proposed is a different, larger question** — it reverses an owner-approved rule (red = primary action, active nav, brand dot, approved 2026-09-14), so D is carrying defect-plus-both-options to the owner as one decision, citing my framing as the alternative. **I agree with that routing and I am not settling it on a branch** | **owner decides; D carries it** |
| **X6** | Re-measure the 24×24 target count at the redesign head | The console's own audit found 99 under-sized controls; the redesign head's number is unknown because that output was not committed | **D** |
| **X7** | "Nothing needs you" as a designed success state | Prevents the most common misreading of a healthy dashboard | **D** |
| **X8** | Three-step onboarding, skippable, resumable from Settings | A new manager currently learns by pressing things | **D** |
| **X9** | Replace the six raw schema identifiers used as venue panel headings | A section titled `venue.inventory_hold` is jargon one level worse than a metric key | **D** |
| **X10** | Converge the two dashboards' type case | The console dropped all-caps per the approved direction; venue did not. Drift a shared layer exists to prevent | **D**, B proposes the rule |
| **X11** | Shared token and component adoption (§9) | Stops all of the above recurring | B proposes, A sequences |

## 9. Shared patterns that should become reusable components
Each is used by both products, and each exists in neither as a component today.

| Component | Consumer use | Console use |
|---|---|---|
| `Notice` (blocking / advisory / ambient) | delivery blocker, hold, payment state | permission limits, load failures, approval waiting |
| `StatusChip` (word + border, never colour alone) | transfer and bid states | case, payout, job and dispute states |
| `MetricTile` (number · label · definition · comparison · next step) | — (or a seller's own sales) | every dashboard tile |
| `DataTable` (label left, tabular right, status chip, next-step column, needs-attention-first) | Bids list | cases, orders, transfers, events |
| `DestructiveBlock` (separated, typed reason, consequence on the button, approval notice) | none — the consumer equivalent is the sticky action bar | refunds, payout release, restrictions, dispute decisions |
| `StateView` (what this is · why · what is unaffected · one action) | already exists in the app | should be adopted by the console |
| `MoneyFigure` (tabular, total-dominant, all-in labelled) | prices | payouts, buyer-paid vs seller-received |
| `GettingStarted` (skippable, resumable, three steps) | could serve a first-time seller | first-time manager |

**Sequencing note:** `StateView`, `Notice` and `StatusChip` should be built once in the shared token package rather than
twice. That package already exists (`packages/design-tokens`) and already has a parity test, so the mechanism is there —
but the mobile tokens do not reach the web app until the package is repacked, which is A's constraint to schedule, not mine.

## 10. What B verified, what D verified, and what nobody has
**B, from source:** the console's 18 pages, the role model and second-approval rule (`permissions.ts:8-17, 30-32`), the
fourteen metric keys (`routes.ts:59-86`), and the money-measure definitions read directly from
`admin/docs/ANALYTICS_DATA_CONTRACT.md` on D's head after D pointed me at it. The prototype was verified **structurally in
Node** — 20 of 20 screen/state combinations build, every tile carries a definition, basis and next step, both destructive
actions are role-gated — because the browser preview pane was unavailable. **No screen here was rendered and looked at.**

**D, measured on `admin/analytics-redesign @ 64f26f9` and `venue/slice1-integration @ d2c634a`:** the point-in-time /
period split, the real labels and definitions, the permission-notice copy as built, the requesting-not-executing copy, the
`danger`-renders-as-primary defect, the 200%-text-size measurement (78 of 212 elements, 195 px overflow), the 99 under-sized
controls, the `abbr title` definitions, the six schema-name headings, the caps divergence and the two denial paths. **Those
are D's observations, not mine, and the brief says so at each one.**

**Nobody has yet:** a rendered check of my prototypes in a browser; the current under-24×24 count at the redesign head; a
venue statement verified at my own pin (D offered to render venue credential-free in fixtures mode — I have not taken that
up, so every venue claim here is D's measurement, cited as such); and the owner's decision on the red question, which is
the one thing in this brief that two sessions agreeing cannot settle.

**Two things I got wrong in the first draft, both corrected in place:** comparison periods on point-in-time counts (§6),
and a permission-limited pattern written against a hidden form that does not exist (§7). Both were caught by D checking
rather than accepting, which is the third time today that has saved a document from shipping a confident error.

## 11. The type scale for X0, as D asked for it
Mirrors what the consumer app solved with `textStyle()` and `MAX_DISPLAY_FONT_SCALE`, in web terms. **The whole point is the
first line.**

```css
/* 1. Never set a font size on html or body in px. This is the defect. */
html { font-size: 100%; }              /* inherit the user's own default */
body { /* no font-size at all */ }

/* 2. One scale, in rem, so every size multiplies the user's default. */
:root {
  --t-eyebrow: 0.75rem;    /* 12 at a 16px default — the floor, used only for labels */
  --t-sm:      0.875rem;   /* 14 — secondary text, table cells */
  --t-body:    1rem;       /* 16 — default body */
  --t-title:   1.0625rem;  /* 17 — card and section titles */
  --t-h2:      1.375rem;   /* 22 */
  --t-h1:      1.625rem;   /* 26 */
  --t-num:     1.625rem;   /* 26 — metric figures, tabular */
  --lh-tight:  1.25;       /* unitless, so it scales with the size */
  --lh-body:   1.45;
}
```
**Rules that go with it, because a scale alone does not fix the 195 px overflow:**
1. **No `font-size` in px anywhere outside this block** — that includes the 260 `text-[Npx]` literals and the shared
   utilities (`.eyebrow`, `.btn`, `.btn-sm`, `.data-table th`, `kbd`).
2. **Line heights unitless.** A px line height clips as soon as the size grows.
3. **`min-height`, never `height`, on anything containing text**, and `min-height: 2.75rem` (44 at default) on every
   control — which also addresses the 99 under-24×24 targets.
4. **`min-width: 0` on every flex child that contains text**, or a long label refuses to wrap and pushes the row wide.
5. **Tables either wrap or scroll in a labelled container** — a data table at a 200% text setting cannot keep six columns
   in 1024 px, and a horizontal scroll with a visible affordance is honest where silent overflow is not.
6. **Page containers in rem** (`max-width: 80rem`), not px, so the measure grows with the text.

**Acceptance criterion, phrased as D's measurement so it can be re-run:** at a 200% browser text-size setting on the venue
Door page, **every** text element grows (the current figure is 78 of 212 that do not), and **no page overflows horizontally
at 1024 CSS px** (currently 195 px). Page zoom is not a substitute test — it scales everything and hides the defect.

## 12. D's render of B's prototype — and the two defects it found
**B's prototypes had never been rendered by B** (the preview pane was unavailable). D served the file over HTTP and drove
it, which is how the following came back. **This is D's evidence, not mine.**

**It renders cleanly:** no horizontal overflow at 1024 px, the switchers work, and the corrected metric wording is visibly
in place — "counted right now — this is not a total over a period", "partial refunds are not here", "gross, before refunds
— this is not net revenue", and pending release carrying "it ignores the date range, so it is deliberately never compared
or charted". Largest-text mode scales the proposed UI (12.5 → 16, 26 → 32, 14 → 18).

**Two defects, both now fixed:**
1. **One heading element and no landmarks.** The file had a single heading for five screens and no `<main>`, `<nav>` or
   `<header>` — so every section title was styled text with no role, and a screen-reader user had no way to move between
   sections. **This matters because a prototype is a specification:** the console today asserts exactly one `main` and one
   `h1` per page (`pagesWithoutSingleMain: 0`, `pagesWithoutSingleH1: 0` across 56 views), so a build from my file would
   have regressed a check the console currently passes. **Fixed:** a `banner` header with a labelled `nav` carrying
   `aria-current`, a `main` landmark per screen, and `role="heading"` with explicit levels on every section title —
   verified mechanically, one main and one banner per screen across all twenty states, no screen with two level-1 headings.
2. **A silent webfont dependency.** The file pulled Google Fonts at render time; under a CSP that restricts `style-src` it
   is blocked without warning, which is what happened on D's server — so the typography D reviewed was not the typography
   proposed. **Fixed:** approximating fallback stacks, and a banner that says plainly when the webfont did not load, so
   nobody reviews type that isn't the proposal.
3. **My own review chrome did not scale** — 9.5 px labels and 11.5 px buttons, so a reviewer at 200% could not read the
   control that turns on 200%. **Fixed:** the chrome is in rem with `min-height` targets. An instructive miss: I wrote a
   brief whose top item is that dashboards hard-code px sizes, in a file that hard-coded px sizes.

**D's own audit** is `design/d-dashboard-usability-20260917 @ 940f944` (`docs/venue-dashboard/DASHBOARD_USABILITY_AUDIT_D_20260917.md`
plus three prototypes), held locally and unpushed because a push runs CI and the owner's standing instruction for this
stretch is no builds. **Whether it is pushed for review is the owner's call, not mine** — I have not asked for it, and D's
findings are cited here from their message rather than from that branch.
