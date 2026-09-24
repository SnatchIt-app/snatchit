# V3 functional findings — reconciled against the release source

**B · 2026-09-22 · corrects the register published at `d6a757ab`.**

## The baseline was wrong, and two findings were wrong with it

My first inventory was read from the design worktree (`design/frontend-audit-20260917`), whose transfer screens
predate the reviewed changes. The owner was right on both counts, and I verified both in source rather than
accepting them:

**Release source: `5b255838dea3d39561714554a547a6121ab2c8ff`** — *"Merge #90 into the release gate"*,
2026-09-22, on `release/production-gate-20260918`. This replaces my earlier statement that the design target was
"Build 22 + #81 + #84"; that described an older line.

**C's V3 implementation branch: `v3/midnight-app` @ `31819593`**, six commits ahead of the release source and
already carrying the type-rule amendment, five mixed-case name tokens, the bid-CTA correction (O-2), the dock
photo (O-5) and truthful reporting (O-3).

These files **changed** between my baseline and the release source, so every finding citing them was re-read:
`app/transfer/receive/[id].tsx`, `app/transfer/send/[id].tsx`, `src/lib/transfer/transferState.ts`,
`src/screens/PlaceBidScreen.tsx`, `src/screens/checkout/CheckoutNative.tsx`, `app/(tabs)/profile.tsx`.
These are byte-identical to my baseline, so findings citing them stand as written: `app/listing/edit/[id].tsx`,
`src/screens/CreateListingScreen.tsx`, `app/settings/*`, `app/profile/[id].tsx`, `app/(auth)/*`,
`app/report/[type]/[id].tsx`, `app/(tabs)/tickets.tsx`, `src/lib/push/registration.ts`,
`src/components/TransferStatusBadge.tsx`.

### The correction to F-17

**F-17 as published was wrong for the seller and right for the buyer.** I inferred screen behaviour from the
shared status vocabulary instead of reading the render path — exactly the mistake the owner named.

At `5b255838`, `src/lib/transfer/transferState.ts:98-110`:

```ts
export function sellerWindowView(i: { status: string; countdown: string | null; checkedSincePassed: boolean }) {
  if (i.status === 'expired') return { kind: 'closed', ...SELLER_ORDER_CLOSED_COPY.expired };
  ...
```

with `SELLER_ORDER_CLOSED_COPY.expired` = **"Order expired" / "This order expired before it was marked as sent.
Don't transfer the tickets for this order."** — rendered at `app/transfer/send/[id].tsx:283`. The seller is told,
from the server fact, and is told not to transfer. That is a good state, and my finding described code that no
longer exists.

**The buyer half survives.** At the same commit, and at `v3/midnight-app`, `app/transfer/receive/[id].tsx`
contains **zero** `status === 'expired'` or `status === 'reversed'` branches (measured: 0 matches on both refs),
and `transferStatusMeta` still routes both to `default:` → a lowercase badge from
`status.replace(/_/g, ' ')`.

### The correction to F-19

**Already fixed in the release source.** `app/transfer/receive/[id].tsx:381`:

```tsx
{countdown && transfer.status === 'pending' ? (
```

The buyer's send-window countdown is restricted to `pending`. The file even carries the reason at `:175` —
*"This effect had no status condition at all, so a buyer could watch a countdown…"*. My finding described the
pre-fix code.

### The rule this establishes, which I am adopting

**Status alone is never evidence about money.** The release source already demonstrates the discipline I should
have read before writing copy — `buyerAutoReleasedCopy` (`transferState.ts`):

```ts
if (payoutReleasedAt) return transferStatusCopy('auto_released', 'buyer');
return { title: 'Review window closed',
         body: 'The review window closed without a confirmation or a report from you. This order is complete.' };
```

The money sentence waits for `payout_released_at`. **No design of mine will translate `expired` or `reversed`
into "refund issued" without payment evidence**, and the neutral copy proposed below follows this template.

---

## The register

**Labels:** ① present in the release source · ② already fixed in the release source · ③ addressed in C's V3
branch · ④ proposed capability · ⑤ still unverified

