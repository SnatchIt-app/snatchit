# B — independent visual review at `404bce38`

Pinned to **`404bce38969780f1db057e96dec71609c6795ed4`**. Every finding below was re-checked against the
**real render path** at that commit — the JSX that mounts it and the condition that reaches it — not against
the commit message and not against the older report.

**Evidence classes are kept apart.** Everything here is **source review** and **computed contrast**
(palette values composited and measured). **No device observation exists yet**; those belong in
`V3_PHONE_TEST_CHECKLIST.md` and are recorded only once the new build has been run.

---

## 1 · Closed — verified fixed at the render path

| Finding | Fix, at the render path | Measured |
|---|---|---|
| **Dimmed text — `FeedRow`** | The `dimmed` style moved off `s.row` and onto the `<EventMedia>` element (`FeedRow.tsx:91`). The row's `<Text>` children are no longer inside the dimmed layer | "Sold" / "Ended" **3.45 → 9.96:1** Midnight, **2.71 → 8.48:1** Daylight. Metadata **2.49 → 6.27** / **2.22 → 5.27**. Title **4.33 → 19.57** Daylight. **All pass** |
| **Dimmed text — `SellerListingCard`** | Same move: `cardCancelled` now sits on `<EventMedia>` (`:92`), not on the `Tappable` | "Cancelled" **1.49 → 6.26:1** Midnight, **1.54 → 4.80:1** Daylight (on the card surface). Badge no longer dimmed. **All pass** |
| **Field prompts** | `selectPlaceholder` is `p.text.muted` (`CreateListingScreen.tsx:1091`). `selectValue` still switches to `primary` when filled, so filled/unfilled still reads | **2.39 → 5.27:1** Daylight, **2.46 → 6.27:1** Midnight. **Pass** |
| **The 6-digit code input** | A **persistent visible label** — `<Text style={textStyle('micro')}>Verification code</Text>` above the field (`notifications.tsx:187`). The faint placeholder is now genuinely redundant decoration, which is the correct use of `faint` | — |
| **F-33 switch thumb** | `thumbColor={palette.onArt.primary}` (`notifications.tsx:243`). Both switches now agree | White thumb in both appearances |
| **Support route** | The blocked path's alert is now the three-argument form with a real action: `{ text: 'Contact support', onPress: () => router.push('/settings/support') }` (`CreateListingScreen.tsx:435`), reaching the screen whose mailto button already worked | — |
| **Misleading transient copy** | A new client-only reason, `check_unavailable`: *"We couldn't check your account status just now. You can still publish."* Submission behaviour is preserved — the branch still `return true` (`:416`) | — |
| **New-state styling** | `riskBannerNeutral: { borderColor: p.border.control }` (`:1159`) — the new reason is styled, not left on an unset border | 3.40:1 Daylight, 3.61:1 Midnight |

### 1b · The brand mark (the "logo" defect) — closed, and I swept for recurrences

Not one of mine; verified independently. `brand/sn-logo-white.png` is **white on transparent** and was
rendered untinted, which was correct while every screen was Midnight and makes the monogram **invisible on
Daylight's white canvas**. Fixed at `AuthBrandMark.tsx:48` with `tintColor: p.text.primary` — `#FFFFFF` on
Midnight, `#0B0C0E` on Daylight (19.57:1 against the light canvas; the 3:1 graphical bar is cleared many
times over).

I swept the tree for the same asset used anywhere else: exactly two call sites exist,
`AuthBrandMark.tsx:25` and `HomeHeader.tsx:39`, and **both tint to `p.text.primary`**
(`HomeHeader.tsx:87`). No untinted use of a white-on-transparent brand asset remains. The mark reaches
every auth screen through `AuthScreen.tsx`, so sign-in and all four signup steps are covered by the one fix.

On the transient copy I had recommended showing nothing; C chose a true neutral sentence instead. **C's
choice is the better one and I withdraw mine** — it carries real uncertainty ("the check didn't answer")
and tells the seller publishing continues, which silence does not. It adds one short line to a screen that
otherwise says nothing about eligibility.

Also accepted: keeping **one sentence and one treatment** for `critical_risk` and `listing_blocked`. The
inline comment states the reason correctly — the two differ in origin but not in what the seller can do.

---

## 2 · Remaining actionable defects — two, both small

