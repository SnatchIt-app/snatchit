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
**Empty states.** Four parts (§1). The console's most important empty state is "nothing needs you" — it must read as
success, not as absence, or managers will assume it is broken.
**Loading.** Skeletons that mirror the real layout, never a spinner over a whole page; a table keeps its header while its
rows load so the columns do not jump.
**Permissions.** Hidden is wrong; disabled with a reason is right. Every gated control says *who* can do it. (Posh renders a
disabled transfer greyed out with the reason rather than hiding it — the same principle.)
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

## 6. Metrics: plain labels, definitions, comparisons, next steps
The current keys are engineering names surfaced to humans. Proposed replacements — **each definition unverified until D
confirms it against `admin/docs/ANALYTICS_DATA_CONTRACT.md`**:

| Current key | Plain label | Definition to show | Comparison | Next step | Jargon verdict |
|---|---|---|---|---|---|
| `transfers_overdue` | Sellers who haven't sent tickets | Sold and paid for; the seller has not marked them sent. Counted now | vs yesterday, same time | Remind the seller | replace |
| `transfers_due_6h` | Deadlines in the next 6 hours | Sales whose send window closes within 6 h. Counted now | none needed | See them, oldest first | replace |
| `paid_unsettled` | Sales stuck mid-payment | Buyer paid but the sale is not recorded complete. Counted now | days since the last one | How this clears itself | **replace — the worst offender.** "Unsettled" reads as unpaid |
| `disputes_open` | Buyers who reported a problem | A buyer opened a case and is waiting for a person | oldest wait time | Read the case | replace |
| `stripe_disputes_open` | Card disputes from banks | A bank is reversing a charge; evidence is due | this quarter | What evidence we send | replace ("Stripe" is our vendor, not their concept) |
| `evidence_due_72h` | Evidence due in 3 days | Bank disputes whose evidence deadline is inside 72 h | none | Send evidence | replace |
| `refunds_pending` | Refunds waiting to be paid | Approved refunds not yet back with the buyer | average wait | See each refund | keep meaning, soften wording |
| `payout_review` | Payouts waiting for review | Held for a manual check before money moves | how many sellers | Review them | replace |
| `open_cases` | Everything open | Every case of any type still unresolved | vs last week | Open the list | keep |
| `reports_pending` | Reports about content or users | Someone reported a listing or a person | oldest wait | Read the reports | keep |
| `jobs_failing` | Background jobs failing | Scheduled work that errored on its last run | days since last failure | See the schedule | replace ("jobs" is ours) |
| `webhook_backlog` | Payment messages waiting | Messages from our payment provider not yet processed | normal range | What this affects | **replace — meaningless outside engineering** |
| `approvals_pending` | Waiting for a second approval | Money actions requested by one admin, awaiting another | who requested | Review the request | keep, and say who |
| `alerts_firing` | Active alerts | Monitoring alerts currently triggered | none | See what fired | replace ("firing" is ours) |

**Rule behind the table:** a metric is allowed on a dashboard only if it can state what it counts, over what period, and
what to do about it. Nine of fourteen currently cannot do the first, and none of them shows a comparison period.

## 7. Where the dashboards make people hunt, guess, or hesitate
**[source, B verified]** and marked where it is inference rather than observation:
1. **Jargon at the top level** — nine of fourteen metric keys are engineering vocabulary (§6). Verified from source.
2. **No definitions anywhere on a metric tile** — `routes.ts` maps a key to a destination, and nothing maps a key to a
   sentence. So the tile's meaning lives in the reader's head. Verified.
3. **No comparison period on any tile** — a number with no baseline cannot tell a manager whether today is unusual.
   Verified by the absence of any period parameter in the metric href map.
4. **Permission failure is discovered late** — `permissions.ts` exists to hide forms the operator cannot submit, and its own
   comment says a hidden form is not security. Hiding also teaches nothing: the manager cannot learn the shape of their
   role. **Proposal:** disable with a reason instead of hiding.
5. **Fear of the irreversible** — payout release and refund require a second approval, which is excellent, but a manager
   cannot tell from the button that they are *requesting* rather than *executing*. One sub-line fixes it. Inference from
   the permission model; D to confirm the UI as built.
6. **The venue dashboard is unverified here** — not at this pin. Anything about its current state is D's to supply.

## 8. Ranked improvements
**Release-critical usability (dashboards):** none found by B. The console's correctness posture — role checks re-verified in
the database, second approval on money, audit logging — is stronger than its legibility. The problems are comprehension
problems, which matters because a manager who misreads a number acts wrongly with correct permissions.

| # | Improvement | Why now | Owner |
|---|---|---|---|
| **X1** | Plain labels + a one-line definition on every metric tile | Nine of fourteen are unreadable to a non-engineer; this is the cheapest comprehension win in the product | D (definitions), B (wording) |
| **X2** | A comparison period on every tile | A number without a baseline cannot trigger a decision | D |
| **X3** | A next step in words on every tile | Turns a dashboard into a work queue | D |
| **X4** | Disabled-with-a-reason instead of hidden, everywhere | Teaches the role, prevents late failure, and names who can act | D |
| **X5** | The destructive-action class (separated block, typed reason, "requesting not executing") | The guard exists in the database; the interface should say so | D, with B's pattern |
| **X6** | "Nothing needs you" as a designed success state | Prevents the most common misreading of a healthy dashboard | D |
| **X7** | Three-step onboarding, skippable, in Settings afterwards | A new manager currently learns by pressing things | D |
| **X8** | Shared token and component adoption (§9) | Stops the two products drifting apart again | B proposes, A sequences |

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

## 10. What B cannot verify
No device, no browser render (the preview pane was unavailable — the prototype was verified structurally in Node instead),
no sandbox, no production. The venue dashboard is not at this pin. Every metric definition, permission claim and action
consequence is a proposal pending D's verification, and the three plain-language labels I am least sure of are
`paid_unsettled`, `webhook_backlog` and `payout_review` — precisely because their current names hide what they count.