| # | Label | Finding | Role / state | Observable consequence | Evidence @ `5b255838` unless noted |
|---|---|---|---|---|---|
| **F-17a** | **②** | Seller expired-order explanation | seller · `expired` | Seller sees "Order expired" and is told not to transfer. **Fixed — my finding was wrong** | `transferState.ts:81-83,98-110`; rendered `send/[id].tsx:283`; tests `send-transfer-expired-window.test.ts` |
| **F-17b** | **①** | **Buyer is told nothing on `expired` / `reversed`** | buyer · `expired`, `reversed` | Badge reads lowercase "expired"/"reversed"; no state block, no explanation, no next step. A buyer who opens the app instead of tapping the push learns nothing about why the order ended | 0 matches for `status === 'expired'\|'reversed'` in `receive/[id].tsx` at **both** `5b255838` and `v3/midnight-app`; `transferStatusMeta` `default:` branch |
| **F-17c** | **①** | **Seller is told nothing on `reversed`** *(new, verified 2026-09-22)* | seller · `reversed` | `sellerWindowView` returns `{kind:'none'}` for every status except `expired` and `pending`, and the send screen has blocks only for pending / seller_sent / buyer_confirmed / auto_released / disputed. I previously reported the seller as covered for both statuses; that was right for `expired` and wrong for `reversed` | `transferState.ts:98-110`; `send/[id].tsx:376,402,443,454,468` @ `5b255838` |
| **F-18** | **①** | `TransferStatusBadge.tsx` is never imported | both | The component already contains "Transfer Expired" and "Payment Reversed" and nothing renders them | 0 importers on both refs (only its own definition) |
| **F-19** | **②** | Buyer saw the seller's deadline on settled transfers | buyer | **Fixed** — countdown gated to `pending` | `receive/[id].tsx:381`, reason at `:175` |
| **F-20** | **①** | A failed proof signed-URL is silent | buyer · `seller_sent` | The proof block disappears; the buyer is not told an image existed that could not load, and may confirm without seeing it | `receive/[id].tsx:107-109` — `.catch(() => setProofUrl(null))` |
| **F-21** | **①** | Raw PostgREST text reaches the buyer | buyer · delivery-info save | Unfiltered `rpcErr.message` in an "Error" alert — the only place in these screens; the seller path filters via `userFacing` | 3 matches on **both** refs; contrast `markSent.ts` |
| **F-22** | **①** | Buyer is never shown the auto-release deadline | buyer · `seller_sent` | `auto_release_at` is not in the select list, so the one date that decides whether payment leaves is invisible to the person it affects. The seller gets a countdown | 0 matches for `auto_release_at` in `receive/[id].tsx` on **both** refs |
| **F-23** | **①** | `send-push` applies no notification preference | both | Every transfer, dispute and expiry push is delivered regardless of preference; only `stripe-webhook` consults `notify_listing_sold` | 0 preference matches in `supabase/functions/send-push/index.ts` |
| **F-24** | **①** | Any unrecognised `type` segment becomes a listing report | reporter | `/report/anything/{id}` silently files a listing report | `report/[type]/[id].tsx:40`; file unchanged |
| **F-1** | **①** | Edit listing can hang on a permanent spinner | seller | Guard paths return without clearing `loading`; dismissing any way but the alert's OK leaves a permanent spinner | `app/listing/edit/[id].tsx:72,82-94` — file byte-identical to my baseline |
| **F-2** | **①** | Edit offers 6 platforms, Create offers 16 | seller | A listing on one of the other ten shows no chip selected | `edit/[id].tsx:31-38` vs `CreateListingScreen.tsx:84-101` |
| **F-3** | **①** | Transient RPC failure shows a reputation warning | seller | A network hiccup says "We've noticed some recent issues…". Failing open is intentional; the copy misattributes | `CreateListingScreen.tsx:386-389` |
| **F-4** | **①** | Signed-out publish is silent | seller | Every field turns red with no explanation | `CreateListingScreen.tsx:410` |
| **F-5** | **①** | Neither Create picker sheet has a no-results state | seller | A non-matching search renders an empty scroll view | `CreateListingScreen.tsx:892,933-937` |
| **F-6** | **⑤** | Stripe onboarding cancellation has no UI | seller | Backing out shows nothing; result type is only logged. File unchanged, but the *consequence* was not re-observed | `settings/payout-setup.tsx:126` |
| **F-7** | **①** | Two different banned-content messages | seller | Same rule, two wordings | `CreateListingScreen.tsx:416` vs `edit/[id].tsx:114` |
| **F-8** | **①** | No offline detection on Create or payout-setup | seller | Offline surfaces only as an upload error string | files unchanged |
| **F-9** | **①** | Phone verification is not enforced | new user | Abandoning after signup step 1 leaves a usable, phone-less session | `signup.tsx:85-88,112-136` — file unchanged |
| **F-10** | **①** | Two sign-out entry points disagree on confirmation | signed-in | Settings confirms; the Profile tab signs out immediately. **Re-checked because `profile.tsx` changed** — still no dialog | `profile.tsx:218-221,322` @ `5b255838` vs `settings/index.tsx:119-140` |
| **F-11** | **①** | Two unblock entry points disagree on confirmation | signed-in | Blocked users confirms; the public profile does not | `blocked-users.tsx:95` vs `profile/[id].tsx:166` — unchanged |
| **F-12** | **①** | Web and native delete-account copy differ | web users | Different wording for the same two-step confirmation | `settings/index.tsx:248-282` — unchanged |
| **F-13** | **①** | Bare-title alerts | signed-out / reset | The message is passed as the title with no body | verified at `5b255838`: `login.tsx` match present |
| **F-14** | **①** | Delete-account obligations can leak raw tokens | deleting user | An unrecognised `kind` falls through to the server string | `settings/index.tsx:193` — unchanged |
| **F-15** | **①** | Five of six notification preferences are hidden | signed-in | Intentional (`WIRED_PREF_KEYS`); listed so it stays deliberate | `notificationPrefs.ts:29-33` — unchanged |
| **F-16** | **⑤** | A signed-out guard on the public profile may be unreachable | — | Cannot be settled from source alone | `profile/[id].tsx:148` vs `app/_layout.tsx:108-118` |