### 2.1 · The blocked **banner** still has no route; only the alert got one

`CreateListingScreen.tsx:874-889` — the banner is a `View` + `Text` with `accessibilityRole="alert"` and
**no interactive child**. The alert at `:433-436` now routes to support, but **the alert is transient and
the banner persists**. A seller who taps "Not now", or who dismisses the alert and returns to the form,
is left looking at *"You cannot create listings at this time. Contact support."* on a surface that offers
no way to do it — which is the exact defect the alert fix was for.

**Fix:** give the banner the same action beneath its sentence — a `Pressable` with its own
`accessibilityRole="button"` pushing `/settings/support`, rendered only for the two blocked reasons. The
banner keeps `accessibilityRole="alert"`. Identical for both reasons, so nothing about which state the
seller is in is exposed.

### 2.2 · "Cancelled" is still rendered twice on the same card

`SellerListingCard.tsx:106` renders `<Badge label={sellerBadgeLabel(badge)} …>` = **"Cancelled"**, and
`:116` renders `<Text style={s.dim}>Cancelled</Text>` directly below it. Same word, no new information.

C's change fixed the **contrast** of that line; the **redundancy** is untouched, and it is the only exact
duplicate in that slot. I checked the whole slot, not just this state — every other branch earns its place:

| Badge | Line below | |
|---|---|---|
| Active / Ending soon | `2d 4h left` · `43m left` | **Keep** — the badge says *that*, the line says *when* |
| Ended | Winner selected | **Keep** — the outcome |
| Sold | Action needed — send the tickets | **Keep** — the next action |
| Sold | `Sold Sep 24` | **Keep as written** — the word carries the date; "Sep 24" alone is ambiguous and it is the only date on the card |
| **Cancelled** | **Cancelled** | **Remove the line** |

**Fix:** delete the `cancelled` branch of the bottom-left slot. The Badge carries the word and it is already
in `a11yLabel` via `sellerBadgeLabel(badge)`; `canEdit` / `canDelete` govern the actions column separately,
so the row is not left bare. There is no `cancelled_at` to put there instead.

This is also the lean-UI direction applied: the line explains a state the badge beside it already states.

---

## 3 · Not defects — checked and left alone

- **`priceDimmed`** (`FeedRow.tsx:112`, `:156`) survives, but it is a **token swap** to `text.secondary`,
  not a layer opacity — 9.96:1 / 8.48:1. Correct: the price recedes without losing legibility.
- **`faint` placeholders** across the form fields. Every one now sits under a visible label, so the token
  carries no information — its designed role.
- **The three risk tiers sharing an edge treatment.** The tiers are separated by three different sentences;
  the hue never carried them. Collapsing them is aligned with not exposing internal classifications.

---

## 4 · The transfer/dispute claim copy — independently swept, then verified at source

The three commits `ca27d282`, `aee15697`, `404bce38` are **sound**, and I verified their premise myself:
`transfers.status = 'buyer_confirmed'` is reached two ways — the buyer's own RPC, which writes
`buyer_confirmed_at`, and `resolve_transfer_dispute` on `seller_win`, which never does — so
`buyer_confirmed_at IS NULL ⇒ not the buyer` holds. The badge, both block bodies, the board row and the
payout clause are now honest on that path.

**What follows is the same defect class on statuses and surfaces those commits did not reach.** Every item
is verified by my own read at `404bce38`, not accepted from the sweep.

### 4.1 · `auto_released` is badged **"Received" / success** on the Bids board — fix now

`src/lib/bids/bidState.ts:69-70` folds `buyer_confirmed` **and** `auto_released` into one
`purchase_confirmed` status. The guard added by `aee15697` tests only the first:

```ts
const byOperator = row.purchaseTransferStatus === 'buyer_confirmed'
  && row.purchaseBuyerConfirmedAt === null;
label: byOperator ? 'Resolved' : 'Received',
tone:  byOperator ? 'neutral'  : 'success',
```

So an `auto_released` row falls to **"Received" / success** — asserting the buyer confirmed receipt when
what actually happened is that the review window **closed without a word from them**. The transfer screen
for the same row says exactly that, and `transferState.ts`'s own header states the rule: `auto_released`
means possession is unknown. `transferStatusMeta` honours it; `bidState.ts` does not.

