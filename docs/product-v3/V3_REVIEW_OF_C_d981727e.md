# B — verification of C's presentation fixes at `d981727e`

Reviewed against the code at `d981727e`, measured, not read from the commit message. **Four fixes are
correct. One is incomplete, one component was missed entirely, one site is classified into the wrong
bucket, and one owner instruction is not yet addressed.**

C's own diagnosis is the right one and I want to quote it, because the gap is not in the reasoning:

> "an ancestor opacity is a contrast multiplier on everything below it … The palette test passes because
> it grades the token; an ancestor multiplier is invisible to it."

That is exactly right, and it is **general**. The fix and the test are not.

---

## 1 · Correct, verified

| Fix | Verified how |
|---|---|
| **`TicketEventGroup`** — `opacity: 0.92` moved from `pastCard` to `pastThumb` | The right fix, and the same pattern `BidCard` already used: the artwork recedes, no text is scaled. Recession still carried by the layout swap and the quieter ink |
| **Risk-banner edges** — fills removed, edge from the status tokens | Measured at `d981727e`: **Midnight** warning **11.48:1**, error **6.42:1**; **Daylight** warning **6.27:1**, error **6.07:1**. C's "6.07–11.48:1" is accurate. The ungraded tints (1.32–1.75:1 against the Daylight canvas, 1.02–1.07:1 against each other) are gone |
| **`text.faint` → `text.muted`** at the listed sites | Confirmed by re-scanning the tree: the counters, the price eyebrow, the " total" suffix, the seller card's line, and the legal/privacy dates all moved |
| **Bio counter dead code** — `trim().length > 200` against `maxLength={200}` | Independent catch, correct: `trim` can only shorten, so the `status.error` state was unreachable and the counter sat at the decoration ink forever |

Collapsing `high` and `critical` onto one edge is **right, not a regression**. The owner's instruction is not
to expose internal risk classifications merely to make two states look different; the three tiers are
separated by three different sentences, and `high` additionally gets its own titled sheet.

## 2 · Incomplete — `SellerListingCard`: the token moved, the multiplier did not

`dim: p.text.faint → p.text.muted` landed. **`cardCancelled: { opacity: 0.55 }` (line 159) survives**, and
is still applied to the whole `Tappable` at line 81. So the word "Cancelled" is now muted *inside* a 0.55
card:

| | before `d981727e` | **after `d981727e`** | |
|---|---|---|---|
| "Cancelled" — Midnight | 1.49:1 | **2.50:1** | still fails |
| "Cancelled" — Daylight | 1.54:1 | **2.11:1** | still fails |
| Badge text — Daylight | 4.12:1 | **4.12:1** | unchanged, still fails |

Better, and not fixed. The multiplier is the defect; the token was only making it worse.

## 3 · Missed entirely — `FeedRow` is not in the diff

`src/components/discovery/FeedRow.tsx` is untouched at `d981727e`. `dimmed: { opacity: 0.55 }` still sits on
`s.row` — **the whole row, text included** — and this is the more severe of the two, because the row is a
`Pressable` with `accessibilityRole="button"` that still navigates:

| Element | Token | Midnight | Daylight |
|---|---|---|---|
| Event name | `text.primary` | 6.27:1 | **4.33:1 FAIL** |
| Date / venue / quantity, "all-in" caption | `text.muted` | **2.49:1 FAIL** | **2.22:1 FAIL** |
| **The status word "Sold" / "Ended"** | `text.secondary` | **3.45:1 FAIL** | **2.71:1 FAIL** |
| Price (via `priceDimmed`) | `text.secondary` | **3.45:1 FAIL** | **2.71:1 FAIL** |

The sharpest part is unchanged from my last review: `FeedRow`'s own comment says *"On a sold or ended row
the CLAIM lives in the status line below (plus the dimmed treatment)"* — and that status line is the thing
being dimmed below the floor. `priceDimmed` compounds it by swapping the price to `secondary` **inside** the
already-dimmed row.

**Fix, both components:** move the opacity to the artwork wrapper, as `TicketEventGroup` now does and
`BidCard` always did, and carry "past" on the text side with a token swap.

## 4 · Test scope — the rule is stated generally, enforced locally