**Nothing in this register is ③.** C's V3 branch closes the design questions O-2, O-3 and O-5, but I found no
finding above that it fixes — F-17b, F-18, F-21 and F-22 were measured on `v3/midnight-app` as well as on the
release source and are present on both.

**Nothing in this register is ④.** The one proposed capability in the V3 work — saved delivery preferences —
is a specification, not a finding, and stays labelled as proposed wherever a mockup depicts it.

---

## Reviews requested

**C — client behaviour.** F-1 (does the spinner really persist?), F-5, F-6, F-16, F-20, F-21, and whether
F-17b's two statuses are reachable in practice.

**A — money claims.** F-22 (is `auto_release_at` the right date to show a buyer, and may it be shown?), F-23
(should transfer pushes respect preferences?), and the proposed copy below before it is used anywhere.

---

## Proposed copy for the verified missing buyer state — FOR REVIEW, NOT APPROVED

**Superseded 2026-09-22 by owner correction.** My first draft said *"If you were charged, any refund is handled
automatically"*. That is withdrawn: it promises a process that is **not established for every affected order**,
and the existing partial-refund findings make the assumption unsafe. Nothing below describes a refund
mechanism, a timeline or an outcome.

**The four rules this copy follows**

1. State only what the **verified transfer status** establishes.
2. Treat **refund status and refund amount as separate facts**, neither of which this screen holds.
3. Where payment information is unavailable, **say it cannot be confirmed here**.
4. Offer an **existing, usable support route** — no invented timeline, no resolution promise.

### `expired`, buyer

> **Order closed**
> This order closed before the seller marked the tickets as sent.
> We can't confirm payment or refund status here.
> **[ Get help ]** → `/settings/support` (the shipped Help & support route)

### `reversed`, buyer — the noun itself is blocked

> **{status noun — pending A}**
> This order was reversed.
> We can't confirm payment or refund status here.
> **[ Get help ]** → `/settings/support`