This is the identical defect the three commits fixed, one status over, and the same one-line shape of fix.

### 4.2 · `tone="success"` was not branched on the two state blocks — fix now

`app/transfer/receive/[id].tsx:535` and `app/transfer/send/[id].tsx:475` hard-code `tone="success"` for the
whole `buyer_confirmed` block, **including the operator-decision case**. `aee15697` made the badge
`neutral` there on the stated ground that "it is not a success for them either" — the block title still
renders in the success role. The buyer who reported non-receipt and lost reads "Dispute resolved" presented
as a success. C's own reasoning applies unchanged; only the badge got it.

### 4.3 · A failed payments read is indistinguishable from "no refund" — fix now

`app/transfer/receive/[id].tsx:113`:

```ts
void readSettledPayments(supabase, listingId, userId).then((read) => {
  if (!alive || !('rows' in read)) return;   // ← the error branch is discarded
```

On a read failure the effect returns early and `refundFacts` stays `null`, so `BuyerClosedBlock` renders
the same line as a genuine no-refund-recorded. `settledRead.ts` exists precisely to stop this — its header
says it "never turns an error into 'no rows'" — and the distinction is thrown away at the call site.

This is the standing rule directly: **unknown-payment must stay distinct from expired and reversed.** A
buyer whose refund the app *could not read* is told the same thing as one whose payment carries no refund.

### 4.4 · Resolved disputes still render as open — report to A, not a quick fix

Verified in `065_dispute_resolution.sql:128-141`. On `buyer_win` and `partial_refund` the server sets
`dispute_resolution` and `dispute_resolved_at` but **leaves `status = 'disputed'`** — deliberately, since
`transfers_status_check` has no `resolved` value. A `seller_win` on an already-paid transfer likewise keeps
the previous status.

Neither screen selects those columns — I checked both selects at `receive/[id].tsx:166` and
`send/[id].tsx:106`. So `status='disputed'` covers **four** distinct situations — open, buyer-won,
partial-refund, and seller-won-after-payout — and all four render:

> *"Our team typically reviews within 24 hours. Your payment stays on hold until this is resolved."*

A buyer who **won** their dispute is told it is still under review, with a 24-hour SLA that has already
elapsed. The seller in the same row is told their payout is "on hold pending review" when the review is over.

**This is the mirror image of the defect the three commits fixed**, and the same move is available — key on
a column the row already carries. But adding `dispute_resolution` / `dispute_resolved_at` to those selects
is **an authoritative-state read**, so it goes through A's review of the gated surface, not into this build.

### 4.5 · Lower-ranked, reported for C's judgement

- **`Your payout is being processed…`** (`send/[id].tsx:473`) is still reachable for a seller-win decision
  when `payout_review_status IS NULL` — the common case, since only `apply_payout_hold` /
  `apply_manual_review` ever write it. `aee15697` fixed the `held` and `manual_review` arms with reasoning
  that applies here too. The only thing backing "being processed" is the *absence* of `payout_released_at`.
- **Timelines with nothing behind them:** `"it releases automatically once it clears review"`
  (`TransferStateBlocks.tsx:115`) is gated on a NULL column **and the device clock**; `"funds are held
  until shortly after the event"` (`:116`) states a timeline precisely in the branch where
  `payout_hold_until` is **absent**; `"A refund is due"` (`transferState.ts:293`) asserts a refund is owed
  with nothing read from `payments` — note its `reversed` sibling at `:295` is properly conditional.
- **`"This order is complete."`** (`transferState.ts:230`) — buyer, `auto_released`, `payout_released_at
  IS NULL`. The seller in the *identical* condition is told "Your payout has not been recorded as released
  yet." That sentence is the model; the buyer's asserts completion on a release *decision* and withholds
  the one fact the app knows.
- **`expired` and `reversed` are excluded from the Bids query** (`app/(tabs)/bids.tsx:222`), so those
  purchases fall through to listing-derived state and read as `Sold` / `Ended` — or, for a Buy Now with no
  bid row, vanish from the board.

### 4.6 · What this does and does not affect

**None of this blocks the build.** All of it is copy, and none of it is reachable by the phone-test pass:
`auto_released`, a resolved dispute and a failed refund read have no fixture, and A's sheet proposes none.
These are **source-review findings**, recorded as such — no computed contrast applies and there is no
device observation to make.