`tests/v3-tickets-past-card.test.ts` imports `@/src/components/tickets/TicketEventGroup` and nothing else.
TP2 walks the tree carrying the product of every ancestor's opacity — the right technique — but only for
that one component. The commit message reads as though the rule now holds wherever an ancestor opacity is
added; it holds for the past ticket card. The two components in §2 and §3 are exactly the cases it would
catch, and they are outside its reach.

## 5 · Wrongly classified — `selectPlaceholder` is not a placeholder

`CreateListingScreen.tsx:1070` is still `text.faint` (2.46:1 / 2.39:1), kept by RD15's "placeholders and
named decoration only".

It is not a placeholder. `placeholderTextColor` sits on a `TextInput`, under a visible label, and vanishes on
the first keystroke. `selectPlaceholder` is a rendered `<Text>` inside a `Pressable`, at `body` **15px**, and
it is the **persistent** content of the control until something is chosen:

> **Select area or venue · Pick a date · Pick a time · Select platform**

Four of them, all **required to publish**. The owner's instruction names this case directly — *"use readable
colours for required-field prompts"*. It should be `text.muted`; `selectValue` already switches to
`text.primary` once filled, so the filled/unfilled distinction survives the change.

## 6 · Not yet addressed — the 6-digit code input

`app/settings/notifications.tsx` is not in the diff. The code field still has **no visible label**, and its
only on-screen naming is a `text.faint` placeholder that disappears on the first keystroke. The owner asked
for a persistent visible label if reachable. It is reachable — it renders whenever a push challenge reaches
`phase === 'awaiting_code'`. The same file still holds the F-33 `thumbColor={palette.text.primary}`.

---

## 7 · Design ruling — the duplicated "Cancelled"

Asked under the no-redundancy direction. I checked the whole slot, not just the one state:

| Badge says | Bottom-left line says | Verdict |
|---|---|---|
| Active | `2d 4h left` | **Keep** — adds the deadline |
| Ending soon | `43m left` | **Keep** — the badge says *that*, the line says *when* |
| Ended | Winner selected | **Keep** — adds the outcome |
| Sold | Action needed — send the tickets | **Keep** — adds the next action |
| Sold | `Sold Sep 24` | **Keep as written.** The word is the grammatical carrier for the date; "Sep 24" alone is ambiguous, and it is the only date on the card |
| **Cancelled** | **Cancelled** | **Remove the line.** Identical word, no new information |

**Ruling: delete the `cancelled` branch of the bottom-left slot.** The Badge already carries the word and it
is in `a11yLabel` via `sellerBadgeLabel(badge)`; `canEdit`/`canDelete` govern the actions column separately,
so the row is not left bare. There is no `cancelled_at` to put there instead.

This is the only exact duplicate in the slot. It also removes the `s.dim` site from §2 — but **it does not
fix §2**: the Badge is still inside the 0.55 card at 4.12:1 in Daylight. Both edits are needed.

## 8 · Transient eligibility errors — the presentation fix, with behaviour preserved

`CreateListingScreen.tsx` `case 'transient'` must keep `return true`. **Only the presentation changes:**
`setRiskBanner(null)`.

Not a neutral replacement sentence. The publish proceeds, so there is no action for the seller to take, and
any line on that screen would either be noise or a claim the client cannot support. The genuine uncertainty
— *does the server enforce eligibility independently of this client check?* — is real and belongs in the
record and with A, not on the seller's screen. **That question goes to A; no eligibility policy changes here.**

## 9 · What is absent from Build 23

Build 23 is commit `9c6c9bf4`. **Everything in `d981727e` lands after it and is absent from the build**, plus
everything still outstanding in §2, §3, §5, §6, §7 and §8. Build 23 therefore still dims past-ticket text,
still paints the ungraded risk tints, and still renders all the original `faint` values. That is the
build's diagnostic value, and the checklist's **Stage 5** (not "§6") carries the list for the device pass.

**A replacement build is not required yet, and I am not asking for one.** Every fix so far is presentation
only; none changes the mechanics the pass exercises — appearance resolution and persistence, the bid summary,
the checkout hold and its boards, the transfer states. **The trigger to flag one:** when a fix lands that
changes behaviour the pass depends on, or when someone needs to verify these fixes *on device* rather than
observe the defects they replace. Neither is true today.

---

## 10 · Do `critical_risk` and `listing_blocked` require different user actions? **Yes — and C's ruling is wrong**

C's commit records them as *"two reason codes for one user-facing state, reached through the same blocked
branch"*. The branch is shared; the states are not. Verified by direct read:

| | `listing_blocked` | `critical_risk` |
|---|---|---|
| **Set by** | An operator only — `ops.execute_action` `user_restrict`, gated to `platform_admin` / `platform_risk`. No trigger, no cron, no automatic writer | Computed by `refresh_seller_risk_score` (`012:245-262`) from live data |
| **Clears** | **Only `user_unrestrict`.** No expiry, no `blocked_until` column, and the risk-refresh upsert never touches the column | **Can clear without a human.** `012:256-262` demotes `critical → medium` once the account is >30 days old with no dispute losses and no duplicates — but only when a refresh runs, and the seller cannot trigger one |
| **Server enforcement** | **Enforced at the database boundary.** `119_listing_block_insert_guard.sql` is a BEFORE INSERT trigger on `public.listings` that raises on `is_listing_blocked` | **Not enforced.** `risk_tier` appears nowhere in 119 — I grepped the file. `013` calls itself "Soft Enforcement" |
| **Console** | An explicit pair — `user_restrict` / `user_unrestrict` | **Read-only badge.** No action to set, clear or recompute the tier |

So a critical-tier seller is stopped by the **client** and not by the server, and may become eligible again
on their own; a blocked seller is stopped by the **database** and stays stopped until a person lifts it.

### What follows for the design — and what must not

**Do not differentiate them in the copy.** The owner's instruction stands and is right: exposing "critical
risk" versus "blocked by an administrator" would publish an internal classification to the person it is
about, invite gaming of the scoring inputs, and tell the seller nothing they can act on. **The difference is
operational, not actionable** — in both states the only move available to the seller is to reach a human.

**So keep one sentence, and make it work.** The defect was never that the two states look alike. It is that
the sentence names a recovery the screen cannot reach — §11.

**Two things go to A, not into the copy:**
1. **The enforcement asymmetry** — the client refuses `critical_risk` while the server accepts it. A
   critical-tier seller who bypasses the client pre-check can still insert. **This is a source reading of the
   migrations, not a check of the deployed sandbox or production**; A owns verifying what is actually
   deployed before any eligibility policy changes.
2. **The undefined recovery for `critical_risk`** — the console has no control for `risk_tier`, so "an
   operator fixes it" is true for `listing_blocked` and undefined for the other. A policy question, not a
   copy question.

## 11 · A working support route exists — it is simply not reachable from where support is named

**`app/settings/support.tsx` is a real screen**, and its address is genuinely tappable:

```tsx
const SUPPORT_EMAIL = 'support@snatchitapp.com';
function openEmail() {
  Linking.openURL(`mailto:${SUPPORT_EMAIL}?subject=Snatch It Support Request`).catch(() => {});
}
…
<Button label={SUPPORT_EMAIL} variant="secondary" onPress={openEmail} />
```

It is the **only** tappable support affordance in the app. Every other appearance of the address — three on
the legal screen, three on privacy, the seller's payout line, the transfer-state block — is plain `Text`
with no `onPress` and no `selectable`. Every "contact support" in an `Alert` body uses the two-argument
form, so it renders one OK button and no route.

**Reachability:** exactly one path pushes it — Profile tab → the gear → Settings → "Help & support". Nothing
in `CreateListingScreen` reaches it; its only `router.push` targets are `verify-phone`, `payout-setup` and
the created listing. A blocked seller must dismiss the alert and find three unguided taps on their own, and
the string `support@snatchitapp.com` never appears on the Create screen or in the alert.

### Recommendation — one change, both states, no classification exposed

Give the blocked path a route to the screen that already exists:

- **The alert** becomes the three-argument form with a real action:
  `Alert.alert('Listing blocked', RISK_COPY[reason], [{ text: 'Contact support', onPress: () => router.push('/settings/support') }, { text: 'OK', style: 'cancel' }])`
- **The banner** gains the same tappable action beneath its sentence, so the route survives dismissing the
  alert. It keeps `accessibilityRole="alert"`; the action is a `Pressable` with its own `accessibilityRole="button"`.

Identical for both reasons — nothing about which state the seller is in is revealed. This is the whole of
the "provide a working support route" instruction: the screen exists, the button works, only the path is
missing.

**One defect in the existing screen, worth fixing while it is open:** `Linking.openURL(...).catch(() => {})`
swallows the failure. On a device with no mail client configured the button does nothing and says nothing.
It should surface the address as selectable text on failure so it can still be copied.