**"Payment Reversed" is not adopted.** The unused `TransferStatusBadge` contains that label, but an unrendered
string is not a product decision and it makes a payment claim the screen cannot support. The badge word and the
block title both wait on A's definition of what `reversed` means. Until then the design carries a placeholder,
not a guess.

**Deliberately absent:** "you have been refunded", "your full refund has been issued", "any refund is handled
automatically", any amount, any date, and any statement about what will happen next.

**What would change this:** if A confirms a refund fact is readable on the transfer, the block splits the way
`buyerAutoReleasedCopy` already splits the payout sentence — a definite sentence when the fact is present, this
neutral one when it is not. **Refund status and amount are two separate facts and neither may be inferred from
the other**, so a present status with an absent amount still gets the neutral sentence.

### Reviews this copy depends on

- **A** — what `expired` and `reversed` actually mean for an order, whether any refund fact is readable on the
  transfer row, and whether the two statuses can carry different payment outcomes.
- **C** — the render path, which statuses are reachable, what data the buyer screen already holds, and whether
  `/settings/support` is the right destination for this entry point.

---

## The buyer's review deadline — worth designing, dependencies named (F-22)

The owner has asked for this to be designed rather than only reported. The design belongs to Package 4
(Orders, transfers and support); what is settled here is the honesty contract it must satisfy.

**It is not a payout guarantee.** The deadline is the point after which the buyer's window to confirm or report
closes. It must never be phrased as a promise that a payout completes at that moment — the release decision and
the payout are separate, which the release source already respects by gating the money sentence on
`payout_released_at`.

**C must verify, before any of this is implemented:**

| # | Question |
|---|---|
| 1 | **The authoritative field.** `auto_release_at` is absent from the buyer's select list today. Is it the right field, and is it readable by the buyer under RLS? |
| 2 | **Applicable states.** Which statuses may show it at all — presumably `seller_sent` only, given F-19 restricted the *seller's* window countdown to `pending` |
| 3 | **Missing-value behaviour.** What the block shows when the field is null or unreadable. It must degrade to saying nothing rather than to a computed or assumed date |
| 4 | **Refresh behaviour.** Whether the value is re-read on focus and after a confirm/dispute attempt, and what a stale value may claim |

**Proposed wording, for the same review:** *"Your confirmation is needed by {date}"* with, beneath it, *"After
that the review window closes."* — and nothing about payout timing. If the field is unavailable the row is
omitted entirely; no placeholder date, no "soon".

---

## Three findings added during the freeze reconciliation (2026-09-22)

All three were found by mapping the listing-detail dialog set line by line against
`src/screens/ListingDetailScreen.tsx` @ `5b255838`. Full derivation:
`V3_FREEZE_RECONCILIATION_20260922.md`.

| # | Label | Finding | Role / state | Observable consequence | Evidence @ `5b255838` |
|---|---|---|---|---|---|
| **F-25** | **①** | **Two screens carry divergent copies of the same three destructive dialogs** | seller · delete / cancel | `my-listings.tsx` and `ListingDetailScreen.tsx` both delete and cancel a listing with different titles (`Delete listing` vs `Delete listing?`), different bodies (*"This listing has bids and cannot be deleted."* vs *"…activity already exists. Cancel it instead."*), and different button casing (`Keep listing` vs `Keep Listing`). The structures differ too: my-listings has **one** control that branches on `bid_count`, listing detail has **two** guarded menu entries | `my-listings.tsx:122,161,166` (5 alerts) vs `ListingDetailScreen.tsx:824,830,871` (23 alerts) |
| **F-26** | **①** | **`More actions` is an `Alert` on Android and an `ActionSheetIOS` on iOS** | any viewer | One control, two menus (owner vs everyone else) and two platform renderings. Deliberate, not a defect — recorded so a restyle does not "unify" it into a single custom sheet and lose the native destructive-index behaviour. `destructiveButtonIndex` is **computed** (last destructive entry), which a previous revision had hardcoded to `2` — correct for only one of the two menus | `ListingDetailScreen.tsx:933-963`; the comment at `:940` records the earlier hardcoded-index bug |
| **F-27** | **①** | **No listing-detail failure path refetches** | buyer · race-lost states | `fetchData()` runs on mount (L420), focus (L426), Retry (L1055), pull-to-refresh (L1235) and after a **successful** reservation (L786). After *Not available*, *Currently reserved* (both), *Already sold* or *Already cancelled*, the alert dismisses to a screen still showing the stale state that caused it — **still offering the action it just refused**. The buyer can tap Buy now repeatedly and be refused each time with no visible change | 5 `fetchData` call sites, none on a failure branch; `reserveAndCheckout` L761-789 |

**F-25 and F-26 are for C to rule on, not for the redesign to resolve.** Unifying F-25's copy is a behaviour
change and the structural difference is a product decision. F-27's fix is drawn as **PROPOSED** on
`pkg6-listing-dialogs.png` and is not represented as existing behaviour anywhere.

---

## One finding added during the copy correction (2026-09-23)

| # | Label | Finding | Role / state | Observable consequence | Evidence @ `5b255838` |
|---|---|---|---|---|---|
| **F-28** | **①** | **The seller is told "marked as sent" four times in two seconds** | seller · `seller_sent` | Tapping *Mark as sent* raises `Alert.alert('Marked as sent', "You've marked this transfer as sent. The buyer still needs to confirm they received the tickets.")`. Dismissing it reveals a screen carrying the badge **"Marked sent"** *and* a `StateBlock` titled **"Marked as sent"** whose body — *"Waiting for the buyer to confirm they received the tickets."* — restates the alert's second sentence. Four statements of one fact, in two wordings, within one interaction | `send/[id].tsx:185`, `:403`; `transferState.ts:137` (badge `Marked sent`), `:162` (block `Marked as sent`) |

**Package 7 removes the `StateBlock` title in the design** and keeps its body, so the badge carries the status
once. **That is a change to shipped copy in `transferState.ts:162`, and `StateBlock` may require a title
prop — C confirms both before implementing.** The alert at `:185` is left alone here: whether a confirmation
alert should fire at all after a visible state change is a behaviour question, not a copy one.

---

## Dialog-copy repetition review (2026-09-23)

The owner directed that existing dialog copy is **not automatically exempt** from the simplification pass.
All 23 listing dialogs and 22 selling dialogs were re-read at `5b255838`.

**Most title/body pairs are not repetition.** A native `Alert` takes a short title and a sentence; the title
being the headline of its own body is the platform convention, not clutter. Rewriting forty shipped bodies to
avoid echoing their titles would be churn with real risk and no gain for the reader.

**Four are genuine — the body restates the title and adds nothing**, where it could instead carry the
recovery:

| # | Label | Finding | Evidence |
|---|---|---|---|
| **F-29** | **①** | **Four dialog bodies restate their own title and offer no recovery**: *"Buy Now unavailable / This listing does not have Buy Now enabled."* · *"Not available / This listing is no longer available."* · *"Already sold / This listing has already been sold."* · *"Already cancelled / This listing has already been cancelled."* Each spends its one sentence saying the title again | `ListingDetailScreen.tsx:766, 768, 782, 868` |

**One is fixed now, because its recovery is knowable without any further ruling.** `buy_now_enabled` being
false means the listing is auction-only, and the dialog can only fire from a buy path on a live listing:

> **"Buy Now unavailable" / ~~"This listing does not have Buy Now enabled."~~ → "You can place a bid instead."**

**The other three are blocked on F-27.** Their honest recovery is *"the screen you are looking at is out of
date"* — and the app does not refetch on any failure path, so offering a refresh would describe behaviour that
does not exist. **When F-27 is resolved, their bodies become the recovery.** Until then they keep their
shipped copy; a speculative rewrite would be inventing a remedy.

**Not changed, and why:** bodies that already carry a reason or a route (*"…because activity already exists.
Cancel it instead."*, *"…You can unblock from Settings → Blocked Users."*, *"Use Cancel from My Listings if
you need to remove it."*) are doing exactly what the four above fail to do. The destructive confirmations keep
every word — a CONFIRM dialog is the authorisation, and shortening consent copy is not simplification.
